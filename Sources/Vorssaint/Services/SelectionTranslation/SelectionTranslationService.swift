// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

enum SelectionTranslationPhase: Equatable {
    case idle
    case ready
    case reading
    case translating
    case streaming
    case completed
    case interrupted
    case failed(String)
}

@MainActor
final class SelectionTranslationService: ObservableObject {
    static let shared = SelectionTranslationService()

    @Published private(set) var phase: SelectionTranslationPhase = .idle
    @Published private(set) var draft = SelectionTranslationDraft()
    @Published private(set) var submittedDraft: SelectionTranslationDraft?
    @Published private(set) var translatedText = ""
    @Published private(set) var usage = SelectionTranslationTokenUsage.zero
    @Published private(set) var timing = SelectionTranslationTiming.idle
    @Published private(set) var generation = 0
    @Published private(set) var requiresSubmission = false
    @Published private(set) var failureAction: SelectionTranslationFailureAction?
    @Published private(set) var shortcutStatus: SelectionTranslationShortcutStatus = .disabled
    @Published private(set) var providerName = ""

    private let hotkey = QuickToolHotkey(id: SelectionTranslationConstants.quickToolHotkeyID)
    private var task: Task<Void, Never>?
    private var panelAnchor = NSEvent.mouseLocation

    private init() {
        hotkey.onPress = { [weak self] in
            Task { @MainActor [weak self] in self?.trigger() }
        }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.selectionTranslation.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.selectionTranslationShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.selectionTranslationShortcut,
                                            fallback: .selectionTranslationDefault)
        let registered = hotkey.sync(enabled: enabled, shortcut: shortcut)
        shortcutStatus = enabled ? (registered ? .registered : .conflict) : .disabled
        if !enabled { dismiss() }
    }

    func suspend() {
        dismiss()
        hotkey.unregister()
        shortcutStatus = .disabled
    }

    func trigger() {
        guard phase != .reading, phase != .translating, phase != .streaming else { return }
        cancelRequestOnly()
        generation &+= 1
        let current = generation
        let settings = SelectionTranslationSettingsStore.snapshot()
        panelAnchor = NSEvent.mouseLocation
        draft = SelectionTranslationDraft(languages: settings.languages)
        submittedDraft = nil
        translatedText = ""
        usage = .zero
        timing = .idle
        requiresSubmission = false
        failureAction = nil
        phase = .reading

        guard Permissions.shared.accessibility else {
            phase = .failed(FeatureStrings.selectionTranslation(L10n.shared.language).permissionRequired)
            failureAction = .openAccessibilitySettings
            SelectionTranslationPanelController.shared.present(anchor: panelAnchor, focusSourceEditor: false)
            return
        }

        task = Task { [weak self] in
            let text = await SelectionTranslationSelectionReader.read()
            guard let self, !Task.isCancelled, self.generation == current else { return }
            self.draft.source = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.phase = .ready
                self.requiresSubmission = true
                self.failureAction = nil
                SelectionTranslationPanelController.shared.present(anchor: self.panelAnchor,
                                                                    focusSourceEditor: true)
                SelectionTranslationPanelController.shared.focusSourceEditor()
            } else {
                self.submittedDraft = self.draft
                self.requiresSubmission = false
                SelectionTranslationPanelController.shared.present(anchor: self.panelAnchor,
                                                                    focusSourceEditor: false)
                self.beginTranslation(self.draft, generation: current)
            }
        }
    }

    /// Opens a manual draft from the menu bar. Unlike the global shortcut this
    /// path never reads another app's selection: opening the menu has already
    /// made Vorssaint the frontmost app, so the user can type or paste safely.
    func openManualDraft() {
        guard AppFeature.selectionTranslation.isAvailable else { return }

        var startsNewDraft = false
        if phase == .idle || phase == .reading {
            cancelRequestOnly()
            generation &+= 1
            let settings = SelectionTranslationSettingsStore.snapshot()
            panelAnchor = NSEvent.mouseLocation
            draft = SelectionTranslationDraft(languages: settings.languages)
            submittedDraft = nil
            translatedText = ""
            usage = .zero
            timing = .idle
            requiresSubmission = true
            failureAction = nil
            providerName = settings.providerName
            phase = .ready
            startsNewDraft = true
        }

        SelectionTranslationPanelController.shared.present(anchor: panelAnchor,
                                                            focusSourceEditor: startsNewDraft)
        if startsNewDraft {
            SelectionTranslationPanelController.shared.focusSourceEditor()
        }
    }

    func updateSource(_ source: String) {
        invalidateActiveTranslationIfNeeded()
        draft.source = source
        requiresSubmission = submittedDraft != draft
        if phase != .reading { phase = .ready }
    }

    func updateLanguageSelection(_ languages: SelectionTranslationLanguageSelection) {
        invalidateActiveTranslationIfNeeded()
        draft.languages = languages
        requiresSubmission = submittedDraft != draft
        if phase != .reading { phase = .ready }
    }

    func swapLanguages() { updateLanguageSelection(draft.languages.swapped()) }

    func submitDraft() {
        let normalized = draft.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            phase = .ready
            requiresSubmission = true
            return
        }
        draft.source = normalized
        submittedDraft = draft
        requiresSubmission = false
        cancelRequestOnly()
        generation &+= 1
        beginTranslation(draft, generation: generation)
    }

    func retry() {
        let retryDraft = SelectionTranslationWorkflow.retryDraft(current: draft, committed: submittedDraft)
        draft = retryDraft
        guard SelectionTranslationWorkflow.shouldSubmit(draft: retryDraft) else {
            phase = .ready
            requiresSubmission = true
            return
        }
        submittedDraft = retryDraft
        requiresSubmission = false
        cancelRequestOnly()
        generation &+= 1
        beginTranslation(retryDraft, generation: generation)
    }

    func interrupt() {
        guard phase == .translating || phase == .streaming else { return }
        cancelRequestOnly()
        generation &+= 1
        phase = translatedText.isEmpty ? .ready : .interrupted
    }

    func dismiss() {
        cancelRequestOnly()
        generation &+= 1
        phase = .idle
        draft = SelectionTranslationDraft()
        submittedDraft = nil
        translatedText = ""
        usage = .zero
        timing = .idle
        requiresSubmission = false
        failureAction = nil
        SelectionTranslationPanelController.shared.hide()
    }

    func cancel() { dismiss() }

    func openFailureAction() {
        switch failureAction {
        case .openAccessibilitySettings: Permissions.shared.openAccessibilitySettings()
        case .openSettings: appDelegate()?.openSettingsWindow()
        case .retry: retry()
        case nil: break
        }
    }

    private func cancelRequestOnly() {
        timing = timing.stopped(at: Date())
        task?.cancel()
        task = nil
    }

    private func invalidateActiveTranslationIfNeeded() {
        guard phase == .translating || phase == .streaming else { return }
        cancelRequestOnly()
        generation &+= 1
        translatedText = ""
        usage = .zero
    }

    private func beginTranslation(_ draft: SelectionTranslationDraft, generation current: Int) {
        translatedText = ""
        usage = .zero
        timing = .running(at: Date())
        failureAction = nil
        phase = .translating
        let snapshot = SelectionTranslationSettingsStore.snapshot()
        providerName = snapshot.providerName
        task = Task { [weak self] in
            do {
                guard let url = URL(string: snapshot.baseURL) else {
                    throw SelectionTranslationProviderConfiguration.ValidationError.unsupportedURL
                }
                let provider = try SelectionTranslationProviderConfiguration(baseURL: url,
                                                                               model: snapshot.model,
                                                                               apiKey: snapshot.apiKey)
                let request = SelectionTranslationRequest(source: draft.source,
                                                           languages: draft.languages,
                                                           prompts: snapshot.prompts,
                                                           provider: provider)
                let result = try await SelectionTranslationClient.shared.translate(request) { [weak self] piece in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == current else { return }
                        self.phase = .streaming
                        self.translatedText += piece
                    }
                }
                guard let self, self.generation == current else { return }
                self.usage = result.usage
                self.timing = self.timing.stopped(at: Date())
                self.phase = .completed
                self.requiresSubmission = false
            } catch is CancellationError {
                // Interrupt owns the visible phase and keeps any partial text.
            } catch {
                guard let self, self.generation == current else { return }
                self.timing = self.timing.stopped(at: Date())
                self.phase = .failed(error.localizedDescription)
                self.failureAction = Self.failureAction(for: error)
            }
        }
    }

    private static func failureAction(for error: Error) -> SelectionTranslationFailureAction {
        if error is SelectionTranslationProviderConfiguration.ValidationError { return .openSettings }
        if let clientError = error as? SelectionTranslationClientError {
            switch clientError {
            case .httpStatus(let code, _):
                return code == 401 || code == 403 || code == 404 ? .openSettings : .retry
            default: return .retry
            }
        }
        return .retry
    }
}
