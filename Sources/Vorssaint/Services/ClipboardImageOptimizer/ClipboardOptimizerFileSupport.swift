// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO

/// The rules for copied files the clipboard optimizer rewrites into a new
/// file: which ones qualify, the limits, where the result lives and when it
/// may be deleted. No AppKit and no pasteboard, so the harness pins them.
enum ClipboardOptimizerFileSupport {
    // MARK: Kinds

    /// Still images ImageIO reads but that are handed on as JPEG or PNG.
    static let convertibleImageUTIs: [String: String] = [
        "heic": "public.heic", "heif": "public.heif", "webp": "org.webmproject.webp",
        "avif": "public.avif", "bmp": "com.microsoft.bmp",
    ]
    /// Containers AVFoundation opens and avconvert writes back unchanged.
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    static func convertibleImageUTI(for url: URL) -> String? {
        convertibleImageUTIs[url.pathExtension.lowercased()]
    }

    static func isVideo(_ url: URL) -> Bool { videoExtensions.contains(url.pathExtension.lowercased()) }
    static func isPDF(_ url: URL) -> Bool { url.pathExtension.lowercased() == "pdf" }

    // MARK: Options

    struct VideoOptions: Equatable {
        static let qualityRange = 0.1...1.0
        static let maxDimensionChoices = [0, 1280, 1920, 3840]

        /// avconvert's HEVC presets start at 1080p, so 1280 is H.264 only.
        static func maxDimensionChoices(codec: MediaVideoCodec) -> [Int] {
            codec == .hevc ? maxDimensionChoices.filter { $0 != 1280 } : maxDimensionChoices
        }
        static let maxMBChoices = [100, 250, 500, 1000, 2000]
        static let maxMinutesChoices = [1, 5, 15, 30, 60]
        static let defaultQuality = 0.6
        static let defaultMaxDimension = 1920
        static let defaultMaxMB = 500
        static let defaultMaxMinutes = 15

        var codec: MediaVideoCodec
        var quality: Double
        /// Long edge in pixels, 0 keeps the size.
        var maxDimension: Int
        var removeAudio: Bool
        var maxMB: Int
        var maxMinutes: Int

        static func sanitized(codec: String?, quality: Double?, maxDimension: Int?, removeAudio: Bool,
                              maxMB: Int?, maxMinutes: Int?) -> VideoOptions {
            let quality = quality.flatMap { $0.isFinite ? $0 : nil } ?? defaultQuality
            let codec = codec.flatMap(MediaVideoCodec.init(rawValue:)) ?? .hevc
            return VideoOptions(
                codec: codec,
                quality: min(qualityRange.upperBound, max(qualityRange.lowerBound, quality)),
                maxDimension: pick(maxDimension, from: maxDimensionChoices(codec: codec),
                                   fallback: defaultMaxDimension),
                removeAudio: removeAudio,
                maxMB: pick(maxMB, from: maxMBChoices, fallback: defaultMaxMB),
                maxMinutes: pick(maxMinutes, from: maxMinutesChoices, fallback: defaultMaxMinutes))
        }

        static func fromDefaults(_ defaults: UserDefaults = .standard) -> VideoOptions {
            sanitized(codec: defaults.string(forKey: DefaultsKey.clipboardOptimizerVideoCodec),
                      quality: defaults.object(forKey: DefaultsKey.clipboardOptimizerVideoQuality) as? Double,
                      maxDimension: defaults.object(forKey: DefaultsKey.clipboardOptimizerVideoMaxDimension) as? Int,
                      removeAudio: defaults.bool(forKey: DefaultsKey.clipboardOptimizerVideoRemoveAudio),
                      maxMB: defaults.object(forKey: DefaultsKey.clipboardOptimizerVideoMaxMB) as? Int,
                      maxMinutes: defaults.object(forKey: DefaultsKey.clipboardOptimizerVideoMaxMinutes) as? Int)
        }
    }

    struct PDFOptions: Equatable {
        static let dpiChoices = [72, 100, 150, 200, 300]
        static let maxMBChoices = [25, 50, 100, 250]
        static let defaultDPI = 150
        static let defaultQuality = 0.7
        static let defaultMaxMB = 100

