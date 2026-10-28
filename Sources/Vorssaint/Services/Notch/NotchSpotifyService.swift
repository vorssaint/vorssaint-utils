// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Network

/// Connects a Spotify account so the island can show whether the playing
/// song is in Liked Songs and change that. Sign-in uses PKCE through the
/// default browser and a one-shot listener on the loopback address. Tokens
/// sit in an owner-only file in the app's container, never in a settings
/// backup and never in the Keychain, which would ask for access whenever a
/// rebuilt app no longer matched the one that saved them.
@MainActor
final class NotchSpotifyService: ObservableObject {
    static let shared = NotchSpotifyService()

    enum Connection: Equatable { case disconnected, connecting, connected, failed }
    @Published private(set) var connection: Connection = .disconnected
    /// The song Spotify reports, once it matches the island's recording.
    @Published private(set) var item: NotchSpotifySupport.Item?
    @Published private(set) var saved: Bool?
    @Published private(set) var busy = false
    @Published private(set) var actionFailed = false
    @Published private(set) var needsReconnect = false

    private var tokens: NotchSpotifySupport.Tokens?
    private var listener: NWListener?
    private var lookup: Task<Void, Never>?
    @Published private(set) var matchedSong: Song?
    private var lookupSong: Song?
    private var accountGeneration = UUID()
    private var mutationID: UUID?
    private var mutation: Task<Void, Never>?
    private var signInTimeout: Task<Void, Never>?
    private var playbackObserver: AnyCancellable?
    private let session: URLSession

    private init() {
        // Nothing from these calls belongs on disk: no cache and no cookies.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
        tokens = TokenStore.load()
        connection = tokens == nil ? .disconnected : .connected
    }

    var clientID: String {
        (UserDefaults.standard.string(forKey: DefaultsKey.notchSpotifyClientID) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Sign-in

    func connect() {
        guard connection != .connecting, AppFeature.notchSpotify.isAvailable else { return }
        let clientID = clientID
        guard NotchSpotifySupport.validClientID(clientID) else { connection = .failed; return }
        invalidateRequests()
        needsReconnect = false
        actionFailed = false
        let verifier = NotchSpotifySupport.randomToken()
        let state = NotchSpotifySupport.randomToken(bytes: 16)
        guard let url = NotchSpotifySupport.authorizationURL(clientID: clientID, verifier: verifier, state: state),
              startListener(clientID: clientID, verifier: verifier, state: state) else { connection = .failed; return }
        connection = .connecting
        NSWorkspace.shared.open(url)
        // An abandoned sign-in frees the port again.
        signInTimeout?.cancel()
        signInTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard let self, !Task.isCancelled, self.connection == .connecting else { return }
            self.stopListener()
            self.connection = self.tokens == nil ? .failed : .connected
        }
    }

    /// Follows the island's song from launch, while the island is still
    /// closed, so the heart is ready with everything else when it opens.
    func syncWithPreferences() {
        guard AppFeature.notchSpotify.isAvailable else { stop(); return }
        guard playbackObserver == nil else { return }
        playbackObserver = NotchMusicService.shared.$playback
            .map { Song($0) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] song in MainActor.assumeIsolated { self?.refresh(song) } }
    }

    struct Song: Equatable {
        let recording: NotchMusicIdentity?
        let context: NotchPlaybackContext?

        init(_ playback: NotchPlayback?) {
            recording = playback.map(NotchMusicIdentity.init)
            context = playback?.commandContext
        }

        var title: String? { recording?.title }
        var bundleIdentifier: String? { recording?.bundle }

        func matches(_ item: NotchSpotifySupport.Item) -> Bool {
            guard let recording else { return false }
            return NotchSpotifySupport.matches(title: recording.title, artist: recording.artist,
                                               album: recording.album, identifier: recording.itemIdentifier, item: item)
        }
    }

    func offersHeart(for playback: NotchPlayback?) -> Bool {
        guard AppFeature.notchSpotify.isAvailable, let playback else { return false }
        return playback.track.appBundleIdentifier == NotchSpotifySupport.bundleIdentifier
            || matchedSong == Song(playback)
    }

    func hasSavedAnswer(for playback: NotchPlayback?) -> Bool {
        playback != nil && saved != nil && item != nil && matchedSong == Song(playback)
    }

    /// Turning the feature off ends any sign-in and lookup but keeps the
    /// account, so turning it back on needs no new sign-in.
    func stop() {
        playbackObserver?.cancel()
        playbackObserver = nil
        if connection == .connecting { connection = tokens == nil ? .disconnected : .connected }
        stopListener()
        invalidateRequests()
        actionFailed = false
    }

