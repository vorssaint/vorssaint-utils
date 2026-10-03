// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO

enum ClipboardOptimizerFileTests {
    typealias Support = ClipboardImageOptimizerSupport
    typealias Files = ClipboardOptimizerFileSupport

    static let root = URL(fileURLWithPath: "/tmp/VorssaintTest/ClipboardOptimizer", isDirectory: true)
    static let finderTypes = ["public.file-url", "public.utf8-plain-text", "com.apple.icns", "public.tiff"]

    static func snapshot(_ url: URL, types: [String] = finderTypes, changeCount: Int = 9) -> PasteboardImageSnapshot {
        PasteboardImageSnapshot(changeCount: changeCount, itemCount: 1, types: types, fileURLs: [url])
    }

    /// The app registers these globally; a test suite gets them written in,
    /// since registering would leak into every other test's defaults.
    static func seedRegistered(_ defaults: UserDefaults) {
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("clipboardOptimizer")
            || key.hasPrefix("clipboardImageOptimizer") {
            defaults.set(value, forKey: key)
        }
    }

    static func run(_ suite: TestSuite) {
        eligibility(suite)
        upgrade(suite)
        options(suite)
        gates(suite)
        pdfFilter(suite)
        pdfTraits(suite)
        imageTraits(suite)
        conversion(suite)
        outputs(suite)
        sweep(suite)
        history(suite)
        commit(suite)
    }

    static func eligibility(_ suite: TestSuite) {
        let all = Support.Scope(images: true, imageFiles: true, convertImages: true, videos: true, pdfs: true,
                                outputRoot: root)
        func check(_ snap: PasteboardImageSnapshot, scope: Support.Scope = all,
                   _ expected: Support.Eligibility, _ label: String) {
            let actual = Support.eligibility(snap, lastOwnWrite: nil, scope: scope)
            suite.expect(actual == expected, "\(label): got \(actual)")
        }
        let mov = URL(fileURLWithPath: "/Users/me/Movies/Clip.MOV")
        let mp4 = URL(fileURLWithPath: "/Users/me/a.mp4")
        let m4v = URL(fileURLWithPath: "/Users/me/a.m4v")
        let pdf = URL(fileURLWithPath: "/Users/me/Doc.pdf")
        let heic = URL(fileURLWithPath: "/Users/me/IMG_1.HEIC")
        check(snapshot(mov), .eligible(.video(mov)), "a copied MOV is a video job")
        check(snapshot(mp4), .eligible(.video(mp4)), "a copied MP4 is a video job")
        check(snapshot(m4v), .eligible(.video(m4v)), "a copied M4V is a video job")
        check(snapshot(pdf), .eligible(.pdf(pdf)), "a copied PDF is a PDF job")
        check(snapshot(heic), .eligible(.convertedImage(heic, uti: "public.heic")), "a copied HEIC is converted")
        for ext in ["webp", "avif", "bmp", "heif"] {
            let url = URL(fileURLWithPath: "/Users/me/x.\(ext)")
            let result = Support.eligibility(snapshot(url), lastOwnWrite: nil, scope: all)
            suite.expect(result == .eligible(.convertedImage(url, uti: Files.convertibleImageUTIs[ext]!)),
                         "a copied \(ext) is converted: \(result)")
        }
        for ext in ["mkv", "webm", "avi", "mpg", "mpeg", "gif", "jxl", "txt"] {
            check(snapshot(URL(fileURLWithPath: "/Users/me/x.\(ext)")), .skip(.notImage),
                  "\(ext) is not something the optimizer can do")
        }
        var noVideo = all
        noVideo.videos = false
        check(snapshot(mov), scope: noVideo, .skip(.kindDisabled), "videos stay alone when their switch is off")
        var noPDF = all
        noPDF.pdfs = false
        check(snapshot(pdf), scope: noPDF, .skip(.kindDisabled), "PDFs stay alone when their switch is off")
        var noConvert = all
        noConvert.convertImages = false
        check(snapshot(heic), scope: noConvert, .skip(.kindDisabled), "HEIC stays alone without conversion")
        var noImageFiles = all
        noImageFiles.imageFiles = false
        check(snapshot(heic), scope: noImageFiles, .skip(.filesDisabled), "conversion needs image files on")
        check(snapshot(mov), scope: noImageFiles, .eligible(.video(mov)), "videos do not depend on image files")
        var noImages = all
        noImages.images = false
        check(PasteboardImageSnapshot(changeCount: 3, itemCount: 1, types: ["public.png"], fileURLs: []),
              scope: noImages, .skip(.kindDisabled), "a bitmap stays alone when images are off")
        check(snapshot(URL(fileURLWithPath: "/Users/me/a.png")), scope: noImages, .skip(.kindDisabled),
              "an image file stays alone when images are off")
        check(snapshot(mov, types: finderTypes + ["org.nspasteboard.TransientType"]), .skip(.sensitive),
              "a transient file copy is left alone")
        check(PasteboardImageSnapshot(changeCount: 3, itemCount: 2, types: finderTypes,
                                      fileURLs: [mov, pdf]), .skip(.multipleItems),
              "several files are left alone")
        let own = root.appendingPathComponent("A1/Clip.mov")
        check(snapshot(own), .skip(.ownWrite), "our own output is never optimized again")
        check(snapshot(URL(fileURLWithPath: "/tmp/VorssaintTest/ClipboardOptimizerX/a.mov")),
              .eligible(.video(URL(fileURLWithPath: "/tmp/VorssaintTest/ClipboardOptimizerX/a.mov"))),
              "a sibling folder with a similar name is not ours")
    }

