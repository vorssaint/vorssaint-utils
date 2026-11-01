// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum RecorderGIFWriterTests {
    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-gif-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try animation(suite, folder: folder)
            try chunkBoundaries(suite, folder: folder)
            try compactness(suite, folder: folder)
            try workspaces(suite, root: folder.appendingPathComponent("scratch", isDirectory: true))
        } catch {
            suite.expect(false, "streaming GIF fixture failed: \(error)")
        }
        let owner = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        suite.expect(RecorderGIFWorkspace.root.deletingLastPathComponent().lastPathComponent == owner,
                     "GIF scratch belongs to the running app or test process, never another's folder")
    }

    private static func animation(_ suite: TestSuite, folder: URL) throws {
        // Different palettes and alpha ensure concatenation does not reuse the
        // previous chunk's color table or show its pixels through transparency.
        // 450 frames cross the 300-frame chunk boundary.
        let pictures = [picture(red: 1, green: 0, transparent: false),
                        picture(red: 0, green: 1, transparent: true)]
        let expectedPixels = try pictures.map(decodedAlone)
        for fps in [8, 12, 15] {
            let url = folder.appendingPathComponent("\(fps).gif")
            let writer = try RecorderGIFWriter(url: url, fps: fps)
            for index in 0..<450 { try writer.append(pictures[index % 2]) }
            try writer.finish()
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                suite.expect(false, "streamed animation decodes at \(fps) fps")
                continue
            }
            suite.expect(CGImageSourceGetCount(source) == 450,
                         "all 450 frames survive streaming at \(fps) fps")
            let properties = CGImageSourceCopyProperties(source, nil) as NSDictionary?
            let gif = properties?[kCGImagePropertyGIFDictionary] as? NSDictionary
            suite.expect((gif?[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue == 0,
                         "streamed animation loops indefinitely")
            var duration = 0.0
            var decoded = 0
            var coloursCorrect = true
            for index in 0..<CGImageSourceGetCount(source) {
                autoreleasepool {
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?
                    let gif = properties?[kCGImagePropertyGIFDictionary] as? NSDictionary
                    duration += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? 0
                    guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return }
                    decoded += 1
                    let pixels = rgba(image)
                    coloursCorrect = coloursCorrect && pixels == expectedPixels[index % 2]
                    if index % 2 == 1 { coloursCorrect = coloursCorrect && pixels[3] == 0 }
                }
            }
            suite.expect(decoded == 450 && coloursCorrect,
                         "every chunk keeps its own palette and clears preceding transparent pixels")
            suite.expectClose(duration, 450.0 / Double(fps),
                              "centisecond delays preserve the whole timeline at \(fps) fps", tol: 0.0051)
            do {
                try writer.append(pictures[0])
                suite.expect(false, "finished GIF writer rejects new frames")
            } catch { suite.expect(true, "finished GIF writer rejects new frames") }
        }

        let data = try encodedTogether(pictures)
        suite.expect((try? RecorderGIFWriter.chunk(from: data))?.frames.count == 2,
                     "a native multi-image GIF parses into its frames")
        // Exercise every truncation boundary, not just a bad magic signature.
        var rejected = 0
        for count in 0..<data.count {
            if (try? RecorderGIFWriter.chunk(from: Data(data.prefix(count)))) == nil { rejected += 1 }
        }
        suite.expect(rejected == data.count, "truncated native GIF blocks are rejected safely")
        let mismatch = try RecorderGIFWriter(url: folder.appendingPathComponent("mismatch.gif"), fps: 12)
        try mismatch.append(pictures[0])
        do {
            try mismatch.append(picture(red: 1, green: 0, transparent: false, width: 16))
            suite.expect(false, "changing frame dimensions fails instead of corrupting the canvas")
        } catch { suite.expect(true, "changing frame dimensions fails instead of corrupting the canvas") }
        let empty = try RecorderGIFWriter(url: folder.appendingPathComponent("empty.gif"), fps: 12)
        do {
            try empty.finish()
            suite.expect(false, "an empty GIF cannot be finalized")
        } catch { suite.expect(true, "an empty GIF cannot be finalized") }
    }

    /// Chunks of three put a boundary before each transparent picture and
    /// before opaque pictures that follow a transparent chunk. Every decoded
    /// frame must match the picture encoded alone: an opaque frame from the
    /// chunk before must never show through a transparent opening picture.
    private static func chunkBoundaries(_ suite: TestSuite, folder: URL) throws {
        let transparent = picture(red: 0, green: 1, transparent: true)
        var square = 0
        let sequence = "OOOTOOOTOOOO".map { kind -> CGImage in
            guard kind == "O" else { return transparent }
            square += 1
            return picture(square: square)
        }
        let expected = try sequence.map(decodedAlone)
        let url = folder.appendingPathComponent("boundaries.gif")
        let writer = try RecorderGIFWriter(url: url, fps: 12, framesPerChunk: 3)
        for image in sequence { try writer.append(image) }
        try writer.finish()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == sequence.count else {
            suite.expect(false, "chunked animation keeps every frame")
            return
        }
        var mismatched: [Int] = []
        for index in 0..<sequence.count {
            let image = CGImageSourceCreateImageAtIndex(source, index, nil)
            if image.map(rgba) != expected[index] { mismatched.append(index) }
        }
        suite.expect(mismatched.isEmpty,
                     "chunk boundaries never let an earlier frame show through \(mismatched)")
    }

    /// A still picture with a small moving square: the old single
    /// destination stores one full picture and tiny changed rectangles.
    private static func compactness(_ suite: TestSuite, folder: URL) throws {
        let frames = (0..<40).map { still(square: $0) }
        let reference = try encodedTogether(frames).count
        let url = folder.appendingPathComponent("still.gif")
        let writer = try RecorderGIFWriter(url: url, fps: 12)
        for image in frames { try writer.append(image) }
        try writer.finish()
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? .max
        // One chunk is the old encoder's own output: the signature and the
        // delays are rewritten in place, so the size may only differ by a few
        // header bytes. Encoding every frame alone made this clip ~25x larger.
        suite.expect(size <= reference + 16,
                     "a GIF within one chunk stays as compact as the single encoder (\(size) vs \(reference))")

        // Past a chunk, the extra cost is bounded: each later chunk opens on a
        // full picture, and each of its frames may carry a 256-color palette.
        let chunked = folder.appendingPathComponent("still-chunked.gif")
        let small = try RecorderGIFWriter(url: chunked, fps: 12, framesPerChunk: 8)
        for image in frames { try small.append(image) }
        try small.finish()
        let chunkedSize = (try FileManager.default.attributesOfItem(
            atPath: chunked.path)[.size] as? NSNumber)?.intValue ?? .max
        let fullPicture = try encodedTogether([frames[0]]).count
        suite.expect(chunkedSize <= reference + 4 * (fullPicture + 8 * 768),
                     "later chunks add at most a full picture and local palettes (\(chunkedSize) vs \(reference))")
        let decoded = CGImageSourceCreateWithURL(chunked as CFURL, nil).map(CGImageSourceGetCount)
        suite.expect(decoded == frames.count, "a chunked still clip keeps every frame")
    }

    private static func workspaces(_ suite: TestSuite, root: URL) throws {
        let manager = FileManager.default
        let first = try RecorderGIFWorkspace(root: root)
        try Data("partial animation".utf8).write(to: first.fileURL)
        let second = try RecorderGIFWorkspace(root: root)
        RecorderGIFWorkspace.sweep(root: root)
        suite.expect(manager.fileExists(atPath: first.fileURL.path)
                && manager.fileExists(atPath: second.folder.path),
                     "new exports and sweeping preserve every live export lease")

        // A crashed process releases its lock even though the file stays.
        let orphan = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: orphan, withIntermediateDirectories: false)
        let lease = Darwin.open(orphan.appendingPathComponent(".lease").path, O_CREAT | O_RDWR, 0o600)
        guard lease >= 0 else { throw CocoaError(.fileWriteUnknown) }
        guard flock(lease, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lease)
            throw CocoaError(.fileWriteUnknown)
        }
        try Data("crash remainder".utf8).write(to: orphan.appendingPathComponent("animation.gif"))
        RecorderGIFWorkspace.sweep(root: root)
        suite.expect(manager.fileExists(atPath: orphan.path), "an external live lease is retained")
        Darwin.close(lease)
        RecorderGIFWorkspace.sweep(root: root)
        suite.expect(!manager.fileExists(atPath: orphan.path),
                     "released crash scratch is swept immediately without an age threshold")

        // A crash between mkdir and acquiring the lease is also recoverable.
        let unfinished = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: unfinished, withIntermediateDirectories: false)
        let unrelated = root.appendingPathComponent("unrelated", isDirectory: true)
        try manager.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let link = root.appendingPathComponent(UUID().uuidString)
        try manager.createSymbolicLink(at: link, withDestinationURL: unrelated)
        RecorderGIFWorkspace.sweep(root: root)
        suite.expect(!manager.fileExists(atPath: unfinished.path)
                && manager.fileExists(atPath: unrelated.path) && manager.fileExists(atPath: link.path),
                     "sweep removes only export folders and never follows symlinks")
        first.discard()
        first.discard()
        second.discard()
        suite.expect(!manager.fileExists(atPath: first.folder.path)
                && !manager.fileExists(atPath: second.folder.path),
                     "export completion removes its scratch immediately and idempotently")
    }

    private static func picture(red: CGFloat, green: CGFloat, transparent: Bool, width: Int = 32) -> CGImage {
        let context = CGContext(data: nil, width: width, height: 32, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: green, blue: 0, alpha: 1))
        let x = transparent ? width / 2 : 0
        context.fill(CGRect(x: x, y: 0, width: width - x, height: 32))
        return context.makeImage()!
    }

    /// Blue with a red square moved along the diagonal; only pure colors, so
    /// any palette reproduces it exactly.
    private static func picture(square: Int) -> CGImage {
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                                bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: square * 2, y: square * 2, width: 6, height: 6))
        return context.makeImage()!
    }

    /// A gradient that needs a full palette, with a small yellow square.
    private static func still(square: Int) -> CGImage {
        let context = CGContext(data: nil, width: 96, height: 64, bitsPerComponent: 8,
                                bytesPerRow: 96 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in stride(from: 0, to: 96, by: 2) {
            let shade = CGFloat(x) / 96
            context.setFillColor(CGColor(red: shade, green: 0.3, blue: 1 - shade, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 2, height: 64))
        }
        for y in stride(from: 0, to: 64, by: 4) {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat(y) / 128))
            context.fill(CGRect(x: 0, y: y, width: 96, height: 1))
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 4 + square, y: 20, width: 6, height: 6))
        return context.makeImage()!
    }

    /// The previous exporter: every frame through one ImageIO destination.
    private static func encodedTogether(_ images: [CGImage]) throws -> Data {
        let data = NSMutableData()
        guard let sink = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.gif.identifier as CFString, images.count, nil) else {
            throw RecorderGIFWriter.Failure.invalidFrame
        }
        CGImageDestinationSetProperties(sink, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let delay = 1.0 / 12
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ],
        ] as CFDictionary
        for image in images { CGImageDestinationAddImage(sink, image, frameProperties) }
        guard CGImageDestinationFinalize(sink) else { throw RecorderGIFWriter.Failure.invalidFrame }
        return data as Data
    }

    private static func decodedAlone(_ image: CGImage) throws -> [UInt8] {
        let data = try encodedTogether([image])
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RecorderGIFWriter.Failure.invalidFrame
        }
        return rgba(decoded)
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
