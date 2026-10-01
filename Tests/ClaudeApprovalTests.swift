// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum ClaudeApprovalTests {
    static func run(_ suite: TestSuite) {
        parsing(suite)
        replies(suite)
        transcript(suite)
        service(suite)
        installer(suite)
        questionsAndPlans(suite)
        codex(suite)
        strings(suite)
    }

    /// Captured from Claude Code 2.1.287, trimmed to the fields the app reads.
    private static let askPayload = #"{"session_id":"s","transcript_path":"/tmp/t.jsonl","cwd":"/Users/me/code/proj","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Which color?","header":"Color","options":[{"label":"Red","description":"The color red"},{"label":"Blue","description":"The color blue"}],"multiSelect":false},{"question":"Which sizes?","header":"Sizes","options":[{"label":"Small","description":"Small size"},{"label":"Large","description":"Large size"}],"multiSelect":true}]}}"#
    private static let planPayload = ##"{"session_id":"s","transcript_path":"/tmp/t.jsonl","cwd":"/Users/me/code/proj","permission_mode":"plan","hook_event_name":"PermissionRequest","tool_name":"ExitPlanMode","tool_input":{"plan":"# Create hello file\n\n1. Create `hello.txt` with the content `hi`.\n2. Reply with DONE.\n","planFilePath":"/Users/me/.claude/plans/p.md"},"permission_suggestions":null}"##
    /// From the Codex hooks documentation; never captured from a real session.
    private static let codexPayload = #"{"session_id":"c","transcript_path":"/Users/me/.codex/sessions/r.jsonl","cwd":"/Users/me/code/proj","hook_event_name":"PermissionRequest","model":"gpt-5","turn_id":"t1","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}"#

    /// Captured from Claude Code 2.1.286, trimmed to the fields the app reads.
    private static func payload(command: String = "python3 -c 'print(42)'",
                                suggestions: String = #"[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"python3 -c 'print(42)'"}],"behavior":"allow","destination":"localSettings"}]"#,
                                transcript: String = "/tmp/t.jsonl") -> String {
        let quoted = String(decoding: try! JSONSerialization.data(withJSONObject: [command], options: [.withoutEscapingSlashes]), as: UTF8.self).dropFirst().dropLast()
        return #"{"session_id":"s","transcript_path":"\#(transcript)","cwd":"/Users/me/code/proj","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":\#(quoted),"description":"Print"},"permission_suggestions":\#(suggestions)}"#
    }

    private static func json(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // MARK: Parsing

    private static func parsing(_ suite: TestSuite) {
        suite.run("parsesBashRequest") {
            let request = ClaudeApprovalSupport.parseRequest(Data(payload().utf8))
            suite.expect(request?.toolName == "Bash" && request?.summary == "python3 -c 'print(42)'",
                         "a Bash request shows its command")
            suite.expect(request?.project == "proj" && request?.transcriptPath == "/tmp/t.jsonl",
                         "the project comes from cwd and the transcript path is kept")
            suite.expect(request?.canAlways == true, "addRules suggestions make Always available")
        }
        suite.run("parsesFileToolSummary") {
            let edit = #"{"hook_event_name":"PermissionRequest","cwd":"/a/b","tool_name":"Edit","tool_input":{"file_path":"/a/b/main.swift","old_string":"x","new_string":"y"}}"#
            suite.expect(ClaudeApprovalSupport.parseRequest(Data(edit.utf8))?.summary == "/a/b/main.swift",
                         "a file tool shows its path")
            let other = #"{"hook_event_name":"PermissionRequest","tool_name":"WebFetch","tool_input":{"url":"https://x.dev/a","prompt":"p"}}"#
            suite.expect(ClaudeApprovalSupport.parseRequest(Data(other.utf8))?.summary == #"{"prompt":"p","url":"https://x.dev/a"}"#,
                         "any other tool shows compact JSON of its input")
        }
        suite.run("rejectsMalformedJSON") {
            suite.expect(ClaudeApprovalSupport.parseRequest(Data("{nope".utf8)) == nil, "broken JSON is not a request")
        }
        suite.run("rejectsOtherHookEvent") {
            let event = payload().replacingOccurrences(of: "PermissionRequest", with: "PreToolUse")
            suite.expect(ClaudeApprovalSupport.parseRequest(Data(event.utf8)) == nil, "only PermissionRequest is shown")
            let noTool = #"{"hook_event_name":"PermissionRequest","tool_input":{}}"#
            suite.expect(ClaudeApprovalSupport.parseRequest(Data(noTool.utf8)) == nil, "a request needs a tool")
        }
        suite.run("rejectsNonObject") {
            suite.expect(ClaudeApprovalSupport.parseRequest(Data("[1,2]".utf8)) == nil, "an array is not a request")
        }
        suite.run("alwaysUnavailableWithoutSuggestions") {
            // The shape Claude Code sent for `touch` in a fresh folder.
            let session = #"[{"type":"addDirectories","directories":["/p"],"destination":"session"},{"type":"setMode","mode":"acceptEdits","destination":"session"}]"#
            suite.expect(ClaudeApprovalSupport.parseRequest(Data(payload(suggestions: session).utf8))?.canAlways == false,
                         "session-wide suggestions never become Always")
            suite.expect(ClaudeApprovalSupport.parseRequest(Data(payload(suggestions: "[]").utf8))?.canAlways == false,
                         "no suggestions, no Always")
        }
    }

    // MARK: Replies

    private static func replies(_ suite: TestSuite) {
        let request = ClaudeApprovalSupport.parseRequest(Data(payload().utf8))!
        func decision(_ choice: ClaudeApprovalDecision) -> [String: Any] {
            let output = json(ClaudeApprovalSupport.reply(choice, for: request))["hookSpecificOutput"] as? [String: Any]
            suite.expect(output?["hookEventName"] as? String == "PermissionRequest", "the reply names its event")
            return output?["decision"] as? [String: Any] ?? [:]
        }
        suite.run("encodesAllow") {
            let allow = decision(.allow)
            suite.expect(allow["behavior"] as? String == "allow" && allow.count == 1, "allow is just allow")
        }
        suite.run("encodesDeny") {
            let deny = decision(.deny)
            suite.expect(deny["behavior"] as? String == "deny" && deny["message"] as? String == "Denied in Vorssaint",
                         "deny tells the model where it was denied")
        }
        suite.run("encodesAlwaysEchoesSuggestions") {
            let always = decision(.always)
            let updates = always["updatedPermissions"] as? [[String: Any]]
            let rule = (updates?.first?["rules"] as? [[String: Any]])?.first
            suite.expect(always["behavior"] as? String == "allow" && updates?.count == 1
                         && updates?.first?["destination"] as? String == "localSettings"
                         && rule?["ruleContent"] as? String == "python3 -c 'print(42)'",
                         "always allows and sends the addRules suggestion as received")
        }
        suite.run("socketPathRejectsLongContainer") {
            suite.expect(ClaudeApprovalSupport.socketPath(container: URL(fileURLWithPath: "/Users/me/Library/Application Support/com.vorssaint.utils"))
                         == "/Users/me/Library/Application Support/com.vorssaint.utils/claude.sock", "a normal container fits")
            let long = URL(fileURLWithPath: "/" + String(repeating: "x", count: 92))
            suite.expect(ClaudeApprovalSupport.socketPath(container: long) == nil, "a path past sun_path is refused")
        }
    }

    // MARK: Transcript

    private static func toolUse(_ id: String, command: String = "python3 -c 'print(42)'") -> String {
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"\#(id)","name":"Bash","input":{"command":"\#(command)","description":"Print"}}]}}"#
    }

    private static func toolResult(_ id: String) -> String {
        #"{"type":"user","message":{"content":[{"tool_use_id":"\#(id)","type":"tool_result","content":"ok"}]}}"#
    }

    private static func transcript(_ suite: TestSuite) {
        let request = ClaudeApprovalSupport.parseRequest(Data(payload().utf8))!
        suite.run("transcriptSettlesOnMatchingResult") {
            var id: String?
            let before = [toolUse("old"), toolResult("old"), toolUse("other", command: "ls")].map { Substring($0) }
            suite.expect(!ClaudeApprovalSupport.scanTranscript(before, for: request, toolUseID: &id, counting: false) && id == nil,
                         "an identical command already answered is not this request")
            let after = [toolUse("new"), toolResult("other"), #"{"type":"assistant","message":{"content":[{"type":"text","text":"tool_use"}]}}"#]
                .map { Substring($0) }
            suite.expect(!ClaudeApprovalSupport.scanTranscript(after, for: request, toolUseID: &id, counting: true) && id == "new",
                         "another tool's result leaves the card up")
            suite.expect(ClaudeApprovalSupport.scanTranscript([Substring(toolResult("new"))], for: request, toolUseID: &id, counting: true),
                         "the request's own result settles it")
        }
    }

    // MARK: Service

    private final class Client {
        let fd: Int32
        init?(path: String) {
            fd = socket(AF_UNIX, SOCK_STREAM, 0)
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard result == 0 else { Darwin.close(fd); return nil }
        }
        deinit { Darwin.close(fd) }

        func send(_ text: String) {
            let bytes = Array(text.utf8)
            var offset = 0
            while offset < bytes.count {
                let count = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
                guard count > 0 else { return }
                offset += count
            }
        }

        /// Everything up to EOF, or nil if the app still holds the connection.
        func reply(within seconds: TimeInterval) -> Data? {
            var data = Data()
            let end = Date().addingTimeInterval(seconds)
            var buffer = [UInt8](repeating: 0, count: 4096)
            while Date() < end {
                var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                guard poll(&pollFD, 1, 20) > 0 else { continue }
                let count = read(fd, &buffer, buffer.count)
                if count <= 0 { return data }
                data.append(contentsOf: buffer[..<count])
            }
            return nil
        }
    }

    private static func waitFor(_ seconds: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cva-" + UUID().uuidString.prefix(8), isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func withService(_ body: (ClaudeApprovalService, URL) -> Void) {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = ClaudeApprovalService(socketPath: directory.appendingPathComponent("c.sock").path,
                                            settingsURL: directory.appendingPathComponent("settings.json"))
        service.start()
        body(service, directory)
        service.stop()
    }

    private static func service(_ suite: TestSuite) {
        suite.run("serviceAnswersOverSocket") {
            withService { service, _ in
                guard let client = Client(path: service.socketPath!) else { return suite.expect(false, "client connects") }
                client.send(payload() + "\n")
                suite.expect(waitFor { service.pending?.summary == "python3 -c 'print(42)'" }, "the request becomes the card")
                service.answer(.allow, to: service.pending!)
                let reply = client.reply(within: 2).map(json)
                suite.expect(((reply?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])?["behavior"] as? String == "allow",
                             "the answer reaches the relay and the connection closes")
                suite.expect(waitFor { service.pending == nil }, "answering clears the card")
            }
        }
        suite.run("serviceReleasesOnTimeout") {
            withService { service, _ in
                service.pendingSeconds = 0.2
                let client = Client(path: service.socketPath!)
                client?.send(payload() + "\n")
                suite.expect(waitFor { service.pending != nil }, "the request is shown")
                suite.expect(client?.reply(within: 2) == Data(), "the deadline closes without a decision")
                suite.expect(waitFor { service.pending == nil }, "and clears the card")
            }
        }
        suite.run("serviceReplacesPendingAndReleasesOld") {
            withService { service, _ in
                let first = Client(path: service.socketPath!)
                first?.send(payload(command: "one") + "\n")
                suite.expect(waitFor { service.pending?.summary == "one" }, "the first request is shown")
                let stale = service.pending!
                let second = Client(path: service.socketPath!)
                second?.send(payload(command: "two") + "\n")
                suite.expect(first?.reply(within: 2) == Data(), "the first goes back to its terminal at once")
                suite.expect(waitFor { service.pending?.summary == "two" }, "the second replaces it")
                service.answer(.allow, to: stale)
                suite.expect(second?.reply(within: 0.3) == nil, "an answer to the replaced card never reaches the new one")
            }
        }
        suite.run("serviceClearsPendingWhenClientCloses") {
            withService { service, _ in
                var client = Client(path: service.socketPath!)
                client?.send(payload() + "\n")
                suite.expect(waitFor { service.pending != nil }, "the request is shown")
                client = nil
                suite.expect(waitFor { service.pending == nil }, "a relay that exits clears the card")
            }
        }
        suite.run("serviceDropsOversizedPayload") {
            withService { service, _ in
                let client = Client(path: service.socketPath!)
                let big = String(repeating: "x", count: (4 << 20) + 1024)
                DispatchQueue.global().async { client?.send(big) }
                suite.expect(client?.reply(within: 5) == Data(), "a payload past the limit is closed unanswered")
                suite.expect(service.pending == nil, "and never shown")
                let junk = Client(path: service.socketPath!)
                junk?.send("not json\n")
                suite.expect(junk?.reply(within: 2) == Data(), "a malformed line is closed unanswered")
            }
        }
        suite.run("serviceReleasesOnStop") {
            withService { service, _ in
                let client = Client(path: service.socketPath!)
                client?.send(payload() + "\n")
                suite.expect(waitFor { service.pending != nil }, "the request is shown")
                service.stop()
                suite.expect(client?.reply(within: 2) == Data(), "stopping hands the request back")
                suite.expect(waitFor { service.pending == nil }, "and clears the card")
                suite.expect(Client(path: service.socketPath!) == nil, "the socket is gone")
            }
        }
        suite.run("serviceClearsWhenTerminalAnswers") {
            withService { service, directory in
                service.transcriptInterval = 0.05
                let transcript = directory.appendingPathComponent("t.jsonl")
                try? Data((toolUse("old") + "\n" + toolResult("old") + "\n").utf8).write(to: transcript)
                let client = Client(path: service.socketPath!)
                client?.send(payload(transcript: transcript.path) + "\n")
                suite.expect(waitFor { service.pending != nil }, "the request is shown")
                let handle = try? FileHandle(forWritingTo: transcript)
                _ = try? handle?.seekToEnd()
                handle?.write(Data((toolUse("new") + "\n").utf8))
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                suite.expect(service.pending != nil, "the tool_use alone keeps the card")
                handle?.write(Data((toolResult("new") + "\n").utf8))
                try? handle?.close()
                suite.expect(client?.reply(within: 2) == Data(), "the terminal's answer releases the relay")
                suite.expect(waitFor { service.pending == nil }, "and clears the card")
            }
        }
    }

    // MARK: Installer

    /// The Coucou block from a real settings file, the case coexistence has to survive.
    private static let coucou = #"""
    {
      "model": "opus",
      "hooks": {
        "PermissionRequest": [{"hooks": [{"type": "command", "command": "/Applications/Coucou.app/Contents/MacOS/nb-hook PermissionRequest"}]}],
        "Stop": [{"hooks": [{"type": "command", "command": "/Applications/Coucou.app/Contents/MacOS/nb-hook Stop"}]}]
      }
    }
    """#

    private static let command = ClaudeApprovalSupport.hookCommand(executable: "/Applications/Vorssaint.app/Contents/MacOS/Vorssaint",
                                                                   socket: "/Users/me/Library/Application Support/com.vorssaint.utils/claude.sock")

    private static func settings(_ text: String) -> [String: Any] {
        ClaudeApprovalSupport.parseSettings(Data(text.utf8)) ?? [:]
    }

    private static func installer(_ suite: TestSuite) {
        suite.run("installIntoEmptyFile") {
            let installed = ClaudeApprovalSupport.installing(settings("{}"), command: command)
            suite.expect(ClaudeApprovalSupport.installedCommand(in: installed) == command, "the entry is added")
            let entry = (((installed["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
            suite.expect(entry?["timeout"] as? Int == 120 && entry?["type"] as? String == "command" && (installed["hooks"] as? [String: Any])?.count == 1,
                         "with the 120 s timeout and no matcher")
        }
        suite.run("installIntoMissingFile") {
            suite.expect(ClaudeApprovalSupport.parseSettings(nil)?.isEmpty == true, "a missing file reads as empty")
            suite.expect(ClaudeApprovalSupport.status(of: nil, command: command) == .notInstalled, "and as not installed")
        }
        suite.run("installPreservesOtherToolsHooks") {
            let installed = ClaudeApprovalSupport.installing(settings(coucou), command: command)
            suite.expect(ClaudeApprovalSupport.foreignPermissionHooks(in: installed) == ["/Applications/Coucou.app/Contents/MacOS/nb-hook PermissionRequest"]
                         && installed["model"] as? String == "opus"
                         && ((installed["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 1,
                         "other tools' hooks and keys stay as they were")
        }
        suite.run("installReplacesOlderVorssaintEntry") {
            let old = ClaudeApprovalSupport.installing(settings(coucou), command: "'/Old/Vorssaint (Developer)' --claude-hook '/x.sock'")
            suite.expect(ClaudeApprovalSupport.status(of: ClaudeApprovalSupport.render(old), command: command) == .otherCopy,
                         "another copy's entry is recognised")
            let installed = ClaudeApprovalSupport.installing(old, command: command)
            let commands = ((installed["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?
                .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }
            suite.expect(commands?.filter(ClaudeApprovalSupport.isVorssaintHook) == [command], "only the current entry remains")
            suite.expect(ClaudeApprovalSupport.status(of: ClaudeApprovalSupport.render(installed), command: command) == .installed,
                         "and reads as installed")
        }
        suite.run("uninstallLeavesOthersEquivalent") {
            let original = settings(coucou)
            let round = ClaudeApprovalSupport.uninstalling(ClaudeApprovalSupport.installing(original, command: command))
            suite.expect(round as NSDictionary == original as NSDictionary, "install then uninstall gives back the same content")
        }
        suite.run("uninstallDropsEmptyContainers") {
            let round = ClaudeApprovalSupport.uninstalling(ClaudeApprovalSupport.installing(settings(#"{"model":"opus"}"#), command: command))
            suite.expect(round as NSDictionary == ["model": "opus"] as NSDictionary, "no empty hooks object is left behind")
        }
        suite.run("detectsForeignPermissionHooks") {
            suite.expect(ClaudeApprovalSupport.foreignPermissionHooks(in: settings(coucou)).count == 1, "Coucou's hook is listed")
            suite.expect(ClaudeApprovalSupport.status(of: Data("{".utf8), command: command) == .unreadable, "broken JSON is unreadable")
        }
        suite.run("hookCommandQuotesSpaces") {
            suite.expect(ClaudeApprovalSupport.hookCommand(executable: "/A B/Vorssaint (Developer)", socket: "/s/it's.sock")
                         == #"'/A B/Vorssaint (Developer)' --claude-hook '/s/it'\''s.sock'"#, "paths are shell-quoted")
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", ClaudeApprovalSupport.hookCommand(executable: "/bin/echo", socket: "/a b/it's.sock")]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()
            suite.expect(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "--claude-hook /a b/it's.sock\n",
                         "the shell hands both paths over intact")
        }
        suite.run("diffMarksAddedAndRemovedLines") {
            let lines = ClaudeApprovalSupport.diff("a\nb\nc", "a\nx\nc\nd")
            suite.expect(lines == [.init(kind: .same, text: "a"), .init(kind: .added, text: "x"), .init(kind: .removed, text: "b"),
                                   .init(kind: .same, text: "c"), .init(kind: .added, text: "d")],
                         "the diff keeps common lines and marks the rest: \(lines)")
        }
        suite.run("backupNameFormat") {
            let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 5, second: 7))!
            suite.expect(ClaudeApprovalSupport.backupName(date: date) == "settings.json.bak-20261001-090507", "the backup is dated")
        }
        suite.run("installWritesBackupInTempDir") {
            withService { service, directory in
                try? Data(coucou.utf8).write(to: service.settingsURL)
                let date = Date(timeIntervalSince1970: 1_790_000_000)
                suite.expect(service.writeSettings(installing: true, now: date), "the install is written")
                let backup = directory.appendingPathComponent(ClaudeApprovalSupport.backupName(date: date))
                suite.expect((try? Data(contentsOf: backup)) == Data(coucou.utf8), "the backup is byte for byte")
                suite.expect(ClaudeApprovalSupport.installedCommand(in: settings(String(decoding: try! Data(contentsOf: service.settingsURL), as: UTF8.self))) != nil,
                             "the file now has the entry")
                suite.expect(service.writeSettings(installing: false, now: date.addingTimeInterval(1)), "the removal is written")
                suite.expect(settings(String(decoding: try! Data(contentsOf: service.settingsURL), as: UTF8.self)) as NSDictionary
                             == settings(coucou) as NSDictionary, "and gives back the original content")
            }
        }
        suite.run("refusesUnparsableSettings") {
            withService { service, directory in
                try? Data("{ broken".utf8).write(to: service.settingsURL)
                suite.expect(!service.writeSettings(installing: true) && service.proposedSettings(installing: true) == nil,
                             "an unreadable file is refused")
                let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
                suite.expect(!files.contains { $0.hasPrefix("settings.json.bak") }
                             && (try? Data(contentsOf: service.settingsURL)) == Data("{ broken".utf8),
                             "nothing is backed up or written")
            }
        }
    }

    // MARK: Questions and plans

    private static func questionsAndPlans(_ suite: TestSuite) {
        let ask = ClaudeApprovalSupport.parseRequest(Data(askPayload.utf8))
        let plan = ClaudeApprovalSupport.parseRequest(Data(planPayload.utf8))
        func decision(_ choice: ClaudeApprovalDecision, _ request: ClaudeApprovalRequest) -> [String: Any] {
            let output = json(ClaudeApprovalSupport.reply(choice, for: request))["hookSpecificOutput"] as? [String: Any]
            return output?["decision"] as? [String: Any] ?? [:]
        }
        suite.run("parsesAskUserQuestion") {
            guard case .questions(let questions)? = ask?.kind else { return suite.expect(false, "AskUserQuestion becomes questions") }
            suite.expect(questions.count == 2 && questions[0].text == "Which color?" && questions[0].header == "Color"
                         && !questions[0].multiSelect && questions[1].multiSelect,
                         "each question keeps its text, header and selection mode")
            suite.expect(questions[0].options == [.init(label: "Red", description: "The color red"),
                                                  .init(label: "Blue", description: "The color blue")],
                         "options keep their label and description")
            let strings = #"{"hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Q","options":["A","B"]}]}}"#
            guard case .questions(let plain)? = ClaudeApprovalSupport.parseRequest(Data(strings.utf8))?.kind
            else { return suite.expect(false, "plain string options are accepted") }
            suite.expect(plain.first?.options.map(\.label) == ["A", "B"] && plain.first?.multiSelect == false,
                         "plain string options are accepted, single select by default")
        }
        suite.run("askUserQuestionWithoutQuestionsIsReleased") {
            for input in [#"{}"#, #"{"questions":[]}"#, #"{"questions":[{"question":"Q","options":[]}]}"#,
                          #"{"questions":[{"options":["A"]}]}"#] {
                let payload = #"{"hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":"# + input + "}"
                suite.expect(ClaudeApprovalSupport.parseRequest(Data(payload.utf8)) == nil,
                             "an unreadable question goes back to the terminal, never as JSON: \(input)")
            }
        }
        suite.run("parsesExitPlanMode") {
            guard case .plan(let text)? = plan?.kind else { return suite.expect(false, "ExitPlanMode becomes a plan") }
            suite.expect(text.hasPrefix("# Create hello file\n") && ClaudeApprovalSupport.planTitle(text) == "Create hello file",
                         "the plan keeps its text and its heading is the title")
            let blank = #"{"hook_event_name":"PermissionRequest","tool_name":"ExitPlanMode","tool_input":{"plan":"  \n"}}"#
            suite.expect(ClaudeApprovalSupport.parseRequest(Data(blank.utf8)) == nil, "a blank plan goes back to the terminal")
        }
        suite.run("planTitleFallsBackToFirstLine") {
            suite.expect(ClaudeApprovalSupport.planTitle("\n  Do the thing\nthen more") == "Do the thing", "no heading, first line")
            suite.expect(ClaudeApprovalSupport.planTitle("intro\n## Sub\n# Main") == "Main", "the first top heading wins")
            suite.expect(ClaudeApprovalSupport.planTitle("#\nbody") == "#", "an empty heading falls back to the line")
            suite.expect(ClaudeApprovalSupport.planTitle(" \n") == nil, "blank is nil")
        }
        suite.run("encodesAnswersAsUpdatedInput") {
            guard let ask, case .questions(let questions) = ask.kind else { return suite.expect(false, "fixture parses") }
            let answers = ClaudeApprovalSupport.answers(for: questions, chosen: [[1], [1, 0]], other: ["", " Medium "])
            suite.expect(answers == ["Which color?": "Blue", "Which sizes?": "Small, Large, Medium"],
                         "labels follow option order, then the typed text: \(answers ?? [:])")
            let allow = decision(.answers(answers ?? [:]), ask)
            let input = allow["updatedInput"] as? [String: Any]
            suite.expect(allow["behavior"] as? String == "allow"
                         && (input?["questions"] as? [Any])?.count == 2
                         && input?["answers"] as? [String: String] == answers,
                         "the questions go back with the answers, which Claude Code requires")
            let other = ClaudeApprovalSupport.answers(for: questions, chosen: [[], [0]], other: ["Green", ""])
            suite.expect(other?["Which color?"] == "Green", "Other text alone answers a single-select question")
        }
        suite.run("recommendedOptionDropsItsMarker") {
            let pick = ClaudeApprovalQuestion.Option(label: "Blue (Recommended)", description: nil)
            let plain = ClaudeApprovalQuestion.Option(label: "Red", description: nil)
            suite.expect(pick.isRecommended && pick.title == "Blue", "the marker becomes a star, not text")
            suite.expect(!plain.isRecommended && plain.title == "Red", "a plain label is unchanged")
        }
        suite.run("answersRequireEveryQuestion") {
            guard let ask, case .questions(let questions) = ask.kind else { return suite.expect(false, "fixture parses") }
            suite.expect(ClaudeApprovalSupport.answers(for: questions, chosen: [[0], []], other: ["", "  "]) == nil,
                         "a blank question keeps Answer unavailable")
            suite.expect(ClaudeApprovalSupport.answers(for: questions, chosen: [], other: []) == nil, "no state, no answer")
            suite.expect(!ClaudeApprovalSupport.accepts(.answers(["Which color?": "Red"]), for: ask),
                         "the service ignores answers that miss a question")
            suite.expect(ClaudeApprovalSupport.accepts(.answers(["Which color?": "Red", "Which sizes?": "Small"]), for: ask),
                         "and takes a full set")
        }
        suite.run("encodesApproveWithAcceptEdits") {
            guard let plan else { return suite.expect(false, "fixture parses") }
            let approve = decision(.allowAcceptingEdits, plan)
            let update = (approve["updatedPermissions"] as? [[String: Any]])?.first
            suite.expect(approve["behavior"] as? String == "allow" && update?["type"] as? String == "setMode"
                         && update?["mode"] as? String == "acceptEdits" && update?["destination"] as? String == "session",
                         "approve + accept edits switches the session mode")
            suite.expect(decision(.allow, plan).count == 1, "plain approve is just allow")
            suite.expect(!ClaudeApprovalSupport.accepts(.allowAcceptingEdits, for: ClaudeApprovalSupport.parseRequest(Data(payload().utf8))!),
                         "accept edits is only for a plan")
        }
        suite.run("encodesKeepPlanningDeny") {
            guard let plan else { return suite.expect(false, "fixture parses") }
            let deny = decision(.deny, plan)
            suite.expect(deny["behavior"] as? String == "deny"
                         && deny["message"] as? String == "Not approved in Vorssaint. Keep planning.",
                         "keep planning denies with its own message")
        }
        suite.run("approvalCardHeightByKind") {
            let bash = ClaudeApprovalSupport.parseRequest(Data(payload().utf8))!
            suite.expect(NotchAgentSupport.approvalCardHeight(for: bash) == 96, "a tool card keeps its height")
            suite.expect(plan.map(NotchAgentSupport.approvalCardHeight(for:)) == 240, "a plan has room to read")
            suite.expect(ask.map(NotchAgentSupport.approvalCardHeight(for:)) == 300, "two questions of two options clamp at 300, and the middle scrolls")
        }
        suite.run("serviceAnswersQuestions") {
            withService { service, _ in
                let client = Client(path: service.socketPath!)
                client?.send(askPayload + "\n")
                suite.expect(waitFor { service.pending != nil }, "the question is shown")
                service.answer(.answers(["Which color?": "Red", "Which sizes?": "Large"]), to: service.pending!)
                let reply = client?.reply(within: 2).map(json)
                let decision = (reply?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
                suite.expect((decision?["updatedInput"] as? [String: Any])?["answers"] as? [String: String]
                             == ["Which color?": "Red", "Which sizes?": "Large"], "the answers reach the relay")
            }
        }
        suite.run("serviceIgnoresDecisionForWrongKind") {
            withService { service, _ in
                let client = Client(path: service.socketPath!)
                client?.send(payload() + "\n")
                suite.expect(waitFor { service.pending != nil }, "the request is shown")
                service.answer(.answers(["x": "y"]), to: service.pending!)
                service.answer(.allowAcceptingEdits, to: service.pending!)
                suite.expect(client?.reply(within: 0.3) == nil && service.pending != nil,
                             "an answer meant for another card leaves this one up")
            }
        }
    }

    // MARK: Codex

    private static func codex(_ suite: TestSuite) {
        suite.run("parsesCodexBashRequest") {
            let request = ClaudeApprovalSupport.parseRequest(Data(codexPayload.utf8), agent: .codex)
            suite.expect(request?.agent == .codex && request?.toolName == "Bash" && request?.summary == "rm -rf build",
                         "a Codex Bash request shows its command")
            suite.expect(request?.canAlways == false && request?.transcriptPath == nil && request?.kind == .tool,
                         "with no Always and no transcript watch")
        }
        suite.run("parsesCodexRequestWithoutToolName") {
            let bare = #"{"hook_event_name":"PermissionRequest","cwd":"/a/proj","tool_input":{"command":"ls"}}"#
            let request = ClaudeApprovalSupport.parseRequest(Data(bare.utf8), agent: .codex)
            suite.expect(request?.toolName == "" && request?.summary == "ls", "Codex may leave the tool out")
            suite.expect(ClaudeApprovalSupport.parseRequest(Data(bare.utf8)) == nil, "Claude Code may not")
        }
        suite.run("codexQuestionNameIsPlainTool") {
            suite.expect(ClaudeApprovalSupport.parseRequest(Data(askPayload.utf8), agent: .codex)?.kind == .tool,
                         "Codex documents no AskUserQuestion, so the name means nothing special")
        }
        suite.run("serviceReadsCodexPrefix") {
            withService { service, _ in
                let client = Client(path: service.socketPath!)
                client?.send("codex " + codexPayload + "\n")
                suite.expect(waitFor { service.pending?.agent == .codex }, "the prefix marks a Codex request")
                service.answer(.always, to: service.pending!)
                suite.expect(client?.reply(within: 0.3) == nil, "Always never reaches Codex")
                service.answer(.allow, to: service.pending!)
                let reply = client?.reply(within: 2).map(json)
                suite.expect(((reply?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])?["behavior"] as? String == "allow",
                             "Allow reaches the relay")
                suite.expect(waitFor { service.pending == nil }, "and clears the card")
            }
        }
        let codexCommand = ClaudeApprovalSupport.hookCommand(executable: "/Applications/Vorssaint.app/Contents/MacOS/Vorssaint",
                                                             socket: "/s/claude.sock", agent: .codex)
        suite.run("codexCommandUsesCodexMarker") {
            suite.expect(codexCommand == "'/Applications/Vorssaint.app/Contents/MacOS/Vorssaint' --codex-hook '/s/claude.sock'",
                         "the Codex hook uses its own argument")
            suite.expect(ClaudeApprovalSupport.isVorssaintHook(codexCommand), "and is recognised as ours")
        }
        // The documented hooks.json shape, with another tool's Stop hook.
        let hooks = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"notify-send done","timeout":30}]}]}}"#
        suite.run("installIntoCodexHooksFile") {
            let original = settings(hooks)
            let installed = ClaudeApprovalSupport.installing(original, command: codexCommand)
            suite.expect(ClaudeApprovalSupport.installedCommand(in: installed) == codexCommand, "the entry is added")
            let entry = (((installed["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
            suite.expect(entry?["timeout"] as? Int == 120, "with the 120 s timeout")
            suite.expect(ClaudeApprovalSupport.uninstalling(installed) as NSDictionary == original as NSDictionary,
                         "removing gives back the same content")
        }
        suite.run("claudeMarkerInCodexFileReadsAsOtherCopy") {
            let wrong = ClaudeApprovalSupport.render(ClaudeApprovalSupport.installing(settings(hooks), command: command))
            suite.expect(ClaudeApprovalSupport.status(of: wrong, command: codexCommand) == .otherCopy,
                         "a Claude entry in hooks.json is offered as an update")
        }
        suite.run("backupNameUsesFileName") {
            let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9, minute: 5, second: 7))!
            suite.expect(ClaudeApprovalSupport.backupName(file: "hooks.json", date: date) == "hooks.json.bak-20261001-090507",
                         "the backup is named after its file")
        }
        suite.run("installWritesCodexBackupInTempDir") {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let codexURL = directory.appendingPathComponent(".codex/hooks.json")
            let service = ClaudeApprovalService(socketPath: directory.appendingPathComponent("c.sock").path,
                                                settingsURL: directory.appendingPathComponent("settings.json"),
                                                codexSettingsURL: codexURL)
            suite.expect(service.hookStatus(for: .codex) == .notInstalled, "a missing hooks.json reads as not installed")
            suite.expect(service.writeSettings(agent: .codex, installing: true), "the first install creates the file")
            suite.expect(service.hookStatus(for: .codex) == .installed && service.hookStatus(for: .claude) == .notInstalled,
                         "only Codex is installed")
            let date = Date(timeIntervalSince1970: 1_790_000_000)
            suite.expect(service.writeSettings(agent: .codex, installing: false, now: date), "the removal is written")
            let backup = codexURL.deletingLastPathComponent()
                .appendingPathComponent(ClaudeApprovalSupport.backupName(file: "hooks.json", date: date))
            suite.expect(FileManager.default.fileExists(atPath: backup.path), "next to a dated hooks.json backup")
            suite.expect(service.hookStatus(for: .codex) == .notInstalled, "and reads as removed")
        }
    }

    // MARK: Strings

    private static func strings(_ suite: TestSuite) {
        suite.run("approvalStringsFormatsInEveryLanguage") {
            for language in AppLanguage.allCases {
                let text = FeatureStrings.claudeApprovals(language)
                for format in [text.statusNotInstalledFormat, text.statusInstalledFormat, text.statusUnreadableFormat,
                               text.reviewTitleFormat, text.writeFailedFormat, text.requestLabelFormat,
                               text.questionLabelFormat, text.planLabelFormat, text.foreignHooksFormat] {
                    let conversions = TestFormat.parse(format)?.conversions
                    suite.expect(conversions == ["@"], "\(language.rawValue): \(format) takes one %@")
                }
                let values = Mirror(reflecting: text).children.compactMap { $0.value as? String }
                suite.expect(values.allSatisfy { !$0.isEmpty && !$0.contains("\u{2014}") },
                             "\(language.rawValue): no blank string and no em-dash")
            }
        }
    }
}