    /// Someone who set the image optimizer up before videos and PDFs existed
    /// keeps exactly what they had.
    static func upgrade(_ suite: TestSuite) {
        let defaults = UserDefaults(suiteName: "vorss.tests.clipboardOptimizer.upgrade")!
        defaults.removePersistentDomain(forName: "vorss.tests.clipboardOptimizer.upgrade")
        seedRegistered(defaults)
        defaults.set(true, forKey: DefaultsKey.clipboardImageOptimizerEnabled)
        defaults.set(true, forKey: DefaultsKey.clipboardImageOptimizerIncludeFiles)
        let scope = Support.Scope.fromDefaults(defaults, outputRoot: root)
        suite.expect(scope.images && scope.imageFiles, "images and image files keep working after upgrade")
        suite.expect(!scope.videos && !scope.pdfs && !scope.convertImages,
                     "videos, PDFs and conversion start off after upgrade")
        let png = URL(fileURLWithPath: "/Users/me/a.png")
        suite.expect(Support.eligibility(snapshot(png), lastOwnWrite: nil, scope: scope)
                     == .eligible(.file(png, uti: "public.png")),
                     "a copied PNG file is handled as before")
        suite.expect(Support.eligibility(snapshot(png), lastOwnWrite: nil, includeFiles: true)
                     == .eligible(.file(png, uti: "public.png")),
                     "the older entry point keeps its meaning")
        defaults.removePersistentDomain(forName: "vorss.tests.clipboardOptimizer.upgrade")
    }

