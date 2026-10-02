// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// The line the helper and the app exchange. Version 1 is one JSON object.
struct CursorHookMessage: Sendable, Equatable {
    var version: Int
    var hook: String
    var source: String
    var remote: Bool
    var payload: Data
}

struct CursorHookReply: Sendable, Equatable {
    var stdout: String
    var exitCode: Int

    static let empty = CursorHookReply(stdout: "", exitCode: 0)
}

enum CursorHookFailure: Sendable {
    /// Nothing accepted the socket. Cursor keeps its own flow.
    case unavailable
    /// The app accepted the hook and then never decided.
    case unanswered
}

enum CursorHookKind: Sendable, Equatable {
    case observation
    case approval
    case stop
    case sessionStart
}

/// Shared by the app and `vorssaint-cursor-hook`. No AppKit.
enum CursorHookProtocol {
    static let version = 1
    static let connectTimeout: TimeInterval = 0.3
    static let receiveTimeout: TimeInterval = 5
    static let maxStdinBytes = 4 * 1024 * 1024
    static let maxRequestBytes = 512 * 1024
    static let maxAcceptedBytes = 1024 * 1024
    static let shellTailBytes = 8 * 1024
    static let promptCap = 2 * 1024
    static let thoughtCap = 4 * 1024
    static let replyCap = 16 * 1024
    static let editCap = 16 * 1024
    static let sunPathLimit = 103
    static let approvalWait: TimeInterval = 95
    static let stopWait: TimeInterval = 130
    static let helperName = "vorssaint-cursor-hook"
    static let directoryName = "CursorHook"
    static let socketName = "hook.sock"

    static let droppedKeys: Set<String> = [
        "user_email", "CURSOR_USER_EMAIL", "transcript_path", "CURSOR_TRANSCRIPT_PATH",
        "attachments", "file_contents", "content", "contents", "fileContent", "file_content",
        "pluginPaths", "env", "updated_input",
    ]

    static func kind(of hook: String) -> CursorHookKind {
        switch hook {
        case "beforeShellExecution", "beforeMCPExecution", "preToolUse":
            return .approval
        case "stop":
            return .stop
        case "sessionStart":
            return .sessionStart
        default:
            return .observation
        }
    }

    /// Observation hooks, including `sessionStart`, send the event and leave.
    /// The context note is printed locally, so a new chat never waits on the socket.
    static func replyWait(for hook: String, override: TimeInterval?) -> TimeInterval? {
        switch kind(of: hook) {
        case .observation, .sessionStart:
            return nil
        case .approval:
            return override ?? approvalWait
        case .stop:
            return override ?? stopWait
        }
    }

    static func preferredSocketPath(home: String, bundleIdentifier: String) -> String {
        let home = URL(fileURLWithPath: home)
        return home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(socketName)
            .path
    }

    /// A path that does not fit in `sockaddr_un` uses a per-user folder in `/tmp`.
    static func resolveSocketPath(preferred: String, uid: uid_t) -> String {
        if preferred.utf8.count <= sunPathLimit { return preferred }
        return "/tmp/vorssaint-\(uid)/cursor.sock"
    }

    static func socketPath(container: URL, uid: uid_t = getuid()) -> String {
        let preferred = container
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(socketName)
            .path
        return resolveSocketPath(preferred: preferred, uid: uid)
    }

    /// The installed helper lives beside `hook.sock`, unless that path is too long.
    static func socketPath(helperExecutable: String, uid: uid_t = getuid()) -> String? {
        let url = URL(fileURLWithPath: helperExecutable).resolvingSymlinksInPath()
        let directory = url.deletingLastPathComponent()
        guard url.lastPathComponent == helperName, directory.lastPathComponent == directoryName else { return nil }
        return resolveSocketPath(preferred: directory.appendingPathComponent(socketName).path, uid: uid)
    }

    static func source(ancestorPaths: [String]) -> String {
        let app = ancestorPaths.contains { path in
            path.contains("Cursor.app/Contents") || path.contains("Cursor Nightly.app/Contents")
        }
        return app ? "app" : "terminal"
    }

    static func currentSource() -> String {
        source(ancestorPaths: ancestorExecutablePaths())
    }

