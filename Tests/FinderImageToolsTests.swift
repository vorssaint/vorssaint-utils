// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum FinderImageToolsTests {
    static func run(_ suite: TestSuite) {
        suite.run("Finder image tools") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: root) }
                let context = CGContext(data: nil, width: 2, height: 3, bitsPerComponent: 8, bytesPerRow: 8,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
                context.fill(CGRect(x: 0, y: 0, width: 1, height: 3))
                let image = context.makeImage()!
                let rotated = try FinderImageTools.rotate(image)
                suite.expect(rotated.width == 3 && rotated.height == 2, "quarter-turn rotates image dimensions")
                let token = FinderToolsCancellation()
                let horizontal = try FinderImageTools.stitch([image, image], horizontal: true, cancellation: token)
                let vertical = try FinderImageTools.stitch([image, image], horizontal: false, cancellation: token)
                suite.expect(horizontal.width == 4 && horizontal.height == 3 && vertical.width == 2 && vertical.height == 6,
                             "stitching preserves all input pixels in either direction")
                let recolored = try FinderImageTools.recolor(image, red: 0, green: 1, blue: 0)
                let bitmap = NSBitmapImageRep(cgImage: recolored)
                let color = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB)
                suite.expect((color?.greenComponent ?? 0) > 0.9 && (color?.redComponent ?? 1) < 0.1,
                             "recolor changes RGB to the requested color")
                suite.expectClose(Double(color?.alphaComponent ?? 0), 0.5, "recolor preserves alpha", tol: 0.01)
                let file = try FinderImageTools.savePNG(recolored, in: root, named: "result", cancellation: token)
                let decoded = try FinderImageTools.load(file)
                suite.expect(decoded.width == 2 && decoded.height == 3, "PNG export is readable with its original dimensions")
                token.cancel()
                do {
                    _ = try FinderImageTools.savePNG(image, in: root, named: "cancelled", cancellation: token)
                    suite.expect(false, "cancelled export should fail")
                } catch is CancellationError {
                    suite.expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("cancelled.png").path),
                                 "cancelled export creates no output file")
                }
            } catch { suite.expect(false, "image fixture failed: \(error)") }
        }
    }
}
