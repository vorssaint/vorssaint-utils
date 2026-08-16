// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MediaTool: String, CaseIterable, Identifiable {
    case videoCompressor, gifMaker, imageCompressor, textExtractor

    var id: String { rawValue }
}

enum MediaImageFormat: String, CaseIterable, Codable, Identifiable {
    case jpeg, heic, png, pdf

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .png: return "png"
        case .pdf: return "pdf"
        }
    }

    static func sanitized(_ value: String) -> MediaImageFormat {
        MediaImageFormat(rawValue: value) ?? .jpeg
    }
}

enum MediaImageResizeKind: String, CaseIterable, Codable, Identifiable {
    case none, maxDimension, width, height, exact

    var id: String { rawValue }

    static func sanitized(_ value: String) -> MediaImageResizeKind {
        MediaImageResizeKind(rawValue: value) ?? .maxDimension
    }
}

enum MediaImageExactResizeMode: String, CaseIterable, Codable, Identifiable {
    case stretch, fit, fill

    var id: String { rawValue }

    static func sanitized(_ value: String) -> MediaImageExactResizeMode {
        MediaImageExactResizeMode(rawValue: value) ?? .stretch
    }
}

struct MediaImageResizeMode: Codable, Equatable {
    var kind: MediaImageResizeKind
    var maxDimension: Int
    var width: Int
    var height: Int
    var exactMode: MediaImageExactResizeMode

    init(kind: MediaImageResizeKind = .maxDimension,
         maxDimension: Int = 1600,
         width: Int = 1600,
         height: Int = 1200,
         exactMode: MediaImageExactResizeMode = .stretch) {
        self.kind = kind
        self.maxDimension = MediaSupport.sanitizedImageDimension(maxDimension, fallback: 1600)
        self.width = MediaSupport.sanitizedImageDimension(width, fallback: 1600)
        self.height = MediaSupport.sanitizedImageDimension(height, fallback: 1200)
        self.exactMode = exactMode
    }

    private enum CodingKeys: String, CodingKey {
        case kind, maxDimension, width, height, exactMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kindRaw = try container.decodeIfPresent(String.self, forKey: .kind) ?? MediaImageResizeKind.maxDimension.rawValue
        let exactModeRaw = try container.decodeIfPresent(String.self, forKey: .exactMode) ?? MediaImageExactResizeMode.stretch.rawValue
        self.init(kind: MediaImageResizeKind.sanitized(kindRaw),
                  maxDimension: try container.decodeIfPresent(Int.self, forKey: .maxDimension) ?? 1600,
                  width: try container.decodeIfPresent(Int.self, forKey: .width) ?? 1600,
                  height: try container.decodeIfPresent(Int.self, forKey: .height) ?? 1200,
                  exactMode: MediaImageExactResizeMode.sanitized(exactModeRaw))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(maxDimension, forKey: .maxDimension)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(exactMode, forKey: .exactMode)
    }

    static let none = MediaImageResizeMode(kind: .none)

    static func maxDimension(_ value: Int) -> MediaImageResizeMode {
        MediaImageResizeMode(kind: .maxDimension, maxDimension: value)
    }

    static func width(_ value: Int) -> MediaImageResizeMode {
        MediaImageResizeMode(kind: .width, width: value)
    }

    static func height(_ value: Int) -> MediaImageResizeMode {
        MediaImageResizeMode(kind: .height, height: value)
    }

    static func exact(width: Int, height: Int,
                      mode: MediaImageExactResizeMode = .stretch) -> MediaImageResizeMode {
        MediaImageResizeMode(kind: .exact, width: width, height: height, exactMode: mode)
    }

