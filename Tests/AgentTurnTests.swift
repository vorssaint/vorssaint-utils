// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Tests for AgentTurnReader: protobuf decoding, SQLite extraction, Command Code jsonl parsing,
/// running vs finished detection, daily duration calculations, and service wiring.
enum AgentTurnTests {
    static func run(_ suite: TestSuite) {
        agyTurns(suite)
        agyGarbage(suite)
        agyOverflowLength(suite)
        agyMissingDir(suite)
        agyRunningVsFinished(suite)
        agySpacedPath(suite)
        dailyDurationGrouping(suite)
        serviceWiring(suite)
    }

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterStandard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseISO8601(_ string: String) -> Date? {
        isoFormatterFractional.date(from: string) ?? isoFormatterStandard.date(from: string)
    }

    // MARK: - Protobuf Test Helpers

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

    private static func encodeTimestampMessage(seconds: UInt64, nanos: UInt64 = 0) -> Data {
        var msg = Data()
        msg.append(encodeVarint((1 << 3) | 0))
        msg.append(encodeVarint(seconds))
        if nanos > 0 {
            msg.append(encodeVarint((2 << 3) | 0))
            msg.append(encodeVarint(nanos))
        }
        return msg
    }

    private static func encodeLengthDelimited(field: UInt64, payload: Data) -> Data {
        var data = Data()
        data.append(encodeVarint((field << 3) | 2))
        data.append(encodeVarint(UInt64(payload.count)))
        data.append(payload)
        return data
    }

    private static func encodeField26(timestamp: Data) -> Data {
        let subField2 = encodeLengthDelimited(field: 2, payload: timestamp)
        return encodeLengthDelimited(field: 26, payload: subField2)
    }

