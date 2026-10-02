// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production subscription bodies with only scheduling, permission, Apple
/// Event reads and image downloads replaced. No real player is controlled.
enum NotchSpotifyContract {
    typealias State = NotchSpotifyPlayback.State
    enum NotchMusicAutomation {
        struct Target: Equatable { let pid: Int32 }
    }
    final class Scheduler {
        static var main: Scheduler { DispatchQueue.main }
        var jobs: [() -> Void] = []
        var later: [DispatchWorkItem] = []
        func async(execute action: @escaping () -> Void) { jobs.append(action) }
        func asyncAfter(deadline: DispatchTime, execute work: DispatchWorkItem) { later.append(work) }
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }
    enum DispatchQueue { static var main = Scheduler() }
    final class DistributedNotificationCenter {
        static let shared = DistributedNotificationCenter()
        var callbacks: [(Notification) -> Void] = []
        var removals = 0
        static func `default`() -> DistributedNotificationCenter { shared }
        func addObserver(forName: Notification.Name, object: Any?, queue: Scheduler,
                         using callback: @escaping (Notification) -> Void) -> NSObjectProtocol {
            callbacks.append(callback); return NSObject()
        }
        func removeObserver(_ observer: NSObjectProtocol) { removals += 1 }
    }
    final class URLSession { var cancelled = false; func invalidateAndCancel() { cancelled = true } }
    enum NotchSpotifyCoverDownload {
        static var replies: [(Data?) -> Void] = []
        static var sessions: [URLSession] = []
        static func load(_ url: URL, completion: @escaping (Data?) -> Void) -> URLSession {
            replies.append(completion)
            let session = URLSession(); sessions.append(session); return session
        }
    }
}

enum NotchSpotifyPlaybackTests {
    static func run(_ suite: TestSuite) {
        records(suite)
        subscription(suite)
    }

    private static func fixture(_ id: String = "spotify:track:A", position: Double = 12,
                                state: UInt32 = 0x6B505350) -> (NSAppleEventDescriptor, NSAppleEventDescriptor) {
        let track = NSAppleEventDescriptor.record(), app = NSAppleEventDescriptor.record()
        for (key, value): (UInt32, String) in [(0x49442020, id), (0x706E616D, "Song " + id),
                                             (0x70417274, "Artist"), (0x70416C62, "Album"),
                                             (0x6155726C, "https://i.scdn.co/image/" + id.suffix(1))] {
            track.setDescriptor(NSAppleEventDescriptor(string: value), forKeyword: key)
        }
        track.setDescriptor(NSAppleEventDescriptor(int32: 214910), forKeyword: 0x70447572)
        app.setDescriptor(NSAppleEventDescriptor(double: position), forKeyword: 0x70506F73)
        app.setDescriptor(NSAppleEventDescriptor(enumCode: state), forKeyword: 0x70506C53)
        return (track, app)
    }

