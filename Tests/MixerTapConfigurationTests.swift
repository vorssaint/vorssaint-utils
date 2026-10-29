// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// The production configuration watch is extracted whole. These queues and
/// property reads exercise its lifecycle without opening an audio device.
enum MixerTapConfigurationTests {
    final class DispatchQueue {
        private var jobs: [() -> Void] = []
        var count: Int { jobs.count }
        init(label: String, qos: DispatchQoS) {}
        func async(execute work: @escaping () -> Void) { jobs.append(work) }
        func runNext() {
            guard !jobs.isEmpty else { return }
            jobs.removeFirst()()
        }
        func run() {
            while !jobs.isEmpty { runNext() }
        }
    }

    final class OperationQueue {
        private var jobs: [() -> Void] = []
        func addOperation(_ work: @escaping () -> Void) { jobs.append(work) }
        func run() {
            while !jobs.isEmpty { jobs.removeFirst()() }
        }
    }

    final class AtomicFloatBox {
        var value: Float
        init(_ value: Float) { self.value = value }
    }

    final class Counter { var value = 0 }
    enum TapGainEngine { static let teardownQueue = OperationQueue() }

    final class Recovery {
        final class Engine {
            let requiresRebuild: Bool
            var stops = 0
            init(requiresRebuild: Bool) { self.requiresRebuild = requiresRebuild }
            func stop() { stops += 1 }
        }

        struct App {
            let id: String
            let audioObjects: [AudioObjectID]
            let effectiveOutputDeviceUID: String?
            let needsEngine: Bool
        }

        var configurationRepairs: [String: CFAbsoluteTime] = [:]
        var engines: [String: Engine] = [:]
        var engineRenderProgress: [String: MixerRoutingSupport.EngineRenderObservation] = [:]
        var apps: [App] = []
        var engineRecovery = MixerEngineRecovery()
        var scheduledDelays: [Double] = []

        func appNeedsEngine(_ app: App) -> Bool { app.needsEngine }
        func scheduleEngineReconcile(after delay: Double) { scheduledDelays.append(delay) }
    }

    static let tap: AudioObjectID = 10
    static let aggregate: AudioObjectID = 20
    static let outputStream: AudioObjectID = 21
    static let device: AudioObjectID = 30
    static let stream: AudioObjectID = 31
    static let process: AudioObjectID = 40

    enum HAL {
        struct Key: Hashable {
            let object: AudioObjectID
            let selector: AudioObjectPropertySelector
        }

        struct Registration {
            let object: AudioObjectID
            let address: AudioObjectPropertyAddress
            let callback: AudioObjectPropertyListenerProc
            let client: UnsafeMutableRawPointer?
        }

        static var values: [Key: Any] = [:]
        static var outputChannels = [8]
        static var outputStreams: [AudioObjectID] = [outputStream]
        static var processDevices: [AudioObjectID] = [device]
        static var registrations: [Registration] = []
        static var additionStatus: OSStatus = noErr
        static var failedAddition: Key?
        static var removalStatus: OSStatus = noErr
        static var readCount = 0
        static var removalCount = 0
        static var duringRead: ((Key) -> Void)?

        static func reset() {
            values = [
                Key(object: tap, selector: kAudioTapPropertyFormat): asbd(),
                Key(object: aggregate, selector: kAudioDevicePropertyNominalSampleRate): Double(48_000),
                Key(object: outputStream, selector: kAudioStreamPropertyVirtualFormat): asbd(),
                Key(object: stream, selector: kAudioStreamPropertyVirtualFormat): asbd(),
            ]
            outputChannels = [8]
            outputStreams = [outputStream]
            processDevices = [device]
            registrations = []
            additionStatus = noErr
            failedAddition = nil
            removalStatus = noErr
            readCount = 0
            removalCount = 0
            duringRead = nil
        }

