// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import ImageIO
import PDFKit

/// End-to-end check of the converters, run with `Vorssaint --convert-selftest`.
/// It builds small real files in a temp folder, converts them through the same
/// engines and queue the island uses, and checks each output by its bytes.
/// Conversions that need ffmpeg are skipped, with a note, when none is found.
enum ConvertSelfTest {
    private struct Result { let name: String; let status: String; let detail: String }
    private static var results: [Result] = []
    private static var quiet = false

    /// The same checks, for Settings: one line per result, no exit.
    @MainActor
    static func runForSettings() async -> [String] {
        results = []
        quiet = true
        defer { quiet = false }
        _ = await run()
        return results.map { "\($0.status)  \($0.name)\($0.detail.isEmpty ? "" : "  — \($0.detail)")" }
    }

    static func runAndExit() -> Never {
        Task { @MainActor in
            let ok = await run()
            exit(ok ? 0 : 1)
        }
        dispatchMain()
    }

    private static func record(_ name: String, _ ok: Bool, _ detail: String = "") {
        results.append(Result(name: name, status: ok ? "PASS" : "FAIL", detail: detail))
        if !quiet { print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  — \(detail)")") }
    }

    private static func skip(_ name: String, _ why: String) {
        results.append(Result(name: name, status: "SKIP", detail: why))
        if !quiet { print("SKIP  \(name)  — \(why)") }
    }

    // MARK: Fixtures

    private static func makeImage(_ side: Int = 96) -> CGImage {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<side {
            for x in 0..<side {
                context.setFillColor(red: CGFloat(x) / CGFloat(side), green: CGFloat(y) / CGFloat(side),
                                     blue: CGFloat((x * y) % 255) / 255, alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return context.makeImage()!
    }

    private static func writePNG(_ image: CGImage, to url: URL) {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private static func writeWAV(to url: URL, seconds: Double = 1.5) {
        let rate = 22_050, count = Int(Double(rate) * seconds)
        var data = Data()
        func le32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func le16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        data.append("RIFF".data(using: .ascii)!); le32(UInt32(36 + count * 2)); data.append("WAVEfmt ".data(using: .ascii)!)
        le32(16); le16(1); le16(1); le32(UInt32(rate)); le32(UInt32(rate * 2)); le16(2); le16(16)
        data.append("data".data(using: .ascii)!); le32(UInt32(count * 2))
        for i in 0..<count { le16(UInt16(bitPattern: Int16(sin(Double(i) / 20) * 12_000))) }
        try? data.write(to: url)
    }

    private static func header(_ url: URL, _ count: Int = 16) -> [UInt8] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        return Array((try? handle.read(upToCount: count)) ?? Data())
    }

    private static func size(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int) ?? 0
    }

    private static func pixelSize(_ url: URL) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    /// Whether the first bytes of `url` are what `format` begins with.
    private static func magic(_ url: URL, _ format: FileFormat) -> Bool {
        let h = header(url)
        func starts(_ bytes: [UInt8], at offset: Int = 0) -> Bool { h.count >= offset + bytes.count && Array(h[offset..<offset + bytes.count]) == bytes }
        switch format {
        case .png: return starts([0x89, 0x50, 0x4E, 0x47])
        case .jpg: return starts([0xFF, 0xD8])
        case .pdf: return starts(Array("%PDF".utf8))
        case .gif: return starts(Array("GIF8".utf8))
        case .bmp: return starts(Array("BM".utf8))
        case .tiff: return starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A])
        case .webp: return starts(Array("RIFF".utf8)) && starts(Array("WEBP".utf8), at: 8)
        case .wav: return starts(Array("RIFF".utf8)) && starts(Array("WAVE".utf8), at: 8)
        case .flac: return starts(Array("fLaC".utf8))
        case .ogg, .opus: return starts(Array("OggS".utf8))
        case .aiff: return starts(Array("FORM".utf8))
        case .mp3: return starts(Array("ID3".utf8)) || (h.count > 1 && h[0] == 0xFF && (h[1] & 0xE0) == 0xE0)
        case .mp4, .mov, .m4a: return starts(Array("ftyp".utf8), at: 4) || starts(Array("moov".utf8), at: 4) || starts(Array("wide".utf8), at: 4)
        case .webm, .mkv: return starts([0x1A, 0x45, 0xDF, 0xA3])
        case .heic, .avif: return starts(Array("ftyp".utf8), at: 4)
        default: return true
        }
    }

    // MARK: Runs

    @MainActor
    private static func run() async -> Bool {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-convert-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        print("ffmpeg: \(FFmpeg.path ?? "none")")

        let png = root.appendingPathComponent("photo.png")
        writePNG(makeImage(), to: png)
        let wav = root.appendingPathComponent("tone.wav")
        writeWAV(to: wav)
        let txt = root.appendingPathComponent("notes.txt")
        try? "Hello from Vorssaint.\nSecond line.".write(to: txt, atomically: true, encoding: .utf8)
        let srt = root.appendingPathComponent("captions.srt")
        try? "1\n00:00:01,000 --> 00:00:03,000\nHello there\n\n2\n00:00:04,000 --> 00:00:06,500\nSecond cue\n".write(to: srt, atomically: true, encoding: .utf8)

        // The matrix: nothing offers itself, and every offered pair has an engine.
        var orphan: [String] = []
        for source in FileFormat.allCases {
            let targets = ConversionMatrix.targets(for: source)
            if targets.contains(source) { orphan.append("\(source.rawValue) offers itself") }
            for target in targets where Engines.engine(from: source, to: target) == nil {
                orphan.append("\(source.rawValue)→\(target.rawValue)")
            }
        }
        record("every offered conversion has an engine", orphan.isEmpty, orphan.joined(separator: ", "))

        // Images.
        for target in [FileFormat.jpg, .webp, .tiff, .bmp, .pdf, .heic, .avif] {
            await convert("image png→\(target.rawValue)", png, target, root) { out in
                magic(out, target) && size(out) > 0
            }
        }
        // Options: quality and the longest side.
        do {
            var low = ConvertOptions(); low.quality = 0.2
            var high = ConvertOptions(); high.quality = 1
            let a = await runOne(png, .jpg, root, low, tag: "lowq")
            let b = await runOne(png, .jpg, root, high, tag: "highq")
            if let a, let b { record("image quality changes size", size(a) < size(b), "q0.2=\(size(a)) q1=\(size(b))") }
            else { record("image quality changes size", false, "conversion failed") }
            var small = ConvertOptions(); small.maxLongEdge = 32
            if let out = await runOne(png, .jpg, root, small, tag: "edge"), let px = pixelSize(out) {
                record("image longest side 32", max(px.0, px.1) <= 32, "\(px.0)x\(px.1)")
            } else { record("image longest side 32", false, "no output") }
        }
        // Image → PDF → text-free PNG back.
        if let pdf = await runOne(png, .pdf, root, ConvertOptions(), tag: "topdf") {
            await convert("pdf →png", pdf, .png, root) { magic($0, .png) && size($0) > 0 }
        }
        // A PDF with real text reads back; a picture-only one needs OCR, which is a separate feature.
        if let textPDF = await runOne(txt, .pdf, root, ConvertOptions(), tag: "textpdf") {
            await convert("pdf (with text) →txt", textPDF, .txt, root) { (try? String(contentsOf: $0))?.contains("Hello from Vorssaint") == true }
        }

        // Documents and subtitles.
        await convert("txt →pdf", txt, .pdf, root) { magic($0, .pdf) }
        await convert("srt →vtt", srt, .vtt, root) { (try? String(contentsOf: $0))?.contains("WEBVTT") == true }
        if let vtt = await runOne(srt, .vtt, root, ConvertOptions(), tag: "v") {
            await convert("vtt →srt", vtt, .srt, root) { (try? String(contentsOf: $0))?.contains("-->") == true }
        }
        await convert("srt →txt", srt, .txt, root) { (try? String(contentsOf: $0))?.contains("Hello there") == true }

        // Audio (native where macOS can, else ffmpeg).
        await convert("audio wav→m4a", wav, .m4a, root) { magic($0, .m4a) }
        await convert("audio wav→aiff", wav, .aiff, root) { magic($0, .aiff) }
        if FFmpeg.isAvailable {
            for target in [FileFormat.mp3, .flac, .ogg, .opus] {
                await convert("audio wav→\(target.rawValue)", wav, target, root) { magic($0, target) && size($0) > 0 }
            }
            var low = ConvertOptions(); low.audioBitrate = 64_000
            var high = ConvertOptions(); high.audioBitrate = 256_000
            if let a = await runOne(wav, .mp3, root, low, tag: "br64"), let b = await runOne(wav, .mp3, root, high, tag: "br256") {
                record("audio bitrate changes size", size(a) < size(b), "64k=\(size(a)) 256k=\(size(b))")
            } else { record("audio bitrate changes size", false, "conversion failed") }
        } else { skip("audio via ffmpeg (mp3, flac, ogg, opus)", "no ffmpeg") }

        // Video: needs ffmpeg both to make the fixture and to convert.
        if let ffmpeg = FFmpeg.path {
            let mp4 = root.appendingPathComponent("clip.mp4")
            let made = try? await ConvertShell.run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=duration=2:size=320x240:rate=15",
                                                     "-f", "lavfi", "-i", "sine=frequency=440:duration=2", "-pix_fmt", "yuv420p", "-shortest", mp4.path])
            if made?.succeeded == true, size(mp4) > 0 {
                await convert("video mp4→gif", mp4, .gif, root) { magic($0, .gif) }
                await convert("video mp4→webm", mp4, .webm, root) { magic($0, .webm) }
                await convert("video mp4→mkv", mp4, .mkv, root) { magic($0, .mkv) }
                await convert("video mp4→mov", mp4, .mov, root) { magic($0, .mov) }
                await convert("video mp4→mp3 (extract audio)", mp4, .mp3, root) { magic($0, .mp3) }
                var tall = ConvertOptions(); tall.maxHeight = 120; tall.removeAudio = true
                for target in [FileFormat.mp4, .mkv, .webm] {
                    if let out = await runOne(mp4, target, root, tall, tag: "scaled") {
                        let probe = FFmpeg.probePath ?? "ffprobe"
                        let height = try? await ConvertShell.run(probe, ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=height", "-of", "csv=p=0", out.path])
                        let audio = try? await ConvertShell.run(probe, ["-v", "error", "-select_streams", "a", "-show_entries", "stream=codec_type", "-of", "csv=p=0", out.path])
                        let h = Int((height?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 9999
                        let hasAudio = !((audio?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        record("video options \(target.rawValue): 120p and no audio", h <= 120 && !hasAudio, "h=\(h) audio=\(hasAudio)")
                    } else { record("video options \(target.rawValue): 120p and no audio", false, "no output") }
                }
                var crfHigh = ConvertOptions(); crfHigh.videoCRF = 18
                var crfLow = ConvertOptions(); crfLow.videoCRF = 36
                if let a = await runOne(mp4, .mp4, root, crfHigh, tag: "crf18"), let b = await runOne(mp4, .mp4, root, crfLow, tag: "crf36") {
                    record("video quality option changes size (mp4)", size(b) < size(a), "crf18=\(size(a)) crf36=\(size(b))")
                } else { record("video quality option changes size (mp4)", false, "conversion failed") }
                var slow = ConvertOptions(); slow.gifFPS = 5; slow.gifWidth = 160
                var fast = ConvertOptions(); fast.gifFPS = 15; fast.gifWidth = 320
                if let a = await runOne(mp4, .gif, root, slow, tag: "g5"), let b = await runOne(mp4, .gif, root, fast, tag: "g15") {
                    record("gif options change size", size(a) < size(b), "5fps/160=\(size(a)) 15fps/320=\(size(b))")
                } else { record("gif options change size", false, "conversion failed") }
            } else { skip("video conversions", "could not make a test clip") }
        } else { skip("video conversions", "no ffmpeg") }

        await ocrChecks(root)
        await toolChecks(root, png: png, wav: wav, txt: txt)

        // The queue: two files, one failure, cancellation, never overwriting.
        await queueChecks(root, png)

        let failed = results.filter { $0.status == "FAIL" }.count
        let passed = results.filter { $0.status == "PASS" }.count
        let skipped = results.filter { $0.status == "SKIP" }.count
        print("\n\(passed) passed, \(failed) failed, \(skipped) skipped")
        return failed == 0
    }

    @MainActor
    private static func runOne(_ source: URL, _ target: FileFormat, _ root: URL, _ options: ConvertOptions, tag: String) async -> URL? {
        guard let format = FileFormat.detect(source) else { return nil }
        let destination = root.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(tag).\(target.fileExtension)")
        let request = ConversionRequest(source: source, sourceFormat: format, target: target, destination: destination,
                                        progress: { _ in }, options: options)
        do { try await Engines.convert(request); return destination } catch {
            print("      (\(source.lastPathComponent)→\(target.rawValue) \(tag): \(error.localizedDescription))")
            return nil
        }
    }

    @MainActor
    private static func convert(_ name: String, _ source: URL, _ target: FileFormat, _ root: URL, check: (URL) -> Bool) async {
        if let out = await runOne(source, target, root, ConvertOptions(), tag: "t-\(target.rawValue)") {
            record(name, check(out), "\(size(out)) bytes")
        } else {
            record(name, false, "conversion threw")
        }
    }

    // MARK: OCR

    private static func textImage(_ text: String, to url: URL) {
        let size = NSSize(width: 900, height: 220)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: size))
        (text as NSString).draw(at: NSPoint(x: 30, y: 60), withAttributes: [.font: NSFont.systemFont(ofSize: 96, weight: .bold), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    @MainActor
    private static func ocrChecks(_ root: URL) async {
        let image = root.appendingPathComponent("words.png")
        textImage("HELLO VORSSAINT", to: image)
        if let out = await runOne(image, .txt, root, ConvertOptions(), tag: "ocr") {
            let text = ((try? String(contentsOf: out)) ?? "").uppercased()
            record("OCR picture →txt", text.contains("HELLO") && text.contains("VORSSAINT"), "read: \(text.prefix(40))")
        } else { record("OCR picture →txt", false, "no output") }
        // A scanned PDF (picture only) reads through the same recognizer.
        if let scan = await runOne(image, .pdf, root, ConvertOptions(), tag: "scan"), let out = await runOne(scan, .txt, root, ConvertOptions(), tag: "scantxt") {
            record("OCR scanned PDF →txt", ((try? String(contentsOf: out)) ?? "").uppercased().contains("HELLO"))
        } else { record("OCR scanned PDF →txt", false, "no output") }
    }

    // MARK: Tools

    @MainActor
    private static func runTool(_ tool: ToolID, _ urls: [URL], _ edit: (inout ToolValues) -> Void = { _ in }) async -> (outputs: [URL], error: String?) {
        let runner = JobRunner.shared
        runner.dismissAll()
        let formats = urls.compactMap(FileFormat.detect)
        var values = ConvertTools.defaults(for: tool, formats: formats)
        edit(&values)
        ConvertToolRunner.run(tool, urls: urls, values: values)
        for _ in 0..<600 where runner.hasWork { try? await Task.sleep(nanoseconds: 100_000_000) }
        let outputs = runner.jobs.flatMap(\.outputs)
        var error: String?
        for job in runner.jobs { if case .failed(let text) = job.status { error = text } }
        return (outputs, error)
    }

    @MainActor
    private static func toolChecks(_ root: URL, png: URL, wav: URL, txt: URL) async {
        func check(_ name: String, _ tool: ToolID, _ urls: [URL], edit: (inout ToolValues) -> Void = { _ in }, ok: ([URL]) -> Bool) async {
            let result = await runTool(tool, urls, edit)
            record("tool \(name)", result.error == nil && ok(result.outputs), result.error ?? "\(result.outputs.count) output")
        }
        let photo = root.appendingPathComponent("tool-photo.png")
        try? FileManager.default.copyItem(at: png, to: photo)
        let words = root.appendingPathComponent("words.png")

        await check("resize image", .resizeImage, [photo], edit: { $0.s["edge"] = "48" }) { out in out.first.flatMap(pixelSize).map { max($0.0, $0.1) <= 48 } == true }
        await check("rotate image 90°", .rotateImage, [photo]) { _ in true }
        await check("crop image 4:3", .cropImage, [photo], edit: { $0.s["ratio"] = "1.3333" }) { out in
            out.first.flatMap(pixelSize).map { Double($0.0) / Double($0.1) > 1.2 } == true }
        await check("edit image", .editImage, [photo], edit: { $0.n["exposure"] = 0.5; $0.b["mono"] = true }) { out in out.first.map(size) ?? 0 > 0 }
        await check("add background", .frameImage, [photo], edit: { $0.s["bg"] = "sunset" }) { out in out.first.map(size) ?? 0 > 0 }
        await check("upscale 2×", .upscaleImage, [photo], edit: { $0.s["factor"] = "2" }) { out in out.first.flatMap(pixelSize).map { $0.0 == 192 } == true }
        await check("compress image", .compress, [photo], edit: { $0.s["preset"] = "strong" }) { out in out.first.map(size) ?? 0 > 0 }
        await check("redact text in picture", .redactImage, [words], edit: { $0.s["find"] = "text"; $0.s["style"] = "solid" }) { out in out.first.map(size) ?? 0 > 0 }
        await check("copy text (OCR)", .copyText, [words]) { _ in (NSPasteboard.general.string(forType: .string) ?? "").uppercased().contains("HELLO") }
        let second = root.appendingPathComponent("tool-photo2.png")
        try? FileManager.default.copyItem(at: png, to: second)
        await check("collage", .createCollage, [photo, second]) { out in out.first.map(size) ?? 0 > 0 }
        await check("images → PDF", .createPDF, [photo, second]) { out in out.first.flatMap { PDFDocument(url: $0)?.pageCount } == 2 }
        // Background removal needs a subject; a plain gradient has none, which must fail cleanly.
        let bg = await runTool(.removeBackground, [photo])
        record("tool remove background (runs; no subject is a clean error)", bg.error != nil || bg.outputs.first.map(size) ?? 0 > 0, bg.error ?? "ok")

        // PDFs.
        if let pdf1 = await runOne(photo, .pdf, root, ConvertOptions(), tag: "a"), let pdf2 = await runOne(second, .pdf, root, ConvertOptions(), tag: "b") {
            await check("merge PDFs", .mergePDF, [pdf1, pdf2]) { out in out.first.flatMap { PDFDocument(url: $0)?.pageCount } == 2 }
            if let merged = (await runTool(.mergePDF, [pdf1, pdf2])).outputs.first {
                await check("split PDF (each page)", .splitPDF, [merged]) { out in out.count == 2 }
                await check("organize PDF: reverse", .organizePDF, [merged], edit: { $0.s["op"] = "reverse" }) { out in out.first.flatMap { PDFDocument(url: $0)?.pageCount } == 2 }
                await check("organize PDF: remove page 1", .organizePDF, [merged], edit: { $0.s["op"] = "remove"; $0.s["pages"] = "1" }) { out in
                    out.first.flatMap { PDFDocument(url: $0)?.pageCount } == 1 }
                await check("compress PDF", .compress, [merged]) { out in out.first.map(size) ?? 0 > 0 }
                await check("PDF metadata clean", .editMetadata, [merged]) { out in out.first.map(size) ?? 0 > 0 }
            }
        }
        await check("image metadata clean", .editMetadata, [photo]) { out in out.first.map(size) ?? 0 > 0 }

        // Audio.
        await check("trim audio", .trimAudio, [wav], edit: { $0.n["start"] = 0.2; $0.n["end"] = 1.0 }) { out in out.first.map(size) ?? 0 > 0 }
        if FFmpeg.isAvailable {
            await check("normalize audio", .normalizeAudio, [wav]) { out in out.first.map(size) ?? 0 > 0 }
            await check("audio to mono", .audioChannels, [wav], edit: { $0.s["mode"] = "mono" }) { out in out.first.map(size) ?? 0 > 0 }
            await check("bleep audio", .redactAudio, [wav], edit: { $0.s["ranges"] = "0:00-0:01" }) { out in out.first.map(size) ?? 0 > 0 }
            await check("audio visualizer", .audioToVideo, [wav]) { out in out.first.map(size) ?? 0 > 0 }

            // Video tools.
            let mp4 = root.appendingPathComponent("tool-clip.mp4")
            if let ffmpeg = FFmpeg.path,
               (try? await ConvertShell.run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=duration=6:size=320x240:rate=15",
                                                     "-f", "lavfi", "-i", "sine=frequency=440:duration=6", "-pix_fmt", "yuv420p", "-shortest", mp4.path]))?.succeeded == true {
                await check("trim video", .trimVideo, [mp4], edit: { $0.n["start"] = 1; $0.n["end"] = 3 }) { out in out.first.map(size) ?? 0 > 0 }
                await check("change video speed 2×", .changeVideoSpeed, [mp4], edit: { $0.s["factor"] = "2" }) { out in out.first.map(size) ?? 0 > 0 }
                await check("crop video 1:1", .cropVideo, [mp4]) { out in out.first.map(size) ?? 0 > 0 }
                await check("save video frames", .videoSnapshots, [mp4], edit: { $0.s["interval"] = "1"; $0.n["max"] = 4 }) { out in
                    out.first.map { ((try? FileManager.default.contentsOfDirectory(atPath: $0.path))?.count) ?? 0 } == 4 }
                await check("split video", .splitVideo, [mp4], edit: { $0.s["every"] = "2" }) { out in out.count >= 2 }
                let mp4b = root.appendingPathComponent("tool-clip2.mp4")
                try? FileManager.default.copyItem(at: mp4, to: mp4b)
                await check("join videos", .joinVideos, [mp4, mp4b]) { out in out.first.map(size) ?? 0 > 0 }
                await check("compress video", .compress, [mp4], edit: { $0.s["preset"] = "strong" }) { out in out.first.map(size) ?? 0 > 0 }
            } else { skip("video tools", "could not make a test clip") }
        } else { skip("audio and video tools needing ffmpeg", "no ffmpeg") }

        // Archives, including one that tries to escape its folder.
        let dir = root.appendingPathComponent("zipsrc")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "inside".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let zip = root.appendingPathComponent("bundle.zip")
        _ = try? await ConvertShell.run("/usr/bin/zip", ["-r", "-X", "-q", zip.path, "."], currentDirectory: dir)
        await check("archive zip →tar", .extractArchive, [zip]) { out in out.first.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("a.txt").path) } == true }
        if let tar = await runOne(zip, .tar, root, ConvertOptions(), tag: "ar"), let back = await runOne(tar, .zip, root, ConvertOptions(), tag: "back") {
            record("archive zip →tar →zip", magicZip(back) && size(tar) > 0)
        } else { record("archive zip →tar →zip", false, "conversion failed") }
        let evil = root.appendingPathComponent("evil.zip")
        let script = "import zipfile,sys\nz=zipfile.ZipFile(sys.argv[1],'w')\nz.writestr('../escaped.txt','x')\nz.writestr('ok.txt','y')\nz.close()"
        _ = try? await ConvertShell.run("/usr/bin/python3", ["-c", script, evil.path])
        do {
            _ = try await ArchiveSafety.extractSafely(evil)
            record("archive path traversal refused", false, "it was opened")
        } catch {
            record("archive path traversal refused", !FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escaped.txt").path), "\(error.localizedDescription.prefix(60))")
        }

        // File actions.
        let copy = root.appendingPathComponent("action-source.txt")
        try? "act".write(to: copy, atomically: true, encoding: .utf8)
        _ = ConvertAction.paths.run([copy])
        record("action copy paths", NSPasteboard.general.string(forType: .string) == copy.path)
        JobRunner.shared.dismissAll()
        _ = ConvertAction.duplicate.run([copy])
        for _ in 0..<100 where JobRunner.shared.hasWork { try? await Task.sleep(nanoseconds: 100_000_000) }
        record("action duplicate", JobRunner.shared.jobs.first?.outputs.first.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        JobRunner.shared.dismissAll()
        _ = ConvertAction.zip.run([copy])
        for _ in 0..<100 where JobRunner.shared.hasWork { try? await Task.sleep(nanoseconds: 100_000_000) }
        record("action zip", JobRunner.shared.jobs.first?.outputs.first.map { magicZip($0) } == true)
        JobRunner.shared.dismissAll()
        _ = ConvertAction.hash.run([copy])
        for _ in 0..<100 where JobRunner.shared.hasWork { try? await Task.sleep(nanoseconds: 100_000_000) }
        record("action SHA-256", (NSPasteboard.general.string(forType: .string) ?? "").contains("action-source.txt"))
        JobRunner.shared.dismissAll()
    }

    private static func magicZip(_ url: URL) -> Bool { header(url).starts(with: [0x50, 0x4B]) }

    @MainActor
    private static func queueChecks(_ root: URL, _ png: URL) async {
        let runner = JobRunner.shared
        runner.dismissAll()
        let sourceHash = try? Data(contentsOf: png).hashValue
        let missing = root.appendingPathComponent("gone.png")
        runner.convert([png, missing], to: .jpg)
        runner.convert([png], to: .jpg) // a second request for the same name must not overwrite the first
        for _ in 0..<200 where runner.hasWork { try? await Task.sleep(nanoseconds: 100_000_000) }
        let done = runner.jobs.filter { $0.status == .done }
        let failed = runner.jobs.filter { if case .failed = $0.status { return true } else { return false } }
        record("queue: two good jobs and one failure", done.count == 2 && failed.count == 1, "done=\(done.count) failed=\(failed.count)")
        let names = Set(done.flatMap(\.outputs).map(\.lastPathComponent))
        record("queue: names never collide", names.count == 2, names.sorted().joined(separator: ", "))
        record("queue: source untouched", (try? Data(contentsOf: png).hashValue) == sourceHash)
        record("queue: progress reaches 100%", done.allSatisfy { $0.progress == 1 })
        runner.dismissAll()
        // Cancel: a long ffmpeg job stops and leaves no staged file behind.
        if let ffmpeg = FFmpeg.path {
            let long = root.appendingPathComponent("long.mp4")
            let made = try? await ConvertShell.run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=duration=40:size=640x480:rate=30",
                                                     "-pix_fmt", "yuv420p", long.path])
            if made?.succeeded == true {
                runner.convert([long], to: .webm)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let sawProgress = runner.jobs.first.map { $0.progress > 0 || $0.status == .running } ?? false
                runner.cancelAll()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let leftovers = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasPrefix(".opentangerine-") }
                record("cancel: long job starts and stops cleanly", sawProgress && leftovers.isEmpty, "running=\(sawProgress) leftovers=\(leftovers.count)")
            }
        }
    }
}
