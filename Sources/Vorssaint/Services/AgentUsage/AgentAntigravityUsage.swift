// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Reads Antigravity CLI (`agy`) conversation SQLite databases to extract
/// per-call token, model, and project usage records.
enum AgentAntigravityUsage {
    static let historyHorizon: TimeInterval = 90 * 86_400
    static let maxScannedFiles = 300

    private struct CachedItem {
        let key: String
        let record: AgentUsageRecord
        let modelId: String
        let displayName: String
        let needsGlobalLookup: Bool
    }

    private struct CacheEntry {
        let mtime: Date
        let size: Int64
        let items: [CachedItem]
    }

    private struct SummariesCache {
        let summariesMtime: Date?
        let historyMtime: Date?
        let projects: [String: String]
    }

    private static var dbCache: [String: CacheEntry] = [:]
    private static var summariesCache: SummariesCache?
    private static let lock = NSLock()

    static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        dbCache.removeAll()
        summariesCache = nil
    }

    static func defaultConversationsDir(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".gemini/antigravity-cli/conversations")
    }

    static func defaultSummariesDB(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".gemini/antigravity-cli/conversation_summaries.db")
    }

    static func defaultHistoryFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".gemini/antigravity-cli/history.jsonl")
    }

    static func readRecords(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date(),
        historyHorizon: TimeInterval = Self.historyHorizon,
        maxFiles: Int = Self.maxScannedFiles
    ) -> [(key: String, record: AgentUsageRecord)] {
        readRecords(
            conversationsDir: defaultConversationsDir(home: home),
            summariesDB: defaultSummariesDB(home: home),
            historyFile: defaultHistoryFile(home: home),
            now: now,
            historyHorizon: historyHorizon,
            maxFiles: maxFiles
        )
    }

    static func readRecords(
        conversationsDir: URL,
        summariesDB: URL,
        historyFile: URL,
        now: Date = Date(),
        historyHorizon: TimeInterval = Self.historyHorizon,
        maxFiles: Int = Self.maxScannedFiles
    ) -> [(key: String, record: AgentUsageRecord)] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: conversationsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        struct Candidate {
            let url: URL
            let mtime: Date
            let size: Int64
        }

        var candidates: [Candidate] = []
        for entry in entries where entry.pathExtension == "db" {
            guard let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile ?? true,
                  let mtime = values.contentModificationDate else { continue }
            var effectiveMtime = mtime
            let walURL = URL(fileURLWithPath: entry.path + "-wal")
            if let walMtime = (try? walURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                effectiveMtime = max(effectiveMtime, walMtime)
            }
            if now.timeIntervalSince(effectiveMtime) <= historyHorizon {
                candidates.append(Candidate(url: entry, mtime: effectiveMtime, size: Int64(values.fileSize ?? 0)))
            }
        }

        candidates.sort { $0.mtime > $1.mtime }
        let selected = candidates.prefix(maxFiles)
        let projectMap = loadProjects(summariesDB: summariesDB, historyFile: historyFile)

        var allItems: [CachedItem] = []
        var globalIdToDisplay: [String: String] = [:]
        for candidate in selected {
            let convId = candidate.url.deletingPathExtension().lastPathComponent
            let project = projectMap[convId] ?? ""
            let items = cachedRecords(
                for: candidate.url.path,
                mtime: candidate.mtime,
                size: candidate.size
            ) {
                parseConversationDB(fileURL: candidate.url, conversationId: convId, project: project, fileMtime: candidate.mtime)
            }
            for item in items where !item.modelId.isEmpty && !item.displayName.isEmpty {
                if globalIdToDisplay[item.modelId] == nil {
                    globalIdToDisplay[item.modelId] = item.displayName
                }
            }
            allItems.append(contentsOf: items)
        }
        return allItems.map { item in
            var rec = item.record
            if item.needsGlobalLookup, let globalDisplay = globalIdToDisplay[item.modelId] {
                rec = AgentUsageRecord(
                    provider: rec.provider,
                    date: rec.date,
                    model: globalDisplay,
                    project: rec.project,
                    session: rec.session,
                    requests: rec.requests,
                    tokens: rec.tokens,
                    cost: rec.cost,
                    savings: rec.savings,
                    reportedCost: rec.reportedCost
                )
            }
            return (key: item.key, record: rec)
        }
    }

    // MARK: - Project Resolution

    private static func loadProjects(summariesDB: URL, historyFile: URL) -> [String: String] {
        let sumMtime = effectiveMtime(for: summariesDB)
        let histMtime = (try? historyFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        lock.lock()
        if let cached = summariesCache, cached.summariesMtime == sumMtime, cached.historyMtime == histMtime {
            let map = cached.projects
            lock.unlock()
            return map
        }
        lock.unlock()

        var map: [String: String] = [:]

        // Fallback first: history.jsonl
        if let data = try? Data(contentsOf: historyFile), let text = String(data: data, encoding: .utf8) {
            text.enumerateLines { line, _ in
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let convId = obj["conversationId"] as? String, !convId.isEmpty,
                      let workspace = obj["workspace"] as? String, !workspace.isEmpty else { return }
                map[convId] = AgentLogParser.projectName(workspace)
            }
        }

        // Primary: conversation_summaries.db
        if let db = AgentTurnReader.openSQLite(path: summariesDB.path) {
            defer { sqlite3_close(db) }
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT conversation_id, workspace_uris FROM conversation_summaries;", -1, &stmt, nil) == SQLITE_OK {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let cidPtr = sqlite3_column_text(stmt, 0),
                          let urisPtr = sqlite3_column_text(stmt, 1) else { continue }
                    let convId = String(cString: cidPtr)
                    let urisText = String(cString: urisPtr)
                    if let urisData = urisText.data(using: .utf8),
                       let uris = try? JSONSerialization.jsonObject(with: urisData) as? [String],
                       let first = uris.first, !first.isEmpty {
                        let path = URL(string: first)?.path ?? first
                        if !path.isEmpty {
                            map[convId] = AgentLogParser.projectName(path)
                        }
                    }
                }
            }
        }

        lock.lock()
        summariesCache = SummariesCache(summariesMtime: sumMtime, historyMtime: histMtime, projects: map)
        lock.unlock()

        return map
    }

    private static func effectiveMtime(for url: URL) -> Date? {
        var mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let walURL = URL(fileURLWithPath: url.path + "-wal")
        if let walMtime = (try? walURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
            mtime = max(mtime ?? walMtime, walMtime)
        }
        return mtime
    }

    // MARK: - Conversation DB Parsing

    private static func parseConversationDB(
        fileURL: URL,
        conversationId: String,
        project: String,
        fileMtime: Date
    ) -> [CachedItem] {
        guard let db = AgentTurnReader.openSQLite(path: fileURL.path) else { return [] }
        defer { sqlite3_close(db) }

        // 1. Load step timestamps
        var stepTimes: [Int: Date] = [:]
        var newestStepTime: Date?
        var stepStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT idx, metadata FROM steps;", -1, &stepStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stepStmt) }
            while sqlite3_step(stepStmt) == SQLITE_ROW {
                let idx = Int(sqlite3_column_int64(stepStmt, 0))
                if let blobPtr = sqlite3_column_blob(stepStmt, 1) {
                    let count = Int(sqlite3_column_bytes(stepStmt, 1))
                    if count > 0 {
                        let data = Data(bytes: blobPtr, count: count)
                        if let ts = extractFirstTimestamp(from: data) {
                            stepTimes[idx] = ts
                            if let cur = newestStepTime {
                                if ts > cur { newestStepTime = ts }
                            } else {
                                newestStepTime = ts
                            }
                        }
                    }
                }
            }
        }

        // 2. Load raw gen_metadata rows
        var rawRows: [(idx: Int, date: Date, parsed: GenMetadataParsed)] = []
        var genStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT idx, data FROM gen_metadata ORDER BY idx ASC;", -1, &genStmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(genStmt) }
            while sqlite3_step(genStmt) == SQLITE_ROW {
                let idx = Int(sqlite3_column_int64(genStmt, 0))
                guard let blobPtr = sqlite3_column_blob(genStmt, 1) else { continue }
                let count = Int(sqlite3_column_bytes(genStmt, 1))
                guard count > 0 else { continue }
                let data = Data(bytes: blobPtr, count: count)

                guard let parsed = parseGenMetadata(data) else { continue }
                let date = parsed.firstStepIdx.flatMap { stepTimes[$0] } ?? newestStepTime ?? fileMtime
                rawRows.append((idx: idx, date: date, parsed: parsed))
            }
        }

        // 3. Resolve model names dynamically per conversation
        var earlierDisplay: [String: String] = [:]
        var prevModel = ""
        var items: [CachedItem] = []

        for i in 0..<rawRows.count {
            let row = rawRows[i]
            let displayName = row.parsed.displayName
            let modelId = row.parsed.modelId
            let resolvedModel: String
            var needsGlobalLookup = false

            if !displayName.isEmpty {
                resolvedModel = displayName
                if !modelId.isEmpty {
                    earlierDisplay[modelId] = displayName
                }
            } else if !modelId.isEmpty {
                if let earlier = earlierDisplay[modelId] {
                    resolvedModel = earlier
                } else if let later = rawRows[(i + 1)...].first(where: { $0.parsed.modelId == modelId && !$0.parsed.displayName.isEmpty })?.parsed.displayName {
                    resolvedModel = later
                } else {
                    resolvedModel = modelId
                    needsGlobalLookup = true
                }
            } else {
                resolvedModel = prevModel
            }

            prevModel = resolvedModel
            let key = "antigravity:\(conversationId):\(row.idx)"
            let record = AgentUsageRecord(
                provider: .antigravity,
                date: row.date,
                model: resolvedModel,
                project: project,
                session: conversationId,
                requests: 1,
                tokens: row.parsed.tokens,
                cost: nil,
                savings: 0
            )
            items.append(CachedItem(
                key: key,
                record: record,
                modelId: modelId,
                displayName: displayName,
                needsGlobalLookup: needsGlobalLookup
            ))
        }

        return items
    }

    private static func extractFirstTimestamp(from data: Data) -> Date? {
        var offset = 0
        while offset < data.count {
            guard let tag = AgentTurnReader.readVarint(from: data, at: &offset) else { break }
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07
            switch wireType {
            case 0:
                guard AgentTurnReader.readVarint(from: data, at: &offset) != nil else { return nil }
            case 1:
                guard offset + 8 <= data.count else { return nil }
                offset += 8
            case 2:
                guard let lenVal = AgentTurnReader.readVarint(from: data, at: &offset) else { return nil }
                let remaining = UInt64(data.count - offset)
                guard lenVal <= remaining, let len = Int(exactly: lenVal) else { return nil }
                let subdata = data.subdata(in: offset..<(offset + len))
                offset += len
                if fieldNumber == 1, let ts = AgentTurnReader.parseTimestampMessage(from: subdata) {
                    return ts
                }
            case 5:
                guard offset + 4 <= data.count else { return nil }
                offset += 4
            default:
                return nil
            }
        }
        return nil
    }

    private struct GenMetadataParsed {
        let tokens: AgentTokens
        let displayName: String
        let modelId: String
        let firstStepIdx: Int?
    }

    private static func parseGenMetadata(_ data: Data) -> GenMetadataParsed? {
        var field1Data: Data?
        var firstStepIdx: Int?

        var offset = 0
        while offset < data.count {
            guard let tag = AgentTurnReader.readVarint(from: data, at: &offset) else { return nil }
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07
            switch wireType {
            case 0:
                guard AgentTurnReader.readVarint(from: data, at: &offset) != nil else { return nil }
            case 1:
                guard offset + 8 <= data.count else { return nil }
                offset += 8
            case 2:
                guard let lenVal = AgentTurnReader.readVarint(from: data, at: &offset) else { return nil }
                let remaining = UInt64(data.count - offset)
                guard lenVal <= remaining, let len = Int(exactly: lenVal) else { return nil }
                let subdata = data.subdata(in: offset..<(offset + len))
                offset += len
                if fieldNumber == 1 {
                    field1Data = subdata
                } else if fieldNumber == 2 {
                    var subOffset = 0
                    if let stepVal = AgentTurnReader.readVarint(from: subdata, at: &subOffset),
                       let stepInt = Int(exactly: stepVal) {
                        firstStepIdx = stepInt
                    }
                }
            case 5:
                guard offset + 4 <= data.count else { return nil }
                offset += 4
            default:
                return nil
            }
        }

        guard let f1 = field1Data else { return nil }

        var tokenBlockData: Data?
        var displayName = ""
        var modelId = ""

        var f1Offset = 0
        while f1Offset < f1.count {
            guard let tag = AgentTurnReader.readVarint(from: f1, at: &f1Offset) else { return nil }
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07
            switch wireType {
            case 0:
                guard AgentTurnReader.readVarint(from: f1, at: &f1Offset) != nil else { return nil }
            case 1:
                guard f1Offset + 8 <= f1.count else { return nil }
                f1Offset += 8
            case 2:
                guard let lenVal = AgentTurnReader.readVarint(from: f1, at: &f1Offset) else { return nil }
                let remaining = UInt64(f1.count - f1Offset)
                guard lenVal <= remaining, let len = Int(exactly: lenVal) else { return nil }
                let subdata = f1.subdata(in: f1Offset..<(f1Offset + len))
                f1Offset += len
                if fieldNumber == 4 {
                    tokenBlockData = subdata
                } else if fieldNumber == 19 {
                    modelId = String(data: subdata, encoding: .utf8) ?? ""
                } else if fieldNumber == 21 {
                    displayName = String(data: subdata, encoding: .utf8) ?? ""
                }
            case 5:
                guard f1Offset + 4 <= f1.count else { return nil }
                f1Offset += 4
            default:
                return nil
            }
        }

        guard let tb = tokenBlockData else { return nil }

        var f1_4_1 = 0
        var f1_4_2 = 0
        var f1_4_3 = 0
        var f1_4_10 = 0

        var tbOffset = 0
        while tbOffset < tb.count {
            guard let tag = AgentTurnReader.readVarint(from: tb, at: &tbOffset) else { return nil }
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07
            switch wireType {
            case 0:
                guard let val = AgentTurnReader.readVarint(from: tb, at: &tbOffset) else { return nil }
                let clamped = Int(min(val, UInt64(Int.max)))
                if fieldNumber == 1 { f1_4_1 = clamped }
                else if fieldNumber == 2 { f1_4_2 = clamped }
                else if fieldNumber == 3 { f1_4_3 = clamped }
                else if fieldNumber == 10 { f1_4_10 = clamped }
            case 1:
                guard tbOffset + 8 <= tb.count else { return nil }
                tbOffset += 8
            case 2:
                guard let lenVal = AgentTurnReader.readVarint(from: tb, at: &tbOffset) else { return nil }
                let remaining = UInt64(tb.count - tbOffset)
                guard lenVal <= remaining, let len = Int(exactly: lenVal) else { return nil }
                tbOffset += len
            case 5:
                guard tbOffset + 4 <= tb.count else { return nil }
                tbOffset += 4
            default:
                return nil
            }
        }

        // Inferred mapping (not provider-confirmed):
        // input = 1.4.2 (fresh prompt), cacheRead = 1.4.1 (cached prefix),
        // cacheWrite = 0, output = 1.4.3 (total output), reasoning = 1.4.10.
        let tokens = AgentTokens(
            input: f1_4_2,
            cacheWrite: 0,
            cacheRead: f1_4_1,
            output: f1_4_3,
            reasoning: f1_4_10
        )

        return GenMetadataParsed(tokens: tokens, displayName: displayName, modelId: modelId, firstStepIdx: firstStepIdx)
    }

    // MARK: - Cache Helper

    private static func cachedRecords(
        for path: String,
        mtime: Date,
        size: Int64,
        parse: () -> [CachedItem]
    ) -> [CachedItem] {
        lock.lock()
        if let cached = dbCache[path], cached.mtime == mtime, cached.size == size {
            let items = cached.items
            lock.unlock()
            return items
        }
        lock.unlock()

        let parsed = parse()

        lock.lock()
        dbCache[path] = CacheEntry(mtime: mtime, size: size, items: parsed)
        lock.unlock()

        return parsed
    }
}
