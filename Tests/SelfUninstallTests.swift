// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production clear and uninstall bodies with the password request,
/// tccutil and every removal step replaced by doubles that log what ran.
enum SelfUninstallContract {
    static var events: [String] = []
    static var ruleRemovalAllowed = true

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
    enum Sudoers {
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
            return (0, "")
        }
    }
    struct Permissions {
        static let shared = Permissions()
        func refresh() {}
    }
    struct BrightnessService {
        static let shared = BrightnessService()
        func resumeInputTaps() { events.append("resume brightness") }
    }
    enum AppFeature: CaseIterable { case any }
    struct FeatureRuntime {
        static let shared = FeatureRuntime()
        func sync(_ features: [AppFeature]) { events.append("resume features") }
    }
    struct L10n {
        struct Text {
            let advancedUninstallFailedBody = "stopped"
            let advancedClearFailed = "rule kept"
        }
        static let shared = L10n()
        let s = Text()
    }

    static func run(_ suite: TestSuite) {
        func reset(allowRule: Bool) {
            events = []; ruleRemovalAllowed = allowRule
        }

        reset(allowRule: false)
        var cleared: Bool?
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == false && events.contains("tccutil"),
                     "a refused password request fails clear permissions while tccutil still runs")

        reset(allowRule: true)
        Host.clearPermissions { cleared = $0 }
        DispatchQueue.main.flush()
        suite.expect(cleared == true, "clear permissions succeeds when the rule and permissions are removed")

        reset(allowRule: false)
        var failure: String?
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(failure == "rule kept"
                        && events == ["suspend", "sleep", "rule", "resume features", "resume brightness"],
                     "a refused password request stops a full uninstall before anything is removed, found \(events)")

        reset(allowRule: true)
        Host.uninstallCompletely { failure = $0 }
        DispatchQueue.main.flush()
        suite.expect(events == ["suspend", "sleep", "rule", "detach", "tccutil", "preferences", "trash"],
                     "a full uninstall restores sleep and removes the rule before detaching, found \(events)")
    }
}
