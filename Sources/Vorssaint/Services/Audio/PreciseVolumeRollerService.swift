// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Owns the volume keys. It turns coarse hardware volume wheel bursts into
/// macOS' fine volume step, and on an output macOS refuses to set the volume
/// of, moves the mixer's software master instead — the keys are dead there
/// otherwise. Active only while one of the two applies and Accessibility is
/// granted.
final class PreciseVolumeRollerService: ObservableObject {
    static let shared = PreciseVolumeRollerService()

    @Published private(set) var tapFailed = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gate = PreciseVolumeRollerGate()
    /// The finer-steps preference, read where it is set rather than in the
    /// tap: the callback runs on every press of a held key.
    private var prefersFineSteps = false

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        prefersFineSteps = UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
        let wanted = AppFeature.mixer.isAvailable
            && (prefersFineSteps || AppVolumeMixer.shared.hasSoftwareMasterOutput)
        if SessionActivitySupport.tapShouldRun(featureWanted: wanted,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
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
        if let tap { CFMachPortInvalidate(tap) }
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
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == CleaningSystemKeyEvent.systemDefinedEventTypeRawValue,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8,
              let volumePress = Self.volumePress(fromData1: nsEvent.data1) else {
            return Unmanaged.passUnretained(event)
        }

        let fine = event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift)

        // Nothing in the system moves for these keys on an output with no
        // volume control, so the press is spent here: the master the mixer
        // renders takes the step, and macOS never gets to draw the overlay
        // that says the key did nothing.
        if AppVolumeMixer.shared.hasSoftwareMasterOutput {
            guard volumePress.isDown else { return nil }
            // The finer-steps option asks for the smaller step everywhere it
            // can reach, and on this output it is the only thing that can
            // honour it: re-posting the key with the modifier reaches a
            // volume macOS still refuses to set.
            let fineStep = fine || prefersFineSteps
            if let level = AppVolumeMixer.shared.stepSoftwareMasterVolume(
                up: volumePress.direction == .up,
                fine: fineStep) {
                LevelOSD.show(displayID: nil,
                              level: level,
                              style: .volume(deviceName: AppVolumeMixer.shared.currentOutputDeviceName))
            }
            return nil
        }

        if fine {
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
