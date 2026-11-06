// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CommonCrypto
import Foundation
import Security

/// Plan allowances for Cursor and for Grok Bot, which Cursor bills as Sand.
/// The sign-in already on this Mac is read locally. The allowance itself is
/// asked of cursor.com, and nothing else is sent. Prompts stay in Cursor.
enum AgentCursorAccount {
    enum Failure: Error, Equatable {
        case missing, needsSignIn, unreachable
    }

    struct Reading: Equatable {
        var cursor: AgentLimits?
        var grok: AgentLimits?
    }

    static func databaseURL(home: URL) -> URL {
        home.appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    /// True when Cursor has stored a sign-in on this Mac. A locked token
    /// still counts: the keychain prompt happens when the allowance is read.
    static func isInstalled(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        FileManager.default.fileExists(atPath: databaseURL(home: home).path)
    }

    /// Turns the dashboard JSON into the two cards. A missing block is an
    /// empty card, not a failure: Cursor answers even when one product is off.
    static func reading(summary: Data, sand: Data?, now: Date) -> Reading {
        let summaryObject = jsonObject(summary) ?? [:]
        let sandObject = sand.flatMap(jsonObject)
        return reading(summary: summaryObject, sand: sandObject, now: now)
    }

    static func reading(summary: [String: Any], sand: [String: Any]?, now: Date) -> Reading {
        let cycleStart = date(summary["billingCycleStart"])
        let cycleEnd = date(summary["billingCycleEnd"])
        let plan = planPercent(summary)
        let weekly = sand.flatMap { weeklyPercent($0, now: now) }
        let unified = isUnified(summary) && (sand?["isUnified"] as? Bool ?? false) && weekly != nil
        var cursorWindows: [AgentLimitWindow] = []
        if unified, let weekly {
            cursorWindows.append(window("week", .weekly, weekly.percent, weekly.resets, 10080))
        } else if let plan {
            let minutes = cycleStart.flatMap { start in
                cycleEnd.map { end in Int((end.timeIntervalSince(start) / 60).rounded()) }
            }
            cursorWindows.append(window("plan", .other, plan, cycleEnd, minutes.flatMap { $0 > 0 ? $0 : nil }))
        }
        let cursor = cursorWindows.isEmpty ? nil : AgentLimits(
            provider: .cursor, windows: cursorWindows, observedAt: now, source: .account)
        let grokWindow = weekly.map { window("grok", .weekly, $0.percent, $0.resets, $0.resets == nil ? nil : 10080) }
        let grok = grokWindow.map { AgentLimits(provider: .grok, windows: [$0], observedAt: now, source: .account) }
        return Reading(cursor: cursor, grok: grok)
    }

    /// The cookie Cursor's own dashboard sends. Nil when the token cannot
    /// name its account or has already expired.
    static func sessionCookie(accessToken: String, now: Date = Date()) -> String? {
        guard let payload = jwtPayload(accessToken),
              let subject = payload["sub"] as? String,
              let userID = subject.split(separator: "|", omittingEmptySubsequences: true).last.map(String.init),
              !userID.isEmpty,
              userID.unicodeScalars.allSatisfy({ cookieCharacters.contains($0) }),
              let expiration = (payload["exp"] as? NSNumber)?.doubleValue,
              expiration > now.timeIntervalSince1970 + 60
        else { return nil }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)"
    }

    static func fetch(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                      now: Date = Date()) -> Result<Reading, Failure> {
        let database = databaseURL(home: home)
        guard FileManager.default.fileExists(atPath: database.path) else { return .failure(.missing) }
        guard let token = accessToken(database: database), let cookie = sessionCookie(accessToken: token, now: now)
        else { return .failure(.needsSignIn) }
        switch dashboard(cookie: cookie) {
        case .failure(let failure): return .failure(failure)
        case .success(let (summary, sand)):
            return .success(reading(summary: summary, sand: sand, now: now))
        }
    }

    // MARK: Dashboard JSON

    private struct Weekly {
        let percent: Double
        let resets: Date?
    }

    private static func planPercent(_ summary: [String: Any]) -> Double? {
        let individual = object(summary["individualUsage"])
        let plan = object(individual?["plan"])
        if let total = number(plan?["totalPercentUsed"]) { return percent(total) }
        let auto = number(plan?["autoPercentUsed"])
        let api = number(plan?["apiPercentUsed"])
        if let auto, let api { return percent((auto + api) / 2) }
        if let api { return percent(api) }
        if let auto { return percent(auto) }
        if let used = number(plan?["used"]), let limit = number(plan?["limit"]), limit > 0 {
            return percent(used / limit * 100)
        }
        let overall = object(individual?["overall"])
        if let used = number(overall?["used"]), let limit = number(overall?["limit"]), limit > 0 {
            return percent(used / limit * 100)
        }
        let pooled = object(object(summary["teamUsage"])?["pooled"])
        if let used = number(pooled?["used"]), let limit = number(pooled?["limit"]), limit > 0 {
            return percent(used / limit * 100)
        }
        return nil
    }

    /// Grok Bot's included week. A trial that has not expired counts too,
    /// without pretending it renews.
    private static func weeklyPercent(_ sand: [String: Any], now: Date) -> Weekly? {
        guard let raw = number(sand["usagePercent"]) else { return nil }
        let included = (sand["includedLimitZero"] as? Bool).map { !$0 } ?? (sand["hasNonZeroIncludedLimit"] as? Bool)
        let trial = included != true && (date(sand["sandTrialExpiresAt"]).map { $0 > now } ?? false)
        guard included == true || trial else { return nil }
        return Weekly(percent: percent(raw), resets: trial ? nil : date(sand["nextResetTimestampUtc"]))
    }

