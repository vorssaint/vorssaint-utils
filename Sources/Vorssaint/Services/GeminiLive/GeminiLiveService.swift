// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import Combine
import CoreImage
import ScreenCaptureKit

/// Voice sessions start on demand; screen capture is a separate, explicit opt-in.
@MainActor
final class GeminiLiveService: NSObject, ObservableObject {
    static let shared = GeminiLiveService()
    enum State { case idle, connecting, live }
    @Published private(set) var state = State.idle
    @Published private(set) var isMuted = true
    @Published private(set) var inputText = ""
    @Published private(set) var outputText = ""
    @Published private(set) var error: String?

    private var socket: URLSessionWebSocketTask?
    private var network: URLSession?
    private var connectionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()
    private var screenGeneration = UUID()
    private var screenTask: Task<Void, Never>?
    @Published private(set) var isSharingScreen = false
    @Published private(set) var isSelectingScreen = false
    private var stream: SCStream?
    private var screenOutput: GeminiLiveScreenOutput?
    private var audioEngine: AVAudioEngine?
    private var microphoneTapInstalled = false
    private var microphoneGeneration = UUID()
    private var player: AVAudioPlayerNode?
    private var playbackGeneration = UUID()
    private var playbackFrames = 0
    private var audioPending = false
    private var videoPending = false
    private var latestFrame: Data?
    @Published private(set) var microphoneRequestPending = false
    private var pickerObserver: GeminiLivePickerObserver?

    private var strings: GeminiLiveStrings { FeatureStrings.geminiLive(L10n.shared.language) }

    func start(apiKey: String, microphone: Bool = true) {
        guard AppFeature.geminiLive.isAvailable, state == .idle else { return }
        guard let url = GeminiLiveSupport.endpoint(apiKey: apiKey) else {
            error = strings.keyRequired
            return
        }
        error = nil
        inputText = ""
        outputText = ""
        generation = UUID()
        connect(url: url, microphone: microphone)
    }

