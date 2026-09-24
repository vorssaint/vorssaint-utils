// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AppKit
import Combine
import CoreAudio
import Foundation

/// Reads the current player's audio output and turns it into seven levels
/// for the island's bars. Off unless chosen, and running only while that
/// player is playing: the tap follows the player's process, listens to
/// nothing else, keeps a fraction of a second of samples in memory and never
/// stores or sends audio.
final class NotchAudioLevelService: ObservableObject {
    static let shared = NotchAudioLevelService()

    /// Band levels from 0 to 1 while a player is being read, nil otherwise.
    @Published private(set) var levels: [Double]?

    private var enabled = false
    private var subscription: AnyCancellable?
    private var reader: NotchAudioLevelReader?
    private var readerPID: pid_t = 0
    private var readerID: UUID?
    private var silence = NotchAudioLevelSupport.SilenceMemory()
    private var stopWork: DispatchWorkItem?

    private init() {}

    func syncWithPreferences() {
        enabled = AppFeature.notchLiveEqualizer.isAvailable && NotchSupport.isEnabled()
            && NotchAudioLevelSupport.isSupported && NotchAudioLevelSupport.isEnabled()
        if enabled {
            if subscription == nil {
                silence.rearm()
                subscription = NotchMusicService.shared.$playback
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] playback in self?.playbackChanged(playback) }
            }
        } else {
            subscription = nil
            stop()
        }
    }

    func stop() {
        stopWork?.cancel(); stopWork = nil
        reader?.stop()
        reader = nil
        readerPID = 0
        readerID = nil
        if levels != nil { levels = nil }
    }

    private func playbackChanged(_ playback: NotchPlayback?) {
        guard enabled, let playback, playback.isPlaying,
              let pid = playback.track.appPID, pid > 0 else {
            // Pausing or stopping arms the next play to read again.
            silence.rearm()
            scheduleStop()
            return
        }
        // A reader that has not heard sound may already be reporting silence
        // from the pause. Give the resumed play a fresh chance, and a new
        // reader identity, while keeping audible readers through short pauses.
        let resumeBeforeSound = stopWork != nil && levels == nil
        stopWork?.cancel(); stopWork = nil
        guard readerPID != pid || resumeBeforeSound else { return }
        // Release the previous player before deciding about this one, or its
        // reader would keep the bars on somebody else's levels.
        stop()
        let identity = NotchMusicIdentity(playback)
        guard silence.reads(identity) else { return }
        readerPID = pid
        read(pid, on: identity)
    }

    private func read(_ pid: pid_t, on identity: NotchMusicIdentity) {
        // A stopped reader can finish a slow device call after its replacement
        // has started for the same player. Only this reading may publish.
        let id = UUID()
        readerID = id
        let created = NotchAudioLevelReader(pid: pid, onLevels: { [weak self] next in
            DispatchQueue.main.async {
                guard let self, self.readerID == id else { return }
                self.receive(next, from: pid)
            }
        }, onSilence: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.readerID == id else { return }
                self.giveUp(pid, on: identity)
            }
        }, onUnavailable: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.readerID == id else { return }
                self.release(pid)
            }
        }, onProcessesLeft: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.readerID == id else { return }
                self.restart(pid, on: identity)
            }
        })
        reader = created
        created.start()
    }

    /// The player moved its sound to another process. The bars go back to
    /// their usual motion while a new tap is built, and the wait for sound
    /// starts over, since the new process may be the silent kind.
    private func restart(_ pid: pid_t, on identity: NotchMusicIdentity) {
        guard enabled, readerPID == pid else { return }
        // Paused, the player may have just let go of its audio: reading again
        // now would only hear silence and write this track off before the next
        // play, which starts a fresh reader on its own.
        let pausing = stopWork != nil
        stop()
        guard !pausing else { return }
        readerPID = pid
        read(pid, on: identity)
    }

    private func giveUp(_ pid: pid_t, on identity: NotchMusicIdentity) {
        guard readerPID == pid else { return }
        // Paused, the tap hears the player letting go of its audio, and the
        // pause already armed the next play; only a play that stayed silent
        // is written off.
        if stopWork == nil { silence.giveUp(on: identity) }
        stop()
    }

    /// No tap could be created, or the one there lost its device for good.
    /// Nothing is marked, so the next change is free to try again.
    private func release(_ pid: pid_t) {
        guard readerPID == pid else { return }
        stop()
    }

    /// A pause keeps the bars for a moment, so a skipped track does not
    /// blink the meter off and on; a real stop then releases the tap.
    private func scheduleStop() {
        guard reader != nil || levels != nil, stopWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.stopWork = nil
            self?.stop()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func receive(_ next: [Double], from pid: pid_t) {
        guard reader != nil, readerPID == pid else { return }
        levels = next
    }
}

