//
//  Copyright © 2020 Axinom. All rights reserved.
//
//  Notification.Name
//

import Foundation

extension Notification.Name {
    /*
     The notification that is posted when all the content keys for a given asset have been saved to disk.
     */
    static let HasAvailablePersistableContentKey = Notification.Name("ContentKeyDelegateHasAvailablePersistableContentKey")
    
    // Notification for when download progress has changed.
    static let AssetDownloadProgress = Notification.Name(rawValue: "AssetDownloadProgressNotification")
    
    // Notification for when the download state of an Asset has changed.
    static let AssetDownloadStateChanged = Notification.Name(rawValue: "AssetDownloadStateChangedNotification")
    
    // Notification for when message is sent to player view console
    static let ConsoleMessageSent = Notification.Name(rawValue: "ConsoleMessageSentNotification")
    
    // Notification for when AssetPersistenceManager has completely restored its state.
    //static let AssetPersistenceManagerDidRestoreState = Notification.Name(rawValue: "AssetPersistenceManagerDidRestoreStateNotification")
}
