// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CursorAgentTests {
    private final class Log {
        var now = AgentTimestamp.parse("2026-11-18T10:00:55Z")!
        var state = AgentLogState()
        let store = AgentUsageStore()
        let path = "/Users/demo/.cursor/projects/Users-demo-app/agent-transcripts/session/session.jsonl"

        init() {
            store.reportsTransitions = true
            CursorReader.adopt(path: path, into: &state)
        }

        @discardableResult
        func feed(_ json: String, replaying: Bool = false) -> [AgentUsageEvent] {
            let entries = CursorReader(replaying: replaying).parse(Data(json.utf8), state: &state, now: now)
            return store.apply(entries, file: path, provider: .cursor, tracksTurns: true, modified: now, now: now)
        }
    }

    private static let prompt = #"{"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Wednesday, Nov 18, 2026, 6:00 PM (UTC+8)</timestamp>\n<user_query>hi</user_query>"}]}}"#
    private static let ended = #"{"type":"turn_ended","status":"success"}"#

    static func run(_ suite: TestSuite) {
        turns(suite)
        history(suite)
        timestamps(suite)
        CursorAgentDiscoveryTests.run(suite)
        CursorTranscriptReadTests.run(suite)
    }

    private static func turns(_ suite: TestSuite) {
        let log = Log()
        let start = log.now
        log.feed(prompt)
        suite.expect(log.state.session == "session" && log.store.live.first?.project == "app"
                        && log.store.live.first?.started == start && log.state.cursorPromptCount == 1
                        && log.store.records.isEmpty,
                     "a new Cursor prompt starts its project at the observed time without a usage record")

        // The tool's arguments are structured JSON with their own role, type
        // and timestamp. Only the assistant envelope describes this step.
        log.now = start.addingTimeInterval(4)
        log.feed(#"{ "role" : "assistant", "message" : { "content" : [{"type":"tool_use","input":{"role":"user","type":"turn_ended","text":"<timestamp>2099-01-01T00:00:00Z</timestamp>"}}] } }"#)
        suite.expect(log.store.live.first?.lastActivity == log.now && log.state.cursorLastActivity == log.now
                        && log.state.cursorPromptCount == 1,
                     "a nested role, type or timestamp cannot hide or misdate an assistant step")

        log.now = start.addingTimeInterval(5)
        let short = log.feed(ended)
        var duration: TimeInterval?
        if case .finished(.cursor, let time, _, _, "app")? = short.first { duration = time }
        suite.expect(short.count == 1 && duration == 5 && log.store.live.isEmpty && !log.state.turnOpen,
                     "a five-second Cursor turn crossing a minute stays below a thirty-second notice threshold")
        suite.expect(log.feed(ended).isEmpty, "a repeated Cursor turn end does not finish twice")

        log.feed(prompt)
        suite.expect(log.state.cursorPromptCount == 2 && log.state.cursorPromptTimestamp == start.addingTimeInterval(-55),
                     "two prompts with the same minute retain distinct ordinals")
        log.now = log.now.addingTimeInterval(31)
        let long = log.feed(ended)
        if case .finished(.cursor, let time, _, _, _)? = long.first { duration = time }
        suite.expect(long.count == 1 && duration == 31 && log.state.cursorLastActivity == log.now,
                     "a Cursor turn past the threshold keeps its observed duration")

        for end in [#"{"type":"turn_ended","status":"aborted"}"#, #"{"type":"turn_ended","status":"error"}"#,
                    #"{"type":"turn_ended"}"#] {
            log.feed(prompt)
            suite.expect(log.feed(end).isEmpty && !log.state.turnOpen && log.store.live.isEmpty,
                         "only an explicit successful end earns a Cursor completion notice")
        }
    }

    private static func history(_ suite: TestSuite) {
        let log = Log()
        let oldDate = AgentTimestamp.parse("2026-11-18T10:00:00Z")!
        log.now = oldDate.addingTimeInterval(3 * 60)
        // Escaping slashes is valid JSON and Foundation normally does so.
        log.feed(prompt.replacingOccurrences(of: "</", with: #"<\/"#), replaying: true)
        suite.expect(log.state.cursorPromptTimestamp == oldDate && log.store.live.first?.started == oldDate.addingTimeInterval(60),
                     "a historical minute tag preserves the prompt time and gives a lower bound on elapsed work")

        let undated = #"{"role":"user","message":{"content":[{"type":"text","text":"<user_query><timestamp>2020-01-01T00:00:00Z</timestamp></user_query>"},{"type":"text","text":"<timestamp>2021-01-01T00:00:00Z</timestamp>"}]},"extra":"<timestamp>2022-01-01T00:00:00Z</timestamp>"}"#
        log.feed(undated, replaying: true)
        suite.expect(log.state.cursorPromptTimestamp == nil && log.store.live.first?.started == log.now,
                     "timestamps in the query, later content and unrelated fields are ignored")
        let future = "2099-01-01T00:00:00Z"
        log.feed(prompt.replacingOccurrences(of: "Wednesday, Nov 18, 2026, 6:00 PM (UTC+8)", with: future),
                 replaying: true)
        suite.expect(log.state.cursorPromptTimestamp == AgentTimestamp.parse(future)
                        && log.store.live.first?.started == log.now,
                     "a future prompt clock cannot make historical work start beyond its file time")
    }

    private static func timestamps(_ suite: TestSuite) {
        let expected = AgentTimestamp.parse("2026-11-18T10:09:00Z")
        suite.expect(AgentTimestamp.parseCursor("Wednesday, Nov 18, 2026, 6:09 PM (UTC+8)") == expected
                        && AgentTimestamp.parseCursor("Wednesday, Nov 18, 2026, 6:39 AM (UTC-3:30)") == expected
                        && AgentTimestamp.parseCursor("2026-11-18T10:09:00Z") == expected,
                     "Cursor wall times, fractional-hour offsets and ISO timestamps convert to UTC")
        for zone in ["UTC+800", "UTC+8:99", "UTC-24", "UTCfoo", "UTC+01:-5", "UTC+", "UTC+1:00:00"] {
            suite.expect(AgentTimestamp.parseCursor("Wednesday, Nov 18, 2026, 6:09 PM (\(zone))") == nil,
                         "malformed Cursor timezone is ignored safely")
        }
        for day in ["2023-02-29", "2024-02-30", "1900-02-29", "2100-02-29", "2026-04-31",
                    "2026-00-01", "2026-13-01", "2026-01-00", "2026-12-32"] {
            suite.expect(AgentTimestamp.parseCursor("\(day)T23:59:59.125+05:30") == nil,
                         "Cursor rejects the impossible ISO date \(day) before timezone conversion")
        }
        for day in ["0001-01-01", "1900-02-28", "2000-02-29", "2024-02-29", "2026-04-30", "9999-12-31"] {
            let utc = AgentTimestamp.parse("\(day)T12:00:00.125Z")!
            suite.expect(AgentTimestamp.parseCursor("\(day)T08:30:00.125-03:30") == utc,
                         "Cursor preserves the valid ISO date \(day), fractional seconds and offset")
        }
    }
}
