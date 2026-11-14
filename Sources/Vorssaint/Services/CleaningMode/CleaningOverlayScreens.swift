// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One connected display as Cleaning Mode sees it: where to put an overlay and
/// whether it is the Mac's own built-in panel.
struct CleaningDisplay: Equatable {
    let frame: CGRect
    let isBuiltIn: Bool
}

/// Chooses the displays Cleaning Mode covers. Extracted from the overlay code so
/// the decision can be tested without real displays.
enum CleaningOverlayScreens {
    /// Every display, or only the built-in ones when `builtInOnly` is set. With
    /// no built-in display connected (a closed MacBook driving an external
    /// monitor, or a desktop Mac) it falls back to every display, so the
    /// keyboard is never locked behind an overlay the user cannot see.
    static func frames(for displays: [CleaningDisplay], builtInOnly: Bool) -> [CGRect] {
        guard builtInOnly else { return displays.map(\.frame) }
        let builtIn = displays.filter(\.isBuiltIn)
        return (builtIn.isEmpty ? displays : builtIn).map(\.frame)
    }
}
