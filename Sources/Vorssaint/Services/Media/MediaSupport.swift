// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum MediaTool: String, CaseIterable, Identifiable {
    case videoCompressor, gifMaker, imageCompressor, textExtractor

    var id: String { rawValue }
}

enum MediaImageFormat: String, CaseIterable, Identifiable {
    case jpeg, heic, png

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .png: return "png"
        }
    }

    static func sanitized(_ value: String) -> MediaImageFormat {
        MediaImageFormat(rawValue: value) ?? .jpeg
    }
}

enum MediaVideoCodec: String, CaseIterable, Identifiable {
    case h264, hevc

    var id: String { rawValue }

    static func sanitized(_ value: String) -> MediaVideoCodec {
        MediaVideoCodec(rawValue: value) ?? .h264
    }
}

struct MediaTrimRange: Equatable {
    let start: Double
    let end: Double

    var duration: Double { max(0, end - start) }
}

enum MediaSupport {
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
        let base = inputURL.deletingPathExtension().lastPathComponent
        return directory
            .appendingPathComponent("\(base)\(suffix)")
            .appendingPathExtension(fileExtension)
    }

    static func uniqueOutputURL(for inputURL: URL, suffix: String, fileExtension: String,
                                fileManager: FileManager = .default) -> URL {
        let candidate = outputURL(for: inputURL, suffix: suffix, fileExtension: fileExtension)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }
        let directory = candidate.deletingLastPathComponent()
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        for index in 2...999 {
            let url = directory.appendingPathComponent("\(base) \(index)").appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: url.path) { return url }
        }
        return candidate
    }

    static func recognitionLanguages(for languageRawValue: String) -> [String] {
        switch languageRawValue {
        case "pt-BR": return ["pt-BR", "en-US"]
        case "es": return ["es-ES", "en-US"]
        case "de": return ["de-DE", "en-US"]
        case "fr": return ["fr-FR", "en-US"]
        case "it": return ["it-IT", "en-US"]
        case "ja": return ["ja-JP", "en-US"]
        case "zh-Hans": return ["zh-Hans", "en-US"]
        default: return ["en-US"]
        }
    }

    private static func even(_ value: Int) -> Int {
        let positive = max(2, value)
        return positive.isMultiple(of: 2) ? positive : positive - 1
    }

    private static func multipleOf16(_ value: Int) -> Int {
        max(16, (max(16, value) / 16) * 16)
    }
}
