// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AVFoundation
import CoreAudio
import Darwin

/// A flag the audio thread raises and another thread reads later.
final class RecorderAudioFlag {
    private var bits: Int32 = 0

    var value: Bool { OSAtomicAdd32Barrier(0, &bits) != 0 }

    func raise() {
        OSAtomicCompareAndSwap32Barrier(0, 1, &bits)
    }
}

/// Whether linear float audio holds anything but silence.
enum RecorderAudioProbe {
    static func containsSound(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              stream.mFormatID == kAudioFormatLinearPCM,
              stream.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              stream.mBitsPerChannel == 32
        else { return false }
        let heard = try? sampleBuffer.withAudioBufferList(blockBufferMemoryAllocator: nil,
                                                          flags: []) { list, _ in
            list.contains { containsSound($0) }
        }
        return heard ?? false
    }

    /// One vectorised pass and no allocation, so the audio thread can ask.
    static func containsSound(_ buffer: AudioBuffer) -> Bool {
        guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { return false }
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return false }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
        return peak > 0
    }
}

/// The sound of the Mac for a recording, read from the audio system as one
/// mix of every process but this one.
///
/// ScreenCaptureKit hands over the same mix, but an app the volume mixer
/// adjusts reaches it twice: its own muted stream and this app's re-render
/// of it, about 30 ms apart, and excluding this app from the stream's filter
/// does not drop that re-render (measured 2026-09-01, issue #692). A process
/// tap that excludes this process hears each app once.
///
/// Reading a tap needs an audio permission of its own. It is asked for at
/// the first start and, while missing, answered with silence rather than an
/// error, so the session keeps the stream's sound as the written source until
/// this tap has heard sound over a whole recording.
///
/// The tap's stereo mixdown loses level on outputs with more than two
/// channels, which `followProcesses` gives back.
///
/// Every mutable field is touched only on `queue`, except `heard` and
/// `levelCompensation`, which are atomic, and `onSample`, which the caller
/// sets once before `start`. That confinement is what makes the reference
/// safe to hand across threads.
final class RecorderSystemAudioTap: @unchecked Sendable {
    /// Called on the audio system's own thread, with the sound retimed onto
    /// the recording's clock. Set before `start`.
    var onSample: ((CMSampleBuffer) -> Void)?

    /// Called on this tap's own queue when an output device change left it
    /// without a reader, so the recording can go back to the stream's sound
    /// instead of falling silent. Set before `start`.
    var onReaderLost: (() -> Void)?

    /// Whether any sample was more than silence. Read after `stop`.
    var heardSound: Bool { heard.value }

    private let queue: DispatchQueue
    private let heard = RecorderAudioFlag()
    private let ownProcess: AudioObjectID
    private let tapID: AudioObjectID
    private let tapUID: String
    private let tapChannels: Int
    private var clock: CMClock?
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var hostDeviceUID: String?
    private var sampleRate: Double = 0
    /// Name the default output and sample rate listeners. See
    /// `AudioListenerClients`.
    private var deviceListenerClient: UnsafeMutableRawPointer?
    private var rateListenerClient: UnsafeMutableRawPointer?
    private var stopped = false
    /// What the mixdown took from the sound, given back to every sample.
    private let levelCompensation = AtomicFloatBox(1)
    private var levelWatch: LevelCompensationWatch?

    /// Destroying a device or a tap can park inside a broken audio path, so
    /// it never happens on a queue anything waits for. Serial, so the device
    /// that hosts a tap is always gone before the tap itself.
    private static let teardownQueue = DispatchQueue(label: "com.vorssaint.recorder.systemaudio.teardown",
                                                     qos: .utility)
    /// The global listener must not wait behind a device destruction that
    /// can remain stuck for the rest of the session.
    private static let listenerQueue = DispatchQueue(label: "com.vorssaint.recorder.systemaudio.listeners",
                                                     qos: .utility)

