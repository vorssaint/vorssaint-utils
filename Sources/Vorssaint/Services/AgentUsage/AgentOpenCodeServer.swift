// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The allowance OpenCode's own background server reports for the Console
/// workspace it is signed in to, as OpenCode's usage page shows it: the
/// rolling five-hour and weekly Go meters. Only the server on this Mac is
/// asked, at the loopback address and with the password OpenCode keeps beside
/// it; OpenCode's account sign-in is never read.
enum AgentOpenCodeServer {
    enum Failure: Error, Equatable {
        /// OpenCode is not running, or a server from before this route.
        case unreachable
        /// Signed out, or on a plan with no allowance to show.
        case noAllowance
    }

    /// Asked while the AI page shows, and otherwise, as Codex's account is.
    static let freshness: TimeInterval = 60
    static let backgroundFreshness: TimeInterval = 5 * 60
    /// A server that was not there, or an answer that did not arrive.
    static let retryAfter: TimeInterval = 5 * 60
    static let settledRetry: TimeInterval = 30 * 60
    static let timeout: TimeInterval = 5

    /// How long after the last check OpenCode is asked again.
    static func interval(after failure: Failure?, pageVisible: Bool) -> TimeInterval {
        switch failure {
        case nil: return pageVisible ? freshness : backgroundFreshness
        case .unreachable?: return retryAfter
        case .noAllowance?: return settledRetry
        }
    }

    /// Where OpenCode keeps the address and password of the server it runs.
    static func serviceFile(home: URL) -> URL {
        home.appending(path: ".local/state/opencode/service.json")
    }

    struct Service: Equatable {
        let url: URL
        let password: String
    }

    private static let loopback: Set<String> = ["127.0.0.1", "::1", "localhost"]

    /// The running server's address, only while it is on this Mac, and the
    /// password that guards it.
    static func service(home: URL) -> Service? {
        guard let data = try? Data(contentsOf: serviceFile(home: home)),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = json["url"] as? String, let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), loopback.contains(host),
              let password = json["password"] as? String, !password.isEmpty else { return nil }
        return Service(url: url, password: password)
    }

    /// The one route OpenCode's usage page reads, asked with the password its
    /// server generates for itself.
    static func request(_ service: Service, timeout: TimeInterval = timeout) -> URLRequest {
        var request = URLRequest(url: service.url.appending(path: "api/experimental/usage/limits"),
                                 timeoutInterval: timeout)
        let credential = Data("opencode:\(service.password)".utf8).base64EncodedString()
        request.setValue("Basic " + credential, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// The Go allowance's windows from the answer that route gives. Nil when
    /// the workspace has none, or when none of its windows is still running,
    /// which is not the same as no use.
    static func limits(_ json: Any, observed: Date) -> AgentLimits? {
        guard let root = json as? [String: Any], let data = root["data"] as? [String: Any],
              let go = data["go"] as? [String: Any] else { return nil }
        let windows = [("rolling", AgentLimitWindow.Kind.session, 300, "opencode.rolling"),
                       ("weekly", .weekly, 10_080, "opencode.weekly")]
            .compactMap { key, kind, minutes, id -> AgentLimitWindow? in
                guard let meter = go[key] as? [String: Any], let number = meter["percent"] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
                // A window that renewed before this reading says nothing about
                // the one running now.
                let resets = AgentLogParser.seconds(meter["resetsAt"])
                guard resets == nil || resets.map({ $0 > observed }) == true else { return nil }
                return AgentLimitWindow(id: id, kind: kind, minutes: minutes, scope: nil,
                                        usedPercent: min(100, max(0, number.doubleValue)), resetsAt: resets)
            }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .opencode, windows: windows, observedAt: observed, source: .account)
    }

    /// A short-lived request whose answer is dropped once the section pauses,
    /// stops or reads again.
    final class Request {
        private let lock = NSLock()
        private let redirects = Redirects()
        private var task: URLSessionDataTask?
        private var session: URLSession?
        private var cancelled = false

        func start(home: URL, now: Date = Date(),
                   completion: @escaping (Result<AgentLimits, Failure>) -> Void) {
            guard let service = AgentOpenCodeServer.service(home: home) else {
                completion(.failure(.unreachable))
                return
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = AgentOpenCodeServer.timeout
            configuration.timeoutIntervalForResource = AgentOpenCodeServer.timeout
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            // A session keeps its delegate alive, and the delegate keeps this
            // request alive until the answer lands or it is cancelled.
            let session = URLSession(configuration: configuration, delegate: redirects, delegateQueue: nil)
            let task = session.dataTask(with: AgentOpenCodeServer.request(service)) { [weak self] data, response, error in
                guard let self, !self.lock.withLock({ self.cancelled }) else { return }
                self.lock.withLock {
                    self.task = nil
                    self.session = nil
                    self.redirects.owner = nil
                }
                session.finishTasksAndInvalidate()
                guard error == nil, let response = response as? HTTPURLResponse, response.statusCode == 200,
                      let data, let json = try? JSONSerialization.jsonObject(with: data) else {
                    completion(.failure(.unreachable))
                    return
                }
                if let limits = AgentOpenCodeServer.limits(json, observed: now) {
                    completion(.success(limits))
                } else {
                    completion(.failure(.noAllowance))
                }
            }
            let accepted = lock.withLock { () -> Bool in
                guard !cancelled else { return false }
                redirects.owner = self
                self.session = session
                self.task = task
                return true
            }
            guard accepted else {
                session.invalidateAndCancel()
                return
            }
            task.resume()
        }

        func cancel() {
            let active = lock.withLock { () -> URLSession? in
                cancelled = true
                let session = self.session
                self.task?.cancel()
                self.task = nil
                self.session = nil
                redirects.owner = nil
                return session
            }
            active?.invalidateAndCancel()
        }

        /// The usage route never redirects; following one could send the
        /// loopback password to another address.
        private final class Redirects: NSObject, URLSessionTaskDelegate {
            var owner: Request?

            func urlSession(_ session: URLSession, task: URLSessionTask,
                            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                            completionHandler: @escaping (URLRequest?) -> Void) {
                completionHandler(nil)
            }
        }
    }
}
