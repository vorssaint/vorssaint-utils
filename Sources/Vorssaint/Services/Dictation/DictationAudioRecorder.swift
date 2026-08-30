// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation

@MainActor
final class DictationAudioRecorder: NSObject, @preconcurrency AVAudioRecorderDelegate {
    static let maximumDuration: TimeInterval = 10 * 60

    var onLevel: ((Float) -> Void)?
    var onFailure: (() -> Void)?
    var onFinished: (() -> Void)?

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var expectsAutomaticFinish = false
    private(set) var fileURL: URL?

    var isRecording: Bool { recorder?.isRecording == true }

    func start() throws {
        cancel()
        guard let container = PrivateFileStore.containerURL else {
            throw DictationFailure.microphoneUnavailable
        }
        let directory = container.appendingPathComponent("Dictation", isDirectory: true)
        guard PrivateFileStore.createDirectory(at: directory) else {
            throw DictationFailure.microphoneUnavailable
        }
        removeAbandonedRecordings(in: directory)
        let file = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: file, settings: settings)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw DictationFailure.microphoneUnavailable
        }
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record(forDuration: Self.maximumDuration) else {
            recorder.deleteRecording()
            throw DictationFailure.microphoneUnavailable
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: file.path)
        self.recorder = recorder
        expectsAutomaticFinish = true
        fileURL = file
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishLevel() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    func stop() throws -> URL {
        guard let recorder, let fileURL else { throw DictationFailure.noSpeech }
        expectsAutomaticFinish = false
        meterTimer?.invalidate()
        meterTimer = nil
        recorder.stop()
        self.recorder = nil
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: fileURL.path)
        guard let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) > 0
        else {
            discardFile()
            throw DictationFailure.noSpeech
        }
        return fileURL
    }

    func cancel() {
        meterTimer?.invalidate()
        meterTimer = nil
        if let recorder {
            expectsAutomaticFinish = false
            recorder.stop()
            recorder.deleteRecording()
        }
        recorder = nil
        discardFile()
        onLevel?(0)
    }

    func discardFile() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
        self.fileURL = nil
    }

    private func publishLevel() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)
        let normalized = max(0, min(1, pow(10, decibels / 30)))
        onLevel?(normalized)
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        meterTimer?.invalidate()
        meterTimer = nil
        let wasAutomatic = expectsAutomaticFinish
        expectsAutomaticFinish = false
        self.recorder = nil
        if flag {
            if wasAutomatic { onFinished?() }
            return
        }
        self.recorder = nil
        discardFile()
        onFailure?()
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        meterTimer?.invalidate()
        meterTimer = nil
        self.recorder = nil
        discardFile()
        onFailure?()
    }

    deinit {
        meterTimer?.invalidate()
        recorder?.stop()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
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
