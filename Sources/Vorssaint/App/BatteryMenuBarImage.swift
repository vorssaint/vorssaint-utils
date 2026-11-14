// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Shared by the status item and its settings preview. The icon keeps a fixed
/// size in each mode; hiding the percentage gives the charge fill more room.
/// As in macOS, the percentage sits to the left of the icon.
enum BatteryMenuBarImage {
    static func make(percent: Int,
                     showsBolt: Bool,
                     externalConnected: Bool,
                     showPercentage: Bool,
                     readable: Bool,
                     color: NSColor) -> NSImage {
        let charge = max(0, min(100, percent))
        let iconSize = showPercentage ? NSSize(width: 22, height: 11) : NSSize(width: 29, height: 15)
        let height: CGFloat = readable ? 22 : 20
        let font = NSFont.monospacedDigitSystemFont(ofSize: readable ? 13 : 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let value = "\(charge)%" as NSString
        let valueSize = value.size(withAttributes: attributes)
        let textWidth = showPercentage ? ("100%" as NSString).size(withAttributes: attributes).width : 0
        let gap: CGFloat = showPercentage ? (readable ? 5 : 4) : 0
        let size = NSSize(width: ceil(iconSize.width + gap + textWidth), height: height)
        // Whole-point offset keeps the outline on the same pixel grid in both modes.
        let iconX = size.width - iconSize.width
        let image = NSImage(size: size, flipped: false) { _ in
            color.setFill()
            color.setStroke()
            let body = NSRect(x: iconX + 0.75, y: (height - iconSize.height) / 2 + 0.75,
                              width: iconSize.width - 3.5, height: iconSize.height - 1.5)
            let outline = NSBezierPath(roundedRect: body, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1.25
            outline.stroke()
            NSBezierPath(roundedRect: NSRect(x: iconX + iconSize.width - 1.75, y: height / 2 - 2,
                                            width: 1.5, height: 4), xRadius: 0.75, yRadius: 0.75).fill()

            let interior = body.insetBy(dx: 1.75, dy: 1.75)
            if charge > 0 {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: interior, xRadius: 0.75, yRadius: 0.75).addClip()
                NSRect(x: interior.minX, y: interior.minY,
                       width: interior.width * CGFloat(charge) / 100, height: interior.height).fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            if showsBolt || externalConnected {
                // A transparent halo keeps the power indicator legible across
                // the charge fill without assuming a menu bar background color.
                let indicator = NSBezierPath()
                let cx = body.midX
                let cy = body.midY
                if showsBolt {
                    let h = iconSize.height * 0.43
                    indicator.move(to: NSPoint(x: cx + 1.5, y: cy + h))
                    indicator.line(to: NSPoint(x: cx - 3, y: cy - 0.5))
                    indicator.line(to: NSPoint(x: cx - 0.25, y: cy - 0.5))
                    indicator.line(to: NSPoint(x: cx - 1.5, y: cy - h))
                    indicator.line(to: NSPoint(x: cx + 3, y: cy + 0.5))
                    indicator.line(to: NSPoint(x: cx + 0.25, y: cy + 0.5))
                    indicator.close()
                } else {
                    indicator.appendRoundedRect(NSRect(x: cx - 3, y: cy - 2, width: 6, height: 4),
                                                xRadius: 1, yRadius: 1)
                    indicator.appendRect(NSRect(x: cx - 2.25, y: cy + 1, width: 1.5, height: 3))
                    indicator.appendRect(NSRect(x: cx + 0.75, y: cy + 1, width: 1.5, height: 3))
                    indicator.appendRect(NSRect(x: cx - 0.75, y: cy - 4, width: 1.5, height: 3))
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                indicator.lineWidth = 2
                indicator.lineJoinStyle = .round
                indicator.stroke()
                NSGraphicsContext.restoreGraphicsState()
                color.setFill()
                indicator.fill()
            }

            if showPercentage {
                // Right-aligned so the gap to the icon stays fixed as digits change.
                value.draw(at: NSPoint(x: iconX - gap - valueSize.width, y: (height - valueSize.height) / 2),
                           withAttributes: attributes)
            }
            return true
        }
        image.accessibilityDescription = "\(charge)%"
        image.isTemplate = false
        return image
    }
}
