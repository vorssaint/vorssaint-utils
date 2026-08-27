// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreImage

/// The two display modes: chips drawn directly over the source text, or a
/// blurred backdrop with the translation on top of it.
enum LiveTranslationMode: String {
    case inPlace
    case window

    static func sanitized(_ raw: String) -> LiveTranslationMode {
        LiveTranslationMode(rawValue: raw) ?? .inPlace
    }
}

/// Bakes translated lines onto the captured image, for both the window-mode
/// preview and the copy-image/save-image pill actions. In-place mode's chip
/// background adapts to the *actual* page color directly behind each chip
/// (`ChipContrast.backgroundColor`, sampled per chip, not just binarized to
/// black or white) so the chip reads as part of the page rather than a
/// stamped-on box; text color is whichever of black/white contrasts against
/// that same sampled color. Window mode draws no per-chip background at all
/// (just the adapted text color, directly over the frame's own whole-image
/// blur, closer to how Apple's own system translation overlays render text)
/// since the whole frame is already obscured by that blur; in-place mode
/// still needs a real background per chip, to hide the live source text
/// sitting directly underneath it. Font size is fixed at the source's own
/// per-row size (`LiveTranslationSupport.blockFontSize`) - never shrunk to
/// make a longer translation fit, never enlarged past what the original
/// text actually was. Width is fixed at the OCR box's own width, except a
/// single-row item may first widen sideways into genuinely open neighboring
/// space (`chipSearchWidth`). Whatever the translation still doesn't fit
/// into at that point, it wraps onto more lines and the chip grows
/// downward to fit them - the only dimension that ever grows.
enum LiveTranslationRenderer {
    /// A chip's box and the font size it's drawn at, computed together.
    private struct ChipLayout {
        let rect: CGRect
        let fontSize: CGFloat
    }

    /// Which styling a chip should use, sampled from the real page content
    /// directly behind it (see `chipContrast`). `backgroundColor` is the
    /// actual average color of that patch of page (not binarized) - used
    /// as-is for in-place mode's chip background, ignored entirely in
    /// window mode, which draws no background. `textColor` is whichever of
    /// black/white contrasts against that same sampled color.
    struct ChipContrast {
        let backgroundColor: NSColor
        let textColor: NSColor
    }

    static func compositeImage(base: CGImage,
                               lines: [LiveTranslationSupport.TranslatedLine],
                               mode: LiveTranslationMode) -> CGImage {
        let blurred = ScreenshotRenderer.blurredBackdrop(base, factor: 0.8)
        // Window mode blurs everything and has no "underneath" to show
        // through, so passthrough (already-target-language) blocks need
        // their own chip there; in-place mode leaves them out since the real
        // text is already visible under the transparent panel.
        let visibleLines = mode == .window ? lines : lines.filter { $0.original != $0.translated }
        let backdrop = mode == .window ? blurred : base
        guard let context = CGContext(data: nil, width: base.width, height: base.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return base }
        let size = CGSize(width: base.width, height: base.height)

        let layouts = chipLayouts(for: visibleLines, panelSize: size)

        // Every *image* draw - the base backdrop, and each chip's blurred
        // patch - happens here, in the context's native unflipped
        // (bottom-left, y-up) space: CGContext always draws image content
        // upright relative to the device, not the current CTM, so an image
        // drawn under a flipped CTM renders upside down. That's the exact
        // bug this file used to hit when the base image draw happened after
        // the flip instead of before it, as it does below.
        context.draw(backdrop, in: CGRect(origin: .zero, size: size))
        if mode != .window {
            for layout in layouts {
                drawBlurredPatch(chipRect: layout.rect, panelSize: size, blurredSource: blurred, in: context)
            }
        }

        // Flip to the chips' top-left space *after* every image draw above -
        // text drawing (via the flipped NSGraphicsContext below) is the one
        // thing that *does* behave correctly under a flipped CTM.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        for (line, layout) in zip(visibleLines, layouts) {
            // layout.rect is already in the same pixel space as `base` here
            // (chipFrame was built with panelSize == the image's own pixel
            // size throughout this function), so it's already the correct
            // sample rect with no separate scaling step needed. Sampled from
            // `base`, not `blurred`: the blur radius scales with the *whole
            // capture region's* size (ScreenshotSupport.backdropBlurRadius),
            // so on a large full-page capture it's tens of pixels wide -
            // easily wider than a chip itself - and washes every chip's
            // sample toward the page's overall average color instead of
            // what's actually behind that one chip. `base` has no such
            // distortion.
            let contrast = chipContrast(behind: layout.rect, lineHeight: layout.rect.height / CGFloat(max(1, line.rowCount)), in: base)
            if mode != .window {
                drawTint(chipRect: layout.rect, contrast: contrast, in: context)
            }
            drawText(line.translated, chipRect: layout.rect, fontSize: layout.fontSize,
                    color: contrast.textColor, in: context)
        }

