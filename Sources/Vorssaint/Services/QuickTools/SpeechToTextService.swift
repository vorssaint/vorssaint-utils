// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import ApplicationServices
import Combine
import Speech

/// Short, explicitly started dictation. Recognition is pinned to the device;
/// no audio file or model is written or bundled.
final class SpeechToTextService: ObservableObject {
    static let shared = SpeechToTextService()

    enum State: Equatable {
        case idle, requestingPermission, listening, finishing, unavailable, failed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 19)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    var statusMessage: String? {
        switch state {
        case .idle: return nil
        case .requestingPermission:
            return SpeechToTextStrings.status(L10n.shared.language, .requesting)
        case .listening: return SpeechToTextStrings.localized(L10n.shared.language).listening
        case .finishing:
            return SpeechToTextStrings.status(L10n.shared.language, .finishing)
        case .unavailable: return SpeechToTextStrings.localized(L10n.shared.language).unavailable
        case .failed:
            return SpeechToTextStrings.status(L10n.shared.language, .failed)
        }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.speechToText.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.speechToTextShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.speechToTextShortcut,
                                            fallback: .speechToTextDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.speechToTextShortcut)
        if !AppFeature.speechToText.isAvailable { cancel() }
    }

    func suspend() {
        hotkey.unregister()
        cancel()
    }

    func toggle() {
        if state == .listening {
            finish()
        } else if state == .requestingPermission || state == .finishing {
            return
        } else {
            start()
        }
    }

    func start() {
        guard AppFeature.speechToText.isAvailable else { return }
        generation = UUID()
        let session = generation
        state = .requestingPermission
        Permissions.shared.requestMicrophone { [weak self] granted in
            guard let self, self.generation == session else { return }
            guard granted else {
                self.fail()
                return
            }
            Permissions.shared.requestSpeechRecognition { [weak self] authorized in
                guard let self, self.generation == session else { return }
                guard authorized else {
                    self.fail()
                    return
                }
                self.beginRecognition(session: session)
            }
        }
    }

    func finish() {
        guard state == .listening else { return }
        state = .finishing
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }

    private func beginRecognition(session: UUID) {
        let locale = Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            state = .unavailable
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        self.request = request
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail()
            return
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.request = nil
            fail()
            return
        }

        state = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.generation == session else { return }
                if error != nil {
                    self.stopCapture()
                    self.fail()
                    return
                }
                guard let result, result.isFinal else { return }
                self.stopCapture()
                let transcript = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.insert(transcript)
            }
        }
    }

    private func insert(_ transcript: String) {
        guard !transcript.isEmpty else {
            state = .idle
            return
        }
        guard AXIsProcessTrusted() else {
            Permissions.shared.requestAccessibility()
            state = .failed
            return
        }
        guard TransientPaste.shared.paste(transcript, didFail: { [weak self] in
            self?.state = .failed
        }) else {
            state = .failed
            return
        }
        state = .idle
    }

    private func stopCapture() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
    }

    private func fail() {
        stopCapture()
        state = .failed
    }

    private func cancel() {
        generation = UUID()
        let activeTask = task
        let activeRequest = request
        stopCapture()
        activeRequest?.endAudio()
        activeTask?.cancel()
        state = .idle
    }
}
