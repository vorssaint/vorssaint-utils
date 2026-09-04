// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The two lines and the button the recorder shows instead of refusing a
/// combination macOS answers. The row decides what accepting does.
struct SystemShortcutTakeOverOffer: View {
    @ObservedObject private var l10n = L10n.shared
    let shortcut: GlobalShortcut
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: l10n.s.shortcutTakeOverOffer, shortcut.displayString))
                .font(.caption)
            HStack {
                Button(l10n.s.shortcutTakeOverAction, action: onAccept)
                Button(l10n.s.shortcutTakeOverDismiss, action: onDismiss)
            }
            Text(l10n.s.shortcutTakeOverCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
