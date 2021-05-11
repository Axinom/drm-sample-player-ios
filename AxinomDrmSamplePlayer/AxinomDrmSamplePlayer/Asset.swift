//
//  Copyright © 2020 Axinom. All rights reserved.
//
//  A class that holds information about an Asset
//  Adds Asset's AVURLAsset as a recipient to the Playback Content Key Session in a protected playback/download use case.
//
//  DownloadState extension is used to track the download states of Assets,
//  Keys extension is used to define a number of values to use as keys in dictionary lookups.
//

import AVFoundation

class Asset {
    
    var name: String
    var url: URL!
    var contentKeyIdList: [String]?
    var urlAsset: AVURLAsset!
    
    init(name: String, url: URL) {
        self.name = name
        self.url = url
        self.contentKeyIdList = [String]()
        
        print("Creating Asset with url: \(url)) name: \(name)")
        
        createUrlAsset()
    }
    
    // Link AVURLAsset to Content Key Session
    func addAsContentKeyRecipient() {
        print("Adding AVURLAsset as a recepient to the Content Key Session")
        ContentKeyManager.sharedManager.contentKeySession.addContentKeyRecipient(urlAsset)
    }
    
    // Using different AVURLAsset to allow simultaneous playback and download
    func createUrlAsset() {
        urlAsset = AVURLAsset(url: url)
    }
}

/*
 Extends `Asset` to add a simple download state enumeration used by the sample
 to track the download states of Assets.
 */
extension Asset {
    enum DownloadState: String {
        case notDownloaded
        case downloading
        case downloadedAndSavedToDevice
    }
}

/*
 Extends `Asset` to define a number of values to use as keys in dictionary lookups.
 */
extension Asset {
    struct Keys {
        /*
         Key for the Asset name, used for `AssetDownloadProgressNotification` and
         `AssetDownloadStateChangedNotification` Notifications as well as
         AssetListManager.
         */
        static let name = "AssetNameKey"
        
        /*
         Key for the Asset download percentage, used for
         `AssetDownloadProgressNotification` Notification.
         */
        static let percentDownloaded = "AssetPercentDownloadedKey"
        
        /*
         Key for the Asset download state, used for
         `AssetDownloadStateChangedNotification` Notification.
         */
        static let downloadState = "AssetDownloadStateKey"
        
        /*
         Key for the Asset download AVMediaSelection display Name, used for
         `AssetDownloadStateChangedNotification` Notification.
         */
        static let downloadSelectionDisplayName = "AssetDownloadSelectionDisplayNameKey"
    }
}