    static func options(_ suite: TestSuite) {
        let video = Files.VideoOptions.sanitized(codec: "vp9", quality: 7, maxDimension: 1234,
                                                 removeAudio: true, maxMB: 3, maxMinutes: 999)
        suite.expect(video.codec == .hevc, "an unknown codec falls back to HEVC")
        suite.expect(video.quality == 1, "video quality is clamped")
        suite.expect(video.maxDimension == Files.VideoOptions.defaultMaxDimension,
                     "an unknown video size falls back to the default")
        suite.expect(video.maxMB == Files.VideoOptions.defaultMaxMB, "an unknown size cap falls back")
        suite.expect(video.maxMinutes == Files.VideoOptions.defaultMaxMinutes, "an unknown duration cap falls back")
        suite.expect(video.removeAudio, "remove audio is kept")
        suite.expect(Files.VideoOptions.sanitized(codec: "hevc", quality: 0.6, maxDimension: 1280, removeAudio: false,
                                                  maxMB: 500, maxMinutes: 15).maxDimension == 1920,
                     "HEVC has no 1280 preset, so that choice falls back")
        let h264 = Files.VideoOptions.sanitized(codec: "h264", quality: 0.5, maxDimension: 1280,
                                                removeAudio: false, maxMB: 2000, maxMinutes: 60)
        suite.expect(h264 == Files.VideoOptions(codec: .h264, quality: 0.5, maxDimension: 1280,
                                                removeAudio: false, maxMB: 2000, maxMinutes: 60),
                     "valid video choices are kept")
        suite.expect(Files.VideoOptions.sanitized(codec: nil, quality: .nan, maxDimension: nil, removeAudio: false,
                                                  maxMB: nil, maxMinutes: nil).quality
                     == Files.VideoOptions.defaultQuality, "a missing video quality uses the default")
        let pdf = Files.PDFOptions.sanitized(dpi: 7, quality: -1, maxMB: 12)
        suite.expect(pdf == Files.PDFOptions(dpi: Files.PDFOptions.defaultDPI, quality: 0.1,
                                             maxMB: Files.PDFOptions.defaultMaxMB),
                     "PDF choices snap to the lists: \(pdf)")
        suite.expect(Files.PDFOptions.sanitized(dpi: 72, quality: 0.5, maxMB: 250)
                     == Files.PDFOptions(dpi: 72, quality: 0.5, maxMB: 250), "valid PDF choices are kept")

        let defaults = UserDefaults(suiteName: "vorss.tests.clipboardOptimizer.options")!
        defaults.removePersistentDomain(forName: "vorss.tests.clipboardOptimizer.options")
        seedRegistered(defaults)
        suite.expect(Files.VideoOptions.fromDefaults(defaults) == Files.VideoOptions(
            codec: .hevc, quality: Files.VideoOptions.defaultQuality,
            maxDimension: Files.VideoOptions.defaultMaxDimension, removeAudio: false,
            maxMB: Files.VideoOptions.defaultMaxMB, maxMinutes: Files.VideoOptions.defaultMaxMinutes),
            "registered video defaults are the documented ones")
        suite.expect(Files.PDFOptions.fromDefaults(defaults) == Files.PDFOptions(
            dpi: Files.PDFOptions.defaultDPI, quality: Files.PDFOptions.defaultQuality,
            maxMB: Files.PDFOptions.defaultMaxMB), "registered PDF defaults are the documented ones")
        for key in [DefaultsKey.clipboardOptimizerImages, DefaultsKey.clipboardOptimizerVideos,
                    DefaultsKey.clipboardOptimizerPDFs, DefaultsKey.clipboardOptimizerConvertImages,
                    DefaultsKey.clipboardOptimizerVideoCodec, DefaultsKey.clipboardOptimizerVideoQuality,
                    DefaultsKey.clipboardOptimizerVideoMaxDimension, DefaultsKey.clipboardOptimizerVideoRemoveAudio,
                    DefaultsKey.clipboardOptimizerVideoMaxMB, DefaultsKey.clipboardOptimizerVideoMaxMinutes,
                    DefaultsKey.clipboardOptimizerPDFDPI, DefaultsKey.clipboardOptimizerPDFQuality,
                    DefaultsKey.clipboardOptimizerPDFMaxMB] {
            suite.expect(Defaults.registeredDefaults[key] != nil, "\(key) is a registered default, so backup includes it")
        }
        defaults.removePersistentDomain(forName: "vorss.tests.clipboardOptimizer.options")
    }

    static func pdfFilter(_ suite: TestSuite) {
        let filter = Files.pdfFilter(Files.PDFOptions(dpi: 100, quality: 0.55, maxMB: 100)) as NSDictionary
        suite.expect(filter.value(forKeyPath: "FilterData.ColorSettings.ImageSettings.ImageScaleSettings.ImageResolution")
                     as? Int == 100, "the filter resamples images to the chosen DPI")
        suite.expect(filter.value(forKeyPath: "FilterData.ColorSettings.ImageSettings.Compression Quality")
                     as? Double == 0.55, "the filter uses the chosen quality")
        suite.expect(filter.value(forKeyPath: "FilterData.ColorSettings.ImageSettings.ImageCompression")
                     as? String == "ImageJPEGCompress", "images are stored as JPEG")
        suite.expect(PropertyListSerialization.propertyList(filter, isValidFor: .xml),
                     "the filter is a valid property list")
    }