        static func AddPropertyListener(_ object: AudioObjectID,
                                        _ address: UnsafePointer<AudioObjectPropertyAddress>,
                                        _ callback: @escaping AudioObjectPropertyListenerProc,
                                        _ client: UnsafeMutableRawPointer?) -> OSStatus {
            guard additionStatus == noErr else { return additionStatus }
            guard failedAddition != Key(object: object, selector: address.pointee.mSelector) else {
                return kAudioHardwareUnspecifiedError
            }
            registrations.append(Registration(object: object, address: address.pointee,
                                              callback: callback, client: client))
            return noErr
        }

        static func RemovePropertyListener(_ object: AudioObjectID,
                                           _ address: UnsafePointer<AudioObjectPropertyAddress>,
                                           _ callback: AudioObjectPropertyListenerProc,
                                           _ client: UnsafeMutableRawPointer?) -> OSStatus {
            removalCount += 1
            if removalStatus == noErr || removalStatus == kAudioHardwareBadObjectError {
                registrations.removeAll {
                    $0.object == object && $0.address.mSelector == address.pointee.mSelector
                        && $0.address.mScope == address.pointee.mScope && $0.client == client
                }
            }
            return removalStatus
        }

        static func announce(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) {
            for registration in registrations.filter({ $0.object == object && $0.address.mSelector == selector }) {
                var address = registration.address
                _ = registration.callback(object, 1, &address, registration.client)
            }
        }
    }

