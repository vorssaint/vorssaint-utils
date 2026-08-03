// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import IOKit
import IOKit.hidsystem

/// Turns Caps Lock into one key that holds Shift, Control, Option and Command
/// together, so shortcuts built on it collide with nothing else.
///
/// Two halves make it work. The keyboard mapping table turns Caps Lock into
/// F18, because a lock key never reports going down and up and so can never be
/// held; the event tap then keeps that key to itself and adds the four
/// modifiers to whatever is pressed while it is down. Nothing is installed
/// while the feature is off, and the mapping is always taken back out, both
/// when the feature goes off and when the app quits. Requires Accessibility:
/// without it the tap cannot modify events, and the mapping is not applied
/// either, so Caps Lock is never left as a key that does nothing.
final class SuperKeyService: ObservableObject {
    static let shared = SuperKeyService()

    /// True while the key is actually working: tap up and mapping applied.
    @Published private(set) var isRunning = false

    /// Read by the shortcut recording tap, which sits ahead of this one while a
    /// field is listening and would otherwise see the bare trigger key instead
    /// of the combination it stands for. Main thread only, like both taps.
    private(set) static var isEngaged = false

    /// A held gesture can follow this virtual modifier. True means the key was
    /// released; false means the hold was cancelled by teardown or recovery.
    var onHoldEnded: ((_ released: Bool) -> Void)?
    var isHeld: Bool { state.isHeld }

    private let hidutilPath = "/usr/bin/hidutil"
    /// Matches every keyboard, including one plugged in later.
    private let keyboardMatch = "keyboard"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var state = SuperKeySupport.State()
    private var soloAction: SuperKeySoloAction = .none
    private var wakeObserver: NSObjectProtocol?
    /// The mapping is written off the main thread, and in the order it was
    /// asked for: a queue of one keeps an apply and a clear from crossing.
    private let mappingQueue = DispatchQueue(label: "com.vorssaint.utils.superkey-mapping")
    /// When the last mapping went in, so a keyboard that arrives without one
    /// is repaired once and not on every keystroke.
    private var lastMappingAt: TimeInterval = 0
    private let mappingRepairInterval: TimeInterval = 3
    /// Lets go of a press whose release never arrived. Without it the four
    /// modifiers would ride every keystroke from then on, with no way back but
    /// pressing the key again, and typing would be dead in the meantime.
    private var heldKeyWatchdog: DispatchWorkItem?
    /// How long the press may go without a repeat before it is let go. A key
    /// really held repeats, so this is pushed out again and again and never
    /// runs; it only decides how long a press whose release was lost can hold
    /// the modifiers down. Taken from the keyboard's own first-repeat delay, so
    /// a slow setting is never fought, and bounded at both ends: never so short
    /// that a hold is cut off, never so long that the keyboard stays unusable
    /// when repeat is switched off and no repeat is ever coming.
    private var heldKeyTimeout: TimeInterval {
        let firstRepeat = NSEvent.keyRepeatDelay
        guard firstRepeat.isFinite, firstRepeat > 0 else { return 3 }
        return min(30, max(3, firstRepeat * 2))
    }

