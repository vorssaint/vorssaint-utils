// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import FinderSync

@objc(FinderToolsExtension)
final class FinderToolsExtension: FIFinderSync {
    // Finder serializes menu items and preserves tags, not representedObject.
    // Never reuse tags: a callback from an expired menu must fail closed.
    private var requests: [Int: URL] = [:]
    private var nextTag = 1

    override init() {
        super.init()
        // Finder owns observation. There is no filesystem enumeration or polling.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        guard let target = controller.targetedURL() else { return nil }
        let selection = menuKind == .contextualMenuForContainer
            ? [] : (controller.selectedItemURLs() ?? [target])
        let directory = menuKind == .contextualMenuForContainer ? target : nil
        let menu = NSMenu()
        if requests.count > 2_048 { requests.removeAll() }
        let parent = NSMenuItem(title: "Vorssaint", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: nil)
        let actions = NSMenu()
        let snapshot = FinderToolsMenuSnapshot.read()
        if snapshot?.enabled == false { return nil }
        let configuration = snapshot?.menu ?? FinderToolsMenuConfiguration()
        let language = snapshot?.language ?? Bundle.main.preferredLocalizations.first ?? "en-US"
        var groups: [FinderToolsCategory: NSMenu] = [:]
        for action in configuration.visibleActions where !action.needsSelection || !selection.isEmpty {
            let request = FinderToolsRequest(selection: selection, directory: directory, suggestedAction: action)
            guard let url = request.url else { continue }
            let item = NSMenuItem(title: configuration.title(for: action, language: language),
                                 action: #selector(openTools(_:)), keyEquivalent: configuration.shortcut(for: action))
            item.keyEquivalentModifierMask = [.command, .shift]
            if let symbol = configuration.icon(for: action) {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            item.target = self
            register(url, for: item)
            if configuration.grouped {
                if groups[action.category] == nil {
                    let group = NSMenu()
                    let header = NSMenuItem(title: action.category.title(language: language), action: nil, keyEquivalent: "")
                    header.submenu = group
                    actions.addItem(header)
                    groups[action.category] = group
                }
                groups[action.category]?.addItem(item)
            } else { actions.addItem(item) }
        }
        if let saved = snapshot?.savedItems, !saved.isEmpty {
            actions.addItem(.separator())
            var savedGroups: [String: NSMenu] = [:]
            for action in saved {
                let request = FinderToolsRequest(selection: selection, directory: directory, savedActionID: action.id)
                guard let url = request.url else { continue }
                let item = NSMenuItem(title: action.title, action: #selector(openTools(_:)), keyEquivalent: "")
                item.target = self
                register(url, for: item)
                if let name = action.group, !name.isEmpty {
                    if savedGroups[name] == nil {
                        let group = NSMenu()
                        let header = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                        header.submenu = group
                        actions.addItem(header)
                        savedGroups[name] = group
                    }
                    savedGroups[name]?.addItem(item)
                } else { actions.addItem(item) }
            }
        }
        parent.submenu = actions
        menu.addItem(parent)
        return menu
    }

    @objc private func openTools(_ item: NSMenuItem) {
        guard let url = requests.removeValue(forKey: item.tag) else { return }
        NSWorkspace.shared.open(url)
    }

    private func register(_ url: URL, for item: NSMenuItem) {
        guard nextTag < Int.max else { item.isEnabled = false; return }
        item.tag = nextTag
        requests[nextTag] = url
        nextTag += 1
    }
}
