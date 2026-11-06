// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure helpers for driving a monitor's own speakers over DDC/CI with the
/// volume keys: the VCP codes, key steps, which audio outputs belong to a
/// display, and which display an output plays through. No IOKit or CoreAudio
/// here so the unit tests cover every decision.
enum DDCVolumeSupport {
    /// VCP code for audio speaker volume in the DDC/CI standard.
    static let volumeCode: UInt8 = 0x62

    /// The step a volume key moves, as a percentage of the monitor's range.
    /// 6.25% is the sixteen steps macOS uses for its own volume; Option-Shift
    /// moves a quarter of whichever step is chosen.
    static let defaultStepPercent = 6.25
    static let stepChoices: [Double] = [1, 2, 3, 5, 6.25, 10]

    static func sanitizedStep(_ percent: Double) -> Double {
        guard percent.isFinite, percent > 0 else { return defaultStepPercent }
        return min(max(percent, 0.25), 25)
    }

    /// The range the volume keys may move in, as percentages of the
    /// monitor's own range. Mute still writes zero below the minimum.
    struct VolumeLimits: Equatable {
        let minimumPercent: Int
        let maximumPercent: Int

        static let full = VolumeLimits(minimumPercent: 0, maximumPercent: 100)

        /// Keeps 0 <= minimum < maximum <= 100. A missing or zero maximum
        /// reads as 100, since a ceiling of silence would make the keys
        /// pointless; a minimum at or above the maximum yields to it.
        static func sanitized(minimum: Int, maximum: Int) -> VolumeLimits {
            let upper = maximum <= 0 ? 100 : min(maximum, 100)
            let lower = min(max(minimum, 0), upper - 1)
            return VolumeLimits(minimumPercent: lower, maximumPercent: upper)
        }
    }

    /// CoreAudio transport types of audio carried over a display cable
    /// ('dprt' and 'hdmi'), spelled out so this file needs no CoreAudio.
    static let displayPortTransport: UInt32 = 0x6470_7274
    static let hdmiTransport: UInt32 = 0x6864_6D69

    /// Only audio that travels down a display cable can be a monitor's
    /// speakers; USB, Bluetooth and built-in outputs keep the system keys.
    static func isDisplayAudio(transportType: UInt32) -> Bool {
        transportType == displayPortTransport || transportType == hdmiTransport
    }

    /// The next value on the step grid, `direction` steps up or down, kept
    /// inside the limits. A value between grid points snaps to the nearest
    /// one first, so a level set on the monitor's own buttons rejoins the
    /// grid instead of drifting. Direction zero only applies the limits.
    static func steppedValue(current: UInt16, maximum: UInt16, direction: Int,
                             stepPercent: Double = defaultStepPercent,
                             limits: VolumeLimits = .full) -> UInt16 {
        let maximum = Double(BrightnessSupport.sanitizedMaximum(maximum))
        let step = max(maximum * sanitizedStep(stepPercent) / 100, 1)
        let index = (min(Double(current), maximum) / step).rounded() + Double(direction)
        let value = direction == 0 ? min(Double(current), maximum) : (index * step).rounded()
        let lower = (maximum * Double(limits.minimumPercent) / 100).rounded()
        let upper = (maximum * Double(limits.maximumPercent) / 100).rounded()
        return UInt16(min(max(value, lower), upper))
    }

    /// 0...1 for the overlay.
    static func level(value: UInt16, maximum: UInt16) -> Double {
        let maximum = BrightnessSupport.sanitizedMaximum(maximum)
        return min(Double(value) / Double(maximum), 1)
    }

    /// A monitor that never answers a volume read still takes writes. It
    /// starts from the middle of the conventional 0-100 scale, so the first
    /// key press is a modest change rather than full volume or silence.
    static let assumedUnreadable: (current: UInt16, maximum: UInt16) = (current: 50, maximum: 100)

    static func normalizedName(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }.map(Character.init))
    }

    /// The display an audio output plays through. macOS names a monitor's
    /// audio device after the monitor, so names decide; containment covers
    /// a vendor prefix on one side. With names that settle nothing, a single
    /// DDC display is the only candidate the sound can be reaching.
    static func matchDisplay(outputName: String, displays: [(id: UInt32, name: String)]) -> UInt32? {
        let output = normalizedName(outputName)
        if !output.isEmpty {
            let exact = displays.filter { normalizedName($0.name) == output }
            if exact.count == 1 { return exact[0].id }
            let partial = displays.filter {
                let name = normalizedName($0.name)
                return !name.isEmpty && (name.contains(output) || output.contains(name))
            }
            if partial.count == 1 { return partial[0].id }
        }
        return displays.count == 1 ? displays[0].id : nil
    }

    /// Mute is volume zero with the previous level remembered: the standard's
    /// own mute control (0x8D) is ignored by many monitors that honor 0x62.
    struct MuteState: Equatable {
        private(set) var restoreValue: UInt16?
        var isMuted: Bool { restoreValue != nil }

        /// The value to write for a mute toggle, given the current value.
        /// Unmuting restores the remembered level, kept inside the limits.
        mutating func toggle(current: UInt16, maximum: UInt16,
                             stepPercent: Double = defaultStepPercent,
                             limits: VolumeLimits = .full) -> UInt16 {
            if let restore = restoreValue {
                restoreValue = nil
                return steppedValue(current: restore, maximum: maximum, direction: 0,
                                    stepPercent: stepPercent, limits: limits)
            }
            // Muting from silence restores to a step rather than to nothing.
            restoreValue = current > 0
                ? current
                : steppedValue(current: 0, maximum: maximum, direction: 1,
                               stepPercent: stepPercent, limits: limits)
            return 0
        }

        /// A volume key while muted moves from the remembered level, the way
        /// the system unmutes on a volume press.
        mutating func unmuteForStep(current: UInt16) -> UInt16 {
            defer { restoreValue = nil }
            return restoreValue ?? current
        }

        mutating func reset() { restoreValue = nil }
    }

    /// Volume and mute keys arrive as system-defined events whose data1
    /// carries the key code (bits 16...31) and the state (0x0a down, 0x0b up).
    enum Key: Int32 {
        case volumeUp = 0
        case volumeDown = 1
        case mute = 7
    }

    struct KeyPress: Equatable {
        let key: Key
        let isDown: Bool
        let isRepeat: Bool
    }

    static func keyPress(fromData1 data1: Int) -> KeyPress? {
        guard let key = Key(rawValue: Int32((data1 >> 16) & 0xffff)) else { return nil }
        let state = (data1 >> 8) & 0xff
        guard state == 0x0a || state == 0x0b else { return nil }
        return KeyPress(key: key, isDown: state == 0x0a, isRepeat: data1 & 1 != 0)
    }

    /// Whether a release belongs to a press this feature took. Releases of
    /// presses it left to the system go to the system too.
    struct KeyOwnership {
        private var owned = Set<Int32>()

        mutating func claim(_ key: Key) { owned.insert(key.rawValue) }

        mutating func releases(_ key: Key) -> Bool {
            owned.remove(key.rawValue) != nil
        }

        mutating func reset() { owned.removeAll() }
    }
}
