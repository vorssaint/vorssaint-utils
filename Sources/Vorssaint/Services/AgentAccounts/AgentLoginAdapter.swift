// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A provider's login could not be read or changed.
enum AgentLoginError: Error, Equatable {
    /// The provider's own tool holds its locks; nothing was touched.
    case busy
    /// Signed in a way that has no plan to swap, such as an API key.
    case unsupported
    /// The text is for logs and support, not for the person.
    case unreadable(String)
}

/// What one provider's login looks like on this Mac. Each implementation
/// takes the home folder it works in, so tests run in a folder of their own.
/// Every call blocks: run them on a work queue.
protocol AgentLoginAdapter {
    var provider: AgentProvider { get }

    /// The login the provider's tool uses right now; nil when signed out.
    /// Throws `.unsupported` for a login without a plan.
    func readLive() throws -> AgentLiveLogin?

    /// Runs `body` holding the locks the provider's tool takes around its own
    /// writes; throws `.busy` when they stay taken. A swap reads, captures and
    /// writes inside one call, so the tool cannot rotate a token in between.
    /// Nothing inside may wait on the network.
    func withLocks<T>(_ body: () throws -> T) throws -> T

    /// Makes `credential` the live login, keeping the Mac's own keys from the
    /// current one. Called inside `withLocks`. A failure part way puts back
    /// what was there before it throws.
    func activate(_ credential: Data, identity: Data) throws

    /// Limits for one saved login, whose copy is `credential`. `rotated` is
    /// the credential to store when it changed: the provider hands out new
    /// tokens on a refresh and the old ones stop working, so it comes back
    /// even beside a failure. May wait on the network for a while.
    func fetchUsage(_ account: AgentAccount, credential: Data,
                    isActive: Bool) -> (limits: Result<AgentLimits, AgentUsageFailure>, rotated: Data?)

    /// How many of the provider's sessions run now and draw on the live login.
    func runningSessions() -> Int
}

/// Files of a login are replaced whole and are never readable by another
/// account on the Mac, not even for the moment between writing and renaming.
enum AgentLoginFiles {
    static func write(_ data: Data, to url: URL) throws {
        // A config kept in a dotfiles folder stays a link to it.
        let target = url.resolvingSymlinksInPath()
        let temporary = target.deletingLastPathComponent()
            .appending(path: ".\(target.lastPathComponent).\(UUID().uuidString)", directoryHint: .notDirectory)
        guard FileManager.default.createFile(atPath: temporary.path, contents: data,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw AgentLoginError.unreadable("\(url.lastPathComponent) could not be written")
        }
        guard rename(temporary.path, target.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw AgentLoginError.unreadable("\(url.lastPathComponent) could not be replaced")
        }
    }
}

/// What a provider answered. `retryAfter` is its `Retry-After` in seconds.
struct AgentHTTPResponse {
    let status: Int
    var retryAfter: TimeInterval?
    let body: Data
}

/// Sends one request and waits for its answer; nil when none came. Tests
/// answer from memory instead.
typealias AgentHTTPTransport = (URLRequest) -> AgentHTTPResponse?

/// One bounded request without cookies or cache that follows no redirect:
/// it carries a login's token, which goes to the host asked and nowhere else.
enum AgentHTTP {
    private static let timeout: TimeInterval = 15
    /// Far above any answer expected here.
    private static let maximumSize = 1 << 20

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("Vorssaint/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func send(_ request: URLRequest) -> AgentHTTPResponse? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let done = DispatchSemaphore(value: 0)
        let answer = Answer()
        session.dataTask(with: request) { data, response, error in
            if error == nil, let response = response as? HTTPURLResponse, let data, data.count <= maximumSize {
                let wait = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                answer.set(AgentHTTPResponse(status: response.statusCode, retryAfter: wait, body: data))
            }
            done.signal()
        }.resume()
        guard done.wait(timeout: .now() + timeout * 2 + 1) == .success else { return nil }
        return answer.value
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    /// The answer, handed from the session's thread to the caller.
    private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var answer: AgentHTTPResponse?
        var value: AgentHTTPResponse? { lock.withLock { answer } }
        func set(_ value: AgentHTTPResponse) { lock.withLock { answer = value } }
    }
}
