// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// One place on the grid: an app, named by its bundle path, or a folder of
/// apps. Paths rather than bundle identifiers, so two copies of one app (a
/// beta beside the release) keep a place each.
enum LaunchpadItem: Codable, Equatable, Identifiable {
    case app(String)
    case folder(LaunchpadFolder)

    var id: String {
        switch self {
        case .app(let path): return path
        case .folder(let folder): return folder.id
        }
    }

    var apps: [String] {
        switch self {
        case .app(let path): return [path]
        case .folder(let folder): return folder.apps
        }
    }
}

struct LaunchpadFolder: Codable, Equatable, Identifiable {
    /// Prefixed so a folder id can never collide with an app path.
    var id: String = "folder:" + UUID().uuidString
    var name: String
    var apps: [String]
}

/// The arrangement the person made. The grid is one ordered list cut into
/// pages by however many cells the screen holds, so a layout made on a large
/// display still reads in the same order on a small one. Empty cells are not
/// kept: a page fills from its first cell, as on the iPhone.
struct LaunchpadLayout: Codable, Equatable {
    var items: [LaunchpadItem] = []
    /// Out of the grid, still found by search and in the Hidden category.
    var hidden: [String] = []

    static func decode(_ data: Data?) -> LaunchpadLayout {
        guard let data, let layout = try? JSONDecoder().decode(LaunchpadLayout.self, from: data) else {
            return LaunchpadLayout()
        }
        return layout
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }

    /// Every app the layout places, folders included, hidden apps left out.
    var placedApps: [String] { items.flatMap(\.apps) }

    func folder(_ id: String) -> LaunchpadFolder? {
        for case .folder(let folder) in items where folder.id == id { return folder }
        return nil
    }

    func folderID(containing path: String) -> String? {
        for case .folder(let folder) in items where folder.apps.contains(path) { return folder.id }
        return nil
    }

    // MARK: - Installed apps

    /// Brings the layout in line with what is installed now: apps that are
    /// gone leave, a folder left with one app becomes that app, and newly
    /// installed apps join the end in the order given. A duplicate left by
    /// an older layout keeps only its first place.
    func reconciled(with installed: [String]) -> LaunchpadLayout {
        let present = Set(installed)
        var seen = Set<String>()
        func keep(_ path: String) -> Bool { present.contains(path) && seen.insert(path).inserted }
        var next = LaunchpadLayout()
        next.hidden = hidden.filter(keep)
        for item in items {
            switch item {
            case .app(let path):
                if keep(path) { next.items.append(item) }
            case .folder(var folder):
                folder.apps = folder.apps.filter(keep)
                if folder.apps.count > 1 { next.items.append(.folder(folder)) }
                else if let only = folder.apps.first { next.items.append(.app(only)) }
            }
        }
        next.items += installed.filter(keep).map(LaunchpadItem.app)
        return next
    }

    // MARK: - Arranging

    /// Moves an item, or an app out of its folder, so it ends at `position`
    /// of the grid as it stands once the item has left its place. That is
    /// the grid a drag shows, with the item in the hand and a gap where it
    /// will land.
    mutating func move(_ id: String, toPosition position: Int) {
        let item: LaunchpadItem
        if let from = items.firstIndex(where: { $0.id == id }) {
            item = items.remove(at: from)
        } else if removeFromFolder(id) != nil {
            item = .app(id)
        } else {
            return
        }
        items.insert(item, at: min(max(position, 0), items.count))
    }

    /// Dropping an app on another app makes a folder in the target's place,
    /// named `folderName`; dropping it on a folder files it there. A folder
    /// dropped on anything just takes that place.
    @discardableResult
    mutating func drop(_ id: String, onto targetID: String, folderName: String) -> String? {
        guard id != targetID, let targetIndex = items.firstIndex(where: { $0.id == targetID }) else { return nil }
        if case .folder = items.first(where: { $0.id == id }) {
            let from = items.firstIndex { $0.id == id } ?? targetIndex
            move(id, toPosition: from < targetIndex ? targetIndex - 1 : targetIndex)
            return nil
        }
        switch items[targetIndex] {
        case .folder(let folder):
            guard !folder.apps.contains(id) else { return nil }
            detach(id)
            update(folder.id) { $0.apps.append(id) }
            return folder.id
        case .app(let targetPath):
            detach(id)
            let folder = LaunchpadFolder(name: folderName, apps: [targetPath, id])
            guard let index = items.firstIndex(where: { $0.id == targetPath }) else { return nil }
            items[index] = .folder(folder)
            return folder.id
        }
    }

