// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderNewFileCreator {
    /// Exclusive creation is also used by MenuWish. Never truncate an
    /// existing document, even when another process wins a naming race.
    static func create(_ kind: FinderNewFileKind, in directory: URL, templates: URL?) throws -> URL {
        guard FinderNewFileRequest.isLocalDirectoryURL(directory) else { throw CocoaError(.fileWriteInvalidFileName) }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        guard values.isDirectory == true, values.isPackage != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let contents: Data
        if kind.usesTemplate {
            guard let templates else { throw CocoaError(.fileReadNoSuchFile) }
            contents = try Data(contentsOf: templates.appendingPathComponent("Blank.\(kind.rawValue)"))
            guard !contents.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        } else {
            contents = kind == .json ? Data("{}\n".utf8) : Data()
        }
        for number in 1...10_000 {
            let suffix = number == 1 ? "" : " \(number)"
            let file = directory.appendingPathComponent("Untitled\(suffix).\(kind.rawValue)")
            do {
                try contents.write(to: file, options: .withoutOverwriting)
                return file
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
