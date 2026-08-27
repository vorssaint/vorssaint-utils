// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// In-place mode's visual layer: one chip per translated paragraph group,
/// positioned directly over the source lines it replaces.
@available(macOS 15.0, *)
struct LiveTranslationChipsView: View {
    @ObservedObject var service: LiveTranslationService

    var body: some View {
        GeometryReader { proxy in
            // Lines already in the target language (original == translated,
            // LiveTranslationService's passthrough marker) need no chip here
            // at all - the real text is already showing through the
            // transparent panel underneath. They still matter for window
            // mode, which blurs everything and has no "underneath" to show.
            let blocks = service.lines.filter { $0.original != $0.translated }
            let baseFrames = blocks.map {
                LiveTranslationSupport.chipFrame(boundingBox: $0.boundingBox, panelSize: proxy.size)
            }
            let maxWidths = LiveTranslationSupport.maxChipWidths(
                frames: baseFrames, panelWidth: proxy.size.width, gap: 4)
            let maxHeights = LiveTranslationSupport.maxChipHeights(
                frames: baseFrames, panelHeight: proxy.size.height, gap: 4)

            ForEach(Array(blocks.indices), id: \.self) { index in
                chip(for: blocks[index], box: baseFrames[index], maxWidth: maxWidths[index],
                    maxHeight: maxHeights[index], panelSize: proxy.size)
            }
        }
    }

    /// A single-row item searches sideways first, into real whitespace to
    /// its right, before it ever wraps
    /// (LiveTranslationRenderer.chipSearchWidth, shared with window mode);
    /// a multi-row paragraph keeps its own width. Font size starts at
    /// `LiveTranslationSupport.blockFontSize` - "the actual size of the
    /// original text" - and only shrinks below that if the translation still
    /// doesn't fit even after growing the chip downward as far as
    /// `maxHeight` (LiveTranslationSupport.maxChipHeights' neighbor-aware
    /// cap) allows (LiveTranslationRenderer.fittedLayout, shared with window
    /// mode). The chip's *drawn* width shrink-wraps to the translation's
    /// actual measured width at that font
    /// (LiveTranslationRenderer.renderedChipWidth) rather than the wider
    /// search bound - using the search bound directly as the drawn width
    /// was a real bug, since a short translation's background would still
    /// paint out to the full bound, bleeding across whatever unrelated
    /// content sat further along (most visibly a sidebar chip's background
    /// running into the page's own right-hand content). The chip's
    /// background and text color both adapt to the real page content
    /// directly behind it (LiveTranslationRenderer.chipContrast, shared
    /// with window mode) - black text on a near-white background over a
    /// light patch of page, white text on a black background over a dark
    /// one.
    @ViewBuilder
    private func chip(for block: LiveTranslationSupport.TranslatedLine, box: CGRect,
                      maxWidth: CGFloat, maxHeight: CGFloat, panelSize: CGSize) -> some View {
        let sourceFontSize = LiveTranslationSupport.blockFontSize(chipHeight: box.height, rowCount: block.rowCount)
        let searchWidth = LiveTranslationRenderer.chipSearchWidth(
            box: box, rowCount: block.rowCount, maxWidth: maxWidth)
        let (fontSize, height) = LiveTranslationRenderer.fittedLayout(
            block.translated, sourceFontSize: sourceFontSize, width: searchWidth,
            minHeight: box.height, maxHeight: maxHeight)
        let width = LiveTranslationRenderer.renderedChipWidth(
            text: block.translated, fontSize: fontSize, box: box,
            rowCount: block.rowCount, searchWidth: searchWidth)
        let chipRect = CGRect(x: box.minX, y: box.minY, width: width, height: height)
        let contrast: LiveTranslationRenderer.ChipContrast = service.lastCapturedImage.map { crisp in
            // `chipRect` is in the SwiftUI panel's own point space, not the
            // captured image's pixel space (which differs by the display's
            // scale factor) - convert via the same scaling
            // LiveTranslationSupport.blurCropRect already uses for the
            // background crop below, rather than sampling the wrong region.
            // Sampled from the crisp, unblurred capture, not
            // `blurredCapturedImage`: that blur's radius scales with the
            // *whole capture region's* size, so on a large full-page capture
            // it's tens of pixels wide - easily wider than a chip itself -
            // and washes every chip's sample toward the page's overall
            // average color instead of what's actually behind that one chip.
            let pixelRect = LiveTranslationSupport.blurCropRect(
                chipRect: chipRect, panelSize: panelSize,
                imageSize: CGSize(width: crisp.width, height: crisp.height), outset: 0)
            return LiveTranslationRenderer.chipContrast(
                behind: pixelRect, lineHeight: pixelRect.height / CGFloat(max(1, block.rowCount)), in: crisp)
        } ?? LiveTranslationRenderer.ChipContrast(backgroundColor: .black, textColor: .white)

        ZStack {
            chipBackground(for: chipRect, panelSize: panelSize, contrast: contrast)
            FittedChipText(text: block.translated, fontSize: fontSize, color: contrast.textColor)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
        }
        .frame(width: width + 8, height: height + 4)
        .position(x: chipRect.midX, y: chipRect.midY)
    }

    /// A blurred crop of the real content behind this chip, tinted to match
    /// `contrast` - not a flat box - so the chip reads as sitting over the
    /// page rather than stamped onto it. Falls back to just the flat tint if
    /// no capture has landed yet or the crop comes back empty at the panel's
    /// own edges.
    @ViewBuilder
    private func chipBackground(for rect: CGRect, panelSize: CGSize,
                                contrast: LiveTranslationRenderer.ChipContrast) -> some View {
        ZStack {
            if let blurred = service.blurredCapturedImage {
                let cropRect = LiveTranslationSupport.blurCropRect(
                    chipRect: rect, panelSize: panelSize,
                    imageSize: CGSize(width: blurred.width, height: blurred.height), outset: 3)
                if cropRect.width > 0, cropRect.height > 0, let cropped = blurred.cropping(to: cropRect) {
                    Image(decorative: cropped, scale: 1, orientation: .up)
                        .resizable()
                }
            }
            Color(nsColor: contrast.backgroundColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Draws with the exact AppKit attributes `LiveTranslationRenderer.
/// wrappedTextSize` measures with, avoiding a second, independent SwiftUI
/// layout pass that could pick a different wrap point and clip the last
/// words in a tightly fitted box - the reason this isn't a plain SwiftUI
/// `Text`.
@available(macOS 15.0, *)
private struct FittedChipText: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let color: NSColor

    func makeNSView(context: Context) -> FittedChipTextView { FittedChipTextView() }

    func updateNSView(_ view: FittedChipTextView, context: Context) {
        view.update(text: text, fontSize: fontSize, color: color)
    }
}

private final class FittedChipTextView: NSView {
    override var isFlipped: Bool { true }

    private var text = ""
    private var fontSize: CGFloat = 1
    private var color: NSColor = .white

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(0.5, fontSize), weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        (text as NSString).draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: attributes)
    }

    func update(text: String, fontSize: CGFloat, color: NSColor) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
        needsDisplay = true
    }
}
