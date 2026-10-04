// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The ring between a tapped app's IO thread and the AirPlay feed. Frame
/// positions only ever grow, so an all-day stream must stay correct once they
/// pass the 32-bit range (about 12 hours at 48 kHz).
enum AirPlayRingBufferContract {
    static func run(_ suite: TestSuite) {
        roundTrip(suite)
        fullRingDropsNewestFrames(suite)
        positionsPastThirtyTwoBits(suite)
        otherChannelLayouts(suite)
        rendererWatch(suite)
    }

    /// The tap index can hand back a lone buffer that does not have the tap's
    /// two channels. Read as stereo, a mono one would run past its end on the
    /// IO thread.
    private static func otherChannelLayouts(_ suite: TestSuite) {
        let mono = AudioRingBuffer(sampleRate: 48_000, capacityFrames: 64)
        let monoInput: [Float] = [1, 2, 3, 4]
        monoInput.withUnsafeBufferPointer { mono.write(frames: $0.baseAddress!, frameCount: 4, channels: 1, gain: 1) }
        var monoOutput = [Float](repeating: 0, count: 4 * 2)
        let monoRead = monoOutput.withUnsafeMutableBufferPointer { mono.read(into: $0.baseAddress!, frameCount: 4) }
        suite.expect(monoRead == 4 && monoOutput == [1, 1, 2, 2, 3, 3, 4, 4],
                     "a mono buffer plays on both sides and is read only as far as it goes")

        let surround = AudioRingBuffer(sampleRate: 48_000, capacityFrames: 64)
        let surroundInput: [Float] = [1, -1, 9, 9, 2, -2, 9, 9]
        surroundInput.withUnsafeBufferPointer {
            surround.write(frames: $0.baseAddress!, frameCount: 2, channels: 4, gain: 1)
        }
        var surroundOutput = [Float](repeating: 0, count: 2 * 2)
        let surroundRead = surroundOutput.withUnsafeMutableBufferPointer {
            surround.read(into: $0.baseAddress!, frameCount: 2)
        }
        suite.expect(surroundRead == 2 && surroundOutput == [1, -1, 2, -2],
                     "of more channels only the first two are kept, frame by frame")
    }

    /// A renderer that fails, or stops taking audio far longer than a hiccup
    /// once playback got going, is reported once so its apps fall back to the
    /// Mac. A speaker still connecting is never taken for a stall.
    private static func rendererWatch(_ suite: TestSuite) {
        var failing = AirPlayRendererWatch()
        suite.expect(!failing.shouldReport(failed: false, ready: true, playing: false, now: 0)
                        && failing.shouldReport(failed: true, ready: true, playing: false, now: 1)
                        && !failing.shouldReport(failed: true, ready: false, playing: true, now: 2),
                     "a failed renderer is reported, and only once")

        var stalling = AirPlayRendererWatch()
        let limit = AirPlayRendererWatch.stallLimit
        suite.expect(!stalling.shouldReport(failed: false, ready: false, playing: true, now: 0)
                        && !stalling.shouldReport(failed: false, ready: false, playing: true, now: limit - 1)
                        && stalling.shouldReport(failed: false, ready: false, playing: true, now: limit + 1),
                     "a playing renderer that takes no audio for longer than the limit is reported")

        var connecting = AirPlayRendererWatch()
        var reportedWhileConnecting = false
        for second in stride(from: 0.0, through: limit * 4, by: 1) {
            reportedWhileConnecting = reportedWhileConnecting
                || connecting.shouldReport(failed: false, ready: false, playing: false, now: second)
        }
        suite.expect(!reportedWhileConnecting
                        && !connecting.shouldReport(failed: false, ready: false, playing: true, now: limit * 4 + 1),
                     "a speaker that takes long to connect is not a stall, and the limit starts once it plays")

        var silent = AirPlayRendererWatch()
        let start = AirPlayRendererWatch.startLimit
        suite.expect(!silent.shouldReport(failed: false, ready: true, playing: false, now: 0)
                        && !silent.shouldReport(failed: false, ready: true, playing: false, now: start - 1)
                        && silent.shouldReport(failed: false, ready: true, playing: false, now: start + 1),
                     "a speaker that never starts playing is reported, after far longer than a slow connection")

        var busy = AirPlayRendererWatch()
        var reported = false
        for second in stride(from: 0.0, through: limit * 3, by: 1) {
            reported = reported || busy.shouldReport(failed: false, ready: Int(second) % 4 == 0, playing: true,
                                                     now: second)
        }
        suite.expect(!reported, "a renderer that keeps taking audio now and then is never reported")
    }