        return context.makeImage() ?? base
    }

    private static let chipPadding: CGFloat = 5

    private static let minChipWidth: CGFloat = 60

    /// How far a single-row item (an isolated sidebar button, a menu label)
    /// is *allowed to search* for room before it has to wrap onto another
    /// line - not how wide it actually ends up (see `renderedChipWidth` for
    /// that).
    /// `rowCount` stays the discriminator (not `original` text length) so it
    /// exactly matches whatever `LiveTranslationSupport.groupIntoParagraphs`
    /// already decided is a standalone line versus a paragraph. A multi-row
    /// paragraph keeps its own width instead - two paragraphs are usually
    /// packed close enough horizontally that widening risks running into
    /// whatever's beside them. `maxWidth` - `LiveTranslationSupport.
    /// maxChipWidths`' neighbor-aware cap - bounds the search to whatever
    /// space is actually open before the next chip in the same row, not
    /// blindly out to the panel's own right edge: on a two-column layout, a
    /// narrow sidebar chip searching "to the panel edge" would otherwise
    /// search straight through the separate content column sitting right
    /// next to it. `minChipWidth` is a safety floor - a source box only a
    /// few points wide (a sliver clipped at the capture region's own edge)
    /// would otherwise force the font down to nearly nothing. Shared with
    /// the live in-place overlay (LiveTranslationChipsView) so both search
    /// the same bound.
    static func chipSearchWidth(box: CGRect, rowCount: Int, maxWidth: CGFloat) -> CGFloat {
        guard rowCount == 1 else { return box.width }
        return max(minChipWidth, max(box.width, maxWidth))
    }

    /// The chip's *drawn* width - shrink-wrapped to the translation's actual
    /// measured width at the fixed font size, not the wider `chipSearchWidth`
    /// bound that search was merely given room to work with. Using the
    /// search bound directly as the drawn width was a real
    /// bug: a short translation that only needed a fraction of the available
    /// space still painted its background out to the full search bound,
    /// running the chip across whatever unrelated content happened to sit
    /// further along - most visibly a left-sidebar chip's background
    /// bleeding into the page's own right-hand content column. A multi-row
    /// paragraph keeps its own fixed box width unchanged. Shared with the
    /// live in-place overlay so both shrink-wrap identically.
    static func renderedChipWidth(text: String, fontSize: CGFloat, box: CGRect,
                                  rowCount: Int, searchWidth: CGFloat) -> CGFloat {
        guard rowCount == 1 else { return box.width }
        let measured = wrappedTextSize(text, fontSize: fontSize, maxWidth: searchWidth - 6).width
        return min(searchWidth, max(box.width, measured + 8))
    }

    /// The box searches sideways for single-row items (see
    /// `chipSearchWidth`) before wrapping; whatever still doesn't fit at that
    /// width, at the source's own fixed font size, wraps onto more lines and
    /// grows the chip downward from the box's own top edge - up to
    /// `LiveTranslationSupport.maxChipHeights`' neighbor-aware cap, a hard
    /// limit, never into space another chip already occupies. Only a
    /// translation that still doesn't fit even at that full downward
    /// allowance shrinks below the source's own size (see `fittedLayout`).
    private static func chipLayouts(for lines: [LiveTranslationSupport.TranslatedLine],
                                    panelSize: CGSize) -> [ChipLayout] {
        let boxes = lines.map { LiveTranslationSupport.chipFrame(boundingBox: $0.boundingBox, panelSize: panelSize) }
        let maxWidths = LiveTranslationSupport.maxChipWidths(frames: boxes, panelWidth: panelSize.width, gap: 4)
        let maxHeights = LiveTranslationSupport.maxChipHeights(frames: boxes, panelHeight: panelSize.height, gap: 4)
        return lines.indices.map { index in
            let line = lines[index]
            let box = boxes[index]
            let sourceFontSize = LiveTranslationSupport.blockFontSize(chipHeight: box.height, rowCount: line.rowCount)
            let searchWidth = chipSearchWidth(box: box, rowCount: line.rowCount, maxWidth: maxWidths[index])
            let (fontSize, height) = fittedLayout(line.translated, sourceFontSize: sourceFontSize,
                                                  width: searchWidth, minHeight: box.height,
                                                  maxHeight: maxHeights[index])
            let width = renderedChipWidth(text: line.translated, fontSize: fontSize, box: box,
                                          rowCount: line.rowCount, searchWidth: searchWidth)
            let rect = CGRect(x: box.minX, y: box.minY, width: width, height: height)
            return ChipLayout(rect: rect, fontSize: fontSize)
        }
    }

    /// Picks the font size and resulting height for a chip: the source's own
    /// size first, growing the chip downward (via word-wrap) to fit it if
    /// needed, but only up to `maxHeight` - a hard, neighbor-aware limit
    /// (`LiveTranslationSupport.maxChipHeights`), never past it. A
    /// translation that still doesn't fit even wrapped into that full
    /// downward allowance shrinks by binary search down to
    /// whatever size actually fits `maxHeight` - a much larger budget than
    /// the original single-row box height this same search used to be
    /// bounded by, so it engages far less often and shrinks far less when it
    /// does. Shared with the live in-place overlay (LiveTranslationChipsView)
    /// so both size chips identically.
    static func fittedLayout(_ text: String, sourceFontSize: CGFloat, width: CGFloat,
                             minHeight: CGFloat, maxHeight: CGFloat) -> (fontSize: CGFloat, height: CGFloat) {
        let availableWidth = width - 6
        func wrappedHeight(_ fontSize: CGFloat) -> CGFloat {
            wrappedTextSize(text, fontSize: fontSize, maxWidth: availableWidth).height + 2
        }
        let atSourceSize = wrappedHeight(sourceFontSize)
        if atSourceSize <= maxHeight {
            return (sourceFontSize, max(minHeight, atSourceSize))
        }
        var lower = minimumFontSize
        var upper = sourceFontSize
        for _ in 0..<24 {
            let candidate = (lower + upper) / 2
            if wrappedHeight(candidate) <= maxHeight {
                lower = candidate
            } else {
                upper = candidate
            }
        }
        // Leaves room for fractional glyph/line-fragment rounding at draw
        // time, same safety margin the ported algorithm uses.
        let fontSize = max(minimumFontSize, lower * 0.97)
        return (fontSize, max(minHeight, min(maxHeight, wrappedHeight(fontSize))))
    }

    /// Draws a rounded, blurred crop of `blurredSource` behind where a chip
    /// will sit. Must run before the caller flips its context, above -
    /// image drawing only renders upright in the unflipped space. Window
    /// mode skips this entirely - no per-chip background there.
    private static func drawBlurredPatch(chipRect: CGRect, panelSize: CGSize,
                                         blurredSource: CGImage, in context: CGContext) {
        let cropRect = LiveTranslationSupport.blurCropRect(
            chipRect: chipRect, panelSize: panelSize, imageSize: panelSize, outset: chipPadding)
        guard cropRect.width > 0, cropRect.height > 0, let cropped = blurredSource.cropping(to: cropRect)
        else { return }
        // The clip path and the draw target must both be expressed in this
        // (still unflipped) context's own bottom-left-origin space - flip
        // the padded chip rect down from chipFrame's top-left convention
        // just for this draw.
        let bgRect = chipRect.insetBy(dx: -chipPadding, dy: -chipPadding)
        let unflippedRect = CGRect(x: bgRect.minX, y: panelSize.height - bgRect.maxY,
                                   width: bgRect.width, height: bgRect.height)
        context.saveGState()
        context.addPath(CGPath(roundedRect: unflippedRect, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.clip()
        context.draw(cropped, in: unflippedRect)
        context.restoreGState()
    }

    private static let averageColorContext = CIContext(options: [.cacheIntermediates: false])

    private static let chipBackgroundOpacity: CGFloat = 0.94
    private static let fallbackContrast = ChipContrast(backgroundColor: .black, textColor: .white)

    /// Samples the color of `image` in the margin *surrounding* `pixelRect`
    /// - already in `image`'s own pixel space and top-left origin, matching
    /// `CGImage.cropping(to:)`'s convention (callers not already operating in
    /// that space should convert first via `LiveTranslationSupport.
    /// blurCropRect`, the same conversion the blurred-patch crop itself
    /// uses, rather than duplicating it here). Deliberately *not* the
    /// interior of `pixelRect` itself: that box tightly bounds the original
    /// text's own glyphs, and averaging its interior blends the dark ink
    /// into the result - a box that's, say, 70% white background and 30%
    /// black text averages out to a muddy gray no matter how white the true
    /// page background actually is, which is exactly what made every chip
    /// look like the same flat gray regardless of what was really behind
    /// it. The surrounding margin - line-height padding above/below,
    /// letter-spacing gutters left/right - is reliably just background, so
    /// four thin strips just outside the box (averaged together via Core
    /// Image's CIAreaAverage filter, the standard way to get a region's
    /// average color without manually iterating pixels) are sampled instead
    /// of the box's own interior. `lineHeight` (a single row's height, not
    /// `pixelRect.height` itself) sizes those strips - for a multi-row
    /// paragraph, `pixelRect` spans the *whole block*, and sizing the outset
    /// off that full height reaches tens of pixels past the paragraph into
    /// a neighboring heading or the next paragraph, corrupting the sample
    /// with unrelated content; a strip sized to one line's height stays
    /// local to the paragraph's own true margin regardless of how many
    /// lines it spans. That sampled color becomes the chip's own background
    /// as-is (in-place mode only; window mode ignores it and draws no
    /// background at all), so the chip reads as part of the page rather
    /// than a stamped-on box; text color is whichever of black/white
    /// contrasts against that same sample. Shared with the live in-place
    /// overlay (LiveTranslationChipsView) so both pick the same contrast for
    /// the same content.
    static func chipContrast(behind pixelRect: CGRect, lineHeight: CGFloat, in image: CGImage) -> ChipContrast {
        let outsetY = max(4, lineHeight * 0.6)
        let outsetX = max(4, lineHeight * 0.3)
        let strips = [
            CGRect(x: pixelRect.minX - outsetX, y: pixelRect.minY - outsetY,
                  width: pixelRect.width + outsetX * 2, height: outsetY),
            CGRect(x: pixelRect.minX - outsetX, y: pixelRect.maxY,
                  width: pixelRect.width + outsetX * 2, height: outsetY),
            CGRect(x: pixelRect.minX - outsetX, y: pixelRect.minY, width: outsetX, height: pixelRect.height),
            CGRect(x: pixelRect.maxX, y: pixelRect.minY, width: outsetX, height: pixelRect.height),
        ]
        let samples = strips.compactMap { averageRGB(of: $0, in: image) }
        guard !samples.isEmpty else { return fallbackContrast }
        let count = CGFloat(samples.count)
        let red = samples.reduce(0) { $0 + $1.0 } / count
        let green = samples.reduce(0) { $0 + $1.1 } / count
        let blue = samples.reduce(0) { $0 + $1.2 } / count
        // ITU-R BT.601 perceptual luminance.
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        let backgroundColor = NSColor(srgbRed: red, green: green, blue: blue, alpha: chipBackgroundOpacity)
        return ChipContrast(backgroundColor: backgroundColor, textColor: luminance > 0.55 ? .black : .white)
    }

    /// One strip's average color, or nil if it falls entirely outside
    /// `image` (routine at a capture region's own edge, e.g. the leftmost
    /// item in a sidebar has no room for a left-side strip) - `chipContrast`
    /// simply averages whichever strips did land inside the image.
    private static func averageRGB(of pixelRect: CGRect, in image: CGImage) -> (CGFloat, CGFloat, CGFloat)? {
        let ciImage = CIImage(cgImage: image)
        let bottomLeftRect = CGRect(x: pixelRect.minX, y: CGFloat(image.height) - pixelRect.maxY,
                                    width: pixelRect.width, height: pixelRect.height)
        let sampleRect = bottomLeftRect.intersection(ciImage.extent)
        guard sampleRect.width > 0, sampleRect.height > 0,
              let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: sampleRect), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        averageColorContext.render(output, toBitmap: &pixel, rowBytes: 4,
                                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                   format: .RGBA8, colorSpace: nil)
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }

    private static func drawTint(chipRect: CGRect, contrast: ChipContrast, in context: CGContext) {
        let bgRect = chipRect.insetBy(dx: -chipPadding, dy: -chipPadding)
        context.saveGState()
        context.addPath(CGPath(roundedRect: bgRect, cornerWidth: 6, cornerHeight: 6, transform: nil))
        context.clip()
        context.setFillColor(contrast.backgroundColor.cgColor)
        context.fill(bgRect)
        context.restoreGState()
    }

    private static func drawText(_ text: String, chipRect: CGRect, fontSize: CGFloat,
                                 color: NSColor, in context: CGContext) {
        let drawRect = chipRect.insetBy(dx: 3, dy: 1)
        // Truncating-tail is a defensive last resort only - chipRect's
        // height was already sized to `wrappedTextSize`'s own measurement at
        // this exact font/width, so this in practice never engages.
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        (text as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: wrappedTextAttributes(fontSize: fontSize, color: color))
        NSGraphicsContext.current = previous
    }

    private static let minimumFontSize: CGFloat = 0.5

    private static func wrappedTextAttributes(fontSize: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: NSFont.systemFont(ofSize: max(minimumFontSize, fontSize), weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    }

    /// Shared with the live in-place overlay (LiveTranslationChipsView) so
    /// both compute the exact same wrapped size for the same text/font/
    /// width, keeping window mode and the live view visually consistent.
    static func wrappedTextSize(_ text: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGSize {
        guard !text.isEmpty else { return .zero }
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: max(minimumFontSize, maxWidth), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: wrappedTextAttributes(fontSize: fontSize, color: .black))
        return bounding.size
    }
}
