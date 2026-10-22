// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import AppKit
import AVFoundation
import Combine
import Foundation
import Speech

// MARK: - Dictation Manager

@MainActor
final class DictationManager: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var isStarting: Bool = false
    @Published var audioLevels: [CGFloat] = []
    @Published var error: String?

    /// Called on main thread with the latest recognized text for the current segment
    var onTextUpdate: (@MainActor (String) -> Void)?
    /// Called on main thread when a new recognition segment begins (after silence or restart)
    var onNewSegment: (@MainActor () -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var configurationChangeObserver: Any?
    private var suppressConfigChange: Bool = false
    private var hasInstalledTap = false
    private let requestLock = NSLock()

    private var sessionGeneration: Int = 0
    private var recognitionTaskGeneration: Int = 0

    // MARK: - Lifecycle

    func start() {
        guard !isRecording else { return }
        sessionGeneration += 1
        let generation = sessionGeneration
        cleanup()
        error = nil
        isStarting = true

        // Check microphone authorization
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            error = "Microphone access denied. Enable Microphone access in System Settings → Privacy & Security."
            isStarting = false
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.sessionGeneration == generation else { return }
                        if granted {
                            self.requestSpeechAuthAndBegin(for: generation)
                        } else {
                            self.error = "Microphone access denied."
                            self.isStarting = false
                        }
                    }
                }
            }
            return
        case .authorized:
            break
        @unknown default:
            break
        }

        requestSpeechAuthAndBegin(for: generation)
    }

    func stop() {
        sessionGeneration += 1
        isRecording = false
        isStarting = false
        cleanup()
    }

    /// Commit the current transcript segment and begin a fresh recognition
    /// request without stopping the audio engine. Used when an editor action
    /// (such as inserting a cue) changes the insertion point mid-dictation.
    func restartCurrentSegment() {
        guard isRecording else { return }
        onNewSegment?()
        restartRecognitionTask()
    }

    private func cleanup() {
        requestLock.lock()
        let req = recognitionRequest
        recognitionRequest = nil
        requestLock.unlock()

        req?.endAudio()

        if let observer = configurationChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationChangeObserver = nil
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionTaskGeneration += 1

        audioLevels.removeAll(keepingCapacity: true)
    }

    // MARK: - Speech Authorization & Setup

    private func requestSpeechAuthAndBegin(for generation: Int) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard self.sessionGeneration == generation else { return }
                    switch status {
                    case .authorized:
                        self.beginSession(for: generation)
                    case .denied, .restricted:
                        self.error = "Speech recognition access denied. Enable Speech Recognition in System Settings."
                        self.isRecording = false
                        self.isStarting = false
                    case .notDetermined:
                        self.isRecording = false
                        self.isStarting = false
                    @unknown default:
                        self.isRecording = false
                        self.isStarting = false
                    }
                }
            }
        }
    }

    private func beginSession(for currentGen: Int) {
        guard sessionGeneration == currentGen else { return }
        let localeId = UserDefaults.standard.string(forKey: DefaultsKey.teleprompterSpeechLanguage) ?? "en-US"
        let locale = Locale(identifier: localeId)

        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            error = "Speech recognizer unavailable for \(localeId)."
            isStarting = false
            return
        }

        guard recognizer.isAvailable else {
            error = "Speech recognition is temporarily unavailable."
            isStarting = false
            return
        }

        speechRecognizer = recognizer

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0 else {
            error = "Invalid audio hardware format."
            isStarting = false
            return
        }

        let captureFormat = speechCaptureFormat(for: hardwareFormat) ?? hardwareFormat
        let bufferSize = speechCaptureBufferSize(for: captureFormat)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        requestLock.lock()
        recognitionRequest = request
        requestLock.unlock()

        inputNode.removeTap(onBus: 0)
        hasInstalledTap = true
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: captureFormat) { [weak self, requestLock] buffer, _ in
            guard let self else { return }
            requestLock.lock()
            let req = self.recognitionRequest
            requestLock.unlock()
            req?.append(buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(max(frameLength, 1)))
            // Lift ordinary speaking levels above the visual noise floor while
            // retaining a smooth 0...1 range for the editor's live meter.
            let level = CGFloat(min(max((Double(rms) - 0.003) * 36.0, 0), 1))

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.isRecording, self.sessionGeneration == currentGen else { return }
                    self.recordAudioLevel(level)
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = "Failed to start audio engine: \(error.localizedDescription)"
            isStarting = false
            cleanup()
            return
        }

        recognitionTaskGeneration += 1
        let taskGeneration = recognitionTaskGeneration
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, taskError in
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.sessionGeneration == currentGen,
                          self.recognitionTaskGeneration == taskGeneration else { return }

                    if let result {
                        let spoken = result.bestTranscription.formattedString
                        self.onTextUpdate?(spoken)
                    }

                    if taskError != nil || result?.isFinal == true {
                        guard self.isRecording else { return }
                        self.onNewSegment?()
                        self.restartRecognitionTask()
                    }
                }
            }
        }

        isRecording = true
        isStarting = false
        watchAudioConfiguration()
    }

    private func restartRecognitionTask() {
        guard isRecording, let recognizer = speechRecognizer else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionTaskGeneration += 1

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        requestLock.lock()
        recognitionRequest = request
        requestLock.unlock()

        let currentGen = sessionGeneration
        recognitionTaskGeneration += 1
        let taskGeneration = recognitionTaskGeneration
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, taskError in
            guard let self else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.sessionGeneration == currentGen,
                          self.recognitionTaskGeneration == taskGeneration else { return }

                    if let result {
                        let spoken = result.bestTranscription.formattedString
                        self.onTextUpdate?(spoken)
                    }

                    if taskError != nil || result?.isFinal == true {
                        guard self.isRecording else { return }
                        self.onNewSegment?()
                        self.restartRecognitionTask()
                    }
                }
            }
        }
    }

    private func recordAudioLevel(_ level: CGFloat) {
        audioLevels.append(level)
        if audioLevels.count > 30 {
            audioLevels.removeFirst()
        }
    }

    private func watchAudioConfiguration() {
        if configurationChangeObserver != nil { return }
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard self.isRecording, !self.suppressConfigChange else { return }
                self.suppressConfigChange = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated {
                        self.suppressConfigChange = false
                        if self.isRecording {
                            let generation = self.sessionGeneration
                            self.cleanup()
                            guard self.sessionGeneration == generation else { return }
                            self.isRecording = false
                            self.beginSession(for: generation)
                        }
                    }
                }
            }
        }
    }
}
