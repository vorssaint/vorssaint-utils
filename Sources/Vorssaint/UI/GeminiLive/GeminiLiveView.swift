// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct GeminiLiveView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var service = GeminiLiveService.shared
    @State private var key = ""
    private var strings: GeminiLiveStrings { FeatureStrings.geminiLive(l10n.language) }

    var body: some View {
        Form {
            Section {
                Text(strings.description)
                Text(strings.privacy).font(.caption).foregroundStyle(.secondary)
            } header: { Text(strings.title) }
            Section {
                GeminiLiveKeyEditor(key: $key)
            } header: { Text(strings.keyLabel) }
            Section {
                Button(service.state == .idle ? strings.talk : strings.end) { GeminiLiveController.shared.toggle(apiKey: key) }
                    .disabled(!AppFeature.geminiLive.isAvailable)
            }
        }
        .formStyle(.grouped)
        .onDisappear { key = "" }
    }
}

private struct GeminiLiveKeyEditor: View {
    @Binding var key: String
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = GeminiLiveService.shared
    @State private var keyError: String?
    private var strings: GeminiLiveStrings { FeatureStrings.geminiLive(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField(strings.keyLabel, text: $key).disabled(service.state != .idle)
            HStack {
                Button(strings.save) { saveKey(key) }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.state != .idle)
                Button(strings.remove, role: .destructive) { saveKey("") }.disabled(service.state != .idle)
                Link(strings.getKey, destination: URL(string: "https://aistudio.google.com/apikey")!)
            }
            if let keyError { Text(keyError).foregroundStyle(.red) }
        }
        // Load once; presenting this editor must not overwrite an in-progress edit.
        .task {
            guard key.isEmpty, AppFeature.geminiLive.isAvailable else { return }
            do { key = try GeminiLiveKeyStore.load() }
            catch { keyError = strings.keychainFailed }
        }
    }

    private func saveKey(_ value: String) {
        guard AppFeature.geminiLive.isAvailable, service.state == .idle else { return }
        do {
            try GeminiLiveKeyStore.save(value)
            key = value.trimmingCharacters(in: .whitespacesAndNewlines)
            keyError = nil
        } catch { keyError = strings.keychainFailed }
    }
}

/// First-use key entry; successful Start dismisses this window while voice continues.
struct GeminiLiveSetupView: View {
    let initialKey: String?
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var key = ""
    private var strings: GeminiLiveStrings { FeatureStrings.geminiLive(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(strings.title, systemImage: "sparkles").font(.title2.bold())
            Text(strings.privacy).font(.caption).foregroundStyle(.secondary)
            GeminiLiveKeyEditor(key: $key)
            Button(strings.talk) {
                guard !Task.isCancelled else { return }
                GeminiLiveController.shared.start(apiKey: key)
            }.keyboardShortcut(.defaultAction)
                .disabled(!AppFeature.geminiLive.isAvailable || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .onAppear { if let initialKey { key = initialKey } }
    }
}
