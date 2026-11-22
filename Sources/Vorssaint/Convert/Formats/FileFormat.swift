// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import Foundation
import UniformTypeIdentifiers

enum FormatCategory: String, CaseIterable {
    case image
    case audio
    case video
    case document
    case subtitle
    case archive

    var symbol: String {
        switch self {
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .document: return "doc.text"
        case .subtitle: return "captions.bubble"
        case .archive: return "archivebox"
        }
    }

    var title: String {
        switch self {
        case .image: return "Image"
        case .audio: return "Audio"
        case .video: return "Video"
        case .document: return "Document"
        case .subtitle: return "Subtitle"
        case .archive: return "Archive"
        }
    }
}

enum FileFormat: String, CaseIterable, Identifiable, Hashable {
    case jpg, png, webp, heic, tiff, svg, avif, bmp, gif
    case mp3, m4a, wav, flac, ogg, opus, aiff, wma
    case mp4, mov, mkv, webm, avi, wmv
    case pdf, docx, txt
    case srt, vtt
    case zip, tar, gz, rar

    var id: String { rawValue }

    static let images: [FileFormat] = [.jpg, .png, .webp, .heic, .tiff, .svg, .avif, .bmp]
    static let imageTargets: [FileFormat] = [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .pdf]
    static let audio: [FileFormat] = [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma]
    static let video: [FileFormat] = [.mp4, .mov, .mkv, .webm, .avi, .wmv]
    static let subtitles: [FileFormat] = [.srt, .vtt]
    static let archives: [FileFormat] = [.zip, .tar, .gz, .rar]

    var category: FormatCategory {
        switch self {
        case .jpg, .png, .webp, .heic, .tiff, .svg, .avif, .bmp: return .image
        case .gif: return .video
        case .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma: return .audio
        case .mp4, .mov, .mkv, .webm, .avi, .wmv: return .video
        case .pdf, .docx, .txt: return .document
        case .srt, .vtt: return .subtitle
        case .zip, .tar, .gz, .rar: return .archive
        }
    }

    var displayName: String {
        switch self {
        case .gz: return "GZIP"
        default: return rawValue.uppercased()
        }
    }

    var fileExtension: String {
        switch self {
        case .gz: return "tar.gz"
        default: return rawValue
        }
    }

    var aliases: [String] {
        switch self {
        case .jpg: return ["jpg", "jpeg", "jpe", "jfif"]
        case .tiff: return ["tiff", "tif"]
        case .heic: return ["heic", "heif"]
        case .m4a: return ["m4a", "aac", "m4b"]
        case .mp4: return ["mp4", "m4v"]
        case .mov: return ["mov", "qt"]
        case .gz: return ["gz", "tgz"]
        case .txt: return ["txt", "text", "md", "log"]
        case .aiff: return ["aiff", "aif"]
        default: return [rawValue]
        }
    }

    var utType: UTType? {
        switch self {
        case .jpg: return .jpeg
        case .png: return .png
        case .webp: return .webP
        case .heic: return .heic
        case .tiff: return .tiff
        case .svg: return .svg
        case .avif: return UTType("public.avif")
        case .bmp: return .bmp
        case .gif: return .gif
        case .mp3: return .mp3
        case .m4a: return .mpeg4Audio
        case .wav: return .wav
        case .flac: return UTType("org.xiph.flac")
        case .ogg: return UTType("org.xiph.ogg-audio") ?? UTType("public.ogg")
        case .opus: return UTType("public.opus") ?? UTType("org.xiph.opus")
        case .aiff: return .aiff
        case .wma: return UTType("com.microsoft.windows-media-wma")
        case .mp4: return .mpeg4Movie
        case .mov: return .quickTimeMovie
        case .mkv: return UTType("org.matroska.mkv")
        case .webm: return UTType("org.webmproject.webm")
        case .avi: return .avi
        case .wmv: return UTType("com.microsoft.windows-media-wmv")
        case .pdf: return .pdf
        case .docx: return UTType("org.openxmlformats.wordprocessingml.document")
        case .txt: return .plainText
        case .srt: return UTType("com.subrip.srt") ?? .plainText
        case .vtt: return UTType("org.w3.webvtt") ?? .plainText
        case .zip: return .zip
        case .tar: return UTType("public.tar-archive")
        case .gz: return .gzip
        case .rar: return UTType("com.rarlab.rar-archive")
        }
    }

    static func detect(_ url: URL) -> FileFormat? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .gz }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return allCases.first { $0.aliases.contains(ext) }
    }

    static func detect(extension ext: String) -> FileFormat? {
        let lower = ext.lowercased()
        return allCases.first { $0.aliases.contains(lower) }
    }

    var isMultiTrack: Bool { category == .video || category == .audio }
}

