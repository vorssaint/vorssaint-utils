// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum FocusFollowsMouseSupport {
    static let defaultDelayMilliseconds = 250
    static let delayRange = 100...3_000

    static func sanitizedDelay(_ milliseconds: Int) -> Int {
        min(max(milliseconds, delayRange.lowerBound), delayRange.upperBound)
    }

    /// Ask only the native mouse target's app. Visual overlays may sit above
    /// it without receiving input. Our interactive panels still stop the scan
    /// before any query: entering our Accessibility tree from a worker can
    /// deadlock against the main thread.
    static func queryWindow<Result>(in windows: [[String: Any]],
                                    at point: CGPoint,
                                    pointerWindowID: CGWindowID,
                                    ownProcessID: pid_t,
                                    clickThroughWindowIDs: Set<CGWindowID>,
                                    query: (pid_t) -> Result?) -> Result? {
        guard pointerWindowID != kCGNullWindowID else { return nil }
        for window in windows {
            guard let bounds = WindowServerSupport.bounds(from: window),
                  bounds.contains(point),
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0
            else { continue }

            guard let processID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  processID > 0 else { return nil }
            if processID == ownProcessID {
                guard let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                      clickThroughWindowIDs.contains(windowID) else { return nil }
                continue
            }
            guard (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value == pointerWindowID
            else { continue }
            // The Dock, the menu bar, a banner and the desktop are not what
            // hover follows, and neither is the app behind them, since the
            // pointer is on them and not on it.
            guard let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  MouseAppExceptionSupport.appWindowLayers.contains(layer)
            else { return nil }
            return query(processID)
        }
        return nil
    }

    static func shouldActivate(targetWindowID: CGWindowID,
                               focusedWindowID: CGWindowID?,
                               targetAppIsFrontmost: Bool) -> Bool {
        guard targetAppIsFrontmost else { return true }
        // Games may not expose focus through Accessibility. Reasserting it can
        // release their captured pointer, so require a known different window.
        guard let focusedWindowID else { return false }
        return focusedWindowID != targetWindowID
    }

    /// A canceled focus handoff gives focus back to the window it took it
    /// from only while that app is in front and still reports that window.
    /// A read that fails or finds no window is unknown, so it restores nothing.
    static func shouldRestoreFocus(to previousWindowID: CGWindowID,
                                   reportedFocusedWindowID: CGWindowID?,
                                   appIsFrontmost: Bool) -> Bool {
        appIsFrontmost && reportedFocusedWindowID == previousWindowID
    }
}

struct FocusFollowsMouseEvaluation: Equatable {
    let point: CGPoint
    let generation: UInt64
}

struct FocusFollowsMouseState: Equatable {
    private enum EvaluationPhase: Equatable {
        case pending, evaluating, completed, cancelled
    }

    private(set) var point: CGPoint?
    private(set) var movedAt: TimeInterval = 0
    private(set) var generation: UInt64 = 0
    private var phase = EvaluationPhase.pending
    private var windowID: CGWindowID?
    private var lastMovementAt: TimeInterval = 0
    private var movedDuringEvaluation = false

    var hasPendingEvaluation: Bool {
        point != nil && phase == .pending
    }

    /// With a window ID, the delay counts time over that window, so moving
    /// within it keeps a pending lookup or a completed focus. A canceled
    /// attempt can try again after movement. Without an ID, movement always
    /// restarts the delay.
    mutating func recordMovement(to point: CGPoint, at time: TimeInterval, windowID: CGWindowID? = nil) {
        defer {
            self.point = point
            lastMovementAt = time
        }
        if let windowID, windowID == self.windowID, self.point != nil {
            if phase == .evaluating { movedDuringEvaluation = true }
            if phase != .cancelled { return }
        }
        self.windowID = windowID
        movedAt = time
        generation &+= 1
        phase = .pending
        movedDuringEvaluation = false
    }

    mutating func reset() {
        point = nil
        generation &+= 1
        phase = .pending
        movedDuringEvaluation = false
    }

    mutating func nextEvaluation(at time: TimeInterval,
                                 delayMilliseconds: Int) -> FocusFollowsMouseEvaluation? {
        guard let point,
              hasPendingEvaluation,
              time - movedAt >= Double(FocusFollowsMouseSupport.sanitizedDelay(delayMilliseconds)) / 1_000
        else { return nil }
        phase = .evaluating
        movedDuringEvaluation = false
        return FocusFollowsMouseEvaluation(point: point, generation: generation)
    }

    /// A failed lookup or canceled handoff consumes no successful focus. Wait
    /// for movement, or preserve movement that arrived while the attempt ran.
    mutating func finishEvaluation(_ evaluation: FocusFollowsMouseEvaluation, succeeded: Bool) {
        guard isCurrent(evaluation) else { return }
        phase = succeeded ? .completed : .cancelled
        if !succeeded, movedDuringEvaluation {
            movedAt = lastMovementAt
            generation &+= 1
            phase = .pending
        }
        movedDuringEvaluation = false
    }

    func isCurrent(_ evaluation: FocusFollowsMouseEvaluation) -> Bool {
        evaluation.generation == generation && phase == .evaluating
    }
}