    private static func frames(_ count: Int, from start: Int) -> [Float] {
        (0..<count).flatMap { [Float(start + $0), -Float(start + $0)] }
    }

    private static func roundTrip(_ suite: TestSuite) {
        let ring = AudioRingBuffer(sampleRate: 48_000, capacityFrames: 64)
        let input = frames(10, from: 1)
        input.withUnsafeBufferPointer { ring.write(frames: $0.baseAddress!, frameCount: 10, gain: 0.5) }

        var output = [Float](repeating: 99, count: 16 * 2)
        let read = output.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, frameCount: 16) }
        suite.expect(read == 10, "a read returns only the frames that were written")
        suite.expect(output[0] == 0.5 && output[1] == -0.5 && output[18] == 5 && output[19] == -5,
                     "written frames come back in order with the gain applied")
        suite.expect(output[20...].allSatisfy { $0 == 0 }, "the rest of a short read is silence")
    }

    private static func fullRingDropsNewestFrames(_ suite: TestSuite) {
        let ring = AudioRingBuffer(sampleRate: 48_000, capacityFrames: 8)
        let input = frames(12, from: 1)
        input.withUnsafeBufferPointer { ring.write(frames: $0.baseAddress!, frameCount: 12, gain: 1) }

        var output = [Float](repeating: 0, count: 12 * 2)
        let read = output.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, frameCount: 12) }
        suite.expect(read == 8 && output[14] == 8, "a full ring keeps the oldest frames and drops the overflow")
    }

    private static func positionsPastThirtyTwoBits(_ suite: TestSuite) {
        let start = Int64(Int32.max) - 100
        let ring = AudioRingBuffer(sampleRate: 48_000, capacityFrames: 1 << 10, startingFramePosition: start)
        var output = [Float](repeating: 0, count: 256 * 2)
        var delivered = 0
        var inOrder = true
        // Stream across the old wrap point in IO-sized chunks.
        for chunk in 0..<8 {
            let input = frames(256, from: chunk * 256)
            input.withUnsafeBufferPointer { ring.write(frames: $0.baseAddress!, frameCount: 256, gain: 1) }
            let read = output.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, frameCount: 256) }
            delivered += read
            inOrder = inOrder && output[0] == Float(chunk * 256) && output[510] == Float(chunk * 256 + 255)
        }
        suite.expect(delivered == 8 * 256 && inOrder,
                     "streaming continues without loss once frame positions pass the 32-bit range")
    }
}

