// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation

enum CursorHookFileError: Error, Equatable {
    case symlink
    case version
    case unreadable
}

enum CursorHookInstallStatus: Equatable {
    case notInstalled
    case installed
    case needsUpdate
    case unreadable
}

struct CursorHookEntry: Equatable {
    var event: String
    var command: String
    var timeout: Int
    var matcher: String?
    /// Set only on approval entries. A crashed hook then denies instead of allowing.
    var failClosed: Bool = false
    /// Set on `stop` so a follow-up cannot schedule another follow-up.
    var loopLimit: Int? = nil
}

/// Merges Vorssaint's hooks into `~/.cursor/hooks.json` without disturbing
/// anyone else's entries. The preview and the write each read the file themselves.
enum CursorHookInstaller {
    static let probeKey = "vorssaintProbe"
    static let helperFileName = CursorHookProtocol.helperName
    static let observationTimeout = 10
    static let editMatcher = "Write|Delete"

    static func hooksFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".cursor/hooks.json")
    }

    static func isProbe(_ message: CursorHookMessage) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: message.payload) as? [String: Any] else { return false }
        if let flag = object[probeKey] as? Bool { return flag }
        if let number = object[probeKey] as? NSNumber { return number.boolValue }
        return false
    }

    static func settingsSignature(in defaults: UserDefaults = .standard) -> String {
        let approvals = defaults.bool(forKey: DefaultsKey.notchCursorApprovals)
        let timeout = approvalSeconds(in: defaults)
        let edits = defaults.bool(forKey: DefaultsKey.notchCursorApproveEdits)
        let hold = holdSeconds(in: defaults)
        let handBack = defaults.string(forKey: DefaultsKey.notchCursorApprovalFallback)
            == CursorNotchApprovalFallback.handBack.rawValue
        return "\(approvals)|\(timeout)|\(edits)|\(hold)|\(handBack)|loop"
    }

    static func desiredEntries(helperPath: String, defaults: UserDefaults = .standard) -> [CursorHookEntry] {
        let approvals = defaults.bool(forKey: DefaultsKey.notchCursorApprovals)
        let edits = defaults.bool(forKey: DefaultsKey.notchCursorApproveEdits)
        let seconds = approvalSeconds(in: defaults)
        let hold = holdSeconds(in: defaults)
        let handBack = defaults.string(forKey: DefaultsKey.notchCursorApprovalFallback)
            == CursorNotchApprovalFallback.handBack.rawValue
        let events = [
            "sessionStart", "sessionEnd", "beforeSubmitPrompt", "afterAgentThought", "afterAgentResponse",
            "preToolUse", "postToolUse", "postToolUseFailure",
            "beforeShellExecution", "afterShellExecution",
            "beforeMCPExecution", "afterMCPExecution", "afterFileEdit",
            "subagentStart", "subagentStop", "preCompact", "workspaceOpen", "stop",
        ]
        return events.map { event in
            CursorHookEntry(event: event,
                            command: command(helperPath: helperPath, event: event, approvals: approvals,
                                             edits: edits, seconds: seconds, hold: hold, handBack: handBack),
                            timeout: cursorTimeout(event: event, approvals: approvals, edits: edits,
                                                   seconds: seconds, hold: hold),
                            matcher: event == "preToolUse" ? editMatcher : nil,
                            failClosed: failClosed(event: event, approvals: approvals, edits: edits),
                            loopLimit: event == "stop" ? 1 : nil)
        }
    }

    static func status(file: URL, helperPath: String, desired: [CursorHookEntry],
                       bundledHelper: URL? = nil, installedHelper: URL? = nil) -> CursorHookInstallStatus {
        var info = stat()
        guard lstat(file.path, &info) == 0 else { return .notInstalled }
        guard case .success(let document) = read(file) else { return .unreadable }
        guard containsOurHelper(document, helperPath: helperPath) else { return .notInstalled }
        if !entriesMatch(document, helperPath: helperPath, desired: desired) { return .needsUpdate }
        if let bundledHelper, let installedHelper,
           CursorHookInstall.hash(of: bundledHelper) != CursorHookInstall.hash(of: installedHelper) {
            return .needsUpdate
        }
        return .installed
    }

    static func otherCopyPaths(file: URL, helperPath: String) -> [String] {
        guard case .success(let document) = read(file) else { return [] }
        return foreignHelperPaths(document, helperPath: helperPath)
    }

    /// The file as it would be saved. Reads the current contents itself.
    static func preview(file: URL, helperPath: String, desired: [CursorHookEntry],
                        replaceOtherCopies: Bool) -> Result<String, CursorHookFileError> {
        merge(file: file, helperPath: helperPath, desired: desired, replaceOtherCopies: replaceOtherCopies)
            .map { $0.rendered() + "\n" }
    }

    /// Re-reads, merges, and writes. A backup is kept only when `backup` is set.
    @discardableResult
    static func apply(file: URL, helperPath: String, desired: [CursorHookEntry],
                      replaceOtherCopies: Bool, backup: Bool) -> Result<Void, CursorHookFileError> {
        let merged = merge(file: file, helperPath: helperPath, desired: desired, replaceOtherCopies: replaceOtherCopies)
        switch merged {
        case .failure(let error):
            return .failure(error)
        case .success(let document):
            return write(document, to: file, backup: backup)
        }
    }

    @discardableResult
    static func uninstall(file: URL, helperPath: String) -> Result<Void, CursorHookFileError> {
        guard FileManager.default.fileExists(atPath: file.path) else { return .success(()) }
        switch read(file) {
        case .failure(let error):
            return .failure(error)
        case .success(var document):
            let before = document.rendered()
            document.removeHelpers(matching: helperPath, foreign: false)
            guard document.rendered() != before else { return .success(()) }
            return write(document, to: file, backup: false)
        }
    }

    /// This app's hooks and the stable helper folder. Used by both uninstall paths.
    static func removeForUninstall() {
        CursorNotchService.shared.stop()
        if let helper = CursorHookInstall.liveInstalledHelperURL() {
            _ = uninstall(file: hooksFile(), helperPath: helper.path)
            try? FileManager.default.removeItem(at: helper.deletingLastPathComponent())
        }
        clearConfirmed()
    }

    static func liveHooksPresent() -> Bool {
        guard let path = CursorHookInstall.liveInstalledHelperURL()?.path else { return false }
        switch status(file: hooksFile(), helperPath: path, desired: desiredEntries(helperPath: path)) {
        case .installed, .needsUpdate: return true
        case .notInstalled, .unreadable: return false
        }
    }

    static func helperPath(in command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("\"") {
            var value = ""
            var escaping = false
            for character in trimmed.dropFirst() {
                if escaping {
                    value.append(character)
                    escaping = false
                    continue
                }
                if character == "\\" { escaping = true; continue }
                if character == "\"" { return value }
                value.append(character)
            }
            return nil
        }
        return trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
    }

    static func isOurHelper(_ path: String, helperPath: String) -> Bool {
        standardized(path) == standardized(helperPath)
    }

    static func isForeignVorssaintHelper(_ path: String, helperPath: String) -> Bool {
        URL(fileURLWithPath: path).lastPathComponent == helperFileName && !isOurHelper(path, helperPath: helperPath)
    }

    static func confirmedState(in defaults: UserDefaults = .standard) -> (confirmed: Bool, signature: String) {
        guard let data = defaults.string(forKey: DefaultsKey.notchCursorHookState)?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, "")
        }
        let confirmed = (object["confirmed"] as? Bool) ?? (object["confirmed"] as? NSNumber)?.boolValue ?? false
        return (confirmed, object["signature"] as? String ?? "")
    }

    static func storeConfirmed(signature: String, defaults: UserDefaults = .standard) {
        let object: [String: Any] = ["confirmed": true, "signature": signature]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: DefaultsKey.notchCursorHookState)
    }

    static func clearConfirmed(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: DefaultsKey.notchCursorHookState)
    }

    /// Runs the installed helper with a synthetic event. Success is an empty
    /// reply from a live socket; a missing app prints Cursor's own prompt.
    static func probe(helper: URL) -> Bool {
        let process = Process()
        process.executableURL = helper
        process.arguments = ["beforeShellExecution", "--wait=2"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        input.fileHandleForWriting.write(Data("{\"\(probeKey)\":true}\n".utf8))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return process.terminationStatus == 0 && !text.contains("\"permission\"")
    }

    private static func approvalSeconds(in defaults: UserDefaults) -> Int {
        let value = defaults.integer(forKey: DefaultsKey.notchCursorApprovalTimeout)
        return [30, 60, 90].contains(value) ? value : 60
    }

    private static func holdSeconds(in defaults: UserDefaults) -> Int {
        let value = defaults.integer(forKey: DefaultsKey.notchCursorHoldForReply)
        return [0, 30, 60, 120].contains(value) ? value : 0
    }

    private static func command(helperPath: String, event: String, approvals: Bool, edits: Bool,
                                seconds: Int, hold: Int, handBack: Bool) -> String {
        var parts = [quote(helperPath), event]
        switch event {
        case "beforeShellExecution", "beforeMCPExecution":
            let wait = approvals ? seconds + 5 : 1
            parts.append("--wait=\(wait)")
            if !approvals || handBack { parts.append("--fallback=ask") }
        case "preToolUse":
            parts.append("--wait=\(edits ? seconds + 5 : 1)")
        case "stop":
            parts.append("--wait=\(hold == 0 ? 1 : hold + 10)")
        default:
            break
        }
        return parts.joined(separator: " ")
    }

    /// Observation entries stay fail-open. Approval entries deny if the hook crashes.
    private static func failClosed(event: String, approvals: Bool, edits: Bool) -> Bool {
        switch event {
        case "beforeShellExecution", "beforeMCPExecution": return approvals
        case "preToolUse": return edits
        default: return false
        }
    }

    private static func cursorTimeout(event: String, approvals: Bool, edits: Bool, seconds: Int, hold: Int) -> Int {
        switch event {
        case "beforeShellExecution", "beforeMCPExecution":
            return approvals ? seconds + 15 : observationTimeout
        case "preToolUse":
            return edits ? seconds + 15 : observationTimeout
        case "stop":
            return max(observationTimeout, hold + 10)
        default:
            return observationTimeout
        }
    }

    private static func quote(_ path: String) -> String {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
        return "\"\(escaped)\""
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func merge(file: URL, helperPath: String, desired: [CursorHookEntry],
                              replaceOtherCopies: Bool) -> Result<CursorJSON, CursorHookFileError> {
        var document: CursorJSON
        if FileManager.default.fileExists(atPath: file.path) {
            switch read(file) {
            case .failure(let error): return .failure(error)
            case .success(let existing): document = existing
            }
        } else {
            document = .object([("version", .number("1")), ("hooks", .object([]))])
        }
        document.removeHelpers(matching: helperPath, foreign: replaceOtherCopies)
        document.add(desired)
        return .success(document)
    }

    private static func containsOurHelper(_ document: CursorJSON, helperPath: String) -> Bool {
        document.helperPaths.contains { isOurHelper($0, helperPath: helperPath) }
    }

    private static func foreignHelperPaths(_ document: CursorJSON, helperPath: String) -> [String] {
        var seen: [String] = []
        for path in document.helperPaths where isForeignVorssaintHelper(path, helperPath: helperPath) && !seen.contains(path) {
            seen.append(path)
        }
        return seen
    }

    private static func entriesMatch(_ document: CursorJSON, helperPath: String, desired: [CursorHookEntry]) -> Bool {
        let present = document.ourEntries(helperPath: helperPath)
        return present.count == desired.count && desired.allSatisfy { wanted in present.contains(wanted) }
    }

    private static func read(_ file: URL) -> Result<CursorJSON, CursorHookFileError> {
        var info = stat()
        guard lstat(file.path, &info) == 0 else { return .failure(.unreadable) }
        if (info.st_mode & S_IFMT) == S_IFLNK { return .failure(.symlink) }
        guard (info.st_mode & S_IFMT) == S_IFREG,
              let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8),
              let document = CursorJSON.parse(text) else { return .failure(.unreadable) }
        guard document.versionNumber == 1 else { return .failure(.version) }
        guard document.hooksArray != nil || document.objectValue("hooks") == nil else { return .failure(.unreadable) }
        if document.objectValue("hooks") != nil, document.hooksArray == nil { return .failure(.unreadable) }
        return .success(document)
    }

    private static func write(_ document: CursorJSON, to file: URL, backup: Bool) -> Result<Void, CursorHookFileError> {
        var info = stat()
        let exists = lstat(file.path, &info) == 0
        if exists {
            if (info.st_mode & S_IFMT) == S_IFLNK { return .failure(.symlink) }
            guard (info.st_mode & S_IFMT) == S_IFREG else { return .failure(.unreadable) }
        }
        let parent = file.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            guard CursorHookProtocol.createOwnerOnlyDirectory(parent.path) else { return .failure(.unreadable) }
        }
        if backup, exists {
            guard copyBackup(of: file) else { return .failure(.unreadable) }
            pruneBackups(near: file)
        }
        let mode = exists ? (info.st_mode & mode_t(0o777)) : mode_t(0o600)
        let incoming = file.appendingPathExtension("incoming")
        let data = Data((document.rendered() + "\n").utf8)
        guard (try? data.write(to: incoming, options: .atomic)) != nil else { return .failure(.unreadable) }
        try? FileManager.default.setAttributes([.posixPermissions: Int(mode)], ofItemAtPath: incoming.path)
        do {
            if exists {
                _ = try FileManager.default.replaceItemAt(file, withItemAt: incoming)
            } else {
                try FileManager.default.moveItem(at: incoming, to: file)
            }
        } catch {
            try? FileManager.default.removeItem(at: incoming)
            return .failure(.unreadable)
        }
        try? FileManager.default.setAttributes([.posixPermissions: Int(mode)], ofItemAtPath: file.path)
        return .success(())
    }

    private static func copyBackup(of file: URL) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "bak-\(formatter.string(from: Date()))"
        var destination = file.appendingPathExtension(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = file.appendingPathExtension("\(name)-\(suffix)")
            suffix += 1
        }
        return (try? FileManager.default.copyItem(at: file, to: destination)) != nil
    }

    private static func pruneBackups(near file: URL) {
        let directory = file.deletingLastPathComponent()
        let prefix = file.lastPathComponent + ".bak-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let backups = names.filter { $0.hasPrefix(prefix) }.sorted()
        for name in backups.dropLast(5) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}

