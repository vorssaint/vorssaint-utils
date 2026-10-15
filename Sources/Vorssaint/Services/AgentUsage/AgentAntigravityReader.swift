// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Reads Antigravity CLI (`agy`) conversations. Each conversation is its own
/// SQLite database in ~/.gemini/antigravity-cli/conversations, holding one
/// row per step in `steps` and one row per model request in `gen_metadata`,
/// both as protobuf. Only times, token counts, model names and the
/// workspace folder are decoded; prompts, replies and tool output are never
/// read out of a step.
enum AgentAntigravityReader {
    static let folder = ".gemini/antigravity-cli/conversations"

    /// Step kinds as Antigravity numbers them.
    enum Kind {
        static let userInput: Int64 = 14
        static let response: Int64 = 15
    }

    /// Statuses after which a step no longer changes: done, cancelled, failed.
    static let settledStatuses: Set<Int64> = [3, 6, 7]

    /// A conversation is one `<uuid>.db` directly in the folder.
    static func isConversation(_ path: String, in root: URL) -> Bool {
        let prefix = root.path + "/"
        guard path.hasPrefix(prefix), path.hasSuffix(".db") else { return false }
        return !path.dropFirst(prefix.count).contains("/")
    }

    /// Reads the steps written since the last read. `cursor.offset` is the
    /// index of the first step that may still change; steps from there on
    /// are handed over again on each read, and the usage they carry is keyed
    /// so a repeat merges instead of counting twice.
    static func readAppended(_ cursor: AgentLogCursor, since horizon: Date = .distantPast,
                             shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue() else { return }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let identity = UInt64(info.st_ino)
        if identity != cursor.identity {
            let replaced = cursor.identity != 0
            cursor.identity = identity
            cursor.offset = 0
            cursor.state = AgentLogState()
            if replaced { line(Data(#"{"type":"reset"}"#.utf8)) }
        }
        cursor.modified = AgentOpenCodeReader.modified(cursor.path) ?? .distantPast

        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        // Antigravity keeps its conversations in WAL mode and removes the
        // -wal and -shm files when it closes one. A read-only connection
        // cannot create the -shm file again and fails to open; a closed
        // conversation is not written, so it is opened as immutable instead.
        var walInfo = stat()
        let open = stat(cursor.path + "-wal", &walInfo) == 0
        let target = open ? cursor.path : URL(fileURLWithPath: cursor.path).absoluteString + "?immutable=1"
        guard sqlite3_open_v2(target, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI,
                              nil) == SQLITE_OK else { return }
        sqlite3_busy_timeout(db, 2000)

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT idx, step_type, status, metadata FROM steps WHERE idx >= ? ORDER BY idx",
                                 -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(cursor.offset))

        struct Step {
            let index: Int64
            let kind: Int64
            let status: Int64
            let meta: StepMeta
        }
        var steps: [Step] = []
        while shouldContinue() && sqlite3_step(stmt) == SQLITE_ROW {
            let meta = blob(stmt, 3).map(StepMeta.init) ?? StepMeta()
            steps.append(Step(index: sqlite3_column_int64(stmt, 0), kind: sqlite3_column_int64(stmt, 1),
                              status: sqlite3_column_int64(stmt, 2), meta: meta))
        }
        guard shouldContinue(), let last = steps.last else { return }

        let conversation = ((cursor.path as NSString).lastPathComponent as NSString).deletingPathExtension
        if cursor.state.project.isEmpty { cursor.state.project = workspace(db) ?? "" }
        let models = steps.contains { $0.meta.usage != nil } ? modelNames(db) : [:]
        let floor = horizon.timeIntervalSince1970

        var settledThrough = Int64(cursor.offset) - 1
        var stillSettled = true
        for step in steps {
            let settled = settledStatuses.contains(step.status)
            if stillSettled && settled { settledThrough = step.index } else { stillSettled = false }
            guard let created = step.meta.created, created >= floor else { continue }
            var json: [String: Any] = [
                "type": "step", "conversation": conversation, "idx": step.index, "kind": step.kind,
                "settled": settled, "time": created, "project": cursor.state.project,
            ]
            if let end = step.meta.completed { json["end"] = end }
            if let usage = step.meta.usage {
                json["model"] = (step.meta.modelEnum > 0 ? models[-step.meta.modelEnum] : nil) ?? models[step.index] ?? ""
                json["input"] = usage.input
                json["cacheRead"] = usage.cacheRead
                json["output"] = usage.output
                json["reasoning"] = usage.reasoning
            }
            if let data = try? JSONSerialization.data(withJSONObject: json) { line(data) }
        }
        cursor.offset = UInt64(max(0, settledThrough + 1))

        // Where the conversation stands now, for the parser to settle or end its turn.
        let moment = last.meta.completed ?? last.meta.created ?? cursor.modified.timeIntervalSince1970
        let tail: [String: Any] = ["type": "tail", "time": moment,
                                   "settled": settledStatuses.contains(last.status) && last.kind != Kind.userInput]
        if let data = try? JSONSerialization.data(withJSONObject: tail) { line(data) }
    }

    /// Model names by the negated model number a step records, and by the
    /// step a request answered, for a step that records no number.
    private static func modelNames(_ db: OpaquePointer?) -> [Int64: String] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT data FROM gen_metadata ORDER BY idx", -1, &stmt, nil) == SQLITE_OK
        else { return [:] }
        defer { sqlite3_finalize(stmt) }
        var names: [Int64: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let data = blob(stmt, 0), let request = Protobuf.message(data, field: 1) else { continue }
            guard let model = Protobuf.string(request, field: 19), !model.isEmpty else { continue }
            if let usage = Protobuf.message(request, field: 4), let number = Protobuf.varint(usage, field: 1) {
                names[-Int64(number)] = model
            }
            for entry in Protobuf.messages(request, field: 20)
            where Protobuf.string(entry, field: 1) == "last_step_index" {
                if let text = Protobuf.string(entry, field: 2), let step = Int64(text) { names[step + 1] = model }
            }
        }
        return names
    }

    /// The folder the conversation works in, from the first file URL its
    /// metadata names.
    private static func workspace(_ db: OpaquePointer?) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT data FROM trajectory_metadata_blob LIMIT 1", -1, &stmt, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let data = blob(stmt, 0) else { return nil }
        let marker = Data("file:///".utf8)
        guard let start = data.range(of: marker)?.lowerBound else { return nil }
        var end = start
        while end < data.endIndex, data[end] > 0x20, data[end] < 0x7f, data[end] != 0x22 { end += 1 }
        guard let text = String(data: data[start..<end], encoding: .utf8), let url = URL(string: text),
              !url.path.isEmpty else { return nil }
        return AgentLogParser.projectName(url.path)
    }

