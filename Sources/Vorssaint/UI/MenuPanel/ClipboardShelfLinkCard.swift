// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import LinkPresentation
import SwiftUI

struct ClipboardShelfLinkCard: View {
    let entryID: UUID
    let url: URL
    let linkText: String
    let tokens: [String]
    let text: ClipboardShelfStrings
    @AppStorage(DefaultsKey.clipboardShelfLinkPreviews) private var enabled = false
    @State private var provider: LPMetadataProvider?
    @State private var metadata: LPLinkMetadata?
    @State private var failed = false
    @FocusState private var loadFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let metadata {
                ShelfLinkPreview(metadata: metadata)
                    .frame(height: 105)
                    .clipped()
                    .allowsHitTesting(false)
            } else {
                Label(url.host ?? linkText, systemImage: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                SearchHighlightText.text(linkText, tokens: tokens, fontSize: 11)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if enabled && metadata == nil { loadControl }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: enabled) { _, enabled in if !enabled { reset() } }
        .onChange(of: url) { _, _ in reset() }
        .onChange(of: loadFocused) { _, focused in updateFocus(focused) }
        .onDisappear {
            updateFocus(false)
            reset()
        }
    }

    @ViewBuilder
    private var loadControl: some View {
        if provider != nil {
            ProgressView().controlSize(.small).accessibilityLabel(text.loadLinkPreview)
        } else {
            Button(text.loadLinkPreview, action: load)
                .controlSize(.small)
                .focused($loadFocused)
                .onKeyPress(keys: ClipboardHistoryFocus.buttonConfirmationKeys) { _ in
                    load()
                    return .handled
                }
                .help(text.linkPreviewsCaption)
            if failed {
                Text(text.linkPreviewUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func updateFocus(_ focused: Bool) {
        let history = ClipboardHistoryService.shared
        if focused {
            history.focusedShelfLinkPreviewID = entryID
        } else if history.focusedShelfLinkPreviewID == entryID {
            history.focusedShelfLinkPreviewID = nil
        }
    }

    private func load() {
        guard enabled, provider == nil else { return }
        let requestProvider = LPMetadataProvider()
        requestProvider.timeout = 8
        requestProvider.shouldFetchSubresources = false
        provider = requestProvider
        failed = false

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpShouldHandleCookies = false
        request.attribution = .user
        requestProvider.startFetchingMetadata(for: request) { linkMetadata, _ in
            DispatchQueue.main.async {
                guard provider === requestProvider else { return }
                provider = nil
                metadata = linkMetadata
                failed = linkMetadata == nil
            }
        }
    }

    private func reset() {
        provider?.cancel()
        provider = nil
        metadata = nil
        failed = false
    }
}

private struct ShelfLinkPreview: NSViewRepresentable {
    let metadata: LPLinkMetadata

    func makeNSView(context: Context) -> LPLinkView { LPLinkView(metadata: metadata) }

    func updateNSView(_ view: LPLinkView, context: Context) {
        view.metadata = metadata
    }
}
