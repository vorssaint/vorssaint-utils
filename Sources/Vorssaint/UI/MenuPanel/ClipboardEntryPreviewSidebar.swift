// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ImageIO
import SwiftUI

/// On-demand inspector for the selected clipboard entry. It keeps the full
/// content selectable and editable without permanently taking space from the
/// history list.
struct ClipboardEntryPreviewSidebar: View {
    @ObservedObject private var l10n = L10n.shared
    var text: ClipboardFeatureStrings
    var entry: ClipboardHistoryEntry?
    @Binding var isEditing: Bool
    var onClose: () -> Void
    @State private var draft = ""
    @State private var editingEntryID: UUID?
    /// Laid out off the main thread for the entry it was made from.
    @State private var prettyJSON: (entry: ClipboardHistoryEntry, text: String)?
    @FocusState private var editorFocused: Bool
    @State private var recognizingEntryID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider()
            if let entry {
                if editingEntryID == entry.id {
                    textEditor(entry)
                } else if entry.kind == .text {
                    textPreview(entry)
                } else {
                    contentScrollView(entry)
                }
                Divider()
                sidebarFooter(entry)
            } else {
                emptyState
            }
        }
        .onChange(of: entry?.id) { _, newID in
            if editingEntryID != nil, editingEntryID != newID {
                cancelEditing()
            }
        }
        .onDisappear { cancelEditing() }
        .task(id: entry) {
            guard let entry, entry.kind == .text else { return }
            let text = entry.text
            let pretty = await Task.detached(priority: .userInitiated) { ClipboardJSONFormat.pretty(text) }.value
            guard !Task.isCancelled else { return }
            prettyJSON = pretty.map { (entry, $0) }
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            Label(text.previewLabel, systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuClose)
            .accessibilityLabel(l10n.s.menuClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// One text view for every text entry: JSON laid out after the entry
    /// appears swaps its text and font in place instead of a new view. The
    /// layout depends only on the text, so a pin or a refreshed copy of the
    /// same entry keeps it.
    private func textPreview(_ entry: ClipboardHistoryEntry) -> ClipboardTextPreview {
        guard let pretty = prettyJSON, pretty.entry.id == entry.id, pretty.entry.text == entry.text else {
            return ClipboardTextPreview(text: entry.text)
        }
        return ClipboardTextPreview(text: pretty.text,
                                    font: .monospacedSystemFont(ofSize: 11.5, weight: .regular))
    }

    private func contentScrollView(_ entry: ClipboardHistoryEntry) -> some View {
        ScrollView {
            previewContent(entry)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private func textEditor(_ entry: ClipboardHistoryEntry) -> some View {
        TextEditor(text: $draft)
            .font(.system(size: 12))
            .lineSpacing(2)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            )
            .padding(12)
            .focused($editorFocused)
            .onExitCommand { cancelEditing() }
            .accessibilityLabel(text.edit)
    }

    @ViewBuilder
    private func previewContent(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            // Standard text selection lets someone copy only the fragment
            // they need; the window monitor leaves ⌘C with this view.
            Text(entry.text)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        case .image:
            imagePreview(entry)
        case .files:
            filesPreview(entry)
        }
    }

    @ViewBuilder
    private func imagePreview(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = entry.imageFile {
                ClipboardThumbnailImage(source: .stored(name: name),
                                        aspectRatio: entry.imageAspectRatio)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func filesPreview(_ entry: ClipboardHistoryEntry) -> some View {
        if entry.filePaths.count == 1, let path = entry.filePaths.first {
            singleFilePreview(path)
        } else {
            multipleFilesPreview(entry)
        }
    }

    @ViewBuilder
    private func singleFilePreview(_ path: String) -> some View {
        let isImage = ClipboardImageStore.isImageFile(atPath: path)
        let fileName = (path as NSString).lastPathComponent

        VStack(alignment: .leading, spacing: 10) {
            if isImage {
                ClipboardThumbnailImage(source: .file(path: path),
                                        aspectRatio: ClipboardImageStore.imageAspectRatio(atPath: path))
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                let dim = ClipboardImageStore.imageDimensionsLabel(atPath: path)
                let size = ClipboardImageStore.fileSizeString(atPath: path)
                let parts = [text.imageEntryLabel, dim, size].compactMap { $0 }
                Text(parts.joined(separator: " · "))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fileName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                        if let size = ClipboardImageStore.fileSizeString(atPath: path) {
                            Text(size)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func multipleFilesPreview(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: text.fileCountFormat, entry.filePaths.count))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(entry.filePaths, id: \.self) { path in
                    HStack(spacing: 6) {
                        if ClipboardImageStore.isImageFile(atPath: path) {
                            ClipboardThumbnailImage(source: .file(path: path, maxPixelSize: 64))
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        } else {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable()
                                .frame(width: 18, height: 18)
                        }
                        Text((path as NSString).lastPathComponent)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )

            Text(entry.filePaths.joined(separator: "\n"))
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        Image(systemName: "doc.on.clipboard")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
            if editingEntryID == entry.id {
                Button(text.cancel) {
                    cancelEditing()
                }
                Button(text.save) {
                    saveEditing(entry)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ClipboardHistoryEditing.canSave(original: entry.text, draft: draft))
            } else {
                if entry.kind == .text {
                    Button(text.edit) {
                        beginEditing(entry)
                    }
                }
                if AppFeature.screenOCR.isAvailable, let url = imageURL(entry) {
                    Button(FeatureStrings.screenshot(l10n.language).copyTextButton) {
                        copyText(in: url, of: entry)
                    }
                    .disabled(recognizingEntryID == entry.id)
                }
                Button(text.copy) {
                    ClipboardHistoryService.shared.copyOnlyQuickEntry(entry)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.mini)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    /// The picture an image entry or a single copied image file holds.
    private func imageURL(_ entry: ClipboardHistoryEntry) -> URL? {
        if entry.kind == .image, let name = entry.imageFile {
            return ClipboardImageStore.directory?.appendingPathComponent(name)
        }
        guard entry.kind == .files, entry.filePaths.count == 1,
              ClipboardImageStore.isImageFile(atPath: entry.filePaths[0]) else { return nil }
        return URL(fileURLWithPath: entry.filePaths[0])
    }

    /// Screen OCR's recognition and answer, on a picture already in the
    /// history. It runs only when asked and its text is never stored with
    /// the entry; the copy itself lands in the history like any other.
    private func copyText(in url: URL, of entry: ClipboardHistoryEntry) {
        recognizingEntryID = entry.id
        let languages = MediaSupport.recognitionLanguages(for: l10n.language.rawValue)
        let removeLineBreaks = UserDefaults.standard.bool(forKey: DefaultsKey.screenOCRRemoveLineBreaks)
        let pasteboardChangeCount = NSPasteboard.general.changeCount
        let strings = l10n.s
        Task { @MainActor in
            let outcome = await Task.detached(priority: .userInitiated) { () -> ScreenTextService.Outcome in
                // Full size, as Screen OCR reads its capture, so small text
                // survives; only a picture past the area bound is scaled down.
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
                else { return .empty }
                let maxPixelSize = ClipboardImageRecognition.decodeMaxPixelSize(width: width, height: height)
                let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                               kCGImageSourceCreateThumbnailWithTransform: true,
                               kCGImageSourceThumbnailMaxPixelSize: maxPixelSize] as CFDictionary
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return .empty }
                return ScreenTextService.outcome(for: image, detectQRCodes: false,
                                                 removeLineBreaks: removeLineBreaks,
                                                 fallbackLanguages: languages)
            }.value
            // A recognition started later, or anything copied meanwhile, is
            // newer than this answer, and Screen OCR turned off drops it.
            let isLatest = recognizingEntryID == entry.id
            if isLatest { recognizingEntryID = nil }
            guard isLatest, pasteboardChangeCount == NSPasteboard.general.changeCount,
                  AppFeature.screenOCR.isAvailable else { return }
            if case .text(let recognized) = outcome {
                ScreenTextService.copyToPasteboard(recognized)
                QuickToolHUD.show(icon: "text.viewfinder", message: strings.ocrCopied)
            } else {
                QuickToolHUD.show(icon: "text.viewfinder", message: strings.ocrNoText)
            }
        }
    }

    private func beginEditing(_ entry: ClipboardHistoryEntry) {
        draft = entry.text
        editingEntryID = entry.id
        isEditing = true
        DispatchQueue.main.async { editorFocused = true }
    }

    private func cancelEditing() {
        editorFocused = false
        editingEntryID = nil
        draft = ""
        isEditing = false
    }

    private func saveEditing(_ entry: ClipboardHistoryEntry) {
        guard ClipboardHistoryService.shared.updateText(entry, to: draft) else { return }
        cancelEditing()
    }
}
