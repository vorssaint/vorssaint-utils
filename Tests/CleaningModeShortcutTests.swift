// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production shortcut lifecycle with isolated preferences and spies
/// for Carbon registration, session changes and the existing keyboard lock.
enum CleaningModeShortcutTests {
    enum UserDefaults { static var standard: Foundation.UserDefaults! }
    enum AppFeature {
        case cleaningMode
        static var available = true
        var isAvailable: Bool { Self.available }
    }
    enum ShortcutCapture { static var isCapturing = false }
    final class SessionActivity {
        static var shared = SessionActivity()
        var isActive = true
        var changed: ((Bool) -> Void)?
        func onChange(_ action: @escaping (Bool) -> Void) { changed = action }
        func setActive(_ active: Bool) { isActive = active; changed?(active) }
    }
    final class QuickToolHotkey {
        var onPress: (() -> Void)?
        var registered: GlobalShortcut?
        var storageKey: String?
        var succeeds = true
        init(id: UInt32) {}
        func sync(enabled: Bool, shortcut: GlobalShortcut, storageKey: String) -> Bool {
            registered = enabled && succeeds ? shortcut : nil
            self.storageKey = enabled && succeeds ? storageKey : nil
            return !enabled || succeeds
        }
        func unregister() { registered = nil; storageKey = nil }
    }
    class Fixture {
        let hotkey = QuickToolHotkey(id: 82)
        var isActive = false
        var shortcutRegistrationFailed = false
        var shouldRestoreSuspendedFeaturesOnSessionReturn = false
        var activations = 0
        var deactivations = 0
        var configuredShortcut = GlobalShortcut.cleaningModeDefault
        func activate() { if !isActive { isActive = true; activations += 1 } }
        func deactivate(restoreSuspendedFeatures: Bool) {
            if isActive { isActive = false; deactivations += 1 }
        }
        func resumeSuspendedFeatures() {}
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.cleaning-shortcut"
        let defaults = Foundation.UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defaults.register(defaults: Defaults.registeredDefaults)
        UserDefaults.standard = defaults
        SessionActivity.shared = SessionActivity()
        AppFeature.available = true
        ShortcutCapture.isCapturing = false
        defer {
            UserDefaults.standard = nil
            defaults.removePersistentDomain(forName: domain)
            SessionActivity.shared = SessionActivity()
            AppFeature.available = true
            ShortcutCapture.isCapturing = false
        }

        let service = Service()
        service.syncWithPreferences()
        suite.expect(service.hotkey.registered == nil && !service.shortcutRegistrationFailed,
                     "Cleaning Mode claims no shortcut by default")
        service.hotkey.onPress?()
        suite.expect(service.activations == 0, "a disabled shortcut cannot activate Cleaning Mode")

        defaults.set(true, forKey: DefaultsKey.cleaningModeShortcutEnabled)
        service.syncWithPreferences()
        suite.expect(service.hotkey.registered == .cleaningModeDefault
                     && service.hotkey.storageKey == DefaultsKey.cleaningModeShortcut,
                     "enabling Cleaning Mode registers its shortcut and takeover claim key")
        service.hotkey.onPress?()
        service.hotkey.onPress?()
        suite.expect(service.activations == 1 && service.isActive && service.deactivations == 0,
                     "the shortcut activates the lock and never toggles it off")

        service.configuredShortcut = .screenshotDefault
        service.syncWithPreferences()
        suite.expect(service.hotkey.registered == .screenshotDefault,
                     "editing the combination replaces the registered shortcut")

        defaults.set(false, forKey: DefaultsKey.cleaningModeShortcutEnabled)
        service.hotkey.onPress?()
        service.syncWithPreferences()
        suite.expect(service.hotkey.registered == nil && service.isActive,
                     "disabling the shortcut releases the key without ending an active cleaning session")
        defaults.set(true, forKey: DefaultsKey.cleaningModeShortcutEnabled)
        service.deactivate(restoreSuspendedFeatures: true)

        ShortcutCapture.isCapturing = true
        service.syncWithPreferences()
        service.hotkey.onPress?()
        suite.expect(service.hotkey.registered == nil && !service.isActive,
                     "recording any shortcut silences Cleaning Mode, including queued callbacks")
        ShortcutCapture.isCapturing = false
        service.syncWithPreferences()
        suite.expect(service.hotkey.registered == .screenshotDefault,
                     "ending recording restores the saved shortcut")

        SessionActivity.shared.setActive(false)
        service.hotkey.onPress?()
        suite.expect(service.hotkey.registered == nil && !service.isActive,
                     "switching away releases the shortcut and refuses queued activation")
        SessionActivity.shared.setActive(true)
        suite.expect(service.hotkey.registered == .screenshotDefault,
                     "returning to the session restores the shortcut")

        service.hotkey.succeeds = false
        service.syncWithPreferences()
        suite.expect(service.shortcutRegistrationFailed && service.hotkey.registered == nil,
                     "a failed Carbon registration is reported to Settings")
        service.hotkey.succeeds = true
        service.syncWithPreferences()
        suite.expect(!service.shortcutRegistrationFailed,
                     "successful registration clears the failure")

        service.hotkey.onPress?()
        AppFeature.available = false
        service.syncWithPreferences()
        service.hotkey.onPress?()
        suite.expect(service.hotkey.registered == nil && !service.isActive && service.activations == 2,
                     "uninstalling Cleaning Mode releases the shortcut and ends the lock")
        AppFeature.available = true
        service.syncWithPreferences()
        suite.expect(service.hotkey.registered == .screenshotDefault,
                     "reinstalling restores the configured shortcut")
        service.deactivateForSystemTeardown()
        suite.expect(service.hotkey.registered == nil,
                     "system teardown releases the shortcut even when no lock is active")
    }
}
