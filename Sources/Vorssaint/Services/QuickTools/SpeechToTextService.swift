// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import ApplicationServices
import Combine
import Speech

final class SpeechToTextService: ObservableObject {
    static let shared = SpeechToTextService()

    // Keep short hesitations inside the same phrase while leaving a safety
    // margin below the legacy recognizer's per-task duration limit.
    private let pauseRotationDelay: TimeInterval = 1.8
    private let safetyRotationDelay: TimeInterval = 50

    enum State: Equatable {
        case idle, requestingPermission, listening, finishing, unavailable, failed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 19)
    private let audioEngine = AVAudioEngine()
    private let audioRequestLock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var rotationTimer: Timer?
    private var pauseWork: DispatchWorkItem?
    private var pendingAudioBuffers: [AVAudioPCMBuffer] = []
    private var segmentID = 0
    private var rotatingSegment = false
    private var latestHypothesis = ""
    private var pasteQueue: [String] = []
    private var pasteInProgress = false
    private var generation = UUID()
    private var pushToTalkHeld = false
    private var captureNeedsHold = false

    private init() {
        hotkey.onPress = { [weak self] in self?.beginPushToTalk() }
        hotkey.onRelease = { [weak self] in self?.endPushToTalk() }
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

    private func beginPushToTalk() {
        guard state == .idle || state == .failed || state == .unavailable else { return }
        pushToTalkHeld = true
        start()
    }

    private func endPushToTalk() {
        pushToTalkHeld = false
        if state == .listening { finish() }
    }

    func start() {
        guard AppFeature.speechToText.isAvailable else { return }
        captureNeedsHold = pushToTalkHeld
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
                guard !self.captureNeedsHold || self.pushToTalkHeld else {
                    self.state = .idle
                    return
                }
                self.beginRecognition(session: session)
            }
        }
    }

    func finish() {
        guard state == .listening else { return }
        state = .finishing
        rotationTimer?.invalidate()
        rotationTimer = nil
        pauseWork?.cancel()
        pauseWork = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioRequestLock.lock()
        let activeRequest = request
        request = nil
        audioRequestLock.unlock()
        activeRequest?.endAudio()
    }

    private func beginRecognition(session: UUID) {
        let locale = Locale.current
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            state = .unavailable
            return
        }

        self.recognizer = recognizer
        latestHypothesis = ""
        pendingAudioBuffers.removeAll()
        rotatingSegment = false
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail()
            return
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.appendAudio(buffer)
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
        QuickToolHUD.showListening(message: SpeechToTextStrings.localized(L10n.shared.language).listening)
        startRecognitionSegment(session: session)
    }

    private func startRecognitionSegment(session: UUID, finishAfterStart: Bool = false) {
        guard let recognizer,
              state == .listening || state == .finishing else { return }
        segmentID += 1
        let id = segmentID
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        latestHypothesis = ""
        rotatingSegment = false

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.generation == session else { return }
                self.handleRecognition(result: result, error: error,
                                       segment: id, session: session)
            }
        }
        self.task = task

        // If the previous task was being finalized, retain the audio captured
        // during that short handoff and feed it into the next task in order.
        audioRequestLock.lock()
        let bufferedAudio = pendingAudioBuffers
        pendingAudioBuffers.removeAll(keepingCapacity: true)
        for buffer in bufferedAudio { request.append(buffer) }
        self.request = request
        audioRequestLock.unlock()

        if finishAfterStart {
            audioRequestLock.lock()
            self.request = nil
            audioRequestLock.unlock()
            request.endAudio()
        } else if state == .listening {
            scheduleSafetyRotation(segment: id, session: session)
        }
    }

    private func appendAudio(_ buffer: AVAudioPCMBuffer) {
        audioRequestLock.lock()
        if let request {
            request.append(buffer)
        } else {
            pendingAudioBuffers.append(buffer)
        }
        audioRequestLock.unlock()
    }

    private func scheduleSafetyRotation(segment: Int, session: UUID) {
        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: safetyRotationDelay, repeats: false) { [weak self] _ in
            guard let self, self.segmentID == segment, self.generation == session else { return }
            self.rotateRecognitionSegment()
        }
    }

    private func schedulePauseRotation(segment: Int, session: UUID) {
        pauseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.segmentID == segment, self.generation == session else { return }
            self.rotateRecognitionSegment()
        }
        pauseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + pauseRotationDelay, execute: work)
    }

    private func rotateRecognitionSegment() {
        guard state == .listening else { return }
        audioRequestLock.lock()
        guard let activeRequest = request else {
            audioRequestLock.unlock()
            return
        }
        request = nil
        audioRequestLock.unlock()
        rotatingSegment = true
        rotationTimer?.invalidate()
        rotationTimer = nil
        pauseWork?.cancel()
        pauseWork = nil
        activeRequest.endAudio()
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?,
                                   error: Error?,
                                   segment: Int,
                                   session: UUID) {
        guard segment == segmentID else { return }
        if let result {
            let hypothesis = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !result.isFinal {
                if !hypothesis.isEmpty, hypothesis != latestHypothesis {
                    latestHypothesis = hypothesis
                    schedulePauseRotation(segment: segment, session: session)
                }
                return
            }
            if !hypothesis.isEmpty { latestHypothesis = hypothesis }
        } else if error == nil {
            return
        }

        // Ending one task is a normal boundary. Keep recording and replay any
        // audio buffered while Speech finalized the previous segment.
        guard state == .listening || state == .finishing else { return }
        if error != nil, state == .listening, !rotatingSegment {
            stopCapture()
            fail()
            return
        }

        rotationTimer?.invalidate()
        rotationTimer = nil
        pauseWork?.cancel()
        pauseWork = nil
        if !latestHypothesis.isEmpty { enqueueFinalChunk(latestHypothesis) }
        task = nil
        audioRequestLock.lock()
        request = nil
        audioRequestLock.unlock()
        let hasBufferedAudio: Bool
        audioRequestLock.lock()
        hasBufferedAudio = !pendingAudioBuffers.isEmpty
        audioRequestLock.unlock()

        if state == .listening {
            startRecognitionSegment(session: session)
        } else if hasBufferedAudio {
            startRecognitionSegment(session: session, finishAfterStart: true)
        } else {
            completeDictation()
        }
    }

    private func completeDictation() {
        stopCapture()
        QuickToolHUD.hideListening()
        state = .idle
    }

    private func enqueueFinalChunk(_ transcript: String) {
        guard !transcript.isEmpty else {
            return
        }
        guard AXIsProcessTrusted() else {
            Permissions.shared.requestAccessibility()
            fail()
            return
        }
        pasteQueue.append(transcript + " ")
        drainPasteQueue()
    }

    private func drainPasteQueue() {
        guard !pasteInProgress, !pasteQueue.isEmpty else { return }
        pasteInProgress = true
        let text = pasteQueue.removeFirst()
        let pasteSession = generation
        let accepted = TransientPaste.shared.paste(
            text,
            didPostShortcut: { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pasteInProgress = false
                    self.drainPasteQueue()
                }
            },
            didFail: { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.pasteInProgress = false
                    if self.generation == pasteSession {
                        self.fail()
                    } else {
                        self.drainPasteQueue()
                    }
                }
            })
        if !accepted {
            pasteInProgress = false
            fail()
        }
    }

    private func stopCapture() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        pauseWork?.cancel()
        pauseWork = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioRequestLock.lock()
        request = nil
        pendingAudioBuffers.removeAll()
        audioRequestLock.unlock()
        task = nil
        recognizer = nil
    }

    private func fail() {
        let activeTask = task
        audioRequestLock.lock()
        let activeRequest = request
        request = nil
        audioRequestLock.unlock()
        stopCapture()
        activeRequest?.endAudio()
        activeTask?.cancel()
        pasteQueue.removeAll()
        pasteInProgress = false
        QuickToolHUD.hideListening()
        state = .failed
    }

    private func cancel() {
        generation = UUID()
        pushToTalkHeld = false
        captureNeedsHold = false
        let activeTask = task
        audioRequestLock.lock()
        let activeRequest = request
        request = nil
        pendingAudioBuffers.removeAll()
        audioRequestLock.unlock()
        stopCapture()
        activeRequest?.endAudio()
        activeTask?.cancel()
        QuickToolHUD.hideListening()
        state = .idle
    }
}
