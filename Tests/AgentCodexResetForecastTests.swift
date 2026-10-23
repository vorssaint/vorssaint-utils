// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentCodexResetForecastTests {
    static func run(_ suite: TestSuite) {
        publicSourceReference(suite)
        let parse = ISO8601DateFormatter()
        let now = parse.date(from: "2026-10-18T12:00:00Z")!
        // Use the published all-time median, not the recent median or a
        // banked credit's timestamp. Attribute order and quotes can vary.
        let body = #"<html><div data-reset-at='2026-10-17T10:00:00Z' class='reset-since' id='reset-since'></div><p class='rhythm-trend' id='live-home-rhythm-trend'>All-time median gap: 5.0 days · last 30 days: 2.0 days</p><time id='home-banked-signal-time' datetime='2026-10-18T11:00:00Z'></time></html>"#
        guard let forecast = AgentCodexResetForecast.decode(Data(body.utf8), fetchedAt: now) else {
            suite.expect(false, "the public reference page supplies a speculative deadline")
            return
        }
        let deadline = parse.date(from: "2026-10-22T10:00:00Z")!
        suite.expect(forecast.estimatedReset == deadline && forecast.medianDays == 5
                     && forecast.lastReset == parse.date(from: "2026-10-17T10:00:00Z"),
                     "the published all-time median is anchored to the global reset, never a banked credit")
        let actual = parse.date(from: "2026-10-25T12:00:00Z")!
        let sample = AgentWeeklyUsage.Sample(observedAt: now, usedPercent: 40, resetsAt: actual, source: "account")
        let scenario = forecast.plan(provider: .codex, sample: sample, now: now)
        suite.expect(scenario?.reset == deadline && scenario?.used(at: deadline) == 100
                     && scenario?.used(at: now) == 40,
                     "the speculative line spends remaining quota from a real reading to its own deadline")
        suite.expect(AgentWeeklyPlan(sample: sample, now: now)?.reset == actual && sample.resetsAt == actual,
                     "the actual account reset and normal budget remain independent of speculation")
        comparison(suite, actual: AgentWeeklyPlan(sample: sample, now: now)!, speculative: scenario!)
        suite.expect(forecast.plan(provider: .claude, sample: sample, now: now) == nil,
                     "a public Codex reset never produces a Claude scenario")
        let sooner = AgentWeeklyUsage.Sample(observedAt: now, usedPercent: 40,
                                              resetsAt: deadline.addingTimeInterval(-60), source: "account")
        suite.expect(forecast.plan(provider: .codex, sample: sooner, now: now) == nil,
                     "an estimate later than the real quota reset is not an early-reset line")
        let unknown = AgentWeeklyUsage.Sample(observedAt: now, usedPercent: 40, resetsAt: nil, source: "account")
        suite.expect(forecast.plan(provider: .codex, sample: unknown, now: now) == nil,
                     "speculation cannot substitute for a missing account deadline")
        suite.expect(forecast.plan(provider: .codex, sample: sample, now: now.addingTimeInterval(600)) == nil,
                     "stale account observations cannot anchor speculative budgets")
        let expiredNow = now.addingTimeInterval(86_400)
        let fresh = AgentWeeklyUsage.Sample(observedAt: expiredNow, usedPercent: 40, resetsAt: actual, source: "account")
        suite.expect(forecast.plan(provider: .codex, sample: fresh, now: expiredNow) == nil,
                     "a forecast expires within 24 hours even with a fresh account reading")
        let atDeadline = AgentWeeklyUsage.Sample(observedAt: deadline, usedPercent: 40, resetsAt: actual, source: "account")
        suite.expect(forecast.plan(provider: .codex, sample: atDeadline, now: deadline) == nil,
                     "passing the estimated reset never rolls speculation forward or invents a refill")
        for changed in [body.replacingOccurrences(of: "All-time median gap:", with: "Recent median gap:"),
                        body.replacingOccurrences(of: "2026-10-17T10:00:00Z", with: "2026-10-19T10:00:00Z"),
                        body.replacingOccurrences(of: "2026-10-17T10:00:00Z", with: "invalid"),
                        body.replacingOccurrences(of: "2026-10-17T10:00:00Z", with: "2026-10-01T10:00:00Z"),
                        body.replacingOccurrences(of: "5.0 days", with: "0 days"),
                        body.replacingOccurrences(of: "5.0 days", with: "91 days"),
                        body.replacingOccurrences(of: "5.0 days", with: "NaN days"),
                        body + body] {
            suite.expect(AgentCodexResetForecast.decode(Data(changed.utf8), fetchedAt: now) == nil,
                         "missing, future, malformed, expired or ambiguous source fields supply no scenario")
        }
        let onlyCredits = body.replacingOccurrences(of: "id='reset-since'", with: "id='banked-since'")
        suite.expect(AgentCodexResetForecast.decode(Data(onlyCredits.utf8), fetchedAt: now) == nil,
                     "banked credits alone are not evidence of an automatic global reset")
        suite.expect(AgentCodexResetForecast.decode(Data(repeating: 65, count: AgentCodexResetForecast.maximumSize + 1),
                                                   fetchedAt: now) == nil,
                     "oversized public pages never enter the forecast parser")
        suite.expect(AgentCodexResetForecast.decode(Data(body.utf8), fetchedAt: .distantPast) == nil,
                     "an invalid fetch clock cannot anchor an estimate")
        source(suite, body: Data(body.utf8), now: now)
    }

    private static func publicSourceReference(_ suite: TestSuite) {
        let page = #"<html><div id="reset-since" data-reset-at="2026-10-17T20:41:01.000Z"></div><p id="live-home-rhythm-trend">All-time median gap: 4.0 days · last 30 days: 4.0 days</p></html>"#
        let parse = ISO8601DateFormatter()
        let now = parse.date(from: "2026-10-19T20:43:00Z")!
        let forecast = AgentCodexResetForecast.decode(Data(page.utf8), fetchedAt: now)
        suite.expect(forecast?.estimatedReset == parse.date(from: "2026-10-21T20:41:01Z"),
                     "the public source reference uses the last global reset plus its all-time four-day median")
        if let forecast {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(identifier: "America/Fortaleza")!
            formatter.dateFormat = "dd/MM HH:mm"
            suite.expect(formatter.string(from: forecast.estimatedReset) == "21/10 17:41",
                         "the reference scenario matches the Fortaleza date without a timezone shift")
        }
    }

    private static func comparison(_ suite: TestSuite, actual: AgentWeeklyPlan, speculative: AgentWeeklyPlan) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Fortaleza")!
        let parse = ISO8601DateFormatter()
        let rows = actual.targets(comparing: speculative, calendar: calendar)
        suite.expect(rows.count == 7 && Set(rows.map(\.date)).count == 7,
                     "the comparison unifies weekday targets and both exact deadlines without duplicate days")
        guard let first = rows.first, let estimated = rows.first(where: \.isSpeculativeReset), let last = rows.last else {
            suite.expect(false, "comparison rows include the speculative reset and the account reset")
            return
        }
        suite.expect(first.date == parse.date(from: "2026-10-19T20:00:00Z")
                     && abs(first.actualPercent - 51.42857142857143) < 0.000001
                     && abs((first.speculativePercent ?? 0) - 60.42553191489362) < 0.000001,
                     "daily columns evaluate their own linear budgets at the same local 17:00 checkpoint")
        suite.expect(estimated.date == parse.date(from: "2026-10-22T10:00:00Z")
                     && estimated.speculativePercent == 100 && !estimated.isActualReset
                     && abs(estimated.actualPercent - 73.57142857142857) < 0.000001,
                     "the estimated deadline is an explicit comparison row without changing the real budget")
        suite.expect(rows.filter { $0.date > estimated.date }.allSatisfy { $0.speculativePercent == nil }
                     && last.isActualReset && last.actualPercent == 100,
                     "speculation stops at its deadline instead of inventing a post-reset allowance")
        let ordinary = actual.targets(comparing: nil, calendar: calendar)
        suite.expect(ordinary.count == 6 && ordinary.allSatisfy { $0.speculativePercent == nil && !$0.isSpeculativeReset },
                     "an unavailable or expired scenario leaves the ordinary target schedule intact")
        let near = parse.date(from: "2026-10-19T20:00:30Z")!
        let sample = AgentWeeklyUsage.Sample(observedAt: actual.start, usedPercent: 40,
                                              resetsAt: actual.reset, source: "account")
        let nearPlan = AgentWeeklyPlan(sample: sample, now: actual.start, speculativeReset: near)!
        let nearRows = actual.targets(comparing: nearPlan, calendar: calendar)
        suite.expect(nearRows.count == 6 && nearRows.first?.date == near,
                     "the speculative deadline replaces an ordinary target in its displayed minute after both schedules are combined")
        let closeSample = AgentWeeklyUsage.Sample(observedAt: actual.start, usedPercent: 40,
                                                   resetsAt: near.addingTimeInterval(20), source: "account")
        let closeActual = AgentWeeklyPlan(sample: closeSample, now: actual.start)!
        let closeRows = closeActual.targets(comparing: nearPlan, calendar: calendar)
        suite.expect(closeRows.count == 2 && closeRows.first?.isSpeculativeReset == true
                     && closeRows.last?.isActualReset == true,
                     "two distinct reset deadlines in one displayed minute are both preserved")
    }

    private static func source(_ suite: TestSuite, body: Data, now: Date) {
        var clock = now
        var callbacks: [(Data?) -> Void] = []
        var cancellations = 0
        let source = AgentCodexResetForecastSource(loader: { completion in
            callbacks.append(completion)
            return { cancellations += 1 }
        }, clock: { clock })
        source.synchronize(enabled: false)
        suite.expect(callbacks.isEmpty, "a hidden or disabled speculative card makes no public request")
        source.synchronize(enabled: true)
        source.synchronize(enabled: true)
        guard callbacks.count == 1 else {
            suite.expect(false, "a visible speculative card starts one bounded public request")
            return
        }
        source.synchronize(enabled: false)
        callbacks[0](body)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        suite.expect(cancellations == 1 && source.forecast == nil,
                     "hiding cancels the public request and ignores its late completion")
        source.synchronize(enabled: true)
        guard callbacks.count == 2 else {
            suite.expect(false, "a cancelled request can retry when the card returns")
            return
        }
        callbacks[1](body)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        suite.expect(source.forecast?.medianDays == 5, "a successful public response reaches the actual forecast state")
        source.synchronize(enabled: true)
        suite.expect(callbacks.count == 2, "UI ticks do not repeatedly fetch a fresh public history")
        clock = now.addingTimeInterval(6 * 3600)
        source.synchronize(enabled: true)
        guard callbacks.count == 3 else {
            suite.expect(false, "an open card checks the public history again after six hours")
            return
        }
        callbacks[2](nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        source.synchronize(enabled: true)
        suite.expect(source.forecast?.medianDays == 5 && callbacks.count == 3,
                     "a download failure retains the expiring estimate and backs off instead of retrying every tick")
    }
}
