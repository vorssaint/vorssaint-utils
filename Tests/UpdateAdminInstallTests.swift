// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the updater's administrator install body with the authorization, the
/// Extra Brightness overlay, the main queue and quitting replaced by doubles
/// that log what ran. The real authorization holds the main thread until it
/// is answered, so anything the prompt needs off the screen must go first.
enum UpdateAdminInstallContract {
    static var events: [String] = []

    final class ExtraBrightnessService {
        static let shared = ExtraBrightnessService()
        var onScreen = true
        func stop() { onScreen = false }
        func syncWithPreferences() { onScreen = true; events.append("overlay") }
    }
    enum AdminShell {
        static var answer: ((Bool) -> Void)?
        static func runInProcess(_ command: String, prompt: String,
                                 completion: @escaping (Bool) -> Void) {
            events.append(ExtraBrightnessService.shared.onScreen ? "prompt under overlay" : "prompt")
            answer = completion
        }
    }
    enum DispatchQueue {
        static let main = Queue()
        final class Queue {
            var pending: [() -> Void] = []
            func async(execute: @escaping () -> Void) { pending.append(execute) }
            func flush() {
                while !pending.isEmpty { pending.removeFirst()() }
            }
        }
    }
    final class Application {
        func terminate(_ sender: Any?) { events.append("quit") }
    }
    static let NSApp = Application()
    struct L10n {
        struct Text { let adminPromptUpdate = "update" }
        static let shared = L10n()
        let s = Text()
    }
    class Fixture {
        func abortInstall(dmgPath: String, offered: String?) { events.append("offer \(offered ?? "")") }
    }

    static func run(_ suite: TestSuite) {
        for granted in [false, true] {
            events = []
            ExtraBrightnessService.shared.onScreen = true
            AdminShell.answer = nil
            let service = Service()
            service.launchAdminInstaller(appPath: "/Applications/Vorssaint.app", dmgPath: "/tmp/update.dmg",
                                         pid: 42, resultPath: "/tmp/update-result", expectedVersion: "9.9.9")
            suite.expect(events == ["prompt"],
                         "the brightness overlay leaves the screen before the prompt holds the main thread")
            AdminShell.answer?(granted)
            DispatchQueue.main.flush()
            if granted {
                suite.expect(events == ["prompt", "quit"] && !ExtraBrightnessService.shared.onScreen,
                             "an approved install quits without bringing the overlay back")
            } else {
                suite.expect(events == ["prompt", "overlay", "offer 9.9.9"]
                                 && ExtraBrightnessService.shared.onScreen,
                             "a declined prompt brings the overlay back and keeps the update offer")
            }
            withExtendedLifetime(service) {}
        }
    }
}
