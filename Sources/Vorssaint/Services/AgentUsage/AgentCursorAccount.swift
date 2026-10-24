// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreFoundation
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SQLite3

/// Uses only the running desktop app's sign-in. The database is read-only;
/// credentials are never refreshed, copied to disk, or sent outside cursor.com.
enum AgentCursorAccount {
    enum Failure: Error, Equatable {
        case closed, needsSignIn, unavailable, incomplete, accountChanged
    }

    struct Credential {
        let account: String
        let token: String
        var cookie: String { "WorkosCursorSessionToken=\(account)%3A%3A\(token)" }
    }

    struct Reading {
        let account: String
        let summary: AgentCursorUsage.Summary?
        /// Nil preserves the last complete history for the same account.
        let records: [AgentUsageRecord]?
    }

    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let interval: TimeInterval = 5 * 60
    static let pageSize = 1_000
    static let maximumPages = 50

    static func databaseURL(home: URL) -> URL {
        home.appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    static func credential(home: URL, now: Date) -> Credential? {
        let url = databaseURL(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        // Do not create WAL sidecars for a database that has none. While Cursor
        // writes, normal read-only mode includes its committed WAL entries.
        let sidecars = ["-wal", "-shm"].contains { FileManager.default.fileExists(atPath: url.path + $0) }
        let path = sidecars ? url.path : url.absoluteString + "?immutable=1"
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 250)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' AND length(value) <= 65536 LIMIT 1",
                                -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        let token = data.contains(0) ? String(data: data, encoding: .utf16LittleEndian) : String(data: data, encoding: .utf8)
        return token.flatMap { credential(token: $0, now: now) }
    }

    static func credential(token: String, now: Date) -> Credential? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        let alphabet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard token.utf8.count <= 32_768, parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(alphabet.contains) }) else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let subject = json["sub"] as? String,
              let account = subject.components(separatedBy: "|").last, !account.isEmpty,
              account.unicodeScalars.allSatisfy(alphabet.contains),
              let expires = json["exp"] as? NSNumber, CFGetTypeID(expires) != CFBooleanGetTypeID(),
              expires.doubleValue.isFinite, expires.doubleValue > now.timeIntervalSince1970 + 60 else { return nil }
        return Credential(account: account, token: token)
    }

    static func read(home: URL, since: Date, now: Date, transport: Transport,
                     onAccount: (String) -> Void) async throws -> Reading {
        guard let credential = credential(home: home, now: now) else { throw Failure.needsSignIn }
        try Task.checkCancellation()
        onAccount(credential.account)
        let reading = try await fetch(credential: credential, since: since, now: now, transport: transport)
        guard let current = self.credential(home: home, now: Date()), current.account == credential.account else {
            throw Failure.accountChanged
        }
        return reading
    }

    static func fetch(credential: Credential, since: Date, now: Date, transport: Transport) async throws -> Reading {
        let summaryData = try await request(path: "/api/usage-summary", credential: credential, transport: transport)
        let summary = AgentCursorUsage.summary(summaryData, now: now)
        do {
            let records = try await history(credential: credential, since: since, now: now, transport: transport)
            return Reading(account: credential.account, summary: summary, records: records)
        } catch Failure.needsSignIn { throw Failure.needsSignIn }
        catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            // A failed or incomplete export must not hide freshly checked limits.
            return Reading(account: credential.account, summary: summary, records: nil)
        }
    }

    static func history(credential: Credential, since: Date, now: Date, transport: Transport) async throws -> [AgentUsageRecord] {
        var records: [AgentUsageRecord] = []
        var total: Int?
        for page in 1...maximumPages {
            let body: [String: Any] = ["page": page, "pageSize": pageSize,
                "startDate": String(Int64(since.timeIntervalSince1970 * 1_000)),
                "endDate": String(Int64(now.timeIntervalSince1970 * 1_000))]
            let data = try await request(path: "/api/dashboard/get-filtered-usage-events", body: body,
                                         credential: credential, transport: transport)
            guard let reading = AgentCursorUsage.page(data, since: since, until: now),
                  reading.total <= maximumPages * pageSize, total == nil || total == reading.total else { throw Failure.incomplete }
            total = reading.total
            records += reading.records
            guard records.count <= reading.total else { throw Failure.incomplete }
            if reading.records.count < pageSize {
                guard records.count == reading.total else { throw Failure.incomplete }
                return records
            }
        }
        // A full page at the safety cap is not proof of a complete export.
        throw Failure.incomplete
    }

    private static func request(path: String, body: [String: Any]? = nil,
                                credential: Credential, transport: Transport) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://cursor.com" + path)!)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(credential.cookie, forHTTPHeaderField: "Cookie")
        if let body {
            request.httpMethod = "POST"
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        if response.statusCode == 401 || response.statusCode == 403 { throw Failure.needsSignIn }
        guard response.statusCode == 200, response.url?.host == "cursor.com",
              response.url?.scheme == "https", data.count <= AgentCursorUsage.maximumSize else { throw Failure.unavailable }
        return data
    }

    /// No shared cookies, response cache, or redirects to another origin.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: Redirects(), delegateQueue: nil)
    }

    private final class Redirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
