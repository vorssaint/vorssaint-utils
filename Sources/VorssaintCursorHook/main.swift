// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

private struct Invocation {
    var hook = ""
    var wait: TimeInterval?
    var handBack = false
}

if CommandLine.arguments.contains("--selftest") {
    let ok = runSelfTest()
    fputs(ok ? "cursor-hook: ok\n" : "cursor-hook: failed\n", stderr)
    exit(ok ? EXIT_SUCCESS : EXIT_FAILURE)
}

private let invocation = parse(CommandLine.arguments)
let stdin = readStdin(maxBytes: CursorHookProtocol.maxStdinBytes)
let payload = CursorHookProtocol.trim(payload: stdin.data, hook: invocation.hook, hitStdinCap: stdin.hitCap)
let source = CursorHookProtocol.currentSource()
let remote = ProcessInfo.processInfo.environment["CURSOR_CODE_REMOTE"] == "true"
guard let line = CursorHookProtocol.encodeRequest(hook: invocation.hook, source: source,
                                                   remote: remote, payload: payload),
      let executable = executablePath(),
      let socket = CursorHookProtocol.socketPath(helperExecutable: executable) else {
    emit(CursorHookProtocol.fallbackStdout(hook: invocation.hook, failure: .unavailable, handBack: invocation.handBack))
    exit(EXIT_SUCCESS)
}

if invocation.hook == "sessionStart" {
    let note = CursorHookProtocol.readContextNote(beside: executable)
    emit(CursorHookProtocol.contextNoteStdout(note))
}

switch CursorHookClient.send(line: line, path: socket, wait: CursorHookProtocol.replyWait(for: invocation.hook, override: invocation.wait)) {
case .sent:
    break
case .reply(let reply):
    emit(CursorHookProtocol.allowlistedStdout(reply.stdout, hook: invocation.hook))
case .failed:
    emit(CursorHookProtocol.fallbackStdout(hook: invocation.hook, failure: .unavailable, handBack: invocation.handBack))
case .timedOut:
    emit(CursorHookProtocol.fallbackStdout(hook: invocation.hook, failure: .unanswered, handBack: invocation.handBack))
}
exit(EXIT_SUCCESS)

