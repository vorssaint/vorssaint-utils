// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

enum SelectionTranslationPhase: Equatable {
    case idle
    case ready
    case reading
    case waitingForShortcutRelease
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
    private var accessibilityTask: Task<Void, Never>?
    private var holdTask: Task<Void, Never>?
    private var releaseTask: Task<Void, Never>?
    private var panelAnchor = NSEvent.mouseLocation
    private var targetProcessIdentifier: pid_t?
    private var shortcutIsHeld = false
    private var shortcutFlow = SelectionTranslationShortcutFlowState()
    @Published private(set) var holdLimitReached = false

    private init() {
        hotkey.onPress = { [weak self] in
            Task { @MainActor [weak self] in self?.trigger() }
        }
        hotkey.onRelease = { [weak self] shortcut in
            Task { @MainActor [weak self] in self?.shortcutReleased(shortcut) }
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
        guard phase != .reading, phase != .waitingForShortcutRelease,
              phase != .translating, phase != .streaming else { return }
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
        phase = .waitingForShortcutRelease
        holdLimitReached = false
        shortcutIsHeld = true
        targetProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier
        shortcutFlow = SelectionTranslationShortcutFlowState()
        SelectionTranslationPanelController.shared.setInteractionLocked(true)
        SelectionTranslationPanelController.shared.present(anchor: panelAnchor, focusSourceEditor: false)

        guard Permissions.shared.accessibility else {
            phase = .failed(FeatureStrings.selectionTranslation(L10n.shared.language).permissionRequired)
            failureAction = .openAccessibilitySettings
            SelectionTranslationPanelController.shared.setInteractionLocked(false)
            return
        }

        accessibilityTask = Task { [weak self] in
            let text = await SelectionTranslationSelectionReader.readAccessibility(processIdentifier: self?.targetProcessIdentifier)
            guard let self, !Task.isCancelled, self.generation == current else { return }
            await MainActor.run { self.accessibilityCompleted(text, generation: current) }
        }
        holdTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.holdDeadlineReached(generation: current) }
        }
    }

    private func accessibilityCompleted(_ text: String, generation current: Int) {
        guard generation == current else { return }
        let action = shortcutFlow.accessibilityCompleted(text)
        handleShortcutAction(action, generation: current)
    }

    private func holdDeadlineReached(generation current: Int) {
        guard generation == current, phase == .waitingForShortcutRelease else { return }
        holdLimitReached = true
        holdTask = nil
        let action = shortcutFlow.deadlineReachedNow()
        handleShortcutAction(action, generation: current)
    }

    private func shortcutReleased(_ shortcut: GlobalShortcut) {
        guard shortcutIsHeld else { return }
        releaseTask?.cancel()
        let current = generation
        releaseTask = Task { [weak self] in
            for attempt in 0...SelectionTranslationShortcutReleaseSupport.maximumAttempts {
                guard !Task.isCancelled else { return }
                let flags = CGEventSource.flagsState(.combinedSessionState)
                let heldModifiers = flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
                let keyHeld = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcut.carbonKeyCode))
                switch SelectionTranslationShortcutReleaseSupport.decision(
                    modifiersHeld: !heldModifiers.isEmpty,
                    keyHeld: keyHeld,
                    attempt: attempt
                ) {
                case .released:
                    await MainActor.run { [weak self] in
                        self?.finishShortcutRelease(generation: current, timedOut: false)
                    }
                    return
                case .timedOut:
                    await MainActor.run { [weak self] in
                        self?.finishShortcutRelease(generation: current, timedOut: true)
                    }
                    return
                case .wait:
                    try? await Task.sleep(nanoseconds: SelectionTranslationShortcutReleaseSupport.pollIntervalNanoseconds)
                    guard !Task.isCancelled else { return }
                }
            }
        }
    }

    private func finishShortcutRelease(generation current: Int, timedOut: Bool) {
        guard generation == current else { return }
        holdTask?.cancel()
        holdTask = nil
        releaseTask = nil
        shortcutIsHeld = false
        holdLimitReached = false
        SelectionTranslationPanelController.shared.setInteractionLocked(false)
        guard !timedOut else {
            if phase == .waitingForShortcutRelease {
                accessibilityTask?.cancel()
                accessibilityTask = nil
                generation &+= 1
                phase = .failed(FeatureStrings.selectionTranslation(L10n.shared.language).shortcutReleaseTimedOut)
                failureAction = .retry
            }
            return
        }
        handleShortcutAction(shortcutFlow.shortcutReleased(), generation: current)
    }

    private func handleShortcutAction(_ action: SelectionTranslationShortcutFlowAction, generation current: Int) {
        guard generation == current else { return }
        switch action {
        case .none:
            break
        case .translate(let text):
            draft.source = text
            submittedDraft = draft
            requiresSubmission = false
            SelectionTranslationPanelController.shared.setInteractionLocked(shortcutIsHeld)
            beginTranslation(draft, generation: current)
        case .readPasteboard:
            guard let target = targetProcessIdentifier,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target else {
                phase = .failed(FeatureStrings.selectionTranslation(L10n.shared.language).targetApplicationChanged)
                failureAction = .retry
                SelectionTranslationPanelController.shared.setInteractionLocked(false)
                return
            }
            SelectionTranslationPanelController.shared.setInteractionLocked(true)
            phase = .reading
            task = Task { [weak self] in
                let result = await SelectionTranslationSelectionReader.readPasteboardOnlyResult()
                guard let self, !Task.isCancelled, self.generation == current else { return }
                SelectionTranslationPanelController.shared.setInteractionLocked(false)
                guard let text = result else {
                    self.phase = .failed(FeatureStrings.selectionTranslation(L10n.shared.language).requestFailed)
                    self.failureAction = .retry
                    return
                }
                self.draft.source = text
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.phase = .ready
                    self.requiresSubmission = true
                    SelectionTranslationPanelController.shared.focusSourceEditor()
                } else {
                    self.submittedDraft = self.draft
                    self.requiresSubmission = false
                    self.beginTranslation(self.draft, generation: current)
                }
            }
        }
    }


    /// Opens a manual draft from the menu bar. Unlike the global shortcut this
    /// path never reads another app's selection: opening the menu has already
    /// made Vorssaint the frontmost app, so the user can type or paste safely.
    func openManualDraft() {
        guard AppFeature.selectionTranslation.isAvailable else { return }

        var startsNewDraft = false
        if phase == .idle || phase == .reading || phase == .waitingForShortcutRelease {
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
            holdLimitReached = false
            phase = .ready
            shortcutIsHeld = false
            SelectionTranslationPanelController.shared.setInteractionLocked(false)
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
        if phase != .reading && phase != .waitingForShortcutRelease { phase = .ready }
    }

    func updateLanguageSelection(_ languages: SelectionTranslationLanguageSelection) {
        invalidateActiveTranslationIfNeeded()
        draft.languages = languages
        requiresSubmission = submittedDraft != draft
        if phase != .reading && phase != .waitingForShortcutRelease { phase = .ready }
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
        shortcutIsHeld = false
        draft = SelectionTranslationDraft()
        submittedDraft = nil
        translatedText = ""
        usage = .zero
        timing = .idle
        requiresSubmission = false
        failureAction = nil
        holdLimitReached = false
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
        accessibilityTask?.cancel()
        accessibilityTask = nil
        holdTask?.cancel()
        holdTask = nil
        releaseTask?.cancel()
        releaseTask = nil
        shortcutIsHeld = false
        SelectionTranslationPanelController.shared.setInteractionLocked(false)
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
