// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production clear and uninstall bodies with the password request,
/// tccutil and every removal step replaced by doubles that log what ran.
enum SelfUninstallContract {
    static var events: [String] = []
    static var suspensionAllowed = true
    static var spacingRestoreAllowed = true
    static let pendingInput = MenuBarInputCleanup()

    struct NoopInputService {
        static let shared = NoopInputService()
        func deactivateForSystemTeardown() {}
        func suspend() {}
        func stop() {}
        func suspendInputTaps() {}
        func unmuteForTeardown() {}
    }
    struct MouseAccelerationService {
        static let shared = MouseAccelerationService()
        func stop() -> Bool { events.append("suspend"); return suspensionAllowed }
    }
    struct MenuBarOrganizerService {
        static let shared = MenuBarOrganizerService()
        func stop() { events.append("organizer stop"); pendingInput.finish() }
    }
    enum MenuBarGlobalSpacing {
        static func restoreForRemoval() -> Bool { events.append("spacing"); return spacingRestoreAllowed }
    }
    static var sleepRestoreAllowed = true
    static var detachAllowed = true
    static var ruleRemovalAllowed = true
    static var tccResetAllowed = true
    static var fanHelperWasRegistered = true
    static var fanRegistrationRestored = true

    enum DispatchQueue {
        static let main = Queue()
        enum QoS { case userInitiated }
        static func global(qos: QoS) -> Queue { main }
        final class Queue {
            var pending: [() -> Void] = []
            func async(execute: @escaping () -> Void) { pending.append(execute) }
            func flush() {
                while !pending.isEmpty { pending.removeFirst()() }
            }
        }
    }
    enum UserDefaults {
        static let standard = UserDefaultsFixture()
        struct UserDefaultsFixture { func bool(forKey key: String) -> Bool { false } }
    }
    enum SMAppService {
        static let mainApp = AppService()
        struct AppService { func unregister() throws { events.append("login") } }
    }
    enum Sudoers {
        static func pmsetDisableSleep(_ disabled: Bool) -> Bool { true }
        static var ruleFilesPresent: Bool { true }
        static func isConfigured() -> Bool { true }
        static func remove(completion: @escaping (Bool) -> Void) {
            events.append("rule")
            DispatchQueue.main.async { completion(ruleRemovalAllowed) }
        }
    }
    enum Shell {
        static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
            events.append("tccutil")
            return (tccResetAllowed ? 0 : 1, "")
        }
    }
    struct Permissions {
        static let shared = Permissions()
        func refresh() { events.append("refresh permissions") }
    }
    struct BrightnessService {
        static let shared = BrightnessService()
        func resumeInputTaps() { events.append("resume brightness") }
    }
    enum SpacesOrderHold {
        static var hasPendingRestore: Bool { true }
        static var restores = true
        static func restoreForRemoval() -> Bool { events.append("spaces"); return restores }
    }
    enum AppFeature: CaseIterable { case any }
    struct FeatureRuntime {
        static let shared = FeatureRuntime()
        func sync(_ features: [AppFeature]) { events.append("resume features") }
    }
    struct KeepAwakeManager {
        static let shared = KeepAwakeManager()
        func resumeAfterSystemTeardown() { events.append("restore keep awake") }
    }
    struct L10n {
        struct Text {
            let advancedUninstallFailedBody = "stopped"
            let advancedClearFailed = "rule kept"
        }
        static let shared = L10n()
        let s = Text()
        let language = "en"
    }
    enum FanControlService {
        static func restoreAndUnregisterForRemoval() -> Bool { events.append("fan"); return detachAllowed }
        static var hasRegisteredHelperForRemoval: Bool {
            events.append("fan registration")
            return fanHelperWasRegistered
        }
        static func restoreRegistrationAfterFailedRemoval() -> Bool {
            events.append("restore fan registration")
            return fanRegistrationRestored
        }
    }
    enum FeatureStrings {
        struct FanStrings { let helperUnavailable = "fan unavailable" }
        static func fanControl(_ language: String) -> FanStrings { FanStrings() }
    }

    static func run(_ suite: TestSuite) {
        func reset(allowRule: Bool, spacesRestore: Bool = true) {
            events = []
            suspensionAllowed = true
            spacingRestoreAllowed = true
            pendingInput.finish()
            sleepRestoreAllowed = true
            detachAllowed = true
            ruleRemovalAllowed = allowRule
            tccResetAllowed = true
            fanHelperWasRegistered = true
            fanRegistrationRestored = true
            SpacesOrderHold.restores = spacesRestore
        }

        reset(allowRule: true)
        suspensionAllowed = false
        var cleared: Bool?
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == true
                        && events == ["organizer stop", "suspend", "sleep", "fan", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume brightness"],
                     "a mouse journal kept for a disconnected device does not block clearing permissions, found \(events)")

        reset(allowRule: true)
        sleepRestoreAllowed = false
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == false
                        && events == ["organizer stop", "suspend", "sleep", "refresh permissions", "resume features", "resume brightness"],
                     "failed sleep restoration keeps the recovery rule and permissions, found \(events)")

        reset(allowRule: true)
        detachAllowed = false
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == false
                        && events == ["organizer stop", "suspend", "sleep", "fan", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "failed system detach keeps the recovery rule and rearms closed-lid mode, found \(events)")

        reset(allowRule: false)
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == false
                        && events == ["organizer stop", "suspend", "sleep", "fan", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume features", "resume brightness"],
                     "a refused password request reports partial clear and restores closed-lid mode, found \(events)")

        reset(allowRule: true)
        tccResetAllowed = false
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == false
                        && events == ["organizer stop", "suspend", "sleep", "fan", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume features", "resume brightness"],
                     "a failed TCC reset reports partial clear and restores closed-lid mode, found \(events)")

        reset(allowRule: true)
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == true
                        && events == ["organizer stop", "suspend", "sleep", "fan", "login", "rule", "tccutil", "refresh permissions", "restore keep awake", "resume brightness"],
                     "clear permissions succeeds when the rule and permissions are removed, found \(events)")

        reset(allowRule: false)
        var failure: String?
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "rule kept"
                        && events == ["organizer stop", "suspend", "spacing", "spaces", "sleep", "rule", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "a refused password request stops a full uninstall before anything is removed, found \(events)")

        reset(allowRule: true)
        sleepRestoreAllowed = false
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "stopped"
                        && events == ["organizer stop", "suspend", "spacing", "spaces", "sleep", "refresh permissions", "resume features", "resume brightness"],
                     "failed sleep restoration does not reset the closed-lid session, found \(events)")

        reset(allowRule: true)
        tccResetAllowed = false
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "rule kept"
                        && events == ["organizer stop", "suspend", "spacing", "spaces", "sleep", "rule", "fan registration", "fan", "tccutil", "restore fan registration", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "a failed permission reset restores the prior fan helper and keeps login, found \(events)")

        reset(allowRule: true)
        tccResetAllowed = false
        fanRegistrationRestored = false
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "rule kept\nfan unavailable"
                        && events == ["organizer stop", "suspend", "spacing", "spaces", "sleep", "rule", "fan registration", "fan", "tccutil", "restore fan registration", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "failed fan registration tells the user the helper is unavailable, found \(events)")

        reset(allowRule: true)
        tccResetAllowed = false
        fanHelperWasRegistered = false
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "rule kept"
                        && events == ["organizer stop", "suspend", "spacing", "spaces", "sleep", "rule", "fan registration", "fan", "tccutil", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "a failed reset does not register a helper the user never had, found \(events)")

        reset(allowRule: true)
        detachAllowed = false
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "stopped"
                        && events == ["organizer stop", "suspend", "spacing", "spaces", "sleep", "rule", "fan registration", "fan", "restore keep awake", "refresh permissions", "resume features", "resume brightness"],
                     "a failed fan-helper detach keeps permissions and login intact, found \(events)")

        reset(allowRule: true)
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == nil
                        && events == ["organizer stop", "suspend", "spacing", "spaces", "sleep", "rule", "fan registration", "fan", "tccutil", "login", "preferences", "trash"],
                     "a full uninstall detaches the fan helper before permission reset and login afterward, found \(events)")

        reset(allowRule: true)
        suspensionAllowed = false
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "stopped"
                        && events == ["organizer stop", "suspend", "refresh permissions", "resume features", "resume brightness"],
                     "a full uninstall still waits for mouse acceleration before deleting its journal, found \(events)")

        reset(allowRule: true, spacesRestore: false)
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "stopped"
                        && events == ["organizer stop", "suspend", "spacing", "spaces", "refresh permissions", "resume features", "resume brightness"],
                     "a failed Space restore stops a full uninstall before sleep, the rule or anything else is touched, found \(events)")
        reset(allowRule: true)
        spacingRestoreAllowed = false
        failure = nil
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "stopped"
                        && events == ["organizer stop", "suspend", "spacing", "refresh permissions", "resume features", "resume brightness"],
                     "failed spacing restoration retains preferences and stops before other restoration, TCC or removal")

        reset(allowRule: true)
        spacingRestoreAllowed = false
        suite.expect(CLI.runAndExit() == EXIT_FAILURE && events == ["spacing"],
                     "command-line uninstall stops before detaching anything if spacing cannot be restored")
        reset(allowRule: true)
        suite.expect(CLI.runAndExit() == EXIT_SUCCESS && events == ["spacing", "fan", "spaces", "login"],
                     "command-line uninstall restores spacing before the helper, Spaces and login item")

        for uninstall in [false, true] {
            reset(allowRule: true)
            var mouseUps = 0
            var cursorRestores = 0
            pendingInput.release = { mouseUps += 1; events.append("mouse up") }
            pendingInput.restoreCursor = { cursorRestores += 1; events.append("cursor restored") }
            if uninstall { Host.uninstallCompletely { _ in } }
            else { Host.clearPermissions { _ in } }
            DispatchQueue.main.flush()
            pendingInput.finish() // The cancelled operation's later defer.
            let resetIndex = events.firstIndex(of: "tccutil")!
            suite.expect(mouseUps == 1 && cursorRestores == 1
                            && events.firstIndex(of: "mouse up")! < resetIndex
                            && events.firstIndex(of: "cursor restored")! < resetIndex,
                         "clear and uninstall release pending organizer input before TCC and only once")
            suite.expect(uninstall == events.contains("spacing"),
                         "only full uninstall restores spacing; clearing permissions preserves the user's spacing")
        }
    }
}