    /// A folder made from a list of apps sits where the first of them was.
    /// One app alone is not a folder.
    @discardableResult
    mutating func createFolder(named name: String, apps: [String]) -> String? {
        let apps = Self.unique(apps)
        guard apps.count > 1 else { return nil }
        let index = apps.compactMap(position).min() ?? items.count
        apps.forEach { detach($0) }
        let folder = LaunchpadFolder(name: name, apps: apps)
        items.insert(.folder(folder), at: min(index, items.count))
        return folder.id
    }

    /// The edit window's result: apps taken out of the folder go back to the
    /// grid just after it, new ones leave wherever they were.
    mutating func editFolder(_ id: String, name: String, apps: [String]) {
        guard let folder = folder(id) else { return }
        let apps = Self.unique(apps)
        let removed = folder.apps.filter { !apps.contains($0) }
        apps.filter { !folder.apps.contains($0) }.forEach { detach($0) }
        update(id) {
            $0.name = name
            $0.apps = apps
        }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.insert(contentsOf: removed.map(LaunchpadItem.app), at: index + 1)
        if apps.isEmpty { items.remove(at: index) }
        else if apps.count == 1 { items[index] = .app(apps[0]) }
    }

    /// Reorders inside a folder; `position` counts the folder once the app
    /// has left its place, as a drag shows it.
    mutating func moveInFolder(_ path: String, toPosition position: Int) {
        guard let id = folderID(containing: path) else { return }
        update(id) { folder in
            guard let from = folder.apps.firstIndex(of: path) else { return }
            folder.apps.remove(at: from)
            folder.apps.insert(path, at: min(max(position, 0), folder.apps.count))
        }
    }

    mutating func renameFolder(_ id: String, to name: String) {
        update(id) { $0.name = name }
    }

    /// The folder's apps take its place, in its order.
    mutating func deleteFolder(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), let folder = folder(id) else { return }
        items.replaceSubrange(index...index, with: folder.apps.map(LaunchpadItem.app))
    }

    /// An app taken out of a folder lands right after it.
    mutating func takeOutOfFolder(_ path: String) {
        guard let removal = removeFromFolder(path) else { return }
        items.insert(.app(path), at: removal.slotRemoved ? removal.index : removal.index + 1)
    }

    mutating func hide(_ path: String) {
        detach(path)
        if !hidden.contains(path) { hidden.append(path) }
    }

    mutating func unhide(_ path: String) {
        guard let index = hidden.firstIndex(of: path) else { return }
        hidden.remove(at: index)
        if !placedApps.contains(path) { items.append(.app(path)) }
    }

    // MARK: - Private

    private func position(of path: String) -> Int? {
        items.firstIndex { $0.apps.contains(path) }
    }

    private mutating func update(_ folderID: String, _ change: (inout LaunchpadFolder) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == folderID }),
              case .folder(var folder) = items[index] else { return }
        change(&folder)
        items[index] = .folder(folder)
    }

    /// Takes an app off the grid wherever it is, at the top level or in a folder.
    private mutating func detach(_ path: String) {
        if let index = items.firstIndex(of: .app(path)) {
            items.remove(at: index)
        } else {
            removeFromFolder(path)
        }
    }

    /// Takes an app out of its folder and says where the folder was. A
    /// folder left with one app becomes that app in the same place, so the
    /// grid keeps its count; only an emptied folder leaves its slot.
    @discardableResult
    private mutating func removeFromFolder(_ path: String) -> (index: Int, slotRemoved: Bool)? {
        guard let folderID = folderID(containing: path),
              let index = items.firstIndex(where: { $0.id == folderID }) else { return nil }
        update(folderID) { $0.apps.removeAll { $0 == path } }
        let remaining = folder(folderID)?.apps ?? []
        if remaining.isEmpty {
            items.remove(at: index)
            return (index, true)
        }
        if remaining.count == 1 { items[index] = .app(remaining[0]) }
        return (index, false)
    }

    private static func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}

/// The App Store category an app declares, folded into the shelves the
/// categories view shows. Apps that declare none, and the ones no shelf
/// fits, go to Other.
enum LaunchpadCategory: String, CaseIterable, Identifiable {
    case productivity, utilities, developer, graphics, photoVideo, music, games, social, reading, other, hidden

    var id: String { rawValue }

    init(applicationCategoryType type: String?) {
        let type = (type ?? "").lowercased()
        let name = type.hasPrefix("public.app-category.")
            ? String(type.dropFirst("public.app-category.".count)) : ""
        switch name {
        case "productivity", "business", "finance": self = .productivity
        case "utilities": self = .utilities
        case "developer-tools": self = .developer
        case "graphics-design": self = .graphics
        case "photography", "video", "entertainment": self = .photoVideo
        case "music": self = .music
        case "social-networking": self = .social
        case "news", "reference", "books", "education", "weather", "lifestyle", "travel": self = .reading
        default: self = name == "games" || name.hasSuffix("-games") ? .games : .other
        }
    }

