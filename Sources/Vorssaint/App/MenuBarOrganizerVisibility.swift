// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MenuBarOrganizerSection: String, CaseIterable {
    case visible, hidden, alwaysHidden
}

struct MenuBarOrganizerRules {
    private(set) var storage: [String: String]

    init(storage: [String: String] = [:]) {
        self.storage = storage.filter { MenuBarOrganizerSection(rawValue: $0.value) != nil }
    }

    func section(for bundle: String) -> MenuBarOrganizerSection {
        MenuBarOrganizerSection(rawValue: storage[bundle] ?? "") ?? .visible
    }

    mutating func set(_ section: MenuBarOrganizerSection, for bundle: String) {
        storage[bundle] = section == .visible ? nil : section.rawValue
    }

    func hiddenBundles(state: MenuBarOrganizerVisibility, ownBundleID: String) -> Set<String> {
        Set(storage.compactMap { bundle, _ in
            guard !bundle.isEmpty, bundle != ownBundleID, !bundle.hasPrefix("com.apple.") else { return nil }
            switch section(for: bundle) {
            case .visible: return nil
            case .hidden: return state.hiddenShown ? nil : bundle
            case .alwaysHidden: return state.alwaysShown ? nil : bundle
            }
        })
    }

    static func allowedBundles(running: Set<String>, menuBarOwners: Set<String> = [],
                               hidden: Set<String>, ownBundleID: String) -> Set<String> {
        // Workspace omits some accessory helpers. Include the live owners
        // discovered through Accessibility, as well as recovery/system agents.
        running.union(menuBarOwners).subtracting(hidden).union([
            ownBundleID, "com.apple.MenuBarAgent", "com.apple.controlcenter",
            "com.apple.systemuiserver", "com.apple.TextInputMenuAgent",
        ])
    }
}

struct MenuBarOrganizerVisibility {
    private(set) var hiddenShown = true
    private(set) var alwaysShown = true

    mutating func toggleHidden() {
        hiddenShown.toggle()
        alwaysShown = false
    }

    mutating func toggleAlwaysHidden() {
        alwaysShown.toggle()
        if alwaysShown { hiddenShown = true }
    }

    mutating func revealAll() {
        hiddenShown = true
        alwaysShown = true
    }

    mutating func revealHidden() {
        hiddenShown = true
        alwaysShown = false
    }

    /// macOS 27 uses native visibility instead of expanding the divider.
    static func collapsedLength(systemMajorVersion: Int, displayWidths: [CGFloat]) -> CGFloat {
        systemMajorVersion >= 27 ? 24 : 10_000
    }

}
