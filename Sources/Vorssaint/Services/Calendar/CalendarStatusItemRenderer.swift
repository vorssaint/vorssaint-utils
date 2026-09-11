// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import EventKit

enum CalendarIconStyle: String, CaseIterable, Identifiable { case icon, date, nextEvent; var id: String { rawValue } }

enum CalendarStatusItemRenderer {
    static func render(style: CalendarIconStyle, date: Date, nextEvent: EKEvent?, scale: Double,
                       dateFormat: CalendarDateDisplayFormat = .dayMonth, customPattern: String = "dd/MM") -> NSImage {
        let components: [CalendarMenuBarComponent] = switch style {
        case .icon: [.icon]
        case .date: [.date]
        case .nextEvent: nextEvent == nil ? [.icon] : [.nextEvent]
        }
        return render(components: components,
                      date: date,
                      nextEvent: nextEvent,
                      scale: scale,
                      dateFormat: dateFormat,
                      customPattern: customPattern)
    }

    static func render(components: [CalendarMenuBarComponent], date: Date, nextEvent: EKEvent?, scale: Double,
                       dateFormat: CalendarDateDisplayFormat = .dayMonth, customPattern: String = "dd/MM") -> NSImage {
        let resolved = components.uniqued()
        let resolvedComponents = resolved.isEmpty ? [.icon] : resolved
        let rendered = resolvedComponents.compactMap { component -> NSImage? in
            switch component {
            case .icon:
                let image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calendar") ?? NSImage()
                image.isTemplate = true
                return image
            case .date:
                return renderText(dateFormat.string(from: date, customPattern: customPattern),
                                  scale: scale,
                                  maxWidth: 160)
            case .nextEvent:
                guard let nextEvent else { return nil }
                let rawTitle = nextEvent.title ?? ""
                let title = rawTitle.count > 25 ? String(rawTitle.prefix(24)) + "…" : rawTitle
                let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
                return renderText("\(title) \(formatter.string(from: nextEvent.startDate))",
                                  scale: scale,
                                  maxWidth: 180)
            }
        }
        if rendered.isEmpty {
            let image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Calendar") ?? NSImage()
            image.isTemplate = true
            return image
        }
        guard rendered.count > 1 else { return rendered[0] }
        return composite(rendered, spacing: 6)
    }

    private static func renderText(_ text: String, scale: Double, maxWidth: CGFloat) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12 * scale, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        let measuredSize = (text as NSString).size(withAttributes: attributes)
        let paddedWidth = ceil(measuredSize.width) + 10
        let paddedHeight = ceil(max(14, measuredSize.height)) + 8
        let size = NSSize(width: min(maxWidth, max(24, paddedWidth)),
                          height: max(18, paddedHeight))
        let image = NSImage(size: size)
        image.lockFocus()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let drawRect = NSRect(
            x: 0,
            y: floor((size.height - measuredSize.height) / 2) - 1,
            width: size.width,
            height: measuredSize.height
        )
        (text as NSString).draw(in: drawRect, withAttributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func composite(_ images: [NSImage], spacing: CGFloat) -> NSImage {
        let heights = images.map(\.size.height)
        let width = images.reduce(CGFloat(0)) { $0 + $1.size.width } + spacing * CGFloat(max(0, images.count - 1))
        let height = max(18, heights.max() ?? 18)
        let image = NSImage(size: NSSize(width: ceil(width), height: ceil(height)))
        image.lockFocus()
        var x: CGFloat = 0
        for subimage in images {
            let y = floor((height - subimage.size.height) / 2)
            subimage.draw(in: NSRect(x: x, y: y, width: subimage.size.width, height: subimage.size.height))
            x += subimage.size.width + spacing
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
