// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Comprehensive unit and integration tests for Antigravity transcript
/// discovery, parsing, subagent rollup, read-only SQLite index lookup,
/// version-gated CLI quota polling, archive persistence, and multi-pool UI support.
enum AntigravityAgentTests {
    private final class Log {
        var now = AgentTimestamp.parse("2026-11-24T10:00:00Z")!
        var state = AgentLogState()
        let store: AgentUsageStore
        let path: String

        init(session: String = "11111111-1111-4111-8111-111111111111",
             project: String = "",
             store: AgentUsageStore = AgentUsageStore()) {
            path = "/Users/demo/.gemini/antigravity-cli/brain/\(session)/.system_generated/logs/transcript.jsonl"
            self.store = store
            store.reportsTransitions = true
            AntigravityReader.adopt(path: path, into: &state)
            if !project.isEmpty { state.project = project }
        }

        @discardableResult
        func feed(_ json: String, tracksTurns: Bool? = nil, parent: String? = nil) -> [AgentUsageEvent] {
            let entries = AgentLogParser.parseAntigravity(Data(json.utf8), state: &state, now: now)
            return store.apply(entries, file: path, provider: .antigravity,
                               tracksTurns: tracksTurns ?? !state.antigravitySubagent,
                               parent: parent, modified: now, now: now)
        }
    }

    static func run(_ suite: TestSuite) {
        discovery(suite)
        parsing(suite)
        subagentsAndArchive(suite)
        index(suite)
        quotaServer(suite)
        limitGroupsAndSupport(suite)
    }

    // MARK: Discovery and canonical path boundaries

