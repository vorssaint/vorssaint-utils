// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentCursorUsageTests {
    static func run(_ suite: TestSuite) {
        let now = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
        let summary = #"{"billingCycleStart":"2026-10-01T00:00:00Z","billingCycleEnd":"2026-11-01T00:00:00Z","membershipType":"pro","individualUsage":{"plan":{"enabled":true,"used":500,"limit":2000,"totalPercentUsed":30}}}"#
        let parsed = AgentCursorUsage.summary(Data(summary.utf8), now: now)
        suite.expect(parsed?.limits.provider == .cursor && parsed?.limits.source == .account
                     && parsed?.plan?.name == "Pro", "Cursor identifies its account usage and capitalizes its plan name")
        suite.expect(parsed?.limits.windows.first?.usedPercent == 30
                     && parsed?.limits.windows.first?.resetsAt == ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"),
                     "Cursor preserves the provider's percentage and exact billing reset")
        let fallback = summary.replacingOccurrences(of: ",\"totalPercentUsed\":30", with: "")
        suite.expect(AgentCursorUsage.summary(Data(fallback.utf8), now: now)?.limits.windows.first?.usedPercent == 25,
                     "Cursor derives missing percentages from the reported allowance")
        for changed in [summary.replacingOccurrences(of: "\"limit\":2000", with: "\"limit\":0"),
                        summary.replacingOccurrences(of: "\"used\":500", with: "\"used\":true"),
                        summary.replacingOccurrences(of: "\"used\":500", with: "\"used\":-1"),
                        summary.replacingOccurrences(of: "\"enabled\":true", with: "\"enabled\":false"),
                        summary.replacingOccurrences(of: "2026-11-01", with: "2026-10-02"),
                        summary.replacingOccurrences(of: "2026-10-01", with: "2026-10-25")] {
            suite.expect(AgentCursorUsage.summary(Data(changed.utf8), now: now) == nil,
                         "invalid or expired Cursor allowances are left unknown")
        }
        let timestamp = Int(now.timeIntervalSince1970 * 1_000)
        let row = #"{"timestamp":"\#(timestamp)","model":"claude-opus-4-6","tokenUsage":{"inputTokens":100,"outputTokens":10,"cacheReadTokens":200,"cacheWriteTokens":50,"totalCents":2.5}}"#
        let page = #"{"totalUsageEventsCount":2,"usageEventsDisplay":[\#(row),\#(row)]}"#
        let parsedPage = AgentCursorUsage.page(Data(page.utf8), since: now.addingTimeInterval(-1), until: now)
        suite.expect(parsedPage?.total == 2 && parsedPage?.records.count == 2,
                     "identical Cursor requests are retained as separate usage")
        suite.expect(parsedPage?.records.first?.tokens == AgentTokens(input: 100, cacheWrite: 50, cacheRead: 200, output: 10)
                     && parsedPage?.records.first?.cost == 0.025,
                     "Cursor separates cache traffic and converts reported cents to dollars")
        for changed in [page.replacingOccurrences(of: "\"inputTokens\":100", with: "\"inputTokens\":-1"),
                        page.replacingOccurrences(of: "\"outputTokens\":10", with: "\"outputTokens\":1.5"),
                        page.replacingOccurrences(of: "\"cacheReadTokens\":200", with: "\"cacheReadTokens\":true"),
                        page.replacingOccurrences(of: "\"totalUsageEventsCount\":2", with: "\"totalUsageEventsCount\":false")] {
            suite.expect(AgentCursorUsage.page(Data(changed.utf8), since: now.addingTimeInterval(-1), until: now) == nil,
                         "a malformed Cursor page cannot publish partial totals")
        }
        suite.expect(AgentCursorUsage.page(Data(page.utf8), since: now.addingTimeInterval(1), until: now) == nil,
                     "Cursor rejects events outside the requested period")
        suite.expect(AgentCursorUsage.page(Data("{}".utf8), since: now, until: now)?.total == 0,
                     "Cursor's confirmed empty response is accepted")
        suite.expect(AgentCursorUsage.page(Data(#"{"error":"unavailable"}"#.utf8), since: now, until: now) == nil,
                     "a Cursor error is never interpreted as zero usage")
    }
}
