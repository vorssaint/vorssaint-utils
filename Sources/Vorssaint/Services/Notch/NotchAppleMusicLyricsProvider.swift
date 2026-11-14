// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import MusicKit
import Combine
import os

/// Native MusicKit authorization and bounded HTTP requests. No web renderer or
/// JavaScript executes; the system account provides the subscriber token.
final class NotchAppleMusicLyricsProvider: ObservableObject {
    static let shared = NotchAppleMusicLyricsProvider()
    enum Result { case ready(NotchLyrics), signIn, subscription, denied, unavailable, failed }
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "AppleMusicLyrics")
    private var task: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?
    @Published private(set) var requestingAuthorization = false
    private var request = UUID()
    private var developerToken: (value: String, expires: Date)?
    private var subscriberToken: String?
    private var subscriberDeveloperToken: String?
    private let requestSubscriberToken: @MainActor (String) async throws -> String = {
        try await MusicUserTokenProvider().userToken(for: $0, options: [])
    }

    func connect(onClose: @escaping () -> Void) {
        guard NotchLyricsSupport.onlineEnabled(), NotchLyricsProvider.selected() == .appleMusic else { return }
        cancel()
        authorizationTask?.cancel()
        requestingAuthorization = true
        authorizationTask = Task { @MainActor in
            let status = await MusicAuthorization.request()
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(status == .authorized, forKey: DefaultsKey.notchLyricsAppleMusicConnected)
            self.subscriberToken = nil
            self.subscriberDeveloperToken = nil
            self.authorizationTask = nil
            self.requestingAuthorization = false
            onClose()
        }
    }

    func disconnect(onComplete: @escaping () -> Void) {
        close()
        subscriberToken = nil
        subscriberDeveloperToken = nil
        developerToken = nil
        UserDefaults.standard.set(false, forKey: DefaultsKey.notchLyricsAppleMusicConnected)
        onComplete()
    }

    func load(_ track: NotchMusicIdentity, completion: @escaping (Result) -> Void) {
        cancel()
        guard NotchAppleMusicLyricsSupport.canLoad(track),
              !track.title.isEmpty, !track.artist.isEmpty,
              [track.title, track.artist, track.album].allSatisfy({ $0.utf8.count <= 1024 }),
              track.duration.isFinite, (1...3600).contains(track.duration) else { completion(.unavailable); return }
        guard MusicAuthorization.currentStatus == .authorized,
              UserDefaults.standard.bool(forKey: DefaultsKey.notchLyricsAppleMusicConnected) else { completion(.signIn); return }
        let requested = request
        task = Task { @MainActor in
            let result: Result
            do { result = try await self.fetch(track) }
            catch is CancellationError { return }
            catch NativeAppleMusicHTTP.Failure.status(let code) {
                Self.log.error("Native Apple request failed, HTTP=\(code, privacy: .public)")
                result = code == 401 ? .signIn : code == 403 ? .denied : code == 404 ? .unavailable : .failed
            } catch {
                // Do not log exception descriptions, tokens, URLs or account data.
                Self.log.error("Native Apple request failed, code=\((error as NSError).code, privacy: .public)")
                result = .failed
            }
            guard !Task.isCancelled, self.request == requested else { return }
            self.task = nil
            completion(result)
        }
    }

    func cancel() { request = UUID(); task?.cancel(); task = nil }
    func suspend() { cancel() }
    func close() {
        cancel()
        authorizationTask?.cancel()
        authorizationTask = nil
        requestingAuthorization = false
    }

    @MainActor private func fetch(_ track: NotchMusicIdentity) async throws -> Result {
        let developer = try await publicWebDeveloperToken()
        try Task.checkCancellation()
        let user = try await loadSubscriberToken(for: developer)
        try Task.checkCancellation()
        let headers = ["Authorization": "Bearer \(developer)", "Media-User-Token": user,
                       "Origin": "https://music.apple.com", "Referer": "https://music.apple.com/", "Accept": "application/json"]
        func get(_ path: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
            var components = URLComponents(string: "https://amp-api.music.apple.com\(path)")!
            if !query.isEmpty { components.queryItems = query }
            let data = try await NativeAppleMusicHTTP.get(components.url!, headers: headers, maximumBytes: NotchLyricsSupport.maximumBytes)
            try Task.checkCancellation()
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NativeAppleMusicHTTP.Failure.invalid }
            return object
        }
        let account = try await get("/v1/me/account", query: [.init(name: "meta", value: "subscription")])
        guard let subscription = (account["meta"] as? [String: Any])?["subscription"] as? [String: Any],
              subscription["active"] as? Bool == true else { return .subscription }
        guard let storefront = (subscription["storefront"] as? String)?.lowercased(),
              storefront.utf8.count == 2, storefront.utf8.allSatisfy({ (97...122).contains($0) }) else { return .failed }
        let base = "/v1/catalog/\(storefront)"
        var song: [String: Any]?
        if let id = NotchAppleMusicLyricsSupport.validCatalogID(track.catalogIdentifier) {
            let reply = try await get("\(base)/songs/\(id)")
            song = (reply["data"] as? [[String: Any]])?.first { NotchAppleMusicLyricsSupport.matches($0, track: track, searching: false) }
        } else {
            let reply = try await get("\(base)/search", query: [.init(name: "term", value: "\(track.title) \(track.artist)"),
                .init(name: "types", value: "songs"), .init(name: "limit", value: "25")])
            let results = reply["results"] as? [String: Any]
            let songs = results?["songs"] as? [String: Any]
            let candidates = songs?["data"] as? [[String: Any]] ?? []
            let matching = candidates.filter { NotchAppleMusicLyricsSupport.matches($0, track: track, searching: true) }
            if matching.count == 1 { song = matching[0] }
        }
        guard let song, let id = NotchAppleMusicLyricsSupport.validCatalogID(song["id"] as? String),
              (song["attributes"] as? [String: Any])?["hasLyrics"] as? Bool != false else { return .unavailable }
        for endpoint in ["syllable-lyrics", "lyrics"] {
            do {
                let reply = try await get("\(base)/songs/\(id)/\(endpoint)")
                let attributes = (reply["data"] as? [[String: Any]])?.first?["attributes"] as? [String: Any]
                guard let source = attributes?["ttml"] as? String ?? attributes?["lrc"] as? String, !source.isEmpty else { continue }
                guard var lyrics = NotchAppleMusicLyricsSupport.decode(source, duration: track.duration) else { return .failed }
                if lyrics.writers.isEmpty, let composer = (song["attributes"] as? [String: Any])?["composerName"] as? String,
                   !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, composer.utf8.count <= 4096 {
                    lyrics.writers = [composer]
                }
                Self.log.notice("Native lyric response decoded")
                return .ready(lyrics)
            } catch NativeAppleMusicHTTP.Failure.status(404) { continue }
        }
        return .unavailable
    }

    @MainActor private func loadSubscriberToken(for developer: String) async throws -> String {
        try Task.checkCancellation()
        if let cached = subscriberToken, subscriberDeveloperToken == developer { return cached }
        Self.log.notice("Native authorization: requesting subscriber token")
        let user = try await requestSubscriberToken(developer)
        // MusicKit may finish its request after our task is cancelled. A late
        // reply must not refill the cache cleared by Disable Apple Music access.
        try Task.checkCancellation()
        subscriberToken = user
        subscriberDeveloperToken = developer
        return user
    }

    /// The lyric service needs Apple's privileged web developer token, rather
    /// than a normal MusicKit developer token. Discover the current public token
    /// from Apple's public asset, without executing or bundling that JavaScript.
    @MainActor private func publicWebDeveloperToken() async throws -> String {
        if let cached = developerToken, cached.expires.timeIntervalSinceNow > 60 { return cached.value }
        let html = try await NativeAppleMusicHTTP.get(URL(string: "https://music.apple.com/")!, maximumBytes: 8 * 1024 * 1024)
        try Task.checkCancellation()
        guard let page = String(data: html, encoding: .utf8),
              let asset = page.range(of: #"/assets/index~[a-zA-Z0-9]+\.js"#, options: .regularExpression) else { throw NativeAppleMusicHTTP.Failure.invalid }
        let data = try await NativeAppleMusicHTTP.get(URL(string: "https://music.apple.com\(page[asset])")!, maximumBytes: 8 * 1024 * 1024)
        try Task.checkCancellation()
        guard let script = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#) else { throw NativeAppleMusicHTTP.Failure.invalid }
        for match in regex.matches(in: script, range: NSRange(script.startIndex..., in: script)) {
            guard let range = Range(match.range, in: script) else { continue }
            let candidate = String(script[range])
            if let expiration = NotchAppleMusicLyricsSupport.publicTokenExpiration(candidate) {
                developerToken = (candidate, expiration)
                return candidate
            }
        }
        throw NativeAppleMusicHTTP.Failure.invalid
    }
}

private final class NativeAppleMusicHTTP: NSObject, URLSessionTaskDelegate {
    enum Failure: Error { case status(Int), invalid, oversized }
    static func get(_ url: URL, headers: [String: String] = [:], maximumBytes: Int) async throws -> Data {
        try Task.checkCancellation()
        guard url.scheme == "https", ["music.apple.com", "amp-api.music.apple.com"].contains(url.host) else { throw Failure.invalid }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        let delegate = NativeAppleMusicHTTP()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = headers
        request.setValue("Vorssaint", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.invalid }
        guard response.statusCode == 200 else { throw Failure.status(response.statusCode) }
        guard response.expectedContentLength <= maximumBytes else { throw Failure.oversized }
        var result = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard result.count < maximumBytes else { throw Failure.oversized }
            result.append(byte)
        }
        return result
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let sameHost = request.url?.host == response.url?.host && request.url?.scheme == "https"
        completionHandler(sameHost ? request : nil)
    }
}
