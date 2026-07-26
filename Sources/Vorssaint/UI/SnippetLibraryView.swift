// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The snippet library panel: a search field, the snippets grouped by folder
/// and a small footer. Selection is driven by the service so the key monitor
/// (arrows, Enter, ⌘digits) and the mouse agree on one source of truth.
struct SnippetLibraryView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var library = SnippetLibraryService.shared
    @FocusState private var searchFocused: Bool

    private var text: SnippetFeatureStrings {
        FeatureStrings.snippets(l10n.language)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 460)
        .background(HUDBackdrop(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onChange(of: library.presentationID) { _, _ in
            searchFocused = true
        }
        .onChange(of: library.query) { _, _ in
            library.refreshPanelLayout()
        }
        .onAppear {
            searchFocused = true
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(text.librarySearchPlaceholder, text: $library.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !library.query.isEmpty {
                Button {
                    library.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var content: some View {
        if !library.hasLibraryContent {
            emptyState
        } else if library.rows.isEmpty {
            VStack {
                Text(text.libraryNoResults)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(text.libraryEmpty)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button(text.manageButton) {
                openSnippetSettings()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(library.sections.enumerated()), id: \.element.folder) { index, section in
                        if !section.folder.isEmpty {
                            folderHeader(section.folder, topPadding: index == 0 ? 4 : 10)
                        }
                        ForEach(section.snippets) { snippet in
                            row(snippet)
                                .id(snippet.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 330)
            .onChange(of: library.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func folderHeader(_ name: String, topPadding: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "folder")
                .font(.system(size: 10, weight: .semibold))
            Text(name)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, topPadding)
        .padding(.bottom, 2)
    }

    private func row(_ snippet: TextSnippet) -> some View {
        let selected = library.selectedID == snippet.id
        return Button {
            library.insert(snippet)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(snippet.name.isEmpty ? snippet.trigger : snippet.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        if !snippet.trigger.isEmpty {
                            Text(snippet.trigger)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.primary.opacity(selected ? 0.12 : 0.07))
                                )
                        }
                    }
                    Text(preview(of: snippet))
                        .font(.caption)
                        .foregroundStyle(selected ? .secondary : .tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { library.select(snippet.id) }
        }
    }

    private func preview(of snippet: TextSnippet) -> String {
        snippet.replacement
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(text.libraryFooterHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(text.manageButton) {
                openSnippetSettings()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func openSnippetSettings() {
        library.hide()
        SettingsRouter.shared.page = .textSnippets
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
}
