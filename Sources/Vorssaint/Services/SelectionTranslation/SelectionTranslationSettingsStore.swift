// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security

struct SelectionTranslationSettingsSnapshot: Sendable {
    let providerName: String
    let baseURL: String
    let model: String
    let apiKey: String
    let languages: SelectionTranslationLanguageSelection
    let prompts: SelectionTranslationPromptTemplates
}

enum SelectionTranslationKeychain {
    private static let service = "com.vorssaint.selection-translation"
    private static let account = "api-key"

    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: service,
                                     kSecAttrAccount as String: account,
                                     kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func write(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func delete() { 
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

enum SelectionTranslationSettingsStore {
    static func snapshot() -> SelectionTranslationSettingsSnapshot {
        let defaults = UserDefaults.standard
        let system = defaults.string(forKey: DefaultsKey.selectionTranslationSystemPrompt) ?? SelectionTranslationPromptTemplates.default.systemPrompt
        let user = defaults.string(forKey: DefaultsKey.selectionTranslationUserPrompt) ?? SelectionTranslationPromptTemplates.default.userPrompt
        let prompts = (try? SelectionTranslationPromptTemplates(systemPrompt: system, userPrompt: user)) ?? .default
        return SelectionTranslationSettingsSnapshot(
            providerName: defaults.string(forKey: DefaultsKey.selectionTranslationProviderName) ?? "OpenAI-compatible",
            baseURL: defaults.string(forKey: DefaultsKey.selectionTranslationBaseURL) ?? "",
            model: defaults.string(forKey: DefaultsKey.selectionTranslationModel) ?? "",
            apiKey: SelectionTranslationKeychain.read(),
            languages: SelectionTranslationLanguageSelection(target: .matching(defaults.string(forKey: DefaultsKey.selectionTranslationTargetLanguage) ?? "zh-Hans")),
            prompts: prompts)
    }

    static func save(providerName: String, baseURL: String, model: String, apiKey: String,
                     targetLanguage: SelectionTranslationLanguage,
                     systemPrompt: String, userPrompt: String) throws {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SelectionTranslationProviderConfiguration.ValidationError.unsupportedURL
        }
        _ = try SelectionTranslationProviderConfiguration(baseURL: url, model: model, apiKey: apiKey)
        _ = try SelectionTranslationPromptTemplates(systemPrompt: systemPrompt, userPrompt: userPrompt)
        let defaults = UserDefaults.standard
        defaults.set(providerName.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.selectionTranslationProviderName)
        defaults.set(baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.selectionTranslationBaseURL)
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.selectionTranslationModel)
        defaults.set(targetLanguage.rawValue, forKey: DefaultsKey.selectionTranslationTargetLanguage)
        defaults.set(systemPrompt, forKey: DefaultsKey.selectionTranslationSystemPrompt)
        defaults.set(userPrompt, forKey: DefaultsKey.selectionTranslationUserPrompt)
        SelectionTranslationKeychain.write(apiKey)
    }
}
