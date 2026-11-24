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
    private let model = LyricsLockModel()
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// With the lyrics on the lock screen, one pill at the bottom carries the
    /// player, so the island's large centred pane steps aside.
    static var takesOverPlayer: Bool {
        let defaults = UserDefaults.standard
        return LyricsWallpaperService.isEnabled && defaults.bool(forKey: DefaultsKey.lyricsLockScreenEnabled)
            && defaults.bool(forKey: DefaultsKey.lyricsWallpaperConsentAsked)
    }

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

        // The song and the lyrics options sit at the left edge, in the room the
        // login leaves clear: the name, picture and password field stay centred.
        let room = (screen.frame.width - NotchLockScreenLayout.playerWidth) / 2
        let width = min(300, max(220, room - 48))
        let controlsFrame = CGRect(x: screen.frame.minX + 32, y: screen.frame.minY + 56, width: width, height: 168)
        let controls = Self.makePanel(frame: controlsFrame, interactive: true,
                                      content: LyricsLockControls(service: LyricsWallpaperService.shared))

        // The island at the camera opens the styles. The window is the open size,
        // clear, hung from the top edge; the black shape inside grows from the
        // camera's own footprint.
        let island = Self.islandRect(on: screen)
        let notched = AppFeature.notch.isAvailable && NotchService.shared.geometry.isNotched
        let expanded = CGSize(width: 540, height: island.height + 156)
        let surfaceFrame = CGRect(x: screen.frame.midX - expanded.width / 2, y: screen.frame.maxY - expanded.height,
                                  width: expanded.width, height: expanded.height)
        model.pickerOpen = false
        let surface = Self.makePanel(frame: surfaceFrame, interactive: true,
                                     content: LyricsLockIslandSurface(model: model, collapsed: island.size,
                                                                      expanded: expanded, visibleTarget: !notched))
        for panel in [lyrics, controls, surface] {
            space.add(panel)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.35; panel.animator().alphaValue = 1 }
        }
        self.space = space
        self.panels = [lyrics, controls, surface]
    }

    private func hide() {
        model.pickerOpen = false
        // Closed, not only ordered out: each lock builds new panels, and an ordered-out one stays alive.
        panels.forEach { $0.orderOut(nil); $0.close() }
        space?.close()
        panels = []
        space = nil
    }

    /// The locked island's footprint at the camera, or a small stand-in at the
    /// top centre on a display without one, or with the island off.
    private static func islandRect(on screen: NSScreen) -> CGRect {
        if AppFeature.notch.isAvailable {
            let geometry = NotchService.shared.geometry
            if geometry.isNotched, let surface = NotchLockScreenLayout.islandSurface(
                in: geometry.screen, cameraWidth: geometry.bareCutout.width, cameraHeight: geometry.bareCutout.height,
                wing: geometry.lockScreenMusicGeometry.compactActivityWingWidth) {
                return NotchLockScreenLayout.islandFrame(around: surface)
            }
        }
        return CGRect(x: screen.frame.midX - 70, y: screen.frame.maxY - 36, width: 140, height: 30)
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

/// The song and the lyrics options in one frosted card at the left edge:
/// the cover and title, the player's buttons, the style, the timing and a way
/// to switch the lyrics off. Without a song only the lyrics options show.
private struct LyricsLockControls: View {
    @ObservedObject var service: LyricsWallpaperService
    @ObservedObject private var music = NotchMusicService.shared
    @AppStorage(DefaultsKey.lyricsWallpaperStyle) private var style = "constellation"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let playback = music.playback {
                HStack(spacing: 10) {
                    artwork
                    VStack(alignment: .leading, spacing: 1) {
                        Text(playback.track.title ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(playback.track.artist ?? "").font(.system(size: 11)).opacity(0.65).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 2) {
                    button("backward.fill", "Previous") { _ = music.send(.previous, context: playback.commandContext) }
                    button(playback.isPlaying ? "pause.fill" : "play.fill", "Play or pause") {
                        _ = music.send(.toggle, context: playback.commandContext)
                    }
                    button("forward.fill", "Next") { _ = music.send(.next, context: playback.commandContext) }
                    Spacer(minLength: 0)
                    button(LyricsMode.from(style).symbol, "Next lyrics style (\(LyricsMode.from(style).next.title))") {
                        style = LyricsMode.from(style).next.rawValue
                    }
                }
            } else {
                HStack(spacing: 2) {
                    Text("Lyrics").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    button(LyricsMode.from(style).symbol, "Next lyrics style (\(LyricsMode.from(style).next.title))") {
                        style = LyricsMode.from(style).next.rawValue
                    }
                }
            }
            Divider().overlay(.white.opacity(0.15))
            HStack(spacing: 2) {
                button("minus", "Lyrics earlier") { service.adjustOffset(by: -0.25) }
                Text(service.userOffset, format: .number.sign(strategy: .always()).precision(.fractionLength(2)))
                    .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.75))
                    .frame(minWidth: 42)
                button("plus", "Lyrics later") { service.adjustOffset(by: 0.25) }
                Spacer(minLength: 0)
                button("xmark", "Turn off lyrics wallpaper") { service.setEnabled(false) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .trueGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.18)))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var artwork: some View {
        if let image = service.cover ?? music.artwork {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.15)).frame(width: 44, height: 44)
                .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.6)))
        }
    }

    private func button(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct LyricsLockScreenView: View {
    @ObservedObject var service: LyricsWallpaperService
    @AppStorage(DefaultsKey.lyricsWallpaperStyle) private var style = "constellation"

    private static let band = LinearGradient(
        stops: [.init(color: .clear, location: 0.2), .init(color: .black, location: 0.36),
                .init(color: .black, location: 0.46), .init(color: .clear, location: 0.6)],
        startPoint: .top, endPoint: .bottom)

    private var accent: Color {
        service.palette.first.map { Color(nsColor: NSColor($0).blended(withFraction: 0.35, of: .white) ?? .white) }
            ?? Color(red: 0.43, green: 0.61, blue: 1.0)
    }

    /// Spotify is playing. Paused, stopped or another player, and the lock screen is left as macOS draws it.
    private var playing: Bool { service.playback?.isPlaying == true }

    var body: some View {
        ZStack {
            // The clock and login stay clear: the cover's colours and a dark
            // band live only between them, fading out at both edges. Only while
            // a song plays: the last cover's colours must not linger as a glow.
            ZStack {
                Color.black.opacity(0.45)
                AuroraBackdrop(palette: service.palette).blendMode(.screen)
            }
            .mask(Self.band)
            .opacity(playing ? 1 : 0)
            .animation(.easeInOut(duration: 0.6), value: playing)
            if !service.idleHidden, let lyrics = service.lyrics, let playback = service.playback, !lyrics.lines.isEmpty, playback.hasPosition {
                if LyricsMode.from(style) == .constellation {
                    ConstellationLyricsView(lyrics: lyrics, playback: playback, offset: service.offset,
                                            compact: true, accent: accent)
                } else {
                    // Every other mode lives in the band between the clock and the login.
                    GeometryReader { proxy in
                        LyricsModeView(mode: LyricsMode.from(style), lyrics: lyrics, playback: playback,
                                       offset: service.offset, accent: accent, compact: true)
                            .frame(width: proxy.size.width * 0.62, height: proxy.size.height * 0.26)
                            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.385)
                    }
                }
            }
        }
        .ignoresSafeArea()
        // Hidden, the glow stops redrawing too.
        .environment(\.lyricsAnimationsActive, playing)
    }
}

