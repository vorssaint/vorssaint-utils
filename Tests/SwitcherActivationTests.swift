// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Production activation and bridge bodies run against transports that never
/// activate an app or post input. Native window ordering is validated separately.
enum SwitcherActivationTests {
    static var events: [String] = []
    static var records: [[UInt8]] = []
    static var canRaise = true

    final class App {
        static let current = App(processIdentifier: 1)!
        let processIdentifier: pid_t
        var isTerminated = false
        init?(processIdentifier: pid_t) {
            guard processIdentifier > 0 else { return nil }
            self.processIdentifier = processIdentifier
        }
        func unhide() { events.append("unhide") }
        @discardableResult func activate(from: App, options: NSApplication.ActivationOptions) -> Bool {
            events.append("activate:\(processIdentifier):\(options.contains(.activateAllWindows))")
            return true
        }
        @discardableResult func activate(options: NSApplication.ActivationOptions) -> Bool { false }
    }
    enum Handoff {
        static func yield(to app: App) { events.append("yield:\(app.processIdentifier)") }
    }
    enum Activator {
        typealias NSRunningApplication = App
        typealias ActivationHandoff = Handoff
        typealias SpaceWindowBridge = Bridge
        @discardableResult static func prepareWindowForActivation(windowID: CGWindowID, pid: pid_t) -> Bool { true }
        @discardableResult static func focusWindow(windowID: CGWindowID, pid: pid_t, makeAppFrontmost: Bool = true) -> Bool {
            events.append("raise:\(windowID):\(pid):\(makeAppFrontmost)")
            return canRaise
        }
    }
    enum Bridge {
        static var processForPID: ((pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus)?
        static var setFrontProcess: ((UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError)?
        static var postEventRecord: ((UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError)?
    }
    static func reset(raise: Bool = true, front: CGError = .success, down: CGError = .success) {
        events = []; records = []; canRaise = raise
        Bridge.processForPID = { pid, _ in events.append("owner:\(pid)"); return noErr }
        Bridge.setFrontProcess = { _, id, _ in events.append("front:\(id)"); return front }
        Bridge.postEventRecord = { _, bytes in
            events.append("event:\(bytes[8])")
            records.append(Array(UnsafeBufferPointer(start: bytes, count: 0x100)))
            return down
        }
    }
    static func run(_ suite: TestSuite) {
        let app = App(processIdentifier: 20)!
        let windowPlan = SwitcherSupport.activationPlan(targetsSpecificWindow: true)
        func select(owner: pid_t = 20) { Activator.activateApp(app, plan: windowPlan, windowID: 77, windowOwnerPID: owner) }
        reset(); select()
        suite.expect(events == ["owner:20", "front:77", "event:1", "raise:77:20:false"],
                     "a delivered window selection raises the exact window without activating every sibling")
        // The press that makes the window key must name the window and land
        // far past its bottom-right corner: a point near the frame is the
        // resize border, and no location at all is read by some apps as (0, 0).
        // It is never released, so no app can turn it into a click.
        let windowIDBytes = withUnsafeBytes(of: CGWindowID(77).littleEndian, Array.init)
        let pressPointBytes = withUnsafeBytes(of: CGPoint(x: 300_000, y: 300_000), Array.init)
        suite.expect(records.count == 1 && records.allSatisfy { record in
            record[0x04] == 0xf8 && record[0x3a] == 0x10
                && Array(record[0x3c..<0x40]) == windowIDBytes
                && Array(record[0x20..<0x30]) == pressPointBytes
        }, "the key-making press names the window and points past any window")
        suite.expect(records.map { $0[0x08] } == [1], "the press is posted alone, with no release")
        reset(raise: false); select()
        suite.expect(events.contains("activate:20:false"), "a window lost by Accessibility retains cooperative recovery")
        reset(front: .failure); select()
        suite.expect(!events.contains("event:1") && events.contains("activate:20:false"), "a refused front request uses the previous activation path")
        reset(down: .failure); select()
        suite.expect(events.contains("activate:20:false"), "a refused press triggers recovery")
        reset(); Bridge.postEventRecord = nil; select()
        suite.expect(!events.contains("front:77") && events.contains("activate:20:false"), "missing event transport cannot claim success")
        reset(); Bridge.setFrontProcess = nil; select()
        suite.expect(events.contains("activate:20:false"), "missing front transport recovers")
        reset(); Bridge.processForPID = { _, _ in -1 }; select()
        suite.expect(events.contains("activate:20:false"), "missing process identity recovers")
        reset(); select(owner: 30)
        suite.expect(events.prefix(3) == ["yield:20", "activate:20:false", "owner:30"],
                     "host menus are activated before fronting an accessory owner's window")
        suite.expect(events.last == "raise:77:30:false", "helper window focusing does not replace host activation")
        reset(); _ = Activator.activateSource(pid: 20, windowID: nil, windowOwnerPID: nil)
        suite.expect(events == ["unhide", "yield:20", "activate:20:false"], "returning without a saved window does not raise all source windows")
        reset(); _ = Activator.activateSource(pid: 20, windowID: 77, windowOwnerPID: 20)
        suite.expect(!events.contains("activate:20:true") && events.contains("front:77"), "returning to an identified source still selects its window")
        reset(); Activator.activateApp(app, plan: SwitcherSupport.activationPlan(targetsSpecificWindow: false))
        suite.expect(events == ["yield:20", "activate:20:true"], "explicit app selection still brings all its windows forward")
        reset(); let restored = Activator.activateSource(pid: -1, windowID: nil, windowOwnerPID: nil)
        suite.expect(!restored && events.isEmpty, "an exited source cannot receive restoration")
    }
}
