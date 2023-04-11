//
//  Copyright © 2020 Axinom. All rights reserved.
//
//  The ContentKeyManager class configures the instance of AVContentKeySession to use for requesting content keys
//  securely for playback or offline use.
//

import Foundation
import AVFoundation

class ContentKeyManager: NSObject, AVContentKeySessionDelegate {
    
    // Certificate Url
    var fpsCertificateUrl: String = ""

    // Licensing Service Url
    var licensingServiceUrl: String = ""

    // Licensing Token
    var licensingToken: String = ""
    
    // Current asset
    var asset: Asset!
    
    // A singleton instance of ContentKeyManager
    static let sharedManager = ContentKeyManager()
    
    // Content Key session
    var contentKeySession: AVContentKeySession!
    
    // Content Key request
    var contentKeyRequest: AVContentKeyRequest!
    
    // Indicates that user requested download action
    var downloadRequestedByUser: Bool = false
    
    // Certificate data
    fileprivate var fpsCertificate:Data!
    
    // A set containing the currently pending content key identifiers associated with persistable content key requests that have not been completed.
    var pendingPersistableContentKeyIdentifiers = Set<String>()
        
    // The directory that is used to save persistable content keys
    lazy var contentKeyDirectory: URL = {
        guard let documentPath =
            NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
                fatalError("Unable to determine library URL")
        }
        
        let documentURL = URL(fileURLWithPath: documentPath)
        
        let contentKeyDirectory = documentURL.appendingPathComponent(".keys", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: contentKeyDirectory.path, isDirectory: nil) {
            do {
                try FileManager.default.createDirectory(at: contentKeyDirectory,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
            } catch {
                fatalError("Unable to create directory for content keys at path: \(contentKeyDirectory.path)")
            }
        }
        
        return contentKeyDirectory
    }()
    
    override init() {
        super.init()
    }
    
    // Creates Content Key Session
    func createContentKeySession() {
        print("Creating new AVContentKeySession")
        contentKeySession = AVContentKeySession(keySystem: .fairPlayStreaming)
        contentKeySession.setDelegate(self, queue: DispatchQueue(label: "\(Bundle.main.bundleIdentifier!).ContentKeyDelegateQueue"))
    }
    
    // Sends message to Console of PlayerViewController
    func postToConsole(_ message: String) {
        // Prepare the basic userInfo dictionary that will be posted as part of our notification
        var userInfo = [String: Any]()
        userInfo["message"] = message
        
        NotificationCenter.default.post(name: .ConsoleMessageSent, object: nil, userInfo: userInfo)
    }
    
    // MARK: Online key retrival
    