    func disconnect() {
        stopListener()
        invalidateRequests()
        tokens = nil
        TokenStore.delete()
        needsReconnect = false
        actionFailed = false
        connection = .disconnected
    }

    private func cancelMutation() {
        mutationID = nil
        mutation?.cancel()
        mutation = nil
        busy = false
    }

    private func invalidateRequests() {
        accountGeneration = UUID()
        lookup?.cancel()
        lookup = nil
        lookupSong = nil
        matchedSong = nil
        cancelMutation()
        item = nil
        saved = nil
    }

    private func accessLost() {
        let previousMatch = matchedSong
        disconnect()
        matchedSong = previousMatch
        needsReconnect = true
        actionFailed = true
        connection = .failed
    }

    private func startListener(clientID: String, verifier: String, state: String) -> Bool {
        stopListener()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: NotchSpotifySupport.callbackPort)!)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else { return false }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let callback = NotchSpotifySupport.callback(fromRequest: request, expectedState: state)
                let response = NotchSpotifySupport.callbackResponse(
                    page: callback == .invalid ? nil : FeatureStrings.notchSpotify(L10n.shared.language).signedIn)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                Task { @MainActor [weak self] in
                    guard let self, self.connection == .connecting else { return }
                    switch callback {
                    case .invalid: return // A favicon or a stray request; keep waiting.
                    case .denied: self.stopListener(); self.connection = self.tokens == nil ? .failed : .connected
                    case .code(let code):
                        self.stopListener()
                        await self.exchange(code: code, clientID: clientID, verifier: verifier)
                    }
                }
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard case .failed = state else { return }
            Task { @MainActor [weak self] in
                guard let self, self.connection == .connecting else { return }
                self.stopListener()
                self.connection = .failed
            }
        }
        listener.start(queue: .main)
        self.listener = listener
        return true
    }

    private func stopListener() {
        signInTimeout?.cancel()
        listener?.cancel()
        listener = nil
    }

    private func exchange(code: String, clientID: String, verifier: String) async {
        let body = NotchSpotifySupport.formBody([("grant_type", "authorization_code"), ("code", code),
                                                 ("redirect_uri", NotchSpotifySupport.redirectURI),
                                                 ("client_id", clientID), ("code_verifier", verifier)])
        let generation = accountGeneration
        let reply = await tokenRequest(body)
        guard generation == accountGeneration, !Task.isCancelled else { return }
        guard let (data, status) = reply, status == 200,
              let tokens = NotchSpotifySupport.tokens(from: data) else {
            connection = .failed; return
        }
        store(tokens)
        needsReconnect = false
        actionFailed = false
        connection = .connected
        reload()
    }

    private func tokenRequest(_ body: Data) async -> (Data, Int)? {
        var request = URLRequest(url: NotchSpotifySupport.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        return (data, status)
    }

    private func store(_ tokens: NotchSpotifySupport.Tokens) {
        self.tokens = tokens
        TokenStore.save(tokens)
    }

    /// A fresh access token, refreshed when it is about to expire. Only a
    /// refresh Spotify refuses, as when access was removed from the account,
    /// signs out; being offline keeps the account for the next try.
    private func accessToken() async -> String? {
        guard let tokens else { return nil }
        if tokens.isFresh() { return tokens.accessToken }
        let body = NotchSpotifySupport.formBody([("grant_type", "refresh_token"), ("refresh_token", tokens.refreshToken),
                                                 ("client_id", clientID)])
        let generation = accountGeneration
        let reply = await tokenRequest(body)
        guard generation == accountGeneration, !Task.isCancelled else { return nil }
        guard let (data, status) = reply else { actionFailed = true; return nil }
        guard status == 200, let renewed = NotchSpotifySupport.tokens(from: data, previousRefreshToken: tokens.refreshToken) else {
            if NotchSpotifySupport.refreshRevoked(status: status) { accessLost() }
            else { actionFailed = true }
            return nil
        }
        store(renewed)
        return renewed.accessToken
    }

    // MARK: Liked Songs

    /// Finds the song Spotify is playing and whether it is saved. Spotify
    /// can trail the island by a moment after a skip, so a different name
    /// from Spotify's own app is tried again before the heart gives up on
    /// it. Another player's song is asked about once, for the web player.
    private func refresh(_ song: Song, force: Bool = false) {
        let title = song.title
        guard connection == .connected, AppFeature.notchSpotify.isAvailable else { return }
        guard force || song != lookupSong else { return }
        if matchedSong != song {
            cancelMutation()
            item = nil
            saved = nil
            matchedSong = nil
        } else if busy { return }
        actionFailed = false
        lookupSong = song
        lookup?.cancel()
        guard title != nil else { return }
        lookup = Task { [weak self] in
            let attempts = song.bundleIdentifier == NotchSpotifySupport.bundleIdentifier ? 3 : 1
            for attempt in 0..<attempts {
                if attempt > 0 { try? await Task.sleep(for: .seconds(1.5)) }
                guard let self, !Task.isCancelled else { return }
                guard let current = await self.currentItem() else { continue }
                guard !Task.isCancelled, song.matches(current) else { continue }
                self.matchedSong = song
                let saved = await self.contains(current.uri)
                guard !Task.isCancelled else { return }
                self.item = current
                self.saved = saved
                self.actionFailed = saved == nil
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.item = nil
            self.saved = nil
        }
    }

    /// Asks again for the same song, as when the island opens: the song may
    /// have been liked on another device. The heart keeps its last answer
    /// on screen until the new one lands.
    func reload() {
        guard !busy else { return }
        refresh(Song(NotchMusicService.shared.playback), force: true)
    }

    func toggleSaved() {
        guard connection == .connected, AppFeature.notchSpotify.isAvailable,
              let item, let saved, !busy,
              matchedSong == Song(NotchMusicService.shared.playback) else { return }
        lookup?.cancel()
        busy = true
        actionFailed = false
        let wanted = !saved
        let requestID = UUID()
        let generation = accountGeneration
        mutationID = requestID
        mutation = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.mutationID == requestID {
                    self.busy = false
                    self.mutationID = nil
                    self.mutation = nil
                }
            }
            let done = await self.send(wanted ? "PUT" : "DELETE", uri: item.uri)
            guard !Task.isCancelled, self.accountGeneration == generation,
                  self.mutationID == requestID, self.item == item else { return }
            // Only Spotify's successful response confirms a change. A failed
            // request keeps the last known state and a persistent retry hint.
            if done { self.saved = wanted }
            self.actionFailed = !done
        }
    }

    private func currentItem() async -> NotchSpotifySupport.Item? {
        guard var components = URLComponents(url: NotchSpotifySupport.apiBase.appendingPathComponent("me/player/currently-playing"),
                                             resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "additional_types", value: "track,episode")]
        guard let url = components.url, let (data, status) = await api("GET", url: url), status == 200 else { return nil }
        return NotchSpotifySupport.currentItem(from: data)
    }

    private func contains(_ uri: String) async -> Bool? {
        guard let url = NotchSpotifySupport.libraryURL("me/library/contains", uri: uri),
              let (data, status) = await api("GET", url: url), status == 200 else { return nil }
        return NotchSpotifySupport.saved(from: data)
    }

    private func send(_ method: String, uri: String) async -> Bool {
        guard let url = NotchSpotifySupport.libraryURL("me/library", uri: uri),
              let (_, status) = await api(method, url: url) else { return false }
        return (200..<300).contains(status)
    }

    private func api(_ method: String, url: URL) async -> (Data, Int)? {
        let generation = accountGeneration
        guard var token = await accessToken(), generation == accountGeneration, !Task.isCancelled else { return nil }
        // A 401 may just be an expired token. Refresh and retry once; a second
        // 401 or a 403 requires the person to restore access and reconnect.
        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let reply = try? await session.data(for: request)
            guard generation == accountGeneration, !Task.isCancelled else { return nil }
            guard let (data, response) = reply,
                  let status = (response as? HTTPURLResponse)?.statusCode else {
                actionFailed = true
                return nil
            }
            if status == 401, attempt == 0 {
                tokens?.expiresAt = .distantPast
                guard let renewed = await accessToken(), generation == accountGeneration, !Task.isCancelled else { return nil }
                token = renewed
                continue
            }
            if status == 401 || status == 403 {
                accessLost()
                return nil
            }
            if status >= 400 { actionFailed = true }
            return (data, status)
        }
        return nil
    }

    // MARK: Storage

    private enum TokenStore {
        static var file: URL? {
            PrivateFileStore.containerURL?.appendingPathComponent("Spotify", isDirectory: true)
                .appendingPathComponent("account.json")
        }

        static func load() -> NotchSpotifySupport.Tokens? {
            guard let file, let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode(NotchSpotifySupport.Tokens.self, from: data)
        }

        static func save(_ tokens: NotchSpotifySupport.Tokens) {
            guard let file, PrivateFileStore.createDirectory(at: file.deletingLastPathComponent()),
                  let data = try? JSONEncoder().encode(tokens) else { return }
            _ = PrivateFileStore.write(data, to: file)
        }

        static func delete() {
            guard let file else { return }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