    static func peerBelongsToCurrentUser(_ uid: uid_t, current: uid_t = getuid()) -> Bool {
        uid == current
    }

    static func fallbackStdout(hook: String, failure: CursorHookFailure, handBack: Bool) -> String {
        guard kind(of: hook) == .approval else { return "" }
        let handsBack = hook != "preToolUse" && (failure == .unavailable || handBack)
        if handsBack { return #"{"permission":"ask"}"# }
        if failure == .unavailable { return "" }
        return deniedStdout()
    }

    static func contextNoteStdout(_ note: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let object = ["additional_context": prefix(trimmed, 4_000)]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// The note sits beside the installed helper. A symlink is ignored.
    static func readContextNote(beside executable: String) -> String {
        let path = URL(fileURLWithPath: executable).deletingLastPathComponent()
            .appendingPathComponent("context-note").path
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return "" }
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func deniedStdout() -> String {
        let object: [String: Any] = [
            "agent_message": "Approval timed out. Check with the user in chat before running this again.",
            "permission": "deny",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func allowlistedStdout(_ stdout: String, hook: String) -> String {
        let allowed: Set<String>
        switch hook {
        case "beforeShellExecution", "beforeMCPExecution", "preToolUse":
            allowed = ["permission", "user_message", "agent_message"]
        case "stop":
            allowed = ["followup_message"]
        case "sessionStart":
            allowed = ["additional_context"]
        default:
            return ""
        }
        guard let data = stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        let kept = object.filter { allowed.contains($0.key) }
        guard !kept.isEmpty,
              let encoded = try? JSONSerialization.data(withJSONObject: kept, options: [.sortedKeys]),
              let text = String(data: encoded, encoding: .utf8) else { return "" }
        return text
    }

    static func trim(payload: Data, hook: String, hitStdinCap: Bool) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            if hook == "afterShellExecution" { return shellTail(payload) }
            return Data("{}".utf8)
        }
        var trimmed = trimObject(object, hook: hook)
        if hook == "afterShellExecution", hitStdinCap { trimmed["truncated"] = true }
        guard let data = try? JSONSerialization.data(withJSONObject: trimmed, options: [.sortedKeys]) else {
            return Data(#"{"truncated":true}"#.utf8)
        }
        return data
    }

    static func encodeRequest(hook: String, source: String, remote: Bool, payload: Data) -> Data? {
        let body = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? ["truncated": true]
        return encode(requestFields(hook: hook, source: source, remote: remote, payload: body))
            ?? encode(requestFields(hook: hook, source: source, remote: remote, payload: ["truncated": true]))
    }

    static func decodeRequest(_ line: Data) -> CursorHookMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let version = intValue(object["v"]), version == Self.version,
              let hook = object["hook"] as? String,
              let source = object["source"] as? String,
              let payload = object["payload"] as? [String: Any],
              let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        else { return nil }
        return CursorHookMessage(version: version, hook: hook, source: source,
                                  remote: boolValue(object["remote"]), payload: payloadData)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    static func encodeReply(_ reply: CursorHookReply, hook: String) -> Data? {
        let stdout = allowlistedStdout(reply.stdout, hook: hook)
        let object: [String: Any] = ["exit": reply.exitCode, "stdout": stdout]
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        data.append(0x0A)
        return data
    }

    static func decodeReplyLine(_ line: Data) -> CursorHookReply? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let stdout = object["stdout"] as? String else { return nil }
        let exitCode = intValue(object["exit"]) ?? 0
        return CursorHookReply(stdout: stdout, exitCode: exitCode)
    }

    static func directoryIsOwnerOnly(_ path: String, uid: uid_t) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return info.st_uid == uid && (info.st_mode & S_IFMT) == S_IFDIR && (info.st_mode & mode_t(0o077)) == 0
    }

    /// Creates one directory, or tightens one we already own. A symlink or another user's folder is refused.
    @discardableResult
    static func createOwnerOnlyDirectory(_ path: String, uid: uid_t = getuid()) -> Bool {
        var info = stat()
        if lstat(path, &info) == 0 {
            guard info.st_uid == uid, (info.st_mode & S_IFMT) == S_IFDIR else { return false }
            if (info.st_mode & mode_t(0o077)) != 0, mayTighten(path) { _ = chmod(path, 0o700) }
            return directoryIsOwnerOnly(path, uid: uid)
        }
        guard mkdir(path, 0o700) == 0 else { return false }
        _ = chmod(path, 0o700)
        return directoryIsOwnerOnly(path, uid: uid)
    }

    private static func mayTighten(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name == directoryName || name.hasPrefix("vorssaint-")
    }

    private static func requestFields(hook: String, source: String, remote: Bool, payload: [String: Any]) -> [String: Any] {
        ["hook": hook, "payload": payload, "remote": remote, "source": source, "v": version]
    }

    private static func encode(_ object: [String: Any]) -> Data? {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        if data.count > maxRequestBytes {
            return nil
        }
        data.append(0x0A)
        return data
    }

    private static func trimObject(_ object: [String: Any], hook: String) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in object where !droppedKeys.contains(key) {
            result[key] = trimValue(value, hook: hook)
        }
        if let prompt = result["prompt"] as? String, prompt.utf8.count > promptCap {
            result["prompt"] = prefix(prompt, promptCap)
            result["truncated"] = true
        }
        if hook == "afterAgentThought", let text = result["text"] as? String, text.utf8.count > thoughtCap {
            result["text"] = prefix(text, thoughtCap)
            result["truncated"] = true
        }
        if hook == "afterAgentResponse", let text = result["text"] as? String, text.utf8.count > replyCap {
            result["text"] = prefix(text, replyCap)
            result["truncated"] = true
        }
        if hook == "afterShellExecution", let output = result["output"] as? String, output.utf8.count > shellTailBytes {
            result["output"] = suffix(output, shellTailBytes)
            result["truncated"] = true
        }
        if let edits = result["edits"] as? [Any] {
            result["edits"] = edits.map { item in
                guard let edit = item as? [String: Any] else { return item }
                return trimEdit(edit)
            }
        }
        return result
    }

