// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The right-hand preview pane of the clipboard quick panel. Always shows the
/// full content of the currently selected history entry so the user can read
/// it and select any portion with the mouse before copying.
struct ClipboardEntryPreviewSidebar: View {
    var text: ClipboardFeatureStrings
    var entry: ClipboardHistoryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider()
            if let entry {
                contentScrollView(entry)
                Divider()
                sidebarFooter(entry)
            } else {
                emptyState
            }
        }
        .padding(.leading, 12)
    }

    // MARK: – Header

    private var sidebarHeader: some View {
        Text(text.previewLabel.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
            .padding(.bottom, 7)
    }

    // MARK: – Content

    private func contentScrollView(_ entry: ClipboardHistoryEntry) -> some View {
        ScrollView {
            previewContent(entry)
                .padding(.vertical, 10)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func previewContent(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            // The full text with standard macOS selection so the user can
            // highlight any substring and press ⌘C to copy just that part.
            // ⌘C only reaches here when no batch selection is active in the
            // list (the key monitor leaves it alone in that case).
            Text(entry.text)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .topLeading)

        case .image:
            imagePreview(entry)

        case .files:
            Text(entry.filePaths.joined(separator: "\n"))
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func imagePreview(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = entry.imageFile,
               let image = ClipboardImageStore.thumbnail(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: – Empty state

    private var emptyState: some View {
        Image(systemName: "doc.on.clipboard")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Footer

    private func sidebarFooter(_ entry: ClipboardHistoryEntry) -> some View {
        HStack(spacing: 6) {
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.accentColor)
            }
            Text(entry.copiedAt, style: .time)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(text.copy) {
                ClipboardHistoryService.shared.copyOnlyQuickEntry(entry)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 4)
    }
}