    private static func discovery(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-agy-discovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Create valid transcripts across all three roots plus rejected decoys.
            let suffixes = [".gemini/antigravity-cli/brain", ".gemini/antigravity/brain", ".gemini/antigravity-ide/brain"]
            let validPaths = try suffixes.enumerated().map { idx, suffix -> URL in
                let transcript = folder.appending(path: "\(suffix)/conv-\(idx)/.system_generated/logs/transcript.jsonl")
                try FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("{}\n".utf8).write(to: transcript)
                return transcript
            }
            let roots = AgentLogRoot.all(home: folder, providers: [.antigravity])
            suite.expect(roots.count == 3 && suffixes.allSatisfy { suffix in roots.contains { $0.url.path.hasSuffix(suffix) } },
                         "Antigravity registers all three canonical brain roots (CLI, app, IDE)")
            let cliBrain = folder.appending(path: ".gemini/antigravity-cli/brain")
            let rejected = [
                cliBrain.appending(path: "conv-0/.system_generated/logs/transcript_full.jsonl"),
                cliBrain.appending(path: "conv-0/.system_generated/logs/chunks/0.jsonl"),
                cliBrain.appending(path: "conv-0/scratch/transcript.jsonl"),
                cliBrain.appending(path: ".hidden/.system_generated/logs/transcript.jsonl"),
                cliBrain.appending(path: "conv-0/transcript.jsonl"),
                cliBrain.appending(path: "conv-0/nested/deep/.system_generated/logs/transcript.jsonl"),
            ]
            for decoy in rejected {
                try FileManager.default.createDirectory(at: decoy.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("{}\n".utf8).write(to: decoy)
            }
            let discovered = AgentLogReader.discover(roots, since: Date().addingTimeInterval(-3600))
            let expected = Set(validPaths.map { AgentLogRoot.canonical($0).path })
            let actual = Set(discovered.map(\.path))
            suite.expect(actual == expected && discovered.allSatisfy { $0.provider == .antigravity },
                         "shallow discovery admits only <session>/.system_generated/logs/transcript.jsonl across all 3 roots")

            let canonicalCLIRoot = AgentLogRoot(provider: .antigravity, url: AgentLogRoot.canonical(cliBrain))
            suite.expect(canonicalCLIRoot.accepts(AgentLogRoot.canonical(validPaths[0]).path)
                            && rejected.allSatisfy { !canonicalCLIRoot.accepts(AgentLogRoot.canonical($0).path) },
                         "accepts enforces the exact 4-part brain-relative transcript path")

            // Symlinked brain root resolves canonically and still discovers transcripts.
            let realBrain = folder.appending(path: "external-brain")
            let linkedTranscript = realBrain.appending(path: "linked-conv/.system_generated/logs/transcript.jsonl")
            try FileManager.default.createDirectory(at: linkedTranscript.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}\n".utf8).write(to: linkedTranscript)
            let symHome = folder.appending(path: "sym-home")
            try FileManager.default.createDirectory(at: symHome.appending(path: ".gemini/antigravity-cli"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: symHome.appending(path: ".gemini/antigravity-cli/brain"),
                                                       withDestinationURL: realBrain)
            let symRoots = AgentLogRoot.all(home: symHome, providers: [.antigravity])
            let symDiscovered = AgentLogReader.discover(symRoots, since: Date().addingTimeInterval(-3600))
            suite.expect(symDiscovered.map(\.path) == [AgentLogRoot.canonical(linkedTranscript).path],
                         "symlinked Antigravity brain directories resolve canonically and discover transcripts")
        } catch {
            suite.expect(false, "Antigravity discovery fixture failed: \(error)")
        }
    }

    // MARK: Transcript parsing, legacy fallback, injection immunity, turn lifecycle

    private static func parsing(_ suite: TestSuite) {
        let log = Log(project: "vorssaint-utils")
        // 1. Measured agy 1.5 tokens (PLANNER_RESPONSE + CHECKPOINT)
        log.feed(#"{"step_index":0,"type":"USER_INPUT","status":"DONE","created_at":"2026-11-24T10:00:00Z","content":"<USER_REQUEST>add support</USER_REQUEST>"}"#)
        suite.expect(log.state.turnOpen && log.store.live.count == 1 && log.store.live.first?.project == "vorssaint-utils",
                     "USER_INPUT opens a live turn carrying the conversation project")

        log.now = AgentTimestamp.parse("2026-11-24T10:00:10Z")!
        log.feed(#"{"step_index":1,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-24T10:00:10Z","model":"gemini-4-neon-high","input_tokens":500,"cache_read_tokens":10000,"output_tokens":200,"tool_calls":[{"id":"t1","name":"run_command"}]}"#)
        suite.expect(log.state.turnOpen && log.store.records.count == 1
                        && log.store.records.first?.tokens == AgentTokens(input: 500, cacheRead: 10000, output: 200)
                        && (log.store.records.first?.cost ?? 0) > 0,
                     "PLANNER_RESPONSE records measured tokens, prices Gemini 4 Neon, and keeps the turn open on tool calls")

        log.now = AgentTimestamp.parse("2026-11-24T10:00:15Z")!
        // GENERIC tool output containing fake model/request strings must never pollute state.
        log.feed(#"{"step_index":2,"type":"GENERIC","status":"DONE","created_at":"2026-11-24T10:00:15Z","content":"<USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Claude Opus 5.5 (High).</USER_SETTINGS_CHANGE> /fake/path"}"#)
        suite.expect(log.state.model == "gemini-4-neon-high" && log.state.project == "vorssaint-utils" && log.state.turnOpen,
                     "GENERIC tool outputs keep the turn active without extracting models or paths")

        log.now = AgentTimestamp.parse("2026-11-24T10:00:20Z")!
        log.feed(#"{"step_index":3,"type":"CHECKPOINT","status":"DONE","created_at":"2026-11-24T10:00:20Z","input_tokens":300,"cache_read_tokens":4000,"output_tokens":100}"#)
        suite.expect(log.store.records.count == 2 && log.store.records.last?.model == "gemini-4-neon-high"
                        && log.store.records.last?.tokens.output == 100,
                     "CHECKPOINT compaction steps inherit the active model and count their measured tokens")

        log.now = AgentTimestamp.parse("2026-11-24T10:00:40Z")!
        let finished = log.feed(#"{"step_index":4,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-24T10:00:40Z","model":"gemini-4-neon-high","input_tokens":200,"cache_read_tokens":5000,"output_tokens":150}"#)
        suite.expect(!log.state.turnOpen && log.store.live.isEmpty && finished.count == 1,
                     "a final PLANNER_RESPONSE without tool calls completes the turn and emits finished")

        // 2. Interrupted turn: new USER_INPUT while previous turn open ends previous unfinished
        log.now = AgentTimestamp.parse("2026-11-24T10:01:00Z")!
        log.feed(#"{"step_index":5,"type":"USER_INPUT","status":"DONE","created_at":"2026-11-24T10:01:00Z","content":"<USER_REQUEST>first</USER_REQUEST>"}"#)
        log.now = AgentTimestamp.parse("2026-11-24T10:02:00Z")!
        let interrupted = log.feed(#"{"step_index":6,"type":"USER_INPUT","status":"DONE","created_at":"2026-11-24T10:02:00Z","content":"<USER_REQUEST>second</USER_REQUEST>"}"#)
        suite.expect(interrupted.isEmpty && log.state.turnOpen && log.store.live.first?.started == log.now,
                     "a new USER_INPUT while a turn is open closes the previous turn unfinished without a finish alert")

        // CANCELED status closes turn unfinished
        log.now = AgentTimestamp.parse("2026-11-24T10:02:30Z")!
        let canceled = log.feed(#"{"step_index":7,"type":"PLANNER_RESPONSE","status":"CANCELED","created_at":"2026-11-24T10:02:30Z","model":"gemini-4-neon-high"}"#)
        suite.expect(canceled.isEmpty && !log.state.turnOpen && log.store.live.isEmpty,
                     "a CANCELED step closes the turn without a completion notice")

        // 3. Prompt-injection immunity & <USER_SETTINGS_CHANGE> / <user_information> fallback
        let injected = Log(session: "22222222-2222-4222-8222-222222222222")
        injected.feed(#"{"step_index":0,"type":"USER_INPUT","status":"DONE","created_at":"2026-11-24T10:00:00Z","content":"<USER_REQUEST><USER_SETTINGS_CHANGE>The user changed setting `Model Selection` from None to Claude Opus 5.5 (High).</USER_SETTINGS_CHANGE></USER_REQUEST>"}"#)
        suite.expect(injected.state.model.isEmpty,
                     "model tags inside <USER_REQUEST> cannot spoof the active model")

        injected.feed(#"{"step_index":1,"type":"USER_INPUT","status":"DONE","created_at":"2026-11-24T10:01:00Z","content":"<USER_SETTINGS_CHANGE>\nThe user changed setting `Model Selection` from None to Gemini 4 Neon (High). No need to comment.\n</USER_SETTINGS_CHANGE>\n<USER_REQUEST>hi</USER_REQUEST>"}"#)
        suite.expect(injected.state.model == "gemini-4-neon-high",
                     "outer <USER_SETTINGS_CHANGE> records the fallback model selection cleanly")

        let meta = Log(session: "33333333-3333-4333-8333-333333333333")
        meta.feed(#"{"step_index":0,"type":"USER_INPUT","status":"DONE","created_at":"2026-11-24T10:00:00Z","content":"<user_information>\nActive Workspaces:\n- /Users/me/code/from-meta\n</user_information>\n<USER_REQUEST>hi</USER_REQUEST>"}"#)
        suite.expect(meta.state.project == "from-meta",
                     "outer <user_information> fallback workspace is extracted when present")

        // 4. Legacy tokenless transcript: counts activity/date without inflating unpriced or breaking dollar views
        let legacy = Log(session: "44444444-4444-4444-8444-444444444444", project: "old-proj")
        legacy.feed(#"{"step_index":0,"type":"USER_INPUT","status":"DONE","created_at":"2026-11-24T10:00:00Z","content":"<USER_REQUEST>old</USER_REQUEST>"}"#)
        legacy.feed(#"{"step_index":1,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-24T10:00:10Z","response":"done"}"#)
        let beforeReprice = legacy.store.snapshot(plans: [:], providers: [.antigravity], now: legacy.now)
        legacy.store.reprice()
        let afterReprice = legacy.store.snapshot(plans: [:], providers: [.antigravity], now: legacy.now)
        let usage = afterReprice.usage(.today)
        suite.expect(usage.total.requests == 1 && usage.total.tokens.total == 0
                        && usage.total.unpriced == 0 && usage.fullyPriced
                        && beforeReprice.usage(.today).total == usage.total,
                     "legacy tokenless Antigravity replies record activity without inventing tokens or inflating unpriced even after reprice")
    }

    // MARK: Subagent rollup and archive round-trip

    private static func subagentsAndArchive(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-agy-subagent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AgentUsageStore()
        let now = AgentTimestamp.parse("2026-11-24T10:05:00Z")!
        let parentID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let childID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let parentURL = folder.appending(path: ".gemini/antigravity-cli/brain/\(parentID)/.system_generated/logs/transcript.jsonl")
        let childURL = folder.appending(path: ".gemini/antigravity-cli/brain/\(childID)/.system_generated/logs/transcript.jsonl")
        let parentLine = #"{"step_index":0,"type":"USER_INPUT","status":"DONE","created_at":"2026-11-24T10:00:00Z","content":"<USER_REQUEST>delegate</USER_REQUEST>"}"#
        let childLines = [
            #"{"step_index":0,"type":"SYSTEM_MESSAGE","status":"DONE","created_at":"2026-11-24T10:01:00Z","content":"<SYSTEM_MESSAGE>\n[Message] timestamp=2026-11-24T10:01:00Z sender=\#(parentID)\n</SYSTEM_MESSAGE>"}"#,
            #"{"step_index":1,"type":"USER_INPUT","status":"DONE","created_at":"2026-11-24T10:01:01Z","content":"<USER_REQUEST>research</USER_REQUEST>"}"#,
            #"{"step_index":2,"type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-24T10:01:20Z","model":"gemini-4-neon-high","input_tokens":100,"output_tokens":50}"#
        ]
        do {
            try FileManager.default.createDirectory(at: parentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: childURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((parentLine + "\n").utf8).write(to: parentURL)
            try Data((childLines.joined(separator: "\n") + "\n").utf8).write(to: childURL)
        } catch {
            suite.expect(false, "Antigravity subagent fixture failed: \(error)")
            return
        }
        let parentPath = parentURL.path
        let childPath = childURL.path

        let parentCursor = AgentLogCursor(path: parentPath, provider: .antigravity)
        let childCursor = AgentLogCursor(path: childPath, provider: .antigravity)
        var cursors = [parentPath: parentCursor, childPath: childCursor]

        AgentLogReader.readAppended(parentCursor) { line in
            let entries = AgentLogParser.parseAntigravity(line, state: &parentCursor.state, now: now)
            store.apply(entries, file: parentPath, provider: .antigravity, tracksTurns: parentCursor.tracksTurns,
                        modified: parentCursor.modified, now: now)
        }
        AgentLogReader.readAppended(childCursor) { line in
            let entries = AgentLogParser.parseAntigravity(line, state: &childCursor.state, now: now)
            let parent = childCursor.antigravityParent(among: cursors)
            store.apply(entries, file: childPath, provider: .antigravity, tracksTurns: childCursor.tracksTurns,
                        parent: parent, modified: childCursor.modified, now: now)
        }
        suite.expect(childCursor.state.antigravitySubagent && childCursor.state.antigravityParent == parentID
                        && !childCursor.tracksTurns && childCursor.antigravityParent(among: cursors) == parentPath,
                     "step-0 SYSTEM_MESSAGE sender= identifies an Antigravity subagent and resolves its parent transcript")
        suite.expect(store.live.count == 1 && store.live.first?.id == parentPath
                        && store.live.first?.tokens.total == 150,
                     "subagent token usage rolls up into the parent live turn without spawning a second live card")

        // Archive persistence round-trip for antigravitySubagent & antigravityParent.
        let contents = AgentUsageArchive.Contents(providers: [.antigravity], store: store.saved,
                                                  cursors: [parentCursor.saved, childCursor.saved])
        let encoded = AgentUsageArchive.encode(contents, build: "agy-archive-test")
        let decoded = AgentUsageArchive.decode(encoded, build: "agy-archive-test")
        let restoredChild = decoded?.cursors.first { $0.path == childPath }.flatMap { AgentLogCursor(saved: $0) }
        suite.expect(decoded == contents
                        && restoredChild?.state.antigravitySubagent == true
                        && restoredChild?.state.antigravityParent == parentID
                        && restoredChild?.tracksTurns == false,
                     "archive format 8 preserves Antigravity subagent flag and parent UUID across launches")
        _ = cursors.removeValue(forKey: childPath)
    }

    // MARK: Read-only SQLite index

    private static func index(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-agy-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            let dataDir = folder.appending(path: ".gemini/antigravity-cli")
            let brainDir = dataDir.appending(path: "brain")
            try FileManager.default.createDirectory(at: brainDir, withIntermediateDirectories: true)
            let dbPath = dataDir.appending(path: "conversation_summaries.db").path

            func writeDB(_ sql: String) -> Bool {
                var db: OpaquePointer?
                guard sqlite3_open(dbPath, &db) == SQLITE_OK, let db else { return false }
                defer { sqlite3_close(db) }
                return sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
            }
            let created = writeDB("""
                CREATE TABLE conversation_summaries (
                    conversation_id TEXT PRIMARY KEY,
                    title TEXT,
                    preview TEXT,
                    workspace_uris TEXT,
                    parent_conversation_id TEXT
                );
                CREATE TABLE conversation_parents (
                    conversation_id TEXT PRIMARY KEY,
                    parent_id TEXT NOT NULL
                ) WITHOUT ROWID;
                INSERT INTO conversation_summaries VALUES
                    ('conv-main', 'secret title', 'secret preview', '["file:///tmp/scratch","file:///Users/me/code/my-app"]', ''),
                    ('conv-child', 'secret child', 'secret preview', '["file:///Users/me/code/my-app"]', 'conv-main'),
                    ('conv-rel', 'secret rel', 'secret preview', '["file:///Users/me/code/other%20proj"]', '');
                INSERT INTO conversation_parents VALUES ('conv-rel', 'conv-main');
                """)
            suite.expect(created, "index test creates a realistic conversation_summaries.db fixture")

            let index = AgentAntigravityIndex()
            let mainTranscript = brainDir.appending(path: "conv-main/.system_generated/logs/transcript.jsonl").path
            let childTranscript = brainDir.appending(path: "conv-child/.system_generated/logs/transcript.jsonl").path
            let relTranscript = brainDir.appending(path: "conv-rel/.system_generated/logs/transcript.jsonl").path

            let mainMeta = index.entry(forSession: "conv-main", transcriptPath: mainTranscript)
            let childMeta = index.entry(forSession: "conv-child", transcriptPath: childTranscript)
            let relMeta = index.entry(forSession: "conv-rel", transcriptPath: relTranscript)
            suite.expect(mainMeta?.project == "my-app" && mainMeta?.parentSession == ""
                            && childMeta?.project == "my-app" && childMeta?.parentSession == "conv-main"
                            && relMeta?.project == "other proj" && relMeta?.parentSession == "conv-main",
                         "read-only SQLite index extracts folder basenames, prefers non-tmp workspaces and resolves parent IDs from both tables")

            // Update DB and bump mtime to verify cache refresh.
            _ = writeDB("INSERT INTO conversation_summaries VALUES ('conv-new', 'x', 'y', '[\"file:///Users/me/code/fresh\"]', '');")
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: dbPath)
            let freshTranscript = brainDir.appending(path: "conv-new/.system_generated/logs/transcript.jsonl").path
            suite.expect(index.entry(forSession: "conv-new", transcriptPath: freshTranscript)?.project == "fresh",
                         "updating conversation_summaries.db invalidates the index cache and surfaces new conversations")

            // Corrupt DB fails closed without crashing.
            let corruptDir = folder.appending(path: ".gemini/antigravity")
            try FileManager.default.createDirectory(at: corruptDir.appending(path: "brain"), withIntermediateDirectories: true)
            try Data("not a sqlite db".utf8).write(to: corruptDir.appending(path: "conversation_summaries.db"))
            let corruptTranscript = corruptDir.appending(path: "brain/c/.system_generated/logs/transcript.jsonl").path
            suite.expect(index.entry(forSession: "c", transcriptPath: corruptTranscript) == nil,
                         "corrupt or missing conversation_summaries.db fails closed cleanly")
        } catch {
            suite.expect(false, "Antigravity index fixture failed: \(error)")
        }
    }

    // MARK: Version-gated CLI quota polling

    private static func quotaServer(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-11-24T12:00:00Z")!
        suite.expect(AgentAntigravityServer.parseVersion("agy 1.5.16 (build 123)")
                            == AgentAntigravityServer.Version(major: 1, minor: 5, patch: 16)
                        && AgentAntigravityServer.parseVersion("1.1.11")
                            == AgentAntigravityServer.Version(major: 1, minor: 1, patch: 11)
                        && AgentAntigravityServer.supportsUsage(versionOutput: "agy 1.1.11")
                        && AgentAntigravityServer.supportsUsage(versionOutput: "agy 1.5.16")
                        && AgentAntigravityServer.supportsUsage(versionOutput: "2.0.0")
                        && !AgentAntigravityServer.supportsUsage(versionOutput: "agy 1.1.10")
                        && !AgentAntigravityServer.supportsUsage(versionOutput: "agy 1.0.99"),
                     "version parsing and the >= 1.1.11 floor classify agy releases accurately")

        let samplePayload = """
        {
          "status": "SUCCESS",
          "command": {
            "name": "usage",
            "data": {
              "groups": [
                {
                  "name": "Gemini Models",
                  "buckets": [
                    {"id": "gemini-weekly", "name": "Weekly Limit Remaining", "window": "weekly", "remaining_fraction": 0.72, "reset_time": "2026-12-01T00:00:00Z"},
                    {"id": "gemini-5h", "name": "Five Hour Limit Remaining", "window": "5h", "remaining_fraction": 0.85, "reset_time": "2026-11-24T17:00:00Z"}
                  ]
                },
                {
                  "name": "Claude and GPT models",
                  "buckets": [
                    {"id": "3p-weekly", "name": "Weekly Limit Remaining", "window": "weekly", "remaining_fraction": 0.40, "reset_time": "2026-12-01T00:00:00Z"},
                    {"id": "3p-5h", "name": "Five Hour Limit Remaining", "window": "5h", "remaining_fraction": 0.15, "reset_time": "2026-11-24T15:30:00Z"}
                  ]
                }
              ]
            }
          }
        }
        """
        let limits = try? AgentAntigravityServer.limits(Data(samplePayload.utf8), observed: now).get()
        suite.expect(limits?.provider == .antigravity && limits?.source == .account
                        && limits?.windows.count == 4
                        && limits?.windows.map(\.scope) == ["Gemini", "Gemini", "Claude/GPT", "Claude/GPT"]
                        && limits?.windows.map(\.kind) == [.weekly, .session, .weekly, .session],
                     "Antigravity /usage JSON maps both Gemini and Claude/GPT pools cleanly")
        if let windows = limits?.windows, windows.count == 4 {
            suite.expectClose(windows[0].usedPercent, 28, "Gemini weekly used percent", tol: 0.001)
            suite.expectClose(windows[1].usedPercent, 15, "Gemini 5h used percent", tol: 0.001)
            suite.expectClose(windows[2].usedPercent, 60, "Claude/GPT weekly used percent", tol: 0.001)
            suite.expectClose(windows[3].usedPercent, 85, "Claude/GPT 5h used percent", tol: 0.001)
        }

        // Expired buckets drop independently via current(_:now:).
        let afterFiveHours = AgentTimestamp.parse("2026-11-24T18:00:00Z")!
        let remaining = AgentAntigravityServer.current(limits, now: afterFiveHours)
        suite.expect(remaining?.windows.map(\.kind) == [.weekly, .weekly]
                        && AgentAntigravityServer.current(limits, now: AgentTimestamp.parse("2026-12-02T00:00:00Z")!) == nil,
                     "expired Antigravity buckets drop independently without inventing zero usage")

        // Booleans and invalid JSON never produce fabricated limits.
        let bogus = #"{"command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"g","window":"5h","remaining_fraction":true}]}]}}}"#
        suite.expect(AgentAntigravityServer.limits(Data(bogus.utf8), observed: now) == .failure(.unreachable)
                        && AgentAntigravityServer.limits(Data("not json".utf8), observed: now) == .failure(.unreachable),
                     "malformed or boolean remaining_fraction payloads are rejected")

        suite.expect(AgentAntigravityServer.interval(after: nil, pageVisible: true) == 60
                        && AgentAntigravityServer.interval(after: nil, pageVisible: false) == 300
                        && [0, 1, 2, 3, 4, 9].map { AgentAntigravityServer.interval(after: .unreachable, repeated: $0, pageVisible: true) }
                            == [300, 300, 600, 1_200, 1_800, 1_800]
                        && [AgentAntigravityServer.Failure.missing, .needsSignIn, .outdated].allSatisfy {
                            AgentAntigravityServer.interval(after: $0, pageVisible: true) == 1_800 },
                     "Antigravity polling cadence and unreachable exponential backoff match Claude Code")

        // All 15 languages supply distinct localized messages for every Antigravity failure.
        let failures: [AgentAntigravityServer.Failure] = [.missing, .needsSignIn, .outdated, .unreachable]
        suite.expect(AppLanguage.allCases.allSatisfy { language in
            let messages = failures.map { FeatureStrings.notchAgents(language).antigravityCLI($0) }
            return Set(messages).count == failures.count && messages.allSatisfy { !$0.isEmpty }
        }, "Settings explains every Antigravity CLI failure in all 15 languages")

        // Real executable stand-in verifying version gate, /usage, auth error, outdated, timeout and cancellation.
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-agy-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let script = """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              if [ "$STAND_IN" = "old" ]; then echo "agy 1.1.10"; else echo "agy 1.5.16"; fi
              exit 0
            fi
            [ "$1" = "--output-format" ] && [ "$2" = "json" ] && [ "$3" = "--print" ] && [ "$4" = "/usage" ] || exit 2
            case "$STAND_IN" in
              ok) printf '%s\\n' '{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-5h","window":"5h","remaining_fraction":0.8,"reset_time":"2099-01-01T05:00:00Z"},{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.9,"reset_time":"2099-01-07T00:00:00Z"}]},{"name":"Claude and GPT models","buckets":[{"id":"3p-5h","window":"5h","remaining_fraction":0.3,"reset_time":"2099-01-01T05:00:00Z"},{"id":"3p-weekly","window":"weekly","remaining_fraction":0.5,"reset_time":"2099-01-07T00:00:00Z"}]}]}}}' ;;
              signedOut) echo "Not authenticated: please run agy login" >&2; exit 1 ;;
              unavailable) echo "temporary upstream error" >&2; exit 1 ;;
              silent) sleep 5 ;;
              *) exit 1 ;;
            esac
            """
            func makeTool(_ name: String) throws -> URL {
                let url = folder.appending(path: name)
                try Data(script.utf8).write(to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                return url
            }
            let okTool = try makeTool("agy-ok")
            let oldTool = try makeTool("agy-old")
            let okRes = AgentAntigravityServer.Request().run(
                okTool, home: folder, environment: ["PATH": "/usr/bin:/bin", "HOME": folder.path, "STAND_IN": "ok"], timeout: 3)
            let oldRes = AgentAntigravityServer.Request().run(
                oldTool, home: folder, environment: ["PATH": "/usr/bin:/bin", "HOME": folder.path, "STAND_IN": "old"], timeout: 3)
            let signedOut = AgentAntigravityServer.Request().run(
                okTool, home: folder, environment: ["PATH": "/usr/bin:/bin", "HOME": folder.path, "STAND_IN": "signedOut"], timeout: 3)
            let unavail = AgentAntigravityServer.Request().run(
                okTool, home: folder, environment: ["PATH": "/usr/bin:/bin", "HOME": folder.path, "STAND_IN": "unavailable"], timeout: 3)
            let timedOut = AgentAntigravityServer.Request().run(
                okTool, home: folder, environment: ["PATH": "/usr/bin:/bin", "HOME": folder.path, "STAND_IN": "silent"], timeout: 0.2)
            suite.expect((try? okRes.get())?.windows.count == 4
                            && oldRes == .failure(.outdated)
                            && signedOut == .failure(.needsSignIn)
                            && unavail == .failure(.unreachable)
                            && timedOut == .failure(.unreachable),
                         "agy CLI stand-in verifies version gate, structured JSON /usage, auth classification and bounded timeouts")
        } catch {
            suite.expect(false, "Antigravity CLI stand-in fixture failed: \(error)")
        }
    }

    // MARK: Multi-pool UI support

    private static func limitGroupsAndSupport(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-11-24T12:00:00Z")!
        let agyLimits = AgentLimits(provider: .antigravity, windows: [
            AgentLimitWindow(id: "agy.gemini-5h", kind: .session, minutes: 300, scope: "Gemini",
                             usedPercent: 18, resetsAt: now.addingTimeInterval(3600)),
            AgentLimitWindow(id: "agy.gemini-weekly", kind: .weekly, minutes: 10_080, scope: "Gemini",
                             usedPercent: 30, resetsAt: now.addingTimeInterval(86_400)),
            AgentLimitWindow(id: "agy.3p-5h", kind: .session, minutes: 300, scope: "Claude/GPT",
                             usedPercent: 88, resetsAt: now.addingTimeInterval(3600)),
            AgentLimitWindow(id: "agy.3p-weekly", kind: .weekly, minutes: 10_080, scope: "Claude/GPT",
                             usedPercent: 52, resetsAt: now.addingTimeInterval(86_400)),
        ], observedAt: now, source: .account)

        let groups = NotchAgentSupport.limitGroups(in: agyLimits, now: now)
        suite.expect(groups.map(\.id) == ["Gemini", "Claude/GPT"]
                        && groups[0].windows.map(\.kind) == [.session, .weekly]
                        && groups[1].windows.map(\.kind) == [.session, .weekly]
                        && NotchAgentSupport.defaultLimitGroup(in: groups)?.id == "Claude/GPT"
                        && NotchAgentSupport.defaultLimitGroup(in: groups, activeModel: "gemini-4-neon-high")?.id == "Gemini"
                        && NotchAgentSupport.defaultLimitGroup(in: groups, activeModel: "claude-opus-5-5")?.id == "Claude/GPT",
                     "Antigravity's scoped buckets partition into ordered pools, prefer the active live model's pool, and fall back to the most constrained pool")

        // Claude mixes unscoped and model-scoped windows -> must NOT trigger pool switcher
        // and weekly focus must still never pick Claude's model-scoped window.
        let claudeLimits = AgentLimits(provider: .claude, windows: [
            AgentLimitWindow(id: "claude.fh", kind: .session, minutes: 300, scope: nil,
                             usedPercent: 25, resetsAt: now.addingTimeInterval(3600)),
            AgentLimitWindow(id: "claude.so", kind: .weekly, minutes: 10_080, scope: "Opus",
                             usedPercent: 90, resetsAt: now.addingTimeInterval(86_400)),
        ], observedAt: now, source: .account)
        suite.expect(NotchAgentSupport.limitGroups(in: claudeLimits, now: now).isEmpty
                        && NotchAgentSupport.focusedLimit(claudeLimits, focus: .weekly, now: now)?.id == "claude.so"
                        && NotchAgentSupport.focusedLimit(claudeLimits, focus: .session, now: now)?.id == "claude.fh",
                     "Claude keeps its single-card layout and unscoped focus semantics")

        // Scoped-only Antigravity pools pick the most constrained session or weekly pool for strip/resting focus.
        suite.expect(NotchAgentSupport.focusedLimit(agyLimits, focus: .session, now: now)?.id == "agy.3p-5h"
                        && NotchAgentSupport.focusedLimit(agyLimits, focus: .weekly, now: now)?.id == "agy.3p-weekly",
                     "focusedLimit selects the most constrained Antigravity pool matching the chosen window kind")

        // Staleness triggers at accountStaleness (10 minutes) for Antigravity.
        suite.expect(!NotchAgentSupport.limitsAreStale(agyLimits, provider: .antigravity, account: false,
                                                       now: now.addingTimeInterval(9 * 60))
                        && NotchAgentSupport.limitsAreStale(agyLimits, provider: .antigravity, account: false,
                                                            now: now.addingTimeInterval(10 * 60)),
                     "Antigravity limits dim as stale after missing two 5-minute refresh intervals")

        // Settings strip preview sample populates realistic limits for Antigravity.
        let sample = NotchAgentSupport.stripSampleSnapshot(AgentUsageSnapshot(), provider: .antigravity,
                                                           focus: .mostUsed, now: now)
        suite.expect(sample.live.first?.provider == .antigravity && sample.limits[.antigravity] != nil,
                     "stripSampleSnapshot builds a live Antigravity preview with sample limits")
    }
}
