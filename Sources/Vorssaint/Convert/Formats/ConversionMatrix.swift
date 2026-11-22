// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import Foundation

enum ConversionMatrix {
    static func targets(for source: FileFormat) -> [FileFormat] {
        let list: [FileFormat]
        switch source {
        case .jpg, .png:
            list = FileFormat.imageTargets + [.docx, .txt]
        case .svg:
            list = FileFormat.imageTargets
        case .webp, .heic, .tiff, .avif, .bmp:
            list = FileFormat.imageTargets + [.txt]
        case .mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff, .wma:
            list = FileFormat.audio
        case .mp4, .mov, .mkv, .webm, .avi, .wmv:
            list = FileFormat.video + [.gif, .mp3]
        case .gif:
            list = FileFormat.video
        case .pdf:
            list = [.docx, .jpg, .png, .txt]
        case .txt:
            list = [.pdf, .jpg, .png, .srt, .vtt]
        case .srt, .vtt:
            list = FileFormat.subtitles + [.txt]
        case .zip, .tar, .gz, .rar:
            list = [.zip, .tar, .gz]
        case .docx:
            list = []
        }
        return list.filter { $0 != source }
    }

    static func targets(for sources: [FileFormat]) -> [FileFormat] {
        guard let first = sources.first else { return [] }
        var common = targets(for: first)
        for source in sources.dropFirst() {
            let next = Set(targets(for: source))
            common = common.filter { next.contains($0) }
        }
        return common
    }

    static var totalConversions: Int {
        FileFormat.allCases.reduce(0) { $0 + targets(for: $1).count }
    }

    static func outputURL(for source: URL, target: FileFormat, in directory: URL, existing: Set<String> = []) -> URL {
        let base = strippedBaseName(source.lastPathComponent)
        var candidate = "\(base).\(target.fileExtension)"
        var counter = 2
        let fm = FileManager.default
        while existing.contains(candidate) || fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(counter).\(target.fileExtension)"
            counter += 1
        }
        return directory.appendingPathComponent(candidate)
    }

    static func uniqueURL(directory: URL, baseName: String, suffix: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = suffix.isEmpty ? "\(baseName).\(ext)" : "\(baseName) \(suffix).\(ext)"
        var counter = 2
        while fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = suffix.isEmpty ? "\(baseName) \(counter).\(ext)" : "\(baseName) \(suffix) \(counter).\(ext)"
            counter += 1
        }
        return directory.appendingPathComponent(candidate)
    }

    static func uniqueDirectory(directory: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = name
        var counter = 2
        while fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(name) \(counter)"
            counter += 1
        }
        return directory.appendingPathComponent(candidate)
    }

    static func strippedBaseName(_ fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.hasSuffix(".tar.gz") { return String(fileName.dropLast(7)) }
        if lower.hasSuffix(".tgz") { return String(fileName.dropLast(4)) }
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return fileName }
        return String(fileName[..<dot])
    }
}

