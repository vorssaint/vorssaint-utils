// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The island over the lock screen: the calendar over music on a stage
/// between the clock and the login controls, This Mac's rail left of it and
/// the AI rail right of it, the activities as a line under the clock, the
/// padlock at the camera, and the padlock sounds. The
/// island drives it from its own session state. On locking it follows the
/// island's teardown, which stops the sources this service then restarts.
/// On unlocking the scene starts leaving before the island comes back, and
/// stops none of the sources the island takes back.
final class NotchLockScreenService {
    static let shared = NotchLockScreenService()

    private struct Frames: Equatable {
        var scene = NotchLockScreenScene()
        var island: CGRect?
        /// The island itself inside its window, at the camera's fitted size.
        var islandSurface: CGRect?
    }

    private let model = NotchLockScreenModel()
    /// The player and the line of activities.
    private var scene: [NotchLockScreenPanel] = []
    private var island: NotchLockScreenPanel?
    private var space: NotchOverlaySpace?
    private var screenObserver: NSObjectProtocol?
    private var padlockWork: DispatchWorkItem?
    private var shownFrames = Frames()
    private var wasLocked = false

    private init() {}

    var isShowing: Bool { space != nil }

    func sync(_ session: NotchSessionState) {
        let locking = session.locked && !wasLocked
        wasLocked = session.locked
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
        hide(unlocking: false, stopsSources: true)
    }

    /// The sound chosen on the Sounds page; the padlock, by default, opens
    /// on unlocking rather than closing.
    func playSound(locking: Bool) {
        AppSoundService.shared.play(.screenLock,
                                    swapping: locking ? [:] : [AppSoundChoice.padlockClosing: AppSoundChoice.padlockOpening])
    }

