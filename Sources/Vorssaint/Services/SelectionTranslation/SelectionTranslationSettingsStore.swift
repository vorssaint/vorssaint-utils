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

    enum Error: LocalizedError {
        case writeFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .writeFailed:
                return FeatureStrings.selectionTranslation(L10n.shared.language).keychainWriteFailed
            }
        }
    }

    static func read() -> String {
        read(service: service, account: account) ?? ""
    }

    static func write(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw Error.writeFailed(deleteStatus)
        }
        var add = query
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Error.writeFailed(addStatus) }
    }

    static func delete() { 
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }

    private static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum SelectionTranslationSettingsStore {
    static let defaultProviderName = "OpenAI-compatible"
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"
    static let defaultTargetLanguage = SelectionTranslationLanguage.simplifiedChinese
    static let defaultSystemPrompt = SelectionTranslationPromptTemplates.default.systemPrompt
    static let defaultUserPrompt = SelectionTranslationPromptTemplates.default.userPrompt

    static func snapshot(defaults: UserDefaults = .standard,
                         apiKey: String? = nil) -> SelectionTranslationSettingsSnapshot {
        func string(_ key: String) -> String {
            guard let value = defaults.string(forKey: key) else {
                preconditionFailure("Missing registered default for \(key)")
            }
            return value
        }
        let system = string(DefaultsKey.selectionTranslationSystemPrompt)
        let user = string(DefaultsKey.selectionTranslationUserPrompt)
        let prompts = (try? SelectionTranslationPromptTemplates(systemPrompt: system, userPrompt: user)) ?? .default
        return SelectionTranslationSettingsSnapshot(
            providerName: string(DefaultsKey.selectionTranslationProviderName),
            baseURL: string(DefaultsKey.selectionTranslationBaseURL),
            model: string(DefaultsKey.selectionTranslationModel),
            apiKey: apiKey ?? SelectionTranslationKeychain.read(),
            languages: SelectionTranslationLanguageSelection(target: .matching(
                string(DefaultsKey.selectionTranslationTargetLanguage))),
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
        try SelectionTranslationKeychain.write(apiKey)
    }

    static func savePrompts(systemPrompt: String, userPrompt: String) throws {
        _ = try SelectionTranslationPromptTemplates(systemPrompt: systemPrompt, userPrompt: userPrompt)
        let defaults = UserDefaults.standard
        defaults.set(systemPrompt, forKey: DefaultsKey.selectionTranslationSystemPrompt)
        defaults.set(userPrompt, forKey: DefaultsKey.selectionTranslationUserPrompt)
    }
}
