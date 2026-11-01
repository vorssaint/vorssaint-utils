// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

/// Turns the Globe key into a predictable input source switcher: one press
/// lands on the layout the single press names, two presses on the double
/// press layout, a long press opens the keyboard settings. Nothing cycles.
///
/// The tap only listens. With "Press Globe key to" set to Do Nothing the key
/// produces no output of its own, so no event ever needs swallowing — the tap
/// watches the `maskSecondaryFn` flag turn on and off, and the machine in
/// `GlobeKeyMachine` decides whether the press was a clean gesture. Requires
/// Accessibility: without it the system refuses to create the tap.
final class GlobeKeyService: ObservableObject {
    static let shared = GlobeKeyService()

    /// True while the tap is up and the feature is listening.
    @Published private(set) var isRunning = false
    /// The system refused to create the tap, which without Accessibility it
    /// always does. Settings reads this to ask for the permission instead of
    /// leaving the feature silently dead.
    @Published private(set) var tapRefused = false

    // The tap must answer every event promptly. A user-interactive run loop
    // on its own thread keeps that answer independent from UI work, the same
    // shape the Super key tap uses.
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingTapRestart = false

    private let stateLock = NSLock()
    private var machine = GlobeKeyMachine()
    private var mapping = GlobeGestureMapping.fallback
    /// The one timer serving the machine's current deadline: the long-press
    /// check while the key is down, the multi-press deadline after a release.
    private var pendingTimer: DispatchWorkItem?
    private var scheduledDeadline: UInt64?

    private var sessionObservation: AnyCancellable?

