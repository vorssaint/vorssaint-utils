// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import Foundation

struct ArchiveEngine: ConversionEngine {
    func supports(from: FileFormat, to: FileFormat) -> Bool {
        from.category == .archive && to.category == .archive && to != .rar
    }

    /// Archives are opened into a private folder and checked before anything
    /// is repacked or moved: no entry may name a path outside it, nothing may
    /// link out of it, and the total stays bounded.
    func convert(_ request: ConversionRequest) async throws {
        let staging = try await ArchiveSafety.extractSafely(request.source, engine: self)
        defer { try? FileManager.default.removeItem(at: staging) }
        request.progress(0.5)
        try await pack(staging, as: request.target, to: request.destination)
        request.progress(1)
    }

    func extract(_ archive: URL, format: FileFormat, into directory: URL) async throws {
        switch format {
        case .zip:
            try await ZipTool.unzip(archive, into: directory)
        case .tar:
            let result = try await ConvertShell.run("/usr/bin/tar", ["-xf", archive.path, "-C", directory.path])
            guard result.succeeded else { throw OpenTangerineError.toolFailed("tar", result.stderr) }
        case .gz:
            let name = archive.lastPathComponent.lowercased()
            if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
                let result = try await ConvertShell.run("/usr/bin/tar", ["-xzf", archive.path, "-C", directory.path])
                guard result.succeeded else { throw OpenTangerineError.toolFailed("tar", result.stderr) }
            } else {
                let output = directory.appendingPathComponent(archive.deletingPathExtension().lastPathComponent)
                let result = try await ConvertShell.run("/bin/sh", ["-c", "/usr/bin/gunzip -c \"$0\" > \"$1\"", archive.path, output.path])
                guard result.succeeded else { throw OpenTangerineError.toolFailed("gunzip", result.stderr) }
            }
        case .rar:
            // 7-Zip comes with the app; the others are used if they are installed.
            if let sevenZip = SevenZip.path {
                let result = try await ConvertShell.run(sevenZip, ["x", "-y", "-snl-", "-o" + directory.path, archive.path])
                if result.succeeded { return }
            }
            let candidates = ["unar", "unrar", "bsdtar"]
            for tool in candidates {
                guard let path = ConvertShell.which(tool) else { continue }
                let args: [String]
                switch tool {
                case "unar": args = ["-q", "-o", directory.path, archive.path]
                case "unrar": args = ["x", "-y", "-idq", archive.path, directory.path + "/"]
                default: args = ["-xf", archive.path, "-C", directory.path]
                }
                let result = try await ConvertShell.run(path, args)
                if result.succeeded { return }
            }
            let bsdtar = try await ConvertShell.run("/usr/bin/tar", ["-xf", archive.path, "-C", directory.path])
            guard bsdtar.succeeded else {
                throw OpenTangerineError.toolFailed("rar", "Install `unar` (`brew install unar`) to extract RAR archives.")
            }
        default:
            throw OpenTangerineError.unsupportedConversion(format, .zip)
        }
    }

    func pack(_ directory: URL, as format: FileFormat, to destination: URL) async throws {
        switch format {
        case .zip:
            try await ZipTool.zip(directory: directory, to: destination)
        case .tar:
            let result = try await ConvertShell.run("/usr/bin/tar", ["-cf", destination.path, "-C", directory.path, "."])
            guard result.succeeded else { throw OpenTangerineError.toolFailed("tar", result.stderr) }
        case .gz:
            let result = try await ConvertShell.run("/usr/bin/tar", ["-czf", destination.path, "-C", directory.path, "."])
            guard result.succeeded else { throw OpenTangerineError.toolFailed("tar", result.stderr) }
        default:
            throw OpenTangerineError.unsupportedConversion(.zip, format)
        }
    }
}


/// The 7-Zip binary shipped inside the app, or one on the system.
enum SevenZip {
    static var path: String? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin/7zz").path,
           FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        return ConvertShell.which("7zz") ?? ConvertShell.which("7z")
    }
}

enum ArchiveSafety {
    static let maxEntries = 50_000
    static let maxBytes: Int64 = 8 * 1024 * 1024 * 1024

    /// Opens `archive` into a new private folder and returns it, or throws and
    /// leaves nothing behind.
    static func extractSafely(_ archive: URL, engine: ArchiveEngine = ArchiveEngine()) async throws -> URL {
        guard let format = FileFormat.detect(archive) else { throw OpenTangerineError.unreadable(archive) }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            // Names first: a hostile archive is refused before a byte is written.
            let names = try await entryNames(archive, format: format)
            guard names.count <= maxEntries else { throw OpenTangerineError.invalidInput("This archive holds too many files.") }
            for name in names where isUnsafe(name) {
                throw OpenTangerineError.invalidInput("This archive names a path outside its own folder (\(name)). It was not opened.")
            }
            try await engine.extract(archive, format: format, into: staging)
            try verify(staging)
            return staging
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    static func isUnsafe(_ name: String) -> Bool {
        if name.hasPrefix("/") || name.hasPrefix("~") { return true }
        return name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..")
    }

    private static func entryNames(_ archive: URL, format: FileFormat) async throws -> [String] {
        let result: ShellResult
        switch format {
        case .zip: result = try await ConvertShell.run("/usr/bin/zipinfo", ["-1", archive.path])
        case .tar, .gz: result = try await ConvertShell.run("/usr/bin/tar", ["-tf", archive.path])
        default:
            guard let sevenZip = SevenZip.path else { return [] }
            result = try await ConvertShell.run(sevenZip, ["l", "-slt", "-ba", archive.path])
            return result.stdout.split(separator: "\n").compactMap { line in
                line.hasPrefix("Path = ") ? String(line.dropFirst(7)) : nil
            }
        }
        guard result.succeeded else { throw OpenTangerineError.toolFailed("archive", result.stderr) }
        return result.stdout.split(separator: "\n").map(String.init)
    }

    /// After extraction: nothing escapes the folder through a link, and the size is bounded.
    private static func verify(_ folder: URL) throws {
        let root = folder.resolvingSymlinksInPath().path
        var total: Int64 = 0
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey],
                                                          options: []) else { return }
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            if values?.isSymbolicLink == true {
                let target = url.resolvingSymlinksInPath().path
                guard target == root || target.hasPrefix(root + "/") else {
                    throw OpenTangerineError.invalidInput("This archive links to a file outside its own folder. It was not opened.")
                }
            }
            total += Int64(values?.fileSize ?? 0)
            if total > maxBytes { throw OpenTangerineError.invalidInput("This archive is larger than 8 GB once opened.") }
        }
    }
}
