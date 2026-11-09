// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Sends small downward steps to the window selected at capture start. The
/// target stays fixed even if the pointer moves onto the capture controls.
final class ScreenshotAutomaticScroller: ScreenshotScrollingCapture.AutomaticScroller {
    private let windowID: CGWindowID
    private let processID: pid_t
    private let bounds: CGRect
    private let point: CGPoint
    private let step: Int32

    init?(region: RecorderSupport.Region, hideVorssaintWindows: Bool,
          protectedWindowIDs: Set<CGWindowID>) {
        guard let mainHeight = NSScreen.screens.first?.frame.maxY else { return nil }
        let point = CGPoint(x: region.anchorRect.midX, y: mainHeight - region.anchorRect.midY)
        let pickable = ScreenshotCaptureEngine.pickableWindows(
            hideVorssaintWindows: hideVorssaintWindows, protectedWindowIDs: protectedWindowIDs)
        guard let id = WindowServerSupport.receivingWindow(at: point),
              region.windowID == nil || region.windowID == id,
              let target = pickable.first(where: { $0.id == id && $0.bounds.contains(point) }),
              let pid = WindowServerSupport.ownerProcessID(ofWindowID: id) else { return nil }
        windowID = id
        processID = pid
        bounds = target.bounds
        self.point = point
        step = Int32(min(160, max(1, region.anchorRect.height * 0.15)))
    }

    func isCurrent() -> Bool {
        guard WindowServerSupport.receivingWindow(at: point) == windowID,
              let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
                as? [[String: Any]] else { return false }
        return WindowServerSupport.ownerProcessID(ofWindowID: windowID, in: info) == processID
            && WindowServerSupport.frame(ofWindowID: windowID, in: info) == bounds
    }

    func scroll() -> Bool {
        guard CGPreflightPostEventAccess(), isCurrent(),
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
