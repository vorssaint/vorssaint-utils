// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation

enum DictationTests {
    static func run(expect: (Bool, String) -> Void) {
        let timestamp = Date(timeIntervalSince1970: 2_000_000)
        expect(DictationSupport.historyAge(timestamp.addingTimeInterval(-59), relativeTo: timestamp) == DateComponents(second: 0),
               "recent history uses a static now label instead of counting seconds")
        expect(DictationSupport.historyAge(timestamp.addingTimeInterval(-8 * 60 - 59), relativeTo: timestamp) == DateComponents(minute: -8),
               "history ages show whole elapsed minutes")
        expect(DictationSupport.historyAge(timestamp.addingTimeInterval(-3661), relativeTo: timestamp) == DateComponents(hour: -1),
               "older history ages use a single whole unit")
        expect(DictationSupport.historyAge(timestamp.addingTimeInterval(60), relativeTo: timestamp) == DateComponents(second: 0),
               "clock changes cannot produce a future history countdown")
        expect(!ClipboardHistoryCapturePolicy.shouldAnnounce(types: ["public.utf8-plain-text", ClipboardHistoryCapturePolicy.dictationOriginType]),
               "dictation clipboard writes suppress the duplicate island notice")
        expect(ClipboardHistoryCapturePolicy.shouldAnnounce(types: ["public.utf8-plain-text"]),
               "an ordinary copy after dictation still announces normally")
        waveformSamples(expect: expect)
        audioConversion(expect: expect)
        if let model = ProcessInfo.processInfo.environment["VORSSAINT_DICTATION_TEST_MODEL"],
           let sample = ProcessInfo.processInfo.environment["VORSSAINT_DICTATION_TEST_AUDIO"] {
            transcriptionPipeline(model: URL(fileURLWithPath: model), sample: URL(fileURLWithPath: sample), expect: expect)
        }
        var access = NotchQuickAccessConfiguration.initial
        let before = access.buttons
        expect(access.addSpeechHistory(label: "Speech history") && access.buttons.dropLast() == before[...]
               && access.actions.last == .module(.dictation), "adding speech history preserves existing island quick buttons")
        let added = access
        expect(access.addSpeechHistory(label: "Speech history") && access == added, "adding the history shortcut twice does not duplicate it")
        var full = NotchQuickAccessConfiguration(buttons: NotchQuickAccessSide.allCases.flatMap { side in
            (0..<NotchQuickAccessConfiguration.maximumPerSide).map { _ in NotchQuickButton(action: .settings, side: side) }
        })
        let originalLayout = full
        expect(!full.addSpeechHistory(label: "Speech history") && full == originalLayout, "a full layout never loses another quick button")
        let original = "  Um, call vorssaint and album art, not callum.  "
        let cleaned = DictationSupport.cleaned(original, replacements: "vorssaint=Vorssaint\nart=Art $1\nbad line", removeFillers: true, language: "en")
        expect(cleaned == "call Vorssaint and album Art $1, not callum.", "corrections honor word boundaries and literal replacement characters")
        expect(DictationSupport.cleaned("Um, test", replacements: "", removeFillers: true, language: "de") == "Um, test",
               "English filler removal never rewrites a different language")
        let root = URL(fileURLWithPath: "/private/dictation")
        let id = UUID()
        expect(DictationSupport.safeAudioURL(filename: id.uuidString + ".caf", directory: root)?.deletingLastPathComponent().path == root.path,
               "valid recording identifiers resolve inside private history")
        for invalid in ["../secret.caf", "/tmp/secret.caf", "anything.caf", "..", id.uuidString + ".wav"] {
            expect(DictationSupport.safeAudioURL(filename: invalid, directory: root) == nil, "history rejects an unsafe recording path")
        }
        let now = Date(timeIntervalSince1970: 2_000_000)
        expect(!DictationSupport.audioExpired(now.addingTimeInterval(-86399), days: 1, now: now)
               && DictationSupport.audioExpired(now.addingTimeInterval(-86400), days: 1, now: now)
               && DictationSupport.audioExpired(now, days: 0, now: now), "audio expiry respects the retention boundary and Never")
        let entries = (0..<5).map { i in DictationEntry(text: "Text \(i)", originalText: "Text \(i)", modelID: "test", language: "en", duration: 1, processingDuration: 0.1, isFavorite: i == 4) }
        expect(DictationSupport.retained(entries, limit: 2).map(\.id) == [entries[0].id, entries[1].id, entries[4].id],
               "history trims old ordinary entries while retaining favorites in order")
        expect(DictationSupport.retained(entries, limit: 0).isEmpty, "turning off history removes favorites too")
        expect((try? JSONDecoder().decode([DictationEntry].self, from: JSONEncoder().encode(entries))) == entries,
               "private history preserves original text, timestamps and favorites across saves")
        expect(AppFeature.dictation.permissions.contains(.microphone) && AppFeature.dictation.permissions.contains(.accessibility)
               && !AppFeature.dictation.installedByDefault, "dictation advertises permissions and remains opt-in")
        for language in AppLanguage.allCases {
            expect(!DictationStrings.localized(language).title.isEmpty && !DictationStrings.localized(language).history.isEmpty,
                   "dictation has core labels in \(language.rawValue)")
        }
    }

