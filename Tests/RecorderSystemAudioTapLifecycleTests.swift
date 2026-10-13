// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Exercises the production stop body with only HAL teardown replaced.
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
        var levelWatch: Watch? = Watch()
        var pipelineStops = 0

        private static let traceLock = NSLock()
        private static var removed: [UInt] = []
        private static var destroyed: [AudioObjectID] = []

        static func reset() { traceLock.withLock { removed = []; destroyed = [] } }
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

        func teardownPipeline() { pipelineStops += 1 }
    }

    static func run(_ suite: TestSuite) {
        Fixture.reset()
        defer { Fixture.reset() }
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
        suite.expect(tap.stopped && tap.deviceListenerClient == nil && tap.levelWatch == nil
                        && watch.stops == 1 && tap.pipelineStops == 1
                        && Fixture.trace.removed == [7] && Fixture.trace.destroyed == [91],
                     "the first stop releases the listeners, level watch, pipeline and tap once")
        guard stop(1) else { return }
        suite.expect(Fixture.trace.destroyed == [91] && tap.pipelineStops == 1 && watch.stops == 1,
                     "finalization after cancelled startup never destroys a potentially reused tap ID")
        guard stop(8) else { return }
        suite.expect(Fixture.trace.destroyed == [91] && Fixture.trace.removed == [7]
                        && tap.pipelineStops == 1 && watch.stops == 1,
                     "concurrent repeated stops complete without releasing the same resources again")
    }
}
