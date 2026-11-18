// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Reads chat turns from local files for providers that keep no usage logs of their own,
/// such as Command Code and Antigravity.
enum AgentTurnReader {
    /// Maximum age of a file write for its newest turn to be considered actively running.
    static let runningThreshold: TimeInterval = 60
    /// Bounded history window for finished turns.
    static let historyHorizon: TimeInterval = 90 * 86_400
    /// Upper limit of recent conversation files scanned per directory.
    static let maxScannedFiles = 300

    private struct CacheEntry {
        let mtime: Date
        let size: Int64
        let turns: [AgentTurn]
    }

    private static var cache: [String: CacheEntry] = [:]
    private static let lock = NSLock()

    /// Clears the in-memory parse cache.
    static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    // MARK: - Public API

    /// Reads chat turns across multiple candidate roots for the given provider.
    static func readTurns(for provider: AgentProvider,
                          roots: [URL],
                          now: Date = Date(),
                          historyHorizon: TimeInterval = Self.historyHorizon,
                          maxFiles: Int = Self.maxScannedFiles) -> [AgentTurn] {
        roots.flatMap { readTurns(for: provider, root: $0, now: now, historyHorizon: historyHorizon, maxFiles: maxFiles) }
    }

    /// Reads chat turns for the given provider under an injected root URL.
    static func readTurns(for provider: AgentProvider,
                          root: URL,
                          now: Date = Date(),
                          historyHorizon: TimeInterval = Self.historyHorizon,
                          maxFiles: Int = Self.maxScannedFiles) -> [AgentTurn] {
        switch provider {
        case .antigravity:
            return readAntigravityTurns(root: root, now: now, historyHorizon: historyHorizon, maxFiles: maxFiles)
        default:
            return []
        }
    }

    /// Groups finished turns into a daily duration summary sorted by day ascending.
    static func dailyDuration(_ turns: [AgentTurn],
                              calendar: Calendar = .autoupdatingCurrent) -> [(day: Date, seconds: TimeInterval, count: Int)] {
        let finished = turns.filter { !$0.running }
        var grouped: [Date: (seconds: TimeInterval, count: Int)] = [:]
        for turn in finished {
            let day = calendar.startOfDay(for: turn.start)
            let duration = max(0, turn.end.timeIntervalSince(turn.start))
            var entry = grouped[day, default: (0, 0)]
            entry.seconds += duration
            entry.count += 1
            grouped[day] = entry
        }
        return grouped.keys.sorted().map { day in
            let entry = grouped[day]!
            return (day: day, seconds: entry.seconds, count: entry.count)
        }
    }

    // MARK: - Protobuf Parsing for Antigravity

