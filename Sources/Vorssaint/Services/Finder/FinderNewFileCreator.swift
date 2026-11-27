// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderNewFileCreator {
    /// Exclusive creation is also used by MenuWish. Never truncate an
    /// existing document, even when another process wins a naming race.
    static func create(_ kind: FinderNewFileKind, in directory: URL, templates: URL?) throws -> URL {
        try create(builtInContents(kind, templates: templates), filename: "Untitled", suffix: kind.rawValue, in: directory)
    }

    private static func builtInContents(_ kind: FinderNewFileKind, templates: URL?) throws -> Data {
        if kind.usesTemplate {
            guard let templates else { throw CocoaError(.fileReadNoSuchFile) }
            let data = try Data(contentsOf: templates.appendingPathComponent("Blank.\(kind.rawValue)"))
            guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            return data
        }
        return kind == .json ? Data("{}\n".utf8) : Data()
    }

    static func create(_ item: FinderNewFileItem, in directory: URL,
                       templateDirectory: URL?, bundledTemplates: URL? = nil) throws -> URL {
        guard let item = item.normalized else { throw CocoaError(.fileWriteInvalidFileName) }
        let contents: Data
        if let template = item.template {
            guard let templateDirectory else { throw CocoaError(.fileReadNoSuchFile) }
            contents = try FinderNewFileTemplateStore.read(templateDirectory.appendingPathComponent(template.id.uuidString))
        } else if item.hasBuiltInContent, let kind = item.builtIn {
            contents = try builtInContents(kind, templates: bundledTemplates)
        } else {
            contents = Data()
        }
        return try create(contents, filename: item.filename, suffix: item.suffix, in: directory)
    }

    private static func create(_ contents: Data, filename: String, suffix: String, in directory: URL) throws -> URL {
        guard FinderNewFileRequest.isLocalDirectoryURL(directory) else { throw CocoaError(.fileWriteInvalidFileName) }
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        guard values.isDirectory == true, values.isPackage != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let ext = suffix.isEmpty ? "" : "." + suffix
        for number in 1...10_000 {
            let numberSuffix = number == 1 ? "" : " \(number)"
            let file = directory.appendingPathComponent(filename + numberSuffix + ext)
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


/// Templates are private user data, not bundle resources or shared menu
/// preferences. Store an immutable copy under a generated identifier.
enum FinderNewFileTemplateStore {
    static var directory: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("FinderNewFileTemplates", isDirectory: true)
    }

    static func read(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize else { throw CocoaError(.fileReadUnknown) }
        guard size <= FinderNewFileItem.maximumTemplateBytes else { throw CocoaError(.fileReadTooLarge) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        let limit = FinderNewFileItem.maximumTemplateBytes
        while let chunk = try handle.read(upToCount: min(1024 * 1024, limit - data.count + 1)),
              !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        }
        return data
    }

    static func importFile(_ source: URL, into root: URL? = directory,
                           container: URL? = PrivateFileStore.containerURL) throws -> FinderNewFileItem.Template {
        guard let root else { throw CocoaError(.fileWriteNoPermission) }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let contents = try read(source.resolvingSymlinksInPath())
        let template = FinderNewFileItem.Template(id: UUID(), name: source.lastPathComponent)
        guard PrivateFileStore.createDirectory(at: root, container: container),
              PrivateFileStore.write(contents, to: root.appendingPathComponent(template.id.uuidString)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return template
    }

    static func remove(_ template: FinderNewFileItem.Template, from root: URL? = directory) {
        guard let root else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(template.id.uuidString))
    }
}
