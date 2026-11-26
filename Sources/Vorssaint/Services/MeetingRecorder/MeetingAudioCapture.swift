// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import CoreAudio
import CoreAudioTapCompat
import Darwin
import Foundation

/// System-audio-capture TCC permission (`kTCCServiceAudioCapture`), required
/// by Core Audio process taps on macOS 14.4+. Without it, taps silently
/// deliver zeros rather than failing.
enum MeetingAudioPermission {
    enum State: Equatable {
        case granted, denied, undetermined, unavailable
    }

    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFn = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void
    private static let serviceName = "kTCCServiceAudioCapture"
    private static let tccPath = "/System/Library/PrivateFrameworks/TCC.framework/TCC"

    static func preflight() -> State {
        guard #available(macOS 14.4, *) else { return .unavailable }
        guard let handle = dlopen(tccPath, RTLD_NOW),
              let sym = dlsym(handle, "TCCAccessPreflight") else { return .unavailable }
        defer { dlclose(handle) }
        switch unsafeBitCast(sym, to: PreflightFn.self)(serviceName as CFString, nil) {
        case 0: return .granted
        case 1: return .denied
        case 2: return .undetermined
        default: return .unavailable
        }
    }

    static func request(completion: @escaping (Bool) -> Void) {
        if preflight() == .granted {
            DispatchQueue.main.async { completion(true) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard #available(macOS 14.4, *),
                  let handle = dlopen(tccPath, RTLD_NOW),
                  let sym = dlsym(handle, "TCCAccessRequest") else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            defer { dlclose(handle) }
            let requestFn = unsafeBitCast(sym, to: RequestFn.self)
            let semaphore = DispatchSemaphore(value: 0)
            final class Box: @unchecked Sendable { var granted = false }
            let box = Box()
            requestFn(serviceName as CFString, nil) { ok in
                box.granted = ok
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 60)
            let granted = box.granted
            DispatchQueue.main.async { completion(granted) }
        }
    }
}

/// Core Audio HAL property helpers shared by meeting detection and system tap
/// setup (no TCC permission needed for reading process input activity).
enum MeetingCoreAudio {
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func scalar<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, default fallback: T) -> T {
        var addr = address
        var size = UInt32(MemoryLayout<T>.size)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size,
                                                   alignment: MemoryLayout<T>.alignment)
        defer { raw.deallocate() }
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, raw) == noErr
            ? raw.load(as: T.self) : fallback
    }

    static func objectIDs(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var addr = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let ok = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0.baseAddress!) == noErr
        }
        return ok ? ids : []
    }

    static func string(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var addr = address
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var unmanaged: Unmanaged<CFString>?
        let ok = withUnsafeMutablePointer(to: &unmanaged) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0) == noErr
        }
        guard ok, let cf = unmanaged else { return nil }
        return cf.takeRetainedValue() as String
    }

    static func audioProcessObject(forPID pid: pid_t) -> AudioObjectID? {
        let processes = objectIDs(systemObject, address(kAudioHardwarePropertyProcessObjectList))
        for obj in processes where scalar(obj, address(kAudioProcessPropertyPID), default: pid_t(-1)) == pid {
            return obj
        }
        return nil
    }

    /// Returns all audio process objects owned by `pid` (including browser or
    /// Electron helper processes whose responsible app is `pid`), excluding
    /// Vorssaint itself.
    static func audioProcessObjects(forPID pid: pid_t, excludingPID ownPID: pid_t = getpid()) -> [AudioObjectID] {
        let targetAppPID = ResponsibleProcess.regularAppOwnerPid(of: pid) ?? pid
        return objectIDs(systemObject, address(kAudioHardwarePropertyProcessObjectList)).filter { obj in
            let owner: pid_t = scalar(obj, address(kAudioProcessPropertyPID), default: pid_t(-1))
            guard owner > 0, owner != ownPID else { return false }
            if owner == pid || owner == targetAppPID { return true }
            return ResponsibleProcess.regularAppOwnerPid(of: owner) == targetAppPID
        }
    }

    static func isAnyOtherProcessPlayingAudio(excludingPID ownPID: pid_t = getpid()) -> Bool {
        for obj in objectIDs(systemObject, address(kAudioHardwarePropertyProcessObjectList)) {
            let pid: pid_t = scalar(obj, address(kAudioProcessPropertyPID), default: pid_t(-1))
            guard pid > 0, pid != ownPID else { continue }
            if scalar(obj, address(kAudioProcessPropertyIsRunningOutput), default: UInt32(0)) != 0 {
                return true
            }
        }
        return false
    }

    /// Computes peak magnitude across all Float32 PCM buffers in `buffer`,
    /// handling both interleaved and non-interleaved layouts (`floatChannelData`
    /// is nil for interleaved buffers on macOS).
    static func peakFloatSample(in buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.format.commonFormat == .pcmFormatFloat32 else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        var peak: Float = 0
        for audioBuf in list {
            guard let data = audioBuf.mData else { continue }
            let count = Int(audioBuf.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            for i in 0..<count {
                let v = abs(samples[i])
                if v > peak { peak = v }
            }
        }
        return peak
    }

    static func defaultInputDeviceName() -> String? {
        let device: AudioDeviceID = scalar(systemObject,
                                           address(kAudioHardwarePropertyDefaultInputDevice),
                                           default: AudioDeviceID(0))
        guard device != 0 else { return nil }
        return string(device, address(kAudioObjectPropertyName))
    }

    static func activeMicConsumers() -> [MeetingMicConsumer] {
        objectIDs(systemObject, address(kAudioHardwarePropertyProcessObjectList)).compactMap { proc in
            guard scalar(proc, address(kAudioProcessPropertyIsRunningInput), default: UInt32(0)) != 0 else {
                return nil
            }
            let pid: pid_t = scalar(proc, address(kAudioProcessPropertyPID), default: pid_t(-1))
            let bundle = string(proc, address(kAudioProcessPropertyBundleID)) ?? "(unknown)"
            return MeetingMicConsumer(pid: pid, bundleID: bundle)
        }
    }
}

