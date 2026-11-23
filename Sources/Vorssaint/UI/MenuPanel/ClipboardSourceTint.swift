// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum ClipboardSourceTint {
    static func color(from icon: NSImage) -> Color? {
        let side = 24
        let bytesPerRow = side * 4
        guard let image = icon.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                          | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var weighted = SIMD3<Double>.zero
        var total = 0.0

        for index in stride(from: 0, to: side * bytesPerRow, by: 4) {
            let alpha = Double(pixels[index + 3])
            guard alpha > 140 else { continue }
            let rgb = SIMD3(Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2])) / alpha
            let saturation = max(rgb.x, rgb.y, rgb.z) - min(rgb.x, rgb.y, rgb.z)
            guard saturation >= 0.14 else { continue }
            let weight = saturation * saturation
            weighted += rgb * weight
            total += weight
        }

        guard total >= 1 else { return nil }
        var rgb = weighted / total
        // Leave enough contrast for the white labels even on a yellow or green icon.
        while luminance(rgb) > 0.175 { rgb *= 0.94 }
        return Color(red: rgb.x, green: rgb.y, blue: rgb.z)
    }

    private static func luminance(_ rgb: SIMD3<Double>) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.x) + 0.7152 * linear(rgb.y) + 0.0722 * linear(rgb.z)
    }
}