/// Names a reader's Core Audio listener registrations.
///
/// The registrations use the plain callback and a client pointer, the way
/// the mixer does. Handing a closure back to be removed never matches the
/// one that was registered: the call answers that it worked and the listener
/// stays, so every reader would leave its listeners behind and they would go
/// on firing for the rest of the session.
///
/// That pointer is a number to look up here, never the reader's own address.
/// A reader lives for one play, and a notification can still be on its way
/// from a HAL thread when the last one goes away; the entry holds the reader
/// until it has given its listeners back, and a forgotten number simply
/// finds nothing.
private enum NotchAudioLevelListeners {
    private static let lock = NSLock()
    private static var readers: [UInt: NotchAudioLevelReader] = [:]
    private static var counter: UInt = 0

    /// A client pointer no other reader holds. Never dereferenced.
    static func reserve() -> UnsafeMutableRawPointer {
        lock.lock()
        defer { lock.unlock() }
        counter &+= 1
        if counter == 0 { counter = 1 }
        // A counter that never reaches zero always makes a usable value.
        return UnsafeMutableRawPointer(bitPattern: counter).unsafelyUnwrapped
    }

    static func attach(_ reader: NotchAudioLevelReader, to client: UnsafeMutableRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        readers[UInt(bitPattern: client)] = reader
    }

    static func forget(_ client: UnsafeMutableRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        readers[UInt(bitPattern: client)] = nil
    }

    static func reader(for client: UnsafeMutableRawPointer?) -> NotchAudioLevelReader? {
        guard let client else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return readers[UInt(bitPattern: client)]
    }
}

/// The player's process taps, read through a private aggregate device on the
/// default output, the same shape the recorder uses, feeding a ring of mono
/// samples that a timer analyses off the audio thread.
///
/// Every Core Audio call runs on this object's own queue. Creating a tap or
/// starting a device can block for as long as a Bluetooth or USB device takes
/// to reconnect, and the island must never wait on that.
private final class NotchAudioLevelReader {
    private let queue = DispatchQueue(label: "com.vorssaint.notch-audio-levels", qos: .utility)
    private static let teardownQueue = DispatchQueue(label: "com.vorssaint.notch-audio-levels.teardown", qos: .utility)
    private let pid: pid_t
    private let onLevels: ([Double]) -> Void
    private let onSilence: () -> Void
    private let onUnavailable: () -> Void
    private let onProcessesLeft: () -> Void
    private let ring = NotchAudioRing(capacity: 8192)
    private var startedAt: TimeInterval = 0
    private var tapID = AudioObjectID(0)
    private var tapUID = ""
    private var tapChannels = 2
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var timer: DispatchSourceTimer?
    private var analyzer: NotchAudioAnalyzer?
    private var smoother = NotchAudioLevelSupport.Smoother()
    private var samples: [Float] = []
    private var hostDeviceUID: String?
    private var sampleRate: Double = 0
    private var tapped: [AudioObjectID] = []
    /// Names this reader's listener registrations. See `NotchAudioLevelListeners`.
    private let listenerClient = NotchAudioLevelListeners.reserve()
    private var deviceListening = false
    private var processListening = false
    private var rateListenerDevice = AudioObjectID(0)
    private var processCheck: DispatchWorkItem?
    private var stopped = false