private extension CursorJSON {
    var versionNumber: Int? {
        guard case .number(let lexeme) = objectValue("version") else { return nil }
        return Int(lexeme)
    }

    var hooksArray: [(String, CursorJSON)]? {
        guard case .object(let pairs) = objectValue("hooks") else { return nil }
        return pairs
    }

    var helperPaths: [String] {
        guard let hooks = hooksArray else { return [] }
        var paths: [String] = []
        for (_, value) in hooks {
            guard case .array(let entries) = value else { continue }
            for entry in entries {
                guard case .object = entry, let command = entry.stringValue("command"),
                      let path = CursorHookInstaller.helperPath(in: command) else { continue }
                paths.append(path)
            }
        }
        return paths
    }

    mutating func removeHelpers(matching helperPath: String, foreign: Bool) {
        guard var hooks = hooksArray else { return }
        for index in hooks.indices {
            guard case .array(var entries) = hooks[index].1 else { continue }
            entries.removeAll { entry in
                guard let command = entry.stringValue("command"),
                      let path = CursorHookInstaller.helperPath(in: command) else { return false }
                if CursorHookInstaller.isOurHelper(path, helperPath: helperPath) { return true }
                return foreign && CursorHookInstaller.isForeignVorssaintHelper(path, helperPath: helperPath)
            }
            hooks[index].1 = .array(entries)
        }
        setObject("hooks", .object(hooks))
    }