    var symbol: String {
        switch self {
        case .productivity: return "briefcase"
        case .utilities: return "wrench.and.screwdriver"
        case .developer: return "hammer"
        case .graphics: return "paintbrush"
        case .photoVideo: return "photo.on.rectangle"
        case .music: return "music.note"
        case .games: return "gamecontroller"
        case .social: return "bubble.left.and.bubble.right"
        case .reading: return "book"
        case .other: return "square.grid.2x2"
        case .hidden: return "eye.slash"
        }
    }
}

/// Where the cells of one page sit, in the coordinates of the whole
/// Launchpad window, so a drag can be read without asking the views.
struct LaunchpadGridGeometry: Equatable {
    var origin: CGPoint = .zero
    var cell = CGSize(width: 1, height: 1)
    var columns = 1
    var rows = 1
    var iconSize: CGFloat = 96

    var perPage: Int { columns * rows }

    /// The slot of the page under a point, and where inside that cell the
    /// point falls, each from 0 to 1. Outside the cells gives nil.
    func hit(_ point: CGPoint) -> (slot: Int, x: CGFloat, y: CGFloat)? {
        let x = (point.x - origin.x) / cell.width
        let y = (point.y - origin.y) / cell.height
        guard x >= 0, y >= 0, x < CGFloat(columns), y < CGFloat(rows) else { return nil }
        let column = Int(x), row = Int(y)
        return (row * columns + column, x - CGFloat(column), y - CGFloat(row))
    }

    /// The middle of a slot's icon (not of the cell, which also holds the name).
    func iconCenter(of slot: Int) -> CGPoint {
        let column = slot % max(columns, 1), row = slot / max(columns, 1)
        return CGPoint(x: origin.x + (CGFloat(column) + 0.5) * cell.width,
                       y: origin.y + (CGFloat(row) + 0.5) * cell.height - LaunchpadSupport.labelBlock / 2)
    }
}

/// What a drag points at, counted in the grid as the drag shows it: the
/// item in the hand gone, and a gap where it would land.
enum LaunchpadDragTarget: Equatable {
    case gap(Int)
    case merge(Int)
}

enum LaunchpadSupport {
    /// The name under an icon and the space above it.
    static let labelBlock: CGFloat = 25

    /// Over the middle of another icon the item asks to make (or join) a
    /// folder; anywhere else in a cell the gap moves there and the icons
    /// around it slide aside. Over the gap itself nothing changes.
    static func dragTarget(at point: CGPoint, in geometry: LaunchpadGridGeometry, page: Int,
                           shownCount: Int, gap: Int, canMerge: Bool) -> LaunchpadDragTarget? {
        guard let hit = geometry.hit(point), shownCount > 0 else { return nil }
        let index = page * geometry.perPage + hit.slot
        // The empty cells after the last item all mean "at the end".
        guard index < shownCount else { return .gap(shownCount - 1) }
        guard index != gap else { return .gap(gap) }
        // The icon sits in the upper part of the cell, above its name.
        let iconY = 0.5 - labelBlock / 2 / geometry.cell.height
        if canMerge, abs(hit.x - 0.5) < 0.22, abs(hit.y - iconY) < 0.24 { return .merge(index) }
        return .gap(index)
    }

    /// The items as a drag shows them: nil marks the gap.
    static func shown<T>(_ base: [T], gap: Int?) -> [T?] {
        guard let gap else { return base.map { $0 } }
        var shown = base.map { Optional($0) }
        shown.insert(nil, at: min(max(gap, 0), shown.count))
        return shown
    }

    /// How the grid is drawn: over the whole screen like the Launchpad macOS
    /// used to have, or as a large panel with the desktop around it.
    enum Style: String, CaseIterable {
        case fullScreen, panel

        static func sanitized(_ raw: String?) -> Style {
            raw.flatMap(Style.init(rawValue:)) ?? .fullScreen
        }
    }

    /// Cells this size give the old Launchpad's seven by five on a laptop
    /// screen and its large, airy icons.
    static let cellWidth: CGFloat = 190
    static let cellHeight: CGFloat = 180

    /// As many columns and rows as fit, up to the old Launchpad's seven by
    /// five: a large display gets more room around each icon, never more
    /// icons, and a small panel never drops below four by three.
    static func grid(for size: CGSize) -> (columns: Int, rows: Int) {
        let columns = Int(size.width / cellWidth)
        let rows = Int(size.height / cellHeight)
        return (min(max(columns, 4), 7), min(max(rows, 3), 5))
    }

