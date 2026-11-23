// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.pwr_mgt
import SwiftUI

/// Music on the desktop, as two switches. The song wallpaper shows the cover
/// in full quality across the desktop; Show lyrics puts time-synced lyrics on
/// top of it, or, with the song wallpaper off, over the normal wallpaper. The
/// window sits at desktop level, below icons and every app, and disappears
/// when nothing plays so the real wallpaper returns. Lyrics, their matching and their timing offset come from
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
    /// The cover a new one fades in over, so a change of song never shows black between them.
    @Published private(set) var previousCover: NSImage?
    /// The cover fills the desktop. Off, the window is clear and only the lyrics show.
    @Published private(set) var songWallpaper = false
    /// The synced lyrics, over the cover or over the normal wallpaper.
    @Published private(set) var showLyrics = false
    /// Spotify's reading, the only player the desktop follows; nil while anything else plays.
    @Published private(set) var playback: NotchPlayback?
    /// Some part of the desktop windows can be seen. Covered by apps, the animations stop.
    @Published private(set) var onScreen = true
    private var occlusionObservers: [NSObjectProtocol] = []

    var lyrics: NotchLyrics? { finder.lyrics ?? extra }
    /// How far ahead of the player's clock the words are shown. Lyrics read as
    /// late far more readily than early, and Bluetooth output adds a lag the
    /// player's clock never sees, so the display leads a little.
    static let lead = 0.25
    /// The person's own timing for this song, as the island's lyrics page keeps it.
    var userOffset: Double { finder.offset }
    /// The offset every lyrics view applies: the person's, less the lead.
    var offset: Double { finder.offset - Self.lead }
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
    /// The song the cover on show belongs to; a new song's cover cross-fades, the same song's just replaces it.
    private var coverTrack: NotchMusicIdentity?
    /// The windows wait unseen for the first cover, so the desktop never flashes black while it decodes.
    private var revealed = false
    private var revealWork: DispatchWorkItem?
    private var extraLookup: Task<Void, Never>?
    private var hideWork: DispatchWorkItem?
    /// How long music may stay paused before the wallpaper goes, so a still screen is not kept animating for nothing.
    private static let idleLimit: TimeInterval = 120
    private var idleWork: DispatchWorkItem?
    private var idleHidden = false
    /// When the music last stopped moving. Kept through dropouts in the player's
    /// feed and rebuilt windows, so a pause is timed from when it really began.
    private var pausedSince: Date?
    private var running = false
    private var awakeAssertion = IOPMAssertionID(0)

    private init() {}

    /// The song wallpaper's switch.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.lyricsWallpaperEnabled) }
    /// The Show lyrics switch.
    static var showsLyrics: Bool { NotchLyricsSupport.showsLyricsOnDesktop() }

    /// Called once at launch and whenever either switch flips.
    func sync() {
        let song = Self.isEnabled
        let lyrics = Self.showsLyrics
        guard song || lyrics else { stop(); return }
        // Lyrics are looked up online, so the first time they are wanted the
        // person is asked before any song name leaves the Mac. Declining turns
        // the lyrics off and leaves the song wallpaper as it was.
        if lyrics, !UserDefaults.standard.bool(forKey: DefaultsKey.lyricsWallpaperConsentAsked) {
            DispatchQueue.main.async { [weak self] in self?.askConsent() }
            return
        }
        let changed = song != songWallpaper || lyrics != showLyrics
        let lyricsTurnedOn = lyrics && !showLyrics
        songWallpaper = song
        showLyrics = lyrics
        guard running else { start(); return }
        // A clear window and an opaque one are different windows.
        if changed { rebuildWindows() }
        if lyricsTurnedOn { playbackChanged(NotchMusicService.shared.playback) }
        if !lyrics {
            extraLookup?.cancel(); extraLookup = nil
            extra = nil
        }
    }

    private func askConsent() {
        let alert = NSAlert()
        alert.messageText = "Allow Vorssaint to look up lyrics for your desktop?"
        alert.informativeText = "While a song plays, Vorssaint shows its synced lyrics on your desktop. "
            + "To find the lyrics it sends the song's title, artist, album and length to lrclib.net and, "
            + "for songs it does not have, the title and artist to music.163.com (NetEase). "
            + "Nothing else is sent, and nothing is recorded. You can turn this off any time in the Wallpaper panel."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Not now")
        NSApp.activate(ignoringOtherApps: true)
        let allowed = alert.runModal() == .alertFirstButtonReturn
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: DefaultsKey.lyricsWallpaperConsentAsked)
        if !allowed { defaults.set(false, forKey: DefaultsKey.lyricsOnWallpaper) }
        sync()
    }

    /// The island's button and the panel's switch both land here: the windows
    /// close in the same turn, with no wait for a song or a lookup.
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.lyricsWallpaperEnabled)
        sync()
    }

    /// Show lyrics: on the song wallpaper, or over the normal one when that is off.
    func setShowLyrics(_ shown: Bool) {
        UserDefaults.standard.set(shown, forKey: DefaultsKey.lyricsOnWallpaper)
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
        idleWork?.cancel(); idleWork = nil
        idleHidden = false
        pausedSince = nil
        extraLookup?.cancel(); extraLookup = nil
        track = nil
        extra = nil
        cover = nil
        previousCover = nil
        coverTrack = nil
        palette = []
        coverSource = nil
        songWallpaper = false
        showLyrics = false
        playback = nil
        setAwake(false)
        closeWindows()
        objectWillChange.send()
    }

    func adjustOffset(by delta: Double) { finder.adjustOffset(by: delta) }
    func resetOffset() { finder.resetOffset() }

    // MARK: Playback

    private func playbackChanged(_ reading: NotchPlayback?) {
        guard running else { return }
        // Only Spotify drives the desktop; anything else playing counts as nothing playing.
        let playback = reading.flatMap { Self.isSpotify($0) ? $0 : nil }
        if self.playback != playback { self.playback = playback }
        // Another player took over (a video, a browser): the normal wallpaper
        // comes back now, rather than a dimmed cover waiting out the grace below.
        if playback == nil, let reading, reading.track.title?.isEmpty == false {
            hideWork?.cancel(); hideWork = nil
            setAwake(false)
            fadeOutWindows()
            return
        }
        guard let playback, playback.track.title?.isEmpty == false else {
            // A player between songs, or the feed restarting around a lock, reports
            // nothing for a moment. The windows stay up through that so nothing
            // flashes, and leave only if the silence lasts.
            guard hideWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.hideWork = nil; self?.setAwake(false); self?.closeWindows(); self?.releaseImages()
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
            return
        }
        hideWork?.cancel()
        hideWork = nil
        // A paused player can still say it is playing; only music that is moving counts.
        let moving = playback.isPlaying && playback.rate > 0
        if moving {
            // Playing again: the wallpaper comes back at once.
            idleWork?.cancel(); idleWork = nil
            idleHidden = false
            pausedSince = nil
        } else {
            let since = pausedSince ?? Date()
            pausedSince = since
            let waited = Date().timeIntervalSince(since)
            if idleHidden || waited >= Self.idleLimit {
                // Paused long enough that the wallpaper went away; it stays away until the music resumes.
                goIdle()
                return
            }
            if idleWork == nil {
                // Paused: the wallpaper stays up for what is left of the wait, then goes if nothing plays.
                let work = DispatchWorkItem { [weak self] in
                    self?.idleWork = nil
                    self?.goIdle()
                }
                idleWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (Self.idleLimit - waited), execute: work)
            }
        }
        showWindows()
        setAwake(moving)
        let identity = NotchMusicIdentity(playback)
        updateCover(from: playback.track.artworkData, for: identity)

        // Vorssaint's finder does the matching, caching and offset memory.
        // The song wallpaper alone has no use for lyrics, so nothing is looked up.
        if showLyrics { finder.update(playback: playback, visible: true) }
        guard identity != track else { return }
        track = identity
        extra = nil
        extraLookup?.cancel(); extraLookup = nil
    }

    private func finderChanged() {
        objectWillChange.send()
        // Not in its catalog: try the extra ones once for this song.
        guard showLyrics, finder.lyrics == nil, extra == nil, extraLookup == nil, let identity = track,
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
    ///
    /// A player often hands over the same song's artwork more than once as it
    /// starts, a thumbnail and then the full image. Only a new song's cover
    /// cross-fades; the same song's sharper copy simply replaces it, so the
    /// desktop does not dip toward black on every copy.
    private func updateCover(from data: Data?, for identity: NotchMusicIdentity) {
        guard data != coverSource else { return }
        coverSource = data
        guard let data else {
            // A song with no artwork still lets the windows show.
            if coverTrack != identity { reveal() }
            return
        }
        // Decoded no larger than the biggest display needs: a cover fills the screen, so its
        // longer edge in pixels. A fixed 3200 px square held some 40 MB per cover.
        let edge = Self.coverPointSize
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = ImageThumbnailer.thumbnail(data: data, pointSize: edge, scale: scale)
            let colors = ArtworkPalette.colors(from: data).map { Color(nsColor: $0) }
            DispatchQueue.main.async {
                guard let self, self.coverSource == data, let image else { return }
                let newSong = self.coverTrack != identity || self.cover == nil
                self.coverTrack = identity
                if newSong {
                    self.previousCover = self.cover
                    self.cover = image
                    self.palette = colors
                    self.coverID += 1
                    // The old cover is only the floor under the cross-fade; once that is done it goes.
                    let fade = self.coverID
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        guard let self, self.coverID == fade else { return }
                        self.previousCover = nil
                    }
                } else {
                    var plain = Transaction()
                    plain.disablesAnimations = true
                    withTransaction(plain) {
                        self.cover = image
                        self.palette = colors
                    }
                }
                self.reveal()
            }
        }
    }

    /// The reading's player, by bundle id or, when the reading has none, by its process.
    private static func isSpotify(_ playback: NotchPlayback) -> Bool {
        let bundle = playback.track.appBundleIdentifier
            ?? playback.track.appPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        return NotchLyricsSupport.drivesDesktop(bundleIdentifier: bundle)
    }

    // MARK: Keep awake

    /// While a song plays and the lyrics are up, the display stays on, on the
    /// desktop and the lock screen alike. It is the same assertion Keep Awake
    /// takes, held on its own so it never touches a session of the person's.
    func refreshAwake() {
        let playback = NotchMusicService.shared.playback
        setAwake(playback.map { Self.isSpotify($0) && $0.isPlaying && $0.rate > 0 } == true)
    }

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

    private func refreshOnScreen() {
        let visible = windows.values.contains { $0.occlusionState.contains(.visible) }
        if visible != onScreen { onScreen = visible }
    }

    /// The longest screen edge, in points, that a cover has to fill.
    private static var coverPointSize: CGFloat {
        min(1600, NSScreen.screens.map { max($0.frame.width, $0.frame.height) }.max() ?? 1600)
    }

    /// Once the windows are gone the decoded covers are too, a few dozen megabytes
    /// each. The next song, or this one resuming, decodes its cover again.
    private func releaseImages() {
        guard windows.isEmpty else { return }
        cover = nil
        previousCover = nil
        coverSource = nil
        coverTrack = nil
        // The colours go with the cover, so nothing keeps tinting a screen after the song.
        palette = []
    }

    /// Fades the waiting windows in. Lyrics alone show at once: a clear window has nothing to flash.
    private func reveal() {
        revealWork?.cancel(); revealWork = nil
        guard !revealed else { return }
        revealed = true
        for window in windows.values where window.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.45
                window.animator().alphaValue = 1
            }
        }
    }

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
        // A new window learns whether it can be seen once the window server has placed it.
        DispatchQueue.main.async { [weak self] in self?.refreshOnScreen() }
        guard !revealed else { return }
        if !songWallpaper || cover != nil {
            reveal()
        } else if revealWork == nil {
            // A cover that never comes still lets the wallpaper show, a little later.
            let work = DispatchWorkItem { [weak self] in self?.reveal() }
            revealWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    private func rebuildWindows() {
        guard !windows.isEmpty, !idleHidden else { return }
        closeWindows()
        showWindows()
    }

    /// A long pause: the normal wallpaper comes back and stays until the music moves again.
    private func goIdle() {
        idleWork?.cancel(); idleWork = nil
        idleHidden = true
        setAwake(false)
        guard !windows.isEmpty else { return }
        fadeOutWindows(whenIdle: true)
    }

    /// The windows fade away, then close; a Spotify reading in the meantime keeps them.
    private func fadeOutWindows(whenIdle: Bool = false) {
        guard !windows.isEmpty else { return }
        revealWork?.cancel(); revealWork = nil
        // Spotify coming back mid-fade shows them again from where they are.
        revealed = false
        let shown = Array(windows.values)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            shown.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            // Music moving again in the meantime keeps the windows.
            guard let self, whenIdle ? self.idleHidden : self.playback == nil else { return }
            self.closeWindows()
            self.releaseImages()
        })
    }

    private func closeWindows() {
        // Closed, not only ordered out: an ordered-out window stays alive with its whole SwiftUI tree.
        windows.values.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        occlusionObservers.forEach(NotificationCenter.default.removeObserver)
        occlusionObservers.removeAll()
        revealed = false
        revealWork?.cancel(); revealWork = nil
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        // The song wallpaper covers the desktop; lyrics alone leave the normal wallpaper showing.
        window.isOpaque = songWallpaper
        window.backgroundColor = songWallpaper ? .black : .clear
        window.alphaValue = revealed ? 1 : 0
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = NSHostingView(rootView: LyricsWallpaperView(service: self))
        occlusionObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in self?.refreshOnScreen() })
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return window
    }
}
