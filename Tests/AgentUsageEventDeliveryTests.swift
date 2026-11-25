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
        var providers: [AgentProvider] = [.claude, .codex, .copilot]
        let events = Events()
        let store = AgentUsageStore()
        var budgetDay: Date?
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
                                       .budgetReached(spent: 2, budget: 1, partial: false)]
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

        for partial in [false, true] {
            let budgetHost = Host()
            budgetHost.store.reportsTransitions = true
            let now = Date(timeIntervalSince1970: 2_000_000)
            let record = AgentUsageRecord(provider: .cursor, date: now, model: "fixture", project: "", session: "example",
                                          tokens: AgentTokens(output: 100), cost: 2, savings: 0)
            var snapshot = AgentUsageSummary.snapshot(records: [record], limits: [:], live: [], plans: [:],
                                                      providers: [.cursor], now: now)
            if partial {
                snapshot.includeCursorActivity([CursorTranscriptActivity(project: "", undatedThrough: now)])
            }
            budgetHost.checkBudget(snapshot)
            drain()
            suite.expect(budgetHost.events.values == [.budgetReached(spent: 2, budget: 1, partial: partial)],
                         "the budget notice carries the coverage of the daily subtotal that crossed the threshold")
        }

        let repricedHost = Host()
        repricedHost.store.reportsTransitions = true
        let now = Date(timeIntervalSince1970: 2_000_000)
        let tokens = AgentTokens(input: 62_500)
        for model in ["gpt-6.2-astra", "gpt-6.2-sol", "gpt-6.2-astra-law"] {
            let record = AgentUsageRecord(provider: .codex, date: now, model: model, project: "", session: "example",
                                          tokens: tokens, cost: nil, savings: 0)
            repricedHost.store.apply([.usage(key: model, record: record, billable: AgentBillable(tokens: tokens))],
                                     file: "example", provider: .codex, tracksTurns: false, modified: now, now: now)
        }
        repricedHost.store.reprice()
        repricedHost.checkBudget(repricedHost.store.snapshot(plans: [:], providers: [.codex], now: now))
        drain()
        suite.expect(repricedHost.events.values == [.budgetReached(spent: 1.125, budget: 1, partial: false)],
                     "repriced GPT-6.2 records count toward the daily budget")

        let tierHost = Host()
        tierHost.store.reportsTransitions = true
        var state = AgentLogState()
        let stamp = "2026-11-24T18:00:00Z"
        let usageDate = AgentTimestamp.parse(stamp)!
        let rollout = [
            #"{"timestamp":"\#(stamp)","type":"turn_context","payload":{"model":"gpt-6.2-sol","service_tier":"ultrafast"}}"#,
            #"{"timestamp":"\#(stamp)","type":"token_usage_record","payload":{"response_id":"priced","usage":{"input_tokens":200000}}}"#,
            #"{"timestamp":"\#(stamp)","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"service_tier":"unlisted"}}}"#,
            #"{"timestamp":"\#(stamp)","type":"token_usage_record","payload":{"response_id":"unpriced","usage":{"input_tokens":200000}}}"#
        ]
        for event in rollout {
            tierHost.store.apply(AgentLogParser.parseCodex(Data(event.utf8), state: &state, now: usageDate),
                                 file: "rollout.jsonl", provider: .codex, tracksTurns: false, modified: usageDate)
        }
        tierHost.store.reprice()
        tierHost.checkBudget(tierHost.store.snapshot(plans: [:], providers: [.codex], now: usageDate))
        drain()
        suite.expect(tierHost.events.values == [.budgetReached(spent: 1.2, budget: 1, partial: true)],
                     "Sol Ultrafast crosses the daily budget and a response on an unpriced tier keeps the total partial")

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
        host.providers = [.claude, .codex, .copilot]
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
