// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Every provider resolves to the reader for its own harness, and each reader
/// parses its harness's lines into the entries the island keeps.
enum HarnessReaderContractTests {
    static func run(_ suite: TestSuite) {
        readersCoverProviders(suite)
        claudeGolden(suite)
        codexGolden(suite)
        openCodeGolden(suite)
        copilotGolden(suite)
        deepSeekGolden(suite)
        deepSeekCache(suite)
        cursorGolden(suite)
        cursorStore(suite)
        cursorDiscovery(suite)
    }

    private static func line(_ json: String) -> Data { Data(json.utf8) }

    private static func readersCoverProviders(_ suite: TestSuite) {
        for provider in AgentProvider.allCases {
            let reader = provider.reader
            suite.expect(reader.provider == provider,
                         "\(provider.rawValue) resolves to its own harness reader")
            suite.expect(reader.readsFullHistoryFirst == (provider == .copilot),
                         "only the Copilot reader rereads history on its first pass")
        }
    }

    private static func claudeGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.claude.reader
        let began = Date(timeIntervalSince1970: 1_790_088_000)
        let prompt = line(#"{"type":"user","timestamp":1790088000,"sessionId":"s","cwd":"/Users/me/code/app","message":{"content":"work"}}"#)
        suite.expect(reader.parse(prompt, state: &state, now: now) == [.turnBegan(began)],
                     "a Claude prompt opens its turn")
        let interrupted = line(#"{"type":"user","timestamp":1790088010,"sessionId":"s","message":{"content":"[Request interrupted by user for now"}}"#)
        suite.expect(reader.parse(interrupted, state: &state, now: now)
                        == [.turnEnded(nil, completed: false, duration: nil)],
                     "an interrupted Claude prompt ends its turn unfinished")
        let sidechain = line(#"{"type":"user","timestamp":1790088020,"sessionId":"s","isSidechain":true,"message":{"content":"work"}}"#)
        suite.expect(reader.parse(sidechain, state: &state, now: now).isEmpty,
                     "a Claude subagent prompt never opens a turn")
        let clear = line(#"{"type":"user","timestamp":1790088030,"sessionId":"s2","cwd":"/Users/me/code/app","message":{"content":"<command-name>/clear</command-name>\n    <command-message>clear</command-message>\n    <command-args></command-args>"}}"#)
        suite.expect(reader.parse(clear, state: &state, now: now).isEmpty && !state.turnOpen
                        && state.session == "s2" && state.project == "app",
                     "/clear adopts the session and project without opening a turn")
        for alias in ["reset", "new"] {
            let reset = line(#"{"type":"user","message":{"content":[{"type":"text","text":"<command-message>clear</command-message>\n <command-name>/\#(alias)</command-name>\n <command-args>previous session</command-args>"}]}}"#)
            suite.expect(reader.parse(reset, state: &state, now: now).isEmpty && !state.turnOpen,
                         "the /\(alias) alias also resets the context without work")
        }
        let cleared = line(#"{"type":"system","subtype":"local_command","timestamp":1790088031,"sessionId":"s2","content":"<local-command-stdout></local-command-stdout>"}"#)
        suite.expect(reader.parse(cleared, state: &state, now: now).isEmpty,
                     "a Claude local command's output parses to nothing")
        // Claude Code writes that output on a line whose outer type varies.
        let clearedUser = line(#"{"type":"user","timestamp":1790088032,"sessionId":"s2","message":{"content":"<local-command-stdout></local-command-stdout>"}}"#)
        suite.expect(reader.parse(clearedUser, state: &state, now: now).isEmpty && !state.turnOpen,
                     "a Claude local command's output never opens a turn")
        let clearedReply = line(#"{"type":"assistant","timestamp":1790088033,"sessionId":"s2","message":{"role":"assistant","content":[{"type":"text","text":"<local-command-stdout>Context cleared</local-command-stdout>"}]}}"#)
        suite.expect(reader.parse(clearedReply, state: &state, now: now).isEmpty && !state.turnOpen,
                     "a Claude local command's output written as a reply opens no turn")
        let next = line(#"{"type":"user","timestamp":1790088040,"sessionId":"s2","cwd":"/Users/me/code/app","message":{"content":"<command-name>/clear</command-name>\nExplain this log entry."}}"#)
        suite.expect(reader.parse(next, state: &state, now: now)
                        == [.turnBegan(Date(timeIntervalSince1970: 1_790_088_040))],
                     "a prompt asking about the command still opens its own turn")
        let quoted = line(#"{"type":"assistant","timestamp":1790088041,"message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"<local-command-stderr>example</local-command-stderr>"}],"stop_reason":null}}"#)
        suite.expect(reader.parse(quoted, state: &state, now: now) == [.turnActive(Date(timeIntervalSince1970: 1_790_088_041))],
                     "a model reply quoting local output still reports activity")
        var idle = AgentLogState()
        let question = line(#"{"type":"user","timestamp":1790088040,"message":{"content":"<local-command-stdout>ready</local-command-stdout>\nWhat does this mean?"}}"#)
        suite.expect(reader.parse(question, state: &idle, now: now) == [.turnBegan(Date(timeIntervalSince1970: 1_790_088_040))],
                     "a question quoting local output opens its own turn")
        let childOutput = line(#"{"type":"user","isSidechain":true,"message":{"content":"<local-command-stdout>Set model</local-command-stdout>"}}"#)
        suite.expect(reader.parse(childOutput, state: &state, now: now).isEmpty && state.turnOpen,
                     "a child command cannot end the parent turn")
        let unfinished = line(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","id":"interrupted-tool"}],"stop_reason":"tool_use"}}"#)
        _ = reader.parse(unfinished, state: &state, now: now)
        suite.expect(state.runningCommands.contains("interrupted-tool")
                     && reader.parse(clear, state: &state, now: now) == [.turnEnded(nil, completed: false, duration: nil)]
                     && !state.turnOpen && state.runningCommands.isEmpty,
                     "clearing a resumed session drops its unfinished turn and command without a finish notice")
    }

    private static func codexGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.codex.reader
        let meta = line(#"{"type":"session_meta","timestamp":1790088000,"payload":{"id":"s","cwd":"/tmp/example"}}"#)
        suite.expect(reader.parse(meta, state: &state, now: now).isEmpty
                        && state.session == "s" && state.project == "example",
                     "Codex session metadata names the session and project")
        let started = line(#"{"type":"event_msg","timestamp":1790088000,"payload":{"type":"task_started"}}"#)
        suite.expect(reader.parse(started, state: &state, now: now)
                        == [.turnBegan(Date(timeIntervalSince1970: 1_790_088_000))],
                     "a Codex task start opens its turn")
        let bogus = line(#"{"type":"bogus","timestamp":1790088000,"payload":{}}"#)
        suite.expect(reader.parse(bogus, state: &state, now: now).isEmpty,
                     "an unknown Codex line parses to nothing")
    }

    private static func openCodeGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.opencode.reader
        let user = line(#"{"session_id":"s_oc_1","time_created":1790088000,"directory":"/Users/me/code/backend","role":"user","parts":[{"type":"text","text":"go"}]}"#)
        suite.expect(reader.parse(user, state: &state, now: now)
                        == [.turnBegan(Date(timeIntervalSince1970: 1_790_088_000))],
                     "an OpenCode prompt opens its session turn")
        let stop = line(#"{"id":"msg_2","session_id":"s_oc_1","time_created":1790088020,"directory":"/Users/me/code/backend","role":"assistant","model_id":"stealth/ox-alpha","provider_id":"relay","cost":0.0015,"tokens":{"total":500,"input":400,"output":100,"reasoning":0,"cache":{"read":0,"write":0}},"finish":"stop"}"#)
        let stopped = reader.parse(stop, state: &state, now: now)
        suite.expect(stopped.last == .turnEnded(Date(timeIntervalSince1970: 1_790_088_020),
                                                completed: true, duration: 20),
                     "a finished OpenCode reply ends its turn with its duration")
        let reset = line(#"{"type":"reset"}"#)
        suite.expect(reader.parse(reset, state: &state, now: now) == [.reset(now)],
                     "an OpenCode reset restarts every session")
    }

    private static func copilotGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.copilot.reader
        let start = line(#"{"id":"start","timestamp":1790088000,"type":"session.start","data":{"sessionId":"s","selectedModel":"gpt-6-sol","context":{"cwd":"/tmp/example"}}}"#)
        suite.expect(reader.parse(start, state: &state, now: now).isEmpty
                        && state.session == "s" && state.model == "gpt-6-sol" && state.project == "example",
                     "a Copilot session start names the session, model and project")
        let prompt = line(#"{"id":"turn","timestamp":1790088000,"type":"user.message","data":{"turnId":"0","content":"private"}}"#)
        suite.expect(reader.parse(prompt, state: &state, now: now)
                        == [.turnBegan(Date(timeIntervalSince1970: 1_790_088_000)),
                            .turnContext(model: "gpt-6-sol", project: "example")],
                     "a Copilot prompt opens its turn with its context")
        let reply = line(#"{"id":"message","timestamp":1790088000,"type":"assistant.message","data":{"model":"gpt-6-sol","content":"private"}}"#)
        suite.expect(reader.parse(reply, state: &state, now: now).count == 3,
                     "a Copilot reply counts its request and keeps the turn active")
        let end = line(#"{"id":"end","timestamp":1790088020,"type":"assistant.turn_end","data":{"turnId":"0"}}"#)
        suite.expect(reader.parse(end, state: &state, now: now)
                        == [.turnEnded(Date(timeIntervalSince1970: 1_790_088_020),
                                       completed: true, duration: nil)],
                     "a Copilot turn end finishes its turn")
        let checkpoint = line(#"{"id":"c","timestamp":1790088020,"type":"session.usage_checkpoint","data":{}}"#)
        suite.expect(reader.parse(checkpoint, state: &state, now: now).isEmpty,
                     "a Copilot usage checkpoint parses to nothing")
    }

    private static func cursorGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.cursor.reader
        let payload = line(#"{"session":"agent-1","run":"run-1","createdAt":1790088000,"project":"/Users/me/code/app","model":"grok-4.7","input":1000,"cacheWrite":0,"cacheRead":100000,"output":2000,"reasoning":500}"#)
        let entries = reader.parse(payload, state: &state, now: now)
        guard case .usage(let key, let record, let billable)? = entries.first(where: {
            if case .usage = $0 { return true }
            return false
        }) else {
            suite.expect(false, "a Cursor run yields its usage")
            return
        }
        suite.expect(key == "cursor:run-1" && record.provider == .cursor
                        && record.model == "grok-4.7" && record.project == "app"
                        && record.tokens == AgentTokens(input: 1000, cacheRead: 100_000, output: 2000, reasoning: 500)
                        && record.requests == 1 && record.date == Date(timeIntervalSince1970: 1_790_088_000),
                     "a Cursor run's counters, model, project and start are read")
        suite.expectClose(record.cost ?? -1, 0.064, "a Cursor run on Grok is priced at xAI's API rates")
        suite.expect(billable.isAggregate && billable.tokens == record.tokens,
                     "a Cursor run's totals are aggregate, not one request's prompt")
        let large = line(#"{"session":"agent-1","run":"run-2","createdAt":1790088000,"project":"/Users/me/code/app","model":"grok-4.7","input":200000,"cacheWrite":0,"cacheRead":100000,"output":10000}"#)
        guard case .usage(_, let largeRecord, let largeBillable)? = reader.parse(large, state: &state, now: now).first else {
            suite.expect(false, "a large Cursor run yields its usage")
            return
        }
        suite.expect(largeBillable.isAggregate && largeRecord.tokens.total == 310_000,
                     "a large Cursor run is still one aggregate billable")
        suite.expectClose(largeRecord.cost ?? -1, 0.51,
                          "a Cursor run's aggregate prompt does not trigger the long-context tier")
    }

    private static func cursorStore(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "cursor-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { suite.expect(false, "the Cursor store fixture creates: \(error)"); return }
        let dbPath = folder.appending(path: "index.db").path
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK, let db else {
            suite.expect(false, "the Cursor store fixture opens")
            return
        }
        let schema = #"""
        CREATE TABLE agents (agent_id TEXT PRIMARY KEY, workspace_ref TEXT NOT NULL);
        CREATE TABLE runs (run_id TEXT PRIMARY KEY, agent_id TEXT NOT NULL, turn_number INTEGER NOT NULL,
            status TEXT NOT NULL, model TEXT, usage_json TEXT, created_at TEXT NOT NULL, started_at TEXT);
        INSERT INTO agents VALUES ('agent-1', '/Users/me/code/app');
        INSERT INTO runs VALUES ('run-1', 'agent-1', 1, 'FINISHED', 'grok-4.7',
            '{"inputTokens":1000,"outputTokens":2000,"cacheReadTokens":100000,"cacheWriteTokens":0}',
            '2026-09-21T23:40:00.000Z', '2026-09-21T23:40:00.000Z');
        INSERT INTO runs VALUES ('run-2', 'agent-1', 2, 'ERROR', 'composer-2.5', NULL,
            '2026-09-21T23:41:00.000Z', '2026-09-21T23:41:00.000Z');
        """#
        let created = sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK
        sqlite3_close(db)
        guard created else {
            suite.expect(false, "the Cursor store fixture writes its rows")
            return
        }
        let cursor = AgentLogCursor(path: dbPath, provider: .cursor)
        let now = Date(timeIntervalSince1970: 0)
        var entries: [AgentLogEntry] = []
        AgentCursorReader.readAppended(cursor, since: .distantPast, line: { data in
            entries += AgentProvider.cursor.reader.parse(data, state: &cursor.state, now: now)
        })
        guard case .usage(let key, let record, _)? = entries.first else {
            suite.expect(false, "a Cursor store yields its finished run")
            return
        }
        suite.expect(entries.count == 1 && key == "cursor:run-1" && record.provider == .cursor
                        && record.model == "grok-4.7" && record.project == "app"
                        && record.tokens == AgentTokens(input: 1000, cacheRead: 100_000, output: 2000)
                        && record.requests == 1 && record.date == Date(timeIntervalSince1970: 1_790_034_000),
                     "a Cursor store's finished run is read and its unused run is left out")
        suite.expectClose(record.cost ?? -1, 0.064, "a Cursor store run is priced at xAI's API rates")
    }

    private static func cursorDiscovery(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "cursor-home-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let db = home.appending(path: ".cursor/projects/Example/sdk-agent-store/store/index.db")
        let wal = URL(fileURLWithPath: db.path + "-wal")
        do {
            try FileManager.default.createDirectory(at: db.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: db)
            try Data().write(to: wal)
        } catch {
            suite.expect(false, "the Cursor discovery fixture writes: \(error)")
            return
        }
        guard let root = AgentLogRoot.all(home: home).first(where: { $0.provider == .cursor }) else {
            suite.expect(false, "the Cursor fixture has a root")
            return
        }
        let canonical = AgentLogRoot.canonical(db).path
        let found = AgentLogReader.discover([root], since: .distantPast)
        suite.expect(found.map(\.path) == [canonical]
                        && AgentLogReader.isLog(canonical) && root.accepts(canonical)
                        && AgentLogReader.isLog(canonical + "-wal") && root.accepts(canonical + "-wal"),
                     "a Cursor agent store is discovered by its nested index and admits its WAL")
        let old = Date().addingTimeInterval(-100 * 86_400)
        do {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: canonical)
        } catch {
            suite.expect(false, "the Cursor discovery fixture ages the base index: \(error)")
            return
        }
        let recent = AgentLogReader.discover([root], since: Date().addingTimeInterval(-91 * 86_400))
        suite.expect(recent.map(\.path) == [canonical],
                     "a fresh Cursor WAL brings an old store back into discovery")
    }
    private static func deepSeekGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.deepseek.reader
        let payload = line(#"{"session":"session-1","createdAt":1790088000,"project":"/Users/me/code/app","model":"deepseek-v4.1-flash","input":1000,"cacheWrite":0,"cacheRead":100000,"output":2000,"steps":3}"#)
        let entries = reader.parse(payload, state: &state, now: now)
        guard case .usage(let key, let record, let billable)? = entries.first(where: {
            if case .usage = $0 { return true }
            return false
        }) else {
            suite.expect(false, "a DeepSeek session cache yields its usage")
            return
        }
        suite.expect(key == "deepseek:session-1" && record.provider == .deepseek
                        && record.model == "deepseek-v4.1-flash" && record.project == "app"
                        && record.tokens == AgentTokens(input: 1000, cacheRead: 100_000, output: 2000)
                        && record.requests == 3 && record.date == Date(timeIntervalSince1970: 1_790_088_000),
                     "a DeepSeek session's totals, model, project and start are read")
        suite.expectClose(record.cost ?? -1, 0.0033, "a DeepSeek session is priced from its model's API rates")
        suite.expect(billable.isAggregate && billable.tokens == record.tokens,
                     "a session's totals never imply a long-context request")
    }

    private static func deepSeekCache(_ suite: TestSuite) {
        let modified = Date(timeIntervalSince1970: 1_790_088_000)
        // The real projection is pretty-printed, one field per line.
        let cache = Data("""
        {
          "version": 7,
          "record": {
            "identity": {
              "createdAt": 1790088000000,
              "cwd": "/Users/me/code/app"
            },
            "rows": {
              "tokenUsage": {
                "val": {
                  "totals": {
                    "uncachedInputTokens": 1000,
                    "outputTokens": 2000,
                    "cacheReadTokens": 100000,
                    "cacheWriteTokens": 0
                  }
                }
              },
              "modelSelection": {
                "val": {
                  "lastUsed": { "provider": "opencode-go", "model": "deepseek-v4.1-flash" }
                }
              },
              "sessionStats": { "val": { "steps": 3 } }
            }
          }
        }
        """.utf8)
        guard let payload = AgentDeepSeekReader.payload(cache, session: "session-1", modified: modified,
                                                        since: modified.addingTimeInterval(-1)) else {
            suite.expect(false, "a DeepSeek session projection yields counters")
            return
        }
        var state = AgentLogState()
        let entries = AgentProvider.deepseek.reader.parse(payload, state: &state, now: modified)
        guard case .usage(_, let record, _)? = entries.first else {
            suite.expect(false, "the projection line parses as usage")
            return
        }
        suite.expect(record.session == "session-1" && record.model == "deepseek-v4.1-flash"
                        && record.project == "app" && record.requests == 3
                        && record.tokens == AgentTokens(input: 1000, cacheRead: 100_000, output: 2000)
                        && record.date == modified,
                     "DeepSeek's projection cache is reduced to one session record")
        let empty = Data(#"{"record":{"identity":{"createdAt":1790088000000,"cwd":"/tmp"},"rows":{"tokenUsage":{"val":{"totals":{}}}}}}"#.utf8)
        suite.expect(AgentDeepSeekReader.payload(empty, session: "empty", modified: modified, since: .distantPast) == nil,
                     "a session with no tokens yields no record")
        suite.expect(AgentDeepSeekReader.payload(cache, session: "session-1", modified: modified,
                                                 since: modified.addingTimeInterval(1)) == nil,
                     "a session that started before the history window is left out")
        let withText = Data(#"{"record":{"identity":{"createdAt":1790088000000,"cwd":"/tmp"},"rows":{"tokenUsage":{"val":{"totals":{"uncachedInputTokens":10}}},"title":{"val":"private title"},"turnOutline":{"val":{"draft":"private prompt"}}}}}"#.utf8)
        let textPayload = AgentDeepSeekReader.payload(withText, session: "session-2", modified: modified,
                                                      since: .distantPast)
        suite.expect(textPayload.map { !String(decoding: $0, as: UTF8.self).contains("private") } == true,
                     "a projection's titles and outline are never decoded into the counters line")
    }
}