/// Captures system audio output (global excluding Vorssaint, or per-app
/// mixdown) to a Float32 PCM WAV via a Core Audio process tap + private
/// aggregate device. Supports pause/resume and quiet in-place `kick()` rebuild.
final class MeetingSystemAudioRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case unsupportedOS, tap, format, aggregate, ioProc, start

        var errorDescription: String? {
            switch self {
            case .unsupportedOS: return "System audio capture requires macOS 14.4 or later."
            case .tap: return "Could not create Core Audio process tap."
            case .format: return "Could not read system audio tap format."
            case .aggregate: return "Could not create private audio aggregate device."
            case .ioProc: return "Could not attach system audio IO handler."
            case .start: return "Could not start system audio capture device."
            }
        }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var format: AVAudioFormat?
    private var file: AVAudioFile?
    private var targetProcesses: [AudioObjectID] = []
    private let ioQueue = DispatchQueue(label: "com.vorssaint.utils.meeting.systemaudio.io")
    private var paused = false

    private(set) var peak: Float = 0
    private(set) var frameCount: Int64 = 0
    let levels = MeetingLevelHistory()

    func setPaused(_ value: Bool) {
        ioQueue.sync { paused = value }
    }

    /// Empty `processes` taps all system audio excluding Vorssaint itself;
    /// non-empty taps only those audio processes (per-app capture).
    func start(toFile url: URL, processes: [AudioObjectID] = []) throws {
        targetProcesses = processes
        let fmt = try buildTap()
        do {
            file = try AVAudioFile(forWriting: url, settings: fmt.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: fmt.isInterleaved)
            try startIO()
        } catch {
            stop()
            throw error
        }
    }

    private func buildTap() throws -> AVAudioFormat {
        guard #available(macOS 14.4, *) else { throw RecorderError.unsupportedOS }
        let mode: VorssaintTapMode
        let tapProcesses: [NSNumber]
        if targetProcesses.isEmpty {
            mode = .stereoGlobalExcluding
            if let ownObj = MeetingCoreAudio.audioProcessObject(forPID: getpid()) {
                tapProcesses = [NSNumber(value: ownObj)]
            } else {
                tapProcesses = []
            }
        } else {
            mode = .stereoMixdown
            tapProcesses = targetProcesses.map { NSNumber(value: $0) }
        }

        var createdTap = AudioObjectID(kAudioObjectUnknown)
        guard let tapUUID = createPrivateAudioTap(mode,
                                                  processes: tapProcesses,
                                                  deviceUID: nil,
                                                  name: "Vorssaint Meeting Tap",
                                                  muteBehavior: .unmuted,
                                                  id: &createdTap),
              createdTap != AudioObjectID(kAudioObjectUnknown) else {
            throw RecorderError.tap
        }
        tapID = createdTap

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var fmtAddr = MeetingCoreAudio.address(kAudioTapPropertyFormat)
        guard AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &size, &asbd) == noErr,
              let fmt = AVAudioFormat(streamDescription: &asbd) else {
            teardownTap()
            throw RecorderError.format
        }
        format = fmt

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vorssaint Meeting Tap Aggregate",
            kAudioAggregateDeviceUIDKey: "com.vorssaint.utils.meeting-tap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUUID.uuidString, kAudioSubTapDriftCompensationKey: true],
            ],
        ]
        var createdAggregate = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &createdAggregate) == noErr,
              createdAggregate != AudioObjectID(kAudioObjectUnknown) else {
            teardownTap()
            throw RecorderError.aggregate
        }
        aggregateID = createdAggregate
        return fmt
    }

    private func startIO() throws {
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) { [weak self] _, input, _, _, _ in
            guard let self, !self.paused, let fmt = self.format,
                  let buffer = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: input, deallocator: nil) else {
                return
            }
            let frames = Int(buffer.frameLength)
            let bufferPeak = MeetingCoreAudio.peakFloatSample(in: buffer)
            self.peak = max(self.peak, bufferPeak)
            self.levels.ingest(peak: bufferPeak, frames: frames, sampleRate: fmt.sampleRate)
            self.frameCount += Int64(frames)
            try? self.file?.write(from: buffer)
        }
        guard status == noErr else { throw RecorderError.ioProc }
        guard AudioDeviceStart(aggregateID, procID) == noErr else { throw RecorderError.start }
    }

    /// Quiet in-place rebuild for a wedged tap (health watchdog), keeping the
    /// same open WAV file when the stream format still matches.
    func kick() throws {
        guard file != nil else { return }
        let previousFormat = format
        teardownTap()
        let nextFormat = try buildTap()
        guard nextFormat == previousFormat else {
            teardownTap()
            throw RecorderError.format
        }
        try startIO()
    }

    func stop() {
        teardownTap()
        ioQueue.sync {
            file = nil
        }
    }

    private func teardownTap() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown), let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown), #available(macOS 14.4, *) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }
}

