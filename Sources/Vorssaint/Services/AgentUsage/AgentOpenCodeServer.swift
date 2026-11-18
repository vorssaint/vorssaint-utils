// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Reads OpenCode Go's allowances from OpenCode's own server. The sign-in is
/// the one OpenCode saved for itself, read from its database for each check
/// and never kept, written or sent anywhere else. Only the percentages and
/// renewals come back; a reading names no model, prompt or account.
enum AgentOpenCodeServer {
    enum Failure: Error, Equatable {
        /// OpenCode is not on this Mac, or has no database of its own.
        case missing
        /// The saved sign-in was refused, or there is no token to send.
        case expired
        /// No answer: the network failed, it ran out of time or the server
        /// reported an error of its own.
        case unreachable
        /// An answer this version cannot read.
        case badResponse
    }

    struct Summary: Equatable {
        let limits: AgentLimits
    }

    /// The only place a check asks. A redirect never leaves this host.
    static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!
    static let timeout: TimeInterval = 15
    /// While the AI page is on screen a reading this old is asked again.
    static let freshness: TimeInterval = 60
    /// Otherwise the server is asked at most this often, as the other
    /// account checks are.
    static let backgroundFreshness: TimeInterval = 5 * 60
    static let retryAfter: TimeInterval = 5 * 60
    /// Only the person can install OpenCode or sign in to it again.
    static let settledRetry: TimeInterval = 30 * 60
    /// An answer larger than this is not the small reading asked for.
    static let maximumSize = 1_048_576

    /// How long after the last check the server is asked again. Each check in
    /// a row without an answer doubles the wait, up to the one for what only
    /// the person can fix.
    static func interval(after failure: Failure?, repeated: Int = 1, pageVisible: Bool) -> TimeInterval {
        switch failure {
        case nil: return pageVisible ? freshness : backgroundFreshness
        case .unreachable?: return min(settledRetry, retryAfter * Double(1 << min(3, max(0, repeated - 1))))
        case .missing?, .expired?, .badResponse?: return settledRetry
        }
    }

    /// OpenCode 2 keeps its sign-in in the one database in its data folder.
    static func databaseURL(home: URL) -> URL {
        home.appending(path: ".local/share/opencode/opencode.db")
    }

    /// The access token OpenCode saved for its own server, read fresh from its
    /// database and dropped with the request. The database is opened read-only
    /// and nothing is ever written to it. Nil when there is no token to send.
    static func accessToken(home: URL) -> String? {
        var db: OpaquePointer?
        // SQLite hands back a connection to close even when opening fails.
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(databaseURL(home: home).path, &db,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 2000)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT value FROM credential WHERE integration_id = 'opencode' AND active = 1 LIMIT 1"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_type(statement, 0) == SQLITE_TEXT,
              let text = sqlite3_column_text(statement, 0),
              let value = (try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8))) as? [String: Any],
              let token = value["access"] as? String, !token.isEmpty else { return nil }
        return token
    }

    /// The three allowances the server reports, as percentages of each window.
    static func limits(_ payload: [String: Any], observed: Date) -> AgentLimits? {
        guard let usage = payload["usage"] as? [String: Any] else { return nil }
        let windows: [AgentLimitWindow] = [
            ("rolling", AgentLimitWindow.Kind.session, 300),
            ("weekly", .weekly, 10_080),
            ("monthly", .other, 44_640)].compactMap { key, kind, minutes in
                guard let window = usage[key] as? [String: Any],
                      let percent = window["percent"] as? NSNumber,
                      CFGetTypeID(percent) != CFBooleanGetTypeID(), percent.doubleValue.isFinite else { return nil }
                return AgentLimitWindow(id: key, kind: kind, minutes: minutes, scope: nil,
                                        usedPercent: min(100, max(0, percent.doubleValue)),
                                        resetsAt: AgentLogParser.timestamp(window["resetsAt"]))
            }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .opencode, windows: windows, observedAt: observed, source: .opencodeAccount)
    }
}

/// A cancellable, short-lived request that carries OpenCode's saved token and
/// nothing else; pause or disable cancels it too.
final class AgentOpenCodeRequest {
    private let lock = NSLock()
    private var cancelled = false
    private var task: URLSessionDataTask?

    func cancel() {
        let active = lock.withLock { () -> URLSessionDataTask? in
            cancelled = true
            return task
        }
        active?.cancel()
    }

    func run(home: URL, completion: @escaping (Result<AgentOpenCodeServer.Summary, AgentOpenCodeServer.Failure>) -> Void) {
        guard !lock.withLock({ cancelled }) else { completion(.failure(.unreachable)); return }
        guard FileManager.default.fileExists(atPath: AgentOpenCodeServer.databaseURL(home: home).path) else {
            completion(.failure(.missing)); return
        }
        guard let token = AgentOpenCodeServer.accessToken(home: home) else {
            completion(.failure(.expired)); return
        }
        var request = URLRequest(url: AgentOpenCodeServer.usageURL, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: AgentOpenCodeServer.timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Vorssaint/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let started = lock.withLock { () -> Bool in
            guard !cancelled else { return false }
            task = AgentOpenCodeDownload.start(request, limit: AgentOpenCodeServer.maximumSize) { [weak self] result in
                self?.finish(result, completion)
            }
            return true
        }
        if !started { completion(.failure(.unreachable)) }
    }

    private func finish(_ result: Result<Data, AgentOpenCodeServer.Failure>,
                        _ completion: (Result<AgentOpenCodeServer.Summary, AgentOpenCodeServer.Failure>) -> Void) {
        let accepted = lock.withLock { () -> Bool in
            guard !cancelled else { return false }
            task = nil
            return true
        }
        guard accepted else { return }
        switch result {
        case .failure(let failure): completion(.failure(failure))
        case .success(let data):
            guard let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let limits = AgentOpenCodeServer.limits(payload, observed: Date()) else {
                completion(.failure(.badResponse)); return
            }
            completion(.success(AgentOpenCodeServer.Summary(limits: limits)))
        }
    }
}

/// One bounded request without cookies or cache that follows no redirect off
/// its own host, and tells a refused sign-in from a server that did not answer.
private final class AgentOpenCodeDownload: NSObject, URLSessionDataDelegate {
    private let limit: Int
    private let host: String?
    private var data = Data()
    private var status = 0
    private let completion: (Result<Data, AgentOpenCodeServer.Failure>) -> Void

    private init(limit: Int, host: String?, completion: @escaping (Result<Data, AgentOpenCodeServer.Failure>) -> Void) {
        self.limit = limit
        self.host = host
        self.completion = completion
    }

    static func start(_ request: URLRequest, limit: Int,
                      completion: @escaping (Result<Data, AgentOpenCodeServer.Failure>) -> Void) -> URLSessionDataTask {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = AgentOpenCodeServer.timeout
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let delegate = AgentOpenCodeDownload(limit: limit, host: request.url?.host, completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
        session.finishTasksAndInvalidate()
        return task
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let sameHost = request.url?.scheme == "https" && request.url?.host == host
        completionHandler(sameHost ? request : nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        data.append(chunk)
        if data.count > limit { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if status == 401 { completion(.failure(.expired)); return }
        if data.count > limit { completion(.failure(.badResponse)); return }
        guard error == nil, status == 200 else { completion(.failure(.unreachable)); return }
        completion(.success(data))
    }
}
