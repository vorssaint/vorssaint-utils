// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

/// Runs the production brightness step and system write against a scripted
/// DDC read, a scripted system pipeline and manually drained queues. No
/// monitor is read or written.
enum BrightnessStepTests {
    typealias UserDefaults = SoftwareDimmingRouteContract.UserDefaults

    final class Queue {
        var jobs: [() -> Void] = []
        func async(execute work: @escaping () -> Void) { jobs.append(work) }
        func drainNext() { if !jobs.isEmpty { jobs.removeFirst()() } }
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
        enum Method: Equatable { case system, ddc, software }
        let id: UInt32
        var brightness: Double
        var method: Method = .ddc
    }

    class Fixture {
        static let log = Logger(subsystem: "vorssaint.tests", category: "brightness-step")
        static let levelTrustWindow: TimeInterval = 3
        let stateLock = NSLock()
        let workQueue = Queue()
        var displays: [BrightnessDisplay] = []
        var levelKnownAt: [UInt32: Date] = [:]
        var ddcPendingSteps: [UInt32: (request: UUID, delta: Double)] = [:]
        var pendingLevels: [UInt32: Double] = [:]
        var lastApplied: [UInt32: Double] = [:]
        var focusedDisplayID: UInt32?
        func focusKeyDisplay(_ id: UInt32) { focusedDisplayID = id }
        var reply: (current: UInt16, maximum: UInt16) = (0, 100)
        var routes: [UInt32: Route] = [:]
        var committed: [Double] = []
        var dimmedDisplays = Set<UInt32>()
        var writes: [UInt16] = []
        var refreshes = 0
        func refresh(force: Bool = false) { refreshes += 1 }
        func applySoftwareDim(_ id: UInt32, value: Double) -> Bool { true }
        func ddcSend(to id: UInt32, service: CFTypeRef, packet: [UInt8]) -> Bool {
            writes.append(UInt16(packet[3]) << 8 | UInt16(packet[4]))
            return true
        }
        func currentSystemBrightness(for id: UInt32, fallback: Double?) -> Double? { fallback }
        func setBrightness(_ value: Double, for displayID: UInt32,
                           showOSD: Bool = false, smooth: Bool = false) {
            committed.append(value)
            pendingLevels[displayID] = value
        }
        func ddcProbe(_ code: UInt8, for id: UInt32, service: CFTypeRef,
                      classifyingChannel: Bool = false) -> DDCProbe {
            .replied(current: reply.current, maximum: reply.maximum)
        }
        func forgetWriteOnlyDDCPath(_ path: String?) {}
        func rememberWriteOnlyDDCPath(_ path: String?) {}
    }

