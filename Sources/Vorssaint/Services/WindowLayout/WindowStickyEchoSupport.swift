// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Whether a reported frame is the result of our own write or a real change.
enum WindowStickyVerdict: Equatable {
    case echo
    case real
}

/// Remembers the frames this service wrote (or placed) for one window. An event
/// is an echo only when the window now sits on one of those frames; anything
/// else is the user moving the window and must be processed, even right after
/// a write. Pure value logic, no Accessibility calls.
struct WindowStickyEchoGuard {
    private(set) var expected: [(frame: CGRect, expires: TimeInterval)] = []
    /// Echoes of one write can arrive late; the entry is forgotten after this.
    static let lifetime: TimeInterval = 1.0
    static let capacity = 4

    mutating func noteWrite(_ frame: CGRect, now: TimeInterval) {
        expected.removeAll { $0.expires <= now || Self.matches($0.frame, frame) }
        expected.append((frame, now + Self.lifetime))
        if expected.count > Self.capacity { expected.removeFirst(expected.count - Self.capacity) }
    }

    mutating func classify(reported: CGRect, now: TimeInterval) -> WindowStickyVerdict {
        expected.removeAll { $0.expires <= now }
        return expected.contains { Self.matches($0.frame, reported) } ? .echo : .real
    }

    static func matches(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = WindowStickySmoothing.echoTolerance) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}

/// Detects the end of a drag: no real event for `interval`. Reports it once.
struct WindowStickyIdleTracker {
    private(set) var lastEvent: TimeInterval?
    static let interval: TimeInterval = 0.2

    mutating func note(at now: TimeInterval) { lastEvent = now }

    /// True exactly once after the events stopped; false while they continue.
    mutating func consumeIfIdle(at now: TimeInterval, interval: TimeInterval = WindowStickyIdleTracker.interval) -> Bool {
        guard let last = lastEvent, now - last >= interval else { return false }
        lastEvent = nil
        return true
    }
}

extension WindowStickyEdgeSupport {
    /// The gap between the facing edges of `driver` and `follower` at `edge`,
    /// never negative: an overlap at the start counts as a flush edge.
    static func facingGap(edge: WindowStickyEdge, driver: CGRect, follower: CGRect) -> CGFloat {
        let raw: CGFloat
        switch edge {
        case .right: raw = follower.minX - driver.maxX
        case .left: raw = driver.minX - follower.maxX
        case .bottom: raw = follower.minY - driver.maxY
        case .top: raw = driver.minY - follower.maxY
        }
        return max(0, raw)
    }

    /// Where the follower belongs for the driver's current frame: the facing
    /// edge sits `gap` away from the driver's edge (exactly flush for gap 0),
    /// the far side stays. Absolute, so lost events never leave a gap or an
    /// overlap behind. `.unaffected` when the follower already sits there.
    static func flushedFrame(edge: WindowStickyEdge, driver: CGRect, follower b: CGRect,
                             gap: CGFloat, tolerance: CGFloat = WindowStickySmoothing.jitterThreshold,
                             minimumSize: CGFloat = 80) -> WindowStickyFollow {
        let gap = max(0, gap)
        var result = b
        switch edge {
        case .right:
            let farEdge = b.maxX
            result.origin.x = driver.maxX + gap
            result.size.width = farEdge - result.origin.x
        case .left:
            result.size.width = driver.minX - gap - b.minX
        case .bottom:
            let farEdge = b.maxY
            result.origin.y = driver.maxY + gap
            result.size.height = farEdge - result.origin.y
        case .top:
            result.size.height = driver.minY - gap - b.minY
        }
        let length = (edge == .left || edge == .right) ? result.width : result.height
        guard length >= minimumSize else { return .tooSmall }
        return WindowStickyEchoGuard.matches(result, b, tolerance: tolerance) ? .unaffected : .follow(result)
    }
}

/// One line per observation, for `Tools/sticky-snap-report.py`.
enum WindowStickyEventLog {
    /// Format: `<uptime seconds> <kind> <window id> <x> <y> <w> <h> <note>`.
    static func line(time: TimeInterval, kind: String, window: Int, frame: CGRect, note: String = "") -> String {
        // Fixed decimal text built by hand: the log is for machines, not for a locale.
        func fixed(_ value: Double, _ digits: Int) -> String {
            let scale = pow(10.0, Double(digits))
            let scaled = Int((abs(value) * scale).rounded())
            let whole = scaled / Int(scale)
            let fraction = String(scaled % Int(scale))
            let padded = String(repeating: "0", count: digits - fraction.count) + fraction
            return (value < 0 && scaled != 0 ? "-" : "") + "\(whole).\(padded)"
        }
        let fields = [fixed(time, 4), kind, String(window), fixed(Double(frame.minX), 1), fixed(Double(frame.minY), 1),
                      fixed(Double(frame.width), 1), fixed(Double(frame.height), 1), note]
        return fields.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
