// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Music wallpaper: while a song plays, the desktop shows its cover blurred
/// behind time-synced lyrics. The window sits at desktop level, below icons
/// and every app, and disappears when nothing plays so the real wallpaper
/// returns. Lyrics come from the same catalog and matching rules as the
/// island's lyrics page, but this feature keeps its own switch and cache.
final class LyricsWallpaperService: ObservableObject {
    static let shared = LyricsWallpaperService()

    enum State: Equatable { case idle, loading, ready, unavailable }

    @Published private(set) var state: State = .idle
    @Published private(set) var lyrics: NotchLyrics?
    @Published private(set) var offset: Double = 0

    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var track: NotchMusicIdentity?
    private var task: URLSessionDataTask?
    private var searchTask: URLSessionDataTask?
    private var generation = UUID()
    private var running = false
    private var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpAdditionalHeaders = ["User-Agent": "Vorssaint lyrics wallpaper"]
        return URLSession(configuration: configuration)
    }()

    private init() {}

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.lyricsWallpaperEnabled) }

    /// Called once at launch and whenever the switch flips.
    func sync() {
        guard Self.isEnabled else { stop(); return }
        // Lyrics are looked up online, so the first run asks before any song
        // name leaves the Mac. Declining switches the wallpaper off.
        guard UserDefaults.standard.bool(forKey: DefaultsKey.lyricsWallpaperConsentAsked) else {
            DispatchQueue.main.async { [weak self] in self?.askConsent() }
            return
        }
        start()
    }

    private func askConsent() {
        let alert = NSAlert()
        alert.messageText = "Allow the music wallpaper to look up lyrics?"
        alert.informativeText = "While a song plays, Vorssaint shows its cover and synced lyrics on your desktop. "
            + "To find the lyrics it sends the song's title, artist, album and length to lrclib.net and, "
            + "for songs it does not have, the title and artist to music.163.com (NetEase). "
            + "Nothing else is sent, and nothing is recorded. You can turn this off any time in the Wallpaper panel."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Not now")
        NSApp.activate(ignoringOtherApps: true)
        let allowed = alert.runModal() == .alertFirstButtonReturn
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: DefaultsKey.lyricsWallpaperConsentAsked)
        defaults.set(allowed, forKey: DefaultsKey.lyricsWallpaperEnabled)
        sync()
    }

    private func start() {
        guard !running else { return }
        running = true
        let music = NotchMusicService.shared
        music.start()
        LyricsLockScreenService.shared.start()
        music.$playback
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.playbackChanged($0) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildWindows() }
            .store(in: &cancellables)
        playbackChanged(music.playback)
    }

    private func stop() {
        guard running else { return }
        running = false
        LyricsLockScreenService.shared.stop()
        cancellables.removeAll()
        cancelLookup()
        track = nil
        lyrics = nil
        state = .idle
        closeWindows()
    }

    func adjustOffset(by delta: Double) { offset = min(10, max(-10, offset + delta)) }

    // MARK: Playback

    private func playbackChanged(_ playback: NotchPlayback?) {
        guard running else { return }
        guard let playback, playback.track.title?.isEmpty == false else {
            // Nothing playing, or the feed restarting around a lock: the desktop
            // window leaves but the lyrics are kept, so the same song coming back
            // needs no new lookup.
            closeWindows()
            return
        }
        let identity = NotchMusicIdentity(playback)
        showWindows()
        guard identity != track else { return }
        track = identity
        lyrics = nil
        offset = 0
        load(identity)
    }

    // MARK: Lookup

    private func cancelLookup() {
        generation = UUID()
        task?.cancel(); task = nil
        searchTask?.cancel(); searchTask = nil
    }

    private func load(_ identity: NotchMusicIdentity) {
        cancelLookup()
        let mine = generation
        guard let url = NotchLyricsSupport.lookupURL(for: identity) else { state = .unavailable; return }
        state = .loading
        task = session.dataTask(with: url) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let exact = status == 200 ? data.flatMap {
                NotchLyricsSupport.decode($0, for: identity) ?? NotchLyricsSupport.decodeCatalogMatch($0, for: identity)
            } : nil
            DispatchQueue.main.async {
                guard let self, self.generation == mine else { return }
                if let exact { self.finish(exact) } else { self.search(identity, generation: mine, remaining: NotchLyricsSupport.searchURLs(for: identity)) }
            }
        }
        task?.resume()
    }

    /// The exact lookup misses songs whose titles or credits differ between
    /// catalogs, so the search endpoint gets the same bounded matching.
    private func search(_ identity: NotchMusicIdentity, generation mine: UUID, remaining: [URL]) {
        guard let url = remaining.first else {
            Task { [weak self] in
                let result = await LyricsFallbackSources.find(for: identity)
                await MainActor.run {
                    guard let self, self.generation == mine else { return }
                    self.finish(result)
                }
            }
            return
        }
        searchTask = session.dataTask(with: url) { [weak self] data, _, _ in
            let best = data.flatMap {
                NotchLyricsSupport.searchCandidates($0, for: identity)
                    .max { ($0.score, -$0.distance) < ($1.score, -$1.distance) }
            }
            DispatchQueue.main.async {
                guard let self, self.generation == mine else { return }
                if let best { self.finish(best.lyrics) }
                else { self.search(identity, generation: mine, remaining: Array(remaining.dropFirst())) }
            }
        }
        searchTask?.resume()
    }

    private func finish(_ result: NotchLyrics?) {
        lyrics = result
        state = result == nil ? .unavailable : .ready
    }

    // MARK: Windows

    private func showWindows() {
        let screens = NSScreen.screens
        let ids = Set(screens.map(\.displayID))
        for (id, window) in windows where !ids.contains(id) { window.orderOut(nil); windows[id] = nil }
        for screen in screens {
            let id = screen.displayID
            if let window = windows[id] {
                if window.frame != screen.frame { window.setFrame(screen.frame, display: true) }
                continue
            }
            windows[id] = makeWindow(for: screen)
        }
    }

    private func rebuildWindows() {
        guard !windows.isEmpty else { return }
        closeWindows()
        showWindows()
    }

    private func closeWindows() {
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: LyricsWallpaperView(service: self))
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return window
    }
}
