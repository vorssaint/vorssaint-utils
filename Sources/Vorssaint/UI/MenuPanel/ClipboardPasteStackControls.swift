// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardPasteStackEntryAction: View {
    @ObservedObject private var history = ClipboardHistoryService.shared
    let entry: ClipboardHistoryEntry
    let language: AppLanguage

    var body: some View {
        let text = ClipboardPasteStackStrings.forLanguage(language)
        let title = history.pasteStackCount == 0 ? text.create : text.add
        Button(title, systemImage: "square.stack") { history.addToPasteStack(entry) }
    }
}

struct ClipboardPasteStackMenu: View {
    @ObservedObject private var history = ClipboardHistoryService.shared
    let language: AppLanguage
    var showsName = false

    var body: some View {
        if history.pasteStackCount > 0 {
            let text = ClipboardPasteStackStrings.forLanguage(language)
            Menu {
                Button(text.pasteNext, systemImage: "clipboard") { history.pasteNextFromStack() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(!history.canPasteNextFromStack)
                Button(text.skipNext, systemImage: "forward.end") { history.skipNextPasteStackEntry() }
                Button(text.clear, systemImage: "xmark", role: .destructive) { history.clearPasteStack() }
            } label: {
                Label(showsName ? text.title : history.pasteStackCount.formatted(), systemImage: "square.stack")
                    .font(.system(size: 11, weight: .medium))
                    .frame(minHeight: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(text.title)
            .accessibilityValue(history.pasteStackCount.formatted())
            .help(text.title)
        }
    }
}
