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

    /// Marks a WAV file created by Meeting Recorder with an extended attribute
    /// so shared custom folders never list or trash unrelated user WAVs. When
    /// the destination filesystem or ACL forbids extended attributes, falls back
    /// to recording the file's `(device, inode)` identity in a local index so
    /// the recording stays visible in Recents and a replaced file is never
    /// trashed.
    private static let ownerXattrName = "com.vorssaint.meeting-recorder"
    private static let ownershipLock = NSLock()

    private static var ownershipIndexURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("Vorssaint", isDirectory: true)
            .appendingPathComponent("meeting-recorder-owned.json")
    }

    /// Returns true if any directory entry exists at `url` (including dangling
    /// symlinks and APFS case/Unicode-equivalent names).
    static func pathEntryExists(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0
    }

    /// Atomically reserves a brand-new regular file at `url` (`O_CREAT | O_EXCL |
    /// O_NOFOLLOW`), failing if any file or symlink already occupies that path,
    /// and returns its `(st_dev, st_ino)` identity.
    static func reserveExclusiveFile(_ url: URL) -> MeetingRecorderSupport.FileIdentity? {
        let fd = open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o644)
        guard fd >= 0 else { return nil }
        var st = stat()
        let ok = fstat(fd, &st) == 0
        close(fd)
        guard ok else { return nil }
        return MeetingRecorderSupport.FileIdentity(device: UInt64(bitPattern: Int64(st.st_dev)),
                                                   inode: UInt64(st.st_ino))
    }

    /// Returns `(st_dev, st_ino)` for a regular non-symlink file at `url`.
    static func regularFileIdentity(of url: URL) -> MeetingRecorderSupport.FileIdentity? {
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        return MeetingRecorderSupport.FileIdentity(device: UInt64(bitPattern: Int64(st.st_dev)),
                                                   inode: UInt64(st.st_ino))
    }

    static func markRecorderOwnedFile(_ url: URL) {
        var marker: UInt8 = 1
        if setxattr(url.path, ownerXattrName, &marker, 1, 0, XATTR_NOFOLLOW) == 0 {
            return
        }
        guard let identity = regularFileIdentity(of: url) else { return }
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        var map = loadOwnershipIndexLocked()
        map[url.standardizedFileURL.path] = identity
        saveOwnershipIndexLocked(map)
    }

    static func isRecorderOwnedFile(_ url: URL,
                                    expectedIdentity: MeetingRecorderSupport.FileIdentity? = nil) -> Bool {
        guard let current = regularFileIdentity(of: url) else { return false }
        if let expectedIdentity, current != expectedIdentity {
            return false
        }
        if getxattr(url.path, ownerXattrName, nil, 0, 0, XATTR_NOFOLLOW) >= 0 {
            return true
        }
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        let map = loadOwnershipIndexLocked()
        return map[url.standardizedFileURL.path] == current
    }

    static func forgetRecorderOwnedFile(_ url: URL) {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        var map = loadOwnershipIndexLocked()
        if map.removeValue(forKey: url.standardizedFileURL.path) != nil {
            saveOwnershipIndexLocked(map)
        }
    }

    private static func loadOwnershipIndexLocked() -> [String: MeetingRecorderSupport.FileIdentity] {
        guard let data = try? Data(contentsOf: ownershipIndexURL),
              let decoded = try? JSONDecoder().decode([String: MeetingRecorderSupport.FileIdentity].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveOwnershipIndexLocked(_ map: [String: MeetingRecorderSupport.FileIdentity]) {
        let url = ownershipIndexURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: url, options: .atomic)
        }
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

/// Monotonic active-elapsed recording clock shared across tracks so idle Core
/// Audio tap gaps are padded with matching silence while deliberate pauses are
/// excluded.
final class MeetingActiveClock: @unchecked Sendable {
    private let lock = NSLock()
    private var accumulated: Double = 0
    private var segmentStart: Double?
    private var paused = false

    func start() {
        lock.lock()
        accumulated = 0
        segmentStart = ProcessInfo.processInfo.systemUptime
        paused = false
        lock.unlock()
    }

    func setPaused(_ value: Bool) {
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        if value, !paused {
            if let start = segmentStart {
                accumulated += max(0, now - start)
            }
            segmentStart = nil
            paused = true
        } else if !value, paused {
            segmentStart = now
            paused = false
        }
        lock.unlock()
    }

    func activeElapsedSeconds() -> Double {
        lock.lock()
        defer { lock.unlock() }
        if paused { return accumulated }
        guard let start = segmentStart else { return accumulated }
        return accumulated + max(0, ProcessInfo.processInfo.systemUptime - start)
    }
}

/// Captures system audio output (global excluding Vorssaint, or per-app
/// mixdown) to a Float32 PCM WAV via a Core Audio process tap + private
/// aggregate device. Supports pause/resume, idle-gap silence alignment,
/// dynamic per-app process refresh, and quiet in-place `kick()` rebuild.
final class MeetingSystemAudioRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case unsupportedOS, permissionDenied, fileExists, tap, format, aggregate, ioProc, start

        var errorDescription: String? {
            switch self {
            case .unsupportedOS: return "System audio capture requires macOS 14.4 or later."
            case .permissionDenied: return "System audio capture permission is not granted."
            case .fileExists: return "Recording file already exists."
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
    private var silenceBuffer: AVAudioPCMBuffer?
    private var processResolver: (() -> [AudioObjectID])?
    private var tappedProcesses: Set<AudioObjectID> = []
    private var pendingTappedProcesses: Set<AudioObjectID> = []
    private var processListener: AudioObjectPropertyListenerBlock?
    private var heartbeatTimer: DispatchSourceTimer?
    private var clock = MeetingActiveClock()
    private let controlQueue = DispatchQueue(label: "com.vorssaint.utils.meeting.systemaudio.control")
    private let ioQueue = DispatchQueue(label: "com.vorssaint.utils.meeting.systemaudio.io")
    private var paused = false
    private var _frameCount: Int64 = 0
    private var _receivedFrameCount: Int64 = 0

    let levels = MeetingLevelHistory()

    /// Number of real audio frames delivered by the Core Audio tap (excluding
    /// silence padding written across idle gaps).
    var receivedFrameCount: Int64 {
        ioQueue.sync { _receivedFrameCount }
    }

    func setPaused(_ value: Bool) {
        ioQueue.sync { paused = value }
    }

    /// `processResolver` nil taps all system audio excluding Vorssaint;
    /// non-nil dynamically resolves the target app's audio processes (including
    /// helper processes that spawn mid-call) and refreshes on process changes.
    @discardableResult
    func start(toFile url: URL,
               processResolver: (() -> [AudioObjectID])? = nil,
               clock: MeetingActiveClock = MeetingActiveClock()) throws -> MeetingRecorderSupport.FileIdentity {
        try controlQueue.sync {
            self.processResolver = processResolver
            self.clock = clock
            self.ioQueue.sync {
                self._frameCount = 0
                self._receivedFrameCount = 0
                self.paused = false
            }
            let fmt = try buildTap()
            self.format = fmt
            var reservedIdentity: MeetingRecorderSupport.FileIdentity?
            do {
                guard let reserved = MeetingCoreAudio.reserveExclusiveFile(url) else {
                    throw RecorderError.fileExists
                }
                reservedIdentity = reserved
                let opened = try AVAudioFile(forWriting: url, settings: fmt.settings,
                                             commonFormat: .pcmFormatFloat32, interleaved: fmt.isInterleaved)
                MeetingCoreAudio.markRecorderOwnedFile(url)
                let pad = Self.makeSilenceBuffer(format: fmt, frames: 4096)
                self.ioQueue.sync {
                    self.file = opened
                    self.silenceBuffer = pad
                }
                try startIO()
                self.tappedProcesses = self.pendingTappedProcesses
                startHeartbeat(sampleRate: fmt.sampleRate)
                installProcessListenerIfNeeded()
                return reserved
            } catch {
                removeProcessListener()
                stopHeartbeat()
                teardownTap()
                self.format = nil
                self.ioQueue.sync {
                    self.file = nil
                    self.silenceBuffer = nil
                }
                if let reservedIdentity, MeetingCoreAudio.regularFileIdentity(of: url) == reservedIdentity {
                    try? FileManager.default.removeItem(at: url)
                    MeetingCoreAudio.forgetRecorderOwnedFile(url)
                }
                throw error
            }
        }
    }

    private func buildTap() throws -> AVAudioFormat {
        guard #available(macOS 14.4, *) else { throw RecorderError.unsupportedOS }
        let resolved = processResolver?() ?? []
        let mode: VorssaintTapMode
        let tapProcesses: [NSNumber]
        if resolved.isEmpty {
            mode = .stereoGlobalExcluding
            pendingTappedProcesses = []
            if let ownObj = MeetingCoreAudio.audioProcessObject(forPID: getpid()) {
                tapProcesses = [NSNumber(value: ownObj)]
            } else {
                tapProcesses = []
            }
        } else {
            mode = .stereoMixdown
            pendingTappedProcesses = Set(resolved)
            tapProcesses = resolved.map { NSNumber(value: $0) }
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
        let fmt = format
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) { [weak self] _, input, _, _, _ in
            guard let self, !self.paused, let fmt, let file = self.file,
                  let buffer = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: input, deallocator: nil) else {
                return
            }
            let frames = Int(buffer.frameLength)
            // The 1-second heartbeat keeps `_frameCount` caught up during idle
            // periods, so cap any synchronous catch-up inside the IO callback
            // to 2 seconds to avoid blocking Core Audio.
            let rawGap = MeetingRecorderSupport.silenceGapFrames(
                activeElapsedSeconds: self.clock.activeElapsedSeconds(),
                writtenFrames: self._frameCount,
                incomingFrames: Int64(frames),
                sampleRate: fmt.sampleRate
            )
            let maxInlineGap = Int64(fmt.sampleRate * 2.0)
            self.writeSilenceOnIOQueue(frames: min(rawGap, maxInlineGap), to: file)
            let bufferPeak = MeetingCoreAudio.peakFloatSample(in: buffer)
            self.levels.ingest(peak: bufferPeak, frames: frames, sampleRate: fmt.sampleRate)
            if (try? file.write(from: buffer)) != nil {
                self._frameCount += Int64(frames)
                self._receivedFrameCount += Int64(frames)
            }
        }
        guard status == noErr else { throw RecorderError.ioProc }
        guard AudioDeviceStart(aggregateID, procID) == noErr else { throw RecorderError.start }
    }

    /// Quiet in-place rebuild for a wedged tap (health watchdog) or newly
    /// spawned per-app helper processes, keeping the same open WAV file when
    /// the stream format still matches.
    func kick() throws {
        try controlQueue.sync {
            try rebuildLocked()
        }
    }

    func stop() {
        controlQueue.sync {
            removeProcessListener()
            stopHeartbeat()
            teardownTap()
            let sampleRate = format?.sampleRate ?? 0
            ioQueue.sync {
                // Flush trailing silence after an idle tail only when real
                // system audio was captured, so the track ends aligned with
                // the mic WAV while still discarding 0-audio tracks.
                if _receivedFrameCount > 0, let file, sampleRate > 0 {
                    let tailGap = MeetingRecorderSupport.silenceGapFrames(
                        activeElapsedSeconds: clock.activeElapsedSeconds(),
                        writtenFrames: _frameCount,
                        incomingFrames: 0,
                        sampleRate: sampleRate
                    )
                    writeSilenceOnIOQueue(frames: tailGap, to: file)
                }
                file = nil
                silenceBuffer = nil
            }
            processResolver = nil
            tappedProcesses = []
            pendingTappedProcesses = []
        }
    }

    private func writeSilenceOnIOQueue(frames: Int64, to file: AVAudioFile) {
        guard frames > 0, let pad = silenceBuffer else { return }
        var remaining = frames
        let chunkCap = Int64(pad.frameCapacity)
        while remaining > 0 {
            let count = min(remaining, chunkCap)
            pad.frameLength = AVAudioFrameCount(count)
            if (try? file.write(from: pad)) == nil { break }
            _frameCount += count
            remaining -= count
        }
    }

    private func startHeartbeat(sampleRate: Double) {
        stopHeartbeat()
        guard sampleRate > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self, !self.paused, let file = self.file else { return }
            let gap = MeetingRecorderSupport.silenceGapFrames(
                activeElapsedSeconds: self.clock.activeElapsedSeconds(),
                writtenFrames: self._frameCount,
                incomingFrames: 0,
                sampleRate: sampleRate,
                thresholdSeconds: 0.5
            )
            // Drip at most 1.5s of silence per tick so even long idle stretches
            // never cause a multi-hundred-MB blocking burst in the IO callback.
            let maxTickFrames = Int64(sampleRate * 1.5)
            self.writeSilenceOnIOQueue(frames: min(gap, maxTickFrames), to: file)
        }
        heartbeatTimer = timer
        timer.resume()
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func rebuildLocked() throws {
        let hasFile = ioQueue.sync { file != nil }
        guard hasFile else { return }
        let previousFormat = format
        teardownTap()
        let nextFormat = try buildTap()
        guard nextFormat == previousFormat else {
            teardownTap()
            throw RecorderError.format
        }
        try startIO()
        tappedProcesses = pendingTappedProcesses
    }

    private func installProcessListenerIfNeeded() {
        guard processResolver != nil, processListener == nil else { return }
        var addr = MeetingCoreAudio.address(kAudioHardwarePropertyProcessObjectList)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, let resolver = self.processResolver else { return }
            let current = Set(resolver())
            guard !current.isEmpty, !current.isSubset(of: self.tappedProcesses) else { return }
            try? self.rebuildLocked()
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &addr, controlQueue, block) == noErr {
            processListener = block
        }
    }

    private func removeProcessListener() {
        guard let listener = processListener else { return }
        var addr = MeetingCoreAudio.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                               &addr, controlQueue, listener)
        processListener = nil
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
        tappedProcesses = []
        pendingTappedProcesses = []
    }

    private static func makeSilenceBuffer(format: AVAudioFormat, frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for audioBuf in list {
            if let data = audioBuf.mData, audioBuf.mDataByteSize > 0 {
                memset(data, 0, Int(audioBuf.mDataByteSize))
            }
        }
        return buffer
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
    private var silenceBuffer: AVAudioPCMBuffer?
    private var clock = MeetingActiveClock()
    private var converter: AVAudioConverter?
    private var converterRate: Double = 0
    private var observer: NSObjectProtocol?
    private var heartbeatTimer: DispatchSourceTimer?
    private let heartbeatQueue = DispatchQueue(label: "com.vorssaint.utils.meeting.mic.heartbeat", qos: .utility)
    private var stopped = false
    private var restartAttempts = 0
    private var _frameCount: Int64 = 0
    private var _receivedFrameCount: Int64 = 0
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

    var receivedFrameCount: Int64 {
        lock.lock(); defer { lock.unlock() }
        return _receivedFrameCount
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

    @discardableResult
    func start(toFile url: URL, clock: MeetingActiveClock = MeetingActiveClock()) throws -> MeetingRecorderSupport.FileIdentity {
        self.clock = clock
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
        guard let reservedIdentity = MeetingCoreAudio.reserveExclusiveFile(url) else {
            throw NSError(domain: "com.vorssaint.utils.meeting", code: 13,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone recording file already exists."])
        }
        do {
            file = try AVAudioFile(forWriting: url, settings: canonical.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
            MeetingCoreAudio.markRecorderOwnedFile(url)
        } catch {
            if MeetingCoreAudio.regularFileIdentity(of: url) == reservedIdentity {
                try? FileManager.default.removeItem(at: url)
                MeetingCoreAudio.forgetRecorderOwnedFile(url)
            }
            throw error
        }
        fileFormat = canonical
        silenceBuffer = Self.makeSilenceBuffer(format: canonical, frames: 4096)
        _frameCount = 0
        _receivedFrameCount = 0
        stopped = false
        guard installTap() else {
            stop()
            if MeetingCoreAudio.regularFileIdentity(of: url) == reservedIdentity {
                try? FileManager.default.removeItem(at: url)
                MeetingCoreAudio.forgetRecorderOwnedFile(url)
            }
            throw NSError(domain: "com.vorssaint.utils.meeting", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone tap rejected by input device."])
        }
        do {
            try startEngine()
        } catch {
            stop()
            if MeetingCoreAudio.regularFileIdentity(of: url) == reservedIdentity {
                try? FileManager.default.removeItem(at: url)
                MeetingCoreAudio.forgetRecorderOwnedFile(url)
            }
            throw error
        }
        startHeartbeat(sampleRate: canonical.sampleRate)
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
        return reservedIdentity
    }

    /// Rebuilds the engine for a watchdog stall recovery without resetting
    /// the hardware device-change grace window, so a persistently dead mic
    /// still escalates to `.neverStarted`/`.wedged`.
    func kick() {
        rebuildEngine()
        verifyDeliverySoon()
    }

    func stop() {
        stopHeartbeat()
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
        silenceBuffer = nil
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
        let outputBuffer: AVAudioPCMBuffer
        if rate == fileFormat.sampleRate {
            outputBuffer = mono
        } else {
            if converter == nil || converterRate != rate {
                converter = AVAudioConverter(from: mono.format, to: fileFormat)
                converterRate = rate
            }
            guard let converter, let out = Self.convert(mono, with: converter, to: fileFormat) else { return }
            outputBuffer = out
        }
        let rawGap = MeetingRecorderSupport.silenceGapFrames(
            activeElapsedSeconds: clock.activeElapsedSeconds(),
            writtenFrames: _frameCount,
            incomingFrames: Int64(outputBuffer.frameLength),
            sampleRate: fileFormat.sampleRate
        )
        // The 1-second heartbeat drips silence during long input outages, so
        // cap any inline catch-up inside the lock to 2 seconds to avoid
        // blocking Stop or subsequent audio callbacks.
        let maxInlineGap = Int64(fileFormat.sampleRate * 2.0)
        writeSilenceLocked(frames: min(rawGap, maxInlineGap), to: file)
        if (try? file.write(from: outputBuffer)) != nil {
            _frameCount += Int64(outputBuffer.frameLength)
            _receivedFrameCount += Int64(outputBuffer.frameLength)
        }
    }

    private func writeSilenceLocked(frames: Int64, to file: AVAudioFile) {
        guard frames > 0, let pad = silenceBuffer else { return }
        var remaining = frames
        let chunkCap = Int64(pad.frameCapacity)
        while remaining > 0 {
            let count = min(remaining, chunkCap)
            pad.frameLength = AVAudioFrameCount(count)
            if (try? file.write(from: pad)) == nil { break }
            _frameCount += count
            remaining -= count
        }
    }

    private func startHeartbeat(sampleRate: Double) {
        stopHeartbeat()
        guard sampleRate > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard !self.stopped, !self.paused, let file = self.file else { return }
            let gap = MeetingRecorderSupport.silenceGapFrames(
                activeElapsedSeconds: self.clock.activeElapsedSeconds(),
                writtenFrames: self._frameCount,
                incomingFrames: 0,
                sampleRate: sampleRate,
                thresholdSeconds: 0.5
            )
            let maxTickFrames = Int64(sampleRate * 1.5)
            self.writeSilenceLocked(frames: min(gap, maxTickFrames), to: file)
        }
        heartbeatTimer = timer
        timer.resume()
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private static func makeSilenceBuffer(format: AVAudioFormat, frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        if let data = buffer.floatChannelData?[0] {
            memset(data, 0, Int(frames) * MemoryLayout<Float>.size)
        }
        return buffer
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
        guard hw.sampleRate > 0, hw.channelCount > 0, installTap(), (try? startEngine()) != nil else {
            restartAttempts += 1
            if restartAttempts <= 40 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.handleConfigurationChange()
                }
            }
            return
        }
        restartAttempts = 0
        verifyDeliverySoon()
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
    private let clock = MeetingActiveClock()
    private let system = MeetingSystemAudioRecorder()
    private let mic: MeetingMicRecorder

    private(set) var systemRunning = false
    private(set) var micRunning = false
    private var createdSystemIdentity: MeetingRecorderSupport.FileIdentity?
    private var createdMicIdentity: MeetingRecorderSupport.FileIdentity?

    var micLevels: MeetingLevelHistory { mic.levels }
    var systemLevels: MeetingLevelHistory { system.levels }
    var micSecondsSinceDeviceChange: Double { mic.secondsSinceDeviceChange }
    var micReceivedFrames: Int64 { mic.receivedFrameCount }
    var systemReceivedFrames: Int64 { system.receivedFrameCount }

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
        clock.start()

        // Gate system capture on TCC kTCCServiceAudioCapture preflight: an
        // unauthorized Core Audio tap succeeds silently and writes all-zero
        // WAV frames, which would otherwise look healthy to the user.
        let resolver: (() -> [AudioObjectID])? = perApp
            ? { [weak self] in
                guard let self, let pid = self.resolvedTargetPID() else { return [] }
                return MeetingCoreAudio.audioProcessObjects(forPID: pid)
            }
            : nil

        if MeetingAudioPermission.preflight() == .granted {
            do {
                createdSystemIdentity = try system.start(toFile: systemFileURL,
                                                         processResolver: resolver,
                                                         clock: clock)
                systemRunning = true
            } catch {
                if resolver != nil {
                    system.stop()
                    do {
                        createdSystemIdentity = try system.start(toFile: systemFileURL,
                                                                 processResolver: nil,
                                                                 clock: clock)
                        systemRunning = true
                    } catch {
                        systemRunning = false
                    }
                }
            }
        }

        do {
            createdMicIdentity = try mic.start(toFile: micFileURL, clock: clock)
            micRunning = true
        } catch {
            if !systemRunning {
                cleanupUnusedFiles()
                throw error
            }
        }
    }

    func setPaused(_ value: Bool) {
        clock.setPaused(value)
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
        let systemHasAudio = systemRunning && system.receivedFrameCount > 0
        let micHasAudio = micRunning && mic.receivedFrameCount > 0
        if !systemHasAudio { removeOwnedSessionFile(systemFileURL, identity: createdSystemIdentity) }
        if !micHasAudio { removeOwnedSessionFile(micFileURL, identity: createdMicIdentity) }
        return Result(
            stem: stem,
            systemAudioURL: systemHasAudio ? systemFileURL : nil,
            micAudioURL: micHasAudio ? micFileURL : nil,
            detectedApp: detectedApp,
            systemCaptured: systemHasAudio,
            micCaptured: micHasAudio
        )
    }

    func discard() {
        if systemRunning { system.stop() }
        if micRunning { mic.stop() }
        removeOwnedSessionFile(systemFileURL, identity: createdSystemIdentity)
        removeOwnedSessionFile(micFileURL, identity: createdMicIdentity)
    }

    private func cleanupUnusedFiles() {
        if !systemRunning { removeOwnedSessionFile(systemFileURL, identity: createdSystemIdentity) }
        if !micRunning { removeOwnedSessionFile(micFileURL, identity: createdMicIdentity) }
    }

    private func removeOwnedSessionFile(_ url: URL, identity: MeetingRecorderSupport.FileIdentity?) {
        guard let identity, MeetingCoreAudio.regularFileIdentity(of: url) == identity else { return }
        if (try? FileManager.default.removeItem(at: url)) != nil {
            MeetingCoreAudio.forgetRecorderOwnedFile(url)
        }
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
