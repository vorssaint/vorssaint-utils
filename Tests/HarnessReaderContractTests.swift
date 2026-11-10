// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Every provider resolves to the reader for its own harness, and each reader
/// parses its harness's lines into the entries the island keeps.
enum HarnessReaderContractTests {
    static func run(_ suite: TestSuite) {
        readersCoverProviders(suite)
        claudeGolden(suite)
        codexGolden(suite)
        openCodeGolden(suite)
        copilotGolden(suite)
        vibeGolden(suite)
        vibeUnified(suite)
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

    private static func vibeGolden(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        var state = AgentLogState()
        let reader = AgentProvider.vibe.reader
        // Vibe writes meta.json indented over several lines.
        let meta = line("""
        {
          "session_id": "a1b2c3",
          "start_time": "2026-09-21T23:40:00Z",
          "end_time": "2026-09-21T23:42:45.078Z",
          "git_branch": "main",
          "environment": {"working_directory": "/Users/me/code/app"},
          "stats": {"steps": 4, "session_prompt_tokens": 1200, "session_completion_tokens": 300,
                    "session_cached_tokens": 500, "tool_calls_agreed": 2, "tool_calls_rejected": 1}
        }
        """)
        let counted = reader.parse(meta, state: &state, now: now)
        if case .usage(let key, let record, let billable)? = counted.first, counted.count == 1 {
            suite.expect(key == "vibe:a1b2c3" && record.provider == .vibe && record.session == "a1b2c3"
                            && record.project == "app" && record.model.isEmpty && record.cost == nil
                            && record.date == AgentTimestamp.parse("2026-09-21T23:42:45.078Z")
                            && record.tokens == AgentTokens(input: 700, cacheRead: 500, output: 300)
                            && billable.tokens == record.tokens && billable.isAggregate,
                         "a Vibe session's metadata counts its running totals once, keyed by session, with cached input apart")
        } else {
            suite.expect(false, "a Vibe session's metadata counts exactly one usage record")
        }

        let open = line(#"{"session_id":"s2","start_time":"2026-09-21T23:40:00","cwd":"/tmp/example","stats":{"session_prompt_tokens":5}}"#)
        var openState = AgentLogState()
        if case .usage(_, let record, _)? = reader.parse(open, state: &openState, now: now).first,
           let utc = AgentTimestamp.parse("2026-09-21T23:40:00Z") {
            suite.expect(record.date == utc.addingTimeInterval(-TimeInterval(TimeZone.current.secondsFromGMT(for: utc)))
                            && record.project == "example" && record.tokens == AgentTokens(input: 5),
                         "a Vibe session without an end, a zone or completion tokens still counts, in local time")
        } else {
            suite.expect(false, "a Vibe session still running is counted")
        }

        for (json, why) in [
            (#"{"start_time":"2026-09-21T23:40:00Z","stats":{"session_prompt_tokens":5}}"#, "without a session id"),
            (#"{"session_id":"s3","stats":{"session_prompt_tokens":5}}"#, "without a time"),
            (#"{"session_id":"s3","start_time":"2026-09-21T23:40:00Z"}"#, "without stats"),
            (#"{"session_id":"s3","start_time":"2026-09-21T23:40:00Z","stats":{"steps":0}}"#, "with no tokens yet"),
            (#"{"session_id":"s3","start_time":"2026-09-21T23:40:00Z","stats":"#, "cut short")
        ] {
            var skipped = AgentLogState()
            suite.expect(reader.parse(line(json), state: &skipped, now: now).isEmpty,
                         "Vibe metadata \(why) counts nothing")
        }

        let root = AgentLogRoot(provider: .vibe, url: URL(fileURLWithPath: "/Users/me/.vibe/logs/session", isDirectory: true))
        suite.expect(root.accepts(root.url.appending(path: "session_20260921_234000_a1b2c3/meta.json").path)
                        && !root.accepts(root.url.appending(path: "session_20260921_234000_a1b2c3/messages.jsonl").path)
                        && !root.accepts(root.url.appending(path: ".session_index.json").path)
                        && !root.accepts(root.url.appending(path: "unified/a1b2c3/meta.json").path)
                        && root.accepts(root.url.appending(path: "unified/a1b2c3/CURRENT").path)
                        && !root.accepts(root.url.appending(path: "unified/.staging/CURRENT").path)
                        && !root.accepts(root.url.appending(path: "unified/a1b2c3/journal/0000000000000004.jsonl").path)
                        && !root.accepts(root.url.appending(
                            path: "unified/a1b2c3/generations/0000000000000003/projection-state.json").path),
                     "only each Vibe session folder's metadata or unified pointer is read, never its transcript")
        suite.expect(AgentLogRoot.all(home: URL(fileURLWithPath: "/Users/me", isDirectory: true))
                        .first { $0.provider == .vibe }?.url.path == "/Users/me/.vibe/logs/session",
                     "the Vibe session folder is read without configuration")

        // Each save replaces the file whole; every version is read whole again.
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-vibe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = folder.appending(path: "session_20260921_234000_a1b2c3")
        let file = session.appending(path: VibeReader.metadata)
        func save(_ prompt: Int) throws {
            let temporary = session.appending(path: "meta.json.tmp")
            try Data("{\n  \"session_id\": \"a1b2c3\",\n  \"start_time\": \"2026-09-21T23:40:00Z\",\n  \"stats\": {\n    \"session_prompt_tokens\": \(prompt)\n  }\n}".utf8)
                .write(to: temporary)
            guard rename(temporary.path, file.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
        do {
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
            try Data("{\"role\":\"user\",\"content\":\"private\"}\n".utf8).write(to: session.appending(path: "messages.jsonl"))
            try save(10)
        } catch {
            suite.expect(false, "the Vibe fixture writes its session: \(error)")
            return
        }
        let vibeRoot = AgentLogRoot(provider: .vibe, url: AgentLogRoot.canonical(folder))
        let found = AgentLogReader.discover([vibeRoot], since: .distantPast)
        suite.expect(found.map(\.path) == [vibeRoot.url.appending(path: session.lastPathComponent).appending(path: VibeReader.metadata).path],
                     "discovery finds a Vibe session's metadata and not its transcript")
        let cursor = AgentLogCursor(path: found.first?.path ?? file.path, provider: .vibe)
        var read: [AgentTokens] = []
        let consume: (Data) -> Void = { data in
            for case .usage(_, let record, _) in reader.parse(data, state: &cursor.state, now: now) { read.append(record.tokens) }
        }
        AgentLogReader.readAppended(cursor, line: consume)
        AgentLogReader.readAppended(cursor, line: consume)
        try? save(25)
        AgentLogReader.readAppended(cursor, line: consume)
        suite.expect(read == [AgentTokens(input: 10), AgentTokens(input: 25)],
                     "Vibe metadata is read whole once per version")
    }

    /// Vibe 3's unified store, as `_storage.py` writes it: canonical JSON
    /// (sorted keys, no spaces) in `CURRENT`, which names a sixteen-digit
    /// generation folder whose `projection-state.json` holds the snapshot
    /// with its history entries detached into chunks.
    private static func vibeUnified(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 0)
        let reader = AgentProvider.vibe.reader
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-vibe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let id = "0b7c0f2e-8f7d-4e0a-9c55-0d5b1b0d6a11"
        let session = folder.appending(path: "unified/\(id)")
        func write(_ text: String, _ path: String) throws {
            let url = session.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).tmp")
            try Data(text.utf8).write(to: temporary)
            guard rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
        func generation(_ number: Int, input: Int, cached: Int, output: Int, pointer: Bool = true) throws {
            let name = String(format: "%016d", number)
            try write(#"{"projection_state_version":1,"session_id":"\#(id)","snapshot":{"activeCallbacks":[],"#
                      + #""format":"harness.public-session-state/v1","history":{"entries":null},"#
                      + #""latestTurn":{"items":[{"text":"private reply"}]},"session":{"createdAt":1790000000000,"#
                      + #""id":"\#(id)","preview":"private prompt","status":{"type":"idle"},"title":"private title","#
                      + #""tokenUsage":{"cachedInputTokens":\#(cached),"inputTokens":\#(input),"#
                      + #""outputTokens":\#(output),"totalTokens":\#(input + output)},"updatedAt":1790000300000},"#
                      + #""turnQueue":{"items":[]}},"snapshot_sequence":\#(number),"watermark":\#(number)}"# + "\n",
                      "generations/\(name)/projection-state.json")
            guard pointer else { return }
            try write(#"{"generation":"\#(name)","manifest_sha256":"\#(String(repeating: "0", count: 64))","#
                      + #""session_id":"\#(id)","snapshot_sequence":\#(number),"#
                      + #""store_format":"mistral.vibe.unified-session-store/v1","store_format_minor":2}"# + "\n",
                      "CURRENT")
        }
        do {
            try write(#"{"archived_at":null,"end_time":null,"environment":{"working_directory":"/Users/me/code/app"},"#
                      + #""origin_directory":"/Users/me/code","session_id":"\#(id)","#
                      + #""start_time":"2026-09-21T23:40:00Z","title":"private title","username":"me"}"#, "meta.json")
            try write(#"{"role":"user","content":"private"}"# + "\n", "journal/0000000000000004.jsonl")
            // A session not yet published has its metadata and no CURRENT.
            let fresh = folder.appending(path: "unified/fresh-session")
            try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
            try Data(#"{"session_id":"fresh-session","start_time":"2026-09-21T23:41:00Z"}"#.utf8)
                .write(to: fresh.appending(path: VibeReader.metadata))
            // An older session in the legacy layout beside the unified ones.
            let legacy = folder.appending(path: "session_20260701_120000_old")
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            try Data(#"{"session_id":"old","start_time":"2026-07-01T12:00:00Z","stats":{"session_prompt_tokens":7}}"#.utf8)
                .write(to: legacy.appending(path: VibeReader.metadata))
            try generation(3, input: 1000, cached: 600, output: 200)
        } catch {
            suite.expect(false, "the unified Vibe fixture writes its session: \(error)")
            return
        }

        let root = AgentLogRoot(provider: .vibe, url: AgentLogRoot.canonical(folder))
        let found = AgentLogReader.discover([root], since: .distantPast).map(\.path)
        let current = root.url.appending(path: "unified/\(id)/\(VibeReader.current)").path
        suite.expect(Set(found) == [current, root.url.appending(path: "session_20260701_120000_old/meta.json").path],
                     "discovery finds each unified session's pointer and legacy metadata, not a session without a pointer")

        let cursor = AgentLogCursor(path: current, provider: .vibe)
        var read: [AgentUsageRecord] = []
        let consume: (Data) -> Void = { data in
            for case .usage(let key, let record, let billable) in reader.parse(data, state: &cursor.state, now: now)
            where key == "vibe:\(id)" && billable.isAggregate { read.append(record) }
        }
        AgentLogReader.readAppended(cursor, line: consume)
        AgentLogReader.readAppended(cursor, line: consume)
        suite.expect(read.count == 1 && read.first.map {
            $0.tokens == AgentTokens(input: 400, cacheRead: 600, output: 200) && $0.session == id
                && $0.project == "app" && $0.model.isEmpty && $0.cost == nil
                && $0.date == Date(timeIntervalSince1970: 1_790_000_300)
        } == true, "a unified Vibe session counts its projected totals once, cached input apart, at its last update")

        // Vibe publishes the next generation, then swaps CURRENT and drops
        // the older generations; a pointer read before its generation lands
        // is read again later.
        do {
            try write(#"{"generation":"0000000000000009","session_id":"\#(id)","snapshot_sequence":9}"# + "\n", "CURRENT")
        } catch {
            suite.expect(false, "the unified Vibe fixture swaps its pointer: \(error)")
            return
        }
        AgentLogReader.readAppended(cursor, line: consume)
        suite.expect(read.count == 1, "a Vibe pointer to a generation not yet readable counts nothing")
        do {
            try generation(9, input: 3000, cached: 0, output: 500, pointer: false)
            try FileManager.default.removeItem(at: session.appending(path: "generations/0000000000000003"))
        } catch {
            suite.expect(false, "the unified Vibe fixture publishes a generation: \(error)")
            return
        }
        AgentLogReader.readAppended(cursor, line: consume)
        suite.expect(read.count == 2 && read.last?.tokens == AgentTokens(input: 3000, output: 500),
                     "a Vibe pointer read before its generation landed is followed on the next pass")

        for (pointer, why) in [
            (#"{"generation":"../../../etc","session_id":"x"}"#, "outside its folder"),
            (#"{"session_id":"x"}"#, "without a generation"),
            (#"{"generation":"0000000000000009""#, "cut short")
        ] {
            suite.expect(VibeReader.unifiedSession(current: Data(pointer.utf8), folder: session) == nil,
                         "a Vibe pointer \(why) is not followed")
        }
        // A session with no model reply yet has no totals.
        var state = AgentLogState()
        let noMeta = #"{"session_id":"x","tokenUsage":null,"updatedAt":1790000300000}"#
        suite.expect(reader.parse(Data(noMeta.utf8), state: &state, now: now).isEmpty,
                     "a unified Vibe session with no token usage yet counts nothing")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: current)),
           let object = VibeReader.unifiedSession(current: data, folder: session).flatMap(AgentLogParser.object) {
            suite.expect(object["preview"] == nil && object["title"] == nil && object["latestTurn"] == nil
                            && (object["tokenUsage"] as? [String: Any]) != nil,
                         "only a unified Vibe session's totals, times and folder are taken from its files")
        } else {
            suite.expect(false, "a unified Vibe pointer is followed")
        }
    }
}