/// Only Vorssaint's own AirPlay entry streams through the route picker. Every
/// other output, including AirPlay devices macOS exposes, follows the normal
/// device rules: listed means usable, missing means fall back to the default.
enum AirPlayRouteContract {
    static func run(_ suite: TestSuite) {
        let sentinel = AirPlayRouteManager.airPlaySentinelUID
        // Real AirPlay outputs carry a session UID; third-party virtual drivers
        // may well mention AirPlay in theirs.
        let macOSAirPlay = "50ea6ba0-8555-4fce-b618-b4cb1729da75-326608458962375-Audio"
        let namedLikeAirPlay = "com.example.AirPlayReceiver.output"

        suite.expect(MixerRoutingSupport.isAirPlaySentinel(sentinel)
                     && !MixerRoutingSupport.isAirPlaySentinel(macOSAirPlay)
                     && !MixerRoutingSupport.isAirPlaySentinel(namedLikeAirPlay)
                     && !MixerRoutingSupport.isAirPlaySentinel("AirPlay"),
                     "only the exact AirPlay entry counts as the picker route")

        let listed: Set<String> = ["BuiltInSpeakerDevice", sentinel]
        suite.expect(MixerRoutingSupport.effectiveDeviceUID(selectedUID: sentinel,
                                                            availableUIDs: listed,
                                                            defaultUID: "BuiltInSpeakerDevice") == sentinel
                     && !MixerRoutingSupport.selectedDeviceUnavailable(selectedUID: sentinel,
                                                                       availableUIDs: listed),
                     "a listed AirPlay entry is used as the app's route")

        let unlisted: Set<String> = ["BuiltInSpeakerDevice"]
        suite.expect(MixerRoutingSupport.effectiveDeviceUID(selectedUID: sentinel,
                                                            availableUIDs: unlisted,
                                                            defaultUID: "BuiltInSpeakerDevice") == "BuiltInSpeakerDevice"
                     && MixerRoutingSupport.selectedDeviceUnavailable(selectedUID: sentinel,
                                                                      availableUIDs: unlisted),
                     "without the picker API the AirPlay route falls back and shows as unavailable")

        suite.expect(MixerRoutingSupport.effectiveDeviceUID(selectedUID: namedLikeAirPlay,
                                                            availableUIDs: unlisted,
                                                            defaultUID: "BuiltInSpeakerDevice") == "BuiltInSpeakerDevice"
                     && MixerRoutingSupport.selectedDeviceUnavailable(selectedUID: namedLikeAirPlay,
                                                                      availableUIDs: unlisted),
                     "a missing output that mentions AirPlay falls back like any other device")

        connection(suite, sentinel: sentinel)
        unavailableRow(suite, sentinel: sentinel)
        engineOutput(suite, sentinel: sentinel)
    }

    /// An engine streaming to AirPlay while no speaker is picked can only mute
    /// its app, so the mixer must treat its output as gone, like an unplugged
    /// device, instead of keeping it until a replacement happens to succeed.
    private static func engineOutput(_ suite: TestSuite, sentinel: String) {
        let listed = ["BuiltInSpeakerDevice", "HeadsetOutput", sentinel]
        suite.expect(!MixerRoutingSupport.engineOutputIsPresent(sentinel, listedUIDs: listed, airPlayConnected: false),
                     "a listed AirPlay entry without a speaker counts as gone for a running engine")
        suite.expect(MixerRoutingSupport.engineOutputIsPresent(sentinel, listedUIDs: listed, airPlayConnected: true),
                     "with a speaker picked the AirPlay engine keeps running")
        suite.expect(MixerRoutingSupport.engineOutputIsPresent("HeadsetOutput", listedUIDs: listed, airPlayConnected: false)
                     && !MixerRoutingSupport.engineOutputIsPresent("UnpluggedHeadphones", listedUIDs: listed,
                                                                   airPlayConnected: true),
                     "other outputs count as present exactly while they are listed")
        // The Mac output clocking an AirPlay stream, gone (headphones turned
        // off), stops its tap: the engine is rebuilt on the output there now.
        suite.expect(MixerRoutingSupport.engineOutputIsPresent(sentinel, clockUID: "HeadsetOutput", listedUIDs: listed,
                                                               airPlayConnected: true)
                     && !MixerRoutingSupport.engineOutputIsPresent(sentinel, clockUID: "UnpluggedHeadphones",
                                                                   listedUIDs: listed, airPlayConnected: true),
                     "an AirPlay engine counts as gone once the output clocking it is gone")
        suite.expect(MixerRoutingSupport.engineOutputIsPresent("HeadsetOutput", clockUID: "UnpluggedHeadphones",
                                                               listedUIDs: listed, airPlayConnected: false),
                     "only an AirPlay engine depends on a clock output")
    }

