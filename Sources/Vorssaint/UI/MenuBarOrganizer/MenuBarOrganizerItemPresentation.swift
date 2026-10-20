// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// How a menu bar item is named and drawn, shared by the layout editor and the
/// shelf so an icon reads the same in both. Hidden and never-shown items are
/// gone from Accessibility, so names fall back to what was remembered.
struct MenuBarOrganizerItemPresentation {
    let inventory: [MenuBarItemSnapshot]
    let lastHidden: [MenuBarHiddenRecord]
    let neverShown: [MenuBarHiddenRecord]
    let strings: MenuBarOrganizerFeatureStrings

    func snapshot(_ identity: MenuBarItemIdentity) -> MenuBarItemSnapshot? {
        inventory.first { $0.identity == identity }
    }

    /// The app's name, from the last walk, then from memory, then the item's
    /// own title. Several icons of one app among `siblings` are told apart by
    /// their own names.
    func name(_ identity: MenuBarItemIdentity, among siblings: [MenuBarItemIdentity]) -> String {
        if let system = MenuBarSystemItem.item(for: identity) { return systemName(system) }
        let appName = snapshot(identity)?.appName
            ?? (lastHidden + neverShown).first { $0.identity == identity }?.appName
            ?? identity.title
        let count = siblings.filter { $0.bundleID == identity.bundleID }.count
        return count > 1 && appName != identity.title ? "\(appName) (\(identity.title))" : appName
    }

    /// The app's icon, a symbol for a system item, the generic menu bar symbol
    /// for anything without an app to show.
    @ViewBuilder
    func icon(_ identity: MenuBarItemIdentity) -> some View {
        if let system = MenuBarSystemItem.item(for: identity) {
            Image(systemName: system.symbol)
                .foregroundStyle(.secondary)
        } else if identity.bundleID != MenuBarOrganizerPolicy.agentBundleID, let url = bundleURL(identity) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        } else {
            Image(systemName: "menubar.rectangle")
                .foregroundStyle(.secondary)
        }
    }

    private func bundleURL(_ identity: MenuBarItemIdentity) -> URL? {
        snapshot(identity).flatMap { NSRunningApplication(processIdentifier: $0.pid)?.bundleURL }
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: identity.bundleID)
    }

    private func systemName(_ item: MenuBarSystemItem) -> String {
        switch item {
        case .battery: return strings.systemBattery
        case .bluetooth: return strings.systemBluetooth
        case .clock: return strings.systemClock
        case .displays: return strings.systemDisplays
        case .keyboard: return strings.systemKeyboard
        case .sound: return strings.systemSound
        case .wifi: return strings.systemWiFi
        case .screenMirroring: return strings.systemScreenMirroring
        case .controlCenter: return strings.systemControlCenter
        }
    }
}
