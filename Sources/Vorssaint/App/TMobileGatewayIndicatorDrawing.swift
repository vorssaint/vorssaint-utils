// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Native, appearance-aware artwork inspired by the supplied rounded bars and
/// compact radio badges. No downloaded bitmap, web content or background tile.
enum TMobileGatewayIndicatorDrawing {
    struct Layout {
        let size: NSSize
        let technologyX: CGFloat?
        let barsX: CGFloat?
        let bandsX: CGFloat?
        let badgeWidth: CGFloat
    }

    private static let cache: NSCache<NSString, NSImage> = {
        let result = NSCache<NSString, NSImage>()
        result.countLimit = 100
        result.totalCostLimit = 1024 * 1024
        return result
    }()

    static func image(_ display: TMobileGatewayMenuBarSupport.ConnectionDisplay,
                      style: MenuBarBlockStyle,
                      components rawComponents: TMobileGatewayMenuBarComponents = .current) -> NSImage {
        let components = TMobileGatewayMenuBarComponents.sanitized(rawComponents.rawValue)
        let shownBadge = components.contains(.technology) ? display.badge : ""
        let shownBands = components.contains(.bands) ? display.bands : ""
        let shownBars = components.contains(.bars) ? display.bars ?? -1 : -1
        let key = "\(components.rawValue)|\(shownBadge)|\(shownBands)|\(shownBars)|\(style)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let layout = layout(display, style: style, components: components)
        let height = layout.size.height
        let badgeFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let bandFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
        let uc = display.badge == "5G UC"
        let badge = uc ? "5G" : display.badge
        let bands = display.bands.isEmpty ? "—" : display.bands
        let image = NSImage(size: layout.size, flipped: false) { _ in
            if let x = layout.technologyX {
                let attributes: [NSAttributedString.Key: Any] = [.font: badgeFont, .foregroundColor: NSColor.labelColor]
                let badgeSize = (badge as NSString).size(withAttributes: attributes)
                (badge as NSString).draw(at: NSPoint(x: x, y: (height - badgeSize.height) / 2), withAttributes: attributes)
                if uc {
                    let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 6, weight: .heavy),
                                                                .foregroundColor: NSColor.labelColor]
                    ("U" as NSString).draw(at: NSPoint(x: x + layout.badgeWidth - 6, y: height / 2 - 0.2), withAttributes: small)
                    ("C" as NSString).draw(at: NSPoint(x: x + layout.badgeWidth - 6, y: height / 2 - 6), withAttributes: small)
                }
            }
            if let x = layout.barsX {
                // Preserve the gateway's actual 0...5 scale.
                for index in 0..<5 {
                    let barHeight = CGFloat(4 + index * 2)
                    let rect = NSRect(x: x + CGFloat(index) * 3.6, y: (height - 12) / 2,
                                      width: 2.4, height: barHeight)
                    let filled = display.bars.map { index < $0 } ?? false
                    NSColor.labelColor.withAlphaComponent(filled ? 1 : 0.22).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2).fill()
                }
            }
            if let x = layout.bandsX {
                let attributes: [NSAttributedString.Key: Any] = [.font: bandFont, .foregroundColor: NSColor.labelColor]
                let bandSize = (bands as NSString).size(withAttributes: attributes)
                (bands as NSString).draw(at: NSPoint(x: x, y: (height - bandSize.height) / 2), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = false
        cache.setObject(image, forKey: key, cost: max(1, Int(layout.size.width * height) * 16))
        return image
    }

    /// Omitted pieces reserve no space. All three retain their previous geometry.
    static func layout(_ display: TMobileGatewayMenuBarSupport.ConnectionDisplay,
                       style: MenuBarBlockStyle,
                       components rawComponents: TMobileGatewayMenuBarComponents) -> Layout {
        let components = TMobileGatewayMenuBarComponents.sanitized(rawComponents.rawValue)
        let uc = display.badge == "5G UC"
        let badge = uc ? "5G" : display.badge
        let badgeWidth = ceil((badge as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold)]).width) + (uc ? 7 : 0)
        let bands = display.bands.isEmpty ? "—" : display.bands
        let bandWidth = max(18, ceil((bands as NSString).size(withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)]).width))
        var width: CGFloat = 0
        func append(_ pieceWidth: CGFloat) -> CGFloat {
            if width > 0 { width += 4 }
            let x = width
            width += pieceWidth
            return x
        }
        let technologyX = components.contains(.technology) ? append(badgeWidth) : nil
        let barsX = components.contains(.bars) ? append(18) : nil
        let bandsX = components.contains(.bands) ? append(bandWidth) : nil
        return Layout(size: NSSize(width: width + 4, height: style == .readable ? 23 : 21),
                      technologyX: technologyX, barsX: barsX, bandsX: bandsX, badgeWidth: badgeWidth)
    }
}
