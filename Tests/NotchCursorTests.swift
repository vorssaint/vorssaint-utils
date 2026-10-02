// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import os

enum NotchCursorTests {
    static func run(_ suite: TestSuite) {
        suite.run("cursor-hook") {
            protocolRules(suite)
            directories(suite)
            installedCopy(suite)
            server(suite)
            installer(suite)
            viewing(suite)
            controls(suite)
            polish(suite)
            quality(suite)
        }
    }

    private static func protocolRules(_ suite: TestSuite) {
        let shell = "beforeShellExecution"
        let poisoned = #"{"permission":"allow","pluginPaths":["/tmp"],"env":{"A":"1"},"updated_input":{"x":1}}"#
        let kept = CursorHookProtocol.allowlistedStdout(poisoned, hook: shell)
        suite.expect(kept == #"{"permission":"allow"}"#, "shell replies keep permission only, got \(kept)")
        suite.expect(CursorHookProtocol.allowlistedStdout(poisoned, hook: "workspaceOpen").isEmpty,
                     "observation replies stay empty")
        suite.expect(CursorHookProtocol.allowlistedStdout(#"{"followup_message":"next","env":{}}"#, hook: "stop")
                        == #"{"followup_message":"next"}"#,
                     "stop replies keep the follow-up only")
        suite.expect(CursorHookProtocol.fallbackStdout(hook: shell, failure: .unavailable, handBack: false)
                        == #"{"permission":"ask"}"#,
                     "a missing app hands a shell approval back to Cursor")
        suite.expect(CursorHookProtocol.fallbackStdout(hook: "preToolUse", failure: .unavailable, handBack: true).isEmpty,
                     "edit approvals cannot hand back")
        suite.expect(CursorHookProtocol.fallbackStdout(hook: shell, failure: .unanswered, handBack: false)
                        .contains(#""permission":"deny""#),
                     "an unanswered shell approval denies")
        suite.expect(CursorHookProtocol.replyWait(for: "postToolUse", override: nil) == nil,
                     "observation hooks do not wait")
        suite.expect(CursorHookProtocol.replyWait(for: "sessionStart", override: 30) == nil,
                     "a new chat does not wait on the socket")

        let email = #"{"prompt":"hello","user_email":"a@b.c","transcript_path":"/tmp/t","file_contents":"secret","content":"file body"}"#
        let trimmed = String(decoding: CursorHookProtocol.trim(payload: Data(email.utf8), hook: "beforeSubmitPrompt", hitStdinCap: false),
                              as: UTF8.self)
        suite.expect(!trimmed.contains("user_email") && !trimmed.contains("transcript_path")
                        && !trimmed.contains("secret") && !trimmed.contains("file body") && trimmed.contains("hello"),
                     "trimmed payloads drop mail, transcripts and file contents")

        let long = String(repeating: "p", count: CursorHookProtocol.promptCap + 8)
        let capped = CursorHookProtocol.trim(payload: Data(#"{"prompt":"\#(long)"}"#.utf8),
                                              hook: "beforeSubmitPrompt", hitStdinCap: false)
        let prompt = (try? JSONSerialization.jsonObject(with: capped) as? [String: Any])?["prompt"] as? String
        suite.expect(prompt?.utf8.count == CursorHookProtocol.promptCap, "prompts stop at 2 KB")

        let output = String(repeating: "o", count: CursorHookProtocol.shellTailBytes + 10)
        let tail = CursorHookProtocol.trim(payload: Data(#"{"output":"\#(output)"}"#.utf8),
                                            hook: "afterShellExecution", hitStdinCap: false)
        let keptOutput = (try? JSONSerialization.jsonObject(with: tail) as? [String: Any])?["output"] as? String
        suite.expect(keptOutput == String(output.suffix(CursorHookProtocol.shellTailBytes)),
                     "shell output keeps its last 8 KB")
        let intact = CursorHookProtocol.trim(payload: Data(#"{"command":"ls","output":"hi"}"#.utf8),
                                              hook: "afterShellExecution", hitStdinCap: true)
        let intactText = String(decoding: intact, as: UTF8.self)
        suite.expect(intactText.contains("ls") && intactText.contains("truncated"),
                     "a readable shell payload keeps its command when the read hits the cap")
        let edit = String(repeating: "e", count: CursorHookProtocol.editCap + 4)
        let edits = CursorHookProtocol.trim(payload: Data(#"{"edits":[{"old_string":"\#(edit)","new_string":"n"}]}"#.utf8),
                                             hook: "afterFileEdit", hitStdinCap: false)
        let editText = String(decoding: edits, as: UTF8.self)
        suite.expect(!editText.contains(edit) && editText.contains("truncated"),
                     "an edit keeps at most 16 KB of each side")

        let home = "/Users/" + String(repeating: "n", count: 80)
        let preferred = CursorHookProtocol.preferredSocketPath(home: home, bundleIdentifier: "com.vorssaint.utils")
        suite.expect(preferred.utf8.count > CursorHookProtocol.sunPathLimit, "the long home is over the socket limit")
        suite.expect(CursorHookProtocol.resolveSocketPath(preferred: preferred, uid: 501) == "/tmp/vorssaint-501/cursor.sock",
                     "a path that does not fit uses the per-user folder")
        suite.expect(!CursorHookProtocol.peerBelongsToCurrentUser(.max) || getuid() == .max,
                     "another user's socket peer is refused")
        suite.expect(CursorHookProtocol.source(ancestorPaths: ["/Applications/Cursor.app/Contents/MacOS/Cursor"]) == "app",
                     "a Cursor ancestor is the app")
        suite.expect(CursorHookProtocol.source(ancestorPaths: ["/Applications/iTerm.app/Contents/MacOS/iTerm2"]) == "terminal",
                     "anything else is the terminal")
    }

    private static func directories(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-cursor-dir-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        suite.expect(CursorHookProtocol.createOwnerOnlyDirectory(root.path), "an owner-only folder can be created")
        var info = stat()
        suite.expect(lstat(root.path, &info) == 0 && (info.st_mode & mode_t(0o077)) == 0,
                     "the folder is not readable by other accounts")
        _ = chmod(root.path, 0o755)
        suite.expect(CursorHookProtocol.createOwnerOnlyDirectory(root.path), "a loose folder we own is tightened")
        suite.expect(CursorHookProtocol.directoryIsOwnerOnly(root.path, uid: getuid()),
                     "the tightened folder stays owner-only")
    }

    private static func installedCopy(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-cursor-copy-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("CursorHook/vorssaint-cursor-hook")
        defer { try? FileManager.default.removeItem(at: root) }
        suite.expect(signedCopy(of: URL(fileURLWithPath: "/bin/echo"), to: source),
                     "a throwaway signed helper can be prepared")
        suite.expect(!CursorHookInstall.refresh(bundled: source, installed: destination),
                     "a launch does not create a helper that was never connected")
        suite.expect(CursorHookInstall.install(bundled: source, installed: destination),
                     "Connect copies a signed helper")
        suite.expect(CursorHookInstall.refresh(bundled: source, installed: destination),
                     "an unchanged helper is left in place")
        var info = stat()
        let mode = lstat(destination.path, &info) == 0 ? info.st_mode & mode_t(0o777) : 0
        suite.expect(mode == 0o755, "the installed helper is executable by its owner, got \(String(mode, radix: 8))")
        _ = chmod(destination.path, 0o644)
        suite.expect(CursorHookInstall.refresh(bundled: source, installed: destination),
                     "a matching helper is repaired")
        let repaired = lstat(destination.path, &info) == 0 ? info.st_mode & mode_t(0o777) : 0
        suite.expect(repaired == 0o755, "a matching helper stays executable, got \(String(repaired, radix: 8))")
    }

    private static func signedCopy(of source: URL, to destination: URL) -> Bool {
        do { try FileManager.default.copyItem(at: source, to: destination) } catch { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func server(_ suite: TestSuite) {
        let directory = URL(fileURLWithPath: "/tmp/vorssaint-cursor-\(getpid())", isDirectory: true)
        let socketPath = directory.appendingPathComponent("hook.sock").path
        defer { try? FileManager.default.removeItem(at: directory) }
        suite.expect(CursorHookProtocol.createOwnerOnlyDirectory(directory.path), "the socket folder exists")

        let server = CursorHookServer()
        let overflow = CursorHookReply(stdout: #"{"permission":"deny","agent_message":"queue"}"#, exitCode: 0)
        let stopped = CursorHookReply(stdout: #"{"permission":"deny","agent_message":"stopped"}"#, exitCode: 0)
        let started = server.start(CursorHookServerConfiguration(
            socketPath: socketPath,
            maxConnections: 4,
            maxHeldApprovals: 1,
            overflowReply: overflow,
            stopReply: stopped,
            decide: { message in
                message.hook == "beforeShellExecution" ? nil : CursorHookReply.empty
            }
        ))
        suite.expect(started, "the server listens")
        var info = stat()
        suite.expect(lstat(socketPath, &info) == 0 && (info.st_mode & S_IFMT) == S_IFSOCK
                        && (info.st_mode & mode_t(0o077)) == 0,
                     "the socket is owner-only")

        guard let line = CursorHookProtocol.encodeRequest(hook: "postToolUse", source: "app", remote: false,
                                                           payload: Data("{}".utf8)) else {
            suite.expect(false, "an observation request encodes")
            return
        }
        let observation = CursorHookClient.send(line: line, path: socketPath, wait: 1)
        if case .reply(let reply) = observation {
            suite.expect(reply.stdout.isEmpty, "an observation is acknowledged with an empty reply")
        } else {
            suite.expect(false, "an observation received a reply, got \(observation)")
        }

        guard let approval = CursorHookProtocol.encodeRequest(hook: "beforeShellExecution", source: "terminal",
                                                               remote: false, payload: Data(#"{"command":"ls"}"#.utf8)) else {
            suite.expect(false, "an approval request encodes")
            return
        }
        let first = DispatchSemaphore(value: 0)
        let firstReply = OSAllocatedUnfairLock<CursorHookExchange?>(initialState: nil)
        DispatchQueue.global().async {
            let reply = CursorHookClient.send(line: approval, path: socketPath, wait: 2)
            firstReply.withLock { $0 = reply }
            first.signal()
        }
        let deadline = Date().addingTimeInterval(2)
        while server.heldApprovals() == 0, deadline.timeIntervalSinceNow > 0 {
            Thread.sleep(forTimeInterval: 0.02)
        }
        suite.expect(server.heldApprovals() == 1, "one approval is held")
        let second = CursorHookClient.send(line: approval, path: socketPath, wait: 1)
        if case .reply(let reply) = second {
            suite.expect(reply.stdout.contains("queue"), "the extra approval is answered immediately")
        } else {
            suite.expect(false, "the extra approval got \(second)")
        }
        server.stop()
        _ = first.wait(timeout: .now() + 2)
        if case .reply(let reply) = firstReply.withLock({ $0 }) {
            suite.expect(reply.stdout.contains("stopped"), "stopping answers the held approval")
        } else {
            suite.expect(false, "the held approval got \(String(describing: firstReply.withLock { $0 }))")
        }

        let rejected = CursorHookServer()
        suite.expect(rejected.start(CursorHookServerConfiguration(socketPath: socketPath, decide: { _ in .empty })),
                     "a fresh server replaces its own stale socket")
        guard let flood = CursorHookSocket.address(socketPath) else {
            suite.expect(false, "the replacement socket has an address")
            rejected.stop()
            return
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let connected = flood.storage.withSockAddr { Darwin.connect(fd, $0, $1) }
        suite.expect(fd >= 0 && connected == 0, "a same-user client can connect")
        var oversized = Data(repeating: 0x61, count: CursorHookProtocol.maxAcceptedBytes + 8)
        oversized.append(0x0A)
        _ = CursorHookSocket.writeAll(fd: fd, data: oversized)
        let read = CursorHookSocket.readLine(fd: fd, maxBytes: 64, timeout: 1)
        suite.expect(read == .closed || read == .tooLarge, "a request over 1 MB is rejected, got \(read)")
        _ = Darwin.close(fd)
        rejected.stop()
    }

    private static func installer(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: "/tmp/vorssaint-hooks-\(getpid())")
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("hooks.json")
        let helper = "/tmp/vorssaint helper/vorssaint-cursor-hook"
        let quoted = CursorHookInstaller.helperPath(in: "\"/tmp/vorssaint helper/vorssaint-cursor-hook\" beforeShellExecution --wait=1")
        suite.expect(quoted == "/tmp/vorssaint helper/vorssaint-cursor-hook", "a quoted helper path is recognised")
        let foreign = "/Applications/Other.app/Contents/Helpers/vorssaint-cursor-hook"
        suite.expect(CursorHookInstaller.isForeignVorssaintHelper(foreign, helperPath: helper),
                     "another Vorssaint helper is a different copy")
        suite.expect(!CursorHookInstaller.isForeignVorssaintHelper("/bin/echo", helperPath: helper),
                     "someone else's command is left alone")

        let defaults = UserDefaults(suiteName: "com.vorssaint.tests.cursor-hooks")!
        defer { defaults.removePersistentDomain(forName: "com.vorssaint.tests.cursor-hooks") }
        defaults.set(false, forKey: DefaultsKey.notchCursorApprovals)
        defaults.set(60, forKey: DefaultsKey.notchCursorApprovalTimeout)
        defaults.set(CursorNotchApprovalFallback.deny.rawValue, forKey: DefaultsKey.notchCursorApprovalFallback)
        defaults.set(false, forKey: DefaultsKey.notchCursorApproveEdits)
        defaults.set(0, forKey: DefaultsKey.notchCursorHoldForReply)
        let desired = CursorHookInstaller.desiredEntries(helperPath: helper, defaults: defaults)
        let shell = desired.first { $0.event == "beforeShellExecution" }
        suite.expect(shell?.command.contains("--wait=1") == true && shell?.command.contains("--fallback=ask") == true,
                     "shell hooks stay short and hand back while approvals are off")
        suite.expect(desired.first { $0.event == "sessionStart" }?.command.contains("--wait=") == false,
                     "a new chat does not wait")
        suite.expect(desired.first { $0.event == "stop" }?.loopLimit == 1
                        && desired.allSatisfy { $0.event == "stop" || $0.loopLimit == nil },
                     "only the stop hook follows up, and only once")
        suite.expect(CursorHookInstaller.settingsSignature(in: defaults).hasSuffix("|loop"),
                     "a confirmed install rewrites once to add the follow-up limit")
        suite.expect(desired.first { $0.event == "preToolUse" }?.matcher == "Write|Delete"
                        && desired.first { $0.event == "preToolUse" }?.command.contains("--fallback") == false,
                     "edit hooks match Write and Delete only")
        suite.expect(desired.first { $0.event == "stop" }?.command.contains("--wait=1") == true,
                     "a follow-up does not block when hold is off")
        suite.expect(desired.allSatisfy { !$0.failClosed },
                     "observation entries stay fail-open while approvals are off")
        suite.expect(desired.first { $0.event == "beforeShellExecution" }?.timeout == CursorHookInstaller.observationTimeout
                        && desired.first { $0.event == "sessionStart" }?.timeout == CursorHookInstaller.observationTimeout,
                     "hooks stay at the short timeout while approvals are off")
        defaults.set(true, forKey: DefaultsKey.notchCursorApprovals)
        defaults.set(true, forKey: DefaultsKey.notchCursorApproveEdits)
        let approving = CursorHookInstaller.desiredEntries(helperPath: helper, defaults: defaults)
        suite.expect(approving.first { $0.event == "beforeShellExecution" }?.failClosed == true
                        && approving.first { $0.event == "beforeMCPExecution" }?.failClosed == true
                        && approving.first { $0.event == "preToolUse" }?.failClosed == true
                        && approving.first { $0.event == "sessionStart" }?.failClosed == false,
                     "only approval entries deny when the hook crashes")
        suite.expect(approving.first { $0.event == "beforeShellExecution" }?.timeout == 75
                        && approving.first { $0.event == "preToolUse" }?.timeout == 75
                        && approving.first { $0.event == "stop" }?.timeout == CursorHookInstaller.observationTimeout,
                     "an approval hook waits 15 seconds past a 60-second card")
        defaults.set(120, forKey: DefaultsKey.notchCursorHoldForReply)
        let held = CursorHookInstaller.desiredEntries(helperPath: helper, defaults: defaults)
        suite.expect(held.first { $0.event == "stop" }?.timeout == 130,
                     "hold for reply gives the stop hook ten extra seconds")
        defaults.set(0, forKey: DefaultsKey.notchCursorHoldForReply)
        defaults.set(false, forKey: DefaultsKey.notchCursorApprovals)
        defaults.set(false, forKey: DefaultsKey.notchCursorApproveEdits)

        let original = """
        {"version":1,"extra":true,"hooks":{"sessionStart":[{"type":"prompt","prompt":"keep me"},{"command":"/bin/echo hi"}]}}
        """
        try? original.write(to: file, atomically: true, encoding: .utf8)
        guard case .success(let preview) = CursorHookInstaller.preview(file: file, helperPath: helper,
                                                                       desired: desired, replaceOtherCopies: false) else {
            suite.expect(false, "the preview can be built")
            return
        }
        let extra = preview.range(of: "\"extra\"")
        let hooks = preview.range(of: "\"hooks\"")
        suite.expect(extra != nil && hooks != nil && extra!.upperBound < hooks!.lowerBound,
                     "unknown top-level keys stay ahead of hooks")
        let prompt = preview.range(of: "keep me")
        let ours = preview.range(of: helper)
        suite.expect(prompt != nil && ours != nil && prompt!.upperBound < ours!.lowerBound,
                     "a prompt hook stays ahead of our entry")
        let edited = original.replacingOccurrences(of: "\"extra\":true", with: "\"extra\":false,\"note\":\"after\"")
        try? edited.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        guard case .success = CursorHookInstaller.apply(file: file, helperPath: helper, desired: desired,
                                                        replaceOtherCopies: false, backup: true) else {
            suite.expect(false, "the merge can be saved")
            return
        }
        let saved = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        suite.expect(saved.contains("\"note\": \"after\"") || saved.contains("\"note\":\"after\""),
                     "the write re-reads the file instead of the preview")
        suite.expect(saved.contains("keep me") && saved.contains("/bin/echo hi") && saved.contains(helper),
                     "other hooks and our helper are both saved")
        suite.expect(!saved.contains("failClosed"), "failClosed stays off")
        let approvalsFile = root.appendingPathComponent("approvals.json")
        guard case .success = CursorHookInstaller.apply(file: approvalsFile, helperPath: helper, desired: approving,
                                                        replaceOtherCopies: false, backup: false) else {
            suite.expect(false, "approval entries can be saved")
            return
        }
        let approvalsSaved = (try? String(contentsOf: approvalsFile, encoding: .utf8)) ?? ""
        suite.expect(approvalsSaved.contains("\"failClosed\": true"),
                     "approval entries deny when the hook crashes")
        suite.expect(CursorHookInstaller.status(file: approvalsFile, helperPath: helper, desired: approving) == .installed,
                     "failClosed is part of a matching entry")
        var mode = stat()
        _ = lstat(file.path, &mode)
        suite.expect((mode.st_mode & 0o777) == 0o640, "an existing file keeps its mode, got \(mode.st_mode & 0o777)")
        suite.expect(CursorHookInstaller.status(file: file, helperPath: helper, desired: desired) == .installed,
                     "matching entries are installed")

        let link = root.appendingPathComponent("link.json")
        _ = symlink(file.path, link.path)
        if case .failure = CursorHookInstaller.apply(file: link, helperPath: helper, desired: desired,
                                                     replaceOtherCopies: false, backup: false) {
            suite.expect(true, "a symlink is refused")
        } else {
            suite.expect(false, "a symlink is refused")
        }
        suite.expect(CursorHookInstaller.status(file: link, helperPath: helper, desired: desired) == .unreadable,
                     "a symlink is unreadable")

        let broken = root.appendingPathComponent("broken.json")
        try? "{".write(to: broken, atomically: true, encoding: .utf8)
        suite.expect(CursorHookInstaller.status(file: broken, helperPath: helper, desired: desired) == .unreadable,
                     "a file that does not parse is unreadable")
        let newer = root.appendingPathComponent("newer.json")
        try? #"{"version":2,"hooks":{}}"#.write(to: newer, atomically: true, encoding: .utf8)
        suite.expect(CursorHookInstaller.status(file: newer, helperPath: helper, desired: desired) == .unreadable,
                     "version 2 is refused")

        let mixed = root.appendingPathComponent("mixed.json")
        let mixedBody = """
        {"version":1,"hooks":{"sessionStart":[{"command":"\(foreign)","timeout":10}]}}
        """
        try? mixedBody.write(to: mixed, atomically: true, encoding: .utf8)
        suite.expect(CursorHookInstaller.otherCopyPaths(file: mixed, helperPath: helper) == [foreign],
                     "another Vorssaint copy is reported")
        _ = CursorHookInstaller.apply(file: mixed, helperPath: helper, desired: desired,
                                     replaceOtherCopies: false, backup: false)
        _ = CursorHookInstaller.uninstall(file: mixed, helperPath: helper)
        let after = (try? String(contentsOf: mixed, encoding: .utf8)) ?? ""
        suite.expect(!after.contains(helper) && after.contains("Other.app"),
                     "uninstall removes only our entries")
        suite.expect(CursorHookInstaller.status(file: mixed, helperPath: helper, desired: desired) == .notInstalled,
                     "our entries are gone")
        try? mixedBody.write(to: mixed, atomically: true, encoding: .utf8)
        _ = CursorHookInstaller.apply(file: mixed, helperPath: helper, desired: desired,
                                     replaceOtherCopies: true, backup: false)
        let replaced = (try? String(contentsOf: mixed, encoding: .utf8)) ?? ""
        suite.expect(!replaced.contains("Other.app") && replaced.contains(helper),
                     "confirming the warning replaces the other copy")

        let created = root.appendingPathComponent("fresh.json")
        guard case .success = CursorHookInstaller.apply(file: created, helperPath: helper, desired: desired,
                                                        replaceOtherCopies: false, backup: true) else {
            suite.expect(false, "a missing file can be created")
            return
        }
        var createdMode = stat()
        _ = lstat(created.path, &createdMode)
        suite.expect((createdMode.st_mode & 0o777) == 0o600, "a new hooks file is owner-only")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        suite.expect(!names.contains { $0.contains(".bak-") && $0.hasPrefix("fresh.json") },
                     "creating a file does not invent a backup")
        for _ in 0..<6 {
            _ = CursorHookInstaller.apply(file: created, helperPath: helper, desired: desired,
                                         replaceOtherCopies: false, backup: true)
        }
        let backups = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { $0.hasPrefix("fresh.json.bak-") }
        suite.expect(backups.count == 5, "only the last 5 backups are kept, got \(backups.count)")
        let beforeSilent = backups.count
        _ = CursorHookInstaller.apply(file: created, helperPath: helper, desired: desired,
                                     replaceOtherCopies: false, backup: false)
        let afterSilent = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { $0.hasPrefix("fresh.json.bak-") }
        suite.expect(afterSilent.count == beforeSilent, "a silent rewrite does not add a backup")
    }

    private static func viewing(_ suite: TestSuite) {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/cursor-hooks/beforeShellExecution.json")
        let fixtureData = (try? Data(contentsOf: fixtureURL)) ?? Data()
        let fixture = CursorHookDecoder.decode(CursorHookMessage(version: 1, hook: "beforeShellExecution",
                                                                  source: "app", remote: false, payload: fixtureData))
        suite.expect(fixture?.command == "echo phase0" && fixture?.cwd == "" && fixture?.sandbox == false
                        && fixture?.cursorVersion == "3.23.12" && fixture?.model == "example"
                        && fixture?.roots == ["/example/project"],
                     "the live shell fixture keeps the fields the page shows")
        suite.expect(CursorHookDecoder.decode(CursorHookMessage(version: 1, hook: "stop", source: "app",
                                                                remote: false, payload: Data("[]".utf8))) == nil,
                     "a payload that is not an object is dropped")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var store = CursorSessionStore()
        let started = reduce(&store, hook: "sessionStart", payload: [
            "conversation_id": "chat",
            "composer_mode": "multitask",
            "workspace_roots": ["/work/vorssaint-utils"],
            "is_background_agent": true,
        ], now: now)
        let session = started.store.sessions.first
        suite.expect(session?.project == "vorssaint-utils" && session?.mode == "multitask" && session?.background == true
                        && session?.state == .idle,
                     "a new chat takes its project, mode and background badge")

        _ = reduce(&store, hook: "beforeSubmitPrompt", payload: [
            "conversation_id": "chat", "prompt": "hello", "generation_id": "gen-1",
        ], now: now.addingTimeInterval(1))
        _ = reduce(&store, hook: "afterAgentThought", payload: [
            "conversation_id": "chat", "generation_id": "gen-1", "text": "hmm", "duration_ms": 12,
        ], now: now.addingTimeInterval(2))
        _ = reduce(&store, hook: "afterAgentResponse", payload: [
            "conversation_id": "chat", "generation_id": "gen-1", "text": "done",
            "input_tokens": 3, "output_tokens": 4,
        ], now: now.addingTimeInterval(3))
        suite.expect(store.sessions[0].thought == "hmm" && store.sessions[0].reply == "done"
                        && store.sessions[0].tokens.input == 3,
                     "thought, reply and tokens land on the chat")
        _ = reduce(&store, hook: "beforeSubmitPrompt", payload: [
            "conversation_id": "chat", "prompt": "next", "generation_id": "gen-2",
        ], now: now.addingTimeInterval(4))
        suite.expect(store.sessions[0].thought == nil && store.sessions[0].reply == nil
                        && store.sessions[0].tokens.isEmpty && store.sessions[0].prompt == "next",
                     "a new generation clears the previous thought and reply")

        _ = reduce(&store, hook: "preToolUse", payload: [
            "conversation_id": "chat", "tool_name": "Read", "tool_use_id": "read-1",
            "tool_input": ["file_path": "Sources/App.swift"],
        ], now: now.addingTimeInterval(5))
        suite.expect(store.sessions[0].state == .reading && store.sessions[0].steps.last?.label == .read("App.swift"),
                     "a read is labeled with the file name")
        _ = reduce(&store, hook: "postToolUseFailure", payload: [
            "conversation_id": "chat", "tool_use_id": "read-1", "failure_type": "permission_denied",
        ], now: now.addingTimeInterval(6))
        suite.expect(store.sessions[0].steps.last?.status == .denied, "a permission failure is denied, not a crash")
        _ = reduce(&store, hook: "postToolUseFailure", payload: [
            "conversation_id": "chat", "tool_name": "Write", "tool_use_id": "write-1", "is_interrupt": true,
        ], now: now.addingTimeInterval(7))
        suite.expect(store.sessions[0].steps.last?.status == .stopped, "an interrupt stops the step")

        _ = reduce(&store, hook: "beforeShellExecution", payload: [
            "conversation_id": "chat", "command": "echo phase0", "sandbox": true,
        ], now: now.addingTimeInterval(8))
        _ = reduce(&store, hook: "afterShellExecution", payload: [
            "conversation_id": "chat", "command": "echo phase0", "output": "phase0",
            "duration": 15, "duration_ms": 999, "sandbox": true,
        ], now: now.addingTimeInterval(9))
        let shell = store.sessions[0].steps.last
        suite.expect(shell?.output == "phase0" && shell?.durationMS == 15 && shell?.sandbox == true,
                     "shell timing uses duration, and the tail stays on that step")

        _ = reduce(&store, hook: "afterFileEdit", payload: [
            "conversation_id": "chat", "file_path": "Sources/App.swift",
            "edits": [["old_string": "a", "new_string": "b\nc", "truncated": true]],
        ], now: now.addingTimeInterval(10))
        suite.expect(store.sessions[0].edits.first?.added == 2 && store.sessions[0].edits.first?.removed == 1
                        && store.sessions[0].edits.first?.truncated == true,
                     "an edit keeps plus and minus counts and the truncated badge")

        _ = reduce(&store, hook: "subagentStart", payload: [
            "conversation_id": "child", "parent_conversation_id": "chat", "subagent_type": "explore",
            "task": "look",
        ], now: now.addingTimeInterval(11))
        suite.expect(store.sessions.count == 1 && store.sessions[0].subagents.first?.task == "look"
                        && store.sessions[0].state == .subagent,
                     "a subagent stays on the parent chat")

        _ = reduce(&store, hook: "preCompact", payload: [
            "conversation_id": "chat", "context_usage_percent": 80, "context_tokens": 8,
            "context_window_size": 10,
        ], now: now.addingTimeInterval(12))
        suite.expect(store.sessions[0].context?.percent == 80 && store.sessions[0].context?.window == 10,
                     "compaction reports the context meter")

        let finished = reduce(&store, hook: "stop", payload: [
            "conversation_id": "chat", "status": "completed",
        ], now: now.addingTimeInterval(20))
        suite.expect(finished.store.sessions[0].state == .done && finished.notices.first?.kind == .finished,
                     "a completed turn finishes and asks for a notice")
        let again = reduce(&store, hook: "sessionEnd", payload: [
            "conversation_id": "chat", "reason": "completed", "duration_ms": 1000,
        ], now: now.addingTimeInterval(21))
        suite.expect(again.notices.isEmpty, "ending a chat that already finished does not notice twice")

        var held = CursorSessionStore()
        _ = reduce(&held, hook: "beforeShellExecution", payload: [
            "conversation_id": "one", "command": "ls",
        ], now: now, holdApprovals: true)
        let needs = reduce(&held, hook: "beforeShellExecution", payload: [
            "conversation_id": "two", "command": "pwd",
        ], now: now, holdApprovals: true)
        suite.expect(held.sessions.allSatisfy { $0.state == .waiting } && needs.notices.contains { $0.kind == .needsYou },
                     "two held approvals say the person is needed")

        var crowded = CursorSessionStore()
        for index in 0..<51 {
            _ = reduce(&crowded, hook: "preToolUse", payload: [
                "conversation_id": "chat", "tool_name": "Read", "tool_use_id": "t-\(index)",
                "tool_input": ["path": "f\(index)"],
            ], now: now.addingTimeInterval(TimeInterval(index)))
        }
        suite.expect(crowded.sessions[0].steps.count == 50 && crowded.sessions[0].steps.first?.id == "t-1",
                     "a chat keeps the latest 50 steps")

        var many = CursorSessionStore()
        for index in 0..<21 {
            _ = reduce(&many, hook: "stop", payload: [
                "conversation_id": "c\(index)", "status": "completed", "workspace_roots": ["/r\(index)"],
            ], now: now.addingTimeInterval(TimeInterval(index)))
        }
        suite.expect(many.sessions.count == 20 && !many.sessions.contains { $0.id == "c0" },
                     "the oldest finished chat leaves when the list is full")

        var quiet = CursorSessionStore()
        _ = reduce(&quiet, hook: "beforeSubmitPrompt", payload: [
            "conversation_id": "chat", "prompt": "hi",
        ], now: now)
        quiet = CursorSessionReducer.tick(quiet, now: now.addingTimeInterval(10 * 60))
        suite.expect(quiet.sessions[0].state == .quiet, "ten quiet minutes replace a working chat")
        var ended = CursorSessionReducer.cursorQuit(quiet, now: now.addingTimeInterval(11 * 60))
        suite.expect(ended.sessions[0].endedAt != nil, "Cursor quitting ends the chat")
        ended = CursorSessionReducer.tick(ended, now: now.addingTimeInterval(11 * 60 + 60 * 60))
        suite.expect(ended.sessions.isEmpty, "a finished chat leaves after an hour")

        var asleep = CursorSessionStore()
        _ = reduce(&asleep, hook: "afterAgentThought", payload: [
            "conversation_id": "chat", "text": "still",
        ], now: now)
        asleep = CursorSessionReducer.wake(asleep, now: now.addingTimeInterval(10 * 60))
        suite.expect(asleep.sessions[0].state == .quiet, "waking quiets a chat that went stale during sleep")

        var remoteStore = CursorSessionStore()
        let remote = reduce(&remoteStore, hook: "sessionStart", payload: [
            "conversation_id": "far", "workspace_roots": ["/local/exists"],
        ], now: now, remote: true)
        suite.expect(remote.store.sessions[0].remote, "a remote flag stays remote even when the path looks local")

        suite.expect(CursorNoticePolicy.include(CursorNoticeFacts(kind: .finished, project: "p", files: 0,
                                                                   commands: 0, failures: 0, duration: 1, waiting: 0),
                                                 finishAlerts: true, failureAlerts: true, minimumSeconds: 30,
                                                 cursorIsFrontmost: false, quietWhenFocused: false) == false,
                     "a short finish stays under the minimum")
        suite.expect(CursorNoticePolicy.include(CursorNoticeFacts(kind: .needsYou, project: "p", files: 0,
                                                                   commands: 0, failures: 0, duration: 0, waiting: 2),
                                                 finishAlerts: false, failureAlerts: false, minimumSeconds: 0,
                                                 cursorIsFrontmost: true, quietWhenFocused: true),
                     "needing the user is not quieted while Cursor is in front")
        let diff = CursorLineDiff.lines(old: "a\nb", new: "b\nc")
        suite.expect(diff.lines.contains { $0.sign == "+" && $0.text == "c" }
                        && diff.lines.contains { $0.sign == "-" && $0.text == "a" },
                     "the line diff uses insertions and removals")
        suite.expect(CursorSessionReducer.isCursorApp(bundleIdentifier: "com.todesktop.230313mzl4w4u92", name: nil),
                     "the stable Cursor bundle ends sessions")
    }

    private static func controls(_ suite: TestSuite) {
        suite.expect(CursorApprovalRules.decision(command: "git status", allow: ["git"], deny: ["git push"]) == .allow,
                     "an allow prefix runs the command")
        suite.expect(CursorApprovalRules.decision(command: "git push origin", allow: ["git"], deny: ["git push"]) == .deny,
                     "deny beats a shorter allow")
        suite.expect(CursorApprovalRules.decision(command: "git push --force", allow: ["git push"], deny: []) == .hold,
                     "a risky command still asks when an allow rule matches")
        suite.expect(CursorApprovalRules.decision(command: "echo hi", allow: [], deny: []) == .hold,
                     "a command with no rule waits for the person")
        suite.expect(CursorProtectedPaths.includes("src/.env.local", globs: [".env*"]),
                     "a protected glob matches the file name")
        suite.expect(!CursorProtectedPaths.includes("src/App.swift", globs: [".env*"]),
                     "an unrelated file stays outside the protected list")
        suite.expect(CursorProtectedPaths.includes("src/App.swift", globs: []),
                     "an empty protected list covers every edit")

        suite.expect(CursorFollowUp.decide(status: "completed", loopCount: 0, queued: "next", holdSeconds: 30,
                                           queueOnAbort: false) == .send("next"),
                     "a queued reply is sent before the hold opens")
        suite.expect(CursorFollowUp.decide(status: "error", loopCount: 0, queued: "next", holdSeconds: 30,
                                           queueOnAbort: true) == .ignore,
                     "a failed turn sends nothing")
        suite.expect(CursorFollowUp.decide(status: "completed", loopCount: 1, queued: "next", holdSeconds: 30,
                                           queueOnAbort: false) == .ignore,
                     "a follow-up does not follow up again")
        suite.expect(CursorFollowUp.decide(status: "aborted", loopCount: 0, queued: "next", holdSeconds: 0,
                                           queueOnAbort: false) == .ignore,
                     "a stopped turn keeps the queue unless that setting is on")
        suite.expect(CursorFollowUp.decide(status: "aborted", loopCount: 0, queued: "next", holdSeconds: 0,
                                           queueOnAbort: true) == .send("next"),
                     "a stopped turn can still send the queue")
        suite.expect(CursorFollowUp.decide(status: "completed", loopCount: 0, queued: nil, holdSeconds: 30,
                                           queueOnAbort: false) == .hold,
                     "an empty queue holds the turn open")
        suite.expect(CursorFollowUp.decide(status: "completed", loopCount: 0, queued: nil, holdSeconds: 0,
                                           queueOnAbort: false) == .ignore,
                     "hold for reply stays off at zero")

        let huge = String(repeating: "é", count: 4_000)
        suite.expect(CursorPromptLink.fits("hello") && !CursorPromptLink.fits(huge)
                        && CursorPromptLink.url(text: huge) == nil,
                     "a prompt link stops past 21 plus the encoded length")
        suite.expect(CursorRepoList.remember("/work/a", existing: ["/work/b", "/work/a"]) == ["/work/a", "/work/b"],
                     "recent repos move to the front and drop the duplicate")

        let stop = CursorHookDecoder.decode(CursorHookMessage(version: 1, hook: "stop", source: "app", remote: false,
                                                              payload: Data(#"{"status":"completed","loop_count":1}"#.utf8)))
        suite.expect(stop?.loopCount == 1 && stop?.status == "completed", "stop keeps the loop count")
        suite.expect(CursorHookReplies.deferral(hook: "preToolUse").stdout.isEmpty,
                     "an edit the person cannot see does not ask")
        suite.expect(CursorHookReplies.deferral(hook: "beforeShellExecution").stdout.contains("\"ask\""),
                     "a shell the person cannot see goes back to Cursor")
        suite.expect(CursorHookProtocol.contextNoteStdout("  ").isEmpty
                        && CursorHookProtocol.contextNoteStdout("note").contains("additional_context"),
                     "an empty context note prints nothing")

        let push = CursorGitPlan.pushArguments(remote: "origin")
        let created = CursorGitPlan.createArguments(draft: true, base: "main", title: "Hello")
        let merged = CursorGitPlan.mergeArguments(number: 4, method: .squash, deleteBranch: true)
        suite.expect(push == ["push", "-u", "origin", "HEAD"] && !CursorGitPlan.refusesUnsafe(push),
                     "create pushes the current branch without force")
        suite.expect(created == ["pr", "create", "--fill", "--base", "main", "--draft", "--title", "Hello"],
                     "create fills the pull request and can stay a draft")
        suite.expect(merged == ["pr", "merge", "4", "--squash", "--delete-branch"] && !CursorGitPlan.refusesUnsafe(merged),
                     "merge names the method and can delete the branch")
        suite.expect(CursorGitPlan.refusesUnsafe(["push", "--force"])
                        && CursorGitPlan.refusesUnsafe(["pr", "merge", "1", "--admin"])
                        && CursorGitPlan.refusesUnsafe(["pr", "merge", "1", "--auto"]),
                     "force, admin and auto stays out of the commands")
        suite.expect(CursorGitPlan.canOpen(url: "https://github.com/a/b/pull/1", expectedHost: "github.com")
                        && !CursorGitPlan.canOpen(url: "http://github.com/a/b/pull/1", expectedHost: "github.com")
                        && !CursorGitPlan.canOpen(url: "https://evil.example/a", expectedHost: "github.com"),
                     "a pull request opens only as https on the expected host")
        var snapshot = CursorGitSnapshot(isRepository: true, branch: "main", defaultBranch: "main", authenticated: true)
        suite.expect(!snapshot.canCreate, "the default branch cannot open a pull request")
        snapshot.branch = "feature"
        suite.expect(snapshot.canCreate, "a feature branch can open a pull request")
        snapshot.detached = true
        suite.expect(!snapshot.canCreate, "a detached checkout cannot open a pull request")
        snapshot.detached = false
        snapshot.pullRequest = CursorPullRequest(number: 4, title: "Hello", url: "https://github.com/a/b/pull/4",
                                                  state: "OPEN", isDraft: false, mergeable: "MERGEABLE",
                                                  base: "main", head: "feature", checksFailed: false, checksPending: true)
        suite.expect(snapshot.canMerge, "a mergeable request with no failed check can merge")
        snapshot.pullRequest?.checksFailed = true
        suite.expect(!snapshot.canMerge, "a failed check blocks the merge")
    }

    private static func polish(_ suite: TestSuite) {
        let ready = CursorExperimentalCheck(trusted: true, frontIsCursor: true, windowCount: 1,
                                            shortcutConfigured: true, remote: false, focusedMatches: true)
        suite.expect(CursorExperimental.evaluate(ready) == .titleUnverified,
                     "an unverified window title aborts the experimental action")
        suite.expect(CursorExperimental.evaluate(CursorExperimentalCheck(trusted: false, frontIsCursor: true,
                                                                         windowCount: 1, shortcutConfigured: true,
                                                                         remote: false, focusedMatches: true)) == .needsTrust,
                     "experimental actions ask for Accessibility first")
        suite.expect(CursorExperimental.evaluate(CursorExperimentalCheck(trusted: true, frontIsCursor: false,
                                                                         windowCount: 1, shortcutConfigured: true,
                                                                         remote: false, focusedMatches: true)) == .notFront,
                     "experimental actions abort unless Cursor is in front")
        suite.expect(CursorExperimental.evaluate(CursorExperimentalCheck(trusted: true, frontIsCursor: true,
                                                                         windowCount: 2, shortcutConfigured: true,
                                                                         remote: false, focusedMatches: true),
                                                 titleFormat: "Project") == .severalWindows,
                     "more than one matching window aborts")
        suite.expect(CursorExperimental.evaluate(CursorExperimentalCheck(trusted: true, frontIsCursor: true,
                                                                         windowCount: 1, shortcutConfigured: true,
                                                                         remote: false, focusedMatches: false),
                                                 titleFormat: "Project") == .titleUnverified,
                     "the focused window has to contain the verified title")
        suite.expect(CursorExperimental.matchCount(["Foo — Cursor", "Bar"], format: "Foo") == 1
                        && CursorExperimental.matchCount(["A", "a"], format: "A") == 2
                        && CursorExperimental.matchCount(["A"], format: " ") == 0,
                     "window titles match the verified format, and an empty format matches none")
        suite.expect(CursorExperimental.evaluate(ready, titleFormat: "Project") == nil,
                     "a verified title with one focused window can run")
        suite.expect(CursorTypewriter.showsCaret(elapsed: 0.1) && !CursorTypewriter.showsCaret(elapsed: 0.6),
                     "the typewriter caret blinks twice a second")
        suite.expect(CursorExperimental.permissions(experimental: false).isEmpty
                        && CursorExperimental.permissions(experimental: true) == [.accessibility],
                     "Accessibility is listed only while the experimental toggle is on")
        suite.expect(CursorShortcutStore.chord(.stop, in: "") == nil,
                     "experimental shortcuts ship with no default chord")
        let saved = CursorShortcutStore.stored([.sendNow: "command:0"])
        suite.expect(CursorShortcutStore.chord(.sendNow, in: saved)?.storageValue == "command:0"
                        && CursorShortcutStore.chord(.undoAll, in: saved) == nil,
                     "a saved shortcut round-trips and the others stay empty")
        suite.expect(CursorTypewriter.shownCount(elapsed: 0.5, length: 90) == 45,
                     "the typewriter reveals about 90 characters a second")
        suite.expect(CursorTypewriter.shownCount(elapsed: 3, length: 1_000) == 600,
                     "a long reply finishes the first 600 characters within 2.5 seconds")
        suite.expect(CursorBuddyPose.pose(for: .quiet) == .quiet && CursorBuddyPose.pose(for: .waiting) == .waiting,
                     "each live state has a mascot pose")
    }

    private static func quality(_ suite: TestSuite) {
        let without = NotchSupport.compactActivities(
            timer: true, downloads: true, agents: true, calendar: true, music: true, keepAwake: true)
        suite.expect(without == [.timer, .downloads, .agents, .calendar, .music, .keepAwake],
                     "leaving Cursor out keeps the closed-island order")
        let withCursor = NotchSupport.compactActivities(
            timer: true, downloads: true, agents: true, calendar: true, music: true, keepAwake: true, cursor: true)
        suite.expect(withCursor == [.timer, .downloads, .cursor, .agents, .calendar, .music, .keepAwake],
                     "Cursor sits between downloads and agents")

        suite.expect(CursorHookProtocol.replyWait(for: "beforeShellExecution", override: nil) == 95
                        && CursorHookProtocol.replyWait(for: "stop", override: nil) == 130
                        && CursorHookProtocol.connectTimeout == 0.3
                        && CursorHookProtocol.replyWait(for: "afterAgentThought", override: 30) == nil,
                     "approvals wait 95 seconds, a held reply waits 130, and observation hooks do not wait")
        suite.expect(CursorPromptLink.encodedCount("a b") == 21 + 5,
                     "the prompt limit counts a space the way encodeURIComponent does")

        suite.expect(CursorGitPlan.branch(from: "feature\n").name == "feature"
                        && CursorGitPlan.branch(from: "HEAD\n").detached,
                     "a branch name is kept and HEAD is detached")
        suite.expect(CursorGitPlan.dirty(from: " M file\n") && !CursorGitPlan.dirty(from: "\n"),
                     "a porcelain line means the tree is dirty")
        suite.expect(CursorGitPlan.remote(from: "origin/main\n") == "origin"
                        && CursorGitPlan.defaultBranch(from: #"{"defaultBranchRef":{"name":"main"}}"#) == "main",
                     "the remote and the default branch come from git and gh")
        let pull = CursorGitPlan.pullRequest(from: """
        {"number":4,"title":"Hello","url":"https://github.com/a/b/pull/4","state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","baseRefName":"main","headRefName":"feature","statusCheckRollup":[{"conclusion":"FAILURE"}]}
        """)
        suite.expect(pull?.number == 4 && pull?.title == "Hello" && pull?.base == "main"
                        && pull?.head == "feature" && pull?.checksFailed == true && pull?.checksPending == false,
                     "a failed check is parsed onto the pull request")
        suite.expect(CursorGitPlan.candidates(home: "/Users/a", searchPath: "/usr/bin").prefix(3).map { $0 }
                        == ["/Users/a/.local/bin/gh", "/opt/homebrew/bin/gh", "/usr/local/bin/gh"],
                     "gh is looked up in the same folders as the Codex helper")
        var store = CursorSessionStore()
        let remote = reduce(&store, hook: "sessionStart", payload: [
            "conversation_id": "far", "workspace_roots": ["/tmp/repo"],
        ], now: Date(), remote: true)
        suite.expect(remote.store.sessions[0].remote && remote.store.sessions[0].root == "/tmp/repo",
                     "a remote chat keeps its folder and the remote flag")
    }

    private static func reduce(_ store: inout CursorSessionStore, hook: String, payload: [String: Any], now: Date,
                               remote: Bool = false, holdApprovals: Bool = false) -> CursorReduceResult {
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let message = CursorHookMessage(version: 1, hook: hook, source: "app", remote: remote, payload: data)
        let result = CursorSessionReducer.reduce(store, message: message, now: now, holdApprovals: holdApprovals)
        store = result.store
        return result
    }
}
