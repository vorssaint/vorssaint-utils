// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// An opt-in global shortcut opens the configured menu at the pointer. Actions
/// only prepare the existing workspace; file operations still require its button.
final class FinderToolsQuickMenu: NSObject, ObservableObject {
    @Published private(set) var registrationFailed = false
    private let hotkey = QuickToolHotkey(id: 82)
    private var menu: NSMenu?
    private var generation = 0
    private let queue = DispatchQueue(label: "com.vorssaint.finder-tools.selection", qos: .userInitiated)
    private let open: (FinderToolsRequest) -> Void

    init(open: @escaping (FinderToolsRequest) -> Void) {
        self.open = open
        super.init()
        hotkey.onPress = { [weak self] in self?.show() }
        SessionActivity.shared.onChange { [weak self] active in
            if !active { self?.suspend() }
            else { self?.sync() }
        }
    }

    func sync() {
        let configuration = FinderToolsConfiguration.decode(UserDefaults.standard.string(forKey: DefaultsKey.finderToolsConfiguration))
        let value = configuration.quickMenuShortcut ?? ""
        guard AppFeature.finderTools.isAvailable, SessionActivity.shared.isActive,
              !ShortcutCapture.isCapturing, !value.isEmpty else {
            suspend()
            registrationFailed = false
            return
        }
        guard let shortcut = GlobalShortcut(storageValue: value) else {
            suspend()
            registrationFailed = true
            return
        }
        registrationFailed = !hotkey.sync(enabled: true, shortcut: shortcut,
            storageKey: DefaultsKey.finderToolsConfiguration + ".quickMenuShortcut")
    }

    func suspend() {
        generation += 1
        hotkey.unregister()
        menu?.cancelTracking()
        menu = nil
    }

    func show(at anchor: NSPoint? = nil) {
        guard AppFeature.finderTools.isAvailable, SessionActivity.shared.isActive,
              !ShortcutCapture.isCapturing, menu == nil else { return }
        generation += 1
        let ticket = generation
        let point = anchor ?? NSEvent.mouseLocation
        let finderIsFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        queue.async { [weak self] in
            let context = finderIsFront ? FinderToolsSelectionReader.read() : nil
            DispatchQueue.main.async {
                guard let self, self.generation == ticket, AppFeature.finderTools.isAvailable,
                      SessionActivity.shared.isActive else { return }
                self.present(selection: context?.selection ?? [], directory: context?.directory, at: point)
            }
        }
    }

    private func present(selection: [URL], directory: URL?, at point: NSPoint) {
        let configuration = FinderToolsConfiguration.decode(UserDefaults.standard.string(forKey: DefaultsKey.finderToolsConfiguration))
        let language = L10n.shared.language.rawValue
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "\(FinderToolsStrings.localized(L10n.shared.language).selection): \(selection.count)",
                               action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        var groups: [String: NSMenu] = [:]
        func append(_ item: NSMenuItem, group: String?) {
            guard let group, !group.isEmpty else { menu.addItem(item); return }
            if groups[group] == nil {
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                let parent = NSMenuItem(title: group, action: nil, keyEquivalent: "")
                parent.submenu = submenu
                menu.addItem(parent)
                groups[group] = submenu
            }
            groups[group]?.addItem(item)
        }
        for action in configuration.menu.visibleActions {
            let item = NSMenuItem(title: configuration.menu.title(for: action, language: language),
                                 action: #selector(choose(_:)), keyEquivalent: configuration.menu.shortcut(for: action))
            item.keyEquivalentModifierMask = [.command, .shift]
            item.target = self
            item.representedObject = FinderToolsRequest(selection: selection, directory: directory, suggestedAction: action)
            if let symbol = configuration.menu.icon(for: action) {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            append(item, group: configuration.menu.grouped ? action.category.title(language: language) : nil)
        }
        if !configuration.savedActions.isEmpty { menu.addItem(.separator()) }
        for action in configuration.savedActions {
            let item = NSMenuItem(title: action.title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = FinderToolsRequest(selection: selection, directory: directory, savedActionID: action.id)
            append(item, group: action.group)
        }
        self.menu = menu
        menu.popUp(positioning: nil, at: point, in: nil)
        self.menu = nil
    }

    @objc private func choose(_ item: NSMenuItem) {
        guard AppFeature.finderTools.isAvailable, let request = item.representedObject as? FinderToolsRequest else { return }
        DispatchQueue.main.async { [weak self] in
            guard AppFeature.finderTools.isAvailable else { return }
            self?.open(request)
        }
    }
}

/// Read Finder's explicitly selected URLs only when it already has Automation
/// consent. Apple event lists preserve filenames containing newlines and commas.
private enum FinderToolsSelectionReader {
    static func read() -> FinderToolsRequest? {
        guard Permissions.automationStatus(for: .finder) == .granted else { return nil }
        let source = """
        with timeout of 3 seconds
            tell application "Finder"
                set selectedItems to selection
                if (count of selectedItems) > 128 then return {}
                set paths to {}
                repeat with itemRef in selectedItems
                    set end of paths to POSIX path of (itemRef as alias)
                end repeat
                return {paths, POSIX path of (insertion location as alias)}
            end tell
        end timeout
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, result.numberOfItems == 2, let paths = result.atIndex(1),
              paths.numberOfItems <= 128, let folder = result.atIndex(2)?.stringValue,
              folder.hasPrefix("/") else { return nil }
        var selection: [URL] = []
        for index in 0..<paths.numberOfItems {
            guard let path = paths.atIndex(index + 1)?.stringValue, path.hasPrefix("/") else { return nil }
            selection.append(URL(fileURLWithPath: path))
        }
        let request = FinderToolsRequest(selection: selection, directory: URL(fileURLWithPath: folder))
        return request.url == nil ? nil : request
    }
}