    mutating func add(_ desired: [CursorHookEntry]) {
        var hooks = hooksArray ?? []
        for entry in desired {
            let object = entry.json
            if let index = hooks.firstIndex(where: { $0.0 == entry.event }) {
                var entries: [CursorJSON]
                if case .array(let existing) = hooks[index].1 { entries = existing } else { entries = [hooks[index].1] }
                entries.append(object)
                hooks[index].1 = .array(entries)
            } else {
                hooks.append((entry.event, .array([object])))
            }
        }
        setObject("hooks", .object(hooks))
    }

    func ourEntries(helperPath: String) -> [CursorHookEntry] {
        guard let hooks = hooksArray else { return [] }
        var entries: [CursorHookEntry] = []
        for (event, value) in hooks {
            guard case .array(let items) = value else { continue }
            for item in items {
                guard let command = item.stringValue("command"),
                      let path = CursorHookInstaller.helperPath(in: command),
                      CursorHookInstaller.isOurHelper(path, helperPath: helperPath) else { continue }
                guard item.matchesOurShape else { return [] }
                let timeout = item.intValue("timeout") ?? -1
                let matcher = item.stringValue("matcher")
                let failClosed = item.boolValue("failClosed") ?? false
                let loopLimit = item.intValue("loop_limit")
                entries.append(CursorHookEntry(event: event, command: command, timeout: timeout,
                                               matcher: matcher, failClosed: failClosed, loopLimit: loopLimit))
            }
        }
        return entries
    }
}

