// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Shows the song's lyrics over the lock screen, between the clock and the
/// login controls, in the same private Space the island uses for its lock
/// screen player. It follows the system's lock and unlock announcements, so
/// it works whether or not the Dynamic Island is installed or on.
final class LyricsLockScreenService {
    static let shared = LyricsLockScreenService()

    private var space: NotchOverlaySpace?
    private var panels: [NotchLockScreenPanel] = []
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                self?.show()
                self?.keepFeedAlive()
            },
            center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                self?.hide()
                // Another feature stopping the player feed at unlock must not end the wallpaper's.
                if LyricsWallpaperService.isEnabled { NotchMusicService.shared.start() }
            }
        ]
    }

    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers = []
        hide()
    }

    /// The island stops the player feed while it tears down for the lock, and
    /// only restarts it for its own lock screen player. The lyrics need the
    /// feed the whole time the Mac is locked, so it is restarted after that
    /// teardown, and again in case the teardown ran late. Starting is idempotent.
    private func keepFeedAlive() {
        guard LyricsWallpaperService.isEnabled else { return }
        for delay in [0.3, 1.5, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if LyricsWallpaperService.isEnabled { NotchMusicService.shared.start() }
            }
        }
    }

    private func show() {
        guard panels.isEmpty, LyricsWallpaperService.isEnabled,
              UserDefaults.standard.bool(forKey: DefaultsKey.lyricsLockScreenEnabled),
              let screen = NSScreen.screens.first(where: { $0.displayID == CGMainDisplayID() }) ?? NSScreen.screens.first,
              let space = NotchOverlaySpace(absoluteLevel: NotchLockScreenSupport.spaceLevel) else { return }
        // The lyrics fill the screen but let every click through to the login.
        let lyrics = Self.makePanel(frame: screen.frame, interactive: false,
                                    content: LyricsLockScreenView(service: LyricsWallpaperService.shared))
        // The options sit low and centred, clear of the clock and the login, and
        // are the one part that takes clicks.
        let size = CGSize(width: 400, height: 46)
        let controlsFrame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + screen.frame.height * 0.09,
                                   width: size.width, height: size.height)
        let controls = Self.makePanel(frame: controlsFrame, interactive: true,
                                      content: LyricsLockControls(service: LyricsWallpaperService.shared))
        for panel in [lyrics, controls] {
            space.add(panel)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.35; panel.animator().alphaValue = 1 }
        }
        self.space = space
        self.panels = [lyrics, controls]
    }

    private func hide() {
        panels.forEach { $0.orderOut(nil) }
        space?.close()
        panels = []
        space = nil
    }

    private static func makePanel<Content: View>(frame: CGRect, interactive: Bool, content: Content) -> NotchLockScreenPanel {
        let panel = NotchLockScreenPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = NotchPanel.normalLevel
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        if !interactive { panel.ignoresMouseEvents = true }
        let host = LyricsLockHostingView(rootView: AnyView(content))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: false)
        return panel
    }
}

/// The panel is never key while the Mac is locked, so a button has to
/// answer the first click.
private final class LyricsLockHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Options on the lock screen: the player's buttons, the lyrics style, timing
/// and a way to switch the lyrics off. Without a song only the lyrics options show.
private struct LyricsLockControls: View {
    @ObservedObject var service: LyricsWallpaperService
    @ObservedObject private var music = NotchMusicService.shared
    @AppStorage(DefaultsKey.lyricsWallpaperStyle) private var style = "constellation"

    var body: some View {
        HStack(spacing: 4) {
            if let playback = music.playback {
                button("backward.fill", "Previous") { _ = music.send(.previous, context: playback.commandContext) }
                button(playback.isPlaying ? "pause.fill" : "play.fill", "Play or pause") {
                    _ = music.send(.toggle, context: playback.commandContext)
                }
                button("forward.fill", "Next") { _ = music.send(.next, context: playback.commandContext) }
                Divider().frame(height: 18).padding(.horizontal, 4)
            }
            button(style == "constellation" ? "text.alignleft" : "sparkles",
                   style == "constellation" ? "Scrolling lyrics" : "Graph lyrics") {
                style = style == "constellation" ? "scroll" : "constellation"
            }
            button("minus", "Lyrics earlier") { service.adjustOffset(by: -0.25) }
            Text(service.offset, format: .number.sign(strategy: .always()).precision(.fractionLength(2)))
                .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                .frame(minWidth: 40)
            button("plus", "Lyrics later") { service.adjustOffset(by: 0.25) }
            Divider().frame(height: 18).padding(.horizontal, 4)
            button("xmark", "Turn off lyrics wallpaper") { service.setEnabled(false) }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
        .environment(\.colorScheme, .dark)
    }

    private func button(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct LyricsLockScreenView: View {
    @ObservedObject var service: LyricsWallpaperService
    @ObservedObject private var music = NotchMusicService.shared
    @AppStorage(DefaultsKey.lyricsWallpaperStyle) private var style = "constellation"

    private static let band = LinearGradient(
        stops: [.init(color: .clear, location: 0.2), .init(color: .black, location: 0.36),
                .init(color: .black, location: 0.46), .init(color: .clear, location: 0.6)],
        startPoint: .top, endPoint: .bottom)

    private var accent: Color {
        service.palette.first.map { Color(nsColor: NSColor($0).blended(withFraction: 0.35, of: .white) ?? .white) }
            ?? Color(red: 0.43, green: 0.61, blue: 1.0)
    }

    var body: some View {
        ZStack {
            // The clock and login stay clear: the cover's colours and a dark
            // band live only between them, fading out at both edges.
            ZStack {
                Color.black.opacity(0.45)
                AuroraBackdrop(palette: service.palette).blendMode(.screen)
            }
            .mask(Self.band)
            if let lyrics = service.lyrics, let playback = music.playback, !lyrics.lines.isEmpty, playback.hasPosition {
                if style == "constellation" {
                    ConstellationLyricsView(lyrics: lyrics, playback: playback, offset: service.offset,
                                            compact: true, accent: accent)
                } else {
                    GeometryReader { proxy in
                        ScrollLyricsView(lyrics: lyrics, playback: playback, offset: service.offset, compact: true)
                            .frame(width: proxy.size.width * 0.6, height: proxy.size.height * 0.26)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.385)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}
