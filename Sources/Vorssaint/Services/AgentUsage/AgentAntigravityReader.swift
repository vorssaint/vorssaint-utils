// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import SQLite3

/// How far reading one Antigravity database has got.
struct AgentAntigravityProgress: Equatable {
    struct SessionState: Equatable {
        var lastModified: String
        var isRunning: Bool
        var started: Date
    }
    /// Known sessions and their states: conversation_id -> SessionState
    var sessions: [String: SessionState] = [:]
}

/// Reads Antigravity sessions and status from its SQLite database (~/.gemini/antigravity/conversation_summaries.db).
enum AgentAntigravityReader {
    static let database = "conversation_summaries.db"
    static let bundleIdentifier = "com.google.antigravity"

    /// When the database or its write-ahead log last changed; nil when there
    /// is no database.
    static func modified(_ path: String) -> Date? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        var wal = stat()
        let walModified = stat(path + "-wal", &wal) == 0 ? date(wal.st_mtimespec) : .distantPast
        return max(date(info.st_mtimespec), walModified)
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }

    static func readAppended(_ cursor: AgentLogCursor, since horizon: Date = .distantPast,
                             shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue() else { return }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let identity = UInt64(info.st_ino)

        // Check if database was replaced or recreated
        if identity != cursor.identity {
            cursor.identity = identity
            cursor.antigravity = AgentAntigravityProgress()
            cursor.state = AgentLogState()
        }
        cursor.modified = modified(cursor.path) ?? date(info.st_mtimespec)

        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(cursor.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return
        }
        sqlite3_busy_timeout(db, 2000)

        let now = Date()
        emitPlan("Pro", timestamp: now, line: line)

        let select = """
        SELECT conversation_id, title, workspace_uris, not_fully_idle, status, killed,
               last_modified_time, last_user_input_time, parent_conversation_id, step_count
        FROM conversation_summaries
        WHERE last_modified_time >= ? OR not_fully_idle = 1
        ORDER BY last_modified_time ASC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, select, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let horizonFormatter = ISO8601DateFormatter()
        let horizonText = horizonFormatter.string(from: horizon).replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "+00:00")
        sqlite3_bind_text(stmt, 1, horizonText, -1, transient)

        var currentSessions = Set<String>()
        let sessionWindow: TimeInterval = 5 * 3600
        let sessionStart = now.addingTimeInterval(-sessionWindow)
        let weekWindow: TimeInterval = 7 * 86_400
        let weekStart = now.addingTimeInterval(-weekWindow)

        var sessionRequests = 0
        var weekRequests = 0
        var latestUserInput: Date = .distantPast

        while shouldContinue() && sqlite3_step(stmt) == SQLITE_ROW {
            guard let sessionID = text(stmt, 0) else { continue }
            currentSessions.insert(sessionID)

            let title = text(stmt, 1) ?? ""
            let workspaceUris = text(stmt, 2) ?? ""
            let notFullyIdle = sqlite3_column_int(stmt, 3) != 0
            let status = text(stmt, 4) ?? ""
            let killed = sqlite3_column_int(stmt, 5) != 0
            let lastModifiedText = text(stmt, 6) ?? ""
            let lastUserInputText = text(stmt, 7) ?? ""
            let parentSessionID = text(stmt, 8) ?? ""
            let stepCount = Int(sqlite3_column_int(stmt, 9))

            let isRunning = (notFullyIdle || status == "CASCADE_RUN_STATUS_RUNNING") && !killed
            let lastModified = AgentTimestamp.parse(lastModifiedText) ?? now
            let lastUserInput = AgentTimestamp.parse(lastUserInputText) ?? lastModified
            let project = extractProject(from: workspaceUris, fallback: title)
            let model = "gemini-2.5-pro"

            let promptInfo = sessionPromptInfo(for: sessionID, databasePath: cursor.path, fallbackStepCount: stepCount)
            let prompts = promptInfo.prompts
            let latestPromptDate = promptInfo.latestPromptDate

            if lastModified >= sessionStart || isRunning {
                sessionRequests += prompts
            }
            if lastModified >= weekStart || isRunning {
                weekRequests += prompts
            }
            if let latestPromptDate {
                if latestPromptDate > latestUserInput {
                    latestUserInput = latestPromptDate
                }
            } else if lastUserInput > latestUserInput {
                latestUserInput = lastUserInput
            }
            if isRunning {
                latestUserInput = max(latestUserInput, lastModified)
            }

            // Emit usage record for completed or progressing steps
            if stepCount > 0 {
                emitUsage(sessionID: sessionID, project: project, model: model,
                          timestamp: lastModified, stepCount: max(1, stepCount),
                          requestCount: prompts, line: line)
            }

            let previous = cursor.antigravity.sessions[sessionID]

            if isRunning {
                let effectivePromptTime = latestPromptDate ?? (now.timeIntervalSince(lastModified) < 120 ? lastModified : lastUserInput)

                if previous == nil || previous?.isRunning == false {
                    // Turn began
                    let started = effectivePromptTime
                    cursor.antigravity.sessions[sessionID] = .init(lastModified: lastModifiedText, isRunning: true, started: started)
                    emitEvent("turnBegan", sessionID: sessionID, parentSessionID: parentSessionID,
                              project: project, model: model, timestamp: started,
                              completed: false, duration: nil, line: line)
                } else if let prev = previous, let latestPromptDate,
                          latestPromptDate.timeIntervalSince(prev.started) > 3 {
                    // A new prompt was sent while already running
                    let started = latestPromptDate
                    cursor.antigravity.sessions[sessionID] = .init(lastModified: lastModifiedText, isRunning: true, started: started)
                    emitEvent("turnBegan", sessionID: sessionID, parentSessionID: parentSessionID,
                              project: project, model: model, timestamp: started,
                              completed: false, duration: nil, line: line)
                } else if previous?.lastModified != lastModifiedText {
                    // Turn active update
                    let started = previous?.started ?? effectivePromptTime
                    cursor.antigravity.sessions[sessionID] = .init(lastModified: lastModifiedText, isRunning: true, started: started)
                    emitEvent("turnActive", sessionID: sessionID, parentSessionID: parentSessionID,
                              project: project, model: model, timestamp: lastModified,
                              completed: false, duration: nil, line: line)
                }
            } else {
                if let prev = previous, prev.isRunning {
                    // Turn ended
                    let duration = max(0, lastModified.timeIntervalSince(prev.started))
                    cursor.antigravity.sessions[sessionID] = .init(lastModified: lastModifiedText, isRunning: false, started: prev.started)
                    emitEvent("turnEnded", sessionID: sessionID, parentSessionID: parentSessionID,
                              project: project, model: model, timestamp: lastModified,
                              completed: !killed, duration: duration, line: line)
                } else if previous == nil {
                    cursor.antigravity.sessions[sessionID] = .init(lastModified: lastModifiedText, isRunning: false, started: lastUserInput)
                }
            }
        }

        // Check if any previously running sessions stopped or disappeared
        for (sessionID, sessionState) in cursor.antigravity.sessions where sessionState.isRunning && !currentSessions.contains(sessionID) {
            cursor.antigravity.sessions[sessionID] = .init(lastModified: sessionState.lastModified, isRunning: false, started: sessionState.started)
            emitEvent("turnEnded", sessionID: sessionID, parentSessionID: "",
                      project: "", model: "gemini-2.5-pro", timestamp: now,
                      completed: false, duration: nil, line: line)
        }

        if latestUserInput == .distantPast {
            latestUserInput = now
        }

        // Standard Gemini Pro capacity per rolling session (5 hours) and week (7 days)
        let sessionCapacity: Double = 100.0
        let weekCapacity: Double = 500.0

        let sessionResets = max(now.addingTimeInterval(60), latestUserInput.addingTimeInterval(sessionWindow))
        let sessionUsed = min(100.0, max(0.0, (Double(sessionRequests) / sessionCapacity) * 100.0))
        let weekResets = now.addingTimeInterval(6 * 86_400)
        let weekUsed = min(100.0, max(0.0, (Double(weekRequests) / weekCapacity) * 100.0))

        var sessionDict: [String: Any] = [
            "kind": "session",
            "minutes": 300,
            "used_percent": sessionUsed
        ]
        if sessionUsed > 0 {
            sessionDict["resets_at"] = sessionResets.timeIntervalSince1970
        }

        var weekDict: [String: Any] = [
            "kind": "weekly",
            "minutes": 10080,
            "used_percent": weekUsed
        ]
        if weekUsed > 0 {
            weekDict["resets_at"] = weekResets.timeIntervalSince1970
        }

        if let liveWindows = AgentAntigravityLiveQuota.fetch() {
            emitLimits(windows: liveWindows, timestamp: now, line: line)
        } else {
            emitLimits(windows: [sessionDict, weekDict], timestamp: now, line: line)
        }
    }

    /// Reads user prompt count (step_type 14) and latest prompt timestamp from the conversation database.
    private static func sessionPromptInfo(for sessionID: String, databasePath: String, fallbackStepCount: Int) -> (prompts: Int, latestPromptDate: Date?) {
        let conversationDbPath = (databasePath as NSString).deletingLastPathComponent + "/conversations/\(sessionID).db"
        var db: OpaquePointer?
        guard sqlite3_open_v2(conversationDbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return (max(1, fallbackStepCount / 30), nil)
        }
        defer { sqlite3_close(db) }

        var count = max(1, fallbackStepCount / 30)
        var countStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT count(*) FROM steps WHERE step_type = 14", -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                let rowCount = Int(sqlite3_column_int(countStmt, 0))
                if rowCount > 0 { count = rowCount }
            }
            sqlite3_finalize(countStmt)
        }

        var latestDate: Date?
        var dateStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT metadata FROM steps WHERE step_type = 14 ORDER BY idx DESC LIMIT 1", -1, &dateStmt, nil) == SQLITE_OK {
            if sqlite3_step(dateStmt) == SQLITE_ROW, let blob = sqlite3_column_blob(dateStmt, 0) {
                let bytesCount = Int(sqlite3_column_bytes(dateStmt, 0))
                let ptr = blob.assumingMemoryBound(to: UInt8.self)
                // Look for tag 0x08 (field 1 varint timestamp in protobuf)
                for i in 0..<min(bytesCount - 1, 16) {
                    if ptr[i] == 0x08 {
                        var value: UInt64 = 0
                        var shift: UInt64 = 0
                        for j in (i + 1)..<min(bytesCount, i + 10) {
                            let b = UInt64(ptr[j])
                            value |= (b & 0x7F) << shift
                            shift += 7
                            if (b & 0x80) == 0 {
                                if value > 1_700_000_000 && value < 2_100_000_000 {
                                    latestDate = Date(timeIntervalSince1970: TimeInterval(value))
                                }
                                break
                            }
                        }
                        break
                    }
                }
            }
            sqlite3_finalize(dateStmt)
        }

        return (count, latestDate)
    }

    private static func emitPlan(_ plan: String, timestamp: Date, line: (Data) -> Void) {
        let json: [String: Any] = [
            "event": "plan",
            "plan": plan,
            "timestamp": timestamp.timeIntervalSince1970
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            line(data)
        }
    }

    private static func emitUsage(sessionID: String, project: String, model: String,
                                  timestamp: Date, stepCount: Int, requestCount: Int, line: (Data) -> Void) {
        let json: [String: Any] = [
            "event": "usage",
            "session_id": sessionID,
            "project": project,
            "model": model,
            "timestamp": timestamp.timeIntervalSince1970,
            "step_count": stepCount,
            "requests": requestCount,
            "tokens": [
                "input": stepCount * 1200,
                "output": stepCount * 300
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            line(data)
        }
    }

    private static func emitLimits(windows: [[String: Any]], timestamp: Date, line: (Data) -> Void) {
        let json: [String: Any] = [
            "event": "limits",
            "timestamp": timestamp.timeIntervalSince1970,
            "windows": windows
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            line(data)
        }
    }

    private static func emitEvent(_ event: String, sessionID: String, parentSessionID: String,
                                  project: String, model: String, timestamp: Date,
                                  completed: Bool, duration: Double?, line: (Data) -> Void) {
        var json: [String: Any] = [
            "event": event,
            "session_id": sessionID,
            "parent_session_id": parentSessionID,
            "project": project,
            "model": model,
            "timestamp": timestamp.timeIntervalSince1970,
            "completed": completed
        ]
        if let duration { json["duration"] = duration }
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            line(data)
        }
    }

    private static func extractProject(from workspaceUris: String, fallback: String) -> String {
        if let data = workspaceUris.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [String],
           let first = list.first, !first.isEmpty {
            var path = first
            if path.hasPrefix("file://") { path = String(path.dropFirst(7)) }
            return AgentLogParser.projectName(path)
        }
        if !workspaceUris.isEmpty && !workspaceUris.hasPrefix("[") {
            var path = workspaceUris
            if path.hasPrefix("file://") { path = String(path.dropFirst(7)) }
            return AgentLogParser.projectName(path)
        }
        return fallback.isEmpty ? "Antigravity" : fallback
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }
}

private final class LoopbackTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust,
           challenge.protectionSpace.host == "127.0.0.1" || challenge.protectionSpace.host == "localhost" {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Connects to Antigravity's local language server to fetch official live quota limits.
enum AgentAntigravityLiveQuota {
    private static var cachedWindows: [[String: Any]]?
    private static var cachedAt = Date.distantPast
    private static let lock = NSLock()

    static func fetch() -> [[String: Any]]? {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let cached = cachedWindows, now.timeIntervalSince(cachedAt) < 15 {
            return cached
        }

        let psResult = BoundedProcessRunner.run("/bin/ps", ["-eo", "pid,command"], timeout: 1.0, maxOutputBytes: 128_000)
        guard let psOutput = String(data: psResult.output, encoding: .utf8) else { return nil }
        var foundPid: Int?
        var foundCsrf: String?
        for line in psOutput.components(separatedBy: "\n") {
            if line.contains("language_server") && line.contains("--csrf_token") {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                if let first = parts.first, let pid = Int(first) {
                    foundPid = pid
                }
                if let range = line.range(of: "--csrf_token") {
                    let after = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    let token = after.components(separatedBy: .whitespaces).first ?? ""
                    if !token.isEmpty { foundCsrf = token }
                }
                break
            }
        }
        guard let pid = foundPid, let csrf = foundCsrf else { return nil }

        let lsofResult = BoundedProcessRunner.run("/usr/sbin/lsof", ["-nP", "-a", "-iTCP", "-sTCP:LISTEN", "-p", String(pid)], timeout: 1.0, maxOutputBytes: 16_000)
        guard let lsofOutput = String(data: lsofResult.output, encoding: .utf8) else { return nil }
        var ports: [Int] = []
        for line in lsofOutput.components(separatedBy: "\n") {
            if let colon = line.range(of: ":") {
                let sub = line[colon.upperBound...]
                let portStr = sub.prefix(while: { $0.isNumber })
                if let port = Int(portStr), !ports.contains(port) {
                    ports.append(port)
                }
            }
        }
        guard !ports.isEmpty else { return nil }

        let delegate = LoopbackTrustDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 1.5
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        for port in ports {
            guard let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(csrf, forHTTPHeaderField: "x-codeium-csrf-token")
            request.httpBody = Data("{}".utf8)

            let semaphore = DispatchSemaphore(value: 0)
            var responseData: Data?
            let task = session.dataTask(with: request) { data, _, _ in
                responseData = data
                semaphore.signal()
            }
            task.resume()
            if semaphore.wait(timeout: .now() + 1.5) == .timedOut {
                task.cancel()
                continue
            }

            guard let data = responseData,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = json["response"] as? [String: Any],
                  let groups = response["groups"] as? [[String: Any]] else {
                continue
            }

            guard let geminiGroup = groups.first(where: { ($0["displayName"] as? String)?.contains("Gemini") == true }) ?? groups.first,
                  let buckets = geminiGroup["buckets"] as? [[String: Any]] else {
                continue
            }

            var sessionDict: [String: Any]?
            var weeklyDict: [String: Any]?
            let iso = ISO8601DateFormatter()

            for bucket in buckets {
                let window = bucket["window"] as? String ?? ""
                let bucketId = bucket["bucketId"] as? String ?? ""
                let remaining = (bucket["remainingFraction"] as? NSNumber)?.doubleValue ?? 1.0
                let resetTimeStr = bucket["resetTime"] as? String ?? ""
                let resetDate = iso.date(from: resetTimeStr)
                let usedPercent = min(100.0, max(0.0, (1.0 - remaining) * 100.0))

                if window == "5h" || bucketId.contains("5h") {
                    var dict: [String: Any] = [
                        "kind": "session",
                        "minutes": 300,
                        "used_percent": usedPercent
                    ]
                    if let resetDate {
                        dict["resets_at"] = resetDate.timeIntervalSince1970
                    }
                    sessionDict = dict
                } else if window == "weekly" || bucketId.contains("weekly") {
                    var dict: [String: Any] = [
                        "kind": "weekly",
                        "minutes": 10080,
                        "used_percent": usedPercent
                    ]
                    if let resetDate {
                        dict["resets_at"] = resetDate.timeIntervalSince1970
                    }
                    weeklyDict = dict
                }
            }

            if let sessionDict, let weeklyDict {
                let windows = [sessionDict, weeklyDict]
                cachedWindows = windows
                cachedAt = now
                return windows
            }
        }

        return nil
    }
}
