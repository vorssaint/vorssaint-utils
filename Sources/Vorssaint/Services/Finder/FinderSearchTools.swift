// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderSearchTools {
    static func search(in roots: [URL], query: String, cancellation: FinderToolsCancellation) throws -> [URL] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw FinderFileActionError.invalidRequest("Enter part of a filename to search.") }
        var matches: [URL] = []
        var visited = Set<URL>()
        var pending = roots
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        while let item = pending.popLast() {
            try cancellation.check()
            let values = try item.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, visited.insert(item.resolvingSymlinksInPath()).inserted else { continue }
            guard visited.count <= 100_000 else {
                throw FinderFileActionError.invalidRequest("The search reached 100,000 items. Choose a smaller folder.")
            }
            if item.lastPathComponent.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                matches.append(item)
                guard matches.count <= 5_000 else {
                    throw FinderFileActionError.invalidRequest("The search found more than 5,000 results. Use a more specific name.")
                }
            }
            if values.isDirectory == true && values.isPackage != true {
                pending += try FileManager.default.contentsOfDirectory(at: item,
                    includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            }
        }
        return matches.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func repairedNames(_ selection: [URL], encoding: String.Encoding) throws -> [FinderFileActions.RenameChange] {
        try selection.map { url in
            guard let bytes = url.lastPathComponent.data(using: encoding, allowLossyConversion: false),
                  let repaired = String(data: bytes, encoding: .utf8), !repaired.isEmpty else {
                throw FinderFileActionError.unsupported(url, "This name cannot be decoded losslessly with the selected encoding")
            }
            return .init(source: url, newName: repaired)
        }
    }
}