        /// Embedded images are resampled down to this resolution on the page.
        var dpi: Int
        /// JPEG quality for the resampled images.
        var quality: Double
        var maxMB: Int

        static func sanitized(dpi: Int?, quality: Double?, maxMB: Int?) -> PDFOptions {
            let quality = quality.flatMap { $0.isFinite ? $0 : nil } ?? defaultQuality
            return PDFOptions(dpi: pick(dpi, from: dpiChoices, fallback: defaultDPI),
                              quality: min(1, max(0.1, quality)),
                              maxMB: pick(maxMB, from: maxMBChoices, fallback: defaultMaxMB))
        }

        /// The clipboard never converts to gray.
        var settings: MediaPDFCompressor.Settings {
            MediaPDFCompressor.Settings(dpi: dpi, quality: quality, grayscale: false)
        }

        static func fromDefaults(_ defaults: UserDefaults = .standard) -> PDFOptions {
            sanitized(dpi: defaults.object(forKey: DefaultsKey.clipboardOptimizerPDFDPI) as? Int,
                      quality: defaults.object(forKey: DefaultsKey.clipboardOptimizerPDFQuality) as? Double,
                      maxMB: defaults.object(forKey: DefaultsKey.clipboardOptimizerPDFMaxMB) as? Int)
        }
    }

    private static func pick(_ value: Int?, from choices: [Int], fallback: Int) -> Int {
        guard let value, choices.contains(value) else { return fallback }
        return value
    }

    static let pdfFilterName = "Vorssaint clipboard optimizer"

    /// The shared media PDF filter, in color, under the clipboard's name.
    static func pdfFilter(_ options: PDFOptions) -> [String: Any] {
        MediaPDFCompressor.filter(options.settings, name: pdfFilterName)
    }

    // MARK: Gates

    enum Gate: Equatable {
        case ok, empty, tooLarge, tooLong
    }

    static func sizeGate(bytes: Int64, capMB: Int) -> Gate {
        guard bytes > 0 else { return .empty }
        return bytes > Int64(capMB) * 1024 * 1024 ? .tooLarge : .ok
    }

    static func durationGate(seconds: Double, capMinutes: Int) -> Gate {
        guard seconds.isFinite, seconds > 0, seconds <= Double(capMinutes * 60) else { return .tooLong }
        return .ok
    }

    /// Room for the output and whatever the encoder keeps beside it, and
    /// never the last gigabyte of the disk.
    static func hasRoom(freeBytes: Int64?, sourceBytes: Int64) -> Bool {
        guard let freeBytes else { return false }
        return freeBytes >= max(2 * sourceBytes, 1024 * 1024 * 1024)
    }

    /// Reading a file whose contents live in the cloud downloads it, which a
    /// copy must never set off.
    static func isAvailableLocally(dataless: Bool, ubiquitous: Bool, downloaded: Bool?) -> Bool {
        guard !dataless else { return false }
        return !ubiquitous || downloaded == true
    }

    /// Checks the file itself, not a link to it, without reading its contents.
    static func isAvailableLocally(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        var info = stat()
        guard stat(resolved.path, &info) == 0 else { return false }
        let values = try? resolved.resourceValues(forKeys: [.isUbiquitousItemKey,
                                                           .ubiquitousItemDownloadingStatusKey])
        let ubiquitous = values?.isUbiquitousItem ?? false
        return isAvailableLocally(dataless: (info.st_flags & UInt32(SF_DATALESS)) != 0,
                                  ubiquitous: ubiquitous,
                                  downloaded: ubiquitous ? values?.ubiquitousItemDownloadingStatus == .current : nil)
    }

    /// A finished encode that stops early is a broken file, not a small one.
    static func validVideo(sourceDuration: Double, outputDuration: Double, hasVideo: Bool) -> Bool {
        hasVideo && sourceDuration.isFinite && outputDuration.isFinite
            && abs(sourceDuration - outputDuration) <= 0.5
    }

    // MARK: Documents and images that must stay as they are

    /// What a rewrite could break in a PDF; shared with the media tools.
    typealias PDFTraits = MediaPDFCompressor.Traits

    /// What a JPEG or 8-bit PNG would lose. Any of it leaves the image alone.
    struct ImageTraits: Equatable {
        let frameCount: Int
        let bitsPerComponent: Int
        let hdrTransfer: Bool
        let auxiliaryData: Bool