    /*
     The following delegate callback gets called when the client initiates a key request or AVFoundation
     determines that the content is encrypted based on the playlist the client provided when it requests playback.
    */
    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVContentKeyRequest) {
        self.postToConsole("Content is encrypted. Initiating key request")
        contentKeyRequest = keyRequest
        handleOnlineContentKeyRequest(keyRequest: keyRequest)
    }
    
    /*
     Provides the receiver with a new content key request representing a renewal of an existing content key.
     Will be invoked by an AVContentKeySession as the result of a call to -renewExpiringResponseDataForContentKeyRequest:.
     */
    func contentKeySession(_ session: AVContentKeySession, didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest) {
        self.postToConsole("Renewal of an existing content key")
        
        handleOnlineContentKeyRequest(keyRequest: keyRequest)
    }
    
    func handleOnlineContentKeyRequest(keyRequest: AVContentKeyRequest) {
        if self.fpsCertificate == nil {
            self.postToConsole("Application Certificate missing, will request")
            
            // Request Application Certificate
            do {
                try self.requestApplicationCertificate()
            } catch {
                self.postToConsole("Failed requesting Application Certificate: \(error)")
                return
            }
        }
        
        /*
         Parse ContentId from keyRequest and capture everything after "sdk://"
        */
        guard let contentKeyIdentifierString = keyRequest.identifier as? String,
              
        /*
          Capture everything after "sdk://" from #EXT-X-SESSION-KEY "URI" parameter.
        */
        let contentIdentifier = contentKeyIdentifierString.replacingOccurrences(of: "skd://", with: "") as String?,
        
        /*
          Convert contentIdentifier to Unicode string (utf8)
        */
        let contentIdentifierData = contentIdentifier.data(using: .utf8) else {
           postToConsole("ERROR: Failed to retrieve the contentIdentifier from the keyRequest!")
           return
        }

        let keyId = contentIdentifier.components(separatedBy: ":")[0]
        let keyIV = contentIdentifier.components(separatedBy: ":")[1]
        
        /*
         Console output
        */
        let contentKeyIdAndIv = """
        - Content Key ID: \(keyId) \n \
        - IV(Initialization Vector): \(keyIV) \n
        """
        
        postToConsole("Key request info:\n \(contentKeyIdAndIv)")
        
        /*
         Save Content Key Identifier String to initiate persisting content key loading process associated with the asset if needed.
        */
        
        if !(asset.contentKeyIdList?.contains(contentKeyIdentifierString))! {
            asset.contentKeyIdList?.append(contentKeyIdentifierString)
        }
        
        /*
         When you receive an AVContentKeyRequest via -contentKeySession:didProvideContentKeyRequest:
         and you want the resulting key response to produce a key that can persist across multiple
         playback sessions, you must invoke -respondByRequestingPersistableContentKeyRequest on that
         AVContentKeyRequest in order to signal that you want to process an AVPersistableContentKeyRequest
         instead. If the underlying protocol supports persistable content keys, in response your
         delegate will receive an AVPersistableContentKeyRequest via -contentKeySession:didProvidePersistableContentKeyRequest:.
        */
        if downloadRequestedByUser || persistableContentKeyExistsOnDisk(withAssetName: asset.name, withContentKeyIV: keyIV) || shouldRequestPersistableContentKey(withIdentifier: contentKeyIdentifierString) {
            /*
             Request a Persistable Key Request.
            */
            do {
                self.postToConsole("User requested offline capabilities for the asset. AVPersistableContentKeyRequest object will be delivered by another delegate callback")
                try keyRequest.respondByRequestingPersistableContentKeyRequestAndReturnError()
            } catch {

                self.postToConsole("WARNING: User requested offline capabilities for the asset. But key loading request from an AirPlay Session requires online key")
                /*
                This case will occur when the client gets a key loading request from an AirPlay Session.
                You should answer the key request using an online key from your key server.
                */
                provideOnlineKey(withKeyRequest: keyRequest, contentIdentifier: contentIdentifierData)
            }
            return
        }
        
        provideOnlineKey(withKeyRequest: keyRequest, contentIdentifier: contentIdentifierData)
    }
    
    func provideOnlineKey(withKeyRequest keyRequest: AVContentKeyRequest, contentIdentifier contentIdentifierData: Data) {
        
        postToConsole("ONLINE KEY FLOW")
        
        /*
         Completion handler for makeStreamingContentKeyRequestData method.
         1. Sends obtained SPC to Key Server
         2. Receives CKC from Key Server
         3. Makes content key response object (AVContentKeyResponse)
         4. Provide the content key response object to make protected content available for processing
        */
        let getCkcAndMakeContentAvailable = { [weak self] (spcData: Data?, error: Error?) in
            guard let strongSelf = self else { return }
            
            if let error = error {
                strongSelf.postToConsole("ERROR: Failed to prepare SPC: \(error)")
                /*
                 Obtaining a content key response has failed.
                 Report error to AVFoundation.
                */
                keyRequest.processContentKeyResponseError(error)
                return
            }

            guard let spcData = spcData else { return }

            do {
                strongSelf.postToConsole("Will use SPC (Server Playback Context) to request CKC (Content Key Context) from KSM (Key Security Module)")
                
                /*
                 Send SPC to Key Server and obtain CKC.
                */
                let ckcData = try strongSelf.requestContentKeyFromKeySecurityModule(spcData: spcData)

                strongSelf.postToConsole("Creating Content Key Response from CKC obtaned from Key Server")
                
                /*
                 AVContentKeyResponse is used to represent the data returned from the key server when requesting a key for
                 decrypting content.
                 */
                let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckcData)

                strongSelf.postToConsole("Providing Content Key Response to make protected content available for processing: \(keyResponse)")
                
                /*
                 Provide the content key response to make protected content available for processing.
                */
                keyRequest.processContentKeyResponse(keyResponse)
            } catch {
                strongSelf.postToConsole("Failed to make protected content available for processing: \(error)")
                
                /*
                 Report error to AVFoundation.
                */
                keyRequest.processContentKeyResponseError(error)
            }
        }

        self.postToConsole("Will prepare content key request SPC (Server Playback Context)")

        /*
         Pass Content Id unicode string together with FPS Certificate to obtain content key request data for a specific combination of application and content.
        */
        keyRequest.makeStreamingContentKeyRequestData(forApp: self.fpsCertificate,
                                                      contentIdentifier: contentIdentifierData,
                                                      options: [AVContentKeyRequestProtocolVersionsKey: [1]],
                                                      completionHandler: getCkcAndMakeContentAvailable)
            
    }
    
    // MARK: Offline key retrival
    
    /*
     Initiates content key loading process associated with an Asset for persisting on disk.
    */
    func requestPersistableContentKeys(forAsset asset: Asset) {
        postToConsole("OFFLINE KEY FLOW")
        
        for contentKeyId in asset.contentKeyIdList ?? [] {
            postToConsole("Initiating Persistable Key Request for key identifier: \(String(describing: contentKeyId))")
            
            pendingPersistableContentKeyIdentifiers.insert(contentKeyId)
            
            contentKeySession.processContentKeyRequest(withIdentifier: contentKeyId, initializationData: nil, options: nil)
        }
    }
    
    /*
      Returns whether or not a content key should be persistable on disk.
      Parameter identifier: The asset ID associated with the content key request.
      - Returns: `true` if the content key request should be persistable, `false` otherwise.
    */
    func shouldRequestPersistableContentKey(withIdentifier identifier: String) -> Bool {
        return pendingPersistableContentKeyIdentifiers.contains(identifier)
    }
    
    /*
     The following delegate callback gets called when the client initiates a key request or AVFoundation
     determines that the content is encrypted based on the playlist the client provided when it requests playback.
    */
    func contentKeySession(_ session: AVContentKeySession, didProvide keyRequest: AVPersistableContentKeyRequest) {
        postToConsole("Initiating persistable key request")
        
        handlePersistableContentKeyRequest(keyRequest: keyRequest)
    }
        
    /*
     Handles responding to an `AVPersistableContentKeyRequest` by determining if a key is already available for use on disk.
     If no key is available on disk, a persistable key is requested from the server and securely written to disk for use in the future.
     In both cases, the resulting content key is used as a response for the `AVPersistableContentKeyRequest`.
    
     - Parameter keyRequest: The `AVPersistableContentKeyRequest` to respond to.
    */
    func handlePersistableContentKeyRequest(keyRequest: AVPersistableContentKeyRequest) {
        /*
         Request Application Certificate
        */
        if self.fpsCertificate == nil {
            self.postToConsole("Application Certificate missing, will request")
            
            // Request Application Certificate
            do {
                try self.requestApplicationCertificate()
            } catch {
                self.postToConsole("Failed requesting Application Certificate: \(error)")
                return
            }
        }
        
        /*
         Parse ContentId from keyRequest and capture everything after "sdk://"
        */
        guard let contentKeyIdentifierString = keyRequest.identifier as? String,
              
        /*
         Capture everything after "sdk://" from #EXT-X-SESSION-KEY "URI" parameter.
        */
        let contentIdentifier = contentKeyIdentifierString.replacingOccurrences(of: "skd://", with: "") as String?,

        /*
         Convert contentIdentifier to Unicode string (utf8)
        */
        let contentIdentifierData = contentIdentifier.data(using: .utf8) else {
           postToConsole("ERROR: Failed to retrieve the contentIdentifier from the keyRequest!")
           return
        }
        
        let keyId = contentIdentifier.components(separatedBy: ":")[0]
        let keyIV = contentIdentifier.components(separatedBy: ":")[1]
        
        /*
         Console output
        */
        let contentKeyIdAndIv = """
        - Content Key ID: \(keyId) \n \
        - IV(Initialization Vector): \(keyIV) \n
        """
        postToConsole("Key request info:\n \(contentKeyIdAndIv)")
        
        /*
         Save Content Key Identifier String to initiate persisting content key loading process associated with the asset if needed.
        */
        if !(asset.contentKeyIdList?.contains(contentKeyIdentifierString))! {
            asset.contentKeyIdList?.append(contentKeyIdentifierString)
        }

        /*
         Completion handler for makeStreamingContentKeyRequestData method.
         1. Sends obtained SPC to Key Server
         2. Receives CKC from Key Server
         3. Obtains persistable content key
         4. Writes persistable content key to disk
         5. Makes content key response object (AVContentKeyResponse)
         4. Provide the content key response object to make protected content available for processing
        */
        let completionHandler = { [weak self] (spcData: Data?, error: Error?) in
            guard let strongSelf = self else { return }
            if let error = error {
                /*
                 Report error to AVFoundation.
                */
                keyRequest.processContentKeyResponseError(error)
                
                strongSelf.pendingPersistableContentKeyIdentifiers.remove(contentKeyIdentifierString)
                
                strongSelf.downloadRequestedByUser = false
                return
            }
            
            guard let spcData = spcData else { return }
            
            do {
                strongSelf.postToConsole("Will use SPC (Server Playback Context) to request CKC (Content Key Context) from KSM (Key Security Module)")
                /*
                 Send SPC to Key Server and obtain CKC
                */
                let ckcData = try strongSelf.requestContentKeyFromKeySecurityModule(spcData: spcData)
                
                strongSelf.postToConsole("Creating Content Key Response from CKC obtaned from Key Server")
                
                /*
                 Obtains a persistable content key from Content Key Context (CKC)
                */
                let persistentKey = try keyRequest.persistableContentKey(fromKeyVendorResponse: ckcData, options: nil)
                
                strongSelf.postToConsole("Persistable Content Key was obtained from Content Key Context (CKC)")
                
                /*
                 Writes out a persistable content key to disk
                */
                try strongSelf.writePersistableContentKey(contentKey: persistentKey, withAssetName: strongSelf.asset.name, withContentKeyIV: keyIV)
                
                strongSelf.postToConsole("Wrote persistable content key to disk")
                
                /*
                 AVContentKeyResponse is used to represent the data returned from the key server when requesting a key for
                 decrypting content.
                */
                let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: persistentKey)
                
                /*
                 Provide the content key response to make protected content available for processing.
                */
                keyRequest.processContentKeyResponse(keyResponse)
                
                strongSelf.postToConsole("Providing Content Key Response to make protected content available for processing: \(keyResponse)")
                
                NotificationCenter.default.post(name: .HasAvailablePersistableContentKey, object: nil, userInfo: nil)
                
                strongSelf.pendingPersistableContentKeyIdentifiers.remove(contentKeyIdentifierString)
       
            } catch {
                
                strongSelf.postToConsole("ERROR: \(error)")
                
                /*
                 Report error to AVFoundation.
                 */
                keyRequest.processContentKeyResponseError(error)
                
                strongSelf.pendingPersistableContentKeyIdentifiers.remove(contentKeyIdentifierString)
                
                strongSelf.downloadRequestedByUser = false
            }
        }
        
        /*
         Check to see if we can satisfy this key request using a saved persistent key file.
        */
        if persistableContentKeyExistsOnDisk(withAssetName: asset.name, withContentKeyIV: keyIV) {
            
            let urlToPersistableKey = urlForPersistableContentKey(withAssetName: asset.name, withContentKeyIV: keyIV)
            
            postToConsole("Presistable key already exists on disk at location: \(urlToPersistableKey.path)")
            
            guard let contentKey = FileManager.default.contents(atPath: urlToPersistableKey.path) else {
                downloadRequestedByUser = false
                
                pendingPersistableContentKeyIdentifiers.remove(contentKeyIdentifierString)
                
                postToConsole("Failed to locate Presistable key from disk. Attempting to create a new one")
                
                /*
                 Pass Content Id unicode string together with FPS Certificate to obtain content key request data for a specific combination of application and content.
                */
                keyRequest.makeStreamingContentKeyRequestData(forApp: self.fpsCertificate,
                                                              contentIdentifier: contentIdentifierData,
                                                              options: [AVContentKeyRequestProtocolVersionsKey: [1]],
                                                              completionHandler: completionHandler)

                return
            }
            
            /*
             Create an AVContentKeyResponse from the persistent key data to use for requesting a key for
             decrypting content.
             */
            postToConsole("Creating Content Key Response from persistent CKC")
            
            let keyResponse = AVContentKeyResponse(fairPlayStreamingKeyResponseData: contentKey)
            
            postToConsole("Providing Content Key Response to make protected content available for processing: \(keyResponse)")
            
            /*
             Provide the content key response to make protected content available for processing.
             */
            keyRequest.processContentKeyResponse(keyResponse)
            
            NotificationCenter.default.post(name: .HasAvailablePersistableContentKey, object: nil, userInfo: nil)
            
            return
        }
                    
        keyRequest.makeStreamingContentKeyRequestData(forApp: self.fpsCertificate,
                                                      contentIdentifier: contentIdentifierData,
                                                      options: [AVContentKeyRequestProtocolVersionsKey: [1]],
                                                      completionHandler: completionHandler)
    }
    
    /*
     Provides the receiver with an updated persistable content key for a particular key request.
     If the content key session provides an updated persistable content key data, the previous
     key data is no longer valid and cannot be used to answer future loading requests.
     
     This scenario can occur when using the FPS "dual expiry" feature which allows you to define
     and customize two expiry windows for FPS persistent keys. The first window is the storage
     expiry window which starts as soon as the persistent key is created. The other window is a
     playback expiry window which starts when the persistent key is used to start the playback
     of the media content.
     
     Here's an example:
     
     When the user rents a movie to play offline you would create a persistent key with a CKC that
     opts in to use this feature. This persistent key is said to expire at the end of storage expiry
     window which is 30 days in this example. You would store this persistent key in your apps storage
     and use it to answer a key request later on. When the user comes back within these 30 days and
     asks you to start playback of the content, you will get a key request and would use this persistent
     key to answer the key request. At that point, you will get sent an updated persistent key which
     is set to expire at the end of playback experiment which is 24 hours in this example.
    */
    func contentKeySession(_ session: AVContentKeySession,
                           didUpdatePersistableContentKey persistableContentKey: Data,
                           forContentKeyIdentifier keyIdentifier: Any) {
        
        postToConsole("Updating Persistable Content Key")

        do {
            /*
             Parse ContentId from keyRequest and capture everything after "sdk://"
            */
            guard let contentKeyIdentifierString = keyIdentifier as? String,
                  
            /*
              Capture everything after "sdk://" from #EXT-X-SESSION-KEY "URI" parameter.
            */
            let contentIdentifier = contentKeyIdentifierString.replacingOccurrences(of: "skd://", with: "") as String?
            
            else {
               postToConsole("ERROR: Failed to retrieve the contentIdentifier")
               return
            }
                        
            deletePeristableContentKey(withAssetName: asset.name, withContentKeyId: contentIdentifier)
            
            postToConsole("Will write updated persistable content key to disk for \(asset.name)")
            
            try writePersistableContentKey(contentKey: persistableContentKey, withAssetName: asset.name, withContentKeyIV: contentIdentifier.components(separatedBy: ":")[1])
        } catch {
            postToConsole("ERROR: Failed to write updated persistable content key to disk: \(error.localizedDescription)")
        }
    }
                
    // Writes out a persistable content key to disk.
    //
    // - Parameters:
    //   - contentKey: The data representation of the persistable content key.
    //   - assetName: The asset name.
    // - Throws: If an error occurs during the file write process.
    func writePersistableContentKey(contentKey: Data, withAssetName assetName: String, withContentKeyIV keyIV: String) throws {
        
        let fileURL = urlForPersistableContentKey(withAssetName: assetName, withContentKeyIV: keyIV)
        
        try contentKey.write(to: fileURL, options: Data.WritingOptions.atomicWrite)
        
        postToConsole("Wrote persistable content key to disk for \(assetName) to location: \(fileURL)")
    }
    
    // Returns whether or not a persistable content key exists on disk for a given asset.
    //
    // - Parameter assetName: The asset name.
    // - Returns: `true` if the key exists on disk, `false` otherwise.
    func persistableContentKeyExistsOnDisk(withAssetName assetName: String, withContentKeyIV keyIV: String) -> Bool {
        let contentKeyURL = urlForPersistableContentKey(withAssetName: assetName, withContentKeyIV: keyIV)
        
        return FileManager.default.fileExists(atPath: contentKeyURL.path)
    }
    
    // Returns the `URL` for persisting or retrieving a persistable content key.
    //
    // - Parameter assetName: The asset name.
    // - Returns: The fully resolved file URL.
    func urlForPersistableContentKey(withAssetName assetName: String, withContentKeyIV keyIV: String) -> URL {
        return contentKeyDirectory.appendingPathComponent("\(assetName)-\(keyIV)-Key")
    }
    
    // Deletes a persistable key for a given content key identifier.
    //
    // - Parameter assetName: The asset name.
    func deletePeristableContentKey(withAssetName assetName: String, withContentKeyId keyId: String) {
        
        /*
         Capture everything after "sdk://" from #EXT-X-SESSION-KEY "URI" parameter.
        */
        guard let contentIdentifier = keyId.replacingOccurrences(of: "skd://", with: "") as String? else {
            postToConsole("ERROR: Failed to retrieve the contentIdentifier")
            return
        }
        
        let keyIV = contentIdentifier.components(separatedBy: ":")[1]
        
        if persistableContentKeyExistsOnDisk(withAssetName: assetName, withContentKeyIV: keyIV) {
            postToConsole("Deleting content key for \(assetName) - \(keyIV): Persistable content key exists on disk")
        } else {
            postToConsole("Deleting content key for \(assetName) - \(keyIV): No persistable content key exists on disk")
            return
        }
        
        let contentKeyURL = urlForPersistableContentKey(withAssetName: assetName, withContentKeyIV: keyIV)
        
        do {
            try FileManager.default.removeItem(at: contentKeyURL)
            
            UserDefaults.standard.removeObject(forKey: "\(assetName)-\(keyIV)-Key")
            
            postToConsole("Presistable Key for \(assetName)-\(keyIV) was deleted")
        } catch {
            print("An error occured removing the persisted content key: \(error)")
        }
    }
    
    func requestApplicationCertificate() throws {
        postToConsole("Requesting FPS Certificate")
    
        guard let url = URL(string: fpsCertificateUrl) else {
            postToConsole("ERROR: missingApplicationCertificateUrl")
            throw ProgramError.missingApplicationCertificateUrl
        }
         
        let (data, response, error) = URLSession.shared.synchronousDataTask(urlRequest: URLRequest(url: url))
        
        if let error = error {
            self.postToConsole("ERROR: Error getting FPS Certificate: \(error)")
            throw ProgramError.applicationCertificateRequestFailed
        }
        guard response != nil else {
            self.postToConsole("ERROR: FPS Certificate request response empty")
            throw ProgramError.applicationCertificateRequestFailed
        }
        guard data != nil else {
            self.postToConsole("ERROR: FPS Certificate request response data is empty")
            throw ProgramError.applicationCertificateRequestFailed
        }
        
        self.fpsCertificate = data!
        
        // Retrieve useful info for logging
        let certificate = SecCertificateCreateWithData(nil, data! as CFData)
        
        guard certificate != nil else {
            self.postToConsole("ERROR: FPS Certificate data is not a valid DER-encoded")
            throw ProgramError.applicationCertificateRequestFailed
        }
        
        if let certificate = certificate {
            let summary = SecCertificateCopySubjectSummary(certificate) as String?
           
            if let summary = summary {
                self.postToConsole("FPS Certificate received, summary: \(summary)")
            }
        }
    }
    
    /*
      Deletes all the persistable content keys on disk for a specific `Asset`.
      - Parameter asset: The `Asset` value to remove keys for.
    */
    func deleteAllPeristableContentKeys(forAsset asset: Asset) {
        for contentKeyId in asset.contentKeyIdList ?? [] {
            deletePeristableContentKey(withAssetName: asset.name, withContentKeyId: contentKeyId)
        }
    }
    
    func requestContentKeyFromKeySecurityModule(spcData: Data) throws -> Data {
        var ckcData: Data? = nil
        
        guard let url = URL(string: licensingServiceUrl) else {
            postToConsole("ERROR: missingLicensingServiceUrl")
            
            throw ProgramError.missingLicensingServiceUrl
        }
        
        /*
         Before sending a SPC to Key Server (KSM) we need to set provided Licensing Token to "X-AxDRM-Message" HTTP header.
        */
        var ksmRequest = URLRequest(url: url)
        ksmRequest.httpMethod = "POST"
        ksmRequest.setValue(licensingToken, forHTTPHeaderField: "X-AxDRM-Message")
        ksmRequest.httpBody = spcData
        
        let (data, response, error) = URLSession.shared.synchronousDataTask(urlRequest: ksmRequest)
        
        if let error = error {
            postToConsole("ERROR: Error getting CKC: \(error)")
            throw ProgramError.noCKCReturnedByKSM
        }
        guard response != nil else {
            postToConsole("ERROR: CKC request response empty")
            throw ProgramError.noCKCReturnedByKSM
            
        }
        guard data != nil else {
            postToConsole("ERROR: CKC response data is empty")
            throw ProgramError.noCKCReturnedByKSM
        }
        
        postToConsole("SUCCESS Requesting Content Key Context (CKC) from Key Security Module (KSM)")
        
        if let httpUrlResponse = response as? HTTPURLResponse {
            let CKCResponseString = """
            - X-AxDRM-Identity: \(httpUrlResponse.allHeaderFields["X-AxDRM-Identity"] ?? "") \n \
            - X-AxDRM-Server: \(httpUrlResponse.allHeaderFields["X-AxDRM-Server"] ?? "") \n \
            - X-AxDRM-Version: \(httpUrlResponse.allHeaderFields["X-AxDRM-Version"] ?? "") \n
            """
            self.postToConsole("CKC response custom headers:\n \(CKCResponseString)")
        }
        
        ckcData = data

        guard ckcData != nil else {
            self.postToConsole("ERROR: No CKC returned By KSM")
            throw ProgramError.noCKCReturnedByKSM
        }
        
        return ckcData!
    }
}
