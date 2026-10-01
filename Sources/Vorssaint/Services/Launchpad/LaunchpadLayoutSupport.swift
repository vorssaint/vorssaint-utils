// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct LaunchpadFolder: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var appIDs: [String]
}

/// One tile in the grid: a loose app, or a folder holding several.
enum LaunchpadItem: Codable, Equatable, Identifiable {
    case app(String)
    case folder(LaunchpadFolder)

    var id: String {
        switch self {
        case .app(let id): return id
        case .folder(let folder): return folder.id.uuidString
        }
    }
}

/// The user's saved arrangement: top-level order plus whatever folders
/// group some of the apps together. Persisted by `LaunchpadLayoutStore` as
/// one JSON blob, the same shape `NotchQuickAccessConfiguration` already
/// uses for the Dynamic Island's quick-access buttons.
struct LaunchpadLayout: Codable, Equatable {
    var items: [LaunchpadItem]
    private var version = 1

    /// Written out because the one Swift generates is private as long as a
    /// stored property is, which older toolchains enforce.
    init(items: [LaunchpadItem]) {
        self.items = items
    }

    static let initial = LaunchpadLayout(items: [])
}

/// Every operation on a `LaunchpadLayout`. Kept pure and testable without
/// `UserDefaults` or a real app catalog — see `LaunchpadLayoutStore` for the
/// persistence wrapper around this.
enum LaunchpadLayoutSupport {
    static let maximumItems = 512

    /// Drops ids no longer installed (out of folders too, dissolving a
    /// folder left with fewer than two apps), then appends any known app
    /// not yet placed anywhere, in catalog order.
    static func applyingCatalog(_ layout: LaunchpadLayout, knownAppIDs: Set<String>) -> LaunchpadLayout {
        var placed = Set<String>()
        var items: [LaunchpadItem] = layout.items.compactMap { item in
            switch item {
            case .app(let id):
                guard knownAppIDs.contains(id) else { return nil }
                placed.insert(id)
                return item
            case .folder(var folder):
                folder.appIDs = folder.appIDs.filter { knownAppIDs.contains($0) }
                folder.appIDs.forEach { placed.insert($0) }
                guard folder.appIDs.count >= 2 else {
                    // A folder left with one app (or none) dissolves; its
                    // one remaining app, if any, rejoins as a loose item.
                    if let only = folder.appIDs.first { placed.insert(only); return .app(only) }
                    return nil
                }
                return .folder(folder)
            }
        }
        let newAppIDs = knownAppIDs.subtracting(placed)
        items.append(contentsOf: newAppIDs.sorted().map { .app($0) })
        return sanitized(LaunchpadLayout(items: items))
    }

    static let maximumFolderNameLength = 40

