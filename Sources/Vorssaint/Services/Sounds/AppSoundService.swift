// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AudioToolbox
import AVFoundation

/// Plays the app's sounds, each at its own loudness and repeat count, on the
/// main thread. A sound set above full is boosted and held under the
/// output's ceiling by a peak limiter, so it gets louder
/// without crackling.
final class AppSoundService {
    static let shared = AppSoundService()

    /// The pause between repeats of one sound.
    static let repeatGap: TimeInterval = 0.25
    /// How long the engine stays up after the last sound, so a burst of
    /// moments does not restart it each time, while the output can still
    /// sleep between them.
    private static let idleStop: TimeInterval = 3

    let library = AppSoundLibrary.shared
    private var lastPlayed: [AppSound: Date] = [:]
    private let engine = AVAudioEngine()
    /// One player per moment, so a new sound for a moment cuts its last one
    /// short while other moments' sounds play on.
    private var players: [AppSound: AVAudioPlayerNode] = [:]
    private var playing = 0
    private var idleTimer: Timer?
    /// The device the engine was last pointed at, so a play only moves it
    /// when the chosen output changed.
    private var device: AudioDeviceID?
    /// Until when each moment's last sound runs, so an alarm that rings on
    /// its own beat lets a longer sound finish.
    private var soundingUntil: [AppSound: Date] = [:]
    /// The last rendering of each moment, so a sound played often, as on
    /// every snippet, is not read and rendered each time.
    private var rendered: [AppSound: (key: RenderKey, buffer: AVAudioPCMBuffer)] = [:]
    /// Each moment's alert sound registered with the sound server, kept for
    /// the app's life: there are only a few.
    private var alertIDs: [AppSound: (url: URL, id: SystemSoundID)] = [:]

    private struct RenderKey: Equatable {
        let url: URL
        let gain: Float
        let repeats: Int
    }

    private init() {
        // The output's hardware changed under the engine: point it again
        // at the next sound.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: .main) { [weak self] _ in self?.device = nil }
    }

    /// Plays the sound for a moment when it is switched on and the page's
    /// rules let it: an agent's moment names its agent in `context`.
    /// `swapping` trades one choice for another as it plays, as the padlock
    /// opens rather than closes on unlocking.
    func play(_ sound: AppSound, context: AppSoundContext = .none, now: Date = Date(),
              swapping: [AppSoundChoice: AppSoundChoice] = [:]) {
        guard AppSoundSupport.isOn(sound),
              AppSoundSupport.isDue(after: lastPlayed[sound], now: now, gap: sound.minimumGap),
              AppSoundRules.allows(sound, context: context) else { return }
        lastPlayed[sound] = now
        preview(sound, swapping: swapping)
    }

    /// Plays a moment's sound unless its last one is still sounding: the
    /// alarm's beat, which a sound set to repeat would otherwise cut short.
    func ring(_ sound: AppSound, now: Date = Date()) {
        if let until = soundingUntil[sound], now < until { return }
        play(sound, now: now)
    }

    /// Cuts a moment's sound short.
    func stop(_ sound: AppSound) {
        players[sound]?.stop()
        soundingUntil[sound] = nil
    }

