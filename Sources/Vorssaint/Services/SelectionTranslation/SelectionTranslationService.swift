// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

enum SelectionTranslationPhase: Equatable {
    case idle, reading, translating, streaming, completed, failed(String)
}

final class SelectionTranslationService: ObservableObject {
    static let shared = SelectionTranslationService()

    @Published private(set) var phase: SelectionTranslationPhase = .idle
    @Published private(set) var sourceText = ""
    @Published private(set) var translatedText = ""
    @Published private(set) var usage = SelectionTranslationTokenUsage.zero
    @Published private(set) var startedAt: Date?
    @Published private(set) var generation = 0

    private let hotkey = QuickToolHotkey(id: 31)
    private var task: Task<Void, Never>?

    private init() {
        hotkey.onPress = { [weak self] in self?.trigger() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.selectionTranslation.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.selectionTranslationShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.selectionTranslationShortcut,
                                            fallback: .selectionTranslationDefault)
        _ = hotkey.sync(enabled: enabled, shortcut: shortcut)
        if !enabled { cancel() }
    }

    func suspend() { cancel(); hotkey.unregister() }

    func trigger() {
        guard phase != .reading, phase != .translating, phase != .streaming else { return }
        cancel()
        let current = generation &+ 1
        generation = current
        phase = .reading
        translatedText = ""
        usage = .zero
        startedAt = Date()
        NotificationCenter.default.post(name: .selectionTranslationPresentPanel, object: nil)
        task = Task { [weak self] in
            let text = await SelectionTranslationSelectionReader.read()
            guard let self, !Task.isCancelled, self.generation == current else { return }
            await MainActor.run {
                self.sourceText = text
                guard !text.isEmpty else { self.phase = .failed("No text was selected."); return }
                self.phase = .translating
            }
            do {
                let snapshot = SelectionTranslationSettingsStore.snapshot()
                guard let url = URL(string: snapshot.baseURL) else { throw SelectionTranslationClientError.invalidResponse }
                let provider = try SelectionTranslationProviderConfiguration(baseURL: url, model: snapshot.model, apiKey: snapshot.apiKey)
                let request = SelectionTranslationRequest(source: text, languages: snapshot.languages,
                                                           prompts: snapshot.prompts, provider: provider)
                let result = try await SelectionTranslationClient.shared.translate(request) { piece in
                    DispatchQueue.main.async {
                        guard self.generation == current else { return }
                        self.phase = .streaming
                        self.translatedText += piece
                    }
                }
                await MainActor.run {
                    guard self.generation == current else { return }
                    self.usage = result.usage
                    self.phase = .completed
                }
            } catch is CancellationError {
                await MainActor.run { if self.generation == current { self.phase = .idle } }
            } catch {
                await MainActor.run { if self.generation == current { self.phase = .failed(error.localizedDescription) } }
            }
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        if phase != .idle { phase = .idle }
    }

    func retry() { trigger() }
}

extension Notification.Name {
    static let selectionTranslationPresentPanel = Notification.Name("Vorssaint.selectionTranslation.present")
}
