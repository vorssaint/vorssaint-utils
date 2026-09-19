// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum MediaFeatureTests {
    static func run(_ suite: TestSuite) {
        suite.expect(MediaImageFormat.sanitized("pdf") == .pdf,
               "Image converter accepts the PDF format")
        suite.expect(MediaImageFormat.pdf.fileExtension == "pdf",
               "PDF output uses the pdf file extension")
        suite.expect(MediaImageFormat.sanitized("bmp") == .jpeg,
               "Unknown image format falls back to JPEG")
        suite.expect(MediaImageResizeKind.sanitized("height") == .height,
               "Image resize mode accepts height")
        suite.expect(MediaImageResizeKind.sanitized("wild") == .maxDimension,
               "Unknown image resize mode falls back to max side")
        suite.expect(MediaImageExactResizeMode.sanitized("fill") == .fill
               && MediaImageExactResizeMode.sanitized("wild") == .stretch,
               "Image exact resize mode accepts fill and falls back to stretch")
        suite.expect(MediaImageBackground.sanitized("black") == .black
               && MediaImageBackground.sanitized("mystery") == .transparent,
               "Image backgrounds sanitize known values and fall back to transparent")
        suite.expect(MediaImageResizeMode.none.targetSize(for: CGSize(width: 123, height: 45))
               == CGSize(width: 123, height: 45),
               "Image resize can preserve source dimensions")
        suite.expect(MediaImageResizeMode.maxDimension(1000).targetSize(for: CGSize(width: 1920, height: 1080))
               == CGSize(width: 1000, height: 563),
               "Image max-side resize keeps aspect ratio")
        suite.expect(MediaImageResizeMode.width(800).targetSize(for: CGSize(width: 1600, height: 1200))
               == CGSize(width: 800, height: 600),
               "Image width resize calculates proportional height")
        suite.expect(MediaImageResizeMode.height(500).targetSize(for: CGSize(width: 1600, height: 1200))
               == CGSize(width: 667, height: 500),
               "Image height resize calculates proportional width")
        suite.expect(MediaImageResizeMode.exact(width: 321, height: 123).targetSize(for: CGSize(width: 1600, height: 1200))
               == CGSize(width: 321, height: 123),
               "Image exact resize uses custom dimensions")
        let exactFill = MediaImageResizeMode.exact(width: 320, height: 180, mode: .fill)
        suite.expect(exactFill.exactMode == .fill
               && exactFill.targetSize(for: CGSize(width: 1600, height: 1200)) == CGSize(width: 320, height: 180),
               "Image exact resize stores fit/fill behavior without changing the target canvas")
        suite.expect(MediaSupport.imageRenderSizeIsSafe(CGSize(width: 9_000, height: 100)),
               "Image render safety accepts a wide image without changing its dimensions")
        suite.expect(!MediaSupport.imageRenderSizeIsSafe(CGSize(width: 9_000, height: 9_000)),
               "Image render safety rejects an allocation above the pixel budget")
        suite.expect(!MediaSupport.imageRenderSizeIsSafe(CGSize(width: 20_001, height: 1)),
               "Image render safety rejects dimensions above the supported bound")
        let rotatedImageProperties: [CFString: Any] = [
            kCGImagePropertyPixelWidth: 640,
            kCGImagePropertyPixelHeight: 480,
            kCGImagePropertyOrientation: 6,
        ]
        suite.expect(MediaSupport.imageDisplaySize(properties: rotatedImageProperties)
               == CGSize(width: 480, height: 640),
               "Image dimensions follow the source orientation used by the renderer")
        let oversizedImageProperties: [CFString: Any] = [
            kCGImagePropertyPixelWidth: Double.greatestFiniteMagnitude,
            kCGImagePropertyPixelHeight: 1,
            kCGImagePropertyOrientation: 6,
        ]
        suite.expect(MediaSupport.imageDisplaySize(properties: oversizedImageProperties) == nil,
               "Malformed finite image dimensions are rejected before integer conversion")
        let renameDate = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC
        let renamePattern = MediaImageRenamePattern("{name}-{counter:03}-{date}-{time}-{width}x{height}-{ext}")
        suite.expect(renamePattern.outputBaseName(for: URL(fileURLWithPath: "/tmp/Photo One.tiff"),
                                            index: 7,
                                            date: renameDate,
                                            size: CGSize(width: 800, height: 600),
                                            format: .png)
               == "Photo One-007-20240101-000000-800x600-png",
               "Image rename pattern expands date, time, extension and padded counter tokens")
        suite.expect(MediaImageRenamePattern("{datetime}-{index}").outputBaseName(for: URL(fileURLWithPath: "/tmp/a.jpg"),
                                                                            index: 2,
                                                                            date: renameDate,
                                                                            size: CGSize(width: 1, height: 1),
                                                                            format: .jpeg)
               == "20240101-000000-2",
               "Image rename pattern expands datetime")
        suite.expect(MediaImageRenamePattern("../bad/name").outputBaseName(for: URL(fileURLWithPath: "/tmp/a.jpg"),
                                                                     index: 1,
                                                                     size: CGSize(width: 1, height: 1),
                                                                     format: .jpeg)
               == "bad-name",
               "Image rename pattern removes path separators")
        let emojiName = MediaSupport.sanitizedFileBaseName(String(repeating: "🙂", count: 120),
                                                           fileExtension: "png",
                                                           uniquenessSuffixByteReservation: 4)
        suite.expect(emojiName.utf8.count <= 247,
               "Image rename pattern output is capped by filesystem bytes, not character count")
        let profileOptions = MediaImageOptions(quality: 0.8,
                                               maxDimension: 1400,
                                               format: .png,
                                               stripMetadata: false,
                                               resizeMode: .exact(width: 900, height: 600, mode: .fit),
                                               watermark: MediaImageWatermark(kind: .text,
                                                                              text: "Sample",
                                                                              opacity: 0.5),
                                               renamePattern: MediaImageRenamePattern("{name}-{index}"))
        let encodedProfile = try? JSONEncoder().encode([MediaImageProfile(id: "profile-1",
                                                                           name: "PNG web",
                                                                           options: profileOptions)])
        let decodedProfile = encodedProfile.flatMap { try? JSONDecoder().decode([MediaImageProfile].self, from: $0) }
        suite.expect(decodedProfile?.first?.options == profileOptions,
               "Image profiles round-trip converter options")
        let largeSideOptions = MediaImageOptions(quality: 0.8,
                                                 maxDimension: 12_000,
                                                 format: .jpeg,
                                                 stripMetadata: true,
                                                 resizeMode: nil)
        suite.expect(largeSideOptions.maxDimension == 12_000
                && largeSideOptions.resizeMode.maxDimension == 12_000,
               "Image profile fields share the same max-side sanitizer")
        let legacyResizeJSON = #"{"kind":"exact","maxDimension":1600,"width":320,"height":180}"#
        let legacyResize = legacyResizeJSON.data(using: .utf8).flatMap { try? JSONDecoder().decode(MediaImageResizeMode.self, from: $0) }
        suite.expect(legacyResize?.exactMode == .stretch,
               "Image resize profiles created before exact fit/fill decode with stretch")
        suite.expect(MediaSupport.imageDecodeMaxPixel(sourceSize: CGSize(width: 1_000, height: 100),
                                                targetSize: CGSize(width: 100, height: 100),
                                                resizeMode: .exact(width: 100, height: 100, mode: .fit)) == 100,
               "Exact fit decodes only the pixels needed for the fitted image")
        suite.expect(MediaSupport.imageDecodeMaxPixel(sourceSize: CGSize(width: 1_000, height: 100),
                                                targetSize: CGSize(width: 100, height: 100),
                                                resizeMode: .exact(width: 100, height: 100, mode: .fill)) == 1_000
               && MediaSupport.imageDecodeMaxPixel(sourceSize: CGSize(width: 1_000, height: 100),
                                                   targetSize: CGSize(width: 100, height: 100),
                                                   resizeMode: .exact(width: 100, height: 100, mode: .stretch)) == 1_000,
               "Exact fill and stretch retain enough source detail before rendering")
        suite.expect(MediaSupport.imageDecodeMaxPixel(sourceSize: CGSize(width: 100_000, height: 1_000),
                                                targetSize: CGSize(width: 1_000, height: 1_000),
                                                resizeMode: .exact(width: 1_000, height: 1_000, mode: .fill)) == nil,
               "Image fill refuses a source decode that would exceed the safe render budget")
        suite.expect(MediaSupport.safeGIFFrameCount(duration: 25, fps: 12) == 300
               && MediaSupport.safeGIFFrameCount(duration: 25.01, fps: 12) == nil
               && MediaSupport.safeGIFFrameCount(duration: .greatestFiniteMagnitude, fps: 30) == nil,
               "GIF export rejects unsafe frame counts and overflow before rendering")
        suite.expect(MediaSupport.maximumGIFDuration(fps: 12) == 25
                && MediaSupport.gifLoopCount(loops: true) == 0
                && MediaSupport.gifLoopCount(loops: false) == nil,
               "GIF limits are actionable and non-looping output omits repeat metadata")

        // MARK: Media size targets

        suite.expect(MediaSizingMode.sanitized("targetSize") == .targetSize
                && MediaSizingMode.sanitized("resolution") == .resolution
                && MediaSizingMode.sanitized("nonsense") == .resolution,
               "A stored sizing mode falls back to the historical resolution mode")
        suite.expect(MediaSupport.targetBytes(megabytes: 20) == 20_000_000
                && MediaSupport.targetBytes(megabytes: 0) == 1_000_000
                && MediaSupport.targetBytes(megabytes: 99_999)
                    == Int64(MediaSupport.maximumTargetMegabytes) * 1_000_000,
               "Target megabytes are 1000 based and clamped to a usable range")

        // The case the mode exists for: a minute of 1080p that has to fit the
        // 20 MB a chat service accepts without paid tiers.
        let sharePlan = MediaSupport.videoSizePlan(targetBytes: 20_000_000,
                                                   duration: 60,
                                                   sourceSize: CGSize(width: 1920, height: 1080),
                                                   frameRate: 30,
                                                   hasAudio: true)
        suite.expect(sharePlan != nil, "A minute of 1080p can be planned into 20 MB")
        if let plan = sharePlan {
            let projectedBytes = Double(plan.videoBitRate + plan.audioBitRate) * 60 / 8
            suite.expect(projectedBytes <= 20_000_000,
                   "The planned bitrate cannot overrun the target it was derived from")
            suite.expect(projectedBytes >= 18_000_000,
                   "The plan spends the budget instead of undershooting it")
            suite.expect(plan.size.width <= 1920 && plan.size.height <= 1080,
                   "A size target never upscales the source")
            suite.expect(Int(plan.size.width).isMultiple(of: 2) && Int(plan.size.height).isMultiple(of: 2),
                   "Planned dimensions stay even, which H.264 requires")
        }

        // Short clips have bitrate to spare, so nothing is thrown away.
        suite.expect(MediaSupport.videoSizePlan(targetBytes: 20_000_000,
                                          duration: 5,
                                          sourceSize: CGSize(width: 1280, height: 720),
                                          frameRate: 30,
                                          hasAudio: true)?.size == CGSize(width: 1280, height: 720),
               "A budget larger than the source needs keeps the full resolution")
        // A budget too thin to be watchable is refused rather than encoded.
        suite.expect(MediaSupport.videoSizePlan(targetBytes: 1_000_000,
                                          duration: 120,
                                          sourceSize: CGSize(width: 1920, height: 1080),
                                          frameRate: 30,
                                          hasAudio: true) == nil,
               "An unreachable target fails planning instead of producing mush")
        suite.expect(MediaSupport.videoSizePlan(targetBytes: 2_000_000,
                                          duration: 60,
                                          sourceSize: CGSize(width: 1920, height: 1080),
                                          frameRate: 30,
                                          hasAudio: false)?.size == CGSize(width: 480, height: 270),
               "Scaling stops at 480 on the long edge even when the budget would buy less")
        suite.expect(MediaSupport.videoSizePlan(targetBytes: 20_000_000,
                                          duration: 0,
                                          sourceSize: CGSize(width: 1920, height: 1080),
                                          frameRate: 30,
                                          hasAudio: true) == nil
                && MediaSupport.videoSizePlan(targetBytes: 20_000_000,
                                              duration: 60,
                                              sourceSize: .zero,
                                              frameRate: 30,
                                              hasAudio: true) == nil,
               "Planning rejects a clip with no duration or no size")
        suite.expect(MediaSupport.targetAudioBitRate(targetBytes: 20_000_000, duration: 60) == 128_000
                && MediaSupport.targetAudioBitRate(targetBytes: 2_000_000, duration: 60) == 64_000,
               "Audio gives up half its bitrate when the whole budget is thin")

        // Rate control lands near the budget, so an overshoot is measured and
        // scaled down rather than retried at the same setting.
        suite.expectClose(MediaSupport.targetRetryScale(current: 1,
                                                  actualBytes: 24_000_000,
                                                  targetBytes: 20_000_000) ?? 0,
                    0.7833, "overshoot retry scale", tol: 0.001)
        suite.expect(MediaSupport.targetRetryScale(current: 1,
                                             actualBytes: 19_000_000,
                                             targetBytes: 20_000_000) == nil,
               "A pass that already fits is never retried")
        suite.expect((MediaSupport.targetRetryScale(current: 1,
                                              actualBytes: 20_000_001,
                                              targetBytes: 20_000_000) ?? 1) <= 0.9,
               "Every retry gives up at least a tenth so the passes converge")

        // A GIF has no bitrate, so overshoot is corrected on frames first.
        let gifRetry = MediaSupport.gifSizePlan(width: 720, fps: 15,
                                                actualBytes: 12_000_000, targetBytes: 8_000_000)
        suite.expect(gifRetry?.fps == 9 && gifRetry?.width == 720,
               "A GIF over its target drops frames before it drops pixels")
        let gifDeepRetry = MediaSupport.gifSizePlan(width: 720, fps: 9,
                                                    actualBytes: 9_000_000, targetBytes: 2_000_000)
        suite.expect((gifDeepRetry?.width ?? 720) < 720 && gifDeepRetry?.fps == MediaSupport.minimumTargetGIFFPS,
               "Once the frame rate hits its floor the frame itself shrinks")
        suite.expect(MediaSupport.gifSizePlan(width: 160, fps: 6,
                                        actualBytes: 5_000_000, targetBytes: 1_000_000) == nil
                && MediaSupport.gifSizePlan(width: 720, fps: 15,
                                            actualBytes: 1_000_000, targetBytes: 8_000_000) == nil,
               "A GIF already at its floor, or already fitting, has nothing left to plan")
        suite.expect(MediaSupport.targetGIFStartFPS(duration: 10) == 15
                && MediaSupport.targetGIFStartFPS(duration: 60) == MediaSupport.minimumTargetGIFFPS,
               "A size targeted GIF starts at the highest rate its frame ceiling allows")
        suite.expect(MediaSupport.targetGIFStartWidth(sourceWidth: 1_920) == 1_600
                && MediaSupport.targetGIFStartWidth(sourceWidth: 640) == 640
                && MediaSupport.targetGIFStartWidth(sourceWidth: 0) == 1_600,
               "A size targeted GIF starts from the source width, capped at the tool maximum")

        let sizeTargetStrings: [(String, Strings)] = [
            ("en-US", .enUS), ("pt-BR", .ptBR), ("tr", .tr), ("ru", .ru), ("es", .es),
            ("de", .de), ("fr", .fr), ("it", .it), ("ja", .ja), ("ko", .ko),
            ("zh-Hans", .zhHans), ("zh-HK", .zhHK), ("zh-TW", .zhTW),
        ]
        for (name, strings) in sizeTargetStrings {
            suite.expect(!strings.mediaSizingResolution.isEmpty
                    && !strings.mediaSizingFileSize.isEmpty
                    && !strings.mediaTargetSize.isEmpty
                    && !strings.mediaTargetSizeHint.isEmpty
                    && !strings.mediaErrorTargetTooSmall.isEmpty
                    && !strings.mediaMegabytesSuffix.isEmpty,
                   "\(name) names the size target controls")
        }
        let sanitizedProfiles = MediaSupport.sanitizedImageProfiles([
            MediaImageProfile(id: "same", name: "  ", options: profileOptions),
            MediaImageProfile(id: "same", name: " Work ", options: profileOptions),
        ])
        suite.expect(sanitizedProfiles.count == 2
               && sanitizedProfiles[0].name == "Profile 1"
               && sanitizedProfiles[1].name == "Work"
               && sanitizedProfiles[0].id != sanitizedProfiles[1].id,
               "Image profiles sanitize empty names and duplicate IDs")
        // This run ends in exit(), which skips every defer, so scratch built
        // in the temp area is listed here and handed back before it reports.
        // The three defers that used to do it never ran once: a directory per
        // run had been piling up in the system's temp area for as long as the
        // suite has existed.
        var scratchPaths: [URL] = []
        let uniqueDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-media-unique-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: uniqueDir, withIntermediateDirectories: true)
        scratchPaths.append(uniqueDir)
        let firstImageOutput = MediaSupport.uniqueOutputURL(in: uniqueDir, baseName: "Export", fileExtension: "png")
        FileManager.default.createFile(atPath: firstImageOutput.path, contents: Data([1]), attributes: nil)
        suite.expect(MediaSupport.uniqueOutputURL(in: uniqueDir, baseName: "Export", fileExtension: "png").lastPathComponent
               == "Export 2.png",
               "Image batch output names avoid overwriting existing files")
        let reservedURL = MediaSupport.uniqueOutputURL(in: uniqueDir,
                                                       baseName: "Reserved",
                                                       fileExtension: "png",
                                                       reservedPaths: [uniqueDir.appendingPathComponent("Reserved.png").standardizedFileURL.path])
        suite.expect(reservedURL.lastPathComponent == "Reserved 2.png",
               "Image batch output names avoid paths already reserved in the current run")
        let occupiedPaths = Set((1...1_000).map { index in
            let name = index == 1 ? "Crowded.png" : "Crowded \(index).png"
            return uniqueDir.appendingPathComponent(name).standardizedFileURL.path
        })
        suite.expect(MediaSupport.uniqueOutputURL(in: uniqueDir,
                                            baseName: "Crowded",
                                            fileExtension: "png",
                                            reservedPaths: occupiedPaths).lastPathComponent == "Crowded 1001.png",
               "Image output naming never falls back to an occupied path")
        let longBaseName = String(repeating: "😀", count: 100)
        let longCandidate = MediaSupport.outputURL(in: uniqueDir,
                                                   baseName: longBaseName,
                                                   fileExtension: "png")
        let longCandidateBase = longCandidate.deletingPathExtension().lastPathComponent
        var longOccupiedPaths = Set([longCandidate.standardizedFileURL.path])
        for index in 2...999 {
            longOccupiedPaths.insert(uniqueDir
                .appendingPathComponent("\(longCandidateBase) \(index)")
                .appendingPathExtension("png").standardizedFileURL.path)
        }
        let longUniqueURL = MediaSupport.uniqueOutputURL(in: uniqueDir,
                                                         baseName: longBaseName,
                                                         fileExtension: "png",
                                                         reservedPaths: longOccupiedPaths)
        suite.expect(longUniqueURL.lastPathComponent.utf8.count <= 255
               && !longOccupiedPaths.contains(longUniqueURL.standardizedFileURL.path),
               "Large collision suffixes remain unique without exceeding filesystem name limits")

        let originalURL = uniqueDir.appendingPathComponent("Original.png")
        let destinationURL = uniqueDir.appendingPathComponent("Destination.png")
        let hardLinkURL = uniqueDir.appendingPathComponent("Original link.png")
        let symbolicLinkURL = uniqueDir.appendingPathComponent("Original alias.png")
        try? Data("original".utf8).write(to: originalURL)
        try? Data("destination".utf8).write(to: destinationURL)
        try? FileManager.default.linkItem(at: originalURL, to: hardLinkURL)
        try? FileManager.default.createSymbolicLink(at: symbolicLinkURL, withDestinationURL: originalURL)
        suite.expect(MediaSupport.fileURLsReferToSameItem(originalURL, hardLinkURL)
               && MediaSupport.fileURLsReferToSameItem(originalURL, symbolicLinkURL),
               "Media outputs reject hard links and symbolic links to the input")
        let abandonedStage = try! MediaSupport.temporaryOutputURL(for: destinationURL)
        try? Data("partial".utf8).write(to: abandonedStage)
        MediaSupport.discardStagedOutput(abandonedStage)
        suite.expect((try? Data(contentsOf: destinationURL)) == Data("destination".utf8),
               "A failed or cancelled staged export preserves the existing destination")
        let completedStage = try! MediaSupport.temporaryOutputURL(for: destinationURL)
        try? Data("replacement".utf8).write(to: completedStage)
        try? MediaSupport.installStagedOutput(completedStage, at: destinationURL)
        MediaSupport.discardStagedOutput(completedStage)
        suite.expect((try? Data(contentsOf: destinationURL)) == Data("replacement".utf8),
               "A completed staged export atomically replaces the destination")
        let renamedOptions = MediaImageOptions(quality: 0.8,
                                               maxDimension: 1600,
                                               format: .png,
                                               stripMetadata: true,
                                               resizeMode: MediaImageResizeMode.none,
                                               renamePattern: MediaImageRenamePattern("{name}-{index:02}"))
        let renamedSingle = MediaSupport.imageOutputURL(
            for: uniqueDir.appendingPathComponent("First.jpg"),
            outputDirectory: uniqueDir,
            options: renamedOptions,
            index: 1,
            outputSize: CGSize(width: 9000, height: 100))
        let renamedBatch = MediaSupport.imageOutputURL(
            for: uniqueDir.appendingPathComponent("Second.jpg"),
            outputDirectory: uniqueDir,
            options: renamedOptions,
            index: 2,
            outputSize: CGSize(width: 320, height: 200))
        suite.expect(renamedSingle.lastPathComponent == "First-01.png"
               && renamedBatch.lastPathComponent == "Second-02.png",
               "Image rename patterns apply to both single and batch outputs")
        let manuallyChosen = uniqueDir.appendingPathComponent("Chosen.jpg")
        try? Data([1]).write(to: uniqueDir.appendingPathComponent("Chosen.png"))
        suite.expect(MediaSupport.outputURLByReplacingExtension(manuallyChosen,
                                                          fileExtension: "png").lastPathComponent == "Chosen 2.png",
               "Changing image format updates a manual output extension without overwriting a collision")
        let orderedDropURLs = MediaSupport.urlsInProviderOrder([
            (offset: 2, url: uniqueDir.appendingPathComponent("Third.png")),
            (offset: 0, url: uniqueDir.appendingPathComponent("First.png")),
            (offset: 1, url: uniqueDir.appendingPathComponent("Second.png")),
        ])
        suite.expect(orderedDropURLs.map(\.lastPathComponent) == ["First.png", "Second.png", "Third.png"],
               "Concurrent image drops keep the person's provider order")
        let corruptLogo = uniqueDir.appendingPathComponent("Corrupt logo.png")
        try? Data("not an image".utf8).write(to: corruptLogo)
        suite.expect(MediaSupport.watermarkLogo(atPath: corruptLogo.path) == nil,
               "An unreadable watermark logo is rejected instead of being silently omitted")

        for language in AppLanguage.allCases {
            let strings = MediaImageConverterStrings.localized(language)
            suite.expect(strings.filesSelectedFormat.contains("%d")
                   && strings.profileDefaultNameFormat.contains("%d")
                   && strings.savedBytesFormat.contains("%@")
                   && strings.grewBytesFormat.contains("%@")
                   && strings.batchSavedFormat.contains("%d")
                   && strings.batchPartialFormat.filter { $0 == "%" }.count == 2
                   && strings.batchSummaryHeaderFormat.filter { $0 == "%" }.count == 2
                   && strings.batchSummaryItemFormat.filter { $0 == "%" }.count == 2,
                   "image converter formats keep their arguments in \(language.rawValue)")
        }

        let trim = MediaSupport.sanitizedTrim(start: -5, end: 3, assetDuration: 10)
        suite.expect(trim == MediaTrimRange(start: 0, end: 3),
               "Media trim clamps negative start")
        let fullTrim = MediaSupport.sanitizedTrim(start: 2, end: 0, assetDuration: 10)
        suite.expect(fullTrim == MediaTrimRange(start: 2, end: 10),
               "Media trim treats zero end as the source duration")
        suite.expectClose(MediaSupport.sanitizedQuality(.infinity), 0.7,
                    "Media invalid quality falls back")
        suite.expectClose(MediaSupport.sanitizedQuality(0.02), 0.1,
                    "Media quality clamps low")
        suite.expectClose(MediaSupport.sanitizedQuality(2), 1,
                    "Media quality clamps high")
        suite.expectClose(MediaSupport.sanitizedFPS(90), 60,
                    "Media FPS clamps high")
        suite.expectClose(MediaSupport.sanitizedFPS(-1), 12,
                    "Media FPS falls back when invalid")
        suite.expect(MediaSupport.sanitizedPixelDimension(641, fallback: 1280) == 640,
               "Media pixel dimensions stay even")
        suite.expect(MediaSupport.scaledEvenSize(source: CGSize(width: 1920, height: 1080), maxDimension: 1000)
               == CGSize(width: 1000, height: 562),
               "Media scaling keeps aspect ratio with even dimensions")
        suite.expect(MediaSupport.scaledVideoSize(source: CGSize(width: 320, height: 180), maxDimension: 180)
               == CGSize(width: 176, height: 96),
               "Media video scaling uses encoder-friendly dimensions")
        let mediaInput = URL(fileURLWithPath: "/tmp/Clip.mov")
        suite.expect(MediaSupport.outputURL(for: mediaInput, suffix: "-compressed", fileExtension: "mp4").path
               == "/tmp/Clip-compressed.mp4",
               "Media output names keep clear suffixes")
        let hiddenMediaInput = URL(fileURLWithPath: "/tmp/.Clip.mov")
        suite.expect(MediaSupport.outputURL(for: hiddenMediaInput, suffix: "", fileExtension: "gif").path
               == "/tmp/Clip.gif",
               "Media GIF output strips a leading dot from the source name")
        let extensionOnlyMediaInput = URL(fileURLWithPath: "/tmp/.mov")
        suite.expect(MediaSupport.outputURL(for: extensionOnlyMediaInput, suffix: "", fileExtension: "gif").path
               == "/tmp/mov.gif",
               "Media GIF output stays visible for extension-looking source names")
        let emptyBaseMediaInput = URL(fileURLWithPath: "/tmp/...")
        suite.expect(MediaSupport.outputURL(for: emptyBaseMediaInput, suffix: "", fileExtension: "gif").path
               == "/tmp/Output.gif",
               "Media GIF output falls back when the visible source name is empty")
        let mediaVisibilityDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-media-visibility-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: mediaVisibilityDir,
                                                 withIntermediateDirectories: true)
        scratchPaths.append(mediaVisibilityDir)
        let visibleMediaOutput = mediaVisibilityDir.appendingPathComponent("Visible.gif")
        FileManager.default.createFile(atPath: visibleMediaOutput.path,
                                       contents: Data([0x47, 0x49, 0x46, 0x38]),
                                       attributes: nil)
        visibleMediaOutput.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = chflags(path, UInt32(UF_HIDDEN))
        }
        var hiddenMediaOutputStat = stat()
        visibleMediaOutput.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = lstat(path, &hiddenMediaOutputStat)
        }
        suite.expect((UInt32(hiddenMediaOutputStat.st_flags) & UInt32(UF_HIDDEN)) != 0,
               "Media visibility test marks the fixture hidden")
        MediaSupport.makeVisibleIfNeeded(visibleMediaOutput)
        var visibleMediaOutputStat = stat()
        visibleMediaOutput.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = lstat(path, &visibleMediaOutputStat)
        }
        suite.expect((UInt32(visibleMediaOutputStat.st_flags) & UInt32(UF_HIDDEN)) == 0,
               "Media visible outputs clear the Finder hidden flag")
        let intentionallyHiddenMediaOutput = mediaVisibilityDir.appendingPathComponent(".Manual.gif")
        FileManager.default.createFile(atPath: intentionallyHiddenMediaOutput.path,
                                       contents: Data([0x47, 0x49, 0x46, 0x38]),
                                       attributes: nil)
        intentionallyHiddenMediaOutput.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = chflags(path, UInt32(UF_HIDDEN))
        }
        MediaSupport.makeVisibleIfNeeded(intentionallyHiddenMediaOutput)
        var intentionallyHiddenMediaOutputStat = stat()
        intentionallyHiddenMediaOutput.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = lstat(path, &intentionallyHiddenMediaOutputStat)
        }
        suite.expect((UInt32(intentionallyHiddenMediaOutputStat.st_flags) & UInt32(UF_HIDDEN)) != 0,
               "Media output visibility respects dot-prefixed manual filenames")
        suite.expect(MediaSupport.recognitionLanguages(for: "pt-BR") == ["pt-BR", "en-US"],
               "Media OCR language defaults include the app language and English")
        suite.expect(MediaSupport.recognitionLanguages(for: "tr") == ["tr-TR", "en-US"],
               "Media OCR language defaults include Turkish and English")
        suite.expect(MediaSupport.recognitionLanguages(for: "ko") == ["ko-KR", "en-US"],
               "Media OCR language defaults include Korean and English")
        suite.expect(MediaSupport.recognitionLanguages(for: "zh-Hans") == ["zh-Hans", "en-US"],
               "Media OCR language defaults include simplified Chinese and English")
        suite.expect(MediaSupport.recognitionLanguages(for: "zh-TW") == ["zh-Hant", "en-US"],
               "Media OCR maps Taiwan Chinese to Vision traditional Chinese")
        suite.expect(MediaSupport.recognitionLanguages(for: "zh-HK") == ["zh-Hant", "en-US"],
               "Media OCR maps Hong Kong Chinese to Vision traditional Chinese")
        scratchPaths.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
