// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import IOKit
import IOKit.hidsystem

/// Turns Caps Lock into one key that holds the user's chosen modifiers.
///
/// Two halves make it work. The keyboard mapping table turns Caps Lock into
/// F18, because a lock key never reports going down and up and so can never be
/// held; the event tap then keeps that key to itself and adds the user's
/// chosen modifiers to whatever is pressed while it is down. Nothing is
/// installed while the feature is off, and the mapping is always taken back
/// out when the feature goes off or the app quits. Requires Accessibility:
/// without it the tap cannot modify events, and the mapping is not applied
/// either, so Caps Lock is never left as a key that does nothing.
final class SuperKeyService: ObservableObject {
    static let shared = SuperKeyService()

    /// True while the key is actually working: tap up and mapping applied.
    @Published private(set) var isRunning = false
    /// What stopped the mapping, while it is stopped. The feature has several
    /// reasons to refuse, and none of them is visible in the key itself.
    @Published private(set) var mappingFailure: SuperKeyMappingFailure?
    @Published private(set) var modifiers = SuperKeySupport.defaultModifiers

    /// Read by the shortcut recording tap, which sits ahead of this one while a
    /// field is listening and would otherwise see the bare trigger key instead
    /// of the combination it stands for. Written and read on the main thread.
    private(set) static var isEngaged = false

    /// A held gesture can follow this virtual modifier. True means the key was
    /// released; false means the hold was cancelled by teardown or recovery.
    var onHoldEnded: ((_ released: Bool) -> Void)?
    var isHeld: Bool { stateLock.withLock { state.isHeld } }

    private let hidutilPath = "/usr/bin/hidutil"
    /// Matches every keyboard, including one plugged in later.
    private let keyboardMatch = "keyboard"

