// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentWeeklyUsageTests {
    static func run(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = start.addingTimeInterval(604_800)
        func reading(_ percent: Double, at date: Date, reset end: Date? = reset,
                     source: AgentLimits.Source = .account, account: String? = "account-a") -> AgentLimits {
            AgentLimits(provider: .codex, windows: [
                AgentLimitWindow(id: "weekly", kind: .weekly, minutes: 10_080, scope: nil,
                                 usedPercent: percent, resetsAt: end)
            ], observedAt: date, source: source, accountScope: account)
        }
        var history = AgentWeeklyUsage()
        var isolated = AgentWeeklyUsage()
        _ = isolated.record(reading(20, at: start), now: start)
        _ = isolated.record(reading(70, at: start.addingTimeInterval(60), reset: reset.addingTimeInterval(3600), account: "account-b"),
                            now: start.addingTimeInterval(60))
        suite.expect(isolated.cycles.count == 2 && isolated.current(.codex)?.originalReset == reset.addingTimeInterval(3600),
                     "switching accounts isolates history and the original baseline even before the old deadline")
        suite.expect(!isolated.record(reading(75, at: start.addingTimeInterval(120), account: nil), now: start.addingTimeInterval(120)),
                     "a session log without account identity cannot contaminate a verified account history")
        isolated.selectAccount(nil, provider: .codex)
        suite.expect(isolated.current(.codex) == nil && isolated.cycles.count == 2,
                     "losing account verification immediately removes the old plan without deleting its history")
        let opaque = AgentWeeklyAccount.scope(identifier: "person@example.invalid", organization: "org-a")
        suite.expect(opaque?.count == 64 && opaque != AgentWeeklyAccount.scope(identifier: "person@example.invalid", organization: "org-b")
                     && AgentWeeklyAccount.scope(identifier: nil, organization: "org-a") == nil,
                     "account namespaces contain only a digest, distinguish organizations, and require individual identity")
        suite.expect(history.record(reading(25, at: start), now: start), "a genuine weekly observation is saved")
        suite.expect(!history.record(reading(25, at: start), now: start), "the same source observation is not sampled again on a UI tick")
        suite.expect(history.record(reading(25, at: start.addingTimeInterval(60)), now: start.addingTimeInterval(60)),
                     "a later real observation with unchanged consumption is retained")
        suite.expect(!history.record(reading(90, at: start.addingTimeInterval(-60)), now: start),
                     "an old log cannot overwrite a newer account reading")
        suite.expect(!history.record(reading(.nan, at: start.addingTimeInterval(120)), now: start.addingTimeInterval(120)),
                     "non-finite consumption is rejected")
        suite.expect(!history.record(reading(101, at: start.addingTimeInterval(120)), now: start.addingTimeInterval(120)),
                     "out-of-range consumption is not silently turned into a measurement")
        suite.expect(!history.record(reading(50, at: reset), now: start), "future observations are rejected")
        let changedReset = reset.addingTimeInterval(-3600)
        _ = history.record(reading(40, at: start.addingTimeInterval(120), reset: changedReset), now: start.addingTimeInterval(120))
        let cycle = history.current(.codex)!
        suite.expect(cycle.originalReset == reset && cycle.latest?.resetsAt == changedReset,
                     "a changed provider deadline updates the plan while preserving the original reference")
        let dropAt = start.addingTimeInterval(180)
        let nextReset = dropAt.addingTimeInterval(604_800)
        _ = history.record(reading(5, at: dropAt, reset: nextReset), now: dropAt)
        let nextCycle = history.current(.codex)
        suite.expect(history.cycles.count == 2 && history.cycles[0].samples.map(\.usedPercent) == [25, 25, 40]
                     && nextCycle?.samples.map(\.usedPercent) == [5] && nextCycle?.originalReset == nextReset
                     && nextCycle?.inferredStart == dropAt,
                     "a lower usage reading starts a cycle whose ideal begins at its reported reset-derived start")
        let plan = AgentWeeklyPlan(sample: cycle.latest!, now: start.addingTimeInterval(120))!
        let laterPlan = AgentWeeklyPlan(sample: cycle.latest!, now: start.addingTimeInterval(180))!
        suite.expect(laterPlan.start == plan.start && laterPlan.used(at: start.addingTimeInterval(3600)) == plan.used(at: start.addingTimeInterval(3600)),
                     "a UI tick cannot move a budget without a new source observation")
        suite.expect(plan.remainingPercent == 60 && plan.used(at: changedReset) == 100 && plan.used(at: plan.start) == 40,
                     "the linear plan starts at consumed usage and spends exactly the remaining allowance at the actual reset")
        suite.expect(AgentWeeklyPlan(sample: cycle.latest!, now: changedReset) == nil,
                     "crossing the deadline cannot invent the next cycle or zero usage")
        suite.expect(AgentWeeklyPlan(sample: cycle.latest!, now: start.addingTimeInterval(1000)) == nil,
                     "stale observations remain history without a purported current budget")
        let afterNextReset = nextReset.addingTimeInterval(60)
        let followingReset = nextReset.addingTimeInterval(604_800)
        _ = history.record(reading(8, at: afterNextReset, reset: followingReset), now: afterNextReset)
        suite.expect(history.cycles.count == 3 && history.current(.codex)?.originalReset == followingReset,
                     "a source observation beyond the current deadline opens the next cycle")

        var desktop = AgentWeeklyUsage()
        suite.expect(!desktop.record(reading(30, at: start, source: .claudeApp), now: start) && desktop.cycles.isEmpty,
                     "organization-only desktop readings cannot be assigned to an individual Code account")
        var unknown = AgentWeeklyUsage()
        _ = unknown.record(reading(30, at: start, reset: nil), now: start)
        suite.expect(unknown.current(.codex)!.latest!.isStale(at: start.addingTimeInterval(600)),
                     "an observation becomes stale even when no reset was reported")
        suite.expect(AgentWeeklyPlan(sample: unknown.current(.codex)!.latest!, now: start) == nil,
                     "an unknown reset means no invented ideal or budget")
        persistence(suite, history: history)
        retention(suite)
        revisedResetBoundaries(suite)
        cycleCapacity(suite)
        checkpoints(suite)
        for language in AppLanguage.allCases {
            let strings = AgentWeeklyStrings.localized(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            suite.expect(values.count == 26 && values.allSatisfy { !$0.isEmpty }
                         && strings.title == FeatureStrings.notchAgents(language).card(.weekly),
                         "weekly usage is localized consistently for \(language.rawValue)")
        }
    }

    private static func cycleCapacity(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func reading(_ used: Double, at date: Date, account: String, provider: AgentProvider = .codex) -> AgentLimits {
            AgentLimits(provider: provider, windows: [
                AgentLimitWindow(id: "weekly", kind: .weekly, minutes: 10_080, scope: nil,
                                 usedPercent: used, resetsAt: start.addingTimeInterval(604_800))
            ], observedAt: date, source: .account, accountScope: account)
        }
        for switches in [false, true] {
            var history = AgentWeeklyUsage()
            for index in 0..<402 {
                let at = start.addingTimeInterval(Double(index * 2))
                if switches {
                    // Different accounts can report at the same source time.
                    history.record(reading(40, at: start, account: "account-\(index)"), now: at)
                } else {
                    history.record(reading(80, at: at, account: "drops"), now: at)
                    history.record(reading(20, at: at.addingTimeInterval(1), account: "drops"),
                                   now: at.addingTimeInterval(1))
                }
            }
            let current = history.current(.codex)
            suite.expect(history.valid && history.cycles.count == 400 && current != nil,
                         "frequent usage drops or account switches retain a valid bounded archive")
            let url = root.appendingPathComponent(switches ? "accounts.json" : "drops.json")
            let saved = AgentWeeklyUsageFile.save(history, to: url)
            let reloaded = AgentWeeklyUsageFile.load(from: url, now: start.addingTimeInterval(1000))
            suite.expect(saved && !reloaded.failed && reloaded.history.current(.codex) == current,
                         "the newest cycle survives a real archive round trip after exceeding 400 cycles")
            let next = start.addingTimeInterval(1001)
            history.record(reading(10, at: next, account: switches ? "next-account" : "drops"), now: next)
            suite.expect(history.valid && history.cycles.count == 400
                         && history.current(.codex)?.latest?.observedAt == next
                         && AgentWeeklyUsageFile.save(history, to: url),
                         "collection and persistence continue after reaching the cycle cap")
        }
        var recent = AgentWeeklyUsage()
        recent.record(reading(20, at: start, account: "active-claude", provider: .claude), now: start)
        for index in 1...399 {
            let at = start.addingTimeInterval(Double(index))
            recent.record(reading(40, at: at, account: "codex-\(index)"), now: at)
        }
        var oldestSelected = recent
        let updated = start.addingTimeInterval(1000)
        recent.record(reading(30, at: updated, account: "active-claude", provider: .claude), now: updated)
        recent.record(reading(40, at: updated.addingTimeInterval(1), account: "new-codex"),
                      now: updated.addingTimeInterval(1))
        suite.expect(recent.valid && recent.cycles.count == 400
                     && recent.current(.claude)?.samples.count == 2
                     && !recent.cycles.contains { $0.accountScope == "codex-1" },
                     "cycle eviction uses the last observation rather than a still-active cycle's creation order")
        oldestSelected.record(reading(40, at: updated, account: "fresh-codex"), now: updated)
        let bytes = (try? JSONEncoder().encode(oldestSelected)) ?? Data()
        suite.expect(oldestSelected.valid && oldestSelected.current(.claude) == nil
                     && oldestSelected.current(.codex) != nil
                     && !String(decoding: bytes, as: UTF8.self).contains("active-claude"),
                     "evicting an account's final cycle removes its selected digest without affecting the surviving provider")
    }

    private static func revisedResetBoundaries(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for (provider, originalHours, revisedHours, expectedCycles) in [
            (AgentProvider.codex, 2, 4, 1), (.claude, 4, 2, 2)
        ] {
            let original = start.addingTimeInterval(Double(originalHours) * 3600)
            let revised = start.addingTimeInterval(Double(revisedHours) * 3600)
            func reading(_ percent: Double, seconds: TimeInterval, reset: Date?) -> AgentLimits {
                AgentLimits(provider: provider, windows: [
                    AgentLimitWindow(id: "weekly", kind: .weekly, minutes: 10_080, scope: nil,
                                     usedPercent: percent, resetsAt: reset)
                ], observedAt: start.addingTimeInterval(seconds), source: .account, accountScope: "revised-account")
            }
            var history = AgentWeeklyUsage()
            history.record(reading(20, seconds: 0, reset: original), now: start)
            history.record(reading(30, seconds: 60, reset: revised), now: start.addingTimeInterval(60))
            history.record(reading(35, seconds: 120, reset: nil), now: start.addingTimeInterval(120))
            if let bytes = try? JSONEncoder().encode(history),
               let loaded = try? JSONDecoder().decode(AgentWeeklyUsage.self, from: bytes) {
                history = loaded
            } else { suite.expect(false, "revised-reset history round-trips its real samples") }
            history.record(reading(40, seconds: 3 * 3600, reset: nil), now: start.addingTimeInterval(3 * 3600))
            suite.expect(history.cycles.count == expectedCycles && history.cycles.first?.originalReset == original,
                         "reset-less samples use the last revised boundary while preserving the original ideal: \(provider)")
            suite.expect(history.cycles.flatMap(\.samples).map(\.usedPercent) == [20, 30, 35, 40]
                         && history.current(provider)?.latest?.resetsAt == nil,
                         "a retained cycle boundary cannot invent a deadline or observations on reset-less samples")
            let next = start.addingTimeInterval(8 * 3600)
            history.record(reading(5, seconds: 4 * 3600 + 60, reset: next),
                           now: start.addingTimeInterval(4 * 3600 + 60))
            suite.expect(history.cycles.count == expectedCycles + 1
                         && history.current(provider)?.samples.map(\.usedPercent) == [5]
                         && history.current(provider)?.originalReset == next,
                         "a lower usage reading opens a new cycle with its own reported deadline after revised boundaries")
        }
    }

    private static func persistence(_ suite: TestSuite, history: AgentWeeklyUsage) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("weekly.json")
        suite.expect(AgentWeeklyUsageFile.save(history, to: url), "normalized history saves in a private local file")
        let loaded = AgentWeeklyUsageFile.load(from: url)
        suite.expect(loaded.history == history && !loaded.failed, "all genuine points and original deadlines survive restart")
        let mode = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
        suite.expect(mode?.intValue == 0o600, "weekly history is owner-only")
        let bytes = (try? Data(contentsOf: url)) ?? Data()
        let text = String(decoding: bytes, as: UTF8.self)
        suite.expect(!text.contains("access_token") && !text.contains("session_id"), "history contains normalized quota observations only")
        try? Data("broken history".utf8).write(to: url)
        let invalid = AgentWeeklyUsageFile.load(from: url)
        suite.expect(invalid.failed && invalid.history == AgentWeeklyUsage(), "corrupt history is reported instead of treated as an empty valid file")
        suite.expect(!AgentWeeklyUsageFile.save(history, to: url) && (try? Data(contentsOf: url)) == Data("broken history".utf8),
                     "subsequent collection cannot overwrite a damaged history file")
    }

    private static func retention(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("weekly.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expired = now.addingTimeInterval(-92 * 86_400)
        let recent = now.addingTimeInterval(-90 * 86_400)
        func reading(at date: Date) -> AgentLimits {
            AgentLimits(provider: .codex, windows: [
                AgentLimitWindow(id: "weekly", kind: .weekly, minutes: 10_080, scope: nil,
                                 usedPercent: 20, resetsAt: date.addingTimeInterval(604_800))
            ], observedAt: date, source: .account, accountScope: "retention-account")
        }
        var history = AgentWeeklyUsage()
        _ = history.record(reading(at: expired), now: expired)
        _ = history.record(reading(at: recent), now: recent)
        suite.expect(AgentWeeklyUsageFile.save(history, to: url), "retention fixture saves both observations before maintenance")
        let loaded = AgentWeeklyUsageFile.load(from: url, now: now)
        suite.expect(!loaded.failed && loaded.history.current(.codex)?.samples.map(\.observedAt) == [recent],
                     "loading history removes expired observations without a new quota reading")
        let disk = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let saved = disk?["history"] as? [String: Any]
        let cycles = saved?["cycles"] as? [[String: Any]]
        suite.expect((cycles?.first?["samples"] as? [[String: Any]])?.count == 1,
                     "load-time retention persists removal instead of only hiding expired observations")
        var old = AgentWeeklyUsage()
        _ = old.record(reading(at: expired), now: expired)
        suite.expect(AgentWeeklyUsageFile.save(old, to: url), "an entirely expired archive can be written for maintenance")
        let empty = AgentWeeklyUsageFile.load(from: url, now: now)
        suite.expect(!empty.failed && empty.history.cycles.isEmpty,
                     "loading an entirely expired archive removes its empty cycles")
        suite.expect(!old.record(reading(at: expired), now: now), "a cached observation adds no new sample")
        suite.expect(old.prune(now: now) && old.cycles.isEmpty && !old.prune(now: now),
                     "periodic maintenance expires history despite a rejected cached observation and is idempotent")
        let prunedText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        suite.expect(!prunedText.contains("retention-account"),
                     "load-time pruning removes the last expired account digest from the archive")
        var orphan = AgentWeeklyUsage()
        orphan.selectAccount("orphan-account", provider: .codex)
        suite.expect(orphan.prune(now: now) && !orphan.prune(now: now),
                     "pruning reports orphan-only selection removal once even without samples")
        suite.expect(AgentWeeklyUsageFile.save(orphan, to: url)
                     && !((try? String(contentsOf: url, encoding: .utf8)) ?? "").contains("orphan-account"),
                     "orphan-only account selections cannot persist indefinitely")
        let boundary = now.addingTimeInterval(-91 * 86_400)
        var exact = AgentWeeklyUsage()
        _ = exact.record(reading(at: boundary), now: boundary)
        suite.expect(!exact.prune(now: now) && exact.current(.codex)?.latest?.observedAt == boundary,
                     "an observation exactly at the retention cutoff is preserved")
        suite.expect(exact.prune(now: now.addingTimeInterval(1)) && exact.cycles.isEmpty,
                     "the same observation expires once it falls behind the cutoff")
    }

    private static func checkpoints(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let parse = ISO8601DateFormatter()
        // Friday before the spring DST change, through Tuesday after it.
        let now = parse.date(from: "2026-03-06T23:00:00Z")!
        let reset = parse.date(from: "2026-03-10T20:00:00Z")!
        let sample = AgentWeeklyUsage.Sample(observedAt: now, usedPercent: 40, resetsAt: reset, source: "account")
        let plan = AgentWeeklyPlan(sample: sample, now: now)!
        let goals = plan.checkpoints(calendar: calendar)
        suite.expect(goals.count == 2 && goals.first?.date == parse.date(from: "2026-03-09T21:00:00Z") && goals.last?.date == reset,
                     "daily checkpoints skip weekends, follow local DST at 17:00, and end at the actual reset")
        suite.expect(abs((goals.first?.usedPercent ?? 0) - 85.16129032258064) < 0.000001,
                     "daily targets use elapsed time on the recalibrated line, in percentage points")
        suite.expect(goals.last?.usedPercent == 100, "the final checkpoint uses the complete quota")
        let nearCheckpoint = parse.date(from: "2026-03-09T21:00:30Z")!
        let nearSample = AgentWeeklyUsage.Sample(observedAt: now, usedPercent: 40,
                                                 resetsAt: nearCheckpoint, source: "account")
        let nearGoals = AgentWeeklyPlan(sample: nearSample, now: now)!.checkpoints(calendar: calendar)
        suite.expect(nearGoals.count == 1 && nearGoals.first?.date == nearCheckpoint
                     && nearGoals.first?.usedPercent == 100,
                     "a reset within the 17:00 display minute replaces the daily checkpoint without changing its actual deadline")
    }
}
