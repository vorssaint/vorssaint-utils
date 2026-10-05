// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AudioToolbox
import Combine
import SwiftUI

/// The island over the lock screen: music on a pane of Liquid Glass between
/// the clock and the login controls, the activities as a line under the
/// clock, the padlock at the camera, and the padlock sounds. The
/// island drives it from its own session state. On locking it follows the
/// island's teardown, which stops the sources this service then restarts.
/// On unlocking the scene starts leaving before the island comes back, and
/// stops none of the sources the island takes back.
final class NotchLockScreenService {
    static let shared = NotchLockScreenService()

    private struct Frames: Equatable {
        var player: CGRect?
        var row: CGRect?
        var island: CGRect?
        /// The island itself inside its window, at the camera's fitted size.
        var islandSurface: CGRect?
    }

    private let model = NotchLockScreenModel()
    /// The player and the line of activities.
    private var scene: [NotchLockScreenPanel] = []
    private var island: NotchLockScreenPanel?
    private var space: NotchOverlaySpace?
    private var playbackSubscription: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var padlockWork: DispatchWorkItem?
    private var shownFrames = Frames()
    private var wasLocked = false

    private init() {}

    var isShowing: Bool { space != nil }

    func sync(_ session: NotchSessionState) {
        let locking = session.locked && !wasLocked
        wasLocked = session.locked
        if !session.locked { model.playedWhileLocked = false }
        if session.showsLockScreen, NotchLockScreenSupport.isEnabled() {
            // Locked at the Mac, the padlock is seen closing; back from a
            // dark display it is simply closed.
            show(closingPadlock: locking)
        } else {
            // Unlocked, the island owns the sources again; otherwise nothing
            // shows them until the lock screen returns.
            hide(unlocking: !session.locked && session.canPresent, stopsSources: !session.canPresent)
        }
    }

    /// The island is off: nothing it started keeps running.
    func close() {
        wasLocked = false
        model.playedWhileLocked = false
        hide(unlocking: false, stopsSources: true)
    }

