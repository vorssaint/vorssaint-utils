// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs production availability methods against isolated preferences and
/// records service synchronization, without starting input taps or hardware.
enum FeatureRuntimeContract {
    class Fixture {
        static let domain = "com.vorssaint.tests.discovery.\(UUID().uuidString)"
        static let defaults = UserDefaults(suiteName: domain)!
        static var supported = Set(AppFeature.allCases)
        var loadedThisSession: Set<AppFeature> = []
        var offerableThisSession: Set<AppFeature> = []
        var synchronized: [AppFeature] = []
        var revisions = 0
        var changeHistory = FeatureChangeHistory()
        func syncFeature(_ feature: AppFeature) { synchronized.append(feature) }
        func finishAvailabilityChange() { revisions += 1 }
        func savedPreferences() -> [String: Any] {
            Self.defaults.persistentDomain(forName: Self.domain) ?? [:]
        }
    }

    static func run(_ suite: TestSuite) {
        let defaults = Fixture.defaults
        defaults.register(defaults: Defaults.registeredDefaults)
        defaults.register(defaults: AppFeature.availabilityDefaults)
        defer { defaults.removePersistentDomain(forName: Fixture.domain) }
        let runtime = Host()
        runtime.replaceAvailable(with: [.clipboardHistory, .windowLayout])
        defaults.set(false, forKey: DefaultsKey.clipboardHistoryEnabled)
        defaults.set(false, forKey: DefaultsKey.windowLayoutShortcutsEnabled)
        defaults.set(false, forKey: DefaultsKey.notchInitialExtensionsInstalled)
        defaults.set("expert", forKey: DefaultsKey.settingsExperience)
        let available = Set(AppFeature.allCases.filter { $0.isAvailable(in: defaults) })
        let enabledKeys = Set(AppFeature.allCases.flatMap(\.enabledKeys))
        let savedBehavior = enabledKeys.map { defaults.bool(forKey: $0) }
        for view in SettingsExperience.allCases {
            defaults.set(view.rawValue, forKey: DefaultsKey.settingsExperience)
            _ = AppFeature.allCases.filter { view.shows($0) }
            _ = view.hiddenFeatureCount()
            suite.expect(Set(AppFeature.allCases.filter { $0.isAvailable(in: defaults) }) == available
                         && enabledKeys.map { defaults.bool(forKey: $0) } == savedBehavior,
                         "changing \(view.rawValue) visibility preserves availability and saved behavior")
        }
        defaults.removeObject(forKey: DefaultsKey.notchInitialExtensionsInstalled)
        defaults.removeObject(forKey: DefaultsKey.notchLyricsEnabled)
        let originalValues = runtime.configurationValues()
        for installAll in [true, false] {
            runtime.setAllAvailable(installAll)
            suite.expect(AppFeature.allCases.allSatisfy { $0.isAvailable(in: defaults) == installAll },
                         "bulk \(installAll ? "install" : "uninstall") changes every supported feature")
            runtime.undoLastFeatureChange()
            suite.expect(runtime.configurationValues() == originalValues,
                         "bulk Undo restores availability, saved off choices and unset preferences")
            suite.expect(defaults.persistentDomain(forName: Fixture.domain)?[DefaultsKey.notchInitialExtensionsInstalled] == nil,
                         "bulk Undo removes a first-install marker that was previously unset")
        }
        runtime.setAllAvailable(true)
        runtime.setAvailable([.switcher], false)
        runtime.turnOn(.clipboardHistory)
        runtime.undoLastFeatureChange()
        suite.expect(!defaults.bool(forKey: DefaultsKey.clipboardHistoryEnabled)
                     && !AppFeature.switcher.isAvailable(in: defaults),
                     "Undo reverses the latest manual behavior change without rolling back the bulk action")
        runtime.undoLastFeatureChange()
        suite.expect(AppFeature.switcher.isAvailable(in: defaults) && AppFeature.notch.isAvailable(in: defaults),
                     "the next Undo reverses only the manual inclusion change")
        defaults.set(true, forKey: DefaultsKey.windowGestureEnabled)
        runtime.undoLastFeatureChange()
        suite.expect(Set(AppFeature.allCases.filter { $0.isAvailable(in: defaults) }) == available
                     && defaults.bool(forKey: DefaultsKey.windowGestureEnabled),
                     "bulk Undo follows manual Undos and preserves unrelated settings edited since")
        runtime.redoLastFeatureChange()
        runtime.redoLastFeatureChange()
        runtime.redoLastFeatureChange()
        suite.expect(AppFeature.notch.isAvailable(in: defaults) && !AppFeature.switcher.isAvailable(in: defaults)
                     && defaults.bool(forKey: DefaultsKey.clipboardHistoryEnabled),
                     "Redo replays bulk, manual inclusion and behavior actions in order")
        runtime.undoLastFeatureChange()
        runtime.setAvailable([.switcher], true)
        suite.expect(runtime.changeHistory.redoCount == 0,
                     "a fresh manual edit clears Redo")
        while runtime.changeHistory.undoCount > 0 { runtime.undoLastFeatureChange() }
        var afterFirstTen: [String: Bool] = [:]
        for index in 0..<60 {
            runtime.setAvailable([.clipboardHistory], !AppFeature.clipboardHistory.isAvailable(in: defaults))
            if index == 9 { afterFirstTen = runtime.configurationValues() }
        }
        suite.expect(runtime.changeHistory.undoCount == 50, "feature history retains at most 50 changes")
        for _ in 0..<50 { runtime.undoLastFeatureChange() }
        suite.expect(runtime.configurationValues() == afterFirstTen && runtime.changeHistory.undoCount == 0,
                     "50 Undos reach the oldest retained state without undoing discarded actions")
        runtime.undoLastFeatureChange()
        suite.expect(runtime.configurationValues() == afterFirstTen, "Undo on an empty history is harmless")
        defaults.set(false, forKey: DefaultsKey.clipboardHistoryEnabled)
        runtime.setAvailable([.connectedDevices], true)
        runtime.setAvailable([.connectedDevices], false)
        suite.expect(runtime.synchronized.last == .connectedDevices,
                     "removing Connected Devices synchronizes its monitor immediately")
        let beforeUnusedRemoval = runtime.configurationValues()
        runtime.setAvailable([.clipboardHistory, .windowLayout], false)
        runtime.undoLastFeatureChange()
        suite.expect(runtime.configurationValues() == beforeUnusedRemoval
                     && !defaults.bool(forKey: DefaultsKey.clipboardHistoryEnabled),
                     "undoing unused-feature removal restores the batch without switching on saved off behaviors")
        runtime.setAvailable([.clipboardHistory], false)
        suite.expect(runtime.synchronized.last == .clipboardHistory,
                     "removing a feature synchronizes its teardown immediately")
        runtime.setAvailable([.clipboardHistory], true)
        suite.expect(!defaults.bool(forKey: DefaultsKey.clipboardHistoryEnabled),
                     "reinstalling preserves an explicit saved off choice")
        runtime.turnOn(.clipboardHistory)
        suite.expect(defaults.bool(forKey: DefaultsKey.clipboardHistoryEnabled)
                     && runtime.synchronized.last == .clipboardHistory,
                     "Turn on engages and synchronizes an included but off feature")
        runtime.setAvailable([.clipboardHistory], false)
        runtime.turnOn(.clipboardHistory)
        suite.expect(!AppFeature.clipboardHistory.isAvailable(in: defaults),
                     "Turn on cannot bypass feature availability")
        Fixture.supported.remove(.fanControl)
        runtime.setAvailable([.fanControl], true)
        suite.expect(!AppFeature.fanControl.isAvailable(in: defaults),
                     "unsupported hardware remains blocked through the shared install gate")
        Fixture.supported.insert(.fanControl)
    }
}
