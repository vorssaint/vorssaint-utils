// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One place listing every global shortcut currently registered, so nobody
/// has to remember which feature page holds which combo. Read-only on
/// purpose: each shortcut keeps being configured where its feature lives.
struct ShortcutsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared

    private var activeRoles: [GlobalShortcutRole] {
        GlobalShortcutRole.activeRoles(isOn: { UserDefaults.standard.bool(forKey: $0) },
                                       isAvailable: { $0.isAvailable })
    }

    private var layoutShortcuts: [WindowLayoutAction] {
        guard AppFeature.windowLayout.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.windowLayoutShortcutsEnabled) else { return [] }
        return WindowLayoutAction.shortcutActions.filter { $0.savedShortcut != nil }
    }

    var body: some View {
        Form {
            Section {
                Text(l10n.s.shortcutsPageCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(activeRoles) { role in
                    row(title: role.title(l10n.s), keys: role.savedShortcut.displayString)
                }
            }
            if !layoutShortcuts.isEmpty {
                Section(FeatureStrings.windowLayout(l10n.language).title) {
                    ForEach(layoutShortcuts) { action in
                        if let shortcut = action.savedShortcut {
                            row(title: action.title(FeatureStrings.windowLayout(l10n.language)),
                                keys: shortcut.displayString)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(title: String, keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
    }
}
