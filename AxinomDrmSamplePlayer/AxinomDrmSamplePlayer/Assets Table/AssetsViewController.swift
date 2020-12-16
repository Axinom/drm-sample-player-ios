//
//  Copyright © 2020 Axinom. All rights reserved.
//
//  AssetsViewController provides a list of the assets the sample can play, download, cancel download, and delete.
//  To play an item, tap on the tableViewCell.
//  To Cancel, Download or Delete an asset, press on the accessory indicator "i" of the cell
//  and you will be provided options based on the download state associated with the Asset on the cell.
//  You can Download or Cancel/Delete an asset from PlayerViewController that will become visible upon opening an Asset.
//

import UIKit
import AVFoundation

let kLocalStreamsFileName = "Streams"
let kShowVideoPlayerSegueId = "showVideoPlayer"

// Struct representing a Stream parsed from JSON
struct StreamData: Codable, Hashable {
    let title: String
    let videoUrl: String
    let licenseServer: String
    let fpsCertificateUrl: String
    let licenseToken: String
}

class AssetsViewController: UIViewController {

    @IBOutlet var assetsTable: UITableView!
    
    // All parsed streams
    var streams = [StreamData]()
    
    // Asset instances are mapped to StreamData structure and used to fill AssetListTableViewCell
    var streamToAssetMap = [StreamData: Asset]()
    
    // Stream selected by the user
    var chosenStream: StreamData?
    
    // The asset of the stream selected by the user
    var chosenAsset: Asset?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Read Streams.json
        if let localData = self.readLocalStreamsJson() {
            // Parse Data read from Streams.json
            self.parseStreamsJson(jsonData: localData)
        }
    }
    
    // Reads Streams.json
    private func readLocalStreamsJson() -> Data? {
        do {
            if let bundlePath = Bundle.main.path(forResource: kLocalStreamsFileName,
                                                 ofType: "json"),
                let jsonData = try String(contentsOfFile: bundlePath).data(using: .utf8) {
                return jsonData
            }
        } catch {
            print(error.localizedDescription)
        }
        
        return nil
    }
    
    // Parses Streams.json and creates Asset instances for each entry
    // Asset instances are mapped to StreamData structure and used to fill AssetListTableViewCell
    private func parseStreamsJson(jsonData: Data) {
        do {
            // Decode Streams.json into StreamData structure
            self.streams = try JSONDecoder().decode([StreamData].self,
                                                       from: jsonData)
            for stream in streams {
                guard let url = URL(string: stream.videoUrl) else {
                    throw ProgramError.missingAssetUrl
                }
                
                let asset: Asset = Asset(name: stream.title, url: url)
                
                // Used to fill AssetListTableViewCell
                streamToAssetMap[stream] = asset
            }
        } catch {
            print(error.localizedDescription)
        }
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Actions performed before launching Player View Controller
        if segue.identifier == kShowVideoPlayerSegueId,
           let playerViewController = segue.destination as? PlayerViewController {
            
            guard let chosenStream = chosenStream else {
                return
            }
            
            // Assume that only protected streams will have Licensing Server Url in Streams.json
            let isProtectedPlayback = !chosenStream.licenseServer.isEmpty
            
            // Assigning chosen asset to Player View Contreller
            // Is used during download and delete operations
            playerViewController.asset = chosenAsset
            
            // Indicates whether player is opened to play a protected asset
            playerViewController.isProtectedPlayback = isProtectedPlayback
            
            if (isProtectedPlayback) {
                // Creting Content Key Session
                ContentKeyManager.sharedManager.createContentKeySession()
                
                // Licensing Service Url
                ContentKeyManager.sharedManager.licensingServiceUrl = chosenStream.licenseServer
                
                // Licensing Token
                ContentKeyManager.sharedManager.licensingToken = chosenStream.licenseToken
                
                // Certificate Url
                ContentKeyManager.sharedManager.fpsCertificateUrl = chosenStream.fpsCertificateUrl
            }
        }
    }
}

extension AssetsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let cell = tableView.cellForRow(at: indexPath) as? AssetListTableViewCell
        
        chosenStream = streams[indexPath.row]
        chosenAsset = cell?.asset
        
        return indexPath
    }
    
    // Actions for the accessary button on a table cell. Allowing to cancel the ongoing download or delete a saved asset
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? AssetListTableViewCell, let asset = cell.asset else { return }
        
        let downloadState = AssetDownloader.sharedDownloader.downloadStateOfAsset(asset: asset)
        let alertAction: UIAlertAction
        
        switch downloadState {
        
        case .notDownloaded:
            return
        case .downloading:
            alertAction = UIAlertAction(title: "Cancel", style: .default) { _ in
                AssetDownloader.sharedDownloader.cancelDownloadOfAsset(asset: asset)
            }
            
        case .downloadedAndSavedToDevice:
            alertAction = UIAlertAction(title: "Delete", style: .default) { _ in
                AssetDownloader.sharedDownloader.deleteDownloadedAsset(asset: asset)
            }
        }
        
        let alertController = UIAlertController(title: asset.name, message: "Select from the following options:", preferredStyle: .actionSheet)
        alertController.addAction(alertAction)
        alertController.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
        
        // iPad
        if UIDevice.current.userInterfaceIdiom == .pad {
            guard let popoverController = alertController.popoverPresentationController else {
                return
            }
            
            popoverController.sourceView = cell
            popoverController.sourceRect = cell.bounds
        }
        
        present(alertController, animated: true, completion: nil)
    }
}

extension AssetsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return streams.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AssetListTableViewCell.reuseIdentifier, for: indexPath)

        if let cell = cell as? AssetListTableViewCell {
            NotificationCenter.default.removeObserver(cell,
                                                      name: .AssetDownloadStateChanged,
                                                      object: nil)
            
            NotificationCenter.default.removeObserver(cell,
                                                      name: .AssetDownloadProgress,
                                                      object: nil)
            
            let stream = streams[indexPath.row]
    
            cell.asset = streamToAssetMap[stream]
            cell.delegate = self
        }

        return cell
    }
}

extension AssetsViewController: AssetListTableViewCellDelegate {
    // Reloads cell to show fresh download state
    func assetListTableViewCell(_ cell: AssetListTableViewCell, downloadStateDidChange newState: Asset.DownloadState) {
        guard let indexPath = assetsTable.indexPath(for: cell) else {
            return
        }
        assetsTable.reloadRows(at: [indexPath], with: .automatic)
    }
}
