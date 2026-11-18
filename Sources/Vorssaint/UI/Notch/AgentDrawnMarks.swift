// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Marks for the agents that have no desktop app to borrow one from, drawn
/// as vectors on a 24 point grid and handed out as template images.
/// Antigravity's arch is its maker's logo; Command Code's mark is the Command
/// key (a 2 point round-capped stroke).
enum AgentDrawnMarks {
    private static let antigravity =
        "M12 3.4c-.8 0-1.5.4-1.9 1.1L3.3 16.8c-1.1 1.9.3 3.8 2.3 3.8 1 0 1.8-.5 2.4-1.2 1.2-1.4 2.4-2.4 4-2.4"
        + "s2.8 1 4 2.4c.6.7 1.4 1.2 2.4 1.2 2 0 3.4-1.9 2.3-3.8L13.9 4.5c-.4-.7-1.1-1.1-1.9-1.1Z"

    static func image(for provider: AgentProvider) -> NSImage? {
        switch provider {
        case .antigravity:
            guard let path = path(antigravity) else { return nil }
            return template { path.fill() }
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

    // MARK: SVG path data

    /// M, L, H, V, C, S and Z in absolute and relative form: all the marks use.
    static func path(_ data: String) -> NSBezierPath? {
        var numbers: [CGFloat] = []
        var tokens: [(command: Character, numbers: [CGFloat])] = []
        var command: Character?
        var number = ""
        func flush() {
            if let value = Double(number) { numbers.append(CGFloat(value)) }
            number = ""
        }
        func close() {
            flush()
            if let command { tokens.append((command, numbers)) }
            numbers = []
        }
        for character in data {
            if character.isLetter {
                close()
                command = character
            } else if character == "-" {
                flush()
                number = "-"
            } else if character == "." {
                if number.contains(".") { flush() }
                number += "."
            } else if character.isNumber {
                number.append(character)
            } else {
                flush()
            }
        }
        close()

        let path = NSBezierPath()
        var current = NSPoint.zero
        var start = NSPoint.zero
        var lastControl: NSPoint?
        for (command, v) in tokens {
            let relative = command.isLowercase
            let dx = relative ? current.x : 0
            let dy = relative ? current.y : 0
            switch Character(command.uppercased()) {
            case "M":
                guard v.count >= 2 else { return nil }
                current = NSPoint(x: v[0] + dx, y: v[1] + dy)
                start = current
                path.move(to: current)
                lastControl = nil
            case "L":
                guard v.count >= 2 else { return nil }
                current = NSPoint(x: v[0] + dx, y: v[1] + dy)
                path.line(to: current)
                lastControl = nil
            case "H":
                guard let x = v.first else { return nil }
                current.x = x + dx
                path.line(to: current)
                lastControl = nil
            case "V":
                guard let y = v.first else { return nil }
                current.y = y + dy
                path.line(to: current)
                lastControl = nil
            case "C":
                guard v.count >= 6, v.count % 6 == 0 else { return nil }
                for i in stride(from: 0, to: v.count, by: 6) {
                    let dx = relative ? current.x : 0
                    let dy = relative ? current.y : 0
                    let c1 = NSPoint(x: v[i] + dx, y: v[i + 1] + dy)
                    let c2 = NSPoint(x: v[i + 2] + dx, y: v[i + 3] + dy)
                    let end = NSPoint(x: v[i + 4] + dx, y: v[i + 5] + dy)
                    path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
                    current = end
                    lastControl = c2
                }
            case "S":
                guard v.count >= 4, v.count % 4 == 0 else { return nil }
                for i in stride(from: 0, to: v.count, by: 4) {
                    let dx = relative ? current.x : 0
                    let dy = relative ? current.y : 0
                    let c1 = lastControl.map { NSPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    let c2 = NSPoint(x: v[i] + dx, y: v[i + 1] + dy)
                    let end = NSPoint(x: v[i + 2] + dx, y: v[i + 3] + dy)
                    path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
                    current = end
                    lastControl = c2
                }
            case "Z":
                path.close()
                current = start
                lastControl = nil
            default:
                return nil
            }
        }
        return path
    }
}
