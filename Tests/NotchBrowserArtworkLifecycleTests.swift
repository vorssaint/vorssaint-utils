// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Runs the production lookup flow with delayed network replies. Browser files,
/// image decoding and the network are replaced; no personal data is read.
enum NotchBrowserArtworkLifecycleTests {
    struct NotchPlayback {
        struct Track {
            let title: String?
            let artist: String? = "Artist"
            let appBundleIdentifier: String? = "app.zen-browser.zen"
        }
        let track: Track
        init(_ title: String) { track = Track(title: title) }
    }

    enum NotchBrowserArtworkSupport {
        struct SessionTab {}
        static var enabled = true
        static var usesCatalog = false
        static func isEnabled() -> Bool { enabled }
        static func lookupKey(for playback: NotchPlayback) -> String? { enabled ? playback.track.title : nil }
        static func artworkURLs(forTrack: String, artist: String?, in tabs: [SessionTab]) -> [URL] {
            usesCatalog ? [] : [URL(string: "https://example.invalid/large.jpg")!,
                                URL(string: "https://example.invalid/small.jpg")!]
        }
        static func asksAppleMusic(tabs: [SessionTab], savedAt: Date, lookupStarted: Date) -> Bool { true }
        static func appleMusicSearchURL(title: String, artist: String?, country: String?) -> URL? {
            URL(string: "https://example.invalid/search")
        }
        static func appleMusicArtworkURL(inSearch: Data, title: String, artist: String?) -> URL? {
            URL(string: "https://example.invalid/album.jpg")
        }
    }

    final class URLSession {
        var cancelled = false
        func invalidateAndCancel() { cancelled = true }
    }

    enum NotchBrowserArtworkDownload {
        struct Request {
            let url: URL
            let session: URLSession
            let completion: (Data?) -> Void
        }
        static var requests: [Request] = []
        @discardableResult
        static func load(_ url: URL, accept: String, completion: @escaping (Data?) -> Void) -> URLSession {
            let session = URLSession()
            requests.append(Request(url: url, session: session, completion: completion))
            return session
        }
    }

    final class Queue {
        var work: [() -> Void] = []
        func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) { work.append(execute) }
        func async(execute: @escaping () -> Void) { work.append(execute) }
        func drain() {
            var remaining = 50
            while !work.isEmpty, remaining > 0 { remaining -= 1; work.removeFirst()() }
        }
    }

    class Fixture {
        static let attemptDelays: [TimeInterval] = [0, 0]
        static let failureCooldown: TimeInterval = 60
        static let rememberedCovers = 8
        let queue = Queue()
        let lock = NSLock()
        var covers: [String: Data] = [:]
        var coverOrder: [String] = []
        var failedAt: [String: Date] = [:]
        var wanted: String?
        var inFlight: String?
        var generation = UUID()
        var downloadSession: URLSession?
        var session: Int?
        func youTubeTabs(bundle: String) -> (modified: Date, tabs: [NotchBrowserArtworkSupport.SessionTab])? {
            (Date(), [NotchBrowserArtworkSupport.SessionTab()])
        }
        static func squareCover(_ data: Data) -> Data? { data }
    }

    static func run(_ suite: TestSuite) {
        let track = NotchPlayback("First")
        let cover = Data("current cover".utf8)
        func fresh(catalog: Bool = false) -> Service {
            NotchBrowserArtworkSupport.enabled = true
            NotchBrowserArtworkSupport.usesCatalog = catalog
            NotchBrowserArtworkDownload.requests = []
            return Service()
        }
        func reply(_ index: Int, _ data: Data?, to service: Service) {
            guard NotchBrowserArtworkDownload.requests.indices.contains(index) else {
                suite.expect(false, "expected artwork request \(index) was started")
                return
            }
            NotchBrowserArtworkDownload.requests[index].completion(data)
            service.queue.drain()
        }
        defer { NotchBrowserArtworkDownload.requests = [] }

        let accepted = fresh()
        var published = 0
        accepted.request(for: track) { published += 1 }
        accepted.queue.drain()
        accepted.request(for: track) { published += 100 }
        accepted.queue.drain()
        suite.expect(NotchBrowserArtworkDownload.requests.count == 1,
                     "repeated readings of the current track share its lookup")
        reply(0, cover, to: accepted)
        suite.expect(published == 1 && accepted.artwork(for: track) == cover,
                     "the current lookup publishes and caches its cover")
        accepted.request(for: track) { published += 100 }
        accepted.queue.drain()
        suite.expect(NotchBrowserArtworkDownload.requests.count == 1 && published == 1,
                     "a cached track does not start another download or publish twice")

        let disabled = fresh()
        disabled.request(for: track) {}
        disabled.queue.drain()
        let active = NotchBrowserArtworkDownload.requests.first?.session
        NotchBrowserArtworkSupport.enabled = false
        disabled.request(for: track) {}
        reply(0, nil, to: disabled)
        suite.expect(active?.cancelled == true && NotchBrowserArtworkDownload.requests.count == 1,
                     "disabling browser covers cancels the download and does not try another thumbnail")

        let cancelled = fresh()
        published = 0
        cancelled.request(for: track) { published += 1 }
        cancelled.queue.drain()
        cancelled.cancel()
        reply(0, cover, to: cancelled)
        suite.expect(published == 0 && cancelled.artwork(for: track) == nil,
                     "a successful reply after the player stops cannot publish or cache a cover")

        let catalog = fresh(catalog: true)
        catalog.request(for: track) {}
        catalog.queue.drain()
        NotchBrowserArtworkSupport.enabled = false
        catalog.request(for: track) {}
        reply(0, Data("catalog result".utf8), to: catalog)
        suite.expect(NotchBrowserArtworkDownload.requests.count == 1,
                     "a catalog reply after disabling covers cannot start its artwork download")

        let resumed = fresh()
        published = 0
        resumed.request(for: track) { published += 100 }
        resumed.queue.drain()
        resumed.cancel()
        resumed.request(for: track) { published += 1 }
        resumed.queue.drain()
        suite.expect(NotchBrowserArtworkDownload.requests.count == 2,
                     "resuming the same track starts a fresh lookup after cancellation")
        reply(0, Data("stale cover".utf8), to: resumed)
        suite.expect(published == 0 && resumed.artwork(for: track) == nil,
                     "an old reply for the same track cannot finish its replacement")
        reply(1, cover, to: resumed)
        suite.expect(published == 1 && resumed.artwork(for: track) == cover,
                     "the replacement lookup still publishes after the stale reply")

        let switched = fresh()
        published = 0
        switched.request(for: track) { published += 100 }
        switched.queue.drain()
        switched.request(for: NotchPlayback("Second")) { published += 100 }
        switched.queue.drain()
        switched.request(for: track) { published += 1 }
        switched.queue.drain()
        suite.expect(NotchBrowserArtworkDownload.requests.count == 3
                     && NotchBrowserArtworkDownload.requests.prefix(2).allSatisfy { $0.session.cancelled },
                     "changing tracks cancels each superseded download, including a return to the first track")
        reply(0, Data("old first cover".utf8), to: switched)
        reply(1, Data("second cover".utf8), to: switched)
        suite.expect(published == 0 && switched.artwork(for: track) == nil,
                     "out-of-order replies from previous tracks cannot publish")
        reply(2, cover, to: switched)
        suite.expect(published == 1 && switched.artwork(for: track) == cover,
                     "the current track survives old replies for both the same and another title")

        let fallback = fresh()
        fallback.request(for: track) {}
        fallback.queue.drain()
        reply(0, nil, to: fallback)
        suite.expect(NotchBrowserArtworkDownload.requests.count == 2,
                     "a failed thumbnail still tries the next size while the lookup is authorized")
        reply(1, cover, to: fallback)
        suite.expect(fallback.artwork(for: track) == cover,
                     "a current fallback cover remains usable")
    }
}

