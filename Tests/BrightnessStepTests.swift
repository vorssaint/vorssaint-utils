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
        var isActive = true
        var method: Method? = .system
    }
    final class UserDefaults {
        static let standard = UserDefaults()
        var allDisplays = false
        func bool(forKey key: String) -> Bool { key == DefaultsKey.brightnessKeysAllDisplays && allDisplays }
    }

    class Fixture {
        static let log = Logger(subsystem: "vorssaint.tests", category: "brightness-step")
        static let levelTrustWindow: TimeInterval = 3
        let stateLock = NSLock()
        let workQueue = Queue()
        var displays: [BrightnessDisplay] = []
        var pendingDisplayIDs = Set<UInt32>()
        var stepped: [(id: UInt32, showOSD: Bool)] = []
        var levelKnownAt: [UInt32: Date] = [:]
        var ddcPendingSteps: [UInt32: Double] = [:]
        var focusedDisplayID: UInt32?
        func focusKeyDisplay(_ id: UInt32) { focusedDisplayID = id }
        var keyLinkLead: (id: UInt32, level: Double)?
        var keyLinks: [UInt32: BrightnessSupport.KeyLink] = [:]
        var linkedWrites: [(id: UInt32, level: Double, announces: Bool)] = []
        var announced: [[Double]] = []
        func announceLinkedLevels(_ level: Double, _ linked: [Double]) { announced.append([level] + linked) }
        func setBrightness(_ value: Double, for id: UInt32, showOSD: Bool = false,
                           smooth: Bool = false, announces: Bool = true) {
            linkedWrites.append((id, value, announces))
            if let index = displays.firstIndex(where: { $0.id == id }) { displays[index].brightness = value }
        }
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
            stepped.append((displayID, showOSD))
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

        // Brightness keys moving every display: the press steps the display
        // it is aimed at, with its overlay, and the others follow that step.
        func keyPress(allDisplays: Bool) -> Service {
            let linked = Service()
            linked.displays = [BrightnessDisplay(id: 1, brightness: 0.5),
                               BrightnessDisplay(id: 2, brightness: 0.25, method: .gamma),
                               BrightnessDisplay(id: 3, brightness: 0.75, isActive: false),
                               BrightnessDisplay(id: 4, brightness: 0.75),
                               BrightnessDisplay(id: 5, brightness: 0.75, method: nil)]
            linked.pendingDisplayIDs = [4]
            UserDefaults.standard.allDisplays = allDisplays
            linked.stepKeyPress(1, method: .system, delta: 0.0625, showOSD: true)
            UserDefaults.standard.allDisplays = false
            return linked
        }
        let single = keyPress(allDisplays: false)
        suite.expect(single.stepped.map(\.id) == [1] && single.committed == [0.5625],
                     "a key press moves only the display it is aimed at by default")
        let every = keyPress(allDisplays: true)
        suite.expect(every.stepped.map(\.id) == [1] && every.stepped.map(\.showOSD) == [true]
                     && every.committed == [0.5625],
                     "with all displays linked, the press steps the aimed display and its overlay stays there")

        // The others follow the aimed display's step, keeping their gap to it.
        func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.000_001 } == true }
        let link = Service()
        link.displays = [BrightnessDisplay(id: 1, brightness: 0.5),
                         BrightnessDisplay(id: 2, brightness: 0.6, method: .ddc),
                         BrightnessDisplay(id: 3, brightness: 0.75, isActive: false),
                         BrightnessDisplay(id: 4, brightness: 0.75),
                         BrightnessDisplay(id: 5, brightness: 0.75, method: nil)]
        link.pendingDisplayIDs = [4]
        func linkedPress(_ delta: Double) {
            let before = link.displays[0].brightness
            let after = BrightnessSupport.steppedBrightness(before, delta: delta)
            link.displays[0].brightness = after
            link.moveLinkedDisplays(after: 1, from: before, to: after)
        }
        UserDefaults.standard.allDisplays = true
        linkedPress(0.0625)
        suite.expect(link.linkedWrites.map(\.id) == [2] && near(link.displays[1].brightness, 0.6625)
                     && link.linkedWrites.allSatisfy { !$0.announces },
                     "a linked display follows the aimed one by the same amount, and only an active, settled one does")
        suite.expect(link.announced.count == 1 && near(link.announced.first?.first, 0.5625)
                     && near(link.announced.first?.last, 0.6625),
                     "the island's notice shows the aimed display's level and each linked display's")
        for _ in 0..<7 { linkedPress(0.0625) }
        suite.expect(near(link.displays[0].brightness, 1) && near(link.displays[1].brightness, 1),
                     "a linked display stops at 100% while the aimed one catches up")
        linkedPress(-0.0625)
        linkedPress(-0.0625)
        suite.expect(near(link.displays[0].brightness, 0.875) && near(link.displays[1].brightness, 0.975),
                     "the gap 100% squeezed comes back on the way down")
        link.displays[1].brightness = 0.5
        linkedPress(-0.0625)
        suite.expect(near(link.displays[1].brightness, 0.4375),
                     "a linked display moved by hand keeps the new gap it shows")
        link.displays[0].brightness = 0.3
        linkedPress(0.0625)
        suite.expect(near(link.displays[1].brightness, 0.5),
                     "moving the aimed display by hand sets new gaps from where both sit")
        UserDefaults.standard.allDisplays = false
        let writes = link.linkedWrites.count
        linkedPress(0.0625)
        suite.expect(link.linkedWrites.count == writes && link.keyLinks.isEmpty && link.keyLinkLead == nil
                     && link.announced.count == 12,
                     "with the keys moving one display, the others stay put and the gaps are forgotten")
    }
}