    static func run(_ suite: TestSuite) {
        UserDefaults.standard = UserDefaults.Store()
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
        suite.expect(service.focusedDisplayID == 2, "the island's brightness level follows the display a key steps")
        suite.expect(BrightnessSupport.keyMovesFocus(islandOpen: true, focused: 1, key: 2)
                     && !BrightnessSupport.keyMovesFocus(islandOpen: false, focused: 1, key: 2)
                     && !BrightnessSupport.keyMovesFocus(islandOpen: true, focused: 2, key: 2),
                     "a key moves the island's brightness focus only while the island shows it")
        suite.expect(BrightnessSupport.sliderShowsFocusedDisplay(controlEnabled: true, shown: [1, 2], focused: 2)
                     && BrightnessSupport.sliderShowsFocusedDisplay(controlEnabled: true, shown: [1], focused: nil)
                     && !BrightnessSupport.sliderShowsFocusedDisplay(controlEnabled: true, shown: [1], focused: 3)
                     && !BrightnessSupport.sliderShowsFocusedDisplay(controlEnabled: true, shown: [], focused: nil)
                     && !BrightnessSupport.sliderShowsFocusedDisplay(controlEnabled: false, shown: [1], focused: 1),
                     "the island's brightness slider shows a key's display only when it is on and can show that display")

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

        dimmingRouteChanges(suite)

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

    private static func dimmingRouteChanges(_ suite: TestSuite) {
        func readableService() -> Service {
            UserDefaults.standard = UserDefaults.Store()
            let service = Service()
            service.routes[2] = Route(method: .ddc, service: "monitor" as CFString, maximum: 100,
                                     ddcReadable: true, ddcPathKey: "path")
            service.displays = [BrightnessDisplay(id: 2, brightness: 0.5)]
            service.lastApplied[2] = 0.5
            service.reply = (50, 100)
            return service
        }
        let delta = BrightnessSupport.brightnessKeyStep

        let ordinary = readableService()
        ordinary.step(2, method: .ddc, delta: -delta, showOSD: false)
        ordinary.step(2, method: .ddc, delta: -delta, showOSD: false)
        suite.expect(ordinary.workQueue.jobs.count == 1,
                     "ordinary repeats still share one DDC read")
        ordinary.workQueue.drain()
        DispatchQueue.main.drain()
        suite.expect(ordinary.committed == [0.5 - 2 * delta] && ordinary.ddcPendingSteps.isEmpty,
                     "a valid DDC reply keeps every queued key step")
        ordinary.displays[0].brightness = 0.5 - 2 * delta
        ordinary.levelKnownAt[2] = Date()
        ordinary.step(2, method: .ddc, delta: delta, showOSD: false)
        suite.expect(ordinary.committed.last == 0.5 - delta && ordinary.workQueue.jobs.isEmpty,
                     "a fresh DDC level still steps immediately without another read")

        // The step and preference setter are extracted from production.
        // Script route publication before or after the read's main-thread
        // completion, with the software choice made while the reply is pending.
        for readFinished in [false, true] {
            for rebuilt in [false, true] {
                let late = readableService()
                late.step(2, method: .ddc, delta: -delta, showOSD: false)
                if readFinished { late.workQueue.drain() }
                late.pendingLevels[2] = 0.25
                late.setSoftwareDimmingPreferred(true, for: 2)
                suite.expect(late.pendingLevels[2] == nil && late.ddcPendingSteps[2] == nil,
                             "choosing software discards old-scale writes and the pending DDC step")
                if !readFinished { late.workQueue.drain() }
                if rebuilt {
                    late.routes[2] = Route(method: .software, service: nil, maximum: 100, ddcPathKey: "path")
                    late.displays[0].method = .software
                    late.displays[0].brightness = 1
                }
                DispatchQueue.main.drain()
                suite.expect(late.committed.isEmpty && late.pendingLevels.isEmpty
                             && late.displays[0].brightness == (rebuilt ? 1 : 0.5),
                             "a late DDC reply never dims the picture, before or after the software rebuild")
            }
        }

        let transition = readableService()
        transition.setSoftwareDimmingPreferred(true, for: 2)
        transition.step(2, method: .ddc, delta: -delta, showOSD: false)
        suite.expect(transition.workQueue.jobs.isEmpty && transition.committed.isEmpty,
                     "keys cannot start another DDC step while the software rebuild is queued")
        transition.routes[2] = Route(method: .software, service: nil, maximum: 100, ddcPathKey: "path")
        transition.step(2, method: .ddc, delta: -delta, showOSD: false)
        transition.step(2, method: .software, delta: -delta, showOSD: false)
        suite.expect(transition.committed.isEmpty,
                     "neither an old key route nor an old published slider scale is applied to a new route")
        transition.displays[0].method = .software
        transition.displays[0].brightness = 1
        transition.step(2, method: .software, delta: -delta, showOSD: false)
        suite.expect(transition.committed == [1 - delta] && transition.workQueue.jobs.isEmpty,
                     "software brightness keys work normally once the new scale is published")

        let replacedRoute = readableService()
        replacedRoute.step(2, method: .ddc, delta: -delta, showOSD: false)
        replacedRoute.workQueue.drain()
        replacedRoute.routes[2] = Route(method: .software, service: nil, maximum: 100, ddcPathKey: "path")
        DispatchQueue.main.drain()
        suite.expect(replacedRoute.committed.isEmpty,
                     "an automatic route change rejects a DDC reply even on the same connection")

        let replacement = readableService()
        replacement.step(2, method: .ddc, delta: -delta, showOSD: false)
        replacement.workQueue.drain()
        replacement.setSoftwareDimmingPreferred(true, for: 2)
        replacement.setSoftwareDimmingPreferred(false, for: 2)
        replacement.step(2, method: .ddc, delta: delta, showOSD: false)
        let newRequest = replacement.ddcPendingSteps[2]?.request
        DispatchQueue.main.drainNext()
        suite.expect(newRequest != nil && replacement.ddcPendingSteps[2]?.request == newRequest
                     && replacement.committed.isEmpty,
                     "a canceled reply cannot consume a newer DDC request after switching back")
        replacement.workQueue.drain()
        DispatchQueue.main.drain()
        suite.expect(replacement.committed == [0.5 + delta] && replacement.ddcPendingSteps.isEmpty,
                     "the new DDC reply applies only the new key step")

        let separate = readableService()
        separate.routes[3] = Route(method: .ddc, service: "other monitor" as CFString, maximum: 100,
                                  ddcReadable: true, ddcPathKey: "other-path")
        separate.displays.append(BrightnessDisplay(id: 3, brightness: 0.5))
        separate.step(2, method: .ddc, delta: -delta, showOSD: false)
        separate.step(3, method: .ddc, delta: delta, showOSD: false)
        separate.workQueue.drain()
        separate.setSoftwareDimmingPreferred(true, for: 2)
        DispatchQueue.main.drain()
        suite.expect(separate.pendingLevels[2] == nil && separate.pendingLevels[3] == 0.5 + delta,
                     "changing one monitor's mode preserves another monitor's pending key step")

        let extended = readableService()
        extended.step(2, method: .ddc, delta: -delta, showOSD: false)
        extended.workQueue.drain()
        extended.setExtendedDimmingPreferred(true, for: 2)
        DispatchQueue.main.drain()
        suite.expect(extended.committed.isEmpty,
                     "the neighboring extra-dimming choice also discards a read in the old slider scale")

        let unkeyed = readableService()
        unkeyed.routes[2]?.ddcPathKey = nil
        unkeyed.step(2, method: .ddc, delta: -delta, showOSD: false)
        unkeyed.setSoftwareDimmingPreferred(true, for: 2)
        unkeyed.workQueue.drain()
        DispatchQueue.main.drain()
        suite.expect(unkeyed.committed == [0.5 - delta] && unkeyed.refreshes == 0,
                     "an unavailable dimming choice leaves a legitimate unkeyed DDC step intact")
        UserDefaults.standard = UserDefaults.Store()
    }
}