/// Exercises the adapter's production reply closure with its main-thread
/// delivery held back, as when a stop or source change wins the race.
enum NotchMusicArtworkReplyTests {
    typealias NotchMusicService = Service

    enum ImageThumbnailer {
        static func thumbnail(data: Data, pointSize: CGFloat, scale: CGFloat) -> NSImage? { nil }
    }

    enum DispatchQueue {
        static let main = NotchBrowserArtworkLifecycleTests.Queue()
    }

    final class NotchMusicPipeReader {
        let receive: (Data) -> Void
        init(receive: @escaping (Data) -> Void) { self.receive = receive }
    }

    enum NotchBrowserArtwork {
        static let shared = Cache()
        final class Cache {
            func artwork(for playback: NotchPlayback) -> Data? { nil }
        }
    }

    class Fixture {
        var generation = UUID()
        var commandFailed = false
        var acceptsSource = true
        var artworkRequests: [String] = []
        var received = 0
        func receiveValidation(_ reply: [String: Any]) {}
        func receiveQueue(_ reply: [String: Any]) {}
        func acceptsSourceReply(automatic: Bool?, sources: [NotchPlaybackSource]) -> Bool { acceptsSource }
        func requestBrowserArtwork(for playback: NotchPlayback?) {
            artworkRequests.append(playback?.track.title ?? "empty")
        }
        func receive(_ reading: Service.Reading) { received += 1 }
        static func artworkTint(of image: NSImage) -> NotchArtworkTint? { nil }
    }

    static func run(_ suite: TestSuite) {
        let data = Data(#"{"pid":42,"kMRMediaRemoteNowPlayingInfoTitle":"First"}"#.utf8)
        let current = Service()
        let reader = current.makeReader()
        reader.receive(data)
        suite.expect(current.artworkRequests.isEmpty,
                     "an adapter reply waits for main-thread acceptance before starting an artwork lookup")
        DispatchQueue.main.drain()
        suite.expect(current.artworkRequests == ["First"] && current.received == 1,
                     "an accepted current adapter reply still starts its artwork lookup")

        let stopped = Service()
        let oldReader = stopped.makeReader()
        // disconnect() invalidates the adapter's generation before stopping it.
        stopped.generation = UUID()
        oldReader.receive(data)
        DispatchQueue.main.drain()
        suite.expect(stopped.artworkRequests.isEmpty && stopped.received == 0,
                     "a reply still decoding after the player stops cannot restart browser artwork")

        let pending = Service()
        let pendingReader = pending.makeReader()
        pendingReader.receive(data)
        pending.generation = UUID()
        DispatchQueue.main.drain()
        suite.expect(pending.artworkRequests.isEmpty && pending.received == 0,
                     "a stop before main-thread delivery also prevents the queued artwork lookup")

        let rejected = Service()
        rejected.acceptsSource = false
        rejected.makeReader().receive(data)
        DispatchQueue.main.drain()
        suite.expect(rejected.artworkRequests.isEmpty && rejected.received == 0,
                     "an automatic source reply rejected while restoring another player cannot start artwork")
    }
}
