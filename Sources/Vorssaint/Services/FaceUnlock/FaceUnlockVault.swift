// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.

import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum FaceUnlockVaultError: LocalizedError {
    case emptyPassword
    case sessionLocked
    case encryptionFailed
    case decryptionFailed
    case sessionKeyUnavailable
    case authenticationUnavailable
    case authenticationFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyPassword: return "The password is empty."
        case .sessionLocked: return "Face Unlock is locked until you confirm it is you."
        case .encryptionFailed: return "The data could not be encrypted."
        case .decryptionFailed: return "The stored data could not be decrypted."
        case .sessionKeyUnavailable:
            return "The key for the stored data is missing. Nothing was deleted; remove the saved password to start over."
        case .authenticationUnavailable: return "This Mac cannot confirm your identity with Touch ID or a password."
        case .authenticationFailed: return "Authentication was cancelled or failed."
        case .keychain(let status):
            return (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)."
        }
    }
}

extension Notification.Name {
    /// Posted whenever the in-memory session key appears or disappears, so
    /// anything encrypted under it reloads itself instead of relying on each
    /// caller to remember.
    static let faceUnlockSessionDidChange = Notification.Name("FaceUnlockVault.sessionDidChange")
}

/// What Face Unlock keeps secret, and how.
///
/// Two layers. A random 256 bit key lives in the login Keychain, where macOS
/// lets only this app read it without asking. The key is released into memory
/// only after Touch ID or the account password confirms the person at the Mac,
/// once per launch. Under that key sit the saved account password and the face
/// templates, both AES-GCM sealed. Locking the session forgets the key; the
/// sealed data is useless without it.
///
/// Nothing here can be read while the Mac is locked unless the session was
/// opened before it locked, which is also why unlocking needs that one
/// confirmation after every launch.
enum FaceUnlockVault {
    private static let service = "com.vorssaint.utils.face-unlock"
    private static let sessionKeyAccount = "sessionKey"
    private static let passwordBlobAccount = "encryptedPassword"

    // MARK: - Session state

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var key: SymmetricKey?
        private var lastActivity: Date?
        private var unlocking = false

        var hasKey: Bool { lock.withLock { key != nil } }
        var currentKey: SymmetricKey? { lock.withLock { key } }
        var activity: Date? { lock.withLock { lastActivity } }

        /// Returns whether the presence of a key changed.
        func set(_ newKey: SymmetricKey?) -> Bool {
            lock.withLock {
                let changed = (newKey != nil) != (key != nil)
                key = newKey
                lastActivity = newKey == nil ? nil : Date()
                return changed
            }
        }

        func touch() { lock.withLock { if key != nil { lastActivity = Date() } } }

        func beginUnlock() -> Bool {
            lock.withLock {
                guard !unlocking else { return false }
                unlocking = true
                return true
            }
        }

