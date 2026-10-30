// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Reads Google Antigravity (agy) conversation databases.
/// agy records measured model token usage in SQLite files at:
/// ~/.gemini/antigravity-cli/conversations/<uuid>.db
/// ~/.gemini/antigravity/conversations/<uuid>.db
final class AgentAgyConversationReader {
    struct Stamp: Equatable {
        let mtime: Date
        let size: Int64
        let walMtime: Date
        let walSize: Int64
    }

    private var stamps: [String: Stamp] = [:]

    static func directories(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        [
            home.appendingPathComponent(".gemini/antigravity-cli/conversations", isDirectory: true).path,
            home.appendingPathComponent(".gemini/antigravity/conversations", isDirectory: true).path,
            home.appendingPathComponent(".gemini/antigravity-ide/conversations", isDirectory: true).path,
            home.appendingPathComponent(".gemini/antigravity-acp/conversations", isDirectory: true).path
        ]
    }

    func reset() {
        stamps.removeAll()
    }

    /// Scans conversation directories for new or modified databases and populates the store.
    /// Returns true if any records were added or modified.
    @discardableResult
    func scan(into store: AgentUsageStore, since horizon: Date = .distantPast,
              home: URL = FileManager.default.homeDirectoryForCurrentUser,
              shouldContinue: () -> Bool = { true }) -> Bool {
        var changed = false
        for dir in Self.directories(home: home) {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".db") && !entry.hasPrefix(".") {
                guard shouldContinue() else { return changed }
                let path = (dir as NSString).appendingPathComponent(entry)
                guard let currentStamp = Self.stamp(for: path) else { continue }
                if currentStamp.size <= 0 {
                    stamps[path] = currentStamp
                    continue
                }
                if currentStamp.mtime < horizon && currentStamp.walMtime < horizon && stamps[path] == nil {
                    stamps[path] = currentStamp
                    continue
                }
                if stamps[path] == currentStamp {
                    continue
                }
                if readConversation(at: path, stamp: currentStamp, into: store, shouldContinue: shouldContinue) {
                    changed = true
                }
                stamps[path] = currentStamp
            }
        }
        return changed
    }

    static func stamp(for path: String) -> Stamp? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let dbMtime = date(info.st_mtimespec)
        let dbSize = Int64(info.st_size)

        var walInfo = stat()
        let walPath = path + "-wal"
        let walExists = stat(walPath, &walInfo) == 0 && (walInfo.st_mode & S_IFMT) == S_IFREG
        let walMtime = walExists ? date(walInfo.st_mtimespec) : .distantPast
        let walSize = walExists ? Int64(walInfo.st_size) : 0

        return Stamp(mtime: dbMtime, size: dbSize, walMtime: walMtime, walSize: walSize)
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }

    /// Reads one conversation database from a temporary copy (or in place if no WAL) and adds records to store.
    private func readConversation(at path: String, stamp: Stamp? = nil, into store: AgentUsageStore,
                                  shouldContinue: () -> Bool) -> Bool {
        let filename = (path as NSString).lastPathComponent
        guard filename.hasSuffix(".db") else { return false }
        let session = String(filename.dropLast(3))

        let currentStamp = stamp ?? Self.stamp(for: path)
        guard let currentStamp, currentStamp.size > 0 else { return false }

        var db: OpaquePointer?
        defer { sqlite3_close(db) }

        var tempDir: URL? = nil
        defer {
            if let tempDir {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }

        // Fast path: if there is no uncheckpointed WAL file, open in place read-only as immutable.
        // This avoids copying hundreds of megabytes across hundreds of database files to temporary storage on launch.
        if currentStamp.walSize == 0 {
            let uri = "file://\(path)?immutable=1"
            if sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil) != SQLITE_OK {
                db = nil
            }
        }

        // Fallback: if WAL has uncheckpointed data or in-place open failed, copy to a temporary directory.
        if db == nil {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("agy_conv_\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                tempDir = dir
            } catch {
                return false
            }

            for ext in ["", "-wal", "-shm"] {
                let src = path + ext
                if FileManager.default.fileExists(atPath: src) {
                    let dest = dir.appendingPathComponent(filename + ext).path
                    try? FileManager.default.copyItem(atPath: src, toPath: dest)
                }
            }

            let copyDbPath = dir.appendingPathComponent(filename).path
            // The copy is ours: a WAL database without its -shm cannot open read-only.
            guard sqlite3_open_v2(copyDbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
                return false
            }
        }
        sqlite3_busy_timeout(db, 2000)

        // Read trajectory_metadata_blob
        var metaData: Data?
        var metaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT data FROM trajectory_metadata_blob LIMIT 1", -1, &metaStmt, nil) == SQLITE_OK {
            if sqlite3_step(metaStmt) == SQLITE_ROW {
                if let blobBytes = sqlite3_column_blob(metaStmt, 0) {
                    let blobSize = sqlite3_column_bytes(metaStmt, 0)
                    metaData = Data(bytes: blobBytes, count: Int(blobSize))
                }
            }
        }
        sqlite3_finalize(metaStmt)

        var workspace: String?
        var startDate: Date?
        if let metaData {
            workspace = Self.extractWorkspace(from: metaData)
            var metaFields: [String: UInt64] = [:]
            _ = Self.parseFields(Array(metaData), out: &metaFields)
            let stamps = metaFields.values.filter { $0 > 1_750_000_000 && $0 < 2_000_000_000 }
            if let minStamp = stamps.min() {
                startDate = Date(timeIntervalSince1970: TimeInterval(minStamp))
            }
        }

        let date = startDate ?? currentStamp.mtime
        let project = workspace.map { AgentLogParser.projectName($0) } ?? ""

        // Read gen_metadata
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT idx, data FROM gen_metadata ORDER BY idx", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        var changed = false
        while shouldContinue() && sqlite3_step(stmt) == SQLITE_ROW {
            let idx = sqlite3_column_int64(stmt, 0)
            guard let blobBytes = sqlite3_column_blob(stmt, 1) else { continue }
            let blobSize = sqlite3_column_bytes(stmt, 1)
            guard blobSize > 0 else { continue }
            let rowData = Array(UnsafeBufferPointer(start: blobBytes.assumingMemoryBound(to: UInt8.self), count: Int(blobSize)))

            var rowFields: [String: UInt64] = [:]
            guard Self.parseFields(rowData, out: &rowFields) else { continue }

            let fresh = Int(rowFields[".1.4.2"] ?? 0)
            let cached = Int(rowFields[".1.4.5"] ?? 0)
            let output = Int(rowFields[".1.4.3"] ?? 0)
            let thinking = Int(rowFields[".1.4.9"] ?? 0)

            let modelCode = rowFields[".1.3"]
            let model: String
            if let modelCode {
                model = Self.modelName(for: modelCode)
            } else {
                model = "gemini-unknown"
            }

            let tokens = AgentTokens(input: fresh, cacheWrite: 0, cacheRead: cached, output: output, reasoning: thinking)
            let billable = AgentBillable(tokens: tokens)
            let priced = AgentPricing.cost(billable, model: model)
            let cost: Double? = model.contains("unknown") ? nil : priced.cost
            let savings = priced.savings

            let key = "agyconv:\(session):\(idx)"
            let record = AgentUsageRecord(
                provider: .agy,
                date: date,
                model: model,
                project: project,
                session: session,
                requests: 1,
                tokens: tokens,
                cost: cost,
                savings: savings,
                reportedCost: false
            )

            if store.addUsageRecord(record, billable: billable, key: key, source: path, recompute: false) {
                changed = true
            }
        }
        if changed {
            store.recomputeAgySession(session)
        }
        if !project.isEmpty {
            store.noteAgySession(session, project: project)
        } else {
            store.syncAgySession(session)
        }
        return changed
    }

    // MARK: - Protobuf Decoder

    private struct ParsedField {
        let path: String
        let wireType: Int
        let intVal: UInt64?
        let dataVal: [UInt8]?
    }

    static func decodeVarint(_ bytes: [UInt8], at index: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
            if shift > 63 {
                return nil
            }
        }
        return nil
    }

    static func parseFields(_ bytes: [UInt8], path: String = "",
                            out: inout [String: UInt64], depth: Int = 0) -> Bool {
        var i = 0
        var found: [ParsedField] = []
        while i < bytes.count {
            guard let key = decodeVarint(bytes, at: &i) else { return false }
            let fieldNum = key >> 3
            let wireType = Int(key & 7)
            if fieldNum == 0 { return false }

            switch wireType {
            case 0:
                guard let val = decodeVarint(bytes, at: &i) else { return false }
                found.append(ParsedField(path: "\(path).\(fieldNum)", wireType: 0, intVal: val, dataVal: nil))
            case 1:
                if i + 8 > bytes.count { return false }
                i += 8
                found.append(ParsedField(path: "\(path).\(fieldNum)", wireType: 1, intVal: nil, dataVal: nil))
            case 2:
                guard let len = decodeVarint(bytes, at: &i) else { return false }
                let n = Int(len)
                if n < 0 || i + n > bytes.count { return false }
                let sub = Array(bytes[i ..< i + n])
                i += n
                found.append(ParsedField(path: "\(path).\(fieldNum)", wireType: 2, intVal: nil, dataVal: sub))
            case 5:
                if i + 4 > bytes.count { return false }
                i += 4
                found.append(ParsedField(path: "\(path).\(fieldNum)", wireType: 5, intVal: nil, dataVal: nil))
            default:
                return false
            }
        }

        for item in found {
            if item.wireType == 0 {
                if let v = item.intVal, out[item.path] == nil {
                    out[item.path] = v
                }
            } else if item.wireType == 2, let sub = item.dataVal, !sub.isEmpty, depth < 6 {
                _ = parseFields(sub, path: item.path, out: &out, depth: depth + 1)
            }
        }
        return true
    }

    static func modelName(for code: UInt64) -> String {
        switch code {
        case 326, 1322: return "gemini-3.8-flash"
        case 1298: return "gemini-3.7-flash-high"
        case 1299: return "gemini-3.7-flash-medium"
        case 1318: return "gemini-3.8-flash-high"
        case 1319: return "gemini-3.8-flash-medium"
        case 1320: return "gemini-3.8-flash-low"
        case 1404: return "claude-sonnet-5-5"
        case 1417: return "gemini-4-argon-high"
        case 1418: return "gemini-4-argon-medium"
        case 1419: return "gemini-4-argon-low"
        default: return "gemini-unknown-\(code)"
        }
    }

    static func extractWorkspace(from data: Data) -> String? {
        guard let filePrefix = "file:///".data(using: .utf8),
              let range = data.range(of: filePrefix) else {
            return nil
        }
        let start = range.lowerBound + 7
        var end = start
        while end < data.count {
            let byte = data[end]
            if byte < 0x20 || byte == 0x22 { break }
            end += 1
        }
        guard end > start, let path = String(data: data[start..<end], encoding: .utf8) else { return nil }
        return path.removingPercentEncoding ?? path
    }
}
