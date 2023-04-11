//
//  Copyright © 2020 Axinom. All rights reserved.
//
//  PlayerViewController uses a native AVPlayer as a base and provides a Video Player user interface together with
//  capabilities of managing the downloading process, deleting downloaded media together with the
//  Content Key associated with an asset.
//
//  Togglable Console view allows user to see verbose logging of the steps performed during
//  the playback of protected and non-protected assets, FairPlay content protection related activity,
//  as well as AVPlayerItem and AVPlayer statuses, buffer events, and Access log
//  and Error log events associated with AVPlayerItem.
//  Console output can be cleared and copied to the device clipboard.
//

import UIKit
import AVKit

class PlayerViewController: UIViewController {
    @IBOutlet weak var consoleOverlayView: ConsoleOverlayView!
    @IBOutlet weak var consoleTextView: UITextView!
    @IBOutlet weak var clearConsoleButton: UIButton!
    @IBOutlet weak var copyConsoleButton: UIButton!
    @IBOutlet weak var saveDeleteAssetButton: UIButton!
    @IBOutlet weak var renewLicenseButton: UIButton!
    @IBOutlet weak var showAllMessagesButton: UIButton!
    @IBOutlet weak var showDownloadMessagesButton: UIButton!
    @IBOutlet weak var showKeyDeliveryMessagesButton: UIButton!
    @IBOutlet weak var showPlaybackMessagesButton: UIButton!
    
    // Current asset
    var asset: Asset!
    
    // Indicates whether player is opened to play protected asset
    var isProtectedPlayback: Bool = false
            
    // Last observed bitrate
    fileprivate var lastBitrate:Double = 0
    
    // Used to caclulate stall duration
    fileprivate var stallBeginTime:Int64 = 0
    
    // Indicates ongoing stall
    fileprivate var isStalling = false
    
    // Asset downloader
    fileprivate var downloader: AssetDownloader = AssetDownloader.sharedDownloader
                
    // Player
    @objc fileprivate var player:AVPlayer? = nil
                