    private static func records(_ suite: TestSuite) {
        typealias State = NotchSpotifyPlayback.State
        let (track, app) = fixture()
        let state = State.decode(track: track, application: app)!
        let revision = UUID(), now = Date(timeIntervalSinceReferenceDate: 100)
        let playback = state.playback(pid: 42, revision: revision, artwork: Data([1, 2]), now: now)
        suite.expect(playback.duration == 214.91 && playback.position(at: now.addingTimeInterval(3)) == 15,
                     "Spotify's millisecond track duration and second position produce a synchronized timeline")
        suite.expect(playback.track.artworkData == Data([1, 2]) && playback.commandContext == .init(pid: 42, revision: revision)
                     && !playback.canSendCommandsDirectly,
                     "authoritative metadata, cover and commands describe the same Spotify process and recording")
        let paused = fixture(position: 78.506, state: 0x6B505370)
        suite.expect(State.decode(track: paused.0, application: paused.1)?.playback(pid: 42, revision: revision, artwork: nil, now: now)
            .position(at: now.addingTimeInterval(30)) == 78.506,
                     "a paused Spotify does not advance its preview despite missing native playback rate")
        for (position, playerState) in [(Double.nan, UInt32(0x6B505350)), (-1, 0x6B505350), (10, 0)] {
            let malformed = fixture(position: position, state: playerState)
            suite.expect(State.decode(track: malformed.0, application: malformed.1) == nil,
                         "malformed Spotify timing or state cannot become authoritative playback")
        }
        suite.expect(State.decode(track: .record(), application: app) == nil,
                     "a missing track does not fabricate a recording or valid command context")
        let noCover = NSAppleEventDescriptor.record()
        for key: UInt32 in [0x49442020, 0x706E616D, 0x70447572] { noCover.setDescriptor(track.forKeyword(key)!, forKeyword: key) }
        suite.expect(State.decode(track: noCover, application: app)?.title == state.title,
                     "a local track without artist, album or cover remains synchronized and controllable")
        for bundle in ["com.spotify.client", "com.apple.Music"] {
            let reply: [String: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": "Song", "pid": 42, "displayID": bundle]
            let data = try! JSONSerialization.data(withJSONObject: reply)
            suite.expect(NotchPlayback.decode(data, canSendCommandsDirectly: true)?.canSendCommandsDirectly == (bundle != "com.spotify.client"),
                         "Spotify uses its process-bound Automation path while native Apple Music control is preserved")
        }
        for id in ["spotify:track:A", "spotify:track:B"] {
            let read = State.read { property, isTrack in
                if property == 0x49442020 { return NSAppleEventDescriptor(string: id) }
                return isTrack ? track : app
            }
            suite.expect((read != nil) == (id == "spotify:track:A"),
                         "a track change between property reads rejects a mixed snapshot while stable input succeeds")
        }
        let nativeReply: [String: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": "New song", "pid": 42,
                                            "displayID": "com.spotify.client", "artworkBase64": "AQID"]
        let native = NotchPlayback.decode(try! JSONSerialization.data(withJSONObject: nativeReply))
        suite.expect(native?.track.artworkData == nil,
                     "Spotify's stale native artwork cannot be displayed with a new title")
        var cache = NotchArtworkCache<String>()
        cache.update("A", for: state.playback(pid: 42, revision: revision, artwork: Data([1])))
        let nextRecord = fixture("spotify:track:B")
        let nextSong = State.decode(track: nextRecord.0, application: nextRecord.1)!
        cache.update(nil, for: nextSong.playback(pid: 42, revision: UUID(), artwork: nil))
        suite.expect(cache.artwork == nil && cache.expiresAt == nil,
                     "a verified Spotify cover never flashes on a different recording while its cover loads")
        suite.expect(State.coverURL("https://i.scdn.co/image/abc") != nil,
                     "Spotify's reported CDN image is accepted without a catalog search")
        for url in ["http://i.scdn.co/image/abc", "https://example.com/image/abc", "https://i.scdn.co.evil/image/abc",
                    "https://user@i.scdn.co/image/abc", "https://i.scdn.co/image/abc?track=private", "file:///image/abc"] {
            suite.expect(State.coverURL(url) == nil, "foreign or credential-bearing artwork addresses are rejected")
        }
    }

    private static func subscription(_ suite: TestSuite) {
        typealias Contract = NotchSpotifyContract
        typealias Reader = Contract.Reader
        Contract.DispatchQueue.main = Contract.Scheduler()
        Contract.NotchSpotifyCoverDownload.replies = []; Contract.NotchSpotifyCoverDownload.sessions = []
        Contract.DistributedNotificationCenter.shared.callbacks = []
        Contract.DistributedNotificationCenter.shared.removals = 0
        func state(_ id: String, position: Double = 12) -> Contract.State {
            let records = fixture(id, position: position)
            return Contract.State.decode(track: records.0, application: records.1)!
        }
        Reader.next = state("spotify:track:A")
        var received: [NotchPlayback?] = []
        let reader = Reader(target: .init(pid: 42)) { received.append($0) }
        func land() { reader.queue.drain(); Contract.DispatchQueue.main.drain() }
        land()
        let first = reader.playback!
        suite.expect(first.itemIdentifier == "spotify:track:A" && Contract.DispatchQueue.main.later.count == 1,
                     "the subscription reads immediately and leaves one bounded backstop")
        Reader.next = state("spotify:track:A", position: 80)
        for _ in 0..<30 { reader.refresh() }
        suite.expect(reader.queue.jobs.count == 1, "bursts coalesce instead of building a backlog of Spotify reads")
        land(); land()
        suite.expect(reader.playback?.elapsed == 80 && reader.playback?.commandContext == first.commandContext,
                     "a seek replaces the displayed position without changing the recording revision")
        Reader.next = state("spotify:track:B")
        reader.refresh(); land()
        let second = reader.playback!
        suite.expect(second.commandContext != first.commandContext && second.track.artworkData == nil,
                     "the next song gets a new command revision and does not inherit the previous album cover")
        Contract.NotchSpotifyCoverDownload.replies[0](Data([1]))
        Contract.DispatchQueue.main.drain()
        suite.expect(reader.playback?.track.artworkData == nil && Contract.NotchSpotifyCoverDownload.sessions[0].cancelled,
                     "a late previous-song cover is cancelled and cannot overwrite the next track")
        Contract.NotchSpotifyCoverDownload.replies[1](Data([2]))
        Contract.DispatchQueue.main.drain()
        suite.expect(reader.playback?.track.artworkData == Data([2]) && reader.playback?.sampledAt == second.sampledAt,
                     "a downloaded cover updates the same recording without resetting its position clock")
        var valid: Bool?
        reader.validate(first.commandContext!) { valid = $0 }
        suite.expect(valid == false, "controls rendered for the previous song are rejected before queuing a read")
        Reader.next = state("spotify:track:C")
        reader.validate(second.commandContext!) { valid = $0 }; land()
        suite.expect(valid == false, "a player advancing before its notification cannot accept an old track's command")
        Reader.next = state("spotify:track:B")
        reader.validate(second.commandContext!) { valid = $0 }; land()
        suite.expect(valid == true, "a still-current recording remains controllable through the fresh Spotify check")
        let sameAlbum = state("spotify:track:C")
        Reader.next = Contract.State(identifier: sameAlbum.identifier, title: sameAlbum.title, artist: sameAlbum.artist,
                                     album: sameAlbum.album, duration: sameAlbum.duration, position: 1, playing: true,
                                     artworkURL: Reader.next!.artworkURL)
        reader.refresh(); land()
        suite.expect(reader.playback?.itemIdentifier == sameAlbum.identifier && reader.playback?.track.artworkData == Data([2])
                     && Contract.NotchSpotifyCoverDownload.replies.count == 2,
                     "another song reporting the same album image reuses its cover without another network request")
        Reader.next = state("spotify:track:D")
        reader.refresh(); land()
        Contract.NotchSpotifyCoverDownload.replies[2](nil); Contract.DispatchQueue.main.drain()
        reader.refresh(); land()
        suite.expect(Contract.NotchSpotifyCoverDownload.replies.count == 3,
                     "a failed image download is throttled instead of retried on every position update")
        reader.nextCoverAttemptAt = 0
        reader.refresh(); land()
        suite.expect(Contract.NotchSpotifyCoverDownload.replies.count == 4,
                     "the still-selected track retries its missing cover after the throttle expires")
        Reader.next = nil
        reader.refresh(); land()
        Contract.NotchSpotifyCoverDownload.replies[3](Data([3])); Contract.DispatchQueue.main.drain()
        suite.expect(reader.playback == nil && received.last! == nil,
                     "a denied permission or failed read withdraws authority instead of retaining stale controls")
        Reader.next = state("spotify:track:D")
        reader.refresh(); land()
        suite.expect(Contract.NotchSpotifyCoverDownload.replies.count == 4 && reader.playback?.track.artworkData == Data([3]),
                     "a cover completing during a rejected snapshot is reused when the same recording recovers")
        Reader.next = state("spotify:track:E")
        reader.refresh(); land()
        Reader.next = nil
        reader.refresh(); land()
        Reader.next = state("spotify:track:E")
        reader.refresh(); land()
        suite.expect(Contract.NotchSpotifyCoverDownload.replies.count == 5 && !Contract.NotchSpotifyCoverDownload.sessions[4].cancelled,
                     "a transient read failure does not cancel and restart the same recording's cover download")
        let count = received.count
        reader.refresh(); reader.stop(); land()
        for work in Contract.DispatchQueue.main.later { work.perform() }
        Contract.DistributedNotificationCenter.shared.callbacks.first?(Notification(name: .init("test")))
        land()
        suite.expect(received.count == count && reader.queue.jobs.isEmpty && Contract.DistributedNotificationCenter.shared.removals == 1,
                     "stopping the consumer cancels polling, notifications and queued or late results")
    }
}
