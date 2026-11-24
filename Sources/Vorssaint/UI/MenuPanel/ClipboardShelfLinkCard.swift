// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardShelfLinkSnapshot: Equatable {
    let url: URL
    let title: String
    let image: NSImage?
}

struct ClipboardShelfLinkCard: View {
    let entryID: UUID
    let url: URL
    let linkText: String
    let tokens: [String]
    let text: ClipboardShelfStrings
    let previewLabel: String
    let snapshot: ClipboardShelfLinkSnapshot?
    let openPreview: (Bool) -> Void

    @AppStorage(DefaultsKey.clipboardShelfLinkPreviews) private var enabled = false
    @FocusState private var loadFocused: Bool

    private var visibleSnapshot: ClipboardShelfLinkSnapshot? { enabled ? snapshot : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
            details
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: loadFocused) { _, focused in updateFocus(focused) }
        .onDisappear { updateFocus(false) }
    }

    private var artwork: some View {
        Group {
            if let image = visibleSnapshot?.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
        .padding(.horizontal, 11)
        .padding(.top, 9)
    }

    private var details: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                SearchHighlightText.text(visibleSnapshot?.title ?? linkText, tokens: tokens, fontSize: 12)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text((visibleSnapshot?.url ?? url).host ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if enabled { previewButton }
        }
        .padding(.horizontal, 11)
        .padding(.top, 7)
    }

    private var previewButton: some View {
        let label = visibleSnapshot == nil ? text.loadLinkPreview : previewLabel
        return Button(label, systemImage: "eye") { openPreview(visibleSnapshot == nil) }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .focused($loadFocused)
            .onKeyPress(keys: ClipboardHistoryFocus.buttonConfirmationKeys) { _ in
                openPreview(visibleSnapshot == nil)
                return .handled
            }
            .help(label)
    }

    private func updateFocus(_ focused: Bool) {
        let history = ClipboardHistoryService.shared
        if focused {
            history.focusedShelfLinkPreviewID = entryID
        } else if history.focusedShelfLinkPreviewID == entryID {
            history.focusedShelfLinkPreviewID = nil
        }
    }
}