    /// Where each part goes on the displays as they are now.
    private static func frames() -> Frames {
        var frames = Frames()
        // macOS draws the clock and the password field on the main display.
        let main = CGMainDisplayID()
        if let screen = (NSScreen.screens.first(where: { $0.notchDisplayID == main }) ?? NSScreen.screens.first)?.frame {
            // With the Calendar section on the card stays, saying so when the
            // app may not read calendars, rather than leaving a gap to explain.
            frames.scene = NotchLockScreenLayout.scene(in: screen, calendar: NotchCalendarSupport.isEnabled(),
                                                       mac: NotchLockScreenSupport.showsMac(),
                                                       ai: NotchLockScreenSupport.showsAgents(),
                                                       widgets: NotchLockScreenWidgets.stored().leavingOutHiddenLimits())
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
        let layout = frames.scene
        // Settled before any view reads it, so a padlock about to close is
        // drawn open from its first frame.
        padlockWork?.cancel()
        model.padlockOpen = closingPadlock
        var widgets = Set(layout.widgets.map(\.widget))
        if layout.calendar != nil { widgets.insert(.calendar) }
        if layout.player != nil { widgets.insert(.nowPlaying) }
        let gates = NotchLockScreenModel.Gates(
            music: NotchLockScreenSupport.showsMusic(), timer: NotchTimerSupport.isEnabled(),
            agents: NotchAgentSupport.showsLiveActivity(),
            downloads: NotchSupport.routes(.download), countdown: NotchCalendarSupport.showsCountdown(),
            timeLeft: NotchCalendarSupport.showsTimeLeft(), widgets: widgets,
            hidesEventTitles: NotchLockScreenSupport.hidesEventTitles(), privacy: NotchLockScreenSupport.agentPrivacy())
        if model.gates != gates { model.gates = gates }
        let privacy = gates.privacy
        var scene: [NotchLockScreenPanel] = []
        // Without the Music section there is no player to show or to click.
        // Its buttons and timeline are one of three things that take the
        // pointer, along with scrolling Agents at work and hovering Streak.
        if gates.music, let frame = layout.player, let fit = layout.playerFit {
            let glow = NotchLockScreenLayout.playerGlow
            scene.append(Self.makePanel(frame: frame.insetBy(dx: -glow, dy: -glow), interactive: true,
                                        content: NotchLockScreenPlayer(model: model, fit: fit, size: frame.size)
                                            .padding(glow)))
        }
        // Everything else is read-only, so every click passes to the lock screen.
        if let frame = layout.calendar {
            scene.append(Self.makePanel(frame: frame, content: NotchLockScreenCalendarCard(
                hidesTitles: gates.hidesEventTitles, size: frame.size)))
        }
        for panel in layout.panels {
            let content: AnyView
            switch panel.widgets.first?.widget {
            case .agents: content = AnyView(NotchLockScreenAgentsAtWork(size: panel.frame.size, privacy: privacy))
            case .streak: content = AnyView(NotchLockScreenStreak(size: panel.frame.size, privacy: privacy))
            case let widget? where widget.place == .mac:
                content = AnyView(NotchLockScreenMacRail(size: panel.frame.size, widgets: panel.widgets))
            default:
                content = AnyView(NotchLockScreenAICards(size: panel.frame.size, widgets: panel.widgets, privacy: privacy))
            }
            scene.append(Self.makePanel(frame: panel.frame, interactive: panel.interactive, content: content))
        }
        if let frame = layout.row {
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
        if !scene.isEmpty { startSources(gates) }
        // What moves on the moon wallpaper, over the still frame and under
        // every widget: shown first, so the widgets are ordered over it.
        if let live = NotchLockWallpaper.liveScene() {
            scene.insert(Self.makePanel(frame: live.frame, content: NotchLockWallpaperLayer(scene: live.scene)), at: 0)
        }
        let panels = scene + [island].compactMap { $0 }
        guard !panels.isEmpty else { space.close(); return }
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
        // A display attached or rearranged while locked moves the clock, the
        // login controls and the camera; the scene and the padlock follow.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.space != nil, Self.frames() != self.shownFrames else { return }
                self.hide(unlocking: false, stopsSources: false)
                self.show(closingPadlock: false)
            }
    }

    /// What This Mac's widgets read from the system monitor, only for those
    /// shown: memory brings its pressure, the GPU its temperature, and
    /// accessories are polled only for their card. The feature hub still
    /// gates each family, as it does for every surface.
    static func macNeeds(_ widgets: Set<NotchLockScreenWidget>) -> SystemMonitorPanelNeeds {
        SystemMonitorPanelNeeds(
            network: widgets.contains(.network), power: widgets.contains(.battery), cpu: widgets.contains(.cpu),
            gpu: widgets.contains(.gpu), memory: widgets.contains(.memory), battery: widgets.contains(.battery),
            peripheralBattery: widgets.contains(.accessories), cpuTemperature: widgets.contains(.cpu),
            gpuTemperature: widgets.contains(.gpu), fanSpeed: widgets.contains(.cpu))
    }

    /// Claude's and Codex's cards count as the AI page shown, so their limits
    /// refresh as they do in the open island.
    private static func showsLimits(_ gates: NotchLockScreenModel.Gates) -> Bool {
        gates.widgets.contains(.claude) || gates.widgets.contains(.codex)
    }

    private func startSources(_ gates: NotchLockScreenModel.Gates) {
        if gates.music { NotchMusicService.shared.start() }
        if gates.downloads { NotchDownloadService.shared.syncWithPreferences() }
        // An event chosen from its menu counts down with the countdown for every event off.
        if gates.countdown || gates.timeLeft || gates.calendar || !NotchCalendarSupport.chosenCountdowns().isEmpty {
            NotchCalendarService.shared.syncWithPreferences()
        }
        if gates.agents || gates.page { AgentUsageService.shared.syncWithPreferences() }
        if Self.showsLimits(gates) { AgentUsageService.shared.pageDidAppear() }
        if gates.widgets.contains(.codex) { CodexProfileLimitsService.shared.pageDidAppear() }
        if gates.mac { SystemMonitor.shared.setLockScreenNeeds(Self.macNeeds(gates.widgets)) }
    }

    private func hide(unlocking: Bool, stopsSources: Bool) {
        // Before the island returns on unlocking, so an AI page it opens on
        // reports itself shown after the lock screen's rail has left.
        if space != nil, Self.showsLimits(model.gates) { AgentUsageService.shared.pageDidDisappear() }
        if space != nil, model.gates.widgets.contains(.codex) { CodexProfileLimitsService.shared.pageDidDisappear() }
        // The island takes the monitor back with its own needs as it returns.
        if space != nil, model.gates.mac { SystemMonitor.shared.setLockScreenNeeds(.none) }
        if stopsSources, !scene.isEmpty {
            NotchMusicService.shared.stop()
            NotchDownloadService.shared.stop()
            NotchCalendarService.shared.stop()
            AgentUsageService.shared.pause()
        }
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
        // An interactive panel takes the pointer only where it draws. Left
        // unset, a window lets clicks through its clear pixels, so the room
        // around the player's pane and a player with no song pass them to
        // the lock screen beneath.
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
