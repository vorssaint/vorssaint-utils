// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The opt-in iCloud sync of the clipboard history, beside the options that
/// decide what the history keeps: sync only ever carries what those let in.
/// Shown only in a build signed for an iCloud container.
struct ClipboardSyncSettingsSection: View {
    let historyEnabled: Bool
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var sync = ClipboardHistorySyncService.shared
    @AppStorage(DefaultsKey.clipboardHistorySyncEnabled) private var syncEnabled = false
    @AppStorage(DefaultsKey.clipboardHistorySyncImages) private var syncImages = false

    private var text: ClipboardSyncStrings {
        FeatureStrings.clipboardSync(l10n.language)
    }

    var body: some View {
        if ClipboardHistorySyncService.isAvailable {
            section
        }
    }

    private var section: some View {
        Section {
            Toggle(text.enable, isOn: $syncEnabled)
                .disabled(!historyEnabled)
                .onChange(of: syncEnabled) { _, enabled in
                    ClipboardHistorySyncService.shared.setEnabled(enabled)
                }
            Picker(text.content, selection: $syncImages) {
                Text(text.textOnly).tag(false)
                Text(text.textAndImages).tag(true)
            }
            .disabled(!historyEnabled || !syncEnabled)
            Text(text.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text.privacyNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if historyEnabled, syncEnabled {
                status
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch sync.status {
        case .off:
            EmptyView()
        case .checking:
            Label(text.checking, systemImage: "icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .noAccount:
            Label(text.noAccount, systemImage: "icloud.slash")
                .font(.caption)
                .foregroundStyle(.orange)
        case .unavailable:
            Label(text.unavailable, systemImage: "exclamationmark.icloud")
                .font(.caption)
                .foregroundStyle(.orange)
        case .storageFull:
            Label(text.storageFull, systemImage: "exclamationmark.icloud")
                .font(.caption)
                .foregroundStyle(.orange)
        case let .synced(at, otherMacs):
            let time = at.formatted(Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(l10n.language.formattingLocale()))
            Label(String(format: text.syncedFormat, time) + " · " + String(format: text.otherMacsFormat, otherMacs),
                  systemImage: "checkmark.icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
