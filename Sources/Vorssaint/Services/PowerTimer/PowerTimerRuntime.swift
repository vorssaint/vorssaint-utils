// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import IOKit.pwr_mgt

extension PowerTimerService {
    static let shared: PowerTimerService = {
        var assertion: IOPMAssertionID = 0
        return PowerTimerService(
            available: { AppFeature.powerTimer.isAvailable },
            sleepDisabled: {
                UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag)
                    || KeepAwakeManager.shared.clamshellSetupInProgress
            },
            acquireAssertion: {
                IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    "Vorssaint: waiting for the sleep or shutdown timer" as CFString,
                    &assertion) == kIOReturnSuccess
            },
            releaseAssertion: { IOPMAssertionRelease(assertion); assertion = 0 },
            authorize: { completion in
                DispatchQueue.global(qos: .userInitiated).async {
                    let allowed = AppleScriptRunner.consentToAutomate(bundleID: "com.apple.systemevents")
                    DispatchQueue.main.async { completion(allowed) }
                }
            },
            execute: { action, completion in
                DispatchQueue.global(qos: .userInitiated).async {
                    let ok: Bool
                    switch action {
                    case .sleep:
                        ok = Shell.run("/usr/bin/pmset", ["sleepnow"]).status == 0
                    case .shutDown:
                        guard Permissions.automationStatus(for: .systemEvents) == .granted else {
                            DispatchQueue.main.async { completion(false) }
                            return
                        }
                        ok = AppleScriptRunner.runDetailed(
                            "tell application \"System Events\" to shut down").ok
                    }
                    DispatchQueue.main.async { completion(ok) }
                }
            })
    }()
}
