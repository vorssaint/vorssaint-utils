// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AIBarSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = AIBarService.shared
    @AppStorage(DefaultsKey.aiBarShortcutEnabled) private var shortcutEnabled = false
    @AppStorage(DefaultsKey.aiBarEndpoint) private var endpoint = "http://localhost:11434/v1"
    @AppStorage(DefaultsKey.aiBarModel) private var model = ""
    @AppStorage(DefaultsKey.aiBarLocalContext) private var localContext = AIBarContextLevel.fullPaths.rawValue
    @AppStorage(DefaultsKey.aiBarRemoteContext) private var remoteContext = AIBarContextLevel.namesOnly.rawValue
    @State private var apiKey = ""

    private var strings: AIBarFeatureStrings { FeatureStrings.aiBar(l10n.language) }

    var body: some View {
        Form {
            Section {
                Text(strings.hubDescription).font(.caption).foregroundStyle(.secondary)
                Toggle(strings.shortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in service.syncWithPreferences() }
                ShortcutPreferenceRow(role: .aiBar, isEnabled: shortcutEnabled) {
                    service.syncWithPreferences()
                }
                if shortcutEnabled, service.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable).font(.caption).foregroundStyle(.orange)
                }
            }
            Section {
                HStack {
                    TextField(strings.endpointLabel, text: $endpoint)
                    Menu {
                        Button(strings.presetOllama) { endpoint = "http://localhost:11434/v1" }
                        Button(strings.presetLMStudio) { endpoint = "http://localhost:1234/v1" }
                        Button(strings.presetOpenAI) { endpoint = "https://api.openai.com/v1" }
                        Button(strings.presetOpenRouter) { endpoint = "https://openrouter.ai/api/v1" }
                    } label: { Image(systemName: "chevron.down.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                if !AIBarEndpoint.isTransportAcceptable(endpoint) {
                    Text(strings.insecureEndpoint).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    TextField(strings.modelLabel, text: $model, prompt: Text(strings.modelPlaceholder))
                    Button(strings.detectModels) { service.detectModels(endpoint: endpoint) }
                        .disabled(service.isDetectingModels || !AIBarEndpoint.isTransportAcceptable(endpoint))
                }
                if !service.detectedModels.isEmpty {
                    Picker(strings.modelsFoundFormat.replacingOccurrences(of: "%d", with: String(service.detectedModels.count)),
                           selection: $model) {
                        ForEach(service.detectedModels, id: \.self) { Text($0).tag($0) }
                    }
                }
                SecureField(strings.apiKeyLabel, text: $apiKey)
                    .onSubmit { AIBarKeychain.write(apiKey) }
                Text(strings.apiKeyCaption).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                contextPicker(strings.localContextLabel, selection: $localContext)
                contextPicker(strings.remoteContextLabel, selection: $remoteContext)
                Text(strings.privacyCaption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { apiKey = AIBarKeychain.read() ?? "" }
        .onDisappear { AIBarKeychain.write(apiKey) }
    }

    private func contextPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text(strings.contextNone).tag(AIBarContextLevel.none.rawValue)
            Text(strings.contextNames).tag(AIBarContextLevel.namesOnly.rawValue)
            Text(strings.contextPaths).tag(AIBarContextLevel.fullPaths.rawValue)
        }
    }
}
