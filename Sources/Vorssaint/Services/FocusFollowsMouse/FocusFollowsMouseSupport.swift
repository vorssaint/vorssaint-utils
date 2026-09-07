// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum FocusFollowsMouseSupport {
    static let defaultDelayMilliseconds = 250
    static let delayRange = 100...1_000

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
}

struct FocusFollowsMouseEvaluation: Equatable {
    let point: CGPoint
    let generation: UInt64
}

struct FocusFollowsMouseState: Equatable {
    private(set) var point: CGPoint?
    private(set) var movedAt: TimeInterval = 0
    private(set) var generation: UInt64 = 0
    private var evaluatedGeneration: UInt64?

    var hasPendingEvaluation: Bool {
        point != nil && evaluatedGeneration != generation
    }

    mutating func recordMovement(to point: CGPoint, at time: TimeInterval) {
        self.point = point
        movedAt = time
        generation &+= 1
        evaluatedGeneration = nil
    }

    mutating func reset() {
        point = nil
        generation &+= 1
        evaluatedGeneration = nil
    }

    mutating func nextEvaluation(at time: TimeInterval,
                                 delayMilliseconds: Int) -> FocusFollowsMouseEvaluation? {
        guard let point,
              hasPendingEvaluation,
              time - movedAt >= Double(FocusFollowsMouseSupport.sanitizedDelay(delayMilliseconds)) / 1_000
        else { return nil }
        evaluatedGeneration = generation
        return FocusFollowsMouseEvaluation(point: point, generation: generation)
    }

    func isCurrent(_ evaluation: FocusFollowsMouseEvaluation) -> Bool {
        evaluation.generation == generation
    }
}
