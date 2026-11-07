// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint Audio contributors
import CoreAudio
import Foundation
import Darwin
import SoftwareVolumePCM
import os

/// Output-only playback. PCM property calls never execute on the audio thread.
final class VirtualOutputBridge {
    private static let log = Logger(subsystem: "com.vorssaint.utils", category: "software-volume")
    final class Progress {
        private var count: Int64 = 0
        var cycles: Int64 { OSAtomicAdd64Barrier(0, &count) }
        func advance() { OSAtomicIncrement64Barrier(&count) }
    }
    private final class Storage {
        let pointer: UnsafeMutableRawPointer
        init(rate: Double, channels: UInt32, channelMap: [UInt32]) throws {
            guard let pointer = vs_playback_create_channels(channels) else { throw Failure("Could not allocate playback buffer") }
            guard channelMap.withUnsafeBufferPointer({ vs_playback_set_channel_map(pointer, $0.baseAddress!, UInt32($0.count)) }) != 0 else {
                vs_playback_destroy(pointer)
                throw Failure("Could not configure physical output channel mapping")
            }
            self.pointer = pointer
            vs_playback_rate(pointer, rate)
        }
        deinit { vs_playback_destroy(pointer) }
    }
    private final class Pump {
        private let device: AudioObjectID
        private let rate: Double
        private let channels: UInt32
        private let storage: Storage
        private let key: Data
        private var generation: UInt64 = 0
        private var cursor: UInt64 = 0
        private var nonce: UInt64 = 0
        private var timer: DispatchSourceTimer?
        private var lastPoll: CFAbsoluteTime = 0
        private var largestGap: Double = 0
        private var lastReport: CFAbsoluteTime = 0
        private var lastFailure: String?
        private var didReportReady = false
        private static let log = Logger(subsystem: "com.vorssaint.utils", category: "output-pcm")
        init(device: AudioObjectID, rate: Double, channels: UInt32, storage: Storage) throws {
            self.device = device; self.rate = rate; self.channels = channels; self.storage = storage
            var keyRef: Unmanaged<CFData>?
            guard VirtualOutputHAL.read(device, 0x766b6579, into: &keyRef), let keyRef else {
                throw Failure("Could not authorize output transport", issue: .privacyUnverified)
            }
            let capability = keyRef.takeRetainedValue()
            guard CFGetTypeID(capability) == CFDataGetTypeID(), CFDataGetLength(capability) == 32 else {
                throw Failure("Invalid output transport capability", issue: .privacyUnverified)
            }
            key = capability as Data
            guard poll() else { throw Failure("Could not establish authorized output PCM transport", issue: .privacyUnverified) }
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.vorssaint.utils.output-pcm", qos: .userInteractive))
            timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in _ = self?.poll() }
            self.timer = timer; timer.resume()
        }
        private func failedPoll(_ message: String) -> Bool {
            if lastFailure != message {
                Self.log.error("Output PCM polling failed: \(message, privacy: .public)")
                lastFailure = message
            }
            return false
        }
        private func poll() -> Bool {
            let now = CFAbsoluteTimeGetCurrent()
            if lastPoll != 0 { largestGap = max(largestGap, now - lastPoll) }
            lastPoll = now
            nonce &+= 1
            var request = key.withUnsafeBytes {
                vs_request(generation, cursor, nonce, generation == 0 ? 0 : UInt32(VS_PACKET_FRAMES), $0.baseAddress!)
            }
            var qualifier = withUnsafeBytes(of: &request) { Data($0) } as CFData
            var response: Unmanaged<CFData>?
            var address = VirtualOutputHAL.address(0x7670636d) // vpcm
            var size = UInt32(MemoryLayout<Unmanaged<CFData>?>.size)
            let status = withUnsafePointer(to: &qualifier) {
                AudioObjectGetPropertyData(device, &address, UInt32(MemoryLayout<CFData>.size), $0, &size, &response)
            }
            guard status == noErr else {
                return failedPoll(Failure("Output PCM property read", status: status).localizedDescription)
            }
            guard let response else { return failedPoll("Output PCM response is missing") }
            let data = response.takeRetainedValue()
            guard CFGetTypeID(data) == CFDataGetTypeID() else { return failedPoll("Output PCM response type is invalid") }
            var header = VSPacket()
            guard vs_packet_validate_channels(CFDataGetBytePtr(data), CFDataGetLength(data), nonce, generation, cursor, rate, channels, &header) != 0 else {
                guard CFDataGetLength(data) >= MemoryLayout<VSPacket>.size else {
                    return failedPoll("Output PCM response header is truncated")
                }
                var observed = VSPacket()
                _ = withUnsafeMutableBytes(of: &observed) { bytes in
                    memcpy(bytes.baseAddress!, CFDataGetBytePtr(data), bytes.count)
                }
                return failedPoll("Output PCM packet rejected: version=\(observed.version) channels=\(observed.channels)/\(channels) rate=\(observed.rate)/\(rate) generationMatches=\(generation == 0 || observed.generation == generation) cursorMatches=\(generation == 0 || observed.cursor == cursor)")
            }
            vs_playback_push(storage.pointer, CFDataGetBytePtr(data), CFDataGetLength(data))
            generation = header.generation; cursor = header.next
            if !didReportReady || lastFailure != nil {
                Self.log.notice("Output PCM transport ready: channels=\(self.channels, privacy: .public) sampleRate=\(self.rate, privacy: .public)")
                didReportReady = true; lastFailure = nil
            }
            if now - lastReport >= 1 {
                let stats = vs_playback_stats(storage.pointer)
                Self.log.debug("PCM queued=\(stats.queued) underruns=\(stats.underruns) trimmed=\(stats.trimmed) dropped=\(stats.dropped) maxPollGapMs=\(self.largestGap * 1000)")
                largestGap = 0; lastReport = now
            }
            return true
        }
        func stop() { timer?.cancel(); timer = nil }
        deinit { stop() }
    }
    let progress = Progress()
    let physicalUID: String
    private var ioProc: AudioDeviceIOProcID?
    private var ioStarted = false
    private var physical = AudioObjectID(0)
    private var rate: Float64 = 0
    private var inputLayout: [UInt32] = []
    private var outputLayout: [UInt32] = []
    private var outputConfiguration = Data()
    private var outputChannelMap: [UInt32] = []
    private var pump: Pump?
    private var storage: Storage?

    init(virtual: AudioObjectID, physicalUID: String) throws {
        self.physicalUID = physicalUID
        guard let uid = VirtualOutputHAL.uid(virtual), uid == VirtualOutputSupport.deviceUID,
              VirtualOutputHAL.channels(virtual, scope: kAudioObjectPropertyScopeInput).isEmpty else {
            throw Failure("Output-only software volume component is required", issue: .privacyUnverified)
        }
        guard let physical = VirtualOutputHAL.device(physicalUID),
              VirtualOutputHAL.read(physical, kAudioDevicePropertyNominalSampleRate, into: &rate), rate.isFinite, rate > 0 else {
            throw Failure("Physical output is unavailable", issue: .outputUnavailable)
        }
        self.physical = physical
        guard let configuration = VirtualOutputHAL.outputConfiguration(physical),
              VirtualOutputHAL.configureOutput(virtual, configuration: configuration) else {
            throw Failure("Could not match the physical output channel layout")
        }
        outputConfiguration = configuration
        guard configuration.count == MemoryLayout<VSOutputFormat>.size else {
            throw Failure("Invalid output channel layout metadata")
        }
        let expectedChannels = configuration.withUnsafeBytes { $0.loadUnaligned(as: VSOutputFormat.self).channels }
        let channelCount = VirtualOutputHAL.channels(virtual, scope: kAudioObjectPropertyScopeOutput).reduce(0, +)
        guard channelCount >= 2, channelCount <= VS_MAX_CHANNELS, channelCount == expectedChannels else {
            throw Failure("Unsupported virtual output channel count")
        }
        guard let channelMap = VirtualOutputHAL.outputChannelMap(physical, configuration: configuration) else {
            throw Failure("Physical output channel mapping is unavailable")
        }
        outputChannelMap = channelMap
        let rateStatus = VirtualOutputHAL.write(virtual, kAudioDevicePropertyNominalSampleRate, value: rate)
        guard rateStatus == noErr else {
            throw Failure("Could not match the virtual output sample rate", status: rateStatus)
        }
        var virtualRate: Float64 = 0
        for _ in 0..<30 {
            _ = VirtualOutputHAL.read(virtual, kAudioDevicePropertyNominalSampleRate, into: &virtualRate)
            if virtualRate == rate { break }; Thread.sleep(forTimeInterval: 0.1)
        }
        guard virtualRate == rate else {
            throw Failure("Virtual sample rate did not settle: requested \(rate), actual \(virtualRate)")
        }
        let formats = VirtualOutputHAL.outputFormatSummary(physical)
        Self.log.notice("Preparing output bridge: sampleRate=\(self.rate, privacy: .public) \(formats, privacy: .public)")
        guard VirtualOutputHAL.floatFormats(physical, scope: kAudioObjectPropertyScopeOutput) else {
            throw Failure("Physical output format is unsupported")
        }
        var physicalFrames: UInt32 = 0
        guard VirtualOutputHAL.read(physical, kAudioDevicePropertyBufferFrameSize, into: &physicalFrames),
              physicalFrames > 0, physicalFrames <= UInt32(VS_PACKET_FRAMES) else {
            throw Failure("Physical output callback size is unsupported: \(physicalFrames) frames")
        }
        inputLayout = VirtualOutputHAL.channels(physical, scope: kAudioObjectPropertyScopeInput)
        outputLayout = VirtualOutputHAL.channels(physical, scope: kAudioObjectPropertyScopeOutput)
        guard outputLayout.reduce(0,+) >= channelCount else { throw Failure("Physical output has fewer channels than its preferred layout") }
        do {
            let storage = try Storage(rate: rate, channels: channelCount, channelMap: channelMap); self.storage = storage
            pump = try Pump(device: virtual, rate: rate, channels: channelCount, storage: storage)
            let progress = progress
            let creationStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProc, physical, nil, { _, _, _, output, _ in
                _ = vs_playback_render(storage.pointer, output)
                if vs_playback_healthy(storage.pointer) != 0 { progress.advance() }
            })
            guard creationStatus == noErr else { throw Failure("Could not create output callback", status: creationStatus) }
            guard let ioProc else { throw Failure("Output callback creation returned no IOProc") }
            guard VirtualOutputHAL.isolatePhysicalOutputInput(physical, ioProc: ioProc) else {
                throw Failure("Could not verify physical input isolation", issue: .privacyUnverified)
            }
            let startStatus = AudioDeviceStart(physical, ioProc)
            guard startStatus == noErr else { throw Failure("Could not start physical output", status: startStatus) }
            ioStarted = true
            for _ in 0..<20 {
                if progress.cycles > 0 { return }; Thread.sleep(forTimeInterval: 0.05)
            }
            throw Failure("Playback output is not rendering")
        } catch { stop(); throw error }
    }
    func configurationIsCurrent() -> Bool {
        var alive: UInt32 = 0, actual: Float64 = 0, frames: UInt32 = 0
        return VirtualOutputHAL.read(physical, kAudioDevicePropertyDeviceIsAlive, into: &alive) && alive != 0
            && VirtualOutputHAL.read(physical, kAudioDevicePropertyNominalSampleRate, into: &actual) && actual == rate
            && VirtualOutputHAL.read(physical, kAudioDevicePropertyBufferFrameSize, into: &frames) && frames > 0 && frames <= UInt32(VS_PACKET_FRAMES)
            && VirtualOutputHAL.channels(physical, scope: kAudioObjectPropertyScopeInput) == inputLayout
            && VirtualOutputHAL.channels(physical, scope: kAudioObjectPropertyScopeOutput) == outputLayout
            && VirtualOutputHAL.outputConfiguration(physical) == outputConfiguration
            && VirtualOutputHAL.outputChannelMap(physical, configuration: outputConfiguration) == outputChannelMap
            && VirtualOutputHAL.floatFormats(physical, scope: kAudioObjectPropertyScopeOutput)
    }
    func stop() {
        pump?.stop(); pump = nil
        if let ioProc {
            if ioStarted {
                let status = AudioDeviceStop(physical, ioProc)
                if status != noErr {
                    let message = Failure("Could not stop physical output", status: status).localizedDescription
                    Self.log.error("\(message, privacy: .public)")
                }
            }
            let status = AudioDeviceDestroyIOProcID(physical, ioProc)
            if status != noErr {
                let message = Failure("Could not destroy output callback", status: status).localizedDescription
                Self.log.error("\(message, privacy: .public)")
            }
        }
        ioStarted = false
        ioProc = nil; storage = nil
    }
    deinit { stop() }
    struct Failure: LocalizedError {
        let errorDescription: String?
        let issue: VirtualOutputSupport.Issue
        init(_ message: String, issue: VirtualOutputSupport.Issue = .setupFailed, status: OSStatus? = nil) {
            if let status {
                let code = UInt32(bitPattern: status)
                let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
                let printable = bytes.allSatisfy { (32...126).contains($0) }
                let detail = printable ? "'\(String(bytes: bytes, encoding: .ascii)!)'" : String(format: "0x%08X", code)
                errorDescription = "\(message) (OSStatus \(status), \(detail))"
            } else { errorDescription = message }
            self.issue = issue
        }
    }
}