    static func readVarint(from data: Data, at offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while offset < data.count {
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    static func parseTimestampMessage(from data: Data) -> Date? {
        var offset = 0
        var seconds: Int64 = 0
        var nanos: Int32 = 0
        var hasSeconds = false
        while offset < data.count {
            guard let key = readVarint(from: data, at: &offset) else { break }
            let fieldNumber = key >> 3
            let wireType = key & 0x7
            switch wireType {
            case 0:
                guard let val = readVarint(from: data, at: &offset) else { return nil }
                if fieldNumber == 1 {
                    seconds = Int64(bitPattern: val)
                    hasSeconds = true
                } else if fieldNumber == 2 {
                    nanos = Int32(truncatingIfNeeded: val)
                }
            case 1:
                offset += 8
                if offset > data.count { return nil }
            case 2:
                guard let lenVal = readVarint(from: data, at: &offset) else { return nil }
                let remaining = UInt64(data.count - offset)
                guard lenVal <= remaining, let len = Int(exactly: lenVal) else { return nil }
                offset += len
            case 5:
                offset += 4
                if offset > data.count { return nil }
            default:
                return nil
            }
        }
        guard hasSeconds, seconds > 1_000_000_000, seconds < 4_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: Double(seconds) + Double(nanos) / 1_000_000_000.0)
    }

    static func extractStepTimestamps(from metadata: Data) -> (creation: Date?, timestamps: [Date]) {
        var offset = 0
        var creation: Date?
        var timestamps: [Date] = []

        while offset < metadata.count {
            guard let key = readVarint(from: metadata, at: &offset) else { break }
            let fieldNumber = key >> 3
            let wireType = key & 0x7
            switch wireType {
            case 0:
                guard let _ = readVarint(from: metadata, at: &offset) else { return (creation, timestamps) }
            case 1:
                offset += 8
                if offset > metadata.count { return (creation, timestamps) }
            case 2:
                guard let lenVal = readVarint(from: metadata, at: &offset) else { return (creation, timestamps) }
                let remaining = UInt64(metadata.count - offset)
                guard lenVal <= remaining, let len = Int(exactly: lenVal) else { return (creation, timestamps) }
                let fieldData = metadata.subdata(in: offset..<(offset + len))
                offset += len

                if fieldNumber == 1 {
                    if let date = parseTimestampMessage(from: fieldData) {
                        creation = date
                        timestamps.append(date)
                    }
                } else if fieldNumber == 6 || fieldNumber == 7 || fieldNumber == 8 || fieldNumber == 32 {
                    if let date = parseTimestampMessage(from: fieldData) {
                        timestamps.append(date)
                    }
                } else if fieldNumber == 26 {
                    var subOffset = 0
                    while subOffset < fieldData.count {
                        guard let subKey = readVarint(from: fieldData, at: &subOffset) else { break }
                        let subField = subKey >> 3
                        let subWire = subKey & 0x7
                        switch subWire {
                        case 0:
                            guard let _ = readVarint(from: fieldData, at: &subOffset) else { break }
                        case 1:
                            subOffset += 8
                        case 2:
                            guard let subLenVal = readVarint(from: fieldData, at: &subOffset) else { break }
                            let subRemaining = UInt64(fieldData.count - subOffset)
                            guard subLenVal <= subRemaining, let subLen = Int(exactly: subLenVal) else { break }
                            if subField == 2 {
                                let tsData = fieldData.subdata(in: subOffset..<(subOffset + subLen))
                                if let date = parseTimestampMessage(from: tsData) {
                                    timestamps.append(date)
                                }
                            }
                            subOffset += subLen
                        case 5:
                            subOffset += 4
                        default:
                            subOffset = fieldData.count
                        }
                    }
                }
            case 5:
                offset += 4
                if offset > metadata.count { return (creation, timestamps) }
            default:
                return (creation, timestamps)
            }
        }

        return (creation, timestamps)
    }

    // MARK: - Antigravity Turns

    static func openSQLite(path: String) -> OpaquePointer? {
        let walPath = path + "-wal"
        let walExists = FileManager.default.fileExists(atPath: walPath)
        let baseURI = URL(fileURLWithPath: path).absoluteString
        let primaryURI = baseURI + (walExists ? "?mode=ro" : "?immutable=1")
        let fallbackURI = baseURI + (walExists ? "?immutable=1" : "?mode=ro")

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(primaryURI, &db, flags, nil) == SQLITE_OK, let validDB = db {
            sqlite3_busy_timeout(validDB, 1000)
            return validDB
        }
        if let db { sqlite3_close(db) }
        db = nil
        if sqlite3_open_v2(fallbackURI, &db, flags, nil) == SQLITE_OK, let validDB = db {
            sqlite3_busy_timeout(validDB, 1000)
            return validDB
        }
        if let db { sqlite3_close(db) }
        return nil
    }

    static func parseAntigravityDB(fileURL: URL) -> [AgentTurn] {
        guard let db = openSQLite(path: fileURL.path) else { return [] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let query = "SELECT idx, step_type, status, metadata FROM steps ORDER BY idx ASC"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        let conversationId = fileURL.deletingPathExtension().lastPathComponent
        var turns: [AgentTurn] = []
        var currentStart: Date?
        var currentEnd: Date?
        var lastStepType: Int64 = 0
        var lastStepStatus: Int64 = 0

        while sqlite3_step(stmt) == SQLITE_ROW {
            let stepType = sqlite3_column_int64(stmt, 1)
            let status = sqlite3_column_int64(stmt, 2)
            guard let blob = sqlite3_column_blob(stmt, 3) else { continue }
            let bytesCount = Int(sqlite3_column_bytes(stmt, 3))
            guard bytesCount > 0 else { continue }
            let data = Data(bytes: blob, count: bytesCount)
            let (creation, timestamps) = extractStepTimestamps(from: data)
            guard !timestamps.isEmpty else { continue }

            let stepMin = timestamps.min() ?? .distantPast
            let stepMax = timestamps.max() ?? .distantPast
            let turnStart = creation ?? stepMin

            if stepType == 14 {
                if let start = currentStart, let end = currentEnd {
                    let cleanly = (lastStepType == 15 && lastStepStatus == 3)
                    turns.append(AgentTurn(
                        provider: .antigravity,
                        conversation: conversationId,
                        start: start,
                        end: end,
                        running: false,
                        endedCleanly: cleanly
                    ))
                }
                currentStart = turnStart
                currentEnd = stepMax
                lastStepType = stepType
                lastStepStatus = status
            } else if currentStart != nil {
                currentEnd = max(currentEnd ?? stepMax, stepMax)
                lastStepType = stepType
                lastStepStatus = status
            }
        }

        if let start = currentStart, let end = currentEnd {
            let cleanly = (lastStepType == 15 && lastStepStatus == 3)
            turns.append(AgentTurn(
                provider: .antigravity,
                conversation: conversationId,
                start: start,
                end: end,
                running: false,
                endedCleanly: cleanly
            ))
        }

        return turns
    }

    static func readAntigravityTurns(root: URL,
                                     now: Date = Date(),
                                     historyHorizon: TimeInterval = Self.historyHorizon,
                                     maxFiles: Int = Self.maxScannedFiles) -> [AgentTurn] {
        let conversationsCandidate = root.appending(path: "conversations")
        let dir = FileManager.default.fileExists(atPath: conversationsCandidate.path)
            ? conversationsCandidate
            : root

        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                         includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                                                                         options: [.skipsHiddenFiles]) else {
            return []
        }

        struct Candidate {
            let url: URL
            let mtime: Date
            let size: Int64
        }

        var candidates: [Candidate] = []
        for entry in entries {
            guard entry.pathExtension == "db" else { continue }
            let walURL = entry.deletingPathExtension().appendingPathExtension("db-wal")
            let dbValues = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let walValues = try? walURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])

            let dbMtime = dbValues?.contentModificationDate ?? .distantPast
            let walMtime = walValues?.contentModificationDate ?? .distantPast
            let effectiveMtime = max(dbMtime, walMtime)

            let dbSize = Int64(dbValues?.fileSize ?? 0)
            let walSize = Int64(walValues?.fileSize ?? 0)
            let effectiveSize = dbSize + walSize

            if now.timeIntervalSince(effectiveMtime) <= historyHorizon {
                candidates.append(Candidate(url: entry, mtime: effectiveMtime, size: effectiveSize))
            }
        }