    // The active tap must answer every key before the window server can deliver
    // it. A user-interactive run loop keeps that answer independent from UI,
    // window enumeration and every other main-thread task.
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var mouseTap: CFMachPort?
    /// How many times in a row the mouse tap was asked for and refused. A
    /// refusal is otherwise indistinguishable from never having asked, and the
    /// keyboard half would keep working with drag chords quietly still broken.
    /// Only the first one counts as a dead tap: the cure is a full rebuild, and
    /// that takes the healthy keyboard tap down with it, dropping held-key
    /// state and letting events through untapped for the gap. A system that
    /// refuses once refuses the retry too, so one is all it is worth — after
    /// that the mouse half stays broken and the keyboard half is left alone.
    /// Back to zero only when a tap is actually created, so a refusal after a
    /// working stretch is a new episode with its own single retry.
    private var mouseTapRefusals = 0
    /// The presses the mouse tap watches, one list for both the tap mask and
    /// classify, so a button added later is added in one place.
    private static let mouseDownTypes: [CGEventType] = [
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingTapRestart = false
    private let stateLock = NSLock()
    private var state = SuperKeySupport.State()
    private var soloAction: SuperKeySoloAction = .none
    private var eventModifiers = SuperKeySupport.defaultModifiers
    private var wakeObserver: NSObjectProtocol?
    /// The mapping is written off the main thread, and in the order it was
    /// asked for: a queue of one keeps an apply and a clear from crossing.
    private let mappingQueue = DispatchQueue(label: "com.vorssaint.utils.superkey-mapping")
    /// When the last mapping went in, so a keyboard that arrives without one
    /// is repaired once and not on every keystroke.
    private var lastMappingAt: TimeInterval = 0
    /// A stop requested while an apply is queued must enqueue a clear behind
    /// it, even though the persistent marker is not written until readback.
    private var pendingMappingEnableCount = 0
    private let mappingRepairInterval: TimeInterval = 3
    /// Lets go of a press whose release never arrived. Without it the chosen
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
        let action = SuperKeySoloAction.sanitized(
            defaults.string(forKey: DefaultsKey.superKeySoloAction)
        )
        let modifiers = SuperKeySupport.modifiers(
            from: defaults.string(forKey: DefaultsKey.superKeyModifiers)
        )
        stateLock.withLock {
            soloAction = action
            eventModifiers = modifiers
        }
        self.modifiers = modifiers
        let enabled = AppFeature.superKey.isAvailable
            && defaults.bool(forKey: DefaultsKey.superKeyEnabled)
        guard enabled else {
            stop()
            return
        }
        // A tap the system disabled (Accessibility revoked and granted again)
        // never revives on its own; rebuild it instead of keeping the corpse.
        // A mouse tap the system refused counts as dead too, or it would stay
        // missing for the rest of the run with nothing to notice — but only
        // the first refusal does, or every sync from here on would tear the
        // working keyboard tap down to ask a question already answered.
        let deadTap = lifecycleLock.withLock { () -> Bool in
            let keyboardDead = tap.map { !CGEvent.tapIsEnabled(tap: $0) } ?? false
            let mouseDead = mouseTap.map { !CGEvent.tapIsEnabled(tap: $0) }
                ?? (mouseTapRefusals == 1)
            return keyboardDead || mouseDead
        }
        if deadTap {
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
        let tapExists = lifecycleLock.withLock { tap != nil && !shouldStopTapThread }
        guard !tapExists else { return }
        // Without Accessibility the tap cannot add the modifiers, and a
        // mapping alone would turn Caps Lock into a dead key. One left by a
        // run that was killed comes out here too: with the feature still
        // enabled, the launch-time stop() that normally clears it never runs.
        guard AXIsProcessTrusted() else {
            clearLeftoverMapping()
            isRunning = false
            return
        }
        forgetHeldKey()
        let thread = lifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingTapRestart = true }
                return nil
            }
            shouldStopTapThread = false
            pendingTapRestart = false
            let thread = Thread { [weak self] in self?.runEventTap() }
            thread.name = "Vorssaint Super Key"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func stop(synchronously: Bool = false) {
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, mouseTap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingTapRestart = false
            return (tapRunLoop, tap, mouseTap, tapThread != nil)
        }
        if let tap = snapshot.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let mouseTap = snapshot.mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: false) }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        forgetHeldKey()
        Self.isEngaged = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        clearLeftoverMapping(synchronously: synchronously)
        isRunning = false
        setMappingFailure(nil)
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { tapRunLoop = runLoop }
            guard !lifecycleLock.withLock({ shouldStopTapThread }) else {
                if clearEventTapThread() { startOnMain() }
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
                    let service = Unmanaged<SuperKeyService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let stillStopped = self.lifecycleLock.withLock {
                        self.tap == nil && self.tapThread == nil
                    }
                    guard stillStopped else { return }
                    self.clearLeftoverMapping()
                    self.isRunning = false
                    Self.isEngaged = false
                }
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock { self.tap = tap }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            // Mouse button presses need the modifiers too — a drag chord like
            // "move and resize by dragging" reads them off the mouse-down, not
            // off any keyboard event (#888). They are stamped from a separate
            // tap at the HID stage, which runs before every session tap
            // regardless of creation order, so consumers in this process and
            // clicks delivered to other apps both see the held modifiers.
            // Moves and drags stay out of the mask: chords are read on the
            // press, and per-move tap work is a known stutter source. Middle,
            // back and forward are in: their consumers read the button number
            // and set their own flags on anything they send on, so a stamped
            // press changes nothing for them and every mouse shortcut is
            // reached by the same chord as every other click.
            let mouseMask = Self.mouseDownTypes.reduce(CGEventMask(0)) {
                $0 | (CGEventMask(1) << $1.rawValue)
            }
            let mouseTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mouseMask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<SuperKeyService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            var mouseSource: CFRunLoopSource?
            lifecycleLock.withLock {
                self.mouseTap = mouseTap
                self.mouseTapRefusals = mouseTap == nil ? self.mouseTapRefusals + 1 : 0
            }
            if let mouseTap {
                mouseSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mouseTap, 0)
                CFRunLoopAddSource(runLoop, mouseSource, .commonModes)
                CGEvent.tapEnable(tap: mouseTap, enable: true)
            }

            DispatchQueue.main.async { [weak self] in self?.tapDidStart(tap) }
            if lifecycleLock.withLock({ shouldStopTapThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
                if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: false) }
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if let mouseTap {
                CGEvent.tapEnable(tap: mouseTap, enable: false)
                if let mouseSource { CFRunLoopRemoveSource(runLoop, mouseSource, .commonModes) }
                CFMachPortInvalidate(mouseTap)
            }
            if clearEventTapThread() { startOnMain() }
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingTapRestart
            tap = nil
            mouseTap = nil
            // mouseTapRefusals deliberately stays: it has to outlive the
            // teardown its own count asked for, or the rebuild it triggers
            // would clear the count and ask again for the rest of the run.
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingTapRestart = false
            return shouldRestart
        }
    }

    private func startOnMain() {
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    private func tapDidStart(_ startedTap: CFMachPort) {
        let active = lifecycleLock.withLock {
            tap === startedTap && !shouldStopTapThread
        }
        guard active else { return }
        confirmMapping(for: startedTap, publishingRunState: true)
    }

    /// The mapping is cleared even when this service never applied it: an
    /// app that was killed while the feature was on leaves one behind, and
    /// every path that ends without a live tap takes it out, so Caps Lock is
    /// never left as a key that does nothing.
    private func clearLeftoverMapping(synchronously: Bool = false) {
        let mappingMayBeApplied = UserDefaults.standard.bool(
            forKey: DefaultsKey.superKeyMappingApplied
        ) || stateLock.withLock { pendingMappingEnableCount > 0 }
        if mappingMayBeApplied {
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
            guard let self,
                  let activeTap = self.lifecycleLock.withLock({
                      self.shouldStopTapThread ? nil : self.tap
                  })
            else { return }
            self.confirmMapping(for: activeTap, publishingRunState: false)
        }
    }

    // MARK: - The key mapping

    private func applyMapping(_ enabled: Bool,
                              synchronously: Bool = false,
                              completion: ((SuperKeyMappingFailure?) -> Void)? = nil) {
        stateLock.withLock {
            lastMappingAt = ProcessInfo.processInfo.systemUptime
            if enabled { pendingMappingEnableCount += 1 }
        }
        let work = { [weak self] in
            guard let self else { return }
            let defaults = UserDefaults.standard
            let previousMarker = defaults.bool(forKey: DefaultsKey.superKeyMappingApplied)
            let failure = self.performMapping(
                enabled,
                ownsExistingMapping: previousMarker
            )
            if !enabled {
                let marker = SuperKeySupport.mappingMarkerAfterClear(
                    previous: previousMarker,
                    readbackConfirmed: failure == nil
                )
                defaults.set(marker, forKey: DefaultsKey.superKeyMappingApplied)
            }
            if enabled {
                self.stateLock.withLock { self.pendingMappingEnableCount -= 1 }
            }
            if let completion {
                DispatchQueue.main.async { completion(failure) }
            }
        }
        if synchronously {
            mappingQueue.sync(execute: work)
        } else {
            mappingQueue.async(execute: work)
        }
    }

    /// Applies or clears the mapping, and answers with the reason it could not
    /// be done, or nil when it was.
    ///
    /// The Modifier Keys rules are not read: hidd keeps
    /// `HIDKeyboardModifierMappingPairs` per client connection, so asking for
    /// it from here answers null whatever the user set in System Settings.
    private func performMapping(_ enabled: Bool,
                                ownsExistingMapping: Bool) -> SuperKeyMappingFailure? {
        let report = Shell.run(
            hidutilPath,
            ["property", "--matching", keyboardMatch,
             "--get", SuperKeySupport.userMappingProperty]
        )
        guard report.status == 0 else { return .systemRefused }
        guard let existing = SuperKeySupport.consistentMappings(
            report.output,
            property: SuperKeySupport.userMappingProperty,
            ownsExistingMapping: ownsExistingMapping
        ) else { return .foreignMapping }
        guard !enabled || !SuperKeySupport.hasMappingConflict(
            in: existing,
            ownsExistingMapping: ownsExistingMapping
        )
        else { return .foreignMapping }
        let wanted = SuperKeySupport.mappings(
            enablingSuperKey: enabled,
            existing: existing,
            ownsExistingMapping: ownsExistingMapping
        )
        if !enabled, !ownsExistingMapping,
           SuperKeySupport.mappingsMatch(existing, wanted) { return nil }
        if enabled {
            // Recovery is write-ahead only after every external-mapping check
            // passed. A crash after the command starts must leave the next
            // launch authorized to remove a possibly partial application.
            UserDefaults.standard.set(true, forKey: DefaultsKey.superKeyMappingApplied)
        }
        let write = Shell.run(
            hidutilPath,
            ["property", "--matching", keyboardMatch,
             "--set", SuperKeySupport.mappingArgument(wanted)]
        )
        guard write.status == 0 else { return .systemRefused }
        let readback = Shell.run(
            hidutilPath,
            ["property", "--matching", keyboardMatch,
             "--get", SuperKeySupport.userMappingProperty]
        )
        guard readback.status == 0 else { return .systemRefused }
        return SuperKeySupport.mappingReportConfirms(readback.output, expected: wanted)
            ? nil
            : .systemRefused
    }

    private func confirmMapping(for expectedTap: CFMachPort, publishingRunState: Bool) {
        applyMapping(true) { [weak self] failure in
            guard let self else { return }
            let active = self.lifecycleLock.withLock {
                self.tap === expectedTap && !self.shouldStopTapThread
            }
            guard active else { return }
            guard let failure else {
                self.setMappingFailure(nil)
                if publishingRunState || !self.isRunning { self.finishStart() }
                return
            }
            // A repair that fails leaves the tap up so the next keystroke can
            // try again. The key is not working, so isRunning goes false and
            // the page can show the reason. stop() would clear that reason.
            if publishingRunState {
                self.stop()
            } else {
                self.isRunning = false
            }
            self.setMappingFailure(failure)
        }
    }

    private func finishStart() {
        // Caps Lock left on would have no way back once the key stops locking.
        setCapsLock(false)
        observeWake()
        isRunning = true
        Self.isEngaged = true
    }

    /// Repair runs every few seconds while typing; republishing an unchanged
    /// reason would redraw Settings just as often.
    private func setMappingFailure(_ failure: SuperKeyMappingFailure?) {
        guard mappingFailure != failure else { return }
        mappingFailure = failure
    }

    /// A keyboard that arrives after the mapping was applied still locks; the
    /// first press on it is the signal to map it too. Repaired at most once
    /// every few seconds, so a keyboard that refuses the mapping cannot turn
    /// typing into a stream of commands.
    private func repairMappingIfStale() {
        guard let activeTap = lifecycleLock.withLock({
            shouldStopTapThread ? nil : tap
        }) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let shouldRepair = stateLock.withLock {
            now - lastMappingAt >= mappingRepairInterval
        }
        if shouldRepair {
            confirmMapping(for: activeTap, publishingRunState: false)
        }
    }

    // MARK: - The tap

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTaps = lifecycleLock.withLock {
                shouldStopTapThread ? (nil, nil) : (tap, mouseTap)
            }
            if let currentTap = currentTaps.0 { CGEvent.tapEnable(tap: currentTap, enable: true) }
            if let currentMouseTap = currentTaps.1 { CGEvent.tapEnable(tap: currentMouseTap, enable: true) }
            forgetHeldKey()
            return Unmanaged.passUnretained(event)
        }
        let event0 = SuperKeyService.classify(type: type, event: event)
        let decision = stateLock.withLock { state.decide(event0) }
        // Only the key's own events say it is still down: the first press and
        // the repeats the system sends while it is held. Keys pressed meanwhile
        // must NOT push the deadline out. Someone whose keyboard is stuck under
        // a press that never lifted is typing, and letting that typing hold the
        // deadline open would keep it stuck for exactly as long as they kept
        // trying to get out of it.
        switch event0 {
        case .triggerDown:
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.lifecycleLock.withLock({
                          self.tap != nil && !self.shouldStopTapThread
                      }),
                      self.stateLock.withLock({ self.state.isHeld })
                else { return }
                self.armHeldKeyWatchdog()
            }
        case .triggerUp:
            DispatchQueue.main.async { [weak self] in
                self?.cancelHeldKeyWatchdog()
                self?.onHoldEnded?(true)
            }
        case .otherKey, .otherModifier, .capsLock:
            break
        }
        switch decision {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .addModifiers:
            let modifierFlags = stateLock.withLock { eventModifiers.cgFlags }
            event.flags = event.flags.union(modifierFlags)
            return Unmanaged.passUnretained(event)
        case .soloTap(repeated: let repeated):
            performSoloAction(longHold: false, repeated: repeated)
            return nil
        case .soloHold(repeated: let repeated):
            performSoloAction(longHold: true, repeated: repeated)
            return nil
        case .interceptAndRemap:
            repairMappingIfStale()
            // At the session tap the missing mapping may already have flipped
            // the lock state. Keep that raw event out of apps and put Caps
            // Lock back off while the keyboard mapping is repaired.
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.lifecycleLock.withLock({
                          self.tap != nil && !self.shouldStopTapThread
                      })
                else { return }
                self.setCapsLock(false)
            }
            return nil
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

    /// Back to the key being up. State resets synchronously; UI callbacks stay
    /// on the main thread.
    private func forgetHeldKey() {
        let wasHeld = stateLock.withLock { () -> Bool in
            let held = state.isHeld
            state.reset()
            return held
        }
        let notify = { [weak self] in
            self?.cancelHeldKeyWatchdog()
            if wasHeld { self?.onHoldEnded?(false) }
        }
        if Thread.isMainThread {
            notify()
        } else {
            DispatchQueue.main.async(execute: notify)
        }
    }

    private static func classify(type: CGEventType, event: CGEvent) -> SuperKeySupport.Event {
        // A mouse press while the key is held behaves like any other key: the
        // modifiers ride along and the press cancels the solo action. Answered
        // above the keycode read on purpose: a mouse event carries no keycode
        // and the field reads back as 0 on one, which is the keycode for A.
        // Kept here, no caller can hand that phantom key to anything.
        if mouseDownTypes.contains(type) { return .otherKey }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged {
            return keyCode == SuperKeySupport.capsLockKeyCode ? .capsLock : .otherModifier
        }
        guard keyCode == SuperKeySupport.triggerKeyCode else { return .otherKey }
        if type == .keyDown {
            return .triggerDown(
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                hasPrimaryModifiers: !GlobalShortcutModifiers(cgFlags: event.flags).isEmpty,
                timestamp: UInt64(event.timestamp)
            )
        }
        return .triggerUp(timestamp: UInt64(event.timestamp))
    }

    // MARK: - Tapped on its own

    private func performSoloAction(longHold: Bool, repeated: Bool) {
        let action = stateLock.withLock { soloAction }
        switch SuperKeySupport.soloEffect(action: action,
                                          longHold: longHold,
                                          repeated: repeated) {
        case .none:
            return
        case .escape:
            runOnMainIfNeeded { _ = Self.postKey(CGKeyCode(kVK_Escape)) }
        case .capsLock:
            runOnMainIfNeeded { self.setCapsLock(!self.capsLockIsOn()) }
        case .inputSource:
            // Must finish before this tap returns: the next keystroke is already
            // in flight, and hopping to main (or waiting on Accessibility) left
            // that character in the old source.
            Self.selectNextInputSource()
        }
    }

    private func runOnMainIfNeeded(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private static func postKey(_ keyCode: CGKeyCode) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    /// Cycle enabled keyboard sources through TIS before the tap lets the next
    /// key through. An earlier path asked another app for marked text (up to
    /// 200 ms) and then slept 100 ms so Control-Space could commit IME
    /// composition; that wait ran on every tap, including ones with nothing to
    /// commit. Selecting the next source directly lets the input method commit
    /// or cancel on its own, the same way the Input menu does.
    private static func selectNextInputSource() {
        let apply = {
            let sources = selectableInputSources()
            let ids = sources.compactMap { inputSourceString($0, property: kTISPropertyInputSourceID) }
            guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
            let currentID = inputSourceString(current, property: kTISPropertyInputSourceID)
            guard let nextID = SuperKeySupport.nextInputSourceID(currentID: currentID,
                                                                 enabledIDs: ids),
                  let next = sources.first(where: {
                      inputSourceString($0, property: kTISPropertyInputSourceID) == nextID
                  })
            else { return }
            _ = TISSelectInputSource(next)
        }
        // TIS talks to the text-input server from the main thread. sync (not
        // async) keeps the switch ahead of the next keystroke this tap is
        // about to let through.
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync(execute: apply)
        }
    }

    private static func selectableInputSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false) else { return [] }
        let values = list.takeRetainedValue() as NSArray
        return (values as! [TISInputSource]).filter {
            inputSourceString($0, property: kTISPropertyInputSourceCategory)
                == kTISCategoryKeyboardInputSource as String
                && inputSourceBool($0, property: kTISPropertyInputSourceIsSelectCapable)
        }
    }

    private static func inputSourceString(_ source: TISInputSource,
                                          property: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func inputSourceBool(_ source: TISInputSource,
                                        property: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
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
