// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The island, grown from the camera to listen and then show the song it heard,
/// with Spotify and YouTube to open it in. A click elsewhere or Escape closes it.
@MainActor
final class MusicRecognitionPanel: ObservableObject {
    static let shared = MusicRecognitionPanel()

    @Published private(set) var open = false
    @Published private(set) var collapsed = CGSize(width: 200, height: 32)
    @Published private(set) var cameraInset: CGFloat = 32

    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var closeGeneration = 0
    private var autoClose: DispatchWorkItem?
    private var observation: Any?

    static let size = CGSize(width: 440, height: 150)
    /// The row of nearby matches under the song, when there are any.
    static let nearbyHeight: CGFloat = 76
    private static let swing: CGFloat = 28

    private init() {}

    func show() {
        closeGeneration += 1
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let top = screen.safeAreaInsets.top
        cameraInset = top > 0 ? top : max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            collapsed = CGSize(width: max(120, right.minX - left.maxX), height: top)
        } else {
            collapsed = CGSize(width: 200, height: cameraInset)
        }
        // Tall enough for the nearby row; the clear space below the island lets clicks through.
        let size = CGSize(width: Self.size.width, height: Self.size.height + Self.nearbyHeight + cameraInset)
        let frame = CGRect(x: screen.frame.midX - size.width / 2 - Self.swing, y: screen.frame.maxY - size.height - Self.swing,
                           width: size.width + 2 * Self.swing, height: size.height + Self.swing)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        open = true
        installMonitors()
        MusicRecognitionService.shared.start()
        observation = MusicRecognitionService.shared.$state.sink { [weak self] state in
            Task { @MainActor in self?.scheduleClose(for: state) }
        }
    }

    func hide() {
        guard open else { return }
        open = false
        autoClose?.cancel(); autoClose = nil
        observation = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        MusicRecognitionService.shared.stop()
        closeGeneration += 1
        let generation = closeGeneration
        // The content fades, then the island shrinks back into the camera.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 + NotchMotion.shrinkingWidth.duration + 0.1) { [weak self] in
            guard let self, generation == self.closeGeneration else { return }
            self.panel?.orderOut(nil)
            MusicRecognitionService.shared.reset()
        }
    }

    /// A song stays a while; nothing found closes sooner; listening never closes by itself.
    private func scheduleClose(for state: MusicRecognitionService.State) {
        autoClose?.cancel(); autoClose = nil
        let delay: TimeInterval
        switch state {
        case .matched: delay = 30
        case .noMatch, .failed, .microphoneDenied: delay = 6
        case .idle, .listening: return
        }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        autoClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        if let click = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }) { monitors.append(click) }
        if let key = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.hide() }
        }) { monitors.append(key) }
    }

    private func makePanel() -> NSPanel {
        let panel = NotchLockScreenPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        // Above the island it grows out of.
        panel.level = NSWindow.Level(rawValue: NotchPanel.normalLevel.rawValue + 1)
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        let host = MusicRecognitionHostingView(rootView: MusicRecognitionView(panel: self, service: .shared))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

private final class MusicRecognitionHostingView: NSHostingView<MusicRecognitionView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct MusicRecognitionView: View {
    @ObservedObject var panel: MusicRecognitionPanel
    @ObservedObject var service: MusicRecognitionService
    @ObservedObject private var l10n = L10n.shared
    private var text: MusicRecognitionStrings { MusicRecognitionStrings.localized(l10n.language) }

    var body: some View {
        let showsNearby = !service.nearby.isEmpty && { if case .matched = service.state { return true }; return false }()
        let size = CGSize(width: MusicRecognitionPanel.size.width,
                          height: MusicRecognitionPanel.size.height + panel.cameraInset
                            + (showsNearby ? MusicRecognitionPanel.nearbyHeight : 0))
        let shoulder = NotchLayout.shoulder(height: size.height)
        NotchMorphSurface(open: panel.open, collapsed: panel.collapsed,
                          expanded: CGSize(width: size.width + 2 * shoulder, height: size.height)) {
            VStack(spacing: 0) {
                Color.clear.frame(height: panel.cameraInset)
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: MusicRecognitionPanel.size.height - 24)
                    .padding(.horizontal, 22).padding(.top, 8)
                if showsNearby {
                    nearbyRow
                        .padding(.horizontal, 22)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Spacer(minLength: 0)
            }
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.spring(duration: 0.32, bounce: 0.15), value: service.state)
        .animation(.spring(duration: NotchMotion.growingHeight.duration, bounce: NotchMotion.growingHeight.bounce),
                   value: service.nearby)
    }

    @ViewBuilder private var content: some View {
        switch service.state {
        case .idle, .listening:
            listening
        case .matched(let song):
            matched(song)
        case .noMatch:
            message(text.noMatch, symbol: "questionmark.circle")
        case .failed:
            message(text.failed, symbol: "exclamationmark.circle")
        case .microphoneDenied:
            message(text.microphoneDenied, symbol: "mic.slash")
        }
    }

    private var listening: some View {
        HStack(spacing: 16) {
            ListeningRings()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(text.listening).font(.system(size: 16, weight: .semibold))
                Text(text.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            NotchIconButton(symbol: "xmark", title: FeatureStrings.clipboard(l10n.language).cancel) { panel.hide() }
        }
        .transition(.opacity)
    }

    private func matched(_ song: RecognisedSong) -> some View {
        HStack(spacing: 14) {
            Group {
                if let artwork = service.artwork {
                    Image(nsImage: artwork).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note").font(.system(size: 26, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.08))
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(song.title).font(.system(size: 16, weight: .bold)).lineLimit(1)
                    if let percent = service.percent {
                        // As Google shows it: how sure the match is.
                        Text("\(percent)%")
                            .font(.system(size: 11, weight: .bold)).monospacedDigit()
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7).frame(height: 18)
                            .background(Capsule().fill(percent >= 80 ? Color(red: 0.3, green: 0.85, blue: 0.45) : .white.opacity(0.8)))
                            .contentTransition(.numericText())
                            .help("Match")
                    }
                    if service.refining { ProgressView().controlSize(.mini) }
                }
                Text(song.artist).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    openButton("Spotify", symbol: "music.note", tint: Color(red: 0.12, green: 0.84, blue: 0.38)) {
                        MusicRecognitionService.openInSpotify(song)
                        panel.hide()
                    }
                    openButton("YouTube", symbol: "play.rectangle.fill", tint: Color(red: 1, green: 0.2, blue: 0.2)) {
                        MusicRecognitionService.openInYouTube(song)
                        panel.hide()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// Up to three other songs close to what was heard; a tap makes one the main song.
    private var nearbyRow: some View {
        HStack(spacing: 8) {
            ForEach(service.nearby) { match in
                Button { service.choose(match) } label: {
                    HStack(spacing: 8) {
                        NearbyArtwork(url: match.song.artworkURL)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(match.song.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Text(match.percent.map { "\($0)% · \(match.song.artist)" } ?? match.song.artist)
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 12))
                .help(match.song.query)
            }
        }
        .frame(height: MusicRecognitionPanel.nearbyHeight - 20)
    }

    private func openButton(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(.white.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 15))
        .help(title)
    }

    private func message(_ message: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 26, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                .frame(width: 64, height: 64)
            Text(message).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(text.tryAgain) { service.start() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 30)
                .background(.white.opacity(0.1), in: Capsule())
        }
        .transition(.opacity)
    }
}

/// The listening mark: the Shazam glyph with rings spreading from it.
private struct ListeningRings: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (t * 0.7 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    Circle().stroke(.white.opacity(0.45 * (1 - phase)), lineWidth: 1.5)
                        .scaleEffect(0.55 + phase * 0.45)
                }
                Circle().fill(Color(red: 0.08, green: 0.5, blue: 1)).frame(width: 40, height: 40)
                Image(systemName: "shazam.logo.fill").font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
            }
        }
    }
}

/// A nearby match's cover, loaded when shown.
private struct NearbyArtwork: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.08))
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "music.note").font(.system(size: 13)).foregroundStyle(.white.opacity(0.45)) }
        }
        .task(id: url) {
            guard let url, let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            image = NSImage(data: data)
        }
    }
}
