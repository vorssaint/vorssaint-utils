// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum DictationShortcutKind: String, CaseIterable, Identifiable {
    case standard
    case modifier

    var id: String { rawValue }
}

enum DictationModifierKey: String, CaseIterable, Identifiable {
    case leftCommand
    case rightCommand
    case leftOption
    case rightOption
    case leftControl
    case rightControl
    case leftShift
    case rightShift
    case function

    var id: String { rawValue }

    var keyCode: Int64 {
        switch self {
        case .leftCommand: return Int64(kVK_Command)
        case .rightCommand: return Int64(kVK_RightCommand)
        case .leftOption: return Int64(kVK_Option)
        case .rightOption: return Int64(kVK_RightOption)
        case .leftControl: return Int64(kVK_Control)
        case .rightControl: return Int64(kVK_RightControl)
        case .leftShift: return Int64(kVK_Shift)
        case .rightShift: return Int64(kVK_RightShift)
        case .function: return Int64(kVK_Function)
        }
    }

    var displayName: String {
        switch self {
        case .leftCommand: return "Command esquerdo"
        case .rightCommand: return "Command direito"
        case .leftOption: return "Option esquerdo"
        case .rightOption: return "Option direito"
        case .leftControl: return "Control esquerdo"
        case .rightControl: return "Control direito"
        case .leftShift: return "Shift esquerdo"
        case .rightShift: return "Shift direito"
        case .function: return "Fn"
        }
    }

    var eventFlag: CGEventFlags {
        switch self {
        case .leftCommand, .rightCommand: return .maskCommand
        case .leftOption, .rightOption: return .maskAlternate
        case .leftControl, .rightControl: return .maskControl
        case .leftShift, .rightShift: return .maskShift
        case .function: return .maskSecondaryFn
        }
    }

    static func from(keyCode: Int64) -> Self? {
        allCases.first { $0.keyCode == keyCode }
    }
}

/// Global flagsChanged monitor used only for standalone modifier shortcuts.
/// Carbon hotkeys cannot represent a modifier without a key, so this tap is
/// deliberately isolated from the existing shortcut registration path.
final class DictationModifierShortcutTap {
    var onPress: ((DictationModifierKey) -> Void)?
    var onRelease: ((DictationModifierKey) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var registeredKeys: Set<DictationModifierKey> = []
    private var downKeys: Set<DictationModifierKey> = []

    @discardableResult
    func sync(keys: Set<DictationModifierKey>) -> Bool {
        guard !keys.isEmpty else {
            stop()
            return true
        }
        guard AXIsProcessTrusted() else {
            stop()
            return false
        }
        if tap != nil, tap.map({ CGEvent.tapIsEnabled(tap: $0) }) == true {
            registeredKeys = keys
            downKeys.removeAll()
            return true
        }
        stop()
        // `stop()` clears the monitored keys. Set them only after that cleanup;
        // otherwise a newly-created monitor receives flagsChanged events but
        // rejects every key as unregistered.
        registeredKeys = keys
        downKeys.removeAll()
        let mask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<DictationModifierShortcutTap>
                    .fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            registeredKeys.removeAll()
            return false
        }
        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    func stop() {
        registeredKeys.removeAll()
        downKeys.removeAll()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            downKeys.removeAll()
            return Unmanaged.passUnretained(event)
        }
        guard type == .flagsChanged,
              let key = DictationModifierKey.from(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode)),
              registeredKeys.contains(key) else {
            return Unmanaged.passUnretained(event)
        }
        let isDown = event.flags.contains(key.eventFlag)
        if isDown {
            guard downKeys.insert(key).inserted else {
                return Unmanaged.passUnretained(event)
            }
            DispatchQueue.main.async { [weak self] in self?.onPress?(key) }
        } else {
            guard downKeys.remove(key) != nil else {
                return Unmanaged.passUnretained(event)
            }
            DispatchQueue.main.async { [weak self] in self?.onRelease?(key) }
        }
        // Keep the modifier event in the system stream. Standalone shortcuts
        // are gestures, not remappings, so normal keyboard state remains sane.
        return Unmanaged.passUnretained(event)
    }

    deinit { stop() }
}

enum DictationShortcutSlot: String, CaseIterable, Identifiable {
    case primary
    case secondary

    var id: String { rawValue }
}

enum DictationShortcutMode: String, CaseIterable, Identifiable {
    case toggle
    case pushToTalk
    case hybrid

    var id: String { rawValue }
}

struct DictationShortcutProfile: Equatable {
    let slot: DictationShortcutSlot
    let mode: DictationShortcutMode
    let provider: DictationProvider
    let model: DictationModel
    let language: DictationLanguage
    let microphoneUID: String?
    let outputMode: DictationOutputMode

    init(slot: DictationShortcutSlot,
         mode: DictationShortcutMode,
         provider: DictationProvider,
         model: DictationModel,
         language: DictationLanguage,
         microphoneUID: String?,
         outputMode: DictationOutputMode = .raw) {
        self.slot = slot
        self.mode = mode
        self.provider = provider
        self.model = model
        self.language = language
        self.microphoneUID = microphoneUID
        self.outputMode = outputMode
    }
}

enum DictationShortcutAction: Equatable {
    case begin
    case stop
}

/// Pure key gesture state. Carbon does not report autorepeat for registered
/// hotkeys consistently, so duplicate downs are rejected here as well.
struct DictationShortcutGesture: Equatable {
    static let hybridHoldThreshold: TimeInterval = 0.5

    private(set) var pressedAt: TimeInterval?
    private(set) var pressedMode: DictationShortcutMode?

    mutating func keyDown(at time: TimeInterval,
                          mode: DictationShortcutMode,
                          sessionIsActive: Bool) -> DictationShortcutAction? {
        guard pressedAt == nil else { return nil }
        pressedAt = time
        pressedMode = mode
        switch mode {
        case .toggle:
            return sessionIsActive ? .stop : .begin
        case .pushToTalk:
            return sessionIsActive ? nil : .begin
        case .hybrid:
            // A second press ends a hands-free session, matching VoiceInk.
            // When idle, release timing still differentiates tap from hold.
            return sessionIsActive ? .stop : .begin
        }
    }

    mutating func keyUp(at time: TimeInterval,
                        sessionIsActive: Bool) -> DictationShortcutAction? {
        guard let pressedAt, let mode = pressedMode else { return nil }
        self.pressedAt = nil
        pressedMode = nil
        guard sessionIsActive else { return nil }
        switch mode {
        case .toggle: return nil
        case .pushToTalk: return .stop
        case .hybrid:
            return time - pressedAt >= Self.hybridHoldThreshold ? .stop : nil
        }
    }

    mutating func cancel() {
        pressedAt = nil
        pressedMode = nil
    }
}
