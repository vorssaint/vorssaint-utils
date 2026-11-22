// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import AppKit
import CryptoKit

enum FileAction: String, CaseIterable, Hashable {
    case reveal = "Reveal", copy = "Copy Files", paths = "Copy Paths", duplicate = "Duplicate", hash = "SHA-256"
    var symbol: String {
        switch self {
        case .reveal: return "folder"
        case .copy: return "doc.on.doc"
        case .paths: return "link"
        case .duplicate: return "plus.square.on.square"
        case .hash: return "number"
        }
    }

    static func duplicateFiles(_ urls: [URL]) throws -> [URL] {
        try urls.map { source in
            let destination = ConversionMatrix.uniqueURL(directory: source.deletingLastPathComponent(), baseName: source.deletingPathExtension().lastPathComponent, suffix: "copy", ext: source.pathExtension)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
    }

    static func hashReport(_ urls: [URL]) throws -> String {
        try urls.map { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { throw OpenTangerineError.unreadable(url) }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var hash = SHA256()
            while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
                try Task.checkCancellation()
                hash.update(data: data)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined() + "  " + url.lastPathComponent
        }.joined(separator: "\n")
    }
}

