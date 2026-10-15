// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Antigravity CLI conversations: one SQLite database each, with protobuf rows.
enum AntigravityAgentTests {
    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-agy-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "c0ffee.db").path

        suite.expect(AgentAntigravityReader.isConversation(path, in: folder)
                        && !AgentAntigravityReader.isConversation(folder.appending(path: "x/y.db").path, in: folder)
                        && !AgentAntigravityReader.isConversation(path + "-wal", in: folder),
                     "only databases directly in the conversations folder are conversations")

        let now = Date()
        let start = UInt64(now.timeIntervalSince1970) - 20
        let prompt = message([(1, .bytes(message([(1, .varint(start))])))])
        let response = message([
            (1, .bytes(message([(1, .varint(start + 1))]))),
            (8, .bytes(message([(1, .varint(start + 5))]))),
            (9, .bytes(message([(1, .varint(1318)), (2, .varint(1000)), (3, .varint(200)),
                                (5, .varint(9000)), (9, .varint(50))]))),
            (11, .varint(1318)),
        ])
        let running = message([(1, .bytes(message([(1, .varint(start + 6))])))])
        let request = message([(1, .bytes(message([
            (4, .bytes(message([(1, .varint(1318)), (2, .varint(1000))]))),
            (19, .bytes(Data("gemini-3.8-flash-n".utf8))),
            (20, .bytes(message([(1, .bytes(Data("last_step_index".utf8))), (2, .bytes(Data("0".utf8)))]))),
        ])))])
        let trajectory = message([(1, .bytes(message([(1, .bytes(Data("file:///Users/me/rocket".utf8)))])))])

        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            suite.expect(false, "the test conversation opens")
            return
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, """
        CREATE TABLE steps (idx integer PRIMARY KEY, step_type integer, status integer, metadata blob);
        CREATE TABLE gen_metadata (idx integer PRIMARY KEY, data blob, size integer);
        CREATE TABLE trajectory_metadata_blob (id text PRIMARY KEY, data blob);
        """, nil, nil, nil)
        func insert(_ sql: String, _ blobs: [Data], _ ints: [Int64] = []) {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            for (index, value) in ints.enumerated() { sqlite3_bind_int64(stmt, Int32(index + 1), value) }
            for (index, blob) in blobs.enumerated() {
                _ = blob.withUnsafeBytes {
                    sqlite3_bind_blob(stmt, Int32(ints.count + index + 1), $0.baseAddress, Int32(blob.count),
                                      unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        insert("INSERT INTO steps VALUES (?, ?, ?, ?)", [prompt], [0, 14, 3])
        insert("INSERT INTO steps VALUES (?, ?, ?, ?)", [response], [1, 15, 3])
        insert("INSERT INTO steps VALUES (?, ?, ?, ?)", [running], [2, 132, 2])
        insert("INSERT INTO gen_metadata VALUES (0, ?, 0)", [request])
        insert("INSERT INTO trajectory_metadata_blob VALUES ('main', ?)", [trajectory])
        sqlite3_close(db)
        // Antigravity closes a conversation the same way, leaving no -wal or -shm beside it.
        try? FileManager.default.removeItem(atPath: path + "-wal")
        try? FileManager.default.removeItem(atPath: path + "-shm")

        let cursor = AgentLogCursor(path: path, provider: .antigravity)
        let store = AgentUsageStore()
        func read() {
            var entries: [AgentLogEntry] = []
            AgentAntigravityReader.readAppended(cursor) { line in
                entries += AgentLogParser.parseAntigravity(line, state: &cursor.state, now: now)
            }
            store.apply(entries, file: path, provider: .antigravity, tracksTurns: true, modified: now, now: now)
        }
        read()

        let record = store.records.first
        suite.expect(store.records.count == 1 && record?.model == "gemini-3.8-flash-n" && record?.project == "rocket"
                        && record?.tokens == AgentTokens(input: 1000, cacheRead: 9000, output: 250, reasoning: 50),
                     "a closed WAL conversation is read, counting its model, folder and tokens, thinking as output")
        let expected = (1000 * 0.75 + 9000 * 0.075 + 250 * 3.75) / 1_000_000
        suite.expect(abs((record?.cost ?? 0) - expected) < 1e-12, "Gemini responses are priced from the Gemini list")
        suite.expect(cursor.offset == 2, "reading stops before the step still running")
        suite.expect(store.live.first?.provider == .antigravity && store.live.first?.project == "rocket",
                     "a running step keeps the turn live")

        read()
        suite.expect(store.records.count == 1 && store.records.first?.tokens.total == record?.tokens.total,
                     "reading a running step again does not count anything twice")

        limits(suite)
        suite.expect(AgentPricing.price(for: AgentLogParser.antigravityModels["gemini-pro-default"] ?? "") != nil
                        && AgentPricing.price(for: "gemini-3.8-flash-lite") == nil,
                     "Antigravity's Pro alias is priced and an unlisted sibling is not")
    }

    static func limits(_ suite: TestSuite) {
        let output = """
        some log line
        {"status":"SUCCESS","num_turns":0,"command":{"name":"usage","data":{"groups":[
        {"name":"Gemini Models","buckets":[
        {"id":"gemini-weekly","window":"weekly","remaining_fraction":0.9,"reset_time":"2026-10-16T19:06:56Z"},
        {"id":"gemini-5h","window":"5h","remaining_fraction":0.97,"reset_time":"2026-10-11T18:39:47Z"}]},
        {"name":"Claude and GPT models","buckets":[
        {"id":"3p-weekly","window":"weekly","remaining_fraction":0.5,"reset_time":"2026-10-16T19:45:23Z"},
        {"id":"3p-5h","window":"5h","remaining_fraction":0.6,"reset_time":"2026-10-11T20:27:52Z"},
        {"id":"off","window":"5h","remaining_fraction":0,"disabled":true}]}]}}}
        """.replacingOccurrences(of: "\n{\"id", with: "{\"id").replacingOccurrences(of: "\n{\"name", with: "{\"name")
            .replacingOccurrences(of: "[\n", with: "[")
        let limits = AgentAntigravityLimits.parse(output, observed: Date())
        let windows = limits?.windows ?? []
        suite.expect(limits?.provider == .antigravity && limits?.source == .account && windows.count == 2,
                     "only the Gemini group's limits are shown, not the Claude and GPT ones")
        suite.expect(windows.contains { $0.kind == .session && $0.scope == nil && abs($0.usedPercent - 3) < 0.001
                                        && $0.resetsAt != nil }
                        && windows.contains { $0.kind == .weekly && $0.scope == nil && abs($0.usedPercent - 10) < 0.001 },
                     "the five-hour bucket is the session and the weekly bucket the week")
        suite.expect(AgentAntigravityLimits.parse("{\"status\":\"SUCCESS\",\"response\":\"hi\"}", observed: Date()) == nil,
                     "a reply that is not the usage command gives no limits")
        suite.expect(AgentAntigravityLimits.parseVersion("agy 1.3.3")?.lexicographicallyPrecedes(
                        AgentAntigravityLimits.minimumVersion) == false
                        && AgentAntigravityLimits.parseVersion("1.1.9")?.lexicographicallyPrecedes(
                        AgentAntigravityLimits.minimumVersion) == true,
                     "agy older than 1.1.11 is never asked, since it would spend quota on the question")
    }

    private enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    private static func message(_ fields: [(Int, Value)]) -> Data {
        var data = Data()
        func varint(_ value: UInt64) {
            var value = value
            while value >= 0x80 {
                data.append(UInt8(value & 0x7f) | 0x80)
                value >>= 7
            }
            data.append(UInt8(value))
        }
        for (number, value) in fields {
            switch value {
            case .varint(let raw):
                varint(UInt64(number) << 3)
                varint(raw)
            case .bytes(let bytes):
                varint(UInt64(number) << 3 | 2)
                varint(UInt64(bytes.count))
                data.append(bytes)
            }
        }
        return data
    }
}
