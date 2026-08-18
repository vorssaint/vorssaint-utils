// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ShelfSelectionSupport {
    /// Escape clears the Shelf selection only when pressed on its own. Keeping
    /// modifier-bearing variants available avoids swallowing future shortcuts.
    static func isClearSelectionShortcut(keyCode: UInt16,
                                         hasSelectionModifiers: Bool) -> Bool {
        keyCode == 53 && !hasSelectionModifiers
    }

    /// The visible ids covered by a shift-click, from the last tile the user
    /// touched to the clicked tile, inclusive and in either direction.
    static func rangeSelectionIDs<ID: Equatable>(allIDs: [ID],
                                                 anchorID: ID?,
                                                 targetID: ID) -> [ID] {
        guard let target = allIDs.firstIndex(of: targetID) else { return [] }
        let anchor = anchorID.flatMap { allIDs.firstIndex(of: $0) } ?? target
        let bounds = min(anchor, target)...max(anchor, target)
        return Array(allIDs[bounds])
    }
}

enum ShelfInteractionSupport {
    /// App exclusions only suppress automatic Shelf appearances. A deliberate
    /// shortcut or "Open now" action remains an escape hatch everywhere.
    static func allowsAutomaticOpen(sourceBundleIdentifier: String?,
                                    excludedBundleIdentifiers: Set<String>) -> Bool {
        guard let sourceBundleIdentifier, !sourceBundleIdentifier.isEmpty else { return true }
        return !excludedBundleIdentifiers.contains(sourceBundleIdentifier)
    }

