// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// Decides which of this process's windows ScreenCaptureKit must exclude.
/// Protected IDs are intersected with the actual own IDs from the same
/// shareable-content snapshot, so stale window numbers cannot affect another app.
enum ScreenshotCapturePolicy {
    /// The app's own windows one capture has to keep out before the "Hide
    /// Vorssaint windows" preference narrows what is left.
    ///
    /// Workflow surfaces — the selection overlays, the countdown and scrolling
    /// HUDs and the quick preview — are the tool taking the capture and can
    /// never be its subject, so they stay out whatever the preference says.
    /// Content windows — editors and pinned captures — are ordinary windows
    /// somebody left on screen, so the preference owns them (issue #780).
    ///
    /// Recording is exempt from that preference in
    /// `ScreenshotSupport.unifiedCapturePolicy`, so it passes
    /// `honoursVisibilityPreference: false` and keeps both kinds out.
    static func protectedWindowIDs(workflowWindowIDs: Set<CGWindowID>,
                                   contentWindowIDs: Set<CGWindowID>,
                                   honoursVisibilityPreference: Bool) -> Set<CGWindowID> {
        honoursVisibilityPreference
            ? workflowWindowIDs
            : workflowWindowIDs.union(contentWindowIDs)
    }

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
        /// The window list gives it no title. Decorations have none; almost
        /// every window a person works in does.
        var isUntitled = false
    }

    /// How far past the window it frames a decoration may reach on each side.
    static let decorationMargin: ClosedRange<CGFloat> = 1...32

    /// Windows another process draws around a window, such as a focus border.
    /// Picking one captures only the painted frame, so a click there has to
    /// reach the window it surrounds. A decoration has no title, sits directly
    /// in front of or behind that window and reaches past it by the same small
    /// margin on every side. Ordinary windows miss at least one of those: two
    /// maximized apps share a frame, and a window over one maximized with a
    /// gap has a title.
    static func decorationWindowIDs(frontToBack windows: [CaptureWindow]) -> Set<CGWindowID> {
        var decorations: Set<CGWindowID> = []
        for (index, window) in windows.enumerated() where window.isUntitled {
            let neighbours = [index - 1, index + 1].filter(windows.indices.contains)
            if neighbours.contains(where: { frames(window, around: windows[$0]) }) {
                decorations.insert(window.id)
            }
        }
        return decorations
    }

    private static func frames(_ decoration: CaptureWindow, around window: CaptureWindow) -> Bool {
        guard decoration.ownerPID != window.ownerPID else { return false }
        let margins = [window.frame.minX - decoration.frame.minX,
                       window.frame.minY - decoration.frame.minY,
                       decoration.frame.maxX - window.frame.maxX,
                       decoration.frame.maxY - window.frame.maxY]
        guard let smallest = margins.min(), let largest = margins.max() else { return false }
        // A point of slack absorbs rounding.
        return decorationMargin.contains(smallest) && decorationMargin.contains(largest)
            && largest - smallest <= 1
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
    /// window list, so this first pass finds the shape it has there: same
    /// application, in front of the window, and lying entirely within it.
    ///
    /// Containment bounds the first pass to the clicked window's area. Anything
    /// reaching past its edge is left to the ordinary capture, while a sheet
    /// the full width of its parent still qualifies.
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

    /// Where one window of an attached plan lands on a canvas drawn at
    /// `scale` pixels per point over the clicked window's `bounds`, in the
    /// canvas's bottom-left coordinates. Frames are window-server points,
    /// top-left origin.
    static func compositeRect(for frame: CGRect, in bounds: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: (frame.minX - bounds.minX) * scale,
               y: (bounds.maxY - frame.maxY) * scale,
               width: frame.width * scale,
               height: frame.height * scale)
    }

    /// Whether a window buffer covers `frame` whole at `scale` pixels per
    /// point in both axes, within a pixel of rounding. A composite draws each
    /// layer into its full frame, so a buffer the window server clipped at a
    /// display edge or seam would be stretched and shift the dialog on it;
    /// such a layer has to be recaptured or drop the composite.
    static func layerCoversFrame(imageWidth: Int, imageHeight: Int, frame: CGRect, scale: CGFloat) -> Bool {
        guard scale > 0, frame.width > 0, frame.height > 0 else { return false }
        return abs(CGFloat(imageWidth) - frame.width * scale) <= 1
            && abs(CGFloat(imageHeight) - frame.height * scale) <= 1
    }

    /// The display scale at which a buffer covers `frame` whole, if any.
    static func layerScale(imageWidth: Int, imageHeight: Int, frame: CGRect,
                           candidates: [CGFloat]) -> CGFloat? {
        candidates.sorted(by: >).first {
            layerCoversFrame(imageWidth: imageWidth, imageHeight: imageHeight, frame: frame, scale: $0)
        }
    }

    /// Narrows a geometric plan to the attached windows Accessibility named.
    /// A missing answer leaves geometry alone; an answer with no matches leaves
    /// the ordinary single-window capture to answer.
    static func confirmedAttachment(_ plan: AttachedCapturePlan,
                                    confirmedIDs: Set<CGWindowID>?) -> AttachedCapturePlan? {
        guard let confirmedIDs else { return plan }
        guard let targetID = plan.windowIDs.first else { return nil }
        let attachedIDs = plan.windowIDs.dropFirst().filter(confirmedIDs.contains)
        guard !attachedIDs.isEmpty else { return nil }
        return AttachedCapturePlan(windowIDs: [targetID] + attachedIDs,
                                   bounds: plan.bounds)
    }
}