/// Records the microphone to a mono Float32 PCM WAV via `AVAudioEngine`,
/// surviving mid-recording device switches (built-in <-> AirPods) by fixing a
/// canonical file format and bridging incoming buffers through
/// `AVAudioConverter`, with optional Voice Processing echo cancellation and
/// 3-second delivery proof-of-life recovery.
final class MeetingMicRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var fileFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterRate: Double = 0
    private var observer: NSObjectProtocol?
    private var stopped = false
    private var restartAttempts = 0
    private var _frameCount: Int64 = 0
    private var _deliveredFrames: Int64 = 0
    private var paused = false
    private var _windowPeak: Float = 0
    private var _lastChangeAt = Date.distantPast
    private var deliveryGeneration = 0
    private let echoCancellation: Bool

    let levels = MeetingLevelHistory()

    init(echoCancellation: Bool = true) {
        self.echoCancellation = echoCancellation
    }

    var frameCount: Int64 {
        lock.lock(); defer { lock.unlock() }
        return _frameCount
    }

    var secondsSinceDeviceChange: Double {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(_lastChangeAt)
    }

    func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        lock.unlock()
    }

    func consumeWindowPeakDb() -> Double {
        lock.lock()
        let peak = _windowPeak
        _windowPeak = 0
        lock.unlock()
        return peak > 0 ? Double(20 * log10(peak)) : -120
    }

    func start(toFile url: URL) throws {
        if echoCancellation {
            _ = catchNSException {
                do {
                    try self.engine.inputNode.setVoiceProcessingEnabled(true)
                    self.engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration =
                        .init(enableAdvancedDucking: false, duckingLevel: .min)
                } catch {
                    // Non-fatal: continue recording unprocessed audio.
                }
            }
        }
        let hw = engine.inputNode.outputFormat(forBus: 0)
        let rate = hw.sampleRate > 0 ? hw.sampleRate : 48_000
        guard let canonical = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                            channels: 1, interleaved: false) else {
            throw NSError(domain: "com.vorssaint.utils.meeting", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Could not build microphone file format."])
        }
        file = try AVAudioFile(forWriting: url, settings: canonical.settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
        fileFormat = canonical
        stopped = false
        guard installTap() else {
            stop()
            throw NSError(domain: "com.vorssaint.utils.meeting", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone tap rejected by input device."])
        }
        do {
            try startEngine()
        } catch {
            stop()
            throw error
        }
        verifyDeliverySoon()
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.markDeviceChange()
            self?.restartAttempts = 0
            self?.handleConfigurationChange()
        }
    }

    func kick() {
        markDeviceChange()
        rebuildEngine()
        verifyDeliverySoon()
    }

    func stop() {
        lock.lock()
        stopped = true
        deliveryGeneration += 1
        lock.unlock()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        _ = catchNSException {
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
        }
        lock.lock()
        file = nil
        converter = nil
        lock.unlock()
    }

    // MARK: - Internals

    private func markDeviceChange() {
        lock.lock()
        _lastChangeAt = Date()
        lock.unlock()
    }

    private func verifyDeliverySoon(attempt: Int = 0) {
        lock.lock()
        deliveryGeneration += 1
        let generation = deliveryGeneration
        let baseline = _deliveredFrames
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stale = generation != self.deliveryGeneration
            let done = self.stopped
            let advanced = self._deliveredFrames > baseline
            self.lock.unlock()
            guard !stale, !done, !advanced, attempt < 5 else { return }
            self.rebuildEngine()
            self.verifyDeliverySoon(attempt: attempt + 1)
        }
    }

    private func rebuildEngine() {
        lock.lock()
        let done = stopped
        lock.unlock()
        guard !done else { return }
        _ = catchNSException {
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
        }
        guard installTap() else { return }
        try? startEngine()
    }

    private func installTap() -> Bool {
        let input = engine.inputNode
        let hw = input.outputFormat(forBus: 0)
        guard hw.sampleRate > 0, hw.channelCount > 0 else { return false }
        let exception = catchNSException {
            input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
                self?.append(buffer)
            }
        }
        return exception == nil
    }

    private func startEngine() throws {
        var swiftError: Error?
        let exception = catchNSException {
            do { try self.engine.start() } catch { swiftError = error }
        }
        if let exception {
            throw NSError(domain: "com.vorssaint.utils.meeting", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone engine rejected start: \(exception)"])
        }
        if let swiftError { throw swiftError }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, let file, let fileFormat else { return }
        _deliveredFrames += Int64(buffer.frameLength)
        if paused { return }
        let bufferPeak = Self.peakAcrossChannels(buffer)
        _windowPeak = max(_windowPeak, bufferPeak)
        levels.ingest(peak: bufferPeak, frames: Int(buffer.frameLength),
                      sampleRate: buffer.format.sampleRate)
        guard let mono = buffer.format.channelCount == 1 ? buffer : Self.mixToMono(buffer) else { return }
        let rate = mono.format.sampleRate
        if rate == fileFormat.sampleRate {
            _frameCount += Int64(mono.frameLength)
            try? file.write(from: mono)
            return
        }
        if converter == nil || converterRate != rate {
            converter = AVAudioConverter(from: mono.format, to: fileFormat)
            converterRate = rate
        }
        guard let converter, let out = Self.convert(mono, with: converter, to: fileFormat) else { return }
        _frameCount += Int64(out.frameLength)
        try? file.write(from: out)
    }

    private static func peakAcrossChannels(_ buffer: AVAudioPCMBuffer) -> Float {
        MeetingCoreAudio.peakFloatSample(in: buffer)
    }

    private static func mixToMono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        guard channels > 1, frames > 0,
              let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: buffer.format.sampleRate,
                                             channels: 1, interleaved: false),
              let out = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(frames)),
              let dst = out.floatChannelData?[0] else { return nil }
        let scale = 1 / Float(channels)
        if buffer.format.isInterleaved {
            let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            guard let raw = list.first?.mData else { return nil }
            let src = raw.assumingMemoryBound(to: Float.self)
            for i in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels { sum += src[i * channels + c] }
                dst[i] = sum * scale
            }
        } else if let data = buffer.floatChannelData {
            for i in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels { sum += data[c][i] }
                dst[i] = sum * scale
            }
        } else {
            return nil
        }
        out.frameLength = AVAudioFrameCount(frames)
        return out
    }

    private static func convert(_ buffer: AVAudioPCMBuffer,
                                with converter: AVAudioConverter,
                                to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) else { return nil }
        var served = false
        let status = converter.convert(to: out, error: nil) { _, outStatus in
            if served { outStatus.pointee = .noDataNow; return nil }
            served = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { return nil }
        return out
    }

    private func handleConfigurationChange() {
        lock.lock()
        let done = stopped
        lock.unlock()
        guard !done else { return }
        _ = catchNSException { self.engine.inputNode.removeTap(onBus: 0) }
        let hw = engine.inputNode.outputFormat(forBus: 0)
        guard hw.sampleRate > 0, hw.channelCount > 0, installTap() else {
            restartAttempts += 1
            if restartAttempts <= 40 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.handleConfigurationChange()
                }
            }
            return
        }
        restartAttempts = 0
        if (try? startEngine()) != nil {
            verifyDeliverySoon()
        }
    }
}