    private static func waveformSamples(expect: (Bool, String) -> Void) {
        let step = 2.0 * Double.pi * 1000.0 / 16000.0
        let samples: [Float] = (0..<16000).map { Float(sin(Double($0) * step) * 0.2) }
        let whole = DictationSpectrum()
        whole.append(samples)
        let split = DictationSpectrum()
        for start in stride(from: 0, to: samples.count, by: 137) {
            split.append(Array(samples[start..<min(samples.count, start + 137)]))
        }
        expect(whole.bars == split.bars, "stationary waveform motion is independent of tap boundaries")
        expect(whole.bars == Array(whole.bars.reversed()), "frequency bars stay mirrored around their fixed center")
        let steady = whole.bars
        whole.append(samples)
        expect(zip(whole.bars, steady).allSatisfy { abs($0 - $1) < 0.01 }, "a steady tone produces steady bar heights rather than horizontal motion")
        expect((whole.bars.max() ?? 0) > 0.5 && (whole.bars.min() ?? 1) < 0.1, "bars resolve real frequency content instead of bouncing randomly together")
        whole.append([Float](repeating: 0, count: 32000))
        expect(whole.bars.allSatisfy { $0 < 0.001 }, "silence releases every bar smoothly to its baseline")
        whole.append([Float](repeating: .nan, count: 1024))
        expect(whole.bars.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, "invalid samples cannot corrupt stationary bar geometry")
    }

