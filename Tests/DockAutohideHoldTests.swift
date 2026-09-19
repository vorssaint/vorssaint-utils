// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DockAutohideHoldTests {
    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.dock-hold.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let marker = DefaultsKey.dockPreviewRestoreAutohide
        var autohide: Bool? = true
        var writes: [Bool] = []
        var acceptsWrites = true
        let makeHold = {
            DockAutohideHold(defaults: defaults, readAutohide: { autohide }, writeAutohide: {
                writes.append($0)
                guard acceptsWrites else { return false }
                autohide = $0
                return true
            })
        }
        let hold = makeHold()
        suite.expect(writes.isEmpty, "starting without a recovery marker never changes the Dock")
        suite.expect(hold.begin() && autohide == false && hold.isHolding,
                     "an auto-hidden Dock stays visible for the preview session")
        suite.expect(defaults.bool(forKey: marker), "the original auto-hide is recoverable while held")
        suite.expect(hold.begin() && writes == [false], "switching preview apps reuses the hold")
        hold.end()
        hold.end()
        suite.expect(autohide == true && !hold.isHolding && writes == [false, true],
                     "ending or disabling a session restores auto-hide exactly once")
        suite.expect(defaults.object(forKey: marker) == nil, "successful restoration clears recovery")

        writes = []
        autohide = false
        suite.expect(!hold.begin(), "a Dock already permanently visible is never changed")
        autohide = nil
        suite.expect(!hold.begin() && writes.isEmpty, "a missing private API leaves normal preview available")

        autohide = true
        acceptsWrites = false
        suite.expect(!hold.begin() && !hold.isHolding, "a rejected hold cannot masquerade as active")
        suite.expect(defaults.bool(forKey: marker), "failed restoration remains recoverable")
        acceptsWrites = true
        let recovered = makeHold()
        suite.expect(autohide == true && !recovered.isHolding && !defaults.bool(forKey: marker),
                     "the next startup retries an interrupted restoration even with the toggle off")

        autohide = true
        _ = hold.begin()
        acceptsWrites = false
        hold.end()
        suite.expect(!hold.isHolding && autohide == false && defaults.bool(forKey: marker),
                     "a failed release retains recovery instead of forgetting the system change")
        suite.expect(!hold.begin(), "a pending restoration cannot be overwritten by another session")
        acceptsWrites = true
        hold.end()
        suite.expect(autohide == true && !defaults.bool(forKey: marker),
                     "a subsequent release can finish restoring auto-hide")

        autohide = true
        _ = hold.begin()
        autohide = true // User re-enables auto-hide while the preview is open.
        hold.end()
        suite.expect(autohide == true && !hold.isHolding, "restoration preserves re-enabled auto-hide")

        autohide = true
        _ = hold.begin()
        let restarted = makeHold() // Simulate interruption without calling end().
        suite.expect(autohide == true && !restarted.isHolding && !defaults.bool(forKey: marker),
                     "a new process restores the pending preference after an interrupted preview")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.dockPreviewKeepDockVisible] as? Bool == false,
                     "the experiment is disabled by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.dockPreviewKeepDockVisible)
                     && !SettingsBackupSupport.exportKeys().contains(marker),
                     "backups carry the toggle but never another session's recovery state")
    }
}
