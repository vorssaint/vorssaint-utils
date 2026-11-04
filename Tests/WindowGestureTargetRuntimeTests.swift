// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Runs the production press handler, target lookup and bounded AX resolver
/// against simulated replies and a clock. Events are never posted.
enum WindowGestureTargetRuntimeTests {
    final class Element: NSObject {
        var pid: pid_t = 1001
        var id: CGWindowID = 7
        var role = kAXWindowRole as String
        var window: Element?
        var fullScreen = false
        var movable = true
        var resizable = true
        var bounds = CGRect(x: 100, y: 100, width: 800, height: 500)
        var timeout: Float = 0.25
        var timeoutResult = AXError.success
        var windowCost: TimeInterval = 0
        var windowResult = AXError.success
        var roleCost: TimeInterval = 0
        var roleResult = AXError.success
        var honorsTimeout = true
    }
    typealias AXUIElement = Element
    struct ProcessInfo {
        static var processInfo = ProcessInfo()
        let processIdentifier = Foundation.ProcessInfo.processInfo.processIdentifier
        var systemUptime: TimeInterval = 10
    }
    struct Query {
        let operation: String
        let timeout: Float
        let started: TimeInterval
    }
    static var hit: Element?
    static var hitResult = AXError.noValue
    static var receivingID: CGWindowID? = 7
    static var ownerPID: pid_t? = 1001
    static var published: [Element] = []
    static var main: Element?
    static var focused: Element?
    static var attributeCosts: [String: TimeInterval] = [:]
    static var attributeResults: [String: AXError] = [:]
    static var queries: [Query] = []
    static var readIDs: [CGWindowID] = []
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
        typealias AXUIElement = Element
        typealias ProcessInfo = WindowGestureTargetRuntimeTests.ProcessInfo

