// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

// Assembles a folder of PNG frames into the animated GIF used by the release
// tour. Consecutive identical frames collapse into one longer beat, so a hold
// costs one frame instead of ten, and every frame is composited onto one
// canvas so a panel that grows and shrinks does not make the picture jump.
//
//   swift Tools/MakeGIF.swift <frames folder> <output.gif> [target width]

import AppKit
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: MakeGIF <frames> <output.gif> [width]\n".utf8))
    exit(2)
}
let framesURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let targetWidth = arguments.count > 3 ? (Double(arguments[3]) ?? 700) : 700

/// Every frame is on screen for this long; a hold is the same frame repeated,
/// which becomes one frame with a multiplied delay.
let frameSeconds = 0.16

let files = (try? FileManager.default.contentsOfDirectory(at: framesURL,
                                                          includingPropertiesForKeys: nil))?
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
guard !files.isEmpty else {
    FileHandle.standardError.write(Data("no frames in \(framesURL.path)\n".utf8))
    exit(1)
}

let images: [NSImage] = files.compactMap { NSImage(contentsOf: $0) }
let checksums: [Data] = files.map { (try? Data(contentsOf: $0)) ?? Data() }

// The canvas fits the tallest frame; the panel is anchored by its top edge,
// exactly where it stays on screen while its list grows and shrinks. A frame
// taller than the cap keeps its top and is cut at the bottom: a list that
// flashes past while a word is being typed must not decide the shape of the
// whole picture.
/// In points, the unit the frames carry: a panel taller than this is a list
/// flashing past mid-word, not a scene.
let maxPanelHeight: CGFloat = 300
let panelWidth = images.map(\.size.width).max() ?? 560
let panelHeight = min(images.map(\.size.height).max() ?? 400, maxPanelHeight)
let margin: CGFloat = 26
let canvasWidth = panelWidth + margin * 2
let canvasHeight = panelHeight + margin * 2
let scale = targetWidth / Double(canvasWidth)
let outputSize = NSSize(width: (canvasWidth * scale).rounded(),
                        height: (canvasHeight * scale).rounded())

func composite(_ panel: NSImage) -> CGImage? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: Int(outputSize.width),
                                     pixelsHigh: Int(outputSize.height),
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return nil }
    rep.size = outputSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // The app's own dark backdrop, so the panel reads as it does floating over
    // a desktop rather than as a screenshot on white.
    let gradient = NSGradient(colors: [NSColor(white: 0.10, alpha: 1),
                                       NSColor(white: 0.04, alpha: 1)])
    gradient?.draw(in: NSRect(origin: .zero, size: outputSize), angle: -60)

    let visibleHeight = min(panel.size.height, maxPanelHeight)
    let source = NSRect(x: 0,
                        y: panel.size.height - visibleHeight,
                        width: panel.size.width,
                        height: visibleHeight)
    let drawWidth = panel.size.width * scale
    let drawHeight = visibleHeight * scale
    // Centred rather than pinned to the top: a short answer would otherwise
    // sit above a wall of empty background.
    let rect = NSRect(x: (outputSize.width - drawWidth) / 2,
                      y: (outputSize.height - drawHeight) / 2,
                      width: drawWidth,
                      height: drawHeight)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
    shadow.shadowBlurRadius = 18 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -4 * scale)
    shadow.set()
    panel.draw(in: rect, from: source, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage
}

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL, UTType.gif.identifier as CFString, 0, nil) else {
    FileHandle.standardError.write(Data("cannot write \(outputURL.path)\n".utf8))
    exit(1)
}
CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
] as CFDictionary)

var written = 0
var index = 0
while index < images.count {
    var run = 1
    while index + run < images.count, checksums[index + run] == checksums[index] { run += 1 }
    if let frame = composite(images[index]) {
        CGImageDestinationAddImage(destination, frame, [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameSeconds * Double(run),
                kCGImagePropertyGIFUnclampedDelayTime: frameSeconds * Double(run),
            ],
        ] as CFDictionary)
        written += 1
    }
    index += run
}

guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("failed to finalize the gif\n".utf8))
    exit(1)
}
let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
print("wrote \(written) frames, \(Int(outputSize.width))x\(Int(outputSize.height)), \((bytes ?? 0) / 1024) KB")