private extension CursorHookEntry {
    var json: CursorJSON {
        var pairs: [(String, CursorJSON)] = [("command", .string(command))]
        if let matcher { pairs.append(("matcher", .string(matcher))) }
        pairs.append(("timeout", .number(String(timeout))))
        if failClosed { pairs.append(("failClosed", .bool(true))) }
        if let loopLimit { pairs.append(("loop_limit", .number(String(loopLimit)))) }
        return .object(pairs)
    }
}

private extension CursorJSON {
    var matchesOurShape: Bool {
        guard case .object(let pairs) = self else { return false }
        let keys = pairs.map(\.0)
        let allowed: Set<String> = ["command", "matcher", "timeout", "failClosed", "loop_limit"]
        return keys.allSatisfy(allowed.contains) && keys.contains("command") && keys.contains("timeout")
    }
}

/// JSON that remembers object key order, so a rewrite does not shuffle someone else's file.
enum CursorJSON {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([CursorJSON])
    case object([(String, CursorJSON)])

    func objectValue(_ key: String) -> CursorJSON? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.last { $0.0 == key }?.1
    }

    func stringValue(_ key: String) -> String? {
        guard case .string(let value) = objectValue(key) else { return nil }
        return value
    }

    func intValue(_ key: String) -> Int? {
        guard case .number(let lexeme) = objectValue(key) else { return nil }
        return Int(lexeme)
    }

    func boolValue(_ key: String) -> Bool? {
        guard case .bool(let value) = objectValue(key) else { return nil }
        return value
    }

    mutating func setObject(_ key: String, _ value: CursorJSON) {
        guard case .object(var pairs) = self else { return }
        if let index = pairs.lastIndex(where: { $0.0 == key }) {
            pairs[index].1 = value
        } else {
            pairs.append((key, value))
        }
        self = .object(pairs)
    }

    static func parse(_ text: String) -> CursorJSON? {
        var parser = Parser(text)
        guard let value = parser.parseValue() else { return nil }
        parser.skipWhitespace()
        guard parser.finished else { return nil }
        return value
    }

    func rendered() -> String {
        render(indent: 0)
    }

    private func render(indent: Int) -> String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let lexeme): return lexeme
        case .string(let value): return CursorJSON.encode(value)
        case .array(let items):
            if items.isEmpty { return "[]" }
            let pad = String(repeating: "  ", count: indent + 1)
            let closing = String(repeating: "  ", count: indent)
            let body = items.map { pad + $0.render(indent: indent + 1) }.joined(separator: ",\n")
            return "[\n\(body)\n\(closing)]"
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            let pad = String(repeating: "  ", count: indent + 1)
            let closing = String(repeating: "  ", count: indent)
            let body = pairs.map { pad + CursorJSON.encode($0.0) + ": " + $0.1.render(indent: indent + 1) }
                .joined(separator: ",\n")
            return "{\n\(body)\n\(closing)}"
        }
    }

    private static func encode(_ text: String) -> String {
        var encoded = "\""
        for character in text {
            switch character {
            case "\\": encoded += "\\\\"
            case "\"": encoded += "\\\""
            case "\n": encoded += "\\n"
            case "\r": encoded += "\\r"
            case "\t": encoded += "\\t"
            default: encoded.append(character)
            }
        }
        encoded.append("\"")
        return encoded
    }

    private struct Parser {
        let text: String
        var index: String.Index

        init(_ text: String) {
            self.text = text
            index = text.startIndex
        }

        var finished: Bool { index == text.endIndex }

        mutating func parseValue() -> CursorJSON? {
            skipWhitespace()
            guard index < text.endIndex else { return nil }
            switch text[index] {
            case "{": return parseObject()
            case "[": return parseArray()
            case "\"": return parseString().map(CursorJSON.string)
            case "t": return consume("true") ? .bool(true) : nil
            case "f": return consume("false") ? .bool(false) : nil
            case "n": return consume("null") ? .null : nil
            default: return parseNumber()
            }
        }

        mutating func parseObject() -> CursorJSON? {
            guard consume("{") else { return nil }
            var pairs: [(String, CursorJSON)] = []
            skipWhitespace()
            if consume("}") { return .object(pairs) }
            while true {
                skipWhitespace()
                guard let key = parseString() else { return nil }
                skipWhitespace()
                guard consume(":"), let value = parseValue() else { return nil }
                pairs.append((key, value))
                skipWhitespace()
                if consume("}") { return .object(pairs) }
                guard consume(",") else { return nil }
            }
        }

        mutating func parseArray() -> CursorJSON? {
            guard consume("[") else { return nil }
            var items: [CursorJSON] = []
            skipWhitespace()
            if consume("]") { return .array(items) }
            while true {
                guard let value = parseValue() else { return nil }
                items.append(value)
                skipWhitespace()
                if consume("]") { return .array(items) }
                guard consume(",") else { return nil }
            }
        }

        mutating func parseString() -> String? {
            guard consume("\"") else { return nil }
            var value = ""
            while index < text.endIndex {
                let character = text[index]
                index = text.index(after: index)
                if character == "\"" { return value }
                if character != "\\" {
                    value.append(character)
                    continue
                }
                guard index < text.endIndex else { return nil }
                let escaped = text[index]
                index = text.index(after: index)
                switch escaped {
                case "\"", "\\", "/": value.append(escaped)
                case "n": value.append("\n")
                case "r": value.append("\r")
                case "t": value.append("\t")
                case "b": value.append("\u{08}")
                case "f": value.append("\u{0C}")
                case "u":
                    guard let scalar = parseHexScalar() else { return nil }
                    value.unicodeScalars.append(scalar)
                default: return nil
                }
            }
            return nil
        }

        mutating func parseHexScalar() -> Unicode.Scalar? {
            var hex = ""
            for _ in 0..<4 {
                guard index < text.endIndex else { return nil }
                hex.append(text[index])
                index = text.index(after: index)
            }
            guard let number = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(number) else { return nil }
            return scalar
        }

        mutating func parseNumber() -> CursorJSON? {
            let start = index
            if text[index] == "-" { index = text.index(after: index) }
            guard index < text.endIndex, text[index].isNumber else { return nil }
            while index < text.endIndex, text[index].isNumber { index = text.index(after: index) }
            if index < text.endIndex, text[index] == "." {
                index = text.index(after: index)
                guard index < text.endIndex, text[index].isNumber else { return nil }
                while index < text.endIndex, text[index].isNumber { index = text.index(after: index) }
            }
            return .number(String(text[start..<index]))
        }

        mutating func skipWhitespace() {
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
        }

        mutating func consume(_ token: String) -> Bool {
            guard text[index...].hasPrefix(token) else { return false }
            index = text.index(index, offsetBy: token.count)
            return true
        }
    }
}

