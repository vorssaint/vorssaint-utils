// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The automatic swap's decision, one row of its table at a time.
enum AgentAccountAutoSwapTests {
    private static let now = AgentAccountTests.now

    private static func limits(_ used: Double, age: TimeInterval = 60, resets: Date? = nil,
                               source: AgentLimits.Source = .account) -> AgentLimits {
        AgentLimits(provider: .claude, windows: [
            AgentLimitWindow(id: "claude.fh", kind: .session, minutes: 300, scope: nil, usedPercent: used, resetsAt: resets),
            AgentLimitWindow(id: "claude.sd", kind: .weekly, minutes: 10_080, scope: nil, usedPercent: 5,
                             resetsAt: now.addingTimeInterval(60))],
                    observedAt: now.addingTimeInterval(-age), source: source)
    }

    private static func login(_ id: String, _ limits: AgentLimits?, active: Bool = false, needsLogin: Bool = false) -> AgentAccountState {
        AgentAccountState(account: AgentAccount(id: id, provider: .claude, email: "\(id)@example.com", organization: "", label: "",
                                                added: now, savedAt: now, needsLogin: needsLogin, identity: Data()),
                          limits: limits, fetchedAt: limits?.observedAt, usageError: nil, isActive: active)
    }

    private static func decide(active: AgentLimits?, _ candidates: [AgentAccountState], threshold: Double = 90,
                               lastSwap: TimeInterval? = nil, log: AgentLimits? = nil, saved: Bool = true) -> AutoSwapDecision {
        AgentAutoSwap.decide(AutoSwapInput(active: saved ? login("active", active, active: true) : nil, candidates: candidates,
                                           threshold: threshold, now: now,
                                           lastAutoSwap: lastSwap.map { now.addingTimeInterval(-$0) }, logLimits: log))
    }

    private static func target(_ decision: AutoSwapDecision) -> String? {
        if case .swap(let id, _) = decision { return id }
        return nil
    }

    static func run(_ suite: TestSuite) {
        let away = { (on: Set<AgentProvider>) in AgentAutoSwap.runsWhileAway([.claude, .codex], autoSwaps: on.contains) }
        suite.expect(!away([]) && away([.claude]) && away([.codex]) && !away([.copilot]),
                     "limits are still read while the island is away once an automatic swap is on for a provider that swaps")

        let roomy = [login("b", limits(50)), login("c", limits(30)), login("d", limits(40))]

        suite.expect(decide(active: limits(89.9), roomy) == .stay && target(decide(active: limits(90), roomy)) == "c"
                        && decide(active: limits(94.9), roomy, threshold: 95) == .stay
                        && target(decide(active: limits(80), roomy, threshold: 80)) == "c",
                     "the active login is left exactly at the threshold, for the saved login with the most room")
        let perModel = AgentLimits(provider: .claude, windows: [
            AgentLimitWindow(id: "claude.fh", kind: .session, minutes: 300, scope: nil, usedPercent: 10, resetsAt: nil),
            AgentLimitWindow(id: "claude.sd.opus", kind: .weekly, minutes: 10_080, scope: "Opus", usedPercent: 96, resetsAt: nil)],
                                   observedAt: now, source: .account)
        suite.expect(AgentAutoSwap.binding(perModel) == 96 && target(decide(active: perModel, roomy)) == "c"
                        && AgentAutoSwap.binding(nil) == nil,
                     "a login's use is that of its tightest limit, a model's own week included")

        suite.expect(target(decide(active: limits(95), [login("b", limits(80))])) == "b"
                        && decide(active: limits(95), [login("b", limits(80.5))]) == .exhausted(nextReset: nil)
                        && target(decide(active: limits(95), [login("b", limits(84)), login("c", limits(85))], threshold: 95)) == "b",
                     "a login is only swapped to when it is ten points under the threshold, or it would be left again at once")

        suite.expect(decide(active: limits(95), roomy, lastSwap: 4 * 60) == .stay && target(decide(active: limits(95), roomy, lastSwap: 5 * 60)) == "c"
                        && target(decide(active: limits(100), roomy, lastSwap: 30)) == "c",
                     "five minutes pass between two automatic swaps, except from a login that is used up")

        suite.expect(decide(active: limits(99, age: 11 * 60), roomy) == .stay && decide(active: nil, roomy) == .stay
                        && target(decide(active: limits(99, age: 10 * 60), roomy)) == "c",
                     "a reading of the active login older than ten minutes, or none, decides nothing")
        suite.expect(decide(active: limits(99), roomy, saved: false) == .stay
                        && decide(active: nil, roomy, log: limits(99, source: .sessionLog), saved: false) == .stay,
                     "a live login that is not saved is never swapped away from")

        suite.expect(target(decide(active: limits(95), [login("b", limits(10), needsLogin: true), login("c", limits(60))])) == "c"
                        && decide(active: limits(95), [login("b", limits(10), needsLogin: true)]) == .exhausted(nextReset: nil),
                     "a login that needs a new sign-in is never swapped to")
        suite.expect(decide(active: limits(95), [login("b", limits(10, age: 11 * 60)), login("c", limits(85))]) == .stay
                        && decide(active: limits(95), [login("b", nil), login("c", limits(85))]) == .stay
                        && target(decide(active: limits(95), [login("b", nil), login("c", limits(60))])) == "c",
                     "a login without a recent reading is not swapped to, and is no proof that every login is used up")

        let soon = now.addingTimeInterval(20 * 60), later = now.addingTimeInterval(3 * 3_600)
        suite.expect(decide(active: limits(96, resets: later), [login("b", limits(92, resets: soon)), login("c", limits(99, resets: now.addingTimeInterval(-5)))])
                        == .exhausted(nextReset: soon)
                        && decide(active: limits(96), []) == .exhausted(nextReset: nil),
                     "with every login near its limit, the first renewal still ahead among their tightest limits is named")

        let logged = limits(93, age: 30, source: .sessionLog)
        suite.expect(target(decide(active: limits(50, age: 4 * 60), roomy, log: logged)) == "c"
                        && decide(active: limits(50, age: 20), roomy, log: logged) == .stay
                        && target(decide(active: limits(50, age: 30 * 60), roomy, log: logged)) == "c"
                        && target(decide(active: nil, roomy, log: logged)) == "c"
                        && decide(active: limits(50, age: 4 * 60), roomy, log: limits(93, age: 11 * 60, source: .sessionLog)) == .stay,
                     "the newer of the fetched limits and the AI section's own decides, so a burst between two requests is seen")
    }
}
