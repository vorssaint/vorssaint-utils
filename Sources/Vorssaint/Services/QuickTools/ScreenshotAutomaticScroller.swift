// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Sends small downward steps to the window selected at capture start. The
/// target stays fixed even if the pointer moves onto the capture controls.
final class ScreenshotAutomaticScroller {
    private let windowID: CGWindowID
    private let processID: pid_t
    private let bounds: CGRect
    private let point: CGPoint
    private let step: Int32

    init?(region: RecorderSupport.Region, protectedWindowIDs: Set<CGWindowID>) {
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let point = CGPoint(x: region.anchorRect.midX, y: mainHeight - region.anchorRect.midY)
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let target = windows.first(where: { entry in
                  guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                        let id = entry[kCGWindowNumber as String] as? CGWindowID,
                        !protectedWindowIDs.contains(id),
                        let raw = entry[kCGWindowBounds as String] as? [String: Any],
                        let rect = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return false }
                  if let selected = region.windowID {
                      return entry[kCGWindowNumber as String] as? CGWindowID == selected
                  }
                  return rect.contains(point)
              }),
              let id = target[kCGWindowNumber as String] as? CGWindowID,
              let pid = target[kCGWindowOwnerPID as String] as? Int32,
              let raw = target[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: raw as CFDictionary) else { return nil }
        windowID = id
        processID = pid
        bounds = rect
        self.point = point
        step = Int32(min(160, max(1, region.anchorRect.height * 0.15)))
    }

    func scroll() -> Bool {
        guard CGPreflightPostEventAccess(),
              let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
                as? [[String: Any]],
              let target = windows.first,
              target[kCGWindowOwnerPID as String] as? Int32 == processID,
              let raw = target[kCGWindowBounds as String] as? [String: Any],
              CGRect(dictionaryRepresentation: raw as CFDictionary) == bounds,
              let event = Self.scrollEvent(processID: processID,
                                           point: point, step: step)
        else { return false }
        // New wheel events need the window server's routing metadata. Direct
        // process delivery works for copied hardware events, but can leave a
        // newly created event without a destination window.
        event.post(tap: .cgSessionEventTap)
        return true
    }

    static func scrollEvent(processID: pid_t,
                            point: CGPoint, step: Int32) -> CGEvent? {
        guard step > 0,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: 1, wheel1: -step, wheel2: 0, wheel3: 0)
        else { return nil }
        event.location = point
        event.flags = []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(processID))
        // Inversion and smoothing leave our tagged events alone as they pass
        // through the session stream to the selected app and position.
        event.setIntegerValueField(.eventSourceUserData, value: ScrollWheelSupport.syntheticTag)
        event.setIntegerValueField(.eventSourceUnixProcessID,
                                   value: Int64(ProcessInfo.processInfo.processIdentifier))
        return event
    }
}
