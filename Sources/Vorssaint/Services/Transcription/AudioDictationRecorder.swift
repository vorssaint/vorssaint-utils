// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation

/// Captures microphone audio directly into an in-memory 16 kHz mono Float32
/// buffer for low-latency system-wide voice dictation with Parakeet Core ML.
final class AudioDictationRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case invalidInputFormat
        case converterCreationFailed
        case startFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidInputFormat:
                return "No active microphone input format was available."
            case .converterCreationFailed:
                return "Could not configure 16 kHz microphone audio conversion."
            case .startFailed(let message):
                return message
            }
        }
    }

    /// Cap a single dictation take at 10 minutes (9.6M Float32 samples ≈ 38 MB)
    /// so an accidentally left-on microphone never grows memory without bound.
    static let maxSamples = Int(AudioTranscriptionSupport.sampleRate * 600)

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var samples: [Float] = []
    private var isRecording = false

    func start(onLevel: @escaping @Sendable (Float) -> Void) throws {
        stopAndDiscard()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.invalidInputFormat
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioTranscriptionSupport.sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterCreationFailed
        }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(Int(AudioTranscriptionSupport.sampleRate * 10))
        self.engine = engine
        isRecording = true
        lock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = targetFormat.sampleRate / max(1.0, inputFormat.sampleRate)
            let outCapacity = max(1, AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 64)
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

            var error: NSError?
            var consumed = false
            let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, error == nil,
                  let channelData = outBuffer.floatChannelData?[0],
                  outBuffer.frameLength > 0 else { return }

            let count = Int(outBuffer.frameLength)
            var sumSq: Float = 0
            for i in 0..<count {
                let v = channelData[i]
                sumSq += v * v
            }
            let rms = sqrt(sumSq / Float(count))
            let normalizedLevel = min(1, max(0, rms * 8))

            self.lock.lock()
            if self.isRecording, self.samples.count < Self.maxSamples {
                let remaining = Self.maxSamples - self.samples.count
                let appendCount = min(count, remaining)
                let ptr = UnsafeBufferPointer(start: channelData, count: appendCount)
                self.samples.append(contentsOf: ptr)
            }
            self.lock.unlock()

            onLevel(normalizedLevel)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            stopAndDiscard()
            throw RecorderError.startFailed(error.localizedDescription)
        }
    }

    func stop() -> [Float] {
        lock.lock()
        let activeEngine = engine
        engine = nil
        isRecording = false
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()

        if let activeEngine {
            activeEngine.inputNode.removeTap(onBus: 0)
            activeEngine.stop()
        }
        return captured
    }

    func stopAndDiscard() {
        _ = stop()
    }
}
