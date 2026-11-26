// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Collects the focus announcements one activation produces.
///
/// Clicking an application's Dock tile raises every one of its windows, and the
/// window server announces `windowFocused` for each, so a single click can name
/// a whole app's windows. Only the window that really kept focus may be
/// promoted; the rest have to stay where they were (issue #4457).
///
/// The window server's front-to-back order answers which of the announced
/// windows is still above the others once the burst settles. Kept free of
/// AppKit so the decision can be tested without a session.
struct SwitcherFocusBurst {
    /// The application whose windows this burst belongs to, if any.
    private(set) var pid: pid_t?
    private var candidates: [CGWindowID] = []

    var isEmpty: Bool { candidates.isEmpty }

    /// Adds a window announced for `pid`. A different application starts a new
    /// burst, because one activation only ever names one application's windows.
    mutating func add(_ windowID: CGWindowID, pid: pid_t) {
        if self.pid != pid {
            self.pid = pid
            candidates = []
        }
        guard !candidates.contains(windowID) else { return }
        candidates.append(windowID)
    }

    /// The window the burst left in focus: the candidate closest to the front in
    /// the window server's order, or the first one announced when none of them
    /// is listed. Empties the burst.
    mutating func resolve(frontToBack: [CGWindowID]) -> CGWindowID? {
        guard let first = candidates.first else { return nil }
        defer { reset() }
        for windowID in frontToBack where candidates.contains(windowID) { return windowID }
        return first
    }

    /// Drops the burst without recording anything.
    mutating func reset() {
        pid = nil
        candidates = []
    }
}
