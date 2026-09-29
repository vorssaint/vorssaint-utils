// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The production delivery method runs unchanged against preference inputs
/// and an event recorder. No agent logs, network or notification windows.
enum AgentUsageEventDeliveryTests {
    enum NotchAgentSupport {
        static var minimum: TimeInterval? = 10
        static var threshold: Double? = 0.2
        static var budget: Double? = 1
        static func finishMinimum() -> TimeInterval? { minimum }
        static func limitThreshold() -> Double? { threshold }
        static func dailyBudget() -> Double? { budget }
    }

    final class Events {
        var values: [AgentUsageEvent] = []
        func send(_ event: AgentUsageEvent) { values.append(event) }
    }

    class Fixture {
        var running = true
        var session = 1
        var readerSession = 1
        var providers: [AgentProvider] = [.claude, .codex]
        let events = Events()
    }

    static func run(_ suite: TestSuite) {
        func drain() {
            var reached = false
            DispatchQueue.main.async { reached = true }
            let deadline = Date().addingTimeInterval(1)
            while !reached && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.001))
            }
            suite.expect(reached, "the agent event fixture drains its delivery queue")
        }
        defer {
            NotchAgentSupport.minimum = 10
            NotchAgentSupport.threshold = 0.2
            NotchAgentSupport.budget = 1
        }
        let host = Host()
        let finished = AgentUsageEvent.finished(provider: .claude, duration: 20, cost: 0.5,
                                                  tokens: 30, project: "example")
        let window = AgentLimitWindow(id: "test", kind: .session, minutes: 300, scope: nil,
                                      usedPercent: 90, resetsAt: nil)
        let events: [AgentUsageEvent] = [finished, .limitWarning(provider: .claude, window: window),
                                       .limitReset(provider: .claude, window: window),
                                       .budgetReached(spent: 2, budget: 1)]
        for event in events { host.report(event) }
        // Stop/restart can finish on main before any queued event is delivered.
        host.session += 1
        drain()
        suite.expect(host.events.values.isEmpty,
                     "events queued by a previous agent reading cannot leak into a restarted session")

        host.events.values.removeAll()
        host.readerSession = host.session
        for event in events { host.report(event) }
        drain()
        suite.expect(host.events.values == events,
                     "the current session still delivers completion, warning, renewal and budget events")

        host.events.values.removeAll()
        host.report(finished)
        host.running = false
        drain()
        suite.expect(host.events.values.isEmpty, "stopping without restarting still drops queued events")
        host.running = true

        host.providers = [.codex]
        host.report(finished)
        host.report(events[1])
        host.report(events[2])
        drain()
        suite.expect(host.events.values.isEmpty, "delivery still respects disabled providers")
        host.providers = [.claude, .codex]
        NotchAgentSupport.minimum = 30
        host.report(finished)
        NotchAgentSupport.threshold = nil
        host.report(events[1])
        host.report(events[2])
        NotchAgentSupport.budget = nil
        host.report(events[3])
        drain()
        suite.expect(host.events.values.isEmpty, "duration and disabled-alert preferences still filter current events")
    }
}
