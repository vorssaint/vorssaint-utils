// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SQLite3

enum AgentCursorAccountTests {
    static func token(account: String = "user_one", expires: Double = Date().timeIntervalSince1970 + 86_400) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["sub": "auth0|" + account, "exp": expires])
        let payload = data.base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return "header.\(payload).signature"
    }

    static func run(_ suite: TestSuite) {
        let now = Date(), token = token()
        let credential = AgentCursorAccount.credential(token: token, now: now)!
        suite.expect(credential.account == "user_one" && credential.cookie == "WorkosCursorSessionToken=user_one%3A%3A" + token,
                     "Cursor's desktop session maps to its dashboard cookie")
        for invalid in ["not-a-token", token + "\r\nInjected: value", self.token(expires: now.timeIntervalSince1970 + 30),
                        self.token(account: "bad;cookie"), self.token(account: ""), self.token(expires: now.timeIntervalSince1970 - 1)] {
            suite.expect(AgentCursorAccount.credential(token: invalid, now: now) == nil,
                         "invalid or expiring desktop credentials never produce a request")
        }
        database(suite, token: token, now: now)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await transport(suite, credential: credential, now: now)
            done.signal()
        }
        suite.expect(done.wait(timeout: .now() + 10) == .success, "Cursor transport tests finish without a network")
    }

    private static func database(_ suite: TestSuite, token: String, now: Date) {
        let home = FileManager.default.temporaryDirectory.appending(path: "vorss-cursor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        suite.expect(AgentCursorAccount.credential(home: home, now: now) == nil
                     && !FileManager.default.fileExists(atPath: home.path), "a missing Cursor database is never created")
        let url = AgentCursorAccount.databaseURL(home: home)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { suite.expect(false, "create Cursor fixture"); return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL; CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value BLOB);", nil, nil, nil)
        func write(_ data: Data) {
            let hex = data.map { String(format: "%02x", $0) }.joined()
            sqlite3_exec(db, "INSERT OR REPLACE INTO ItemTable VALUES('cursorAuth/accessToken', X'\(hex)')", nil, nil, nil)
        }
        write(Data(token.utf8))
        suite.expect(AgentCursorAccount.credential(home: home, now: now)?.token == token,
                     "Cursor reads a committed desktop token from the active WAL")
        let second = self.token(account: "user_two")
        write(second.data(using: .utf16LittleEndian)!)
        suite.expect(AgentCursorAccount.credential(home: home, now: now)?.account == "user_two",
                     "Cursor supports UTF-16 blobs and sees account changes")
        sqlite3_exec(db, "BEGIN; DELETE FROM ItemTable;", nil, nil, nil)
        suite.expect(AgentCursorAccount.credential(home: home, now: now)?.account == "user_two",
                     "an uncommitted sign-out does not expose partial database state")
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        suite.expect(AgentCursorAccount.credential(home: home, now: now) == nil, "a committed sign-out removes the usable credential")
        write(Data(token.utf8))
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
        sqlite3_close(db)
        db = nil
        let before = try! FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        suite.expect(AgentCursorAccount.credential(home: home, now: now)?.token == token,
                     "a checkpointed database without WAL sidecars is readable")
        let after = try! FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        suite.expect(before.sorted() == after.sorted(), "reading an idle Cursor database creates no sidecars")
    }

    private static func transport(_ suite: TestSuite, credential: AgentCursorAccount.Credential, now: Date) async {
        let since = now.addingTimeInterval(-86_400)
        func response(_ request: URLRequest, _ body: String, status: Int = 200) -> (Data, HTTPURLResponse) {
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let start = ISO8601DateFormatter().string(from: since)
        let end = ISO8601DateFormatter().string(from: now.addingTimeInterval(86_400))
        let summary = #"{"billingCycleStart":"\#(start)","billingCycleEnd":"\#(end)","individualUsage":{"plan":{"used":50,"limit":200}}}"#
        let row = #"{"timestamp":"\#(Int64(now.timeIntervalSince1970 * 1000))","model":"test-model","tokenUsage":{"inputTokens":1,"outputTokens":2,"cacheReadTokens":3,"cacheWriteTokens":4,"totalCents":5}}"#
        do {
            let reading = try await AgentCursorAccount.fetch(credential: credential, since: since, now: now) { request in
                suite.expect(request.url?.scheme == "https" && request.url?.host == "cursor.com"
                             && request.value(forHTTPHeaderField: "Cookie") == credential.cookie,
                             "desktop authentication is sent only to Cursor's HTTPS usage endpoints")
                if request.httpMethod == "POST" {
                    let body = (try? JSONSerialization.jsonObject(with: request.httpBody!)) as? [String: Any]
                    suite.expect(request.value(forHTTPHeaderField: "Origin") == "https://cursor.com"
                                 && body?["page"] as? Int == 1 && body?["pageSize"] as? Int == 1000,
                                 "Cursor history requests include pagination, fixed dates and CSRF origin")
                    return response(request, #"{"totalUsageEventsCount":2,"usageEventsDisplay":[\#(row),\#(row)]}"#)
                }
                return response(request, summary)
            }
            suite.expect(reading.records?.count == 2 && reading.summary?.limits.windows.first?.usedPercent == 25,
                         "a complete export publishes both identical requests and current limits")
            let incomplete = try await AgentCursorAccount.fetch(credential: credential, since: since, now: now) { request in
                response(request, request.httpMethod == "POST" ? #"{"totalUsageEventsCount":2,"usageEventsDisplay":[\#(row)]}"# : summary)
            }
            suite.expect(incomplete.records == nil && incomplete.summary != nil,
                         "an incomplete export preserves the previous totals while fresh limits remain available")
            let fullPage = Array(repeating: row, count: 1000).joined(separator: ",")
            let pages = try await AgentCursorAccount.history(credential: credential, since: since, now: now) { request in
                let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                return response(request, body["page"] as? Int == 1
                    ? #"{"totalUsageEventsCount":1001,"usageEventsDisplay":[\#(fullPage)]}"#
                    : #"{"totalUsageEventsCount":1001,"usageEventsDisplay":[\#(row)]}"#)
            }
            suite.expect(pages.count == 1001, "multi-page exports preserve distinct requests with identical counters")
            do {
                _ = try await AgentCursorAccount.fetch(credential: credential, since: since, now: now) { request in
                    response(request, "{}", status: 401)
                }
                suite.expect(false, "an expired server session must fail")
            } catch {
                suite.expect(error as? AgentCursorAccount.Failure == .needsSignIn, "server rejection asks for desktop sign-in")
            }
            let home = FileManager.default.temporaryDirectory.appending(path: "vorss-cursor-account-change-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: home) }
            let url = AgentCursorAccount.databaseURL(home: home)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var db: OpaquePointer?
            guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw AgentCursorAccount.Failure.unavailable }
            defer { sqlite3_close(db) }
            sqlite3_exec(db, "CREATE TABLE ItemTable(key TEXT PRIMARY KEY, value TEXT); INSERT INTO ItemTable VALUES('cursorAuth/accessToken', '\(credential.token)')", nil, nil, nil)
            do {
                _ = try await AgentCursorAccount.read(home: home, since: since, now: now, transport: { request in
                    if request.httpMethod == "POST" {
                        sqlite3_exec(db, "UPDATE ItemTable SET value = '\(token(account: "changed"))'", nil, nil, nil)
                        return response(request, "{}")
                    }
                    return response(request, summary)
                }, onAccount: { account in
                    suite.expect(account == credential.account, "the account is identified before network results arrive")
                })
                suite.expect(false, "an old account's response cannot survive a desktop account switch")
            } catch {
                suite.expect(error as? AgentCursorAccount.Failure == .accountChanged,
                             "a desktop account change during a fetch discards the old account's response")
            }
            let task = Task {
                try await AgentCursorAccount.history(credential: credential, since: since, now: now) { request in
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    return response(request, "{}")
                }
            }
            task.cancel()
            do { _ = try await task.value; suite.expect(false, "cancelled requests never publish") }
            catch { suite.expect(error is CancellationError, "pausing tracking cancels history work") }
            let network = AgentCursorAccount.session()
            suite.expect(network.configuration.httpCookieStorage == nil && network.configuration.urlCache == nil,
                         "Cursor requests share neither browser cookies nor a persistent response cache")
            network.invalidateAndCancel()
        } catch { suite.expect(false, "Cursor transport fixture failed: \(error)") }
    }
}
