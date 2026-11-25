// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Hides the pointer once it has been still for a while, so a screen left
/// mid-thought does not keep an arrow parked on it. The idle reading is the
/// window server's own "seconds since the last mouse move" counter rather than
/// an event tap: a tap needs Accessibility, and an invisible cursor must never
/// be recoverable only through a permission the user may have declined.
///
/// Four deliberate escapes guarantee no one is ever stranded, and every one of
/// them calls the show path with nothing consulted — no threshold, no flag, no
/// notion of whether this service is even enabled:
///   1. any pointer movement,
///   2. any key press,
///   3. the displays going to sleep,
///   4. the screen locking.
/// A session resign and a normal quit show it too, so leaving the app the
/// ordinary way cannot leave the pointer gone either.
final class PointerHideService: ObservableObject {
    static let shared = PointerHideService()

    /// How often the idle counter is sampled. One second is under the shortest
    /// threshold the range allows, so the cursor never overshoots the user's
    /// setting by a visible margin.
    private static let tickInterval: TimeInterval = 1
    /// Hiding a cursor is not worth waking a laptop for. The leeway lets the
    /// scheduler coalesce ticks with whatever else the machine is doing.
    private static let tickTolerance: TimeInterval = 0.2
    private static let screenLockNotification = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlockNotification = Notification.Name("com.apple.screenIsUnlocked")

    /// Whether the user asked for this. Nothing reads it on an escape path,
    /// so a switch flipped off mid-session still hands back a hidden cursor.
    @Published private(set) var isEnabled: Bool
    /// Whether this service is the reason the cursor is currently gone. Reads
    /// false for a cursor hidden by anything else, which is exactly the case
    /// the escapes still recover.
    @Published private(set) var isHiding: Bool

    /// Seconds of pointer stillness before the cursor is hidden, already clamped
    /// to `PointerHideSupport.thresholdRange`.
    var threshold: Double { storedThreshold }

    private var storedThreshold: Double
    /// The previous idle reading. The counter only ever grows, so a reading
    /// lower than the last one means input landed in between — that is the
    /// movement signal, and it is why no event tap is needed to see it.
    private var previousIdleSeconds: TimeInterval?
    private var timer: Timer?
    private var keyMonitor: Any?
    /// Held only so the tokens are not dropped; a singleton outlives every
    /// notification it cares about, so they are never removed.
    private var observers: [NSObjectProtocol] = []
    private var displayAsleep = false
    private var screenLocked = false

    private init() {
        let stored = UserDefaults.standard.object(forKey: DefaultsKey.pointerHideIdleSeconds) as? NSNumber
        storedThreshold = PointerHideSupport.sanitizedThreshold(
            stored?.doubleValue ?? PointerHideSupport.defaultThreshold)
        screenLocked = KeepAwakeAutomationSupport.isScreenLocked(
            sessionDictionary: CGSessionCopyCurrentDictionary() as? [String: Any])
        isEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.pointerHideIdleEnabled)
        isHiding = false
        if isEnabled {
            // Restored late rather than inline: this singleton is built on
            // first touch, which is not guaranteed to be the main thread, and
            // the timer below has to be scheduled on the main run loop.
            DispatchQueue.main.async { [weak self] in self?.start() }
        }
        // These outlive the timer on purpose. They are the stranding
        // guarantees, and a display that sleeps or a screen that locks while
        // this service is switched off still has to be able to hand back a
        // cursor somebody else hid. They cost a handful of notifications a
        // session; the key monitor below would cost a window-server round trip
        // on every keystroke in every app, so that one is scoped to `isEnabled`.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            self?.displayAsleep = true
            self?.showCursor()
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            self?.displayAsleep = false
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                              object: nil, queue: .main) { [weak self] _ in
            self?.showCursor()
        })
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Self.screenLockNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
            self?.showCursor()
        })
        observers.append(distributed.addObserver(forName: Self.screenUnlockNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.showCursor()
        })
    }

    func setThreshold(_ value: Double) {
        let sanitized = PointerHideSupport.sanitizedThreshold(value)
        storedThreshold = sanitized
        UserDefaults.standard.set(sanitized, forKey: DefaultsKey.pointerHideIdleSeconds)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.pointerHideIdleEnabled)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    // MARK: Lifecycle

    private func start() {
        guard timer == nil else { return }
        previousIdleSeconds = nil
        // A global monitor is the cheapest permission-free way to see a key
        // press; a CGEventTap was rejected here because it would make an
        // invisible cursor recoverable only through an Accessibility grant the
        // user may have declined. Its real limitation is that it is blind while
        // this app is frontmost, which is why the tick below refuses to hide in
        // that case rather than trusting an escape it cannot see.
        if keyMonitor == nil {
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
                self?.showCursor()
            }
        }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = Self.tickTolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        previousIdleSeconds = nil
        if isHiding { showCursor() }
    }

    // MARK: Decision

    private func tick() {
        let idle = Self.secondsSincePointerActivity()
        let pointerMoved = previousIdleSeconds.map { idle < $0 } ?? false
        previousIdleSeconds = idle

        if PointerHideSupport.shouldShow(pointerMoved: pointerMoved, keyPressed: false,
                                         displayAsleep: displayAsleep, screenLocked: screenLocked) {
            showCursor()
            return
        }
        // The global key monitor is blind while this app is frontmost, so a
        // cursor hidden here would have nobody left to bring it back. Being
        // frontmost is therefore itself an escape, not a hiding window.
        if NSApp.isActive {
            showCursor()
            return
        }
        // A cursor is only ever hidden in the session actually on screen: a
        // switched-away session belongs to a machine nobody is looking at, and
        // the window server there is not the one whose display we touched.
        // Not deciding is no safer either, so this shows rather than leaving a
        // hidden cursor behind in a session no longer in use.
        if !SessionActivity.shared.isActive {
            showCursor()
            return
        }
        guard PointerHideSupport.shouldHide(idleSeconds: idle, thresholdEnabled: isEnabled,
                                            threshold: storedThreshold, pointerMoved: pointerMoved)
        else {
            // Undoing this service's own hide. Every escape has already returned
            // above, so the only hide left to reverse is one this service began.
            if isHiding { showCursor() }
            return
        }
        hideCursor()
    }

    private static func secondsSincePointerActivity() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
    }

    // MARK: Cursor

    /// Unconditional: nothing here reads the threshold, the feature state or
    /// how long the cursor has been hidden. The only guard is on writing the
    /// published flag, so an already-visible cursor is not reported as a change
    /// — the window server call itself always happens, which is what lets this
    /// recover a cursor hidden by anything, not only by this service.
    private func showCursor() {
        for display in Self.activeDisplays() {
            _ = CGDisplayShowCursor(display)
        }
        guard isHiding else { return }
        isHiding = false
    }

    private func hideCursor() {
        guard !isHiding else { return }
        for display in Self.activeDisplays() {
            _ = CGDisplayHideCursor(display)
        }
        isHiding = true
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