/// Settings and the empty Cursor page share one Connect flow.
final class CursorHookConnectModel: ObservableObject {
    static let shared = CursorHookConnectModel()

    @Published private(set) var status: CursorHookInstallStatus = .notInstalled
    @Published private(set) var preview: String?
    @Published private(set) var otherCopies: [String] = []
    @Published private(set) var showingConnect = false
    @Published private(set) var replaceCopies = false
    @Published private(set) var helperMissing = false
    @Published private(set) var working = false
    @Published private(set) var confirmedAt: Date?
    @Published private(set) var testResult: Bool?

    private init() {}

    func refresh() {
        guard let path = CursorHookInstall.liveInstalledHelperURL()?.path else {
            status = .notInstalled
            otherCopies = []
            return
        }
        let desired = CursorHookInstaller.desiredEntries(helperPath: path)
        status = CursorHookInstaller.status(file: CursorHookInstaller.hooksFile(), helperPath: path, desired: desired,
                                            bundledHelper: CursorHookInstall.bundledHelperURL(),
                                            installedHelper: CursorHookInstall.liveInstalledHelperURL())
        otherCopies = CursorHookInstaller.otherCopyPaths(file: CursorHookInstaller.hooksFile(), helperPath: path)
    }

    func alignIfSettingsChanged() {
        let state = CursorHookInstaller.confirmedState()
        let signature = CursorHookInstaller.settingsSignature()
        guard state.confirmed, signature != state.signature,
              let path = CursorHookInstall.liveInstalledHelperURL()?.path else { return }
        let desired = CursorHookInstaller.desiredEntries(helperPath: path)
        let file = CursorHookInstaller.hooksFile()
        let current = CursorHookInstaller.status(file: file, helperPath: path, desired: desired,
                                                 bundledHelper: CursorHookInstall.bundledHelperURL(),
                                                 installedHelper: CursorHookInstall.liveInstalledHelperURL())
        guard current == .installed || current == .needsUpdate else { return }
        guard case .success = CursorHookInstaller.apply(file: file, helperPath: path, desired: desired,
                                                        replaceOtherCopies: false, backup: false) else { return }
        CursorHookInstaller.storeConfirmed(signature: signature)
        refresh()
        CursorNotchService.shared.noteHooksUpdated()
    }