    /// Drops duplicate item ids, caps the total count, and trims/clamps
    /// every folder's name, so a corrupted or runaway blob can never grow
    /// the grid or a name without bound.
    static func sanitized(_ layout: LaunchpadLayout) -> LaunchpadLayout {
        var seen = Set<String>()
        let items = layout.items.prefix(maximumItems).filter { seen.insert($0.id).inserted }.map { item -> LaunchpadItem in
            guard case .folder(var folder) = item else { return item }
            folder.name = String(folder.name.components(separatedBy: .newlines).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces).prefix(maximumFolderNameLength))
            return .folder(folder)
        }
        return LaunchpadLayout(items: Array(items))
    }

    /// The arrangement a fresh install starts from: every app whose real
    /// filesystem location is macOS's own `Utilities` subfolder grouped into
    /// one folder (matching the native Launchpad's own default), everything
    /// else loose in alphabetical order. Only used the very first time —
    /// once a layout is saved, `applyingCatalog` takes over and never
    /// re-groups a newly installed app into an existing folder on its own.
    static func defaultLayout(for apps: [LaunchpadApp], utilitiesFolderName: String) -> LaunchpadLayout {
        let sorted = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let utilities = sorted.filter(isNativeUtility)
        let everythingElse = sorted.filter { !isNativeUtility($0) }
        var items = everythingElse.map { LaunchpadItem.app($0.id) }
        if utilities.count >= 2 {
            items.append(.folder(LaunchpadFolder(id: UUID(), name: utilitiesFolderName, appIDs: utilities.map(\.id))))
        } else {
            items.append(contentsOf: utilities.map { .app($0.id) })
        }
        return sanitized(LaunchpadLayout(items: items))
    }

    private static func isNativeUtility(_ app: LaunchpadApp) -> Bool {
        URL(fileURLWithPath: app.path).deletingLastPathComponent().lastPathComponent == "Utilities"
    }

    /// Renames a folder in place. An empty or all-whitespace name is
    /// ignored rather than leaving a folder with no title at all.
    static func renamingFolder(_ layout: LaunchpadLayout, folderID: UUID, name: String) -> LaunchpadLayout {
        guard let index = layout.items.firstIndex(where: { $0.id == folderID.uuidString }),
              case .folder(var folder) = layout.items[index],
              !name.trimmingCharacters(in: .whitespaces).isEmpty
        else { return layout }
        folder.name = name
        var items = layout.items
        items[index] = .folder(folder)
        return sanitized(LaunchpadLayout(items: items))
    }

    /// Moves `itemID` to just before `beforeItemID`, or to the end when
    /// `beforeItemID` is nil.
    static func moving(_ layout: LaunchpadLayout, itemID: String, beforeItemID: String?) -> LaunchpadLayout {
        var items = layout.items
        guard let sourceIndex = items.firstIndex(where: { $0.id == itemID }) else { return layout }
        let moved = items.remove(at: sourceIndex)
        guard let beforeItemID, let targetIndex = items.firstIndex(where: { $0.id == beforeItemID }) else {
            items.append(moved)
            return LaunchpadLayout(items: items)
        }
        items.insert(moved, at: targetIndex)
        return LaunchpadLayout(items: items)
    }

    /// Dragging one app onto another creates a folder holding both, target
    /// first. Dragging an app onto an existing folder adds it to that
    /// folder instead of nesting.
    static func combining(_ layout: LaunchpadLayout, draggedAppID: String, ontoID: String, defaultFolderName: String) -> LaunchpadLayout {
        guard draggedAppID != ontoID, let draggedIndex = layout.items.firstIndex(where: { $0.id == draggedAppID }),
              let targetIndex = layout.items.firstIndex(where: { $0.id == ontoID })
        else { return layout }
        var items = layout.items
        switch items[targetIndex] {
        case .app(let targetAppID):
            let folder = LaunchpadFolder(id: UUID(), name: defaultFolderName, appIDs: [targetAppID, draggedAppID])
            items.remove(at: draggedIndex)
            let newTargetIndex = items.firstIndex(where: { $0.id == ontoID })!
            items[newTargetIndex] = .folder(folder)
        case .folder(var folder):
            guard !folder.appIDs.contains(draggedAppID) else { return layout }
            folder.appIDs.append(draggedAppID)
            items.remove(at: draggedIndex)
            let newTargetIndex = items.firstIndex(where: { $0.id == ontoID })!
            items[newTargetIndex] = .folder(folder)
        }
        return sanitized(LaunchpadLayout(items: items))
    }

    /// Pulls one app back out of a folder as a loose top-level item. A
    /// folder left with exactly one app dissolves into that loose app.
    static func removingFromFolder(_ layout: LaunchpadLayout, appID: String, folderID: UUID) -> LaunchpadLayout {
        guard let folderIndex = layout.items.firstIndex(where: { $0.id == folderID.uuidString }),
              case .folder(var folder) = layout.items[folderIndex],
              let appIndex = folder.appIDs.firstIndex(of: appID)
        else { return layout }
        folder.appIDs.remove(at: appIndex)
        var items = layout.items
        if folder.appIDs.count <= 1 {
            if let remaining = folder.appIDs.first {
                items[folderIndex] = .app(remaining)
                items.insert(.app(appID), at: folderIndex + 1)
            } else {
                items[folderIndex] = .app(appID)
            }
        } else {
            items[folderIndex] = .folder(folder)
            items.append(.app(appID))
        }
        return LaunchpadLayout(items: items)
    }
}
