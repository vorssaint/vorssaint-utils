// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuickLookThumbnailing
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

/// Finder's file-type icon remains useful even after an original file disappears.
@MainActor
enum ClipboardFileIcons {
    static func icon(for paths: [String]) -> NSImage? {
        guard let path = paths.first else { return nil }
        if paths.count > 1 { return NSWorkspace.shared.icon(forFiles: paths) }
        if FileManager.default.fileExists(atPath: path) {
            return ClipboardImageStore.fileIcon(atPath: path)
        }
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: (path as NSString).pathExtension) ?? .data)
    }
}

/// Quick Look chooses the installed thumbnail provider, including PDF, Office,
/// image and movie providers. An unsupported file keeps its actual type icon.
struct ClipboardFileThumbnail: View {
    let entry: ClipboardHistoryEntry
    var index = 0
    @StateObject private var loader = ClipboardFileThumbnailLoader()
    private struct Identity: Equatable {
        let entry: ClipboardHistoryEntry
        let index: Int
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else if entry.filePaths.indices.contains(index),
                      let icon = ClipboardFileIcons.icon(for: [entry.filePaths[index]]) {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityLabel(entry.fileNames.indices.contains(index) ? entry.fileNames[index] : entry.preview)
        .task(id: Identity(entry: entry, index: index)) { await loader.load(entry, at: index) }
        .onDisappear { loader.cancel() }
    }
}

@MainActor
private final class ClipboardFileThumbnailLoader: ObservableObject {
    @Published var image: NSImage?
    private var request: QLThumbnailGenerator.Request?
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    func load(_ entry: ClipboardHistoryEntry, at index: Int) async {
        cancel()
        image = nil
        guard let lease = ClipboardHistoryFileResolver.resolve(entry, at: index) else { return }
        let values = try? lease.url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = "\(lease.url.path):\(values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0):\(values?.fileSize ?? 0)" as NSString
        if let cached = Self.cache.object(forKey: key) { image = cached; return }
        let request = QLThumbnailGenerator.Request(fileAt: lease.url, size: CGSize(width: 480, height: 360),
                                                   scale: 1, representationTypes: .thumbnail)
        self.request = request
        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        // The lease must span the provider's asynchronous read, even on cancellation.
        withExtendedLifetime(lease) {}
        guard self.request === request, !Task.isCancelled else { return }
        self.request = nil
        guard let representation, representation.type != .icon else { return }
        let image = representation.nsImage
        Self.cache.setObject(image, forKey: key,
                             cost: representation.cgImage.bytesPerRow * representation.cgImage.height)
        self.image = image
    }

    func cancel() {
        if let request { QLThumbnailGenerator.shared.cancel(request) }
        request = nil
    }
}

/// This view owns Quick Look's scroll, page, zoom and media controls. The drag
/// source lives on its header, so interacting with a document never starts a drag.
struct ClipboardFilesPreview: View {
    let entry: ClipboardHistoryEntry
    @State private var selection = 0

    private var selectedIndex: Int {
        entry.filePaths.indices.contains(selection) ? selection : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            if entry.filePaths.count > 1 {
                Picker("", selection: $selection) {
                    ForEach(Array(entry.fileNames.enumerated()), id: \.offset) { index, name in
                        Text(name).tag(index)
                    }
                }
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }
            if entry.filePaths.indices.contains(selectedIndex) {
                HStack(spacing: 8) {
                    if let icon = ClipboardFileIcons.icon(for: [entry.filePaths[selectedIndex]]) {
                        Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                    }
                    Text(entry.fileNames[selectedIndex])
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipboardHistoryDragSource(entry, activate: {}, draggingChanged: { active in
                    ClipboardHistoryService.shared.setQuickDragging(active)
                    NotchService.shared.setClipboardDragging(active)
                })
                ClipboardNativeFilePreview(entry: entry, index: selectedIndex)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: entry.id) { _, _ in selection = 0 }
    }
}

struct ClipboardNativeFilePreview: NSViewRepresentable {
    let entry: ClipboardHistoryEntry
    let index: Int

    func makeNSView(context: Context) -> NSView {
        let view = Container()
        context.coordinator.container = view
        return view
    }

    /// The history's keyboard shortcuts yield while Quick Look owns focus.
    static func ownsFocus(_ responder: NSResponder?) -> Bool {
        var responder = responder
        while let current = responder {
            if current is Container { return true }
            responder = current.nextResponder
        }
        return false
    }

    private final class Container: NSView {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(entry, index: index)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    @MainActor final class Coordinator {
        weak var container: NSView?
        private var preview: QLPreviewView?
        private var lease: ClipboardHistoryFileLease?
        private var identity: ClipboardHistoryEntry?
        private var index: Int?

        func update(_ entry: ClipboardHistoryEntry, index: Int) {
            guard identity != entry || self.index != index else { return }
            close()
            identity = entry
            self.index = index
            guard let container else { return }
            guard let lease = ClipboardHistoryFileResolver.resolve(entry, at: index) else {
                let label = NSTextField(wrappingLabelWithString: ClipboardFilePreviewStrings.unavailable(L10n.shared.language))
                label.alignment = .center
                label.textColor = .secondaryLabelColor
                label.font = .systemFont(ofSize: 12)
                label.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                    label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20)
                ])
                return
            }
            self.lease = lease
            guard let preview = QLPreviewView(frame: container.bounds, style: .compact) else { return }
            preview.shouldCloseWithWindow = false
            preview.autostarts = false
            preview.autoresizingMask = [.width, .height]
            container.addSubview(preview)
            self.preview = preview
            preview.previewItem = FileItem(url: lease.url, title: entry.fileNames[index])
        }

        func close() {
            preview?.close()
            preview = nil
            container?.subviews.forEach { $0.removeFromSuperview() }
            lease = nil
            identity = nil
            index = nil
        }
    }

    private final class FileItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?
        init(url: URL, title: String) {
            previewItemURL = url
            previewItemTitle = title
        }
    }
}

private enum ClipboardFilePreviewStrings {
    static func unavailable(_ language: AppLanguage) -> String {
        switch language {
        case .enUS: return "Copy this file again from its source to preview it."
        case .ptBR: return "Copie este arquivo novamente da origem para visualizá-lo."
        case .tr: return "Önizlemek için bu dosyayı kaynağından tekrar kopyalayın."
        case .ru: return "Скопируйте файл из источника ещё раз для предпросмотра."
        case .es: return "Vuelve a copiar este archivo desde su origen para previsualizarlo."
        case .sk: return "Ak chcete zobraziť ukážku, skopírujte súbor znova zo zdroja."
        case .de: return "Kopiere diese Datei erneut aus ihrer Quelle, um sie anzuzeigen."
        case .fr: return "Recopiez ce fichier depuis sa source pour l’aperçu."
        case .it: return "Copia di nuovo questo file dall’origine per visualizzarlo."
        case .ja: return "プレビューするには、元の場所からこのファイルをもう一度コピーしてください。"
        case .ko: return "미리 보려면 원본에서 이 파일을 다시 복사하세요."
        case .zhHans: return "请从原位置重新复制此文件以预览内容。"
        case .zhTW, .zhHK: return "請從原位置重新複製此檔案以預覽內容。"
        case .uk: return "Скопіюйте файл із джерела ще раз для попереднього перегляду."
        }
    }
}
