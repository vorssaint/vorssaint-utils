// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreAudio
import os

/// Volume and mute keys for a monitor's own speakers. macOS gives audio sent
/// over DisplayPort or HDMI no volume control of its own, so the keys do
/// nothing while a monitor plays the sound. While this is on and the default
/// output is such a monitor, the keys write the monitor's speaker volume over
/// DDC/CI instead, through the display channel the brightness feature found.
///
/// Standing resources while on: one CoreAudio listener for the default output
/// and one event tap for system-defined events. The tap leaves every key
/// alone unless the output is a display it can address, so the system and the
/// other volume features keep every other device.
final class DDCVolumeService {
    static let shared = DDCVolumeService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "ddc-volume")
    private static let systemDefinedEventType: UInt32 = 14

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private let audioQueue = DispatchQueue(label: "com.vorssaint.utils.ddc-volume.audio", qos: .userInitiated)

    /// The default output as last read: its name, and whether it is audio
    /// carried by a display cable. Read off the tap's thread; the tap only
    /// ever reads this cached copy.
    private var output: (name: String, isDisplayAudio: Bool)?

    // Main-thread state per display.
    private var levels: [CGDirectDisplayID: (current: UInt16, maximum: UInt16)] = [:]
    private var mute: [CGDirectDisplayID: DDCVolumeSupport.MuteState] = [:]
    private var inFlight = Set<CGDirectDisplayID>()
    private var pendingSteps: [CGDirectDisplayID: (steps: Int, fine: Bool)] = [:]
    private var pendingMute = Set<CGDirectDisplayID>()
    private var keyOwnership = DDCVolumeSupport.KeyOwnership()

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.ddcVolumeEnabled)
    }

    /// Read at each key press, so Settings changes apply to the next press.
    private var stepPercent: Double {
        DDCVolumeSupport.sanitizedStep(UserDefaults.standard.double(forKey: DefaultsKey.ddcVolumeStep))
    }

    private var limits: DDCVolumeSupport.VolumeLimits {
        let defaults = UserDefaults.standard
        return .sanitized(minimum: defaults.integer(forKey: DefaultsKey.ddcVolumeMinimum),
                          maximum: defaults.integer(forKey: DefaultsKey.ddcVolumeMaximum))
    }

    func syncWithPreferences() {
        if isEnabled, AXIsProcessTrusted(), SessionActivity.shared.isActive {
            installOutputListener()
            refreshOutput()
            installTap()
        } else {
            stop()
        }
    }

    func stop() {
        removeTap()
        removeOutputListener()
        output = nil
        levels.removeAll()
        mute.removeAll()
        pendingSteps.removeAll()
        pendingMute.removeAll()
        inFlight.removeAll()
        keyOwnership.reset()
    }

    // MARK: - Target

    /// The DDC display the volume keys should drive right now, or nil to
    /// leave them to the system.
    private func targetDisplay() -> CGDirectDisplayID? {
        guard let output, output.isDisplayAudio else { return nil }
        let candidates = BrightnessService.shared.ddcDisplays.map { (id: $0.id, name: $0.name) }
        return DDCVolumeSupport.matchDisplay(outputName: output.name, displays: candidates)
    }

    // MARK: - Keys

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, isEnabled, SessionActivity.shared.isActive {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == Self.systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8,
              let press = DDCVolumeSupport.keyPress(fromData1: nsEvent.data1) else {
            return Unmanaged.passUnretained(event)
        }
        if !press.isDown {
            return keyOwnership.releases(press.key) ? nil : Unmanaged.passUnretained(event)
        }
        // Command and Control combinations stay with the system, as they do
        // for the other volume features.
        guard event.flags.isDisjoint(with: [.maskCommand, .maskControl]),
              let display = targetDisplay() else {
            return Unmanaged.passUnretained(event)
        }
        keyOwnership.claim(press.key)
        // A held mute key repeats; one press is one toggle, as with the
        // system's own mute.
        if press.key == .mute, press.isRepeat { return nil }
        let fine = event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift)
        // Never hold the tap's reply for DDC work; it runs on the brightness
        // queue with the pacing monitors need.
        DispatchQueue.main.async { [weak self] in
            switch press.key {
            case .volumeUp: self?.step(display, by: 1, fine: fine)
            case .volumeDown: self?.step(display, by: -1, fine: fine)
            case .mute: self?.toggleMute(display)
            }
        }
        return nil
    }

    // MARK: - Volume

    private func step(_ display: CGDirectDisplayID, by steps: Int, fine: Bool) {
        if inFlight.contains(display) {
            // Coalesce a held key into one write per DDC round trip.
            let pending = pendingSteps[display]
            pendingSteps[display] = (steps: (pending?.steps ?? 0) + steps, fine: fine)
            return
        }
        inFlight.insert(display)
        withLevel(display) { [weak self] level in
            guard let self else { return }
            var muteState = self.mute[display] ?? DDCVolumeSupport.MuteState()
            let from = muteState.unmuteForStep(current: level.current)
            self.mute[display] = muteState
            let step = fine ? self.stepPercent / 4 : self.stepPercent
            let value = DDCVolumeSupport.steppedValue(current: from, maximum: level.maximum,
                                                      direction: steps, stepPercent: step,
                                                      limits: self.limits)
            self.write(value, maximum: level.maximum, to: display)
        }
    }

    private func toggleMute(_ display: CGDirectDisplayID) {
        if inFlight.contains(display) {
            // A mute pressed while a volume write is on the bus runs right
            // after it instead of being dropped. A second press cancels it.
            if pendingMute.remove(display) == nil { pendingMute.insert(display) }
            return
        }
        inFlight.insert(display)
        withLevel(display) { [weak self] level in
            guard let self else { return }
            var muteState = self.mute[display] ?? DDCVolumeSupport.MuteState()
            let value = muteState.toggle(current: level.current, maximum: level.maximum,
                                         stepPercent: self.stepPercent, limits: self.limits)
            self.mute[display] = muteState
            self.write(value, maximum: level.maximum, to: display)
        }
    }

    /// The monitor's level: the last one written here, or else read from the
    /// monitor once. Changes made on the monitor's own buttons are picked up
    /// again whenever the output or the display set changes.
    private func withLevel(_ display: CGDirectDisplayID,
                           _ body: @escaping ((current: UInt16, maximum: UInt16)) -> Void) {
        if let level = levels[display] {
            body(level)
            return
        }
        BrightnessService.shared.readVCP(DDCVolumeSupport.volumeCode, display: display) { reply in
            let level: (current: UInt16, maximum: UInt16) = reply.map {
                (current: $0.current, maximum: BrightnessSupport.sanitizedMaximum($0.maximum))
            } ?? DDCVolumeSupport.assumedUnreadable
            if reply == nil {
                Self.log.log("display \(display) gave no volume reading; starting from the middle")
            }
            body(level)
        }
    }

    private func write(_ value: UInt16, maximum: UInt16, to display: CGDirectDisplayID) {
        BrightnessService.shared.writeVCP(DDCVolumeSupport.volumeCode, value: value,
                                          display: display) { [weak self] accepted in
            guard let self else { return }
            self.inFlight.remove(display)
            if accepted {
                self.levels[display] = (current: value, maximum: maximum)
                let muted = self.mute[display]?.isMuted ?? false
                let level = DDCVolumeSupport.level(value: value, maximum: maximum)
                // The Dynamic Island shows the level when it handles volume,
                // just as it does for brightness; otherwise the overlay does.
                if AppFeature.notch.isAvailable, NotchSupport.routes(.volume),
                   NotchService.shared.showVolume(level, muted: muted) {
                    // Shown in the island.
                } else {
                    BrightnessOSD.show(displayID: display, brightness: level,
                                       symbol: Self.symbol(value: value, maximum: maximum, muted: muted),
                                       routesToNotch: false)
                }
            } else {
                // A rejected write means the channel changed under us; read
                // it fresh next time.
                self.levels.removeValue(forKey: display)
                self.mute.removeValue(forKey: display)
            }
            if self.pendingMute.remove(display) != nil {
                self.toggleMute(display)
            } else if let pending = self.pendingSteps.removeValue(forKey: display), pending.steps != 0 {
                self.step(display, by: pending.steps, fine: pending.fine)
            }
        }
    }

    private static func symbol(value: UInt16, maximum: UInt16, muted: Bool) -> String {
        if muted || value == 0 { return "speaker.slash.fill" }
        let level = DDCVolumeSupport.level(value: value, maximum: maximum)
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    // MARK: - Default output

    private func installOutputListener() {
        guard outputListener == nil else { return }
        var address = Self.defaultOutputAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshOutput() }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &address, audioQueue, listener) == noErr {
            outputListener = listener
        }
    }

    private func removeOutputListener() {
        guard let listener = outputListener else { return }
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &address, audioQueue, listener)
        outputListener = nil
    }

    /// CoreAudio can block on a device that is reconnecting, so the read runs
    /// on its own queue and lands on the main thread.
    private func refreshOutput() {
        audioQueue.async { [weak self] in
            let current = Self.readDefaultOutput()
            DispatchQueue.main.async {
                guard let self else { return }
                if current?.name != self.output?.name {
                    // A different device: forget levels read for the old one.
                    self.levels.removeAll()
                    self.mute.removeAll()
                }
                self.output = current
                Self.log.log("default output \(current?.name ?? "none", privacy: .public) display audio \(current?.isDisplayAudio ?? false)")
            }
        }
    }

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func readDefaultOutput() -> (name: String, isDisplayAudio: Bool)? {
        var address = defaultOutputAddress
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }

        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)

        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        let deviceName = status == noErr ? (name?.takeRetainedValue() as String?) ?? "" : ""

        return (name: deviceName, isDisplayAudio: DDCVolumeSupport.isDisplayAudio(transportType: transport))
    }

    // MARK: - Event tap

    private func installTap() {
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return Unmanaged<DDCVolumeService>.fromOpaque(userInfo)
                .takeUnretainedValue()
                .handle(type: type, event: event)
        }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << Self.systemDefinedEventType),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.log.log("could not create the volume key tap")
            return
        }
        tap = created
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        if let tapSource { CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        CGEvent.tapEnable(tap: created, enable: true)
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        tapSource = nil
    }
}
