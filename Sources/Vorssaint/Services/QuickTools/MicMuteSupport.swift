// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind a global microphone mute, kept apart from the audio
/// calls so they can be pinned down by tests: which devices the mute has to
/// reach, which ones it must never touch, and how a device gets its level back.
enum MicMuteSupport {
    /// The app's own private aggregate devices: the mixer's, the island's
    /// level reader's and the recorder's. Each carries a tapped app's audio,
    /// not a microphone, and muting one would silence the very thing it is
    /// rendering or reading; a private aggregate is still listed to the
    /// process that created it, so every device list skips them by name.
    static let ownDeviceNames: Set<String> = ["Vorssaint Mixer", "Vorssaint AirPlay", "Vorssaint Island Levels",
                                              "Vorssaint Recorder"]

    /// A restore bound to the old default input and its scalar elements can
    /// lack an original gain. Its historical fallback was 75 percent.
    static let fallbackVolume: Float = 0.75
    /// Drivers may rebound to a small positive gain after a zero write. It
    /// still needs to be zeroed and cannot establish a call's unmute.
    static let residualGainLimit: Float = 0.01
    /// Devices without a readable stream layout still get the stereo pair
    /// tried, the way the mute used to.
    static let minimumChannelCount = 2
    /// CoreAudio's master element. Kept as a number so this file stays
    /// free of the HAL import the tests do not need.
    static let masterElement: UInt32 = 0

    static func isOwnDevice(name: String) -> Bool {
        ownDeviceNames.contains(name)
    }

    /// A level worth remembering. Saving a zero would make the unmute restore
    /// silence, which is how a re-applied mute could strand a microphone.
    static func shouldSaveVolume(_ volume: Float?) -> Bool {
        guard let volume else { return false }
        return volume > 0 && volume <= 1
    }

    /// The first real level is the one unmute should put back. A later
    /// re-apply, from an app raising gain while we are muted, must not
    /// replace it or the user would get that app's level instead of their own.
    static func shouldReplaceSavedVolume(existing: Double?, current: Float?) -> Bool {
        if let existing, shouldSaveVolume(Float(existing)) { return false }
        return shouldSaveVolume(current)
    }

    /// Capture is silent only when the input volume is down, because that is
    /// the control recording apps actually hear. A mute switch that reads
    /// engaged while the level is still live is not silence; a device with
    /// no volume control at all still counts the switch.
    static func isCaptureSilenced(muteSwitch: UInt32?, volume: Float?) -> Bool {
        if let volume { return volume == 0 }
        return muteSwitch == 1
    }

    /// A microphone the user silenced themselves is left alone, so unmuting
    /// later never opens something this app did not close. One this app
    /// already muted is still ours even when it is already quiet.
    static func shouldLeaveUntouched(owned: Bool, captureSilenced: Bool) -> Bool {
        !owned && captureSilenced
    }

    struct InputControls {
        enum Gain { case unavailable, unreadable, silent, audible }
        let gain: Gain
        let muteSwitch: UInt32?
        /// Gain addresses actually read at zero.
        var silentGains: Set<String> = []
        /// Engaged switches covering the input or channels without gain.
        var mutedElements: Set<UInt32> = []

        var isSilenced: Bool {
            gain == .silent || (gain == .unavailable && muteSwitch == 1)
        }

        /// A driver losing a readable gain control does not establish that it opened.
        func opened(since previous: InputControls) -> Bool {
            previous.isSilenced && ((previous.gain == .silent && gain == .audible)
                || ((previous.muteSwitch == 1 || !previous.mutedElements.isEmpty) && muteSwitch == 0))
        }
    }

    /// Master first, then every channel the stream layout named, never fewer
    /// than a stereo pair so a device that hides its count still gets 1 and 2.
    static func inputChannelElements(channelCount: Int) -> [UInt32] {
        let channels = max(channelCount, minimumChannelCount)
        return [masterElement] + (1...channels).map { UInt32($0) }
    }

