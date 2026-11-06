// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics

/// Layout Fix: a tap of the trigger key retypes the last word, or the
/// selection, in another enabled keyboard layout and switches to it. The key
/// tap, the observers and the buffer only exist while the feature is on.
/// Requires Accessibility (the tap and the field checks).
final class LayoutFixService: ObservableObject {
    static let shared = LayoutFixService()

    @Published private(set) var isRunning = false

    // The tap callback and its state live off the main thread, like Text
    // Snippets, so a busy app in front cannot hold up the keyboard.
    private let tapLifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingTapRestart = false

    /// Everything the tap reads and writes, mirrored behind one lock so the
    /// callback never asks AppKit or the text input server.
    private let inputLock = NSLock()
    private var buffer = LayoutFixBuffer()
    private var triggerState = LayoutFixTriggerState(trigger: .rightOption)
    private var currentLayoutID: String?

    // Main thread only.
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private(set) var layouts: [LayoutFixLayout] = []
    private(set) var recency: [String] = []

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.layoutFix.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.layoutFixEnabled)
        let trigger = LayoutFixTrigger.sanitized(UserDefaults.standard.string(forKey: DefaultsKey.layoutFixTrigger))
        inputLock.withLock {
            if triggerState.trigger != trigger { triggerState = LayoutFixTriggerState(trigger: trigger) }
        }
        MouseAppExceptions.shared.setSourceTracking(enabled, for: .layoutFix)
        if SessionActivitySupport.tapShouldRun(featureWanted: enabled,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            startObserving()
            start()
        } else {
            stop()
        }
    }

    func suspend() { stop() }

    // MARK: - Mirrors

    private func startObserving() {
        refreshLayouts()
        noteCurrentLayout()
        guard observers.isEmpty, distributedObservers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in self?.noteCurrentLayout() })
        distributedObservers.append(distributed.addObserver(
            forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshLayouts() })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshLayouts() })
        // Switching apps invalidates whatever was half-typed there, except
        // when the Accessibility Keyboard comes forward to type into it.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == AssistiveKeyboard.bundleID { return }
            self?.resetBuffer()
        })
    }

    private func stopObserving() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributedObservers.removeAll()
    }

    /// The enabled layouts taking part, in the Input menu order.
    private func refreshLayouts() {
        let excluded = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.layoutFixExcludedLayouts) ?? [])
        let refreshed = Self.enabledLayouts().filter { !excluded.contains($0.id) }
        if refreshed != layouts { layouts = refreshed }
    }

    /// Every enabled keyboard layout with its key tables. Input methods have
    /// no key table and are left out.
    static func enabledLayouts() -> [LayoutFixLayout] {
        InputSourceSelection.selectableInputSources().compactMap { source in
            guard InputSourceSelection.inputSourceString(source, property: kTISPropertyInputSourceType)
                    == kTISTypeKeyboardLayout as String,
                  let id = InputSourceSelection.inputSourceString(source, property: kTISPropertyInputSourceID),
                  let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { return nil }
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            let language = InputSourceSelection.languages(of: source).first?
                .split(separator: "-").first.map(String.init) ?? ""
            return LayoutFixLayout(id: id, language: language,
                                   table: LayoutFixSupport.table(from: data, capsLock: false),
                                   capsTable: LayoutFixSupport.table(from: data, capsLock: true))
        }
    }

    private func noteCurrentLayout() {
        guard let id = InputSourceSelection.currentSourceID() else { return }
        inputLock.withLock { currentLayoutID = id }
        recency.removeAll { $0 == id }
        recency.insert(id, at: 0)
    }

    private func resetBuffer() {
        inputLock.withLock { buffer.apply(.reset, key: nil) }
    }

    /// The buffer as the tap sees it now, for a trigger that does not come
    /// from the tap: the Super key solo action and a recorded shortcut.
    func performExternalTrigger() {
        let snapshot = inputLock.withLock { (buffer.keys, buffer.generation) }
        performFix(snapshot: snapshot.0, generation: snapshot.1)
    }

    /// Runs one fix on the main thread.
    func performFix(snapshot: [LayoutFixKey], generation: UInt64) {}

    // MARK: - Tap lifecycle

    private func start() {
        let thread = tapLifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingTapRestart = true }
                return nil
            }
            shouldStopTapThread = false
            pendingTapRestart = false
            let thread = Thread { [weak self] in self?.runEventTap() }
            thread.name = "Vorssaint Layout Fix"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func stop() {
        let snapshot = tapLifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingTapRestart = false
            return (tapRunLoop, tap, tapThread != nil)
        }
        if let tap = snapshot.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            tapLifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        stopObserving()
        resetBuffer()
        if isRunning { isRunning = false }
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            tapLifecycleLock.withLock { tapRunLoop = runLoop }
            guard !tapLifecycleLock.withLock({ shouldStopTapThread }) else {
                if clearEventTapThread() { startOnMain() }
                return
            }

            let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.rightMouseDown.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<LayoutFixService>.fromOpaque(userInfo).takeUnretainedValue()
                    service.handle(type: type, event: event)
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            tapLifecycleLock.withLock { self.tap = tap }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            DispatchQueue.main.async { [weak self] in self?.tapDidStart(tap) }

            if tapLifecycleLock.withLock({ shouldStopTapThread }) {
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
        tapLifecycleLock.withLock {
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

    private func tapDidStart(_ startedTap: CFMachPort) {
        let active = tapLifecycleLock.withLock { tap === startedTap && !shouldStopTapThread }
        if isRunning != active { isRunning = active }
    }

    // MARK: - Tap

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTap = tapLifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else if currentTap != nil {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return
        }
        // Our own retyping, and every other key Vorssaint posts, is not typing.
        guard !OwnKeyEvent.isPosted(event) else { return }
        if type == .leftMouseDown || type == .rightMouseDown {
            // A click on the Accessibility Keyboard types a key and leaves
            // the caret alone; any other click moves it somewhere unknown.
            guard !AssistiveKeyboard.ownsPoint(event.location) else { return }
            inputLock.withLock {
                buffer.apply(.reset, key: nil)
                _ = triggerState.fires(.mouse)
            }
            return
        }
        // Password fields: nothing typed there is remembered.
        guard !IsSecureEventInputEnabled() else {
            resetBuffer()
            return
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if type == .flagsChanged {
            let timestamp = EventTimestamp.nanoseconds(of: event)
            let down = Self.modifierIsDown(keyCode: keyCode, flags: flags)
            let fired = inputLock.withLock { () -> (keys: [LayoutFixKey], generation: UInt64)? in
                let event: LayoutFixTriggerEvent = down
                    ? .modifierDown(keyCode: keyCode, timestamp: timestamp)
                    : .modifierUp(keyCode: keyCode, timestamp: timestamp)
                return triggerState.fires(event) ? (buffer.keys, buffer.generation) : nil
            }
            if let fired {
                DispatchQueue.main.async { [weak self] in
                    self?.performFix(snapshot: fired.keys, generation: fired.generation)
                }
            }
            return
        }
        guard type == .keyDown else { return }
        let action = LayoutFixSupport.bufferAction(keyCode: keyCode,
                                                   command: flags.contains(.maskCommand),
                                                   control: flags.contains(.maskControl))
        inputLock.withLock {
            _ = triggerState.fires(.otherKey)
            let key = LayoutFixKey(keyCode: UInt16(clamping: keyCode),
                                   shift: flags.contains(.maskShift),
                                   option: flags.contains(.maskAlternate),
                                   capsLock: flags.contains(.maskAlphaShift),
                                   layoutID: currentLayoutID ?? "")
            buffer.apply(action, key: action == .append ? key : nil)
        }
    }

    /// Whether a modifier key's flagsChanged event is its press. The flag of
    /// the key's own side is read where macOS reports it, so holding the left
    /// key does not make a tap of the right one look like a release.
    static func modifierIsDown(keyCode: Int, flags: CGEventFlags) -> Bool {
        let raw = flags.rawValue
        switch keyCode {
        case kVK_RightOption: return raw & UInt64(NX_DEVICERALTKEYMASK) != 0
        case kVK_Option: return raw & UInt64(NX_DEVICELALTKEYMASK) != 0
        case kVK_RightShift: return raw & UInt64(NX_DEVICERSHIFTKEYMASK) != 0
        case kVK_Shift: return raw & UInt64(NX_DEVICELSHIFTKEYMASK) != 0
        case kVK_RightCommand: return raw & UInt64(NX_DEVICERCMDKEYMASK) != 0
        case kVK_Command: return raw & UInt64(NX_DEVICELCMDKEYMASK) != 0
        case kVK_RightControl: return raw & UInt64(NX_DEVICERCTLKEYMASK) != 0
        case kVK_Control: return raw & UInt64(NX_DEVICELCTLKEYMASK) != 0
        default: return false
        }
    }
}
