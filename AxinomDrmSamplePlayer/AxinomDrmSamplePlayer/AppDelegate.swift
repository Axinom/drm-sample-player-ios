//
//  Copyright © 2020 Axinom. All rights reserved.
//
//  AppDelegate is the AppDelegate for this sample. No additionl work performed in this class.
//

import UIKit
import AVFoundation
    
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

