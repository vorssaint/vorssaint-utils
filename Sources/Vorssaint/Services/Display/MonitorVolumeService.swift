// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreAudio
import os

/// The speaker volume of external monitors, over the DDC channel the
/// brightness feature already drives (VCP 0x62, like MonitorControl). Every
/// write goes through `BrightnessService.sendDDC`, so volume and brightness
/// share one serial queue and the standard's command spacing.
///
/// Nothing here polls. A monitor that answers readings is asked once for its
/// volume; one that does not (the same ones whose brightness reads fail) keeps
/// the last level this app set, and is only offered after a person turns it on
/// for that monitor, because a write the monitor accepts does not show it
/// speaks the control.
final class MonitorVolumeService: ObservableObject {
    static let shared = MonitorVolumeService()
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "display")

    /// The level and mute state of each monitor offered, by display.
    @Published private(set) var states: [CGDirectDisplayID: MonitorVolumeSupport.State] = [:]
    /// Displays whose volume answered a reading, and the range it reported.
    private var replied: [CGDirectDisplayID: UInt16] = [:]
    private var asked = Set<CGDirectDisplayID>()
    @Published private(set) var chosen: Set<String>
    private var stored: [String: MonitorVolumeSupport.State]
    private var waiting: [CGDirectDisplayID: [MonitorVolumeSupport.Command]] = [:]
    private var flushScheduled = Set<CGDirectDisplayID>()
    /// Key-downs consumed, so the matching key-up is consumed too.
    private var swallowed = Set<MonitorVolumeSupport.Key>()
    private var observer: AnyCancellable?
    /// How long writes gather before they go out: a held key repeats faster
    /// than a monitor takes commands.
    private static let flushDelay: TimeInterval = 0.08

    private init() {
        let defaults = UserDefaults.standard
        chosen = Set(defaults.stringArray(forKey: DefaultsKey.monitorVolumeChosen) ?? [])
        stored = (defaults.data(forKey: DefaultsKey.monitorVolumeStates))
            .flatMap { try? JSONDecoder().decode([String: MonitorVolumeSupport.State].self, from: $0) } ?? [:]
        observer = BrightnessService.shared.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displays in self?.displaysChanged(displays) }
    }

    // MARK: - What is offered

    /// External monitors with a DDC route: the ones whose speakers can be tried.
    var candidates: [BrightnessDisplay] {
        BrightnessService.shared.displays.filter {
            $0.isActive && !$0.isBuiltIn && BrightnessService.shared.ddcChannel(for: $0.id) != nil
        }
    }

    func isOffered(_ id: CGDirectDisplayID) -> Bool {
        guard let channel = BrightnessService.shared.ddcChannel(for: id) else { return false }
        return MonitorVolumeSupport.isOffered(volumeReplied: replied[id] != nil,
                                              chosenByPerson: chosen.contains(channel.fingerprint),
                                              hasDDCRoute: true)
    }

    func isChosen(_ id: CGDirectDisplayID) -> Bool {
        BrightnessService.shared.ddcChannel(for: id).map { chosen.contains($0.fingerprint) } ?? false
    }

    func setChosen(_ on: Bool, for id: CGDirectDisplayID) {
        guard let channel = BrightnessService.shared.ddcChannel(for: id) else { return }
        if on { chosen.insert(channel.fingerprint) } else { chosen.remove(channel.fingerprint) }
        UserDefaults.standard.set(Array(chosen).sorted(), forKey: DefaultsKey.monitorVolumeChosen)
        displaysChanged(BrightnessService.shared.displays)
        BrightnessService.shared.syncWithPreferences()
    }

    private func displaysChanged(_ displays: [BrightnessDisplay]) {
        let live = Set(displays.map(\.id))
        for id in replied.keys where !live.contains(id) { replied.removeValue(forKey: id) }
        asked.formIntersection(live)
        waiting = waiting.filter { live.contains($0.key) }
        var next: [CGDirectDisplayID: MonitorVolumeSupport.State] = [:]
        for display in displays where display.isActive && !display.isBuiltIn {
            guard let channel = BrightnessService.shared.ddcChannel(for: display.id) else { continue }
            // A monitor that answers readings is asked once whether it
            // speaks the volume control; one that does not is never read.
            if channel.readable, !asked.contains(display.id) {
                asked.insert(display.id)
                askVolume(of: display.id)
            }
            if isOffered(display.id) {
                next[display.id] = states[display.id] ?? stored[channel.fingerprint] ?? MonitorVolumeSupport.State()
            }
        }
        if next != states { states = next }
    }

    private func askVolume(of id: CGDirectDisplayID) {
        BrightnessService.shared.readDDC(code: MonitorVolumeSupport.volumeCode, from: id) { [weak self] answer in
            guard let self, let answer else {
                Self.log.log("volume read for display \(id) unanswered")
                return
            }
            let maximum = BrightnessSupport.sanitizedMaximum(answer.maximum)
            self.replied[id] = maximum
            let level = BrightnessSupport.normalized(current: answer.current, maximum: maximum)
            var state = self.states[id] ?? MonitorVolumeSupport.State()
            if !state.muted { state.level = level }
            self.remember(state, for: id)
            Self.log.log("volume read for display \(id): \(answer.current) of \(maximum)")
            self.displaysChanged(BrightnessService.shared.displays)
        }
    }

    // MARK: - Changing the volume

    private func maximum(for id: CGDirectDisplayID) -> UInt16 {
        replied[id] ?? MonitorVolumeSupport.defaultMaximum
    }

    /// 0x8D keeps the level where it was but not every monitor honours it;
    /// volume zero works wherever 0x62 does. Silence therefore uses the volume
    /// until a monitor has been shown to take the mute code.
    private let muteMethod = MonitorVolumeSupport.MuteMethod.volumeZero

    func level(for id: CGDirectDisplayID) -> Double { states[id]?.shown ?? 0 }
    func isMuted(_ id: CGDirectDisplayID) -> Bool { states[id]?.muted ?? false }

    func setLevel(_ level: Double, for id: CGDirectDisplayID) {
        change(id) { $0.set(level: level, maximum: $1, method: muteMethod) }
    }

    func step(_ delta: Double, for id: CGDirectDisplayID) {
        change(id) { $0.step(delta: delta, maximum: $1, method: muteMethod) }
    }

    func toggleMute(for id: CGDirectDisplayID) {
        change(id) { $0.toggleMute(maximum: $1, method: muteMethod) }
    }

    private func change(_ id: CGDirectDisplayID,
                        _ apply: (inout MonitorVolumeSupport.State, UInt16) -> [MonitorVolumeSupport.Command]) {
        guard isOffered(id), let channel = BrightnessService.shared.ddcChannel(for: id) else { return }
        var state = states[id] ?? stored[channel.fingerprint] ?? MonitorVolumeSupport.State()
        let commands = apply(&state, maximum(for: id))
        guard !commands.isEmpty else { return }
        states[id] = state
        remember(state, for: id)
        waiting[id] = MonitorVolumeSupport.collapsed((waiting[id] ?? []) + commands)
        guard flushScheduled.insert(id).inserted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flushDelay) { [weak self] in self?.flush(id) }
    }

    private func flush(_ id: CGDirectDisplayID) {
        flushScheduled.remove(id)
        guard let commands = waiting.removeValue(forKey: id), !commands.isEmpty else { return }
        BrightnessService.shared.sendDDC(commands.map(MonitorVolumeSupport.packet(for:)), to: id) { accepted in
            if !accepted { Self.log.log("volume write for display \(id) refused") }
        }
    }

    private func remember(_ state: MonitorVolumeSupport.State, for id: CGDirectDisplayID) {
        guard let channel = BrightnessService.shared.ddcChannel(for: id) else { return }
        stored = MonitorVolumeSupport.updatedStates(stored, fingerprint: channel.fingerprint, state: state)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.monitorVolumeStates)
        }
    }

    // MARK: - Keys

    /// Whether this volume key press goes to a monitor. The Mac's own keys
    /// do nothing while the sound goes out through a display, so they are
    /// taken over only then; every other press, and any monitor whose volume
    /// is not offered, is left to the system untouched. Main thread.
    func consumes(_ press: MonitorVolumeSupport.KeyPress, flags: CGEventFlags) -> Bool {
        guard press.isDown else { return swallowed.remove(press.key) != nil }
        if press.isRepeat, swallowed.contains(press.key) { return true }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.monitorVolumeKeysEnabled),
              flags.isDisjoint(with: [.maskCommand, .maskControl]),
              let id = keyTarget() else { return false }
        swallowed.insert(press.key)
        let option = flags.contains(.maskAlternate)
        switch press.key {
        case .up: step(option ? MonitorVolumeSupport.keyStep / 4 : MonitorVolumeSupport.keyStep, for: id)
        case .down: step(option ? -MonitorVolumeSupport.keyStep / 4 : -MonitorVolumeSupport.keyStep, for: id)
        case .mute: if !press.isRepeat { toggleMute(for: id) }
        }
        _ = NotchService.shared.showVolume(level(for: id), muted: isMuted(id))
        return true
    }

    private func keyTarget() -> CGDirectDisplayID? {
        let output = Self.defaultOutput()
        let pointer = NSEvent.mouseLocation
        let pointerDisplay = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            .flatMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
        let candidates = self.candidates.filter { isOffered($0.id) }
            .map { MonitorVolumeSupport.Candidate(id: $0.id, name: $0.name) }
        return MonitorVolumeSupport.target(outputIsDisplayAudio: output.isDisplay, outputName: output.name,
                                           candidates: candidates, pointerDisplay: pointerDisplay)
    }

    /// The sound output the Mac plays through, and whether it reaches the
    /// speakers over a display connection.
    static func defaultOutput() -> (name: String?, isDisplay: Bool) {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                         &size, &device) == noErr, device != 0 else { return (nil, false) }
        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        let hasTransport = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        let hasName = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr
        return (hasName ? name?.takeRetainedValue() as String? : nil,
                hasTransport && (transport == kAudioDeviceTransportTypeDisplayPort
                                 || transport == kAudioDeviceTransportTypeHDMI))
    }
}
