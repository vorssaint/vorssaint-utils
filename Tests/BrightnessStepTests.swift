// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

/// Runs the production brightness step against a scripted DDC read and
/// manually drained queues. No monitor is read or written.
enum BrightnessStepTests {
    final class Queue {
        var jobs: [() -> Void] = []
        func async(execute work: @escaping () -> Void) { jobs.append(work) }
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }
    enum DispatchQueue { static let main = Queue() }
    struct BrightnessDisplay {
        enum Method: Equatable { case system, ddc, gamma }
        let id: UInt32
        var brightness: Double
    }

    class Fixture {
        static let log = Logger(subsystem: "vorssaint.tests", category: "brightness-step")
        static let levelTrustWindow: TimeInterval = 3
        let stateLock = NSLock()
        let workQueue = Queue()
        var displays: [BrightnessDisplay] = []
        var levelKnownAt: [UInt32: Date] = [:]
        var ddcPendingSteps: [UInt32: Double] = [:]
        var reply: (current: UInt16, maximum: UInt16) = (0, 100)
        var routes: [UInt32: Route] = [:]
        var committed: [Double] = []
        func currentSystemBrightness(for id: UInt32, fallback: Double?) -> Double? { fallback }
        func commitStep(from current: Double, delta: Double, to displayID: UInt32,
                        method: BrightnessDisplay.Method, showOSD: Bool) {
            committed.append(current + delta)
        }
        func ddcProbeLuminance(for id: UInt32, service: CFTypeRef) -> DDCProbe {
            .replied(current: reply.current, maximum: reply.maximum)
        }
        func forgetWriteOnlyDDCPath(_ path: String?) {}
        func rememberWriteOnlyDDCPath(_ path: String?) {}
    }

    static func run(_ suite: TestSuite) {
        let service = Service()
        service.routes[2] = Route(method: .ddc, service: "monitor" as CFString, maximum: 100,
                                          ddcReadable: true, ddcPathKey: "path")
        service.displays = [BrightnessDisplay(id: 2, brightness: 0.5)]
        service.reply = (80, 100)

        service.step(2, method: .ddc, delta: 0.1, showOSD: false)
        service.workQueue.drain()
        DispatchQueue.main.drain()
        suite.expect(service.committed.last.map { abs($0 - 0.9) < 0.0001 } == true,
                     "a step after a pause starts from the level the monitor reports")

        service.levelKnownAt[2] = nil
        service.step(2, method: .ddc, delta: 0.1, showOSD: false)
        service.workQueue.drain()
        service.levelKnownAt[2] = Date()
        service.displays[0].brightness = 0.3
        DispatchQueue.main.drain()
        suite.expect(service.committed.last.map { abs($0 - 0.4) < 0.0001 } == true
                     && service.displays[0].brightness == 0.3,
                     "a level set while the monitor was read wins over the older read")

        service.routes[2]?.extendedDimming = true
        service.levelKnownAt[2] = nil
        service.displays[0].brightness = 0.125
        service.step(2, method: .ddc, delta: 0.1, showOSD: false)
        suite.expect(service.workQueue.jobs.isEmpty
                     && service.committed.last.map { abs($0 - 0.225) < 0.0001 } == true,
                     "a step in the extended software range uses the known picture level")

        service.displays[0].brightness = 0.625
        service.reply = (80, 100)
        service.step(2, method: .ddc, delta: 0.1, showOSD: false)
        service.workQueue.drain()
        DispatchQueue.main.drain()
        suite.expect(service.committed.last.map { abs($0 - 0.95) < 0.0001 } == true,
                     "a stale hardware-range step maps the monitor's actual DDC level")
    }
}
