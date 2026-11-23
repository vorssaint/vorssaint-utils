// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CursorAgentTests {
    private final class Log {
        var now = AgentTimestamp.parse("2026-11-18T10:00:55Z")!
        var state = AgentLogState()
        let store: AgentUsageStore
        let path: String

        init(project: String = "app", session: String = "session", store: AgentUsageStore = AgentUsageStore()) {
            path = "/Users/demo/.cursor/projects/Users-demo-\(project)/agent-transcripts/\(session)/\(session).jsonl"
            self.store = store
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
        partialCost(suite)
        activityCoverage(suite)
        reconciledCoverage(suite)
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

    private static func partialCost(_ suite: TestSuite) {
        let log = Log()
        log.feed(prompt)
        log.feed(#"{"role":"assistant","timestamp":"2026-11-18T10:00:32Z","message":{"id":"one","model":"gpt-5.2","usage":{"output_tokens":1000}}}"#)
        log.feed(#"{"role":"assistant","timestamp":"2026-11-18T10:00:40Z","message":{"id":"two","model":"gpt-5.2"}}"#)
        log.feed(ended)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let snapshot = log.store.snapshot(plans: [:], providers: [.cursor], now: log.now, calendar: calendar,
                                          cursorActivity: [log.store.transcriptActivity(for: log.state)])
        let usage = snapshot.usage(.today)
        let locale = Locale(identifier: "en_US")
        let minimum = AgentFormat.cost(usage.total.cost, partial: true, locale: locale)
        suite.expect(usage.fullyPriced && usage.total.requests == 1 && usage.total.tokens.total == 1000
                     && usage.total.cost > 0 && snapshot.live.isEmpty
                     && AgentFormat.cost(snapshot, for: .today, locale: locale) == minimum,
                     "a priced Cursor reply and an unmetered reply leave only a lower bound on today's idle cost")

        let tomorrow = log.store.snapshot(plans: [:], providers: [.cursor], now: log.now.addingTimeInterval(86_400),
                                          calendar: calendar, cursorActivity: [log.store.transcriptActivity(for: log.state)])
        suite.expect(AgentFormat.cost(tomorrow, for: .today, locale: locale) == "—"
                     && AgentFormat.cost(tomorrow, for: .week, locale: locale) == minimum,
                     "an idle day with only Cursor keeps the unknown daily cost separate from the week's known spend")
        log.now = tomorrow.now
        log.feed(#"{"role":"assistant","timestamp":"2026-11-19T10:00:32Z","message":{"id":"three","model":"gpt-6-sol","usage":{"output_tokens":1000}}}"#)
        let measuredDay = log.store.snapshot(plans: [:], providers: [.cursor], now: log.now, calendar: calendar,
                                             cursorActivity: [log.store.transcriptActivity(for: log.state)])
        let day = measuredDay.usage(.today)
        suite.expect(!measuredDay.hasPartialCost(.today) && day.total.cost > 0
                     && AgentFormat.cost(measuredDay, for: .today, locale: locale) == AgentFormat.cost(day.total.cost, locale: locale),
                     "a fully metered Cursor day stays exact when another day has a reply without counters")
        let models = measuredDay.usage(.week).models
        suite.expect(Set(models.filter { $0.totals.hasPartialCost }.map(\.name)) == [AgentPricing.displayName("gpt-5.2")]
                     && models.first { $0.name == AgentPricing.displayName("gpt-6-sol") }?.totals.hasPartialCost == false,
                     "only the known Cursor model reported by the unmetered reply gets a weekly lower bound")
    }

    private static func activityCoverage(_ suite: TestSuite) {
        let previous = Log(project: "previous")
        let current = Log(project: "current")
        let now = current.now
        // Both files are discovered now, although their replies belong to different days.
        previous.feed(#"{"role":"assistant","timestamp":"2026-11-17T08:30:00Z","message":{"id":"one"}}"#, replaying: true)
        current.feed(#"{"role":"assistant","timestamp":"2026-11-18T10:00:00Z","message":{"id":"two"}}"#, replaying: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = AgentUsageStore()
        let providers: Set<AgentProvider> = [.cursor, .codex]
        for (project, date) in [("previous", "2026-11-17T09:00:00Z"), ("previous", "2026-11-18T08:15:00Z"),
                                ("current", "2026-11-18T10:00:10Z"),
                                ("other", "2026-11-18T09:30:00Z"), ("earlier", "2026-11-16T05:30:00Z")] {
            let tokens = AgentTokens(output: 100)
            let record = AgentUsageRecord(provider: .codex, date: AgentTimestamp.parse(date)!, model: "test", project: project,
                                          session: "test", tokens: tokens, cost: 1, savings: 0)
            store.apply([.usage(key: date, record: record, billable: AgentBillable(tokens: tokens))],
                        file: "codex", provider: .codex, tracksTurns: false, modified: now, now: now)
        }
        func snapshot(_ activity: [CursorTranscriptActivity]) -> AgentUsageSnapshot {
            store.snapshot(plans: [:], providers: providers, now: now, calendar: calendar,
                           cursorProjectsFound: true, cursorActivity: activity)
        }
        let locale = Locale(identifier: "en_US")
        suite.expect(AgentFormat.cost(snapshot([]), for: .today, locale: locale) == "$3.00",
                     "an installed Cursor without activity leaves known costs complete")
        let older = snapshot([store.transcriptActivity(for: previous.state)])
        suite.expect(!older.hasPartialCost(.today) && older.hasPartialCost(.week) && older.hasPartialCost(.month),
                     "a replayed reply from yesterday never qualifies today's bucket at the file modification time")
        previous.feed(#"{"role":"assistant","timestamp":"2026-11-18T08:40:00Z","message":{"id":"three"}}"#, replaying: true)
        let activity = [store.transcriptActivity(for: previous.state), store.transcriptActivity(for: current.state)]
        let mixed = snapshot(activity)
        let lastDays = mixed.days.suffix(3).map(\.total)
        let hours = mixed.hours[8...10].map(\.total)
        suite.expect(lastDays.map(\.hasPartialCost) == [false, true, true] && lastDays.map(\.cost) == [1, 1, 3]
                     && hours.map(\.hasPartialCost) == [true, false, true] && hours.map(\.cost) == [1, 1, 1]
                     && mixed.historyTotal.hasPartialCost,
                     "two transcripts qualify both days and both affected hours, retaining the exact intervening hour")
        let week = mixed.usage(.week)
        suite.expect(week.fullyPriced && week.total.requests == 5 && week.byProvider[.cursor] == nil
                     && Set(week.projects.filter { $0.totals.hasPartialCost }.map(\.id)) == ["previous", "current"]
                     && week.models.allSatisfy { !$0.totals.hasPartialCost }
                     && AgentFormat.cost(mixed, for: .today, locale: locale) == "≥ $3.00",
                     "unmetered replies qualify only matching projects without assigning requests, cost or a model")
        var full = AgentUsageSummary.snapshot(records: store.records, limits: [:], live: [], plans: [:],
                                              providers: providers, now: now, calendar: calendar)
        full.cursorProjectsFound = true
        full.includeCursorActivity(activity)
        suite.expect(mixed == full, "publishing cached usage and rebuilding give identical coverage for both sources")
        let unknown = snapshot([CursorTranscriptActivity(project: "current", undatedThrough: now)])
        suite.expect(unknown.hasPartialCost(.today) && unknown.historyTotal.hasPartialCost
                     && unknown.days.allSatisfy { !$0.total.hasPartialCost } && unknown.hours.allSatisfy { !$0.total.hasPartialCost }
                     && unknown.usage(.week).projects.allSatisfy { !$0.totals.hasPartialCost },
                     "a replay without a reliable date qualifies the period and map without guessing its day, hour or project row")
        let expiredMinute = Int(mixed.days[0].start.timeIntervalSince1970 / 60) - 1
        let outside = snapshot([CursorTranscriptActivity(project: "previous", minutes: IndexSet(integer: expiredMinute))])
        suite.expect(!outside.hasPartialCost(.month) && !outside.historyTotal.hasPartialCost,
                     "activity outside the retained history leaves all displayed costs complete")
    }

    private static func reconciledCoverage(_ suite: TestSuite) {
        let store = AgentUsageStore()
        let missing = Log(store: store)
        let first = Log(project: "first", store: store)
        let second = Log(project: "second", store: store)
        let unrelated = Log(session: "other", store: store)
        let session = missing.state.session
        let dated = #"{"role":"assistant","timestamp":"2026-11-18T10:00:32Z","message":{"id":"one","model":"gpt-5.2"}}"#
        let metered = #"{"role":"assistant","timestamp":"2026-11-18T10:00:32Z","message":{"id":"one","model":"gpt-5.2","usage":{"output_tokens":1000}}}"#
        missing.feed(dated)
        let emptyRevision = store.cursorUsageRevision(for: session)
        unrelated.feed(metered)
        suite.expect(store.cursorUsageRevision(for: session) == emptyRevision
                     && store.transcriptActivity(for: missing.state).minutes.count == 1,
                     "the same response ID in another Cursor session cannot resolve an unmetered reply")
        first.feed(metered)
        let measuredRevision = store.cursorUsageRevision(for: session)
        second.feed(metered)
        store.forgetUsage(files: [first.path])
        suite.expect(measuredRevision != emptyRevision && store.cursorUsageRevision(for: session) == measuredRevision
                     && store.transcriptActivity(for: missing.state).minutes.isEmpty,
                     "a duplicate and removal of one metered copy preserve the original session's resolved coverage")
        let restored = AgentUsageStore(saved: store.saved)
        suite.expect(restored.cursorUsageRevision(for: session) != 0 && restored.transcriptActivity(for: missing.state).minutes.isEmpty,
                     "restored measured IDs resolve the same gaps as the live store")
        restored.dropRecords(before: missing.now)
        suite.expect(restored.cursorUsageRevision(for: session) == 0 && restored.transcriptActivity(for: missing.state).minutes.count == 1,
                     "pruning the last metered copy restores its unmetered observation")
        store.forgetUsage(files: [second.path])
        first.feed(metered)
        suite.expect(store.cursorUsageRevision(for: session) != measuredRevision,
                     "a removed and reinserted session key invalidates coverage across both changes")
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