    init(pid: pid_t, onLevels: @escaping ([Double]) -> Void,
         onSilence: @escaping () -> Void, onUnavailable: @escaping () -> Void,
         onProcessesLeft: @escaping () -> Void) {
        self.pid = pid
        self.onLevels = onLevels
        self.onSilence = onSilence
        self.onUnavailable = onUnavailable
        self.onProcessesLeft = onProcessesLeft
    }

    deinit {
        Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: tapID)
    }

    /// Builds and starts on the reader's queue. A failure is reported through
    /// `onUnavailable` rather than returned, since the caller is not waiting.
    func start() {
        queue.async { [self] in
            guard !stopped else { return }
            NotchAudioLevelListeners.attach(self, to: listenerClient)
            guard buildTap(), buildPipeline() else {
                release(reporting: onUnavailable)
                return
            }
            watchDefaultOutputDevice()
            watchProcessList()
            startAnalysis()
        }
    }

    func stop() {
        queue.async { [self] in
            guard !stopped else { return }
            release(reporting: nil)
        }
    }

    // MARK: - Pipeline

    private func buildTap() -> Bool {
        guard #available(macOS 14.4, *), tapID == 0 else { return false }
        let objects = Self.processObjects(for: pid)
        guard !objects.isEmpty else { return false }
        tapped = objects
        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.name = "Vorssaint Island Levels"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tapID = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else { return false }
        self.tapID = tapID
        tapUID = description.uuid.uuidString
        var format = AudioStreamBasicDescription()
        if Self.read(tapID, kAudioTapPropertyFormat, &format), format.mChannelsPerFrame > 0 {
            tapChannels = Int(format.mChannelsPerFrame)
        }
        return true
    }

    private func buildPipeline() -> Bool {
        guard aggregateID == 0, tapID != 0, let hostUID = Self.hostDeviceUID() else { return false }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Vorssaint Island Levels",
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
              aggregateID != 0 else { return false }
        let sampleRate = Self.nominalSampleRate(of: aggregateID)
        guard let analyzer = NotchAudioAnalyzer(sampleRate: sampleRate) else {
            Self.destroy(aggregateID: aggregateID, ioProc: nil, tapID: 0)
            return false
        }
        // The audio thread touches only these captured values, never this
        // object, matching the mixer's realtime discipline.
        let ring = self.ring
        let channels = tapChannels
        var ioProc: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, input, _, output, _ in
            // The device beneath the aggregate would otherwise play whatever
            // this memory last held.
            MixerRender.silence(UnsafeMutableAudioBufferListPointer(output))
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let index = MixerRender.tapBufferIndex(in: inputBuffers, tapChannels: channels) else { return }
            ring.write(inputBuffers[index])
        }
        guard created == noErr, let ioProc, AudioDeviceStart(aggregateID, ioProc) == noErr else {
            Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: 0)
            return false
        }
        self.aggregateID = aggregateID
        self.ioProc = ioProc
        self.analyzer = analyzer
        self.hostDeviceUID = hostUID
        self.sampleRate = sampleRate
        samples = [Float](repeating: 0, count: analyzer.size)
        watchSampleRate(of: aggregateID)
        return true
    }

    private func teardownPipeline() {
        let aggregateID = self.aggregateID
        let ioProc = self.ioProc
        let rateDevice = rateListenerDevice
        self.aggregateID = 0
        self.ioProc = nil
        rateListenerDevice = 0
        analyzer = nil
        hostDeviceUID = nil
        if rateDevice != 0 {
            var address = Self.address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListener(rateDevice, &address, Self.deviceCallback, listenerClient)
        }
        guard aggregateID != 0 else { return }
        if let ioProc { AudioDeviceStop(aggregateID, ioProc) }
        Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: 0)
    }

    /// Gives everything back for good, optionally saying why. The tap goes
    /// too, and this reader builds no other: the service makes the next one.
    private func release(reporting callback: (() -> Void)?) {
        stopped = true
        stopAnalysis()
        processCheck?.cancel()
        processCheck = nil
        if deviceListening {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address,
                                              Self.deviceCallback, listenerClient)
            deviceListening = false
        }
        if processListening {
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address,
                                              Self.processCallback, listenerClient)
            processListening = false
        }
        tapped = []
        teardownPipeline()
        let tapID = self.tapID
        self.tapID = 0
        Self.destroy(aggregateID: 0, ioProc: nil, tapID: tapID)
        // The last reference to this reader may be the registry's, so the
        // caller's own strong capture is what keeps it alive to here.
        NotchAudioLevelListeners.forget(listenerClient)
        callback?()
    }

    /// Headphones that come and go, or a device that changes its rate for a
    /// call, would otherwise leave the bars still while the music plays on.
    /// Only a real change rebuilds, so the notifications a rebuild raises
    /// settle instead of looping.
    private func rebuildIfDeviceChanged() {
        guard !stopped, aggregateID != 0 else { return }
        guard Self.hostDeviceUID() != hostDeviceUID
                || Self.nominalSampleRate(of: aggregateID) != sampleRate else { return }
        teardownPipeline()
        // The ring keeps what it has heard, so a device change does not
        // restart the silence countdown on a player already known to sound.
        if !buildPipeline() { release(reporting: onUnavailable) }
    }

    private func watchDefaultOutputDevice() {
        guard !deviceListening else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        deviceListening = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &address,
                                                         Self.deviceCallback, listenerClient) == noErr
    }

    private func watchProcessList() {
        guard !processListening else { return }
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        processListening = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &address,
                                                          Self.processCallback, listenerClient) == noErr
    }

    private func watchSampleRate(of aggregateID: AudioObjectID) {
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        if AudioObjectAddPropertyListener(aggregateID, &address,
                                          Self.deviceCallback, listenerClient) == noErr {
            rateListenerDevice = aggregateID
        }
    }

    /// A browser makes its sound in a helper process that it opens and shuts
    /// as tabs come and go. One that leaves takes the tap's ears with it;
    /// one that arrives is a part of the player the tap cannot hear, such as
    /// a tab that starts playing a moment after the tap was built. Either
    /// way the tap has to be made again from the player's processes as they
    /// are now, and `TapChange` says what that costs the bars.
    private func tappedProcessesChanged() {
        processCheck = nil
        guard !stopped, !tapped.isEmpty else { return }
        guard #available(macOS 14.4, *) else { return }
        switch NotchAudioLevelSupport.tapChange(tapped: Set(tapped),
                                                current: Set(Self.processObjects(for: pid))) {
        case .none: return
        case .restart: release(reporting: onProcessesLeft)
        case .rebuild: rebuildTap()
        }
    }

    /// Builds the tap again around the player's processes as they are now,
    /// keeping the ring: the processes already heard never stopped, so the
    /// bars carry on and the wait for sound is not started over.
    private func rebuildTap() {
        teardownPipeline()
        let previous = tapID
        tapID = 0
        tapped = []
        Self.destroy(aggregateID: 0, ioProc: nil, tapID: previous)
        if !buildTap() || !buildPipeline() { release(reporting: onProcessesLeft) }
    }

    /// One app launching stirs the whole process list. The player's own
    /// processes are read once the burst has settled, not on each of them.
    private func scheduleProcessCheck() {
        guard !stopped, !tapped.isEmpty else { return }
        processCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.tappedProcessesChanged() }
        processCheck = work
        queue.asyncAfter(deadline: .now() + NotchAudioLevelSupport.processSettle, execute: work)
    }

    // MARK: - Listeners

    /// The default output device and the aggregate's sample rate ask the
    /// same question: is the tap still reading the device the music comes
    /// out of. Both notifications arrive on a HAL thread, so each one hops
    /// to the reader's queue before touching anything.
    private static let deviceCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        NotchAudioLevelListeners.reader(for: client)?.deviceChanged()
        return noErr
    }

    private static let processCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        NotchAudioLevelListeners.reader(for: client)?.processListChanged()
        return noErr
    }

    fileprivate func deviceChanged() {
        queue.async { [self] in rebuildIfDeviceChanged() }
    }

    fileprivate func processListChanged() {
        queue.async { [self] in scheduleProcessCheck() }
    }

    // MARK: - Analysis

    private func startAnalysis() {
        startedAt = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.1, repeating: 1 / NotchAudioLevelSupport.updatesPerSecond, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.analyse() }
        self.timer = timer
        timer.resume()
    }

    private func stopAnalysis() {
        timer?.cancel()
        timer = nil
    }

    private func analyse() {
        guard !stopped, let analyzer else { return }
        // Levels are reported only once sound has arrived, so the bars keep
        // their usual motion while the tap warms up, and give this play up
        // when the tap only ever delivers silence.
        guard ring.hasHeard else {
            if NotchAudioLevelSupport.fallsBack(heard: false, elapsed: ProcessInfo.processInfo.systemUptime - startedAt) {
                release(reporting: onSilence)
            }
            return
        }
        guard ring.latest(into: &samples) else { return }
        let magnitudes = analyzer.magnitudes(of: samples)
        let raw = NotchAudioLevelSupport.bandLevels(magnitudes: magnitudes, bands: analyzer.bands)
        onLevels(smoother.next(raw))
    }

    // MARK: - Core Audio

    private static func destroy(aggregateID: AudioObjectID, ioProc: AudioDeviceIOProcID?, tapID: AudioObjectID) {
        guard aggregateID != 0 || tapID != 0 else { return }
        teardownQueue.async {
            if aggregateID != 0 {
                if let ioProc { AudioDeviceDestroyIOProcID(aggregateID, ioProc) }
                AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            if tapID != 0, #available(macOS 14.4, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer)) == noErr
        }
    }

    /// Every audio process the player is responsible for. Some browsers make
    /// their sound in a helper process, so a tap on the app's own pid alone
    /// would never hear them; the mixer gathers its rows the same way.
    @available(macOS 14.4, *)
    private static func processObjects(for pid: pid_t) -> [AudioObjectID] {
        var objects: [AudioObjectID] = []
        for object in AppVolumeMixer.audioProcessObjects() {
            var owner: pid_t = -1
            guard read(object, kAudioProcessPropertyPID, &owner), owner > 0,
                  owner == pid || ResponsibleProcess.regularAppOwner(of: owner)?.processIdentifier == pid
            else { continue }
            objects.append(object)
        }
        // A player that holds no audio connection yet still has a process
        // object of its own, which starts sounding when it does.
        if objects.isEmpty, let direct = processObject(for: pid) { objects.append(direct) }
        return objects
    }

    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var object = AudioObjectID(0)
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<pid_t>.size), pidPointer, &size, &object)
        }
        guard status == noErr, object != 0 else { return nil }
        return object
    }

    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double {
        var sampleRate: Float64 = 0
        guard read(deviceID, kAudioDevicePropertyNominalSampleRate, &sampleRate), sampleRate > 0 else { return 48_000 }
        return sampleRate
    }

    private static func hostDeviceUID() -> String? {
        var defaultDevice = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &defaultDevice),
              defaultDevice != 0 else { return nil }
        var uid: CFString = "" as CFString
        guard read(defaultDevice, kAudioDevicePropertyDeviceUID, &uid) else { return nil }
        return uid as String
    }
}

