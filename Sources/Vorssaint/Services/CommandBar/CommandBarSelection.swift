// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// What the person had selected in the app in front when the bar opened.
///
/// This is what turns the bar from a place you go to into something that acts
/// on what you are already doing: select a link and the bar offers to clean
/// it, select a paragraph and it offers to change its case, count it or keep
/// it. Nothing is read while the bar is closed, and the text never leaves the
/// Mac or reaches disk.
enum CommandBarSelectionReader {
    /// A selection longer than this is a document, not a phrase; offering to
    /// retype it would be slower than doing it by hand.
    static let maximumLength = 20_000

    /// The selected text of whatever is in front, read through Accessibility:
    /// trimmed, and exactly as the app holds it. Blocking, so callers run it
    /// off the main thread. Empty when nothing is selected, when the app does
    /// not tell Accessibility what is selected, or when the front app is us
    /// (the field's own text is not a selection). `typesOver` is false for a
    /// web page read through a text marker range: typed letters reach the
    /// page, not the selection.
    static func readSelection() -> (text: String, exact: String, typesOver: Bool) {
        guard AXIsProcessTrusted() else { return ("", "", false) }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier,
              let selection = SelectedTextReader.read(processID: front.processIdentifier)
        else { return ("", "", false) }
        let trimmed = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= maximumLength
            ? (trimmed, selection.text, !selection.fromTextMarkers)
            : ("", "", false)
    }
}
