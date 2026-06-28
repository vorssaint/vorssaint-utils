// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardQuickPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @FocusState private var searchFocused: Bool

    private var text: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var filtered: [ClipboardHistoryEntry] {
        history.filteredQuickEntries
    }

    private var canReorderEntries: Bool {
        history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            search
            content
            footer
        }
        .padding(16)
        .frame(width: 520, height: 560, alignment: .topLeading)
        .background(.regularMaterial)
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title)
                    .font(.system(size: 15, weight: .bold))
                Text(text.shortcutHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer()
            Button {
                history.hideHistoryWindow()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }

    private var search: some View {
        TextField(text.search, text: $history.quickQuery)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState(history.entries.isEmpty ? text.empty : text.noResults)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if history.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            section(title: text.pinned, entries: history.pinnedEntries)
                            section(title: text.recent, entries: history.recentEntries)
                        } else {
                            section(title: text.newestFirst, entries: filtered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: history.quickSelectionIndex) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
                .onChange(of: history.quickQuery) { _, _ in
                    scrollSelectedEntry(with: proxy)
                }
            }
        }
    }

    private func section(title: String, entries: [ClipboardHistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if !entries.isEmpty {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                ForEach(Array(entries.enumerated()), id: \.element.id) { _, entry in
                    entryRow(entry,
                             shortcutIndex: shortcutIndex(for: entry),
                             isSelected: history.selectedQuickEntryID == entry.id)
                        .id(entry.id)
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func entryRow(_ entry: ClipboardHistoryEntry,
                          shortcutIndex: Int?,
                          isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            if let shortcutIndex {
                Text("⌘\(shortcutIndex + 1)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    )
            } else {
                Image(systemName: entry.isPinned ? "pin.fill" : "doc.text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.isPinned ? Color.accentColor : Color.secondary)
                    .opacity(entry.isPinned ? 1 : 0.65)
                    .frame(width: 32, height: 24)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.preview)
                    .font(.system(size: 11.5))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .help(entry.preview)
                HStack(spacing: 7) {
                    Text(entry.copiedAt, style: .time)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        history.move(entry, .up)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(text.moveUp)
                    .disabled(!canReorderEntries || !history.canMove(entry, .up))
                    Button {
                        history.move(entry, .down)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(text.moveDown)
                    .disabled(!canReorderEntries || !history.canMove(entry, .down))
                    Button {
                        history.togglePin(entry)
                    } label: {
                        Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(entry.isPinned ? text.unpin : text.pin)
                    Button {
                        history.remove(entry)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(text.delete)
                    Button {
                        history.copyOnlyQuickEntry(entry)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .help(text.copy)
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(entry.isPinned ? 0.075 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1)
        )
        .help(entry.preview)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(text.clearRecent) {
                history.clearRecent()
            }
            .disabled(history.recentEntries.isEmpty)
            Button(text.clearAll) {
                history.clearAll()
            }
            .disabled(history.recentEntries.isEmpty)
            Spacer()
            Text("\(history.entries.count)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
    }

    private func shortcutIndex(for entry: ClipboardHistoryEntry) -> Int? {
        guard let index = filtered.firstIndex(where: { $0.id == entry.id }), index < 9 else { return nil }
        return index
    }

    private func scrollSelectedEntry(with proxy: ScrollViewProxy) {
        guard let id = history.selectedQuickEntryID else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}
