// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure decision logic for pausing the chosen music player whenever another
/// app produces audio, and resuming it once that other app stops. Kept free
/// of AppKit, Core Audio and MediaRemote so the state machine and AppleScript
/// commands can be tested without a running app.
enum AutoPauseMusicSupport {
    struct SourceActivity: Equatable {
        let bundleIdentifier: String
        let isRunningOutput: Bool
        let bypassesProcessTap: Bool
    }

    enum Decision: Equatable {
        case pause
        case resume
        case clearFlag
        case none
    }

    /// A competing stream must persist before it interrupts music, while a
    /// short gap must persist before music resumes. This filters notification
    /// dings and avoids pause/play churn between adjacent video segments.
    static let competingAudioStartDelay: TimeInterval = 1.0
    static let competingAudioStopDelay: TimeInterval = 2.0

    static let pausedMarker = "vorssaint-paused"

    /// True while a different app than the chosen player currently owns Now
    /// Playing and is actively producing sound.
    static func otherSourceIsActive(nowPlayingBundleID: String?,
                                    nowPlayingIsPlaying: Bool,
                                    musicPlayerBundleID: String) -> Bool {
        guard !musicPlayerBundleID.isEmpty, let nowPlayingBundleID, nowPlayingIsPlaying else { return false }
        return nowPlayingBundleID != musicPlayerBundleID
    }

    /// Turns the shared Core Audio process snapshot into the identities this
    /// feature may treat as competing output. IsRunningOutput is an active
    /// stream rather than an audibility meter; apps known to keep unmanaged
    /// streams open (calls and DAWs) are therefore excluded.
    static func activeBundleIdentifiers(from sources: [SourceActivity]) -> Set<String> {
        Set(sources.lazy.filter {
            $0.isRunningOutput && !$0.bypassesProcessTap
        }.map(\.bundleIdentifier))
    }

    /// True while Core Audio reports at least one eligible active-output app
    /// other than the music player. Unlike Now Playing metadata, this covers
    /// browser videos and apps that never publish a media session.
    static func otherAudioSourceIsActive(activeBundleIDs: Set<String>,
                                         musicPlayerBundleID: String) -> Bool {
        guard !musicPlayerBundleID.isEmpty else { return false }
        return activeBundleIDs.contains { $0 != musicPlayerBundleID }
    }

    /// MediaRemote's PID can belong to a browser helper that AppKit cannot
    /// resolve to an `NSRunningApplication`. Prefer the framework's direct
    /// display identifier and retain the PID-derived identifier as a fallback.
    static func nowPlayingBundleIdentifier(displayID: String?,
                                           pidBundleIdentifier: String?) -> String? {
        for candidate in [displayID, pidBundleIdentifier] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// `weAutoPaused` tracks whether this feature (not the user) is the
    /// reason the player is paused, so a manual pause is never mistaken for
    /// one to resume, and a resume never fires without a matching pause.
    static func decide(otherSourceIsActive: Bool,
                       weAutoPaused: Bool,
                       resumeEnabled: Bool) -> Decision {
        if otherSourceIsActive {
            return weAutoPaused ? .none : .pause
        }
        guard weAutoPaused else { return .none }
        return resumeEnabled ? .resume : .clearFlag
    }

    static func transitionDelay(stableOtherSourceIsActive: Bool,
                                observedOtherSourceIsActive: Bool) -> TimeInterval? {
        guard stableOtherSourceIsActive != observedOtherSourceIsActive else { return nil }
        return observedOtherSourceIsActive ? competingAudioStartDelay : competingAudioStopDelay
    }

    /// Reads state and pauses in one script execution. Besides cutting the
    /// number of blocking calls in half, the marker distinguishes a pause this
    /// feature performed from a player the user had already paused.
    static func pauseIfPlayingScript(bundleID: String) -> String {
        let target = AppleScriptRunner.literal(bundleID)
        return """
        tell application id \(target)
            if (player state as string) is "playing" then
                pause
                return "\(pausedMarker)"
            end if
        end tell
        return "vorssaint-unchanged"
        """
    }

    static func playScript(bundleID: String) -> String {
        "tell application id \(AppleScriptRunner.literal(bundleID)) to play"
    }

    static func didPause(output: String?) -> Bool {
        output?.trimmingCharacters(in: .whitespacesAndNewlines) == pausedMarker
    }

    /// Auto-pause has an explicit override, but adopts the Music blocker's
    /// replacement when no player was chosen here. The replacement cannot
    /// always be the same setting (Apple Music is a valid auto-pause target
    /// and an invalid replacement for a feature that blocks Apple Music).
    static func selectedPlayerPath(autoPausePath: String, musicBlockReplacementPath: String) -> String {
        autoPausePath.isEmpty ? musicBlockReplacementPath : autoPausePath
    }

    /// The bundle identifier of the .app the user picked in Settings, or nil
    /// for an empty or unreadable path (the picker only ever writes a valid
    /// application bundle, but a moved or deleted app must fail quietly).
    static func bundleIdentifier(forAppAtPath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        return Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
    }
}