    /// The sweep resolves historical claims before choosing which of the
    /// connected microphones it can release.
    static func restoreTargets(recorded: [String], present: [String]) -> [String] {
        let wanted = Set(recorded)
        return present.filter { wanted.contains($0) }
    }

    /// The claims a sweep carries forward untouched: the devices this app
    /// silenced that are not here right now. A headset unplugged while muted
    /// comes back still silenced, and it is still this app's to release;
    /// dropping the claim would leave it muted with nothing left to unmute it.
    static func absentClaims(recorded: [String]?, present: [String]) -> [String] {
        let here = Set(present)
        return (recorded ?? []).filter { !here.contains($0) }
    }

    /// Retries belong to one control on one input. A driver can change the
    /// reported gain on each refusal without changing which setter failed.
    struct Retry {
        enum Reason { case unconfirmed, smallRebound, idleVirtual }
        let reason: Reason
        let attempts: Int
        let deadline: TimeInterval?
        let wasIdleVirtual: Bool
        private let waitsForStableZero: Bool
        private var zeroSince: TimeInterval?
        private static let settlingInterval: TimeInterval = 0.25
        private static let maximumAttempts = 10

        /// After the timed attempts, hardware notices can still recheck the
        /// control at the same capped cadence without polling indefinitely.
        var scheduledDeadline: TimeInterval? {
            if let zeroSince, reason != .idleVirtual || deadline != nil { return zeroSince + Self.settlingInterval }
            return attempts < Self.maximumAttempts ? deadline : nil
        }

        init(reason: Reason, smallGain: Bool, idleVirtual: Bool, previous: Retry?, now: TimeInterval) {
            self.reason = reason
            wasIdleVirtual = idleVirtual
            zeroSince = reason == .unconfirmed ? nil : now
            // The address owns the burst. A different result of the next
            // setter only changes how its next opening should be handled.
            if let previous {
                attempts = min(previous.attempts + 1, Self.maximumAttempts)
                waitsForStableZero = previous.waitsForStableZero || smallGain || reason == .idleVirtual
            } else {
                attempts = 1
                waitsForStableZero = smallGain || reason == .idleVirtual
            }
            // A driver can recover silently even after its very first refusal.
            // Allow a short burst of callbacks before throttling this setter.
            if reason == .unconfirmed || attempts >= 3 {
                deadline = now + min(30, 0.25 * Double(1 << max(0, attempts - 3)))
            } else {
                deadline = nil
            }
        }

        func defers(_ value: Double, idle: Bool, now: TimeInterval) -> Bool {
            guard attempts >= 3, let deadline, now < deadline, !wasIdleVirtual || idle else { return false }
            switch reason {
            case .unconfirmed: return idle || zeroSince == nil || Self.isSmallGain(value)
            case .smallRebound: return Self.isSmallGain(value)
            case .idleVirtual: return idle
            }
        }

        func observingZero(now: TimeInterval) -> Self? {
            guard waitsForStableZero else { return nil }
            // Repeated reads during one HAL sweep can all see the same brief
            // zero. Clear the history only after a later observation agrees.
            if let zeroSince, now >= zeroSince + Self.settlingInterval { return nil }
            var retry = self
            retry.zeroSince = zeroSince ?? now
            return retry
        }

        func observingOpen() -> Self {
            var retry = self
            retry.zeroSince = nil
            return retry
        }

        func waitingForReadableControl(now: TimeInterval) -> Self? {
            if zeroSince == nil {
                guard reason == .unconfirmed || waitsForStableZero else { return nil }
                if let deadline, now < deadline { return self }
            }
            return Self(reason: .unconfirmed, smallGain: false, idleVirtual: wasIdleVirtual, previous: self, now: now)
        }

        static func isSmallGain(_ value: Double) -> Bool {
            value > 0 && value <= Double(residualGainLimit)
        }
    }
}
