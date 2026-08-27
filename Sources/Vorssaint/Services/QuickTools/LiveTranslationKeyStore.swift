// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import Foundation
import Security

/// Stores the user's own Google Cloud Translation API key. A credential like
/// this has no business in UserDefaults (plist, world-readable within the
/// sandbox), so this is the app's first Keychain usage - scoped to this one
/// generic-password item rather than built as a general-purpose store.
enum LiveTranslationKeyStore {
    private static let service = "com.vorssaint.utils.live-translation"
    private static let account = "google-api-key"

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns whether the write actually succeeded, so a caller can tell
    /// the person their key wasn't saved instead of assuming it was.
    @discardableResult
    static func save(_ key: String) -> Bool {
        guard !key.isEmpty else {
            delete()
            return true
        }
        let data = Data(key.utf8)
        // Set on both paths, not just add: an update that only wrote
        // kSecValueData left an existing item's accessibility exactly as it
        // was first created, silently diverging from this constant if it
        // ever changes.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status: OSStatus
        if read() != nil {
            status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        } else {
            status = SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
