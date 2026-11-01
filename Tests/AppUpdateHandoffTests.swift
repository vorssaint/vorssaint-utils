// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production handoff and return methods with controlled workspace
/// replies. No application or store URL is opened.
enum AppUpdateHandoffTests {
    final class NSWorkspace {
        struct OpenConfiguration {}
        static let shared = NSWorkspace()
        var completions: [(Any?, Error?) -> Void] = []
        func open(_ url: URL, configuration: OpenConfiguration,
                  completionHandler: @escaping (Any?, Error?) -> Void) {
            completions.append(completionHandler)
        }
    }
    class State {
        var pendingUpdateHandoffs = Set<UUID>()
        var checks = 0
        func checkIfNeeded() { checks += 1 }
    }
    private static func drain(_ suite: TestSuite) {
        var finished = false
        DispatchQueue.main.async { finished = true }
        let deadline = Date(timeIntervalSinceNow: 2)
        while !finished, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        suite.expect(finished, "workspace failure replies return to the main queue")
    }

    static func run(_ suite: TestSuite) {
        let url = URL(fileURLWithPath: "/fixture/App.app")
        let failure = NSError(domain: "handoff.fixture", code: 1)
        let workspace = NSWorkspace.shared
        defer { workspace.completions = [] }
        for succeeded in [true, false] {
            let service = Service()
            workspace.completions = []
            service.handOff(url)
            suite.expect(service.updateHandoffPending && workspace.completions.count == 1,
                         "an asynchronous handoff is pending before its workspace reply")
            workspace.completions[0](nil, succeeded ? nil : failure)
            drain(suite)
            service.applicationBecameActive()
            suite.expect(service.checks == (succeeded ? 1 : 0)
                         && service.consumeUpdateHandoffReturn() == succeeded
                         && !service.consumeUpdateHandoffReturn(),
                         "only a successful handoff refreshes and restores the window once")
        }
        for failedIndex in [0, 1] {
            let service = Service()
            workspace.completions = []
            service.handOff(url)
            service.handOff(url)
            workspace.completions[1 - failedIndex](nil, nil)
            workspace.completions[failedIndex](nil, failure)
            drain(suite)
            suite.expect(service.updateHandoffPending && service.consumeUpdateHandoffReturn(),
                         "failure of request \(failedIndex) cannot erase the other successful handoff")
        }
        let failed = Service()
        workspace.completions = []
        failed.handOff(url)
        failed.handOff(url)
        workspace.completions.reversed().forEach { $0(nil, failure) }
        drain(suite)
        suite.expect(!failed.updateHandoffPending && !failed.consumeUpdateHandoffReturn(),
                     "two failed requests leave no pending handoff")

        let returned = Service()
        workspace.completions = []
        returned.handOff(url)
        suite.expect(returned.consumeUpdateHandoffReturn(),
                     "a return may be consumed before the workspace completion arrives")
        returned.handOff(url)
        workspace.completions[0](nil, failure)
        drain(suite)
        suite.expect(returned.updateHandoffPending && returned.consumeUpdateHandoffReturn(),
                     "a failed request from an earlier return cannot clear a new handoff")
        workspace.completions[1](nil, nil)
        drain(suite)
        suite.expect(!returned.updateHandoffPending,
                     "a late success does not restore an already consumed return")
    }
}
