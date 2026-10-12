// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ScreenshotCanvasExpansionPreview: View {
    let originalSize: CGSize
    let draft: CGRect
    let fill: ScreenshotCanvasSupport.Fill
    let zoom: CGFloat
    let scale: CGFloat

    static let checker: CGColor = {
        var callbacks = CGPatternCallbacks(version: 0, drawPattern: { _, context in
            context.setFillColor(CGColor(gray: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            context.setFillColor(CGColor(gray: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            context.fill(CGRect(x: 4, y: 4, width: 4, height: 4))
        }, releaseInfo: nil)
        let pattern = CGPattern(info: nil, bounds: CGRect(x: 0, y: 0, width: 8, height: 8),
                                matrix: .identity, xStep: 8, yStep: 8,
                                tiling: .constantSpacing, isColored: true, callbacks: &callbacks)!
        return CGColor(patternSpace: CGColorSpace(patternBaseSpace: nil)!,
                       pattern: pattern, components: [1])!
    }()

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                let outer = CGRect(origin: .zero, size: size)
                let old = CGRect(x: -draft.minX * zoom, y: -draft.minY * zoom,
                                 width: originalSize.width * zoom, height: originalSize.height * zoom)
                cg.saveGState()
                cg.addRect(outer)
                cg.addRect(old)
                cg.clip(using: .evenOdd)
                cg.setFillColor(fill == .transparent ? Self.checker : fill.cgColor)
                cg.fill(outer)
                cg.restoreGState()
                cg.setStrokeColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1))
                cg.setLineWidth(1)
                cg.stroke(outer.insetBy(dx: 0.5, dy: 0.5))
                let displayScale = scale * zoom
                let radius = 3.5 * displayScale
                let lineWidth = 1.5 * displayScale
                cg.setStrokeColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.9))
                cg.setLineWidth(lineWidth)
                for handle in ScreenshotSupport.Handle.allCases {
                    let point = handle.position(in: outer.insetBy(
                        dx: min(4, outer.width / 4), dy: min(4, outer.height / 4)))
                    let dot = CGRect(x: point.x - radius, y: point.y - radius,
                                     width: radius * 2, height: radius * 2)
                    cg.setFillColor(CGColor(gray: 1, alpha: 1))
                    cg.fillEllipse(in: dot)
                    cg.strokeEllipse(in: dot)
                }
            }
        }
        .frame(width: draft.width * zoom, height: draft.height * zoom)
        .allowsHitTesting(false)
    }
}