    enum AppVolumeMixer {
        static func outputStreamChannels(of object: AudioObjectID) -> [Int] { HAL.outputChannels }
        static func outputStreams(_ object: AudioObjectID) -> [AudioObjectID] { HAL.outputStreams }
        static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope) -> [AudioObjectID] { HAL.processDevices }
        static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                            _ value: inout T) -> Bool {
            let key = HAL.Key(object: object, selector: selector)
            let snapshot = HAL.values[key] as? T
            HAL.readCount += 1
            HAL.duringRead?(key)
            guard let snapshot else { return false }
            value = snapshot
            return true
        }
    }

    private static func asbd(channels: UInt32 = 8, rate: Double = 48_000) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                                   mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
                                        | kAudioFormatFlagsNativeEndian,
                                   mBytesPerPacket: channels * 4, mFramesPerPacket: 1,
                                   mBytesPerFrame: channels * 4, mChannelsPerFrame: channels,
                                   mBitsPerChannel: 32, mReserved: 0)
    }

    static func run(_ suite: TestSuite) {
        guard #available(macOS 14.4, *) else { return }
        formats(suite)
        selection(suite)
        recovery(suite)
        // The lifecycle fixtures need one supported production format.
        guard let format = MixerTapFormat(asbd()) else {
            suite.expect(false, "the watch fixture has a supported Float32 stream")
            return
        }
        notifications(suite, format: format)
        changes(suite, format: format)
        fallbackOutputFormat(suite, format: format)
        notificationDuringRead(suite, format: format)
        for status in [noErr, kAudioHardwareBadObjectError, kAudioHardwareUnspecifiedError] {
            removal(suite, format: format, status: status)
        }
        failedRegistration(suite, format: format)
        sharedStreamRegistration(suite, format: format)
    }

    private static func formats(_ suite: TestSuite) {
        for channels: UInt32 in [2, 8, 32] {
            for rate: Double in [44_100, 48_000, 96_000] {
                let format = MixerTapFormat(asbd(channels: channels, rate: rate))
                suite.expect(format?.channels == Int(channels) && format?.sampleRate == rate,
                             "packed Float32 validates every sample and channel at \(rate) Hz / \(channels) channels")
                var planar = asbd(channels: channels, rate: rate)
                planar.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
                planar.mBytesPerFrame = 4
                planar.mBytesPerPacket = 4
                let outputFormat = MixerTapFormat(planar, allowNonInterleaved: true)
                suite.expect(outputFormat?.channels == Int(channels) && outputFormat?.sampleRate == rate
                                && MixerTapFormat(planar) == nil,
                             "planar Float32 is permitted for output validation only at \(rate) Hz / \(channels) channels")
                planar.mBytesPerFrame = channels * 4
                planar.mBytesPerPacket = channels * 4
                suite.expect(MixerTapFormat(planar, allowNonInterleaved: true) == nil,
                             "a planar format cannot claim interleaved frame sizes")
            }
        }
        let invalid: [(String, (inout AudioStreamBasicDescription) -> Void)] = [
            ("Int16", { $0.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
                $0.mBitsPerChannel = 16; $0.mBytesPerFrame = 16; $0.mBytesPerPacket = 16 }),
            ("Int24", { $0.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
                $0.mBitsPerChannel = 24; $0.mBytesPerFrame = 24; $0.mBytesPerPacket = 24 }),
            ("Float64", { $0.mBitsPerChannel = 64; $0.mBytesPerFrame = 64; $0.mBytesPerPacket = 64 }),
            ("planar Float32", { $0.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
                $0.mBytesPerFrame = 4; $0.mBytesPerPacket = 4 }),
            ("opposite endian", { $0.mFormatFlags ^= kAudioFormatFlagIsBigEndian }),
            ("unpacked", { $0.mFormatFlags &= ~kAudioFormatFlagIsPacked }),
            ("compressed", { $0.mFormatID = kAudioFormatMPEG4AAC }),
            ("no channels", { $0.mChannelsPerFrame = 0 }),
            ("short frame", { $0.mBytesPerFrame = 28 }),
            ("short packet", { $0.mBytesPerPacket = 28 }),
            ("multiple frames per packet", { $0.mFramesPerPacket = 2 }),
            ("zero rate", { $0.mSampleRate = 0 }),
            ("negative rate", { $0.mSampleRate = -48_000 }),
            ("infinite rate", { $0.mSampleRate = .infinity }),
            ("NaN rate", { $0.mSampleRate = .nan }),
        ]
        for (name, mutate) in invalid {
            var candidate = asbd()
            mutate(&candidate)
            suite.expect(MixerTapFormat(candidate) == nil,
                         "\(name) cannot be interpreted by the interleaved Float32 renderer")
        }
    }

    private static func selection(_ suite: TestSuite) {
        let wide = MixerTapFormat(asbd())
        let cases: [(String, [[AudioObjectID]], AudioObjectID, Int, UInt32, MixerTapFormat?, Bool)] = [
            ("one wide native stream", [[device]], device, 1, 1, wide, true),
            ("32-channel native stream", [[device]], device, 1, 1, MixerTapFormat(asbd(channels: 32)), true),
            ("helpers on the same output", [[device], [device], []], device, 1, 1, wide, true),
            ("ordinary stereo", [[device]], device, 1, 1, MixerTapFormat(asbd(channels: 2)), false),
            ("multiple streams", [[device]], device, 2, 1, wide, false),
            ("missing streams", [[device]], device, 0, 1, wide, false),
            ("shifted channel range", [[device]], device, 1, 3, wide, false),
            ("unknown format", [[device]], device, 1, 1, nil, false),
            ("app routed to another output", [[device]], device + 1, 1, 1, wide, false),
            ("process spans outputs", [[device, device + 1]], device, 1, 1, wide, false),
            ("helpers span outputs", [[device], [device + 1]], device, 1, 1, wide, false),
            ("silent process", [[]], device, 1, 1, wide, false),
            ("missing process", [], device, 1, 1, wide, false),
            ("unknown output", [[0]], 0, 1, 1, wide, false),
        ]
        for (name, devices, output, count, start, format, expected) in cases {
            suite.expect(MixerTapFormat.usesDeviceStream(processDevices: devices, outputDevice: output,
                                                        streamCount: count, startingChannel: start,
                                                        format: format) == expected,
                         "\(name) selects a direct stream only when every captured channel keeps its destination")
        }
    }

    private static func makeWatch(format: MixerTapFormat, direct: Bool = true,
                                  counter: Counter) -> MixerTapConfiguration {
        let source = direct ? MixerTapConfiguration.Source(device: device, stream: stream, format: format) : nil
        return MixerTapConfiguration(tap: tap, aggregate: aggregate, objects: [process], source: source,
                                     format: format, sampleRate: 48_000, outputChannels: [8],
                                     outputFormats: [outputStream: format]) {
            counter.value += 1
        }
    }

    private static func finish(_ watch: MixerTapConfiguration, _ suite: TestSuite) {
        watch.stop()
        TapGainEngine.teardownQueue.run()
        watch.queue.run()
        suite.expect(HAL.registrations.isEmpty, "configuration fixtures remove every installed callback")
    }

    private static func notifications(_ suite: TestSuite, format: MixerTapFormat) {
        HAL.reset()
        let counter = Counter()
        let watch = makeWatch(format: format, counter: counter)
        watch.start()
        defer { finish(watch, suite) }
        suite.expect(!watch.canRender && HAL.readCount == 0,
                     "registration suspends audio before the first asynchronous validation")
        watch.queue.run()
        suite.expect(watch.canRender && !watch.requiresRebuild && counter.value == 0,
                     "an unchanged initial configuration enables the callback")
        let listeners: [(AudioObjectID, AudioObjectPropertySelector)] = [
            (tap, kAudioTapPropertyFormat),
            (aggregate, kAudioDevicePropertyNominalSampleRate),
            (aggregate, kAudioDevicePropertyStreamConfiguration),
            (aggregate, kAudioDevicePropertyStreams),
            (outputStream, kAudioStreamPropertyVirtualFormat),
            (stream, kAudioStreamPropertyVirtualFormat),
            (process, kAudioProcessPropertyDevices),
        ]
        for (object, selector) in listeners {
            let reads = HAL.readCount
            HAL.announce(object, selector)
            HAL.announce(object, selector)
            suite.expect(!watch.canRender && HAL.readCount == reads && watch.queue.count == 1,
                         "HAL notification \(selector) suspends immediately and coalesces reads off its callback")
            watch.queue.run()
            suite.expect(watch.canRender && !watch.requiresRebuild && counter.value == 0,
                         "unchanged notification \(selector) resumes only after validation")
        }
        HAL.processDevices = []
        HAL.announce(process, kAudioProcessPropertyDevices)
        watch.queue.run()
        suite.expect(watch.canRender && counter.value == 0,
                     "silence alone does not invalidate a stream's source device")
    }

    private static func changes(_ suite: TestSuite, format: MixerTapFormat) {
        let cases: [(String, () -> Void)] = [
            ("tap sample rate", { HAL.values[HAL.Key(object: tap, selector: kAudioTapPropertyFormat)] = asbd(rate: 96_000) }),
            ("tap channel count", { HAL.values[HAL.Key(object: tap, selector: kAudioTapPropertyFormat)] = asbd(channels: 32) }),
            ("unreadable tap", { HAL.values[HAL.Key(object: tap, selector: kAudioTapPropertyFormat)] = nil }),
            ("output sample rate", { HAL.values[HAL.Key(object: aggregate, selector: kAudioDevicePropertyNominalSampleRate)] = Double(44_100) }),
            ("output stream shape", { HAL.outputChannels = [2, 6] }),
            ("output stream identity", { HAL.outputStreams = [outputStream + 1] }),
            ("output stream format", { HAL.values[HAL.Key(object: outputStream, selector: kAudioStreamPropertyVirtualFormat)] = asbd(rate: 96_000) }),
            ("unreadable output stream", { HAL.values[HAL.Key(object: outputStream, selector: kAudioStreamPropertyVirtualFormat)] = nil }),
            ("source format", { HAL.values[HAL.Key(object: stream, selector: kAudioStreamPropertyVirtualFormat)] = asbd(rate: 44_100) }),
            ("source device", { HAL.processDevices = [device + 1] }),
            ("additional source device", { HAL.processDevices = [device, device + 1] }),
        ]
        for (name, change) in cases {
            HAL.reset()
            let counter = Counter()
            let watch = makeWatch(format: format, counter: counter)
            watch.start()
            watch.queue.run()
            change()
            HAL.announce(tap, kAudioTapPropertyFormat)
            watch.queue.run()
            suite.expect(!watch.canRender && watch.requiresRebuild && counter.value == 1,
                         "a changed \(name) leaves the old callback silent and requests one replacement")
            HAL.announce(tap, kAudioTapPropertyFormat)
            watch.refresh(immediately: true)
            watch.queue.run()
            suite.expect(!watch.canRender && counter.value == 1,
                         "an invalid \(name) cannot resume or request duplicate replacements")
            finish(watch, suite)
        }
    }

    private static func notificationDuringRead(_ suite: TestSuite, format: MixerTapFormat) {
        HAL.reset()
        let counter = Counter()
        let watch = makeWatch(format: format, counter: counter)
        watch.start()
        watch.queue.run()
        defer { finish(watch, suite) }
        HAL.duringRead = { key in
            guard key.object == tap else { return }
            HAL.duringRead = nil
            // The read already captured the old value. The notification owns
            // a newer pass, so this result must not re-enable the callback.
            HAL.values[key] = asbd(rate: 96_000)
            HAL.announce(tap, kAudioTapPropertyFormat)
        }
        HAL.announce(tap, kAudioTapPropertyFormat)
        watch.queue.runNext()
        suite.expect(!watch.canRender && !watch.requiresRebuild && counter.value == 0 && watch.queue.count == 1,
                     "a notification during a read keeps its older snapshot suspended")
        watch.queue.run()
        suite.expect(!watch.canRender && watch.requiresRebuild && counter.value == 1,
                     "the subsequent read invalidates the new sample rate exactly once")
    }

    private static func fallbackOutputFormat(_ suite: TestSuite, format: MixerTapFormat) {
        HAL.reset()
        var planar = asbd()
        planar.mFormatFlags |= kAudioFormatFlagIsNonInterleaved
        planar.mBytesPerFrame = 4
        planar.mBytesPerPacket = 4
        guard let outputFormat = MixerTapFormat(planar, allowNonInterleaved: true) else {
            suite.expect(false, "a planar output fixture has a supported Float32 format")
            return
        }
        HAL.values[HAL.Key(object: outputStream, selector: kAudioStreamPropertyVirtualFormat)] = planar
        let counter = Counter()
        let watch = MixerTapConfiguration(tap: tap, aggregate: aggregate, objects: [process], source: nil,
                                          format: format, sampleRate: 48_000, outputChannels: [8],
                                          outputFormats: [outputStream: outputFormat]) {
            counter.value += 1
        }
        watch.start()
        watch.queue.run()
        defer { finish(watch, suite) }
        suite.expect(watch.canRender && !watch.requiresRebuild,
                     "the mixdown fallback also validates planar Float32 output streams")
        var integer = asbd()
        integer.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        integer.mBitsPerChannel = 16
        integer.mBytesPerFrame = 16
        integer.mBytesPerPacket = 16
        HAL.values[HAL.Key(object: outputStream, selector: kAudioStreamPropertyVirtualFormat)] = integer
        HAL.announce(outputStream, kAudioStreamPropertyVirtualFormat)
        suite.expect(!watch.canRender, "a fallback output format notification suspends before any sample interpretation")
        watch.queue.run()
        suite.expect(!watch.canRender && watch.requiresRebuild && counter.value == 1,
                     "an integer output format invalidates the mixdown fallback even without a direct source")
    }

    private static func removal(_ suite: TestSuite, format: MixerTapFormat, status: OSStatus) {
        HAL.reset()
        let counter = Counter()
        var watch: MixerTapConfiguration? = makeWatch(format: format, counter: counter)
        weak var weakWatch = watch
        watch?.start()
        watch?.queue.run()
        let client = HAL.registrations.first?.client
        let count = HAL.registrations.count
        HAL.announce(tap, kAudioTapPropertyFormat)
        let reads = HAL.readCount
        HAL.removalStatus = status
        watch?.stop()
        watch?.stop()
        TapGainEngine.teardownQueue.run()
        watch?.queue.run()
        suite.expect(watch?.canRender == false && HAL.readCount == reads && counter.value == 0,
                     "stop prevents a pending read from resuming or replacing the configuration")
        suite.expect(HAL.removalCount == count, "repeated stop removes each registration only once")
        watch = nil
        let remainsInstalled = status != noErr && status != kAudioHardwareBadObjectError
        suite.expect((weakWatch != nil) == remainsInstalled,
                     "listener client retention matches HAL removal status \(status)")
        if remainsInstalled {
            if let surviving = weakWatch {
                HAL.announce(tap, kAudioTapPropertyFormat)
                surviving.queue.run()
                suite.expect(!surviving.canRender && HAL.readCount == reads && counter.value == 0,
                             "a callback after refused removal has a live but inert client")
            }
            // Only the fixture may discard fake registrations. Release the
            // deliberately retained failure case after none can call it.
            HAL.registrations = []
            if weakWatch != nil, let client {
                Unmanaged<MixerTapConfiguration>.fromOpaque(client).release()
            }
        }
        suite.expect(weakWatch == nil && HAL.registrations.isEmpty,
                     "teardown fixtures leave no retained watch or fake callback")
    }

    private static func failedRegistration(_ suite: TestSuite, format: MixerTapFormat) {
        for partial in [false, true] {
            HAL.reset()
            if partial {
                HAL.failedAddition = HAL.Key(object: aggregate, selector: kAudioDevicePropertyStreams)
            } else {
                HAL.additionStatus = kAudioHardwareUnspecifiedError
            }
            let counter = Counter()
            var watch: MixerTapConfiguration? = makeWatch(format: format, direct: false, counter: counter)
            weak var weakWatch = watch
            let started = watch?.start()
            let installed = HAL.registrations.count
            suite.expect(started == false && watch?.canRender == false && HAL.readCount == 0,
                         "\(partial ? "partial" : "total") registration failure refuses to render without every format listener")
            suite.expect(partial ? installed > 0 : installed == 0,
                         "registration failure fixtures cover both partial and empty installations")
            HAL.announce(tap, kAudioTapPropertyFormat)
            watch?.refresh(immediately: true)
            watch?.queue.run()
            suite.expect(HAL.readCount == 0 && counter.value == 0,
                         "a refused configuration remains inert while partial registrations await removal")
            watch?.stop()
            TapGainEngine.teardownQueue.run()
            watch?.queue.run()
            suite.expect(HAL.registrations.isEmpty && HAL.removalCount == installed,
                         "failed startup removes every listener it managed to install exactly once")
            watch = nil
            suite.expect(weakWatch == nil, "failed registration releases its listener retain after cleanup")
        }
    }

    private static func sharedStreamRegistration(_ suite: TestSuite, format: MixerTapFormat) {
        HAL.reset()
        let counter = Counter()
        let source = MixerTapConfiguration.Source(device: device, stream: outputStream, format: format)
        let watch = MixerTapConfiguration(tap: tap, aggregate: aggregate, objects: [process], source: source,
                                          format: format, sampleRate: 48_000, outputChannels: [8],
                                          outputFormats: [outputStream: format]) {
            counter.value += 1
        }
        let started = watch.start()
        watch.queue.run()
        defer { finish(watch, suite) }
        suite.expect(started && watch.canRender && HAL.registrations.filter {
            $0.object == outputStream && $0.address.mSelector == kAudioStreamPropertyVirtualFormat
        }.count == 1,
                     "a shared capture/output stream has one format listener and remains valid")
    }

    private static func recovery(_ suite: TestSuite) {
        let id = "app"
        let original = MixerEngineRecovery.Configuration(objects: [process], outputDeviceUID: "original-output")
        let recovery = Recovery()
        recovery.apps = [Recovery.App(id: id, audioObjects: original.objects,
                                      effectiveOutputDeviceUID: original.outputDeviceUID, needsEngine: true)]
        let invalid = Recovery.Engine(requiresRebuild: true)
        recovery.engines[id] = invalid
        recovery.engineRenderProgress[id] = MixerRoutingSupport.EngineRenderObservation(cycles: 12, at: 1)
        suite.expect(recovery.retryInvalidatedEngine(for: id),
                     "a failed replacement of an invalid format is handled as configuration recovery")
        suite.expect(invalid.stops == 1 && recovery.engines[id] == nil && recovery.engineRenderProgress[id] == nil,
                     "failed format repair stops and removes the silent engine to restore the original audio")
        suite.expect(recovery.configurationRepairs[id] != nil && recovery.scheduledDelays == [0.5]
                        && recovery.engineRecovery.allowsBuild(id, configuration: original),
                     "the first format repair failure permits one delayed retry")

        suite.expect(recovery.retryInvalidatedEngine(for: id),
                     "a second repair failure is recognized after the old engine was already removed")
        suite.expect(recovery.configurationRepairs[id] == nil && recovery.scheduledDelays == [0.5]
                        && !recovery.engineRecovery.allowsBuild(id, configuration: original),
                     "the second failure counts against the same configuration and cannot schedule an endless retry")
        suite.expect(!recovery.retryInvalidatedEngine(for: id) && recovery.scheduledDelays == [0.5],
                     "a completed repair failure sequence adds no further scheduled work")

        let changed = MixerEngineRecovery.Configuration(objects: [process + 1], outputDeviceUID: "new-output")
        suite.expect(recovery.engineRecovery.allowsBuild(id, configuration: changed),
                     "a new process/output configuration is allowed after the old configuration failed twice")
        recovery.apps = [Recovery.App(id: id, audioObjects: changed.objects,
                                      effectiveOutputDeviceUID: changed.outputDeviceUID, needsEngine: true)]
        recovery.engines[id] = Recovery.Engine(requiresRebuild: true)
        suite.expect(recovery.retryInvalidatedEngine(for: id)
                        && recovery.configurationRepairs[id] != nil
                        && recovery.scheduledDelays == [0.5, 0.5]
                        && recovery.engineRecovery.allowsBuild(id, configuration: changed),
                     "the new configuration receives its own bounded repair attempt")

        let cancellations: [(String, [Recovery.App])] = [
            ("row disappeared", []),
            ("adjustment cancelled", [Recovery.App(id: id, audioObjects: [process],
                                                   effectiveOutputDeviceUID: "original-output", needsEngine: false)]),
            ("output unavailable", [Recovery.App(id: id, audioObjects: [process],
                                                 effectiveOutputDeviceUID: nil, needsEngine: true)]),
        ]
        for (name, apps) in cancellations {
            let cancelled = Recovery()
            cancelled.apps = apps
            cancelled.configurationRepairs[id] = 20
            cancelled.engineRenderProgress[id] = MixerRoutingSupport.EngineRenderObservation(cycles: 2, at: 1)
            suite.expect(cancelled.retryInvalidatedEngine(for: id)
                            && cancelled.configurationRepairs[id] == nil
                            && cancelled.engineRenderProgress[id] == nil
                            && cancelled.scheduledDelays.isEmpty,
                         "\(name) clears a pending repair without creating another engine")
        }

        let ordinary = Recovery()
        let valid = Recovery.Engine(requiresRebuild: false)
        ordinary.engines[id] = valid
        let observation = MixerRoutingSupport.EngineRenderObservation(cycles: 21, at: 2)
        ordinary.engineRenderProgress[id] = observation
        suite.expect(!ordinary.retryInvalidatedEngine(for: id) && ordinary.engines[id] === valid
                        && valid.stops == 0 && ordinary.engineRenderProgress[id] == observation
                        && ordinary.configurationRepairs.isEmpty && ordinary.scheduledDelays.isEmpty,
                     "an ordinary failed build leaves a valid running engine to the existing failure handler")

        let settling = Recovery()
        settling.configurationRepairs[id] = 20
        suite.expect(settling.configurationRepairDelay(for: id, now: 19.75) == 0.25,
                     "an unrelated event before the repair deadline waits out the remaining settling time")
        suite.expect(settling.configurationRepairDelay(for: id, now: 20) == nil
                        && settling.configurationRepairDelay(for: id, now: 21) == nil,
                     "a retry is allowed at or after its settling deadline")
        suite.expect(settling.configurationRepairDelay(for: "other-app", now: 19.75) == nil,
                     "one app's settling interval never delays another app")
        suite.expect(settling.configurationRepairs[id] == 20,
                     "checking the deadline keeps repair identity until the subsequent build succeeds or fails")
    }
}