        var leavesAlone: Bool {
            frameCount != 1 || bitsPerComponent > 8 || hdrTransfer || auxiliaryData
        }

        static var auxiliaryTypes: [CFString] {
            var types = baseAuxiliaryTypes
            if #available(macOS 15.0, *) { types.append(kCGImageAuxiliaryDataTypeISOGainMap) }
            return types
        }

        private static let baseAuxiliaryTypes: [CFString] = [
            kCGImageAuxiliaryDataTypeHDRGainMap,
            kCGImageAuxiliaryDataTypeDepth, kCGImageAuxiliaryDataTypeDisparity,
            kCGImageAuxiliaryDataTypePortraitEffectsMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationSkinMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationHairMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationTeethMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationGlassesMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationSkyMatte,
        ]

        /// Reads headers only; the image itself is decoded just far enough to
        /// learn its color space.
        static func read(_ source: CGImageSource) -> ImageTraits? {
            let count = CGImageSourceGetCount(source)
            guard count > 0,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            else { return nil }
            let depth = properties[kCGImagePropertyDepth] as? Int ?? 8
            let auxiliary = auxiliaryTypes.contains {
                CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil
            }
            var hdr = false
            if let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
               let space = image.colorSpace {
                hdr = CGColorSpaceUsesITUR_2100TF(space) || image.bitsPerComponent > 8
            }
            return ImageTraits(frameCount: count, bitsPerComponent: depth, hdrTransfer: hdr, auxiliaryData: auxiliary)
        }
    }

    // MARK: Where results live

    static func isOwnOutput(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    /// `<root>/<id>/<original name>`, with the extension of what was written.
    static func outputURL(root: URL, id: UUID, source: URL, outputExtension: String?) -> URL {
        var base = source.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        if base.isEmpty || base == "." || base == ".." { base = "Optimized" }
        let ext = outputExtension ?? source.pathExtension
        let name = ext.isEmpty ? base : base + "." + ext
        return root.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent(name)
    }

    /// Written first and renamed once it checks out, so nothing half written
    /// ever carries the final name.
    static func partialURL(for output: URL) -> URL {
        let ext = output.pathExtension
        let name = ".partial"
        return output.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? name : name + "." + ext)
    }

    struct StoredJob: Equatable {
        let url: URL
        let created: Date
        let bytes: Int64
    }

    struct SweepPolicy: Equatable {
        var maxAge: TimeInterval = 24 * 3600
        var keepNewest = 5
        var maxTotalBytes: Int64 = 2 * 1024 * 1024 * 1024
    }

    /// Protected paths (the clipboard's current file, pinned history) are
    /// never removed. Paths unpinned history still shows survive the age
    /// rule but not the total cap: that history filters missing files.
    static func sweepCandidates(_ jobs: [StoredJob], now: Date, protected: Set<String>, referenced: Set<String>,
                                policy: SweepPolicy) -> [URL] {
        let newestFirst = jobs.sorted { $0.created > $1.created }
        func holds(_ job: StoredJob, _ paths: Set<String>) -> Bool {
            let prefix = job.url.standardizedFileURL.path + "/"
            return paths.contains { $0.hasPrefix(prefix) }
        }
        var removed: [URL] = []
        var kept: [StoredJob] = []
        for (index, job) in newestFirst.enumerated() {
            let old = now.timeIntervalSince(job.created) > policy.maxAge
            if index >= policy.keepNewest, old, !holds(job, protected), !holds(job, referenced) {
                removed.append(job.url)
            } else {
                kept.append(job)
            }
        }
        var total = kept.reduce(Int64(0)) { $0 + $1.bytes }
        for job in kept.reversed() where total > policy.maxTotalBytes && !holds(job, protected) {
            removed.append(job.url)
            total -= job.bytes
        }
        return removed
    }

    /// Everything that neither the clipboard nor a pin still needs.
    static func clearCandidates(_ jobs: [StoredJob], protected: Set<String>) -> [URL] {
        jobs.filter { job in
            let prefix = job.url.standardizedFileURL.path + "/"
            return !protected.contains { $0.hasPrefix(prefix) }
        }.map(\.url)
    }
}
