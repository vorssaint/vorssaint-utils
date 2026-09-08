// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// Do not rename these IDs. Saved menu settings use them.
enum StatusItemContextMenuItemID: String, CaseIterable, Identifiable {
    case keepAwakeToggle, activateFor, cleaningMode
    case settings, about, uninstaller, shelf, checkForUpdates
    case quit

    var id: String { rawValue }

    var canHide: Bool {
        self != .settings && self != .quit
    }

    var group: StatusItemContextMenuGroup {
        switch self {
        case .keepAwakeToggle, .activateFor, .cleaningMode:
            return .actions
        case .settings, .about, .uninstaller, .shelf, .checkForUpdates:
            return .application
        case .quit:
            return .termination
        }
    }

    // The menu applies additional checks for Keep Awake and Shelf.
    var isAvailable: Bool {
        switch self {
        case .keepAwakeToggle, .activateFor:
            return AppFeature.keepAwake.isAvailable
        case .cleaningMode:
            return AppFeature.cleaningMode.isAvailable
        case .uninstaller:
            return AppFeature.uninstaller.isAvailable
        case .shelf:
            return AppFeature.shelf.isAvailable
        case .settings, .about, .checkForUpdates, .quit:
            return true
        }
    }

    func title(_ strings: Strings) -> String {
        switch self {
        case .keepAwakeToggle: return strings.keepAwakeTitle
        case .activateFor: return strings.menuActivateFor
        case .cleaningMode: return strings.cleaningMenuItem
        case .settings: return strings.menuSettings
        case .about: return strings.menuAbout
        case .uninstaller: return strings.uninstallerMenuItem
        case .shelf: return strings.shelfMenuItem
        case .checkForUpdates: return strings.menuCheckUpdates
        case .quit: return strings.menuQuit
        }
    }
}

enum StatusItemContextMenuGroup {
    case actions, application, termination
}

enum StatusItemContextMenuLayout {
    static let defaultOrder = StatusItemContextMenuItemID.allCases

    static func order(defaults: UserDefaults = .standard) -> [StatusItemContextMenuItemID] {
        let raw = defaults.string(forKey: DefaultsKey.statusItemContextMenuOrder) ?? ""
        var seen = Set<StatusItemContextMenuItemID>()
        var result = raw.split(separator: ",")
            .compactMap { StatusItemContextMenuItemID(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
        result.append(contentsOf: defaultOrder.filter { seen.insert($0).inserted })
        return result
    }

    static func setOrder(_ items: [StatusItemContextMenuItemID],
                         defaults: UserDefaults = .standard) {
        var seen = Set<StatusItemContextMenuItemID>()
        var normalized = items.filter { seen.insert($0).inserted }
        normalized.append(contentsOf: defaultOrder.filter { seen.insert($0).inserted })
        defaults.set(normalized.map(\.rawValue).joined(separator: ","),
                     forKey: DefaultsKey.statusItemContextMenuOrder)
    }

    static func hiddenItems(defaults: UserDefaults = .standard) -> Set<StatusItemContextMenuItemID> {
        let raw = defaults.string(forKey: DefaultsKey.statusItemContextMenuHiddenItems) ?? ""
        return Set(raw.split(separator: ",")
            .compactMap { StatusItemContextMenuItemID(rawValue: String($0)) }
            .filter(\.canHide))
    }

    static func setHiddenItems(_ items: Set<StatusItemContextMenuItemID>,
                               defaults: UserDefaults = .standard) {
        let normalized = defaultOrder.filter { $0.canHide && items.contains($0) }
        defaults.set(normalized.map(\.rawValue).joined(separator: ","),
                     forKey: DefaultsKey.statusItemContextMenuHiddenItems)
    }

    static func isShown(_ item: StatusItemContextMenuItemID,
                        defaults: UserDefaults = .standard) -> Bool {
        !hiddenItems(defaults: defaults).contains(item)
    }

    static func visibleOrder(defaults: UserDefaults = .standard) -> [StatusItemContextMenuItemID] {
        let hidden = hiddenItems(defaults: defaults)
        return order(defaults: defaults).filter { !hidden.contains($0) }
    }

    // Use the visible items to prevent empty menu groups.
    static func separatorIndexes(for items: [StatusItemContextMenuItemID]) -> IndexSet {
        guard let first = items.first else { return [] }
        var indexes = IndexSet()
        var previousGroup = first.group
        for index in items.indices.dropFirst() {
            let group = items[index].group
            if group != previousGroup {
                indexes.insert(index)
            }
            previousGroup = group
        }
        return indexes
    }
}
