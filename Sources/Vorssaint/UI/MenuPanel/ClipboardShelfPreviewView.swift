// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import QuickLookUI
import SwiftUI

struct ClipboardShelfPreviewView: View {
    let entry: ClipboardHistoryEntry
    let text: ClipboardFeatureStrings
    @State private var selectedFile = 0

    private var files: [URL] {
        switch entry.kind {
        case .text:
            return []
        case .files:
            return entry.filePaths.map { URL(fileURLWithPath: $0) }
        case .image:
            guard let name = entry.imageFile, let directory = ClipboardImageStore.directory else { return [] }
            return [directory.appendingPathComponent(name)]
        }
    }

    var body: some View {
        Group {
            if entry.kind == .text {
                textPreview
            } else {
                filePreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let color = entry.color {
                ColorSwatch(color: color, size: 54)
            }
            ClipboardTextPreview(text: entry.text)
        }
        .padding(14)
    }

    private var filePreview: some View {
        let files = files
        return VStack(spacing: 0) {
            if files.count > 1 {
                Picker(text.previewLabel, selection: $selectedFile) {
                    ForEach(files.indices, id: \.self) { index in
                        Text(files[index].lastPathComponent).tag(index)
                    }
                }
                .padding(10)
            }
            if files.indices.contains(selectedFile) {
                ClipboardFileQuickLook(file: files[selectedFile])
            } else {
                Text(text.noResults).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ClipboardFileQuickLook: NSViewRepresentable {
    let file: URL

    func makeNSView(context: Context) -> QLPreviewView {
        QLPreviewView(frame: .zero, style: .normal)
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = file as NSURL
    }
}
