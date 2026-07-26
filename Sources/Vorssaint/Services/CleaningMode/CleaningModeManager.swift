// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// "Cleaning mode" temporarily locks the keyboard so the user can wipe it down
/// without typing gibberish, then restores it on a deliberate gesture. The lock
/// is a HID-level event tap that swallows key events before the system handles
/// them, including keyboard system keys such as brightness, media and volume.
/// The very same tap watches for the unlock gesture, so there is always a way
/// back.
///
/// Three independent escapes guarantee no one is ever stranded:
///   1. press the same key five times in a row (deliberate, unlike random wiping),
///   2. click Unlock on the overlay (the mouse is never locked),
///   3. an automatic timeout after a minute.
///
/// Requires Accessibility, like the app's other event taps. If it is missing the
/// tap can't be created, so we never lock the keyboard with no way to unlock it.
final class CleaningModeManager: ObservableObject {
    static let shared = CleaningModeManager()

    private static let systemDefinedEventType = CGEventType(rawValue: CleaningSystemKeyEvent.systemDefinedEventTypeRawValue)!

    @Published private(set) var isActive = false
    /// Consecutive presses of the current key so far (0...unlockThreshold). The
    /// overlay shows this as progress.
    @Published private(set) var unlockProgress = 0

    /// Deliberate presses of one key needed to unlock. Random wiping hits many
    /// different keys, which keeps resetting the count, so it won't unlock by
    /// accident while the keyboard is being cleaned.
    let unlockThreshold = 5

    /// Failsafe: the keyboard always comes back on its own after this long, even
    /// if the overlay is somehow missed.
    private let autoUnlockSeconds: TimeInterval = 60

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlays: [NSPanel] = []
    private var screenObserver: NSObjectProtocol?
    private var autoUnlockTimer: Timer?

    /// The unlock-gesture state machine (pure, unit-tested separately).
    private lazy var unlock = CleaningUnlockCounter(threshold: unlockThreshold, pressWindow: 2.0)

    private init() {}

    func toggle() { isActive ? deactivate() : activate() }

    /// Starts the lock. No-op (and guides the user) when Accessibility is missing,
    /// because without the tap there would be no way to unlock the keyboard.
    func activate() {
        guard !isActive else { return }
        // Check Accessibility explicitly (same gate the other event taps use) so a
        // missing grant is reported clearly, rather than inferred from a nil tap.
        guard Permissions.shared.accessibility else {
            promptForAccessibility()
            return
        }
        guard installTap() else { return }
        // Debounce must not filter while the lock is up: its tap can run ahead
        // of ours (head-insert order depends on creation order) and would eat
        // the repeated same-key presses the unlock gesture counts on.
        KeyboardDebounceService.shared.suspend()
        // Wiping the trackpad is nothing but stray three-finger contacts;
        // middle-click emulation must not fire from them.
        MiddleClickService.shared.suspend()
        MouseNavigationService.shared.suspend()
        // A stray side-button press while wiping the mouse must not type a
        // key combination into the frontmost app (the synthesized keys are
        // posted below this lock's keyboard tap) nor open the wheel over
        // the cleaning overlay.
        MouseButtonShortcutService.shared.suspend()
        RadialMenuService.shared.suspend()
        unlock.reset()
        unlockProgress = 0
        isActive = true
        installScreenObserver()
        showOverlays()
        // Add the failsafe to .common modes (not just the default mode) so it still
        // fires while a tracking or modal run-loop is active — matching the tap's
        // own run-loop source, so the 60 s "always unlocks" guarantee always holds.
        let timer = Timer(timeInterval: autoUnlockSeconds, repeats: false) { [weak self] _ in
            self?.deactivate()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoUnlockTimer = timer
    }

    func deactivate() {
        guard isActive else { return }
        removeTap()
        autoUnlockTimer?.invalidate()
        autoUnlockTimer = nil
        removeScreenObserver()
        hideOverlays()
        unlock.reset()
        unlockProgress = 0
        isActive = false
        // Restore debounce and middle click if the user still has them enabled.
        KeyboardDebounceService.shared.syncWithPreferences()
        MiddleClickService.shared.syncWithPreferences()
        MouseNavigationService.shared.syncWithPreferences()
        MouseButtonShortcutService.shared.syncWithPreferences()
        RadialMenuService.shared.syncWithPreferences()
    }

    // MARK: - Event tap

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << Self.systemDefinedEventType.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<CleaningModeManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    /// The tap callback. Its run-loop source lives on the main run loop, so this
    /// runs on the main thread and can touch published state and AppKit directly.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables taps that stall or when the session locks; re-arm so
        // the keyboard stays locked instead of silently coming back.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        // Feed key-downs to the unlock state machine. Auto-repeat (holding a key)
        // is ignored, so only distinct, deliberate taps of the same key count.
        if type == .keyDown {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            registerUnlockKeyDown(code: code, isRepeat: isRepeat)
        } else if type == Self.systemDefinedEventType,
                  let systemKey = systemKeyEvent(from: event),
                  systemKey.isKeyDown {
            registerUnlockKeyDown(code: systemKey.code, isRepeat: systemKey.isRepeat)
        }

        // Swallow every key event while the lock is on.
        return nil
    }

    private func systemKeyEvent(from event: CGEvent) -> CleaningSystemKeyEvent? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
        return CleaningSystemKeyEvent.decode(subtype: Int(nsEvent.subtype.rawValue),
                                             data1: nsEvent.data1)
    }

    private func registerUnlockKeyDown(code: Int64, isRepeat: Bool) {
        let unlocked = unlock.registerKeyDown(code: code,
                                              time: ProcessInfo.processInfo.systemUptime,
                                              isRepeat: isRepeat)
        unlockProgress = unlock.progress
        if unlocked {
            // Defer so we don't tear down the tap from inside its own callback.
            DispatchQueue.main.async { [weak self] in self?.deactivate() }
        }
    }

    // MARK: - Overlay

    private func showOverlays() {
        hideOverlays()
        let frames = NSScreen.screens.map(\.frame)
        let targetFrames = frames.isEmpty
            ? [NSRect(x: 0, y: 0, width: 800, height: 600)]
            : frames
        overlays = targetFrames.map(makeOverlay(frame:))
    }

    private func makeOverlay(frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // Above the menu bar and full-screen apps — the shielding level macOS uses
        // for its own lock-style windows.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // acceptsFirstMouse so the Unlock button fires on the very first click even
        // though the panel never becomes key or activates the app — otherwise that
        // click would just be absorbed as the window-activating click.
        let host = OverlayHostingView(rootView: CleaningOverlayView())
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()
        return panel
    }

    private func hideOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
    }

    private func installScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard self?.isActive == true else { return }
            self?.showOverlays()
        }
    }

    private func removeScreenObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    /// Hosting view that accepts the first click into the (non-key, non-activating)
    /// overlay panel, so the Unlock button works without a throwaway activating click.
    private final class OverlayHostingView: NSHostingView<CleaningOverlayView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private func promptForAccessibility() {
        let strings = L10n.shared.s
        let alert = NSAlert()
        alert.messageText = strings.cleaningNeedsAxTitle
        alert.informativeText = strings.cleaningNeedsAxBody
        alert.addButton(withTitle: strings.permissionOpenSettings)
        alert.addButton(withTitle: strings.uninstallerCancel)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.shared.requestAccessibility()
            Permissions.shared.openAccessibilitySettings()
        }
    }
}
