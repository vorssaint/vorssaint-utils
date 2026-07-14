// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ShelfInteractionSupport {
    /// App exclusions only suppress automatic Shelf appearances. A deliberate
    /// shortcut or "Open now" action remains an escape hatch everywhere.
    static func allowsAutomaticOpen(sourceBundleIdentifier: String?,
                                    excludedBundleIdentifiers: Set<String>) -> Bool {
        guard let sourceBundleIdentifier, !sourceBundleIdentifier.isEmpty else { return true }
        return !excludedBundleIdentifiers.contains(sourceBundleIdentifier)
    }

    /// A successful drag that really left the Shelf can dismiss it. Cancelled
    /// drags and internal merges never do, and pinning always wins.
    static func shouldCloseAfterDrag(dropAccepted: Bool,
                                     draggedItemCount: Int,
                                     closeAfterDrop: Bool,
                                     pinned: Bool) -> Bool {
        dropAccepted && draggedItemCount > 0 && closeAfterDrop && !pinned
    }

    /// Keeping an item after it was dragged out is safe only when the source
    /// offers copy semantics; the live AppKit source uses this preference to
    /// avoid a target moving the underlying file away from its persisted URL.
    static func shouldRemoveAfterDrag(dropAccepted: Bool,
                                      draggedItemCount: Int,
                                      removeAfterDrop: Bool) -> Bool {
        dropAccepted && draggedItemCount > 0 && removeAfterDrop
    }
}

/// Persisted form of one shelf item, so the shelf survives relaunches (and app
/// updates, which relaunch the app). Payloads and titles are stored; icons and
/// image flags are rebuilt from the payload at load.
struct ShelfPersistedItem: Codable, Equatable {
    enum Kind: String, Codable {
        case file, text, link, batch
    }

    let id: UUID
    let kind: Kind
    let title: String
    var text: String?
    var url: String?
    var path: String?
    var children: [ShelfPersistedItem]?

    init(id: UUID,
         kind: Kind,
         title: String,
         text: String? = nil,
         url: String? = nil,
         path: String? = nil,
         children: [ShelfPersistedItem]? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.url = url
        self.path = path
        self.children = children
    }
}

enum ShelfPersistenceSupport {
    /// Ceilings so a stale or hand-edited blob cannot balloon startup: the
    /// shelf is a hand-curated surface, not an archive.
    static let maxLeaves = 200
    static let maxTextLength = 200_000
    static let maxDepth = 4

    /// Drops entries that can no longer be honored (missing files, empty text,
    /// invalid links) and mirrors the live shelf's batch rules: an emptied
    /// batch disappears and a single-child batch collapses to its child, the
    /// same way removing items from a live batch behaves.
    ///
    /// `fileExists` decides whether a file item survives. Callers must answer
    /// true for files on volumes that are merely NOT MOUNTED right now (see
    /// unmountedVolumeRoot): the app can launch at login before an external
    /// or network drive appears, and dropping those items would lose them
    /// permanently the moment the pruned list is saved back.
    static func sanitized(_ items: [ShelfPersistedItem],
                          fileExists: (String) -> Bool) -> [ShelfPersistedItem] {
        var remainingLeaves = maxLeaves
        return sanitized(items, depth: 0, remainingLeaves: &remainingLeaves, fileExists: fileExists)
    }

    /// For a path under /Volumes, the volume root directory that must exist
    /// for the file's absence to be meaningful; nil for boot-volume paths.
    static func unmountedVolumeRoot(of path: String) -> String? {
        let components = (path as NSString).pathComponents
        guard components.count > 2, components[0] == "/", components[1] == "Volumes" else {
            return nil
        }
        return "/Volumes/" + components[2]
    }

    private static func sanitized(_ items: [ShelfPersistedItem],
                                  depth: Int,
                                  remainingLeaves: inout Int,
                                  fileExists: (String) -> Bool) -> [ShelfPersistedItem] {
        guard depth < maxDepth else { return [] }
        var result: [ShelfPersistedItem] = []
        for item in items {
            guard remainingLeaves > 0 else { break }
            switch item.kind {
            case .file:
                guard let path = item.path, !path.isEmpty, fileExists(path) else { continue }
                remainingLeaves -= 1
                result.append(ShelfPersistedItem(id: item.id, kind: .file, title: item.title, path: path))
            case .text:
                guard let text = item.text,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                remainingLeaves -= 1
                result.append(ShelfPersistedItem(id: item.id, kind: .text, title: item.title,
                                                 text: String(text.prefix(maxTextLength))))
            case .link:
                guard let raw = item.url, let url = URL(string: raw),
                      url.scheme != nil, !url.isFileURL else { continue }
                remainingLeaves -= 1
                result.append(ShelfPersistedItem(id: item.id, kind: .link, title: item.title, url: raw))
            case .batch:
                let children = sanitized(item.children ?? [], depth: depth + 1,
                                         remainingLeaves: &remainingLeaves, fileExists: fileExists)
                if children.isEmpty { continue }
                if children.count == 1 {
                    result.append(children[0])
                    continue
                }
                result.append(ShelfPersistedItem(id: item.id, kind: .batch, title: item.title,
                                                 children: children))
            }
        }
        return result
    }
}
