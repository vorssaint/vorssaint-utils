// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ScreenshotCompositingTests {
    static func solid(_ color: CGColor, size: Int = 160) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    static func render(_ base: CGImage, _ annotations: [ScreenshotSupport.Annotation],
                       sources: ScreenshotRenderer.BlurSources, scale: CGFloat = 1) -> CGImage {
        ScreenshotRenderer.renderExport(
            baseImage: base, annotations: annotations, blurSources: sources, scale: scale,
            annotationShadowsEnabled: false, watermark: ScreenshotSupport.WatermarkStyle(),
            watermarkImage: nil, style: ScreenshotSupport.BackdropStyle(), fill: .none,
            downscaleTo1x: false)!.image
    }

    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let bytes = CFDataGetBytePtr(image.dataProvider!.data!)!
        return Array(UnsafeBufferPointer(start: bytes + y * image.bytesPerRow + x * 4, count: 4))
    }

    static func run(_ suite: TestSuite) {
        let white = solid(CGColor(gray: 1, alpha: 1))
        let green = solid(ScreenshotRenderer.color(.green), size: 16)
        let blue = solid(ScreenshotRenderer.color(.blue), size: 16)
        let lens = ScreenshotSupport.Annotation(tool: .magnifier, rect: CGRect(x: 40, y: 40, width: 80, height: 80))
        // These are deliberately smaller than the lens sample. A later
        // censor must also cover the enlarged pixels outside its own rect.
        let censorRect = CGRect(x: 76, y: 76, width: 8, height: 8)
        let sources = ScreenshotRenderer.BlurSources(mosaics: [5: green], softBlurs: [5: blue], image: white)
        let censors = [
            ScreenshotSupport.Annotation(tool: .redact, rect: censorRect, color: .black),
            ScreenshotSupport.Annotation(tool: .pixelate, rect: censorRect, blurLevel: 5, blurStyle: .pixelate),
            ScreenshotSupport.Annotation(tool: .pixelate, rect: censorRect, blurLevel: 5, blurStyle: .blur),
        ]
        for censor in censors {
            for order in [[censor, lens], [lens, censor]] {
                for scale: CGFloat in [1, 2] {
                    let image = render(white, order, sources: sources, scale: scale)
                    let sample = pixel(image, 74, 80) // Outside the 76...84 censor, inside its enlargement.
                    let expected = censor.tool == .redact ? ScreenshotRenderer.color(.black)
                        : ScreenshotRenderer.color(censor.blurStyle == .pixelate ? .green : .blue)
                    let reference = pixel(solid(expected), 0, 0)
                    suite.expect(zip(sample, reference).allSatisfy { abs(Int($0.0) - Int($0.1)) <= 2 },
                                 "\(censor.tool.rawValue)/\(censor.blurStyle.rawValue) stays censored inside a \(scale)x lens in either layer order")
                    suite.expect(pixel(image, 65, 80)[0] > 240,
                                 "a lens preserves uncensored source pixels beside its censored sample")
                }
            }
        }

        let secretContext = CGContext(data: nil, width: 160, height: 160, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        secretContext.draw(white, in: CGRect(x: 0, y: 0, width: 160, height: 160))
        secretContext.setFillColor(ScreenshotRenderer.color(.red))
        secretContext.fill(censorRect)
        let secret = secretContext.makeImage()!
        let erase = ScreenshotSupport.Annotation(tool: .pixelate, rect: censorRect, blurStyle: .erase)
        for order in [[erase, lens], [lens, erase]] {
            let image = render(secret, order, sources: ScreenshotRenderer.BlurSources(image: secret))
            suite.expect(pixel(image, 74, 80).prefix(3).allSatisfy { $0 > 240 },
                         "erased source pixels never reappear through a magnifier in either layer order")
        }

        let spotlight = ScreenshotSupport.Annotation(tool: .spotlight,
                                                      rect: CGRect(x: 5, y: 5, width: 25, height: 25))
        let mark = ScreenshotSupport.Annotation(tool: .rect, rect: CGRect(x: 60, y: 60, width: 20, height: 20),
                                                color: .white, fill: .solid)
        let blur = ScreenshotSupport.Annotation(tool: .pixelate, rect: CGRect(x: 40, y: 40, width: 80, height: 80),
                                                blurLevel: 5, blurTextOnly: true)
        for style in ScreenshotSupport.BlurStyleID.allCases {
            var area = blur
            area.blurStyle = style
            var input = sources
            input.textRuns = []
            let original = render(white, [spotlight, mark], sources: input)
            let empty = render(white, [spotlight, mark, area], sources: input)
            suite.expect(original.dataProvider!.data! as Data == empty.dataProvider!.data! as Data,
                         "an empty text-only \(style.rawValue) leaves spotlight shading and marks unchanged")
            let run = CGRect(x: 90, y: 90, width: 10, height: 10)
            input.textRuns = [run, run.offsetBy(dx: 2, dy: 2)]
            let partial = render(white, [spotlight, mark, area], sources: input)
            suite.expect(pixel(partial, 50, 50) == pixel(original, 50, 50)
                            && pixel(partial, 70, 70) == pixel(original, 70, 70),
                         "partial text-only \(style.rawValue) never dims untouched background or existing marks")
            input.textRuns = [run]
            let single = render(white, [spotlight, mark, area], sources: input)
            suite.expect(pixel(partial, 95, 95) == pixel(single, 95, 95),
                         "overlapping \(style.rawValue) text runs receive exactly one spotlight dim layer")
        }
        let missing = render(white, [spotlight, mark, blur], sources: ScreenshotRenderer.BlurSources(image: white))
        let unblurred = render(white, [spotlight, mark], sources: ScreenshotRenderer.BlurSources(image: white))
        suite.expect(missing.dataProvider!.data! as Data == unblurred.dataProvider!.data! as Data,
                     "an unavailable blur sample does not add a second spotlight layer")
    }
}
