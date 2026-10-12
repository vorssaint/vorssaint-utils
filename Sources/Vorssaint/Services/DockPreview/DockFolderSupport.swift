// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DockFolderEntry: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let name: String
    let directory: Bool
    let modified: Date
    let size: Int
}

enum DockFolderSupport {
    static func sorted(_ entries: [DockFolderEntry], by order: String, descending: Bool) -> [DockFolderEntry] {
        entries.sorted { lhs, rhs in
            if lhs.directory != rhs.directory { return lhs.directory }
            if order == "modified", lhs.modified != rhs.modified { return descending ? lhs.modified > rhs.modified : lhs.modified < rhs.modified }
            if order == "size", lhs.size != rhs.size { return descending ? lhs.size > rhs.size : lhs.size < rhs.size }
            let result = lhs.name.localizedStandardCompare(rhs.name)
            if result == .orderedSame { return lhs.url.path < rhs.url.path }
            return descending ? result == .orderedDescending : result == .orderedAscending
        }
    }
}
