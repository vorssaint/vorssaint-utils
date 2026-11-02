// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Cursor and Grok allowances are reduced from the dashboard JSON. The
/// sign-in and the network stay out of this check.
enum CursorAccountTests {
    static func run(_ suite: TestSuite) {
        let now = date("2026-10-15T00:00:00Z")
        let monthly = AgentCursorAccount.reading(summary: json("""
        {"membershipType":"pro","limitType":"user",
         "billingCycleStart":"2026-10-01T00:00:00.000Z","billingCycleEnd":"2026-11-01T00:00:00.000Z",
         "individualUsage":{"plan":{"used":500,"limit":2000,"totalPercentUsed":0.36,
         "autoPercentUsed":10,"apiPercentUsed":40}}}
        """), sand: json("""
        {"usagePercent":70,"hasNonZeroIncludedLimit":true,"isUnified":false,
         "nextResetTimestampUtc":"2026-10-20T00:00:00Z"}
        """), now: now)
        let shown = monthly.cursor?.windows[0].usedPercent ?? -1
        suite.expect(monthly.cursor?.provider == .cursor && monthly.cursor?.windows.count == 1
                        && monthly.cursor?.windows[0].id == "plan"
                        && monthly.cursor?.windows[0].kind == .other
                        && shown > 0.3 && shown < 0.4
                        && monthly.cursor?.windows[0].resetsAt == date("2026-11-01T00:00:00Z")
                        && monthly.grok?.windows[0].id == "grok"
                        && monthly.grok?.windows[0].kind == .weekly
                        && monthly.grok?.windows[0].usedPercent == 70
                        && monthly.grok?.windows[0].resetsAt == date("2026-10-20T00:00:00Z"),
                     "a Cursor plan percent stays in percent units, and Grok Bot keeps its own week")

        let fromCents = AgentCursorAccount.reading(summary: json("""
        {"individualUsage":{"plan":{"used":250,"limit":1000}}}
        """), sand: nil, now: now)
        suite.expect(fromCents.cursor?.windows[0].usedPercent == 25 && fromCents.grok == nil,
                     "a plan without a percent is used divided by its limit")

        let unified = AgentCursorAccount.reading(summary: json("""
        {"membershipType":"unified_pro","limitType":"user",
         "individualUsage":{"plan":{"totalPercentUsed":90}}}
        """), sand: json("""
        {"usagePercent":40,"hasNonZeroIncludedLimit":true,"isUnified":true,
         "nextResetTimestampUtc":"2026-10-22T00:00:00Z"}
        """), now: now)
        suite.expect(unified.cursor?.windows.count == 1
                        && unified.cursor?.windows[0].kind == .weekly
                        && unified.cursor?.windows[0].usedPercent == 40
                        && unified.grok?.windows[0].usedPercent == 40,
                     "a shared Cursor and Grok week replaces the old monthly percent")

        let silent = AgentCursorAccount.reading(summary: json("{}"), sand: json(#"{"usagePercent":12}"#), now: now)
        suite.expect(silent.cursor == nil && silent.grok == nil,
                     "a sand percent without an included grant is not an allowance")

        let token = jwt(subject: "github|user_01", expiration: 2_000_000_000)
        suite.expect(AgentCursorAccount.sessionCookie(accessToken: token, now: now)
                        == "WorkosCursorSessionToken=user_01%3A%3A\(token)",
                     "the dashboard cookie is the Cursor user id and the access token")
        suite.expect(AgentCursorAccount.sessionCookie(accessToken: jwt(subject: "github|user_01", expiration: 1), now: now) == nil,
                     "an expired Cursor sign-in is not sent")
    }

    private static func json(_ text: String) -> Data { Data(text.utf8) }

    private static func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)!
    }

    private static func jwt(subject: String, expiration: Double) -> String {
        func encoded(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return encoded(["alg": "none"]) + "." + encoded(["sub": subject, "exp": expiration]) + ".sig"
    }
}
