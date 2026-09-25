// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Only an observed media key can explain an automatic music-app launch.
/// Absence of a click is not evidence: voice, automation and login can all
/// open an app intentionally without a keyboard or pointer gesture.
enum MusicLaunchSupport {
    static let systemDefinedEventTypeRawValue: UInt32 = 14
    static let auxiliaryControlButtonsSubtype = 8
    static let keyDownState = 10
    /// Launch Services needs a moment after the key to start the app.
    static let launchArmWindow: TimeInterval = 2.0
    static let playPauseKeyCode: UInt16 = 16
    static let nextTrackKeyCode: UInt16 = 17
    static let previousTrackKeyCode: UInt16 = 18
    static let fastForwardKeyCode: UInt16 = 19
    static let rewindKeyCode: UInt16 = 20

    static let musicLaunchKeyCodes: Set<UInt16> = [
        playPauseKeyCode, nextTrackKeyCode, previousTrackKeyCode,
        fastForwardKeyCode, rewindKeyCode
    ]

    /// A player opened in place of the music app gets this long to finish
    /// launching, then this long to settle before it is asked to play.
    static let replacementLaunchTimeout: TimeInterval = 15
    static let replacementSettleDelay: TimeInterval = 1
    static let playbackAttempts = 3

    /// True for the key-down of a media key that would otherwise open the
    /// music app. Releases, auto-repeat and volume or brightness keys do not
    /// count, so those never arm the blocker.
    static func isMusicLaunchTrigger(subtype: Int, data1: Int) -> Bool {
        guard subtype == auxiliaryControlButtonsSubtype else { return false }
        let raw = UInt32(truncatingIfNeeded: data1)
        let state = Int((raw >> 8) & 0xFF)
        guard state == keyDownState, (raw & 0x1) == 0 else { return false }
        return musicLaunchKeyCodes.contains(keyCode(data1: data1))
    }

    static func keyCode(data1: Int) -> UInt16 {
        UInt16((UInt32(truncatingIfNeeded: data1) >> 16) & 0xFFFF)
    }

    /// procNotFound and connectionInvalid: the player was not listening yet,
    /// so the command never arrived and asking again cannot play twice. Any
    /// other failure, a timeout included, may follow delivery.
    static func playbackNeverArrived(_ status: Int) -> Bool {
        status == -600 || status == -609
    }

    /// A newer click or key press takes precedence over a media key. Invalid
    /// or expired evidence always leaves the launch alone. An infinite gesture
    /// age means the session has never seen one, and still needs a real key.
    static func shouldBlockLaunch(now: TimeInterval,
                                  lastTriggerAt: TimeInterval?,
                                  secondsSinceUserGesture: TimeInterval) -> Bool {
        guard now.isFinite, now >= 0, let lastTriggerAt,
              lastTriggerAt.isFinite, lastTriggerAt >= 0,
              !secondsSinceUserGesture.isNaN, secondsSinceUserGesture >= 0 else { return false }
        let elapsed = now - lastTriggerAt
        return (0...launchArmWindow).contains(elapsed) && secondsSinceUserGesture > elapsed
    }
}

/// Sends the playback keys to the music player instead of whatever the system
/// last saw playing, which is often a browser tab.
enum MediaKeyPlayerSupport {
    enum Command: Equatable, Hashable, CaseIterable {
        case toggle, next, previous

        /// The scripting dictionary command that carries it out. A player
        /// without `playpause` keeps the toggle with the system: its `play`
        /// alone could only start playback, never pause it.
        var dictionaryName: String {
            switch self {
            case .toggle: return "playpause"
            case .next: return "next track"
            case .previous: return "previous track"
            }
        }
    }

    enum KeyPhase: Equatable { case down, repeatDown, up }

    struct Key: Equatable {
        let command: Command
        let code: UInt16
        let phase: KeyPhase
    }

    /// Apple keyboards send fast-forward and rewind for the track keys, so
    /// both pairs mean next and previous.
    static func key(subtype: Int, data1: Int) -> Key? {
        guard subtype == MusicLaunchSupport.auxiliaryControlButtonsSubtype else { return nil }
        let code = MusicLaunchSupport.keyCode(data1: data1)
        let command: Command
        switch code {
        case MusicLaunchSupport.playPauseKeyCode: command = .toggle
        case MusicLaunchSupport.nextTrackKeyCode, MusicLaunchSupport.fastForwardKeyCode: command = .next
        case MusicLaunchSupport.previousTrackKeyCode, MusicLaunchSupport.rewindKeyCode: command = .previous
        default: return nil
        }
        let raw = UInt32(truncatingIfNeeded: data1)
        let state = Int((raw >> 8) & 0xFF)
        let phase: KeyPhase
        switch state {
        case MusicLaunchSupport.keyDownState: phase = (raw & 0x1) == 0 ? .down : .repeatDown
        case 11: phase = .up
        default: return nil
        }
        return Key(command: command, code: code, phase: phase)
    }

    /// Whether macOS lets this app send Apple Events to the player.
    enum Access: Equatable { case granted, consent, denied }

    /// A running music app as the snapshot saw it, off the tap.
    struct Player: Equatable {
        let pid: Int32
        let bundleIdentifier: String
        let launched: Date?
        let commands: Set<Command>
        let access: Access
    }

    /// A process Core Audio reports as producing output. Helpers carry
    /// their app's identifier as a prefix.
    struct SoundingProcess: Equatable {
        let pid: Int32
        let bundleIdentifier: String?
    }

    enum Route: Equatable {
        /// The key keeps its system behavior.
        case system
        case player(Int32)
        /// The player needs consent first; the key keeps its system behavior
        /// this time.
        case askConsent(Int32)
    }

    static func sounds(_ player: Player, in sounding: [SoundingProcess]) -> Bool {
        sounding.contains { process in
            process.pid == player.pid
                || process.bundleIdentifier.map {
                    $0 == player.bundleIdentifier || $0.hasPrefix(player.bundleIdentifier + ".")
                } == true
        }
    }

    /// Where a playback key goes. A player that is sounding takes it first.
    /// With every player silent, sound from any other app (a video, a
    /// podcast, a browser tab) keeps the key with the system, so the key
    /// pauses what is audible instead of starting music on top of it. With
    /// nothing sounding, the player last brought forward takes it, then the
    /// one launched last.
    static func route(_ command: Command, players: [Player], sounding: [SoundingProcess],
                      lastActivePID: Int32?, ownPID: Int32) -> Route {
        let usable = players.filter { $0.commands.contains(command) }
        guard !usable.isEmpty else { return .system }
        let playing = usable.filter { sounds($0, in: sounding) }
        let otherSounds = sounding.contains { process in
            process.pid != ownPID && !usable.contains { sounds($0, in: [process]) }
        }
        let pool: [Player]
        if !playing.isEmpty {
            pool = playing
        } else if otherSounds {
            return .system
        } else {
            pool = usable
        }
        guard let pid = preferredPlayer(pool, lastActivePID: lastActivePID),
              let chosen = pool.first(where: { $0.pid == pid }) else { return .system }
        switch chosen.access {
        case .granted: return .player(pid)
        case .consent: return .askConsent(pid)
        case .denied: return .system
        }
    }

    /// The player last brought to the front, then the one launched last.
    static func preferredPlayer(_ players: [Player], lastActivePID: Int32?) -> Int32? {
        if let lastActivePID, players.contains(where: { $0.pid == lastActivePID }) { return lastActivePID }
        return players.max {
            ($0.launched ?? .distantPast, -$0.pid) < ($1.launched ?? .distantPast, -$1.pid)
        }?.pid
    }
}