    private static func trimValue(_ value: Any, hook: String) -> Any {
        if let object = value as? [String: Any] { return trimObject(object, hook: hook) }
        if let array = value as? [Any] { return array.map { trimValue($0, hook: hook) } }
        if let edits = value as? [[String: Any]] { return edits.map { trimObject($0, hook: hook) } }
        return value
    }

    private static func trimEdit(_ edit: [String: Any]) -> [String: Any] {
        var edit = trimObject(edit, hook: "afterFileEdit")
        var truncated = edit["truncated"] as? Bool ?? false
        for key in ["old_string", "new_string"] {
            guard let text = edit[key] as? String, text.utf8.count > editCap else { continue }
            edit[key] = prefix(text, editCap)
            truncated = true
        }
        if truncated { edit["truncated"] = true }
        return edit
    }

    private static func shellTail(_ payload: Data) -> Data {
        let tail = payload.suffix(shellTailBytes)
        let text = String(decoding: tail, as: UTF8.self)
        let object: [String: Any] = ["output": text, "truncated": true]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data(#"{"truncated":true}"#.utf8)
    }

    static func prefix(_ string: String, _ maxBytes: Int) -> String {
        var count = 0
        var end = string.startIndex
        for index in string.indices {
            let bytes = string[index].utf8.count
            if count + bytes > maxBytes { break }
            count += bytes
            end = string.index(after: index)
        }
        return String(string[..<end])
    }

    static func suffix(_ string: String, _ maxBytes: Int) -> String {
        var count = 0
        var start = string.endIndex
        var index = string.endIndex
        while index > string.startIndex {
            string.formIndex(before: &index)
            let bytes = string[index].utf8.count
            if count + bytes > maxBytes { break }
            count += bytes
            start = index
        }
        return String(string[start...])
    }

    private static func ancestorExecutablePaths() -> [String] {
        var pid = getppid()
        var paths: [String] = []
        var seen = Set<Int32>()
        while pid > 1, paths.count < 32, seen.insert(pid).inserted {
            if let path = executablePath(pid) { paths.append(path) }
            guard let parent = parentPID(pid), parent != pid else { break }
            pid = parent
        }
        return paths
    }

    private static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func parentPID(_ pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let expected = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected) == expected else { return nil }
        return Int32(bitPattern: info.pbi_ppid)
    }
}

enum CursorHookExchange: Sendable, Equatable {
    case sent
    case reply(CursorHookReply)
    case failed
    case timedOut
}

