// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AntigravityAgentTests {
    static func run(_ suite: TestSuite) {
        discoveryAndBoundaries(suite)
        turnLifecycleAndEdgeCases(suite)
        workspacePriority(suite)
        sessionCursorAndArchive(suite)
        subagentRollup(suite)
        geminiPricingAndUnpricedInvariants(suite)
        serverAndMultiPoolLimits(suite)
    }

    private static func jsonLine(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    // MARK: 1. Path Boundary & Discovery

    private static func discoveryAndBoundaries(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "vorssaint-antigravity-roots-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }

        do {
            let desktopBrain = home.appending(path: ".gemini/antigravity/brain", directoryHint: .isDirectory)
            let ideBrain = home.appending(path: ".gemini/antigravity-ide/brain", directoryHint: .isDirectory)
            let cliBrain = home.appending(path: ".gemini/antigravity-cli/brain", directoryHint: .isDirectory)
            let claudeProjects = home.appending(path: ".claude/projects", directoryHint: .isDirectory)
            for dir in [desktopBrain, ideBrain, cliBrain, claudeProjects] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            let roots = AgentLogRoot.all(home: home)
            let antigravityRoots = roots.filter { $0.provider == .antigravity }
            let expectedURLs = Set([desktopBrain, ideBrain, cliBrain].map(AgentLogRoot.canonical))
            suite.expect(antigravityRoots.count == 3 && Set(antigravityRoots.map(\.url)) == expectedURLs,
                         "Antigravity watches Desktop, IDE and agy CLI brain roots")

            guard let root = antigravityRoots.first(where: { $0.url == AgentLogRoot.canonical(desktopBrain) }),
                  let claudeRoot = roots.first(where: { $0.provider == .claude }) else {
                suite.expect(false, "Antigravity and Claude roots resolve under temporary home")
                return
            }

            let valid = root.url.appending(path: "conv-1/.system_generated/logs/transcript.jsonl").path
            let full = root.url.appending(path: "conv-1/.system_generated/logs/transcript_full.jsonl").path
            let chunk = root.url.appending(path: "conv-1/.system_generated/logs/chunks/0.txt").path
            let chunkJsonl = root.url.appending(path: "conv-1/.system_generated/logs/chunks/0.jsonl").path
            let scratch = root.url.appending(path: "conv-1/scratch/repo/data.jsonl").path
            let hidden = root.url.appending(path: ".tmp/.system_generated/logs/transcript.jsonl").path
            let claudeInBrainProject = claudeRoot.url.appending(path: "work-brain/session.jsonl").path
            let claudeInsideProjectNamedBrain = home.appending(path: "code/brain/.claude/session.jsonl").path

            suite.expect(root.accepts(valid)
                            && !root.accepts(full)
                            && !root.accepts(chunk)
                            && !root.accepts(chunkJsonl)
                            && !root.accepts(scratch)
                            && !root.accepts(hidden)
                            && !root.accepts(claudeInBrainProject)
                            && !root.accepts(claudeInsideProjectNamedBrain)
                            && claudeRoot.accepts(claudeInBrainProject)
                            && !claudeRoot.accepts(valid),
                         "Antigravity accepts only canonical 4-segment transcript.jsonl logs and never crosses into other harnesses")

            let now = AgentTimestamp.parse("2026-10-31T20:10:00Z")!
            let rootConv = root.url.appending(path: "conv-root/.system_generated/logs/transcript.jsonl")
            let subConv = root.url.appending(path: "conv-sub/.system_generated/logs/transcript.jsonl")
            let fullConv = root.url.appending(path: "conv-root/.system_generated/logs/transcript_full.jsonl")
            let nestedScratch = root.url
                .appending(path: "conv-root/scratch/clone/nested/.system_generated/logs/transcript.jsonl")

            for file in [rootConv, subConv, fullConv, nestedScratch] {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
            }

            let rootHeader = Data((#"{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-10-31T20:05:00Z","content":"work"}"# + "\n").utf8)
            let subHeader = Data((#"{"step_index":0,"source":"SYSTEM","type":"SYSTEM_MESSAGE","status":"DONE","created_at":"2026-10-31T20:04:00Z","content":"[Message] timestamp=2026-10-31T20:04:00Z sender=conv-root task"}"# + "\n").utf8)
            try rootHeader.write(to: rootConv)
            try subHeader.write(to: subConv)
            try rootHeader.write(to: fullConv)
            try rootHeader.write(to: nestedScratch)

            // Give the subagent an older mtime than the root session so discovery must sort by subagent role, not mtime alone.
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)],
                                                  ofItemAtPath: rootConv.path)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-120)],
                                                  ofItemAtPath: subConv.path)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-30)],
                                                  ofItemAtPath: fullConv.path)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)],
                                                  ofItemAtPath: nestedScratch.path)

            let discovered = AgentLogReader.discover(antigravityRoots, since: now.addingTimeInterval(-3_600))
            suite.expect(discovered.map(\.path) == [rootConv.path, subConv.path]
                            && discovered.allSatisfy { $0.provider == .antigravity },
                         "shallow Antigravity discovery skips scratch checkouts and orders root transcripts before subagents")
        } catch {
            suite.expect(false, "Antigravity discovery fixture: \(error)")
        }
    }

    // MARK: 2. Turn Lifecycle & Edge Cases

    private static func turnLifecycleAndEdgeCases(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-10-31T20:10:00Z")!
        let file = "/tmp/brain/session-1/.system_generated/logs/transcript.jsonl"
        var state = AgentLogState()
        state.session = "session-1"
        let store = AgentUsageStore()
        store.reportsTransitions = true

        func iso(_ offset: TimeInterval) -> String {
            ISO8601DateFormatter().string(from: now.addingTimeInterval(offset))
        }

        func feed(_ object: [String: Any]) -> (entries: [AgentLogEntry], events: [AgentUsageEvent]) {
            let entries = AgentLogParser.parseAntigravity(jsonLine(object), state: &state, now: now)
            let events = store.apply(entries, file: file, provider: .antigravity,
                                     tracksTurns: true, modified: now, now: now)
            return (entries, events)
        }

        // Open first turn and start a long shell command.
        _ = feed([
            "step_index": 0, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
            "created_at": iso(-120),
            "content": "<USER_REQUEST>\nfirst\n</USER_REQUEST>\n<ADDITIONAL_METADATA>\nActive Workspaces:\n- /Users/me/vorssaint-utils\nchanged setting `Model Selection` from `None` to `Gemini 4 Argon (High)`.\n</ADDITIONAL_METADATA>"
        ])
        _ = feed([
            "step_index": 1, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
            "created_at": iso(-110), "input_tokens": 500, "output_tokens": 80,
            "tool_calls": [["id": "cmd-1", "name": "run_command", "args": ["CommandLine": "sleep 10"]]]
        ])
        suite.expect(state.turnOpen && store.turns[file] != nil,
                     "run_command tool calls keep the turn open while work continues")

        // Interrupting with a new USER_INPUT while turnOpen == true closes the old turn with completed: false.
        let interrupted = feed([
            "step_index": 2, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
            "created_at": iso(-90),
            "content": "<USER_REQUEST>\nsecond\n</USER_REQUEST>"
        ])
        let closedIncomplete = interrupted.entries.first == .turnEnded(nil, completed: false, duration: nil)
        suite.expect(closedIncomplete && state.turnOpen
                        && interrupted.events.isEmpty
                        && store.turns[file]?.started == now.addingTimeInterval(-90),
                     "a new user prompt during an open turn closes the interrupted turn without a finished alert")

        // GENERIC tool output refreshes turn activity while the turn stays open.
        _ = feed([
            "step_index": 3, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
            "created_at": iso(-80), "input_tokens": 400, "output_tokens": 60,
            "tool_calls": [["id": "cmd-2", "name": "run_command", "args": ["CommandLine": "ls"]]]
        ])
        let genericOut = feed([
            "step_index": 4, "source": "MODEL", "type": "GENERIC", "status": "DONE",
            "created_at": iso(-60), "content": "ok"
        ])
        suite.expect(state.turnOpen && genericOut.events.isEmpty
                        && store.turns[file]?.lastActivity == now.addingTimeInterval(-60),
                     "GENERIC tool output refreshes turn activity")

        // ERROR closes the turn with completed: false even when tool_calls is non-empty.
        let errored = feed([
            "step_index": 5, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "ERROR",
            "created_at": iso(-50), "input_tokens": 100, "output_tokens": 10,
            "tool_calls": [["id": "cmd-err", "name": "run_command", "args": ["CommandLine": "echo fail"]]]
        ])
        suite.expect(!state.turnOpen
                        && store.turns[file] == nil && errored.events.isEmpty,
                     "PLANNER_RESPONSE with status ERROR closes the turn incomplete even when tool_calls are attached")

        // Clean DONE without tool_calls emits .finished once.
        _ = feed([
            "step_index": 6, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
            "created_at": iso(-30), "content": "<USER_REQUEST>\nfinish cleanly\n</USER_REQUEST>"
        ])
        let completed = feed([
            "step_index": 7, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
            "created_at": iso(-5), "input_tokens": 1_000, "output_tokens": 200
        ])
        var finishedMatch = false
        if completed.events.count == 1,
           case .finished(let provider, let duration, _, let tokens, let project) = completed.events[0] {
            finishedMatch = provider == .antigravity && abs(duration - 25) < 0.01
                && tokens == 1_200 && project == "vorssaint-utils"
        }
        suite.expect(!state.turnOpen && store.turns[file] == nil && finishedMatch,
                     "status DONE without tool_calls closes the turn and emits a single finished event")
    }

    // MARK: 3. Strict Workspace Priority

    private static func workspacePriority(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-10-31T20:10:00Z")!
        var state = AgentLogState()
        state.session = "ws-1"

        // File tool paths (read_file, edit_file, write_file) must never infer a project.
        _ = AgentLogParser.parseAntigravity(jsonLine([
            "step_index": 0, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
            "created_at": "2026-10-31T20:00:00Z",
            "content": "<USER_REQUEST>\nInspect /Users/me/secret-project/File.swift\n</USER_REQUEST>"
        ]), state: &state, now: now)
        _ = AgentLogParser.parseAntigravity(jsonLine([
            "step_index": 1, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
            "created_at": "2026-10-31T20:00:05Z", "input_tokens": 50, "output_tokens": 10,
            "tool_calls": [
                ["id": "r1", "name": "read_file", "args": ["Path": "/Users/me/secret-a/main.swift"]],
                ["id": "e1", "name": "edit_file", "args": ["Path": "/Users/me/secret-b/main.swift"]],
                ["id": "w1", "name": "write_file", "args": ["Path": "/Users/me/secret-c/main.swift"]]
            ]
        ]), state: &state, now: now)
        suite.expect(state.project.isEmpty && state.antigravityNamedWorkspace.isEmpty,
                     "read_file, edit_file and write_file paths never set or alter project")

        // Fallback to run_command Cwd when no workspace is known yet.
        _ = AgentLogParser.parseAntigravity(jsonLine([
            "step_index": 2, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
            "created_at": "2026-10-31T20:00:10Z", "input_tokens": 50, "output_tokens": 10,
            "tool_calls": [
                ["id": "c1", "name": "run_command", "args": ["Cwd": "/Users/me/fallback-cmd-repo", "CommandLine": "pwd"]]
            ]
        ]), state: &state, now: now)
        suite.expect(state.project == "fallback-cmd-repo" && state.antigravityNamedWorkspace.isEmpty,
                     "run_command Cwd provides a fallback project only while no named workspace exists")

        // Command Working Directory sets project when Active Workspaces is absent, and Active Workspaces overrides and locks it.
        var cwdState = AgentLogState()
        cwdState.session = "ws-2"
        _ = AgentLogParser.parseAntigravity(jsonLine([
            "step_index": 0, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
            "created_at": "2026-10-31T20:01:00Z",
            "content": "<ADDITIONAL_METADATA>\nCommand Working Directory: /Users/me/cli-workdir\n</ADDITIONAL_METADATA>"
        ]), state: &cwdState, now: now)
        let adoptedCwd = cwdState.project == "cli-workdir" && cwdState.antigravityNamedWorkspace.isEmpty

        _ = AgentLogParser.parseAntigravity(jsonLine([
            "step_index": 1, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
            "created_at": "2026-10-31T20:02:00Z",
            "content": "<ADDITIONAL_METADATA>\nActive Workspaces:\n- /Users/me/locked-workspace\nCommand Working Directory: /Users/me/ignored-cwd\n</ADDITIONAL_METADATA>"
        ]), state: &cwdState, now: now)
        _ = AgentLogParser.parseAntigravity(jsonLine([
            "step_index": 2, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
            "created_at": "2026-10-31T20:03:00Z",
            "content": "<ADDITIONAL_METADATA>\nCommand Working Directory: /Users/me/later-cwd\n</ADDITIONAL_METADATA>"
        ]), state: &cwdState, now: now)
        _ = AgentLogParser.parseAntigravity(jsonLine([
            "step_index": 3, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
            "created_at": "2026-10-31T20:03:05Z", "input_tokens": 20, "output_tokens": 5,
            "tool_calls": [
                ["id": "c2", "name": "run_command", "args": ["Cwd": "/Users/me/later-cmd", "CommandLine": "ls"]]
            ]
        ]), state: &cwdState, now: now)
        suite.expect(adoptedCwd
                        && cwdState.antigravityNamedWorkspace == "locked-workspace"
                        && cwdState.project == "locked-workspace",
                     "Active Workspaces outranks Command Working Directory and run_command Cwd and stays locked")
    }

    // MARK: 4. Session Identity, Cursor startOver & Archive v5 Round-Trip

    private static func sessionCursorAndArchive(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "vorssaint-antigravity-archive-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }

        do {
            let now = AgentTimestamp.parse("2026-10-31T20:15:00Z")!
            let brain = folder.appending(path: "brain", directoryHint: .isDirectory)
            let rootFile = brain.appending(path: "conv-uuid-42/.system_generated/logs/transcript.jsonl")
            let subFile = brain.appending(path: "sub-uuid-99/.system_generated/logs/transcript.jsonl")
            for file in [rootFile, subFile] {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
            }

            let rootLines = [
                jsonLine([
                    "step_index": 0, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
                    "created_at": "2026-10-31T20:10:00Z",
                    "content": "<ADDITIONAL_METADATA>\nActive Workspaces:\n- /Users/me/vorssaint-utils\nchanged setting `Model Selection` from `None` to `Gemini 4 Argon`.\n</ADDITIONAL_METADATA>"
                ]),
                jsonLine([
                    "step_index": 1, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
                    "created_at": "2026-10-31T20:10:15Z", "input_tokens": 2_000, "output_tokens": 300
                ])
            ]
            let subLines = [
                jsonLine([
                    "step_index": 0, "source": "SYSTEM", "type": "SYSTEM_MESSAGE", "status": "DONE",
                    "created_at": "2026-10-31T20:10:05Z",
                    "content": "[Message] timestamp=2026-10-31T20:10:05Z sender=conv-uuid-42 Check tests"
                ]),
                jsonLine([
                    "step_index": 1, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
                    "created_at": "2026-10-31T20:10:10Z", "model": "Gemini 3.8 Flash",
                    "input_tokens": 1_000, "output_tokens": 150
                ])
            ]

            try Data((rootLines.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n").utf8)
                .write(to: rootFile)
            try Data((subLines.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n").utf8)
                .write(to: subFile)

            let rootCursor = AgentLogCursor(path: rootFile.path, provider: .antigravity)
            suite.expect(rootCursor.state.session == "conv-uuid-42" && rootCursor.tracksTurns && rootCursor.parent == nil,
                         "AgentLogCursor extracts the Antigravity conversation UUID from transcript.jsonl path")

            rootCursor.state.model = "Gemini 4 Argon"
            rootCursor.startOver(identity: 77)
            suite.expect(rootCursor.state.model.isEmpty && rootCursor.state.session == "conv-uuid-42",
                         "AgentLogCursor.startOver resets transient parser state without losing the conversation session ID")

            let subCursor = AgentLogCursor(path: subFile.path, provider: .antigravity)
            let store = AgentUsageStore()

            for cursor in [rootCursor, subCursor] {
                AgentLogReader.readAppended(cursor) { line in
                    let entries = AgentLogParser.parseAntigravity(line, state: &cursor.state, now: now)
                    store.apply(entries, file: cursor.path, provider: .antigravity,
                                tracksTurns: cursor.tracksTurns, parent: cursor.parent,
                                modified: cursor.modified, now: now)
                }
            }

            let contents = AgentUsageArchive.Contents(providers: [.antigravity], store: store.saved,
                                                      cursors: [rootCursor.saved, subCursor.saved])
            let encoded = AgentUsageArchive.encode(contents, build: "antigravity-v5-test")
            let decoded = AgentUsageArchive.decode(encoded, build: "antigravity-v5-test")
            suite.expect(decoded == contents, "Archive v5 encodes and decodes Antigravity cursor state losslessly")

            if let decoded {
                let resumed = AgentUsageArchive.resume(decoded, logs: [rootFile.path, subFile.path],
                                                       since: now.addingTimeInterval(-3_600))
                let resumedRoot = resumed.cursors[rootFile.path]
                let resumedSub = resumed.cursors[subFile.path]
                suite.expect(resumed.unchanged
                                && resumedRoot?.state.session == "conv-uuid-42"
                                && resumedRoot?.state.antigravityNamedWorkspace == "vorssaint-utils"
                                && resumedSub?.state.session == "sub-uuid-99"
                                && resumedSub?.state.antigravitySubagent == true
                                && resumedSub?.state.antigravityRoot == "conv-uuid-42"
                                && resumedSub?.tracksTurns == false
                                && resumedSub?.parent == rootFile.path,
                             "resuming Archive v5 restores named workspaces, subagent flags and parent transcript links")
            }
        } catch {
            suite.expect(false, "Antigravity cursor/archive fixture: \(error)")
        }
    }

    // MARK: 5. Subagent Rollup

    private static func subagentRollup(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-10-31T20:20:00Z")!
        let parentPath = "/tmp/brain/parent-uuid/.system_generated/logs/transcript.jsonl"
        let childPath = "/tmp/brain/child-uuid/.system_generated/logs/transcript.jsonl"
        let parentCursor = AgentLogCursor(path: parentPath, provider: .antigravity)
        let childCursor = AgentLogCursor(path: childPath, provider: .antigravity)
        let store = AgentUsageStore()
        store.reportsTransitions = true

        func apply(_ cursor: AgentLogCursor, _ object: [String: Any]) -> [AgentUsageEvent] {
            let entries = AgentLogParser.parseAntigravity(jsonLine(object), state: &cursor.state, now: now)
            return store.apply(entries, file: cursor.path, provider: .antigravity,
                               tracksTurns: cursor.tracksTurns, parent: cursor.parent,
                               modified: now, now: now)
        }

        // Open parent turn on Gemini 4 Argon ($2/M input, $10/M output): 1M in + 100k out = $3.00.
        _ = apply(parentCursor, [
            "step_index": 0, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
            "created_at": "2026-10-31T20:18:00Z",
            "content": "<ADDITIONAL_METADATA>\nActive Workspaces:\n- /Users/me/main-project\nchanged setting `Model Selection` from `None` to `Gemini 4 Argon (High)`.\n</ADDITIONAL_METADATA>"
        ])
        _ = apply(parentCursor, [
            "step_index": 1, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
            "created_at": "2026-10-31T20:18:10Z", "input_tokens": 1_000_000, "output_tokens": 100_000,
            "tool_calls": [["id": "sub-1", "name": "invoke_subagent", "args": ["Role": "Researcher"]]]
        ])

        // Subagent starts with SYSTEM_MESSAGE sender=parent-uuid and finishes on Gemini 3.8 Flash ($0.75/M in, $3.75/M out):
        // 1M in + 200k out = $1.50.
        _ = apply(childCursor, [
            "step_index": 0, "source": "SYSTEM", "type": "SYSTEM_MESSAGE", "status": "DONE",
            "created_at": "2026-10-31T20:18:12Z",
            "content": "[Message] timestamp=2026-10-31T20:18:12Z sender=parent-uuid Research files"
        ])
        suite.expect(childCursor.state.antigravitySubagent
                        && childCursor.state.antigravityRoot == "parent-uuid"
                        && !childCursor.tracksTurns
                        && childCursor.parent == parentPath,
                     "SYSTEM_MESSAGE sender header marks an Antigravity subagent and links it to its parent transcript")

        _ = apply(childCursor, [
            "step_index": 1, "source": "USER_EXPLICIT", "type": "USER_INPUT", "status": "DONE",
            "created_at": "2026-10-31T20:18:13Z",
            "content": "<ADDITIONAL_METADATA>\nActive Workspaces:\n- /Users/me/subagent-other\n</ADDITIONAL_METADATA>"
        ])
        let childEvents = apply(childCursor, [
            "step_index": 2, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
            "created_at": "2026-10-31T20:18:40Z", "model": "Gemini 3.8 Flash",
            "input_tokens": 1_000_000, "output_tokens": 200_000
        ])

        let liveDuringSubagent = store.live
        suite.expect(childEvents.isEmpty
                        && liveDuringSubagent.count == 1
                        && liveDuringSubagent.first?.id == parentPath
                        && liveDuringSubagent.first?.project == "main-project"
                        && liveDuringSubagent.first?.model == "Gemini 4 Argon (High)"
                        && liveDuringSubagent.first?.tokens.total == 2_300_000
                        && abs((liveDuringSubagent.first?.cost ?? 0) - 4.5) < 1e-6,
                     "subagent tokens and API value roll into the parent live session without opening a second turn or altering its model/project")

        // Finishing the parent turn includes the subagent's rolled-up tokens and cost.
        let parentFinish = apply(parentCursor, [
            "step_index": 2, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
            "created_at": "2026-10-31T20:19:00Z", "input_tokens": 0, "output_tokens": 50_000
        ])
        var rollupFinished = false
        if parentFinish.count == 1,
           case .finished(let provider, _, let cost, let tokens, let project) = parentFinish[0] {
            rollupFinished = provider == .antigravity && tokens == 2_350_000
                && abs(cost - 5.0) < 1e-6 && project == "main-project"
        }
        suite.expect(rollupFinished && store.live.isEmpty,
                     "completing the parent turn reports combined parent and subagent tokens and API value")
    }

    // MARK: 6. Official Gemini Pricing & Unpriced Invariants

    private static func geminiPricingAndUnpricedInvariants(_ suite: TestSuite) {
        suite.expect(AgentPricing.normalized("Gemini 4 Argon (High)") == "gemini-4-argon"
                        && AgentPricing.normalized("Claude Sonnet 4.6 (Thinking)") == "claude-sonnet-4-6"
                        && AgentPricing.normalized("models/gemini-3.8-flash") == "gemini-3.8-flash",
                     "AgentPricing normalizes Antigravity Model Selection labels and API model prefixes")

        suite.expect(AgentPricing.displayName("gemini-4-argon") == "Gemini 4 Argon"
                        && AgentPricing.displayName("gemini-3.8-flash") == "Gemini 3.8 Flash"
                        && AgentPricing.displayName("gemini-3.5-flash-lite") == "Gemini 3.5 Flash-Lite"
                        && AgentPricing.displayName("gemini-2.5-pro-preview-05-06") == "Gemini 2.5 Pro",
                     "AgentPricing formats Gemini family names cleanly without preview suffixes")

        let argon = AgentPricing.cost(
            AgentBillable(tokens: AgentTokens(input: 1_000_000, cacheRead: 1_000_000, output: 100_000)),
            model: "Gemini 4 Argon (High)")
        let flash38 = AgentPricing.cost(
            AgentBillable(tokens: AgentTokens(input: 1_000_000, cacheRead: 1_000_000, output: 100_000)),
            model: "Gemini 3.8 Flash")
        let pro25Standard = AgentPricing.cost(
            AgentBillable(tokens: AgentTokens(input: 100_000, cacheRead: 50_000, output: 10_000)),
            model: "gemini-2.5-pro")
        let pro25Long = AgentPricing.cost(
            AgentBillable(tokens: AgentTokens(input: 150_000, cacheRead: 100_000, output: 10_000)),
            model: "gemini-2.5-pro")
        let claudeSonnet = AgentPricing.cost(
            AgentBillable(tokens: AgentTokens(input: 1_000_000, output: 100_000)),
            model: "Claude Sonnet 4.6 (Thinking)")

        suite.expect(abs((argon.cost ?? -1) - 3.10) < 1e-9 && abs(argon.savings - 1.90) < 1e-9
                        && abs((flash38.cost ?? -1) - 1.20) < 1e-9
                        && abs((pro25Standard.cost ?? -1) - 0.23125) < 1e-9
                        && abs((pro25Long.cost ?? -1) - 0.55) < 1e-9
                        && abs((claudeSonnet.cost ?? -1) - 4.50) < 1e-9,
                     "official Gemini and Claude models in Antigravity price input, cache reads and >200k long context accurately")

        let carbon = AgentPricing.cost(
            AgentBillable(tokens: AgentTokens(input: 1_000_000, cacheRead: 1_000_000, output: 100_000)),
            model: "Gemini 4 Carbon (High)")
        let fable52 = AgentPricing.cost(
            AgentBillable(tokens: AgentTokens(input: 1_000_000, cacheRead: 1_000_000, output: 100_000)),
            model: "Claude Fable 5.2 (Medium)")
        suite.expect(abs((carbon.cost ?? -1) - 3.10) < 1e-9 && abs(carbon.savings - 1.90) < 1e-9
                        && abs((fable52.cost ?? -1) - 12.20) < 1e-9 && abs(fable52.savings - 7.80) < 1e-9,
                     "Gemini 4 Carbon and Claude Fable 5.2 are priced from their Antigravity Model Selection labels")

        // Unpriced models & legacy tokenless transcripts must remain cost == nil even after store.reprice().
        suite.expect(AgentPricing.price(for: "gemini-experimental-preview") == nil
                        && AgentPricing.price(for: "gemini-3.8-live") == nil
                        && AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 50_000, output: 5_000)),
                                             model: "gemini-experimental-preview").cost == nil
                        && AgentPricing.cost(AgentBillable(tokens: AgentTokens(input: 50_000, output: 5_000)),
                                             model: "gemini-3.8-live").cost == nil,
                     "unlisted Gemini models and Live audio siblings never inherit text family prices")

        let now = AgentTimestamp.parse("2026-10-31T14:00:00Z")!
        var state = AgentLogState()
        state.session = "unpriced-session"
        let store = AgentUsageStore()
        let logFile = "/tmp/brain/unpriced-session/.system_generated/logs/transcript.jsonl"

        // 1) Empty model with tokens, 2) Unlisted Gemini model with tokens, 3) Legacy PLANNER_RESPONSE without token counters on priced model.
        let unpricedLines: [[String: Any]] = [
            ["step_index": 1, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
             "created_at": "2026-10-31T13:50:00Z", "input_tokens": 500, "output_tokens": 100],
            ["step_index": 2, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
             "created_at": "2026-10-31T13:51:00Z", "model": "gemini-experimental-preview", "input_tokens": 800, "output_tokens": 200],
            ["step_index": 3, "source": "MODEL", "type": "PLANNER_RESPONSE", "status": "DONE",
             "created_at": "2026-10-31T13:52:00Z", "model": "Gemini 4 Argon"]
        ]
        for line in unpricedLines {
            let entries = AgentLogParser.parseAntigravity(jsonLine(line), state: &state, now: now)
            store.apply(entries, file: logFile, provider: .antigravity, tracksTurns: true, modified: now, now: now)
        }
        let allNilBefore = store.records.count == 3 && store.records.allSatisfy { $0.cost == nil }
        store.reprice()
        let allNilAfter = store.records.count == 3 && store.records.allSatisfy { $0.cost == nil }
        let snap = store.snapshot(plans: [:], providers: [.antigravity], now: now)
        suite.expect(allNilBefore && allNilAfter && snap.usage(.today).total.unpriced == 3,
                     "empty models, unlisted Gemini models and tokenless legacy responses stay unpriced (cost == nil) across reprice()")

        // Remote price list without a gemini section preserves shipped Gemini prices.
        let shipped = AgentPricing.list
        let remoteWithoutGemini = AgentPriceList(
            updated: Date.distantFuture, claude: shipped.claude, codex: shipped.codex,
            claudePlans: shipped.claudePlans, codexPlans: shipped.codexPlans,
            webSearch: shipped.webSearch, usOnlyMultiplier: shipped.usOnlyMultiplier, gemini: [])
        let merged = AgentPriceList.newer(shipped, remoteWithoutGemini)
        suite.expect(!shipped.gemini.isEmpty && merged?.gemini == shipped.gemini,
                     "downloading a price list without a gemini table preserves the app's shipped Gemini prices")
    }

    // MARK: 7. AgentAntigravityServer & Multi-Pool Limits

    private static func serverAndMultiPoolLimits(_ suite: TestSuite) {
        let now = AgentTimestamp.parse("2026-10-31T20:00:00Z")!
        let payload: [String: Any] = [
            "status": "SUCCESS",
            "command": [
                "name": "usage",
                "data": [
                    "groups": [
                        [
                            "name": "Gemini models",
                            "buckets": [
                                ["window": "5h", "remaining_fraction": 0.68, "reset_time": "2026-10-31T23:00:00Z"],
                                ["window": "weekly", "remaining_fraction": 0.45, "reset_time": "2026-11-05T00:00:00Z"],
                                ["window": "5h", "remaining_fraction": 0.50, "reset_time": "2026-10-31T19:00:00Z"],
                                ["window": "weekly", "remaining_fraction": 0.10, "disabled": true, "reset_time": "2026-11-05T00:00:00Z"],
                                ["window": "5h", "remaining_fraction": true, "reset_time": "2026-10-31T23:00:00Z"]
                            ]
                        ],
                        [
                            "name": "Claude & GPT models",
                            "buckets": [
                                ["window": "5h", "remaining_fraction": 0.15, "reset_time": "2026-10-31T22:30:00Z"],
                                ["window": "weekly", "remaining_fraction": 0.25, "reset_time": "2026-11-04T00:00:00Z"]
                            ]
                        ],
                        [
                            "name": "Experimental Pool",
                            "buckets": [
                                ["window": "5h", "remaining_fraction": -0.25, "reset_time": "2026-10-31T22:00:00Z"],
                                ["window": "weekly", "remaining_fraction": 1.30, "reset_time": NSNull()]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let parsed = AgentAntigravityServer.limits(payload, observed: now)
        suite.expect(parsed?.provider == .antigravity
                        && parsed?.source == .account
                        && parsed?.windows.map(\.id) == [
                            "antigravity.gemini.5h", "antigravity.gemini.wk",
                            "antigravity.claude-gpt.5h", "antigravity.claude-gpt.wk",
                            "antigravity.experimental-pool.5h", "antigravity.experimental-pool.wk"
                        ]
                        && parsed?.windows[0].scope == nil
                        && parsed?.windows[2].scope == "Claude/GPT"
                        && abs((parsed?.windows[0].usedPercent ?? -1) - 32) < 1e-6
                        && abs((parsed?.windows[1].usedPercent ?? -1) - 55) < 1e-6
                        && abs((parsed?.windows[2].usedPercent ?? -1) - 85) < 1e-6
                        && abs((parsed?.windows[3].usedPercent ?? -1) - 75) < 1e-6
                        && parsed?.windows[4].usedPercent == 100
                        && parsed?.windows[5].usedPercent == 0
                        && parsed?.windows[5].resetsAt == nil,
                     "AgentAntigravityServer parses multi-pool usage JSON, assigns scopes, clamps fractions and skips disabled or expired buckets")

        // Multi-pool selection picks the most binding window for both session and weekly focus.
        let twoPool = AgentLimits(provider: .antigravity, windows: Array((parsed?.windows ?? []).prefix(4)),
                                  observedAt: now, source: .account)
        let chosenSession = NotchAgentSupport.focusedLimit(twoPool, focus: .session, now: now)
        let chosenWeekly = NotchAgentSupport.focusedLimit(twoPool, focus: .weekly, now: now)
        suite.expect(chosenSession?.id == "antigravity.claude-gpt.5h" && chosenSession?.scope == "Claude/GPT"
                        && chosenWeekly?.id == "antigravity.claude-gpt.wk" && chosenWeekly?.scope == "Claude/GPT",
                     "NotchAgentSupport selects the highest usedPercent window across Gemini and Claude/GPT quota pools")

        // Multi-group 20-hour schema (agy 1.4+) with explicit bucket IDs.
        let twentyHourPayload: [String: Any] = [
            "status": "SUCCESS",
            "command": [
                "name": "usage",
                "data": [
                    "groups": [
                        [
                            "name": "Gemini Flash",
                            "buckets": [
                                ["id": "gemini-flash-20h", "window": "20h", "remaining_fraction": 1.0,
                                 "reset_time": "2026-11-01T17:34:06Z"]
                            ]
                        ],
                        [
                            "name": "Gemini 3.1 Pro",
                            "buckets": [
                                ["id": "gemini-3-1-pro-20h", "window": "20h", "remaining_fraction": 0.71,
                                 "reset_time": "2026-11-01T09:12:51Z"]
                            ]
                        ],
                        [
                            "name": "Third-Party Models",
                            "buckets": [
                                ["id": "third-party-20h", "window": "20h", "remaining_fraction": 0.90,
                                 "reset_time": "2026-11-01T17:34:06Z"]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let twentyHour = AgentAntigravityServer.limits(twentyHourPayload, observed: now)
        let twentyHourFocused = NotchAgentSupport.focusedLimit(twentyHour, focus: .session, now: now)
        suite.expect(twentyHour?.windows.count == 3
                        && twentyHour?.windows.map(\.id) == [
                            "antigravity.gemini-flash-20h.20h",
                            "antigravity.gemini-3-1-pro-20h.20h",
                            "antigravity.third-party-20h.20h"
                        ]
                        && twentyHour?.windows.map(\.kind) == [.other, .other, .other]
                        && twentyHour?.windows.map(\.minutes) == [1_200, 1_200, 1_200]
                        && twentyHour?.windows.map(\.scope) == ["Gemini Flash", "Gemini 3.1 Pro", "Third-Party"]
                        && twentyHourFocused?.id == "antigravity.gemini-3-1-pro-20h.20h"
                        && abs((twentyHourFocused?.usedPercent ?? -1) - 29) < 1e-6,
                     "AgentAntigravityServer parses 20h multi-group buckets with distinct bucket IDs and scopes")

        // Window expiry and idle window retention.
        suite.expect(AgentAntigravityServer.current(twoPool, now: AgentTimestamp.parse("2026-10-31T22:45:00Z")!)?
                        .windows.map(\.id) == ["antigravity.gemini.5h", "antigravity.gemini.wk", "antigravity.claude-gpt.wk"]
                        && AgentAntigravityServer.current(twoPool, now: AgentTimestamp.parse("2026-11-06T00:00:00Z")!) == nil,
                     "AgentAntigravityServer expires elapsed reset windows without inventing zero usage")

        // Polling cadence and exponential backoff.
        suite.expect(AgentAntigravityServer.interval(after: nil, pageVisible: true) == 60
                        && AgentAntigravityServer.interval(after: nil, pageVisible: false) == 300
                        && [0, 1, 2, 3, 4, 8].map {
                            AgentAntigravityServer.interval(after: .unreachable, repeated: $0, pageVisible: true)
                        } == [300, 300, 600, 1_200, 1_800, 1_800]
                        && [AgentAntigravityServer.Failure.missing, .needsSignIn, .outdated].allSatisfy {
                            AgentAntigravityServer.interval(after: $0, pageVisible: true) == 1_800
                        },
                     "Antigravity limits refresh every 60s when visible, 5m in background, and back off up to 30m on failure")

        // Version parsing and comparison.
        suite.expect(AgentAntigravityServer.parseVersion("Antigravity CLI v1.1.11 (darwin-arm64)") == [1, 1, 11]
                        && AgentAntigravityServer.parseVersion("1.5.7") == [1, 5, 7]
                        && AgentAntigravityServer.parseVersion("diagnostic: backend 2.0.1") == nil
                        && AgentAntigravityServer.isSupportedVersion([1, 1, 11])
                        && AgentAntigravityServer.isSupportedVersion([1, 2, 0])
                        && !AgentAntigravityServer.isSupportedVersion([1, 1, 10])
                        && !AgentAntigravityServer.isSupportedVersion([0, 9, 9]),
                     "Antigravity CLI version check requires 1.1.11 or newer")

        // Clean subprocess environment & executable discovery.
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "vorssaint-antigravity-cli-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let cleaned = AgentAntigravityServer.environment([
                "PATH": "/usr/bin:/bin",
                "USER": "tester",
                "HTTPS_PROXY": "http://proxy.invalid:8443",
                "SSL_CERT_FILE": "/etc/ssl/cert.pem",
                "AGY_ACCOUNT": "override",
                "ANTIGRAVITY_API_KEY": "secret",
                "GEMINI_API_KEY": "secret-2",
                "GOOGLE_API_KEY": "secret-3"
            ], home: folder)
            suite.expect(cleaned["HOME"] == folder.path
                            && cleaned["USER"] == "tester"
                            && cleaned["HTTPS_PROXY"] == "http://proxy.invalid:8443"
                            && cleaned["SSL_CERT_FILE"] == "/etc/ssl/cert.pem"
                            && cleaned["AGY_ACCOUNT"] == nil
                            && cleaned["ANTIGRAVITY_API_KEY"] == nil
                            && cleaned["GEMINI_API_KEY"] == nil
                            && cleaned["GOOGLE_API_KEY"] == nil,
                         "Antigravity subprocess environment preserves proxy/TLS settings and strips session and API key overrides")

            let fakeApp = folder.appending(path: "Antigravity.app", directoryHint: .isDirectory)
            let bundledBin = fakeApp.appending(path: "Contents/Resources/app/bin/agy")
            try FileManager.default.createDirectory(at: bundledBin.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bundledBin)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledBin.path)
            let emptyHome = folder.appending(path: "empty-home", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)
            let discoveredAppBin = AgentAntigravityServer.candidates(home: emptyHome, searchPath: "relative/bin", appURLs: [fakeApp])
            suite.expect(discoveredAppBin.contains(bundledBin.standardizedFileURL)
                            && !discoveredAppBin.contains { $0.path.contains("relative/bin") },
                         "agy candidate lookup finds installed app bundle binaries and ignores relative PATH entries")

            func makeScript(_ name: String, _ body: String) throws -> URL {
                let url = folder.appending(path: name)
                try Data(body.utf8).write(to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                return url
            }

            // 1) Outdated CLI (< 1.1.11) must return .outdated WITHOUT ever invoking `-p /usage`.
            let marker = folder.appending(path: "invoked-usage-marker")
            let agyOld = try makeScript("agy-old", """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "agy 1.1.10"
              exit 0
            fi
            touch "\(marker.path)"
            exit 0
            """)
            let oldResult = AgentAntigravityServer.Request().run(
                agyOld, home: folder, environment: ["PATH": "/usr/bin:/bin"], timeout: 5)
            suite.expect(oldResult == .failure(.outdated)
                            && !FileManager.default.fileExists(atPath: marker.path),
                         "an outdated agy (< 1.1.11) fails before -p /usage is ever executed")

            // 2) Healthy CLI (1.2.0) returns parsed multi-pool Summary.
            let futureReset = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3_600))
            let agyOK = try makeScript("agy-ok", """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "Antigravity CLI 1.2.0"
              exit 0
            fi
            cat <<'EOF'
            {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini models","buckets":[{"window":"5h","remaining_fraction":0.6,"reset_time":"\(futureReset)"}]},{"name":"Claude & GPT models","buckets":[{"window":"5h","remaining_fraction":0.2,"reset_time":"\(futureReset)"}]}]}}}
            EOF
            """)
            let okSummary = try? AgentAntigravityServer.Request().run(
                agyOK, home: folder, environment: ["PATH": "/usr/bin:/bin"], timeout: 5).get()
            suite.expect(okSummary?.limits.windows.map(\.usedPercent) == [40, 80]
                            && okSummary?.limits.windows.map(\.scope) == [nil, "Claude/GPT"],
                         "Request.run parses live multi-pool quota buckets from agy 1.2.0")

            // 3) Signed-out CLI classifies as .needsSignIn.
            let agySignedOut = try makeScript("agy-signedout", """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "agy 1.2.0"
              exit 0
            fi
            echo "Error: Not logged in. Run agy auth login to sign in." >&2
            exit 1
            """)
            let signedOutResult = AgentAntigravityServer.Request().run(
                agySignedOut, home: folder, environment: ["PATH": "/usr/bin:/bin"], timeout: 5)
            suite.expect(signedOutResult == .failure(.needsSignIn),
                         "signed-out stderr diagnostics map to .needsSignIn")

            // 4) Hanging CLI cancels promptly via Request.cancel().
            let agyHang = try makeScript("agy-hang", """
            #!/bin/sh
            if [ "$1" = "--version" ]; then
              echo "agy 1.2.0"
              exit 0
            fi
            sleep 30
            """)
            let request = AgentAntigravityServer.Request()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { request.cancel() }
            let startedCancel = Date()
            let cancelled = request.run(agyHang, home: folder, environment: ["PATH": "/usr/bin:/bin"], timeout: 15)
            suite.expect(cancelled == .failure(.unreachable) && Date().timeIntervalSince(startedCancel) < 4,
                         "cancelling an active Antigravity quota request terminates the child process promptly")
        } catch {
            suite.expect(false, "Antigravity CLI fixture: \(error)")
        }

        // All 15 locales provide non-empty, distinct failure strings without em-dashes.
        let failures: [AgentAntigravityServer.Failure] = [.missing, .needsSignIn, .outdated, .unreachable]
        let allLocalesValid = AppLanguage.allCases.allSatisfy { language in
            let text = FeatureStrings.notchAgents(language)
            let messages = failures.map { text.antigravity($0) }
            return messages.allSatisfy { !$0.isEmpty && !$0.contains("\u{2014}") }
                && Set(messages).count == failures.count
                && !text.antigravityLimitsTitle.isEmpty && !text.antigravityLimitsTitle.contains("\u{2014}")
                && !text.antigravityLimitsPrivacy.isEmpty && !text.antigravityLimitsPrivacy.contains("\u{2014}")
        }
        suite.expect(allLocalesValid,
                     "every supported language provides distinct, em-dash-free Antigravity limit strings")
    }
}
