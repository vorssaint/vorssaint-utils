// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO
import WebP

private enum EncoderFailure: Error {
    case invalidArguments
    case unreadableImage
    case pixelBuffer
    case encoding
}

private func rgbaPixels(from image: CGImage) throws -> [UInt8] {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    guard let context = CGContext(data: &pixels,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)
                                    ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                                    | CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw EncoderFailure.pixelBuffer
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Quartz provides premultiplied RGBA. libwebp expects straight RGBA.
    for offset in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = Int(pixels[offset + 3])
        guard alpha > 0, alpha < 255 else { continue }
        for channel in 0..<3 {
            pixels[offset + channel] = UInt8(min(255, Int(pixels[offset + channel]) * 255 / alpha))
        }
    }
    return pixels
}

do {
    guard CommandLine.arguments.count == 4,
          let quality = Float(CommandLine.arguments[3]), quality.isFinite else {
        throw EncoderFailure.invalidArguments
    }
    let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw EncoderFailure.unreadableImage
    }
    let pixels = try rgbaPixels(from: image)
    var encoded: UnsafeMutablePointer<UInt8>?
    let encodedSize = WebPEncodeRGBA(pixels,
                                     Int32(image.width),
                                     Int32(image.height),
                                     Int32(image.width * 4),
                                     min(100, max(0, quality)),
                                     &encoded)
    guard let encoded, encodedSize > 0 else { throw EncoderFailure.encoding }
    defer { WebPFree(encoded) }
    try Data(bytes: encoded, count: encodedSize).write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("WebP encoding failed: \(error)\n".utf8))
    exit(1)
}
