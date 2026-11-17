// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Marks for the agents that have no desktop app to borrow one from, drawn
/// as vectors on a 24 point grid and handed out as template images.
/// Command Code's mark is the Command key (a 2 point round-capped stroke).
enum AgentDrawnMarks {
    static func image(for provider: AgentProvider) -> NSImage? {
        switch provider {
        case .commandcode:
            return template { commandKey().stroke() }
        default:
            return nil
        }
    }

    private static func template(_ draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
            NSColor.black.set()
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A square with a loop at each corner.
    private static func commandKey() -> NSBezierPath {
        let key = NSBezierPath()
        key.lineWidth = 2
        key.lineCapStyle = .round
        key.lineJoinStyle = .round
        key.appendRect(NSRect(x: 9, y: 9, width: 6, height: 6))
        // Each loop leaves its corner along one side, goes round a circle
        // and comes back along the other.
        for (corner, center) in [
            (NSPoint(x: 9, y: 9), NSPoint(x: 6.5, y: 6.5)),
            (NSPoint(x: 15, y: 9), NSPoint(x: 17.5, y: 6.5)),
            (NSPoint(x: 9, y: 15), NSPoint(x: 6.5, y: 17.5)),
            (NSPoint(x: 15, y: 15), NSPoint(x: 17.5, y: 17.5)),
        ] {
            let sx: CGFloat = corner.x < 12 ? -1 : 1
            let sy: CGFloat = corner.y < 12 ? -1 : 1
            // The circle touches the corner's column and row at 2.5 out.
            let start = NSPoint(x: corner.x, y: center.y)
            let end = NSPoint(x: center.x, y: corner.y)
            key.move(to: corner)
            key.line(to: start)
            // Three quarters round the circle, away from the square.
            let from = atan2(start.y - center.y, start.x - center.x) * 180 / .pi
            let to = atan2(end.y - center.y, end.x - center.x) * 180 / .pi
            key.appendArc(withCenter: center, radius: 2.5, startAngle: from, endAngle: to,
                          clockwise: sx * sy > 0)
            key.line(to: corner)
        }
        return key
    }
}
