// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import CoreGraphics
import Foundation

/// Runs the production remote-token loop with a clock and AX transport doubles.
/// This checks request budgets and selection, not undocumented macOS behavior.
enum AXHiddenSpaceLookupTests {
    final class Element: NSObject {
        let id: UInt64
        let windowID: CGWindowID
        let role: String
        var windowCost: TimeInterval = 0
        var roleCost: TimeInterval = 0
        var windowResult: AXError = .success
        var roleResult: AXError = .success
        var timeoutResult: AXError = .success
        var timeout: Float = 0

        init(_ id: UInt64, windowID: CGWindowID, role: String = kAXWindowRole as String) {
            self.id = id
            self.windowID = windowID
            self.role = role
        }
    }

    enum Resolver {
        typealias AXUIElement = Element
        struct Clock {
            var systemUptime: TimeInterval = 0
            let processIdentifier: pid_t = 77
        }
        enum ProcessInfo { static var processInfo = Clock() }
        static var elements: [UInt64: Element] = [:]
        static var probes: [UInt64] = []
        static var tokenOwners: [pid_t] = []
        static var tokenMarkers: [Int32] = []
        static var calls: [String] = []
        static var timeouts: [Float] = []
        static var createWithRemoteToken: ((CFData) -> Unmanaged<Element>?)? = makeRemoteElement

