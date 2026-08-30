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
    @State private var promptStatus = ""

    private var text: SelectionTranslationFeatureStrings { FeatureStrings.selectionTranslation(l10n.language) }

    var body: some View {
        Form {
            Section { Text(text.pageCaption).font(.caption).foregroundStyle(.secondary)
                Toggle(text.shortcut, isOn: $shortcutEnabled).onChange(of: shortcutEnabled) { _, _ in service.syncWithPreferences() }
                ShortcutPreferenceRow(role: .selectionTranslation, isEnabled: shortcutEnabled) { service.syncWithPreferences() }
                if service.shortcutStatus.isError {
                    Label(text.shortcutConflict, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
                PromptEditorCard(title: text.systemPrompt,
                                 systemImage: "brain.head.profile",
                                 text: $systemPrompt,
                                 minimumHeight: 220,
                                 variables: [text.sourceVariable, text.targetVariable],
                                 strings: text)
                PromptEditorCard(title: text.userPrompt,
                                 systemImage: "text.quote",
                                 text: $userPrompt,
                                 minimumHeight: 160,
                                 variables: [text.sourceVariable, text.targetVariable, text.textVariable],
                                 strings: text)
                HStack(spacing: 10) {
                    Button(text.savePrompts) { savePrompts() }
                    Button(text.restoreDefaults) { restoreDefaultPrompts() }
                    Spacer()
                    if !promptStatus.isEmpty {
                        Text(promptStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section(text.permissions) {
                Label(permissions.accessibility ? text.accessibilityGranted : text.permissionRequired,
                      systemImage: permissions.accessibility ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .foregroundStyle(permissions.accessibility ? .green : .orange)
                if !permissions.accessibility {
                    Button(text.openAccessibilitySettings) { Permissions.shared.openAccessibilitySettings() }
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
        do {
            try SelectionTranslationSettingsStore.save(providerName: providerName, baseURL: baseURL, model: model, apiKey: apiKey,
                                                       targetLanguage: target, systemPrompt: systemPrompt, userPrompt: userPrompt)
            status = text.savedStatus
            service.syncWithPreferences()
        }
        catch { status = error.localizedDescription }
    }

    private func savePrompts() {
        do {
            try SelectionTranslationSettingsStore.savePrompts(systemPrompt: systemPrompt, userPrompt: userPrompt)
            promptStatus = text.savedStatus
            service.syncWithPreferences()
        } catch {
            promptStatus = error.localizedDescription
        }
    }

    private func restoreDefaultPrompts() {
        systemPrompt = SelectionTranslationSettingsStore.defaultSystemPrompt
        userPrompt = SelectionTranslationSettingsStore.defaultUserPrompt
        savePrompts()
    }
    private func test() {
        do {
            guard let url = URL(string: baseURL) else { throw SelectionTranslationProviderConfiguration.ValidationError.unsupportedURL }
            let p = try SelectionTranslationProviderConfiguration(baseURL: url, model: model, apiKey: apiKey)
            let prompts = try SelectionTranslationPromptTemplates(systemPrompt: systemPrompt, userPrompt: userPrompt)
            let request = SelectionTranslationRequest(source: "Hello", languages: .init(target: target), prompts: prompts, provider: p)
            Task {
                do {
                    try await SelectionTranslationClient.shared.testConnection(request)
                    await MainActor.run { status = text.connectedStatus }
                } catch {
                    await MainActor.run { status = error.localizedDescription }
                }
            }
        } catch { status = error.localizedDescription }
    }
}

private struct PromptEditorCard: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    let minimumHeight: CGFloat
    let variables: [String]
    let strings: SelectionTranslationFeatureStrings
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(.secondary)
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(String(format: strings.charactersFormat, text.count))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $text)
                .font(.system(size: 16))
                .lineSpacing(6)
                .tint(.accentColor)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: minimumHeight)
                .focused($isFocused)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isFocused ? Color.accentColor : Color.secondary.opacity(0.28),
                                lineWidth: isFocused ? 2 : 1)
                )
            VStack(alignment: .leading, spacing: 7) {
                Text(strings.availableVariables)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    ForEach(variables, id: \.self) { variable in
                        Text(variable)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }
}
