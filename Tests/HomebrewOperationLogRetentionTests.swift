// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum HomebrewOperationLogRetentionTests {
    // The test build reads the output view getter from AppUpdatesListView.
    @MainActor struct Updates {
        let homebrew: HomebrewManager
        let compact: Bool
    }

    private final class Fixture {
        private var executable: String?
        var timers: [(delay: TimeInterval, item: DispatchWorkItem)] = []
        lazy var manager = HomebrewManager(detectBrewPath: { [unowned self] in self.executable },
                                           processForCommand: Fixture.process,
                                           scheduleCleanup: { [unowned self] in self.timers.append(($0, $1)) })

        func upgrade(_ token: String) {
            executable = "/fixture/brew"
            manager.upgradeCasks([token])
            // Refresh after completion sees no installation. No real inventory,
            // profile, login shell, package or network service is involved.
            executable = nil
        }

        func uninstall(_ package: HomebrewPackage) {
            executable = "/fixture/brew"
            manager.uninstall(package, fromUninstaller: true)
            executable = nil
        }

        private static func process(_ command: HomebrewCommand) -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.environment = [:]
            let script = #"""
            case "$*" in
              "upgrade --cask --greedy success") printf 'downloaded\ninstalled\n' ;;
              "upgrade --cask --greedy cancel") printf 'working\n'; exec /bin/sleep 5 ;;
              "upgrade --cask --greedy failure") printf 'error: fixture failed\n' >&2; exit 1 ;;
              "upgrade --cask --greedy terminal") printf 'sudo: a terminal is required\n' >&2; exit 1 ;;
              "upgrade --cask --greedy large") printf '%0*d\nend\n' \#(HomebrewOperationOutput.byteLimit + 32) 0 ;;
              "uninstall --cask editor") printf 'removed Editor\n' ;;
              *) printf 'unexpected fixture command\n' >&2; exit 2 ;;
            esac
            """#
            process.arguments = ["-c", script, command.executable] + command.arguments
            return process
        }
    }

    private static func wait(for condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 8)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        return condition()
    }

    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated { check(suite) }
    }

    @MainActor private static func check(_ suite: TestSuite) {
        let fixture = Fixture()
        let manager = fixture.manager
        let updates = Updates(homebrew: manager, compact: false)
        let panel = Updates(homebrew: manager, compact: true)
        let available: (AppFeature) -> Bool = { $0 == .appUpdates }
        suite.expect(FeatureVisibilitySupport.isPageVisible(.appUpdates, isAvailable: available)
                     && !FeatureVisibilitySupport.isPageVisible(.homebrew, isAvailable: available)
                     && updates.operationLog == nil, "app updates can run alone and starts without a log")

        fixture.upgrade("success")
        suite.expect(manager.operationStatus?.result == .running && fixture.timers.isEmpty,
                     "the running command has a live card and no cleanup timer")
        guard wait(for: { manager.operation == nil }),
              let success = manager.operationStatus, let timer = fixture.timers.last else {
            suite.expect(false, "the successful fixture schedules its production cleanup")
            return
        }
        suite.expect(success.result == .succeeded && timer.delay == 8, "success keeps the eight-second card")
        timer.item.perform()
        suite.expect(manager.operationStatus == nil && manager.log == "downloaded\ninstalled\n"
                     && updates.operationLog?.output == .lastLog(success)
                     && panel.operationLog?.output == .lastLog(success),
                     "both app update surfaces can reopen the exact output after the timer fires")
        manager.upgradeCasks([])
        suite.expect(updates.operationLog?.output == .lastLog(success),
                     "a rejected request preserves the last finished run")

        fixture.upgrade("cancel")
        suite.expect(manager.log.isEmpty, "an accepted run starts with a fresh log")
        suite.expect(wait(for: { manager.log.contains("working") }), "the cancellable process started streaming")
        manager.cancelOperation()
        guard wait(for: { manager.operation == nil }), let cancelled = manager.operationStatus,
              let cancelTimer = fixture.timers.last else {
            suite.expect(false, "the fixture process finishes after cancellation")
            return
        }
        suite.expect(cancelled.result == .cancelled && cancelTimer.delay == 6,
                     "cancellation schedules the shorter card timeout")
        cancelTimer.item.perform()
        suite.expect(manager.operationStatus == nil && manager.log == "working\n\nCancelled.\n"
                     && updates.operationLog?.output == .lastLog(cancelled),
                     "cancellation keeps both process output and its cancellation note after expiry")
        manager.clearLog()
        suite.expect(updates.operationLog == nil && manager.log.isEmpty, "Clear removes the archived output")

        // Leave a real expiry pending, then start another upgrade with the same
        // targetID. A delayed callback must not dismiss the newer failure.
        fixture.upgrade("success")
        guard wait(for: { manager.operation == nil }), let oldTimer = fixture.timers.last else {
            suite.expect(false, "the previous run has a pending expiry")
            return
        }
        let priorTimerCount = fixture.timers.count
        for (token, result, message) in [("failure", HomebrewOperationResult.failed, "error: fixture failed"),
                                          ("terminal", .needsTerminal, "sudo: a terminal is required")] {
            fixture.upgrade(token)
            guard wait(for: { manager.operation == nil }), let failed = manager.operationStatus else {
                suite.expect(false, "the \(token) fixture completes")
                return
            }
            oldTimer.item.perform()
            suite.expect(oldTimer.item.isCancelled && fixture.timers.count == priorTimerCount
                         && updates.operationLog?.output == .status(failed) && failed.result == result
                         && failed.lastActivity == message && manager.log == message + "\n",
                         "\(token) keeps the explanation and output through refresh and prior cleanup")
            if result == .needsTerminal {
                suite.expect(manager.terminalFallbackCommand?.contains("upgrade --cask --greedy terminal") == true,
                             "the terminal handoff retains the requested cask")
            }
            manager.clearLog()
            suite.expect(manager.operationOutput == nil && manager.terminalFallbackCommand == nil
                         && manager.errorMessage == nil, "Clear dismisses the \(token) diagnostic")
        }

        let editor = HomebrewPackage(kind: .cask, name: "editor", displayName: "Editor")
        fixture.uninstall(editor)
        guard wait(for: { manager.operation == nil }), let removal = manager.operationStatus,
              let removalTimer = fixture.timers.last else {
            suite.expect(false, "the uninstaller fixture completes")
            return
        }
        suite.expect(removal.result == .succeeded && manager.uninstallerLastLog(showingPackageID: editor.id) == nil
                     && manager.uninstallerLastLog(showingPackageID: nil) == removal,
                     "the completion screen can reopen the removal log without duplicating a matching live card")
        removalTimer.item.perform()
        suite.expect(manager.uninstallerLastLog(showingPackageID: editor.id) == removal,
                     "the uninstaller keeps its matching log after the card expires")
        fixture.upgrade("success")
        suite.expect(wait(for: { manager.operation == nil }) && manager.uninstallerLastLog(showingPackageID: nil) == nil,
                     "the next app update does not become an uninstaller log")
        manager.clearLog()

        let limit = HomebrewOperationOutput.byteLimit
        let exact = String(repeating: "x", count: limit)
        suite.expect(HomebrewOperationOutput.retainedText(exact) == exact, "an output at the limit stays intact")
        let oversized = String(repeating: "🍺", count: limit / 4) + "end"
        let tail = HomebrewOperationOutput.retainedText(oversized)
        suite.expect(tail.utf8.count <= limit && tail.hasPrefix("…\n") && tail.hasSuffix("🍺end")
                     && !tail.contains("\u{fffd}"), "truncation marks the cut and keeps complete UTF-8 scalars")
        fixture.upgrade("large")
        guard wait(for: { manager.operation == nil }),
              manager.operationStatus?.result == .succeeded, let largeTimer = fixture.timers.last else {
            suite.expect(false, "the oversized stream completes")
            return
        }
        largeTimer.item.perform()
        suite.expect(manager.log.utf8.count == limit && manager.log.hasPrefix("…\n") && manager.log.hasSuffix("\nend\n")
                     && updates.operationLog != nil, "the manager retains only the marked tail of the completed process")
    }
}