    static func gates(_ suite: TestSuite) {
        let mb: Int64 = 1024 * 1024
        suite.expect(Files.sizeGate(bytes: 0, capMB: 100) == .empty, "an empty file is skipped")
        suite.expect(Files.sizeGate(bytes: 100 * mb, capMB: 100) == .ok, "the cap itself is allowed")
        suite.expect(Files.sizeGate(bytes: 100 * mb + 1, capMB: 100) == .tooLarge, "over the cap is skipped")
        suite.expect(Files.durationGate(seconds: 900, capMinutes: 15) == .ok, "the duration cap is allowed")
        suite.expect(Files.durationGate(seconds: 900.5, capMinutes: 15) == .tooLong, "longer is skipped")
        suite.expect(Files.durationGate(seconds: .nan, capMinutes: 15) == .tooLong, "an unknown duration is skipped")
        suite.expect(Files.durationGate(seconds: 0, capMinutes: 15) == .tooLong, "a zero duration is skipped")
        let gb: Int64 = 1024 * mb
        suite.expect(Files.hasRoom(freeBytes: gb, sourceBytes: 10 * mb), "1 GB free is enough for a small file")
        suite.expect(!Files.hasRoom(freeBytes: gb - 1, sourceBytes: 10 * mb), "under 1 GB free is never enough")
        suite.expect(Files.hasRoom(freeBytes: 4 * gb, sourceBytes: 2 * gb), "twice the source is enough")
        suite.expect(!Files.hasRoom(freeBytes: 4 * gb - 1, sourceBytes: 2 * gb), "less than twice is not")
        suite.expect(Files.hasRoom(freeBytes: nil, sourceBytes: 1) == false, "an unknown free space is not enough")
        suite.expect(Files.isAvailableLocally(dataless: false, ubiquitous: false, downloaded: nil),
                     "a plain local file is readable")
        suite.expect(!Files.isAvailableLocally(dataless: true, ubiquitous: false, downloaded: nil),
                     "a dataless file is never read, which would download it")
        suite.expect(!Files.isAvailableLocally(dataless: false, ubiquitous: true, downloaded: false),
                     "an iCloud placeholder is never read")
        suite.expect(Files.isAvailableLocally(dataless: false, ubiquitous: true, downloaded: true),
                     "a downloaded iCloud file is fine")
        suite.expect(Files.validVideo(sourceDuration: 10, outputDuration: 9.6, hasVideo: true),
                     "an output within half a second is complete")
        suite.expect(!Files.validVideo(sourceDuration: 10, outputDuration: 9.4, hasVideo: true),
                     "a truncated output is rejected")
        suite.expect(!Files.validVideo(sourceDuration: 10, outputDuration: 10, hasVideo: false),
                     "an output without video is rejected")
    }

