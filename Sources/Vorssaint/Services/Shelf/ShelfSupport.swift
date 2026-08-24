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

/// A Shelf item reduced to what revealing needs: identity and nesting. A pure
/// stand-in for the service's item tree, like ShelfEdgeScreen is for NSScreen,
/// so the rules below stay in the unit harness.
struct ShelfRevealNode: Equatable {
    let id: UUID
    let children: [ShelfRevealNode]

    init(id: UUID, children: [ShelfRevealNode] = []) {
        self.id = id
        self.children = children
    }
}

enum ShelfRevealSupport {
    /// The item the Shelf should scroll to when `target` is added. A merged
    /// file becomes a child of a pile, and a collapsed pile draws no tile for
    /// its children, so the answer is the deepest ancestor that is drawn:
    /// the item itself when every ancestor is expanded, the outermost
    /// collapsed pile otherwise, and nothing when the id is not on the shelf.
    static func visibleAncestorID(of target: UUID,
                                  in nodes: [ShelfRevealNode],
                                  expanded: Set<UUID>) -> UUID? {
        for node in nodes {
            if node.id == target { return node.id }
            guard !node.children.isEmpty else { continue }
            guard let deeper = visibleAncestorID(of: target,
                                                 in: node.children,
                                                 expanded: expanded) else { continue }
            return expanded.contains(node.id) ? deeper : node.id
        }
        return nil
    }

    /// Whether this add is one the Shelf hasn't already scrolled to. Keyed
    /// on the add serial rather than the resolved target: the target alone
    /// changes when a pile is expanded or collapsed with nothing added,
    /// and repeats when two files land in the same collapsed pile back to
    /// back, either of which would misfire a target-keyed dedup.
    static func shouldReveal(serial: Int, lastHonored: Int?) -> Bool {
        serial != lastHonored
    }
}

enum ShelfTileLayout {
    /// How many tile columns fit a given width, never fewer than one so a
    /// narrow panel still lays out.
    static func columnCount(contentWidth: CGFloat,
                            tileWidth: CGFloat,
                            spacing: CGFloat,
                            inset: CGFloat) -> Int {
        let usable = contentWidth - inset * 2 + spacing
        return max(1, Int(usable / (tileWidth + spacing)))
    }

