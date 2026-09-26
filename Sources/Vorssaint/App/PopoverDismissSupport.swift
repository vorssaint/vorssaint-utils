// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// Decides whether a click reported by the global mouse monitor belongs to one
/// of our own windows after all. Out-of-process content hosted in our windows
/// (the system AirPlay route picker) reaches the global monitor like a click in
/// another app. Click-through overlays (extra brightness, notch probes) never
/// receive clicks, so a click inside one really did land in another app.
enum PopoverDismissSupport {
    struct Window {
        let frame: CGRect
        let isVisible: Bool
        let ignoresMouseEvents: Bool
    }

    static func clickIsInsideOwnWindow(_ location: CGPoint, windows: [Window]) -> Bool {
        windows.contains { $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(location) }
    }
}