    func startConnect() {
        helperMissing = false
        testResult = nil
        refresh()
        showingConnect = true
        replaceCopies = otherCopies.isEmpty
        if replaceCopies { loadPreview() } else { preview = nil }
    }

    func replaceAndPreview() {
        replaceCopies = true
        loadPreview()
    }

    func cancelConnect() {
        showingConnect = false
        preview = nil
        replaceCopies = false
    }

    func confirm() {
        helperMissing = false
        if !otherCopies.isEmpty, !replaceCopies { return }
        let started = Date()
        guard CursorHookInstall.installLiveCopy(),
              let path = CursorHookInstall.liveInstalledHelperURL()?.path else {
            helperMissing = true
            return
        }
        let desired = CursorHookInstaller.desiredEntries(helperPath: path)
        guard case .success = CursorHookInstaller.apply(file: CursorHookInstaller.hooksFile(), helperPath: path,
                                                        desired: desired, replaceOtherCopies: replaceCopies,
                                                        backup: true) else {
            refresh()
            return
        }
        CursorHookInstaller.storeConfirmed(signature: CursorHookInstaller.settingsSignature())
        preview = nil
        showingConnect = false
        confirmedAt = started
        testResult = nil
        refresh()
    }

    func repair() {
        helperMissing = false
        guard CursorHookInstall.installLiveCopy(),
              let path = CursorHookInstall.liveInstalledHelperURL()?.path else {
            helperMissing = true
            return
        }
        let desired = CursorHookInstaller.desiredEntries(helperPath: path)
        guard case .success = CursorHookInstaller.apply(file: CursorHookInstaller.hooksFile(), helperPath: path,
                                                        desired: desired, replaceOtherCopies: true,
                                                        backup: true) else {
            refresh()
            return
        }
        CursorHookInstaller.storeConfirmed(signature: CursorHookInstaller.settingsSignature())
        testResult = nil
        refresh()
    }

