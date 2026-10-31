// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint Audio contributors
import CoreAudio
import Foundation
import Darwin
import SoftwareVolumePCM
import os

/// Output-only playback. PCM property calls never execute on the audio thread.
final class VirtualOutputBridge {
    final class Progress {
        private var count: Int64 = 0
        var cycles: Int64 { OSAtomicAdd64Barrier(0, &count) }
        func advance() { OSAtomicIncrement64Barrier(&count) }
    }
    private final class Storage {
        let pointer: UnsafeMutableRawPointer
        init(rate: Double) throws {
            guard let pointer = vs_playback_create() else { throw Failure("Could not allocate playback buffer") }
            self.pointer = pointer
            vs_playback_rate(pointer, rate)
        }
        deinit { vs_playback_destroy(pointer) }
    }
    private final class Pump {
        private let device: AudioObjectID
        private let rate: Double
        private let storage: Storage
        private let key: Data
        private var generation: UInt64 = 0
        private var cursor: UInt64 = 0
        private var nonce: UInt64 = 0
        private var timer: DispatchSourceTimer?
        private var lastPoll: CFAbsoluteTime = 0
        private var largestGap: Double = 0
        private var lastReport: CFAbsoluteTime = 0
        private static let log = Logger(subsystem: "com.vorssaint.utils", category: "output-pcm")
        init(device: AudioObjectID, rate: Double, storage: Storage) throws {
            self.device = device; self.rate = rate; self.storage = storage
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
            guard status == noErr, let response else { return false }
            let data = response.takeRetainedValue()
            guard CFGetTypeID(data) == CFDataGetTypeID() else { return false }
            var header = VSPacket()
            guard vs_packet_validate(CFDataGetBytePtr(data), CFDataGetLength(data), nonce, generation, cursor, rate, &header) != 0 else { return false }
            vs_playback_push(storage.pointer, CFDataGetBytePtr(data), CFDataGetLength(data))
            generation = header.generation; cursor = header.next
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
    private var physical = AudioObjectID(0)
    private var rate: Float64 = 0
    private var inputLayout: [UInt32] = []
    private var outputLayout: [UInt32] = []
    private var pump: Pump?
    private var storage: Storage?

    init(virtual: AudioObjectID, physicalUID: String) throws {
        self.physicalUID = physicalUID
        guard let uid = VirtualOutputHAL.uid(virtual), uid == VirtualOutputSupport.deviceUID,
              VirtualOutputHAL.channels(virtual, scope: kAudioObjectPropertyScopeInput).isEmpty,
              VirtualOutputHAL.channels(virtual, scope: kAudioObjectPropertyScopeOutput) == [2] else {
            throw Failure("Output-only software volume component is required", issue: .privacyUnverified)
        }
        guard let physical = VirtualOutputHAL.device(physicalUID),
              VirtualOutputHAL.read(physical, kAudioDevicePropertyNominalSampleRate, into: &rate), rate.isFinite, rate > 0 else {
            throw Failure("Physical output is unavailable", issue: .outputUnavailable)
        }
        self.physical = physical
        guard VirtualOutputHAL.write(virtual, kAudioDevicePropertyNominalSampleRate, value: rate) == noErr else {
            throw Failure("Could not match the virtual output sample rate")
        }
        var virtualRate: Float64 = 0
        for _ in 0..<30 {
            _ = VirtualOutputHAL.read(virtual, kAudioDevicePropertyNominalSampleRate, into: &virtualRate)
            if virtualRate == rate { break }; Thread.sleep(forTimeInterval: 0.1)
        }
        guard virtualRate == rate, VirtualOutputHAL.floatFormats(physical, scope: kAudioObjectPropertyScopeOutput) else {
            throw Failure("Physical output format is unsupported")
        }
        var physicalFrames: UInt32 = 0
        guard VirtualOutputHAL.read(physical, kAudioDevicePropertyBufferFrameSize, into: &physicalFrames),
              physicalFrames > 0, physicalFrames <= UInt32(VS_PACKET_FRAMES) else {
            throw Failure("Physical output callback size is unsupported")
        }
        inputLayout = VirtualOutputHAL.channels(physical, scope: kAudioObjectPropertyScopeInput)
        outputLayout = VirtualOutputHAL.channels(physical, scope: kAudioObjectPropertyScopeOutput)
        guard outputLayout.reduce(0,+) >= 2 else { throw Failure("Stereo physical output is required") }
        do {
            let storage = try Storage(rate: rate); self.storage = storage
            pump = try Pump(device: virtual, rate: rate, storage: storage)
            let progress = progress
            guard AudioDeviceCreateIOProcIDWithBlock(&ioProc, physical, nil, { _, _, _, output, _ in
                _ = vs_playback_render(storage.pointer, output)
                if vs_playback_healthy(storage.pointer) != 0 { progress.advance() }
            }) == noErr, let ioProc else { throw Failure("Could not create output callback") }
            guard VirtualOutputHAL.isolatePhysicalOutputInput(physical, ioProc: ioProc) else {
                throw Failure("Could not verify physical input isolation", issue: .privacyUnverified)
            }
            guard AudioDeviceStart(physical, ioProc) == noErr else { throw Failure("Could not start physical output") }
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
            && VirtualOutputHAL.floatFormats(physical, scope: kAudioObjectPropertyScopeOutput)
    }
    func stop() {
        pump?.stop(); pump = nil
        if let ioProc { AudioDeviceStop(physical, ioProc); AudioDeviceDestroyIOProcID(physical, ioProc) }
        ioProc = nil; storage = nil
    }
    deinit { stop() }
    struct Failure: LocalizedError {
        let errorDescription: String?
        let issue: VirtualOutputSupport.Issue
        init(_ message: String, issue: VirtualOutputSupport.Issue = .setupFailed) {
            errorDescription = message; self.issue = issue
        }
    }
}
