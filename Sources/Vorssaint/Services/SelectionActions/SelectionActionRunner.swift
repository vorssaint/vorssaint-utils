// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import AppKit

/// Carries out one `SelectionAction` against a captured selection. Actions
/// that rewrite it either hand the new text to
/// `SyntheticPasteSupport.replaceSelection(with:)` (the pasteboard-swap-and-
/// ⌘V primitive Paste Plain also uses) or, for Cut/Delete, post a synthetic
/// Delete keystroke via `SyntheticPasteSupport.deleteSelection()` — pasting
/// an empty string turned out not to reliably clear a selection in every
/// field, where a real Delete keystroke does. Must be called on the main
/// thread — `.addToScratchpad` touches AppKit UI (`ScratchpadService`)
/// directly, the same assumption the rest of this feature's UI code makes.
enum SelectionActionRunner {
    static func run(_ action: SelectionAction, on snapshot: SelectionSnapshot) {
        switch action {
        case .copy:
            copyToPasteboard(snapshot.text)
        case .cut:
            copyToPasteboard(snapshot.text)
            SyntheticPasteSupport.deleteSelection()
        case .paste:
            guard let clipboard = NSPasteboard.general.string(forType: .string) else { return }
            SyntheticPasteSupport.replaceSelection(with: clipboard)
        case .pastePlain:
            guard let plain = PastePlainService.plainText(from: NSPasteboard.general) else { return }
            SyntheticPasteSupport.replaceSelection(with: plain)
        case .delete:
            SyntheticPasteSupport.deleteSelection()
        case .uppercase:
            SyntheticPasteSupport.replaceSelection(with: snapshot.text.uppercased())
        case .lowercase:
            SyntheticPasteSupport.replaceSelection(with: snapshot.text.lowercased())
        case .capitalize:
            SyntheticPasteSupport.replaceSelection(with: snapshot.text.capitalized)
        case .removeSpaces:
            SyntheticPasteSupport.replaceSelection(with: removingAllSpaces(snapshot.text))
        case .underscore:
            SyntheticPasteSupport.replaceSelection(with: underscored(snapshot.text))
        case .joinLines:
            SyntheticPasteSupport.replaceSelection(with: joinedLines(snapshot.text))
        case .commaList:
            SyntheticPasteSupport.replaceSelection(with: commaList(snapshot.text))
        case .sort:
            SyntheticPasteSupport.replaceSelection(with: TextListSupport.sorted(snapshot.text))
        case .reverse:
            SyntheticPasteSupport.replaceSelection(with: TextListSupport.reversed(snapshot.text))
        case .random:
            SyntheticPasteSupport.replaceSelection(with: TextListSupport.shuffled(snapshot.text))
        case .quotes:
            SyntheticPasteSupport.replaceSelection(with: "\"\(snapshot.text)\"")
        case .brackets:
            SyntheticPasteSupport.replaceSelection(with: "(\(snapshot.text))")
        case .urlEncode:
            let encoded = snapshot.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            SyntheticPasteSupport.replaceSelection(with: encoded ?? snapshot.text)
        case .urlDecode:
            SyntheticPasteSupport.replaceSelection(with: snapshot.text.removingPercentEncoding ?? snapshot.text)
        case .base64Encode:
            SyntheticPasteSupport.replaceSelection(with: Data(snapshot.text.utf8).base64EncodedString())
        case .base64Decode:
            guard let data = Data(base64Encoded: snapshot.text, options: .ignoreUnknownCharacters),
                  let decoded = String(data: data, encoding: .utf8)
            else { return }
            SyntheticPasteSupport.replaceSelection(with: decoded)
        case .calculate:
            guard let value = ArithmeticEvaluator.evaluate(snapshot.text) else { return }
            SyntheticPasteSupport.replaceSelection(with: formatResult(value))
        case .addToScratchpad:
            ScratchpadService.shared.show()
            let existing = ScratchpadService.shared.text
            let separator = existing.isEmpty ? "" : "\n"
            ScratchpadService.shared.text = existing + separator + snapshot.text
        }
    }

    // MARK: - Clipboard

    private static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Text transforms

    /// Every space and tab, leading, trailing, and between words — not a
    /// collapse-repeats normalize, a full strip.
    private static func removingAllSpaces(_ text: String) -> String {
        text.filter { $0 != " " && $0 != "\t" }
    }

    private static func underscored(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private static func joinedLines(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Lines become a comma list when the selection has line breaks; a
    /// single word has nothing to list, so it passes through unchanged.
    private static func commaList(_ text: String) -> String {
        if text.contains(where: \.isNewline) {
            let items = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return items.joined(separator: ", ")
        }
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 1 else { return text }
        return words.joined(separator: ", ")
    }

    // MARK: - Calculate

    private static func formatResult(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        var result = String(format: "%.6f", value)
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }
}
