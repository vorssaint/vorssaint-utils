// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The list a slice opens beside the wheel. Every part has the fixed height
/// `RadialMenuPeekLayout` gives it, because the service finds the row under
/// the pointer from that layout and never asks this view. The rows scroll by
/// whole rows for the same reason, and the entry being pointed at is shown
/// whole underneath, so what is about to be pasted can be read first.
struct RadialMenuPeekView: View {
    @ObservedObject var controller: RadialMenuPeekController
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var clipboardText: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }
    private var accent: Color { controller.color.color(for: colorScheme) }

    private var visibleIndices: Range<Int> {
        let count = controller.entries.count
        let first = min(controller.firstVisibleRow, count)
        return first..<min(first + RadialMenuPeekLayout.visibleRows, count)
    }

    var body: some View {
        Group {
            if controller.isFolder {
                RadialFolderPeekContent(controller: controller, accent: accent, text: text)
                    .frame(width: RadialMenuPeekLayout.width,
                           height: RadialMenuPeekLayout.height(rowCount: RadialMenuPeekLayout.visibleRows,
                                                               basket: true),
                           alignment: .top)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    rows
                    preview
                }
                .padding(RadialMenuPeekLayout.padding)
                .frame(width: RadialMenuPeekLayout.width,
                       height: RadialMenuPeekLayout.height(rowCount: controller.entries.count),
                       alignment: .top)
            }
        }
        .background(HUDBackdrop(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.6)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: AppFeature.clipboardHistory.symbolName)
                .font(.system(size: 11, weight: .semibold))
            Text(AppFeature.clipboardHistory.hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language)))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(controller.entries.count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: RadialMenuPeekLayout.headerHeight,
               maxHeight: RadialMenuPeekLayout.headerHeight, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(visibleIndices, id: \.self) { index in
                row(controller.entries[index], number: index + 1,
                    highlighted: controller.highlightedRow == index)
                    .frame(height: RadialMenuPeekLayout.rowHeight)
            }
        }
        .frame(height: RadialMenuPeekLayout.rowHeight * CGFloat(visibleIndices.count), alignment: .top)
        .overlay(alignment: .trailing) { scrollIndicator }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: controller.firstVisibleRow)
    }

    /// Only when the list is longer than its window: where the visible rows
    /// sit in the whole list, the way a system scroller shows it.
    @ViewBuilder
    private var scrollIndicator: some View {
        let count = controller.entries.count
        let visible = RadialMenuPeekLayout.visibleRows
        if count > visible {
            let track = RadialMenuPeekLayout.rowHeight * CGFloat(visible) - 8
            let thumb = max(track * CGFloat(visible) / CGFloat(count), 18)
            let travel = track - thumb
            let offset = travel * CGFloat(controller.firstVisibleRow) / CGFloat(count - visible)
            Capsule()
                .fill(Color.primary.opacity(0.28))
                .frame(width: 3, height: thumb)
                .offset(y: offset)
                .frame(height: track, alignment: .top)
                .padding(.trailing, 1)
                .accessibilityHidden(true)
        }
    }

    private func row(_ entry: ClipboardHistoryEntry, number: Int, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
                .frame(width: 16, alignment: .trailing)
            leadingIcon(entry)
                .frame(width: 28, height: 28)
            Text(label(for: entry))
                .font(.system(size: 12))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            }
        }
        .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(highlighted ? accent : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let entry = controller.highlightedEntry {
                previewBody(entry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Text(Self.relativeDate(entry.copiedAt, language: l10n.language))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(text.peekClipboardHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .light ? 0.05 : 0.07))
        )
        .padding(.top, 6)
        .frame(height: RadialMenuPeekLayout.previewHeight)
    }

    @ViewBuilder
    private func previewBody(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            Text(entry.cardPreview)
                .font(.system(size: 11.5))
                .lineLimit(5)
                .truncationMode(.tail)
        case .image:
            if let name = entry.imageFile {
                ClipboardThumbnailImage(source: .stored(name: name), aspectRatio: entry.imageAspectRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(label(for: entry)).font(.system(size: 11.5))
            }
        case .files:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(entry.filePaths.prefix(4).enumerated()), id: \.offset) { _, path in
                    HStack(spacing: 6) {
                        Image(nsImage: ClipboardImageStore.fileIcon(atPath: path))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 14, height: 14)
                        Text((path as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if entry.filePaths.count > 4 {
                    Text("+\(entry.filePaths.count - 4)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func label(for entry: ClipboardHistoryEntry) -> String {
        entry.kind == .image ? "\(clipboardText.imageEntryLabel) · \(entry.imageDimensionsLabel)" : entry.preview
    }

    /// "5 minutes ago" in the app's own language, which can differ from the
    /// system's.
    static func relativeDate(_ date: Date, language: AppLanguage) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.unitsStyle = .full
        // Named style so a copy just made reads "now" instead of the literal
        // "in 0 seconds".
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private func leadingIcon(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .image:
            if let name = entry.imageFile {
                ClipboardThumbnailImage(source: .stored(name: name),
                                        aspectRatio: entry.imageAspectRatio,
                                        contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                symbol("photo")
            }
        case .files:
            if let path = entry.filePaths.first {
                Image(nsImage: ClipboardImageStore.fileIcon(atPath: path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
            } else {
                symbol("doc")
            }
        case .text:
            symbol("text.alignleft")
        }
    }

    private func symbol(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .overlay(Image(systemName: name).font(.system(size: 12, weight: .medium)))
    }
}

/// A folder slice's list: where it is, what is inside, the files picked so
/// far and the one the pointer is on. Laid out to the same fixed heights as
/// the clipboard list, plus the bar of picked files, whose clear button and
/// the header's back arrow sit where `RadialMenuPeekLayout` says they do.
private struct RadialFolderPeekContent: View {
    @ObservedObject var controller: RadialMenuPeekController
    let accent: Color
    let text: RadialMenuFeatureStrings
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleIndices: Range<Int> {
        let count = controller.folderEntries.count
        let first = min(controller.firstVisibleRow, count)
        return first..<min(first + RadialMenuPeekLayout.visibleRows, count)
    }

    private var rowsHeight: CGFloat {
        RadialMenuPeekLayout.rowHeight * CGFloat(RadialMenuPeekLayout.visibleRows)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rows
            basket
            preview
        }
        .padding(RadialMenuPeekLayout.padding)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Group {
                if controller.folder?.canGoUp == true {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityLabel(text.backButton)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(width: RadialMenuPeekLayout.backButtonWidth)
            Text((controller.folder?.pathNames ?? []).joined(separator: " › "))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 6)
            Text("\(controller.folderEntries.count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .padding(.trailing, 8)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: RadialMenuPeekLayout.headerHeight,
               maxHeight: RadialMenuPeekLayout.headerHeight, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var rows: some View {
        if controller.folderEntries.isEmpty {
            Text(controller.folderUnreadable ? text.peekFolderUnreadable : text.peekFolderEmpty)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: rowsHeight, maxHeight: rowsHeight)
        } else {
            VStack(spacing: 0) {
                ForEach(visibleIndices, id: \.self) { index in
                    let entry = controller.folderEntries[index]
                    row(entry, number: index + 1,
                        highlighted: controller.highlightedRow == index,
                        picked: controller.folder?.isPicked(entry.url) == true)
                        .frame(height: RadialMenuPeekLayout.rowHeight)
                }
            }
            .frame(maxWidth: .infinity, minHeight: rowsHeight, maxHeight: rowsHeight, alignment: .top)
            .overlay(alignment: .trailing) { scrollIndicator }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: controller.firstVisibleRow)
        }
    }

    @ViewBuilder
    private var scrollIndicator: some View {
        let count = controller.folderEntries.count
        let visible = RadialMenuPeekLayout.visibleRows
        if count > visible {
            let track = rowsHeight - 8
            let thumb = max(track * CGFloat(visible) / CGFloat(count), 18)
            let offset = (track - thumb) * CGFloat(controller.firstVisibleRow) / CGFloat(count - visible)
            Capsule()
                .fill(Color.primary.opacity(0.28))
                .frame(width: 3, height: thumb)
                .offset(y: offset)
                .frame(height: track, alignment: .top)
                .padding(.trailing, 1)
                .accessibilityHidden(true)
        }
    }

    private func row(_ entry: RadialFolderEntry, number: Int, highlighted: Bool, picked: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
                .frame(width: 22, alignment: .trailing)
            Image(nsImage: RadialFolderIcons.icon(for: entry))
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail(for: entry))
                    .font(.system(size: 9.5))
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if entry.isFolder {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
            } else {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white)
                                     : (picked ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary)))
            }
        }
        .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(highlighted ? accent : (picked ? accent.opacity(0.16) : Color.clear))
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(highlighted || picked ? .isSelected : [])
    }

    private func detail(for entry: RadialFolderEntry) -> String {
        let date = RadialMenuPeekView.relativeDate(entry.date, language: l10n.language)
        guard let size = entry.size else { return date }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) · \(date)"
    }

    private var basket: some View {
        let picked = controller.folder?.basket ?? []
        return HStack(spacing: 8) {
            if picked.isEmpty {
                Text(text.peekBasketEmpty)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 10)
                Spacer(minLength: 0)
            } else {
                ZStack(alignment: .leading) {
                    ForEach(Array(picked.prefix(3).enumerated()), id: \.offset) { offset, url in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                            .offset(x: CGFloat(offset) * 7)
                    }
                }
                .frame(width: 22 + CGFloat(min(picked.count, 3) - 1) * 7, alignment: .leading)
                .padding(.leading, 8)
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: text.peekBasketFormat, picked.count))
                        .font(.system(size: 11, weight: .semibold))
                    Text(text.peekBasketHint)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: RadialMenuPeekLayout.clearButtonWidth,
                           height: RadialMenuPeekLayout.basketHeight)
                    .help(text.peekClearSelection)
                    .accessibilityLabel(text.peekClearSelection)
            }
        }
        .frame(maxWidth: .infinity, minHeight: RadialMenuPeekLayout.basketHeight,
               maxHeight: RadialMenuPeekLayout.basketHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(picked.isEmpty ? Color.primary.opacity(0.12) : accent.opacity(0.6),
                              style: StrokeStyle(lineWidth: 1, dash: picked.isEmpty ? [3, 3] : []))
        )
    }

    private var preview: some View {
        Group {
            if let entry = controller.highlightedFolderEntry {
                previewBody(entry)
            } else {
                Text(text.peekFolderHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .light ? 0.05 : 0.07))
        )
        .padding(.top, 6)
        .frame(height: RadialMenuPeekLayout.previewHeight)
    }

    @ViewBuilder
    private func previewBody(_ entry: RadialFolderEntry) -> some View {
        if !entry.isFolder, entry.contentType?.conforms(to: .image) == true {
            ClipboardThumbnailImage(source: .file(path: entry.url.path),
                                    failureText: entry.name)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: RadialFolderIcons.icon(for: entry))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if let kind = entry.typeDescription {
                        Text(kind)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(detail(for: entry))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Icons by file type, never by path: the list draws them while the pointer
/// moves over it, and a type's icon needs nothing from the disk, so a slow
/// or dead volume can never stall a row.
enum RadialFolderIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for entry: RadialFolderEntry) -> NSImage {
        let type = entry.isFolder ? UTType.folder : (entry.contentType ?? .data)
        if let cached = cache[type.identifier] { return cached }
        let icon = NSWorkspace.shared.icon(for: type)
        cache[type.identifier] = icon
        return icon
    }
}
