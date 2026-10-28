// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production request and mutation bodies against a suspended transport.
/// No requests reach Spotify and no account files are read or written.
enum NotchSpotifyRequestTests {
    @MainActor final class Session {
        var requests: [URLRequest] = []
        var pending: [CheckedContinuation<(Data, URLResponse), Error>] = []
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }
        func finish(_ status: Int, _ body: String = "") {
            let url = requests[requests.count - pending.count].url!
            pending.removeFirst().resume(returning: (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status,
                                                                                   httpVersion: nil, headerFields: nil)!))
        }
        func fail() { pending.removeFirst().resume(throwing: URLError(.notConnectedToInternet)) }
    }

    @MainActor final class Service {
        enum Connection { case disconnected, connecting, connected, failed }
        var connection: Connection = .connected
        var item: NotchSpotifySupport.Item? = .init(uri: "spotify:track:4uLU6hMCjMI75M1A2tKUQC", name: "Song")
        var saved: Bool? = false
        var busy = false
        var actionFailed = false
        var needsReconnect = false
        var tokens: NotchSpotifySupport.Tokens? = .init(accessToken: "test-access", refreshToken: "test-refresh",
                                                        expiresAt: .distantFuture)
        var accountGeneration = UUID()
        var mutationID: UUID?
        var mutation: Task<Void, Never>?
        var lookup: Task<Void, Never>?
        var lookupSong: Song?
        var matchedSong: Song?
        let session = Session()
        let clientID = "0123456789abcdef0123456789abcdef"
        func stopListener() {}
        enum TokenStore {
            static func save(_ tokens: NotchSpotifySupport.Tokens) {}
            static func delete() {}
        }
        init() {
            let current = NotchSpotifyRequestTests.playback()
            NotchMusicService.shared.playback = current
            lookupSong = Song(current)
            matchedSong = lookupSong
        }
        enum AppFeature { static let notchSpotify = Feature(); struct Feature { var isAvailable = true } }
        enum NotchMusicService {
            static var shared = Player()
            struct Player { var playback: NotchPlayback? = nil }
        }
    }

    static func playback(title: String = "Song", artist: String = "Artist", album: String = "Album",
                         identifier: String? = nil, revision: UUID? = nil) -> NotchPlayback {
        let track = RadialNowPlayingSnapshot(title: title, artist: artist, album: album, artworkData: nil,
                                             appBundleIdentifier: "browser", appPID: 42)
        return NotchPlayback(track: track, isPlaying: true, elapsed: 0, duration: 180, rate: 1,
                             sampledAt: Date(), canSeek: false, itemIdentifier: identifier,
                             commandContext: revision.map { NotchPlaybackContext(pid: 42, revision: $0) })
    }

    @MainActor struct MusicView {
        var service: Service.NotchMusicService.Player
        let spotify: Service
        typealias AppFeature = Service.AppFeature
    }

    static func run(_ suite: TestSuite) {
        var finished = false
        Task { @MainActor in
            await mutations(suite)
            await accessFailures(suite)
            let sameTitle = Service()
            sameTitle.refresh(.init(playback(artist: "Another artist")))
            suite.expect(sameTitle.saved == nil && sameTitle.item == nil,
                         "a different recording with the same title invalidates the previous save target")
            sameTitle.lookup?.cancel()
            let browser = Service()
            browser.item = .init(uri: "spotify:track:4uLU6hMCjMI75M1A2tKUQC", name: "Song")
            browser.saved = nil
            browser.actionFailed = true
            let view = MusicView(service: .init(playback: playback()), spotify: browser)
            suite.expect(view.showsHeart, "a matched browser song retains its warning and retry control")
            finished = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.001)) }
        suite.expect(finished, "Spotify request tests finish without a live network")
    }

    @MainActor static func settle(_ condition: @escaping () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor private static func mutations(_ suite: TestSuite) async {
        let service = Service()
        service.toggleSaved()
        await settle { !service.session.pending.isEmpty }
        suite.expect(service.busy && service.saved == false, "a pending like keeps the last confirmed state")
        suite.expect(service.session.requests.first?.httpMethod == "PUT", "liking sends a save request")
        service.toggleSaved()
        suite.expect(service.session.requests.count == 1, "repeated clicks cannot queue a second mutation")
        service.session.finish(204)
        await settle { !service.busy }
        suite.expect(service.saved == true && !service.actionFailed, "a successful like changes the confirmed state")
        service.toggleSaved()
        await settle { !service.session.pending.isEmpty }
        suite.expect(service.saved == true, "a pending unlike keeps the confirmed like")
        suite.expect(service.session.requests.last?.httpMethod == "DELETE", "unliking sends a remove request")
        service.session.finish(500)
        await settle { !service.busy }
        suite.expect(service.saved == true && service.actionFailed && service.connection == .connected,
                     "a server failure keeps the confirmed like and shows a retryable error")
        try? await Task.sleep(for: .milliseconds(2100))
        suite.expect(service.actionFailed, "a failure remains visible until a retry or new song")
        service.toggleSaved()
        await settle { !service.session.pending.isEmpty }
        service.session.fail()
        await settle { !service.busy }
        suite.expect(service.saved == true && service.actionFailed && service.tokens != nil,
                     "offline failures retain the account and the confirmed like")
        service.toggleSaved()
        await settle { !service.session.pending.isEmpty }
        service.session.finish(204)
        await settle { !service.busy }
        suite.expect(service.saved == false && !service.actionFailed, "a successful retry clears the error")

        let revisionChange = Service()
        revisionChange.toggleSaved()
        await settle { !revisionChange.session.pending.isEmpty }
        revisionChange.refresh(.init(playback(revision: UUID())))
        suite.expect(revisionChange.item == nil && revisionChange.saved == nil && !revisionChange.busy,
                     "a new playback revision retires a pending save even when title and artist match")
        revisionChange.lookup?.cancel()
        revisionChange.session.finish(204)
        for _ in 0..<10 { await Task.yield() }
        suite.expect(revisionChange.saved == nil, "a prior recording's completion cannot restore its heart")

        let stale = Service()
        stale.toggleSaved()
        await settle { !stale.session.pending.isEmpty }
        stale.disconnect()
        stale.session.finish(204)
        await Task.yield()
        suite.expect(stale.saved == nil && !stale.busy && stale.connection == .disconnected,
                     "a reply arriving after disconnect cannot restore state or a spinner")

        let changed = Service()
        changed.toggleSaved()
        await settle { !changed.session.pending.isEmpty }
        changed.refresh(.init(playback(title: "Other song")))
        await settle { changed.session.pending.count == 2 }
        changed.session.finish(204) // Old save completes after the new song starts loading.
        changed.session.finish(200, #"{"item":{"uri":"spotify:track:0123456789abcdefghijkl","name":"Other song","artists":[{"name":"Artist"}],"album":{"name":"Album"}}}"#)
        await settle { !changed.session.pending.isEmpty }
        changed.session.finish(200, "[false]")
        await settle { changed.item?.name == "Other song" }
        suite.expect(changed.saved == false && !changed.busy && !changed.actionFailed,
                     "an old save reply cannot change the next song's saved state")
    }

    @MainActor private static func accessFailures(_ suite: TestSuite) async {
        let denied = Service()
        denied.toggleSaved()
        await settle { !denied.session.pending.isEmpty }
        denied.session.finish(403)
        await settle { !denied.busy }
        suite.expect(denied.needsReconnect && denied.connection == .failed && denied.saved == nil,
                     "forbidden access clears stale saved state and asks to reconnect")

        let browserPlayback = playback()
        suite.expect(denied.offersHeart(for: browserPlayback) && !denied.hasSavedAnswer(for: browserPlayback),
                     "rejected access retains the matched browser's reconnect action without stale saved state")
        suite.expect(!denied.offersHeart(for: playback(artist: "Other artist")),
                     "a different browser recording cannot inherit another song's reconnect action")

        let expired = Service()
        expired.toggleSaved()
        await settle { !expired.session.pending.isEmpty }
        expired.session.finish(401)
        await settle { !expired.session.pending.isEmpty || !expired.busy }
        if !expired.session.pending.isEmpty {
            suite.expect(expired.session.requests.last?.url == NotchSpotifySupport.tokenURL,
                         "an unauthorized request first refreshes the token")
            expired.session.finish(200, #"{"access_token":"renewed","expires_in":3600}"#)
            await settle { !expired.session.pending.isEmpty }
            if !expired.session.pending.isEmpty { expired.session.finish(204) }
        }
        await settle { !expired.busy }
        suite.expect(expired.saved == true && !expired.needsReconnect && expired.session.requests.count == 3,
                     "one token refresh and one retry recover an expired access token")

        let revoked = Service()
        revoked.toggleSaved()
        await settle { !revoked.session.pending.isEmpty }
        revoked.session.finish(401)
        await settle { !revoked.session.pending.isEmpty || !revoked.busy }
        if !revoked.session.pending.isEmpty { revoked.session.finish(400) }
        await settle { !revoked.busy }
        suite.expect(revoked.needsReconnect && revoked.connection == .failed && revoked.saved == nil,
                     "a revoked refresh token ends the connected state")

        let rejected = Service()
        rejected.toggleSaved()
        await settle { !rejected.session.pending.isEmpty }
        rejected.session.finish(401)
        await settle { !rejected.session.pending.isEmpty }
        rejected.session.finish(200, #"{"access_token":"renewed","expires_in":3600}"#)
        await settle { !rejected.session.pending.isEmpty }
        rejected.session.finish(401)
        await settle { !rejected.busy }
        suite.expect(rejected.needsReconnect && rejected.tokens == nil && rejected.session.requests.count == 3,
                     "a second unauthorized response stops retrying and requests reconnection")

        let limited = Service()
        limited.toggleSaved()
        await settle { !limited.session.pending.isEmpty }
        limited.session.finish(429)
        await settle { !limited.busy }
        suite.expect(limited.saved == false && limited.tokens != nil && !limited.needsReconnect && limited.actionFailed,
                     "rate limits preserve the account without pretending a like succeeded")

        let refreshOffline = Service()
        refreshOffline.tokens?.expiresAt = .distantPast
        refreshOffline.toggleSaved()
        await settle { !refreshOffline.session.pending.isEmpty }
        refreshOffline.session.fail()
        await settle { !refreshOffline.busy }
        suite.expect(refreshOffline.tokens != nil && refreshOffline.connection == .connected && refreshOffline.actionFailed,
                     "an offline token refresh is retryable and does not sign out")

        let retired = Service()
        retired.tokens?.expiresAt = .distantPast
        retired.toggleSaved()
        await settle { !retired.session.pending.isEmpty }
        retired.disconnect()
        retired.session.finish(200, #"{"access_token":"late","expires_in":3600}"#)
        for _ in 0..<10 { await Task.yield() }
        suite.expect(retired.tokens == nil && retired.connection == .disconnected && !retired.busy,
                     "a refresh finishing after disconnect cannot restore credentials")
    }
}
