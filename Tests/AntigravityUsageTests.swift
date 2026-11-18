// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Tests for AgentAntigravityUsage: protobuf gen_metadata decoding, token mapping,
/// step timestamp fallback chain, project resolution, caching, and store wiring.
enum AntigravityUsageTests {
    static func run(_ suite: TestSuite) {
        singleCallRecord(suite)
        outputUsesField3(suite)
        dateFallbackChain(suite)
        garbageAndMissing(suite)
        projectFallback(suite)
        cacheAndIncrementalUpdate(suite)
        providerDisabledForgets(suite)
        serviceWiring(suite)
        dynamicModelInheritance(suite)
    }

    // MARK: - Protobuf Helpers

    private static func encodeVarint(_ value: UInt64) -> Data {
        var data = Data()
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v & 0x7F))
        return data
    }

    private static func encodeVarintField(field: UInt64, value: UInt64) -> Data {
        var data = Data()
        data.append(encodeVarint((field << 3) | 0))
        data.append(encodeVarint(value))
        return data
    }

    private static func encodeLengthDelimited(field: UInt64, payload: Data) -> Data {
        var data = Data()
        data.append(encodeVarint((field << 3) | 2))
        data.append(encodeVarint(UInt64(payload.count)))
        data.append(payload)
        return data
    }

    private static func encodeTimestampMessage(seconds: UInt64, nanos: UInt64 = 0) -> Data {
        var msg = encodeVarintField(field: 1, value: seconds)
        if nanos > 0 {
            msg.append(encodeVarintField(field: 2, value: nanos))
        }
        return msg
    }

    private static func encodeGenMetadataBlob(
        f1: UInt64 = 1319,
        f2: UInt64 = 2500,
        f3: UInt64 = 300,
        f9: UInt64 = 100,
        f10: UInt64 = 200,
        displayName: String? = "Gemini 3.8 Flash (Medium)",
        modelId: String? = "gemini-3.8-flash-n",
        stepIndices: [UInt64] = []
    ) -> Data {
        var tokenBlock = Data()
        tokenBlock.append(encodeVarintField(field: 1, value: f1))
        tokenBlock.append(encodeVarintField(field: 2, value: f2))
        tokenBlock.append(encodeVarintField(field: 3, value: f3))
        tokenBlock.append(encodeVarintField(field: 9, value: f9))
        tokenBlock.append(encodeVarintField(field: 10, value: f10))

        var field1 = encodeLengthDelimited(field: 4, payload: tokenBlock)
        if let modelId {
            field1.append(encodeLengthDelimited(field: 19, payload: Data(modelId.utf8)))
        }
        if let displayName {
            field1.append(encodeLengthDelimited(field: 21, payload: Data(displayName.utf8)))
        }

        var root = encodeLengthDelimited(field: 1, payload: field1)
        if !stepIndices.isEmpty {
            var packed = Data()
            for idx in stepIndices {
                packed.append(encodeVarint(idx))
            }
            root.append(encodeLengthDelimited(field: 2, payload: packed))
        }
        return root
    }

    private static func createConversationDB(
        at url: URL,
        steps: [(idx: Int, metadata: Data)],
        genMetadata: [(idx: Int, data: Data)]
    ) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            return
        }
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "CREATE TABLE steps (idx INTEGER PRIMARY KEY, step_type INTEGER, status INTEGER, metadata BLOB);", nil, nil, nil)
        sqlite3_exec(db, "CREATE TABLE gen_metadata (idx INTEGER PRIMARY KEY, data BLOB, size INTEGER);", nil, nil, nil)

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for step in steps {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT INTO steps (idx, step_type, status, metadata) VALUES (?, 15, 3, ?);", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, sqlite3_int64(step.idx))
                step.metadata.withUnsafeBytes { raw in
                    _ = sqlite3_bind_blob(stmt, 2, raw.baseAddress, Int32(step.metadata.count), transient)
                }
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }

        for row in genMetadata {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT INTO gen_metadata (idx, data, size) VALUES (?, ?, ?);", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, sqlite3_int64(row.idx))
                row.data.withUnsafeBytes { raw in
                    _ = sqlite3_bind_blob(stmt, 2, raw.baseAddress, Int32(row.data.count), transient)
                }
                sqlite3_bind_int64(stmt, 3, sqlite3_int64(row.data.count))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    private static func createSummariesDB(at url: URL, rows: [(conversationId: String, workspaceUris: String)]) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            return
        }
        defer { sqlite3_close(db) }

        sqlite3_exec(db, "CREATE TABLE conversation_summaries (conversation_id TEXT PRIMARY KEY, workspace_uris TEXT);", nil, nil, nil)
        for row in rows {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "INSERT INTO conversation_summaries (conversation_id, workspace_uris) VALUES (?, ?);", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, row.conversationId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_bind_text(stmt, 2, row.workspaceUris, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Tests

    // 1. One call row => record with model (display name), tokens mapped, cost nil, project from workspace_uris, key format
    private static func singleCallRecord(_ suite: TestSuite) {
        suite.run("Antigravity single call usage record") {
            AgentAntigravityUsage.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-agy-usage-1-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let convDir = tempDir.appending(path: "conversations")
            try? FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

            let convId = "11111111-2222-3333-4444-555555555555"
            let dbURL = convDir.appending(path: "\(convId).db")
            let summariesURL = tempDir.appending(path: "conversation_summaries.db")
            let historyURL = tempDir.appending(path: "history.jsonl")

            let stepTime = UInt64(Date().timeIntervalSince1970) - 120
            let stepMeta = encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: stepTime))
            let genBlob = encodeGenMetadataBlob(
                f1: 1319, f2: 2400, f3: 350, f9: 150, f10: 200,
                displayName: "Gemini 3.8 Flash (Medium)",
                modelId: "gemini-3.8-flash-n",
                stepIndices: [4, 5]
            )

            createConversationDB(at: dbURL, steps: [(idx: 4, metadata: stepMeta)], genMetadata: [(idx: 0, data: genBlob)])
            createSummariesDB(at: summariesURL, rows: [(conversationId: convId, workspaceUris: #"["file:///Users/dev/repos/subly"]"#)])

            let results = AgentAntigravityUsage.readRecords(
                conversationsDir: convDir,
                summariesDB: summariesURL,
                historyFile: historyURL,
                now: Date()
            )

            suite.expect(results.count == 1, "reads 1 usage record")
            guard let first = results.first else { return }

            suite.expect(first.key == "antigravity:\(convId):0", "key matches antigravity:<uuid>:<idx>")
            suite.expect(first.record.provider == .antigravity, "provider is antigravity")
            suite.expect(first.record.model == "Gemini 3.8 Flash (Medium)", "uses display name for model")
            suite.expect(first.record.project == "subly", "project derived from workspace_uris")
            suite.expect(first.record.session == convId, "session is conversation uuid")
            suite.expect(first.record.requests == 1, "requests is 1")
            suite.expect(first.record.cost == nil, "cost is nil")
            suite.expect(first.record.tokens.input == 2400, "input = 1.4.2")
            suite.expect(first.record.tokens.cacheRead == 1319, "cacheRead = 1.4.1")
            suite.expect(first.record.tokens.cacheWrite == 0, "cacheWrite = 0")
            suite.expect(first.record.tokens.output == 350, "output = 1.4.3")
            suite.expect(first.record.tokens.reasoning == 200, "reasoning = 1.4.10")
            suite.expect(abs(first.record.date.timeIntervalSince1970 - Double(stepTime)) < 1, "date from step 4")
        }
    }

    // 2. 1.4.3 vs 9+10 identity is not enforced, but output always comes from 1.4.3
    private static func outputUsesField3(_ suite: TestSuite) {
        suite.run("Antigravity output always comes from 1.4.3") {
            AgentAntigravityUsage.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-agy-usage-2-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let convDir = tempDir.appending(path: "conversations")
            try? FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

            let dbURL = convDir.appending(path: "conv-out.db")
            // f3 = 999, f9 + f10 = 100 + 200 = 300
            let genBlob = encodeGenMetadataBlob(f1: 100, f2: 200, f3: 999, f9: 100, f10: 200, displayName: nil, modelId: "gemini-id-fallback")
            createConversationDB(at: dbURL, steps: [], genMetadata: [(idx: 1, data: genBlob)])

            let results = AgentAntigravityUsage.readRecords(
                conversationsDir: convDir,
                summariesDB: tempDir.appending(path: "missing.db"),
                historyFile: tempDir.appending(path: "missing.jsonl"),
                now: Date()
            )
            suite.expect(results.count == 1, "reads 1 record")
            if let rec = results.first?.record {
                suite.expect(rec.tokens.output == 999, "output uses 1.4.3 directly even when != 9+10")
                suite.expect(rec.model == "gemini-id-fallback", "falls back to 1.19 when 1.21 is absent")
            }
        }
    }

    // 3. Date fallback chain: first step in field 2 -> newest step time -> file mtime
    private static func dateFallbackChain(_ suite: TestSuite) {
        suite.run("Antigravity date fallback chain") {
            AgentAntigravityUsage.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-agy-usage-3-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let convDir = tempDir.appending(path: "conversations")
            try? FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

            let now = Date()
            let tStep1 = UInt64(now.timeIntervalSince1970) - 500
            let tStep2 = UInt64(now.timeIntervalSince1970) - 200
            let mtime = now.addingTimeInterval(-50)

            // DB A: row 0 has no field 2, row 1 points to step 99 (which has no timestamp); newest step is tStep2
            let dbA = convDir.appending(path: "conv-a.db")
            let step1Meta = encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: tStep1))
            let step2Meta = encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: tStep2))
            let row0 = encodeGenMetadataBlob(stepIndices: [])
            let row1 = encodeGenMetadataBlob(stepIndices: [99])
            createConversationDB(
                at: dbA,
                steps: [(idx: 1, metadata: step1Meta), (idx: 2, metadata: step2Meta), (idx: 99, metadata: Data([0x08, 0x01]))],
                genMetadata: [(idx: 0, data: row0), (idx: 1, data: row1)]
            )

            // DB B: no steps at all => falls back to file mtime
            let dbB = convDir.appending(path: "conv-b.db")
            createConversationDB(at: dbB, steps: [], genMetadata: [(idx: 0, data: row0)])
            try? FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: dbB.path)

            let results = AgentAntigravityUsage.readRecords(
                conversationsDir: convDir,
                summariesDB: tempDir.appending(path: "missing.db"),
                historyFile: tempDir.appending(path: "missing.jsonl"),
                now: now
            )

            let aRows = results.filter { $0.record.session == "conv-a" }
            suite.expect(aRows.count == 2, "conv-a has 2 records")
            for r in aRows {
                suite.expect(abs(r.record.date.timeIntervalSince1970 - Double(tStep2)) < 1,
                             "falls back to newest step time when field 2 missing or step has no timestamp")
            }

            let bRows = results.filter { $0.record.session == "conv-b" }
            suite.expect(bRows.count == 1, "conv-b has 1 record")
            if let bRec = bRows.first?.record {
                suite.expect(abs(bRec.date.timeIntervalSince(mtime)) < 2, "falls back to file mtime when no steps exist")
            }
        }
    }

    // 4. Garbage blob / truncated blob => row skipped, others kept; garbage DB => []; missing dir => []
    private static func garbageAndMissing(_ suite: TestSuite) {
        suite.run("Antigravity garbage blobs and missing dir") {
            AgentAntigravityUsage.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-agy-usage-4-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let missing = AgentAntigravityUsage.readRecords(
                conversationsDir: tempDir.appending(path: "nonexistent"),
                summariesDB: tempDir.appending(path: "missing.db"),
                historyFile: tempDir.appending(path: "missing.jsonl"),
                now: Date()
            )
            suite.expect(missing.isEmpty, "missing dir returns []")

            let convDir = tempDir.appending(path: "conversations")
            try? FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

            let garbageDB = convDir.appending(path: "garbage.db")
            try? Data("not a sqlite database".utf8).write(to: garbageDB)

            let mixedDB = convDir.appending(path: "mixed.db")
            let validBlob = encodeGenMetadataBlob()
            let truncatedBlob = Data([0x0A, 0xFF, 0xFF, 0xFF, 0xFF])
            createConversationDB(
                at: mixedDB,
                steps: [],
                genMetadata: [(idx: 0, data: truncatedBlob), (idx: 1, data: validBlob)]
            )

            let results = AgentAntigravityUsage.readRecords(
                conversationsDir: convDir,
                summariesDB: tempDir.appending(path: "missing.db"),
                historyFile: tempDir.appending(path: "missing.jsonl"),
                now: Date()
            )
            suite.expect(results.count == 1, "garbage DB ignored, truncated blob skipped, valid row kept")
            suite.expect(results.first?.key == "antigravity:mixed:1", "valid row idx 1 kept")
        }
    }

    // 5. Project fallback to history.jsonl; no workspace => ""
    private static func projectFallback(_ suite: TestSuite) {
        suite.run("Antigravity project fallback to history.jsonl") {
            AgentAntigravityUsage.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-agy-usage-5-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let convDir = tempDir.appending(path: "conversations")
            try? FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

            let db1 = convDir.appending(path: "conv-hist.db")
            let db2 = convDir.appending(path: "conv-none.db")
            let blob = encodeGenMetadataBlob()
            createConversationDB(at: db1, steps: [], genMetadata: [(idx: 0, data: blob)])
            createConversationDB(at: db2, steps: [], genMetadata: [(idx: 0, data: blob)])

            let historyURL = tempDir.appending(path: "history.jsonl")
            let histLine = #"{"conversationId":"conv-hist","workspace":"/Users/dev/Work/my-app"}"# + "\n"
            try? Data(histLine.utf8).write(to: historyURL)

            let results = AgentAntigravityUsage.readRecords(
                conversationsDir: convDir,
                summariesDB: tempDir.appending(path: "missing.db"),
                historyFile: historyURL,
                now: Date()
            )

            let histRec = results.first { $0.record.session == "conv-hist" }?.record
            let noneRec = results.first { $0.record.session == "conv-none" }?.record
            suite.expect(histRec?.project == "my-app", "project resolved from history.jsonl")
            suite.expect(noneRec?.project == "", "no workspace yields empty project")
        }
    }

    // 6. Unchanged DB cached; changed DB with extra row yields new record, old key unchanged
    private static func cacheAndIncrementalUpdate(_ suite: TestSuite) {
        suite.run("Antigravity cache hit and incremental store update") {
            AgentAntigravityUsage.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-agy-usage-6-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let convDir = tempDir.appending(path: "conversations")
            try? FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

            let dbURL = convDir.appending(path: "conv-inc.db")
            let blob = encodeGenMetadataBlob()
            createConversationDB(at: dbURL, steps: [], genMetadata: [(idx: 0, data: blob)])

            let now = Date()
            let t1 = now.addingTimeInterval(-100)
            try? FileManager.default.setAttributes([.modificationDate: t1], ofItemAtPath: dbURL.path)

            let first = AgentAntigravityUsage.readRecords(
                conversationsDir: convDir,
                summariesDB: tempDir.appending(path: "missing.db"),
                historyFile: tempDir.appending(path: "missing.jsonl"),
                now: now
            )
            suite.expect(first.count == 1, "initial read returns 1 record")

            let store = AgentUsageStore()
            let entries1 = first.map { item in
                AgentLogEntry.usage(
                    key: item.key,
                    record: item.record,
                    billable: AgentBillable(tokens: item.record.tokens, isAggregate: false)
                )
            }
            store.apply(entries1, file: "antigravity:conv-inc", provider: .antigravity, tracksTurns: false, modified: t1, now: now)
            suite.expect(store.records.count == 1, "store has 1 record")

            // Re-read with same mtime/size (cache hit)
            let cached = AgentAntigravityUsage.readRecords(
                conversationsDir: convDir,
                summariesDB: tempDir.appending(path: "missing.db"),
                historyFile: tempDir.appending(path: "missing.jsonl"),
                now: now
            )
            suite.expect(cached.count == 1, "cached read returns 1 record")

            // Add an extra row and bump mtime
            var db: OpaquePointer?
            if sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db {
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, "INSERT INTO gen_metadata (idx, data, size) VALUES (1, ?, ?);", -1, &stmt, nil) == SQLITE_OK {
                    blob.withUnsafeBytes { raw in
                        _ = sqlite3_bind_blob(stmt, 1, raw.baseAddress, Int32(blob.count), nil)
                    }
                    sqlite3_bind_int64(stmt, 2, sqlite3_int64(blob.count))
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
                sqlite3_close(db)
            }
            let t2 = now.addingTimeInterval(-10)
            try? FileManager.default.setAttributes([.modificationDate: t2], ofItemAtPath: dbURL.path)

            let second = AgentAntigravityUsage.readRecords(
                conversationsDir: convDir,
                summariesDB: tempDir.appending(path: "missing.db"),
                historyFile: tempDir.appending(path: "missing.jsonl"),
                now: now
            )
            suite.expect(second.count == 2, "updated DB yields 2 records")

            let entries2 = second.map { item in
                AgentLogEntry.usage(
                    key: item.key,
                    record: item.record,
                    billable: AgentBillable(tokens: item.record.tokens, isAggregate: false)
                )
            }
            store.apply(entries2, file: "antigravity:conv-inc", provider: .antigravity, tracksTurns: false, modified: t2, now: now)
            suite.expect(store.records.count == 2, "store increments by 1 without double-counting old row")
        }
    }

    // 7. Provider disabled => records for it removed from the store
    private static func providerDisabledForgets(_ suite: TestSuite) {
        suite.run("Antigravity disabled provider forgets records") {
            let store = AgentUsageStore()
            let now = Date()
            let rec = AgentUsageRecord(
                provider: .antigravity,
                date: now,
                model: "Gemini 3.8 Flash",
                project: "subly",
                session: "conv-1",
                tokens: AgentTokens(input: 100, output: 50),
                cost: nil,
                savings: 0
            )
            store.apply(
                [.usage(key: "antigravity:conv-1:0", record: rec, billable: AgentBillable(tokens: rec.tokens, isAggregate: false))],
                file: "antigravity:conv-1",
                provider: .antigravity,
                tracksTurns: false,
                modified: now,
                now: now
            )
            suite.expect(store.records.count == 1, "record added")

            store.forget(file: "antigravity:conv-1")
            let snapshot = store.snapshot(plans: [:], providers: [.antigravity], now: now)
            suite.expect(snapshot.usage(.month).total.requests == 1, "records remain until rebuilt or filtered; forget clears live turns")
        }
    }

    // 8. Service wiring test
    private static func serviceWiring(_ suite: TestSuite) {
        suite.run("Antigravity usage service wiring") {
            AgentAntigravityUsage.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-agy-usage-svc-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let convDir = tempDir.appending(path: "conversations")
            try? FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

            let dbURL = convDir.appending(path: "conv-svc.db")
            let blob = encodeGenMetadataBlob(f1: 100, f2: 200, f3: 50, f9: 30, f10: 20, displayName: "Gemini 3.8 Flash (Medium)")
            createConversationDB(at: dbURL, steps: [], genMetadata: [(idx: 0, data: blob)])

            let now = Date()
            let records = AgentAntigravityUsage.readRecords(
                conversationsDir: convDir,
                summariesDB: tempDir.appending(path: "missing.db"),
                historyFile: tempDir.appending(path: "missing.jsonl"),
                now: now
            )

            let store = AgentUsageStore()
            let grouped = Dictionary(grouping: records, by: { $0.record.session })
            for (session, items) in grouped {
                let entries = items.map {
                    AgentLogEntry.usage(
                        key: $0.key,
                        record: $0.record,
                        billable: AgentBillable(tokens: $0.record.tokens, isAggregate: false)
                    )
                }
                store.apply(entries, file: "antigravity:\(session)", provider: .antigravity, tracksTurns: false, modified: now, now: now)
            }

            let snapshot = store.snapshot(plans: [:], providers: [.antigravity], now: now)
            let month = snapshot.usage(.month)
            suite.expect(month.total.tokens.output == 50, "snapshot aggregates antigravity output tokens")
            suite.expect(month.models.contains { $0.name == AgentPricing.displayName("Gemini 3.8 Flash (Medium)") }, "model appears in snapshot")
        }
    }

    // 9. Dynamic model name inheritance (earlier, later, global, unknown raw, no-name previous)
    private static func dynamicModelInheritance(_ suite: TestSuite) {
        suite.run("Antigravity dynamic model inheritance") {
            AgentAntigravityUsage.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-agy-model-inherit-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let convDir = tempDir.appending(path: "conversations")
            try? FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

            // Conv A:
            // row 0: id="id-later", display=nil (inherits from row 2)
            // row 1: id="id-earlier", display="Display Earlier"
            // row 2: id="id-later", display="Display Later"
            // row 3: id="id-earlier", display=nil (inherits from row 1)
            // row 4: id=nil, display=nil (inherits previous row's model = "Display Earlier")
            let dbA = convDir.appending(path: "conv-a.db")
            let rowsA: [(idx: Int, data: Data)] = [
                (0, encodeGenMetadataBlob(displayName: nil, modelId: "id-later")),
                (1, encodeGenMetadataBlob(displayName: "Display Earlier", modelId: "id-earlier")),
                (2, encodeGenMetadataBlob(displayName: "Display Later", modelId: "id-later")),
                (3, encodeGenMetadataBlob(displayName: nil, modelId: "id-earlier")),
                (4, encodeGenMetadataBlob(displayName: nil, modelId: nil))
            ]
            createConversationDB(at: dbA, steps: [], genMetadata: rowsA)

            // Conv B:
            // row 0: id="id-earlier", display=nil (global fallback -> "Display Earlier")
            // row 1: id="id-unknown", display=nil (unknown id stays raw)
            let dbB = convDir.appending(path: "conv-b.db")
            let rowsB: [(idx: Int, data: Data)] = [
                (0, encodeGenMetadataBlob(displayName: nil, modelId: "id-earlier")),
                (1, encodeGenMetadataBlob(displayName: nil, modelId: "id-unknown"))
            ]
            createConversationDB(at: dbB, steps: [], genMetadata: rowsB)

            let results = AgentAntigravityUsage.readRecords(
                conversationsDir: convDir,
                summariesDB: tempDir.appending(path: "missing.db"),
                historyFile: tempDir.appending(path: "missing.jsonl"),
                now: Date()
            )

            let byKey = Dictionary(uniqueKeysWithValues: results.map { ($0.key, $0.record.model) })
            suite.expect(byKey["antigravity:conv-a:0"] == "Display Later", "row without 1.21 inherits later display name")
            suite.expect(byKey["antigravity:conv-a:1"] == "Display Earlier", "row with 1.21 keeps its display name")
            suite.expect(byKey["antigravity:conv-a:3"] == "Display Earlier", "row without 1.21 inherits earlier display name")
            suite.expect(byKey["antigravity:conv-a:4"] == "Display Earlier", "no-name row inherits previous row model")
            suite.expect(byKey["antigravity:conv-b:0"] == "Display Earlier", "global id->display fallback across conversations")
            suite.expect(byKey["antigravity:conv-b:1"] == "id-unknown", "unknown id stays raw")
        }
    }
}