    func targetSize(for source: CGSize) -> CGSize {
        let sourceWidth = max(1, abs(source.width))
        let sourceHeight = max(1, abs(source.height))
        switch kind {
        case .none:
            return CGSize(width: Int(sourceWidth.rounded()), height: Int(sourceHeight.rounded()))
        case .maxDimension:
            let maxSide = CGFloat(max(1, maxDimension))
            let scale = min(1, maxSide / max(sourceWidth, sourceHeight))
            return MediaSupport.integralImageSize(width: sourceWidth * scale, height: sourceHeight * scale)
        case .width:
            let outWidth = CGFloat(max(1, width))
            let outHeight = outWidth * sourceHeight / sourceWidth
            return MediaSupport.integralImageSize(width: outWidth, height: outHeight)
        case .height:
            let outHeight = CGFloat(max(1, height))
            let outWidth = outHeight * sourceWidth / sourceHeight
            return MediaSupport.integralImageSize(width: outWidth, height: outHeight)
        case .exact:
            return CGSize(width: max(1, width), height: max(1, height))
        }
    }
}

enum MediaImageWatermarkKind: String, CaseIterable, Codable, Identifiable {
    case off, text, logo, textAndLogo

    var id: String { rawValue }

    static func sanitized(_ value: String) -> MediaImageWatermarkKind {
        MediaImageWatermarkKind(rawValue: value) ?? .off
    }
}

enum MediaImageWatermarkPosition: String, CaseIterable, Codable, Identifiable {
    case topLeft, topRight, center, bottomLeft, bottomRight

    var id: String { rawValue }

    static func sanitized(_ value: String) -> MediaImageWatermarkPosition {
        MediaImageWatermarkPosition(rawValue: value) ?? .bottomRight
    }
}

enum MediaImageBackground: String, CaseIterable, Codable, Identifiable {
    case transparent, white, black

    var id: String { rawValue }

    static func sanitized(_ value: String) -> MediaImageBackground {
        MediaImageBackground(rawValue: value) ?? .transparent
    }
}

struct MediaImageWatermark: Codable, Equatable {
    var kind: MediaImageWatermarkKind
    var text: String
    var logoPath: String
    var position: MediaImageWatermarkPosition
    var opacity: Double
    var margin: Int
    var scale: Double

    init(kind: MediaImageWatermarkKind = .off,
         text: String = "",
         logoPath: String = "",
         position: MediaImageWatermarkPosition = .bottomRight,
         opacity: Double = 0.45,
         margin: Int = 32,
         scale: Double = 0.18) {
        self.kind = kind
        self.text = text
        self.logoPath = logoPath
        self.position = position
        self.opacity = MediaSupport.sanitizedOpacity(opacity)
        self.margin = MediaSupport.sanitizedImageDimension(margin, fallback: 32, min: 0, max: 2000)
        self.scale = MediaSupport.sanitizedWatermarkScale(scale)
    }

    static let off = MediaImageWatermark()

