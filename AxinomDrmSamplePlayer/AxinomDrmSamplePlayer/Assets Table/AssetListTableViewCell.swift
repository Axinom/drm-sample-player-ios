//
//  Copyright © 2020 Axinom. All rights reserved.
//
//  AssetListTableViewCell is the UITableViewCell subclass that represents an Asset visually in
//  AssetsViewController. This cell handles responding to user events as well as updating itself to reflect the
//  state of the Asset if it has been downloaded, deleted, or is actively downloading.
//

import UIKit
import AVFoundation

class AssetListTableViewCell: UITableViewCell {
    static let reuseIdentifier = "AssetListTableViewCellIdentifier"
    
    @IBOutlet weak var assetNameLabel: UILabel!
    
    @IBOutlet weak var downloadStateLabel: UILabel!
    
    @IBOutlet weak var downloadProgressView: UIProgressView!
    
    weak var delegate: AssetListTableViewCellDelegate?
    
    var asset: Asset? {
        didSet {
            if let asset = asset {
                // Initial label text and progress bar visibility according to download state
                let downloadState = AssetDownloader.sharedDownloader.downloadStateOfAsset(asset: asset)
                    switch downloadState {
                    case .downloadedAndSavedToDevice:
                        downloadProgressView.isHidden = true
                    case .downloading:
                        downloadProgressView.isHidden = false
                    case .notDownloaded:
                        break
                    }

                    downloadStateLabel.text = downloadState.rawValue

                    let notificationCenter = NotificationCenter.default
                    notificationCenter.addObserver(self,
                                                   selector: #selector(handleAssetDownloadStateChanged(_:)),
                                                   name: .AssetDownloadStateChanged, object: nil)
                    notificationCenter.addObserver(self, selector: #selector(handleAssetDownloadProgress(_:)),
                                                   name: .AssetDownloadProgress, object: nil)
                assetNameLabel.text = asset.name
            } 
        }
    }
    
    // Changes label text and progress bar visibility according to download state
    @objc func handleAssetDownloadStateChanged(_ notification: Notification) {
        guard let assetStreamName = notification.userInfo![Asset.Keys.name] as? String,
            let downloadStateRawValue = notification.userInfo![Asset.Keys.downloadState] as? String,
            let downloadState = Asset.DownloadState(rawValue: downloadStateRawValue),
            let asset = asset,
            asset.name == assetStreamName else { return }
        
        DispatchQueue.main.async {
            switch downloadState {
            case .downloading:
                self.downloadProgressView.isHidden = false

                if let downloadSelection = notification.userInfo?[Asset.Keys.downloadSelectionDisplayName] as? String {
                    self.downloadStateLabel.text = "\(downloadState): \(downloadSelection)"
                }

            case .downloadedAndSavedToDevice:
                self.downloadProgressView.isHidden = true
                
            case .notDownloaded:
                self.downloadStateLabel.text = "\(downloadState)"
                self.downloadProgressView.isHidden = true
            }

            // Reload the cell to show a fresh state
            self.delegate?.assetListTableViewCell(self, downloadStateDidChange: downloadState)
        }
    }
    
    // Shows progresss on the progress bar
    @objc func handleAssetDownloadProgress(_ notification: Notification) {
        guard let assetStreamName = notification.userInfo![Asset.Keys.name] as? String,
              asset?.name == assetStreamName else { return }
        guard let progress = notification.userInfo![Asset.Keys.percentDownloaded] as? Double else { return }
        
        self.downloadProgressView.setProgress(Float(progress), animated: true)
    }
}

protocol AssetListTableViewCellDelegate: AnyObject {
    func assetListTableViewCell(_ cell: AssetListTableViewCell, downloadStateDidChange newState: Asset.DownloadState)
}
