// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Combine
import CoreGraphics
import Foundation

/// Suppresses accidental duplicate physical key presses inside a short window.
/// Auto-repeat from a held key is left untouched so normal key-repeat behavior
/// keeps working.
final class KeyboardDebounceService: ObservableObject {
    static let shared = KeyboardDebounceService()

    @Published private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var state = KeyboardDebounceState()
    private var config = KeyboardDebounceConfig(enabled: false,
                                                globalWindowMs: Defaults.defaultKeyboardDebounceWindowMs,
                                                keyWindows: [:])

    private init() {}

    func syncWithPreferences() {
        config = KeyboardDebounceConfig(
            enabled: UserDefaults.standard.bool(forKey: DefaultsKey.keyboardDebounceEnabled),
            globalWindowMs: Defaults.sanitizedKeyboardDebounceWindow(
                UserDefaults.standard.integer(forKey: DefaultsKey.keyboardDebounceWindowMs)
            ),
            keyWindows: KeyboardDebounceConfig.decodeKeyWindows(
                UserDefaults.standard.string(forKey: DefaultsKey.keyboardDebounceKeyWindows) ?? ""
            )
        )

        if config.enabled, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    func suspend() {
        stop()
    }

    private func start() {
        guard tap == nil else {
            isRunning = true
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<KeyboardDebounceService>.fromOpaque(userInfo).takeUnretainedValue()
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
        state.reset()
        isRunning = true
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        state.reset()
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              AXIsProcessTrusted(),
              !CleaningModeManager.shared.isActive else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let now = TimeInterval(event.timestamp) / 1_000_000_000.0
        if state.shouldSuppress(keyCode: keyCode,
                                isAutoRepeat: isRepeat,
                                time: now,
                                config: config) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
