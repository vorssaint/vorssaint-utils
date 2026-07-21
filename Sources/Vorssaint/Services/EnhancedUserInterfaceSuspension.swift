// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices

/// Apps that switch into an assistive mode through the application-level
/// AXEnhancedUserInterface attribute mishandle window frame changes while that
/// mode is on: the position lands but the new size is ignored, leaving the
/// window parked at a screen edge instead of taking its new frame. The
/// established fix in mature window managers is to switch the flag off around
/// the frame change and put it back afterwards, which is what this does.
struct EnhancedUserInterfaceSuspension {
    private static let attribute = "AXEnhancedUserInterface" as CFString
    private let application: AXUIElement

    static func suspend(forAppOf window: AXUIElement) -> EnhancedUserInterfaceSuspension? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid != 0 else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.35)
        guard isEnabled(on: application) else { return nil }
        // Setting this attribute reports cannotComplete even when it takes
        // effect (measured on macOS 27), so trust the read-back, never the
        // return code.
        _ = AXUIElementSetAttributeValue(application, Self.attribute, kCFBooleanFalse)
        guard !isEnabled(on: application) else { return nil }
        return EnhancedUserInterfaceSuspension(application: application)
    }

    private static func isEnabled(on application: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, Self.attribute, &value) == .success else { return false }
        return (value as? Bool) == true
    }

    func resume() {
        _ = AXUIElementSetAttributeValue(application, Self.attribute, kCFBooleanTrue)
    }
}