    var usesText: Bool {
        (kind == .text || kind == .textAndLogo) && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var usesLogo: Bool {
        (kind == .logo || kind == .textAndLogo) && !logoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isEnabled: Bool { usesText || usesLogo }
}

struct MediaImageRenamePattern: Codable, Equatable {
    var rawValue: String

    init(_ rawValue: String = "") {
        self.rawValue = rawValue
    }

    static let automatic = MediaImageRenamePattern()

    func outputBaseName(for inputURL: URL,
                        index: Int,
                        date: Date = Date(),
                        size: CGSize,
                        format: MediaImageFormat) -> String {
        let pattern = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{name}" : rawValue
        let baseName = MediaSupport.visibleOutputBaseName(for: inputURL)
        var output = pattern
            .replacingOccurrences(of: "{name}", with: baseName)
            .replacingOccurrences(of: "{date}", with: Self.dateFormatter.string(from: date))
            .replacingOccurrences(of: "{time}", with: Self.timeFormatter.string(from: date))
            .replacingOccurrences(of: "{datetime}", with: Self.dateTimeFormatter.string(from: date))
            .replacingOccurrences(of: "{width}", with: "\(max(1, Int(size.width.rounded())))")
            .replacingOccurrences(of: "{height}", with: "\(max(1, Int(size.height.rounded())))")
            .replacingOccurrences(of: "{format}", with: format.fileExtension)
            .replacingOccurrences(of: "{ext}", with: format.fileExtension)
            .replacingOccurrences(of: "{index}", with: "\(max(1, index))")
            .replacingOccurrences(of: "{counter}", with: "\(max(1, index))")
        for digits in 2...6 {
            output = output.replacingOccurrences(of: "{index:0\(digits)}",
                                                 with: String(format: "%0\(digits)d", max(1, index)))
            output = output.replacingOccurrences(of: "{counter:0\(digits)}",
                                                 with: String(format: "%0\(digits)d", max(1, index)))
        }
        let clean = MediaSupport.sanitizedFileBaseName(output)
        return clean.isEmpty ? baseName : clean
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HHmmss"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

struct MediaImageOptions: Codable, Equatable {
    var quality: Double
    var maxDimension: Int
    var format: MediaImageFormat
    var stripMetadata: Bool
    var resizeMode: MediaImageResizeMode
    var watermark: MediaImageWatermark
    var renamePattern: MediaImageRenamePattern
    var background: MediaImageBackground
    var preserveModificationDate: Bool

    init(quality: Double,
         maxDimension: Int,
         format: MediaImageFormat,
         stripMetadata: Bool,
         resizeMode: MediaImageResizeMode? = nil,
         watermark: MediaImageWatermark = .off,
         renamePattern: MediaImageRenamePattern = .automatic,
         background: MediaImageBackground = .transparent,
         preserveModificationDate: Bool = false) {
        self.quality = MediaSupport.sanitizedQuality(quality)
        self.maxDimension = MediaSupport.sanitizedPixelDimension(Double(maxDimension), fallback: 1600)
        self.format = format
        self.stripMetadata = stripMetadata
        self.resizeMode = resizeMode ?? .maxDimension(self.maxDimension)
        self.watermark = watermark
        self.renamePattern = renamePattern
        self.background = background
        self.preserveModificationDate = preserveModificationDate
    }
}

struct MediaImageProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var options: MediaImageOptions

    init(id: String = UUID().uuidString, name: String, options: MediaImageOptions) {
        self.id = id
        self.name = name
        self.options = options
    }
}

enum MediaVideoCodec: String, CaseIterable, Identifiable {
    case h264, hevc

    var id: String { rawValue }

    static func sanitized(_ value: String) -> MediaVideoCodec {
        MediaVideoCodec(rawValue: value) ?? .h264
    }
}

/// Uniform Type Identifiers normally provide their conformance graph through
/// LaunchServices. That service is not always available to the standalone
/// helper/tests (and can briefly be unavailable during login), so keep a
/// small identifier fallback for the media families this app accepts. The
/// system conformance result remains authoritative whenever it is available.
enum VorssaintUTTypeSupport {
    static func conforms(identifier: String, to expected: UTType) -> Bool {
        let actualID = identifier.lowercased()
        let expectedID = expected.identifier.lowercased()
        if actualID == expectedID { return true }
        if let actual = UTType(identifier), actual.conforms(to: expected) { return true }

        switch expectedID {
        case UTType.image.identifier.lowercased():
            return imageIdentifiers.contains(actualID)
        case UTType.movie.identifier.lowercased(), UTType.video.identifier.lowercased():
            return movieIdentifiers.contains(actualID)
        case UTType.audio.identifier.lowercased():
            return audioIdentifiers.contains(actualID)
        case UTType.archive.identifier.lowercased():
            return archiveIdentifiers.contains(actualID)
        case UTType.text.identifier.lowercased():
            return textIdentifiers.contains(actualID)
        default:
            return false
        }
    }

    private static let imageIdentifiers: Set<String> = [
        "public.image", "public.jpeg", "public.png", "public.tiff", "public.gif",
        "public.heic", "public.heif", "public.camera-raw-image", "com.apple.icns",
        "org.webmproject.webp",
    ]

    private static let movieIdentifiers: Set<String> = [
        "public.movie", "public.video", "public.mpeg-4", "public.mpeg",
        "public.avi", "public.3gpp", "public.3gpp2", "public.m2ts",
        "com.apple.quicktime-movie", "public.quicktime-movie",
    ]

    private static let audioIdentifiers: Set<String> = [
        "public.audio", "public.mp3", "public.mpeg-4-audio", "public.aiff-audio",
        "public.wav", "public.flac", "public.midi-audio", "public.ac3-audio",
        "com.microsoft.waveform-audio",
    ]

    private static let archiveIdentifiers: Set<String> = [
        "public.archive", "public.zip-archive", "public.tar-archive",
        "public.bzip2-archive", "public.gzip-archive", "public.7z-archive",
    ]

    private static let textIdentifiers: Set<String> = [
        "public.text", "public.plain-text", "public.utf8-plain-text",
        "public.utf16-plain-text", "public.rtf", "com.apple.traditional-mac-plain-text",
    ]
}

struct MediaTrimRange: Equatable {
    let start: Double
    let end: Double

    var duration: Double { max(0, end - start) }
}

enum MediaSupport {
    static let maxImageRenderDimension = 20_000
    static let maxImageRenderPixels = 8_192 * 8_192
    private static let maxFilenameBytes = 255

    static func sanitizedTool(_ value: String) -> MediaTool {
        MediaTool(rawValue: value) ?? .videoCompressor
    }

    static func sanitizedQuality(_ value: Double) -> Double {
        guard value.isFinite else { return 0.7 }
        return min(1, max(0.1, value))
    }

    static func sanitizedFPS(_ value: Double, fallback: Double = 12, maxFPS: Double = 60) -> Double {
        guard value.isFinite, value > 0 else { return fallback }
        return min(maxFPS, max(1, value.rounded()))
    }

    static func sanitizedPixelDimension(_ value: Double, fallback: Int, min: Int = 64, max: Int = 7680) -> Int {
        guard value.isFinite, value > 0 else { return even(fallback) }
        return even(Swift.min(max, Swift.max(min, Int(value.rounded()))))
    }

    static func sanitizedImageDimension(_ value: Int, fallback: Int, min: Int = 1, max: Int = 20_000) -> Int {
        let clean = value > 0 ? value : fallback
        return Swift.min(max, Swift.max(min, clean))
    }

    static func sanitizedOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return 0.45 }
        return min(1, max(0.1, value))
    }

    static func sanitizedWatermarkScale(_ value: Double) -> Double {
        guard value.isFinite else { return 0.18 }
        return min(0.8, max(0.05, value))
    }

    static func sanitizedTrim(start: Double, end: Double, assetDuration: Double) -> MediaTrimRange {
        guard assetDuration.isFinite, assetDuration > 0 else {
            return MediaTrimRange(start: 0, end: 0)
        }
        let cleanStart = start.isFinite ? max(0, min(start, assetDuration)) : 0
        let proposedEnd = end.isFinite && end > 0 ? end : assetDuration
        let cleanEnd = max(cleanStart, min(proposedEnd, assetDuration))
        return MediaTrimRange(start: cleanStart, end: cleanEnd)
    }

    static func scaledEvenSize(source: CGSize, maxDimension: Int) -> CGSize {
        let width = max(1, abs(source.width))
        let height = max(1, abs(source.height))
        let maxSide = CGFloat(max(2, maxDimension))
        let scale = min(1, maxSide / max(width, height))
        return CGSize(width: CGFloat(even(max(2, Int((width * scale).rounded())))),
                      height: CGFloat(even(max(2, Int((height * scale).rounded())))))
    }

    static func scaledVideoSize(source: CGSize, maxDimension: Int) -> CGSize {
        let size = scaledEvenSize(source: source, maxDimension: maxDimension)
        return CGSize(width: CGFloat(multipleOf16(Int(size.width))),
                      height: CGFloat(multipleOf16(Int(size.height))))
    }

    static func outputURL(for inputURL: URL, suffix: String, fileExtension: String) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let base = visibleOutputBaseName(for: inputURL)
        return outputURL(in: directory, baseName: "\(base)\(suffix)", fileExtension: fileExtension)
    }

