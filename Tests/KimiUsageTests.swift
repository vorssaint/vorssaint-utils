// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum KimiUsageTests {
    static func run(_ suite: TestSuite) {
        let observed = Date(timeIntervalSince1970: 1_800_000_000)
        let legacy = Data(#"""
        {
          "membership": {"level": "plus"},
          "usage": {"limit": "2048", "used": "214", "remaining": "1834",
                    "resetTime": "2026-01-09T15:23:13.716839300Z"},
          "limits": [{"window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
                      "detail": {"limit": "200", "used": "139", "remaining": "61",
                                 "resetTime": "2026-01-06T13:33:02.717479433Z"}}]
        }
        """#.utf8)
        guard let old = KimiUsageParser.reading(legacy, observedAt: observed) else {
            suite.expect(false, "Kimi's count-based usage response parses")
            return
        }
        suite.expect(old.limits.provider == .kimi && old.limits.source == .account
                        && old.limits.windows.map(\.id) == ["kimi.5h", "kimi.7d"],
                     "Kimi's weekly and five-hour allowances keep their identities")
        suite.expect(old.limits.windows[0].kind == .session && old.limits.windows[0].minutes == 300
                        && old.limits.windows[1].kind == .weekly && old.limits.windows[1].minutes == 10_080
                        && old.plan == AgentPlan(name: "Plus", monthlyPrice: nil),
                     "Kimi's windows and membership are read from the response")
        suite.expectClose(old.limits.windows[0].usedPercent, 69.5, "Kimi's session request share is calculated")
        suite.expectClose(old.limits.windows[1].usedPercent, 214.0 / 2048 * 100,
                          "Kimi's weekly request share is calculated")

        let ratios = Data(#"""
        {
          "user": {"membership": {"level": "pro"}},
          "limits": [{"window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
                      "detail": {"limit": "100", "used": "100",
                                 "resetTime": "2026-09-22T12:22:15.593402Z"}}],
          "usages": {
            "limit_5h": {"used_ratio": 0, "reset_time": "2026-09-22T12:22:15Z"},
            "limit_7d": {"used_ratio": 0.25, "reset_time": "2026-09-25T00:00:00Z"},
            "limit_month_total": {"used_ratio": 0.0795, "reset_time": "2026-10-22T00:00:00Z"},
            "limit_month_code": {"used_ratio": 0.04, "reset_time": "2026-10-22T00:00:00Z"}
          }
        }
        """#.utf8)
        guard let current = KimiUsageParser.reading(ratios, observedAt: observed) else {
            suite.expect(false, "Kimi's ratio-pool usage response parses")
            return
        }
        suite.expect(current.limits.windows.map(\.id) == ["kimi.5h", "kimi.7d", "kimi.month.total"]
                        && current.limits.windows.map(\.kind) == [.session, .weekly, .monthly]
                        && current.limits.windows[2].resetsAt == AgentTimestamp.parse("2026-10-22T00:00:00Z")
                        && current.plan?.name == "Pro",
                     "Kimi's ratio pools cover the session, week and account-wide month without a duplicate Code cap")
        suite.expect(current.limits.windows[0].usedPercent == 100 && current.limits.windows[1].usedPercent == 25
                        && current.limits.windows[2].usedPercent == 7.95,
                     "matching absolute and ratio readings keep the more exhausted window without losing precision")
        let codeOnly = Data(#"{"usages":{"limit_month_code":{"used_ratio":0.4}}}"#.utf8)
        suite.expect(KimiUsageParser.reading(codeOnly, observedAt: observed)?.limits.windows.first?.scope == "Kimi Code",
                     "a Code-only monthly response still has a monthly reading when no account-wide pool is supplied")

        let invalid = [
            Data("{}".utf8),
            Data(#"{"usage":{"limit":"0","used":"1"}}"#.utf8),
            Data(#"{"usages":{"limit_5h":{"used_ratio":true}}}"#.utf8),
            Data(#"{"usages":{"limit_5h":{"used_ratio":-0.1}}}"#.utf8),
            Data("not json".utf8),
            Data(repeating: 0x20, count: 64 * 1024 + 1),
        ]
        suite.expect(invalid.allSatisfy { KimiUsageParser.reading($0, observedAt: observed) == nil },
                     "empty, malformed, non-finite and oversized Kimi responses create no allowance")

        suite.expect(KimiRegion.china.usageURL.absoluteString == "https://api.kimi.com/coding/v1/usages"
                        && KimiRegion.international.usageURL.absoluteString == "https://api.kimi.ai/coding/v1/usages"
                        && KimiRegion.china.consoleURL.host == "www.kimi.com"
                        && KimiRegion.international.consoleURL.host == "www.kimi.ai",
                     "each Kimi region uses its own usage endpoint and console")

        for language in AppLanguage.allCases {
            let text = FeatureStrings.kimiAccount(language)
            let strings = Mirror(reflecting: text).children.compactMap { $0.value as? String }
            suite.expect(strings.count == 13 && strings.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                         "Kimi settings are complete in \(language.rawValue)")
            let failures: [KimiUsageError] = [.expiredCredential, .unauthorized, .unavailable, .invalidResponse]
            suite.expect(Set(failures.map(text.failure)).count == failures.count,
                         "Kimi failures have distinct explanations in \(language.rawValue)")
        }
        KimiCLIAuthTests.run(suite)
        KimiReaderTests.run(suite)
    }
}
