// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct FinderToolsQuickMenuSettings: View {
    @ObservedObject var service: FinderToolsService
    @ObservedObject var quickMenu: FinderToolsQuickMenu
    @ObservedObject private var l10n = L10n.shared
    @State private var message: String?

    var body: some View {
        let labels = FeatureStrings.radialMenu(l10n.language)
        VStack(alignment: .leading, spacing: 8) {
            Text(FinderQuickMenuStrings.title(l10n.language.rawValue)).font(.headline)
            Text(FinderQuickMenuStrings.description(l10n.language.rawValue))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(labels.profileShortcutLabel)
                Spacer()
                ShortcutRecorderButton(
                    shortcut: GlobalShortcut(storageValue: service.configuration.quickMenuShortcut ?? "") ?? .radialMenuDefault,
                    isEnabled: true,
                    waitingTitle: l10n.s.shortcutPressKeys,
                    emptyTitle: service.configuration.quickMenuShortcut?.isEmpty != false ? l10n.s.shortcutNone : nil,
                    clearAction: { service.configuration.quickMenuShortcut = nil; message = nil },
                    notCapturedAction: { message = l10n.s.shortcutNotCaptured },
                    recordingChanged: { if $0 { message = nil } },
                    invalidAction: { message = l10n.s.shortcutInvalid },
                    captureAction: { service.configuration.quickMenuShortcut = $0.storageValue; message = nil }
                ).frame(width: 130)
                Button(labels.tryButton) {
                    let frame = NSApp.keyWindow?.frame
                    quickMenu.show(at: frame.map { NSPoint(x: $0.midX, y: $0.midY) })
                }
            }
            if quickMenu.registrationFailed { Text(l10n.s.shortcutInvalid).font(.caption).foregroundStyle(.orange) }
            if let message { Text(message).font(.caption).foregroundStyle(.orange) }
        }
    }
}
