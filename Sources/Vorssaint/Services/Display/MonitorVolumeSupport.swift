// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The logic behind a monitor's own speaker volume, kept apart from the DDC
/// channel it travels over. Monitors answer VCP 0x62 (Audio Speaker Volume)
/// and some 0x8D (Audio Mute) over DDC/CI, but many answer no reads at all
/// (the same monitors the brightness slider calls write-only), so the level
/// shown here is the last one this app wrote, never a reading.
enum MonitorVolumeSupport {
    /// VCP codes of the MCCS standard.
    static let volumeCode: UInt8 = 0x62
    static let muteCode: UInt8 = 0x8D
    /// 0x8D takes 1 to mute and 2 to unmute.
    static let muteOn: UInt16 = 1
    static let muteOff: UInt16 = 2
    /// The range a monitor that reports none is taken to have.
    static let defaultMaximum: UInt16 = 100
    /// One key press, as the system's own volume keys step by sixteenths.
    static let keyStep = 1.0 / 16.0
    /// Where a monitor sitting at silence starts when it is unmuted.
    static let unmuteFloor = keyStep

    /// How silence is reached. Setting the volume to zero works on every
    /// monitor that takes 0x62; 0x8D keeps the volume where it was but not
    /// every monitor honours it.
    enum MuteMethod: String, Equatable {
        case volumeZero
        case muteCode
    }

    /// One DDC write a change needs, in order.
    enum Command: Equatable {
        case volume(UInt16)
        case mute(UInt16)
    }

    /// What the app knows of a monitor's speakers: the level it last set and
    /// whether silence was asked for. `level` keeps the audible level while
    /// muted, so unmuting brings it back instead of a guess.
    struct State: Codable, Equatable {
        var level: Double
        var muted: Bool

        init(level: Double = 0.125, muted: Bool = false) {
            self.level = level.isFinite ? min(max(level, 0), 1) : 0.125
            self.muted = muted
        }

        /// What the slider and the notice show.
        var shown: Double { muted ? 0 : level }

        /// Moves the level by `delta`, a press of the volume keys. A monitor
        /// that was muted comes back first, at the stepped level, so a
        /// press up from silence is heard.
        mutating func step(delta: Double, maximum: UInt16 = defaultMaximum,
                           method: MuteMethod) -> [Command] {
            guard delta.isFinite else { return [] }
            return set(level: level + delta, maximum: maximum, method: method)
        }

        /// Sets the audible level, from a slider or a step. Setting any level
        /// above zero ends a mute.
        mutating func set(level proposed: Double, maximum: UInt16 = defaultMaximum,
                          method: MuteMethod) -> [Command] {
            guard proposed.isFinite else { return [] }
            let wasMuted = muted
            level = min(max(proposed, 0), 1)
            muted = false
            var commands: [Command] = []
            if wasMuted, method == .muteCode { commands.append(.mute(muteOff)) }
            commands.append(.volume(deviceValue(level, maximum: maximum)))
            return commands
        }

        /// F10: silences, or brings back the level before it. A level of
        /// zero comes back at the floor, so unmuting is always heard.
        mutating func toggleMute(maximum: UInt16 = defaultMaximum, method: MuteMethod) -> [Command] {
            if muted {
                muted = false
                if level < unmuteFloor { level = unmuteFloor }
                switch method {
                case .volumeZero: return [.volume(deviceValue(level, maximum: maximum))]
                case .muteCode: return [.mute(muteOff), .volume(deviceValue(level, maximum: maximum))]
                }
            }
            muted = true
            switch method {
            case .volumeZero: return [.volume(0)]
            case .muteCode: return [.mute(muteOn)]
            }
        }
    }

    /// Merges writes waiting for the channel: of volumes with no mute between
    /// them only the newest matters, so a held key or a drag sends what it
    /// ended on and never a queue of steps the monitor would run behind.
    static func collapsed(_ commands: [Command]) -> [Command] {
        var result: [Command] = []
        for command in commands {
            if case .volume = command, case .volume? = result.last { result.removeLast() }
            result.append(command)
        }
        return result
    }

    /// The value a monitor with this range takes for `level`.
    static func deviceValue(_ level: Double, maximum: UInt16) -> UInt16 {
        BrightnessSupport.deviceValue(for: level, maximum: BrightnessSupport.sanitizedMaximum(maximum))
    }

    /// The packet of a command, which the brightness code sends as well.
    static func packet(for command: Command) -> [UInt8] {
        switch command {
        case .volume(let value): return BrightnessSupport.writePacket(code: volumeCode, value: value)
        case .mute(let value): return BrightnessSupport.writePacket(code: muteCode, value: value)
        }
    }

    // MARK: - Keys

    enum Key: Equatable {
        case up, down, mute
    }

    struct KeyPress: Equatable {
        let key: Key
        let isDown: Bool
        let isRepeat: Bool
    }

    /// A volume key as the system sends it: the media-key subtype, with the
    /// key in the top half of `data1` (0 up, 1 down, 7 mute) and the state in
    /// the byte below (0xA down, 0xB up).
    static func keyPress(subtype: Int, data1: Int) -> KeyPress? {
        guard subtype == 8 else { return nil }
        let raw = UInt32(truncatingIfNeeded: data1)
        let state = Int((raw >> 8) & 0xFF)
        guard state == 0x0A || state == 0x0B else { return nil }
        let key: Key
        switch (raw >> 16) & 0xFFFF {
        case 0: key = .up
        case 1: key = .down
        case 7: key = .mute
        default: return nil
        }
        return KeyPress(key: key, isDown: state == 0x0A, isRepeat: raw & 0x1 != 0)
    }

    // MARK: - Which monitor

    struct Candidate: Equatable {
        let id: UInt32
        let name: String
    }

    /// The monitor a volume key belongs to: the one whose speakers the Mac is
    /// playing through. macOS cannot change the volume of a display output, so
    /// its keys do nothing there, and that is the one case taken over. The
    /// output is a display's when it travels over DisplayPort or HDMI and is
    /// named like a connected monitor; when two share a name the pointer picks.
    static func target(outputIsDisplayAudio: Bool, outputName: String?,
                       candidates: [Candidate], pointerDisplay: UInt32?) -> UInt32? {
        guard outputIsDisplayAudio, let outputName else { return nil }
        let wanted = normalized(outputName)
        guard !wanted.isEmpty else { return nil }
        let matches = candidates.filter { normalized($0.name) == wanted }
        if matches.count > 1, let pointerDisplay, matches.contains(where: { $0.id == pointerDisplay }) {
            return pointerDisplay
        }
        return matches.first?.id
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: - Memory

    /// Keeps what was last set on each monitor, by monitor, bounded.
    static func updatedStates(_ stored: [String: State], fingerprint: String, state: State,
                              limit: Int = 16) -> [String: State] {
        guard !fingerprint.isEmpty, limit > 0 else { return stored }
        var updated = stored
        if updated[fingerprint] == nil, updated.count >= limit,
           let oldest = updated.keys.sorted().first { updated.removeValue(forKey: oldest) }
        updated[fingerprint] = state
        return updated
    }

    /// Whether a monitor's volume is offered. One that answered a reading of
    /// 0x62 has shown it speaks the control. One that answers no reading can
    /// only be tested by listening, so it is offered once a person turns it on
    /// for that monitor, and never before.
    static func isOffered(volumeReplied: Bool, chosenByPerson: Bool, hasDDCRoute: Bool) -> Bool {
        hasDDCRoute && (volumeReplied || chosenByPerson)
    }
}