    func shareScreen() {
        guard AppFeature.geminiLive.isAvailable, state == .live,
              !isSharingScreen, !isSelectingScreen else { return }
        error = nil
        isSelectingScreen = true
        screenGeneration = UUID()
        let picker = SCContentSharingPicker.shared
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleWindow, .singleDisplay]
        config.allowsChangingSelectedContent = false
        picker.defaultConfiguration = config
        let observer = GeminiLivePickerObserver(service: self, id: screenGeneration)
        pickerObserver = observer
        picker.add(observer)
        picker.isActive = true
        picker.present()
    }

    private func dismissPicker() {
        if let pickerObserver {
            SCContentSharingPicker.shared.remove(pickerObserver)
            SCContentSharingPicker.shared.isActive = false
            self.pickerObserver = nil
        }
    }

    func stopSharingScreen() {
        screenGeneration = UUID()
        screenTask?.cancel()
        screenTask = nil
        dismissPicker()
        isSelectingScreen = false
        isSharingScreen = false
        if let stream {
            self.stream = nil
            Task { try? await stream.stopCapture() }
        }
        screenOutput = nil
        videoPending = false
        latestFrame = nil
    }

    func stop() {
        generation = UUID()
        state = .idle
        isMuted = true
        microphoneRequestPending = false
        inputText = ""
        outputText = ""
        timeoutTask?.cancel()
        timeoutTask = nil
        connectionTask?.cancel()
        connectionTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        network?.invalidateAndCancel()
        network = nil
        stopMicrophone()
        clearPlayback()
        audioEngine?.stop()
        audioEngine = nil
        player = nil
        audioPending = false
        stopSharingScreen()
    }

    func toggleMicrophone() {
        guard AppFeature.geminiLive.isAvailable, state == .live, !microphoneRequestPending else { return }
        if !isMuted {
            isMuted = true
            stopMicrophone()
            send(["realtimeInput": ["audioStreamEnd": true]])
            return
        }
        let id = generation
        microphoneRequestPending = true
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard id == generation, state == .live, AppFeature.geminiLive.isAvailable else { return }
            microphoneRequestPending = false
            guard allowed else { error = strings.microphoneDenied; return }
            do {
                try startMicrophone()
                isMuted = false
            } catch {
                fail(strings.audioFailed)
            }
        }
    }

    private func connect(url: URL, microphone: Bool) {
        state = .connecting
        let id = generation
        let session = URLSession(configuration: .ephemeral)
        network = session
        let socket = session.webSocketTask(with: url)
        self.socket = socket
        socket.resume()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.generation == id, self.state == .connecting else { return }
            self.fail(self.strings.connectionFailed)
        }
        connectionTask = Task { [weak self] in
            do {
                let setup = try JSONSerialization.data(withJSONObject: GeminiLiveSupport.setup)
                try await socket.send(.data(setup))
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.generation == id, AppFeature.geminiLive.isAvailable else { return }
                    let data: Data
                    switch message {
                    case .data(let bytes): data = bytes
                    case .string(let text): data = Data(text.utf8)
                    @unknown default: continue
                    }
                    let event = try GeminiLiveSupport.decode(data)
                    if event.failed { self.fail(self.strings.connectionFailed); return }
                    if event.ended { self.fail(self.strings.sessionEnded); return }
                    if event.ready, self.state == .connecting {
                        self.timeoutTask?.cancel()
                        self.state = .live
                        if microphone { self.toggleMicrophone() }
                    }
                    if event.interrupted { self.clearPlayback() }
                    if let text = event.inputText { self.inputText = String((self.inputText + text).suffix(4000)) }
                    if let text = event.outputText { self.outputText = String((self.outputText + text).suffix(8000)) }
                    do {
                        for audio in event.audio { try self.play(audio) }
                    } catch { self.fail(self.strings.audioFailed); return }
                }
            } catch {
                guard let self, self.generation == id else { return }
                // Never display raw networking errors: they can contain the credential URL.
                self.fail(self.strings.connectionFailed)
            }
        }
    }

    private func fail(_ message: String) {
        stop()
        error = message
    }

    private func receiveFrame(_ data: Data) {
        // Keep one successor while startup or a slow send is in progress. Idle
        // screens need not produce another complete frame to make this deliver.
        latestFrame = data
        flushVideo()
    }

    private func flushVideo() {
        guard AppFeature.geminiLive.isAvailable, state == .live, isSharingScreen, let socket,
              !videoPending, let frame = latestFrame else { return }
        latestFrame = nil
        videoPending = true
        let id = generation
        let screenID = screenGeneration
        Task { [weak self] in
            do {
                let data = try JSONSerialization.data(withJSONObject: GeminiLiveSupport.realtime(frame, video: true))
                try await socket.send(.data(data))
                guard let self, self.generation == id, self.screenGeneration == screenID else { return }
                self.videoPending = false
                self.flushVideo()
            } catch {
                guard let self, self.generation == id, self.screenGeneration == screenID else { return }
                self.fail(self.strings.connectionFailed)
            }
        }
    }

    private func send(_ message: [String: Any], audio: Bool = false) {
        guard AppFeature.geminiLive.isAvailable, state == .live, let socket else { return }
        if audio { guard !audioPending else { return }; audioPending = true }
        let id = generation
        Task { [weak self] in
            do {
                let data = try JSONSerialization.data(withJSONObject: message)
                try await socket.send(.data(data))
                guard let self, self.generation == id else { return }
                if audio { self.audioPending = false }
            } catch {
                guard let self, self.generation == id else { return }
                self.fail(self.strings.connectionFailed)
            }
        }
    }

    private func startCapture(filter: SCContentFilter, id: UUID, screenID: UUID) async throws {
        let config = SCStreamConfiguration()
        let rect = filter.contentRect
        let scale = min(1, 1280 / max(rect.width, rect.height, 1))
        config.width = max(2, Int(rect.width * scale))
        config.height = max(2, Int(rect.height * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 2
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.capturesAudio = false
        let output = GeminiLiveScreenOutput { [weak self] data in
            Task { @MainActor in
                guard let self, self.generation == id, self.screenGeneration == screenID else { return }
                self.receiveFrame(data)
            }
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        self.stream = stream
        screenOutput = output
        try await stream.startCapture()
        if generation != id || screenGeneration != screenID { try? await stream.stopCapture() }
    }

    private func startMicrophone() throws {
        let engine = try prepareAudioEngine()
        let input = engine.inputNode
        // Both directions must use the same voice-processing IO unit so its
        // echo canceller receives the actual assistant playback reference.
        if !input.isVoiceProcessingEnabled {
            engine.stop()
            try input.setVoiceProcessingEnabled(true)
        }
        input.isVoiceProcessingInputMuted = false
        let hardware = input.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: hardware, to: target) else { throw CocoaError(.coderInvalidValue) }
        // Voice processing can expose discrete auxiliary channels. Its first
        // channel is the microphone; automatic downmixing can produce silence.
        converter.channelMap = [0]
        let id = generation
        let microphoneID = microphoneGeneration
        input.installTap(onBus: 0, bufferSize: 2048, format: hardware) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / hardware.sampleRate) + 64
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, converted.frameLength > 0, let samples = converted.int16ChannelData else { return }
            let data = Data(bytes: samples.pointee, count: Int(converted.frameLength) * 2)
            Task { @MainActor in
                guard let self, self.generation == id, self.microphoneGeneration == microphoneID,
                      !self.isMuted else { return }
                self.send(GeminiLiveSupport.realtime(data, video: false), audio: true)
            }
        }
        microphoneTapInstalled = true
        if !engine.isRunning { try engine.start() }
        if playbackFrames > 0 { player?.play() }
    }

    private func stopMicrophone() {
        microphoneGeneration = UUID()
        if microphoneTapInstalled, let engine = audioEngine {
            engine.inputNode.isVoiceProcessingInputMuted = true
            engine.inputNode.removeTap(onBus: 0)
        }
        microphoneTapInstalled = false
        // Keep playback running on mute; the entire engine stops with the session.
    }

    private func clearPlayback() {
        playbackGeneration = UUID()
        playbackFrames = 0
        player?.stop()
        player?.reset()
    }

    private func prepareAudioEngine() throws -> AVAudioEngine {
        if let audioEngine { return audioEngine }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1) else { throw CocoaError(.coderInvalidValue) }
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        audioEngine = engine
        player = node
        return engine
    }

    private func play(_ data: Data) throws {
        guard data.count.isMultiple(of: 2), let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1) else { return }
        let engine = try prepareAudioEngine()
        if !engine.isRunning { try engine.start() }
        let frames = data.count / 2
        // Bound queued speech even if playback falls behind the network.
        guard playbackFrames + frames <= 24000 * 30,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let samples = buffer.floatChannelData?.pointee else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { bytes in
            for index in 0..<frames {
                let low = UInt16(bytes[index * 2])
                let high = UInt16(bytes[index * 2 + 1]) << 8
                samples[index] = Float(Int16(bitPattern: low | high)) / 32768
            }
        }
        playbackFrames += frames
        let id = playbackGeneration
        player?.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playbackGeneration == id else { return }
                self.playbackFrames = max(0, self.playbackFrames - frames)
            }
        }
        player?.play()
    }

    fileprivate func pickerCancelled(id: UUID) {
        guard screenGeneration == id, isSelectingScreen else { return }
        stopSharingScreen()
    }

    fileprivate func pickerSelected(_ filter: SCContentFilter, id: UUID) {
        guard screenGeneration == id, state == .live, isSelectingScreen, pickerObserver != nil else { return }
        dismissPicker()
        let sessionID = generation
        screenTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await startCapture(filter: filter, id: sessionID, screenID: id)
                guard generation == sessionID, screenGeneration == id,
                      AppFeature.geminiLive.isAvailable else { return }
                isSelectingScreen = false
                isSharingScreen = true
                screenTask = nil
                flushVideo()
            } catch {
                guard generation == sessionID, screenGeneration == id else { return }
                stopSharingScreen()
                self.error = strings.captureFailed
            }
        }
    }

    fileprivate func pickerFailed(id: UUID) {
        guard screenGeneration == id, isSelectingScreen else { return }
        stopSharingScreen()
        error = strings.captureFailed
    }
}

extension GeminiLiveService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            self.stopSharingScreen()
            self.error = self.strings.captureFailed
        }
    }
}

/// Each picker presentation carries its own immutable session identity, including
/// callbacks already queued when its observer is removed during stop/restart.
private final class GeminiLivePickerObserver: NSObject, SCContentSharingPickerObserver {
    private weak var service: GeminiLiveService?
    private let id: UUID

    init(service: GeminiLiveService, id: UUID) {
        self.service = service
        self.id = id
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak service, id] in service?.pickerCancelled(id: id) }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak service, id] in service?.pickerSelected(filter, id: id) }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak service, id] in service?.pickerFailed(id: id) }
    }
}

private final class GeminiLiveScreenOutput: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "com.vorssaint.gemini-live.screen", qos: .utility)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let onFrame: (Data) -> Void

    init(onFrame: @escaping (Data) -> Void) { self.onFrame = onFrame }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        autoreleasepool {
            guard let jpeg = context.jpegRepresentation(of: CIImage(cvPixelBuffer: pixelBuffer), colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.65]) else { return }
            onFrame(jpeg)
        }
    }
}