        static func AXUIElementGetPid(_ element: Element, _ pid: inout pid_t) -> AXError {
            pid = element.pid
            return .success
        }
        static func AXUIElementSetMessagingTimeout(_ element: Element, _ timeout: Float) -> AXError {
            element.timeout = timeout
            return element.timeoutResult
        }
        static func reply(_ element: Element, operation: String,
                          cost: TimeInterval, result: AXError) -> AXError {
            queries.append(Query(operation: operation, timeout: element.timeout,
                                 started: ProcessInfo.processInfo.systemUptime))
            ProcessInfo.processInfo.systemUptime += element.honorsTimeout
                ? min(cost, Double(element.timeout)) : cost
            return element.honorsTimeout && cost > Double(element.timeout) ? .cannotComplete : result
        }
        static func _AXUIElementGetWindow(_ element: Element, _ id: inout CGWindowID) -> AXError {
            readIDs.append(element.id)
            id = element.id
            return reply(element, operation: "window", cost: element.windowCost, result: element.windowResult)
        }
        static func AXUIElementCopyAttributeValue(_ element: Element, _ attribute: CFString,
                                                  _ value: inout CFTypeRef?) -> AXError {
            let name = attribute as String
            if name == kAXRoleAttribute as String {
                value = element.role as NSString
                return reply(element, operation: name, cost: element.roleCost, result: element.roleResult)
            }
            if name == kAXWindowsAttribute as String {
                value = published as NSArray
            } else if name == kAXMainWindowAttribute as String {
                value = main
            } else if name == kAXFocusedWindowAttribute as String {
                value = focused
            }
            return reply(element, operation: name, cost: attributeCosts[name] ?? 0,
                         result: attributeResults[name] ?? (value == nil ? .noValue : .success))
        }
        static func CFGetTypeID(_ value: CFTypeRef) -> CFTypeID { value is Element ? 42 : 0 }
        static func AXUIElementGetTypeID() -> CFTypeID { 42 }
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
        func AXUIElementSetMessagingTimeout(_ element: Element, _ timeout: Float) { element.timeout = timeout }
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
            published = [window]
            main = nil
            focused = nil
            attributeCosts = [:]
            attributeResults = [:]
            queries = []
            readIDs = []
            ProcessInfo.processInfo = ProcessInfo()
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
                        && readIDs == [window.id],
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
                && queries.isEmpty,
                     "a usable AX hit keeps the ordinary path without another window lookup")

        let cases: [(String, (Element) -> Void)] = [
            ("no receiving window", { _ in receivingID = nil }),
            ("no window owner", { _ in ownerPID = nil }),
            ("own window", { _ in ownerPID = ProcessInfo.processInfo.processIdentifier }),
            ("non-regular app", { _ in regular = false }),
            ("terminated app", { _ in terminated = true }),
            ("unpublished receiver", { _ in published = [] }),
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

        let exact = reset()
        let sibling = Element()
        sibling.id = 88
        let matchingChild = Element()
        matchingChild.role = kAXGroupRole as String
        published = [sibling, matchingChild, exact]
        let exactHost = Host()
        suite.expect(press(exactHost) && exactHost.pendingGesture?.window === exact,
                     "the bounded resolver skips sibling IDs and non-window children with the receiver's ID")

        let focusedWindow = reset()
        published = []
        attributeResults[kAXWindowsAttribute as String] = .attributeUnsupported
        main = sibling
        focused = focusedWindow
        let focusedHost = Host()
        suite.expect(press(focusedHost) && focusedHost.pendingGesture?.window === focusedWindow,
                     "an exact focused reference remains available when the published list omits the receiver")

        _ = reset()
        published = []
        main = sibling
        focused = sibling
        let siblingHost = Host()
        suite.expect(!press(siblingHost) && siblingHost.pendingGesture == nil,
                     "a different main or focused window never substitutes for the click receiver")

        let validAfterStale = reset()
        let invalid = Element()
        invalid.timeoutResult = .invalidUIElement
        published = [invalid, validAfterStale]
        let staleHost = Host()
        suite.expect(press(staleHost) && staleHost.pendingGesture?.window === validAfterStale,
                     "a stale published reference does not hide a responsive exact receiver")

        for attribute in [kAXWindowsAttribute, kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            _ = reset()
            published = []
            attributeCosts[attribute as String] = 1
            let host = Host()
            suite.expect(!press(host) && host.pendingGesture == nil
                    && queries.last?.operation == attribute as String
                    && ProcessInfo.processInfo.systemUptime <= 10.051,
                         "an unanswered \(attribute) stops the fallback at its first timeout")
        }

        for failure in ["window", kAXRoleAttribute as String] {
            let target = reset()
            let stalled = Element()
            if failure == "window" {
                stalled.windowResult = .cannotComplete
            } else {
                stalled.roleResult = .cannotComplete
            }
            published = [stalled, target]
            focused = target
            let host = Host()
            suite.expect(!press(host) && host.pendingGesture == nil
                    && readIDs.count == 1 && queries.last?.operation == failure,
                         "an unanswered \(failure) query stops before another candidate or focused lookup")
        }

        _ = reset()
        published = (0..<20).map { index in
            let element = Element()
            element.id = CGWindowID(index + 100)
            element.windowCost = 0.04
            return element
        }
        let slowHost = Host()
        suite.expect(!press(slowHost) && slowHost.pendingGesture == nil
                && readIDs.count == 3 && ProcessInfo.processInfo.systemUptime <= 10.101,
                     "a long published list shares one 100 ms budget instead of one timeout per window")
        suite.expect(queries.allSatisfy { $0.timeout > 0 && $0.timeout <= 0.05
                && $0.started < 10.1 }
                && queries.last.map { $0.timeout < 0.021 } == true,
                     "each request uses at most the remaining deadline without resetting to a global timeout")

        let slowRole = reset()
        attributeCosts[kAXWindowsAttribute as String] = 0.04
        slowRole.windowCost = 0.04
        slowRole.roleCost = 0.04
        let roleHost = Host()
        suite.expect(!press(roleHost) && roleHost.pendingGesture == nil
                && queries.last?.operation == kAXRoleAttribute as String
                && ProcessInfo.processInfo.systemUptime <= 10.101,
                     "the role query shares the list and ID deadline instead of starting a fresh timeout")

        let late = reset()
        late.honorsTimeout = false
        late.roleCost = 0.2
        let lateHost = Host()
        suite.expect(!press(lateHost) && lateHost.pendingGesture == nil,
                     "a successful role reply after the deadline cannot arm a stale press")

        let responsive = reset()
        attributeCosts[kAXWindowsAttribute as String] = 0.01
        responsive.windowCost = 0.01
        responsive.roleCost = 0.01
        let responsiveHost = Host()
        suite.expect(press(responsiveHost, resize: true)
                && responsiveHost.pendingGesture?.window === responsive,
                     "a responsive custom-drawn receiver still starts resizing within the shared budget")
        _ = reset()
    }
}
