// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import CoreGraphics
import Foundation

/// Resolves an Accessibility window element to its WindowServer id. Exported by
/// ApplicationServices and used by macOS window switchers; there is no public
/// alternative for this mapping.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                   _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AXWindowResolver {
    static func windowID(for element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    private typealias CreateWithRemoteTokenFunction = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private static let createWithRemoteToken: CreateWithRemoteTokenFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */,
                                 "_AXUIElementCreateWithRemoteToken") else { return nil }
        return unsafeBitCast(symbol, to: CreateWithRemoteTokenFunction.self)
    }()

    /// Element ids an app hands out start low and only grow, so the windows of
    /// a running app sit among the first few hundred (measured below 300 on
    /// macOS 26.6). The budget keeps an app that answers slowly from holding
    /// up the caller; a miss leaves the caller on its earlier behavior.
    private static let remoteElementIDLimit: UInt64 = 1_000
    static let remoteLookupBudget: TimeInterval = 0.15

    /// The Accessibility element of a window parked on a Space the user is not
    /// looking at. Nil when the lookup is unavailable or runs out of time.
    static func elementOnHiddenSpace(windowID: CGWindowID, pid: pid_t) -> AXUIElement? {
        elementsOnHiddenSpace(windowIDs: [windowID], pid: pid)[windowID]
    }

    /// The Accessibility elements of an app's windows parked on Spaces the
    /// user is not looking at. The app's window list omits such windows, but
    /// their elements still exist and can be addressed by the token
    /// Accessibility uses for remote elements, so the app's element ids are
    /// tried in order until every window is found or the budget runs out.
    /// Every element inside a window reports that window's id, and Safari
    /// hands some out before the window itself, so only a window element
    /// counts. Windows not found are missing from the answer.
    static func elementsOnHiddenSpace(windowIDs: Set<CGWindowID>, pid: pid_t,
                                      budget: TimeInterval = remoteLookupBudget) -> [CGWindowID: AXUIElement] {
        guard let createWithRemoteToken, !windowIDs.isEmpty, budget > 0 else { return [:] }
        let deadline = Date().addingTimeInterval(budget)
        var found: [CGWindowID: AXUIElement] = [:]
        // pid, a zero word, the "coco" Cocoa marker, then the element id.
        var token = Data(count: 20)
        for elementID in 0..<remoteElementIDLimit {
            token.withUnsafeMutableBytes { bytes in
                bytes.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
                bytes.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
                bytes.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
                bytes.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self)
            }
            if let element = createWithRemoteToken(token as CFData)?.takeRetainedValue() {
                AXUIElementSetMessagingTimeout(element, 0.05)
                if let windowID = windowID(for: element), windowIDs.contains(windowID), isWindow(element) {
                    found[windowID] = element
                    if found.count == windowIDs.count { break }
                }
            }
            if elementID % 32 == 31, Date() > deadline { break }
        }
        return found
    }

    private static func isWindow(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success else { return false }
        return role as? String == kAXWindowRole as String
    }
}
