// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// On-demand inspector for the selected clipboard entry. It keeps the full
/// content selectable and editable without permanently taking space from the
/// history list.
struct ClipboardEntryPreviewSidebar: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    var text: ClipboardFeatureStrings
    var entry: ClipboardHistoryEntry?
    @Binding var isEditing: Bool
    var onClose: () -> Void
    @State private var draft = ""
    @State private var facts: ClipboardEntryFacts?
    @State private var editingEntryID: UUID?
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            Divider()
            if let entry {
                metadata(entry)
                Divider()
                if editingEntryID == entry.id {
                    textEditor(entry)
                } else if entry.kind == .text {
                    ClipboardTextPreview(text: entry.text)
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
        // The ⌘K list can ask for editing, which only this view knows how to
        // start; the request is cleared so a later one is still noticed.
        // `initial` because the request and this view often arrive in the
        // same turn, when the action also opens the pane.
        .onChange(of: history.quickEditRequest, initial: true) { _, requested in
            guard let requested, let entry, entry.id == requested, entry.kind == .text else { return }
            beginEditing(entry)
            history.clearQuickEditRequest()
        }
        .onDisappear { cancelEditing() }
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

    /// What the item is, how big it is, when it was copied and where from.
    /// The lines that need the disk or the workspace are gathered once per
    /// entry, off the main thread, so stepping through the list with the
    /// arrow keys costs the same for a big file as for a word.
    private func metadata(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            metaRow(text.typeLabel) {
                // Top-aligned: the description can wrap, and the glyph belongs
                // to its first line, not to the middle of two.
                HStack(alignment: .top, spacing: 5) {
                    ClipboardKindGlyph(kind: entry.displayKind, size: 16)
                    Text(facts?.type ?? ClipboardKindPresentation.label(entry, text: text))
                        .lineLimit(2)
                }
            }
            if let size = facts?.size {
                metaRow(text.sizeLabel) { Text(size) }
            }
            metaRow(text.copiedLabel) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.copiedAt.formatted(date: .abbreviated, time: .shortened))
                    Text(entry.copiedAt, style: .relative)
                        .foregroundStyle(.tertiary)
                }
            }
            if let source = entry.source {
                metaRow(text.sourceLabel) {
                    HStack(spacing: 5) {
                        if let icon = facts?.sourceIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(source.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .help(source.bundleID)
                }
            }
            // A file's path is already in the content below, with its own
            // copy button; only a link has a location to add here.
            if entry.displayKind == .link, let host = URL(string: entry.text)?.host {
                metaRow(text.locationLabel) {
                    Text(host)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .font(.system(size: 10.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Keyed on the entry, not its id: an edit keeps the id and changes
        // the text, and the counts here have to follow the text.
        .task(id: entry) {
            // Cleared first: the rows fall back to what the entry itself
            // says, rather than showing the previous entry's facts until the
            // disk answers for this one.
            facts = nil
            let strings = text
            let gathered = await Task.detached(priority: .userInitiated) {
                ClipboardEntryFacts.gather(entry, text: strings)
            }.value
            guard !Task.isCancelled else { return }
            facts = gathered
        }
    }

    private func metaRow<Value: View>(_ label: String,
                                      @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 58, alignment: .trailing)
            value()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The path, with a button that copies it, since the path is the thing
    /// most often wanted from a file entry short of the file itself.
    private func pathBox(_ path: String, of entry: ClipboardHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(path)
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                // The copy adds a row at the top; the selection stays on the
                // file whose path this is, so the pane does not jump.
                ClipboardHistoryService.shared.copyPlainText(path, keepingSelectionOn: entry)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(text.copy)
            .accessibilityLabel(text.copy)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
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
            if let name = entry.imageFile,
               let image = ClipboardImageStore.thumbnail(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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
            singleFilePreview(path, of: entry)
        } else {
            multipleFilesPreview(entry)
        }
    }

    @ViewBuilder
    private func singleFilePreview(_ path: String, of entry: ClipboardHistoryEntry) -> some View {
        let isImage = ClipboardImageStore.isImageFile(atPath: path)
        let thumbnail = ClipboardImageStore.fileThumbnail(atPath: path)
        let fileName = (path as NSString).lastPathComponent

        VStack(alignment: .leading, spacing: 10) {
            if isImage, let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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

            pathBox(path, of: entry)
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
                        if ClipboardImageStore.isImageFile(atPath: path),
                           let thumb = ClipboardImageStore.fileThumbnail(atPath: path, maxPixelSize: 64) {
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
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

/// The metadata lines that cost a disk or workspace round trip, gathered off
/// the main thread once per entry. Everything else is read straight off the
/// entry when drawing.
struct ClipboardEntryFacts: Sendable {
    let type: String
    let size: String?
    let sourceIcon: NSImage?

    static func gather(_ entry: ClipboardHistoryEntry, text: ClipboardFeatureStrings) -> ClipboardEntryFacts {
        ClipboardEntryFacts(type: typeDescription(entry, text: text),
                            size: sizeDescription(entry),
                            sourceIcon: entry.source.flatMap(ClipboardHistoryService.sourceIcon))
    }

    private static func typeDescription(_ entry: ClipboardHistoryEntry,
                                        text: ClipboardFeatureStrings) -> String {
        let label = ClipboardKindPresentation.label(entry, text: text)
        switch entry.displayKind {
        case .text, .link:
            // Lines and words only when there is more than one of them: a
            // single line is not a line count, and "1 lines" reads wrong.
            var parts = [label, String(format: text.characterCountFormat, count(entry.characterCount))]
            if entry.lineCount > 1 { parts.append(String(format: text.lineCountFormat, count(entry.lineCount))) }
            if entry.wordCount > 1 { parts.append(String(format: text.wordCountFormat, count(entry.wordCount))) }
            return parts.joined(separator: " · ")
        case .image:
            return "\(label) · PNG · \(entry.imageDimensionsLabel)"
        case .files:
            if entry.filePaths.count == 1, let path = entry.filePaths.first {
                // The filesystem's own answer, so a folder says "Folder" and a
                // file with no extension still gets its Get Info kind.
                let kind = (try? URL(fileURLWithPath: path)
                    .resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
                let dimensions = ClipboardImageStore.imageDimensionsLabel(atPath: path)
                let details = [kind, dimensions].compactMap { $0 }
                return details.isEmpty ? label : details.joined(separator: " · ")
            }
            return label
        }
    }

    private static func sizeDescription(_ entry: ClipboardHistoryEntry) -> String? {
        switch entry.kind {
        case .text:
            return ByteCountFormatter.string(fromByteCount: Int64(entry.utf8ByteCount), countStyle: .file)
        case .image:
            guard let name = entry.imageFile, let url = ClipboardImageStore.imageURL(named: name)
            else { return nil }
            return ClipboardImageStore.fileSizeString(atPath: url.path)
        case .files:
            return ClipboardImageStore.totalFileSizeString(paths: entry.filePaths)
        }
    }

    private static func count(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}
