// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import CoreGraphics
import Foundation

/// Runs the production resolver against simulated AX replies and a monotonic
/// clock. No remote process, Accessibility permission or WindowServer is used.
enum AXWindowResolverTests {
    final class Element: NSObject {
        let pid: pid_t
        let windowID: CGWindowID
        var role = kAXWindowRole as String
        var windowResult: AXError = .success
        var roleResult: AXError = .success
        var pidResult: AXError = .success
        var windowDuration: TimeInterval = 0
        var roleDuration: TimeInterval = 0
        var timeout: Float?
        var timeoutResult: AXError = .success

        init(pid: pid_t = 10, windowID: CGWindowID) {
            self.pid = pid
            self.windowID = windowID
        }
    }

    enum Resolver {
        typealias AXUIElement = Element
        struct ProcessInfo {
            static var processInfo = ProcessInfo()
            let processIdentifier: pid_t = 99
            var systemUptime: TimeInterval = 10
        }
        struct Call {
            let element: Element
            let operation: String
            let started: TimeInterval
            let timeout: Float?
        }
        static var published: [Element] = []
        static var main: Element?
        static var focused: Element?
        static var publishedResult: AXError = .success
        static var remote: [UInt64: Element] = [:]
        static var remoteDefault: Element?
        static var tokens: [[UInt8]] = []
        static var calls: [Call] = []
        static var createWithRemoteToken: ((CFData) -> Unmanaged<Element>?)? = createRemote

        static func reset() {
            ProcessInfo.processInfo = ProcessInfo()
            published = []
            main = nil
            focused = nil
            publishedResult = .success
            remote = [:]
            remoteDefault = nil
            tokens = []
            calls = []
            createWithRemoteToken = createRemote
        }

        static func createRemote(_ data: CFData) -> Unmanaged<Element>? {
            let bytes = [UInt8](data as Data)
            tokens.append(bytes)
            guard bytes.count == 20 else { return nil }
            let identifier = bytes[12..<20].enumerated().reduce(UInt64(0)) {
                $0 | UInt64($1.element) << UInt64($1.offset * 8)
            }
            guard let element = remote[identifier] ?? remoteDefault else { return nil }
            return Unmanaged.passRetained(element)
        }

        static func AXUIElementGetPid(_ element: Element, _ pid: inout pid_t) -> AXError {
            pid = element.pid
            return element.pidResult
        }

        @discardableResult
        static func AXUIElementSetMessagingTimeout(_ element: Element, _ timeout: Float) -> AXError {
            element.timeout = timeout
            return element.timeoutResult
        }

        static func _AXUIElementGetWindow(_ element: Element, _ id: inout CGWindowID) -> AXError {
            calls.append(Call(element: element, operation: "window",
                              started: ProcessInfo.processInfo.systemUptime, timeout: element.timeout))
            ProcessInfo.processInfo.systemUptime += element.windowDuration
            id = element.windowID
            return element.windowResult
        }

        static func AXUIElementCopyAttributeValue(_ element: Element, _ attribute: CFString,
                                                  _ value: inout CFTypeRef?) -> AXError {
            let attribute = attribute as String
            calls.append(Call(element: element, operation: attribute,
                              started: ProcessInfo.processInfo.systemUptime, timeout: element.timeout))
            switch attribute {
            case kAXWindowsAttribute as String:
                value = published as NSArray
                return publishedResult
            case kAXMainWindowAttribute as String:
                value = main
                return main == nil ? .noValue : .success
            case kAXFocusedWindowAttribute as String:
                value = focused
                return focused == nil ? .noValue : .success
            case kAXRoleAttribute as String:
                ProcessInfo.processInfo.systemUptime += element.roleDuration
                value = element.role as NSString
                return element.roleResult
            default:
                return .attributeUnsupported
            }
        }

        static func CFGetTypeID(_ value: CFTypeRef) -> CFTypeID { value is Element ? 42 : 0 }
        static func AXUIElementGetTypeID() -> CFTypeID { 42 }
    }