    private static func audioConversion(expect: (Bool, String) -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-conversion-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for rate in [8000.0, 16000.0, 44100.0, 48000.0] {
                for channels: AVAudioChannelCount in [1, 2] {
                    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
                    let frames = AVAudioFrameCount(rate * 0.37)
                    let source = root.appendingPathComponent(UUID().uuidString + ".caf")
                    // Exercise the production writer, close, decoder and resampler.
                    // No hardware or personal recordings are used.
                    try autoreleasepool {
                        let writer = try DictationRecorder.makeRecordingFile(at: source, format: format)
                        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
                        buffer.frameLength = frames
                        for channel in 0..<Int(channels) {
                            for frame in 0..<Int(frames) { buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 220 / rate)) * 0.2 }
                        }
                        try writer.write(from: buffer)
                        if #available(macOS 15, *) { writer.close() }
                    }
                    let input = try AVAudioFile(forReading: source)
                    let live = try DictationPCMConverter(format: input.processingFormat)
                    let chunk = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 137)!
                    var streamed = Data()
                    while input.framePosition < input.length {
                        try input.read(into: chunk, frameCount: AVAudioFrameCount(min(137, input.length - input.framePosition)))
                        for data in try live.append(chunk) { streamed.append(data) }
                    }
                    for data in try live.finish() { streamed.append(data) }
                    let output = try DictationEngine.convertAudio(source, temporaryDirectory: root)
                    let bytes = try Data(contentsOf: output)
                    let actualFrames = bytes.count / MemoryLayout<Float>.size
                    let expectedFrames = Int(Double(frames) * 16000 / rate)
                    expect(abs(actualFrames - expectedFrames) <= 2,
                           "CAF conversion reaches EOF cleanly and preserves duration at \(Int(rate)) Hz / \(channels) channels")
                    expect(abs(streamed.count - bytes.count) <= 8, "live resampling preserves the final audio tail at \(Int(rate)) Hz / \(channels) channels")
                    let liveSamples = streamed.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                    let liveEnergy = liveSamples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, liveSamples.count))
                    expect(liveSamples.allSatisfy(\.isFinite) && abs(liveEnergy - 0.02) < 0.003,
                           "streamed tone keeps its amplitude across buffer boundaries and resampling")
                    let samples = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                    expect(samples.allSatisfy(\.isFinite) && samples.contains { abs($0) > 0.01 },
                           "resampled microphone-format audio contains finite nonzero samples")
                }
            }
        } catch { expect(false, "production audio conversion failed: \(error)") }
    }

    /// Optional integration check with explicitly supplied public audio/model.
    /// This follows capture-format CAF → production resampler → native worker,
    /// unlike the worker-only smoke test, which starts with preconverted PCM.
    private static func transcriptionPipeline(model: URL, sample: URL, expect: (Bool, String) -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-pipeline-" + UUID().uuidString, isDirectory: true)
        let engine = DictationEngine()
        defer { engine.cancel(); try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let recorded = root.appendingPathComponent("recording.caf")
            try autoreleasepool {
                let input = try AVAudioFile(forReading: sample)
                let writer = try DictationRecorder.makeRecordingFile(at: recorded, format: input.processingFormat)
                let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 4096)!
                while input.framePosition < input.length {
                    try input.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, input.length - input.framePosition)))
                    try writer.write(from: buffer)
                }
                if #available(macOS 15, *) { writer.close() }
            }
            var response: Result<DictationEngine.Result, Error>?
            engine.transcribe(.init(audio: recorded, model: model, language: "en", translate: false,
                                    vocabulary: [], cpu: false, temporaryDirectory: root)) { response = $0 }
            let deadline = Date().addingTimeInterval(120)
            while response == nil, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            switch response {
            case .success(let result):
                expect(result.text?.localizedCaseInsensitiveContains("country") == true,
                       "full CAF-to-text pipeline transcribes the public JFK sample with the selected model")
            case .failure(let error): expect(false, "full dictation pipeline failed: \(error)")
            case nil: expect(false, "full dictation pipeline timed out")
            }
            // Exercise live conversion and queued feeds in audio time. An explicitly
            // unsupported model must still return the complete batch transcript.
            let request = DictationEngine.Request(audio: recorded, model: model, language: "en", translate: false,
                                                  vocabulary: [], cpu: false, temporaryDirectory: root)
            var streaming: Bool?
            let id = engine.beginLive(request) { streaming = $0 }
            let input = try AVAudioFile(forReading: recorded)
            let converter = try DictationPCMConverter(format: input.processingFormat)
            let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 1600)!
            let began = Date()
            while input.framePosition < input.length {
                try input.read(into: buffer, frameCount: AVAudioFrameCount(min(1600, input.length - input.framePosition)))
                for data in try converter.append(buffer) { engine.appendLive(data, id: id) }
                let due = began.addingTimeInterval(Double(input.framePosition) / input.processingFormat.sampleRate)
                if due > Date() { RunLoop.current.run(until: due) }
            }
            for data in try converter.finish() { engine.appendLive(data, id: id) }
            response = nil
            let released = Date()
            engine.transcribe(request, finishingLive: id) { response = $0 }
            let liveDeadline = Date().addingTimeInterval(120)
            while response == nil, Date() < liveDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            switch response {
            case .success(let result):
                expect(result.text?.localizedCaseInsensitiveContains("country") == true,
                       "live microphone resampling and finalization retain the full speech fixture")
                expect(streaming != nil && (result.streaming == true) == streaming,
                       "stream-capable models finalize live; unsupported models fall back to batch")
                print(String(format: "Dictation release-to-result: %.3f s (streaming: %@)", Date().timeIntervalSince(released), String(streaming ?? false)))
            case .failure(let error): expect(false, "live dictation pipeline failed: \(error)")
            case nil: expect(false, "live dictation pipeline timed out")
            }
            let discarded = engine.beginLive(request)
            engine.appendLive(Data(count: 640), id: discarded)
            engine.discardLive(discarded)
            engine.appendLive(Data(count: 640), id: discarded)
            var warm: Bool?
            let warmID = engine.beginLive(request) { warm = $0 }
            let warmDeadline = Date().addingTimeInterval(120)
            while warm == nil, Date() < warmDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            expect(warm == streaming, "discarding a recording resets live state while keeping the selected model usable")
            engine.discardLive(warmID)
            // Cancellation must invalidate callbacks from the old tap and stream,
            // including a finalization request already racing with cancellation.
            var abandonedReady = false
            let abandoned = engine.beginLive(request) { _ in abandonedReady = true }
            let beginDeadline = Date().addingTimeInterval(120)
            while !abandonedReady, Date() < beginDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            engine.cancel()
            // A tap callback already in flight may flush after cancellation.
            engine.appendLive(Data(count: 640), id: abandoned)
            response = nil
            engine.transcribe(request, finishingLive: abandoned) { response = $0 }
            let retryDeadline = Date().addingTimeInterval(120)
            while response == nil, Date() < retryDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            if case .success(let result) = response {
                expect(result.text?.localizedCaseInsensitiveContains("country") == true, "a cancelled live utterance cannot poison the next transcription")
            } else if case .failure(let error) = response {
                expect(false, "batch retry after cancelling live dictation failed: \(error)")
            } else { expect(false, "batch retry after cancelling live dictation timed out") }
        } catch { expect(false, "audio pipeline fixture failed: \(error)") }
    }
}
