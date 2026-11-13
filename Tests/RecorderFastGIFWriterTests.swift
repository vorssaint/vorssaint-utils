// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreImage
import Foundation
import ImageIO
import Metal
import RecorderGIFCodec

enum RecorderFastGIFWriterTests {
    static func run(_ suite: TestSuite) {
        do { try probe(suite) }
        catch { suite.expect(false, "fast GIF fixture failed \(error)") }
    }

    private static func probe(_ suite: TestSuite) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fast-gif-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func encode(_ pixels: [UInt8], previous: [UInt8] = [], width: UInt32 = 2,
                    height: UInt32 = 2, colors: [UInt8] = [0, 0, 0, 255, 255, 255]) -> Data? {
            pixels.withUnsafeBufferPointer { current in
                previous.withUnsafeBufferPointer { old in
                    colors.withUnsafeBufferPointer { table in
                        var count = 99
                        guard let data = RecorderGIFCodecEncode(current.baseAddress,
                            previous.isEmpty ? nil : old.baseAddress, pixels.count, width, height,
                            table.baseAddress, table.count, &count) else { return nil }
                        return Data(bytesNoCopy: data, count: count, deallocator: .free)
                    }
                }
            }
        }
        suite.expect(encode([0], width: 0, height: 0) == nil
                && encode([0], width: UInt32.max, height: UInt32.max) == nil
                && encode([0], width: 65536, height: 1) == nil
                && encode([0], width: 2, height: 2) == nil,
                     "indexed GIF rejects invalid dimensions and truncated pixel buffers")
        suite.expect(encode([0, 1, 1, 0], colors: [0, 0, 0, 255]) == nil
                && encode([0, 1, 9, 0]) == nil && encode([0, 1, 255, 0]) == nil,
                     "indexed GIF rejects malformed palettes and reserved pixel indices")
        if let small = encode([0, 1, 1, 0]),
           let full = encode([0, 254, 254, 0], colors: Array(repeating: 0, count: 255 * 3)) {
            let smallChunk = try RecorderGIFWriter.chunk(from: small)
            let fullChunk = try RecorderGIFWriter.chunk(from: full)
            suite.expect(smallChunk.globalTable?.count == 4 * 3
                    && smallChunk.frames.first?.transparentIndex == 3
                    && smallChunk.frames.first?.pixels.first == 2,
                         "a two-color animation needs only four table entries and a two-bit LZW minimum")
            suite.expect(fullChunk.globalTable?.count == 256 * 3
                    && fullChunk.frames.first?.transparentIndex == 255,
                         "all 255 opaque indices remain available in a full GIF table")
        } else { suite.expect(false, "small and full GIF palettes both encode") }
        let indexedURL = folder.appendingPathComponent("indexed.gif")
        let indexed = try RecorderGIFWriter(url: indexedURL, fps: 12)
        var last: [UInt8] = []
        for pixels in [[UInt8(0), 1, 1, 0], [0, 1, 1, 0], [0, 0, 0, 0]] {
            guard let data = encode(pixels, previous: last) else {
                suite.expect(false, "indexed GIF frame encodes")
                return
            }
            try indexed.appendEncodedFrames([RecorderGIFWriter.chunk(from: data)])
            last = pixels
        }
        try indexed.finish()
        if let source = CGImageSourceCreateWithURL(indexedURL as CFURL, nil) {
            suite.expect(CGImageSourceGetCount(source) == 3,
                         "an identical indexed frame retains its animation delay")
            if let final = CGImageSourceCreateImageAtIndex(source, 2, nil) {
                suite.expect(rgba(CIImage(cgImage: final), width: 2, height: 2)
                    == [0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255],
                    "delta transparency clears changed white pixels without losing the canvas")
            } else { suite.expect(false, "indexed final frame decodes") }
        } else { suite.expect(false, "indexed animation decodes") }

        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let url = folder.appendingPathComponent("gpu.gif")
        let sink = try RecorderGIFWriter(url: url, fps: 12)
        guard let fast = RecorderFastGIFWriter(writer: sink, size: CGSize(width: 64, height: 32),
                                               isCancelled: { false }) else {
            suite.expect(false, "fast GIF resources initialize on a Metal device")
            return
        }
        let rect = CGRect(x: 0, y: 0, width: 64, height: 32)
        let background = CIImage(color: .black).cropped(to: rect)
        var reference: [[UInt8]] = []
        // Repeated pictures and small moving regions span three batches.
        for index in 0..<41 {
            let position = index / 2 % 7 * 8
            let sprite = CIImage(color: index < 23 ? .red : .green)
                .cropped(to: CGRect(x: position, y: 8, width: 8, height: 8))
            let image = sprite.composited(over: background)
            reference.append(rgba(image, width: 64, height: 32))
            try fast.append(image, sourceBytes: 0)
        }
        try fast.finish()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            suite.expect(false, "GPU GIF decodes")
            return
        }
        suite.expect(CGImageSourceGetCount(source) == reference.count,
                     "all GPU frames survive batch boundaries and partial final batches")
        var matches = 0
        var duration = 0.0
        for index in reference.indices {
            if let frame = CGImageSourceCreateImageAtIndex(source, index, nil),
               rgba(CIImage(cgImage: frame), width: 64, height: 32) == reference[index] { matches += 1 }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?
            let gif = properties?[kCGImagePropertyGIFDictionary] as? NSDictionary
            duration += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? 0
        }
        suite.expect(matches == reference.count,
                     "GPU orientation, frame order and unchanged regions match every source picture (\(matches))")
        suite.expectClose(duration, 3.42, "GPU frames retain the cumulative 12 fps clock", tol: 0.001)
        let alphaSink = try RecorderGIFWriter(url: folder.appendingPathComponent("alpha.gif"), fps: 12)
        guard let alpha = RecorderFastGIFWriter(writer: alphaSink, size: rect.size,
                                                isCancelled: { false }) else { return }
        try alpha.append(CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 0.5)).cropped(to: rect),
                         sourceBytes: 0)
        do {
            try alpha.finish()
            suite.expect(false, "transparent pixels must request the existing encoder")
        } catch RecorderFastGIFWriter.Failure.unavailable {
            suite.expect(true, "transparent pixels request the existing encoder")
        }
        let cancelled = try RecorderGIFWriter(url: folder.appendingPathComponent("cancelled.gif"), fps: 12)
        if let fast = RecorderFastGIFWriter(writer: cancelled, size: rect.size, isCancelled: { true }) {
            do {
                try fast.append(background, sourceBytes: 0)
                suite.expect(false, "cancelled GPU encoding must stop")
            } catch RecorderFastGIFWriter.Failure.cancelled {
                suite.expect(true, "cancelled GPU encoding stops before submitting work")
            }
        }
        let flag = CancelFlag()
        let batchSink = try RecorderGIFWriter(url: folder.appendingPathComponent("cancelled-batch.gif"), fps: 12)
        if let batch = RecorderFastGIFWriter(writer: batchSink, size: rect.size,
                                             isCancelled: { flag.value }) {
            for _ in 0..<batch.framesPerBatch { try batch.append(background, sourceBytes: 0) }
            flag.cancel()
            do {
                try batch.finish()
                suite.expect(false, "a submitted compression batch must honor cancellation")
            } catch RecorderFastGIFWriter.Failure.cancelled {
                suite.expect(true, "a submitted compression batch honors cancellation before finalizing")
            }
        }
        try sparseColor(suite, folder: folder)
        try retainedBytes(suite, folder: folder)
        suite.expect(RecorderFastGIFWriter(writer: cancelled,
            size: CGSize(width: CGFloat.infinity, height: 32), isCancelled: { false }) == nil,
                     "invalid GPU canvases request fallback")
    }

    private static func sparseColor(_ suite: TestSuite, folder: URL) throws {
        let url = folder.appendingPathComponent("thin-line.gif")
        let sink = try RecorderGIFWriter(url: url, fps: 12)
        let rect = CGRect(x: 0, y: 0, width: 2048, height: 128)
        guard let fast = RecorderFastGIFWriter(writer: sink, size: rect.size, isCancelled: { false }) else {
            suite.expect(false, "thin-line fixture initializes the Metal writer")
            return
        }
        let image = CIImage(color: .red).cropped(to: CGRect(x: 256, y: 0, width: 1, height: 128))
            .composited(over: CIImage(color: .white).cropped(to: rect))
        for _ in 0...fast.framesPerBatch { try fast.append(image, sourceBytes: 0) }
        try fast.finish()
        let chunk = try RecorderGIFWriter.chunk(from: Data(contentsOf: url))
        suite.expect(chunk.frames.count == fast.framesPerBatch + 1
            && chunk.frames.dropFirst().allSatisfy { $0.width == 1 && $0.height == 1 },
            "an unchanged detailed picture stays a delta across GPU batch boundaries")
        guard let gif = CGImageSourceCreateWithURL(url as CFURL, nil),
              let last = CGImageSourceCreateImageAtIndex(gif, fast.framesPerBatch, nil) else {
            suite.expect(false, "thin-line GIF decodes")
            return
        }
        let row = rgba(CIImage(cgImage: last), width: 2048, height: 1)
        suite.expect(Array(row[(255 * 4)..<(258 * 4)]) == [255, 255, 255, 255, 255, 0, 0, 255, 255, 255, 255, 255],
                     "a single red column stays red on white after palette sampling and delta compression")
    }

    private static func retainedBytes(_ suite: TestSuite, folder: URL) throws {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferBytesPerRowAlignmentKey: 4096] as CFDictionary
        guard CVPixelBufferCreate(nil, 64, 32, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer, CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else {
            suite.expect(false, "padded source buffer allocates")
            return
        }
        let bytes = CVPixelBufferGetDataSize(buffer)
        memset(CVPixelBufferGetBaseAddress(buffer)!, 255, CVPixelBufferGetBytesPerRow(buffer) * 32)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        suite.expect(bytes > 64 * 32 * 4, "the source fixture includes actual row padding")
        let url = folder.appendingPathComponent("padded-source.gif")
        let sink = try RecorderGIFWriter(url: url, fps: 12)
        let rect = CGRect(x: 0, y: 0, width: 64, height: 32)
        guard let fast = RecorderFastGIFWriter(writer: sink, size: rect.size, sourceByteLimit: bytes + bytes / 2,
                                               isCancelled: { false }) else {
            suite.expect(false, "padded source initializes the Metal writer")
            return
        }
        for _ in 0..<3 { try fast.append(CIImage(cvPixelBuffer: buffer), sourceBytes: bytes) }
        // The third append drains the first one-frame batch before finish.
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        suite.expect(size > 0, "padded sources flush at the byte limit before reaching the frame count limit")
        try fast.finish()
        let frames = try RecorderGIFWriter.chunk(from: Data(contentsOf: url)).frames
        suite.expect(frames.count == 3, "flushing small source batches retains every frame")
    }

    private static func rgba(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        CIContext().render(image, toBitmap: &bytes, rowBytes: width * 4,
                           bounds: CGRect(x: 0, y: 0, width: width, height: height),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return bytes
    }

    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
        func cancel() { lock.lock(); defer { lock.unlock() }; cancelled = true }
    }
}
