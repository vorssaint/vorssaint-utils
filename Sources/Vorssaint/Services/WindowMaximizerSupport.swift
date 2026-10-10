// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowMaximizerSupport {
    enum ToggleAction: Equatable {
        case maximize(CGRect)
        case restore(CGRect)
    }

    /// A captured original may be smaller than the minimum maximize target.
    /// Restore its exact geometry, provided it is still a valid AX frame.
    static func toggleAction(current: CGRect,
                             maximized: CGRect,
                             original: CGRect?,
                             tolerance: CGFloat) -> ToggleAction? {
        guard validFrame(current), validFrame(maximized),
              tolerance.isFinite, tolerance >= 0 else { return nil }
        if abs(current.origin.x - maximized.origin.x) <= tolerance,
           abs(current.origin.y - maximized.origin.y) <= tolerance,
           abs(current.size.width - maximized.size.width) <= tolerance,
           abs(current.size.height - maximized.size.height) <= tolerance,
           let original, validFrame(original) {
            return .restore(original)
        }
        return .maximize(maximized)
    }

    private static func validFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.size.width.isFinite && frame.size.height.isFinite
            && frame.size.width > 0 && frame.size.height > 0
            && frame.maxX.isFinite && frame.maxY.isFinite
    }

    /// The green-button override shares Window Layout's screen-edge gap and
    /// its oversized-gap clamp, even when Window Layout itself is unavailable.
    static func maximizeTarget(visibleFrame: CGRect, screenGap: Int) -> CGRect {
        WindowLayoutGeometry.screenGapFrame(visibleFrame, screenGap: CGFloat(screenGap))
    }

    /// An app on the exception list keeps the green button's own behavior, so
    /// a game, an emulator or a player can still enter macOS full screen.
    static func excludes(bundleIdentifier: String?, excludedBundleIdentifiers: [String]) -> Bool {
        guard let bundleIdentifier else { return false }
        return Defaults.sanitizedBundleIdentifierList(excludedBundleIdentifiers).contains(bundleIdentifier)
    }

    /// Some apps keep a window edge out from under a Dock at the side of the
    /// screen and refuse a size that would put it there: a window dragged in
    /// from another display stays wider than the target, by a few points or by
    /// the whole Dock. Within the frame tolerance that still reads as done while
    /// the window sits under the Dock, so any excess counts, not only one past
    /// the tolerance; half a point absorbs rounding.
    static func overshoots(_ actual: CGSize, target: CGSize) -> Bool {
        actual.width > target.width + 0.5 || actual.height > target.height + 0.5
    }

    /// Taking the target size a tolerance up and to the left keeps the far
    /// edges clear of the Dock, so those apps accept it in full; the move back
    /// onto the target is not limited the same way and lands where native zoom
    /// does. Growing into the target instead stops a point short.
    static func approachOrigin(for target: CGPoint, tolerance: CGFloat) -> CGPoint {
        CGPoint(x: target.x - tolerance, y: target.y - tolerance)
    }
}

/// Restore bookkeeping kept separate from Accessibility so target changes,
/// manual moves and late animation completions can be tested deterministically.
struct WindowMaximizerFrameState<Frame> {
    struct Attempt {
        fileprivate enum Kind { case maximize, restore }
        fileprivate let id = UUID()
        fileprivate let kind: Kind
        fileprivate let previousOriginal: Frame?
        fileprivate let previousMaximized: Frame?
    }

    private(set) var original: Frame?
    private(set) var maximized: Frame?
    private var activeAttemptID: UUID?

    mutating func beginMaximize(current: Frame,
                                target: Frame,
                                isClose: (Frame, Frame) -> Bool) -> Attempt {
        let supersedesActiveAttempt = activeAttemptID != nil
        let attempt = Attempt(kind: .maximize,
                              previousOriginal: original,
                              previousMaximized: maximized)
        let gapChangedWhileMaximized = maximized.map { isClose(current, $0) } ?? false
        // A frame sampled during our own maximize/restore animation is neither
        // a deliberate manual position nor a safe restore target. Once the
        // attempt completes, a later manual move is still allowed to replace it.
        if !supersedesActiveAttempt, !gapChangedWhileMaximized { original = current }
        maximized = target
        activeAttemptID = attempt.id
        return attempt
    }

    mutating func beginRestore() -> Attempt {
        let attempt = Attempt(kind: .restore,
                              previousOriginal: original,
                              previousMaximized: maximized)
        activeAttemptID = attempt.id
        return attempt
    }

    /// Returns false for a completion superseded by another attempt or reset.
    @discardableResult
    mutating func complete(_ attempt: Attempt, success: Bool) -> Bool {
        guard activeAttemptID == attempt.id else { return false }
        activeAttemptID = nil
        if success {
            if case .restore = attempt.kind {
                original = nil
                maximized = nil
            }
        } else {
            original = attempt.previousOriginal
            maximized = attempt.previousMaximized
        }
        return true
    }

    mutating func reset() {
        activeAttemptID = nil
        original = nil
        maximized = nil
    }

    var isEmpty: Bool { original == nil && maximized == nil }
}