    /// Where the tile at `index` sits in the flipped document view.
    static func tileFrame(index: Int,
                          columns: Int,
                          tileSize: CGSize,
                          spacing: CGFloat,
                          inset: CGFloat) -> CGRect {
        let safeColumns = max(1, columns)
        let column = index % safeColumns
        let row = index / safeColumns
        return CGRect(x: inset + CGFloat(column) * (tileSize.width + spacing),
                      y: inset + CGFloat(row) * (tileSize.height + spacing),
                      width: tileSize.width,
                      height: tileSize.height)
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

/// A leaf item's kind, reduced to what the pile-breakdown tooltip needs. A
/// pure stand-in for ShelfService.Item's payload, like ShelfEdgeScreen is
/// for NSScreen, so this stays testable without depending on Item.
enum ShelfTooltipLeafKind {
    case image, file, note, link
}

/// How many leaves of each kind a pile holds, for its tooltip breakdown.
struct ShelfTooltipPileBreakdown: Equatable {
    var images = 0
    var files = 0
    var notes = 0
    var links = 0

    var total: Int { images + files + notes + links }
}

/// The localized words the pile breakdown needs, one singular and one
/// plural per kind (this app has no CLDR-style pluralization, so each
/// form is its own string) plus the always-plural items count, since a
/// pile always holds two or more leaves.
struct ShelfTooltipStrings {
    let itemsFormat: String
    let imageSingular: String
    let imagePlural: String
    let fileSingular: String
    let filePlural: String
    let noteSingular: String
    let notePlural: String
    let linkSingular: String
    let linkPlural: String
}

enum ShelfTooltipSupport {
    /// Long enough to show a real paragraph, short enough that a huge paste
    /// doesn't produce an unusably huge tooltip.
    static let textCap = 500

    /// A file tile's tooltip: its name, and the system's own Kind string on
    /// a second line when one was found. A blank or missing kind (the file
    /// went away, or the lookup failed for any reason) is not worth
    /// surfacing as an error to someone just hovering, so it falls back to
    /// the name alone rather than showing a blank second line.
    static func text(forFileNamed title: String, resolvedKind: String?) -> String {
        guard let resolvedKind, !resolvedKind.isEmpty else { return title }
        return "\(title)\n\(resolvedKind)"
    }

    /// A text tile's tooltip: the full content, not the truncated preview
    /// the tile's own title already shows. Trimmed the same way the title
    /// preview is, since the stored payload keeps the original whitespace
    /// verbatim but that whitespace carries no identifying information.
    static func text(forText string: String, cap: Int = textCap) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > cap else { return trimmed }
        return String(trimmed.prefix(cap)) + "…"
    }

    /// A link tile's tooltip: the full URL. The tile's own title is only
    /// the host, so this is where the rest of it becomes visible. Capped
    /// the same way pasted text is: an unbroken query token can otherwise
    /// produce an unusably tall popover with no line breaks to wrap on.
    static func text(forLink url: URL, cap: Int = textCap) -> String {
        let string = url.absoluteString
        guard string.count > cap else { return string }
        return String(string.prefix(cap)) + "…"
    }

    /// Counts a pile's flattened leaves by kind.
    static func breakdown(of kinds: [ShelfTooltipLeafKind]) -> ShelfTooltipPileBreakdown {
        var result = ShelfTooltipPileBreakdown()
        for kind in kinds {
            switch kind {
            case .image: result.images += 1
            case .file: result.files += 1
            case .note: result.notes += 1
            case .link: result.links += 1
            }
        }
        return result
    }

    /// A pile's tooltip: the total, then a breakdown of only the kinds it
    /// actually has, each in the grammatically correct singular or plural
    /// form for its own count. A pile with nothing in it (should not occur
    /// in practice) still returns a plain string rather than crashing or
    /// leaving a dangling colon with nothing after it.
    static func text(forPile breakdown: ShelfTooltipPileBreakdown, strings: ShelfTooltipStrings) -> String {
        var parts: [String] = []
        if breakdown.images > 0 {
            parts.append(String(format: breakdown.images == 1 ? strings.imageSingular : strings.imagePlural,
                                breakdown.images))
        }
        if breakdown.files > 0 {
            parts.append(String(format: breakdown.files == 1 ? strings.fileSingular : strings.filePlural,
                                breakdown.files))
        }
        if breakdown.notes > 0 {
            parts.append(String(format: breakdown.notes == 1 ? strings.noteSingular : strings.notePlural,
                                breakdown.notes))
        }
        if breakdown.links > 0 {
            parts.append(String(format: breakdown.links == 1 ? strings.linkSingular : strings.linkPlural,
                                breakdown.links))
        }
        let itemsText = String(format: strings.itemsFormat, breakdown.total)
        guard !parts.isEmpty else { return itemsText }
        return "\(itemsText): \(parts.joined(separator: ", "))"
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

    static func boundedLiveText(_ text: String) -> String? {
        let bounded = String(text.prefix(maxTextLength))
        guard !bounded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return bounded
    }

    static func canAdd(existingLeaves: Int, newLeaves: Int) -> Bool {
        existingLeaves >= 0 && newLeaves > 0 && existingLeaves <= maxLeaves - newLeaves
    }

    static func discardablePayloadPaths(candidatePaths: [String],
                                        referencedPaths: Set<String>) -> Set<String> {
        Set(candidatePaths).subtracting(referencedPaths)
    }

    static func needsPersistAfterRestore(restoredIsEmpty: Bool, liveItemCount: Int) -> Bool {
        restoredIsEmpty || liveItemCount > 0
    }

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

enum ShelfBatchSupport {
    /// Restores original drop order after resolving every provider in a
    /// multi-item drop in parallel, which completes out of order, and
    /// drops any provider that failed to resolve to anything.
    static func orderedItems<Item>(from resolved: [(index: Int, item: Item)]) -> [Item] {
        resolved.sorted { $0.index < $1.index }.map(\.item)
    }
}
