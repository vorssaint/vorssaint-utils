// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A short-lived metadata request. The session retains its delegate until
/// completion, then invalidates; no session or observer survives the check.
final class AppUpdateFeedLoader: NSObject, URLSessionDataDelegate {
    private var data = Data()
    private var accepted = false
    private var redirects = 0
    private let completion: (Data?) -> Void

    private init(completion: @escaping (Data?) -> Void) { self.completion = completion }

    static func load(_ url: URL, completion: @escaping (Data?) -> Void) {
        guard AppUpdateFeedSupport.publicURL(url.absoluteString) != nil else {
            completion(nil)
            return
        }
        let delegate = AppUpdateFeedLoader(completion: completion)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: url).resume()
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        accepted = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } == true
            && response.expectedContentLength <= Int64(AppUpdateFeedSupport.byteLimit)
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard accepted, chunk.count <= AppUpdateFeedSupport.byteLimit - data.count else {
            accepted = false
            dataTask.cancel()
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 5, let url = request.url,
              AppUpdateFeedSupport.publicURL(url.absoluteString) != nil else {
            completionHandler(nil)
            return
        }
        completionHandler(URLRequest(url: url))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completion(error == nil && accepted ? data : nil)
    }
}
