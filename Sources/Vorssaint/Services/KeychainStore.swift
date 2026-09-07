// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os
import Security

protocol KeychainStoring {
    func value(service: String, account: String) throws -> String?
    func setValue(_ value: String, service: String, account: String) throws
    func deleteValue(service: String, account: String) throws
}

enum KeychainStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

final class KeychainStore: KeychainStoring {
    static let shared = KeychainStore()
    private let logger = Logger(subsystem: "com.vorssaint.utils", category: "KeychainStore")

    /// Developer and Release bundles have different signing identities. Keep
    /// their credentials in separate Keychain records so a local build never
    /// asks to access an item created by the distributed app.
    static func namespacedService(_ service: String,
                                  bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> String {
        guard bundleIdentifier == "com.vorssaint.utils.dev" else { return service }
        return service + ".dev"
    }

    func value(service: String, account: String) throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { throw KeychainStoreError.invalidData }
        return value
    }

    func setValue(_ value: String, service: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteValue(service: service, account: account)
            return
        }
        let data = Data(trimmed.utf8)
        let query = baseQuery(service: service, account: account)
        // Recreate only this record instead of updating across legacy and
        // data-protection keychain classes. This is reliable after a bundle
        // signature changes and mirrors the safe replacement flow used by
        // other macOS clients.
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            logger.error("Keychain delete failed with status \(deleteStatus, privacy: .public)")
            throw KeychainStoreError.unexpectedStatus(deleteStatus)
        }
        var addition = query
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            logger.error("Keychain add failed with status \(addStatus, privacy: .public)")
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }
    }

    func deleteValue(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Keep this query on the classic login keychain. The Developer
            // bundle is ad-hoc signed and has no team entitlement, so Apple's
            // data-protection keychain returns errSecMissingEntitlement
            // (-34018). The item remains encrypted by the user's login
            // keychain, while the bundle-specific service prevents cross-app
            // ACL prompts.
        ]
    }
}
