// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

enum TrafficLightButton {
    case close
    case zoom
}

struct TrafficLightCandidate {
    let pid: pid_t
    let windowID: CGWindowID
}

struct WindowServerWindowCandidate {
    let pid: pid_t
    let windowID: CGWindowID
    let frame: CGRect
}

/// The window server's on-screen list and the scans run over it. Asking for
/// the list and reading a rectangle out of an entry were written out again at
/// every caller, so a mistake in one copy was invisible from the others.
///
/// The two scans stay separate because they are not the same scan: they
/// disagree on the far edge of a window and on what a window that matches
/// geometrically but fails a later check means. Each says why below.
enum WindowServerSupport {
    /// The on-screen windows, front to back, without the desktop and its
    /// icons: scrolling the empty desktop must fall through to the app in
    /// front rather than answer with the file manager behind everything.
    static func onScreenWindowInfo() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                   kCGNullWindowID) as? [[String: Any]] ?? []
    }

    /// The same list, reduced to what a pointer lookup needs.
    static func onScreenWindows() -> [MouseAppExceptionSupport.Window] {
        MouseAppExceptionSupport.windows(from: onScreenWindowInfo())
    }

    static func bounds(from window: [String: Any]) -> CGRect? {
        guard let raw = window[kCGWindowBounds as String] as? [String: Any],
              let x = (raw["X"] as? NSNumber)?.doubleValue,
              let y = (raw["Y"] as? NSNumber)?.doubleValue,
              let width = (raw["Width"] as? NSNumber)?.doubleValue,
              let height = (raw["Height"] as? NSNumber)?.doubleValue else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The frontmost window that answers for a click, with the edges compared
    /// by hand so that a point sitting exactly on the right or bottom edge is
    /// still inside, which `CGRect.contains` would drop. Every condition is
    /// one guard: a window failing any of them is not the window being asked
    /// about, so the scan keeps going to the one behind it.
    static func windowCandidate(in windows: [[String: Any]],
                                at point: CGPoint,
                                ownProcessID: pid_t,
                                pidIsEligible: (pid_t) -> Bool) -> WindowServerWindowCandidate? {
        for window in windows {
            guard let bounds = bounds(from: window),
                  bounds.width >= 80, bounds.height >= 80,
                  point.x >= bounds.minX, point.x <= bounds.maxX,
                  point.y >= bounds.minY, point.y <= bounds.maxY,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ownProcessID,
                  pidIsEligible(pid),
                  let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }
            return WindowServerWindowCandidate(pid: pid,
                                               windowID: CGWindowID(number),
                                               frame: bounds)
        }
        return nil
    }

    /// The traffic light a click landed on, if any. `CGRect.contains` decides
    /// what the point is over, so the far edge belongs to the window next to
    /// this one rather than to both. Once a window does contain the point the
    /// scan is over either way: a click that landed on the window in front
    /// must not be handed to a window behind it just because this one turned
    /// out to be an app the feature leaves alone, or because the point missed
    /// the buttons.
    static func trafficLightCandidate(in windows: [[String: Any]],
                                      at point: CGPoint,
                                      button: TrafficLightButton,
                                      ownProcessID: pid_t,
                                      pidIsEligible: (pid_t) -> Bool) -> TrafficLightCandidate? {
        for window in windows {
            guard let bounds = bounds(from: window),
                  bounds.width >= 80,
                  bounds.height >= 80,
                  bounds.contains(point) else {
                continue
            }

            guard let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID != ownProcessID,
                  let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value else {
                continue
            }

            guard pidIsEligible(ownerPID),
                  contains(point, inTrafficLightAreaOf: bounds, button: button) else {
                return nil
            }
            return TrafficLightCandidate(pid: ownerPID, windowID: CGWindowID(number))
        }
        return nil
    }

    static func contains(_ point: CGPoint,
                         inTrafficLightAreaOf bounds: CGRect,
                         button: TrafficLightButton) -> Bool {
        let dx = point.x - bounds.minX
        let dy = point.y - bounds.minY
        guard dy >= -6, dy <= 46 else { return false }

        switch button {
        case .close:
            return dx >= -6 && dx <= 52
        case .zoom:
            return dx >= 42 && dx <= 104
        }
    }
}
