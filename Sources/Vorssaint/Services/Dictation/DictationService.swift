// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

@MainActor
final class DictationService: ObservableObject {
    static let shared = DictationService()
    static let keychainService = "com.vorssaint.utils.dictation"

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var shortcutRegistrationFailed = false

    private let keychain: KeychainStoring
    private let client: DictationTranscriptionClient
    private let recorder: DictationAudioRecorder
    private let hud = DictationHUD()
    private let hotkey = QuickToolHotkey(id: 25)
    private let cancelHotkey = QuickToolHotkey(id: 26)
    private var transcriptionTask: Task<Void, Never>?
    private var localEscapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var sessionID: UUID?
    private var target: Target?
    private var sessionConfiguration: SessionConfiguration?
    private var dismissWork: DispatchWorkItem?

    private init(keychain: KeychainStoring = KeychainStore.shared,
                 client: DictationTranscriptionClient = DictationTranscriptionClient(),
                 recorder suppliedRecorder: DictationAudioRecorder? = nil) {
        let recorder = suppliedRecorder ?? DictationAudioRecorder()
        self.keychain = keychain
        self.client = client
        self.recorder = recorder
        hotkey.onPress = { [weak self] in self?.toggle() }
        cancelHotkey.onPress = { [weak self] in self?.cancel() }
        recorder.onLevel = { [weak self] level in
            self?.level = level
            self?.hud.updateLevel(level)
        }
        recorder.onFailure = { [weak self] in
            self?.fail(.microphoneUnavailable)
        }
        recorder.onFinished = { [weak self] in
            guard self?.state == .listening else { return }
            self?.stopAndTranscribe()
        }
    }

    var provider: DictationProvider {
        DictationProvider(rawValue: UserDefaults.standard.string(
            forKey: DefaultsKey.dictationProvider) ?? "") ?? .openAI
    }

    var model: DictationModel {
        let provider = provider
        let key = provider == .openAI
            ? DefaultsKey.dictationOpenAIModel : DefaultsKey.dictationGroqModel
        return provider.sanitizedModel(UserDefaults.standard.string(forKey: key))
    }

    func storedKey(for provider: DictationProvider) throws -> String? {
        try keychain.value(service: Self.keychainService, account: provider.rawValue)
    }

    func saveKey(_ value: String, for provider: DictationProvider) throws {
        try keychain.setValue(value, service: Self.keychainService, account: provider.rawValue)
    }

    func removeKey(for provider: DictationProvider) throws {
        try keychain.deleteValue(service: Self.keychainService, account: provider.rawValue)
    }

    func testConfiguration(provider: DictationProvider, apiKey: String) async throws {
        try await client.testConfiguration(provider: provider, apiKey: apiKey)
    }

