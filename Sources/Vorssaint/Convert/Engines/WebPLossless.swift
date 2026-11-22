// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import Foundation
import CoreGraphics

/// Minimal literal-only VP8L writer. Fallback when ImageIO/FFmpeg cannot encode WebP.
/// Writes 8-bit sRGB pixels (premultiplication may round colors); intentionally trades compression ratio for no dependencies.
/// Format: https://developers.google.com/speed/webp/docs/webp_lossless_bitstream_specification
enum WebPLossless {
    private struct Bits {
        var data = Data()
        var pending: UInt64 = 0
        var count = 0
        mutating func put(_ value: Int, _ width: Int) {
            pending |= UInt64(value) << count
            count += width
            while count >= 8 {
                data.append(UInt8(pending & 255)); pending >>= 8; count -= 8
            }
        }
        mutating func finish() { if count > 0 { data.append(UInt8(pending & 255)); count = 0 } }
        mutating func literalTree(_ alphabet: Int) {
            put(0, 1); put(8, 4) // normal tree, twelve code-length symbols
            for symbol in [17,18,0,1,2,3,4,5,16,6,7,8] { put(symbol == 0 || symbol == 8 ? 1 : 0, 3) }
            put(0, 1) // full alphabet
            for index in 0..<alphabet { put(index < 256 ? 1 : 0, 1) }
        }
    }
    static func write(_ image: CGImage, to url: URL) throws {
        let w = image.width, h = image.height
        guard w > 0, h > 0, w <= 16384, h <= 16384, w * h <= 40_000_000 else {
            throw OpenTangerineError.invalidInput("WebP requires dimensions up to 16,384 pixels and at most 40 megapixels.")
        }
        guard w * h * 4 + 180 <= 100_000_000 else {
            throw OpenTangerineError.invalidInput("This image needs a compressed WebP encoder to stay within the 100 MB file limit. Use an FFmpeg build with libwebp, or resize the image below 25 megapixels.")
        }
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            let memory = context.data else { throw OpenTangerineError.encodeFailed("WebP pixel buffer") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = memory.assumingMemoryBound(to: UInt8.self)
        var bits = Bits()
        bits.data.reserveCapacity(w * h * 4 + 180)
        bits.put(0x2f, 8); bits.put(w - 1, 14); bits.put(h - 1, 14); bits.put(1, 1); bits.put(0, 3)
        bits.put(0, 1); bits.put(0, 1); bits.put(0, 1) // no transform, cache, or meta image
        bits.literalTree(280)
        for _ in 0..<3 { bits.literalTree(256) }
        bits.put(1, 1); bits.put(0, 1); bits.put(0, 1); bits.put(0, 1) // single distance symbol
        let reversed = (0..<256).map { value -> Int in
            var n = value, r = 0
            for _ in 0..<8 { r = (r << 1) | (n & 1); n >>= 1 }
            return r
        }
        for i in 0..<(w * h) {
            if i % 4096 == 0 { try Task.checkCancellation() }
            let alpha = Int(pixels[i * 4 + 3])
            for channel in [1, 0, 2] {
                let value = alpha == 0 ? 0 : min(255, (Int(pixels[i * 4 + channel]) * 255 + alpha / 2) / alpha)
                bits.put(reversed[value], 8)
            }
            bits.put(reversed[alpha], 8)
        }
        bits.finish()
        var result = Data("RIFF".utf8)
        func append32(_ n: Int) { for shift in stride(from: 0, to: 32, by: 8) { result.append(UInt8((n >> shift) & 255)) } }
        append32(12 + bits.data.count + (bits.data.count & 1))
        result.append(Data("WEBPVP8L".utf8)); append32(bits.data.count); result.append(bits.data)
        if bits.data.count & 1 != 0 { result.append(0) }
        try result.write(to: url, options: .atomic)
    }
}