    private init() {}

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        soloAction = SuperKeySoloAction.sanitized(defaults.string(forKey: DefaultsKey.superKeySoloAction))
        let enabled = AppFeature.superKey.isAvailable
            && defaults.bool(forKey: DefaultsKey.superKeyEnabled)
        guard enabled else {
            stop()
            return
        }
        // A tap the system disabled (Accessibility revoked and granted again)
        // never revives on its own; rebuild it instead of keeping the corpse.
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            stop()
        }
        start()
    }

    /// Quitting takes the mapping out on the spot: the process is about to go
    /// away, and a mapping left behind would leave Caps Lock doing nothing.
    func suspend() {
        stop(synchronously: true)
    }

    private func start() {
        guard tap == nil else {
            isRunning = true
            Self.isEngaged = true
            return
        }
        // Without Accessibility the tap cannot add the modifiers, and a
        // mapping alone would turn Caps Lock into a dead key. One left by a
        // run that was killed comes out here too: with the feature still
        // enabled, the launch-time stop() that normally clears it never runs.
        guard AXIsProcessTrusted() else {
            clearLeftoverMapping()
            isRunning = false
            return
        }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<SuperKeyService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            clearLeftoverMapping()
            isRunning = false
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        forgetHeldKey()
        applyMapping(true)
        // Caps Lock left on would have no way back once the key stops locking.
        setCapsLock(false)
        observeWake()
        isRunning = true
        Self.isEngaged = true
    }

    private func stop(synchronously: Bool = false) {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        forgetHeldKey()
        Self.isEngaged = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        clearLeftoverMapping(synchronously: synchronously)
        isRunning = false
    }

    /// The mapping is cleared even when this service never applied it: an
    /// app that was killed while the feature was on leaves one behind, and
    /// every path that ends without a live tap takes it out, so Caps Lock is
    /// never left as a key that does nothing.
    private func clearLeftoverMapping(synchronously: Bool = false) {
        if UserDefaults.standard.bool(forKey: DefaultsKey.superKeyMappingApplied) {
            applyMapping(false, synchronously: synchronously)
        }
    }

    /// Sleep can bring the keyboard back without the mapping, and so can
    /// plugging in another one. Waking is the cheap moment to put it back.
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.tap != nil else { return }
            self.applyMapping(true)
        }
    }

    // MARK: - The key mapping

    private func applyMapping(_ enabled: Bool, synchronously: Bool = false) {
        lastMappingAt = ProcessInfo.processInfo.systemUptime
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.superKeyMappingApplied)
        let work = { [hidutilPath, keyboardMatch] in
            let report = Shell.run(hidutilPath,
                                   ["property", "--matching", keyboardMatch, "--get", "UserKeyMapping"])
            let existing = SuperKeySupport.parseMappings(report.output)
            let wanted = SuperKeySupport.mappings(enablingSuperKey: enabled, existing: existing)
            Shell.run(hidutilPath,
                      ["property", "--matching", keyboardMatch,
                       "--set", SuperKeySupport.mappingArgument(wanted)])
        }
        if synchronously {
            mappingQueue.sync(execute: work)
        } else {
            mappingQueue.async(execute: work)
        }
    }

    /// A keyboard that arrives after the mapping was applied still locks; the
    /// first press on it is the signal to map it too. Repaired at most once
    /// every few seconds, so a keyboard that refuses the mapping cannot turn
    /// typing into a stream of commands.
    private func repairMappingIfStale() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMappingAt >= mappingRepairInterval else { return }
        applyMapping(true)
    }

    // MARK: - The tap

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            forgetHeldKey()
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let event0 = SuperKeyService.classify(type: type, keyCode: keyCode, event: event)
        let decision = state.decide(event0)
        // Only the key's own events say it is still down: the first press and
        // the repeats the system sends while it is held. Keys pressed meanwhile
        // must NOT push the deadline out. Someone whose keyboard is stuck under
        // a press that never lifted is typing, and letting that typing hold the
        // deadline open would keep it stuck for exactly as long as they kept
        // trying to get out of it.
        switch event0 {
        case .triggerDown:
            armHeldKeyWatchdog()
        case .triggerUp:
            cancelHeldKeyWatchdog()
            onHoldEnded?(true)
        case .otherKey, .otherModifier, .capsLock:
            break
        }
        switch decision {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .addModifiers:
            event.flags = event.flags.union(SuperKeyService.superFlags)
            return Unmanaged.passUnretained(event)
        case .soloTap:
            performSoloAction()
            return nil
        case .remapNeeded:
            repairMappingIfStale()
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - A press whose release never came

    private func armHeldKeyWatchdog() {
        heldKeyWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.forgetHeldKey() }
        heldKeyWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + heldKeyTimeout, execute: work)
    }

    private func cancelHeldKeyWatchdog() {
        heldKeyWatchdog?.cancel()
        heldKeyWatchdog = nil
    }

    /// Back to the key being up. Runs on the main thread, like the tap.
    private func forgetHeldKey() {
        cancelHeldKeyWatchdog()
        let wasHeld = state.isHeld
        state.reset()
        if wasHeld { onHoldEnded?(false) }
    }

    private static func classify(type: CGEventType, keyCode: Int64, event: CGEvent) -> SuperKeySupport.Event {
        if type == .flagsChanged {
            return keyCode == SuperKeySupport.capsLockKeyCode ? .capsLock : .otherModifier
        }
        guard keyCode == SuperKeySupport.triggerKeyCode else { return .otherKey }
        if type == .keyDown {
            return .triggerDown(isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        }
        return .triggerUp
    }

    private static let superFlags: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand,
    ]

    // MARK: - Tapped on its own

    private func performSoloAction() {
        switch soloAction {
        case .none:
            return
        case .escape:
            postEscape()
        case .capsLock:
            setCapsLock(!capsLockIsOn())
        }
    }

    private func postEscape() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else { return }
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    // MARK: - Caps Lock itself

    /// The lock state lives with the system's own keyboard service, which is
    /// also what lights the key.
    private func withHIDSystem<T>(_ body: (io_connect_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS
        else { return nil }
        defer { IOServiceClose(connection) }
        return body(connection)
    }

    private func capsLockIsOn() -> Bool {
        withHIDSystem { connection in
            var state = false
            guard IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS
            else { return nil }
            return state
        } ?? false
    }

    private func setCapsLock(_ on: Bool) {
        _ = withHIDSystem { connection in
            IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), on)
        }
    }
}
