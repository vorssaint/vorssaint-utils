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

    /// The base with the images drawn over it. `region`, in whole canvas
    /// pixels, keeps only that part of the canvas.
    static func composite(base: CGImage, images: [ScreenshotSupport.Annotation],
                          region: CGRect? = nil) -> CGImage? {
        if images.isEmpty && region == nil { return base }
        let bounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let crop = region ?? bounds
        guard !crop.isEmpty,
              let context = CGContext(data: nil, width: Int(crop.width), height: Int(crop.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // The region's top-left pixel lands on the bitmap's.
        context.translateBy(x: -crop.minX, y: crop.maxY - bounds.height)
        context.draw(base, in: bounds)
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: 1, y: -1)
        context.clip(to: bounds)
        for image in images { draw(image, in: context) }
        return context.makeImage()
    }
}

extension ScreenshotRenderer {
    /// Samples for the blur areas the capture's own samples cannot serve:
    /// areas over pasted images, which paint the images below them too, and
    /// areas kept at their size from before a canvas expansion. A sample
    /// carries random noise, so each one is made once for its style, level,
    /// reference size and the images below, and every redraw after that
    /// reuses it while other marks change. All of them go with the capture.
    final class ImageLayerCache {
        /// Holding the asset keeps its identity from being reused by a newer one.
        private struct Layer: Equatable {
            let asset: ScreenshotSupport.ImageAsset
            let rect: CGRect
        }

        private struct Key: Equatable {
            let style: ScreenshotSupport.BlurStyleID
            let level: Int
            let referenceSize: CGSize?
            let layers: [Layer]
            let region: CGRect?
        }

        private final class Entry {
            let key: Key
            let sources: BlurSources
            /// The last redraw that used it. A new entry starts outside any,
            /// so its first use begins its erase fills' pass too.
            var pass = -1

            init(key: Key, sources: BlurSources) {
                self.key = key
                self.sources = sources
            }
        }

        static let entryLimit = 16
        private var base: CGImage?
        private var entries: [Entry] = []
        private var pass = 0

        /// Whether an area paints from the capture's own samples: no pasted
        /// image lies below it, and it kept no size from before an expansion.
        /// Erasing reads the pixels themselves, so only images change it.
        static func usesCapture(_ annotation: ScreenshotSupport.Annotation,
                                below images: [ScreenshotSupport.Annotation]) -> Bool {
            if annotation.blurStyle == .erase { return images.isEmpty }
            return images.isEmpty && annotation.renderReferenceSize == nil
        }

        /// The images among `preceding` that show in an area: those inside
        /// it and those close enough to its edge for its paint to read.
        /// Images farther away leave it as it is, so moving one keeps its sample.
        static func images(below annotation: ScreenshotSupport.Annotation,
                           among preceding: [ScreenshotSupport.Annotation],
                           textRuns: [CGRect]?, imageSize: CGSize) -> [ScreenshotSupport.Annotation] {
            guard !preceding.isEmpty else { return [] }
            let read = readRect(of: annotation, textRuns: textRuns.map { $0 + preceding.map(\.rect) },
                                imageSize: imageSize)
            return preceding.filter { $0.rect.intersects(read) }
        }

        /// What an area's paint is made from: the area and the pixels past its
        /// edge that the paint reads. Erasing reads a strip of up to 8 px
        /// around each run it fills, and a text only run can reach past the
        /// area. A mosaic block on the edge spans up to two blocks of pixels
        /// past it, and a blur spreads about one block more.
        static func readRect(of annotation: ScreenshotSupport.Annotation,
                             textRuns: [CGRect]?, imageSize: CGSize) -> CGRect {
            let area = annotation.rect.standardized
            switch annotation.blurStyle {
            case .erase:
                let runs = annotation.blurTextOnly
                    ? ScreenshotSupport.blurTextRuns(in: area, from: textRuns) : []
                return runs.reduce(area) { $0.union($1) }.integral.insetBy(dx: -8, dy: -8)
            case .pixelate, .blur:
                let block = CGFloat(ScreenshotSupport.pixelBlockSize(
                    for: annotation.renderReferenceSize ?? imageSize, level: annotation.blurLevel))
                let reach = block * (annotation.blurStyle == .blur ? 3 : 2)
                return area.insetBy(dx: -reach, dy: -reach)
            }
        }

        /// Starts a redraw. An erase sample holds a copy of the canvas its
        /// area reads, so it goes as soon as a redraw no longer uses it.
        /// Mosaics and blurs are small and stay until there are many, so
        /// moving an image back finds the same noise again.
        func beginPass(base: CGImage?) {
            if self.base !== base {
                self.base = base
                entries.removeAll()
            } else {
                let crowded = entries.count > Self.entryLimit
                entries.removeAll { $0.pass != pass && (crowded || $0.sources.eraseCache != nil) }
            }
            pass += 1
        }

        func sources(for annotation: ScreenshotSupport.Annotation,
                     images: [ScreenshotSupport.Annotation], original: BlurSources) -> BlurSources? {
            if Self.usesCapture(annotation, below: images) { return original }
            let style = annotation.blurStyle
            let layers = images.compactMap { image in
                image.imageAsset.map { Layer(asset: $0, rect: image.rect) }
            }
            // Recognition reads only the capture, so a text only area covers
            // the part of each image below it as text it could not read.
            let textRuns = original.textRuns.map { $0 + layers.map(\.rect) }
            // An erase sample keeps only the part of the canvas its area
            // reads, so moving the area makes a new one.
            var region: CGRect?
            if style == .erase, let base {
                let bounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
                region = Self.readRect(of: annotation, textRuns: textRuns, imageSize: bounds.size)
                    .intersection(bounds)
            }
            let key = Key(style: style,
                          level: style == .erase ? 0 : annotation.blurLevel,
                          referenceSize: style == .erase ? nil : annotation.renderReferenceSize,
                          layers: layers, region: region)
            let entry: Entry
            if let hit = entries.first(where: { $0.key == key }) {
                entry = hit
            } else {
                guard let made = makeEntry(key, images: images) else { return nil }
                entries.append(made)
                entry = made
            }
            if entry.pass != pass {
                entry.pass = pass
                entry.sources.eraseCache?.beginPass(image: entry.sources.image, textRuns: textRuns)
            }
            var result = entry.sources
            result.textRuns = textRuns
            return result
        }

        private func makeEntry(_ key: Key, images: [ScreenshotSupport.Annotation]) -> Entry? {
            guard let base,
                  let composite = ScreenshotImageLayerRendering.composite(
                    base: base, images: images, region: key.region)
            else { return nil }
            var sources = BlurSources()
            switch key.style {
            case .pixelate:
                guard let sample = ScreenshotRenderer.pixelatedImage(
                    from: composite, level: key.level, referenceSize: key.referenceSize) else { return nil }
                sources.mosaics = [key.level: sample]
            case .blur:
                guard let sample = ScreenshotRenderer.softBlurredImage(
                    from: composite, level: key.level, referenceSize: key.referenceSize) else { return nil }
                sources.softBlurs = [key.level: sample]
            case .erase:
                sources.image = composite
                sources.imageOrigin = key.region?.origin ?? .zero
                sources.eraseCache = EraseCache()
            }
            return Entry(key: key, sources: sources)
        }
    }
}
