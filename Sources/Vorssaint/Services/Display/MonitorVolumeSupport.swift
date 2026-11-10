// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A write-only monitor has no observed speaker level. The person supplies
/// its current percentage once, then only accepted writes advance it.
enum MonitorVolumeSupport {
    struct Preference: Codable, Equatable {
        var enabled: Bool
        var raw: UInt16?
        var maximum: UInt16 = 100

        var level: Double? {
            guard let raw, raw > 0, raw <= maximum else { return nil }
            return Double(raw) / Double(maximum)
        }

        var percent: Int? { level.map { max(1, Int(($0 * 100).rounded())) } }

        mutating func setReference(_ percent: Int) {
            guard percent != self.percent, (1...100).contains(percent), maximum > 0 else { return }
            raw = max(1, BrightnessSupport.deviceValue(for: Double(percent) / 100, maximum: maximum))
        }
    }

    struct Setup: Equatable {
        let target: BrightnessSupport.SpeakerTarget
        let writeOnly: Bool
        let preference: Preference?
        var persistent = true

        var reference: Int? { preference?.percent }

        var enabled: Bool {
            if writeOnly { return preference?.enabled == true && reference != nil }
            return preference?.enabled ?? true
        }
    }

    /// Identical models can occupy the same connector at different times.
    /// Without a serial the reference is valid only for this attachment.
    static func connection(path: String, displaySerial: UInt32, serviceSerial: Int64, entryID: UInt64)
        -> (path: String, persistent: Bool)? {
        let displayKnown = displaySerial != 0 && displaySerial != UInt32.max
        let serviceKnown = serviceSerial > 0 && serviceSerial < Int64(UInt32.max)
        if displayKnown && serviceKnown && Int64(displaySerial) != serviceSerial { return nil }
        if displayKnown { return (path, true) }
        if serviceKnown { return ("\(path)#\(serviceSerial)", true) }
        guard entryID != 0 else { return nil }
        return ("\(path)@\(entryID)", false)
    }

    /// Choices and reported ranges belong to one connection. The service
    /// serializes changes and forgets anonymous attachments after removal.
    struct Preferences {
        let defaults: UserDefaults
        var temporary: [String: Preference] = [:]

        func value(for path: String, persistent: Bool) -> Preference? {
            guard persistent else { return temporary[path] }
            guard let data = defaults.dictionary(forKey: DefaultsKey.displaySpeakerPreferences)?[path] as? Data
            else { return nil }
            return try? PropertyListDecoder().decode(Preference.self, from: data)
        }

        mutating func save(_ preference: Preference, for path: String, persistent: Bool) {
            guard !path.isEmpty else { return }
            if !persistent {
                temporary[path] = preference
                return
            }
            guard let data = try? PropertyListEncoder().encode(preference) else { return }
            var choices = defaults.dictionary(forKey: DefaultsKey.displaySpeakerPreferences) ?? [:]
            choices[path] = data
            defaults.set(choices, forKey: DefaultsKey.displaySpeakerPreferences)
        }

        /// Refresh a reference the person already chose when the monitor
        /// starts answering again. Remember a reported range even for a
        /// monitor whose manual control has never been enabled.
        mutating func rememberReported(_ level: BrightnessSupport.SpeakerLevel?, muted: Bool?,
                                       for path: String, persistent: Bool) -> Preference? {
            let saved = value(for: path, persistent: persistent)
            guard saved != nil || (level?.maximum ?? 100) != 100 else { return nil }
            var choice = saved ?? Preference(enabled: true)
            if let level { choice.maximum = level.maximum }
            if choice.raw != nil {
                choice.raw = level.flatMap { $0.raw > 0 && muted != true ? $0.raw : nil }
            }
            if choice != saved { save(choice, for: path, persistent: persistent) }
            return choice
        }
    }

    /// Steps use the last raw level. A previously reported range wins over
    /// the conventional percentage scale. Zero can mean the monitor's
    /// factory volume, so only positive levels go to a write-only channel.
    static func apply(_ change: BrightnessSupport.SpeakerChange, setup: Setup,
                      write: (UInt16) -> Bool) -> Preference? {
        guard setup.writeOnly, setup.enabled, var next = setup.preference, var raw = next.raw else { return nil }
        switch change {
        case let .set(.some(level), nil):
            guard level.isFinite else { return nil }
            raw = max(1, BrightnessSupport.deviceValue(for: level, maximum: next.maximum))
        case let .step(levels, _):
            guard !levels.isEmpty else { return nil }
            for step in levels {
                let current = Double(raw) / Double(next.maximum)
                let requested = step(current)
                guard requested.isFinite else { return nil }
                let rounded = max(1, BrightnessSupport.deviceValue(for: requested, maximum: next.maximum))
                if rounded != raw { raw = rounded }
                else if requested > current && raw < next.maximum { raw += 1 }
                else if requested < current && raw > 1 { raw -= 1 }
            }
        default: return nil
        }
        guard write(raw) else { return nil }
        next.raw = raw
        return next
    }
}
