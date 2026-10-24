// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// iCloud sync at a glance in the history window, only while sync is on: a
/// symbol and one short line, kept current while the window stays open.
/// Clicking it syncs now. It sizes itself and assumes nothing about the bar
/// it sits in.
struct ClipboardSyncStatusView: View {
    @ObservedObject private var sync = ClipboardHistorySyncService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        if ClipboardSyncStatusDisplay.isShown(sync.status) {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                status(at: context.date)
            }
        }
    }

    private func status(at now: Date) -> some View {
        let display = ClipboardSyncStatusDisplay(status: sync.status, syncing: sync.isSyncing,
                                                 now: now, language: l10n.language)
        return Button {
            ClipboardHistorySyncService.shared.syncNow()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: display.symbol)
                Text(display.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(display.tone == .warning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sync.isSyncing)
        .help(display.help)
        .accessibilityLabel(FeatureStrings.clipboardSync(l10n.language).statusLabel)
        .accessibilityValue(display.text)
    }
}
