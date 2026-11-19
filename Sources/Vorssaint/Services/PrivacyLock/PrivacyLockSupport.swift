// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived in part from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.

import CommonCrypto
import Foundation
import Security

/// How a locked app is opened again.
enum AppLockMethod: String, CaseIterable, Identifiable {
    /// Touch ID, with the Mac login password offered when Touch ID is not available.
    case biometric
    /// A password of its own, chosen here and kept only as a salted hash.
    case password

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> AppLockMethod {
        raw.flatMap(AppLockMethod.init(rawValue:)) ?? .biometric
    }
}

/// How long an app stays open after it was unlocked.
enum AppLockRelock: String, CaseIterable, Identifiable {
    case everyTime, oneMinute, fiveMinutes, fifteenMinutes, untilQuit

    var id: String { rawValue }

    /// Seconds the app may sit in the background before it locks again, nil
    /// when it stays open until it quits.
    var seconds: TimeInterval? {
        switch self {
        case .everyTime: return 0
        case .oneMinute: return 60
        case .fiveMinutes: return 5 * 60
        case .fifteenMinutes: return 15 * 60
        case .untilQuit: return nil
        }
    }

    static func sanitized(_ raw: String?) -> AppLockRelock {
        raw.flatMap(AppLockRelock.init(rawValue:)) ?? .fiveMinutes
    }
}

enum PrivacyLockSupport {
    static let fileExtension = "vslock"
    static let minimumPasswordLength = 8
    static let maximumPasswordLength = 256

    /// Apps that can never be locked: locking them would shut the person out of
    /// the Mac, or out of the app that holds the lock.
    static let protectedBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver",
        "com.apple.SecurityAgent", "com.apple.UserNotificationCenter", "com.apple.controlcenter",
    ]

    static func canLock(bundleID: String, ownBundleID: String?) -> Bool {
        !bundleID.isEmpty && !protectedBundleIDs.contains(bundleID) && bundleID != ownBundleID
    }

    // MARK: Stored list of locked apps

    /// One bundle id per line; ids contain no newline, and a restored backup
    /// cannot smuggle in a protected one.
    static func lockedBundleIDs(from stored: String?, ownBundleID: String?) -> [String] {
        var seen = Set<String>()
        return (stored ?? "").split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { canLock(bundleID: $0, ownBundleID: ownBundleID) && seen.insert($0).inserted }
    }

    static func storedValue(for bundleIDs: [String]) -> String {
        bundleIDs.joined(separator: "\n")
    }

    // MARK: Passwords

    enum PasswordProblem: Equatable {
        case tooShort, tooLong, mismatch
    }

    /// Nil when the password may be used. Only length is checked: a rule about
    /// character classes only makes people write the password down.
    static func passwordProblem(_ password: String, confirmation: String?) -> PasswordProblem? {
        if password.count < minimumPasswordLength { return .tooShort }
        if password.count > maximumPasswordLength { return .tooLong }
        if let confirmation, confirmation != password { return .mismatch }
        return nil
    }

    // MARK: Password hash (the app lock's own password)

    static let hashIterations: UInt32 = 600_000
    private static let hashVersion: UInt8 = 1

    /// version(1) | iterations(4, big endian) | salt(16) | derived(32)
    static func makePasswordRecord(_ password: String, iterations: UInt32 = hashIterations) -> Data? {
        var salt = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt) == errSecSuccess,
              let derived = derive(password, salt: salt, iterations: iterations) else { return nil }
        var record = Data([hashVersion])
        withUnsafeBytes(of: iterations.bigEndian) { record.append(contentsOf: $0) }
        record.append(contentsOf: salt)
        record.append(contentsOf: derived)
        return record
    }

    static func verify(_ password: String, against record: Data) -> Bool {
        guard record.count == 1 + 4 + 16 + 32, record[record.startIndex] == hashVersion else { return false }
        let bytes = [UInt8](record)
        let iterations = bytes[1..<5].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard iterations > 0, iterations <= 10_000_000,
              let derived = derive(password, salt: Array(bytes[5..<21]), iterations: iterations) else { return false }
        return constantTimeEqual(derived, Array(bytes[21..<53]))
    }

    private static func derive(_ password: String, salt: [UInt8], iterations: UInt32) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count,
                                          salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                          iterations, &out, out.count)
        return status == Int32(kCCSuccess) ? out : nil
    }

    private static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }

    // MARK: Guessing

    /// Seconds to wait before another try after `failures` wrong passwords in a
    /// row: none for the first four, then doubling from 30 seconds to an hour.
    static func lockoutSeconds(afterFailures failures: Int) -> TimeInterval {
        guard failures >= 5 else { return 0 }
        return min(3600, 30 * pow(2, Double(failures - 5)))
    }

    // MARK: What may be locked

    /// Places that must never be packed and removed: the system, and the home
    /// folder or its Library as a whole.
    static func isLockable(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path == "/" || path == homePath || path == homePath + "/Library" { return false }
        for root in ["/System", "/usr", "/bin", "/sbin", "/private", "/Library", "/Applications"] {
            if path == root || path.hasPrefix(root + "/") { return false }
        }
        return true
    }

    // MARK: Names

    /// `name.txt` becomes `name.txt.vslock`; a taken name gets ` 2`, ` 3` and so on.
    static func containerName(for original: String) -> String { original + "." + fileExtension }

    static func uniqueName(_ name: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ext.isEmpty ? name : ns.deletingPathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !exists(candidate) { return candidate }
            counter += 1
        }
    }

    /// A name taken from inside a container must stay inside its folder.
    static func safeComponent(_ name: String) -> String? {
        let last = (name as NSString).lastPathComponent
        return (last.isEmpty || last == "." || last == "..") ? nil : last
    }
}

/// What a Finder Quick Action asks Vorssaint to do. The action runs a short
/// script that opens `vorssaint://privacy-lock/<action>?p=<path>&p=<path>`,
/// each path in base64url so no character of a file name can break the link.
/// A link only ever starts a question (a password prompt) or adds an app to
/// the lock list; nothing that weakens a lock happens without proof.
enum PrivacyLockLinkAction: String, CaseIterable {
    case lockItems = "lock"
    case unlockItems = "unlock"
    case lockApps = "lock-app"
    case unlockApps = "unlock-app"
    /// Locks the apps that are open and unlocks the ones that are locked.
    case toggleApps = "toggle-app"
}

enum PrivacyLockLink {
    static let scheme = "vorssaint"
    static let host = "privacy-lock"
    static let maximumPaths = 500

    static func encode(_ path: String) -> String {
        Data(path.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> String? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64), let path = String(data: data, encoding: .utf8),
              path.hasPrefix("/"), !path.contains("\0") else { return nil }
        return path
    }

    static func url(action: PrivacyLockLinkAction, paths: [String]) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + action.rawValue
        components.queryItems = paths.map { URLQueryItem(name: "p", value: encode($0)) }
        return components.url
    }

    static func parse(_ url: URL) -> (action: PrivacyLockLinkAction, paths: [URL])? {
        guard url.scheme == scheme, url.host == host,
              let action = PrivacyLockLinkAction(rawValue: String(url.path.dropFirst())),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let paths = items.filter { $0.name == "p" }.prefix(maximumPaths)
            .compactMap { $0.value.flatMap(decode) }.map { URL(fileURLWithPath: $0) }
        return paths.isEmpty ? nil : (action, paths)
    }
}