/// Records system audio + microphone together for one meeting into separate
/// WAV files (`<stem>-system.wav` and `<stem>-mic.wav`). Either side may fail
/// without aborting the session; throws only when both fail.
final class MeetingCaptureSession: @unchecked Sendable {
    struct Result: Sendable {
        let stem: String
        let systemAudioURL: URL?
        let micAudioURL: URL?
        let detectedApp: String?
        let systemCaptured: Bool
        let micCaptured: Bool
    }

    let stem: String
    let detectedApp: String?
    let systemFileURL: URL
    let micFileURL: URL

    private let detectedPID: pid_t?
    private let perApp: Bool
    private let system = MeetingSystemAudioRecorder()
    private let mic: MeetingMicRecorder

    private(set) var systemRunning = false
    private(set) var micRunning = false
    private(set) var systemError: String?
    private(set) var micError: String?

    var micLevels: MeetingLevelHistory { mic.levels }
    var systemLevels: MeetingLevelHistory { system.levels }
    var micSecondsSinceDeviceChange: Double { mic.secondsSinceDeviceChange }

    init(stem: String,
         detectedApp: String?,
         detectedPID: pid_t? = nil,
         outputDir: URL,
         perApp: Bool = false,
         echoCancellation: Bool = true) {
        self.stem = stem
        self.detectedApp = detectedApp
        self.detectedPID = detectedPID
        self.perApp = perApp
        self.mic = MeetingMicRecorder(echoCancellation: echoCancellation)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        systemFileURL = outputDir.appendingPathComponent("\(stem)-system.wav")
        micFileURL = outputDir.appendingPathComponent("\(stem)-mic.wav")
    }

