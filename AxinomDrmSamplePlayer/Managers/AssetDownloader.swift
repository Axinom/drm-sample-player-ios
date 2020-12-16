//
//  Copyright © 2020 Axinom. All rights reserved.
//
//  AssetDownloader demonstrates how to manage the downloading of HLS streams.
//  It includes APIs for starting and canceling downloads,
//  deleting existing assets of the user's device, and monitoring the download progress and status.

import Foundation
import AVFoundation

class AssetDownloader: NSObject, AVAssetDownloadDelegate  {
    
    // A singleton instance of AssetDownloader
    static let sharedDownloader = AssetDownloader()
    
    // The AVAssetDownloadURLSession to use for managing AVAssetDownloadTasks
    fileprivate var assetDownloadURLSession: AVAssetDownloadURLSession!
            
    // Internal map of AVAggregateAssetDownloadTask to its corresponding Asset
    fileprivate var activeDownloadsMap = [AVAggregateAssetDownloadTask: Asset]()
    
    // Internal map of AVAggregateAssetDownloadTask to download URL
    fileprivate var willDownloadToUrlMap = [AVAggregateAssetDownloadTask: URL]()
    
    override init() {
        super.init()
        
        if assetDownloadURLSession == nil {
            print("DOWNLOADER: Will create AVAssetDownloadURLSession")
            
            // Create the configuration for the AVAssetDownloadURLSession
            let backgroundConfiguration = URLSessionConfiguration.background(withIdentifier: "\(Bundle.main.bundleIdentifier!).background")
            
            // Avoid OS scheduling the background request transfers due to battery or performance
            backgroundConfiguration.isDiscretionary = false
            
            // Makes the TCP sockets open even when the app is locked or suspended
            backgroundConfiguration.shouldUseExtendedBackgroundIdleMode = true
            
            // Create the AVAssetDownloadURLSession using the configuration
            assetDownloadURLSession =
                AVAssetDownloadURLSession(configuration: backgroundConfiguration,
                                          assetDownloadDelegate: self, delegateQueue: OperationQueue.main)
        } else {
            print("DOWNLOADER: AVAssetDownloadURLSession already exists, will reuse")
        }
    }
    
    func download(asset: Asset) {
        print("DOWNLOADER: Download")
        
        guard let urlAsset = asset.urlAsset else {
            print("DOWNLOADER: No AVURLAsset supplied")
            return
        }
        
        // Get the default media selections for the asset's media selection groups
        let preferredMediaSelection = urlAsset.preferredMediaSelection
        
        /*
         Creates and initializes an AVAggregateAssetDownloadTask to download multiple AVMediaSelections
         on an AVURLAsset.
         
         For the initial download, we ask the URLSession for an AVAssetDownloadTask with a minimum bitrate
         corresponding with one of the lower bitrate variants in the asset.
         */
        guard let task = assetDownloadURLSession.aggregateAssetDownloadTask(with: urlAsset,
                                                          mediaSelections: [preferredMediaSelection],
                                                          assetTitle: asset.name,
                                                          assetArtworkData: nil,
                                                          options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 265_000])
            else {
                print("DOWNLOADER: Failed to create AVAggregateAssetDownloadTask")
                return
        }
        