    /// The AirPlay entry stays listed while no speaker is picked; the app's
    /// menu must keep that row selected instead of adding a second one.
    private static func unavailableRow(_ suite: TestSuite, sentinel: String) {
        let listed = ["BuiltInSpeakerDevice", "HeadsetOutput", sentinel]
        suite.expect(MixerRoutingSupport.needsUnavailableOutputRow(selectedUID: "UnpluggedHeadphones",
                                                                   isUnavailable: true, listedUIDs: listed),
                     "an unplugged output that is no longer listed still gets its unavailable row")
        suite.expect(!MixerRoutingSupport.needsUnavailableOutputRow(selectedUID: sentinel,
                                                                    isUnavailable: true, listedUIDs: listed),
                     "the listed AirPlay entry keeps its own row instead of a duplicate unavailable row")
        suite.expect(!MixerRoutingSupport.needsUnavailableOutputRow(selectedUID: "HeadsetOutput",
                                                                    isUnavailable: false, listedUIDs: listed)
                     && !MixerRoutingSupport.needsUnavailableOutputRow(selectedUID: nil,
                                                                       isUnavailable: true, listedUIDs: listed),
                     "an available or unset output never gets the unavailable row")
    }

    /// Losing the speaker must hand the app back to the default output, not
    /// keep it tapped and silent; picking one again restores the AirPlay route.
    private static func connection(_ suite: TestSuite, sentinel: String) {
        let listedOutputs = ["BuiltInSpeakerDevice", "HeadsetOutput", sentinel]

        let disconnected = MixerRoutingSupport.routableOutputUIDs(listedOutputs, airPlayConnected: false)
        suite.expect(disconnected == ["BuiltInSpeakerDevice", "HeadsetOutput"],
                     "without a picked speaker the AirPlay entry carries no audio")
        suite.expect(MixerRoutingSupport.effectiveDeviceUID(selectedUID: sentinel,
                                                            availableUIDs: disconnected,
                                                            defaultUID: "HeadsetOutput") == "HeadsetOutput"
                     && MixerRoutingSupport.selectedDeviceUnavailable(selectedUID: sentinel,
                                                                      availableUIDs: disconnected),
                     "an app routed to AirPlay plays on the default output while no speaker is picked")
        suite.expect(!MixerRoutingSupport.requiresEngine(volume: 1,
                                                         selectedOutputDeviceUID: sentinel,
                                                         targetOutputDeviceUID: "HeadsetOutput",
                                                         defaultOutputDeviceUID: "HeadsetOutput"),
                     "at 100% that fallback is untapped passthrough, not a muting tap")

        let connected = MixerRoutingSupport.routableOutputUIDs(listedOutputs, airPlayConnected: true)
        suite.expect(MixerRoutingSupport.effectiveDeviceUID(selectedUID: sentinel,
                                                            availableUIDs: connected,
                                                            defaultUID: "HeadsetOutput") == sentinel,
                     "picking a speaker again restores the AirPlay route")
        suite.expect(MixerRoutingSupport.effectiveDeviceUID(selectedUID: "BuiltInSpeakerDevice",
                                                            availableUIDs: disconnected,
                                                            defaultUID: "HeadsetOutput") == "BuiltInSpeakerDevice",
                     "other routes are untouched by the AirPlay connection")
    }
}

