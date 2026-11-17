// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// The production focus helper rechecks cancellation after each blocking read.
/// AX replies are controlled here; no real application is activated or raised.
enum ScrollZoomFocusTests {
    static var current = true
    static var onResolve: () -> Void = {}
    static var onRead: () -> Void = {}
    static var writes = 0
    static func AXIsProcessTrusted() -> Bool { true }
    static func isCurrentActivation(_ generation: UInt64) -> Bool { current }
    static func AXUIElementCreateApplication(_ pid: pid_t) -> NSObject { NSObject() }
    static func AXUIElementSetMessagingTimeout(_ element: NSObject, _ timeout: Float) {}
    static func axElement(windowID: CGWindowID, in app: NSObject, pid: pid_t) -> NSObject? {
        onResolve(); return NSObject()
    }
    static func AXUIElementCopyAttributeValue(_ element: NSObject, _ name: CFString,
                                              _ value: inout CFTypeRef?) -> AXError {
        onRead(); value = kCFBooleanTrue; return .success
    }
    @discardableResult
    static func AXUIElementSetAttributeValue(_ element: NSObject, _ name: CFString, _ value: CFTypeRef) -> AXError {
        writes += 1; return .success
    }
    static func AXUIElementPerformAction(_ element: NSObject, _ action: CFString) -> AXError {
        writes += 1; return .success
    }
    // Zoom uses the synchronous restore path. The observer and generation
    // paths are exercised separately by SwitcherActivationTests.
    static func restoreWindowBeforeFocus(_ window: NSObject, pid: pid_t, generation: UInt64?,
                                          writeGuard: SwitcherActivationWriteGuard? = nil,
                                          isCurrent: () -> Bool = { true }) -> Bool {
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        return false
    }
    static func windowIsVisiblyFocused(windowID: CGWindowID, pid: pid_t, window: NSObject) -> Bool {
        false
    }

    static func run(_ suite: TestSuite) {
        defer { onResolve = {}; onRead = {}; current = true; writes = 0 }
        for cancelDuringResolve in [true, false] {
            current = true; writes = 0
            onResolve = cancelDuringResolve ? { current = false } : {}
            onRead = cancelDuringResolve ? {} : { current = false }
            let focused = focusWindow(windowID: 7, pid: 42, isCurrent: { current })
            suite.expect(!focused && writes == 0,
                         "cancellation during AX resolution or the minimized-state read prevents every focus side effect")
        }
        current = true; writes = 0; onResolve = {}; onRead = {}
        suite.expect(focusWindow(windowID: 7, pid: 42) && writes == 7,
                     "ordinary callers still unminimize, activate, focus and raise the requested window")
    }
}
