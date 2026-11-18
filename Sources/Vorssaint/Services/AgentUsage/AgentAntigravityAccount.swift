// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Antigravity, Google's coding agent CLI (`agy`): a 5-hour and a weekly limit
/// for each group of models.
///
/// Google's server answers those numbers to Antigravity itself only, and
/// Vorssaint does not ask as another app. They come from `agy`'s own `/usage`
/// command, which asks Google by itself with no model turn:
///
/// - Sign-in: `agy` keeps it in the keychain (item "gemini", account
///   "antigravity"). It is read only to see whether somebody is signed in;
///   the tokens in it are never used or sent.
/// - Numbers: `agy -p /usage --output-format json`, only after `agy --version`
///   says it is a version that answers `/usage` itself (earlier ones send the
///   command to the model, which spends quota). A reply that shows a model
///   turn is not read. A run costs about two seconds of CPU, so it is asked
///   for at most every `minimumGap`.
/// - Never refreshed here: `agy` renews its own sign-in when it runs.
enum AgentAntigravityAccount {
    enum Failure: Error, Equatable {
        case notFound, signedOut, unreadable
    }

    enum Command: Equatable {
        case version, usage
    }

    /// What running a program came to.
    enum Output: Equatable {
        case text(String)
        /// `agy` is not on this Mac (the sign-in may be from its IDE).
        case notInstalled
        /// It would not start, did not finish in time or exited with an error.
        case failed
    }

    typealias Run = (Command) -> Output

    static let keychainService = "gemini"
    static let keychainAccount = "antigravity"
    /// The first `agy` that answers `/usage` itself in print mode.
    static let minimumVersion = [1, 1, 11]
    /// Its limits move slowly, and a run costs about two seconds of CPU.
    static let minimumGap: TimeInterval = 15 * 60

    private static let base64Prefix = "go-keyring-base64:"
    private static let fiveHoursMinutes = 300
    private static let weekMinutes = 7 * 24 * 60

    // MARK: Sign-in

