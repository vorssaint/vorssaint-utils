// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// Eye-Guard runs a work/break cycle and, when the break falls due, fades every
/// screen to black for its length.
///
/// The break screen is a shielding-level panel, never a change to the display
/// itself: a window dies with the process, where a dimmed or gamma-shifted
/// display outlives a crash and has to be undone by something that is no longer
/// running.
///
/// Every timing decision lives in `EyeGuardSchedule` so it can be tested without
/// a screen; this type only starts a timer, renders the phase it is handed and
/// owns the panels.
final class EyeGuardService: ObservableObject {
    static let shared = EyeGuardService()

    /// kCGAnyInputEventType — the most recent of every input kind rather than
    /// one of them, so reading a book on screen still counts as idle.
    private static let anyInputEventType = CGEventType(rawValue: ~0)!

    @Published private(set) var phase: EyeGuardPhase = .working

    private var timer: Timer?
    private var cycleStart = ProcessInfo.processInfo.systemUptime
    private var overlays: [NSPanel] = []
    private var screenObserver: NSObjectProtocol?

    private init() {
        // A switched-away session must not hold a break screen over the account
        // actually in use, and the cycle it was counting is no longer this
        // user's time. Coming back starts a fresh work period.
        SessionActivity.shared.onChange { [weak self] active in
            guard let self, self.timer != nil else { return }
            if active {
                self.startCycle()
            } else {
                self.endBreak()
            }
        }
    }

    // MARK: - Preferences

    var isEnabled: Bool {
        AppFeature.eyeGuard.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.eyeGuardEnabled)
    }

    var timing: (work: TimeInterval, breakLength: TimeInterval) {
        let defaults = UserDefaults.standard
        return EyeGuardSchedule.timing(
            preset: EyeGuardPreset.sanitized(defaults.string(forKey: DefaultsKey.eyeGuardPreset)),
            customWorkMinutes: defaults.integer(forKey: DefaultsKey.eyeGuardWorkMinutes),
            customBreakSeconds: defaults.integer(forKey: DefaultsKey.eyeGuardBreakSeconds)
        )
    }

    /// Re-read after any change to availability or the preferences above. A
    /// timing change restarts the cycle rather than measuring the new length
    /// against a start that belonged to the old one.
    func syncWithPreferences() {
        guard isEnabled else {
            stop()
            return
        }
        startCycle()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // A second of slack lets the system coalesce this with other wakeups;
        // the cycle is minutes long, so nothing here needs a punctual tick.
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        endBreak()
    }

    /// Restarts the work period. Also the "break taken" path, so skipping and
    /// finishing a break land in the same place.
    private func startCycle() {
        cycleStart = ProcessInfo.processInfo.systemUptime
        endBreak()
    }

    func skipBreak() {
        startCycle()
    }

    // MARK: - Cycle

    private func tick() {
        guard isEnabled else {
            stop()
            return
        }
        // A break screen over a session that is not on screen would be shown to
        // whoever switched in, so the cycle only advances while this one is.
        guard SessionActivity.shared.isActive else { return }

        let timing = self.timing
        let elapsed = ProcessInfo.processInfo.systemUptime - cycleStart
        if EyeGuardSchedule.cycleIsComplete(elapsed: elapsed,
                                            work: timing.work,
                                            breakLength: timing.breakLength) {
            startCycle()
            return
        }

        let next = EyeGuardSchedule.phase(elapsed: elapsed,
                                          work: timing.work,
                                          breakLength: timing.breakLength)
        if case .onBreak = next {} else if idleCountsAsBreak(timing.breakLength) {
            // Away from the keyboard for at least a break's worth: that break
            // has happened, so the work period starts over rather than blacking
            // the screen at somebody who just sat back down.
            startCycle()
            return
        }

        apply(next)
    }

    private func idleCountsAsBreak(_ breakLength: TimeInterval) -> Bool {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: Self.anyInputEventType)
        return EyeGuardSchedule.idleCountsAsBreak(idle: idle, breakLength: breakLength)
    }

    private func apply(_ next: EyeGuardPhase) {
        let wasOnBreak = isOnBreak(phase)
        let isOnBreakNow = isOnBreak(next)
        phase = next
        if isOnBreakNow, !wasOnBreak {
            showOverlays()
        } else if !isOnBreakNow, wasOnBreak {
            endBreak()
        }
    }

    private func isOnBreak(_ phase: EyeGuardPhase) -> Bool {
        if case .onBreak = phase { return true }
        return false
    }

    private func endBreak() {
        phase = .working
        hideOverlays()
    }

    // MARK: - Overlay

    private func showOverlays() {
        let frames = NSScreen.screens.map(\.frame)
        let targetFrames = frames.isEmpty
            ? [NSRect(x: 0, y: 0, width: 800, height: 600)]
            : frames
        // Screen notifications arrive in bursts even when the frames are
        // unchanged, so panels are reused rather than rebuilt: a fresh panel
        // would restart the fade and flash the desktop back for a frame.
        var reusable = overlays
        overlays = targetFrames.map { frame in
            if let index = reusable.firstIndex(where: { $0.frame == frame }) {
                return reusable.remove(at: index)
            }
            return makeOverlay(frame: frame)
        }
        reusable.forEach { $0.orderOut(nil) }
        installScreenObserver()
    }

    private func makeOverlay(frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // The shielding level macOS uses for its own lock-style windows, so the
        // break covers full-screen apps and the menu bar too.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = OverlayHostingView(rootView: EyeGuardOverlayView())
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        // Fading in from nothing is the whole point of a gentle break screen,
        // but Reduce Motion means cut rather than animate.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.6
                panel.animator().alphaValue = 1
            }
        }
        return panel
    }

    private func hideOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
        removeScreenObserver()
    }

    private func installScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isOnBreak(self.phase) else { return }
            self.showOverlays()
        }
    }

    private func removeScreenObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    /// Accepts the first click into a non-key, non-activating panel, so Skip
    /// fires on the very first press instead of being eaten as the click that
    /// would otherwise activate the window.
    private final class OverlayHostingView: NSHostingView<EyeGuardOverlayView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
