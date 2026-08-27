// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FileOutputSupport {
    private static let maxFilenameBytes = 255

    static func outputURL(for inputURL: URL, suffix: String, fileExtension: String) -> URL {
        outputURL(in: inputURL.deletingLastPathComponent(),
                  baseName: "\(visibleBaseName(for: inputURL))\(suffix)",
                  fileExtension: fileExtension)
    }

    static func outputURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        directory
            .appendingPathComponent(sanitizedBaseName(baseName,
                                                       fileExtension: fileExtension,
                                                       uniquenessSuffixByteReservation: 4))
            .appendingPathExtension(fileExtension)
    }

    static func visibleBaseName(for inputURL: URL) -> String {
        let raw = inputURL.deletingPathExtension().lastPathComponent
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = trimmed.drop { $0 == "." }
        return visible.isEmpty ? "Output" : String(visible)
    }

    static func uniqueOutputURL(for inputURL: URL, suffix: String, fileExtension: String,
                                fileManager: FileManager = .default) -> URL {
        uniqueOutputURL(candidate: outputURL(for: inputURL,
                                             suffix: suffix,
                                             fileExtension: fileExtension),
                        fileManager: fileManager)
    }

    static func uniqueOutputURL(in directory: URL, baseName: String, fileExtension: String,
                                reservedPaths: Set<String> = [],
                                fileManager: FileManager = .default) -> URL {
        uniqueOutputURL(candidate: outputURL(in: directory,
                                             baseName: baseName,
                                             fileExtension: fileExtension),
                        reservedPaths: reservedPaths,
                        fileManager: fileManager)
    }

    static func sanitizedBaseName(_ value: String,
                                  fileExtension: String = "",
                                  uniquenessSuffixByteReservation: Int = 0) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\\0")
            .union(.newlines)
            .union(.controlCharacters)
        let clean = value.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        let visible = clean.isEmpty ? "Output" : clean
        let extensionBytes = fileExtension.isEmpty ? 0 : fileExtension.utf8.count + 1
        let byteLimit = max(1, maxFilenameBytes - extensionBytes
                            - max(0, uniquenessSuffixByteReservation))
        guard visible.utf8.count > byteLimit else { return visible }
        let shortened = prefix(visible, maxUTF8Bytes: byteLimit)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        return shortened.isEmpty ? "Output" : shortened
    }

    static func uniqueOutputURL(candidate: URL,
                                reservedPaths: Set<String> = [],
                                fileManager: FileManager = .default) -> URL {
        guard reservedPaths.contains(candidate.standardizedFileURL.path)
                || fileManager.fileExists(atPath: candidate.path)
        else { return candidate }

        let directory = candidate.deletingLastPathComponent()
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var index = 2
        while true {
            let suffix = " \(index)"
            let uniqueBase = sanitizedBaseName(base,
                                               fileExtension: ext,
                                               uniquenessSuffixByteReservation: suffix.utf8.count)
            let url = directory.appendingPathComponent("\(uniqueBase)\(suffix)")
                .appendingPathExtension(ext)
            if !reservedPaths.contains(url.standardizedFileURL.path),
               !fileManager.fileExists(atPath: url.path) { return url }
            index += 1
        }
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
