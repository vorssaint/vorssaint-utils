// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

/// Runs the production brightness step and system write against a scripted
/// DDC read, a scripted system pipeline and manually drained queues. No
/// monitor is read or written.
enum BrightnessStepTests {
    final class Queue {
        var jobs: [() -> Void] = []
        func async(execute work: @escaping () -> Void) { jobs.append(work) }
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }
    enum DispatchQueue { static let main = Queue() }
    /// The system brightness pipeline, with the level it reports and what
    /// its easing call does with a change.
    enum BrightnessBridge {
        enum Easing { case lands, refused, ignored }
        static var level: Float = 0.5
        static var easing = Easing.lands
        static var calls: [String] = []
        static var getBrightness: ((UInt32, UnsafeMutablePointer<Float>) -> Int32)? = { _, reading in
            reading.pointee = BrightnessBridge.level
            return 0
        }
        static var setBrightness: ((UInt32, Float) -> Int32)? = { _, value in
            BrightnessBridge.calls.append("set \(value)")
            BrightnessBridge.level = value
            return 0
        }
        static var setBrightnessSmooth: ((UInt32, Float) -> Int32)? = { _, change in
            BrightnessBridge.calls.append("ease \(change)")
            switch BrightnessBridge.easing {
            case .lands:
                BrightnessBridge.level += change
                return 0
            case .refused:
                return 1000
            case .ignored:
                return 0
            }
        }
    }
    static var displayAsleep = false
    static func CGDisplayIsAsleep(_ id: UInt32) -> UInt32 { displayAsleep ? 1 : 0 }
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
        var dimmedDisplays = Set<UInt32>()
        var writes: [UInt16] = []
        func applySoftwareDim(_ id: UInt32, value: Double) -> Bool { true }
        func ddcSend(to id: UInt32, service: CFTypeRef, packet: [UInt8]) -> Bool {
            writes.append(UInt16(packet[3]) << 8 | UInt16(packet[4]))
            return true
        }
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

        service.routes[2]?.lastDDCValue = 50
        service.levelKnownAt[2] = nil
        service.displays[0].brightness = 0.625
        service.reply = (58, 100)
        service.step(2, method: .ddc, delta: -BrightnessSupport.brightnessKeyStep, showOSD: false)
        service.workQueue.drain()
        DispatchQueue.main.drain()
        let written = service.writeExtendedBrightness(service.committed.last!, to: 2,
                                                       route: service.routes[2]!, service: "monitor" as CFString)
        suite.expect(written && service.writes == [50],
                     "a physical monitor adjustment cannot suppress a step back to the app's previous value")

        // A key step on a system display eases by the change from the level
        // the system reports. Everything else writes the level itself, once,
        // so a change the system refuses or ignores is never added twice
        // (issue #2149).
        func systemWrite(_ value: Double, from level: Float, smooth: Bool = true,
                         easing: BrightnessBridge.Easing = .lands)
            -> (written: Bool, calls: [String], level: Float) {
            BrightnessBridge.level = level
            BrightnessBridge.easing = easing
            BrightnessBridge.calls = []
            let written = Service.writeSystemBrightness(value, to: 1, smooth: smooth)
            return (written, BrightnessBridge.calls, BrightnessBridge.level)
        }
        let eased = systemWrite(0.5625, from: 0.5)
        suite.expect(eased.written && eased.calls == ["ease 0.0625"] && eased.level == 0.5625,
                     "a key step on a system display eases by the change from the reported level")
        let slider = systemWrite(0.25, from: 0.5, smooth: false)
        suite.expect(slider.written && slider.calls == ["set 0.25"] && slider.level == 0.25,
                     "a slider write on a system display lands at once")
        let fallback = ["ease 0.0625", "set 0.5625"]
        let refused = systemWrite(0.5625, from: 0.5, easing: .refused)
        suite.expect(refused.written && refused.calls == fallback && refused.level == 0.5625,
                     "an eased step the system refuses gets the level written directly")
        let ignored = systemWrite(0.5625, from: 0.5, easing: .ignored)
        suite.expect(ignored.written && ignored.calls == fallback && ignored.level == 0.5625,
                     "an eased step the system ignores gets the level written once, never the change twice")
        let atEnd = systemWrite(1, from: 1)
        suite.expect(atEnd.written && atEnd.calls == ["set 1.0"] && atEnd.level == 1,
                     "a step already at the end of the range writes the level without easing")
        displayAsleep = true
        let asleep = systemWrite(0.5625, from: 0.5)
        displayAsleep = false
        suite.expect(asleep.written && asleep.calls == ["set 0.5625"],
                     "an asleep display gets the level directly")
        let smoothCall = BrightnessBridge.setBrightnessSmooth
        BrightnessBridge.setBrightnessSmooth = nil
        let missing = systemWrite(0.5625, from: 0.5)
        BrightnessBridge.setBrightnessSmooth = smoothCall
        suite.expect(missing.written && missing.calls == ["set 0.5625"],
                     "a system without the easing call gets the level directly")
    }
}