    static func outputURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        directory
            .appendingPathComponent(sanitizedFileBaseName(baseName,
                                                          fileExtension: fileExtension,
                                                          uniquenessSuffixByteReservation: 4))
            .appendingPathExtension(fileExtension)
    }

    static func visibleOutputBaseName(for inputURL: URL) -> String {
        let raw = inputURL.deletingPathExtension().lastPathComponent
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = trimmed.drop { $0 == "." }
        return visible.isEmpty ? "Output" : String(visible)
    }

    static func uniqueOutputURL(for inputURL: URL, suffix: String, fileExtension: String,
                                fileManager: FileManager = .default) -> URL {
        let candidate = outputURL(for: inputURL, suffix: suffix, fileExtension: fileExtension)
        return uniqueOutputURL(candidate: candidate, fileManager: fileManager)
    }

    static func uniqueOutputURL(in directory: URL, baseName: String, fileExtension: String,
                                reservedPaths: Set<String> = [],
                                fileManager: FileManager = .default) -> URL {
        uniqueOutputURL(candidate: outputURL(in: directory, baseName: baseName, fileExtension: fileExtension),
                        reservedPaths: reservedPaths,
                        fileManager: fileManager)
    }

    static func imageOutputURL(for inputURL: URL,
                               outputDirectory: URL,
                               options: MediaImageOptions,
                               index: Int,
                               outputSize: CGSize,
                               reservedPaths: Set<String> = [],
                               fileManager: FileManager = .default) -> URL {
        let baseName = options.renamePattern.outputBaseName(for: inputURL,
                                                            index: index,
                                                            size: outputSize,
                                                            format: options.format)
        return uniqueOutputURL(in: outputDirectory,
                               baseName: baseName,
                               fileExtension: options.format.fileExtension,
                               reservedPaths: reservedPaths,
                               fileManager: fileManager)
    }

    static func sanitizedFileBaseName(_ value: String,
                                      fileExtension: String = "",
                                      uniquenessSuffixByteReservation: Int = 0) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\\0")
            .union(.newlines)
            .union(.controlCharacters)
        let parts = value.components(separatedBy: invalid)
        let clean = parts.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        let visible = clean.isEmpty ? "Output" : clean
        let extensionBytes = fileExtension.isEmpty ? 0 : fileExtension.utf8.count + 1
        let byteLimit = max(1, maxFilenameBytes - extensionBytes - max(0, uniquenessSuffixByteReservation))
        guard visible.utf8.count > byteLimit else { return visible }
        let shortened = prefix(visible, maxUTF8Bytes: byteLimit)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        return shortened.isEmpty ? "Output" : shortened
    }

    static func imageDisplaySize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else { return nil }
        return imageDisplaySize(properties: properties)
    }

    static func imageDisplaySize(properties: [CFString: Any]) -> CGSize? {
        guard let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if 5...8 ~= orientation {
            return integralImageSize(width: CGFloat(height), height: CGFloat(width))
        }
        return integralImageSize(width: CGFloat(width), height: CGFloat(height))
    }

    static func imageRenderSizeIsSafe(_ size: CGSize,
                                      maxDimension: Int = maxImageRenderDimension,
                                      maxPixels: Int = maxImageRenderPixels) -> Bool {
        let width = abs(size.width)
        let height = abs(size.height)
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width <= CGFloat(maxDimension), height <= CGFloat(maxDimension) else { return false }
        return width * height <= CGFloat(maxPixels)
    }

    static func sanitizedImageProfiles(_ profiles: [MediaImageProfile]) -> [MediaImageProfile] {
        var seenIDs = Set<String>()
        return profiles.enumerated().map { offset, profile in
            let trimmedID = profile.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = trimmedID.isEmpty || seenIDs.contains(trimmedID) ? UUID().uuidString : trimmedID
            seenIDs.insert(id)
            let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmedName.isEmpty ? "Profile \(offset + 1)" : trimmedName
            return MediaImageProfile(id: id, name: name, options: profile.options)
        }
    }

    static func integralImageSize(width: CGFloat, height: CGFloat) -> CGSize {
        CGSize(width: max(1, Int(width.rounded())),
               height: max(1, Int(height.rounded())))
    }

    private static func uniqueOutputURL(candidate: URL,
                                        reservedPaths: Set<String> = [],
                                        fileManager: FileManager = .default) -> URL {
        guard !reservedPaths.contains(candidate.standardizedFileURL.path),
              !fileManager.fileExists(atPath: candidate.path) else {
            let directory = candidate.deletingLastPathComponent()
            let base = candidate.deletingPathExtension().lastPathComponent
            let ext = candidate.pathExtension
            for index in 2...999 {
                let url = directory.appendingPathComponent("\(base) \(index)").appendingPathExtension(ext)
                if !reservedPaths.contains(url.standardizedFileURL.path),
                   !fileManager.fileExists(atPath: url.path) { return url }
            }
            return candidate
        }
        return candidate
    }

    static func makeVisibleIfNeeded(_ outputURL: URL, fileManager: FileManager = .default) {
        guard shouldForceVisibleOutput(outputURL),
              fileManager.fileExists(atPath: outputURL.path) else { return }
        try? (outputURL as NSURL).setResourceValue(false, forKey: .isHiddenKey)
        var info = stat()
        guard outputURL.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return lstat(path, &info) == 0
        }) else { return }
        let flags = UInt32(info.st_flags)
        let visibleFlags = flags & ~UInt32(UF_HIDDEN)
        guard visibleFlags != flags else { return }
        outputURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = chflags(path, visibleFlags)
        }
    }

    /// Whether a dropped file fits the selected tool, mirroring the open
    /// panel's filter. Without this, dropping a PDF on the image tool would
    /// "succeed" by silently rasterizing page one (ImageIO opens PDFs).
    static func inputMatchesTool(contentType: UTType?, inputTypes: [UTType]) -> Bool {
        guard let contentType else { return false }
        return inputTypes.contains {
            VorssaintUTTypeSupport.conforms(identifier: contentType.identifier, to: $0)
        }
    }

    /// Whether the result deserves the "came out larger" caption: growth is
    /// normal (PDF wraps the image, high quality can beat the source) but a
    /// "compressor" should say so instead of looking broken. Unknown sizes
    /// (zero) never trigger it.
    static func outputGrew(originalBytes: Int64, outputBytes: Int64) -> Bool {
        originalBytes > 0 && outputBytes > originalBytes
    }

    static func recognitionLanguages(for languageRawValue: String) -> [String] {
        switch languageRawValue {
        case "pt-BR": return ["pt-BR", "en-US"]
        case "tr": return ["tr-TR", "en-US"]
        case "ru": return ["ru-RU", "en-US"]
        case "es": return ["es-ES", "en-US"]
        case "de": return ["de-DE", "en-US"]
        case "fr": return ["fr-FR", "en-US"]
        case "it": return ["it-IT", "en-US"]
        case "ja": return ["ja-JP", "en-US"]
        case "ko": return ["ko-KR", "en-US"]
        case "zh-Hans": return ["zh-Hans", "en-US"]
        case "zh-TW", "zh-HK": return ["zh-Hant", "en-US"]
        default: return ["en-US"]
        }
    }

    private static func shouldForceVisibleOutput(_ outputURL: URL) -> Bool {
        let name = outputURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !name.hasPrefix(".")
    }

    private static func even(_ value: Int) -> Int {
        let positive = max(2, value)
        return positive.isMultiple(of: 2) ? positive : positive - 1
    }

    private static func multipleOf16(_ value: Int) -> Int {
        max(16, (max(16, value) / 16) * 16)
    }

    private static func prefix(_ value: String, maxUTF8Bytes: Int) -> String {
        var result = ""
        var usedBytes = 0
        for character in value {
            let count = String(character).utf8.count
            guard usedBytes + count <= maxUTF8Bytes else { break }
            result.append(character)
            usedBytes += count
        }
        return result
    }
}
