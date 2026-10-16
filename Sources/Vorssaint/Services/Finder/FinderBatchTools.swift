// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

enum FinderBatchTools {
    /// A pattern is interpreted as a filename only, never as shell syntax.
    static func renameChanges(_ inputs: [URL], pattern: String) -> [FinderFileActions.RenameChange] {
        inputs.enumerated().map { index, input in
            let replacements = ["{name}": input.lastPathComponent,
                                "{stem}": input.deletingPathExtension().lastPathComponent,
                                "{ext}": input.pathExtension,
                                "{n}": String(index + 1)]
            // Replace tokens in the pattern in one pass: filenames containing
            // token-like text must not be interpreted again.
            var name = ""
            var remaining = pattern[...]
            while !remaining.isEmpty {
                if let token = ["{name}", "{stem}", "{ext}", "{n}"].first(where: { remaining.hasPrefix($0) }) {
                    name += replacements[token]!
                    remaining = remaining.dropFirst(token.count)
                } else { name.append(remaining.removeFirst()) }
            }
            return .init(source: input, newName: name)
        }
    }

    /// Two-phase renaming permits swaps. Any interrupted transaction attempts
    /// rollback without replacing files created by another process.
    static func rename(_ plan: FinderFileActions.RenamePlan,
                       cancellation: FinderToolsCancellation) throws -> [URL] {
        let renames = plan.renames.filter { $0.source.path != $0.destination.path }
        for (index, item) in renames.enumerated() {
            let prefix = item.source.standardizedFileURL.path + "/"
            guard !renames.enumerated().contains(where: {
                $0.offset != index && $0.element.source.standardizedFileURL.path.hasPrefix(prefix)
            }) else { throw FinderFileActionError.invalidRequest("Rename folders and their children in separate operations.") }
        }
        struct Staged {
            let source: URL
            let temporary: URL
            let destination: URL
            var committed: Bool
        }
        var staged: [Staged] = []
        do {
            for item in renames {
                try cancellation.check()
                let temporary = item.source.deletingLastPathComponent()
                    .appendingPathComponent(".vorssaint-rename-" + UUID().uuidString)
                try moveExclusively(item.source, to: temporary)
                staged.append(Staged(source: item.source, temporary: temporary,
                                     destination: item.destination, committed: false))
            }
            for index in staged.indices {
                try cancellation.check()
                try moveExclusively(staged[index].temporary, to: staged[index].destination)
                staged[index].committed = true
            }
            return plan.renames.map(\.destination)
        } catch {
            let originalError = error
            var recoveryFailures: [FinderFileActionItemFailure] = []
            // First restore committed files to staging so cycles can be unwound.
            for index in staged.indices where staged[index].committed {
                do {
                    try moveExclusively(staged[index].destination, to: staged[index].temporary)
                    staged[index].committed = false
                } catch {
                    recoveryFailures.append(.init(url: staged[index].destination, reason: error.localizedDescription))
                }
            }
            for item in staged.reversed() where !item.committed {
                do { try moveExclusively(item.temporary, to: item.source) }
                catch { recoveryFailures.append(.init(url: item.temporary, reason: error.localizedDescription)) }
            }
            if !recoveryFailures.isEmpty {
                throw FinderFileActionError.partialFailure(operation: "rename and restore original names",
                    completed: staged.filter(\.committed).map(\.destination), failures: recoveryFailures)
            }
            throw originalError
        }
    }

    /// Groups content-identical regular files; links and repeated paths are ignored.
    static func duplicates(in inputs: [URL], cancellation: FinderToolsCancellation) throws -> [[URL]] {
        var bySize: [Int64: [URL]] = [:]
        var seen = Set<String>()
        var pending = inputs
        var examined = 0
        while let input = pending.popLast() {
            try cancellation.check()
            let values = try input.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { continue }
            let canonical = input.resolvingSymlinksInPath().standardizedFileURL
            let path = canonical.path
            guard seen.insert(path).inserted else { continue }
            examined += 1
            guard examined <= 100_000 else {
                throw FinderFileActionError.invalidRequest("The scan exceeds 100,000 items. Select a smaller folder.")
            }
            if values.isDirectory == true {
                pending += try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            } else if values.isRegularFile == true, let size = values.fileSize {
                bySize[Int64(size), default: []].append(canonical)
            }
        }
        var groups: [[URL]] = []
        for candidates in bySize.values where candidates.count > 1 {
            var byHash: [String: [URL]] = [:]
            for file in candidates {
                let digest = try FinderFileActions.sha256(of: file, checkCancellation: cancellation.check)
                byHash[digest, default: []].append(file)
            }
            groups += byHash.values.filter { $0.count > 1 }.map { $0.sorted { $0.path < $1.path } }
        }
        return groups.sorted { $0[0].path < $1[0].path }
    }

    private static func moveExclusively(_ source: URL, to destination: URL) throws {
        let status = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL))
            }
        }
        guard status == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                          userInfo: [NSFilePathErrorKey: destination.path])
        }
    }
}
