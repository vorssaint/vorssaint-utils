// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import CoreMediaIO

enum BreakSignalSampler {
    static func sample(includeBusy: Bool) -> BreakSignals {
        var s = BreakSignals()
        s.idleSeconds = CGEventSource.secondsSinceLastEventType(.hidSystemState,
                                                                eventType: CGEventType(rawValue: ~0)!)
        guard includeBusy else { return s }
        s.micInUse = AudioInputActivity.anyOtherProcessCapturing()
        s.cameraInUse = cameraInUse()
        s.fullscreenFrontmost = fullscreenFrontmost()
        return s
    }

    static func screenLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    static func cameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &devices) == 0 else { return false }
        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var value: UInt32 = 0
            var out: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size),
                                             &out, &value) == 0 && value != 0
        }
    }

    /// Frontmost app owns a layer-0 window exactly covering a display.
    /// Our own windows (the overlay) never count.
    static func fullscreenFrontmost() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid(),
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { s -> CGRect in
            CGRect(x: s.frame.minX, y: mainHeight - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
        return info.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let raw = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw) else { return false }
            return screens.contains { $0 == bounds }
        }
    }
}