        if activeDownloadsMap[task] != nil {
            print("DOWNLOADER: Asset is already being downloaded")
        } else {
        
            // Map active task to asset
            activeDownloadsMap[task] = asset
            
            task.taskDescription = asset.name
            task.resume()
                        
            // Prepare the basic userInfo dictionary that will be posted as part of our notification
            var userInfo = [String: Any]()
            userInfo[Asset.Keys.name] = asset.name
            userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloading.rawValue
            userInfo[Asset.Keys.downloadSelectionDisplayName] = displayNamesForSelectedMediaOptions(preferredMediaSelection)
            
            NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo: userInfo)
        }
    }
    
    // Returns an Asset pointing to a file on disk if it exists
    func downloadedAsset(withName name: String) -> Asset? {
        let userDefaults = UserDefaults.standard
        
        guard let localFileLocation = userDefaults.value(forKey: name) as? Data else { return nil }

        var bookmarkDataIsStale = false
        do {
            let url = try URL(resolvingBookmarkData: localFileLocation,
                                    bookmarkDataIsStale: &bookmarkDataIsStale)

            if bookmarkDataIsStale {
                fatalError("Bookmark data is stale!")
            }
            
            // Create an asset that will be used during the playback
            let asset = Asset(name: name, url: url)
            
            return asset
        } catch {
            fatalError("Failed to create URL from bookmark with error: \(error)")
        }
    }
    
    // Returns the current download state for a given Asset
    func downloadStateOfAsset(asset: Asset) -> Asset.DownloadState {
        // Check if there is a file URL stored for this asset
        if let localFileLocation = downloadedAsset(withName: asset.name)?.urlAsset?.url {
            // Check if the file exists on disk
            if FileManager.default.fileExists(atPath: localFileLocation.path) {
                
                print("DOWNLOADER: downloadState() \(Asset.DownloadState.downloadedAndSavedToDevice.rawValue)")
                
                return .downloadedAndSavedToDevice
            }
        }
        
        // Check if there are any active downloads in flight
        for (_, assetValue) in activeDownloadsMap where asset.name == assetValue.name {
            print("DOWNLOADER: downloadState() \(Asset.DownloadState.downloading.rawValue)")
            
            return .downloading
        }
        
        print("DOWNLOADER: downloadState() \(Asset.DownloadState.notDownloaded.rawValue)")
        
        return .notDownloaded
    }
    
    // Deletes an Asset from the device if possible
    func deleteDownloadedAsset(asset: Asset) {
        let userDefaults = UserDefaults.standard
    
        do {
            if let localFileLocation = downloadedAsset(withName: asset.name)?.urlAsset?.url {
                try FileManager.default.removeItem(at: localFileLocation)

                userDefaults.removeObject(forKey: asset.name)
                
                print("DOWNLOADER: Deleting downloaded: \(asset.name)")
                
                // Prepare the basic userInfo dictionary that will be posted as part of our notification
                var userInfo = [String: Any]()
                userInfo[Asset.Keys.name] = asset.name
                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.notDownloaded.rawValue
                NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo: userInfo)
            }
        } catch {
            print("DOWNLOADER: An error occured deleting the file: \(error)")
        }
    }
    
    // Canceles the download task
    func cancelDownloadOfAsset(asset: Asset) {
        var task: AVAggregateAssetDownloadTask?
        
        for (taskKey, assetVal) in activeDownloadsMap where asset.name == assetVal.name {
            task = taskKey
            print("DOWNLOADER: Cancelling download of \(String(describing: task?.taskDescription))")
            break
        }
        
        task?.cancel()
    }

    // Tells the delegate that the task finished transferring data
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let userDefaults = UserDefaults.standard
    
        print("DOWNLOADER: Downloading did complete")
        
        /*
         This is the ideal place to begin downloading additional media selections
         once the asset itself has finished downloading.
         */
        guard let task = task as? AVAggregateAssetDownloadTask,
            let asset = activeDownloadsMap.removeValue(forKey: task) else { return }
        
        guard let downloadURL = willDownloadToUrlMap.removeValue(forKey: task) else { return }
        
        // Prepare the basic userInfo dictionary that will be posted as part of our notification
        var userInfo = [String: Any]()
        userInfo[Asset.Keys.name] = asset.name
        
        if let error = error as NSError? {
            switch (error.domain, error.code) {
            case (NSURLErrorDomain, NSURLErrorCancelled):
                
                print("DOWNLOADER: Downloading was cancelled")
                
                userInfo[Asset.Keys.downloadState] = Asset.DownloadState.notDownloaded.rawValue
                
                /*
                 This task was canceled, you should perform cleanup using the
                 URL saved from AVAssetDownloadDelegate.urlSession(_:assetDownloadTask:didFinishDownloadingTo:).
                 */
                guard let localFileLocation = downloadedAsset(withName: asset.name)?.urlAsset?.url else {
                    NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo: userInfo)
                    return
                }
                
                do {
                    try FileManager.default.removeItem(at: localFileLocation)
                    
                    userDefaults.removeObject(forKey: asset.name)
                } catch {
                    print("DOWNLOADER: An error occured trying to delete the contents on disk for \(asset.name): \(error)")
                }
                
            case (NSURLErrorDomain, NSURLErrorUnknown):
                print("DOWNLOADER: Downloading HLS streams is not supported in the simulator.")
                
            default:
                print("DOWNLOADER: An unexpected error occured \(error.domain)")
            }
        } else {
            do {
                let bookmark = try downloadURL.bookmarkData()
                
                userDefaults.set(bookmark, forKey: asset.name)
            } catch {
                print("DOWNLOADER: Failed to create bookmarkData for download URL.")
            }
            
            print("DOWNLOADER: Downloading completed with success")
        
            userInfo[Asset.Keys.downloadState] = Asset.DownloadState.downloadedAndSavedToDevice.rawValue
            userInfo[Asset.Keys.downloadSelectionDisplayName] = ""
        }
        
        NotificationCenter.default.post(name: .AssetDownloadStateChanged, object: nil, userInfo: userInfo)
    }
    
    // Method called when the an aggregate download task determines the location this asset will be downloaded to
    func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                    willDownloadTo location: URL) {
        
        print("DOWNLOADER: will download to location: \(location)")
        
        /*
         This delegate callback should only be used to save the location URL
         somewhere in your application. Any additional work should be done in
         `URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:)`.
         */
        
        willDownloadToUrlMap[aggregateAssetDownloadTask] = location
    }
    
    // Method called when a child AVAssetDownloadTask completes
    func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                    didCompleteFor mediaSelection: AVMediaSelection) {
        
        print("DOWNLOADER: Done with mediaSelection: \(mediaSelection)")
    }
    
    // Method to adopt to subscribe to progress updates of an AVAggregateAssetDownloadTask
    func urlSession(_ session: URLSession, aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                    didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange, for mediaSelection: AVMediaSelection) {
        
        // This delegate callback should be used to provide download progress for your AVAssetDownloadTask
        var percentComplete = 0.0
        for value in loadedTimeRanges {
            let loadedTimeRange: CMTimeRange = value.timeRangeValue
            percentComplete +=
                CMTimeGetSeconds(loadedTimeRange.duration) / CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
        }
        
        // Prepare the basic userInfo dictionary that will be posted as part of our notification
        var userInfo = [String: Any]()
        userInfo[Asset.Keys.name] = aggregateAssetDownloadTask.taskDescription
        userInfo[Asset.Keys.percentDownloaded] = percentComplete
        
        NotificationCenter.default.post(name: .AssetDownloadProgress, object: nil, userInfo: userInfo)
    }
    
    // Return the display names for the media selection options that are currently selected in the specified group
    func displayNamesForSelectedMediaOptions(_ mediaSelection: AVMediaSelection) -> String {
        
        var displayNames = ""
        
        guard let asset = mediaSelection.asset else {
            return displayNames
        }
        
        // Iterate over every media characteristic in the asset in which a media selection option is available.
        for mediaCharacteristic in asset.availableMediaCharacteristicsWithMediaSelectionOptions {
            /*
             Obtain the AVMediaSelectionGroup object that contains one or more options with the
             specified media characteristic, then get the media selection option that's currently
             selected in the specified group.
             */
            guard let mediaSelectionGroup =
                asset.mediaSelectionGroup(forMediaCharacteristic: mediaCharacteristic),
                let option = mediaSelection.selectedMediaOption(in: mediaSelectionGroup) else { continue }
            
            // Obtain the display string for the media selection option.
            if displayNames.isEmpty {
                displayNames += " " + option.displayName
            } else {
                displayNames += ", " + option.displayName
            }
        }
        
        return displayNames
    }
}