    static func run(_ suite: TestSuite) {
        defer { Resolver.reset() }
        let app = Element(windowID: 0)
        let target = Element(windowID: 77)
        let sibling = Element(windowID: 88)

        Resolver.reset()
        Resolver.published = [sibling, target]
        suite.expect(Resolver.element(for: 77, in: app, pid: 10) === target && Resolver.tokens.isEmpty,
                     "a published exact window resolves without a remote probe or sibling substitution")

        Resolver.reset()
        Resolver.main = target
        suite.expect(Resolver.element(for: 77, in: app) === target && Resolver.tokens.isEmpty,
                     "the main-window reference resolves even without remote probing enabled")
        Resolver.reset()
        Resolver.main = sibling
        Resolver.focused = target
        suite.expect(Resolver.element(for: 77, in: app) === target && Resolver.tokens.isEmpty,
                     "a sibling main window cannot replace the exact focused target")

        Resolver.reset()
        Resolver.publishedResult = .cannotComplete
        Resolver.focused = target
        suite.expect(Resolver.element(for: 77, in: app) === target,
                     "a failed published list still permits an exact focused-window reference")

        Resolver.reset()
        Resolver.remote[0] = target
        suite.expect(Resolver.element(for: 77, in: app) == nil && Resolver.tokens.isEmpty,
                     "ordinary reads do not opt into remote enumeration")

        for (windowID, owner, requestedPID) in [(CGWindowID(0), pid_t(10), pid_t(10)),
                                               (77, 99, 99), (77, 0, 0), (77, 10, 20)] {
            Resolver.reset()
            Resolver.published = [target]
            suite.expect(Resolver.element(for: windowID, in: Element(pid: owner, windowID: 0),
                                          pid: requestedPID) == nil
                            && Resolver.calls.isEmpty && Resolver.tokens.isEmpty,
                         "zero window IDs, own/invalid owners and mismatched PIDs stop before any AX query")
        }
        Resolver.reset()
        let invalidApp = Element(windowID: 0)
        invalidApp.pidResult = .invalidUIElement
        suite.expect(Resolver.element(for: 77, in: invalidApp, pid: 10) == nil && Resolver.calls.isEmpty,
                     "an unresolved owner stops before inspecting its Accessibility tree")

        Resolver.reset()
        Resolver.createWithRemoteToken = nil
        suite.expect(Resolver.element(for: 77, in: app, pid: 10) == nil && Resolver.tokens.isEmpty,
                     "a missing private symbol leaves the normal fallback available")

        Resolver.reset()
        let child = Element(windowID: 77)
        child.role = kAXButtonRole as String
        Resolver.remote = [0: sibling, 1: child, 2: target]
        let resolved = Resolver.element(for: 77, in: app, pid: 10)
        let bytes = Resolver.tokens.first ?? []
        suite.expect(resolved === target && Resolver.tokens.count == 3,
                     "remote resolution skips sibling IDs and child elements with the target window ID")
        suite.expect(bytes.count == 20 && Array(bytes.prefix(4)) == [10, 0, 0, 0]
                        && Array(bytes[8..<12]) == [0x6f, 0x63, 0x6f, 0x63],
                     "remote tokens encode the requested owner and the expected Cocoa token marker")
        suite.expect(target.timeout == Float(0.35),
                     "a resolved window restores the ordinary timeout before subsequent activation work")
        let remoteCalls = Resolver.calls.filter { $0.element !== app }
        suite.expect(!remoteCalls.isEmpty && remoteCalls.allSatisfy {
            guard let timeout = $0.timeout else { return false }
            return timeout > 0 && timeout <= 0.05
        }, "every remote window and role read has its own short nonzero timeout")

        Resolver.reset()
        let invalidRemote = Element(windowID: 77)
        invalidRemote.timeoutResult = .invalidUIElement
        Resolver.remote = [0: invalidRemote, 1: target]
        suite.expect(Resolver.element(for: 77, in: app, pid: 10) === target
                        && !Resolver.calls.contains { $0.element === invalidRemote },
                     "an element that refuses a timeout is never queried and cannot block the fallback candidate")

        Resolver.reset()
        let hung = Element(windowID: 77)
        hung.windowResult = .cannotComplete
        Resolver.remoteDefault = hung
        suite.expect(Resolver.element(for: 77, in: app, pid: 10) == nil && Resolver.tokens.count == 1,
                     "an unresponsive remote process stops the probe after its first failed message")

        Resolver.reset()
        let hungRole = Element(windowID: 77)
        hungRole.roleResult = .cannotComplete
        Resolver.remoteDefault = hungRole
        suite.expect(Resolver.element(for: 77, in: app, pid: 10) == nil && Resolver.tokens.count == 1,
                     "a timed-out role read does not continue enumerating the same unresponsive process")

        Resolver.reset()
        let slow = Element(windowID: 88)
        slow.windowDuration = 0.06
        Resolver.remoteDefault = slow
        suite.expect(Resolver.element(for: 77, in: app, pid: 10) == nil && Resolver.tokens.count == 3,
                     "the remote deadline is checked per candidate instead of after hundreds of messages")
        let slowCalls = Resolver.calls.filter { $0.element === slow }
        suite.expect(slowCalls.count == 3 && slowCalls.last?.timeout.map { $0 > 0 && $0 < 0.031 } == true,
                     "the last candidate receives only the remaining budget")

        Resolver.reset()
        let expired = Element(windowID: 77)
        expired.windowDuration = 0.2
        Resolver.remoteDefault = expired
        suite.expect(Resolver.element(for: 77, in: app, pid: 10) == nil
                        && !Resolver.calls.contains { $0.element === expired && $0.operation == kAXRoleAttribute as String },
                     "a spent deadline prevents a role query and never publishes a partial match")

        Resolver.reset()
        suite.expect(Resolver.element(for: 77, in: app, pid: 10) == nil && Resolver.tokens.count == 3000,
                     "fast absent candidates still stop at the bounded probe count")
    }
}
