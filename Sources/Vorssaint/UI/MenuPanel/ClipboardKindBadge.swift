// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One look per kind of clipboard entry, shared by the rows, the ⌘K card and
/// the preview so an item is recognizable as the same thing everywhere.
enum ClipboardKindPresentation {
    static func symbolName(_ kind: ClipboardHistoryDisplayKind) -> String {
        switch kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        }
    }

    static func tint(_ kind: ClipboardHistoryDisplayKind) -> Color {
        switch kind {
        case .text: return .secondary
        case .link: return .blue
        case .image: return .purple
        case .files: return .orange
        }
    }

    static func label(_ entry: ClipboardHistoryEntry, text: ClipboardFeatureStrings) -> String {
        switch entry.displayKind {
        case .text: return text.textEntryLabel
        case .link: return text.linkEntryLabel
        case .image: return text.imageEntryLabel
        case .files:
            // The row already prints the file's name; this slot says what it is.
            return entry.filePaths.count == 1
                ? text.fileEntryLabel
                : String(format: text.fileCountFormat, entry.filePaths.count)
        }
    }
}

/// A small tinted square with the kind's glyph.
struct ClipboardKindGlyph: View {
    let kind: ClipboardHistoryDisplayKind
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: ClipboardKindPresentation.symbolName(kind))
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(ClipboardKindPresentation.tint(kind))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(ClipboardKindPresentation.tint(kind).opacity(0.13))
            )
    }
}

/// The kind as a capsule of text, for places with no room for a glyph well.
struct ClipboardKindCapsule: View {
    let entry: ClipboardHistoryEntry
    let text: ClipboardFeatureStrings

    var body: some View {
        let kind = entry.displayKind
        HStack(spacing: 3) {
            Image(systemName: ClipboardKindPresentation.symbolName(kind))
                .font(.system(size: 8, weight: .bold))
            Text(ClipboardKindPresentation.label(entry, text: text))
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(ClipboardKindPresentation.tint(kind))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(ClipboardKindPresentation.tint(kind).opacity(0.12)))
    }
}