    func start() throws {
        var processes: [AudioObjectID] = []
        if perApp, let pid = resolvedTargetPID() {
            processes = MeetingCoreAudio.audioProcessObjects(forPID: pid)
        }

        do {
            try system.start(toFile: systemFileURL, processes: processes)
            systemRunning = true
        } catch {
            if !processes.isEmpty {
                system.stop()
                do {
                    try system.start(toFile: systemFileURL)
                    systemRunning = true
                } catch {
                    systemError = error.localizedDescription
                }
            } else {
                systemError = error.localizedDescription
            }
        }

        do {
            try mic.start(toFile: micFileURL)
            micRunning = true
        } catch {
            micError = error.localizedDescription
            if !systemRunning {
                cleanupUnusedFiles()
                throw error
            }
        }
    }

    func setPaused(_ value: Bool) {
        if systemRunning { system.setPaused(value) }
        if micRunning { mic.setPaused(value) }
    }

    func consumeMicWindowPeakDb() -> Double {
        micRunning ? mic.consumeWindowPeakDb() : -120
    }

    func kickMic() {
        guard micRunning else { return }
        mic.kick()
    }

    @discardableResult
    func kickSystem() -> Bool {
        guard systemRunning else { return false }
        return (try? system.kick()) != nil
    }

    @discardableResult
    func stop() -> Result {
        if systemRunning { system.stop() }
        if micRunning { mic.stop() }
        cleanupUnusedFiles()
        return Result(
            stem: stem,
            systemAudioURL: systemRunning ? systemFileURL : nil,
            micAudioURL: micRunning ? micFileURL : nil,
            detectedApp: detectedApp,
            systemCaptured: systemRunning,
            micCaptured: micRunning
        )
    }

    func discard() {
        if systemRunning { system.stop() }
        if micRunning { mic.stop() }
        try? FileManager.default.removeItem(at: systemFileURL)
        try? FileManager.default.removeItem(at: micFileURL)
    }

    private func cleanupUnusedFiles() {
        if !systemRunning { try? FileManager.default.removeItem(at: systemFileURL) }
        if !micRunning { try? FileManager.default.removeItem(at: micFileURL) }
    }

    private func resolvedTargetPID() -> pid_t? {
        if let detectedPID, detectedPID > 0 { return detectedPID }
        guard let detectedApp else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.caseInsensitiveCompare(detectedApp) == .orderedSame
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(detectedApp) ?? false)
        }?.processIdentifier
    }
}