enum CursorHookClient {
    static func send(line: Data, path: String, wait: TimeInterval?) -> CursorHookExchange {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard CursorHookProtocol.directoryIsOwnerOnly(parent, uid: getuid()) else { return .failed }
        let fd = connect(path: path, timeout: CursorHookProtocol.connectTimeout)
        guard fd >= 0 else { return .failed }
        defer { _ = Darwin.close(fd) }
        guard CursorHookSocket.writeAll(fd: fd, data: line) else { return .failed }
        guard let wait else { return .sent }
        switch CursorHookSocket.readLine(fd: fd, maxBytes: CursorHookProtocol.maxAcceptedBytes, timeout: wait) {
        case .line(let data):
            guard let reply = CursorHookProtocol.decodeReplyLine(data) else { return .failed }
            return .reply(reply)
        case .timeout:
            return .timedOut
        case .closed, .tooLarge, .interrupted:
            return .failed
        }
    }

    private static func connect(path: String, timeout: TimeInterval) -> Int32 {
        guard let address = CursorHookSocket.address(path) else { return -1 }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        CursorHookSocket.setNoSigPipe(fd)
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let connected = address.storage.withSockAddr { pointer, length in
            Darwin.connect(fd, pointer, length)
        }
        if connected != 0 && errno != EINPROGRESS {
            _ = Darwin.close(fd)
            return -1
        }
        if connected != 0 {
            var polled = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&polled, 1, Int32(timeout * 1000))
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            let failed = ready <= 0 || getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) != 0 || error != 0
            if failed {
                _ = Darwin.close(fd)
                return -1
            }
        }
        _ = fcntl(fd, F_SETFL, flags)
        return fd
    }
}

enum CursorHookRead: Sendable, Equatable {
    case line(Data)
    case timeout
    case closed
    case tooLarge
    case interrupted
}

enum CursorHookSocket {
    struct Address {
        var storage: sockaddr_un
        var length: socklen_t
    }

    static func address(_ path: String) -> Address? {
        let bytes = Array(path.utf8)
        guard bytes.count <= CursorHookProtocol.sunPathLimit else { return nil }
        var storage = sockaddr_un()
        let length = socklen_t(2 + bytes.count + 1)
        storage.sun_family = sa_family_t(AF_UNIX)
        storage.sun_len = UInt8(length)
        withUnsafeMutablePointer(to: &storage.sun_path) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: 104) { raw in
                for (index, byte) in bytes.enumerated() { raw[index] = byte }
                raw[bytes.count] = 0
            }
        }
        return Address(storage: storage, length: length)
    }

    static func setNoSigPipe(_ fd: Int32) {
        var enabled: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    }

    static func writeAll(fd: Int32, data: Data) -> Bool {
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
            }
            if written > 0 { offset += written; continue }
            if written < 0 && errno == EINTR { continue }
            return false
        }
        return true
    }

    static func readLine(fd: Int32, maxBytes: Int, timeout: TimeInterval, wake: Int32 = -1) -> CursorHookRead {
        var data = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count <= maxBytes {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return data.isEmpty ? .timeout : .closed }
            var polls = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0)]
            if wake >= 0 { polls.append(pollfd(fd: wake, events: Int16(POLLIN), revents: 0)) }
            let ready = polls.withUnsafeMutableBufferPointer { pointer -> Int32 in
                guard let base = pointer.baseAddress else { return -1 }
                return poll(base, nfds_t(pointer.count), Int32(remaining * 1000))
            }
            if ready == 0 { return .timeout }
            if ready < 0 { if errno == EINTR { continue }; return .closed }
            if wake >= 0, polls[1].revents != 0 { return .interrupted }
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fd, base, raw.count)
            }
            if count == 0 { return .closed }
            if count < 0 { if errno == EINTR { continue }; return .closed }
            data.append(buffer, count: count)
            if data.count > maxBytes { return .tooLarge }
            if let end = data.firstIndex(of: 0x0A) { return .line(Data(data[..<end])) }
        }
        return .tooLarge
    }
}

extension sockaddr_un {
    func withSockAddr<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var copy = self
        let length = socklen_t(sun_len)
        return withUnsafePointer(to: &copy) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, length) }
        }
    }
}
