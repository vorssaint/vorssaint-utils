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
    private var panel: NotchLockScreenPanel?
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
        guard panel == nil, LyricsWallpaperService.isEnabled,
              UserDefaults.standard.bool(forKey: DefaultsKey.lyricsLockScreenEnabled),
              let screen = NSScreen.screens.first(where: { $0.displayID == CGMainDisplayID() }) ?? NSScreen.screens.first,
              let space = NotchOverlaySpace(absoluteLevel: NotchLockScreenSupport.spaceLevel) else { return }
        let panel = NotchLockScreenPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
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
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: LyricsLockScreenView(service: LyricsWallpaperService.shared))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(screen.frame, display: false)
        space.add(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.35; panel.animator().alphaValue = 1 }
        self.space = space
        self.panel = panel
    }

    private func hide() {
        panel?.orderOut(nil)
        space?.close()
        panel = nil
        space = nil
    }
}

private struct LyricsLockScreenView: View {
    @ObservedObject var service: LyricsWallpaperService
    @ObservedObject private var music = NotchMusicService.shared

    var body: some View {
        ZStack {
            // A soft dark band keeps the words readable over any lock wallpaper.
            LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: .black.opacity(0.4), location: 0.38),
                                   .init(color: .black.opacity(0.4), location: 0.46), .init(color: .clear, location: 0.58)],
                           startPoint: .top, endPoint: .bottom)
            if let lyrics = service.lyrics, let playback = music.playback, !lyrics.lines.isEmpty, playback.hasPosition {
                ConstellationLyricsView(lyrics: lyrics, playback: playback, offset: service.offset, compact: true)
                    .id(playback.sampledAt)
            }
        }
        .ignoresSafeArea()
    }
}