    /// The tap, or nothing when the audio system refuses one.
    static func make() async -> RecorderSystemAudioTap? {
        guard #available(macOS 14.4, *) else { return nil }
        let queue = DispatchQueue(label: "com.vorssaint.recorder.systemaudio",
                                  qos: .userInitiated)
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: RecorderSystemAudioTap(queue: queue))
            }
        }
    }

    @available(macOS 14.4, *)
    private init?(queue: DispatchQueue) {
        self.queue = queue
        guard let ownProcess = Self.ownProcessObject() else { return nil }
        self.ownProcess = ownProcess
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcess])
        description.name = "Vorssaint Recorder"
        description.isPrivate = true
        var tapID = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else {
            return nil
        }
        self.tapID = tapID
        tapUID = description.uuid.uuidString
        var format = AudioStreamBasicDescription()
        tapChannels = Self.read(tapID, kAudioTapPropertyFormat, &format) && format.mChannelsPerFrame > 0
            ? Int(format.mChannelsPerFrame)
            : 2
    }

    deinit {
        // A stopped tap's ID may already belong to another tap.
        let tapID = stopped ? 0 : self.tapID
        let aggregateID = self.aggregateID
        let ioProc = self.ioProc
        levelWatch?.stop()
        Self.removeListener(deviceListenerClient, from: AudioObjectID(kAudioObjectSystemObject),
                            kAudioHardwarePropertyDefaultOutputDevice)
        Self.removeListener(rateListenerClient, from: aggregateID, kAudioDevicePropertyNominalSampleRate)
        Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: tapID)
    }

    // MARK: - Lifecycle

    /// Starts delivering and answers whether a reader is now running. The
    /// first start on a Mac may raise the system's audio permission prompt;
    /// until it is granted, the reader runs but every buffer is silent.
    /// A false answer means no reader exists, so its sound must come from
    /// elsewhere for this recording.
    @discardableResult
    func start(synchronizingTo clock: CMClock) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                self.clock = clock
                if !stopped {
                    // Read before the first cycle, so the head of the file
                    // already has its level.
                    followProcesses()
                    buildPipeline()
                    watchDefaultOutputDevice()
                }
                continuation.resume(returning: aggregateID != 0)
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                // Cancelling startup stops the tap there and again when the
                // session finishes. The HAL may already have reused its ID.
                guard !stopped else { continuation.resume(); return }
                stopped = true
                Self.removeListener(deviceListenerClient, from: AudioObjectID(kAudioObjectSystemObject),
                                    kAudioHardwarePropertyDefaultOutputDevice)
                deviceListenerClient = nil
                levelWatch?.stop()
                levelWatch = nil
                teardownPipeline()
                Self.destroy(aggregateID: 0, ioProc: nil, tapID: tapID)
                continuation.resume()
            }
        }
    }

    // MARK: - Pipeline

    /// The tap needs an aggregate device to be read through, and that device
    /// needs a real one beneath it for its clock: the default output, as the
    /// volume mixer does.
    private func buildPipeline() {
        guard aggregateID == 0, let clock,
              let hostUID = Self.hostDeviceUID() else { return }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vorssaint Recorder",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: hostUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: hostUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        var aggregateID = AudioObjectID(0)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0 else { return }
        let sampleRate = Self.nominalSampleRate(of: aggregateID)
        guard let format = Self.format(sampleRate: sampleRate, channels: tapChannels) else {
            Self.destroy(aggregateID: aggregateID, ioProc: nil, tapID: 0)
            return
        }

        // The audio thread touches only these captured values, never the
        // engine object, matching the mixer's realtime discipline.
        let channels = tapChannels
        let heard = self.heard
        let onSample = self.onSample
        let compensation = levelCompensation
        let ramp = TapLevelRamp()
        let limiter = LimiterState(release: BoostLimiter.release(sampleRate: sampleRate))
        let timescale = CMTimeScale(sampleRate.rounded())
        let hostClock = CMClockGetHostTimeClock()
        var ioProc: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) {
            now, input, inputTime, output, _ in
            // The device beneath the aggregate would otherwise play whatever
            // this memory last held.
            MixerRender.silence(UnsafeMutableAudioBufferListPointer(output))
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let index = MixerRender.tapBufferIndex(in: inputBuffers, tapChannels: channels)
            else { return }
            let buffer = inputBuffers[index]
            if !heard.value, RecorderAudioProbe.containsSound(buffer) { heard.raise() }
            guard let onSample else { return }
            let hostTime = inputTime.pointee.mFlags.contains(.hostTimeValid)
                ? CMClockMakeHostTimeFromSystemUnits(inputTime.pointee.mHostTime)
                : CMClockGetTime(hostClock)
            let time = CMSyncConvertTime(hostTime, from: hostClock, to: clock)
            guard time.isValid,
                  let sample = Self.sampleBuffer(from: buffer, format: format,
                                                 timescale: timescale, time: time)
            else { return }
            // Eased as in the mixer, so a change never steps the level.
            let gain = ramp.next(toward: compensation.value, hostTime: now.pointee.mHostTime)
            if gain > 1 {
                Self.withSamples(of: sample) { samples, count in
                    RecorderSupport.restoreTapLevel(samples, count: count, channels: channels,
                                                    gain: gain, limiter: &limiter.limiter,
                                                    release: limiter.release)
                }
            } else {
                // Peaks held from an earlier stretch must not turn down the
                // next one, which starts from the sound it brings.
                limiter.limiter = BoostLimiter()
            }
            onSample(sample)
        }
        guard created == noErr, let ioProc,
              AudioDeviceStart(aggregateID, ioProc) == noErr else {
            Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: 0)
            return
        }
        self.aggregateID = aggregateID
        self.ioProc = ioProc
        hostDeviceUID = hostUID
        self.sampleRate = sampleRate
        watchSampleRate(of: aggregateID)
    }

    private func teardownPipeline() {
        let aggregateID = self.aggregateID
        let ioProc = self.ioProc
        let rateListenerClient = self.rateListenerClient
        self.aggregateID = 0
        self.ioProc = nil
        self.rateListenerClient = nil
        hostDeviceUID = nil
        guard aggregateID != 0 else { return }
        if let ioProc {
            AudioDeviceStop(aggregateID, ioProc)
        }
        Self.removeListener(rateListenerClient, from: aggregateID, kAudioDevicePropertyNominalSampleRate)
        Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: 0)
    }

    /// Headphones that come and go, or a device that changes its rate for a
    /// call, would otherwise leave the rest of the recording silent or at
    /// the wrong pitch. Only a real change rebuilds, so the notifications a
    /// rebuild itself raises settle instead of looping.
    private func rebuildPipelineIfChanged() {
        guard !stopped, aggregateID != 0 else { return }
        let hostChanged = Self.hostDeviceUID() != hostDeviceUID
        let rateChanged = Self.nominalSampleRate(of: aggregateID) != sampleRate
        guard hostChanged || rateChanged else { return }
        teardownPipeline()
        buildPipeline()
        // Nothing came back, and with no aggregate left this tap can no longer
        // see a later change, so the rest of the recording needs the stream.
        if aggregateID == 0 { onReaderLost?() }
    }

    private func watchDefaultOutputDevice() {
        guard deviceListenerClient == nil else { return }
        deviceListenerClient = listen(to: AudioObjectID(kAudioObjectSystemObject),
                                      kAudioHardwarePropertyDefaultOutputDevice)
    }

    private func watchSampleRate(of aggregateID: AudioObjectID) {
        rateListenerClient = listen(to: aggregateID, kAudioDevicePropertyNominalSampleRate)
    }

    /// Registers `pipelineDeviceChanged` for one property under a client
    /// number, or nothing when the HAL refuses.
    private func listen(to object: AudioObjectID,
                        _ selector: AudioObjectPropertySelector) -> UnsafeMutableRawPointer? {
        let client = AudioListenerClients.reserve(for: self)
        var address = Self.address(selector)
        guard AudioObjectAddPropertyListener(object, &address, Self.pipelineDeviceChanged,
                                             client) == noErr else {
            AudioListenerClients.forget(client)
            return nil
        }
        return client
    }

    /// The default output and the aggregate's rate ask the same question: is
    /// the tap still read through the device the sound plays on.
    private static let pipelineDeviceChanged: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let tap = AudioListenerClients.owner(of: client) as? RecorderSystemAudioTap else {
            return noErr
        }
        tap.queue.async { [weak tap] in tap?.rebuildPipelineIfChanged() }
        return noErr
    }

    /// Forgets the client at once, so a callback on its way finds nothing,
    /// and gives the global registration back independently of device
    /// destruction. A rate listener still goes on the teardown queue ahead
    /// of the aggregate it listens to.
    private static func removeListener(_ client: UnsafeMutableRawPointer?, from object: AudioObjectID,
                                       _ selector: AudioObjectPropertySelector) {
        guard let client else { return }
        AudioListenerClients.forget(client)
        let removalQueue = object == AudioObjectID(kAudioObjectSystemObject)
            ? listenerQueue
            : teardownQueue
        removalQueue.async {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListener(object, &address, Self.pipelineDeviceChanged, client)
        }
    }

    // MARK: - Level

    /// Keeps the level the tap gives back right for where every other
    /// process plays.
    ///
    /// The stereo mixdown divides what a process plays on an output with more
    /// than two channels by that output's channel pairs, a known system issue
    /// (FB13479345), so a recording made with a TV over HDMI or an audio
    /// interface as the output came out at a half or a quarter of its level.
    /// The mix holds every process wherever it plays (measured 2026-10-07:
    /// two apps on two outputs, neither of them the default, both reached it
    /// whole), so the correction is read from all of them, and the narrowest
    /// output decides, as in the mixer: no process is ever recorded louder
    /// than it plays. One gain cannot suit outputs of different widths at
    /// once, so while an app holds a narrower output, the rest keeps the
    /// level it had before this correction. The watch follows processes that
    /// come or go, since a video started during the recording can play
    /// through one the first read never saw.
    private func followProcesses() {
        guard !stopped, levelWatch == nil else { return }
        let compensation = levelCompensation
        let watch = LevelCompensationWatch.started(everyProcessExcept: [ownProcess]) {
            compensation.value = $0
        }
        // Briefly, as the mixer's engines do, so the head of the file
        // already has its level.
        watch.waitForFirstRead()
        levelWatch = watch
    }

    private static func destroy(aggregateID: AudioObjectID,
                                ioProc: AudioDeviceIOProcID?,
                                tapID: AudioObjectID) {
        guard aggregateID != 0 || tapID != 0 else { return }
        teardownQueue.async {
            if aggregateID != 0 {
                if let ioProc {
                    AudioDeviceDestroyIOProcID(aggregateID, ioProc)
                }
                AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            if tapID != 0, #available(macOS 14.4, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }

    // MARK: - Samples

    /// The limiter's memory, touched only on the audio thread.
    private final class LimiterState {
        var limiter = BoostLimiter()
        let release: Float

        init(release: Float) {
            self.release = release
        }
    }

    /// The samples a buffer just made holds, to change in place before anyone
    /// else sees them.
    private static func withSamples(of sampleBuffer: CMSampleBuffer,
                                    _ body: (UnsafeMutablePointer<Float>, Int) -> Void) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var data: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &length,
                                          totalLengthOut: nil,
                                          dataPointerOut: &data) == kCMBlockBufferNoErr,
              let data else { return }
        let count = length / MemoryLayout<Float>.size
        data.withMemoryRebound(to: Float.self, capacity: count) { body($0, count) }
    }

    private static func format(sampleRate: Double, channels: Int) -> CMAudioFormatDescription? {
        guard sampleRate > 0, channels > 0 else { return nil }
        let bytesPerFrame = UInt32(channels * MemoryLayout<Float>.size)
        var stream = AudioStreamBasicDescription(mSampleRate: sampleRate,
                                                 mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagIsFloat
                                                     | kAudioFormatFlagIsPacked,
                                                 mBytesPerPacket: bytesPerFrame,
                                                 mFramesPerPacket: 1,
                                                 mBytesPerFrame: bytesPerFrame,
                                                 mChannelsPerFrame: UInt32(channels),
                                                 mBitsPerChannel: 32,
                                                 mReserved: 0)
        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                             asbd: &stream,
                                             layoutSize: 0,
                                             layout: nil,
                                             magicCookieSize: 0,
                                             magicCookie: nil,
                                             extensions: nil,
                                             formatDescriptionOut: &description) == noErr
        else { return nil }
        return description
    }

    /// The samples copied out of the audio system's buffer, which is reused
    /// as soon as this cycle returns.
    private static func sampleBuffer(from buffer: AudioBuffer,
                                     format: CMAudioFormatDescription,
                                     timescale: CMTimeScale,
                                     time: CMTime) -> CMSampleBuffer? {
        let frames = MixerRender.frames(bytes: buffer.mDataByteSize, channels: buffer.mNumberChannels)
        guard frames > 0 else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: timescale),
                                        presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                   dataBuffer: nil,
                                   dataReady: false,
                                   makeDataReadyCallback: nil,
                                   refcon: nil,
                                   formatDescription: format,
                                   sampleCount: frames,
                                   sampleTimingEntryCount: 1,
                                   sampleTimingArray: &timing,
                                   sampleSizeEntryCount: 0,
                                   sampleSizeArray: nil,
                                   sampleBufferOut: &sampleBuffer) == noErr,
              let sampleBuffer
        else { return nil }
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: &list) == noErr
        else { return nil }
        return sampleBuffer
    }

    // MARK: - Audio system

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID,
                                _ selector: AudioObjectPropertySelector,
                                _ value: inout T,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }

    private static func ownProcessObject() -> AudioObjectID? {
        var pid = ProcessInfo.processInfo.processIdentifier
        var object = AudioObjectID(0)
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<pid_t>.size), pidPointer,
                                       &size, &object)
        }
        guard status == noErr, object != 0 else { return nil }
        return object
    }

    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double {
        var sampleRate: Float64 = 0
        guard read(deviceID, kAudioDevicePropertyNominalSampleRate, &sampleRate), sampleRate > 0
        else { return 48_000 }
        return sampleRate
    }

    /// The device that clocks the aggregate: the current default output, the
    /// same choice the volume mixer makes. A device that also records puts
    /// its input in front of the tap in the buffer list, which the shared
    /// `MixerRender.tapBufferIndex` already steps over.
    private static func hostDeviceUID() -> String? {
        var defaultDevice = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject),
                   kAudioHardwarePropertyDefaultOutputDevice, &defaultDevice),
              defaultDevice != 0 else { return nil }
        var uid: CFString = "" as CFString
        guard read(defaultDevice, kAudioDevicePropertyDeviceUID, &uid) else { return nil }
        return uid as String
    }
}
