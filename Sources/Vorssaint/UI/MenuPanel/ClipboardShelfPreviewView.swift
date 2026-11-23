// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import QuickLookUI
import SwiftUI

struct ClipboardShelfPreviewView: View {
    let entry: ClipboardHistoryEntry
    let text: ClipboardFeatureStrings
    let loadLinkImmediately: Bool
    let linkSnapshot: ClipboardShelfLinkSnapshot?
    let onLinkSnapshot: (ClipboardShelfLinkSnapshot) -> Void

    @ObservedObject private var l10n = L10n.shared
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
            if let color = entry.color {
                colorPreview(color)
            } else if let url = entry.shelfLink {
                ClipboardShelfLinkPreview(url: url, snapshot: linkSnapshot, strings: .forLanguage(l10n.language),
                                          openInBrowser: FeatureStrings.commandBar(l10n.language).openInBrowser,
                                          loadImmediately: loadLinkImmediately, onSnapshot: onLinkSnapshot)
            } else if entry.kind == .text {
                ClipboardTextPreview(text: entry.text).padding(14)
            } else {
                filePreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func colorPreview(_ color: ColorValue) -> some View {
        VStack(spacing: 0) {
            ClipboardShelfColorPreview(color: color, selectsCode: true)
            if entry.text.caseInsensitiveCompare(ClipboardShelfColorPreview.hexCode(for: color)) != .orderedSame {
                Text(entry.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
        }
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

struct ClipboardShelfColorPreview: View {
    let color: ColorValue
    var selectsCode = false

    static func hexCode(for color: ColorValue) -> String {
        ColorValue.string(red: color.red, green: color.green, blue: color.blue,
                          alpha: color.alpha < 1 ? color.alpha : nil, format: .hex)
    }

    private var labelColor: Color {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        return luminance > 0.179 && color.alpha == 1 ? .black : .white
    }

    var body: some View {
        ZStack {
            if color.alpha < 1 { checkerboard }
            Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
                .accessibilityHidden(true)
            if selectsCode {
                codeLabel.textSelection(.enabled)
            } else {
                codeLabel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var codeLabel: some View {
        Text(Self.hexCode(for: color))
            .font(.system(size: 27, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(labelColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.alpha < 1 ? .black.opacity(0.82) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
    }

    private var checkerboard: some View {
        Canvas { context, size in
            let tile: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.85)))
            for row in 0..<Int(ceil(size.height / tile)) {
                for column in stride(from: row % 2, to: Int(ceil(size.width / tile)), by: 2) {
                    let square = CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)
                    context.fill(Path(square), with: .color(Color(white: 0.65)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
