// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Turns coarse hardware volume wheel bursts into macOS' fine volume step.
/// Active only while enabled and Accessibility is granted.
final class PreciseVolumeRollerService: ObservableObject {
    static let shared = PreciseVolumeRollerService()

    @Published private(set) var tapFailed = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gate = PreciseVolumeRollerGate()

    private init() {}

    func syncWithPreferences() {
        let wanted = AppFeature.mixer.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
        wanted ? start() : stop()
    }

    func suspend() {
        stop()
    }

    func stop() {
        removeTap()
        tapFailed = false
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        gate.reset()
    }

    private func start() {
        guard AXIsProcessTrusted() else {
            removeTap()
            tapFailed = false
            return
        }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        guard tap == nil else { return }

        let systemDefined = CGEventType(rawValue: CleaningSystemKeyEvent.systemDefinedEventTypeRawValue)!
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<PreciseVolumeRollerService>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return service.handle(type: type, event: event)
        }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << systemDefined.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            tapFailed = true
            return
        }

        tap = created
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: created, enable: true)
        tapFailed = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if AXIsProcessTrusted(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == CleaningSystemKeyEvent.systemDefinedEventTypeRawValue,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8,
              let volumePress = Self.volumePress(fromData1: nsEvent.data1) else {
            return Unmanaged.passUnretained(event)
        }

        if event.flags.contains(.maskAlternate), event.flags.contains(.maskShift) {
            return Unmanaged.passUnretained(event)
        }

        guard volumePress.isDown else { return nil }
        guard gate.accepts(volumePress.direction, at: ProcessInfo.processInfo.systemUptime) else {
            return nil
        }
        Self.postVolumeKey(volumePress.keyCode, optionShift: true)
        return nil
    }

    private static func volumePress(fromData1 data1: Int) -> (keyCode: Int32,
                                                             direction: PreciseVolumeRollerDirection,
                                                             isDown: Bool)? {
        let keyCode = Int32((data1 >> 16) & 0xffff)
        guard let mediaKey = PreciseVolumeMediaKey(rawValue: keyCode),
              let direction = mediaKey.rollerDirection else { return nil }
        let state = (data1 >> 8) & 0xff
        return (keyCode, direction, state == 0x0a)
    }

    private static func postVolumeKey(_ keyCode: Int32, optionShift: Bool) {
        let fineFlags: UInt = optionShift ? 0x80000 | 0x20000 : 0
        for state in [0x0a, 0x0b] {
            let event = NSEvent.otherEvent(with: .systemDefined,
                                           location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8) | fineFlags),
                                           timestamp: 0,
                                           windowNumber: 0,
                                           context: nil,
                                           subtype: 8,
                                           data1: Int((keyCode << 16) | Int32(state << 8)),
                                           data2: -1)
            event?.cgEvent?.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }
}