/// Boosted apps, or several loud apps together, must not be hard-clipped on
/// their way to the speaker (the AirPlay twin of issue #326).
enum AirPlayMixLimiterContract {
    static func run(_ suite: TestSuite) {
        let mixer = MixingAudioSource()
        let frames = 4096
        let loud = [Float](repeating: 0.9, count: frames * 2)
        for key in ["a", "b"] {
            let ring = AudioRingBuffer(sampleRate: 44_100, capacityFrames: frames)
            loud.withUnsafeBufferPointer { ring.write(frames: $0.baseAddress!, frameCount: frames, gain: 1) }
            mixer.setBuffer(ring, forKey: key)
        }

        var output = [Int16](repeating: 0, count: frames * 2)
        output.withUnsafeMutableBufferPointer { mixer.readFrames(into: $0.baseAddress!, frameCount: frames) }
        let ceiling = Int16(BoostLimiter.ceiling * 32_767)
        let settled = output[(frames - 64) * 2..<frames * 2]
        suite.expect(settled.allSatisfy { abs(Int($0) - Int(ceiling)) <= 2 },
                     "a mix past full scale is limited to the ceiling instead of clipped")

        let quiet = MixingAudioSource()
        let ring = AudioRingBuffer(sampleRate: 44_100, capacityFrames: frames)
        [Float](repeating: 0.25, count: frames * 2)
            .withUnsafeBufferPointer { ring.write(frames: $0.baseAddress!, frameCount: frames, gain: 1) }
        quiet.setBuffer(ring, forKey: "a")
        output.withUnsafeMutableBufferPointer { quiet.readFrames(into: $0.baseAddress!, frameCount: frames) }
        suite.expect(output[(frames - 1) * 2] == Int16(0.25 * 32_767),
                     "a mix inside full scale passes through at its level")
    }
}

/// An app is heard once in the AirPlay mix, through its newest live engine.
/// A replacement registers before its predecessor stops, so the mix must not
/// carry both, and ending one engine must never remove another one's stream.
enum AirPlayStreamRegistryContract {
    /// One engine: its ring and its registration. Engines keep writing after
    /// they register, like a running tap.
    private final class Engine {
        let ring = AudioRingBuffer(sampleRate: 44_100, capacityFrames: 1 << 15)
        var registration: AirPlayStreamRegistration!
        func write(_ level: Float, frames: Int = 4_096) {
            [Float](repeating: level, count: frames * 2)
                .withUnsafeBufferPointer { ring.write(frames: $0.baseAddress!, frameCount: frames, gain: 1) }
        }
    }

    static func run(_ suite: TestSuite) {
        let mixer = MixingAudioSource()
        let registry = AirPlayStreamRegistry(mixer: mixer)
        var emptied: [Bool] = []
        func start(_ appID: String) -> Engine {
            let engine = Engine()
            engine.registration = registry.register(appID: appID, buffer: engine.ring) { token in
                emptied.append(registry.remove(token))
            }
            return engine
        }
        /// Reads one block of the mix and answers whether it settled at `level`.
        func heard(_ level: Float) -> Bool {
            var output = [Int16](repeating: 0, count: 2_048 * 2)
            output.withUnsafeMutableBufferPointer { mixer.readFrames(into: $0.baseAddress!, frameCount: 2_048) }
            return abs(Int(output[2_047 * 2]) - Int(Int16(level * 32_767))) <= 2
        }

        let previous = start("app.first")
        previous.write(0.1)
        let replacement = start("app.first")
        previous.write(0.1)
        replacement.write(0.2)
        suite.expect(heard(0.2),
                     "while the previous engine still runs, the mix carries the app once, from the replacement")

        previous.registration.end()
        replacement.write(0.2)
        suite.expect(emptied == [false] && heard(0.2),
                     "stopping the previous engine keeps the replacement's stream playing")
        previous.registration.end()
        replacement.write(0.2)
        suite.expect(emptied == [false] && heard(0.2), "a second stop (from deinit) changes nothing")

        let discarded = start("app.first")
        discarded.write(0.3)
        replacement.write(0.2)
        discarded.registration.end()
        replacement.write(0.2)
        suite.expect(emptied == [false, false] && heard(0.2),
                     "a discarded build hands the app back to the engine that is still running")

        // The engine heard again kept writing while hidden; the mix continues
        // with what it writes from now on, not with that backlog.
        let hidden = start("app.second")
        hidden.write(0.4)
        replacement.write(0.2)
        _ = heard(0.6)
        let brief = start("app.second")
        hidden.write(0.4, frames: 16_384)
        brief.registration.end()
        hidden.write(0.5)
        replacement.write(0.2)
        suite.expect(heard(0.7), "a lane that falls back starts at new audio, not at its hidden backlog")
        hidden.registration.end()

        let other = start("app.third")
        other.write(0.05)
        replacement.write(0.2)
        suite.expect(heard(0.25), "different apps are mixed together")

        replacement.registration.end()
        other.write(0.05)
        suite.expect(emptied.last == false && heard(0.05), "ending one app leaves the others")
        other.registration.end()
        suite.expect(emptied.last == true && emptied.dropLast().allSatisfy { !$0 },
                     "only the last live stream reports the mix as empty")
    }
}

