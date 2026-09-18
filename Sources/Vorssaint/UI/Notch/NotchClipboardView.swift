// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchClipboardView: View {
    let service: NotchService
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var query = ""
    @State private var copiedID: UUID?
    @State private var pinnedOnly = false
    @FocusState private var searching: Bool
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }

    private var entries: [ClipboardHistoryEntry] {
        history.filteredEntries(matching: query).filter { !pinnedOnly || $0.isPinned }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(text.search, text: $query).textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searching)
                    .accessibilityLabel(text.search)
                NotchIconButton(symbol: "pin", title: text.pinned, selected: pinnedOnly) {
                    pinnedOnly.toggle()
                }
                NotchIconButton(symbol: "arrow.up.forward.app", title: text.title) {
                    service.perform { history.showHistoryWindow(preferNotch: false) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .modifier(NotchControlSurface(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(searching ? 0.34 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.15), value: searching)
            if entries.isEmpty {
                NotchEmptyView(symbol: pinnedOnly ? "pin" : "doc.on.clipboard",
                               message: query.isEmpty && !pinnedOnly ? text.empty : text.noResults)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(entries) { entry in
                            HStack(spacing: 10) {
                                Button {
                                    if permissions.accessibility {
                                        service.collapse()
                                        history.copyQuickEntry(entry)
                                    } else {
                                        history.copy(entry) { copied in
                                            if copied {
                                                copiedID = entry.id
                                            } else {
                                                NSSound.beep()
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        preview(entry)
                                        Text(entry.kind == .image ? text.imageEntryLabel : entry.preview)
                                            .font(.system(size: 12)).lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(NotchButtonStyle(lifts: false))
                                .help(permissions.accessibility ? text.clickRowShortcut : text.copy)
                                NotchIconButton(symbol: copiedID == entry.id ? "checkmark" : "doc.on.doc",
                                                title: copiedID == entry.id ? text.copied : text.copy) {
                                    history.copy(entry) { copied in
                                        if copied {
                                            copiedID = entry.id
                                        } else {
                                            NSSound.beep()
                                        }
                                    }
                                }
                                NotchIconButton(symbol: entry.isPinned ? "pin.fill" : "pin",
                                                title: entry.isPinned ? text.unpin : text.pin) {
                                    history.togglePin(entry)
                                }
                            }
                            .padding(10)
                            .modifier(NotchControlSurface(cornerRadius: 14, selected: entry.isPinned))
                        }
                    }
                    .padding(.bottom, 2)
                }.scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: copiedID) {
            // The tick confirms one copy; leaving it on the row forever would
            // read as a permanent state instead of an answer.
            guard copiedID != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            copiedID = nil
        }
    }

    @ViewBuilder private func preview(_ entry: ClipboardHistoryEntry) -> some View {
        if entry.kind == .image, let name = entry.imageFile,
           let image = ClipboardImageStore.thumbnail(named: name) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 36, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: entry.kind == .files ? "doc" : "text.alignleft")
                .foregroundStyle(.secondary).frame(width: 24)
        }
    }
}