        func endUnlock() { lock.withLock { unlocking = false } }
    }

    private static let state = State()

    static var isSessionUnlocked: Bool { state.hasKey }

    /// The last unlock or successful password read; what the idle limit is
    /// measured from. `nil` while the session is locked.
    static var lastActivityAt: Date? { state.activity }

    private static func setKey(_ key: SymmetricKey?) {
        // Posted after the lock is released: observers call straight back in.
        guard state.set(key) else { return }
        NotificationCenter.default.post(name: .faceUnlockSessionDidChange, object: nil)
    }

    // MARK: - Crypto under the session key

    static func encrypt(_ plaintext: Data) throws -> Data {
        guard let key = state.currentKey else { throw FaceUnlockVaultError.sessionLocked }
        guard let combined = try? AES.GCM.seal(plaintext, using: key).combined else {
            throw FaceUnlockVaultError.encryptionFailed
        }
        return combined
    }

    static func decrypt(_ ciphertext: Data) throws -> Data {
        guard let key = state.currentKey else { throw FaceUnlockVaultError.sessionLocked }
        guard let box = try? AES.GCM.SealedBox(combined: ciphertext),
              let plaintext = try? AES.GCM.open(box, using: key) else {
            throw FaceUnlockVaultError.decryptionFailed
        }
        return plaintext
    }

    // MARK: - Session

    static var hasSessionKey: Bool { keychainExists(sessionKeyAccount) }

    /// Checked without the key, so it stays answerable exactly when the key
    /// cannot be read.
    static var hasSessionEncryptedData: Bool {
        keychainExists(passwordBlobAccount) || FaceUnlockFaceStore.exists
    }

    static func hasStoredPassword() -> Bool { keychainExists(passwordBlobAccount) }

    /// Confirms the person with Touch ID or the account password, then
    /// releases the key. Creates it on first use, but never when sealed data
    /// already exists: a new key would make that data unreadable for good.
    static func unlockSession(reason: String) async throws {
        if state.hasKey { return }
        guard state.beginUnlock() else { return }
        defer { state.endUnlock() }
        try await authenticate(reason: reason)
        if let existing = try keychainRead(sessionKeyAccount) {
            setKey(SymmetricKey(data: existing))
            return
        }
        guard !hasSessionEncryptedData else { throw FaceUnlockVaultError.sessionKeyUnavailable }
        let key = SymmetricKey(size: .bits256)
        try keychainSave(sessionKeyAccount, key.withUnsafeBytes { Data($0) })
        setKey(key)
    }

    static func lockSession() { setKey(nil) }

    private static func authenticate(reason: String) async throws {
        let context = LAContext()
        var availability: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availability) else {
            throw FaceUnlockVaultError.authenticationUnavailable
        }
        do {
            let confirmed = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                             localizedReason: reason)
            guard confirmed else { throw FaceUnlockVaultError.authenticationFailed }
        } catch let error as FaceUnlockVaultError {
            throw error
        } catch {
            throw FaceUnlockVaultError.authenticationFailed
        }
    }

    // MARK: - Password

    /// Seals and stores the password. The session must be unlocked.
    static func savePassword(_ bytes: Data) throws {
        guard !bytes.isEmpty else { throw FaceUnlockVaultError.emptyPassword }
        try keychainSave(passwordBlobAccount, try encrypt(bytes))
    }

    /// The caller zeroes the returned bytes with `resetBytes(in:)` after use.
    static func readPassword() throws -> Data {
        guard state.hasKey else { throw FaceUnlockVaultError.sessionLocked }
        guard let ciphertext = try keychainRead(passwordBlobAccount) else {
            throw FaceUnlockVaultError.decryptionFailed
        }
        let plaintext = try decrypt(ciphertext)
        state.touch()
        return plaintext
    }

    /// Removes the saved password and the key together, and forgets the
    /// session. Face data sealed under that key goes with it, by the caller.
    static func deletePassword() throws {
        try keychainDelete(passwordBlobAccount)
        try keychainDelete(sessionKeyAccount)
        setKey(nil)
    }

    // MARK: - Keychain

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// Attributes only: never prompts.
    private static func keychainExists(_ account: String) -> Bool {
        var query = baseQuery(account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) != errSecItemNotFound
    }

    private static func keychainRead(_ account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        case errSecUserCanceled, errSecAuthFailed: throw FaceUnlockVaultError.authenticationFailed
        default: throw FaceUnlockVaultError.keychain(status)
        }
    }

    /// Updates in place when the item exists, which avoids a delete and add
    /// gap that a second save could race into a duplicate-item error.
    private static func keychainSave(_ account: String, _ data: Data) throws {
        let update = SecItemUpdate(baseQuery(account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess: return
        case errSecItemNotFound: break
        default: throw FaceUnlockVaultError.keychain(update)
        }
        var add = baseQuery(account)
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { return }
        if status == errSecDuplicateItem {
            let retry = SecItemUpdate(baseQuery(account) as CFDictionary,
                                      [kSecValueData as String: data] as CFDictionary)
            guard retry == errSecSuccess else { throw FaceUnlockVaultError.keychain(retry) }
            return
        }
        throw FaceUnlockVaultError.keychain(status)
    }

    private static func keychainDelete(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FaceUnlockVaultError.keychain(status)
        }
    }
}

/// The enrolled face templates, sealed under the session key. A distinct file
/// name, so plaintext can never be taken for ciphertext.
enum FaceUnlockFaceStore {
    private static var fileURL: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("FaceUnlock", isDirectory: true)
            .appendingPathComponent("face-identities.enc")
    }

    static var exists: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Throws while the session is locked rather than returning nothing, so a
    /// locked store is never mistaken for an empty one.
    static func load() throws -> [FaceIdentity] {
        guard FaceUnlockVault.isSessionUnlocked else { throw FaceUnlockVaultError.sessionLocked }
        guard let fileURL, let ciphertext = try? Data(contentsOf: fileURL) else { return [] }
        let plaintext = try FaceUnlockVault.decrypt(ciphertext)
        return try JSONDecoder().decode([FaceIdentity].self, from: plaintext)
    }

    static func save(_ identities: [FaceIdentity]) throws {
        guard FaceUnlockVault.isSessionUnlocked else { throw FaceUnlockVaultError.sessionLocked }
        guard let fileURL, PrivateFileStore.createDirectory(at: fileURL.deletingLastPathComponent()) else {
            throw FaceUnlockVaultError.encryptionFailed
        }
        let ciphertext = try FaceUnlockVault.encrypt(try JSONEncoder().encode(identities))
        guard PrivateFileStore.write(ciphertext, to: fileURL) else {
            throw FaceUnlockVaultError.encryptionFailed
        }
    }

    static func deleteAll() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
