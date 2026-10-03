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

    /// With "only between displays" on, hover moves focus only when the
    /// pointer rests on a different display than the focused window. Without
    /// a focused window there is nothing holding focus to a display.
    static func crossesDisplays(pointer: CGPoint,
                                focusedWindowBounds: CGRect?,
                                displays: [CGRect]) -> Bool {
        guard let focusedWindowBounds,
              let focusedDisplay = display(of: focusedWindowBounds, in: displays)
        else { return true }
        guard let pointerDisplay = displays.firstIndex(where: { contains($0, pointer) }) else { return false }
        return pointerDisplay != focusedDisplay
    }

    /// The bounds of the window holding the app's keyboard focus, as
    /// Accessibility names it. That can be a floating panel on one display
    /// while the app's frontmost normal window sits on another, so the
    /// stacking order alone cannot tell. Only when Accessibility names no
    /// window does the app's frontmost window, panels included, stand in.
    /// A named window counts on any layer, so a focused modal alert above
    /// the app layers still holds hover to its display.
    static func focusedWindowBounds(in windows: [[String: Any]],
                                    processID: pid_t,
                                    focusedWindowID: CGWindowID?) -> CGRect? {
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = WindowServerSupport.bounds(from: window),
                  bounds.width > 1, bounds.height > 1
            else { continue }
            if let focusedWindowID {
                guard (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value == focusedWindowID
                else { continue }
            } else {
                guard MouseAppExceptionSupport.appWindowLayers.contains(layer) else { continue }
            }
            return bounds
        }
        return nil
    }

    /// The display a window mostly sits on, as macOS assigns it.
    private static func display(of bounds: CGRect, in displays: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, display) in displays.enumerated() {
            let overlap = display.intersection(bounds)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        return best?.index
    }

    /// Right and bottom edges count, like the pointer reaching a screen edge.
    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
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