/// Stopping a renderer's feed waits for a running step, and no step starts
/// afterwards, so a replacement renderer never shares the mix with it.
enum AirPlayFeedDriverContract {
    static func run(_ suite: TestSuite) {
        let queue = DispatchQueue(label: "test.airplay.feed")
        let driver = AirPlayFeedDriver(queue: queue, interval: .milliseconds(5))
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var steps = 0
        var blockNext = true

        driver.start {
            lock.lock()
            steps += 1
            let block = blockNext
            blockNext = false
            lock.unlock()
            if block {
                entered.signal()
                release.wait()
            }
        }
        suite.expect(entered.wait(timeout: .now() + 2) == .success, "the feed step runs")

        let stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            driver.stop()
            stopped.signal()
        }
        suite.expect(stopped.wait(timeout: .now() + 0.2) == .timedOut,
                     "stop waits while a feed step is still running")
        release.signal()
        suite.expect(stopped.wait(timeout: .now() + 2) == .success, "stop returns once the step finished")

        lock.lock(); let atStop = steps; lock.unlock()
        Thread.sleep(forTimeInterval: 0.05)
        lock.lock(); let later = steps; lock.unlock()
        suite.expect(later == atStop, "no feed step runs after stop returned")

        let selfStopping = AirPlayFeedDriver(queue: queue, interval: .milliseconds(5))
        let finished = DispatchSemaphore(value: 0)
        selfStopping.start {
            selfStopping.stop()
            finished.signal()
        }
        suite.expect(finished.wait(timeout: .now() + 2) == .success, "a step may stop its own driver without deadlocking")
    }
}

/// The clock device can renegotiate its rate under a running tap (a headset
/// taking a call). The AirPlay feed must follow the new rate at once, or the
/// app plays at the wrong speed on the speaker.
enum AirPlayRateChangeContract {
    static func run(_ suite: TestSuite) {
        let ring = AudioRingBuffer(sampleRate: 44_100, capacityFrames: 1 << 14)
        // Each frame carries its own index, so the output shows which source
        // frame it came from.
        let ramp = (0..<8_192).flatMap { [Float($0), Float($0)] }
        ramp.withUnsafeBufferPointer { ring.write(frames: $0.baseAddress!, frameCount: 8_192, gain: 1) }
        let resampler = LinearResampler(buffer: ring)
        var output = [Float](repeating: 0, count: 1_024 * 2)

        output.withUnsafeMutableBufferPointer { resampler.read(into: $0.baseAddress!, frameCount: 1_024) }
        suite.expect(output[1_023 * 2] == 1_023, "at the feed's own rate every source frame is played once")

        ring.sampleRate = 48_000
        output.withUnsafeMutableBufferPointer { resampler.read(into: $0.baseAddress!, frameCount: 1_024) }
        let expected = 1_024 + 1_023 * 48_000 / 44_100.0
        suite.expect(abs(Double(output[1_023 * 2]) - expected) < 1,
                     "after a rate change the feed consumes source frames at the new rate")
        suite.expect(ring.sampleRate == 48_000, "the ring reports the renegotiated rate")
    }
}