/// Mono samples from the audio thread, most recent last. The audio thread
/// skips a buffer rather than wait when the analysis thread is reading.
private final class NotchAudioRing {
    private let lock = NSLock()
    private var samples: [Float]
    private var head = 0
    private var filled = 0
    private var heard = false
    private let capacity: Int

    /// Whether any sample so far carried sound rather than digital silence.
    var hasHeard: Bool {
        lock.lock()
        defer { lock.unlock() }
        return heard
    }

    init(capacity: Int) {
        self.capacity = capacity
        samples = [Float](repeating: 0, count: capacity)
    }

    func write(_ buffer: AudioBuffer) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        let channels = Int(buffer.mNumberChannels)
        guard channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let frames = MixerRender.frames(bytes: buffer.mDataByteSize, channels: buffer.mNumberChannels)
        let scale = 1 / Float(channels)
        var loudest: Float = 0
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels { sum += data[frame * channels + channel] }
            let mono = sum * scale
            samples[head] = mono
            head = (head + 1) % capacity
            loudest = max(loudest, abs(mono))
        }
        filled = min(capacity, filled + frames)
        if loudest > 0.001 { heard = true }
    }

    /// The most recent `output.count` samples, oldest first. False until
    /// that many have arrived.
    func latest(into output: inout [Float]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let count = output.count
        guard count > 0, count <= capacity, filled >= count else { return false }
        var index = (head - count + capacity) % capacity
        for position in 0..<count {
            output[position] = samples[index]
            index = (index + 1) % capacity
        }
        return true
    }
}

