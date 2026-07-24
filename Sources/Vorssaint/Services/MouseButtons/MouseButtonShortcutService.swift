// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics

/// Types a keyboard shortcut when an extra mouse button is pressed. The
/// mapped button's click is the shortcut's alone: the whole gesture is
/// consumed, so the app under the pointer never sees the press it used to
/// get (the Settings caption promises exactly that). Nothing is installed
/// while the feature is off or while no button is mapped. Requires
/// Accessibility for the modifying event tap and the posted keys.
final class MouseButtonShortcutService: ObservableObject {
    static let shared = MouseButtonShortcutService()

    /// True while the tap is up and the mapped buttons actually fire.
    @Published private(set) var isRunning = false
    /// The last extra mouse button that arrived while Settings was asking
    /// for one. Nil means nothing has arrived yet.
    @Published private(set) var lastButtonSeen: Int64?

    /// True while the Settings capture row is listening for a press. The
    /// other button-owning taps (navigation at the HID level, the radial
    /// menu's summoner) read this and let every extra button through, so the
    /// press being captured reaches this service instead of navigating or
    /// opening the wheel. Main thread only, like the taps that read it.
    private(set) static var isCaptureActive = false

    private var mappings: [Int64: GlobalShortcut] = [:]
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Set only while the Settings capture row is on screen. The tap stays up
    /// during capture even with no mappings yet, so the row can see the press.
    private var isCapturing = false
    /// Buttons whose current press was consumed. The Up and Drag of a gesture
    /// must follow its Down: a mapping removed mid-press must not let half a
    /// gesture leak to the app underneath. Only touched from the tap
    /// callback, which runs on the main run loop.
    private var consumedButtons: Set<Int64> = []
    /// True while the tap only exists to swallow the pending Up of a button
    /// whose Down it consumed; no new press is claimed in this state.
    private var isDraining = false

    private init() {}

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = AppFeature.mouseButtonShortcuts.isAvailable
            && defaults.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled)
        mappings = MouseButtonShortcutSupport.decode(
            defaults.dictionary(forKey: DefaultsKey.mouseButtonShortcuts) as? [String: String])
        let wanted = enabled && (!mappings.isEmpty || isCapturing)
        guard wanted else {
            stop()
            return
        }
        isDraining = false
        // A tap the system disabled (Accessibility revoked and regranted)
        // never revives on its own; rebuild it instead of keeping the corpse.
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            stop()
        }
        start()
    }

    func suspend() { stop() }

    /// Starts and stops reporting which extra button arrives, for the
    /// Settings capture row. Syncs on both edges: the way in may need to
    /// raise the tap before the first mapping exists, and the way out drops
    /// it again when nothing is mapped.
    func setCapturing(_ capturing: Bool) {
        guard isCapturing != capturing else { return }
        isCapturing = capturing
        Self.isCaptureActive = capturing
        lastButtonSeen = nil
        syncWithPreferences()
    }

    private func start() {
        guard tap == nil else {
            isRunning = true
            return
        }
        guard AXIsProcessTrusted() else {
            isRunning = false
            return
        }
        // The session tap runs after the HID-level navigation tap, which
        // already lets a button this feature claims pass through whole.
        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseDragged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MouseButtonShortcutService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isRunning = false
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func stop() {
        // A button whose Down this tap consumed must have its Up consumed by
        // the same tap, or the app under the pointer receives half a click.
        // With a claimed button still physically held, the tap stays alive
        // in drain mode until the release arrives (handle() finishes the
        // teardown), instead of dying between the halves. This also covers
        // ending a capture right after the first press.
        if !consumedButtons.isEmpty, tap != nil {
            isDraining = true
            isRunning = false
            return
        }
        tearDownTap()
    }

    private func tearDownTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        consumedButtons.removeAll()
        isDraining = false
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        if type == .otherMouseDown {
            if isDraining {
                return Unmanaged.passUnretained(event)
            }
            if isCapturing {
                // The capture row reports every extra button, even one it
                // will refuse, so it can explain instead of leaving the user
                // guessing. The press itself belongs to the capture: letting
                // it through would navigate, open a system overlay bound to
                // that button, or fire its old mapping while the user is
                // rearranging buttons. Only the middle button, which cannot
                // be captured, keeps working.
                lastButtonSeen = button
                guard MouseButtonShortcutSupport.canMap(button) else {
                    return Unmanaged.passUnretained(event)
                }
                consumedButtons.insert(button)
                return nil
            }
            guard let shortcut = MouseButtonShortcutSupport.firesShortcut(
                for: button,
                isAvailable: AppFeature.mouseButtonShortcuts.isAvailable,
                isEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled),
                mappings: mappings,
                claimedByWheel: RadialMenuSupport.claimsMouseButton)
            else { return Unmanaged.passUnretained(event) }
            consumedButtons.insert(button)
            post(shortcut)
            return nil
        }

        // Up and Drag follow their Down's decision, so a mapping edited
        // mid-press can never split a gesture in half.
        guard consumedButtons.contains(button) else {
            return Unmanaged.passUnretained(event)
        }
        if type == .otherMouseUp {
            consumedButtons.remove(button)
            // The drain existed only for this release; finishing outside the
            // callback keeps the mach port teardown off the tap's own stack.
            if isDraining, consumedButtons.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isDraining, self.consumedButtons.isEmpty else { return }
                    self.tearDownTap()
                }
            }
        }
        return nil
    }

    /// The shortcut goes out as a virtual key plus modifier flags, nothing
    /// more. No keyboardSetUnicodeString: a forced character string on a
    /// shortcut event breaks menu key equivalent dispatch in the target app,
    /// so the combination would arrive and still do nothing.
    private func post(_ shortcut: GlobalShortcut) {
        guard shortcut.hasUsableKeyCode else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: CGKeyCode(shortcut.keyCode),
                                 keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: CGKeyCode(shortcut.keyCode),
                               keyDown: false) else { return }
        down.flags = shortcut.modifiers.cgFlags
        up.flags = shortcut.modifiers.cgFlags
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
