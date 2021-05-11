//
//  Copyright © 2020 Axinom. All rights reserved.
//
//  LogManager class. Writes messages to the TextView.
//

import Foundation
import UIKit

class LogManager: NSObject {

    // A singleton instance of LogManager
    static let sharedManager = LogManager()
    
    // Initialization time, used to calculate text entry time
    fileprivate let initTime = Date().toMillis()!
    
    fileprivate var logMessageAll: String = ""
    fileprivate var logMessageKeyDelivery: String = ""
    fileprivate var logMessagePlayback: String = ""
    fileprivate var logMessageDownload: String = ""
    
    var textView: UITextView?
    
    var logLevel: LogManagerLevel = LogManagerLevel.LogManagerLevelAll
    
    enum LogManagerLevel {
        case LogManagerLevelAll
        case LogManagerLevelKeyDelivery
        case LogManagerLevelPlayback
        case LogManagerLevelDownload
    }
    
    enum LogMessageType {
        case LogMessageTypeAll
        case LogMessageTypeKeyDelivery
        case LogMessageTypePlayback
        case LogMessageTypeDownload
    }
    
    // Prints message to the Console view.
    // Also showing the amount of time in ms it took relatively to PlayerViewContorller's init time.
    // Dublicates output to Xcode debug console.
    func writeToTextView(_ textView: UITextView, _ message: String, _ type: LogMessageType = LogMessageType.LogMessageTypeAll) {
        
        self.textView = textView
        
        DispatchQueue.main.async {
            let timeDeltaMs: Int64 = Date().toMillis()! - self.initTime
            
            let dateFormmater = DateFormatter()
            dateFormmater.timeZone = TimeZone(identifier: "UTC")
            dateFormmater.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS'Z'"
            
            let dateString = dateFormmater.string(from: Date())
            
            self.logMessageAll = NSString(format: "%@%@%dms (%@) %@\n", self.logMessageAll,  self.logMessageAll.isEmpty ? "\n" : "", timeDeltaMs, dateString,  message) as String
            
            switch type {
            case .LogMessageTypePlayback:
                self.logMessagePlayback = NSString(format: "%@%@%dms (%@) %@\n", self.logMessagePlayback,  self.logMessagePlayback.isEmpty ? "\n" : "", timeDeltaMs, dateString,  message) as String
            case .LogMessageTypeKeyDelivery:
                self.logMessageKeyDelivery = NSString(format: "%@%@%dms (%@) %@\n", self.logMessageKeyDelivery,  self.logMessageKeyDelivery.isEmpty ? "\n" : "", timeDeltaMs, dateString,  message) as String
            case .LogMessageTypeDownload:
                self.logMessageDownload = NSString(format: "%@%@%dms (%@) %@\n", self.logMessageDownload,  self.logMessageDownload.isEmpty ? "\n" : "", timeDeltaMs, dateString,  message) as String
            case .LogMessageTypeAll:
                break
                // Saving all messages before
            }
            
            self.writeMessageForLevel(self.logLevel)
            
            print("CONSOLE OUTPUT: \(message)")
        }
    }
    
    func writeMessageForLevel(_ level: LogManagerLevel) {
        switch level {
        case .LogManagerLevelAll:
            self.textView!.text = self.logMessageAll
        case .LogManagerLevelKeyDelivery:
            self.textView!.text = self.logMessageKeyDelivery
        case .LogManagerLevelPlayback:
            self.textView!.text = self.logMessagePlayback
        case .LogManagerLevelDownload:
            self.textView!.text = self.logMessageDownload
        }
    }
    
    func swithLogLevel(_ level: LogManagerLevel) {
        self.writeMessageForLevel(level)
    }
    
    func clear() {
        logMessageAll = ""
        logMessageKeyDelivery = ""
        logMessagePlayback = ""
        logMessageDownload = ""
        
        self.textView?.text = ""
    }
}