/// A windowed discrete Fourier transform of one block of samples.
private final class NotchAudioAnalyzer {
    let size = 1024
    let bands: [Range<Int>]
    private let setup: vDSP_DFT_Setup
    private var window: [Float]
    private var windowed: [Float]
    private var imaginary: [Float]
    private var outReal: [Float]
    private var outImaginary: [Float]
    private var magnitudes: [Float]

    init?(sampleRate: Double) {
        guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD) else { return nil }
        self.setup = setup
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        windowed = [Float](repeating: 0, count: size)
        imaginary = [Float](repeating: 0, count: size)
        outReal = [Float](repeating: 0, count: size)
        outImaginary = [Float](repeating: 0, count: size)
        magnitudes = [Float](repeating: 0, count: size / 2)
        bands = NotchAudioLevelSupport.bandRanges(sampleRate: sampleRate, size: size)
    }

    deinit { vDSP_DFT_DestroySetup(setup) }

    /// Magnitudes of the first `size / 2` bins relative to full scale.
    /// Every vDSP call takes explicit buffer pointers: the implicit array
    /// conversions read fine on the newest compiler and not on Swift 6.0.
    func magnitudes(of samples: [Float]) -> [Float] {
        guard samples.count == size else { return magnitudes }
        let length = vDSP_Length(size)
        let half = vDSP_Length(size / 2)
        samples.withUnsafeBufferPointer { input in
            window.withUnsafeBufferPointer { taper in
                windowed.withUnsafeMutableBufferPointer { output in
                    vDSP_vmul(input.baseAddress!, 1, taper.baseAddress!, 1, output.baseAddress!, 1, length)
                }
            }
        }
        windowed.withUnsafeBufferPointer { real in
            imaginary.withUnsafeBufferPointer { imaginaryInput in
                outReal.withUnsafeMutableBufferPointer { realOutput in
                    outImaginary.withUnsafeMutableBufferPointer { imaginaryOutput in
                        vDSP_DFT_Execute(setup, real.baseAddress!, imaginaryInput.baseAddress!,
                                         realOutput.baseAddress!, imaginaryOutput.baseAddress!)
                    }
                }
            }
        }
        var scale = 1 / Float(size)
        outReal.withUnsafeMutableBufferPointer { real in
            outImaginary.withUnsafeMutableBufferPointer { imaginaryOutput in
                magnitudes.withUnsafeMutableBufferPointer { output in
                    var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginaryOutput.baseAddress!)
                    vDSP_zvabs(&split, 1, output.baseAddress!, 1, half)
                    vDSP_vsmul(output.baseAddress!, 1, &scale, output.baseAddress!, 1, half)
                }
            }
        }
        return magnitudes
    }
}
