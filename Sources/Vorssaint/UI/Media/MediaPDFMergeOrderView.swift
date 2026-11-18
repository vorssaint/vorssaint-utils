// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Quartz
import SwiftUI

/// The merge order for the PDF tool: one row per input, reorderable by dragging or with the
/// arrow buttons. The selected file can be previewed inline, with the eye button or Space,
/// so pages can be checked before anything is written.
struct MediaPDFMergeOrderView: View {
    @Binding var urls: [URL]
    let caption: String
    let previewHelp: String
    let moveUpHelp: String
    let moveDownHelp: String
    let compact: Bool
    let isDisabled: Bool

    @State private var selection: URL?
    @State private var isPreviewing = false
    @State private var pageCounts: [URL: Int] = [:]
    @State private var icons: [URL: NSImage] = [:]
    /// Files already probed, readable or not, so a reorder never reopens them.
    @State private var probed: Set<URL> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(caption)
                    .font(.system(size: compact ? 9.5 : 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // Space works when the list has keyboard focus; hosts that never take key
                // focus (the menu popover) still need a pointer route to the preview.
                Button {
                    isPreviewing.toggle()
                } label: {
                    Image(systemName: isPreviewing ? "eye.fill" : "eye")
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                .help(previewHelp)
            }

            // The compact Notch has no room for both, so there the preview takes the list's place.
            if !(compact && showsPreview) {
                List(selection: $selection) {
                    ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                        row(url, position: index)
                            .tag(url)
                    }
                    .onMove { source, destination in
                        guard !isDisabled else { return }
                        urls.move(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(height: listHeight)
                .disabled(isDisabled)
                .onKeyPress(.space) {
                    guard selection != nil else { return .ignored }
                    isPreviewing.toggle()
                    return .handled
                }
            }

            if showsPreview, let selection {
                QuickLookPreview(url: selection)
                    .frame(height: compact ? listHeight : 320)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .task(id: urls) { await loadDetails() }
        .onChange(of: urls) { _, newURLs in
            if let selection, !newURLs.contains(selection) { self.selection = nil; isPreviewing = false }
        }
    }

    private var listHeight: CGFloat {
        min(CGFloat(max(urls.count, 2)) * (compact ? 30 : 36) + 8, compact ? 160 : 220)
    }

    private var showsPreview: Bool {
        isPreviewing && selection.map(urls.contains) == true
    }

    private func row(_ url: URL, position: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(position + 1)")
                .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Group {
                if let icon = icons[url] {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc").foregroundStyle(.secondary)
                }
            }
            .frame(width: compact ? 20 : 26, height: compact ? 20 : 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: compact ? 10.5 : 11.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let pages = pageCounts[url], pages > 1 {
                    // A symbol and a number need no translation or plural rules.
                    Label("\(pages)", systemImage: "doc.on.doc")
                        .font(.system(size: compact ? 9 : 9.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            moveButton("chevron.up", help: moveUpHelp, enabled: position > 0) {
                urls.move(fromOffsets: [position], toOffset: position - 1)
            }
            moveButton("chevron.down", help: moveDownHelp, enabled: position < urls.count - 1) {
                urls.move(fromOffsets: [position], toOffset: position + 2)
            }
        }
        .padding(.vertical, 1)
    }

    private func moveButton(_ symbol: String, help: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.borderless)
        .disabled(!enabled || isDisabled)
        .help(help)
    }

    /// Page counts and icons load once per file, off the main thread where possible.
    private func loadDetails() async {
        for url in urls where !probed.contains(url) {
            let count = await Task.detached(priority: .utility) { MediaPDFMerger.pageCount(of: url) }.value
            guard !Task.isCancelled else { return }
            if let count { pageCounts[url] = count }
            if let thumbnail = await ImageThumbnailer.thumbnail(for: url, pointSize: 26) {
                icons[url] = thumbnail
            } else {
                icons[url] = NSWorkspace.shared.icon(forFile: url.path)
            }
            guard !Task.isCancelled else { return }
            probed.insert(url)
        }
    }
}

/// Inline Quick Look for one file; multi-page PDFs scroll.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view: QLPreviewView = QLPreviewView(frame: .zero, style: .normal)
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
