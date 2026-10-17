// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation

enum FinderMediaExportTests {
    static func run(_ suite: TestSuite) {
        suite.run("Finder audio export") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: root) }
                let input = root.appendingPathComponent("input.wav")
                let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
                buffer.frameLength = 44_100
                for index in 0..<44_100 { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 440 * 2 * .pi / 44_100)) * 0.25 }
                do {
                    let writer = try AVAudioFile(forWriting: input, settings: format.settings)
                    try writer.write(from: buffer)
                }
                let original = try Data(contentsOf: input)
                let output = root.appendingPathComponent("audio.m4a")
                _ = try FinderAudioTools.extract(from: input, to: output, cancellation: FinderToolsCancellation())
                let reader = try AVAudioFile(forReading: output)
                suite.expect(reader.length > 40_000 && reader.processingFormat.channelCount == 1,
                             "native M4A export contains a decodable audio track with the expected duration")
                let after = try Data(contentsOf: input)
                suite.expect(after == original, "audio extraction preserves the source bytes")
                let cancelled = FinderToolsCancellation()
                cancelled.cancel()
                let cancelledOutput = root.appendingPathComponent("cancelled.m4a")
                do {
                    _ = try FinderAudioTools.extract(from: input, to: cancelledOutput, cancellation: cancelled)
                    suite.expect(false, "cancelled export must fail")
                } catch is CancellationError {
                    suite.expect(!FileManager.default.fileExists(atPath: cancelledOutput.path), "cancellation publishes no audio output")
                }
            } catch { suite.expect(false, "audio fixture failed: \(error)") }
        }
    }
}