    private static func isUnified(_ summary: [String: Any]) -> Bool {
        let membership = (summary["membershipType"] as? String)?.lowercased() ?? ""
        let limit = (summary["limitType"] as? String)?.lowercased() ?? ""
        return membership.hasPrefix("unified_") && limit == "user"
    }

    private static func window(_ id: String, _ kind: AgentLimitWindow.Kind, _ used: Double,
                               _ resets: Date?, _ minutes: Int?) -> AgentLimitWindow {
        AgentLimitWindow(id: id, kind: kind, minutes: minutes, scope: nil, usedPercent: used, resetsAt: resets)
    }

    private static func percent(_ raw: Double) -> Double {
        guard raw.isFinite else { return 0 }
        return min(100, max(0, raw))
    }

    // MARK: Sign-in

    private static let cookieCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    private static let storagePrefix = "cursor-safe-storage:v1:"

    private static func accessToken(database: URL) -> String? {
        guard let stored = sqliteText(database: database, key: "cursorAuth/accessToken") else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix(storagePrefix) else { return trimmed }
        guard let encrypted = Data(base64Encoded: String(trimmed.dropFirst(storagePrefix.count))),
              let password = keychainPassword(),
              let plain = decryptChromium(encrypted, password: password)
        else { return nil }
        let token = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    /// Cursor keeps the session key the way Chromium keeps cookie keys.
    private static func keychainPassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Cursor Safe Storage",
            kSecAttrAccount as String: "Cursor",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16LittleEndian)
    }

    /// `v10` plus AES-128-CBC, key from PBKDF2-HMAC-SHA1 of the keychain secret.
    private static func decryptChromium(_ data: Data, password: String) -> String? {
        guard data.starts(with: Data("v10".utf8)), data.count > 3 else { return nil }
        let cipher = data.dropFirst(3)
        guard !cipher.isEmpty, (cipher.count).isMultiple(of: 16) else { return nil }
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let passwordData = Data(password.utf8)
        let derived = key.withUnsafeMutableBytes { keyBytes -> Int32 in
            passwordData.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress, passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress, kCCKeySizeAES128)
                }
            }
        }
        guard derived == kCCSuccess else { return nil }
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: cipher.count + kCCBlockSizeAES128)
        let outputCount = output.count
        let cipherCount = cipher.count
        var moved = 0
        let status = cipher.withUnsafeBytes { cipherBytes in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, kCCKeySizeAES128, ivBytes.baseAddress,
                                cipherBytes.baseAddress, cipherCount,
                                outputBytes.baseAddress, outputCount, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess, moved > 0 else { return nil }
        return String(data: output.prefix(moved), encoding: .utf8)
    }

    private static func sqliteText(database: URL, key: String) -> String? {
        let query = "SELECT value FROM ItemTable WHERE key = '\(key)' LIMIT 1;"
        let plain = database.absoluteURL.absoluteString + "?mode=ro"
        if let text = sqlite(plain, query) { return text }
        return sqlite(database.absoluteURL.absoluteString + "?mode=ro&immutable=1", query)
    }

    private static func sqlite(_ uri: String, _ query: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", uri, query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, let data = base64URL(String(parts[1])) else { return nil }
        return jsonObject(data)
    }

    private static func base64URL(_ string: String) -> Data? {
        var padded = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        return Data(base64Encoded: padded)
    }

    // MARK: Network

    private static func dashboard(cookie: String) -> Result<(Data, Data?), Failure> {
        let summary = request(path: "/api/usage-summary", method: "GET", cookie: cookie)
        switch summary {
        case .failure(let failure): return .failure(failure)
        case .success(let summary):
            let sand = request(path: "/api/dashboard/get-sand-usage-status", method: "POST", cookie: cookie)
            return .success((summary, try? sand.get()))
        }
    }

    private static func request(path: String, method: String, cookie: String) -> Result<Data, Failure> {
        guard let url = URL(string: "https://cursor.com" + path) else {
            return .failure(Failure.unreachable)
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        let box = ReplyBox()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            box.set(data: data, response: response, error: error)
            semaphore.signal()
        }.resume()
        semaphore.wait()
        let (data, response, error) = box.get()
        if error != nil { return .failure(Failure.unreachable) }
        guard let data, let http = response as? HTTPURLResponse else {
            return .failure(Failure.unreachable)
        }
        if http.statusCode == 401 || http.statusCode == 403 { return .failure(Failure.needsSignIn) }
        guard http.statusCode == 200 else { return .failure(Failure.unreachable) }
        return .success(data)
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func object(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        default: return nil
        }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

/// One slot for the reply of a URLSession callback.
private final class ReplyBox {
    private let lock = NSLock()
    private var data: Data?
    private var response: URLResponse?
    private var error: Error?

    func set(data: Data?, response: URLResponse?, error: Error?) {
        lock.lock()
        self.data = data
        self.response = response
        self.error = error
        lock.unlock()
    }

    func get() -> (Data?, URLResponse?, Error?) {
        lock.lock()
        defer { lock.unlock() }
        return (data, response, error)
    }
}