    func disconnect() {
        if let path = CursorHookInstall.liveInstalledHelperURL()?.path {
            _ = CursorHookInstaller.uninstall(file: CursorHookInstaller.hooksFile(), helperPath: path)
        }
        CursorHookInstaller.clearConfirmed()
        confirmedAt = nil
        preview = nil
        showingConnect = false
        testResult = nil
        refresh()
    }

    func testConnection() {
        guard let helper = CursorHookInstall.liveInstalledHelperURL() else {
            testResult = false
            return
        }
        working = true
        testResult = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let reached = CursorHookInstaller.probe(helper: helper)
            DispatchQueue.main.async {
                CursorHookConnectModel.shared.finishTest(reached)
            }
        }
    }

    fileprivate func finishTest(_ reached: Bool) {
        working = false
        testResult = reached
    }

    private func loadPreview() {
        guard let path = CursorHookInstall.liveInstalledHelperURL()?.path else {
            helperMissing = true
            preview = nil
            return
        }
        let desired = CursorHookInstaller.desiredEntries(helperPath: path)
        switch CursorHookInstaller.preview(file: CursorHookInstaller.hooksFile(), helperPath: path,
                                           desired: desired, replaceOtherCopies: replaceCopies) {
        case .success(let text):
            preview = text
        case .failure:
            preview = nil
            refresh()
        }
    }
}
