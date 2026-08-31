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
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

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

        guard input.inputFormat(forBus: 0).sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
            throw DictationFailure.microphoneUnavailable
        }
        let fileWriter: DictationAudioFileWriter
        do {
            fileWriter = try DictationAudioFileWriter(url: file, settings: settings)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw DictationFailure.microphoneUnavailable
        }

        captureFailed = false
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self, weak fileWriter] buffer, _ in
            guard let fileWriter else { return }
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
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: fileURL.path)
        guard let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) > 0 else {
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
        for index in 0 ..< Int(buffer.frameLength) {
            let sample = samples[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(buffer.frameLength))
        return max(0, min(1, rms * 4))
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
