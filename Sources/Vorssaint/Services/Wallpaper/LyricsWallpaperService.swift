// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.pwr_mgt
import SwiftUI

/// Music wallpaper: while a song plays, the desktop shows its cover in full
/// quality behind time-synced lyrics. The window sits at desktop level, below
/// icons and every app, and disappears when nothing plays so the real
/// wallpaper returns. Lyrics, their matching and their timing offset come from
/// Vorssaint's own lyrics finder (the one behind the island's lyrics page);
/// only songs it cannot find go on to the extra catalogs for regional music.
final class LyricsWallpaperService: ObservableObject {
    static let shared = LyricsWallpaperService()

    enum State: Equatable { case idle, loading, ready, unavailable }

    private let finder = NotchLyricsService.shared
    /// Lyrics from the extra catalogs, for the song named by `track` only.
    @Published private var extra: NotchLyrics?
    @Published private(set) var cover: NSImage?
    /// Changes with each new cover, so views can cross-fade between them.
    @Published private(set) var coverID = 0
    /// The cover's dominant colours, most prominent first.
    @Published private(set) var palette: [Color] = []

    var lyrics: NotchLyrics? { finder.lyrics ?? extra }
    var offset: Double { finder.offset }
    var state: State {
        if lyrics != nil { return .ready }
        switch finder.state {
        case .loading: return .loading
        case .unavailable, .failed: return extraLookup == nil ? .unavailable : .loading
        default: return .idle
        }
    }

    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var track: NotchMusicIdentity?
    private var coverSource: Data?
    private var extraLookup: Task<Void, Never>?
    private var hideWork: DispatchWorkItem?
    private var running = false
    private var awakeAssertion = IOPMAssertionID(0)

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

    /// The island's button and the panel's switch both land here: the windows
    /// close in the same turn, with no wait for a song or a lookup.
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.lyricsWallpaperEnabled)
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
        // The finder publishes when lyrics arrive or the offset moves.
        finder.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.finderChanged() }
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
        hideWork?.cancel(); hideWork = nil
        extraLookup?.cancel(); extraLookup = nil
        track = nil
        extra = nil
        cover = nil
        palette = []
        coverSource = nil
        setAwake(false)
        closeWindows()
        objectWillChange.send()
    }

    func adjustOffset(by delta: Double) { finder.adjustOffset(by: delta) }
    func resetOffset() { finder.resetOffset() }

    // MARK: Playback

    private func playbackChanged(_ playback: NotchPlayback?) {
        guard running else { return }
        guard let playback, playback.track.title?.isEmpty == false else {
            // A player between songs, or the feed restarting around a lock, reports
            // nothing for a moment. The windows stay up through that so nothing
            // flashes, and leave only if the silence lasts.
            guard hideWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in self?.hideWork = nil; self?.setAwake(false); self?.closeWindows() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
            return
        }
        hideWork?.cancel()
        hideWork = nil
        showWindows()
        setAwake(playback.isPlaying)
        updateCover(from: playback.track.artworkData)

        let identity = NotchMusicIdentity(playback)
        // Vorssaint's finder does the matching, caching and offset memory.
        finder.update(playback: playback, visible: true)
        guard identity != track else { return }
        track = identity
        extra = nil
        extraLookup?.cancel(); extraLookup = nil
    }

    private func finderChanged() {
        objectWillChange.send()
        // Not in its catalog: try the extra ones once for this song.
        guard finder.lyrics == nil, extra == nil, extraLookup == nil, let identity = track,
              finder.state == .unavailable || finder.state == .failed else { return }
        extraLookup = Task { [weak self] in
            let found = await LyricsFallbackSources.find(for: identity)
            await MainActor.run {
                guard let self, self.track == identity else { return }
                self.extra = found
                self.extraLookup = nil
            }
        }
    }

    /// The cover at full quality, decoded once per image off the main thread:
    /// the island's own copy is a small thumbnail and looks soft across a
    /// whole display.
    private func updateCover(from data: Data?) {
        guard data != coverSource else { return }
        coverSource = data
        guard let data else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = ImageThumbnailer.thumbnail(data: data, pointSize: 1600, scale: 2)
            let colors = ArtworkPalette.colors(from: data).map { Color(nsColor: $0) }
            DispatchQueue.main.async {
                guard let self, self.coverSource == data, let image else { return }
                self.cover = image
                self.palette = colors
                self.coverID += 1
            }
        }
    }

    // MARK: Keep awake

    /// While a song plays and the lyrics are up, the display stays on, on the
    /// desktop and the lock screen alike. It is the same assertion Keep Awake
    /// takes, held on its own so it never touches a session of the person's.
    func refreshAwake() { setAwake(NotchMusicService.shared.playback?.isPlaying == true) }

    private func setAwake(_ playing: Bool) {
        let wanted = running && playing && UserDefaults.standard.bool(forKey: DefaultsKey.lyricsKeepAwake)
        if wanted, awakeAssertion == 0 {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "Vorssaint lyrics wallpaper" as CFString, &id) == kIOReturnSuccess {
                awakeAssertion = id
            }
        } else if !wanted, awakeAssertion != 0 {
            IOPMAssertionRelease(awakeAssertion)
            awakeAssertion = 0
        }
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
        window.animationBehavior = .none
        window.contentView = NSHostingView(rootView: LyricsWallpaperView(service: self))
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return window
    }
}
