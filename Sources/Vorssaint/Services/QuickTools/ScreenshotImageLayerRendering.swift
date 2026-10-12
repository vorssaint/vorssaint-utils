// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ScreenshotImageLayerRendering {
    static func draw(_ annotation: ScreenshotSupport.Annotation, in context: CGContext) {
        guard let image = annotation.imageAsset?.image else { return }
        context.saveGState()
        context.translateBy(x: 0, y: annotation.rect.minY + annotation.rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: annotation.rect)
        context.restoreGState()
    }

    static func composite(base: CGImage, images: [ScreenshotSupport.Annotation]) -> CGImage? {
        if images.isEmpty { return base }
        guard let context = CGContext(data: nil, width: base.width, height: base.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        context.draw(base, in: bounds)
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: 1, y: -1)
        context.clip(to: bounds)
        for image in images { draw(image, in: context) }
        return context.makeImage()
    }
}

extension ScreenshotRenderer {
    final class ImageLayerCache {
        private var base: CGImage?
        private var annotations: [ScreenshotSupport.Annotation] = []
        private var samples: [UUID: BlurSources] = [:]

        func beginPass(base: CGImage?, annotations: [ScreenshotSupport.Annotation]) {
            if self.base !== base || self.annotations != annotations {
                self.base = base
                self.annotations = annotations
                samples.removeAll()
            }
        }

        func sources(for annotation: ScreenshotSupport.Annotation,
                     images: [ScreenshotSupport.Annotation], original: BlurSources) -> BlurSources? {
            if images.isEmpty && annotation.renderReferenceSize == nil { return original }
            if var cached = samples[annotation.id] {
                cached.textRuns = original.textRuns
                return cached
            }
            guard let base,
                  let composite = ScreenshotImageLayerRendering.composite(base: base, images: images)
            else { return nil }
            var result = original
            result.imageLayerCache = nil
            let reference = annotation.renderReferenceSize
            switch annotation.blurStyle {
            case .pixelate:
                guard let sample = ScreenshotRenderer.pixelatedImage(
                    from: composite, level: annotation.blurLevel, referenceSize: reference) else { return nil }
                result.mosaics = [annotation.blurLevel: sample]
            case .blur:
                guard let sample = ScreenshotRenderer.softBlurredImage(
                    from: composite, level: annotation.blurLevel, referenceSize: reference) else { return nil }
                result.softBlurs = [annotation.blurLevel: sample]
            case .erase:
                return original
            }
            samples[annotation.id] = result
            return result
        }
    }
}
