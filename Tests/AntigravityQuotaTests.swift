// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AntigravityQuotaTests {
    static func run(_ suite: TestSuite) {
        suite.expect(!AgentAntigravityQuota.supportsUsage(Data("1.1.10\n".utf8))
                        && AgentAntigravityQuota.supportsUsage(Data("1.1.11\n".utf8))
                        && AgentAntigravityQuota.supportsUsage(Data("1.5.18\n".utf8))
                        && !AgentAntigravityQuota.supportsUsage(Data("unexpected".utf8)),
                     "only a recognized Antigravity CLI version that supports /usage may be queried")

        let now = AgentTimestamp.parse("2026-11-26T10:00:00Z")!
        let reset = AgentTimestamp.parse("2026-11-26T15:00:00Z")!
        let reading = """
            {"status":"SUCCESS","num_turns":0,"command":{"name":"usage","data":{"groups":[
              {"name":"Gemini Models","buckets":[
                {"id":"gemini-weekly","window":"weekly","remaining_fraction":0.2},
                {"id":"gemini-5h","window":"5h","remaining_fraction":0.7,"reset_time":"2026-11-26T15:00:00Z"}]},
              {"name":"Claude and GPT models","buckets":[
                {"id":"3p-weekly","window":"weekly","remaining_fraction":0.9}]}]}}}
            """
        func windows(_ output: String) -> [AgentLimitWindow] {
            AgentAntigravityQuota.windows(Data(output.utf8), observedAt: now)
        }
        let parsed = windows(reading)
        suite.expect(parsed.map(\.kind) == [.session, .weekly] && parsed.map(\.minutes) == [300, 10_080]
                        && parsed.map { Int($0.usedPercent.rounded()) } == [30, 80]
                        && parsed.first?.resetsAt == reset,
                     "Gemini's five-hour and weekly meters show used percentages from their own pool")
        suite.expect(windows(reading.replacingOccurrences(of: "0.7", with: "0.9")).first
                        .map { Int($0.usedPercent.rounded()) } == 10
                        && windows(reading.replacingOccurrences(of: "0.7", with: "1")).first?.usedPercent == 0
                        && windows(reading.replacingOccurrences(of: "0.7", with: "0")).first?.usedPercent == 100,
                     "ten percent, an unused allowance and an exhausted allowance are distinct")
        for unreadable in ["true", "\"0.7\"", "null", "-0.7", "1.2"] {
            suite.expect(windows(reading.replacingOccurrences(of: "0.7", with: unreadable)).map(\.kind) == [.weekly],
                         "an invalid percentage leaves the other Gemini window readable")
        }
        suite.expect(windows("Warning\n" + reading.replacingOccurrences(of: "\n", with: "")) == parsed
                        && windows(reading.replacingOccurrences(of: "SUCCESS", with: "ERROR")).isEmpty
                        && windows(reading.replacingOccurrences(of: "\"num_turns\":0", with: "\"num_turns\":1")).isEmpty,
                     "only a structured /usage response with no model turn supplies a percentage")
        suite.expect(AgentAntigravityQuota.current(parsed, now: reset).map(\.kind) == [.weekly]
                        && windows(reading.replacingOccurrences(of: "15:00:00", with: "09:00:00")).map(\.kind) == [.weekly],
                     "when a window expires, its new percentage remains unknown until the next read")

        let cards = NotchAgentCard.allCases
        let quotaTile = NotchAgentTile(card: .limits, provider: nil, antigravityQuota: true)
        suite.expect(NotchAgentSupport.tiles(cards: cards, providers: [], antigravityQuota: true) == [quotaTile]
                        && NotchAgentSupport.tiles(cards: cards, providers: [.cursor], antigravityQuota: true).contains(quotaTile)
                        && NotchAgentSupport.tiles(cards: [.live], providers: [], antigravityQuota: true).isEmpty
                        && !NotchAgentSupport.tiles(cards: cards, providers: [.cursor]).contains(quotaTile),
                     "the opt-in Gemini card is visible on its own and follows the Limits card setting")
    }
}
