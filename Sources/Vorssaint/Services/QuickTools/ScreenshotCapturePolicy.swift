// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// Decides which of this process's windows ScreenCaptureKit must exclude.
/// Protected IDs are intersected with the actual own IDs from the same
/// shareable-content snapshot, so stale window numbers cannot affect another app.
enum ScreenshotCapturePolicy {
    static func excludedWindowIDs(hideVorssaintWindows: Bool,
                                  ownWindowIDs: Set<CGWindowID>,
                                  protectedWindowIDs: Set<CGWindowID>) -> Set<CGWindowID> {
        hideVorssaintWindows ? ownWindowIDs : ownWindowIDs.intersection(protectedWindowIDs)
    }

    static func canPickWindow(_ windowID: CGWindowID,
                              isOwnWindow: Bool,
                              hideVorssaintWindows: Bool,
                              protectedWindowIDs: Set<CGWindowID>) -> Bool {
        !isOwnWindow
            || (!hideVorssaintWindows && !protectedWindowIDs.contains(windowID))
    }

    /// One on-screen window as the capture decision needs it.
    struct CaptureWindow: Equatable {
        let id: CGWindowID
        let ownerPID: pid_t
        let frame: CGRect
    }

    /// The windows a capture of one clicked window has to draw. The area is
    /// the clicked window's own, so the shot stays the one that was asked for.
    struct AttachedCapturePlan: Equatable {
        /// The clicked window first, then what sits on it, back to front.
        let windowIDs: [CGWindowID]
        let bounds: CGRect
    }

    /// What a sheet, alert or modal dialog stacked on the clicked window adds
    /// to its capture (issue #1098).
    ///
    /// macOS gives a sheet a window of its own, so asking the window server or
    /// ScreenCaptureKit for the one window that was clicked returns it without
    /// whatever the app put on top — the capture comes back showing a dialog
    /// that is plainly on screen as missing. The relationship is not in the
    /// window list, and the Accessibility API that does know it would put a
    /// permission behind a feature that needs only Screen Recording, so the
    /// shape it has instead: same application, in front of the window, and
    /// lying entirely within it.
    ///
    /// Containment is what carries this, and it is deliberately strict.
    /// Drawing a window the person did not choose is worse than leaving a
    /// dialog out, because the shot then quietly holds something they never
    /// selected, so anything that reaches past the clicked window's edge —
    /// another document window, a compose window, an inspector — is left to
    /// the ordinary capture. It also takes a sheet the full width of its
    /// parent, which a rule about being smaller would have thrown away.
    ///
    /// `nil` when nothing is attached, which leaves the ordinary single-window
    /// capture to answer.
    static func attachedCapturePlan(target: CaptureWindow,
                                    frontToBack: [CaptureWindow]) -> AttachedCapturePlan? {
        guard target.frame.width > 0, target.frame.height > 0,
              let position = frontToBack.firstIndex(where: { $0.id == target.id })
        else { return nil }
        let attached = frontToBack[..<position].filter { candidate in
            candidate.ownerPID == target.ownerPID
                && target.frame.contains(candidate.frame)
        }
        guard !attached.isEmpty else { return nil }
        // Back to front, so the clicked window is drawn first and what the app
        // stacked on it lands on top in the order it is shown.
        let ordered = Array(attached.reversed())
        return AttachedCapturePlan(windowIDs: [target.id] + ordered.map(\.id),
                                   bounds: target.frame)
    }
}
