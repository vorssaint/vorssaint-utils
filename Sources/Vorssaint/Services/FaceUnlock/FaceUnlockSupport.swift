// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How closely a face must match an enrolled one. The three steps are the
/// similarity thresholds the recognizer is compared against; a wrong guess in
/// either direction is a trade between letting the owner in the first time and
/// keeping everyone else out, so only these three are offered.
enum FaceUnlockStrictness: String, CaseIterable, Identifiable {
    case relaxed, standard, strict

    var id: String { rawValue }

    var threshold: Float {
        switch self {
        case .relaxed: return 0.60
        case .standard: return 0.66
        case .strict: return 0.72
        }
    }

    static func sanitized(_ raw: String?) -> FaceUnlockStrictness {
        raw.flatMap(FaceUnlockStrictness.init(rawValue:)) ?? .standard
    }
}

/// How hard the camera is made to prove a live person is in front of it.
enum FaceUnlockLiveness: String, CaseIterable, Identifiable {
    case off, light, heavy

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> FaceUnlockLiveness {
        raw.flatMap(FaceUnlockLiveness.init(rawValue:)) ?? .light
    }
}

/// How long the opened session may sit unused before it asks for Touch ID
/// again. The session key is only ever held in memory.
enum FaceUnlockSessionLimit: String, CaseIterable, Identifiable {
    case sevenDays, fourteenDays, thirtyDays, never

    var id: String { rawValue }

    var duration: TimeInterval? {
        let day: TimeInterval = 24 * 60 * 60
        switch self {
        case .sevenDays: return 7 * day
        case .fourteenDays: return 14 * day
        case .thirtyDays: return 30 * day
        case .never: return nil
        }
    }

    static func sanitized(_ raw: String?) -> FaceUnlockSessionLimit {
        raw.flatMap(FaceUnlockSessionLimit.init(rawValue:)) ?? .thirtyDays
    }
}

/// What the Mac's lock state just did, as the monitor reports it.
enum FaceUnlockLockEvent: Equatable {
    case locked
    case unlocked
    case willSleep
    /// The display came back, from system sleep, display sleep or the
    /// screen saver stopping.
    case wake
}

/// What the lock screen shows while a scan is under way. The island's padlock
/// follows it.
enum FaceUnlockPhase: Equatable {
    /// Nothing is looking: the padlock sits as it always does.
    case idle
    /// Ready to look, camera off. A tap starts a scan.
    case armed
    case scanning
    case success
    case failure(FaceUnlockFailure)
}

enum FaceUnlockFailure: Equatable {
    case notRecognized
    case notLive
    case noFace
    case cameraUnavailable
    /// The saved password was typed and the Mac stayed locked: it is probably
    /// out of date, and typing it again would only count more wrong attempts.
    case passwordRejected
}

/// Why Face Unlock cannot act right now, in the order a person fixes them.
enum FaceUnlockBlocker: Equatable {
    case notEnabled
    /// The face model is missing from the app, and the weaker fallback is not
    /// trusted to open a lock screen.
    case modelUnavailable
    /// Two saved-password attempts failed in a row; it needs saving again.
    case passwordOutdated
    case needsAccessibility
    case needsCamera
    case sessionLocked
    case needsPassword
    case needsFace
}

enum FaceUnlockSupport {
    static let scanSecondsRange = 3...10
    static let defaultScanSeconds = 5
    /// A face narrower than this fraction of the frame is someone passing
    /// behind, not the person at the keyboard.
    static let minimumFaceWidth: Float = 0.19
    /// A sustained wrong face resolves a scan; a few early frames do not,
    /// because a wake often finds the owner still looking away.
    static let wrongFaceGrace: TimeInterval = 2

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.faceUnlock.isAvailable(in: defaults) && defaults.bool(forKey: DefaultsKey.faceUnlockEnabled)
    }

    static func scanSeconds(in defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: DefaultsKey.faceUnlockScanSeconds) as? Int ?? defaultScanSeconds
        return min(max(stored, scanSecondsRange.lowerBound), scanSecondsRange.upperBound)
    }

    static func strictness(in defaults: UserDefaults = .standard) -> FaceUnlockStrictness {
        .sanitized(defaults.string(forKey: DefaultsKey.faceUnlockStrictness))
    }

    static func liveness(in defaults: UserDefaults = .standard) -> FaceUnlockLiveness {
        .sanitized(defaults.string(forKey: DefaultsKey.faceUnlockLiveness))
    }

    static func sessionLimit(in defaults: UserDefaults = .standard) -> FaceUnlockSessionLimit {
        .sanitized(defaults.string(forKey: DefaultsKey.faceUnlockSessionLimit))
    }

    /// With neither trigger chosen nothing would ever start a scan, so the
    /// settings keep one on; a backup that turned both off reads as wake.
    static func triggersOnWake(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.faceUnlockOnWake) || !defaults.bool(forKey: DefaultsKey.faceUnlockOnLock)
    }

    static func triggersOnLock(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.faceUnlockOnLock)
    }

    /// The padlock scans in the island only where the island's lock screen
    /// layer is on; without it Face Unlock still works, just unseen.
    static func showsOnLockScreen(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.faceUnlockShowOnLockScreen)
    }

    /// The first thing standing between the person and an unlock, or nil when
    /// nothing does. Pure, so the order is pinned by tests.
    static func blocker(isEnabled: Bool, modelAvailable: Bool, passwordRejectedTwice: Bool,
                        accessibility: Bool, camera: Bool, sessionUnlocked: Bool,
                        hasPassword: Bool, hasActiveFace: Bool) -> FaceUnlockBlocker? {
        if !isEnabled { return .notEnabled }
        if !modelAvailable { return .modelUnavailable }
        if passwordRejectedTwice { return .passwordOutdated }
        if !accessibility { return .needsAccessibility }
        if !camera { return .needsCamera }
        if !sessionUnlocked { return .sessionLocked }
        if !hasPassword { return .needsPassword }
        if !hasActiveFace { return .needsFace }
        return nil
    }

    /// Whether an opened session has been idle past its limit.
    static func sessionExpired(lastActivity: Date?, limit: FaceUnlockSessionLimit, now: Date = Date()) -> Bool {
        guard let lastActivity, let duration = limit.duration else { return false }
        return now.timeIntervalSince(lastActivity) >= duration
    }

    /// A lock event arms a scan only when its own trigger is chosen. The
    /// display waking arms on wake; the Mac locking while awake arms on lock.
    static func armsScan(event: FaceUnlockLockEvent, onWake: Bool, onLock: Bool) -> Bool {
        switch event {
        case .wake: return onWake
        case .locked: return onLock
        case .unlocked, .willSleep: return false
        }
    }
}
