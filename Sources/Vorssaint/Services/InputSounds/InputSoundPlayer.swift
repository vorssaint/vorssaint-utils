// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation

/// Plays the input sounds with as little delay as the audio system allows.
///
/// A small pool of player voices sits on one engine, so overlapping sounds
/// (a fast typist, a double click) never cut each other off. Sounds are
/// rendered the first time they are needed and kept, a few slight variations
/// each. The engine pauses after a quiet spell, so a Mac nobody is typing on
/// runs no audio at all, and resumes on the next sound. The microphone is
/// never touched: the engine's input side is not even looked at.
///
/// Everything runs on `queue`.
final class InputSoundPlayer {
    static let variationsPerSound = 4
    private static let voiceCount = 12
    private static let idlePauseSeconds: TimeInterval = 20

    let queue = DispatchQueue(label: "com.vorssaint.inputsounds.audio", qos: .userInteractive)

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: InputSoundSynth.sampleRate, channels: 1)!
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var cache: [String: [AVAudioPCMBuffer]] = [:]
    private var variationCounter = 0
    private var lastPlay = Date.distantPast
    private var idleTimer: DispatchSourceTimer?
    private var configurationObserver: NSObjectProtocol?
    private var isSetUp = false

    // MARK: Playback

    /// Plays `recipe`, rendering and caching it under `key` the first time.
    func play(key: String, recipe: @autoclosure () -> InputSoundRecipe, volume: Float, pan: Float) {
        let buffers: [AVAudioPCMBuffer]
        if let cached = cache[key] {
            buffers = cached
        } else {
            let base = recipe()
            buffers = (0..<Self.variationsPerSound).compactMap {
                makeBuffer(InputSoundSynth.render(base, variation: $0))
            }
            cache[key] = buffers
        }
        guard !buffers.isEmpty else { return }
        variationCounter &+= 1
        play(buffers[variationCounter % buffers.count], volume: volume, pan: pan)
    }

    /// Plays a recording the user added, already converted to the engine's
    /// format by `loadCustom`.
    func play(buffer: AVAudioPCMBuffer, volume: Float, pan: Float) {
        play(buffer, volume: volume, pan: pan)
    }

    /// Renders ahead of time so the first press after a change is instant.
    func prepare(key: String, recipe: InputSoundRecipe) {
        guard cache[key] == nil else { return }
        cache[key] = (0..<Self.variationsPerSound).compactMap {
            makeBuffer(InputSoundSynth.render(recipe, variation: $0))
        }
    }

    func clearCache() {
        cache.removeAll()
    }

    /// Stops the engine and lets go of every voice, as when the feature is
    /// turned off.
    func shutDown() {
        idleTimer?.cancel()
        idleTimer = nil
        for voice in voices { voice.stop() }
        if engine.isRunning { engine.stop() }
        cache.removeAll()
    }

    private func play(_ buffer: AVAudioPCMBuffer, volume: Float, pan: Float) {
        guard volume > 0, ensureRunning() else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.volume = min(1, volume)
        voice.pan = max(-1, min(1, pan))
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !voice.isPlaying { voice.play() }
        lastPlay = Date()
    }

    // MARK: Engine

    private func setUpIfNeeded() {
        guard !isSetUp else { return }
        isSetUp = true
        for _ in 0..<Self.voiceCount {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
        // A new output (headphones, AirPods, a display's speakers) stops the
        // engine; the next sound starts it again on the new route.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.queue.async {
                self?.voices.forEach { $0.stop() }
            }
        }
    }

    private func ensureRunning() -> Bool {
        setUpIfNeeded()
        if engine.isRunning { return true }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            return false
        }
        startIdleTimer()
        return true
    }

    private func startIdleTimer() {
        guard idleTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard Date().timeIntervalSince(self.lastPlay) > Self.idlePauseSeconds else { return }
            self.voices.forEach { $0.stop() }
            self.engine.pause()
            self.idleTimer?.cancel()
            self.idleTimer = nil
        }
        idleTimer = timer
        timer.resume()
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }

    // MARK: Custom recordings

    /// Reads an audio file into the engine's format: mono, at the synth's
    /// rate, cut to the longest sound the library allows.
    func loadCustom(url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sourceFormat = file.processingFormat
        let maximumFrames = AVAudioFrameCount(
            min(Double(file.length), InputSoundSynth.maximumDuration * sourceFormat.sampleRate))
        guard maximumFrames > 0,
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: maximumFrames),
              (try? file.read(into: source, frameCount: maximumFrames)) != nil,
              let converter = AVAudioConverter(from: sourceFormat, to: format) else { return nil }
        let ratio = format.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var delivered = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if delivered {
                status.pointee = .endOfStream
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return source
        }
        guard conversionError == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
