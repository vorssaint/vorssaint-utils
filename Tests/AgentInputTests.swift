// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentInputContract {
    static func run(_ suite: TestSuite) {
        let session = "0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0"
        let since = 1_794_612_600.0
        func file(_ json: [String: Any]) -> Data {
            (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        }
        let question = file(["session_id": session, "reason": "question", "tool": "AskUserQuestion",
                             "cwd": "/Users/me/Projects/Vorssaint", "app": "com.anthropic.claudefordesktop",
                             "since": since])

        // Reading what the hook writes
        let parsed = AgentInputSupport.parse(question, fileName: "\(session).json")
        suite.expect(parsed?.session == session && parsed?.reason == .question
                        && parsed?.project == "Vorssaint" && parsed?.app == "com.anthropic.claudefordesktop"
                        && parsed?.since == Date(timeIntervalSince1970: since),
                     "a hook file becomes a waiting session with its reason, project, app and start")
        let permission = file(["reason": "permission", "tool": "Bash", "cwd": "", "app": "", "since": since])
        let permissionRequest = AgentInputSupport.parse(permission, fileName: "\(session).json")
        suite.expect(permissionRequest?.reason == .permission && permissionRequest?.app == nil
                        && permissionRequest?.project == "",
                     "a permission wait reads as one, and an empty app or folder is left out")
        suite.expect(AgentInputSupport.parse(question, fileName: "not-a-session.json") == nil
                        && AgentInputSupport.parse(question, fileName: "\(session).tmp") == nil
                        && AgentInputSupport.parse(Data("{".utf8), fileName: "\(session).json") == nil
                        && AgentInputSupport.parse(file(["reason": "lunch", "since": since]),
                                                   fileName: "\(session).json") == nil
                        && AgentInputSupport.parse(file(["reason": "question"]), fileName: "\(session).json") == nil,
                     "names that are not session ids, half-written files and unknown reasons are ignored")

        // Matching a live turn, ageing out and announcing
        suite.expect(AgentInputSupport.sessionID(forLog: "/Users/me/.claude/projects/x/\(session).jsonl") == session,
                     "a live turn is matched by its log's file name")
        let request = parsed!
        suite.expect(!AgentInputSupport.isStale(request, now: request.since.addingTimeInterval(3600))
                        && AgentInputSupport.isStale(request, now: request.since.addingTimeInterval(7 * 3600)),
                     "a wait left behind stops counting after six hours")
        let later = AgentInputRequest(session: session, reason: .permission, tool: "Bash", cwd: "",
                                      since: request.since.addingTimeInterval(90), app: nil)
        suite.expect(AgentInputSupport.arrivals([request], after: []) == [request]
                        && AgentInputSupport.arrivals([request], after: [request]).isEmpty
                        && AgentInputSupport.arrivals([later], after: [request]) == [later],
                     "only a new wait is announced, including a second one in the same session")

        // Reading a folder
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "vorssaint-agent-input-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = "11111111-2222-3333-4444-555555555555"
        try? question.write(to: folder.appending(path: "\(session).json"))
        try? file(["reason": "question", "since": since - 8 * 3600]).write(to: folder.appending(path: "\(old).json"))
        try? Data("{}".utf8).write(to: folder.appending(path: ".\(session).tmp"))
        let read = AgentInputSupport.read(folder: folder, now: Date(timeIntervalSince1970: since + 60))
        suite.expect(read.requests.map(\.session) == [session]
                        && read.stale.map(\.lastPathComponent) == ["\(old).json"],
                     "a folder read keeps current waits and hands back stale files to remove")

        ClaudeHookSetupContract.run(suite)

        // The strip's words
        let strings = FeatureStrings.agentInput(.enUS)
        suite.expect(strings.waiting(count: 1) == "Needs you" && strings.waiting(count: 2) == "2 need you"
                        && strings.noticeTitle("Claude") == "Claude needs you"
                        && strings.reason(.permission) == "Permission",
                     "the strip and notice read Needs you, 2 need you and Claude needs you")
        for language in AppLanguage.allCases {
            let s = FeatureStrings.agentInput(language)
            let values = [s.needsYou, s.needYouFormat, s.noticeTitleFormat, s.question, s.permission, s.waitingFormat]
            suite.expect(values.allSatisfy { !$0.isEmpty }
                            && s.needYouFormat.contains("%d") && s.noticeTitleFormat.contains("%@")
                            && s.waitingFormat.contains("%@"),
                         "agent input strings are complete in \(language.rawValue)")
        }
    }
}

