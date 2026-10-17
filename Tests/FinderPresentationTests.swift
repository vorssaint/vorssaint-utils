// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum FinderPresentationTests {
    static func run(_ suite: TestSuite) {
        suite.run("Finder presentation compression") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: root) }
                let input = root.appendingPathComponent("input.pptx")
                let original = FinderNewFileTemplates.contents(for: "input.pptx")
                try original.write(to: input)
                let output = root.appendingPathComponent("compressed.pptx")
                _ = try FinderPresentationTools.compress(input, to: output, cancellation: FinderToolsCancellation())
                let reduced = try Data(contentsOf: output)
                suite.expect(reduced.count < original.count, "compression publishes a smaller PPTX")
                let validation = BoundedProcessRunner.run("/usr/bin/unzip", ["-t", output.path], timeout: 10, maxOutputBytes: 4096)
                suite.expect(validation.status == 0, "independent unzip validates all output CRCs")
                for part in ["[Content_Types].xml", "ppt/presentation.xml", "_rels/.rels"] {
                    // unzip treats square brackets as globs: use its escaped literal pattern.
                    let pattern = part.replacingOccurrences(of: "[", with: "\\[")
                    let before = BoundedProcessRunner.run("/usr/bin/unzip", ["-p", input.path, pattern], timeout: 10, maxOutputBytes: 16384)
                    let after = BoundedProcessRunner.run("/usr/bin/unzip", ["-p", output.path, pattern], timeout: 10, maxOutputBytes: 16384)
                    suite.expect(before.status == 0 && after.status == 0 && before.output == after.output,
                                 "compression preserves the exact \(part) document part")
                }
                suite.expect(try Data(contentsOf: input) == original, "compression leaves source bytes unchanged")
                do {
                    _ = try FinderPresentationTools.compress(input, to: output, cancellation: FinderToolsCancellation())
                    suite.expect(false, "existing output must be rejected")
                } catch FinderFileActionError.destinationExists {
                    suite.expect(try Data(contentsOf: output) == reduced, "collision preserves the previous output")
                }
                let cancelled = FinderToolsCancellation()
                cancelled.cancel()
                let cancelledOutput = root.appendingPathComponent("cancelled.pptx")
                do {
                    _ = try FinderPresentationTools.compress(input, to: cancelledOutput, cancellation: cancelled)
                    suite.expect(false, "cancelled compression must fail")
                } catch is CancellationError {
                    suite.expect(!FileManager.default.fileExists(atPath: cancelledOutput.path), "cancellation publishes no presentation")
                }
                // Re-open a deflated package, exercising the reader independently
                // of the stored template. No-op recompression must stay lossless.
                let roundTrip = try FinderPresentationArchive(reduced).rewrite(cancellation: FinderToolsCancellation()) { $0.contents }
                suite.expect(roundTrip == reduced, "deflated entry decoding preserves bytes across a no-op rewrite")
                let noGainOutput = root.appendingPathComponent("no-gain.pptx")
                do {
                    _ = try FinderPresentationTools.compress(output, to: noGainOutput, cancellation: FinderToolsCancellation())
                    suite.expect(false, "a same-size presentation must not be published")
                } catch {
                    suite.expect(!FileManager.default.fileExists(atPath: noGainOutput.path), "no size reduction produces no output")
                }
                var corrupt = original
                let marker = Data("<?xml".utf8)
                if let range = corrupt.range(of: marker) { corrupt[range.lowerBound] ^= 1 }
                do {
                    _ = try FinderPresentationArchive(corrupt).rewrite(cancellation: FinderToolsCancellation()) { $0.contents }
                    suite.expect(false, "corrupt part checksum must fail")
                } catch { suite.expect(true, "corrupt entry is rejected before publication") }
                // A forged directory offset must be a validation error, never an out-of-bounds read.
                var malformed = original
                for index in (malformed.count - 6)..<(malformed.count - 2) { malformed[index] = 0xff }
                do { _ = try FinderPresentationArchive(malformed); suite.expect(false, "invalid directory must fail") }
                catch { suite.expect(true, "invalid directory offset is rejected") }
                try verifyJPEGCompression(root: root, suite: suite)
            } catch { suite.expect(false, "presentation fixture failed: \(error)") }
        }
    }

    private static func verifyJPEGCompression(root: URL, suite: TestSuite) throws {
        let package = root.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        let seed = root.appendingPathComponent("input.pptx")
        let unzip = BoundedProcessRunner.run("/usr/bin/unzip", ["-q", seed.path, "-d", package.path], timeout: 10, maxOutputBytes: 4096)
        guard unzip.status == 0 else { throw CocoaError(.fileReadCorruptFile) }
        let media = package.appendingPathComponent("ppt/media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let jpeg = media.appendingPathComponent("image1.jpg")
        let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        var random: UInt32 = 42
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        for index in 0..<(256 * 256 * 4) {
            random = random &* 1664525 &+ 1013904223
            bytes[index] = UInt8(truncatingIfNeeded: random >> 24)
        }
        let encoder = CGImageDestinationCreateWithURL(jpeg as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        guard CGImageDestinationFinalize(encoder) else { throw CocoaError(.fileWriteUnknown) }
        let input = root.appendingPathComponent("pictures.pptx")
        let archive = Process()
        archive.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        archive.arguments = ["-q", "-r", input.path, "."]
        archive.currentDirectoryURL = package
        try archive.run(); archive.waitUntilExit()
        guard archive.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        let output = root.appendingPathComponent("pictures-small.pptx")
        _ = try FinderPresentationTools.compress(input, to: output, cancellation: FinderToolsCancellation())
        let extracted = BoundedProcessRunner.run("/usr/bin/unzip", ["-p", output.path, "ppt/media/image1.jpg"],
                                                timeout: 10, maxOutputBytes: 1_048_576)
        let originalImage = try Data(contentsOf: jpeg)
        suite.expect(extracted.status == 0 && extracted.output.count < originalImage.count,
                     "JPEG optimization reduces embedded picture bytes")
        let image = CGImageSourceCreateWithData(extracted.output as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        suite.expect(image?.width == 256 && image?.height == 256, "optimized JPEG preserves picture dimensions")
    }
}
