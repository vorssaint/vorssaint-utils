// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Combine
import IOKit

/// Stops a press of the Touch ID / Power button from locking the Mac right
/// away. The tap only looks at system-defined events and passes everything but
/// the press itself, and only a press the built-in button sent: the same event
/// from a key on another keyboard reaches macOS untouched. In hold mode the
/// press is swallowed, the button's own state is polled for as long as it
/// stays down, and the screen is locked from here if the press outlasts the
/// chosen time. Nothing runs between presses.
final class TouchIDGuardService: ObservableObject {
    static let shared = TouchIDGuardService()

    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let pollQueue = DispatchQueue(label: "vorssaint.touchid-guard", qos: .userInitiated)
    /// Bumped on stop and on every new press so a poll that is still going
    /// can tell it has been replaced. Read from the poll queue, so locked.
    private let generationLock = NSLock()
    private var currentGeneration: UInt64 = 0
    /// Main thread only: the tap callback, the poll's completion and stop.
    private var holdInFlight = false
    private let hud = QuitProtectionHUD()

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    // MARK: Preferences

    var isEnabled: Bool {
        AppFeature.quitWindowProtection.isAvailable
            && Self.builtInButtonID != nil
            && UserDefaults.standard.bool(forKey: DefaultsKey.touchIDGuardEnabled)
    }

    /// The registry id of the built-in button's driver, nil on a Mac without
    /// one. Read once: the driver lives as long as the machine is up.
    static let builtInButtonID: UInt64? = {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching(TouchIDGuardSupport.builtInButtonServiceClass))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var id: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS ? id : nil
    }()

    var mode: TouchIDGuardMode {
        TouchIDGuardSupport.modeFor(UserDefaults.standard.string(forKey: DefaultsKey.touchIDGuardMode))
    }

    var holdDurationMilliseconds: Double {
        TouchIDGuardSupport.sanitizedHoldDuration(
            UserDefaults.standard.double(forKey: DefaultsKey.touchIDGuardHoldDurationMs))
    }

    /// Hold mode needs the button's state; ignore mode only needs the event,
    /// so a Mac without the key can still use it. Asked once: the Settings
    /// page reads it every time SwiftUI rebuilds the view, and the answer
    /// cannot change while the app runs.
    static let canMeasureHold: Bool = {
        guard let smc = SMCClient() else { return false }
        return smc.key(named: TouchIDGuardSupport.pressedStateKey) != nil
    }()

    func syncWithPreferences() {
        guard SessionActivitySupport.tapShouldRun(
            featureWanted: isEnabled,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) else {
            stop()
            return
        }
        start()
    }

    /// Releases the tap and any press in flight, for callers outside this type.
    func suspend() { stop() }

    // MARK: Lifecycle

    private func start() {
        guard !isRunning, installTap() else { return }
        isRunning = true
    }

    private func stop() {
        advanceGeneration()
        holdInFlight = false
        hud.hide()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isRunning = false
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << TouchIDGuardSupport.systemDefinedEventTypeRawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<TouchIDGuardService>
                    .fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
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

    // MARK: Event routing

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            advanceGeneration()
            holdInFlight = false
            hud.hide()
            let shouldRearm = SessionActivitySupport.tapShouldRun(
                featureWanted: isEnabled,
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            )
            if shouldRearm, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.stop()
                    self?.syncWithPreferences()
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard isRunning,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              TouchIDGuardSupport.isPress(eventType: type.rawValue,
                                          subtype: Int(nsEvent.subtype.rawValue)),
              let senderField = CGEventField(rawValue: TouchIDGuardSupport.senderIDFieldRawValue),
              TouchIDGuardSupport.isBuiltInPress(senderID: event.getIntegerValueField(senderField),
                                                 builtInButtonID: Self.builtInButtonID)
        else {
            return Unmanaged.passUnretained(event)
        }

        switch mode {
        case .ignore:
            return nil
        case .hold:
            // Without the button's state there is no way to measure a hold, so
            // the press is left to macOS rather than swallowed for nothing.
            guard let smc = SMCClient(),
                  let key = smc.key(named: TouchIDGuardSupport.pressedStateKey) else {
                return Unmanaged.passUnretained(event)
            }
            guard !holdInFlight else { return nil }
            // A tap is over before its event arrives: nothing to watch or show.
            guard smc.readBytes(key).map(TouchIDGuardSupport.isDown) == true else { return nil }
            holdInFlight = true
            let hold = holdDurationMilliseconds
            let remaining = max(0, hold - TouchIDGuardSupport.pressToEventDelayMilliseconds) / 1_000
            if UserDefaults.standard.bool(forKey: DefaultsKey.touchIDGuardShowFeedback) {
                let strings = FeatureStrings.quitProtection(L10n.shared.language)
                hud.show(title: strings.touchIDHoldHUD, detail: strings.releaseCancelHint,
                         holdDeadline: Date().addingTimeInterval(remaining))
            }
            watchPress(smc: smc, key: key, generation: advanceGeneration(), hold: hold)
            return nil
        }
    }

    // MARK: Hold

    private func watchPress(smc: SMCClient, key: SMCClient.Key, generation: UInt64, hold: Double) {
        let budget = TouchIDGuardSupport.pollBudgetMilliseconds(holdDurationMilliseconds: hold)
        let started = DispatchTime.now()
        pollQueue.async { [weak self] in
            var verdict = TouchIDGuardVerdict.released
            while true {
                guard let self, self.isCurrent(generation) else { return }
                guard let bytes = smc.readBytes(key) else { break }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
                verdict = TouchIDGuardSupport.verdict(elapsedSinceEventMilliseconds: elapsed,
                                                      down: TouchIDGuardSupport.isDown(bytes),
                                                      holdDurationMilliseconds: hold)
                if verdict != .waiting || elapsed > budget { break }
                usleep(UInt32(TouchIDGuardSupport.pollIntervalMilliseconds * 1_000))
            }
            DispatchQueue.main.async {
                guard let self, self.isCurrent(generation) else { return }
                self.holdInFlight = false
                self.hud.hide()
                if verdict == .reached { ScreenLock.lockNow() }
            }
        }
    }

    @discardableResult
    private func advanceGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        currentGeneration &+= 1
        return currentGeneration
    }

    private func isCurrent(_ value: UInt64) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return currentGeneration == value
    }
}
