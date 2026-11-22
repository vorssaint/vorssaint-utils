// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The dominant colours of a cover, by k-means on a 48-pixel copy. Pure and
/// deterministic: the same cover always gives the same palette, most
/// prominent colour first, each lifted into a range that glows on a dark veil.
enum ArtworkPalette {
    static func colors(from data: Data, count: Int = 4) -> [NSColor] {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 48] as CFDictionary) else { return [] }
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return [] }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [] }

        var points: [SIMD3<Double>] = []
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 128 {
            points.append(SIMD3(Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2])) / 255)
        }
        guard !points.isEmpty else { return [] }
        let clusters = kMeans(points, k: min(count, points.count))
        return clusters.sorted { $0.size > $1.size }.map { lifted($0.center) }
    }

    private static func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return d.x * d.x + d.y * d.y + d.z * d.z
    }

    private static func kMeans(_ points: [SIMD3<Double>], k: Int) -> [(center: SIMD3<Double>, size: Int)] {
        // Farthest-point seeding keeps it deterministic and spreads the centres.
        var centers = [points.reduce(SIMD3<Double>.zero, +) / Double(points.count)]
        while centers.count < k {
            guard let next = points.max(by: { a, b in
                (centers.map { distance(a, $0) }.min() ?? 0) < (centers.map { distance(b, $0) }.min() ?? 0)
            }) else { break }
            centers.append(next)
        }
        var sizes = [Int](repeating: 0, count: centers.count)
        for _ in 0..<10 {
            var sums = [SIMD3<Double>](repeating: .zero, count: centers.count)
            sizes = [Int](repeating: 0, count: centers.count)
            for point in points {
                var best = 0, bestDistance = Double.infinity
                for (index, center) in centers.enumerated() {
                    let d = distance(point, center)
                    if d < bestDistance { bestDistance = d; best = index }
                }
                sums[best] += point
                sizes[best] += 1
            }
            for index in centers.indices where sizes[index] > 0 { centers[index] = sums[index] / Double(sizes[index]) }
        }
        return zip(centers, sizes).map { (center: $0, size: $1) }
    }

    /// Brightness and saturation brought into a band where a colour still
    /// reads as itself but is neither black nor washed out on a dark veil.
    private static func lifted(_ rgb: SIMD3<Double>) -> NSColor {
        let base = NSColor(srgbRed: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return NSColor(hue: hue, saturation: min(1, max(saturation, 0.12) * 1.15),
                       brightness: min(0.95, max(brightness, 0.45)), alpha: 1)
    }
}
