// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct SelectionTranslationSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = SelectionTranslationService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.selectionTranslationShortcutEnabled) private var shortcutEnabled = true
    @State private var providerName = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var target = SelectionTranslationLanguage.simplifiedChinese
    @State private var systemPrompt = ""
    @State private var userPrompt = ""
    @State private var status = ""

    private var text: SelectionTranslationFeatureStrings { FeatureStrings.selectionTranslation(l10n.language) }

    var body: some View {
        Form {
            Section { Text(text.pageCaption).font(.caption).foregroundStyle(.secondary)
                Toggle(text.shortcut, isOn: $shortcutEnabled).onChange(of: shortcutEnabled) { _, _ in service.syncWithPreferences() }
                ShortcutPreferenceRow(role: .selectionTranslation, isEnabled: shortcutEnabled) { service.syncWithPreferences() }
            } header: { Text(text.title) }
            Section(text.providerSection) {
                TextField(text.providerName, text: $providerName)
                TextField(text.baseURL, text: $baseURL)
                TextField(text.model, text: $model)
                SecureField(text.apiKey, text: $apiKey)
                HStack { Button(text.save) { save() }; Button(text.testConnection) { test() }; Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Section(text.targetLanguage) {
                Picker(text.targetLanguage, selection: $target) { ForEach(SelectionTranslationLanguage.targetOptions) { Text($0.displayName).tag($0) } }
            }
            Section(text.promptsSection) {
                TextEditor(text: $systemPrompt).frame(minHeight: 110)
                TextEditor(text: $userPrompt).frame(minHeight: 90)
                Text("{{text}} is replaced with the selected text.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                Label(permissions.accessibility ? "Accessibility granted" : text.permissionRequired,
                      systemImage: permissions.accessibility ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .foregroundStyle(permissions.accessibility ? .green : .orange)
                if !permissions.accessibility {
                    Button("Open Accessibility Settings") { Permissions.shared.openAccessibilitySettings() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { load() }
    }

    private func load() {
        let s = SelectionTranslationSettingsStore.snapshot()
        providerName = s.providerName; baseURL = s.baseURL; model = s.model; apiKey = s.apiKey
        target = s.languages.target; systemPrompt = s.prompts.systemPrompt; userPrompt = s.prompts.userPrompt
    }
    private func save() {
        do { try SelectionTranslationSettingsStore.save(providerName: providerName, baseURL: baseURL, model: model, apiKey: apiKey, targetLanguage: target, systemPrompt: systemPrompt, userPrompt: userPrompt); status = "Saved"; service.syncWithPreferences() }
        catch { status = error.localizedDescription }
    }
    private func test() {
        do {
            guard let url = URL(string: baseURL) else { throw SelectionTranslationProviderConfiguration.ValidationError.unsupportedURL }
            let p = try SelectionTranslationProviderConfiguration(baseURL: url, model: model, apiKey: apiKey)
            let prompts = try SelectionTranslationPromptTemplates(systemPrompt: systemPrompt, userPrompt: userPrompt)
            let request = SelectionTranslationRequest(source: "Hello", languages: .init(target: target), prompts: prompts, provider: p)
            Task { do { try await SelectionTranslationClient.shared.testConnection(request); await MainActor.run { status = "Connected" } } catch { await MainActor.run { status = error.localizedDescription } } }
        } catch { status = error.localizedDescription }
    }
}