    /// Where a released swipe settles. Positions are points from the first
    /// page and a positive velocity moves towards the later ones. A flick
    /// turns one page past the page the swipe caught, or on to the next page
    /// ahead of the fingers if they dragged further; a slow release settles
    /// on the nearest page.
    static func settledPage(began: CGFloat, position: CGFloat, velocity: CGFloat,
                            pageWidth: CGFloat, pageCount: Int) -> Int {
        let width = max(pageWidth, 1)
        let start = (began / width).rounded()
        let here = position / width
        let target = velocity > 300 ? max(start + 1, here.rounded(.up))
            : velocity < -300 ? min(start - 1, here.rounded(.down))
            : here.rounded()
        return min(max(Int(target), 0), max(pageCount - 1, 0))
    }

    /// How far a step of the fingers moves the pages already past the first
    /// or last page: less the further out they are, as the iPhone's rubber
    /// band, which never stretches a whole page.
    static func rubberBand(_ step: CGFloat, overshoot: CGFloat, pageWidth: CGFloat) -> CGFloat {
        let give = max(1 - abs(overshoot) / max(pageWidth, 1), 0)
        return step * 0.55 * give * give
    }

    /// One frame of a critically damped spring, the system's bounce-free
    /// glide: it never passes its rest point unless already thrown past it.
    /// The offset is the distance still to go.
    static func springStep(offset: CGFloat, velocity: CGFloat, elapsed: CGFloat,
                           response: CGFloat = 0.32) -> (offset: CGFloat, velocity: CGFloat) {
        let omega = 2 * .pi / response
        let carry = velocity + omega * offset
        let decay = exp(-omega * elapsed)
        return ((offset + carry * elapsed) * decay, (velocity - omega * carry * elapsed) * decay)
    }

    /// The picture the person chose for a display, read from the system's
    /// wallpaper store, since the workspace answers with the default picture
    /// once a wallpaper is not a plain file. The newest slot that covers the
    /// display wins: a Space's, the display's own, or the one for all of
    /// them. A still names its file; an Aerial names an asset whose still
    /// thumbnail sits beside its video. Anything else gives nil.
    static func wallpaperFile(inStore root: [String: Any], displayUUID: String, aerialThumbnails: URL) -> URL? {
        var slots: [[String: Any]] = []
        func add(_ container: Any?) {
            guard let container = container as? [String: Any] else { return }
            let slot = container["Type"] as? String == "linked"
                ? container["Linked"] : container["Desktop"] ?? container["Linked"]
            if let slot = slot as? [String: Any] { slots.append(slot) }
        }
        for case let space as [String: Any] in (root["Spaces"] as? [String: Any])?.values.map({ $0 }) ?? [] {
            add((space["Displays"] as? [String: Any])?[displayUUID])
            add(space["Default"])
        }
        add((root["Displays"] as? [String: Any])?[displayUUID])
        add(root["AllSpacesAndDisplays"])
        add(root["SystemDefault"])
        let newest = slots.max { ($0["LastSet"] as? Date ?? .distantPast) < ($1["LastSet"] as? Date ?? .distantPast) }
        guard let content = newest?["Content"] as? [String: Any],
              let choice = (content["Choices"] as? [[String: Any]])?.first,
              let data = choice["Configuration"] as? Data,
              let configuration = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { return nil }
        if let asset = configuration["assetID"] as? String, !asset.contains("/") {
            return aerialThumbnails.appendingPathComponent(asset + ".png")
        }
        return ((configuration["url"] as? [String: Any])?["relative"] as? String).flatMap(URL.init(string:))
    }

    static func pageCount(items: Int, perPage: Int) -> Int {
        guard perPage > 0 else { return 1 }
        return max(1, (items + perPage - 1) / perPage)
    }

    /// Names that start with the query come first, then names with a word
    /// that does, then names that merely contain it; each group keeps the
    /// given order. Case and accents are ignored, as in Spotlight.
    static func search<T>(_ query: String, in entries: [T], name: (T) -> String) -> [T] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        func rank(_ name: String) -> Int? {
            guard let range = name.range(of: query, options: options) else { return nil }
            if range.lowerBound == name.startIndex { return 0 }
            let before = name[name.index(before: range.lowerBound)]
            return before.isWhitespace || before.isPunctuation ? 1 : 2
        }
        return entries.enumerated()
            .compactMap { offset, entry in rank(name(entry)).map { (rank: $0, offset: offset, entry: entry) } }
            .sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }
            .map(\.entry)
    }
}