        candidates.sort { $0.mtime > $1.mtime }
        let selected = candidates.prefix(maxFiles)

        var allTurns: [AgentTurn] = []
        for candidate in selected {
            let turns = cachedTurns(for: candidate.url.path, mtime: candidate.mtime, size: candidate.size) {
                parseAntigravityDB(fileURL: candidate.url)
            }
            let adjusted = adjustRunning(turns: turns, fileMtime: candidate.mtime, now: now)
            allTurns.append(contentsOf: adjusted)
        }

        return allTurns
    }







    // MARK: - Helpers

    private static func cachedTurns(for path: String, mtime: Date, size: Int64, parse: () -> [AgentTurn]) -> [AgentTurn] {
        lock.lock()
        if let cached = cache[path], cached.mtime == mtime, cached.size == size {
            let turns = cached.turns
            lock.unlock()
            return turns
        }
        lock.unlock()

        let parsed = parse()

        lock.lock()
        cache[path] = CacheEntry(mtime: mtime, size: size, turns: parsed)
        lock.unlock()

        return parsed
    }

    static func adjustRunning(turns: [AgentTurn], fileMtime: Date, now: Date) -> [AgentTurn] {
        guard !turns.isEmpty else { return [] }
        var result = turns
        let lastIndex = result.count - 1
        let age = now.timeIntervalSince(fileMtime)
        let last = result[lastIndex]
        let isRunning: Bool
        if last.endedCleanly {
            isRunning = false
        } else {
            isRunning = age >= 0 && age <= runningThreshold
        }
        result[lastIndex] = AgentTurn(
            provider: last.provider,
            conversation: last.conversation,
            start: last.start,
            end: isRunning ? max(last.end, fileMtime) : last.end,
            running: isRunning,
            endedCleanly: last.endedCleanly
        )
        return result
    }
}