    func playSound(locking: Bool) {
        guard let url = NotchLockScreenSupport.soundURL(locking: locking) else { return }
        var sound: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &sound) == noErr else { return }
        // Asked for here, so it plays even with interface sound effects off
        // in System Settings. The alert volume and the sound effects output
        // still apply, as they do to the Mac's own sounds.
        var interface: UInt32 = 0
        AudioServicesSetProperty(kAudioServicesPropertyIsUISound, UInt32(MemoryLayout<SystemSoundID>.size), &sound,
                                 UInt32(MemoryLayout<UInt32>.size), &interface)
        AudioServicesPlaySystemSoundWithCompletion(sound) { AudioServicesDisposeSystemSoundID(sound) }
    }

    /// Where each part goes on the displays as they are now.
    private static func frames() -> Frames {
        var frames = Frames()
        // macOS draws the clock and the password field on the main display.
        let main = CGMainDisplayID()
        if let screen = (NSScreen.screens.first(where: { $0.notchDisplayID == main }) ?? NSScreen.screens.first)?.frame {
            frames.player = NotchLockScreenLayout.playerFrame(in: screen)
            frames.row = NotchLockScreenLayout.rowFrame(in: screen)
        }
        // The island's own reading of its camera, with the fit the person set.
        let geometry = NotchService.shared.geometry
        if geometry.isNotched, NSScreen.screens.contains(where: { $0.frame == geometry.screen && $0.safeAreaInsets.top > 0 }) {
            let surface = NotchLockScreenLayout.islandSurface(
                in: geometry.screen, cameraWidth: geometry.bareCutout.width, cameraHeight: geometry.bareCutout.height,
                wing: geometry.lockScreenMusicGeometry.compactActivityWingWidth)
            frames.islandSurface = surface
            frames.island = surface.map(NotchLockScreenLayout.islandFrame(around:))
        }
        return frames
    }

    private func show(closingPadlock: Bool) {
        guard space == nil,
              let space = NotchOverlaySpace(absoluteLevel: NotchLockScreenSupport.spaceLevel) else { return }
        let frames = Self.frames()
        // Settled before any view reads it, so a padlock about to close is
        // drawn open from its first frame.
        padlockWork?.cancel()
        model.padlockOpen = closingPadlock
        let gates = NotchLockScreenModel.Gates(
            music: NotchLockScreenSupport.showsMusic(), timer: NotchTimerSupport.isEnabled(),
            agents: NotchAgentSupport.showsLiveActivity(),
            downloads: NotchSupport.routes(.download), countdown: NotchCalendarSupport.showsCountdown(),
            timeLeft: NotchCalendarSupport.showsTimeLeft())
        if model.gates != gates { model.gates = gates }
        var scene: [NotchLockScreenPanel] = []
        // Without the Music section there is no player to show or to click.
        if gates.music, let frame = frames.player {
            // The one part that takes clicks: the player's buttons and timeline.
            scene.append(Self.makePanel(frame: frame, interactive: true,
                                        content: NotchLockScreenPlayer(model: model, size: frame.size)))
        }
        if let frame = frames.row {
            scene.append(Self.makePanel(frame: frame, content: NotchLockScreenActivities(model: model, size: frame.size)))
        }
        let island = frames.island.flatMap { frame in
            frames.islandSurface.map { surface in
                Self.makePanel(frame: frame, content: NotchLockScreenIsland(
                    model: model, size: surface.size, cameraWidth: NotchService.shared.geometry.bareCutout.width,
                    geometry: NotchService.shared.geometry.lockScreenMusicGeometry,
                    window: frame.size, origin: CGPoint(x: surface.minX - frame.minX, y: frame.maxY - surface.maxY)))
            }
        }
        let panels = scene + [island].compactMap { $0 }
        guard !panels.isEmpty else { space.close(); return }
        if !scene.isEmpty { startSources(gates) }
        // Joined before they are first shown, the windows belong to this
        // Space alone and are drawn over the lock screen with it.
        for panel in panels { space.add(panel) }
        self.space = space
        self.scene = scene
        self.island = island
        shownFrames = frames
        if closingPadlock {
            let work = DispatchWorkItem { [weak self] in self?.model.padlockOpen = false }
            padlockWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        for panel in panels {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                panel.animator().alphaValue = 1
            }
        }
        playbackSubscription = NotchMusicService.shared.$playback
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playback in
                guard let self, playback?.isPlaying == true, !self.model.playedWhileLocked else { return }
                self.model.playedWhileLocked = true
            }
        // A display attached or rearranged while locked moves the clock, the
        // login controls and the camera; the scene and the padlock follow.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.space != nil, Self.frames() != self.shownFrames else { return }
                self.hide(unlocking: false, stopsSources: false)
                self.show(closingPadlock: false)
            }
    }

    private func startSources(_ gates: NotchLockScreenModel.Gates) {
        if gates.music { NotchMusicService.shared.start() }
        if gates.downloads { NotchDownloadService.shared.syncWithPreferences() }
        // An event chosen from its menu counts down with the countdown for every event off.
        if gates.countdown || gates.timeLeft || !NotchCalendarSupport.chosenCountdowns().isEmpty {
            NotchCalendarService.shared.syncWithPreferences()
        }
        if gates.agents { AgentUsageService.shared.syncWithPreferences() }
    }

    private func hide(unlocking: Bool, stopsSources: Bool) {
        if stopsSources, !scene.isEmpty {
            NotchMusicService.shared.stop()
            NotchDownloadService.shared.stop()
            NotchCalendarService.shared.stop()
            AgentUsageService.shared.pause()
        }
        playbackSubscription = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        padlockWork?.cancel()
        padlockWork = nil
        guard let space else { return }
        let scene = scene, island = island
        self.scene = []
        self.island = nil
        self.space = nil
        guard unlocking else {
            (scene + [island].compactMap { $0 }).forEach { $0.orderOut(nil) }
            space.close()
            return
        }
        // The lock screen is gone about 0.3 s after the unlock is announced;
        // the player leaves with it rather than lingering over the desktop.
        // The padlock opens first, then the island underneath takes over.
        var remaining = scene.count + (island == nil ? 0 : 1)
        let finished = { remaining -= 1; if remaining == 0 { space.close() } }
        scene.forEach { Self.fadeOut($0, after: 0, completion: finished) }
        if let island {
            model.padlockOpen = true
            // The island comes back on this turn and holds the main thread, so
            // the padlock is first seen opening once that is done. Its time
            // starts there, or the island would fade while the padlock opens.
            DispatchQueue.main.async { Self.fadeOut(island, after: 0.55, completion: finished) }
        }
    }

    private static func fadeOut(_ panel: NSPanel, after delay: TimeInterval, completion: @escaping () -> Void) {
        let duration: TimeInterval = 0.2
        let fade = {
            // AppKit steps its fades on the main thread, which the island
            // coming back holds as the Mac unlocks, so the player could stay
            // over the desktop for a second. The window server fades on its own,
            // once a fade-in AppKit may still be stepping stops where it is.
            panel.alphaValue = panel.alphaValue
            if NotchWindowServerFade.fadeOut(panel, duration: duration) {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    panel.alphaValue = 0
                    panel.orderOut(nil)
                    completion()
                }
            } else {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = duration
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    panel.orderOut(nil)
                    completion()
                })
            }
        }
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: fade) } else { fade() }
    }

    private static func makePanel<Content: View>(frame: CGRect, interactive: Bool = false,
                                                 content: Content) -> NotchLockScreenPanel {
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
        // Only the player's pane takes clicks, where it draws. Left unset, a
        // window lets clicks through its clear pixels, so the room around the
        // pane and a player with no song pass them to the lock screen beneath.
        // Set to false, the whole frame would take them even with nothing shown.
        if !interactive { panel.ignoresMouseEvents = true }
        let host = NotchLockScreenHostingView(rootView: AnyView(content))
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrame(frame, display: false)
        return panel
    }
}

/// A fade the window server runs by itself, whatever the main thread is
/// doing. The symbols are resolved at runtime. Without them AppKit fades.
private enum NotchWindowServerFade {
    private typealias AlphaFunction = @convention(c) (UInt32, UnsafePointer<UInt32>, Int32, Float, Float) -> Int32

    private static let bridge: (connection: UInt32, setAlpha: AlphaFunction)? = {
        func symbol(_ name: String) -> UnsafeMutableRawPointer? {
            dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
        }
        guard let main = symbol("CGSMainConnectionID"), let alpha = symbol("CGSSetWindowListAlpha") else { return nil }
        let connection = unsafeBitCast(main, to: (@convention(c) () -> UInt32).self)()
        guard connection != 0 else { return nil }
        return (connection, unsafeBitCast(alpha, to: AlphaFunction.self))
    }()

    /// Whether the window server took the fade.
    static func fadeOut(_ window: NSWindow, duration: TimeInterval) -> Bool {
        guard let bridge, window.windowNumber > 0 else { return false }
        var id = UInt32(window.windowNumber)
        return bridge.setAlpha(bridge.connection, &id, 1, 0, Float(duration)) == 0
    }
}

/// Never key and never main: while the Mac is locked every keystroke belongs
/// to the password field, and a click on the player must not take it away.
final class NotchLockScreenPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // A window that never holds key focus would otherwise draw its glass as
    // an inactive window does, flat and dull.
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }
}

private final class NotchLockScreenHostingView: NSHostingView<AnyView> {
    // The panel is never key, so a button has to answer the first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