    /// Whether the gesture in flight drags real content, as opposed to moving
    /// or resizing a window. The drag pasteboard retains the previous drag's
    /// items indefinitely, so retained content alone proves nothing: only a
    /// change-count bump during the current gesture makes it current. Dock
    /// stacks are the one source that can publish the contents before the
    /// mouse-down, hence the Dock escape. Either way the pasteboard must hold
    /// something the Shelf can keep; the check stays lazy because most dragged
    /// events resolve on the cheap change count alone.
    static func isContentDrag(baselineChangeCount: Int,
                              changeCount: Int,
                              beganInDock: Bool,
                              hasDroppableContent: () -> Bool) -> Bool {
        guard changeCount != baselineChangeCount || beganInDock else { return false }
        return hasDroppableContent()
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

/// Which side of the screen a drag is being aimed at, for the "open near a
/// screen edge" trigger. Only left and right: top and bottom already belong
/// to the menu bar and the Dock, wherever it sits.
enum ShelfEdge: Equatable {
    case left, right
}

/// A resolved edge match: which side, and the screen it belongs to, kept
/// together so a later retreat check tests the same edge instead of
/// accidentally resolving a different screen's edge.
struct ShelfEdgeMatch: Equatable {
    let edge: ShelfEdge
    let screen: CGRect
}

/// A screen's physical frame paired with its visible frame (the physical
/// frame minus the menu bar and Dock), so `ShelfEdgeDragSupport.match` can
/// tell "near the physical edge" apart from "over the Dock's own reserved
/// space" when a Dock is mounted on the left or right. When nothing is
/// reserved there (Dock at the bottom or auto-hidden), `visibleFrame`'s
/// horizontal bounds equal `frame`'s and this carries no effect.
struct ShelfEdgeScreen: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

enum ShelfEdgeDragSupport {
    /// How close the pointer has to be to a screen's outer edge to count as
    /// heading for it.
    static let triggerDistance: CGFloat = 200
    /// Wider than the trigger distance on purpose: the boundary needs its
    /// own hysteresis, or hovering right at the edge would flicker between
    /// shown and retracted.
    static let retreatDistance: CGFloat = 330
    /// How long the pointer has to stay within the trigger distance before
    /// it counts as heading for the edge, so a fast pass through the zone
    /// (e.g. flicking the pointer past it on the way elsewhere) does not
    /// fire. `match`'s Dock-margin exclusion keeps parking on a Dock icon
    /// from triggering it at all; a slow approach through the rest of the
    /// zone before ever reaching the Dock can still dwell long enough to
    /// fire, the same as approaching any other point near the edge would.
    static let dwell: TimeInterval = 0.15

    /// The left or right edge of whichever screen the point is closest to,
    /// within `distance` of that edge, or nil when nothing qualifies. A
    /// seam shared by two adjacent displays never counts as either
    /// screen's own outer edge, so a drag crossing between displays there
    /// is never caught. A point resting inside a side-mounted Dock's own
    /// reserved margin (`frame` minus `visibleFrame`, horizontally) never
    /// counts either, so parking over a Dock icon to drop there doesn't
    /// also peek the shelf.
    static func match(at point: CGPoint, screens: [ShelfEdgeScreen], distance: CGFloat) -> ShelfEdgeMatch? {
        let ordered = screens.enumerated().sorted {
            distanceSquared(from: point, to: $0.element.frame) < distanceSquared(from: point, to: $1.element.frame)
        }
        for (index, screen) in ordered {
            let frame = screen.frame
            guard frame.width > 0, frame.height > 0,
                  point.x >= frame.minX - distance, point.x <= frame.maxX + distance,
                  point.y >= frame.minY - distance, point.y <= frame.maxY + distance
            else { continue }
            let others = screens.enumerated().compactMap { $0.offset == index ? nil : $0.element.frame }
            let nearLeft = point.x <= frame.minX + distance
                && point.x >= screen.visibleFrame.minX
                && !hasNeighbor(at: CGPoint(x: frame.minX - distance - 1, y: point.y), frames: others)
            if nearLeft { return ShelfEdgeMatch(edge: .left, screen: frame) }
            let nearRight = point.x >= frame.maxX - distance
                && point.x <= screen.visibleFrame.maxX
                && !hasNeighbor(at: CGPoint(x: frame.maxX + distance + 1, y: point.y), frames: others)
            if nearRight { return ShelfEdgeMatch(edge: .right, screen: frame) }
        }
        return nil
    }

    /// Whether the point is still within `distance` of the same edge and
    /// screen an earlier match resolved, without re-resolving which screen
    /// or edge is nearest now. Used to check retreat against the edge that
    /// is actually showing, not whichever edge happens to be closest.
    static func stillNear(_ match: ShelfEdgeMatch, point: CGPoint, distance: CGFloat) -> Bool {
        let withinHeight = point.y >= match.screen.minY - distance && point.y <= match.screen.maxY + distance
        guard withinHeight else { return false }
        switch match.edge {
        case .left: return point.x <= match.screen.minX + distance
        case .right: return point.x >= match.screen.maxX - distance
        }
    }

    /// Whether a dwell that began at `since` has lasted long enough, given
    /// the current time, to count as heading for the edge rather than
    /// passing near it.
    static func hasDwelled(since: TimeInterval, now: TimeInterval, required: TimeInterval = dwell) -> Bool {
        now - since >= required
    }

    private static func distanceSquared(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }

    private static func hasNeighbor(at point: CGPoint, frames: [CGRect]) -> Bool {
        frames.contains { $0.insetBy(dx: -1, dy: -1).contains(point) }
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
    /// Lets a file item find its payload again after a move or rename. The
    /// field is optional on purpose: stores written before it decode fine,
    /// and older app versions simply ignore it.
    var bookmark: Data?
    var children: [ShelfPersistedItem]?

    init(id: UUID,
         kind: Kind,
         title: String,
         text: String? = nil,
         url: String? = nil,
         path: String? = nil,
         bookmark: Data? = nil,
         children: [ShelfPersistedItem]? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.url = url
        self.path = path
        self.bookmark = bookmark
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
    ///
    /// `resolveBookmark` gives a dead path one chance to heal: a file moved
    /// or renamed behind the app's back is found again through its bookmark,
    /// and the entry keeps living under its new path and name.
    static func sanitized(_ items: [ShelfPersistedItem],
                          fileExists: (String) -> Bool,
                          resolveBookmark: (Data) -> String? = { _ in nil }) -> [ShelfPersistedItem] {
        var remainingLeaves = maxLeaves
        return sanitized(items, depth: 0, remainingLeaves: &remainingLeaves,
                         fileExists: fileExists, resolveBookmark: resolveBookmark)
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
                                  fileExists: (String) -> Bool,
                                  resolveBookmark: (Data) -> String?) -> [ShelfPersistedItem] {
        guard depth < maxDepth else { return [] }
        var result: [ShelfPersistedItem] = []
        for item in items {
            guard remainingLeaves > 0 else { break }
            switch item.kind {
            case .file:
                guard let path = item.path, !path.isEmpty else { continue }
                var keptPath = path
                var keptTitle = item.title
                if !fileExists(path) {
                    guard let bookmark = item.bookmark,
                          let healed = resolveBookmark(bookmark),
                          fileExists(healed) else { continue }
                    keptPath = healed
                    keptTitle = (healed as NSString).lastPathComponent
                }
                remainingLeaves -= 1
                result.append(ShelfPersistedItem(id: item.id, kind: .file, title: keptTitle,
                                                 path: keptPath, bookmark: item.bookmark))
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
                                         remainingLeaves: &remainingLeaves,
                                         fileExists: fileExists, resolveBookmark: resolveBookmark)
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
