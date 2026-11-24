// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

final class DictationRecorder {
    struct Microphone: Identifiable { let id: String; let name: String; let device: AudioDeviceID }
    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private let lock = NSLock()
    private var level = 0.0
    private var waveform = DictationSpectrum()
    private var liveConverter: DictationPCMConverter?
    private var onPCM: ((Data?) -> Void)?
    private var writeError: Error?
    private var active = false

    static func microphones() -> [Microphone] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.compactMap { device in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
            func string(_ selector: AudioObjectPropertySelector) -> String? {
                var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var value: Unmanaged<CFString>?
                var length = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                guard AudioObjectGetPropertyData(device, &property, 0, nil, &length, &value) == noErr else { return nil }
                return value?.takeUnretainedValue() as String?
            }
            guard let id = string(kAudioDevicePropertyDeviceUID), let name = string(kAudioObjectPropertyName) else { return nil }
            return Microphone(id: id, name: name, device: device)
        }
    }

    func start(at url: URL, microphoneUID: String, onPCM: ((Data?) -> Void)? = nil) throws {
        let engine = AVAudioEngine()
        let node = engine.inputNode
        if !microphoneUID.isEmpty {
            guard var device = Self.microphones().first(where: { $0.id == microphoneUID })?.device,
                  let unit = node.audioUnit,
                  AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device,
                                       UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
                throw DictationError.message("The selected microphone is unavailable. Choose another input in Dictation settings.")
            }
        }
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationError.message("No microphone input is available.") }
        let file = try Self.makeRecordingFile(at: url, format: format)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let converter = try DictationPCMConverter(format: format)
        lock.lock()
        waveform = DictationSpectrum()
        liveConverter = converter; self.onPCM = onPCM
        self.file = file; active = true; level = 0; writeError = nil; lock.unlock()
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.active else { return }
            do { try self.file?.write(from: buffer) } catch { self.writeError = error; self.active = false }
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            if let converter = self.liveConverter {
                do {
                    for data in try converter.append(buffer) {
                        self.waveform.append(data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) })
                        self.onPCM?(data)
                    }
                }
                catch { self.liveConverter = nil; self.onPCM?(nil) }
            }
            var energy: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = channels[channel][frame]
                    energy += sample * sample
                }
            }
            let rms = sqrt(energy / Float(buffer.frameLength * buffer.format.channelCount))
            self.level = min(1, max(0, Double(rms) * 6))
        }
        do { try engine.start(); self.engine = engine }
        catch { node.removeTap(onBus: 0); stop(); throw error }
    }

    func reading() -> (level: Double, waveform: [Double], error: Error?) {
        lock.lock(); defer { lock.unlock() }
        return (level, waveform.bars, writeError)
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        lock.lock()
        active = false
        if let converter = liveConverter {
            do { for data in try converter.finish() { onPCM?(data) } }
            catch { onPCM?(nil) }
        }
        liveConverter = nil; onPCM = nil
        if #available(macOS 15, *) { file?.close() }
        file = nil
        level = 0
        lock.unlock()
    }

    /// CAF stores interleaved PCM on disk; the writer's processing format
    /// follows the engine's buffers, which are normally planar float32.
    static func makeRecordingFile(at url: URL, format: AVAudioFormat) throws -> AVAudioFile {
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        return try AVAudioFile(forWriting: url, settings: settings,
                               commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    }
}

/// A stationary, mirrored spectrum of the current 32 ms of microphone audio.
/// Each bar owns a fixed frequency band. Attack/release smoothing happens in
/// audio time so tap size and UI cadence cannot change its motion.
final class DictationSpectrum {
    static let bandCount = 16
    static let count = bandCount * 2 - 1
    private let size = 512
    private let setup: vDSP_DFT_Setup?
    private var block: [Float] = []
    private let window: [Float]
    private var real = [Float](repeating: 0, count: 512)
    private var imaginary = [Float](repeating: 0, count: 512)
    private let zero = [Float](repeating: 0, count: 512)
    private var envelopes = [Double](repeating: 0, count: bandCount)
    private(set) var bars = [Double](repeating: 0, count: count)

    init() {
        setup = vDSP_DFT_zop_CreateSetup(nil, 512, .FORWARD)
        window = (0..<512).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / 511)) }
        block.reserveCapacity(512)
    }
    deinit { if let setup { vDSP_DFT_DestroySetup(setup) } }

    func append(_ samples: [Float]) {
        for sample in samples {
            block.append(sample.isFinite ? sample : 0)
            if block.count == size { analyze(); block.removeAll(keepingCapacity: true) }
        }
    }

    private func analyze() {
        guard let setup else { return }
        let input = zip(block, window).map(*)
        input.withUnsafeBufferPointer { source in
            zero.withUnsafeBufferPointer { zeros in
                real.withUnsafeMutableBufferPointer { real in
                    imaginary.withUnsafeMutableBufferPointer { imaginary in
                        vDSP_DFT_Execute(setup, source.baseAddress!, zeros.baseAddress!, real.baseAddress!, imaginary.baseAddress!)
                    }
                }
            }
        }
        for band in 0..<Self.bandCount {
            let lower = 80 * pow(6000.0 / 80, Double(band) / Double(Self.bandCount))
            let upper = 80 * pow(6000.0 / 80, Double(band + 1) / Double(Self.bandCount))
            let first = max(1, Int(ceil(lower * Double(size) / 16000)))
            let last = min(size / 2, max(first + 1, Int(ceil(upper * Double(size) / 16000))))
            var power = 0.0
            for bin in first..<last { power += Double(real[bin] * real[bin] + imaginary[bin] * imaginary[bin]) }
            let amplitude = sqrt(power) * 4 / Double(size)
            // A fixed noise floor and gain: no random motion or silence AGC.
            let target = min(1, max(0, (20 * log10(max(0.00001, amplitude)) + 58) / 44))
            let coefficient = 1 - exp(-0.032 / (target > envelopes[band] ? 0.045 : 0.18))
            envelopes[band] += (target - envelopes[band]) * coefficient
        }
        bars = Array(envelopes.dropFirst().reversed()) + envelopes
    }
}

/// Stateful streaming resampler: carries filter history across microphone taps
/// and flushes its final samples before inference is finalized.
final class DictationPCMConverter {
    private let converter: AVAudioConverter
    private let output: AVAudioPCMBuffer

    init(format: AVAudioFormat) throws {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) else {
            throw DictationError.message("Could not prepare microphone audio.")
        }
        self.converter = converter; self.output = output
    }

    func append(_ buffer: AVAudioPCMBuffer) throws -> [Data] { try convert(buffer, ending: false) }
    func finish() throws -> [Data] { try convert(nil, ending: true) }

    private func convert(_ input: AVAudioPCMBuffer?, ending: Bool) throws -> [Data] {
        var supplied = false
        var chunks: [Data] = []
        while true {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                if let input, !supplied { supplied = true; state.pointee = .haveData; return input }
                state.pointee = ending ? .endOfStream : .noDataNow
                return nil
            }
            if let error { throw error }
            if status == .error { throw DictationError.message("Live audio conversion failed.") }
            if output.frameLength > 0, let samples = output.floatChannelData?[0] {
                chunks.append(Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Float>.size))
            }
            if status != .haveData { return chunks }
        }
    }
}