    /// Why nobody is signed in, or nil once somebody is: the keychain item
    /// holds a refresh token. The access token's own expiry does not matter,
    /// as `agy` renews it when it runs.
    static func signIn(keychain: String?) -> Failure? {
        guard let item = keychain?.trimmingCharacters(in: .whitespacesAndNewlines) else { return .notFound }
        let json: Data?
        if item.hasPrefix(base64Prefix) {
            json = decode(String(item.dropFirst(base64Prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            json = Data(item.utf8)
        }
        guard let json, let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return .unreadable }
        let refresh = (object["token"] as? [String: Any])?["refresh_token"] as? String
        return refresh?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? nil : .signedOut
    }

    /// Standard or URL-safe base64, with or without padding.
    private static func decode(_ text: String) -> Data? {
        var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base += String(repeating: "=", count: (4 - base.count % 4) % 4)
        return Data(base64Encoded: base)
    }

    // MARK: Version

    /// `1.4.12` out of `agy --version`'s text.
    static func version(of text: String) -> [Int]? {
        for word in text.split(whereSeparator: { !($0.isASCII && ($0.isNumber || $0 == ".")) }) {
            let parts = word.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
            if parts.count == 3, parts.allSatisfy({ $0 != nil }) { return parts.compactMap { $0 } }
        }
        return nil
    }

    static func accepts(_ version: [Int]) -> Bool {
        for (found, wanted) in zip(version, minimumVersion) where found != wanted { return found > wanted }
        return true
    }

    // MARK: Limits

    /// The limits out of `agy -p /usage --output-format json`: one JSON line
    /// (log lines may come before it).
    static func limits(stdout: String, observed: Date) -> Result<AgentLimits, Failure> {
        let answer = stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("{") }
            .compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
            .first { object in
                object["status"] as? String == "SUCCESS"
                    && (object["command"] as? [String: Any])?["name"] as? String == "usage"
            }
        guard let answer else { return .failure(.unreadable) }
        // A model turn means `agy` took `/usage` as a prompt: quota was spent
        // and these are not the limits.
        if (answer["num_turns"] as? Int ?? 0) > 0 || !(answer["conversation_id"] as? String ?? "").isEmpty {
            return .failure(.unreadable)
        }
        guard let groups = ((answer["command"] as? [String: Any])?["data"] as? [String: Any])?["groups"] as? [[String: Any]]
        else { return .failure(.unreadable) }
        var windows: [AgentLimitWindow] = []
        for group in groups {
            let name = (group["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                // Unmetered: drawn as unused it would invent room next to a pool that is empty.
                guard bucket["disabled"] as? Bool != true, let id = bucket["id"] as? String,
                      let left = (bucket["remaining_fraction"] as? NSNumber)?.doubleValue, left.isFinite else { continue }
                let (kind, minutes): (AgentLimitWindow.Kind, Int?) = switch bucket["window"] as? String {
                case "5h": (.session, fiveHoursMinutes)
                case "weekly": (.weekly, weekMinutes)
                default: (.other, nil)
                }
                windows.append(AgentLimitWindow(
                    id: "antigravity.\(id)", kind: kind, minutes: minutes,
                    scope: name?.isEmpty == false ? name : nil,
                    usedPercent: min(100, max(0, (1 - left) * 100)),
                    resetsAt: (bucket["reset_time"] as? String).flatMap(AgentTimestamp.parse)))
            }
        }
        guard !windows.isEmpty else { return .failure(.unreadable) }
        return .success(AgentLimits(provider: .antigravity, windows: windows, observedAt: observed, source: .account))
    }

    // MARK: Asking

    /// The sign-in, then `agy`'s version, then its limits, each only if the
    /// step before it allowed.
    static func check(keychain: String?, now: Date, run: Run) -> Result<AgentLimits, Failure> {
        if let failure = signIn(keychain: keychain) { return .failure(failure) }
        switch run(.version) {
        case .notInstalled: return .failure(.notFound)
        case .failed: return .failure(.unreadable)
        case .text(let text):
            guard let found = version(of: text), accepts(found) else { return .failure(.unreadable) }
        }
        switch run(.usage) {
        case .notInstalled: return .failure(.notFound)
        case .failed: return .failure(.unreadable)
        case .text(let text): return limits(stdout: text, observed: now)
        }
    }

    // MARK: This Mac

    /// Where `agy` is installed.
    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        [home.appending(path: ".local/bin/agy").path, "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The sign-in item, read with macOS's own `security` tool; nil when there
    /// is none or the person said no.
    static func readKeychain(timeout: TimeInterval = 10) -> String? {
        let result = BoundedProcessRunner.run(
            "/usr/bin/security", ["find-generic-password", "-s", keychainService, "-a", keychainAccount, "-w"],
            timeout: timeout, maxOutputBytes: 64 * 1024)
        guard !result.timedOut, result.status == 0 else { return nil }
        return String(data: result.output, encoding: .utf8)
    }

    /// Runs `agy` for one command, bounded in time and output.
    static func runProgram(_ command: Command, cancellation: BoundedProcessCancellation? = nil) -> Output {
        guard let path = executable() else { return .notInstalled }
        let arguments = command == .version ? ["--version"] : ["-p", "/usage", "--output-format", "json"]
        // The runner starts a child with no environment at all, and `agy` stops
        // at once without a HOME.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let environment = ["HOME": home, "USER": NSUserName(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let result = BoundedProcessRunner.run(path, arguments, timeout: command == .version ? 10 : 30,
                                              maxOutputBytes: 256 * 1024, environment: environment,
                                              cancellation: cancellation)
        guard !result.timedOut, result.status == 0, let text = String(data: result.output, encoding: .utf8) else { return .failed }
        return .text(text)
    }
}
