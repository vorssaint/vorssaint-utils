// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

/// Cursor plan usage from the account Cursor.app is already signed in with.
/// The app session is read once for the request and is not stored. Browser
/// cookies are not used.
enum AgentCursorAccountUsage {
    static let summaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    static let maximumBody = 1 << 20
    /// How often an idle Mac asks again; a live Cursor turn asks sooner.
    static let idleInterval: TimeInterval = 5 * 60
    static let liveInterval: TimeInterval = 60

    struct Session: Equatable {
        let accessToken: String
        let userID: String
        let expiresAt: Date

        /// Cookie Cursor's web API expects for the same account.
        var cookieHeader: String { "WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)" }

        var isUsable: Bool { expiresAt.timeIntervalSinceNow > 60 }
    }

    /// Result of one usage check. Nil windows mean the account answered with
    /// nothing that can fill a ring.
    struct Reading: Equatable {
        let limits: AgentLimits
        let planName: String?
    }

    /// The token Cursor.app saved for this Mac's login, or nil when none is
    /// present or it has already expired.
    static func session(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Session? {
        let path = home.appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
        guard let token = accessToken(at: path)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              let claims = jwtClaims(token),
              let subject = claims["sub"] as? String,
              let userID = subject.split(separator: "|").last.map(String.init), !userID.isEmpty,
              let expiration = (claims["exp"] as? NSNumber)?.doubleValue
        else { return nil }
        let session = Session(accessToken: token, userID: userID,
                              expiresAt: Date(timeIntervalSince1970: expiration))
        return session.isUsable ? session : nil
    }

    /// Turns the usage-summary JSON into the windows the island already draws.
    static func reading(from data: Data, now: Date = Date()) -> Reading? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let individual = json["individualUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any]
        let onDemand = individual?["onDemand"] as? [String: Any]
        let overall = individual?["overall"] as? [String: Any]
        let team = json["teamUsage"] as? [String: Any]
        let pooled = team?["pooled"] as? [String: Any]

        let total = optionalDouble(plan?["totalPercentUsed"])
        let auto = optionalDouble(plan?["autoPercentUsed"])
        let api = optionalDouble(plan?["apiPercentUsed"])
        let planUsed = double(plan?["used"])
        let planLimit = double(plan?["limit"])
        let overallUsed = double(overall?["used"])
        let overallLimit = double(overall?["limit"])
        let pooledUsed = double(pooled?["used"])
        let pooledLimit = double(pooled?["limit"])

        let percent: Double
        if let total {
            percent = clampPercent(total)
        } else if let auto, let api {
            percent = clampPercent((auto + api) / 2)
        } else if let api {
            percent = clampPercent(api)
        } else if let auto {
            percent = clampPercent(auto)
        } else if planLimit > 0 {
            percent = clampPercent(planUsed / planLimit * 100)
        } else if overallLimit > 0 {
            percent = clampPercent(overallUsed / overallLimit * 100)
        } else if pooledLimit > 0 {
            percent = clampPercent(pooledUsed / pooledLimit * 100)
        } else {
            return nil
        }

        let resets = parseDate(json["billingCycleEnd"])
        let start = parseDate(json["billingCycleStart"])
        let minutes: Int?
        if let start, let resets, resets > start {
            minutes = Int((resets.timeIntervalSince(start) / 60).rounded())
        } else {
            minutes = nil
        }

        var windows = [
            AgentLimitWindow(id: "cursor-plan", kind: .other, minutes: minutes, scope: nil,
                             usedPercent: percent, resetsAt: resets),
        ]
        if let demandLimit = optionalDouble(onDemand?["limit"]), demandLimit > 0 {
            let used = double(onDemand?["used"])
            windows.append(AgentLimitWindow(id: "cursor-on-demand", kind: .other, minutes: minutes,
                                            scope: "On-demand", usedPercent: clampPercent(used / demandLimit * 100),
                                            resetsAt: resets))
        }

        let membership = (json["membershipType"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let planName = membership.flatMap { $0.isEmpty ? nil : $0.capitalized }
        return Reading(limits: AgentLimits(provider: .cursor, windows: windows, observedAt: now, source: .account),
                       planName: planName)
    }

    /// Asks cursor.com with the app session. The cookie is only on this request.
    static func fetch(session: Session, completion: @escaping (Reading?) -> Void) {
        var request = URLRequest(url: summaryURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Vorssaint/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let task = URLSession(configuration: configuration).dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, status == 200, let data, data.count <= maximumBody else {
                completion(nil)
                return
            }
            completion(reading(from: data))
        }
        task.resume()
    }

    // MARK: Local session

    private static func accessToken(at path: String) -> String? {
        value(for: "cursorAuth/accessToken", database: path)
    }

    private static func value(for key: String, database path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        if let value = value(for: key, database: path, immutable: false) { return value }
        // Idle WAL-mode files can refuse a normal open once the sidecars are gone.
        let walMissing = !FileManager.default.fileExists(atPath: path + "-wal")
            && !FileManager.default.fileExists(atPath: path + "-shm")
        return walMissing ? value(for: key, database: path, immutable: true) : nil
    }

    private static func value(for key: String, database path: String, immutable: Bool) -> String? {
        var db: OpaquePointer?
        let flags = immutable ? SQLITE_OPEN_READONLY | SQLITE_OPEN_URI : SQLITE_OPEN_READONLY
        let filename = immutable
            ? URL(fileURLWithPath: path).absoluteURL.absoluteString + "?immutable=1"
            : path
        guard sqlite3_open_v2(filename, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;", -1, &stmt, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, key, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(stmt, 0) == SQLITE_TEXT {
            return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
        }
        guard sqlite3_column_type(stmt, 0) == SQLITE_BLOB else { return nil }
        let length = Int(sqlite3_column_bytes(stmt, 0))
        guard length > 0, let bytes = sqlite3_column_blob(stmt, 0) else { return nil }
        return decodeToken(Data(bytes: bytes, count: length))
    }

    /// Cursor sometimes stores the token as UTF-16LE without a BOM.
    private static func decodeToken(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.contains("\0") {
            return utf8
        }
        if data.count % 2 == 0, let utf16 = String(data: data, encoding: .utf16LittleEndian) {
            return utf16
        }
        return nil
    }

    private static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    private static func double(_ value: Any?) -> Double {
        optionalDouble(value) ?? 0
    }

    private static func optionalDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String, let number = Double(text) { return number }
        return nil
    }

    private static func clampPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return AgentTimestamp.parse(text) ?? ISO8601DateFormatter().date(from: text)
    }
}