final class LyricsLockModel: ObservableObject {
    @Published var pickerOpen = false
}

/// The island on the lock screen: a tap target at the camera that opens the
/// styles as the island itself opens, growing from the camera's footprint.
private struct LyricsLockIslandSurface: View {
    @ObservedObject var model: LyricsLockModel
    let collapsed: CGSize
    let expanded: CGSize
    /// A display without a camera has no island to tap, so the target shows.
    let visibleTarget: Bool
    @AppStorage(DefaultsKey.lyricsWallpaperStyle) private var style = "constellation"

    var body: some View {
        ZStack(alignment: .top) {
            // Nearly clear, not clear: a window passes clicks through pixels with no colour.
            ZStack {
                Color.black.opacity(visibleTarget ? 0.55 : 0.02)
                if visibleTarget {
                    Label("Lyrics", systemImage: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: collapsed.width, height: collapsed.height)
            .clipShape(NotchLiveShape())
            .contentShape(Rectangle())
            .onTapGesture { model.pickerOpen = true }

            NotchMorphSurface(open: model.pickerOpen, collapsed: collapsed, expanded: expanded) {
                VStack(spacing: 8) {
                    // The camera's own row stays clear; tapping it shuts the island.
                    Color.clear.frame(height: collapsed.height)
                        .contentShape(Rectangle())
                        .onTapGesture { model.pickerOpen = false }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(LyricsMode.allCases) { mode in tile(mode) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
                .environment(\.colorScheme, .dark)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func tile(_ mode: LyricsMode) -> some View {
        let selected = LyricsMode.from(style) == mode
        return Button {
            style = mode.rawValue
            model.pickerOpen = false
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.symbol).font(.system(size: 18, weight: .semibold))
                Text(mode.title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(selected ? 0.28 : 0.09)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
