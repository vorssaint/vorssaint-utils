// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Face Unlock's decisions that do not need a camera: what blocks it and in
/// which order, when a session expires, which events start a scan, how stored
/// choices are read back, and that every language has its words.
enum FaceUnlockTests {
    static func run(_ suite: TestSuite) {
        // MARK: Blockers read in the order a person fixes them

        func blocker(enabled: Bool = true, model: Bool = true, rejected: Bool = false, accessibility: Bool = true,
                     camera: Bool = true, session: Bool = true, password: Bool = true,
                     face: Bool = true) -> FaceUnlockBlocker? {
            FaceUnlockSupport.blocker(isEnabled: enabled, modelAvailable: model, passwordRejectedTwice: rejected,
                                      accessibility: accessibility, camera: camera, sessionUnlocked: session,
                                      hasPassword: password, hasActiveFace: face)
        }
        suite.expect(blocker() == nil, "with everything in place nothing blocks Face Unlock")
        suite.expect(blocker(enabled: false, accessibility: false) == .notEnabled,
                     "a switched off feature reports that before any missing permission")
        suite.expect(blocker(model: false, accessibility: false) == .modelUnavailable,
                     "a missing face model stops it before anything the person could grant")
        suite.expect(blocker(rejected: true, password: false) == .passwordOutdated,
                     "a password refused twice must be replaced before anything else is asked")
        suite.expect(blocker(accessibility: false, camera: false) == .needsAccessibility
                     && blocker(camera: false, session: false) == .needsCamera
                     && blocker(session: false, password: false) == .sessionLocked
                     && blocker(password: false, face: false) == .needsPassword
                     && blocker(face: false) == .needsFace,
                     "each missing piece is reported once the one before it is in place")

        // MARK: Sessions

        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 10_000_000)
        suite.expect(!FaceUnlockSupport.sessionExpired(lastActivity: nil, limit: .sevenDays, now: now),
                     "a locked session has no activity to age")
        suite.expect(!FaceUnlockSupport.sessionExpired(lastActivity: now.addingTimeInterval(-365 * day),
                                                       limit: .never, now: now),
                     "a session set to never expire does not, however long it sits")
        suite.expect(!FaceUnlockSupport.sessionExpired(lastActivity: now.addingTimeInterval(-6 * day),
                                                       limit: .sevenDays, now: now),
                     "a session inside its limit stays open")
        suite.expect(FaceUnlockSupport.sessionExpired(lastActivity: now.addingTimeInterval(-7 * day),
                                                      limit: .sevenDays, now: now),
                     "a session expires once idle for its whole limit")

        // MARK: Triggers

        suite.expect(FaceUnlockSupport.armsScan(event: .wake, onWake: true, onLock: false)
                     && !FaceUnlockSupport.armsScan(event: .wake, onWake: false, onLock: true),
                     "the display waking starts a scan only when waking is a chosen trigger")
        suite.expect(FaceUnlockSupport.armsScan(event: .locked, onWake: false, onLock: true)
                     && !FaceUnlockSupport.armsScan(event: .locked, onWake: true, onLock: false),
                     "locking starts a scan only when locking is a chosen trigger")
        suite.expect(![FaceUnlockLockEvent.unlocked, .willSleep].contains {
            FaceUnlockSupport.armsScan(event: $0, onWake: true, onLock: true)
        }, "unlocking and going to sleep never start a scan")

        // MARK: Stored choices

        let suiteName = "FaceUnlockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        suite.expect(FaceUnlockStrictness.sanitized("nonsense") == .standard
                     && FaceUnlockLiveness.sanitized(nil) == .light
                     && FaceUnlockSessionLimit.sanitized("forever") == .thirtyDays,
                     "a value from an edited backup falls back to the safe default")
        defaults.set(99, forKey: DefaultsKey.faceUnlockScanSeconds)
        suite.expect(FaceUnlockSupport.scanSeconds(in: defaults) == FaceUnlockSupport.scanSecondsRange.upperBound,
                     "an out of range scan time is held to the longest allowed")
        defaults.set(-4, forKey: DefaultsKey.faceUnlockScanSeconds)
        suite.expect(FaceUnlockSupport.scanSeconds(in: defaults) == FaceUnlockSupport.scanSecondsRange.lowerBound,
                     "a negative scan time is held to the shortest allowed")
        defaults.set(false, forKey: DefaultsKey.faceUnlockOnWake)
        defaults.set(false, forKey: DefaultsKey.faceUnlockOnLock)
        suite.expect(FaceUnlockSupport.triggersOnWake(in: defaults),
                     "with both triggers off a scan can still start on wake")
        suite.expect(FaceUnlockStrictness.strict.threshold > FaceUnlockStrictness.standard.threshold
                     && FaceUnlockStrictness.standard.threshold > FaceUnlockStrictness.relaxed.threshold,
                     "a stricter setting asks for a closer match")

        // MARK: Catalog

        suite.expect(AppFeature.faceUnlock.group == .authentication && AppFeature.privacyLock.group == .authentication,
                     "Face Unlock and Privacy Lock sit together in Authentication")
        suite.expect(AppFeature.faceUnlock.installedByDefault == false,
                     "Face Unlock is never installed by an update")
        suite.expect(AppFeature.faceUnlock.permissions == [.accessibility, .camera],
                     "Face Unlock declares the two permissions it uses")
        suite.expect(!AppFeature.faceUnlock.onboardingPermissions.contains(.accessibility),
                     "setup does not ask for Accessibility on behalf of a feature nobody chose")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.faceUnlockEnabled] as? Bool == false,
                     "Face Unlock starts switched off")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.faceUnlockCameraID)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.faceUnlockStrictness),
                     "the camera id stays on this Mac while the other choices travel in a backup")

        // MARK: Words

        for lang in AppLanguage.allCases {
            let strings = FeatureStrings.faceUnlock(lang)
            suite.expect(!strings.title.isEmpty && !strings.hubDescription.isEmpty && !strings.caution.isEmpty,
                         "Face Unlock has a title, a hub description and its caution in \(lang)")
            suite.expect(strings.scanSecondsFormat.contains("%d"),
                         "the scan time sentence carries its number in \(lang)")
            if lang != .enUS {
                suite.expect(strings.caution != FaceUnlockFeatureStrings.enUS.caution,
                             "the security caution is translated for \(lang)")
            }
        }
    }
}
