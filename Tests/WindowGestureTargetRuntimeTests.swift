// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Runs the production press handler and target lookup against AX replies.
/// Events are created but never posted, and no application is queried.
enum WindowGestureTargetRuntimeTests {
    final class Element {
        var pid: pid_t = 1001
        var id: CGWindowID = 7
        var role = kAXWindowRole as String
        var window: Element?
        var fullScreen = false
        var movable = true
        var resizable = true
        var bounds = CGRect(x: 100, y: 100, width: 800, height: 500)
    }
    typealias AXUIElement = Element
    static var hit: Element?
    static var hitResult = AXError.noValue
    static var receivingID: CGWindowID? = 7
    static var ownerPID: pid_t? = 1001
    static var resolved: Element?
    static var requestedIDs: [CGWindowID] = []
    static var regular = true
    static var terminated = false

    final class NSRunningApplication {
        enum ActivationPolicy { case regular, prohibited }
        var isTerminated: Bool { terminated }
        var activationPolicy: ActivationPolicy { regular ? .regular : .prohibited }
        init?(processIdentifier: pid_t) {}
    }
    enum WindowServerSupport {
        static func receivingWindow(at point: CGPoint) -> CGWindowID? { receivingID }
        static func ownerProcessID(ofWindowID id: CGWindowID) -> pid_t? { ownerPID }
    }
    enum AXWindowResolver {
        static func element(for id: CGWindowID, in app: Element) -> Element? {
            requestedIDs.append(id)
            return resolved
        }
    }
    class Fixture {
        var pendingGesture: PendingWindowGesture?
        func AXUIElementCreateSystemWide() -> Element { Element() }
        func AXUIElementCreateApplication(_ pid: pid_t) -> Element {
            let app = Element()
            app.pid = pid
            return app
        }
        func AXUIElementCopyElementAtPosition(_ system: Element, _ x: Float, _ y: Float,
                                              _ result: inout Element?) -> AXError {
            result = hit
            return hitResult
        }
        func AXUIElementSetMessagingTimeout(_ element: Element, _ timeout: Float) {}
        func AXUIElementGetPid(_ element: Element, _ pid: inout pid_t) -> AXError {
            pid = element.pid
            return .success
        }
        func role(of element: Element) -> String? { element.role }
        func windowAttribute(_ element: Element, _ attribute: String) -> Element? { element.window }
        func boolAttribute(_ element: Element, _ attribute: String) -> Bool { element.fullScreen }
        func canSetPosition(on element: Element) -> Bool { element.movable }
        func canSetSize(on element: Element) -> Bool { element.resizable }
        func frame(of element: Element) -> WindowLayoutFrame? {
            WindowLayoutFrame(origin: element.bounds.origin, size: element.bounds.size)
        }
    }

    static func run(_ suite: TestSuite) {
        let point = CGPoint(x: 200, y: 200)
        func reset() -> Element {
            let window = Element()
            hit = nil
            hitResult = .noValue
            receivingID = window.id
            ownerPID = window.pid
            resolved = window
            requestedIDs = []
            regular = true
            terminated = false
            return window
        }
        func press(_ host: Host, resize: Bool = false) -> Bool {
            let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                mouseCursorPosition: point, mouseButton: .left)!
            return host.arm(chord: (.primary, resize), event: event) == nil
        }

        for result: AXError in [.noValue, .cannotComplete] {
            for resize in [false, true] {
                let window = reset()
                hitResult = result
                let host = Host()
                suite.expect(press(host, resize: resize)
                        && host.pendingGesture?.window === window
                        && requestedIDs == [window.id],
                    "a missing child hit arms the exact receiving window for move or resize")
            }
        }
        let linked = reset()
        let child = Element()
        child.role = kAXStaticTextRole as String
        hit = child
        hitResult = .success
        let unlinked = Host()
        suite.expect(press(unlinked) && unlinked.pendingGesture?.window === linked,
                     "a hit with no containing-window attribute uses the same fallback")

        let direct = reset()
        hit = direct
        hitResult = .success
        receivingID = 88
        let directHost = Host()
        suite.expect(press(directHost) && directHost.pendingGesture?.window === direct
                && requestedIDs.isEmpty,
                     "a usable AX hit keeps the ordinary path without another window lookup")

        let cases: [(String, (Element) -> Void)] = [
            ("no receiving window", { _ in receivingID = nil }),
            ("no window owner", { _ in ownerPID = nil }),
            ("own window", { _ in ownerPID = ProcessInfo.processInfo.processIdentifier }),
            ("non-regular app", { _ in regular = false }),
            ("terminated app", { _ in terminated = true }),
            ("unpublished receiver", { _ in resolved = nil }),
            ("non-window element", { $0.role = kAXMenuRole as String }),
            ("full screen window", { $0.fullScreen = true }),
            ("fixed position", { $0.movable = false }),
            ("fixed size", { $0.resizable = false }),
            ("stale bounds", { $0.bounds.origin = CGPoint(x: 500, y: 500) }),
            ("small window", { $0.bounds.size = CGSize(width: 80, height: 80) }),
        ]
        for (name, configure) in cases {
            let window = reset()
            configure(window)
            let host = Host()
            suite.expect(!press(host, resize: true) && host.pendingGesture == nil,
                         "\(name) preserves the click instead of arming another window")
        }
        let fixedSize = reset()
        fixedSize.resizable = false
        suite.expect(press(Host()), "a movable fixed-size window still accepts a move")
    }
}
