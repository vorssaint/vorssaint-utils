// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Exercises production stop and device-change handling with HAL calls replaced.
/// Startup cancellation and finalization can both stop the same tap.
enum RecorderSystemAudioTapLifecycleTests {
    final class Watch {
        var stops = 0
        func stop() { stops += 1 }
    }

    class Fixture: @unchecked Sendable {
        let queue = DispatchQueue(label: "test.recorder.system-audio-lifecycle")
        let tapID = AudioObjectID(91)
        var stopped = false
        var deviceListenerClient = UnsafeMutableRawPointer(bitPattern: 7)
        var processListenerClient = UnsafeMutableRawPointer(bitPattern: 8)
        var levelWatch: Watch? = Watch()
        var pipelineStops = 0
        var pipelineBuilds = 0
        var aggregateID = AudioObjectID(92)
        var hostDeviceUID: String? = "original"
        var sampleRate: Double = 48_000
        var deviceChangeReported = false
        var onDeviceChange: (() -> Void)?
        var onReaderLost: (() -> Void)?

        private static let traceLock = NSLock()
        private static var removed: [UInt] = []
        private static var destroyed: [AudioObjectID] = []
        private static var deviceUID = "original"
        private static var deviceRate: Double = 48_000

        static func reset() {
            traceLock.withLock { removed = []; destroyed = []; deviceUID = "original"; deviceRate = 48_000 }
        }
        static func device(_ uid: String, rate: Double = 48_000) {
            traceLock.withLock { deviceUID = uid; deviceRate = rate }
        }
        static func hostDeviceUID() -> String? { traceLock.withLock { deviceUID } }
        static func nominalSampleRate(of device: AudioObjectID) -> Double {
            traceLock.withLock { deviceRate }
        }
        static var trace: (removed: [UInt], destroyed: [AudioObjectID]) {
            traceLock.withLock { (removed, destroyed) }
        }

        static func removeListener(_ client: UnsafeMutableRawPointer?, from object: AudioObjectID,
                                   _ selector: AudioObjectPropertySelector) {
            guard let client else { return }
            traceLock.withLock { removed.append(UInt(bitPattern: client)) }
        }

        static func destroy(aggregateID: AudioObjectID, ioProc: AudioDeviceIOProcID?, tapID: AudioObjectID) {
            traceLock.withLock { destroyed.append(tapID) }
        }

        func teardownPipeline() { pipelineStops += 1; aggregateID = 0 }
        func buildPipeline() {
            pipelineBuilds += 1
            aggregateID = 92
            hostDeviceUID = Self.hostDeviceUID()
            sampleRate = Self.nominalSampleRate(of: aggregateID)
        }
    }

    static func run(_ suite: TestSuite) {
        Fixture.reset()
        defer { Fixture.reset() }

        let interrupted = Tap()
        var changes = 0
        interrupted.onDeviceChange = { changes += 1 }
        interrupted.queue.sync { interrupted.rebuildPipelineIfChanged() }
        suite.expect(changes == 0, "an unchanged audio device does not interrupt a recording")
        Fixture.device("new output")
        interrupted.queue.sync {
            interrupted.rebuildPipelineIfChanged()
            interrupted.rebuildPipelineIfChanged()
        }
        suite.expect(changes == 1 && interrupted.pipelineStops == 0 && interrupted.pipelineBuilds == 0,
                     "a route change reports once and leaves finalization to the audio-only owner")

        Fixture.reset()
        let rateChanged = Tap()
        var rateChanges = 0
        rateChanged.onDeviceChange = { rateChanges += 1 }
        Fixture.device("original", rate: 44_100)
        rateChanged.queue.sync { rateChanged.rebuildPipelineIfChanged() }
        suite.expect(rateChanges == 1 && rateChanged.pipelineBuilds == 0,
                     "a sample rate change also interrupts the protected recording")

        Fixture.reset()
        let video = Tap()
        Fixture.device("new output")
        video.queue.sync { video.rebuildPipelineIfChanged(); video.rebuildPipelineIfChanged() }
        suite.expect(video.pipelineStops == 1 && video.pipelineBuilds == 1 && video.hostDeviceUID == "new output",
                     "a video owner without interruption handling retains the existing one-time rebuild")

        Fixture.reset()
        let tap = Tap()
        let watch = tap.levelWatch!
        func stop(_ count: Int) -> Bool {
            let done = DispatchGroup()
            for _ in 0..<count {
                done.enter()
                Task.detached { await tap.stop(); done.leave() }
            }
            let completed = done.wait(timeout: .now() + 5) == .success
            suite.expect(completed, "every stop caller receives completion")
            return completed
        }

        guard stop(1) else { return }
        suite.expect(tap.stopped && tap.deviceListenerClient == nil && tap.processListenerClient == nil
                        && tap.levelWatch == nil && watch.stops == 1 && tap.pipelineStops == 1
                        && Fixture.trace.removed == [7, 8] && Fixture.trace.destroyed == [91],
                     "the first stop releases the listeners, level watch, pipeline and tap once")
        guard stop(1) else { return }
        suite.expect(Fixture.trace.destroyed == [91] && tap.pipelineStops == 1 && watch.stops == 1,
                     "finalization after cancelled startup never destroys a potentially reused tap ID")
        guard stop(8) else { return }
        suite.expect(Fixture.trace.destroyed == [91] && Fixture.trace.removed == [7, 8]
                        && tap.pipelineStops == 1 && watch.stops == 1,
                     "concurrent repeated stops complete without releasing the same resources again")
    }
}
