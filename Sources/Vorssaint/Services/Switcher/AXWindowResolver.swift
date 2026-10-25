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

    /// Resolves the Accessibility element representing `windowID` within `axApp`.
    ///
    /// Some apps omit off-Space and fullscreen windows from `kAXWindowsAttribute`.
    /// For those windows, this checks the application's main and focused window
    /// references before probing remote identifiers for the owning process (issue #2210).
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
                if self.windowID(for: candidate) == windowID {
                    return candidate
                }
            }
        }

        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            var attributeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, attribute as CFString, &attributeValue) == .success,
               let value = attributeValue,
               CFGetTypeID(value) == AXUIElementGetTypeID() {
                let candidate = (value as! AXUIElement)
                if self.windowID(for: candidate) == windowID {
                    return candidate
                }
            }
        }

        guard let pid else { return nil }
        return resolveRemoteElement(windowID: windowID, pid: pid)
    }

    /// Iterates remote element tokens for `pid` to find the window root of `windowID`.
    /// The token is an undocumented 20-byte payload consumed by HIServices:
    /// bytes 0..<4: pid, bytes 8..<12: 'coco' (0x636f636f), bytes 12..<20: uint64 element id.
    /// Each IPC uses only the remaining budget. A timed-out app stops the scan;
    /// the deadline cannot interrupt an IPC already in flight.
    private static func resolveRemoteElement(windowID: CGWindowID, pid: pid_t) -> AXUIElement? {
        guard let createWithRemoteToken else { return nil }

        var tokenBuffer = [UInt8](repeating: 0, count: 20)
        var pidValue = pid
        var magicValue: UInt32 = 0x636f_636f
        withUnsafeBytes(of: &pidValue) { tokenBuffer.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: &magicValue) { tokenBuffer.replaceSubrange(8..<12, with: $0) }

        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        let maxProbeCount: UInt64 = 3000

        for probeID in 0..<maxProbeCount {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var idValue = probeID
            withUnsafeBytes(of: &idValue) { tokenBuffer.replaceSubrange(12..<20, with: $0) }
            let tokenData = tokenBuffer.withUnsafeBytes { Data($0) as CFData }
            guard let element = createWithRemoteToken(tokenData)?.takeRetainedValue() else { continue }

            var remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            // A timeout on axApp does not apply to independently created elements.
            guard AXUIElementSetMessagingTimeout(element, Float(min(0.05, remaining))) == .success
            else { continue }
            var matchedWindowID: CGWindowID = 0
            let result = _AXUIElementGetWindow(element, &matchedWindowID)
            if result == .cannotComplete { return nil }
            if result == .success,
               matchedWindowID == windowID {
                remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { return nil }
                guard AXUIElementSetMessagingTimeout(element, Float(min(0.05, remaining))) == .success
                else { return nil }
                var roleValue: CFTypeRef?
                let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
                if roleResult == .cannotComplete { return nil }
                if roleResult == .success,
                   let role = roleValue as? String, role == (kAXWindowRole as String) {
                    AXUIElementSetMessagingTimeout(element, 0.35)
                    return element
                }
            }
        }
        return nil
    }
}
