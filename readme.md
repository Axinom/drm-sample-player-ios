# Axinom DRM Sample Player

This sample demonstrates how to use the Axinom DRM with AVFoundation framework to play FairPlay protected HTTP Live Streams (HLS) hosted on remote servers as well as how to persist FairPlay protected and non-protected HLS streams on disk for offline playback. 

Sample application's Player View has togglable Console overlay, that allows user to observe verbose logging of the steps performed during the playback of protected and non-protected assets, Fairplay content protection related activity, as well as AVPlayerItem and AVPlayer statuses, buffer events, and Access log and Error log events associated with AVPlayerItem. Console output can be cleared and copied to the device clipboard.

## Installing the application

This application can be downloaded from App Center by either navigating to the [website](https://install.appcenter.ms/orgs/ax/apps/axinom-drm-sample-player/distribution_groups/public) directly or by scanning this QR code with your device:

![QR](InstallQR.png "Install")

**NOTE:**
In order for the app to be available for use, you'll need to trust the developer's certificate. From your phone’s home screen, tap Settings > General > Profiles or Profiles & Device Management. Under the Enterprise App heading, you see will see a profile for the developer. Tap the name of the Axinom GmbH profile and then confirm you trust them. You can now launch the app.

## Using the Sample

Build and run the sample on an actual device running iOS 13.1 or later using Xcode.  The APIs demonstrated in this sample do not work on the iOS Simulator.

This sample provides a list of HLS Streams that you can playback by tapping on the UITableViewCell corresponding to the stream.  If you wish to cancel an already running `AVAggregateAssetDownloadTask` or delete an already downloaded HLS stream from disk, you can accomplish this by tapping on the accessory button on the `UITableViewCell` corresponding to the stream you wish to manage.
If you wish to download an HLS stream initiating an `AVAggregateAssetDownloadTask`, you can accomplish this by tapping the multifunction button (Save/Delete/Cancel) button on Player View Controller. Canceling and deleting downloaded stream actions are can also be performed on Player View Controller by tapping the multifunction button (Save/Delete/Cancel).

When the sample creates and initializes an `AVAggregateAssetDownloadTask` for the download of an HLS stream, only the default selections for each of the media selection groups will be used (these are indicated in the HLS playlist `EXT-X-MEDIA` tags by a DEFAULT attribute of YES).

### Adding Streams to the Sample

If you wish to add your own HLS streams to test with using this sample, you can do this by adding an entry into the Streams.json that is part of the Xcode Project.  There are two important keys you need to provide values for:

__title__: What the display name of the HLS stream should be in the sample, also used as file name for downloaded asset and for storage of the persisten key.

__videoUrl__: The URL of the HLS stream's master playlist.

__licenseServer__:  Axinom DRM License Server URL.

__fpsCertificateUrl__: FairPlay Streaming Certificate URL.

__licenseToken__:  License Token for License Request.

### Application Transport Security

If any of the streams you add are not hosted securely, you will need to add an Application Transport Security (ATS) exception in the Info.plist.  More information on ATS and the relevant plist keys can be found in Apple documentation:

Information Property List Key Reference - NSAppTransportSecurity: <https://developer.apple.com/library/ios/documentation/General/Reference/InfoPlistKeyReference/Articles/CocoaKeys.html#//apple_ref/doc/uid/TP40009251-SW33>

## Important Notes

Saving HLS streams for offline playback is only supported for VOD streams.  If you try to save a live HLS stream, the system will throw an exception. 

## Main Files

__AssetDownloader.swift__: 

- `AssetDownloader` demonstrates how to manage the downloading of HLS streams. It includes APIs for starting and canceling downloads, deleting existing assets of the user's device, and monitoring the download progress and status.

__ContentKeyManager.swift__:

- `ContentKeyManager` class configures the instance of AVContentKeySession to use for requesting Content Keys securely for playback or offline use.

__PlayerViewController.swift__:

- The `PlayerViewController` uses a native AVPlayer as a base and provides a Video Player user interface together with capabilities of managing the downloading process, deleting downloaded media together with the Content Key associated with an asset. Togglable Console view allows user to see verbose logging of the steps performed during the playback of protected and non-protected assets, Fairplay content protection related activity, as well as AVPlayerItem and AVPlayer statuses, buffer events and Access log and Error log events associated with AVPlayerItem. Console output can be cleared and copied to the device clipboard.

__Asset.swift__:

- `Asset` is a class that holds information about an Asset and adds its AVURLAsset as a recipient to the Playback Content Key Session in a protected playback/download use case. DownloadState extension is used to track the download states of Assets, Keys extension is used to define a number of values to use as keys in dictionary lookups.

## Requirements

### Build

Xcode 11.0 or later; iOS 13.0 SDK or later

### Runtime

iOS 13.1 or later.