/// The routing objects are private and may lose a property in a future macOS.
/// Reading one that is gone must answer nil, not raise.
enum AirPlayPrivateAPIContract {
    private final class Device: NSObject {
        @objc let name = "Living Room Speaker"
    }

    static func run(_ suite: TestSuite) {
        suite.expect(AirPlayPrivateAPI.string(Device(), "name") == "Living Room Speaker",
                     "a property that exists is read")
        suite.expect(AirPlayPrivateAPI.string(Device(), "ID") == nil,
                     "a property this object does not have answers nil instead of raising")
        suite.expect(AirPlayPrivateAPI.string(NSObject(), "name") == nil,
                     "an object without the key answers nil")
    }
}

/// AirPlay hides itself unless every private piece it needs is present; a
/// picker that cannot be bound would move the whole Mac's output instead.
enum AirPlayAvailabilityContract {
    static func run(_ suite: TestSuite) {
        func available(mixer: Bool = true, context: Bool = true, id: String? = "context-id",
                       picker: Bool = true, renderer: Bool = true) -> Bool {
            AirPlayAvailability.isAvailable(mixerSupported: mixer, hasContext: context, contextID: id,
                                            pickerCanBind: picker, rendererCanBind: renderer)
        }
        suite.expect(available(), "AirPlay is offered when every piece is present")
        suite.expect(!available(mixer: false), "not on a system it was not tried on (before macOS 27)")
        suite.expect(!available(context: false), "not without the routing context")
        suite.expect(!available(id: nil) && !available(id: ""), "not when the context id cannot be read")
        suite.expect(!available(picker: false), "not when the picker cannot be bound to the context")
        suite.expect(!available(renderer: false), "not when the renderer cannot be bound to the context")

        suite.expect(AirPlayAvailability.isConnected(hasDevice: true, speakerName: "Speaker", failedSpeakerName: nil),
                     "a picked speaker with a name counts as connected")
        suite.expect(!AirPlayAvailability.isConnected(hasDevice: true, speakerName: "Speaker", failedSpeakerName: "Speaker"),
                     "the speaker streaming just failed for does not, so apps show unavailable instead of claiming AirPlay")
        suite.expect(AirPlayAvailability.isConnected(hasDevice: true, speakerName: "Other", failedSpeakerName: "Speaker"),
                     "picking another speaker is a fresh try")
        suite.expect(!AirPlayAvailability.isConnected(hasDevice: false, speakerName: "Speaker", failedSpeakerName: nil)
                     && !AirPlayAvailability.isConnected(hasDevice: true, speakerName: nil, failedSpeakerName: nil),
                     "no device or no name is not connected")
    }
}