    /// Readies a moment's sound so its first play does not wait on the
    /// file, for one heard on a keystroke.
    func prepare(_ sound: AppSound) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.prepare(sound) }
            return
        }
        guard let choice = AppSoundSupport.choice(sound, library: library), let url = library.url(for: choice) else { return }
        if AppSoundSupport.playsAsAlert(sound, choice: choice) { _ = alertID(for: sound, url: url) } else { _ = buffer(for: sound, url: url) }
    }

    /// Plays the chosen sound as set, switched on or not.
    func preview(_ sound: AppSound, swapping: [AppSoundChoice: AppSoundChoice] = [:]) {
        guard let chosen = AppSoundSupport.choice(sound, library: library) else { return }
        let choice = swapping[chosen] ?? chosen
        guard let url = library.url(for: choice) else { return }
        if AppSoundSupport.playsAsAlert(sound, choice: choice) {
            playAlert(sound, url: url)
            return
        }
        guard let buffer = buffer(for: sound, url: url) else { return }
        soundingUntil[sound] = Date().addingTimeInterval(Double(buffer.frameLength) / buffer.format.sampleRate)
        route()
        let player = players[sound] ?? attach(for: sound, format: buffer.format)
        player.stop()
        if engine.outputNode.outputFormat(forBus: 0).sampleRate == 0 { return }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        guard start() else { return }
        playing += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.finished() }
        }
        player.play()
    }

    private func buffer(for sound: AppSound, url: URL) -> AVAudioPCMBuffer? {
        let key = RenderKey(url: url, gain: Float(AppSoundSupport.volume(sound)), repeats: AppSoundSupport.repeats(sound))
        if let cached = rendered[sound], cached.key == key { return cached.buffer }
        guard let buffer = Self.render(url, gain: key.gain, repeats: key.repeats) else { return nil }
        rendered[sound] = (key, buffer)
        return buffer
    }

    /// The way the padlock and the snippet sound always played: through the
    /// sound server, on the sound effects output at the alert volume.
    private func playAlert(_ sound: AppSound, url: URL) {
        guard let id = alertID(for: sound, url: url) else { return }
        if sound == .screenLock {
            AudioServicesPlaySystemSoundWithCompletion(id, nil)
        } else {
            // An alert, so it flashes the screen when Accessibility asks.
            AudioServicesPlayAlertSoundWithCompletion(id, nil)
        }
    }

    private func alertID(for sound: AppSound, url: URL) -> SystemSoundID? {
        if let alert = alertIDs[sound], alert.url == url { return alert.id }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == noErr else { return nil }
        if sound == .screenLock {
            // Not an interface sound, so the padlock plays even with
            // interface sound effects off in System Settings. The alert
            // volume and the sound effects output still apply.
            var interface: UInt32 = 0
            AudioServicesSetProperty(kAudioServicesPropertyIsUISound, UInt32(MemoryLayout<SystemSoundID>.size), &id,
                                     UInt32(MemoryLayout<UInt32>.size), &interface)
        }
        if let old = alertIDs[sound] { AudioServicesDisposeSystemSoundID(old.id) }
        alertIDs[sound] = (url, id)
        return id
    }

    private func attach(for sound: AppSound, format: AVAudioFormat) -> AVAudioPlayerNode {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        players[sound] = player
        return player
    }

    /// Points the engine at the chosen output, checked at every sound so
    /// it follows the Mac's choice when that moves. Moving it stops what
    /// plays, as the engine must be still to change device.
    private func route() {
        guard let wanted = AppSoundSituation.device(for: AppSoundRules.output()), wanted != device,
              let unit = engine.outputNode.audioUnit else { return }
        var current = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let read = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                        &current, &size)
        if read == noErr, current == wanted { device = wanted; return }
        if engine.isRunning {
            players.values.forEach { $0.stop() }
            engine.stop()
            playing = 0
        }
        var target = wanted
        if AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                &target, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr {
            device = wanted
        }
    }

    private func start() -> Bool {
        idleTimer?.invalidate()
        idleTimer = nil
        guard !engine.isRunning else { return true }
        engine.prepare()
        do { try engine.start() } catch { return false }
        return true
    }

    private func finished() {
        playing = max(0, playing - 1)
        guard playing == 0 else { return }
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleStop, repeats: false) { [weak self] _ in
            guard let self, self.playing == 0 else { return }
            self.engine.stop()
        }
    }

    /// The file at `gain`, `repeats` times with a short pause between, in
    /// one buffer. Peaks a boost would push past full scale are limited.
    static func render(_ url: URL, gain: Float, repeats: Int) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url),
              file.length > 0, file.length < AVAudioFramePosition(Int32.max),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: source)) != nil else { return nil }
        let format = source.format
        let channels = Int(format.channelCount)
        let frames = Int(source.frameLength)
        let gap = Int(format.sampleRate * repeatGap)
        let count = max(1, repeats)
        let total = frames * count + gap * (count - 1)
        guard channels > 0, let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let input = source.floatChannelData, let target = output.floatChannelData else { return nil }
        output.frameLength = AVAudioFrameCount(total)
        // Interleaved, as the limiter takes it.
        var samples = [Float](repeating: 0, count: total * channels)
        for pass in 0..<count {
            let start = pass * (frames + gap)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    samples[(start + frame) * channels + channel] = input[channel][frame] * gain
                }
            }
        }
        if gain > 1 {
            var limiter = BoostLimiter()
            let release = BoostLimiter.release(sampleRate: format.sampleRate)
            samples.withUnsafeMutableBufferPointer {
                if let base = $0.baseAddress { limiter.process(base, frames: total, channels: channels, release: release) }
            }
        }
        for frame in 0..<total {
            for channel in 0..<channels { target[channel][frame] = samples[frame * channels + channel] }
        }
        return output
    }
}
