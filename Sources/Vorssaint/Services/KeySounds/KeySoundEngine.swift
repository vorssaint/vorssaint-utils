// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import CoreAudio
import Foundation

/// Plays preloaded key samples through a small pool of voices. Every call
/// arrives on `queue`; nothing here touches the main thread.
final class KeySoundEngine {
    let queue = DispatchQueue(label: "com.vorssaint.keysounds.audio", qos: .userInteractive)

    private let engine = AVAudioEngine()
    private var voices: [(player: AVAudioPlayerNode, varispeed: AVAudioUnitVarispeed)] = []
    private var nextVoice = 0
    private var format: AVAudioFormat?
    private var loadedPackID: String?
    private var press: [KeySoundGroup: [KeySoundStrength: [AVAudioPCMBuffer]]] = [:]
    private var release: [KeySoundGroup: [AVAudioPCMBuffer]] = [:]
    private var configObserver: NSObjectProtocol?
    private var builtInCheck: (at: UInt64, ok: Bool) = (0, true)

    var volume: Float = 0.8
    var builtInSpeakersOnly = false
    var pitchVariation: Float = 0.03
    var gainVariation: Float = 0.06

    private let voiceCount = 12

    /// Loads a pack (no-op when already loaded). Returns false if unusable.
    @discardableResult
    func load(pack: KeySoundPackInfo) -> Bool {
        if loadedPackID == pack.id { return true }
        guard let manifest = KeySoundPackCatalog.load(pack.url) else { return false }
        var cache: [String: AVAudioPCMBuffer] = [:]
        var newFormat: AVAudioFormat?
        func buffers(_ paths: [String]) -> [AVAudioPCMBuffer] {
            paths.compactMap { path in
                if let hit = cache[path] { return hit }
                guard let file = try? AVAudioFile(forReading: pack.url.appendingPathComponent(path)),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)),
                      (try? file.read(into: buffer)) != nil else { return nil }
                if newFormat == nil { newFormat = file.processingFormat }
                guard file.processingFormat == newFormat else { return nil }
                cache[path] = buffer
                return buffer
            }
        }
        var newPress: [KeySoundGroup: [KeySoundStrength: [AVAudioPCMBuffer]]] = [:]
        var newRelease: [KeySoundGroup: [AVAudioPCMBuffer]] = [:]
        for group in KeySoundGroup.allCases {
            for strength in KeySoundStrength.allCases {
                newPress[group, default: [:]][strength] = buffers(manifest.pressSamples(group, strength))
            }
            newRelease[group] = buffers(manifest.releaseSamples(group))
        }
        guard let newFormat, !(newPress[.alpha]?[.medium] ?? []).isEmpty else { return false }
        press = newPress
        release = newRelease
        loadedPackID = pack.id
        if format != newFormat {
            format = newFormat
            rebuildGraph()
        }
        return true
    }

    func start() {
        if voices.isEmpty { rebuildGraph() }
        if configObserver == nil {
            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                self?.queue.async { self?.restart() }
            }
        }
        restart()
    }

    func stop() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        voices.forEach { $0.player.stop() }
        engine.stop()
    }

    /// Unloads samples so an idle, switched-off feature holds no memory.
    func unload() {
        stop()
        press = [:]
        release = [:]
        loadedPackID = nil
    }

    func playPress(_ group: KeySoundGroup, _ strength: KeySoundStrength) {
        guard let buffer = press[group]?[strength]?.randomElement() else { return }
        // Harder hits are also a little louder, on top of the sample itself.
        let accent: Float = [0.8, 0.92, 1.0, 1.0][strength.index]
        play(buffer, gain: accent)
    }

    func playRelease(_ group: KeySoundGroup) {
        guard let buffer = release[group]?.randomElement() else { return }
        play(buffer, gain: 0.7)
    }

    private func play(_ buffer: AVAudioPCMBuffer, gain: Float) {
        guard !voices.isEmpty, outputAllowed() else { return }
        if !engine.isRunning { restart() }
        guard engine.isRunning else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.player.stop()
        voice.varispeed.rate = 1 + Float.random(in: -pitchVariation...pitchVariation)
        voice.player.volume = max(0, min(1, volume * gain * (1 + Float.random(in: -gainVariation...gainVariation))))
        voice.player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        voice.player.play()
    }

    private func rebuildGraph() {
        engine.stop()
        for voice in voices {
            engine.detach(voice.player)
            engine.detach(voice.varispeed)
        }
        voices = []
        guard let format else { return }
        for _ in 0..<voiceCount {
            let player = AVAudioPlayerNode()
            let varispeed = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(varispeed)
            engine.connect(player, to: varispeed, format: format)
            engine.connect(varispeed, to: engine.mainMixerNode, format: format)
            voices.append((player, varispeed))
        }
    }

    private func restart() {
        guard !voices.isEmpty else { return }
        engine.prepare()
        try? engine.start()
    }

    private func outputAllowed() -> Bool {
        guard builtInSpeakersOnly else { return true }
        let now = DispatchTime.now().uptimeNanoseconds
        if now - builtInCheck.at > 1_000_000_000 {
            builtInCheck = (now, Self.defaultOutputIsBuiltIn())
        }
        return builtInCheck.ok
    }

    private static func defaultOutputIsBuiltIn() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                         &size, &device) == noErr else { return true }
        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr
        else { return true }
        return transport == kAudioDeviceTransportTypeBuiltIn
    }
}
