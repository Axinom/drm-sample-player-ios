//
//  Copyright © 2020 Axinom. All rights reserved.
//
//  Utils
//

import Foundation

extension Date {
    func toMillis() -> Int64! {
        return Int64(self.timeIntervalSince1970 * 1000)
    }
}

extension URLSession {
    func synchronousDataTask(urlRequest: URLRequest) -> (data: Data?, response: URLResponse?, error: Error?) {
        var data: Data?
        var response: URLResponse?
        var error: Error?

        let semaphore = DispatchSemaphore(value: 0)

        let dataTask = self.dataTask(with: urlRequest) {
            data = $0
            response = $1
            error = $2

            semaphore.signal()
        }
        dataTask.resume()

        _ = semaphore.wait(timeout: .distantFuture)

        return (data, response, error)
    }
}

func bytesToHumanReadable(bytes: Double) -> String {
    let formatter = ByteCountFormatter()
    
    if (bytes.isNaN || bytes.isInfinite) {
        return "-"
    }
    
    return formatter.string(fromByteCount: Int64(bytes)) + "/s"
}

enum ProgramError: Error {
    case missingApplicationCertificate
    case missingApplicationCertificateUrl
    case missingAssetUrl
    case applicationCertificateRequestFailed
    case missingLicensingServiceUrl
    case noCKCReturnedByKSM
}