    func syncWithPreferences() {
        let enabled = AppFeature.dictation.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.dictationEnabled)
        if !enabled {
            shortcutRegistrationFailed = false
            hotkey.unregister()
            cancel(event: .disable)
            return
        }
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.dictationShortcut,
                                            fallback: .dictationDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: true, shortcut: shortcut)
    }

    func suspend() {
        hotkey.unregister()
        cancel(event: .disable)
    }

    func toggle() {
        switch state {
        case .idle, .failure:
            begin()
        case .listening:
            stopAndTranscribe()
        case .processing:
            cancel()
        }
    }

    func cancel() {
        cancel(event: .cancel)
    }

    private func begin() {
        guard AppFeature.dictation.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.dictationEnabled) else { return }
        dismissWork?.cancel()
        dismissWork = nil
        let provider = provider
        let model = model(for: provider)
        let apiKey: String
        do {
            guard let key = try storedKey(for: provider),
                  !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                fail(.missingKey)
                return
            }
            apiKey = key
        } catch {
            fail(.keychain)
            return
        }
        let id = UUID()
        sessionID = id
        target = Target.capture()
        sessionConfiguration = SessionConfiguration(provider: provider,
                                                    model: model,
                                                    apiKey: apiKey)
        switch Permissions.shared.microphone {
        case .granted:
            startRecording(sessionID: id)
        case .denied:
            fail(.microphoneDenied)
        case .undetermined, .unknown:
            Permissions.shared.requestMicrophone { [weak self] granted in
                guard let self, self.sessionID == id else { return }
                if granted {
                    self.startRecording(sessionID: id)
                } else {
                    self.fail(.microphoneDenied)
                }
            }
        }
    }

    private func startRecording(sessionID id: UUID) {
        guard sessionID == id,
              AppFeature.dictation.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.dictationEnabled) else {
            cancel(event: .disable)
            return
        }
        do {
            try recorder.start()
        } catch let failure as DictationFailure {
            fail(failure)
            return
        } catch {
            fail(.microphoneUnavailable)
            return
        }
        let transition = DictationLifecycle.transition(from: state, event: .begin)
        state = transition.state
        installEscapeHandlers()
        showHUD()
    }

    private func stopAndTranscribe() {
        guard state == .listening,
              let id = sessionID,
              let configuration = sessionConfiguration else { return }
        let file: URL
        do {
            file = try recorder.stop()
        } catch let failure as DictationFailure {
            fail(failure)
            return
        } catch {
            fail(.noSpeech)
            return
        }
        let transition = DictationLifecycle.transition(from: state, event: .stop)
        state = transition.state
        level = 0
        showHUD()
        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.recorder.discardFile() }
            do {
                let text = try await self.client.transcribe(file: file,
                                                            provider: configuration.provider,
                                                            model: configuration.model,
                                                            apiKey: configuration.apiKey)
                guard !Task.isCancelled, self.sessionID == id else { return }
                let hasSpeech = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let completed = DictationLifecycle.transition(
                    from: self.state,
                    event: .transcriptionCompleted(hasText: hasSpeech))
                self.state = completed.state
                guard hasSpeech else {
                    self.fail(.noSpeech)
                    return
                }
                self.insert(text, sessionID: id)
            } catch let failure as DictationFailure {
                guard failure != .cancelled, !Task.isCancelled, self.sessionID == id else { return }
                self.fail(failure)
            } catch {
                guard !Task.isCancelled, self.sessionID == id else { return }
                self.fail(.network)
            }
        }
    }

    private func insert(_ text: String, sessionID id: UUID) {
        guard sessionID == id else { return }
        guard let target else {
            copyToClipboard(text)
            fail(.focusChangedCopied)
            return
        }
        switch DictationInsertionDecision.decide(
            accessibilityGranted: AXIsProcessTrusted(),
            originalTargetIsFocused: target.isFocused) {
        case .copy(let failure):
            copyToClipboard(text)
            fail(failure)
        case .paste:
            var focusChanged = false
            let accepted = TransientPaste.shared.paste(
                text,
                shouldPostShortcut: {
                    let focused = target.isFocused
                    focusChanged = !focused
                    return focused
                },
                didPostShortcut: { [weak self] in
                    guard let self, self.sessionID == id else { return }
                    self.finishSuccessfully()
                },
                didFail: { [weak self] in
                    guard let self, self.sessionID == id else { return }
                    let failure: DictationFailure = focusChanged
                        ? .focusChangedCopied : .pasteFailedCopied
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                        guard let self, self.sessionID == id else { return }
                        self.copyToClipboard(text)
                        self.fail(failure)
                    }
                })
            if !accepted {
                copyToClipboard(text)
                fail(.pasteFailedCopied)
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(text, forType: .string) {
            ClipboardHistoryService.shared.ignoreNextChange(upTo: pasteboard.changeCount)
        }
    }

    private func finishSuccessfully() {
        transcriptionTask = nil
        sessionID = nil
        target = nil
        sessionConfiguration = nil
        recorder.discardFile()
        removeEscapeHandlers()
        state = .idle
        hud.hide()
    }

    private func fail(_ failure: DictationFailure) {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        recorder.cancel()
        removeEscapeHandlers()
        sessionID = nil
        target = nil
        sessionConfiguration = nil
        state = .failure(failure)
        level = 0
        showHUD(failure: failure)
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .failure(failure) else { return }
            self.state = .idle
            self.hud.hide()
            self.dismissWork = nil
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func cancel(event: DictationLifecycleEvent) {
        dismissWork?.cancel()
        dismissWork = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        recorder.cancel()
        removeEscapeHandlers()
        sessionID = nil
        target = nil
        sessionConfiguration = nil
        level = 0
        state = DictationLifecycle.transition(from: state, event: event).state
        hud.hide()
    }

    private func installEscapeHandlers() {
        let escape = GlobalShortcut(keyCode: Int64(kVK_Escape), modifiers: [])
        _ = cancelHotkey.sync(enabled: true, shortcut: escape)
        if localEscapeMonitor == nil {
            localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard event.keyCode == UInt16(kVK_Escape) else { return event }
                self?.cancel()
                return nil
            }
        }
        if globalEscapeMonitor == nil {
            globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard event.keyCode == UInt16(kVK_Escape) else { return }
                self?.cancel()
            }
        }
    }

    private func removeEscapeHandlers() {
        cancelHotkey.unregister()
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
        if let globalEscapeMonitor { NSEvent.removeMonitor(globalEscapeMonitor) }
        localEscapeMonitor = nil
        globalEscapeMonitor = nil
    }

    private func showHUD(failure: DictationFailure? = nil) {
        let strings = FeatureStrings.dictation(L10n.shared.language)
        let opensSettings = failure == .microphoneDenied
            || failure == .accessibilityRequiredCopied
        hud.show(state: state,
                 level: level,
                 strings: strings,
                 opensSettings: opensSettings) {
            if failure == .microphoneDenied {
                Permissions.shared.openMicrophoneSettings()
            } else {
                Permissions.shared.openAccessibilitySettings()
            }
        }
    }

    private func model(for provider: DictationProvider) -> DictationModel {
        let key = provider == .openAI
            ? DefaultsKey.dictationOpenAIModel : DefaultsKey.dictationGroqModel
        return provider.sanitizedModel(UserDefaults.standard.string(forKey: key))
    }

    private struct SessionConfiguration {
        let provider: DictationProvider
        let model: DictationModel
        let apiKey: String
    }

    private struct Target {
        let pid: pid_t
        let element: AXUIElement?
        let focusIdentity: DictationFocusIdentity?

        static func capture() -> Target? {
            guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
            let pid = front.processIdentifier
            guard AXIsProcessTrusted() else {
                return Target(pid: pid, element: nil, focusIdentity: nil)
            }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            let element = focusedElement(in: app)
            return Target(pid: pid,
                          element: element,
                          focusIdentity: element.flatMap(identity(for:)))
        }

        var isFocused: Bool {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let element else { return false }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            guard let current = Self.focusedElement(in: app) else { return false }
            if CFEqual(element, current) { return true }
            guard let focusIdentity,
                  let currentIdentity = Self.identity(for: current) else { return false }
            return focusIdentity.matches(currentIdentity)
        }

        private static func focusedElement(in app: AXUIElement) -> AXUIElement? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString,
                                                &value) == .success,
                  let value,
                  CFGetTypeID(value) == AXUIElementGetTypeID()
            else { return nil }
            return (value as! AXUIElement)
        }

        private static func identity(for element: AXUIElement) -> DictationFocusIdentity? {
            guard let role = stringAttribute(kAXRoleAttribute as CFString, from: element) else {
                return nil
            }
            return DictationFocusIdentity(
                role: role,
                subrole: stringAttribute(kAXSubroleAttribute as CFString, from: element),
                identifier: stringAttribute(kAXIdentifierAttribute as CFString, from: element),
                domIdentifier: stringAttribute("AXDOMIdentifier" as CFString, from: element),
                placeholder: stringAttribute("AXPlaceholderValue" as CFString, from: element),
                description: stringAttribute(kAXDescriptionAttribute as CFString, from: element),
                frame: frame(of: element))
        }

        private static func stringAttribute(_ attribute: CFString,
                                            from element: AXUIElement) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
                  let string = value as? String else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private static func frame(of element: AXUIElement) -> CGRect? {
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString,
                                                &positionValue) == .success,
                  AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString,
                                                &sizeValue) == .success,
                  let positionValue,
                  let sizeValue,
                  CFGetTypeID(positionValue) == AXValueGetTypeID(),
                  CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
            var position = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
                  AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
            return CGRect(x: position.x.rounded(), y: position.y.rounded(),
                          width: size.width.rounded(), height: size.height.rounded())
        }
    }
}
