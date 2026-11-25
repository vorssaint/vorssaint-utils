// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import QuickLookUI
import SwiftUI

struct ClipboardShelfPreviewChrome<Content: View>: View {
    let edge: ClipboardShelfEdge
    let pointer: CGFloat?
    let content: Content

    private var facingEdge: Edge.Set {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
            ZStack {
                content
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
                    .padding(facingEdge, pointer == nil ? 0 : 8)
                pointerView(in: geometry.size)
            }
        }
    }

    @ViewBuilder
    private func pointerView(in size: CGSize) -> some View {
        if let pointer {
            tail(at: pointer, in: size)
                .fill(Color(nsColor: .windowBackgroundColor))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func tail(at position: CGFloat, in size: CGSize) -> Path {
        let extent = edge.isVertical ? size.height : size.width
        let center = min(max(20, position), max(20, extent - 20))
        func point(_ along: CGFloat, _ inset: CGFloat) -> CGPoint {
            switch edge {
            case .top: return CGPoint(x: along, y: inset)
            case .bottom: return CGPoint(x: along, y: size.height - inset)
            case .left: return CGPoint(x: inset, y: along)
            case .right: return CGPoint(x: size.width - inset, y: along)
            }
        }
        return Path { path in
            path.move(to: point(center - 8, 9))
            path.addLine(to: point(center, 0))
            path.addLine(to: point(center + 8, 9))
            path.closeSubpath()
        }
    }
}

struct ClipboardShelfPreviewView: View {
    let entry: ClipboardHistoryEntry
    let text: ClipboardFeatureStrings
    let title: String
    let loadLinkImmediately: Bool
    let editText: Bool
    let linkSnapshot: ClipboardShelfLinkSnapshot?
    let close: () -> Void
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
            if editText {
                ClipboardShelfTextEditor(entryID: entry.id, text: text, close: close)
            } else {
                VStack(spacing: 0) {
                    header
                    content
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(l10n.s.menuClose)
            .help(l10n.s.menuClose)

            Text(title).font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
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
        return VStack(spacing: 8) {
            if files.count > 1 {
                Picker(text.previewLabel, selection: $selectedFile) {
                    ForEach(files.indices, id: \.self) { index in
                        Text(files[index].lastPathComponent).tag(index)
                    }
                }
            }
            if files.indices.contains(selectedFile) {
                let file = files[selectedFile]
                ClipboardFileQuickLook(file: file)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                if entry.kind == .files {
                    ClipboardShelfFileDetails(file: file, revealLabel: l10n.s.cleanerRevealInFinder)
                        .id(file)
                }
            } else {
                Text(text.noResults)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

private struct ClipboardShelfTextEditor: View {
    @ObservedObject private var history = ClipboardHistoryService.shared
    @State private var isEditing = false
    let entryID: UUID
    let text: ClipboardFeatureStrings
    let close: () -> Void

    var body: some View {
        ClipboardEntryPreviewSidebar(text: text,
                                     entry: history.entries.first { $0.id == entryID },
                                     isEditing: $isEditing, onClose: close, startsEditing: true)
    }
}

private struct ClipboardShelfFileDetails: View {
    let file: URL
    let revealLabel: String
    @State private var size: String?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Text((file.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(file.path)
                if let size {
                    Text("·").accessibilityHidden(true)
                    Text(size).fixedSize()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } label: {
                Label(revealLabel, systemImage: "folder")
            }
            .fixedSize()
        }
        .task {
            let path = file.path
            let fileSize = await Task.detached(priority: .utility) {
                ClipboardImageStore.fileSizeString(atPath: path)
            }.value
            if !Task.isCancelled { size = fileSize }
        }
    }
}

private struct ClipboardFileQuickLook: NSViewRepresentable {
    let file: URL

    func makeNSView(context: Context) -> QLPreviewView {
        QLPreviewView(frame: .zero, style: .normal)
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard (view.previewItem as? URL) != file else { return }
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
