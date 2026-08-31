// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreAudio
import Foundation

/// Serializes writes made by AVAudioEngine's realtime tap without crossing the
/// recorder's main-actor boundary from the audio thread.
private final class DictationAudioFileWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var audioFile: AVAudioFile?

    init(url: URL, settings: [String: Any]) throws {
        audioFile = try AVAudioFile(forWriting: url, settings: settings)
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        try audioFile?.write(from: buffer)
    }

    func close() {
        lock.lock()
        audioFile = nil
        lock.unlock()
    }
}

@MainActor
final class DictationAudioRecorder {
    static let maximumDuration: TimeInterval = 10 * 60

    var onLevel: ((Float) -> Void)?
    var onFailure: (() -> Void)?
    var onFinished: (() -> Void)?
    var onDeviceFallback: ((String?) -> Void)?

    private var engine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var writer: DictationAudioFileWriter?
    private var automaticFinishWork: DispatchWorkItem?
    private var captureFailed = false
    private(set) var fileURL: URL?
    private(set) var activeMicrophoneUID: String?
    private(set) var lastRecordingStartedAt: Date?
    private(set) var lastRecordingDuration: TimeInterval?
    private var recordingStartedAt: Date?

    var isRecording: Bool { engine?.isRunning == true }

    func start(microphoneUID: String? = nil) throws {
        cancel()
        guard let container = PrivateFileStore.containerURL else {
            throw DictationFailure.microphoneUnavailable
        }
        let directory = container.appendingPathComponent("Dictation", isDirectory: true)
        guard PrivateFileStore.createDirectory(at: directory) else {
            throw DictationFailure.microphoneUnavailable
        }
        removeAbandonedRecordings(in: directory)

        let resolved = DictationInputDeviceCatalog.selection(preferredUID: microphoneUID)
        guard let device = resolved.device else {
            throw DictationFailure.microphoneUnavailable
        }
        if resolved.selection.usedFallback {
            onDeviceFallback?(device.name)
        }
        let file = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard let audioUnit = input.audioUnit else {
            throw DictationFailure.microphoneUnavailable
        }
        var audioDeviceID = device.audioDeviceID
        let status = AudioUnitSetProperty(audioUnit,
                                          kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global,
                                          0,
                                          &audioDeviceID,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw DictationFailure.microphoneUnavailable
        }

        // An input node's output format can be temporarily zero just after a
        // CoreAudio device switch. The input format is the format delivered by
        // the microphone and is the reliable source for an input tap.
        let captureFormat = input.inputFormat(forBus: 0)
        guard captureFormat.sampleRate > 0, captureFormat.channelCount > 0 else {
            throw DictationFailure.microphoneUnavailable
        }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: captureFormat.sampleRate,
            AVNumberOfChannelsKey: Int(captureFormat.channelCount),
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let fileWriter: DictationAudioFileWriter
        do {
            fileWriter = try DictationAudioFileWriter(url: file, settings: settings)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw DictationFailure.microphoneUnavailable
        }

        captureFailed = false
        input.installTap(onBus: 0, bufferSize: 1_024, format: captureFormat) { [weak self, weak fileWriter] buffer, _ in
            guard let fileWriter else { return }
            Self.applyRecordingGain(to: buffer)
            do {
                try fileWriter.write(buffer)
            } catch {
                Task { @MainActor [weak self] in
                    guard let self, !self.captureFailed else { return }
                    self.captureFailed = true
                    self.onFailure?()
                }
                return
            }
            let level = Self.normalizedLevel(buffer)
            Task { @MainActor [weak self] in self?.onLevel?(level) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            fileWriter.close()
            try? FileManager.default.removeItem(at: file)
            throw DictationFailure.microphoneUnavailable
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: file.path)
        self.engine = engine
        inputNode = input
        writer = fileWriter
        activeMicrophoneUID = device.uid
        recordingStartedAt = Date()
        fileURL = file
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording else { return }
            self.onFinished?()
        }
        automaticFinishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maximumDuration, execute: work)
    }

    func stop() throws -> URL {
        guard let engine, let fileURL else { throw DictationFailure.noSpeech }
        automaticFinishWork?.cancel()
        automaticFinishWork = nil
        inputNode?.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        writer?.close()
        writer = nil
        self.engine = nil
        inputNode = nil
        activeMicrophoneUID = nil
        lastRecordingStartedAt = recordingStartedAt
        lastRecordingDuration = recordingStartedAt.map { Date().timeIntervalSince($0) }
        recordingStartedAt = nil
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: fileURL.path)
        guard let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              DictationRecordedAudio.isUsable(fileSize: values.fileSize,
                                               duration: Self.duration(of: fileURL)) else {
            discardFile()
            throw DictationFailure.noSpeech
        }
        return fileURL
    }

    func cancel() {
        automaticFinishWork?.cancel()
        automaticFinishWork = nil
        inputNode?.removeTap(onBus: 0)
        engine?.stop()
        engine?.reset()
        writer?.close()
        writer = nil
        engine = nil
        inputNode = nil
        activeMicrophoneUID = nil
        recordingStartedAt = nil
        discardFile()
        onLevel?(0)
    }

    func discardFile() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
        self.fileURL = nil
    }

    private static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?.pointee,
              buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        var peak: Float = 0
        for index in 0 ..< Int(buffer.frameLength) {
            let sample = samples[index]
            sum += sample * sample
            peak = max(peak, abs(sample))
        }
        let rms = sqrt(sum / Float(buffer.frameLength))
        // RMS captures sustained speech while peak catches consonants; the
        // combined visual gain does not change audio uploaded to the provider.
        return max(0, min(1, max(rms * 16, peak * 4)))
    }

    /// Microphone input levels vary substantially across Mac devices. Keep a
    /// conservative headroom-preserving gain in the stored recording so local
    /// playback is intelligible, while the soft limiter prevents clipping.
    private static func applyRecordingGain(to buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData,
              buffer.frameLength > 0 else { return }
        let gain: Float = 2.0
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        for channel in 0 ..< channelCount {
            let samples = channels[channel]
            for index in 0 ..< frameCount {
                samples[index] = tanh(samples[index] * gain)
            }
        }
    }

    private static func duration(of fileURL: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: fileURL),
              file.fileFormat.sampleRate > 0,
              file.length > 0 else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    private func removeAbandonedRecordings(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]) else { return }
        for file in files where file.pathExtension.lowercased() == "m4a" {
            guard file != fileURL,
                  let values = try? file.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
