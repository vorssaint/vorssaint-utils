// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The pointer image for one look, drawn once per setting change rather than
/// on every frame: one of the bundled pictures with a soft shadow under it,
/// or the ring, drawn here in the chosen color with a dark outline and a
/// highlight so it reads on any background.
struct PresentationPointerArtwork {
    let image: CGImage
    /// Size in points.
    let size: CGSize
    /// The point the pointer clicks with, in points from the image's top-left.
    let hotSpot: CGPoint
    /// The chosen color, which the ring and the bursts are drawn in.
    let color: NSColor
    /// The outline that keeps the ring and the bursts readable.
    let outlineColor: NSColor
    /// The setting the image was drawn at, in points.
    let pointerSize: CGFloat

    /// Reads a style's bundled picture. Injectable so tests can read the
    /// pictures from the repository instead of an app bundle.
    typealias PictureLoader = (PresentationPointerStyle) -> CGImage?

    /// Decoded once each and kept; the four pictures are small.
    private static var decodedPictures: [PresentationPointerStyle: CGImage] = [:]

    static let bundledPicture: PictureLoader = { style in
        if let decoded = decodedPictures[style] { return decoded }
        guard let name = style.pictureResource,
              let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Images"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        decodedPictures[style] = image
        return image
    }

    static func make(style: PresentationPointerStyle, color: NSColor, pointerSize: CGFloat, scale: CGFloat,
                     picture: PictureLoader = bundledPicture) -> PresentationPointerArtwork? {
        guard pointerSize > 0, scale > 0 else { return nil }
        let color = color.usingColorSpace(.sRGB) ?? .systemYellow
        let outlineColor = outline(for: color)
        let shadowBlur = pointerSize * 0.07
        let shadowOffset = pointerSize * 0.035
        let padding = ceil(shadowBlur + shadowOffset) + 1
        let side = pointerSize
        let size = CGSize(width: ceil(side + padding * 2), height: ceil(side + padding * 2))
        let pixelWidth = Int((size.width * scale).rounded(.up))
        let pixelHeight = Int((size.height * scale).rounded(.up))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high
        context.setShadow(offset: CGSize(width: 0, height: -shadowOffset), blur: shadowBlur,
                          color: NSColor.black.withAlphaComponent(0.3).cgColor)
        // The square the figure fills. It sits as far from the top as from
        // the bottom, so the hot spot below can be measured from the top.
        let square = CGRect(x: padding, y: padding, width: side, height: side)

        let hotSpot: CGPoint
        if let tip = style.pictureTip {
            guard let source = picture(style) else { return nil }
            context.draw(source, in: square)
            let unit = side / CGFloat(max(source.height, 1))
            hotSpot = CGPoint(x: padding + tip.x * unit, y: padding + tip.y * unit)
        } else {
            drawRing(in: square, color: color, outline: outlineColor, context: context)
            hotSpot = CGPoint(x: square.midX, y: square.midY)
        }

        guard let image = context.makeImage() else { return nil }
        return PresentationPointerArtwork(image: image, size: size, hotSpot: hotSpot, color: color,
                                          outlineColor: outlineColor, pointerSize: pointerSize)
    }

    /// A thick band in the chosen color, inked inside and out, lit along its
    /// upper left and shaded along its lower right.
    private static func drawRing(in square: CGRect, color: NSColor, outline: NSColor, context: CGContext) {
        let unit = square.width / 100
        let ink = 3.5 * unit
        let band = CGPath(ellipseIn: square.insetBy(dx: 9 * unit + ink, dy: 9 * unit + ink), transform: nil)
            .copy(strokingWithWidth: 18 * unit, lineCap: .round, lineJoin: .round, miterLimit: 1)
        let cool = NSColor(srgbRed: 0.18, green: 0.24, blue: 0.40, alpha: 1)
        let shade = color.blended(withFraction: 0.2, of: cool) ?? color

        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.addPath(band)
        context.setStrokeColor(outline.cgColor)
        context.setLineWidth(ink * 2)
        context.strokePath()
        context.saveGState()
        context.addPath(band)
        context.clip()
        context.setFillColor(shade.cgColor)
        context.fill(square)
        // Light from the top left: the color, nudged that way, leaves the
        // shade showing along the lower right edge.
        var lit = CGAffineTransform(translationX: -2.8 * unit, y: 2.8 * unit)
        if let litBand = band.copy(using: &lit) {
            context.addPath(litBand)
            context.setFillColor(color.cgColor)
            context.fillPath()
        }
        let shine = CGMutablePath()
        shine.addArc(center: CGPoint(x: square.midX, y: square.midY), radius: square.width * 0.36,
                     startAngle: .pi * 0.62, endAngle: .pi * 0.86, clockwise: false)
        context.addPath(shine)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.75).cgColor)
        context.setLineWidth(3.6 * unit)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()
        context.endTransparencyLayer()
    }

    /// Dark ink for light colors and light ink for very dark ones, judged by
    /// relative luminance.
    static func outline(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return PresentationPointerSupport.relativeLuminance(red: rgb.redComponent, green: rgb.greenComponent,
                                                            blue: rgb.blueComponent) > 0.22
            ? NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1)
            : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1)
    }
}
