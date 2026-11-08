// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog

final class KeyboardRemappingService: ObservableObject {
    static let shared = KeyboardRemappingService()

    @Published private(set) var isRunning = false
    @Published private(set) var tapStatus = KeyboardRemappingTapStatus.inactive

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "KeyboardRemapping")

    private let eventLock = NSLock()
    private let lifecycleLock = NSLock()
    private var enabled = false
    private var rules: [KeyboardRemappingRule] = []
    private var frontmostBundleIdentifier: String?
    private var captureInProgress = false
    private var heldMappings: [Int64: (KeyboardRemappingRule, GlobalShortcutModifiers)] = [:]
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    private var lifecycleGeneration: UInt = 0
    private var workspaceObserver: NSObjectProtocol?

    private init() {
        frontmostBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.eventLock.withLock {
                self?.frontmostBundleIdentifier = app.bundleIdentifier
            }
        }
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let nextRules = KeyboardRemappingConfig.decode(
            defaults.string(forKey: DefaultsKey.keyboardRemappingRules) ?? "[]"
        )
        let nextEnabled = AppFeature.keyRemapping.isAvailable
            && defaults.bool(forKey: DefaultsKey.keyboardRemappingEnabled)
            && nextRules.contains { $0.enabled && $0.isValid }
        eventLock.withLock {
            enabled = nextEnabled
            rules = nextRules
        }

        if SessionActivitySupport.tapShouldRun(featureWanted: nextEnabled,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    func setCaptureInProgress(_ capturing: Bool) {
        eventLock.withLock {
            captureInProgress = capturing
        }
    }

    func suspend() {
        stop()
    }

    private func start() {
        let startState = lifecycleLock.withLock {
            () -> (Thread?, UInt) in
            if tapThread != nil {
                if shouldStopTapThread {
                    pendingStartAfterStop = true
                    return (nil, lifecycleGeneration)
                }
                return (nil, lifecycleGeneration)
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            let generation = lifecycleGeneration
            let thread = Thread { [weak self] in
                self?.runEventTap(generation: generation)
            }
            thread.name = "Vorssaint Keyboard Remapping"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return (thread, generation)
        }
        if let thread = startState.0 {
            publishTapStatus(.starting, generation: startState.1)
            thread.start()
        }
    }

    private func stop() {
        eventLock.withLock {
            heldMappings.removeAll()
        }
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool, generation: UInt) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            return (tapRunLoop, tap, tapThread != nil, lifecycleGeneration)
        }
        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
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
        publishTapStatus(.inactive, generation: snapshot.generation)
    }

    private func runEventTap(generation: UInt) {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock {
                tapRunLoop = runLoop
            }
            guard !lifecycleLock.withLock({ shouldStopTapThread }) else {
                finishEventTapThread(generation: generation)
                return
            }

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
                | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<KeyboardRemappingService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                finishEventTapThread(generation: generation)
                Self.log.error("Could not create the keyboard remapping event tap.")
                publishTapStatus(
                    KeyboardRemappingTapStatus.afterTapCreation(succeeded: false),
                    generation: generation
                )
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            if lifecycleLock.withLock({ shouldStopTapThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                publishTapStatus(
                    KeyboardRemappingTapStatus.afterTapCreation(succeeded: true),
                    generation: generation
                )
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            finishEventTapThread(generation: generation)
        }
    }

    private func finishEventTapThread(generation: UInt) {
        let shouldRestart = lifecycleLock.withLock {
            let restart = pendingStartAfterStop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return restart
        }
        if shouldRestart {
            start()
        } else {
            publishTapStatus(.inactive, generation: generation)
        }
    }

    private func publishTapStatus(_ status: KeyboardRemappingTapStatus, generation: UInt) {
        let update = { [weak self] in
            guard let self,
                  self.lifecycleLock.withLock({ generation == self.lifecycleGeneration })
            else { return }
            self.tapStatus = status
            self.isRunning = status == .active
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTap = lifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else if currentTap != nil {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard KeyboardRemappingRisk.handles(eventType: type, keyCode: keyCode),
              !OwnKeyEvent.isPosted(event) else {
            return Unmanaged.passUnretained(event)
        }

        let isModifierEvent = type == .flagsChanged
        let isKeyDown = !isModifierEvent
            || CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode))
        if type == .keyUp || (isModifierEvent && !isKeyDown) {
            let wasMapped = eventLock.withLock { heldMappings.removeValue(forKey: keyCode) != nil }
            return wasMapped ? nil : Unmanaged.passUnretained(event)
        }

        let eventDetails = eventLock.withLock {
            () -> (KeyboardRemappingRule, GlobalShortcutModifiers, Bool)? in
            guard enabled, !captureInProgress else { return nil }
            if let held = heldMappings[keyCode] { return (held.0, held.1, false) }
            let modifiers = GlobalShortcutModifiers(cgFlags: event.flags)
            guard let rule = KeyboardRemappingConfig.matchingRule(
                keyCode: keyCode,
                modifiers: modifiers,
                bundleIdentifier: frontmostBundleIdentifier,
                rules: rules
            ) else { return nil }
            let outputModifiers = isModifierEvent
                ? modifiers.subtracting(KeyboardRemappingRisk.modifierForSourceKeyCode(keyCode) ?? [])
                : modifiers
            heldMappings[keyCode] = (rule, outputModifiers)
            return (rule, outputModifiers, true)
        }
        guard let (rule, incomingModifiers, isFirstKeyDown) = eventDetails else {
            return Unmanaged.passUnretained(event)
        }
        let succeeded: Bool
        switch rule.resolvedActionKind {
        case .keySequence:
            succeeded = !isFirstKeyDown || post(rule.output, matching: rule, incomingModifiers: incomingModifiers)
        case .typeText:
            succeeded = !isFirstKeyDown || post(text: rule.text)
        case .openLink:
            if isFirstKeyDown { open(link: rule.link) }
            succeeded = true
        case .openApp:
            if isFirstKeyDown { open(appBundleIdentifier: rule.appBundleIdentifier) }
            succeeded = true
        case .disabled:
            succeeded = true
        }
        if !succeeded {
            _ = eventLock.withLock { heldMappings.removeValue(forKey: keyCode) }
            return Unmanaged.passUnretained(event)
        }
        return nil
    }

    private func post(_ chords: [KeyboardRemappingChord],
                      matching rule: KeyboardRemappingRule,
                      incomingModifiers: GlobalShortcutModifiers) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        var events: [CGEvent] = []
        for chord in chords {
            let flags = KeyboardRemappingConfig.outputModifiers(
                for: chord,
                matching: rule,
                incoming: incomingModifiers
            ).cgFlags
            guard let down = CGEvent(keyboardEventSource: source,
                                     virtualKey: CGKeyCode(chord.keyCode),
                                     keyDown: true),
                  let up = CGEvent(keyboardEventSource: source,
                                   virtualKey: CGKeyCode(chord.keyCode),
                                   keyDown: false)
            else { return false }
            for event in [down, up] {
                event.flags = flags
                event.setIntegerValueField(.eventSourceUserData, value: OwnKeyEvent.keyboardRemappingMarker)
                events.append(event)
            }
        }
        events.forEach { $0.post(tap: .cghidEventTap) }
        return true
    }

    private func post(text: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        for scalar in text.unicodeScalars {
            let characters = Array(String(scalar).utf16)
            guard !characters.isEmpty,
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return false }
            characters.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            }
            for event in [down, up] {
                event.setIntegerValueField(.eventSourceUserData, value: OwnKeyEvent.keyboardRemappingMarker)
                event.post(tap: .cghidEventTap)
            }
        }
        return true
    }

    private func open(link: String) {
        guard let url = URL(string: link) else { return }
        DispatchQueue.main.async {
            guard NSWorkspace.shared.open(url) else {
                Self.log.error("Could not open a URL from a keyboard remapping rule.")
                NSSound.beep()
                return
            }
        }
    }

    private func open(appBundleIdentifier: String) {
        DispatchQueue.main.async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleIdentifier) else {
                Self.log.error("Could not find the app named in a keyboard remapping rule.")
                NSSound.beep()
                return
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                guard error != nil else { return }
                Self.log.error("Could not open an app from a keyboard remapping rule.")
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
    }
}
