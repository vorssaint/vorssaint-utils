// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import FinderSync

@objc(FinderNewFileExtension)
final class FinderNewFileExtension: FIFinderSync {
    private struct Action {
        let kind: FinderNewFileKind
        let directory: URL
    }

    // Finder serializes menu items. Tags survive; representedObject may not.
    // Never reuse a tag, even when old menu snapshots are discarded.
    private var actions: [Int: Action] = [:]
    private var nextTag = 1

    override init() {
        super.init()
        // Finder manages observation; there is no filesystem crawl.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true),
            URL(fileURLWithPath: "/Volumes", isDirectory: true)
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        guard let directory = destination(for: menuKind, controller: controller),
              FinderNewFileRequest.isLocalDirectoryURL(directory) else { return nil }

        // Never expose a default/stale menu when settings could not be read.
        guard let snapshot = FinderNewFileExchange.snapshot(), snapshot.enabled else { return nil }
        let kinds = snapshot.kinds
        guard !kinds.isEmpty else { return nil }
        let strings = FinderNewFileStrings.localized(snapshot.language)
        if actions.count > 256 { actions.removeAll() }
        let menu = NSMenu()
        let parent = NSMenuItem(title: strings.title, action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
        let submenu = NSMenu()
        for kind in kinds {
            guard nextTag < Int.max else { break }
            let item = NSMenuItem(title: kind.title(strings), action: #selector(create(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
            item.target = self
            item.tag = nextTag
            actions[nextTag] = Action(kind: kind, directory: directory)
            nextTag += 1
            submenu.addItem(item)
        }
        parent.submenu = submenu
        menu.addItem(parent)
        return menu
    }

    private func destination(for kind: FIMenuKind, controller: FIFinderSyncController) -> URL? {
        switch kind {
        case .contextualMenuForContainer:
            return controller.targetedURL()
        case .contextualMenuForItems, .contextualMenuForSidebar:
            guard let items = controller.selectedItemURLs(), items.count == 1,
                  let item = items.first else { return nil }
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true && values?.isPackage != true { return item }
            if values == nil && item.hasDirectoryPath { return item }
            return item.deletingLastPathComponent()
        default:
            return nil
        }
    }

    @objc private func create(_ item: NSMenuItem) {
        guard let action = actions.removeValue(forKey: item.tag) else { return }
        guard let snapshot = FinderNewFileExchange.snapshot(), snapshot.enabled,
              snapshot.kinds.contains(action.kind) else { return }
        let request = FinderNewFileRequest(kind: action.kind, directory: action.directory)
        guard request.isValid() else { return }
        let url: URL?
        if FinderNewFileExchange.supportsTrustedRequests {
            do {
                try FinderNewFileExchange.enqueue(request)
                url = request.wakeURL
            } catch {
                // If shared storage is unavailable, the only fallback is an
                // explicit confirmation in the containing application.
                url = request.confirmationURL
            }
        } else {
            url = request.confirmationURL
        }

        let appURL = Bundle.main.bundleURL.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard let url, appURL.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error { NSLog("Vorssaint Finder action could not open its host: %@", error.localizedDescription) }
        }
    }
}
