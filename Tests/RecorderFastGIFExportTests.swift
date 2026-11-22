// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Metal

/// End-to-end GIF exports at sizes that qualify for the GPU encoder. Every
/// timing fixture is BT.709 H.264. Imports with alpha or non-square pixels
/// exercise the fallback alongside a regular recording on the fast path.
/// Each source frame carries its own number in a binary strip along the
/// bottom, so a GIF frame names the source frame it shows.
enum RecorderFastGIFExportTests {
    static func run(_ suite: TestSuite) {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                try await probe(suite)
            } catch {
                suite.expect(false, "fast GIF export fixture failed \(error)")
            }
            done.signal()
        }
        suite.expect(done.wait(timeout: .now() + 240) == .success,
                     "fast GIF export regression finishes within its deadline")
    }

    private enum FixtureFailure: Error { case writeFailed }

    private static let width = 640
    private static let height = 480

    private static func probe(_ suite: TestSuite) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-fast-gif-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        print("fast GIF export: Metal device \(MTLCreateSystemDefaultDevice() == nil ? "absent, fallback encoder" : "present")")
        eligibility(suite)
        try await variableFrameRate(suite, folder: folder)
        try await editedTimeline(suite, folder: folder)
        try await orientation(suite, folder: folder)
        try await importedFormats(suite, folder: folder)
        try await cancellation(suite, folder: folder)
    }

    // MARK: - Eligibility

    private static func eligibility(_ suite: TestSuite) {
        func format(_ codec: CMVideoCodecType, transfer: CFString? = nil,
                    primaries: CFString? = nil, extra: [CFString: Any] = [:]) -> CMFormatDescription? {
            var extensions = extra
            if let transfer { extensions[kCMFormatDescriptionExtension_TransferFunction] = transfer }
            if let primaries { extensions[kCMFormatDescriptionExtension_ColorPrimaries] = primaries }
            var description: CMFormatDescription?
            let status = CMVideoFormatDescriptionCreate(allocator: nil, codecType: codec,
                width: 640, height: 480,
                extensions: extensions.isEmpty ? nil : extensions as CFDictionary,
                formatDescriptionOut: &description)
            return status == noErr ? description : nil
        }
        let h264 = kCMVideoCodecType_H264
        let hevc = kCMVideoCodecType_HEVC
        let bt709 = kCMFormatDescriptionTransferFunction_ITU_R_709_2
        let accepted: [(String, CMFormatDescription?)] = [
            ("untagged H.264", format(h264)),
            ("BT.709 H.264", format(h264, transfer: bt709,
                                    primaries: kCMFormatDescriptionColorPrimaries_ITU_R_709_2)),
            ("sRGB H.264", format(h264, transfer: kCMFormatDescriptionTransferFunction_sRGB)),
            ("BT.709 HEVC", format(hevc, transfer: bt709)),
        ]
        for (label, description) in accepted {
            suite.expect(description.map { RecorderExporter.supportsFastGIF([$0]) } == true,
                         "\(label) qualifies for the fast GIF encoder")
        }
        let rejected: [(String, [CMFormatDescription?])] = [
            ("no format", []),
            ("untagged HEVC, possibly HDR", [format(hevc)]),
            ("HEVC with a separate alpha plane", [format(hevc, transfer: bt709,
                extra: [kCMFormatDescriptionExtension_ContainsAlphaChannel: true])]),
            ("cropped H.264 raster", [format(h264, extra: [kCMFormatDescriptionExtension_CleanAperture: [
                kCMFormatDescriptionKey_CleanApertureWidth: 320, kCMFormatDescriptionKey_CleanApertureHeight: 240,
                kCMFormatDescriptionKey_CleanApertureHorizontalOffset: 0, kCMFormatDescriptionKey_CleanApertureVerticalOffset: 0]])]),
            ("PQ HEVC", [format(hevc, transfer: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ)]),
            ("HLG HEVC", [format(hevc, transfer: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG)]),
            ("Display P3 H.264", [format(h264, transfer: bt709,
                                         primaries: kCMFormatDescriptionColorPrimaries_P3_D65)]),
            ("BT.2020 HEVC", [format(hevc, transfer: bt709,
                                     primaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020)]),
            ("ProRes 4444 with alpha", [format(kCMVideoCodecType_AppleProRes4444)]),
            ("an SDR format beside an HDR one", [format(h264), format(hevc,
                transfer: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ)]),
        ]
        for (label, descriptions) in rejected {
            let built = descriptions.compactMap { $0 }
            suite.expect(built.count == descriptions.count && !RecorderExporter.supportsFastGIF(built),
                         "\(label) keeps the established GIF encoder")
        }
    }

    // MARK: - Sampling

    /// Irregular source timing: some frames are shorter than one GIF frame and
    /// must be skipped, others hold for several. The first and last pictures
    /// are held, and the clip spans more than two GPU batches.
    private static func variableFrameRate(_ suite: TestSuite, folder: URL) async throws {
        let take = try makeTake(in: folder, named: "variable")
        let gaps: [Int64] = [66, 223, 14, 175, 31, 247, 9, 128]
        var times: [Int64] = []
        var raw: Int64 = 0
        while raw < 3_400 {
            // GIF frames at 15 fps sit on multiples of 40/600 s. No source
            // frame begins exactly there, so the expected picture is unambiguous.
            times.append(raw > 0 && raw % 40 == 0 ? raw + 3 : raw)
            raw += gaps[times.count % gaps.count]
        }
        let end: Int64 = 3_730
        try await writeMovie(to: take.videoURL, times: times.map { CMTime(value: $0, timescale: 600) },
                             end: CMTime(value: end, timescale: 600)) { context, index in
            context.setFillColor(gray: 0.2, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(swatch(index).color)
            context.fill(CGRect(x: 64, y: 64, width: 192, height: 192))
            drawCode(index, in: context)
        }
        try await expectQualifiesForFastPath(suite, take.videoURL, "variable-rate fixture")
        let duration = try await AVURLAsset(url: take.videoURL).load(.duration).seconds
        suite.expectClose(duration, Double(end) / 600, "variable-rate fixture keeps its held last frame",
                          tol: 0.002)

        var document = plainDocument()
        document.gifFrameRate = 15
        let destination = folder.appendingPathComponent("variable.gif")
        let failure = await RecorderExporter().export(take: take, document: document, output: .gif,
                                                      to: destination, progress: { _ in })
        suite.expect(failure == nil, "variable-rate GIF exports, failure \(String(describing: failure))")
        guard failure == nil, let animation = decode(destination, { bitmap in
            (size: (bitmap.width, bitmap.height), code: readCode(bitmap),
             swatch: classify(bitmap.mean(x: 112..<208, y: 112..<208)))
        }) else {
            suite.expect(false, "variable-rate GIF decodes")
            return
        }
        let count = RecorderSupport.gifFrameCount(duration: document.exportDuration(duration: duration),
                                                  fps: 15)
        suite.expect(count == 93 && animation.frames.count == count,
                     "every GIF timestamp becomes a frame across six batches, got \(animation.frames.count) of \(count)")
        suite.expectClose(animation.duration, Double(count) / 15,
                          "variable-rate GIF keeps the 15 fps clock", tol: 0.011)
        suite.expect(animation.frames.allSatisfy { $0.size == (width, height) },
                     "variable-rate GIF keeps the full 640x480 picture")
        let expected = (0..<count).map { frame -> Int in
            let time = min(Double(end) / 600, Double(frame) / 15)
            return times.lastIndex { Double($0) / 600 <= time + 1e-9 } ?? 0
        }
        let shown = animation.frames.map(\.code)
        let mismatches = zip(shown, expected).enumerated().filter { $0.element.0 != $0.element.1 }
        suite.expect(shown.count == expected.count && mismatches.isEmpty,
                     "each GIF frame shows the source frame covering its timestamp, mismatches \(mismatches.prefix(6).map { "\($0.offset): \($0.element.0) not \($0.element.1)" })")
        let skipped = Set(times.indices).subtracting(expected)
        suite.expect(!skipped.isEmpty && expected.prefix(2) == [0, 0]
                        && expected.suffix(5).allSatisfy { $0 == times.count - 1 },
                     "the fixture holds its first and last frames and skips short ones")
        suite.expect(shown.prefix(2) == [0, 0], "the first source frame is held at the start, got \(shown.prefix(2))")
        suite.expect(shown.suffix(5).allSatisfy { $0 == times.count - 1 },
                     "the last source frame is held to the end, got \(shown.suffix(5))")
        let colours = animation.frames.map(\.swatch)
        let wrongColours = zip(colours, expected).filter { $0.0 != swatch($0.1).name }.count
        suite.expect(wrongColours == 0, "NV12 source colours survive the GIF palette, \(wrongColours) wrong")
    }

    // MARK: - Editing

    /// Trim, a cut and a non-integer speed retime the picture; a timed blur
    /// over the top of it must follow the frame that is actually shown.
    private static func editedTimeline(_ suite: TestSuite, folder: URL) async throws {
        let take = try makeTake(in: folder, named: "edited")
        try await writeMovie(to: take.videoURL, times: (0..<180).map { CMTime(value: Int64($0), timescale: 60) },
                             end: CMTime(value: 180, timescale: 60)) { context, index in
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(gray: 1, alpha: 1)
            for row in 0..<25 {
                for column in 0..<40 where (row + column) % 2 == 0 {
                    context.fill(CGRect(x: column * 16, y: row * 16, width: 16, height: 16))
                }
            }
            drawCode(index, in: context)
        }
        try await expectQualifiesForFastPath(suite, take.videoURL, "edited fixture")

        let speed = 1.37
        let trimStart = 0.15
        let trimEnd = 2.85
        let cut = (start: 0.9, end: 1.4)
        let blur = (start: 0.6, end: 1.7)
        var document = plainDocument()
        document.gifFrameRate = 15
        document.exportSpeed = speed
        document.trimStart = trimStart
        document.trimEnd = trimEnd
        document.cuts = [.init(start: cut.start, end: cut.end)]
        // Top-left origin: the top 60 percent, clear of the frame number.
        document.blurs = [RecorderBlurRegion(start: blur.start, end: blur.end,
                                             rect: CGRect(x: 0, y: 0, width: 1, height: 0.6))]
        let destination = folder.appendingPathComponent("edited.gif")
        let failure = await RecorderExporter().export(take: take, document: document, output: .gif,
                                                      to: destination, progress: { _ in })
        suite.expect(failure == nil, "edited GIF exports, failure \(String(describing: failure))")
        guard failure == nil, let animation = decode(destination, { bitmap in
            (size: (bitmap.width, bitmap.height), code: readCode(bitmap),
             contrast: bitmap.deviation(x: 160..<480, y: 48..<240))
        }) else {
            suite.expect(false, "edited GIF decodes")
            return
        }
        let count = RecorderSupport.gifFrameCount(duration: document.exportDuration(duration: 3), fps: 15)
        suite.expect(count == 24 && animation.frames.count == count,
                     "edited GIF keeps its retimed frame count, got \(animation.frames.count) of \(count)")
        suite.expectClose(animation.duration, Double(count) / 15, "edited GIF keeps the 15 fps clock",
                          tol: 0.011)
        suite.expect(animation.frames.allSatisfy { $0.size == (width, height) },
                     "edited GIF keeps the full 640x480 canvas")
        // Where each kept source frame lands on the exported clock.
        func outputTime(_ frame: Int) -> Double? {
            let time = Double(frame) / 60
            if time >= trimStart && time < cut.start { return (time - trimStart) / speed }
            if time >= cut.end && time < trimEnd { return (time - trimStart - (cut.end - cut.start)) / speed }
            return nil
        }
        let outputDuration = document.exportDuration(duration: 3)
        var misplaced: [String] = []
        var exposed: [String] = []
        var protected = 0
        var clear = 0
        for (index, frame) in animation.frames.enumerated() {
            let time = min(outputDuration, Double(index) / 15)
            let expected = (0..<180).last { outputTime($0).map { $0 <= time + 1e-6 } ?? false } ?? -1
            if abs(frame.code - expected) > 1 { misplaced.append("\(index): \(frame.code) not \(expected)") }
            // Blur state follows the recording time of the picture shown, with
            // a margin for the composer's neighbouring-sample coverage.
            let shown = Double(frame.code) / 60
            if shown > blur.start + 2.0 / 60 && shown < blur.end - 2.0 / 60 {
                protected += 1
                if frame.contrast >= 40 { exposed.append("\(index) at \(frame.code): \(Int(frame.contrast))") }
            } else if shown < blur.start - 3.0 / 60 || shown > blur.end + 3.0 / 60 {
                clear += 1
                if frame.contrast <= 100 { exposed.append("\(index) at \(frame.code) hidden: \(Int(frame.contrast))") }
            }
        }
        suite.expect(misplaced.isEmpty,
                     "trim, cut and 1.37x speed pick the right source frames, \(misplaced.prefix(6))")
        suite.expect(protected >= 5 && clear >= 10 && exposed.isEmpty,
                     "the timed blur covers exactly its frames on the edited clock (\(protected) protected, \(clear) clear) \(exposed.prefix(6))")
        let codes = animation.frames.map(\.code)
        suite.expect(!codes.contains { (54..<84).contains($0) } && !codes.contains { $0 < 9 || $0 >= 171 },
                     "neither the trimmed ends nor the cut appear in the GIF")
    }

    // MARK: - Orientation

    /// Rotated and mirrored non-square sources keep the displayed shape and
    /// layout, with and without the composer.
    private static func orientation(_ suite: TestSuite, folder: URL) async throws {
        let take = try makeTake(in: folder, named: "oriented")
        let transforms: [(String, CGAffineTransform)] = [
            ("90 degree portrait", CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0)),
            ("270 degree portrait", CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: CGFloat(width))),
            ("mirrored", CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: CGFloat(width), ty: 0)),
        ]
        for (label, transform) in transforms {
            try await writeMovie(to: take.videoURL, times: (0..<10).map { CMTime(value: Int64($0), timescale: 10) },
                                 end: CMTime(value: 1, timescale: 1), transform: transform) { context, _ in
                for (quadrant, colour) in zip(0..<4, "RGBW") {
                    context.setFillColor(named(colour))
                    context.fill(CGRect(x: quadrant % 2 * width / 2, y: quadrant / 2 * height / 2,
                                        width: width / 2, height: height / 2))
                }
            }
            if label == transforms[0].0 {
                try await expectQualifiesForFastPath(suite, take.videoURL, "oriented fixture")
            }
            let displayed = CGRect(x: 0, y: 0, width: width, height: height).applying(transform).size
            // Each displayed quadrant, traced back to the authored picture.
            let inverse = transform.inverted()
            let expected = (0..<4).map { quadrant -> Character in
                let point = CGPoint(x: (CGFloat(quadrant % 2) + 0.5) * displayed.width / 2,
                                    y: (CGFloat(quadrant / 2) + 0.5) * displayed.height / 2).applying(inverse)
                return Array("RGBW")[(point.y < CGFloat(height) / 2 ? 0 : 2) + (point.x < CGFloat(width) / 2 ? 0 : 1)]
            }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: take.videoURL))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let reference = bitmap(try await generator.image(at: .zero).image)
            suite.expect(quadrants(reference) == expected,
                         "\(label) reference shows \(String(quadrants(reference))), expected \(String(expected))")
            for edited in [false, true] {
                var document = plainDocument()
                // A cut sends the frames through the composer.
                if edited { document.cuts = [.init(start: 0.3, end: 0.5)] }
                let destination = folder.appendingPathComponent("oriented-\(edited).gif")
                let failure = await RecorderExporter().export(take: take, document: document, output: .gif,
                                                              to: destination, progress: { _ in })
                guard failure == nil, let animation = decode(destination, { bitmap in
                    (size: CGSize(width: bitmap.width, height: bitmap.height), layout: quadrants(bitmap),
                     difference: bitmap.difference(from: reference))
                }), let first = animation.frames.first, let last = animation.frames.last else {
                    suite.expect(false, "\(label) GIF exports and decodes, failure \(String(describing: failure))")
                    continue
                }
                suite.expect(first.size == displayed && last.size == displayed,
                             "\(label) GIF keeps the displayed \(displayed) size, edited \(edited), got \(first.size)")
                suite.expect(first.layout == expected && last.layout == expected,
                             "\(label) GIF keeps the displayed layout, edited \(edited): \(String(first.layout)) \(String(last.layout)) not \(String(expected))")
                suite.expect(first.difference < 12 && last.difference < 12,
                             "\(label) GIF matches the displayed source, edited \(edited), difference \(first.difference)")
            }
        }
    }

    /// Import the same two-panel drawing with three actual sample descriptions.
    /// Check the exported and copied bytes, including after scaling and a cut.
    private static func importedFormats(_ suite: TestSuite, folder: URL) async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let cases: [(String, AVVideoCodecType, Int)] = [
            ("sdr", .h264, 1), ("alpha", .hevcWithAlpha, 1), ("anamorphic", .h264, 2),
        ]
        for (name, codec, aspect) in cases {
            let take = try makeTake(in: folder, named: name)
            let alpha = codec == .hevcWithAlpha
            try await writeMovie(to: take.videoURL, times: (0..<12).map { CMTime(value: Int64($0), timescale: 12) },
                                 end: CMTime(value: 1, timescale: 1), codec: codec, pixelAspect: aspect) { context, _ in
                let full = CGRect(x: 0, y: 0, width: width, height: height)
                if alpha {
                    context.clear(full)
                } else {
                    context.setFillColor(named("G"))
                    context.fill(full)
                }
                context.setFillColor(named("R"))
                context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
            }
            let video = try await AVURLAsset(url: take.videoURL).loadTracks(withMediaType: .video)[0]
            let formats = try await video.load(.formatDescriptions)
            suite.expect(RecorderExporter.supportsFastGIF(formats) == (!alpha && aspect == 1),
                         "\(name) selects the encoder for its actual sample description")
            if alpha {
                let characteristics = try await video.load(.mediaCharacteristics)
                suite.expect(characteristics.contains(.containsAlphaChannel)
                    && formats.first.map { CMFormatDescriptionGetMediaSubType($0) } == kCMVideoCodecType_HEVC,
                    "the transparent HEVC fixture carries alpha under the regular HEVC subtype")
            }
            for (percent, cut) in [(100, false), (75, false), (75, true)] {
                var document = plainDocument()
                document.gifScalePercent = percent
                if cut { document.cuts = [.init(start: 0.25, end: 0.5)] }
                let gif = take.folder.appendingPathComponent("\(percent)-\(cut).gif")
                let failure = await RecorderExporter().export(take: take, document: document, output: .gif,
                                                            to: gif, progress: { _ in })
                guard failure == nil, let source = CGImageSourceCreateWithURL(gif as CFURL, nil) else {
                    suite.expect(false, "\(name) at \(percent)% exports, cut \(cut), failure \(String(describing: failure))")
                    continue
                }
                let count = CGImageSourceGetCount(source)
                suite.expect(count == (cut ? 9 : 12), "\(name) keeps its frame count with cut \(cut)")
                for index in [0, count - 1] {
                    guard index >= 0, let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                        suite.expect(false, "\(name) decodes frame \(index)")
                        continue
                    }
                    let image = bitmap(frame)
                    suite.expect(image.width == width * aspect * percent / 100 && image.height == height * percent / 100,
                                 "\(name) keeps its presentation dimensions at \(percent)%")
                    let middle = image.width * (image.height / 2)
                    let left = (middle + image.width / 4) * 4
                    let right = (middle + image.width * 3 / 4) * 4
                    let bytes = image.bytes
                    let leftOK = alpha ? bytes[left + 3] == 0 : bytes[left + 1] > 180 && bytes[left + 3] == 255
                    suite.expect(leftOK && bytes[right] > 180 && bytes[right + 1] < 70 && bytes[right + 3] == 255,
                                 "\(name) preserves the left panel and fills the right at \(percent)%, cut \(cut)")
                }
                let data = try Data(contentsOf: gif)
                if name == "sdr", percent == 100, MTLCreateSystemDefaultDevice() != nil {
                    let chunk = try RecorderGIFWriter.chunk(from: data)
                    let first = chunk.frames.first
                    let entries = (chunk.globalTable?.count ?? 0) / 3
                    suite.expect(first?.disposal == 1 && first?.transparency == 1
                            && first.map { Int($0.transparentIndex) } == entries - 1
                            && chunk.screen.first.map { $0 & 0x70 == 0 } == true,
                                 "an ordinary opaque export actually uses the indexed Metal/cgif writer")
                }
                suite.expect(RecorderGIFClipboard.publish(fileURL: gif, to: pasteboard)
                    && pasteboard.data(forType: RecorderGIFClipboard.pasteboardType) == data
                    && pasteboard.string(forType: .fileURL) == gif.absoluteString,
                    "\(name) copy publishes the same animation as Save as GIF")
            }
        }
    }

    // MARK: - Cancellation

    /// Cancelling once a batch is already in flight publishes nothing and
    /// leaves no scratch behind.
    private static func cancellation(_ suite: TestSuite, folder: URL) async throws {
        let take = try makeTake(in: folder, named: "cancelled")
        // Enough output frames for a fractional progress report. Cancel the
        // first report regardless of wall-clock speed; the writer unit test
        // separately covers cancellation after a compression batch starts.
        try await writeMovie(to: take.videoURL, times: (0..<30).map { CMTime(value: Int64($0), timescale: 1) },
                             end: CMTime(value: 30, timescale: 1)) { context, index in
            context.setFillColor(gray: CGFloat(index % 5) / 4, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            drawCode(index, in: context)
        }
        var document = plainDocument()
        document.gifFrameRate = 15
        let destination = take.folder.appendingPathComponent("kept.gif")
        let previous = Data("previous gif".utf8)
        try previous.write(to: destination)
        let scratch = RecorderGIFWorkspace.root
        func leftovers() -> Set<String> {
            Set((try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? [])
        }
        let scratchBefore = leftovers()
        let siblingsBefore = Set(try FileManager.default.contentsOfDirectory(atPath: take.folder.path))
        let exporter = RecorderExporter()
        let cancelledAt = CancelPoint()
        let threshold = 0.005
        let failure = await exporter.export(take: take, document: document, output: .gif,
                                            to: destination, progress: { value in
            if value >= threshold, value < 1, cancelledAt.record(value) { exporter.cancel() }
        })
        let point = cancelledAt.value
        suite.expect(point.map { $0 >= threshold && $0 < 0.99 } == true,
                     "cancellation lands during export, at \(String(describing: point))")
        suite.expect(failure == .cancelled, "a cancelled fast GIF reports cancellation, got \(String(describing: failure))")
        suite.expect((try? Data(contentsOf: destination)) == previous,
                     "a cancelled GIF leaves the existing destination unchanged")
        let siblingsAfter = Set(try FileManager.default.contentsOfDirectory(atPath: take.folder.path))
        suite.expect(siblingsAfter == siblingsBefore,
                     "a cancelled GIF leaves no staged file beside the destination, \(siblingsAfter.subtracting(siblingsBefore))")
        suite.expect(leftovers().subtracting(scratchBefore).isEmpty,
                     "a cancelled GIF removes its scratch workspace, \(leftovers().subtracting(scratchBefore))")
    }

    private final class CancelPoint: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: Double?

        /// True only for the first report, which is the one that cancels.
        func record(_ value: Double) -> Bool {
            lock.withLock {
                guard recorded == nil else { return false }
                recorded = value
                return true
            }
        }

        var value: Double? { lock.withLock { recorded } }
    }

    // MARK: - Fixtures

    private static func makeTake(in folder: URL, named name: String) throws -> RecorderTakeStore.Take {
        let take = RecorderTakeStore.Take(id: UUID(), folder: folder.appendingPathComponent(name))
        try FileManager.default.createDirectory(at: take.folder, withIntermediateDirectories: true)
        return take
    }

    private static func plainDocument() -> RecorderEditDocument {
        var document = RecorderEditDocument()
        document.showsPointer = false
        document.zoomEnabled = false
        // Compare frames at native size; GIF scaling has separate coverage.
        document.gifScalePercent = 100
        return document
    }

    private static func expectQualifiesForFastPath(_ suite: TestSuite, _ url: URL, _ label: String) async throws {
        let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)[0]
        let formats = try await track.load(.formatDescriptions)
        suite.expect(RecorderExporter.supportsFastGIF(formats), "\(label) is BT.709 H.264 the fast encoder accepts")
    }

    /// Draws each frame with Core Graphics, top-left origin, into the
    /// writer's own buffers, and stamps the given timestamps exactly.
    private static func writeMovie(to url: URL, times: [CMTime], end: CMTime,
                                   transform: CGAffineTransform = .identity,
                                   codec: AVVideoCodecType = .h264, pixelAspect: Int = 1,
                                   draw: @escaping (CGContext, Int) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var settings: [String: Any] = [
            AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        if pixelAspect != 1 {
            settings[AVVideoPixelAspectRatioKey] = [
                AVVideoPixelAspectRatioHorizontalSpacingKey: pixelAspect,
                AVVideoPixelAspectRatioVerticalSpacingKey: 1,
            ]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.transform = transform
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            ])
        writer.add(input)
        guard writer.startWriting() else { throw FixtureFailure.writeFailed }
        writer.startSession(atSourceTime: .zero)
        let queue = DispatchQueue(label: "recorder-fast-gif-fixture")
        let appended = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let feed = Feed(input: input, adapter: adapter, times: times, draw: draw,
                            continuation: continuation)
            input.requestMediaDataWhenReady(on: queue) { feed.pump() }
        }
        guard appended else {
            writer.cancelWriting()
            throw FixtureFailure.writeFailed
        }
        writer.endSession(atSourceTime: end)
        await writer.finishWriting()
        guard writer.status == .completed else { throw FixtureFailure.writeFailed }
    }

    /// Only touched on the writer's serial feeding queue. The ready callback
    /// can fire again after the last frame; only the first finish resumes.
    private final class Feed: @unchecked Sendable {
        private let input: AVAssetWriterInput
        private let adapter: AVAssetWriterInputPixelBufferAdaptor
        private let times: [CMTime]
        private let draw: (CGContext, Int) -> Void
        private let continuation: CheckedContinuation<Bool, Never>
        private var index = 0
        private var finished = false

        init(input: AVAssetWriterInput, adapter: AVAssetWriterInputPixelBufferAdaptor, times: [CMTime],
             draw: @escaping (CGContext, Int) -> Void, continuation: CheckedContinuation<Bool, Never>) {
            self.input = input
            self.adapter = adapter
            self.times = times
            self.draw = draw
            self.continuation = continuation
        }

        func pump() {
            while !finished && input.isReadyForMoreMediaData {
                guard index < times.count else { return finish(true) }
                var maybe: CVPixelBuffer?
                guard let pool = adapter.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybe) == kCVReturnSuccess,
                      let pixel = maybe else { return finish(false) }
                CVPixelBufferLockBaseAddress(pixel, [])
                if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width,
                        height: height, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pixel),
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                            | CGBitmapInfo.byteOrder32Little.rawValue) {
                    context.translateBy(x: 0, y: CGFloat(height))
                    context.scaleBy(x: 1, y: -1)
                    draw(context, index)
                }
                CVPixelBufferUnlockBaseAddress(pixel, [])
                guard adapter.append(pixel, withPresentationTime: times[index]) else { return finish(false) }
                index += 1
            }
        }

        private func finish(_ result: Bool) {
            finished = true
            input.markAsFinished()
            continuation.resume(returning: result)
        }
    }

    /// Eight black or white cells along the bottom: the source frame number.
    private static func drawCode(_ value: Int, in context: CGContext) {
        let cell = width / 8
        for bit in 0..<8 {
            context.setFillColor(gray: (value >> bit) & 1 == 1 ? 1 : 0, alpha: 1)
            context.fill(CGRect(x: bit * cell, y: height - 64, width: cell, height: 64))
        }
    }

    private static func readCode(_ bitmap: Bitmap) -> Int {
        let cell = bitmap.width / 8
        return (0..<8).reduce(0) { value, bit in
            let mean = bitmap.mean(x: (bit * cell + cell / 4)..<(bit * cell + cell * 3 / 4),
                                   y: (bitmap.height - 52)..<(bitmap.height - 12))
            return (mean.red + mean.green + mean.blue) / 3 > 128 ? value | 1 << bit : value
        }
    }

    private static func swatch(_ index: Int) -> (name: Character, color: CGColor) {
        let name = Array("RGBW")[index % 4]
        return (name, named(name))
    }

    private static func named(_ name: Character) -> CGColor {
        switch name {
        case "R": return CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        case "G": return CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        case "B": return CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        default: return CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    private static func classify(_ colour: (red: Double, green: Double, blue: Double)) -> Character {
        let (red, green, blue) = colour
        if red > 170 && green > 170 && blue > 170 { return "W" }
        if red > 150 && green < 100 && blue < 100 { return "R" }
        if green > 150 && red < 100 && blue < 100 { return "G" }
        if blue > 150 && red < 100 && green < 100 { return "B" }
        return "?"
    }

    private static func quadrants(_ bitmap: Bitmap) -> [Character] {
        (0..<4).map { quadrant in
            let x = quadrant % 2 * bitmap.width / 2
            let y = quadrant / 2 * bitmap.height / 2
            return classify(bitmap.mean(x: (x + bitmap.width / 8)..<(x + bitmap.width * 3 / 8),
                                        y: (y + bitmap.height / 8)..<(y + bitmap.height * 3 / 8)))
        }
    }

    // MARK: - Decoding

    /// sRGB RGBA bytes, top row first.
    private struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func mean(x: Range<Int>, y: Range<Int>) -> (red: Double, green: Double, blue: Double) {
            var sum = (0, 0, 0)
            for row in y {
                for column in x {
                    let offset = (row * width + column) * 4
                    sum.0 += Int(bytes[offset])
                    sum.1 += Int(bytes[offset + 1])
                    sum.2 += Int(bytes[offset + 2])
                }
            }
            let count = Double(max(1, x.count * y.count))
            return (Double(sum.0) / count, Double(sum.1) / count, Double(sum.2) / count)
        }

        /// Standard deviation of luminance: high for a sharp checkerboard.
        func deviation(x: Range<Int>, y: Range<Int>) -> Double {
            var values: [Double] = []
            values.reserveCapacity(x.count * y.count)
            for row in y {
                for column in x {
                    let offset = (row * width + column) * 4
                    values.append(0.299 * Double(bytes[offset]) + 0.587 * Double(bytes[offset + 1])
                                  + 0.114 * Double(bytes[offset + 2]))
                }
            }
            let mean = values.reduce(0, +) / Double(max(1, values.count))
            return sqrt(values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, values.count)))
        }

        /// Mean absolute channel difference, or infinity for another size.
        func difference(from other: Bitmap) -> Double {
            guard width == other.width, height == other.height else { return .infinity }
            var total = 0
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                total += abs(Int(bytes[offset]) - Int(other.bytes[offset]))
                    + abs(Int(bytes[offset + 1]) - Int(other.bytes[offset + 1]))
                    + abs(Int(bytes[offset + 2]) - Int(other.bytes[offset + 2]))
            }
            return Double(total) / Double(width * height * 3)
        }
    }

    private static func bitmap(_ image: CGImage) -> Bitmap {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Bitmap(width: image.width, height: image.height, bytes: bytes)
    }

    /// Measures each frame as it decodes, so a long GIF is never held whole.
    private static func decode<Measure>(_ url: URL, _ measure: (Bitmap) -> Measure)
        -> (frames: [Measure], duration: Double)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var frames: [Measure] = []
        var duration = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            let frame: Measure? = autoreleasepool {
                CGImageSourceCreateImageAtIndex(source, index, nil).map { measure(bitmap($0)) }
            }
            guard let frame else { return nil }
            frames.append(frame)
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?
            let gif = properties?[kCGImagePropertyGIFDictionary] as? NSDictionary
            duration += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? 0
        }
        return (frames, duration)
    }
}