    private static func blob(_ stmt: OpaquePointer?, _ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, column)))
    }

    struct Usage {
        var input = 0
        var cacheRead = 0
        var output = 0
        var reasoning = 0
    }

    /// The parts of a step's metadata the island reads.
    struct StepMeta {
        var created: Double?
        var completed: Double?
        var usage: Usage?
        var modelEnum: Int64 = 0

        init() {}

        init(_ data: Data) {
            created = Protobuf.message(data, field: 1).flatMap(Protobuf.timestamp)
            completed = Protobuf.message(data, field: 8).flatMap(Protobuf.timestamp)
            modelEnum = Int64(Protobuf.varint(data, field: 11) ?? 0)
            if let counts = Protobuf.message(data, field: 9) {
                let input = Int(Protobuf.varint(counts, field: 2) ?? 0)
                let output = Int(Protobuf.varint(counts, field: 3) ?? 0)
                let cached = Int(Protobuf.varint(counts, field: 5) ?? 0)
                let thinking = Int(Protobuf.varint(counts, field: 9) ?? 0)
                if input + output + cached + thinking > 0 {
                    usage = Usage(input: input, cacheRead: cached, output: output, reasoning: thinking)
                }
            }
        }
    }
}

/// Just enough protobuf wire format to pick fields out of a message without
/// its schema.
enum Protobuf {
    enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    /// Every top-level field, in order; nil when the bytes are not a message.
    static func fields(_ data: Data) -> [(number: Int, value: Value)]? {
        var result: [(Int, Value)] = []
        var index = data.startIndex
        func varint() -> UInt64? {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while index < data.endIndex, shift < 64 {
                let byte = data[index]
                index += 1
                value |= UInt64(byte & 0x7f) << shift
                if byte < 0x80 { return value }
                shift += 7
            }
            return nil
        }
        while index < data.endIndex {
            guard let key = varint() else { return nil }
            let number = Int(key >> 3)
            guard number > 0 else { return nil }
            switch key & 7 {
            case 0:
                guard let value = varint() else { return nil }
                result.append((number, .varint(value)))
            case 1:
                guard data.endIndex - index >= 8 else { return nil }
                index += 8
            case 2:
                guard let length = varint(), length <= UInt64(data.endIndex - index) else { return nil }
                let end = index + Int(length)
                result.append((number, .bytes(data.subdata(in: index..<end))))
                index = end
            case 5:
                guard data.endIndex - index >= 4 else { return nil }
                index += 4
            default:
                return nil
            }
        }
        return result
    }

    static func varint(_ data: Data, field: Int) -> UInt64? {
        for entry in fields(data) ?? [] where entry.number == field {
            if case .varint(let value) = entry.value { return value }
        }
        return nil
    }

    static func message(_ data: Data, field: Int) -> Data? {
        messages(data, field: field).first
    }

    static func messages(_ data: Data, field: Int) -> [Data] {
        (fields(data) ?? []).compactMap { entry in
            guard entry.number == field, case .bytes(let bytes) = entry.value else { return nil }
            return bytes
        }
    }

    static func string(_ data: Data, field: Int) -> String? {
        message(data, field: field).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// A google.protobuf.Timestamp, as seconds since 1970.
    static func timestamp(_ data: Data) -> Double? {
        guard let seconds = varint(data, field: 1) else { return nil }
        return Double(seconds) + Double(varint(data, field: 2) ?? 0) / 1_000_000_000
    }
}
