// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security

/// Optional OpenAI-compatible cleanup. The API credential lives in Keychain;
/// neither preferences nor settings backups carry it.
enum DictationCleanup {
    static var service: String { (Bundle.main.bundleIdentifier ?? "com.vorssaint.utils") + ".dictation" }
    static func key() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: "cleanup", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func setKey(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "cleanup"]
        if value.isEmpty { SecItemDelete(query as CFDictionary); return }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw DictationError.message("Could not save the cleanup credential in Keychain (\(status)).") }
    }

    static func run(_ text: String) async throws -> String {
        let defaults = UserDefaults.standard
        guard let url = URL(string: defaults.string(forKey: DefaultsKey.dictationCleanupURL) ?? ""),
              let host = url.host, url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw DictationError.message("Cleanup requires HTTPS, or HTTP on localhost for a local model.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = key()
        if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": defaults.string(forKey: DefaultsKey.dictationCleanupModel) ?? "",
            "messages": [["role": "system", "content": defaults.string(forKey: DefaultsKey.dictationCleanupPrompt) ?? DictationSupport.defaultCleanupPrompt],
                         ["role": "user", "content": text]], "stream": false])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw DictationError.message("Text cleanup failed. The original transcript is available in history.")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any],
              let cleaned = message["content"] as? String,
              !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DictationError.message("Text cleanup returned no text.")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
