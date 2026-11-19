// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum OMPUsageTests {
    static func run(_ suite: TestSuite) {
        let observed = Date(timeIntervalSince1970: 1_800_000_000)
        let data = Data(#"""
        {
          "generatedAt": 1800000000000,
          "reports": [
            {
              "provider": "kimi-code",
              "fetchedAt": 1799999900000,
              "metadata": {"accountId": "me@example.com", "credentialId": 3},
              "limits": [
                {"id":"kimi-code:0", "label":"5h limit",
                 "window":{"id":"5h", "label":"5h limit", "durationMs":18000000, "resetsAt":1800003600000},
                 "amount":{"usedFraction":0.12}},
                {"id":"kimi-code:1", "label":"Monthly total",
                 "window":{"id":"limit_month_total", "label":"Monthly total", "resetsAt":1800086400000},
                 "amount":{"usedFraction":0.3955}},
                {"id":"kimi-code:2", "label":"Monthly code",
                 "window":{"id":"limit_month_code", "label":"Monthly code", "resetsAt":1800086400000},
                 "amount":{"usedFraction":0.3757}}
              ]
            },
            {
              "provider": "anthropic",
              "fetchedAt": 1799999950000,
              "metadata": {"credentialId": 4},
              "limits": [
                {"id":"anthropic:0", "label":"5h limit",
                 "window":{"id":"5h", "label":"5h limit", "durationMs":18000000},
                 "amount":{"usedFraction":0.25}},
                {"id":"anthropic:1", "label":"Weekly limit",
                 "window":{"id":"7d", "label":"Weekly limit", "durationMs":604800000},
                 "amount":{"usedFraction":0.5}}
              ]
            }
          ],
          "accountsWithoutUsage": []
        }
        """#.utf8)
        guard let readings = OMPUsageParser.readings(data, observedAt: observed), readings.count == 2 else {
            suite.expect(false, "Oh My Pi's multi-account usage response parses")
            return
        }
        let kimi = readings[0]
        suite.expect(kimi.id == "kimi-code:3" && kimi.name == "Kimi Code · me@example.com"
                        && kimi.limits.provider == .omp && kimi.limits.source == .account
                        && kimi.limits.observedAt == Date(timeIntervalSince1970: 1_799_999_900)
                        && kimi.limits.windows.map(\.kind) == [.session, .monthly, .monthly]
                        && kimi.limits.windows.map(\.minutes) == [300, nil, nil]
                        && kimi.limits.windows[0].scope == nil && kimi.limits.windows[1].scope == nil
                        && kimi.limits.windows[2].scope == "Kimi Code",
                     "each Oh My Pi account keeps its provider, identity and distinct windows")
        suite.expect(kimi.limits.windows[0].usedPercent == 12
                        && kimi.limits.windows[0].resetsAt == Date(timeIntervalSince1970: 1_800_003_600),
                     "Oh My Pi millisecond reset times become native limits")
        suite.expectClose(kimi.limits.windows[1].usedPercent, 39.55, "Oh My Pi monthly fraction becomes a percentage")
        suite.expectClose(kimi.limits.windows[2].usedPercent, 37.57, "Oh My Pi Code fraction becomes a percentage")
        suite.expect(readings[1].id == "anthropic:4" && readings[1].name == "Claude"
                        && readings[1].limits.windows.map(\.kind) == [.session, .weekly]
                        && readings[1].limits.windows[1].minutes == 10_080
                        && readings[1].limits.windows[1].scope == nil,
                     "Oh My Pi reports another provider as a separate account")

        let merged = OMPUsageParser.limits(for: readings)
        suite.expect(merged?.windows.count == 5 && merged?.provider == .omp
                        && merged?.observedAt == Date(timeIntervalSince1970: 1_799_999_950)
                        && Set(merged?.windows.map(\.id) ?? []).count == 5,
                     "merged Oh My Pi limits feed alerts without colliding across accounts")
        suite.expect(kimi.currentLimits(at: Date(timeIntervalSince1970: 1_800_003_601))?.windows.count == 2
                        && kimi.currentLimits(at: Date(timeIntervalSince1970: 1_800_086_401)) == nil,
                     "expired Oh My Pi windows leave their account card")

        suite.expect(OMPUsageParser.readings(Data(#"{"reports":[]}"#.utf8), observedAt: observed) == [],
                     "a signed-out Oh My Pi report is valid and empty")
        let invalid = [Data("{}".utf8), Data(#"{"reports":{}}"#.utf8), Data("not json".utf8),
                       Data(repeating: 0x20, count: 4 * 1024 * 1024 + 1)]
        suite.expect(invalid.allSatisfy { OMPUsageParser.readings($0, observedAt: observed) == nil },
                     "malformed and oversized Oh My Pi responses are rejected")
        let badWindows = Data(#"{"reports":[{"provider":"kimi-code","limits":[{"id":"x","window":{},"amount":{"usedFraction":true}},{"id":"y","window":{},"amount":{"usedFraction":-1}}]}]}"#.utf8)
        suite.expect(OMPUsageParser.readings(badWindows, observedAt: observed) == [],
                     "boolean, negative and incomplete Oh My Pi windows create no allowance")
        let scoped = Data(#"{"reports":[{"provider":"anthropic","metadata":{"credentialId":9},"limits":[{"id":"month","scope":{"accountId":"one"},"window":{"id":"custom","durationMs":2592000000},"amount":{"usedFraction":0.1}},{"id":"session","scope":{"accountId":"two","windowId":"5h"},"amount":{"usedFraction":0.2}}]}]}"#.utf8)
        let scopedReadings = OMPUsageParser.readings(scoped, observedAt: observed)
        suite.expect(scopedReadings?.map(\.name) == ["Claude · one", "Claude · two"]
                        && scopedReadings?.first?.limits.windows.first?.kind == .monthly
                        && scopedReadings?.first?.limits.windows.first?.minutes == 43_200
                        && scopedReadings?.last?.limits.windows.first?.kind == .session
                        && scopedReadings?.last?.limits.windows.first?.minutes == nil,
                     "Oh My Pi groups scope accounts, recognizes 30 days and reads a missing window from scope")
        let privateAccount = Data(#"{"reports":[{"provider":"kimi-code","metadata":{"accountId":"private@example.com"},"limits":[{"id":"0","window":{"id":"5h","durationMs":18000000},"amount":{"usedFraction":0.1}}]}]}"#.utf8)
        let privateReading = OMPUsageParser.readings(privateAccount, observedAt: observed)?.first
        suite.expect(privateReading?.id == "kimi-code:account"
                        && privateReading?.limits.windows.first?.id.contains("private@example.com") == false,
                     "Oh My Pi account identifiers stay in memory and out of archived window IDs")
        OMPReaderTests.run(suite)
    }
}