/// Lanes are switched on whichever thread starts or stops an engine while the
/// feed keeps reading on its own queue. Only the feed may move a ring's read
/// position, or both move it at once and a read runs past what was written.
enum AirPlayConcurrentLanesContract {
    static func run(_ suite: TestSuite) {
        let mixer = MixingAudioSource()
        let registry = AirPlayStreamRegistry(mixer: mixer)
        let running = AudioRingBuffer(sampleRate: 44_100, capacityFrames: 1 << 14)
        let long = registry.register(appID: "app.first", buffer: running) { token in _ = registry.remove(token) }
        let stop = DispatchSemaphore(value: 0)
        let finished = DispatchGroup()

        // Like the real pipeline: the tap writes small IO blocks on its own
        // thread while the feed reads large chunks on another.
        finished.enter()
        DispatchQueue.global().async {
            let block = [Float](repeating: 0.1, count: 64 * 2)
            while stop.wait(timeout: .now()) == .timedOut {
                block.withUnsafeBufferPointer { running.write(frames: $0.baseAddress!, frameCount: 64, gain: 1) }
            }
            finished.leave()
        }
        finished.enter()
        DispatchQueue.global().async {
            var output = [Int16](repeating: 0, count: 2_048 * 2)
            while stop.wait(timeout: .now()) == .timedOut {
                output.withUnsafeMutableBufferPointer { mixer.readFrames(into: $0.baseAddress!, frameCount: 2_048) }
            }
            finished.leave()
        }
        for _ in 0..<5_000 {
            let replacement = AudioRingBuffer(sampleRate: 44_100, capacityFrames: 1 << 12)
            let registration = registry.register(appID: "app.first", buffer: replacement) { token in _ = registry.remove(token) }
            registration.end()
        }
        stop.signal()
        stop.signal()
        suite.expect(finished.wait(timeout: .now() + 5) == .success,
                     "lanes switching while the feed reads never break the reader")
        suite.expect(running.availableFrames <= 1 << 14, "the running ring never reads past what was written")
        long.end()

        // The invariant behind it, deterministically: switching lanes records
        // where to start and leaves every read position alone; only the next
        // read on the feed queue moves it.
        let quietMixer = MixingAudioSource()
        let quietRegistry = AirPlayStreamRegistry(mixer: quietMixer)
        let heard = AudioRingBuffer(sampleRate: 44_100, capacityFrames: 1 << 14)
        let first = quietRegistry.register(appID: "app.first", buffer: heard) { token in _ = quietRegistry.remove(token) }
        let backlog = [Float](repeating: 0.1, count: 3_000 * 2)
        backlog.withUnsafeBufferPointer { heard.write(frames: $0.baseAddress!, frameCount: 3_000, gain: 1) }
        let brief = quietRegistry.register(appID: "app.first",
                                           buffer: AudioRingBuffer(sampleRate: 44_100, capacityFrames: 1 << 12)) { token in
            _ = quietRegistry.remove(token)
        }
        brief.end()
        suite.expect(heard.availableFrames == 3_000,
                     "switching lanes does not move a ring's read position from outside the feed")
        var output = [Int16](repeating: 0, count: 512 * 2)
        output.withUnsafeMutableBufferPointer { quietMixer.readFrames(into: $0.baseAddress!, frameCount: 512) }
        suite.expect(heard.availableFrames == 0, "the feed's next read skips the backlog")
        first.end()
    }
}

/// Audio that piled up while the renderer was not reading must not turn into
/// delay for the rest of the session, while normal feeding keeps every frame.
enum AirPlayBacklogContract {
    static func run(_ suite: TestSuite) {
        func ring(holding frames: Int) -> AudioRingBuffer {
            let ring = AudioRingBuffer(sampleRate: 44_100, capacityFrames: 1 << 16)
            let block = (0..<frames).flatMap { [Float($0), Float($0)] }
            block.withUnsafeBufferPointer { ring.write(frames: $0.baseAddress!, frameCount: frames, gain: 1) }
            return ring
        }
        var output = [Float](repeating: 0, count: 1_024 * 2)

        let stalled = ring(holding: 44_100)
        LinearResampler(buffer: stalled).read(into: &output, frameCount: 1_024)
        suite.expect(stalled.availableFrames <= Int(44_100 * LinearResampler.keptBacklog),
                     "a second of backlog is cut down to the kept margin")
        suite.expect(output[0] >= Float(44_100 - Int(44_100 * LinearResampler.keptBacklog) - 1),
                     "playback continues from the newest audio, not the oldest")

        let normal = ring(holding: 4_096)
        LinearResampler(buffer: normal).read(into: &output, frameCount: 1_024)
        suite.expect(normal.availableFrames == 4_096 - 1_024 && output[0] == 0,
                     "a normal amount of buffered audio is played in full")
    }
}
