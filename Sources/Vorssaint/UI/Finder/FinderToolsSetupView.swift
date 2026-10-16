// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import FinderSync

struct FinderToolsSetupView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var enabled = FIFinderSyncController.isExtensionEnabled
    private var text: FinderToolsSetupStrings { .localized(l10n.language.rawValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.title).font(.headline)
            Text(text.description).font(.caption).foregroundStyle(.secondary)
            HStack {
                Label(enabled ? text.enabled : text.disabled, systemImage: enabled ? "checkmark.circle" : "circle")
                    .font(.caption)
                Spacer()
                Button(text.open) { FIFinderSyncController.showExtensionManagementInterface() }
            }
            if FinderToolsMenuSnapshot.sharedDefaults == nil {
                Text(text.localBuild).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            enabled = FIFinderSyncController.isExtensionEnabled
        }
    }
}