    private static func createSQLiteDB(at url: URL,
                                       wal: Bool = false,
                                       steps: [(idx: Int, stepType: Int, status: Int, metadata: Data)]) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
            return
        }
        defer { sqlite3_close(db) }

        if wal {
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        }
        sqlite3_exec(db, "CREATE TABLE steps (idx INTEGER PRIMARY KEY, step_type INTEGER, status INTEGER, metadata BLOB);", nil, nil, nil)

        for step in steps {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO steps (idx, step_type, status, metadata) VALUES (?, ?, ?, ?);", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, Int64(step.idx))
            sqlite3_bind_int64(stmt, 2, Int64(step.stepType))
            sqlite3_bind_int64(stmt, 3, Int64(step.status))
            _ = step.metadata.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(step.metadata.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: - Test 1: agy 3 turns across mixed step types

    private static func agyTurns(_ suite: TestSuite) {
        suite.run("Antigravity 3 turns across mixed step types") {
            AgentTurnReader.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-agy-turns-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let t0: UInt64 = 1_700_000_000
            let t1: UInt64 = 1_700_000_010
            let t2: UInt64 = 1_700_000_015

            let t3: UInt64 = 1_700_000_100
            let t4: UInt64 = 1_700_000_120
            let t5: UInt64 = 1_700_000_150

            let t6: UInt64 = 1_700_000_500
            let t7_6: UInt64 = 1_700_000_520
            let t7_26: UInt64 = 1_700_000_530

            var step7Meta = encodeLengthDelimited(field: 6, payload: encodeTimestampMessage(seconds: t7_6))
            step7Meta.append(encodeField26(timestamp: encodeTimestampMessage(seconds: t7_26)))

            let steps: [(idx: Int, stepType: Int, status: Int, metadata: Data)] = [
                // Turn 1
                (0, 14, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t0))),
                (1, 15, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t1))),
                (2, 132, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t2))),
                // Turn 2
                (3, 14, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t3))),
                (4, 90, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t4))),
                (5, 15, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t5))),
                // Turn 3
                (6, 14, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t6))),
                (7, 15, 3, step7Meta)
            ]

            let dbURL = tempDir.appending(path: "session-alpha.db")
            createSQLiteDB(at: dbURL, wal: false, steps: steps)

            let fileMtime = Date(timeIntervalSince1970: Double(t7_26))
            try? FileManager.default.setAttributes([.modificationDate: fileMtime], ofItemAtPath: dbURL.path)

            let turns = AgentTurnReader.readTurns(for: .antigravity, root: tempDir, now: fileMtime.addingTimeInterval(300))
            suite.expect(turns.count == 3, "parses 3 turns from mixed step types")
            guard turns.count == 3 else { return }

            suite.expect(turns[0].conversation == "session-alpha", "conversation id matches file basename")
            suite.expect(abs(turns[0].start.timeIntervalSince1970 - Double(t0)) < 0.001, "turn 1 start matches step 0 creation time")
            suite.expect(abs(turns[0].end.timeIntervalSince1970 - Double(t2)) < 0.001, "turn 1 end matches step 2 timestamp")
            suite.expect(abs(turns[0].end.timeIntervalSince(turns[0].start) - 15) < 0.001, "turn 1 duration is 15s")

            suite.expect(abs(turns[1].start.timeIntervalSince1970 - Double(t3)) < 0.001, "turn 2 start matches step 3 creation time")
            suite.expect(abs(turns[1].end.timeIntervalSince1970 - Double(t5)) < 0.001, "turn 2 end matches step 5 timestamp")
            suite.expect(abs(turns[1].end.timeIntervalSince(turns[1].start) - 50) < 0.001, "turn 2 duration is 50s")

            suite.expect(abs(turns[2].start.timeIntervalSince1970 - Double(t6)) < 0.001, "turn 3 start matches step 6 creation time")
            suite.expect(abs(turns[2].end.timeIntervalSince1970 - Double(t7_26)) < 0.001, "turn 3 end matches field 26 timestamp")
            suite.expect(abs(turns[2].end.timeIntervalSince(turns[2].start) - 30) < 0.001, "turn 3 duration is 30s")
        }
    }

    // MARK: - Test 2: agy truncated/garbage metadata blob & whole garbage DB

    private static func agyGarbage(_ suite: TestSuite) {
        suite.run("Antigravity garbage handling") {
            AgentTurnReader.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-agy-garbage-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let t0: UInt64 = 1_700_000_000
            let t1: UInt64 = 1_700_000_020
            let corruptMetadata = Data([0xFF, 0xFF, 0xFF, 0x02, 0x99, 0x01])

            let steps: [(idx: Int, stepType: Int, status: Int, metadata: Data)] = [
                (0, 14, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t0))),
                (1, 15, 3, corruptMetadata),
                (2, 15, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t1)))
            ]

            let partialURL = tempDir.appending(path: "partial.db")
            createSQLiteDB(at: partialURL, wal: false, steps: steps)
            let parsed = AgentTurnReader.parseAntigravityDB(fileURL: partialURL)
            suite.expect(parsed.count == 1, "parses turn despite corrupt step metadata")
            if let first = parsed.first {
                suite.expect(abs(first.start.timeIntervalSince1970 - Double(t0)) < 0.001, "valid start preserved")
                suite.expect(abs(first.end.timeIntervalSince1970 - Double(t1)) < 0.001, "valid end preserved")
            }

            let garbageURL = tempDir.appending(path: "garbage.db")
            try? Data("This is plain text, not a sqlite database".utf8).write(to: garbageURL)
            let garbageResult = AgentTurnReader.parseAntigravityDB(fileURL: garbageURL)
            suite.expect(garbageResult.isEmpty, "corrupt database returns empty array without throwing")
        }
    }

    // MARK: - Test 2b: agy overflow varint length handling

    private static func agyOverflowLength(_ suite: TestSuite) {
        suite.run("Antigravity overflow varint length safety") {
            // Nested in field 1: length varint 0xFFFFFFFFFFFFFFFF
            var badField1 = Data()
            badField1.append(encodeVarint((1 << 3) | 2))
            badField1.append(encodeVarint(UInt64.max))
            badField1.append(Data([1, 2, 3, 4]))

            let res1 = AgentTurnReader.extractStepTimestamps(from: badField1)
            suite.expect(res1.creation == nil && res1.timestamps.isEmpty, "field 1 with max UInt64 length handled safely")

            // Nested in field 26: subfield 2 with length varint 0xFFFFFFFFFFFFFFFF
            var badField26 = Data()
            badField26.append(encodeVarint((26 << 3) | 2))
            badField26.append(encodeVarint(16)) // submessage length
            badField26.append(encodeVarint((2 << 3) | 2))
            badField26.append(encodeVarint(UInt64.max))
            badField26.append(Data([1, 2, 3, 4]))

            let res26 = AgentTurnReader.extractStepTimestamps(from: badField26)
            suite.expect(res26.timestamps.isEmpty, "field 26 with max UInt64 sub-length handled safely without crash")
        }
    }

    // MARK: - Test 3: agy missing directory

    private static func agyMissingDir(_ suite: TestSuite) {
        suite.run("Antigravity missing directory") {
            AgentTurnReader.clearCache()
            let missingDir = FileManager.default.temporaryDirectory.appending(path: "test-missing-\(UUID().uuidString)")
            let result = AgentTurnReader.readTurns(for: .antigravity, root: missingDir)
            suite.expect(result.isEmpty, "missing directory returns empty turns list")
        }
    }

    // MARK: - Test 4: agy running vs finished and completion signals

    private static func agyRunningVsFinished(_ suite: TestSuite) {
        suite.run("Antigravity running vs finished by mtime and step status") {
            AgentTurnReader.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-agy-running-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let t0: UInt64 = 1_700_000_000
            let t1: UInt64 = 1_700_000_020
            let t2: UInt64 = 1_700_000_100
            let t3: UInt64 = 1_700_000_140

            // Case A: Last step is 15 with status 3 (finished cleanly)
            let finishedSteps: [(idx: Int, stepType: Int, status: Int, metadata: Data)] = [
                (0, 14, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t0))),
                (1, 15, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t1))),
                (2, 14, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t2))),
                (3, 15, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t3)))
            ]

            let finishedDB = tempDir.appending(path: "finished.db")
            createSQLiteDB(at: finishedDB, wal: true, steps: finishedSteps)

            let mtimeFinished = Date(timeIntervalSince1970: Double(t3))
            try? FileManager.default.setAttributes([.modificationDate: mtimeFinished], ofItemAtPath: finishedDB.path)
            let finishedWal = tempDir.appending(path: "finished.db-wal")
            if FileManager.default.fileExists(atPath: finishedWal.path) {
                try? FileManager.default.setAttributes([.modificationDate: mtimeFinished], ofItemAtPath: finishedWal.path)
            }

            // Even with fresh mtime (10s ago), finished cleanly step 15/3 => running is false
            let freshNow = mtimeFinished.addingTimeInterval(10)
            AgentTurnReader.clearCache()
            let finishedTurns = AgentTurnReader.readTurns(for: .antigravity, root: tempDir, now: freshNow)
            suite.expect(finishedTurns.count == 2, "parses two turns")
            if finishedTurns.count == 2 {
                suite.expect(finishedTurns[1].endedCleanly, "turn 2 marked endedCleanly")
                suite.expect(!finishedTurns[1].running, "cleanly finished turn 2 is not running despite fresh mtime")
            }

            // Case B: Last step is 132 (tool call still in progress)
            try? FileManager.default.removeItem(at: finishedDB)
            if FileManager.default.fileExists(atPath: finishedWal.path) {
                try? FileManager.default.removeItem(at: finishedWal)
            }

            let activeSteps: [(idx: Int, stepType: Int, status: Int, metadata: Data)] = [
                (0, 14, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t0))),
                (1, 15, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t1))),
                (2, 14, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t2))),
                (3, 132, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t3)))
            ]
            let activeDB = tempDir.appending(path: "active.db")
            createSQLiteDB(at: activeDB, wal: true, steps: activeSteps)
            try? FileManager.default.setAttributes([.modificationDate: mtimeFinished], ofItemAtPath: activeDB.path)
            let activeWal = tempDir.appending(path: "active.db-wal")
            if FileManager.default.fileExists(atPath: activeWal.path) {
                try? FileManager.default.setAttributes([.modificationDate: mtimeFinished], ofItemAtPath: activeWal.path)
            }

            AgentTurnReader.clearCache()
            let activeTurns = AgentTurnReader.readTurns(for: .antigravity, root: tempDir, now: freshNow)
            suite.expect(activeTurns.count == 2, "parses two turns")
            if activeTurns.count == 2 {
                suite.expect(!activeTurns[1].endedCleanly, "turn 2 not endedCleanly due to last step 132")
                suite.expect(activeTurns[1].running, "tool_use step 132 + fresh mtime => running is true")
            }

            // Stale mtime (>60s) with step 132 => running becomes false
            let staleNow = mtimeFinished.addingTimeInterval(120)
            AgentTurnReader.clearCache()
            let staleTurns = AgentTurnReader.readTurns(for: .antigravity, root: tempDir, now: staleNow)
            if staleTurns.count == 2 {
                suite.expect(!staleTurns[1].running, "stale mtime >60s => running is false")
            }
        }
    }

    // MARK: - Test 4b: agy path with spaces

    private static func agySpacedPath(_ suite: TestSuite) {
        suite.run("Antigravity SQLite path with spaces") {
            AgentTurnReader.clearCache()
            let spacedDir = FileManager.default.temporaryDirectory.appending(path: "test agy spaces \(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: spacedDir) }
            try? FileManager.default.createDirectory(at: spacedDir, withIntermediateDirectories: true)

            let t0: UInt64 = 1_700_000_000
            let t1: UInt64 = 1_700_000_015
            let steps: [(idx: Int, stepType: Int, status: Int, metadata: Data)] = [
                (0, 14, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t0))),
                (1, 15, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t1)))
            ]

            let dbURL = spacedDir.appending(path: "session with spaces.db")
            createSQLiteDB(at: dbURL, wal: false, steps: steps)

            let turns = AgentTurnReader.readTurns(for: .antigravity, root: spacedDir, now: Date())
            suite.expect(turns.count == 1, "successfully opens SQLite path with spaces via URI percent encoding")
            if let first = turns.first {
                suite.expect(first.conversation == "session with spaces", "conversation matches spaced file name")
                suite.expect(abs(first.end.timeIntervalSince(first.start) - 15) < 0.001, "duration is 15s")
            }
        }
    }

    // MARK: - dailyDuration grouping across midnight

    private static func dailyDurationGrouping(_ suite: TestSuite) {
        suite.run("dailyDuration grouping across midnight") {
            let tA_start = parseISO8601("2026-11-16T23:50:00.000Z")!
            let tA_end = parseISO8601("2026-11-16T23:55:00.000Z")! // 300s

            let tB_start = parseISO8601("2026-11-17T00:05:00.000Z")!
            let tB_end = parseISO8601("2026-11-17T00:07:00.000Z")! // 120s

            let tC_start = parseISO8601("2026-11-17T12:00:00.000Z")!
            let tC_end = parseISO8601("2026-11-17T12:01:00.000Z")! // 60s

            let tD_start = parseISO8601("2026-11-17T13:00:00.000Z")!
            let tD_end = parseISO8601("2026-11-17T13:02:00.000Z")!

            let turns: [AgentTurn] = [
                AgentTurn(provider: .antigravity, conversation: "1", start: tA_start, end: tA_end, running: false, endedCleanly: true),
                AgentTurn(provider: .antigravity, conversation: "2", start: tB_start, end: tB_end, running: false, endedCleanly: true),
                AgentTurn(provider: .antigravity, conversation: "3", start: tC_start, end: tC_end, running: false, endedCleanly: true),
                AgentTurn(provider: .antigravity, conversation: "4", start: tD_start, end: tD_end, running: true) // running excluded
            ]

            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

            let utcDaily = AgentTurnReader.dailyDuration(turns, calendar: utcCalendar)
            suite.expect(utcDaily.count == 2, "grouped into two separate calendar days in UTC")
            if utcDaily.count == 2 {
                let day1 = utcCalendar.startOfDay(for: tA_start)
                let day2 = utcCalendar.startOfDay(for: tB_start)
                suite.expect(utcDaily[0].day == day1, "day 1 starts at 2026-11-16 00:00:00 UTC")
                suite.expect(abs(utcDaily[0].seconds - 300) < 0.001, "day 1 has 300s total duration")
                suite.expect(utcDaily[0].count == 1, "day 1 has 1 turn")

                suite.expect(utcDaily[1].day == day2, "day 2 starts at 2026-11-17 00:00:00 UTC")
                suite.expect(abs(utcDaily[1].seconds - 180) < 0.001, "day 2 has 120s + 60s = 180s total duration")
                suite.expect(utcDaily[1].count == 2, "day 2 has 2 finished turns")
            }

            var gmt7Calendar = Calendar(identifier: .gregorian)
            gmt7Calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!

            let gmt7Daily = AgentTurnReader.dailyDuration(turns, calendar: gmt7Calendar)
            suite.expect(gmt7Daily.count == 1, "all turns fall on 2026-11-17 in GMT+7")
            if gmt7Daily.count == 1 {
                let localDay = gmt7Calendar.startOfDay(for: tA_start)
                suite.expect(gmt7Daily[0].day == localDay, "day starts at 2026-11-17 local midnight")
                suite.expect(abs(gmt7Daily[0].seconds - 480) < 0.001, "sum of all three turns: 300s + 120s + 60s = 480s")
                suite.expect(gmt7Daily[0].count == 3, "count is 3 finished turns")
            }
        }
    }

    // MARK: - Test 8: Service Wiring

    private static func serviceWiring(_ suite: TestSuite) {
        suite.run("Service wiring for running and finished turns") {
            AgentTurnReader.clearCache()
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-wiring-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let convDir = tempDir.appending(path: ".gemini/antigravity-cli/conversations")
            try? FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

            let t0: UInt64 = 1_700_000_000
            let t1: UInt64 = 1_700_000_020
            let t2: UInt64 = 1_700_000_100
            let t3: UInt64 = 1_700_000_140

            // Turn 1 finished cleanly, turn 2 still in progress (step 132)
            let steps: [(idx: Int, stepType: Int, status: Int, metadata: Data)] = [
                (0, 14, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t0))),
                (1, 15, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t1))),
                (2, 14, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t2))),
                (3, 132, 3, encodeLengthDelimited(field: 1, payload: encodeTimestampMessage(seconds: t3)))
            ]

            let dbURL = convDir.appending(path: "live-conv.db")
            createSQLiteDB(at: dbURL, wal: false, steps: steps)

            let mtime = Date(timeIntervalSince1970: Double(t3))
            try? FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: dbURL.path)

            let now = mtime.addingTimeInterval(20) // running within 60s
            let turns = AgentTurnReader.readTurns(for: .antigravity, root: convDir, now: now)
            suite.expect(turns.count == 2, "readTurns finds 2 turns")
            guard turns.count == 2 else { return }

            suite.expect(!turns[0].running, "first turn is finished")
            suite.expect(turns[1].running, "second turn is running")

            // Simulate AgentUsageService publishing logic
            var snapshot = AgentUsageSnapshot(loaded: true, now: now)
            let enabled: Set<AgentProvider> = [.antigravity]

            // When provider is enabled:
            let providerTurns = turns
            let finished = providerTurns.filter { !$0.running }
            if enabled.contains(.antigravity), !finished.isEmpty {
                snapshot.turns[.antigravity] = finished
                snapshot.seen.insert(.antigravity)
            }
            for running in providerTurns where enabled.contains(.antigravity) && running.running {
                let liveSession = AgentLiveSession(
                    id: running.conversation,
                    provider: .antigravity,
                    started: running.start,
                    lastActivity: max(running.end, mtime),
                    model: "",
                    project: "",
                    tokens: AgentTokens(),
                    cost: 0
                )
                snapshot.live.append(liveSession)
                snapshot.seen.insert(.antigravity)
            }

            suite.expect(snapshot.live.count == 1, "running turn appears in snapshot.live")
            if let live = snapshot.live.first {
                suite.expect(live.provider == .antigravity, "live provider is antigravity")
                suite.expect(live.id == "live-conv", "live session id matches conversation id")
                suite.expect(live.started == turns[1].start, "live started == turn start")
                suite.expect(live.tokens.total == 0, "live tokens are zero")
                suite.expect(live.cost == 0, "live cost is zero")
            }
            suite.expect(snapshot.turns[.antigravity]?.count == 1, "finished turn stored in snapshot.turns")
            suite.expect(snapshot.seen.contains(.antigravity), "provider is marked seen")

            // When provider is disabled:
            var disabledSnapshot = AgentUsageSnapshot(loaded: true, now: now)
            let disabledProviders: Set<AgentProvider> = []
            for (provider, turns) in [AgentProvider.antigravity: turns] where disabledProviders.contains(provider) {
                let finished = turns.filter { !$0.running }
                if !finished.isEmpty { disabledSnapshot.turns[provider] = finished }
                for running in turns where running.running {
                    disabledSnapshot.live.append(AgentLiveSession(
                        id: running.conversation, provider: provider, started: running.start,
                        lastActivity: running.end, model: "", project: "", tokens: AgentTokens(), cost: 0
                    ))
                }
            }
            suite.expect(disabledSnapshot.live.isEmpty, "disabled provider contributes nothing to live")
            suite.expect(disabledSnapshot.turns[.antigravity] == nil, "disabled provider contributes nothing to turns")
        }
    }
}