    /// The bit `CGEventType` has no case for in Swift: NSSystemDefined, the
    /// events media keys arrive as. While the Globe key is down, one of these
    /// means a chord (Globe+brightness), not a gesture.
    private static let systemDefinedRawValue: UInt32 = 14
    /// The keycode macOS synthesizes for the Globe key itself: a key down and
    /// key up with this code arrive the instant the flag comes back up, as an
    /// echo of the very press we just counted. Reading them as typing would
    /// cancel every finished press before its multi-press deadline, so they
    /// are dropped before they reach the machine.
    private static let globeKeycode: Int64 = 179
    private static let tapMask: CGEventMask = {
        var mask = CGEventMask(1) << CGEventType.keyDown.rawValue
            | CGEventMask(1) << CGEventType.keyUp.rawValue
            | CGEventMask(1) << CGEventType.flagsChanged.rawValue
        mask |= CGEventMask(1) << systemDefinedRawValue
        return mask
    }()

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        mapping = Self.mapping(from: defaults)
        let enabled = AppFeature.globeKey.isAvailable
            && defaults.bool(forKey: DefaultsKey.globeKeyEnabled)
            && SessionActivity.shared.isActive
        guard enabled else {
            stop()
            return
        }
        // A tap the system disabled (Accessibility revoked and granted again)
        // never revives on its own; rebuild it instead of keeping the corpse.
        let deadTap = lifecycleLock.withLock { tap.map { !CGEvent.tapIsEnabled(tap: $0) } ?? false }
        if deadTap { stop() }
        start()
    }

    private static func mapping(from defaults: UserDefaults) -> GlobeGestureMapping {
        GlobeGestureMapping(
            singlePress: GlobeKeyAction.sanitized(
                defaults.string(forKey: DefaultsKey.globeKeySinglePressAction)),
            doublePress: GlobeKeyAction.sanitized(
                defaults.string(forKey: DefaultsKey.globeKeyDoublePressAction)),
            triplePress: GlobeKeyAction.sanitized(
                defaults.string(forKey: DefaultsKey.globeKeyTriplePressAction)),
            longPress: GlobeKeyAction.sanitized(
                defaults.string(forKey: DefaultsKey.globeKeyLongPressAction))
        )
    }

    private func start() {
        let tapExists = lifecycleLock.withLock { tap != nil && !shouldStopTapThread }
        guard !tapExists else { return }
        guard AXIsProcessTrusted() else {
            tapRefused = true
            isRunning = false
            return
        }
        tapRefused = false
        let thread = lifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingTapRestart = true }
                return nil
            }
            shouldStopTapThread = false
            pendingTapRestart = false
            let thread = Thread { [weak self] in self?.runEventTap() }
            thread.name = "Vorssaint Globe Key"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func stop() {
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingTapRestart = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            return (tapRunLoop, tap, tapThread != nil)
        }
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
        stateLock.withLock {
            machine.reset()
            cancelTimerLocked()
        }
        isRunning = false
        tapRefused = false
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { tapRunLoop = runLoop }
            guard !lifecycleLock.withLock({ shouldStopTapThread }) else {
                if clearEventTapThread() { startOnMain() }
                return
            }

            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: Self.tapMask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<GlobeKeyService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.lifecycleLock.withLock({ self.tap == nil && self.tapThread == nil })
                    else { return }
                    self.tapRefused = true
                    self.isRunning = false
                }
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock { self.tap = tap }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            DispatchQueue.main.async { [weak self] in
                self?.isRunning = true
            }
            if lifecycleLock.withLock({ shouldStopTapThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if clearEventTapThread() { startOnMain() }
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingTapRestart
            tap = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingTapRestart = false
            return shouldRestart
        }
    }

    private func startOnMain() {
        DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
    }

    // MARK: - The tap

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let currentTap = lifecycleLock.withLock({ shouldStopTapThread ? nil : tap }) {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        let keyEvent: GlobeKeyEvent?
        if type.rawValue == Self.systemDefinedRawValue {
            keyEvent = .otherEvent
        } else {
            switch type {
            case .flagsChanged:
                let hasFunctionFlag = event.flags.contains(.maskSecondaryFn)
                let wasDown = stateLock.withLock { machine.fnIsDown }
                if hasFunctionFlag != wasDown {
                    keyEvent = hasFunctionFlag
                        ? .fnDown(hasPrimaryModifiers: !GlobalShortcutModifiers(cgFlags: event.flags).isEmpty,
                                  timestamp: EventTimestamp.nanoseconds(of: event))
                        : .fnUp(timestamp: EventTimestamp.nanoseconds(of: event))
                } else {
                    // Another modifier changing state while the key sits still.
                    keyEvent = .otherEvent
                }
            case .keyDown, .keyUp:
                if event.getIntegerValueField(.keyboardEventKeycode) == Self.globeKeycode {
                    keyEvent = nil
                } else {
                    keyEvent = .otherEvent
                }
            default:
                keyEvent = nil
            }
        }
        if let keyEvent {
            let actions: [GlobePressInterpreter.Action] = stateLock.withLock {
                let actions = machine.handle(keyEvent)
                syncTimerLocked()
                return actions
            }
            if !actions.isEmpty { perform(actions) }
        }
        // The tap only listens: every event carries on untouched.
        return Unmanaged.passUnretained(event)
    }

    // MARK: - The deadline timer

    /// Must run with `stateLock` held: it owns `pendingTimer` and
    /// `scheduledDeadline`. The machine publishes one deadline at a time, so
    /// one work item serves it; a deadline that moved is cancelled and rearmed.
    private func syncTimerLocked() {
        let deadline = machine.pendingDeadline
        if deadline == scheduledDeadline { return }
        cancelTimerLocked()
        guard let deadline else { return }
        scheduledDeadline = deadline
        let work = DispatchWorkItem { [weak self] in self?.timerFired() }
        pendingTimer = work
        let now = DispatchTime.now().uptimeNanoseconds
        let delay = deadline > now ? Double(deadline - now) / 1_000_000_000.0 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelTimerLocked() {
        pendingTimer?.cancel()
        pendingTimer = nil
        scheduledDeadline = nil
    }

    private func timerFired() {
        let now = DispatchTime.now().uptimeNanoseconds
        let actions: [GlobePressInterpreter.Action] = stateLock.withLock {
            guard !shouldStopTapThread else { return [] }
            let actions = machine.tick(at: now)
            syncTimerLocked()
            return actions
        }
        perform(actions)
    }

    // MARK: - What gestures do

    private func perform(_ actions: [GlobePressInterpreter.Action]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for action in actions {
                guard let gesture = Self.gesture(of: action) else { continue }
                self.perform(self.mapping.action(for: gesture))
            }
        }
    }

    private static func gesture(of action: GlobePressInterpreter.Action) -> GlobeGesture? {
        switch action {
        case .singlePress: .singlePress
        case .doublePress: .doublePress
        case .triplePress: .triplePress
        case .longPress: .longPress
        }
    }

    private func perform(_ action: GlobeKeyAction) {
        switch action {
        case .none:
            return
        case .inputSource(let sourceID):
            // The island notices the switch on its own: it watches the same
            // system notification the Input menu speaks through.
            _ = InputSourceSelection.select(sourceID: sourceID)
        case .openKeyboardSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
