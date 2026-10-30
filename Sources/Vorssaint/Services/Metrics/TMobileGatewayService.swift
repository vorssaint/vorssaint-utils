// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// View-owned, credential-free status reader for a TMO-G4AR on a private LAN.
@MainActor
final class TMobileGatewayService: ObservableObject {
    static let defaultBaseURL = "http://192.168.12.1"

    @Published private(set) var snapshot: TMobileGatewaySnapshot?
    @Published private(set) var phase: TMobileGatewayPhase = .idle

    private let session: URLSession
    private var pollingTask: Task<Void, Never>?
    private var baseURL: URL?
    private var generation = 0
    private var errorStreak = 0

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = nil
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: TMobileGatewaySessionDelegate(),
                             delegateQueue: nil)
    }

    deinit {
        pollingTask?.cancel()
        session.invalidateAndCancel()
    }

    func start(baseURL input: String) {
        guard let validated = TMobileGatewaySupport.privateLANBaseURL(input) else {
            cancel()
            phase = .failed(.invalidAddress)
            return
        }
        if baseURL == validated, pollingTask != nil, !pollingTask!.isCancelled { return }
        cancel()
        baseURL = validated
        launchPolling()
    }

    func refresh() {
        guard baseURL != nil else { return }
        errorStreak = 0
        launchPolling()
    }

    func cancel() {
        generation += 1
        pollingTask?.cancel()
        // Retain the cancelled task as a retirement barrier. A subsequent start
        // waits for its request to finish cancelling before opening another one.
        baseURL = nil
        errorStreak = 0
        snapshot = nil
        phase = .idle
    }

    private func launchPolling() {
        guard let baseURL else { return }
        let previous = pollingTask
        previous?.cancel()
        generation += 1
        let generation = generation
        phase = .loading
        pollingTask = Task { [weak self] in
            if let previous { await previous.value }
            while !Task.isCancelled {
                guard let delay = await self?.poll(baseURL: baseURL, generation: generation) else { return }
                do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                catch { return }
            }
        }
    }

    private func poll(baseURL: URL, generation: Int) async -> TimeInterval? {
        guard generation == self.generation, !Task.isCancelled else { return nil }
        phase = .loading
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/TMI/v1/gateway"
        components.query = "get=all"
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 15)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard generation == self.generation, !Task.isCancelled else { return nil }
            guard let response = response as? HTTPURLResponse else {
                throw TMobileGatewayFailure.invalidResponse
            }
            if response.statusCode == 401 || response.statusCode == 403 {
                throw TMobileGatewayFailure.authenticationRequired
            }
            guard (200...299).contains(response.statusCode) else { throw TMobileGatewayFailure.unavailable }
            snapshot = try TMobileGatewaySupport.parse(data)
            errorStreak = 0
            phase = .ready
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return nil }
            let failure: TMobileGatewayFailure
            if let gatewayFailure = error as? TMobileGatewayFailure { failure = gatewayFailure }
            else if let error = error as? URLError,
                    [.userAuthenticationRequired, .userCancelledAuthentication].contains(error.code) {
                failure = .authenticationRequired
            } else { failure = .unavailable }
            snapshot = nil
            phase = .failed(failure)
            errorStreak = min(errorStreak + 1, 3)
        }
        return TMobileGatewaySupport.pollingDelay(errorStreak: errorStreak)
    }
}

/// Never follow the gateway to another origin or offer saved HTTP credentials.
final class TMobileGatewaySessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
