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
        // The options sit low and centred, clear of the clock and the login, and
        // are the one part that takes clicks.
        let size = CGSize(width: 600, height: 60)
        let controlsFrame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + screen.frame.height * 0.06,
                                   width: size.width, height: size.height)
        let controls = Self.makePanel(frame: controlsFrame, interactive: true,
                                      content: LyricsLockControls(service: LyricsWallpaperService.shared))
        // The island at the camera takes a click to open the style picker just
        // under it; the picker is clear, so clicks pass through while it is shut.
        let island = Self.islandRect(on: screen)
        let notched = AppFeature.notch.isAvailable && NotchService.shared.geometry.isNotched
        let hit = Self.makePanel(frame: island, interactive: true, content: LyricsLockIslandHit(model: model, visible: !notched))
        // Opened, the island grows from the camera: black, hung from the top
        // edge, with the styles below the camera's own row.
        let pickerSize = CGSize(width: 540, height: island.height + 176)
        let pickerFrame = CGRect(x: screen.frame.midX - pickerSize.width / 2,
                                 y: screen.frame.maxY - pickerSize.height, width: pickerSize.width, height: pickerSize.height)
        let picker = Self.makePanel(frame: pickerFrame, interactive: true,
                                    content: LyricsLockStylePicker(model: model, cameraRow: island.height))
        model.pickerOpen = false
        for panel in [lyrics, controls, hit, picker] {
            space.add(panel)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.35; panel.animator().alphaValue = 1 }
        }
        self.space = space
        self.panels = [lyrics, controls, hit, picker]
    }

    private func hide() {
        model.pickerOpen = false
        panels.forEach { $0.orderOut(nil) }
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

/// The lock screen's one pill, low and centred: the song with its cover and
/// buttons, then the lyrics options. Without a song only the options show.
private struct LyricsLockControls: View {
    @ObservedObject var service: LyricsWallpaperService
    @ObservedObject private var music = NotchMusicService.shared
    @AppStorage(DefaultsKey.lyricsWallpaperStyle) private var style = "constellation"

    var body: some View {
        HStack(spacing: 4) {
            if let playback = music.playback {
                artwork
                VStack(alignment: .leading, spacing: 1) {
                    Text(playback.track.title ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(playback.track.artist ?? "").font(.system(size: 11)).opacity(0.65).lineLimit(1)
                }
                .foregroundStyle(.white).frame(width: 130, alignment: .leading).padding(.horizontal, 6)
                button("backward.fill", "Previous") { _ = music.send(.previous, context: playback.commandContext) }
                button(playback.isPlaying ? "pause.fill" : "play.fill", "Play or pause") {
                    _ = music.send(.toggle, context: playback.commandContext)
                }
                button("forward.fill", "Next") { _ = music.send(.next, context: playback.commandContext) }
                Divider().frame(height: 20).padding(.horizontal, 4)
            }
            button(LyricsMode.from(style).symbol, "Next lyrics style (\(LyricsMode.from(style).next.title))") {
                style = LyricsMode.from(style).next.rawValue
            }
            button("minus", "Lyrics earlier") { service.adjustOffset(by: -0.25) }
            Text(service.offset, format: .number.sign(strategy: .always()).precision(.fractionLength(2)))
                .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                .frame(minWidth: 38)
            button("plus", "Lyrics later") { service.adjustOffset(by: 0.25) }
            Divider().frame(height: 20).padding(.horizontal, 4)
            button("xmark", "Turn off lyrics wallpaper") { service.setEnabled(false) }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var artwork: some View {
        if let image = service.cover ?? music.artwork {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                .frame(width: 40, height: 40).clipShape(Circle())
        } else {
            Circle().fill(.white.opacity(0.15)).frame(width: 40, height: 40)
                .overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.6)))
        }
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
    }
}

final class LyricsLockModel: ObservableObject {
    @Published var pickerOpen = false
}

/// A tap target over the island at the camera. It is nearly clear but not
/// quite: a window passes clicks through pixels with no colour at all.
private struct LyricsLockIslandHit: View {
    @ObservedObject var model: LyricsLockModel
    let visible: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(visible ? 0.55 : 0.02)
            if visible {
                Label("Lyrics", systemImage: model.pickerOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .clipShape(Capsule())
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.smooth(duration: 0.2)) { model.pickerOpen.toggle() } }
    }
}

/// The styles to choose from, opened by tapping the island. Shut, it draws
/// nothing at all, so the lock screen under it takes its clicks.
private struct LyricsLockStylePicker: View {
    @ObservedObject var model: LyricsLockModel
    /// The camera's own row at the top, kept clear.
    let cameraRow: CGFloat
    @AppStorage(DefaultsKey.lyricsWallpaperStyle) private var style = "constellation"

    var body: some View {
        Group {
            if model.pickerOpen {
                VStack(spacing: 8) {
                    // Tapping the camera's row shuts it again.
                    Color.black.frame(height: cameraRow)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.smooth(duration: 0.25)) { model.pickerOpen = false } }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(LyricsMode.allCases) { mode in
                            let selected = LyricsMode.from(style) == mode
                            Button {
                                style = mode.rawValue
                                withAnimation(.smooth(duration: 0.25)) { model.pickerOpen = false }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: mode.symbol).font(.system(size: 18, weight: .semibold))
                                    Text(mode.title).font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 62)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.white.opacity(selected ? 0.28 : 0.09)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(NotchShape(attached: true, radius: 28).fill(.black))
                .environment(\.colorScheme, .dark)
                .transition(.scale(scale: 0.5, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
