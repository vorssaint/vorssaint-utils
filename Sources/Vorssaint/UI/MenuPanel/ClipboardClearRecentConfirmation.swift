// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Asks before "Clear unpinned" deletes anything. The button stores the
/// unpinned IDs it saw, and only those are deleted.
struct ClipboardClearRecentConfirmation: ViewModifier {
    @Binding var entryIDs: Set<UUID>?
    @ObservedObject private var l10n = L10n.shared

    func body(content: Content) -> some View {
        let text = FeatureStrings.clipboard(l10n.language)
        content.alert(String(format: text.clearRecentConfirmFormat, entryIDs?.count ?? 0),
                      isPresented: Binding(get: { entryIDs != nil }, set: { if !$0 { entryIDs = nil } }),
                      presenting: entryIDs) { ids in
            Button(text.cancel, role: .cancel) {}
            Button(text.clearRecent, role: .destructive) {
                ClipboardHistoryService.shared.clearRecent(ids)
            }
        } message: { _ in
            Text(text.clearRecentConfirmMessage)
        }
    }
}