private func emit(_ stdout: String) {
    guard !stdout.isEmpty, let data = stdout.data(using: .utf8) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

private func parse(_ arguments: [String]) -> Invocation {
    var invocation = Invocation()
    for argument in arguments.dropFirst() where !argument.hasPrefix("--") {
        invocation.hook = argument
        break
    }
    for argument in arguments where argument.hasPrefix("--wait=") {
        invocation.wait = TimeInterval(argument.dropFirst("--wait=".count))
    }
    invocation.handBack = arguments.contains("--fallback=ask")
    return invocation
}

private func executablePath() -> String? {
    let raw = CommandLine.arguments[0]
    let absolute: String
    if raw.hasPrefix("/") {
        absolute = raw
    } else {
        absolute = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(raw).path
    }
    return URL(fileURLWithPath: absolute).resolvingSymlinksInPath().path
}

private func readStdin(maxBytes: Int) -> (data: Data, hitCap: Bool) {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    let limit = maxBytes + 1
    while data.count < limit {
        let room = min(buffer.count, limit - data.count)
        let count = Darwin.read(STDIN_FILENO, &buffer, room)
        if count == 0 { break }
        if count < 0 { if errno == EINTR { continue }; break }
        data.append(buffer, count: count)
    }
    let hitCap = data.count > maxBytes
    if hitCap { data = data.prefix(maxBytes) }
    return (data, hitCap)
}

private func runSelfTest() -> Bool {
    let shell = "beforeShellExecution"
    let poisoned = #"{"permission":"allow","pluginPaths":["/tmp"],"env":{"A":"1"},"updated_input":{"x":1},"user_message":"kept"}"#
    guard CursorHookProtocol.allowlistedStdout(poisoned, hook: shell) == #"{"permission":"allow","user_message":"kept"}"# else { return false }
    guard CursorHookProtocol.allowlistedStdout(poisoned, hook: "postToolUse").isEmpty else { return false }
    guard CursorHookProtocol.allowlistedStdout(#"{"followup_message":"next","env":{"A":"1"}}"#, hook: "stop")
            == #"{"followup_message":"next"}"# else { return false }
    guard CursorHookProtocol.allowlistedStdout(#"{"additional_context":"note","pluginPaths":["/tmp"]}"#, hook: "sessionStart")
            == #"{"additional_context":"note"}"# else { return false }

    guard CursorHookProtocol.fallbackStdout(hook: "postToolUse", failure: .unavailable, handBack: false).isEmpty else { return false }
    guard CursorHookProtocol.fallbackStdout(hook: "stop", failure: .unavailable, handBack: false).isEmpty else { return false }
    guard CursorHookProtocol.fallbackStdout(hook: shell, failure: .unavailable, handBack: false) == #"{"permission":"ask"}"# else { return false }
    guard CursorHookProtocol.fallbackStdout(hook: "preToolUse", failure: .unavailable, handBack: true).isEmpty else { return false }
    guard CursorHookProtocol.fallbackStdout(hook: shell, failure: .unanswered, handBack: false).contains(#""permission":"deny""#) else { return false }
    guard CursorHookProtocol.fallbackStdout(hook: "preToolUse", failure: .unanswered, handBack: true).contains(#""permission":"deny""#) else { return false }
    guard CursorHookProtocol.fallbackStdout(hook: shell, failure: .unanswered, handBack: true) == #"{"permission":"ask"}"# else { return false }

    let email = #"{"prompt":"hello","user_email":"a@b.c","transcript_path":"/tmp/t","env":{"CURSOR_USER_EMAIL":"a@b.c"}}"#
    let trimmed = CursorHookProtocol.trim(payload: Data(email.utf8), hook: "beforeSubmitPrompt", hitStdinCap: false)
    let text = String(decoding: trimmed, as: UTF8.self)
    guard !text.contains("user_email"), !text.contains("transcript_path"), !text.contains("CURSOR_USER_EMAIL"),
          text.contains("hello") else { return false }

    let long = String(repeating: "p", count: CursorHookProtocol.promptCap + 20)
    let capped = CursorHookProtocol.trim(payload: Data(#"{"prompt":"\#(long)"}"#.utf8), hook: "beforeSubmitPrompt", hitStdinCap: false)
    guard let object = try? JSONSerialization.jsonObject(with: capped) as? [String: Any],
          let prompt = object["prompt"] as? String, prompt.utf8.count <= CursorHookProtocol.promptCap,
          object["truncated"] as? Bool == true else { return false }

    guard CursorHookProtocol.source(ancestorPaths: ["/Applications/Cursor.app/Contents/MacOS/Cursor"]) == "app" else { return false }
    guard CursorHookProtocol.source(ancestorPaths: ["/Applications/Cursor Nightly.app/Contents/MacOS/Cursor"]) == "app" else { return false }
    guard CursorHookProtocol.source(ancestorPaths: ["/Applications/Terminal.app/Contents/MacOS/Terminal"]) == "terminal" else { return false }
    guard CursorHookProtocol.currentSource() == "app" || CursorHookProtocol.currentSource() == "terminal" else { return false }

    let home = "/Users/" + String(repeating: "n", count: 80)
    let preferred = CursorHookProtocol.preferredSocketPath(home: home, bundleIdentifier: "com.vorssaint.utils")
    guard preferred.utf8.count > CursorHookProtocol.sunPathLimit else { return false }
    let resolved = CursorHookProtocol.resolveSocketPath(preferred: preferred, uid: 501)
    guard resolved == "/tmp/vorssaint-501/cursor.sock" else { return false }
    guard !CursorHookProtocol.peerBelongsToCurrentUser(uid_t.max) || getuid() == uid_t.max else { return false }

    guard let line = CursorHookProtocol.encodeRequest(hook: shell, source: "app", remote: true, payload: Data(#"{"command":"ls"}"#.utf8)),
          let message = CursorHookProtocol.decodeRequest(line.filter { $0 != 0x0A }),
          message.hook == shell, message.remote, message.source == "app" else { return false }
    let encoded = String(decoding: line, as: UTF8.self)
    guard !encoded.contains("pluginPaths"), !encoded.contains("\"env\"") else { return false }
    return CursorHookProtocol.replyWait(for: "postToolUse", override: nil) == nil
        && CursorHookProtocol.replyWait(for: "sessionStart", override: 30) == nil
        && CursorHookProtocol.replyWait(for: shell, override: 12) == 12
}
