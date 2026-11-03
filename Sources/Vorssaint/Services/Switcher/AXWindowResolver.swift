// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import CoreGraphics
import Foundation

/// Resolves an Accessibility window element to its WindowServer id and vice versa.
/// Exported by ApplicationServices and SkyLight / HIServices; used by macOS window switchers.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                   _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AXWindowResolver {
    private typealias CreateWithRemoteTokenFunction =
        @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private static let createWithRemoteToken: CreateWithRemoteTokenFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */,
                                 "_AXUIElementCreateWithRemoteToken") else {
            return nil
        }
        return unsafeBitCast(symbol, to: CreateWithRemoteTokenFunction.self)
    }()

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    private static let remoteElementIDLimit: UInt64 = 3_000
    static let remoteLookupBudget: TimeInterval = 0.15

    /// Resolves the Accessibility element representing `windowID` within `axApp`.
    /// Some apps omit off-Space and fullscreen windows from their published list.
    /// Check main and focused references before opting into remote lookup.
    static func element(for windowID: CGWindowID, in axApp: AXUIElement, pid: pid_t? = nil) -> AXUIElement? {
        var appPID: pid_t = 0
        guard windowID != 0,
              AXUIElementGetPid(axApp, &appPID) == .success,
              appPID > 0, appPID != ProcessInfo.processInfo.processIdentifier,
              pid == nil || pid == appPID else { return nil }
        var publishedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &publishedValue) == .success,
           let publishedWindows = publishedValue as? [AXUIElement] {
            for candidate in publishedWindows {
                if let window = actionElement(candidate, matching: windowID) {
                    return window
                }
            }
        }

        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            var attributeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, attribute as CFString, &attributeValue) == .success,
               let value = attributeValue,
               CFGetTypeID(value) == AXUIElementGetTypeID() {
                let candidate = (value as! AXUIElement)
                if let window = actionElement(candidate, matching: windowID) {
                    return window
                }
            }
        }

        guard let pid else { return nil }
        return resolveRemoteElement(windowID: windowID, pid: pid)
    }

    /// A matching child reports its containing window's id too. Verify the role
    /// before returning an action target. Each exact object gets its own timeout;
    /// the matching published reference adds at most one role request.
    private static func actionElement(_ candidate: AXUIElement, matching windowID: CGWindowID) -> AXUIElement? {
        guard AXUIElementSetMessagingTimeout(candidate, 0.35) == .success,
              self.windowID(for: candidate) == windowID,
              isWindow(candidate) else { return nil }
        return candidate
    }

    /// Adapts the shared scan for activation, position and minimize callers.
    /// Restore their ordinary timeout after the short lookup requests.
    private static func resolveRemoteElement(windowID: CGWindowID, pid: pid_t) -> AXUIElement? {
        guard let element = elementsOnHiddenSpace(windowIDs: [windowID], pid: pid)[windowID],
              AXUIElementSetMessagingTimeout(element, 0.35) == .success else { return nil }
        return element
    }

    /// Finds exact AXWindow roots in one bounded scan per app. The undocumented
    /// token contains pid, a zero word, the Cocoa marker, then the element id.
    /// Each IPC uses the remaining deadline; an unresponsive app discards the
    /// batch so callers cannot start title reads against that same stalled app.
    /// The deadline cannot interrupt a synchronous system call already in flight.
    /// Partial answers retain short timeouts so title reads can share this budget.
    static func elementsOnHiddenSpace(windowIDs: Set<CGWindowID>, pid: pid_t,
                                      budget: TimeInterval = remoteLookupBudget,
                                      isCancelled: () -> Bool = { false }) -> [CGWindowID: AXUIElement] {
        let requestedIDs = windowIDs.subtracting([0])
        guard let createWithRemoteToken, !requestedIDs.isEmpty, budget.isFinite, budget > 0,
              pid > 0, pid != ProcessInfo.processInfo.processIdentifier, !isCancelled() else { return [:] }
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        var found: [CGWindowID: AXUIElement] = [:]
        var token = Data(count: 20)
        for elementID in 0..<remoteElementIDLimit {
            guard !isCancelled(), ProcessInfo.processInfo.systemUptime < deadline else { break }
            token.withUnsafeMutableBytes { bytes in
                bytes.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
                bytes.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
                bytes.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
                bytes.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self)
            }
            guard let element = createWithRemoteToken(token as CFData)?.takeRetainedValue(),
                  !isCancelled(), prepareForRequest(element, deadline: deadline) else { continue }
            var windowID: CGWindowID = 0
            let result = _AXUIElementGetWindow(element, &windowID)
            if result == .cannotComplete { return [:] }
            guard result == .success, requestedIDs.contains(windowID), found[windowID] == nil,
                  !isCancelled(), prepareForRequest(element, deadline: deadline) else { continue }
            var role: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if roleResult == .cannotComplete { return [:] }
            guard roleResult == .success, role as? String == kAXWindowRole as String else { continue }
            found[windowID] = element
            if found.count == requestedIDs.count { break }
        }
        return found
    }

    /// A zero timeout restores the global default, so an exhausted budget must
    /// skip the request. Timeouts apply only to this exact AX object.
    static func prepareForRequest(_ element: AXUIElement, deadline: TimeInterval) -> Bool {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return false }
        let timeout = Float(min(0.05, remaining))
        guard timeout > 0 else { return false }
        return AXUIElementSetMessagingTimeout(element, timeout) == .success
    }

    private static func isWindow(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success else { return false }
        return role as? String == kAXWindowRole as String
    }
}
