// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CursorTranscriptReadTests {
    private static let start = AgentTimestamp.parse("2026-11-18T12:00:00Z")!
    private static let finished = #"{"type":"turn_ended","status":"success"}"#
    private static let assistant = #"{"role":"assistant","message":{"content":[]}}"#

    private static func prompt(_ text: String, dated: Bool = false) -> String {
        let prefix = dated ? "<timestamp>Wednesday, Nov 18, 2026, 12:00 PM (UTC)</timestamp>" : ""
        return #"{"role":"user","message":{"content":[{"type":"text","text":"\#(prefix)<user_query>\#(text)</user_query>"}]}}"#
    }

    private final class Log {
        let root: URL
        let file: URL
        var cursor: AgentLogCursor
        var store = AgentUsageStore()
        var events: [AgentUsageEvent] = []

        init(_ directory: URL, _ name: String) {
            root = AgentLogRoot.canonical(directory.deletingLastPathComponent().deletingLastPathComponent())
            file = AgentLogRoot.canonical(directory).appending(path: name + ".jsonl")
            cursor = AgentLogCursor(path: file.path, provider: .cursor, cursorRoot: root)
            store.reportsTransitions = true
        }

        func write(_ lines: [String], at seconds: TimeInterval, append: Bool = false) throws {
            let data = Data((lines.joined(separator: "\n") + "\n").utf8)
            if append {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: file, options: .atomic)
            }
            try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(seconds)],
                                                  ofItemAtPath: file.path)
        }

        func read(at seconds: TimeInterval) {
            _ = AgentLogReader.readCursor(cursor, into: store, now: start.addingTimeInterval(seconds)) {
                self.events.append($0)
            }
        }
    }

    static func run(_ suite: TestSuite) {
        let temp = FileManager.default.temporaryDirectory.appending(path: "vorss-cursor-reads-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        let directory = temp.appending(path: ".cursor/projects/workspace/agent-transcripts")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try history(suite, directory)
            try meteredReplies(suite, directory)
            try streamedCoverage(suite, directory)
            try unmeteredReplies(suite, directory)
            try inactiveCoverage(suite, directory)
            try editedWhileGrowing(suite, directory)
            try cancelVerification(suite, directory)
            try sharedMeteredReplies(suite, directory)
            try rewrites(suite, directory)
            try cache(suite, directory)
            try archiveRoot(suite, temp)
        } catch {
            suite.expect(false, "could not exercise the Cursor transcript reader: \(error)")
        }
    }

    private static func inactiveCoverage(_ suite: TestSuite, _ directory: URL) throws {
        typealias Archive = AgentUsageArchiveSaveTests.AgentUsageArchive
        let prior = Archive.saved
        defer { Archive.saved = prior }
        let quiet = Log(directory, "quiet")
        let active = Log(directory, "active")
        active.store = quiet.store
        let host = AgentUsageArchiveSaveTests.Host()
        host.enabled = [.cursor]
        host.store = quiet.store
        host.cursors = [quiet.file.path: quiet.cursor, active.file.path: active.cursor]
        let window = AgentUsageSnapshot.historyDuration
        func gap(_ id: String, after seconds: TimeInterval) -> String {
            let stamp = ISO8601DateFormatter().string(from: start.addingTimeInterval(seconds))
            return #"{"role":"assistant","timestamp":"\#(stamp)","message":{"id":"\#(id)"}}"#
        }
        let anonymous = #"{"role":"assistant","timestamp":"2026-11-18T12:00:10Z","message":{"model":"old-model"}}"#
        try quiet.write([gap("old", after: 0), anonymous, assistant], at: 10)
        quiet.read(at: 10)
        try active.write([gap("old", after: 0)], at: 0)
        active.read(at: 0)
        try active.write([gap("recent", after: window - 60)], at: window - 60, append: true)
        active.read(at: window - 60)
        host.saveProgress(now: start.addingTimeInterval(window - 60))
        let quietActivity = quiet.cursor.transcriptActivity(in: host.store)
        suite.expect(quietActivity.minutes.count == 1 && quietActivity.modelMinutes["old-model"] != nil
                     && quietActivity.undatedThrough == start.addingTimeInterval(10)
                     && active.cursor.transcriptActivity(in: host.store).minutes.count == 2,
                     "both transcripts publish their dated gaps before the first one expires")

        let later = start.addingTimeInterval(window + 60)
        host.saveProgress(now: later)
        let saved = Archive.saved.last?.cursors
        let quietState = saved?.first { $0.path == quiet.file.path }?.state
        suite.expect(Archive.saved.count == prior.count + 2
                     && quietState?.cursorUnmeteredResponses.isEmpty == true && quietState?.cursorUnmeteredMinutes.isEmpty == true
                     && quietState?.cursorUnmeteredModelMinutes.isEmpty == true && quietState?.cursorUndatedResponseThrough == nil
                     && saved?.first(where: { $0.path == active.file.path })?.state.cursorUnmeteredResponses.keys.sorted() == ["recent"]
                     && quiet.cursor.transcriptActivity(in: host.store).minutes.isEmpty
                     && active.cursor.transcriptActivity(in: host.store).minutes.count == 1,
                     "the save expires quiet and active transcripts from the checkpoint and their cached coverage without another read")
        host.saveProgress(now: later)
        suite.expect(Archive.saved.count == prior.count + 2, "the same checkpoint stays clean after the expiry was saved")
    }

    private static func history(_ suite: TestSuite, _ directory: URL) throws {
        let log = Log(directory, "history")
        try log.write([prompt("old"), assistant], at: -86_400)
        log.read(at: 0)
        log.store.closeIdleTurns(now: start, after: NotchAgentSupport.idleTurn)
        suite.expect(log.store.live.isEmpty && log.events.isEmpty &&
                     log.cursor.state.cursorLastActivity == start.addingTimeInterval(-86_400),
                     "an old unfinished Cursor file is quiet and keeps its actual last activity")

        let closed = Log(directory, "closed")
        try closed.write([prompt("old", dated: true), assistant, finished], at: 120)
        closed.read(at: 121)
        try closed.write([prompt("old", dated: true), assistant, finished], at: 135)
        closed.read(at: 136)
        suite.expect(closed.events.isEmpty && closed.store.live.isEmpty && closed.store.records.isEmpty &&
                     !closed.cursor.state.turnOpen, "attaching and replaying a closed transcript never reports a new finish")

        let loading = Log(directory, "loading")
        loading.store.reportsTransitions = false
        try loading.write([prompt("in progress", dated: true)], at: 55)
        loading.read(at: 57)
        loading.store.reportsTransitions = true
        try loading.write([finished], at: 61, append: true)
        loading.read(at: 62)
        suite.expect(loading.events == [.finished(provider: .cursor, duration: 6, cost: 0, tokens: 0, project: "workspace")],
                     "attaching just before the minute changes does not announce a short turn as a long task")
    }

    private static func meteredReplies(_ suite: TestSuite, _ directory: URL) throws {
        let log = Log(directory, "metered")
        let previousDay = "2026-11-17T23:59:59Z"
        let thisDay = "2026-11-18T00:00:01Z"
        func reply(_ id: String, _ date: String, output: Int = 20) -> String {
            #"{"role":"assistant","timestamp":"\#(date)","message":{"model":"fixture-unpriced","usage":{"message_id":"\#(id)","input_tokens":10,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":\#(output),"output_tokens_details":{"thinking_tokens":4}}}}"#
        }
        let first = reply("one", previousDay)
        let second = reply("two", thisDay)
        let third = reply("three", thisDay)
        let nested = #"{"role":"assistant","message":{"content":[{"usage":{"message_id":"embedded","output_tokens":9999},"timestamp":"2026-11-18T00:00:01Z"}]}}"#
        let undated = #"{"role":"assistant","message":{"usage":{"message_id":"undated","output_tokens":9999}}}"#
        try log.write([prompt("one"), first, reply("one", previousDay, output: 30), second, third, third,
                       nested, undated, reply("", thisDay), reply("bad-date", "2026-02-30T00:00:00Z"),
                       reply("out-of-window", "2025-01-01T00:00:00Z"), reply("in-future", "2027-01-01T00:00:00Z"), finished], at: 1)
        func read(_ seconds: TimeInterval) {
            _ = AgentLogReader.readCursor(log.cursor, into: log.store, now: start.addingTimeInterval(seconds),
                                          since: start.addingTimeInterval(-86_400)) { log.events.append($0) }
        }
        read(2)
        let records = log.store.records
        suite.expect(records.count == 3 && records.first?.date == AgentTimestamp.parse(previousDay)
                     && records.first?.tokens == AgentTokens(input: 10, cacheWrite: 2, cacheRead: 3, output: 30, reasoning: 4)
                     && records.last?.date == AgentTimestamp.parse(thisDay) && records.last?.cost == nil,
                     "Cursor counts distinct dated response IDs, merges streamed counters, and leaves reasoning inside output")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let snapshot = log.store.snapshot(plans: [:], providers: [.cursor], now: start, calendar: calendar)
        suite.expect(snapshot.usage(.today).byProvider[.cursor]?.tokens.total == 70 && log.events.isEmpty && log.store.live.isEmpty,
                     "Cursor usage keeps each response's own day across midnight, without historical finish notices")

        try log.write([reply("four", thisDay)], at: 5, append: true)
        read(6)
        let saved = AgentUsageArchive.Contents(providers: [.cursor], store: log.store.saved, cursors: [log.cursor.saved])
        let resumed = AgentUsageArchive.resume(saved, logs: [log.file.path], since: .distantPast, cursorRoot: log.root)
        guard let cursor = resumed.cursors[log.file.path] else {
            return suite.expect(false, "the metered Cursor transcript restores")
        }
        log.cursor = cursor
        log.store = resumed.store
        read(7)
        suite.expect(log.store.records.count == 4, "a Cursor append, then a resumed offset, counts its reply only once")

        try log.write([prompt("rewritten"), reply("two", thisDay, output: 7), finished], at: 12)
        read(13)
        read(14)
        suite.expect(log.store.records.count == 1 && log.store.records.first?.tokens.output == 7 && log.events.isEmpty,
                     "rewriting the transcript removes missing replies and corrects a smaller counter without a finish")
        let flatModel = #""model":"fixture-unpriced""#
        let lateModel = reply("one", thisDay).replacingOccurrences(of: flatModel, with: #""model":"""#)
        let knownModel = reply("one", thisDay).replacingOccurrences(of: flatModel,
            with: #""model":"","modelInfo":{"modelId":"gpt-5.2"}"#)
        let padding = #"{"ignored":""# + String(repeating: "x", count: 8192) + #""}"#
        try log.write([padding, lateModel, knownModel, padding, finished], at: 14)
        read(15)
        let expectedCost = AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 10, cacheWrite: 2, cacheRead: 3, output: 20, reasoning: 4)), model: "gpt-5.2").cost
        suite.expect(log.store.records.count == 1 && log.store.records.first?.model == "gpt-5.2"
                     && expectedCost != nil && log.store.records.first?.cost == expectedCost,
                     "later metadata prices a streamed Cursor response even without counter growth")

        let original = try Data(contentsOf: log.file)
        let edited = String(decoding: original, as: UTF8.self).replacingOccurrences(of: #""output_tokens":20"#, with: #""output_tokens":18"#)
        try Data(edited.utf8).write(to: log.file)
        try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(16)], ofItemAtPath: log.file.path)
        read(17)
        suite.expect(original.count == edited.utf8.count && log.store.records.first?.tokens.output == 18,
                     "a same-inode, same-size edit in the middle corrects counters beyond both sampled edges")

        try FileManager.default.removeItem(at: log.file)
        read(18)
        suite.expect(log.store.records.isEmpty, "a removed Cursor transcript takes its response counters back")
    }

    private static func streamedCoverage(_ suite: TestSuite, _ directory: URL) throws {
        let name = "streamed-coverage"
        let original = Log(directory, name)
        let model = "gpt-5.2", otherModel = "gpt-6-astra"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func reply(_ id: String, metered: Bool, model: String? = nil, dated: Bool = true) -> String {
            let usage = metered ? #","usage":{"message_id":"\#(id)","output_tokens":1000}"# : ""
            let timestamp = dated ? #""timestamp":"2026-11-18T12:00:00Z","# : ""
            let modelField = model.map { #","model":"\#($0)""# } ?? ""
            return #"{"role":"assistant",\#(timestamp)"message":{"id":"\#(id)"\#(modelField)\#(usage)}}"#
        }
        func today(_ logs: [Log]) -> AgentPeriodUsage {
            let store = original.store
            return store.snapshot(plans: [:], providers: [.cursor], now: start.addingTimeInterval(60), calendar: calendar,
                                  cursorActivity: logs.map { $0.cursor.transcriptActivity(in: store) }).usage(.today)
        }

        try original.write([reply("first", metered: false, model: model), reply("second", metered: true),
                            reply("anchor", metered: true, model: otherModel), reply("third", metered: false, model: otherModel)], at: 1)
        original.read(at: 2)
        suite.expect(today([original]).total.hasPartialCost, "an unresolved stream begins with partial coverage")
        let unrelated = Log(directory, "different-session")
        unrelated.store = original.store
        try unrelated.write([reply("second", metered: false, model: otherModel), finished], at: 2)
        unrelated.read(at: 2)
        suite.expect(original.store.records.first?.model == "" && original.store.records.first?.cost == nil,
                     "a model fragment from another session cannot price an identically named response")
        try original.write([reply("first", metered: true),
                            reply("second", metered: false, model: model, dated: false)], at: 3, append: true)
        original.read(at: 4)
        let priced = original.store.records.filter { $0.model == model }
        let cost = AgentPricing.cost(AgentBillable(tokens: AgentTokens(output: 1000)), model: model).cost
        suite.expect(cost != nil && priced.count == 2 && priced.allSatisfy { $0.cost == cost && $0.tokens.output == 1000 },
                     "a model before or after its separate counters prices exactly one request in both stream orders")
        let replay = Log(directory, name)
        replay.read(at: 4)
        suite.expect(replay.store.records == original.store.records,
                     "replaying the same transcript preserves both split models, costs and token counts")
        let mixed = today([original])
        suite.expect(mixed.total.requests == 3 && mixed.total.hasPartialCost
                     && mixed.models.first { $0.name == AgentPricing.displayName(model) }?.totals.hasPartialCost == false
                     && mixed.models.first { $0.name == AgentPricing.displayName(otherModel) }?.totals.hasPartialCost == true,
                     "resolving a response preserves another ID's gap in the same minute and only its model stays partial")
        try original.write([reply("third", metered: true, model: otherModel)], at: 5, append: true)
        original.read(at: 6)
        let complete = today([original])
        suite.expect(complete.total.requests == 4 && complete.total.tokens.output == 4000 && !complete.total.hasPartialCost,
                     "counters supersede undated or dated fragments of the same response in either stream order")

        try original.write([reply("shared", metered: false, model: model)], at: 7, append: true)
        original.read(at: 8)
        suite.expect(today([original]).total.hasPartialCost, "a new ID remains unresolved before its metered copy arrives")
        let folder = original.root.appending(path: "coverage-copy/agent-transcripts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = Log(folder, name)
        copy.store = original.store
        try copy.write([reply("shared", metered: true, model: model)], at: 9)
        copy.read(at: 10)
        let copied = today([original, copy])
        suite.expect(copied.total.requests == 5 && !copied.total.hasPartialCost,
                     "a metered copy resolves a gap from another transcript of the same session")

        let saved = AgentUsageArchive.Contents(providers: [.cursor], store: original.store.saved,
                                               cursors: [original.cursor.saved, copy.cursor.saved])
        let data = AgentUsageArchive.encode(saved, build: name)
        guard let decoded = AgentUsageArchive.decode(data, build: name) else {
            return suite.expect(false, "the streamed coverage checkpoint decodes")
        }
        let resumed = AgentUsageArchive.resume(decoded, logs: [original.file.path, copy.file.path],
                                              since: .distantPast, cursorRoot: original.root)
        guard let restoredOriginal = resumed.cursors[original.file.path], let restoredCopy = resumed.cursors[copy.file.path] else {
            return suite.expect(false, "both Cursor streams resume from the checkpoint")
        }
        original.cursor = restoredOriginal
        copy.cursor = restoredCopy
        copy.store = resumed.store
        original.store = resumed.store
        copy.read(at: 11)
        original.read(at: 12)
        suite.expect(today([original, copy]) == copied, "restoring the streams preserves reconciled coverage and usage")
        try FileManager.default.removeItem(at: copy.file)
        copy.read(at: 13)
        let remaining = today([original])
        suite.expect(remaining.total.requests == 4 && remaining.total.hasPartialCost
                     && remaining.projects.first { $0.name == "workspace" }?.totals.hasPartialCost == true,
                     "removing the only metered copy exposes the original project's unresolved response again")
        try original.write([reply("shared", metered: true, model: model),
                            reply("unknown", metered: false, model: "fixture-no-price"),
                            reply("unknown", metered: true, model: "fixture-no-price")], at: 14, append: true)
        original.read(at: 15)
        let unpriced = today([original]).total
        suite.expect(unpriced.requests == 6 && unpriced.unpriced == 1 && unpriced.hasPartialCost
                     && !unpriced.includesUnmeteredCursorActivity,
                     "an unpriced model's counters resolve its missing usage while its cost remains partial")
    }

    private static func unmeteredReplies(_ suite: TestSuite, _ directory: URL) throws {
        let log = Log(directory, "unmetered")
        func reply(_ date: String, model: String = "") -> String {
            #"{"role":"assistant","timestamp":"\#(date)","message":{"model":"\#(model)"}}"#
        }
        func minute(_ date: Date) -> Int { Int(date.timeIntervalSince1970 / 60) }
        // Local midnight in UTC+05:45 splits these two minutes.
        let before = AgentTimestamp.parse("2026-11-17T18:14:00Z")!
        let after = before.addingTimeInterval(60)
        let minutes = IndexSet([minute(before), minute(after), minute(start)])
        let stable = CursorUnmeteredResponse(minute: minute(start), model: "named", undatedThrough: nil)
        try log.write([reply("2026-11-17T18:14:59.999Z", model: "first"), reply("2026-11-17T18:15:00Z", model: "first"),
                       reply("2026-11-17T18:15:32Z"), reply("2026-11-18T12:00:01Z", model: "second"),
                       reply("2025-01-01T00:00:00Z"), reply("2027-01-01T00:00:00Z"),
                       #"{"role":"assistant","message":{"id":"expired"}}"#,
                       #"{"role":"assistant","timestamp":"2025-01-01T00:00:00Z","message":{"id":"expired"}}"#,
                       #"{"role":"assistant","message":{"id":"stream","model":"named"}}"#,
                       #"{"role":"assistant","timestamp":"2026-11-18T12:00:01Z","message":{"id":"other","usage":{"message_id":"stream"}}}"#,
                       #"{"role":"assistant","message":{"model":"undated"}}"#, finished], at: -1)
        log.read(at: 2)
        suite.expect(log.cursor.state.cursorUnmeteredMinutes == minutes
                     && log.cursor.state.cursorUnmeteredModelMinutes == ["first": minute(after), "second": minute(start)]
                     && log.cursor.state.cursorUndatedResponseThrough == start.addingTimeInterval(-1)
                     && log.cursor.state.cursorUnmeteredResponses == ["stream": stable]
                     && log.cursor.state.cursorEarliestUnmeteredResponse == start
                     && log.store.records.isEmpty && log.events.isEmpty,
                     "dated unmetered replies keep their own minutes and an undated reply keeps only the observed upper bound")
        let saved = AgentUsageArchive.Contents(providers: [.cursor], store: log.store.saved, cursors: [log.cursor.saved])
        let data = AgentUsageArchive.encode(saved, build: "unmetered")
        var inconsistent = saved
        log.cursor.state.setUnmeteredResponse(CursorUnmeteredResponse(minute: minute(start), undatedThrough: start), id: "invalid")
        inconsistent.cursors = [log.cursor.saved]
        suite.expect(AgentUsageArchive.decode(AgentUsageArchive.encode(inconsistent, build: "unmetered"), build: "unmetered") == nil,
                     "the cache rejects a response with both a dated minute and an undated bound even under a valid checksum")
        guard let decoded = AgentUsageArchive.decode(data, build: "unmetered"), decoded == saved,
              let cursor = AgentUsageArchive.resume(decoded, logs: [log.file.path], since: .distantPast,
                                                    cursorRoot: log.root).cursors[log.file.path] else {
            return suite.expect(false, "unmetered Cursor coverage survives the binary archive and resumes at its offset")
        }
        log.cursor = cursor
        let pruned = AgentUsageArchive.resume(saved, logs: [log.file.path], since: start, cursorRoot: log.root)
        suite.expect(!pruned.unchanged && pruned.cursors[log.file.path]?.state.cursorUnmeteredMinutes == IndexSet(integer: minute(start))
                     && pruned.cursors[log.file.path]?.state.cursorUnmeteredModelMinutes == ["second": minute(start)]
                     && pruned.cursors[log.file.path]?.state.cursorUndatedResponseThrough == nil,
                     "resuming after earlier gaps expire keeps only the current minute and schedules a new checkpoint")
        let measured = #"{"role":"assistant","timestamp":"2026-11-18T12:00:01Z","message":{"id":"stream","model":"named","usage":{"output_tokens":5}}}"#
        try log.write([reply("2026-11-18T11:20:01Z"), measured,
                       #"{"role":"assistant","message":{"id":"bounded"}}"#], at: 5, append: true)
        log.read(at: 6)
        let appended = minute(start.addingTimeInterval(-40 * 60))
        suite.expect(cursor.state.cursorUnmeteredMinutes == minutes.union(IndexSet(integer: appended))
                     && cursor.state.cursorUndatedResponseThrough == start.addingTimeInterval(-1)
                     && cursor.state.cursorUnmeteredResponses["bounded"]?.undatedThrough == start.addingTimeInterval(5)
                     && cursor.state.cursorUnmeteredResponses["stream"] == stable && log.store.records.count == 1,
                     "an identified gap keeps its source evidence when counters arrive, independently of anonymous and undated replies")
        let expired = AgentUsageArchive.resume(saved, logs: [log.file.path], since: start.addingTimeInterval(60), cursorRoot: log.root)
        suite.expect(expired.cursors[log.file.path]?.state.cursorUnmeteredResponses.isEmpty == true,
                     "restored response IDs expire at their dated minute, including a reply first seen without a date")

        try log.write([reply("2026-11-18T11:20:01Z"), finished], at: 7)
        log.read(at: 8)
        suite.expect(cursor.state.cursorUnmeteredMinutes == IndexSet(integer: appended) && cursor.state.cursorUndatedResponseThrough == nil
                     && cursor.state.cursorUnmeteredModelMinutes.isEmpty,
                     "a rewritten transcript withdraws dated and undated gaps from its removed replies")
        let later = AgentUsageSnapshot.historyDuration + 86_400
        let recent = start.addingTimeInterval(later)
        let unix = Int(recent.timeIntervalSince1970)
        try log.write([#"{"role":"assistant","timestamp":\#(unix),"message":{}}"#], at: 7, append: true)
        log.read(at: later + 1)
        suite.expect(cursor.state.cursorUnmeteredMinutes == IndexSet(integer: minute(recent)) && cursor.state.cursorUndatedResponseThrough == nil,
                     "a long-lived transcript drops expired minutes even when its append preserves the modification time")
        try FileManager.default.removeItem(at: log.file)
        log.read(at: later + 2)
        suite.expect(cursor.state.cursorUndatedResponseThrough == nil && cursor.state.cursorUnmeteredMinutes.isEmpty,
                     "removing a transcript removes its remaining coverage")
    }

    private static func editedWhileGrowing(_ suite: TestSuite, _ directory: URL) throws {
        let name = "growing"
        let log = Log(directory, name)
        let quiet = Log(directory, name)
        func reply(_ id: String, _ count: Int) -> String {
            #"{"role":"assistant","timestamp":"2026-11-18T12:00:00Z","message":{"id":"\#(id)","usage":{"output_tokens":\#(count)}}}"#
        }
        func archive() -> Data {
            let contents = AgentUsageArchive.Contents(providers: [.cursor], store: log.store.saved, cursors: [log.cursor.saved])
            return AgentUsageArchive.encode(contents, build: "growing-test")
        }
        let padding = #"{"ignored":""# + String(repeating: "x", count: 160 << 10) + #""}"#
        try log.write([padding, reply("middle", 20), padding, finished], at: 1)
        log.read(at: 2)
        quiet.read(at: 2)
        let identity = log.cursor.identity
        let before = archive()
        let middle = UInt64(padding.utf8.count + 1)
        var checked: UInt64 = 0
        for second in 3...7 {
            try log.write(["{}"], at: TimeInterval(second), append: true)
            log.read(at: TimeInterval(second))
            quiet.read(at: TimeInterval(second))
            let next = log.cursor.cursorPrefix.checkedBytes
            suite.expect(!log.cursor.restarted && next > checked && next - checked <= 64 << 10,
                         "a small Cursor append advances a bounded prefix check without replaying history")
            checked = next
        }
        suite.expect(checked > middle + UInt64(reply("middle", 20).utf8.count) && checked < log.cursor.offset,
                     "the fixture edits an already checked region while the first pass is still running")

        verifyQuietCheckpoint(suite, log: quiet, data: archive())
        do {
            let handle = try FileHandle(forWritingTo: log.file)
            defer { try? handle.close() }
            try handle.seek(toOffset: middle)
            try handle.write(contentsOf: Data(reply("middle", 18).utf8))
        }
        try log.write([reply("appended", 7)], at: 8, append: true)
        log.read(at: 9)
        let during = archive()
        let cold = Log(directory, name)
        cold.read(at: 10)
        let expected = cold.store.saved.records
        suite.expect(log.cursor.identity == identity && log.cursor.cursorPrefix.needsVerification &&
                     log.store.records.count == 2 && log.store.records.last?.tokens.output == 7 &&
                     expected.map { $0.record.tokens.output } == [18, 7],
                     "a small append counts the new reply while the same inode's old prefix is still being checked")

        func checkRestore(_ data: Data, _ label: String, verified: Bool = false) {
            guard let contents = AgentUsageArchive.decode(data, build: "growing-test") else {
                return suite.expect(false, "the Cursor archive decodes \(label)")
            }
            let resumed = AgentUsageArchive.resume(contents, logs: [log.file.path], since: .distantPast, cursorRoot: log.root)
            let launch = Log(directory, name)
            if let cursor = resumed.cursors[log.file.path] { launch.cursor = cursor }
            if verified {
                suite.expect(launch.cursor.offset == log.cursor.offset, "the corrected checkpoint retains its verified offset")
            }
            launch.store = resumed.store
            launch.read(at: 90)
            suite.expect(launch.store.saved.records == expected && launch.events.isEmpty,
                         "archive resume matches a cold Cursor read \(label)")
        }
        checkRestore(before, "from before the edit")
        checkRestore(during, "while the old prefix is still being checked")

        quiet.read(at: 9)
        quiet.read(at: 10)
        quiet.read(at: 11)
        suite.expect(quiet.store.saved.records == expected && quiet.events.isEmpty,
                     "verification corrects the Cursor count even when the writer goes quiet after the append")
        for second in 12...36 {
            if log.cursor.restarted { break }
            try log.write(["{}"], at: TimeInterval(second), append: true)
            log.read(at: TimeInterval(second))
        }
        suite.expect(log.cursor.restarted && log.store.saved.records == expected && log.events.isEmpty,
                     "continued small appends recheck earlier bytes and converge to the cold Cursor reading")
        checkRestore(archive(), "after correcting the running total", verified: true)
    }

    private static func verifyQuietCheckpoint(_ suite: TestSuite, log: Log, data: Data) {
        let path = log.file.path
        guard var contents = AgentUsageArchive.decode(data, build: "growing-test") else {
            return suite.expect(false, "the pending Cursor checkpoint decodes")
        }
        let resumed = AgentUsageArchive.resume(contents, logs: [path], since: .distantPast, cursorRoot: log.root)
        guard let cursor = resumed.cursors[path] else {
            return suite.expect(false, "a pending checkpoint with a valid prefix restores its cursor")
        }
        suite.expect(contents.cursors.first?.cursorSample == nil && !resumed.unchanged && cursor.offset == log.cursor.offset
                     && resumed.store.saved == contents.store && cursor.saved.cursorSample != nil,
                     "restoring a valid pending checksum preserves the reading and schedules its verified checkpoint")
        contents.cursors = [cursor.saved]
        let stable = AgentUsageArchive.resume(contents, logs: [path], since: .distantPast, cursorRoot: log.root)
        suite.expect(stable.unchanged, "reopening that verified checkpoint requires no further save")

        let host = AgentUsageReadTests.Host()
        host.watchedRoots = [AgentLogRoot(provider: .cursor, url: log.root)]
        host.cursors[path] = log.cursor
        host.store = log.store
        let pendingMark = host.progressMark
        _ = host.pollOpenLogs(within: 0)
        _ = host.pollOpenLogs(within: 0)
        suite.expect(!log.cursor.cursorPrefix.needsVerification && log.cursor.saved == cursor.saved
                     && host.progressMark != pendingMark && host.store.saved == contents.store,
                     "quiet polls complete verification and mark it for saving without another append or record change")
    }

    private static func cancelVerification(_ suite: TestSuite, _ directory: URL) throws {
        let log = Log(directory, "cancel-verification")
        let other = Log(directory, "cancel-between-files")
        let padding = #"{"ignored":""# + String(repeating: "x", count: 2 << 20) + #""}"#
        let metered = #"{"role":"assistant","timestamp":"2026-11-18T12:00:00Z","message":{"id":"one","usage":{"output_tokens":20}}}"#
        let lines = [prompt("open"), metered, padding]
        try log.write(lines, at: 1)
        log.read(at: 2)
        try other.write(["{}"], at: 1)
        other.read(at: 2)
        let checkpoint = log.cursor.saved
        let saved = AgentUsageArchive.Contents(providers: [.cursor], store: log.store.saved, cursors: [checkpoint])
        func allow(_ checks: Int) -> () -> Bool {
            var remaining = checks
            return {
                remaining -= 1
                return remaining >= 0
            }
        }
        var both = saved
        both.cursors.append(other.cursor.saved)
        let partial = AgentUsageArchive.resume(both, logs: [log.file.path, other.file.path], since: .distantPast,
                                               cursorRoot: log.root, shouldContinue: allow(1))
        suite.expect(partial == nil, "stopping between two unchanged logs does not return a partial cache")

        try log.write(["{}"], at: 3, append: true)
        // The file check and two 1 MiB blocks succeed before cancellation.
        let cancelled = AgentUsageArchive.resume(saved, logs: [log.file.path], since: .distantPast,
                                                 cursorRoot: log.root, shouldContinue: allow(3))
        suite.expect(cancelled == nil, "restoring a single grown transcript can stop between checksum blocks")
        let resumed = AgentUsageArchive.resume(saved, logs: [log.file.path], since: .distantPast, cursorRoot: log.root)
        guard let cursor = resumed.cursors[log.file.path] else {
            return suite.expect(false, "the interrupted cache can be verified on retry")
        }
        log.cursor = cursor
        log.store = resumed.store
        log.store.reportsTransitions = true
        suite.expect(cursor.saved == checkpoint && log.store.saved == saved.store && log.store.records.first?.tokens.output == 20,
                     "retrying verification restores the original open turn, counted reply and offset")

        try log.write(lines + ["{}", finished], at: 12)
        let changed = AgentLogReader.readCursor(cursor, into: log.store, now: start.addingTimeInterval(13),
                                                shouldContinue: allow(3)) { log.events.append($0) }
        suite.expect(!changed && cursor.saved == checkpoint && log.store.saved == saved.store && log.events.isEmpty,
                     "stopping during the restored prompt's prefix check preserves its checkpoint and usage")
        log.read(at: 14)
        log.read(at: 15)
        suite.expect(!cursor.state.turnOpen && log.store.saved.records == saved.store.records &&
                     log.events == [.finished(provider: .cursor, duration: 11, cost: 0, tokens: 0, project: "workspace")],
                     "retrying the preserved prompt counts its reply once and reports its finish from the observed start")
    }

    private static func archiveRoot(_ suite: TestSuite, _ temp: URL) throws {
        let manager = FileManager.default
        let directory = temp.appending(path: ".cursor/projects/cache-root/agent-transcripts")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = Log(directory, "empty")
        try log.write(["{}"], at: 0)
        log.read(at: 1)
        let offset = log.cursor.offset
        let saved = AgentUsageArchive.Contents(providers: [.cursor], store: log.store.saved, cursors: [log.cursor.saved])
        func restore() -> AgentLogCursor? {
            AgentUsageArchive.resume(saved, logs: [log.file.path], since: .distantPast, cursorRoot: log.root)
                .cursors[log.file.path]
        }
        suite.expect(offset > 0 && restore()?.offset == offset, "a regular transcript restores from the admitted root")

        // A saved name can have a different parent by the time reading resumes.
        let moved = temp.appending(path: "former-transcripts")
        try manager.moveItem(at: directory, to: moved)
        try manager.createSymbolicLink(at: directory, withDestinationURL: moved)
        suite.expect(restore() == nil, "a cache hit still requires a transcript inside its authorized root")
        let handle = try FileHandle(forWritingTo: moved.appending(path: log.file.lastPathComponent))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{}\n".utf8))
        log.read(at: 2)
        suite.expect(log.cursor.offset <= offset && log.store.live.isEmpty && log.events.isEmpty,
                     "an existing cursor consumes no bytes after its transcript directory becomes a link")
    }

    private static func rewrites(_ suite: TestSuite, _ directory: URL) throws {
        let log = Log(directory, "two-in-one-minute")
        let first = prompt("first", dated: true)
        let second = prompt("second", dated: true)
        try log.write(["{}"], at: 0)
        log.read(at: 1)
        try log.write([first], at: 3, append: true)
        log.read(at: 4)
        try log.write([finished], at: 10, append: true)
        log.read(at: 11)
        try log.write([second], at: 15, append: true)
        log.read(at: 16)
        suite.expect(log.cursor.state.cursorPromptCount == 2 && log.store.live.first?.started == start.addingTimeInterval(15),
                     "two prompts with the same minute tag keep distinct observed starts")
        try log.write([first, finished, second, assistant, finished], at: 48)
        log.read(at: 50)
        log.read(at: 51)
        suite.expect(log.events == [.finished(provider: .cursor, duration: 7, cost: 0, tokens: 0, project: "workspace"),
                                    .finished(provider: .cursor, duration: 33, cost: 0, tokens: 0, project: "workspace")],
                     "rewriting both turns reports only the new finish and keeps its observed duration")

        let undated = Log(directory, "undated")
        try undated.write([prompt("keep")], at: 9)
        undated.read(at: 11)
        try undated.write([prompt("keep"), assistant], at: 19)
        undated.read(at: 21)
        try undated.write([prompt("keep"), assistant, finished], at: 55)
        undated.read(at: 65)
        suite.expect(undated.events == [.finished(provider: .cursor, duration: 46, cost: 0, tokens: 0, project: "workspace")],
                     "an undated but observed prompt keeps its original start across intermediate and final rewrites")

        let replaced = Log(directory, "replaced")
        try replaced.write([first], at: 4)
        replaced.read(at: 5)
        try replaced.write([second, finished], at: 40)
        replaced.read(at: 45)
        suite.expect(replaced.events.isEmpty && replaced.store.live.isEmpty,
                     "a different prompt at the same ordinal and minute cannot finish the previously observed turn")
    }

    private static func cache(_ suite: TestSuite, _ directory: URL) throws {
        let log = Log(directory, "cached")
        try log.write(["{}"], at: 1)
        log.read(at: 2)
        try log.write([prompt("saved", dated: true)], at: 9, append: true)
        log.read(at: 10)

        // Keep a real second cursor so resume retains this provider's usage.
        let file = directory.deletingLastPathComponent().appending(path: "codex.jsonl")
        try Data("{}\n".utf8).write(to: file)
        let codex = AgentLogCursor(path: file.path, provider: .codex)
        AgentLogReader.readAppended(codex) { _ in }
        let billable = AgentBillable(tokens: AgentTokens(input: 80, output: 20))
        let model = "gpt-6-astra"
        let priced = AgentPricing.cost(billable, model: model)
        let record = AgentUsageRecord(provider: .codex, date: start, model: model, project: "other", session: "other",
                                      tokens: billable.tokens, cost: priced.cost, savings: priced.savings)
        log.store.apply([.usage(key: "codex:test", record: record, billable: billable)],
                        file: file.path, provider: .codex, tracksTurns: false, modified: start)
        let now = start.addingTimeInterval(10)
        let providers: Set<AgentProvider> = [.codex, .cursor]
        let before = log.store.snapshot(plans: [:], providers: providers, now: now, cursorProjectsFound: true,
                                        cursorLastActivity: log.cursor.state.cursorLastActivity)
        let archive = AgentUsageArchive.Contents(providers: providers, store: log.store.saved,
                                                 cursors: [log.cursor.saved, codex.saved])
        let data = AgentUsageArchive.encode(archive, build: "cursor-test")
        guard let decoded = AgentUsageArchive.decode(data, build: "cursor-test") else {
            suite.expect(false, "the Cursor and Codex cache can be decoded")
            return
        }
        let resumed = AgentUsageArchive.resume(decoded, logs: [log.file.path, file.path], since: .distantPast,
                                              cursorRoot: log.root)
        guard let cursor = resumed.cursors[log.file.path] else {
            suite.expect(false, "the unchanged Cursor file resumes at its saved offset")
            return
        }
        log.cursor = cursor
        log.store = resumed.store
        log.store.reportsTransitions = true
        log.read(at: 12)
        let after = log.store.snapshot(plans: [:], providers: providers, now: now, cursorProjectsFound: true,
                                       cursorLastActivity: cursor.state.cursorLastActivity)
        let usage = after.usage(.today)
        suite.expect(usage == before.usage(.today) && usage.fullyPriced && usage.total.cost > 0 &&
                     usage.total.requests == 1 && usage.byProvider[.cursor] == nil &&
                     log.store.records.map(\.provider) == [.codex],
                     "Cursor activity leaves other providers' priced totals unchanged after archive repricing")
        suite.expect(after.seen.contains(.cursor) && after.lastActivity[.cursor] == start.addingTimeInterval(9) &&
                     after.cursorProjectsFound && cursor.state.cursorPromptCount == 1 && cursor.state.turnOpen,
                     "restoring the cache preserves Cursor activity and the open turn without a billing record")

        // A second restore from the same bytes exercises the valid finish
        // independently from a replacement that only looks like that turn.
        let verified = AgentUsageArchive.resume(decoded, logs: [log.file.path, file.path], since: .distantPast,
                                               cursorRoot: log.root)
        try log.write([prompt("other", dated: true), finished], at: 54)
        log.read(at: 56)
        suite.expect(log.events.isEmpty && log.store.live.isEmpty,
                     "a different prompt with identical timestamp and ordinal after cache restore does not notify")
        guard let verifiedCursor = verified.cursors[log.file.path] else {
            suite.expect(false, "the second cache restore also matched the original bytes")
            return
        }
        log.cursor = verifiedCursor
        log.store = verified.store
        log.store.reportsTransitions = true
        try log.write(["{}", prompt("saved", dated: true), assistant, finished], at: 54)
        log.read(at: 56)
        suite.expect(log.events == [.finished(provider: .cursor, duration: 45, cost: 0, tokens: 0, project: "workspace")],
                     "a rewrite preserving the verified cache prefix can finish the previously observed turn")
    }

    private static func sharedMeteredReplies(_ suite: TestSuite, _ directory: URL) throws {
        let manager = FileManager.default
        let projects = directory.deletingLastPathComponent().deletingLastPathComponent()
        let other = projects.appending(path: "copy/agent-transcripts")
        try manager.createDirectory(at: other, withIntermediateDirectories: true)
        let large = Log(directory, "shared")
        let small = Log(other, "shared")
        small.store = large.store
        func reply(_ count: Int) -> String {
            #"{"role":"assistant","timestamp":"2026-11-18T12:00:00Z","message":{"id":"one","usage":{"output_tokens":\#(count)}}}"#
        }
        try large.write([prompt("original"), reply(100)], at: 1)
        try small.write([prompt("copy"), reply(20)], at: 2)
        large.read(at: 3)
        small.read(at: 4)
        try small.write([reply(30)], at: 5, append: true)
        small.read(at: 6)
        let store = large.store
        suite.expect(store.records.count == 1 && store.records.first?.tokens.total == 100,
                     "multiple sources of the same Cursor response count the fullest single copy")
        let saved = AgentUsageArchive.Contents(providers: [.cursor], store: store.saved,
                                               cursors: [large.cursor.saved, small.cursor.saved])
        suite.expect(store.forgetUsage(files: [large.file.path]) && store.records.first?.tokens.total == 30,
                     "removing the larger reading publishes the latest remaining copy instead of its former maximum")
        let paths: Set<String> = [large.file.path, small.file.path]
        let stopped = AgentUsageArchive.resume(saved, logs: paths, since: .distantPast, cursorRoot: small.root)
        guard let first = stopped.cursors[small.file.path] else {
            return suite.expect(false, "the smaller shared copy is ready for replay before cancellation")
        }
        typealias RecordingArchive = AgentUsageArchiveSaveTests.AgentUsageArchive
        let prior = RecordingArchive.saved
        defer { RecordingArchive.saved = prior }
        RecordingArchive.saved = [saved]
        let host = AgentUsageArchiveSaveTests.Host()
        host.enabled = [.cursor]
        host.store = stopped.store
        host.cursors = stopped.cursors
        let now = start.addingTimeInterval(7)
        _ = AgentLogReader.readCursor(first, into: host.store, now: now, shouldContinue: { false }) { _ in }
        host.saveProgress()
        suite.expect(host.store.records.isEmpty && RecordingArchive.saved == [saved],
                     "stopping before shared Cursor replay keeps the last complete checkpoint")
        _ = AgentLogReader.readCursor(first, into: host.store, now: now) { _ in }
        host.saveProgress()
        suite.expect(host.store.records.first?.tokens.total == 30 && RecordingArchive.saved == [saved],
                     "stopping between shared copies preserves the checkpoint with the fuller reply")
        guard let checkpoint = RecordingArchive.saved.last else {
            return suite.expect(false, "a shared Cursor checkpoint survives shutdown")
        }
        let restored = AgentUsageArchive.resume(checkpoint, logs: paths, since: .distantPast, cursorRoot: small.root)
        guard let a = restored.cursors[large.file.path], let b = restored.cursors[small.file.path] else {
            return suite.expect(false, "both verified Cursor copies retain their progress for replay")
        }
        large.cursor = a
        small.cursor = b
        large.store = restored.store
        small.store = restored.store
        small.read(at: 7)
        large.read(at: 7)
        suite.expect(restored.store.records.count == 1 && restored.store.records.first?.tokens.total == 100,
                     "restoring shared Cursor readings in reverse order still counts only the fuller reply")
        try manager.removeItem(at: large.file)
        large.read(at: 8)
        suite.expect(restored.store.records.count == 1 && restored.store.records.first?.tokens.total == 30
                     && restored.store.records.first?.project == "copy",
                     "deleting a shared Cursor source after restore uses the remaining copy's counters and project")
        let one = AgentUsageArchive.resume(checkpoint, logs: [small.file.path], since: .distantPast, cursorRoot: small.root)
        guard let remaining = one.cursors[small.file.path] else {
            return suite.expect(false, "the surviving Cursor transcript keeps its verified turn")
        }
        small.cursor = remaining
        small.store = one.store
        small.read(at: 9)
        suite.expect(one.store.records.first?.tokens.total == 30 &&
                     one.store.turns[small.file.path]?.started == start.addingTimeInterval(2),
                     "resuming after one copy disappears restores both the surviving usage and observed turn start")
    }
}
