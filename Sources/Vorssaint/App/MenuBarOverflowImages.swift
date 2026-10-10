// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreImage

/// UI-thread image conversion and rendering, warmed when inventory refreshes.
final class MenuBarOverflowImages {
    private lazy var context = CIContext(options: [.useSoftwareRenderer: true])
    private var cache: [String: NSImage] = [:]

    func removeAll() { cache.removeAll() }

    /// Preserve tonal detail in app icons while allowing AppKit to choose
    /// the foreground color that contrasts with the actual menu bar.
    func monochrome(_ icon: NSImage, cacheKey: String) -> NSImage {
        if icon.isTemplate { return icon }
        if let cached = cache[cacheKey] { return cached }
        guard let data = icon.tiffRepresentation, let input = CIImage(data: data),
              let filter = CIFilter(name: "CIColorMatrix") else { return icon }
        filter.setValue(input, forKey: kCIInputImageKey)
        for key in ["inputRVector", "inputGVector", "inputBVector"] {
            filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: key)
        }
        filter.setValue(CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0), forKey: "inputAVector")
        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return icon }
        let result = NSImage(cgImage: cgImage, size: icon.size)
        result.isTemplate = true
        cache[cacheKey] = result
        return result
    }

    func inlineImage(icons: [NSImage], capacity: Int, pageNumber: String?, monochrome: Bool) -> NSImage {
        let width = CGFloat(capacity) * 24 + (pageNumber != nil ? 32 : 0)
        let image = NSImage(size: NSSize(width: width + 20, height: 18))
        image.lockFocus()
        var x: CGFloat = 0
        if let pageNumber {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let text = NSAttributedString(string: pageNumber, attributes: attributes)
            text.draw(at: CGPoint(x: (32 - text.size().width) / 2, y: (18 - text.size().height) / 2))
            x += 32
        }
        x += CGFloat(capacity - icons.count) * 24
        for icon in icons.reversed() {
            icon.draw(in: CGRect(x: x + 3, y: 0, width: 18, height: 18))
            x += 24
        }
        NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .bold))?
            .draw(in: CGRect(x: x + 4, y: 3, width: 12, height: 12))
        image.unlockFocus()
        image.isTemplate = monochrome
        return image
    }
}
