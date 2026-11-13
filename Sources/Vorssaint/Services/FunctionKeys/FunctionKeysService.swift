// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import IOKit

/// Gives the Spotlight key (F4), the dictation key (F5) and the Do Not Disturb
/// key (F6) a different job: press Command-F, toggle the microphone mute, or
/// put the Mac to sleep. The tap is installed only while one of them is
/// switched on and Accessibility is granted, listens to key presses alone, and
/// hands every key but those straight back without looking at it.
final class FunctionKeysService: ObservableObject {
    static let shared = FunctionKeysService()

    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// The settings as the last sync read them, so the tap callback decides
    /// from memory and never reads preferences while a key is waiting.
    private var configuration = FunctionKeysSupport.Configuration.off

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        let next = Self.currentConfiguration()
        configuration = next
        if SessionActivitySupport.tapShouldRun(featureWanted: next.wantsTap,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    /// Releases the tap for callers outside this type.
    func suspend() { stop() }

    private static func currentConfiguration() -> FunctionKeysSupport.Configuration {
        let defaults = UserDefaults.standard
        guard AppFeature.functionKeys.isAvailable else { return .off }
        return FunctionKeysSupport.Configuration(
            micMuteEnabled: defaults.bool(forKey: DefaultsKey.functionKeysMicMuteEnabled),
            sleepEnabled: defaults.bool(forKey: DefaultsKey.functionKeysSleepEnabled),
            microphoneMuteAvailable: AppFeature.micMute.isAvailable,
            findEnabled: defaults.bool(forKey: DefaultsKey.functionKeysFindEnabled))
    }

    // MARK: Lifecycle

    private func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<FunctionKeysService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        self.tap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func stop() {
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

    // MARK: Events

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // The system switched the tap off. Switch it back on only if the
            // feature is still wanted and the session is on screen; otherwise
            // let the next sync tear it down.
            if let tap, SessionActivitySupport.tapShouldRun(featureWanted: configuration.wantsTap,
                                                            accessibilityGranted: AXIsProcessTrusted(),
                                                            sessionIsActive: SessionActivity.shared.isActive) {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }
        let decision = FunctionKeysSupport.decision(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            isKeyDown: type == .keyDown,
            isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            hasModifiers: !event.flags.intersection(FunctionKeysSupport.shortcutModifiers).isEmpty,
            configuration: configuration)
        switch decision {
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .perform(let action):
            // Leave the callback at once: the work runs after the key has
            // been taken, so typing is never held up behind it.
            DispatchQueue.main.async { Self.perform(action) }
            return nil
        }
    }

    private static func perform(_ action: FunctionKeysSupport.Action) {
        switch action {
        case .findInFrontApp: postFind()
        case .toggleMicrophone: MicMuteService.shared.toggle()
        case .sleepSystem:
            // `pmset disablesleep` (closed-lid mode, other tools) makes the
            // system refuse every sleep request. Say so instead of doing
            // nothing, since the key was taken and nothing else would show it.
            guard !systemSleepIsDisabled else { NSSound.beep(); return }
            CommandBarExtras.run(.sleep)
        }
    }

    /// Command-F, as if typed: the app in front opens its own search. Only
    /// Command is held, so the Fn flag the Spotlight key carries stays behind.
    private static func postFind() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: FunctionKeysSupport.findKeyCode,
                                keyDown: down)
            event?.flags = FunctionKeysSupport.findShortcutFlags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Whether the system has been told never to sleep.
    private static var systemSleepIsDisabled: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString,
                                                    kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (value as? Bool) ?? false
    }
}