    override func viewDidLoad() {
        super.viewDidLoad()
        
        writeToConsole("Initiating playback of: \(asset.name)", LogManager.LogMessageType.LogMessageTypePlayback)

        // Using downloaded asset, if exists
        if let downloadedAsset = downloader.downloadedAsset(withName: asset.name) {
            writeToConsole("OFFLINE PLAYBACK", LogManager.LogMessageType.LogMessageTypePlayback)
            writeToConsole("Using AVURLAsset from \(String(describing: downloadedAsset.urlAsset?.url)))", LogManager.LogMessageType.LogMessageTypePlayback)
            
            asset = downloadedAsset
        }
        
        // Using different AVURLAsset to allow simultaneous playback and download
        asset.createUrlAsset()
        
        if (isProtectedPlayback) {
            // Making the asset a Content Key Session recepient
            asset.addAsContentKeyRecipient()
            
            // Assigning chosen asset to Content Key Session manager
            // Is used to request Persistable Content Keys and writing them to disk
            ContentKeyManager.sharedManager.asset = asset
        }
        
        prepareSaveDeleteAssetButton(forState: downloader.downloadStateOfAsset(asset: asset))
                
        writeToConsole("Initiating AVPlayer with AVPlayerItem", LogManager.LogMessageType.LogMessageTypePlayback)
        
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset.urlAsset))
    
        writeToConsole("AVPlayer Ready", LogManager.LogMessageType.LogMessageTypePlayback)
            
        // Observe player and playerItem states as well as NotificationCenter relevant notifications
        addObservers()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // UI, Console overlay
        let playerFrame = CGRect(x: 0, y: 0, width: view.frame.width, height: view.frame.height)
        let playerViewController: AVPlayerViewController = AVPlayerViewController()
        
        playerViewController.player = player
        playerViewController.view.frame = playerFrame
        
        addChild(playerViewController)
        view.addSubview(playerViewController.view)
        playerViewController.didMove(toParent: self)
        
        view.addSubview(consoleOverlayView)
        consoleOverlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            consoleOverlayView.heightAnchor.constraint(equalTo: view.heightAnchor, constant: -150),
            consoleOverlayView.widthAnchor.constraint(equalTo: view.widthAnchor),
            consoleOverlayView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            consoleOverlayView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    // MARK: Observers
    // Most of the observed notifications are handed for console logging purpose
    // Mandatory notifications are: .HasAvailablePersistableContentKey, .AssetDownloadProgress, .AssetDownloadStateChanged
    func addObservers() {

        // [LOGGING] Add observer for player status
        addObserver(self, forKeyPath: #keyPath(player.status), options: [.new, .initial], context: nil)
        
        // [LOGGING] Add observer for playerItem status
        addObserver(self, forKeyPath: #keyPath(player.currentItem.status), options: [.new, .initial], context: nil)
        
        // [LOGGING] Add observer for playerItem buffer
        addObserver(self, forKeyPath: #keyPath(player.currentItem.isPlaybackBufferEmpty), options: .new, context: nil)
        
        // [LOGGING] Add observer for monitoring buffer full event
        addObserver(self, forKeyPath: #keyPath(player.currentItem.isPlaybackBufferFull), options: .new, context: nil)
        
        // [LOGGING] Add observer for monitoring whether the item will likely play through without stalling
        addObserver(self, forKeyPath: #keyPath(player.currentItem.isPlaybackLikelyToKeepUp), options: .new, context: nil)
        
        // [LOGGING] Provides a collection of time ranges for which the player has the media data readily available
        addObserver(self, forKeyPath: #keyPath(player.currentItem.loadedTimeRanges), options: .new, context: nil)
        
        // [LOGGING] Indicates whether output is being obscured because of insufficient external protection
        addObserver(self, forKeyPath: #keyPath(player.isOutputObscuredDueToInsufficientExternalProtection), options: .new, context: nil)
        
        // [LOGGING] Console message arrived
        NotificationCenter.default.addObserver(self, selector: #selector(handleConsoleMessageSent(_:)), name: NSNotification.Name.ConsoleMessageSent, object: nil)
        
        // [LOGGING] Item has failed to play to its end time
        NotificationCenter.default.addObserver(self, selector: #selector(itemFailedToPlayToEndTime), name: NSNotification.Name.AVPlayerItemFailedToPlayToEndTime, object: player?.currentItem)
        
        // [LOGGING] Item has played to its end time
        NotificationCenter.default.addObserver(self, selector: #selector(itemDidPlayToEndTime), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
        
        // [LOGGING] Media did not arrive in time to continue playback
        NotificationCenter.default.addObserver(self, selector: #selector(itemPlaybackStalled), name: NSNotification.Name.AVPlayerItemPlaybackStalled, object: player?.currentItem)
        
        // [LOGGING] A new access log entry has been added
        NotificationCenter.default.addObserver(self, selector: #selector(itemNewAccessLogEntry), name: NSNotification.Name.AVPlayerItemNewAccessLogEntry, object: player?.currentItem)
        
        // [LOGGING] A new error log entry has been added
        NotificationCenter.default.addObserver(self, selector: #selector(itemNewErrorLogEntry), name: NSNotification.Name.AVPlayerItemNewErrorLogEntry, object: player?.currentItem)

        // [LOGGING] A media selection group changed its selected option
        NotificationCenter.default.addObserver(self, selector: #selector(mediaSelectionDidChange), name: AVPlayerItem.mediaSelectionDidChangeNotification, object: player?.currentItem)
        
        // [MANDATORY] ContentKey delegate did save a Persistable Content Key
        NotificationCenter.default.addObserver(self, selector: #selector(handleContentKeyDelegateHasAvailablePersistableContentKey(notification:)), name: .HasAvailablePersistableContentKey, object: nil)
        
        // [MANDATORY] State of downloading process is changed
        NotificationCenter.default.addObserver(self, selector: #selector(handleAssetDownloadStateChanged(_:)), name: .AssetDownloadStateChanged, object: nil)
        
        // [MANDATORY] Track asset download progress
        NotificationCenter.default.addObserver(self, selector: #selector(handleAssetDownloadProgress(_:)),name: .AssetDownloadProgress, object:nil)
    }
    
    // All observed values are handed for console logging purpose
    // [LOGGING]
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        // Player Item Status
        if keyPath == #keyPath(player.currentItem.status) {
            let status: AVPlayerItem.Status

            // Get the status change from the change dictionary
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
            }

            // Switch over the status
            switch status {
            case .readyToPlay:
                writeToConsole("Player item is ready to play", LogManager.LogMessageType.LogMessageTypePlayback)
            case .failed:
                writeToConsole("Player item failed error: \(String(describing: player?.currentItem?.error?.localizedDescription))\n Debug info: \(String(describing: player?.currentItem?.error.debugDescription))", LogManager.LogMessageType.LogMessageTypePlayback)
            case .unknown:
                writeToConsole("Player item is not yet ready", LogManager.LogMessageType.LogMessageTypePlayback)
            @unknown default:
                writeToConsole("UNEXPECTED STATUS", LogManager.LogMessageType.LogMessageTypePlayback)
            }
        }

        // Player Status
        if keyPath == #keyPath(player.status) {
            let status: AVPlayer.Status

            // Get the status change from the change dictionary
            if let statusNumber = change?[.newKey] as? NSNumber {
               status = AVPlayer.Status(rawValue: statusNumber.intValue)!
            } else {
               status = .unknown
            }

            // Switch over the status
            switch status {
            case .readyToPlay:
               writeToConsole("Player is ready to play AVPlayerItem instances", LogManager.LogMessageType.LogMessageTypePlayback)
            case .failed:
               writeToConsole("Player can no longer play AVPlayerItem instances because of an error: \(String(describing: player?.error?.localizedDescription))\n Debug info: \(String(describing: player?.error.debugDescription))", LogManager.LogMessageType.LogMessageTypePlayback)
            case .unknown:
               writeToConsole("Player is not yet ready", LogManager.LogMessageType.LogMessageTypePlayback)
            @unknown default:
               writeToConsole("UNEXPECTED STATUS", LogManager.LogMessageType.LogMessageTypePlayback)
            }
        }
        
        /*
         This property communicates a prediction of playability. Factors considered in this prediction
         include I/O throughput and media decode performance. It is possible for playbackLikelyToKeepUp to
         indicate NO while the property playbackBufferFull indicates YES. In this event the playback buffer has
         reached capacity but there isn't the statistical data to support a prediction that playback is likely to
         keep up. It is left to the application programmer to decide to continue media playback or not.
        */
        
        if keyPath == #keyPath(player.currentItem.isPlaybackBufferEmpty) {
            
            guard let currentItem = player!.currentItem else {
                return
            }
            
            if currentItem.isPlaybackBufferEmpty {
                writeToConsole("Data buffer used for playback is empty. Playback will stall or end", LogManager.LogMessageType.LogMessageTypePlayback)
            } else {
                writeToConsole("Data buffer used for playback is not empty anymore", LogManager.LogMessageType.LogMessageTypePlayback)
            }
        }
        
        /*
         This property reports that the data buffer used for playback has reach capacity.
         Despite the playback buffer reaching capacity there might not exist sufficient statistical
         data to support a playbackLikelyToKeepUp prediction of YES. See playbackLikelyToKeepUp above
        */
        if keyPath == #keyPath(player.currentItem.isPlaybackBufferFull) {
            
            guard let currentItem = player!.currentItem else {
                return
            }
            
            if currentItem.isPlaybackBufferFull {
                writeToConsole("Data buffer used for playback is full", LogManager.LogMessageType.LogMessageTypePlayback)
            } else {
                writeToConsole("Data buffer used for playback is not full anymore", LogManager.LogMessageType.LogMessageTypePlayback)
            }
        }
        
        /*
         This property communicates a prediction of playability. Factors considered in this prediction
         include I/O throughput and media decode performance. It is possible for playbackLikelyToKeepUp to
         indicate NO while the property playbackBufferFull indicates YES. In this event the playback buffer has
         reached capacity but there isn't the statistical data to support a prediction that playback is likely to
         keep up. It is left to the application programmer to decide to continue media playback or not.
         See playbackBufferFull below.
        */
        if keyPath == #keyPath(player.currentItem.isPlaybackLikelyToKeepUp) {
            guard let currentItem = player!.currentItem else {
                return
            }
            
            if currentItem.isPlaybackLikelyToKeepUp {
                writeToConsole("Playback will likely to keep up", LogManager.LogMessageType.LogMessageTypePlayback)
                
                if isStalling {
                    isStalling = false
                    let stallDurationMs: Int64 = Date().toMillis()! - stallBeginTime
                    writeToConsole("Stall took \(stallDurationMs) ms", LogManager.LogMessageType.LogMessageTypePlayback)
                }
                
            } else {
                writeToConsole("Playback will likey to fail", LogManager.LogMessageType.LogMessageTypePlayback)
            }
        }
        
        if keyPath == #keyPath(player.isOutputObscuredDueToInsufficientExternalProtection) {
            if player!.isOutputObscuredDueToInsufficientExternalProtection {
                writeToConsole("Output is being obscured because current device configuration does not meet the requirements for protecting the item", LogManager.LogMessageType.LogMessageTypePlayback)
            } else {
                writeToConsole("OK. Device configuration meets the requirements for protecting the item", LogManager.LogMessageType.LogMessageTypePlayback)
            }
        }
    }
    
    // [LOGGING]
    // Item has failed to play to its end time
    @objc func itemFailedToPlayToEndTime(_ notification: Notification) {
        let error:Error? = notification.userInfo!["AVPlayerItemFailedToPlayToEndTimeErrorKey"] as? Error
        
        writeToConsole("Item failed to play to the end. Error: \(String(describing:error?.localizedDescription)), error: \(String(describing: error))", LogManager.LogMessageType.LogMessageTypePlayback)
    }
    
    // Item has played to its end time
    // [LOGGING]
    @objc func itemDidPlayToEndTime(_ notification: Notification) {
        writeToConsole("Item has played to its end time", LogManager.LogMessageType.LogMessageTypePlayback)
    }
    
    // Media did not arrive in time to continue playback
    // [LOGGING]
    @objc func itemPlaybackStalled(_ notification: Notification) {
        isStalling = true
        // Used to calculate time delta of the stall which is printed to the Console
        stallBeginTime = Date().toMillis()!
        
        writeToConsole("Stall occured. Media did not arrive in time to continue playback", LogManager.LogMessageType.LogMessageTypePlayback)
    }
    
    // A new access log entry has been added
    // [LOGGING]
    @objc func itemNewAccessLogEntry(_ notification: Notification) {
        
        guard let playerItem = notification.object as? AVPlayerItem,
            let lastEvent = playerItem.accessLog()?.events.last else {
            return
        }
        
        if lastEvent.indicatedBitrate != lastBitrate {
            writeToConsole("Bitrate changed to \(bytesToHumanReadable(bytes: lastEvent.indicatedBitrate))", LogManager.LogMessageType.LogMessageTypePlayback)
        }

        writeToConsole("""
            \n-------------- NEW PLAYER ACCESS LOG ENTRY -------------- \n \
            URI: \(String(describing: lastEvent.uri)) \n \
            PLAYBACK SESSION ID: \(String(describing: lastEvent.playbackSessionID)) \n \
            PLAYBACK START DATE: \(String(describing: lastEvent.playbackStartDate)) \n \
            PLAYBACK START OFFSET: \(lastEvent.playbackStartOffset) \n \
            PLAYBACK TYPE: \(String(describing: lastEvent.playbackType)) \n \
            INDICATED BITRATE (ADVERTISED BY SERVER): \(bytesToHumanReadable(bytes: lastEvent.indicatedBitrate)) \n \
            OBSERVED BITRATE (ACROSS ALL MEDIA DOWNLOADED): \(bytesToHumanReadable(bytes: lastEvent.observedBitrate)) \n \
            AVERAGE BITRATE REQUIRED TO PLAY THE STREAM (ADVERTISED BY SERVER): \(bytesToHumanReadable(bytes: lastEvent.indicatedAverageBitrate)) \n \
            BYTES TRANSFERRED: \(bytesToHumanReadable(bytes: Double(lastEvent.numberOfBytesTransferred))) \n \
            STARTUP TIME: \(lastEvent.startupTime) \n \
            DURATION WATCHED: \(lastEvent.durationWatched) \n \
            NUMBER OF DROPPED VIDEO FRAMES: \(lastEvent.numberOfDroppedVideoFrames) \n \
            NUMBER OF STALLS: \(lastEvent.numberOfStalls) \n \
            NUMBER OF TIMES DOWNLOADING SEGMENTS TOOK TOO LONG: \(lastEvent.downloadOverdue) \n \
            TOTAL DURATION OF DOWNLOADED SEGMENTS: \(lastEvent.segmentsDownloadedDuration)
        """, LogManager.LogMessageType.LogMessageTypePlayback)
    }
    
    // A new error log entry has been added
    // [LOGGING]
    @objc func itemNewErrorLogEntry(_ notification: Notification) {
        
        guard let playerItem = notification.object as? AVPlayerItem,
            let lastEvent = playerItem.errorLog()?.events.last else {
            return
        }

        writeToConsole("""
            \n-------------- NEW PLAYER ERROR LOG ENTRY -------------- \n \
            URI: \(String(describing: lastEvent.uri)) \n \
            DATE: \(String(describing: lastEvent.date)) \n \
            SERVER: \(String(describing: lastEvent.serverAddress)) \n \
            ERROR STATUS CODE: \(String(describing: lastEvent.errorStatusCode)) \n \
            ERROR DOMAIN: \(String(describing: lastEvent.errorDomain)) \n \
            ERROR COMMENT: \(String(describing: lastEvent.errorComment)) \n \
            PLAYBACK SESSION ID: \(String(describing: lastEvent.playbackSessionID))
        """, LogManager.LogMessageType.LogMessageTypePlayback)
    }
    
    // A media selection group changed its selected option
    // [LOGGING]
    @objc func mediaSelectionDidChange(_ notification: Notification) {
        writeToConsole("A media selection group changed its selected option", LogManager.LogMessageType.LogMessageTypePlayback)
    }
    
    // Begin with stream download process after .ContentKeyDelegateHasAvailablePersistableContentKey notification is received
    @objc func handleContentKeyDelegateHasAvailablePersistableContentKey(notification: Notification) {
        writeToConsole("Persistable Content Key is now available", LogManager.LogMessageType.LogMessageTypeKeyDelivery)
 
//        guard let assetName = notification.userInfo?["name"] as? String,
//            let asset = ContentKeyManager.pendingContentKeyRequests.removeValue(forKey: assetName) else {
//            return
//        }
        
        // Initiate download if not already downloaded
        if downloader.downloadStateOfAsset(asset: asset) != Asset.DownloadState.downloadedAndSavedToDevice && ContentKeyManager.sharedManager.downloadRequestedByUser {
            downloadStream()
            ContentKeyManager.sharedManager.downloadRequestedByUser = false
        }
    }
    
    // Reacting to .ConsoleMessageSent notification posted by ContentKeyManager
    // [LOGGING]
    @objc func handleConsoleMessageSent(_ notification: Notification) {
        guard let message = notification.userInfo!["message"] as? String else {
            return
        }
        writeToConsole(message, LogManager.LogMessageType.LogMessageTypeKeyDelivery)
    }
    
    // Reacting to asset download state changes
    @objc func handleAssetDownloadStateChanged(_ notification: Notification) {
        DispatchQueue.main.async {
        
            guard let downloadStateRawValue = notification.userInfo![Asset.Keys.downloadState] as? String,
                  let downloadState = Asset.DownloadState(rawValue: downloadStateRawValue)
                else {
                    self.writeToConsole("Download state missing", LogManager.LogMessageType.LogMessageTypeDownload)
                    return
            }
                    
            switch downloadState {
                case .downloading:
                    var downloadSelectionDisplayName:String
                    
                    // Showing which media selection is being downloaded
                    if let downloadSelection = notification.userInfo?[Asset.Keys.downloadSelectionDisplayName] as? String {
                        downloadSelectionDisplayName  = downloadSelection
                        self.writeToConsole("DOWNLOADING \(String(describing: downloadSelectionDisplayName))", LogManager.LogMessageType.LogMessageTypeDownload)
                    }
                case .downloadedAndSavedToDevice:
                    self.writeToConsole("FINISHED DOWNLOADING", LogManager.LogMessageType.LogMessageTypeDownload)
                case .notDownloaded:
                    self.writeToConsole("ASSET NOT DOWNLOADED", LogManager.LogMessageType.LogMessageTypeDownload)
            }
            
            self.prepareSaveDeleteAssetButton(forState: downloadState)
        }
    }
    
    // Download button can have three different label text variants: "DELETE", "SAVE", "CANCEL"
    // Choosing the right one according to asset download state
    func prepareSaveDeleteAssetButton(forState state: Asset.DownloadState) {
        switch state {
        case .downloadedAndSavedToDevice:
            self.saveDeleteAssetButton.setTitle("DELETE", for: UIControl.State.normal)
        case .notDownloaded:
            self.saveDeleteAssetButton.setTitle("SAVE", for: UIControl.State.normal)
        case .downloading:
            self.saveDeleteAssetButton.setTitle("CANCEL", for: UIControl.State.normal)
        }
    }
    
    // Shows Download progress in %
    // [LOGGING]
    @objc func handleAssetDownloadProgress(_ notification: Notification) {
        guard let progress = notification.userInfo![Asset.Keys.percentDownloaded] as? Double,
              let assetName = notification.userInfo![Asset.Keys.name] as? String,
              assetName == asset.name else { return }
                
        let humanReadableProgress = Double(round(1000 * progress) / 10)
        
        writeToConsole("DOWNLOADING PROGRESS of \(assetName) : \(humanReadableProgress)%", LogManager.LogMessageType.LogMessageTypeDownload)
    }
    
    func downloadStream() {
        writeToConsole("Initiating stream download", LogManager.LogMessageType.LogMessageTypeDownload)
        downloader.download(asset: asset)
    }

    // MARK: Console
    
    // Prints message to the Console view.
    // [LOGGING]
    func writeToConsole(_ message: String, _ messageType: LogManager.LogMessageType = LogManager.LogMessageType.LogMessageTypeAll) {
        LogManager.sharedManager.writeToTextView(self.consoleTextView, message, messageType)
    }

    // Toggles the Console visibility
    // [LOGGING]
    @IBAction func showConsole(_ sender: Any) {
        let hide = !consoleTextView.isHidden

        consoleTextView.isHidden = hide
        copyConsoleButton.isHidden = hide
        clearConsoleButton.isHidden = hide
        showAllMessagesButton.isHidden = hide
        showDownloadMessagesButton.isHidden = hide
        showKeyDeliveryMessagesButton.isHidden = hide
        showPlaybackMessagesButton.isHidden = hide
    }
    
    @IBAction func saveOrDeleteAsset(_ sender: Any) {
        switch downloader.downloadStateOfAsset(asset: asset) {
            case .notDownloaded:
                
                // Using different AVURLAsset to allow simultaneous playback and download
                asset.createUrlAsset()
                
                if isProtectedPlayback {
                    // Create a new Content Key Session for downloading an asset
                    ContentKeyManager.sharedManager.createContentKeySession()
                    
                    // Making the asset a Content Key Session recipient
                    asset.addAsContentKeyRecipient()
                    
                    // This will tell ContenyKeyManager to initiate Persistable Content Key Request
                    ContentKeyManager.sharedManager.downloadRequestedByUser = true
                                        
                    // Initiate Persistable Key Request
                    ContentKeyManager.sharedManager.requestPersistableContentKeys(forAsset: asset)
                    
                    // The download will start after handlePersistableContentKeyRequest signals that the key has been downloaded
                } else {
                    // Download the stream
                    downloadStream()
                }
            case .downloading :
                if isProtectedPlayback {
                    writeToConsole("Cancelling download of \(String(describing: asset.name))", LogManager.LogMessageType.LogMessageTypeDownload)
                          
                    // Remove Content Key from the device
                    ContentKeyManager.sharedManager.deleteAllPeristableContentKeys(forAsset: asset)
                }
                // Cancel current asset downloading process
                downloader.cancelDownloadOfAsset(asset: asset)
            case .downloadedAndSavedToDevice:
                if isProtectedPlayback {
                    writeToConsole("Deleting download of \(String(describing: asset.name))", LogManager.LogMessageType.LogMessageTypeDownload)
                    
                    // Remove Content Key from the device
                    ContentKeyManager.sharedManager.deleteAllPeristableContentKeys(forAsset: asset)
                }
                // Remove downloaded stream from the device
                downloader.deleteDownloadedAsset(asset: asset)
        }
    }
    
    // Renews the license
    @IBAction func renewLicense(_ sender: Any) {
        if (ContentKeyManager.sharedManager.contentKeySession != nil) {
            NSLog("Trying to renew license")
            ContentKeyManager.sharedManager.contentKeySession.renewExpiringResponseData(for: ContentKeyManager.sharedManager.contentKeyRequest)
        } else {
            NSLog("Can't renew license, Content Key Session does not exist")
        }
    }
    
    // Copies Console text to device's clipboard
    // [LOGGING]
    @IBAction func copyConsoleText(_ sender: Any) {
        let pasteBoard = UIPasteboard.general
        pasteBoard.string = consoleTextView.text
    }
    
    // Cleans the Console
    // [LOGGING]
    @IBAction func clearConsoleText(_ sender: Any) {
        LogManager.sharedManager.clear()
    }
    
    // Shows all messages in the Console
    // [LOGGING]
    @IBAction func showAllLogMessages(_ sender: Any) {
        LogManager.sharedManager.swithLogLevel(LogManager.LogManagerLevel.LogManagerLevelAll)
    }
    
    // Shows only playback related messages in the Console
    // [LOGGING]
    @IBAction func showPlaybackLog(_ sender: Any) {
        LogManager.sharedManager.swithLogLevel(LogManager.LogManagerLevel.LogManagerLevelPlayback)
    }
    
    // Shows only key delivery messages in the Console
    // [LOGGING]
    @IBAction func showKeyDeliveryLog(_ sender: Any) {
        LogManager.sharedManager.swithLogLevel(LogManager.LogManagerLevel.LogManagerLevelKeyDelivery)
    }
    
    // Shows only downloading related messages in the Console
    // [LOGGING]
    @IBAction func showDownloadLog(_ sender: Any) {
        LogManager.sharedManager.swithLogLevel(LogManager.LogManagerLevel.LogManagerLevelDownload)
    }
        
    deinit {
        LogManager.sharedManager.clear()
        NotificationCenter.default.removeObserver(self)
    }
}