        static func makeRemoteElement(_ token: CFData) -> Unmanaged<Element>? {
            let bytes = token as Data
            let id = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt64.self) }
            probes.append(id)
            tokenOwners.append(bytes.withUnsafeBytes { $0.loadUnaligned(as: pid_t.self) })
            tokenMarkers.append(bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: Int32.self) })
            return elements[id].map { Unmanaged.passRetained($0) }
        }

        static func AXUIElementSetMessagingTimeout(_ element: Element, _ timeout: Float) -> AXError {
            timeouts.append(timeout)
            element.timeout = timeout
            return element.timeoutResult
        }

        static func _AXUIElementGetWindow(_ element: Element, _ id: inout CGWindowID) -> AXError {
            calls.append("window:\(element.id)")
            ProcessInfo.processInfo.systemUptime += min(element.windowCost, Double(element.timeout))
            guard element.windowCost <= Double(element.timeout) else { return .cannotComplete }
            id = element.windowID
            return element.windowResult
        }

        static func AXUIElementCopyAttributeValue(_ element: Element, _ attribute: CFString,
                                                  _ value: inout CFTypeRef?) -> AXError {
            calls.append("role:\(element.id)")
            ProcessInfo.processInfo.systemUptime += min(element.roleCost, Double(element.timeout))
            guard element.roleCost <= Double(element.timeout) else { return .cannotComplete }
            value = element.role as CFString
            return element.roleResult
        }

        static func reset() {
            ProcessInfo.processInfo = Clock()
            elements = [:]
            probes = []
            tokenOwners = []
            tokenMarkers = []
            calls = []
            timeouts = []
            createWithRemoteToken = makeRemoteElement
        }
    }

    static func run(_ suite: TestSuite) {
        defer { Resolver.reset() }
        Resolver.reset()
        let child = Element(0, windowID: 10, role: kAXGroupRole as String)
        let first = Element(1, windowID: 10)
        let unrelated = Element(2, windowID: 99)
        let second = Element(3, windowID: 20)
        Resolver.elements = [0: child, 1: first, 2: unrelated, 3: second]
        let found = Resolver.elementsOnHiddenSpace(windowIDs: [10, 20], pid: 9)
        suite.expect(found[10] === first && found[20] === second && Resolver.probes == [0, 1, 2, 3],
                     "remote lookup rejects child elements and finds each exact window in one scan")
        suite.expect(!Resolver.calls.contains("role:2"),
                     "an unrelated window does not spend the remaining budget reading its role")
        suite.expect(Resolver.tokenOwners.allSatisfy { $0 == 9 }
                        && Resolver.tokenMarkers.allSatisfy { $0 == 0x636f_636f },
                     "remote tokens retain the requested owner and Cocoa marker")

        Resolver.reset()
        _ = Resolver.elementsOnHiddenSpace(windowIDs: [10], pid: 9)
        suite.expect(Resolver.probes.count == Int(Resolver.remoteElementIDLimit) && Resolver.calls.isEmpty,
                     "a missing remote element stops at the candidate cap without AX reads")

        Resolver.reset()
        for budget: TimeInterval in [0, -1, .infinity, .nan] {
            _ = Resolver.elementsOnHiddenSpace(windowIDs: [10], pid: 9, budget: budget)
        }
        for pid: pid_t in [-1, 0, Resolver.ProcessInfo.processInfo.processIdentifier] {
            _ = Resolver.elementsOnHiddenSpace(windowIDs: [10], pid: pid)
        }
        _ = Resolver.elementsOnHiddenSpace(windowIDs: [], pid: 9)
        _ = Resolver.elementsOnHiddenSpace(windowIDs: [0], pid: 9)
        _ = Resolver.elementsOnHiddenSpace(windowIDs: [10], pid: 9, isCancelled: { true })
        Resolver.createWithRemoteToken = nil
        _ = Resolver.elementsOnHiddenSpace(windowIDs: [10], pid: 9)
        suite.expect(Resolver.probes.isEmpty && Resolver.timeouts.isEmpty,
                     "invalid budgets, owners, empty targets, cancellation and missing symbols skip remote lookup")

        Resolver.reset()
        for id: UInt64 in 0..<32 {
            let slow = Element(id, windowID: 0)
            slow.windowCost = 0.05
            Resolver.elements[id] = slow
        }
        _ = Resolver.elementsOnHiddenSpace(windowIDs: [10], pid: 9, budget: 0.125)
        suite.expect(Resolver.probes == [0, 1, 2] && Resolver.calls.count == 3
                        && Resolver.ProcessInfo.processInfo.systemUptime <= 0.126,
                     "slow lookups stop at the shared deadline instead of waiting for 32 candidates")
        suite.expect(Resolver.timeouts.count == 3 && abs(Double(Resolver.timeouts.last ?? 0) - 0.025) < 0.001,
                     "the final lookup timeout shrinks to the remaining budget")

        Resolver.reset()
        let unresponsive = Element(0, windowID: 10)
        unresponsive.windowResult = .cannotComplete
        Resolver.elements = [0: unresponsive, 1: first]
        suite.expect(Resolver.elementsOnHiddenSpace(windowIDs: [10], pid: 9).isEmpty
                        && Resolver.probes == [0] && Resolver.calls == ["window:0"],
                     "an unresponsive app stops the shared scan at its first failed window-id request")

        Resolver.reset()
        let matched = Element(0, windowID: 10)
        let unansweredRole = Element(1, windowID: 20)
        unansweredRole.roleResult = .cannotComplete
        Resolver.elements = [0: matched, 1: unansweredRole, 2: second]
        let partial = Resolver.elementsOnHiddenSpace(windowIDs: [0, 10, 20], pid: 9)
        suite.expect(partial.isEmpty && Resolver.probes == [0, 1],
                     "a timed-out role discards earlier matches so callers cannot read titles from the stalled app")
        Resolver.reset()
        unansweredRole.windowResult = .cannotComplete
        Resolver.elements = [0: matched, 1: unansweredRole, 2: second]
        suite.expect(Resolver.elementsOnHiddenSpace(windowIDs: [10, 20], pid: 9).isEmpty
                        && Resolver.probes == [0, 1] && !Resolver.calls.contains("role:1"),
                     "a timed-out window-id read also discards the batch before any subsequent AX request")
        Resolver.reset()
        Resolver.elements = [0: matched]
        let available = Resolver.elementsOnHiddenSpace(windowIDs: [0, 10], pid: 9)
        suite.expect(available[10] === matched && available.count == 1 && Resolver.probes == [0],
                     "id zero is ignored without preventing complete valid answers")
        suite.expect(matched.timeout > 0 && matched.timeout <= 0.05,
                     "plural answers retain short lookup timeouts for budgeted title reads")

        Resolver.reset()
        let expiring = Element(0, windowID: 10)
        expiring.windowCost = 0.04
        expiring.roleCost = 0.05
        Resolver.elements = [0: expiring]
        let expired = Resolver.elementsOnHiddenSpace(windowIDs: [10], pid: 9, budget: 0.06)
        suite.expect(expired.isEmpty && Resolver.calls == ["window:0", "role:0"]
                        && Resolver.ProcessInfo.processInfo.systemUptime <= 0.061,
                     "a slow role query shares the lookup deadline without further AX requests")
        suite.expect(Resolver.timeouts.count == 2 && abs(Double(Resolver.timeouts[1]) - 0.02) < 0.001,
                     "role lookup gets a fresh timeout from the remaining budget")

        Resolver.reset()
        let exhausted = Element(0, windowID: 10)
        exhausted.windowCost = 0.05
        Resolver.elements = [0: exhausted]
        _ = Resolver.elementsOnHiddenSpace(windowIDs: [10], pid: 9, budget: 0.05)
        suite.expect(Resolver.calls == ["window:0"] && Resolver.timeouts.count == 1,
                     "a window-id reply at the deadline does not start a role request")

        Resolver.reset()
        let cancelled = Element(0, windowID: 10)
        Resolver.elements = [0: cancelled, 1: first]
        let cancelledAnswer = Resolver.elementsOnHiddenSpace(windowIDs: [10], pid: 9,
            isCancelled: { !Resolver.calls.isEmpty })
        suite.expect(cancelledAnswer.isEmpty && Resolver.probes == [0] && Resolver.calls == ["window:0"],
                     "cancellation after window-id lookup prevents the role request and later candidates")

        Resolver.reset()
        let invalid = Element(0, windowID: 10)
        invalid.timeoutResult = .invalidUIElement
        Resolver.elements = [0: invalid, 1: first]
        let afterInvalid = Resolver.elementsOnHiddenSpace(windowIDs: [10], pid: 9)
        suite.expect(afterInvalid[10] === first && Resolver.calls == ["window:1", "role:1"],
                     "a token whose timeout cannot be set is skipped without abandoning later valid windows")

        Resolver.reset()
        Resolver.ProcessInfo.processInfo.systemUptime = 1
        suite.expect(!Resolver.prepareForRequest(first, deadline: 1)
                        && !Resolver.prepareForRequest(first, deadline: 0.9)
                        && Resolver.timeouts.isEmpty,
                     "an exhausted deadline never installs a zero timeout that restores the global default")
    }
}
