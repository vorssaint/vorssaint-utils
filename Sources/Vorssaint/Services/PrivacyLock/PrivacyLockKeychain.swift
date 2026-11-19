// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import LocalAuthentication
import Security

enum PrivacyLockKeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            return (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)."
        }
    }
}

/// What Privacy Lock keeps in the login Keychain: the app lock's own password
/// as a salted hash, and, only when a person asks for it, the password of a
/// locked item so Touch ID can open it. macOS lets only this app read these
/// without asking; Touch ID is checked in the app before a remembered
/// password is read (see `PrivacyLockAuthenticator`).
enum PrivacyLockKeychain {
    private static let service = "com.vorssaint.utils.privacy-lock"
    private static let appLockAccount = "appLockPassword"
    private static func itemAccount(_ id: String) -> String { "item.\(id)" }

    // MARK: App lock password

    static var hasAppLockPassword: Bool { exists(appLockAccount) }

    static func setAppLockPassword(_ password: String) throws {
        guard let record = PrivacyLockSupport.makePasswordRecord(password) else {
            throw PrivacyLockKeychainError.status(errSecParam)
        }
        try save(appLockAccount, record)
    }

    static func verifyAppLockPassword(_ password: String) -> Bool {
        guard let record = try? read(appLockAccount) else { return false }
        return PrivacyLockSupport.verify(password, against: record)
    }

    static func removeAppLockPassword() { try? delete(appLockAccount) }

    // MARK: Remembered item passwords

    static func hasRememberedPassword(forItem id: String) -> Bool { exists(itemAccount(id)) }

    static func rememberPassword(_ password: String, forItem id: String) throws {
        try save(itemAccount(id), Data(password.utf8))
    }

    static func rememberedPassword(forItem id: String) throws -> String? {
        guard let data = try read(itemAccount(id)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func forgetPassword(forItem id: String) { try? delete(itemAccount(id)) }

    // MARK: Keychain

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func exists(_ account: String) -> Bool {
        var q = query(account)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) != errSecItemNotFound
    }

    private static func read(_ account: String) throws -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default: throw PrivacyLockKeychainError.status(status)
        }
    }

    private static func save(_ account: String, _ data: Data) throws {
        let update = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess: return
        case errSecItemNotFound: break
        default: throw PrivacyLockKeychainError.status(update)
        }
        var add = query(account)
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw PrivacyLockKeychainError.status(status) }
    }

    private static func delete(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PrivacyLockKeychainError.status(status)
        }
    }
}

enum PrivacyLockAuthError: LocalizedError {
    case cancelled
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return nil
        case .unavailable(let message), .failed(let message): return message
        }
    }
}

/// The one place that asks macOS for Touch ID.
enum PrivacyLockAuthenticator {
    /// With `allowPassword` the Mac login password is offered when Touch ID is
    /// not usable; without it only Touch ID counts.
    static func authenticate(reason: String, allowPassword: Bool) async throws {
        let context = LAContext()
        let policy: LAPolicy = allowPassword ? .deviceOwnerAuthentication : .deviceOwnerAuthenticationWithBiometrics
        if !allowPassword { context.localizedFallbackTitle = "" }
        var availability: NSError?
        guard context.canEvaluatePolicy(policy, error: &availability) else {
            throw PrivacyLockAuthError.unavailable(availability?.localizedDescription ?? "")
        }
        do {
            guard try await context.evaluatePolicy(policy, localizedReason: reason) else {
                throw PrivacyLockAuthError.failed("")
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel: throw PrivacyLockAuthError.cancelled
            default: throw PrivacyLockAuthError.failed(error.localizedDescription)
            }
        }
    }
}