enum ClaudeHookSetupContract {
    static func run(_ suite: TestSuite) {
        let script = URL(fileURLWithPath: "/Users/me/.claude/vorssaint/needs-input-hook.sh")
        let theirs: [String: Any] = [
            "theme": "auto",
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "'/opt/bartender/hook.sh' Idle"]]]],
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "lint"]]]],
            ],
        ]
        func same(_ a: [String: Any], _ b: [String: Any]) -> Bool { NSDictionary(dictionary: a).isEqual(to: b) }

        // Merging into the person's settings
        let added = ClaudeHookSetup.adding(to: theirs, script: script)
        let hooks = added["hooks"] as? [String: Any] ?? [:]
        suite.expect(ClaudeHookSetup.isConnected(added, script: script) && !ClaudeHookSetup.isConnected(theirs, script: script),
                     "setting up adds every needed hook")
        suite.expect((added["theme"] as? String) == "auto"
                        && (hooks["Stop"] as? [Any])?.count == 2 && (hooks["PreToolUse"] as? [Any])?.count == 2,
                     "the person's own settings and other apps' hooks stay beside Vorssaint's")
        suite.expect(same(ClaudeHookSetup.adding(to: added, script: script), added),
                     "setting up again adds nothing twice")
        suite.expect(same(ClaudeHookSetup.removing(from: added), theirs),
                     "removing gives the settings back exactly as they were")
        suite.expect(same(ClaudeHookSetup.removing(from: theirs), theirs) && same(ClaudeHookSetup.removing(from: [:]), [:]),
                     "removing leaves settings without Vorssaint's hooks alone")
        let quoted = ClaudeHookSetup.command(script: URL(fileURLWithPath: "/Users/o'neil/hook.sh"), action: "set")
        suite.expect(quoted == "'/Users/o'\\''neil/hook.sh' set \(ClaudeHookSetup.marker)",
                     "a home folder with a quote in it stays one argument")

        // Files, in a home folder of its own
        let home = FileManager.default.temporaryDirectory
            .appending(path: "vorssaint-hook-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }
        let settingsURL = ClaudeHookSetup.settingsURL(home: home)
        try? FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: theirs).write(to: settingsURL)
        suite.expect(ClaudeHookSetup.status(home: home) == .notConnected, "a fresh Mac is not connected")
        let connected = (try? ClaudeHookSetup.connect(home: home)) != nil
        let scriptPath = ClaudeHookSetup.scriptURL(home: home).path
        suite.expect(connected && ClaudeHookSetup.status(home: home) == .connected
                        && FileManager.default.isExecutableFile(atPath: scriptPath)
                        && FileManager.default.fileExists(atPath: settingsURL.deletingLastPathComponent()
                            .appending(path: "settings.json.before-vorssaint").path),
                     "Set up writes the script, connects Claude Code and keeps a backup")

        // The script itself, as Claude Code runs it
        func hook(_ action: String, _ json: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: scriptPath)
            process.arguments = [action]
            var environment = ProcessInfo.processInfo.environment
            environment["HOME"] = home.path
            environment["__CFBundleIdentifier"] = "com.anthropic.claudefordesktop"
            process.environment = environment
            let input = Pipe()
            process.standardInput = input
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            input.fileHandleForWriting.write(Data(json.utf8))
            try? input.fileHandleForWriting.close()
            process.waitUntilExit()
        }
        let session = "0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0"
        let folder = AgentInputSupport.folder(home: home)
        hook("set", #"{"session_id":"\#(session)","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","cwd":"/Users/me/My \"app\""}"#)
        let written = AgentInputSupport.read(folder: folder, now: Date()).requests.first
        suite.expect(written?.session == session && written?.reason == .question
                        && written?.cwd == #"/Users/me/My "app""# && written?.app == "com.anthropic.claudefordesktop",
                     "the script records a question with its folder and app")
        hook("set", #"{"session_id":"\#(session)","hook_event_name":"Notification","message":"Claude is waiting for your input"}"#)
        hook("clear", #"{"session_id":"\#(session)"}"#)
        suite.expect(AgentInputSupport.read(folder: folder, now: Date()).requests.isEmpty,
                     "answering clears the wait")
        hook("set", #"{"session_id":"\#(session)","hook_event_name":"Notification","message":"Claude is waiting for your input"}"#)
        hook("set", #"{"session_id":"../../escape","hook_event_name":"PermissionRequest","tool_name":"Bash"}"#)
        suite.expect(AgentInputSupport.read(folder: folder, now: Date()).requests.isEmpty
                        && !FileManager.default.fileExists(atPath: home.appending(path: ".claude/escape.json").path),
                     "an idle reminder is not a wait, and a malformed session never becomes a path")
        hook("set", #"{"session_id":"\#(session)","hook_event_name":"PermissionRequest","tool_name":"Bash","cwd":""}"#)
        suite.expect(AgentInputSupport.read(folder: folder, now: Date()).requests.first?.reason == .permission,
                     "a permission prompt records a permission wait")

        let disconnected = (try? ClaudeHookSetup.disconnect(home: home)) != nil
        let after = ClaudeHookSetup.readSettings(at: settingsURL) ?? [:]
        suite.expect(disconnected && ClaudeHookSetup.status(home: home) == .notConnected && same(after, theirs)
                        && !FileManager.default.fileExists(atPath: scriptPath)
                        && !FileManager.default.fileExists(atPath: folder.path),
                     "Remove restores the settings and removes the script and any waits")

        try? Data("{ not json".utf8).write(to: settingsURL)
        let refused = (try? ClaudeHookSetup.connect(home: home)) == nil
        suite.expect(refused && ClaudeHookSetup.status(home: home) == .unreadable
                        && (try? String(contentsOf: settingsURL, encoding: .utf8)) == "{ not json",
                     "a settings file that is not JSON is never changed")
    }
}
