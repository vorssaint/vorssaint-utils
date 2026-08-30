// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct DictationSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DictationService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.dictationEnabled) private var enabled = false
    @AppStorage(DefaultsKey.dictationProvider) private var providerRaw = DictationProvider.openAI.rawValue
    @AppStorage(DefaultsKey.dictationOpenAIModel) private var openAIModel = DictationProvider.openAI.defaultModel.id
    @AppStorage(DefaultsKey.dictationGroqModel) private var groqModel = DictationProvider.groq.defaultModel.id
    @AppStorage(DefaultsKey.dictationMode) private var modeRaw = DictationShortcutMode.toggle.rawValue
    @AppStorage(DefaultsKey.dictationLanguage) private var languageRaw = DictationLanguage.automatic.rawValue
    @AppStorage(DefaultsKey.dictationSecondaryEnabled) private var secondaryEnabled = false
    @AppStorage(DefaultsKey.dictationSecondaryMode) private var secondaryModeRaw = DictationShortcutMode.toggle.rawValue
    @AppStorage(DefaultsKey.dictationSecondaryLanguage) private var secondaryLanguageRaw = DictationLanguage.automatic.rawValue
    @AppStorage(DefaultsKey.dictationSecondaryProvider) private var secondaryProviderRaw = DictationProvider.groq.rawValue
    @AppStorage(DefaultsKey.dictationSecondaryOpenAIModel) private var secondaryOpenAIModel = DictationProvider.openAI.defaultModel.id
    @AppStorage(DefaultsKey.dictationSecondaryGroqModel) private var secondaryGroqModel = DictationProvider.groq.defaultModel.id
    @State private var keyDraft = ""
    @State private var status: Status?
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?

    private enum Status {
        case saved, removed, testSucceeded, failure(DictationFailure)
    }

    private var strings: DictationFeatureStrings { FeatureStrings.dictation(l10n.language) }
    private var activation: DictationActivationStrings { FeatureStrings.dictationActivation(l10n.language) }
    private var provider: DictationProvider {
        DictationProvider(rawValue: providerRaw) ?? .openAI
    }
    private var mode: DictationShortcutMode {
        DictationShortcutMode(rawValue: modeRaw) ?? .toggle
    }

    var body: some View {
        Form {
            Section {
                Toggle(strings.enable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
                Text(activation.intro(mode, toggleIntro: strings.intro))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, permissions.microphone == .denied {
                    PermissionRow(kind: .microphone)
                }
                if enabled, !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                }
            } header: {
                Text(strings.title)
            }

            Section {
                Text(activation.primary).font(.headline)
                Picker(strings.shortcut, selection: $modeRaw) {
                    ForEach(DictationShortcutMode.allCases) { mode in
                        Text(activation.modeName(mode)).tag(mode.rawValue)
                    }
                }
                .onChange(of: modeRaw) { _, _ in service.syncWithPreferences() }
                Picker(activation.language, selection: $languageRaw) {
                    ForEach(DictationLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                .onChange(of: languageRaw) { _, _ in service.syncWithPreferences() }
                ShortcutPreferenceRow(role: .dictation, isEnabled: enabled) {
                    service.syncWithPreferences()
                }
                if enabled, service.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable).font(.caption).foregroundStyle(.orange)
                }
                Divider()
                Toggle(activation.secondary, isOn: $secondaryEnabled)
                    .onChange(of: secondaryEnabled) { _, _ in service.syncWithPreferences() }
                if secondaryEnabled {
                    Picker(strings.shortcut, selection: $secondaryModeRaw) {
                        ForEach(DictationShortcutMode.allCases) { mode in
                            Text(activation.modeName(mode)).tag(mode.rawValue)
                        }
                    }
                    .onChange(of: secondaryModeRaw) { _, _ in service.syncWithPreferences() }
                    Picker(activation.language, selection: $secondaryLanguageRaw) {
                        ForEach(DictationLanguage.allCases) { language in
                            Text(language.displayName).tag(language.rawValue)
                        }
                    }
                    .onChange(of: secondaryLanguageRaw) { _, _ in service.syncWithPreferences() }
                    Picker(strings.provider, selection: $secondaryProviderRaw) {
                        ForEach(DictationProvider.allCases) { provider in
                            Text(strings.providerName(provider)).tag(provider.rawValue)
                        }
                    }
                    .onChange(of: secondaryProviderRaw) { _, _ in service.syncWithPreferences() }
                    Picker(strings.model, selection: secondaryModelBinding) {
                        ForEach(secondaryProvider.models) { model in Text(model.id).tag(model.id) }
                    }
                    .onChange(of: secondaryOpenAIModel) { _, _ in service.syncWithPreferences() }
                    .onChange(of: secondaryGroqModel) { _, _ in service.syncWithPreferences() }
                    ShortcutPreferenceRow(role: .dictationSecondary, isEnabled: enabled) {
                        service.syncWithPreferences()
                    }
                    if service.secondaryShortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable).font(.caption).foregroundStyle(.orange)
                    }
                }
            } header: { Text(activation.activation) }

            Section {
                Picker(strings.provider, selection: $providerRaw) {
                    ForEach(DictationProvider.allCases) { provider in
                        Text(strings.providerName(provider)).tag(provider.rawValue)
                    }
                }
                .onChange(of: providerRaw) { _, _ in
                    cancelConfigurationTest()
                    status = nil
                    loadKey()
                    service.syncWithPreferences()
                }
                Picker(strings.model, selection: modelBinding) {
                    ForEach(provider.models) { model in
                        Text(model.id).tag(model.id)
                    }
                }
                .onChange(of: openAIModel) { _, _ in service.syncWithPreferences() }
                .onChange(of: groqModel) { _, _ in service.syncWithPreferences() }
                SecureField(strings.apiKey, text: $keyDraft)
                    .textContentType(.password)
                HStack(spacing: 8) {
                    Button(strings.saveKey) { saveKey() }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(strings.removeKey, role: .destructive) { removeKey() }
                    Button(testing ? strings.testing : strings.testConfiguration) {
                        testConfiguration()
                    }
                    .disabled(testing || keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let status {
                    Text(statusMessage(status))
                        .font(.caption)
                        .foregroundStyle(statusIsSuccess(status) ? .green : .orange)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Label(strings.externalWarning, systemImage: "network")
                    Label(strings.microphoneNote, systemImage: "mic")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadKey()
            service.syncWithPreferences()
        }
        .onDisappear { cancelConfigurationTest() }
    }

    private var modelBinding: Binding<String> {
        Binding(get: {
            provider == .openAI ? openAIModel : groqModel
        }, set: { value in
            if provider == .openAI { openAIModel = value } else { groqModel = value }
        })
    }

    private var secondaryProvider: DictationProvider {
        DictationProvider(rawValue: secondaryProviderRaw) ?? .groq
    }

    private var secondaryModelBinding: Binding<String> {
        Binding(get: {
            secondaryProvider == .openAI ? secondaryOpenAIModel : secondaryGroqModel
        }, set: { value in
            if secondaryProvider == .openAI { secondaryOpenAIModel = value }
            else { secondaryGroqModel = value }
        })
    }

    private func loadKey() {
        do {
            keyDraft = try service.storedKey(for: provider) ?? ""
        } catch {
            keyDraft = ""
            status = .failure(.keychain)
        }
    }

    private func saveKey() {
        do {
            try service.saveKey(keyDraft, for: provider)
            keyDraft = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            status = .saved
        } catch {
            status = .failure(.keychain)
        }
    }

    private func removeKey() {
        do {
            try service.removeKey(for: provider)
            keyDraft = ""
            status = .removed
        } catch {
            status = .failure(.keychain)
        }
    }

    private func testConfiguration() {
        let provider = provider
        let key = keyDraft
        testing = true
        status = nil
        testTask?.cancel()
        testTask = Task {
            do {
                try await service.testConfiguration(provider: provider, apiKey: key)
                guard !Task.isCancelled,
                      self.provider == provider,
                      self.keyDraft == key else { return }
                status = .testSucceeded
            } catch let failure as DictationFailure {
                guard !Task.isCancelled,
                      self.provider == provider,
                      self.keyDraft == key else { return }
                status = .failure(failure)
            } catch {
                guard !Task.isCancelled,
                      self.provider == provider,
                      self.keyDraft == key else { return }
                status = .failure(.network)
            }
            testing = false
            testTask = nil
        }
    }

    private func cancelConfigurationTest() {
        testTask?.cancel()
        testTask = nil
        testing = false
    }

    private func statusMessage(_ status: Status) -> String {
        switch status {
        case .saved: return strings.keySaved
        case .removed: return strings.keyRemoved
        case .testSucceeded: return strings.testSucceeded
        case .failure(let failure): return strings.failureMessage(failure)
        }
    }

    private func statusIsSuccess(_ status: Status) -> Bool {
        switch status {
        case .saved, .removed, .testSucceeded: return true
        case .failure: return false
        }
    }
}