    static func pdfTraits(_ suite: TestSuite) {
        suite.expect(!Files.PDFTraits().leavesAlone, "a plain PDF is optimized")
        let flags: [(WritableKeyPath<Files.PDFTraits, Bool>, String)] = [
            (\.encrypted, "encrypted"), (\.signed, "signed"), (\.permissions, "permission-locked"),
            (\.tagged, "tagged"), (\.xfa, "XFA form"), (\.embeddedFiles, "attachments"),
            (\.javaScript, "scripted"),
        ]
        for (flag, name) in flags {
            var traits = Files.PDFTraits()
            traits[keyPath: flag] = true
            suite.expect(traits.leavesAlone, "a \(name) PDF is left alone")
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardOptimizerFileTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = dir.appendingPathComponent("plain.pdf")
        let locked = dir.appendingPathComponent("locked.pdf")
        makePDF(plain, info: [:])
        makePDF(locked, info: [kCGPDFContextOwnerPassword as String: "owner",
                               kCGPDFContextAllowsCopying as String: false])
        let plainTraits = CGPDFDocument(plain as CFURL).map(Files.PDFTraits.read)
        suite.expect(plainTraits == Files.PDFTraits(), "a generated plain PDF reads as plain: \(String(describing: plainTraits))")
        let lockedTraits = CGPDFDocument(locked as CFURL).map(Files.PDFTraits.read)
        suite.expect(lockedTraits?.encrypted == true, "an owner-password PDF reads as encrypted")
    }

    static func makePDF(_ url: URL, info: [String: Any]) {
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { return }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 50, height: 50))
        context.endPDFPage()
        context.closePDF()
    }

    static func imageTraits(_ suite: TestSuite) {
        suite.expect(!Files.ImageTraits(frameCount: 1, bitsPerComponent: 8, hdrTransfer: false,
                                        auxiliaryData: false).leavesAlone, "an ordinary image is optimized")
        suite.expect(Files.ImageTraits(frameCount: 2, bitsPerComponent: 8, hdrTransfer: false,
                                       auxiliaryData: false).leavesAlone, "an animation is never flattened")
        suite.expect(Files.ImageTraits(frameCount: 1, bitsPerComponent: 16, hdrTransfer: false,
                                       auxiliaryData: false).leavesAlone, "a 16-bit image keeps its depth")
        suite.expect(Files.ImageTraits(frameCount: 1, bitsPerComponent: 8, hdrTransfer: true,
                                       auxiliaryData: false).leavesAlone, "an HDR image keeps its range")
        suite.expect(Files.ImageTraits(frameCount: 1, bitsPerComponent: 8, hdrTransfer: false,
                                       auxiliaryData: true).leavesAlone, "a gain map or depth map is kept")

        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = context.makeImage()!
        let still = NSMutableData()
        let stillDestination = CGImageDestinationCreateWithData(still, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(stillDestination, image, nil)
        CGImageDestinationFinalize(stillDestination)
        let animated = NSMutableData()
        let animatedDestination = CGImageDestinationCreateWithData(animated, "public.png" as CFString, 2, nil)!
        CGImageDestinationAddImage(animatedDestination, image, nil)
        CGImageDestinationAddImage(animatedDestination, image, nil)
        CGImageDestinationFinalize(animatedDestination)
        let stillTraits = CGImageSourceCreateWithData(still, nil).flatMap(Files.ImageTraits.read)
        suite.expect(stillTraits?.leavesAlone == false, "a still PNG reads as optimizable: \(String(describing: stillTraits))")
        let animatedTraits = CGImageSourceCreateWithData(animated, nil).flatMap(Files.ImageTraits.read)
        suite.expect(animatedTraits?.frameCount == 2, "an animated PNG reads as animated")
    }

    static func image(width: Int, height: Int, alpha: Bool, type: String, frames: Int = 1) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast
                                                   : CGImageAlphaInfo.noneSkipLast).rawValue)!
        for x in stride(from: 0, to: width, by: 4) {
            context.setFillColor(CGColor(red: CGFloat(x % 255) / 255, green: 0.4, blue: 0.2,
                                         alpha: alpha ? 0.5 : 1))
            context.fill(CGRect(x: x, y: 0, width: 4, height: height))
        }
        let picture = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type as CFString, frames, nil)!
        for _ in 0..<frames { CGImageDestinationAddImage(destination, picture, nil) }
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func conversion(_ suite: TestSuite) {
        let options = Support.Options.sanitized(format: "keep", quality: 0.7, maxDimension: 0, halveRetina: false,
                                                includeFiles: true)
        let opaque = image(width: 64, height: 40, alpha: false, type: "com.microsoft.bmp")
        let converted = ClipboardImageOptimizerEncoding.convert(data: opaque, options: options, isCancelled: { false })
        suite.expect(converted?.type == "public.jpeg" && converted?.longEdge == 64,
                     "an opaque BMP becomes a full-size JPEG: \(String(describing: converted?.type))")
        let clear = image(width: 64, height: 40, alpha: true, type: "public.tiff")
        suite.expect(ClipboardImageOptimizerEncoding.convert(data: clear, options: options,
                                                             isCancelled: { false })?.type == "public.png",
                     "an image with transparency becomes PNG, never JPEG")
        let limited = Support.Options.sanitized(format: "keep", quality: 0.7, maxDimension: 1600, halveRetina: true,
                                                includeFiles: true)
        suite.expect(ClipboardImageOptimizerEncoding.convert(data: opaque, options: limited,
                                                             isCancelled: { false })?.longEdge == 32,
                     "conversion honors the resize options")
        let animated = image(width: 16, height: 16, alpha: false, type: "public.png", frames: 3)
        suite.expect(ClipboardImageOptimizerEncoding.convert(data: animated, options: options,
                                                             isCancelled: { false }) == nil,
                     "an animation is never flattened into one frame")
        suite.expect(ClipboardImageOptimizerEncoding.optimize(data: animated, sourceType: "public.png",
                                                              options: options, isCancelled: { false }) == nil,
                     "an animated PNG on the clipboard is left alone")
        suite.expect(ClipboardImageOptimizerEncoding.convert(data: opaque, options: options,
                                                             isCancelled: { true }) == nil,
                     "a cancelled conversion yields nothing")
    }

    static func outputs(_ suite: TestSuite) {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let mov = Files.outputURL(root: root, id: id, source: URL(fileURLWithPath: "/Users/me/My Clip.mov"),
                                  outputExtension: nil)
        suite.expect(mov.path == root.path + "/11111111-2222-3333-4444-555555555555/My Clip.mov",
                     "an output keeps its exact name: \(mov.path)")
        let heic = Files.outputURL(root: root, id: id, source: URL(fileURLWithPath: "/Users/me/IMG.HEIC"),
                                   outputExtension: "jpg")
        suite.expect(heic.lastPathComponent == "IMG.jpg", "a conversion only changes the extension")
        let odd = Files.outputURL(root: root, id: id, source: URL(fileURLWithPath: "/.."), outputExtension: nil)
        suite.expect(odd.deletingLastPathComponent().lastPathComponent == id.uuidString
                     && !odd.lastPathComponent.isEmpty && odd.lastPathComponent != "..",
                     "a strange name never leaves the job folder: \(odd.path)")
        let partial = Files.partialURL(for: mov)
        suite.expect(partial.deletingLastPathComponent() == mov.deletingLastPathComponent()
                     && partial.pathExtension == "mov" && partial != mov,
                     "the partial file sits next to the output with the same extension")
        suite.expect(Files.isOwnOutput(mov, root: root), "a job output is recognized as ours")
        suite.expect(!Files.isOwnOutput(URL(fileURLWithPath: "/Users/me/My Clip.mov"), root: root),
                     "a user file is not ours")
    }

    static func sweep(_ suite: TestSuite) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let mb: Int64 = 1024 * 1024
        func job(_ name: String, hoursAgo: Double, mb size: Int64 = 1) -> Files.StoredJob {
            Files.StoredJob(url: root.appendingPathComponent(name),
                            created: now.addingTimeInterval(-hoursAgo * 3600), bytes: size * mb)
        }
        func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent).sorted() }
        let policy = Files.SweepPolicy(maxAge: 24 * 3600, keepNewest: 5, maxTotalBytes: 2048 * mb)
        let jobs = (0..<8).map { job("j\($0)", hoursAgo: Double($0) * 10) }
        suite.expect(names(Files.sweepCandidates(jobs, now: now, protected: [], referenced: [], policy: policy))
                     == ["j5", "j6", "j7"], "only old jobs beyond the newest five go")
        let inHistory = [root.appendingPathComponent("j7/Clip.mov").path]
        suite.expect(names(Files.sweepCandidates(jobs, now: now, protected: [], referenced: Set(inHistory),
                                                 policy: policy)) == ["j5", "j6"],
                     "a job history still points at survives the age sweep")
        suite.expect(names(Files.sweepCandidates(jobs, now: now, protected: Set(inHistory), referenced: [],
                                                 policy: policy)) == ["j5", "j6"],
                     "a protected job survives the age sweep")
        let young = (0..<9).map { job("y\($0)", hoursAgo: 1) }
        suite.expect(Files.sweepCandidates(young, now: now, protected: [], referenced: [], policy: policy).isEmpty,
                     "recent small jobs are never swept")

        let big = [job("b0", hoursAgo: 1, mb: 900), job("b1", hoursAgo: 2, mb: 900), job("b2", hoursAgo: 3, mb: 900)]
        let current = root.appendingPathComponent("b2/Movie.mov").path
        suite.expect(names(Files.sweepCandidates(big, now: now, protected: [], referenced: [], policy: policy))
                     == ["b2"], "over the total cap the oldest job goes, even if recent")
        suite.expect(names(Files.sweepCandidates(big, now: now, protected: [current], referenced: [],
                                                 policy: policy)) == ["b1"],
                     "the cap never removes what the clipboard holds, it takes the next oldest")
        suite.expect(names(Files.sweepCandidates(big, now: now, protected: [],
                                                 referenced: [root.appendingPathComponent("b2/M.mov").path],
                                                 policy: policy)) == ["b2"],
                     "unpinned history does not hold a job over the cap")
        suite.expect(names(Files.clearCandidates(big, protected: [current])) == ["b0", "b1"],
                     "clearing keeps only what the clipboard or a pin still needs")
    }

    static func history(_ suite: TestSuite) {
        let original = ["/Users/me/Clip.mov"]
        let optimized = [root.appendingPathComponent("A/Clip.mov").path]
        let recent = ClipboardHistoryEntry(text: "", kind: .files, filePaths: original)
        let older = ClipboardHistoryEntry(text: "older")
        var result = ClipboardHistoryRewrite.apply([recent, older], from: original, to: optimized)
        suite.expect(result.map(\.filePaths) == [optimized, []] && result.first?.id == recent.id,
                     "the newest entry is repointed at the smaller copy")
        let captured = ClipboardHistoryEntry(text: "", kind: .files, filePaths: optimized)
        result = ClipboardHistoryRewrite.apply([captured, recent, older], from: original, to: optimized)
        suite.expect(result.count == 2 && result.first?.filePaths == optimized && result.first?.id == recent.id
                     && result.first?.copiedAt == recent.copiedAt
                     && result.filter { $0.filePaths == original }.isEmpty,
                     "a copy history already recorded is merged, leaving one entry")
        let pinned = ClipboardHistoryEntry(text: "", pinnedAt: Date(), kind: .files, filePaths: original)
        result = ClipboardHistoryRewrite.apply([pinned, older], from: original, to: optimized)
        suite.expect(result.map(\.filePaths) == [original, []], "a pinned original is never repointed")
        result = ClipboardHistoryRewrite.apply([older, recent], from: original, to: optimized)
        suite.expect(result.map(\.filePaths) == [[], original], "an older copy of the same file is left alone")
        result = ClipboardHistoryRewrite.apply([older], from: original, to: optimized)
        suite.expect(result == [older], "with no entry for the original, history is left unchanged")

        let repointed = ClipboardHistoryRewrite.apply([recent, older], from: original, to: optimized)
        let pinnedCopy = ClipboardHistoryEntry(text: "", pinnedAt: Date(), kind: .files, filePaths: optimized)
        result = ClipboardHistoryRewrite.restore(repointed + [pinnedCopy], originals: [optimized[0]: original[0]])
        suite.expect(result.map(\.filePaths) == [original, [], optimized] && result.first?.id == recent.id,
                     "clearing a copy points its unpinned entry back at the original")
    }

    static func commit(_ suite: TestSuite) {
        func accepts(generation: Int = 2, enabled: Bool = true, pasteboard: Int = 5) -> Bool {
            OptimizationCommit.accepts(generation: generation, current: 2, enabled: enabled, kindEnabled: true,
                                       pasteboardChangeCount: pasteboard, snapshotChangeCount: 5)
        }
        suite.expect(!accepts(generation: 1), "a result from before a restart is dropped")
        suite.expect(!accepts(enabled: false), "a result after the feature was turned off is dropped")
        suite.expect(!accepts(pasteboard: 6), "a result for a clipboard that changed is dropped")
        suite.expect(OptimizationCommit.accepts(generation: 2, current: 2, enabled: true, kindEnabled: true,
                                                pasteboardChangeCount: 5, snapshotChangeCount: 5),
                     "an unchanged clipboard takes the result")
        suite.expect(!OptimizationCommit.accepts(generation: 2, current: 2, enabled: true, kindEnabled: false,
                                                 pasteboardChangeCount: 5, snapshotChangeCount: 5),
                     "a type switched off meanwhile drops the result")
    }
}
