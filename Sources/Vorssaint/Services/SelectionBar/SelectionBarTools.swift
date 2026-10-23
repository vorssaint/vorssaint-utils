// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The name, symbol and availability of each tool on the selection bar. The
/// bar and its settings both read them here.
enum SelectionBarTools {
    struct Tool {
        let id: String
        let title: String
        let symbol: String
        /// Text drawn in place of the symbol, for a tool no symbol shows well.
        var glyph: String? = nil
    }

    /// The tools that can appear with the features installed now, in bar
    /// order. Settings offers these.
    static func offered(language: AppLanguage) -> [Tool] {
        SelectionBarSupport.actionIDs.filter(isOffered).map { tool($0, language: language) }
    }

    /// False when the feature behind the tool is not installed or not on, so
    /// the bar cannot show the tool.
    static func isOffered(_ id: String) -> Bool {
        switch id {
        case "selection.cleanLink":
            return AppFeature.urlCleaner.isAvailable
        case "selection.shelf":
            return AppFeature.shelf.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
        default:
            return true
        }
    }

    static func tool(_ id: String, language: AppLanguage) -> Tool {
        let bar = FeatureStrings.commandBar(language)
        let strings = FeatureStrings.selectionBar(language)
        switch id {
        case "copy": return Tool(id: id, title: strings.copy, symbol: "doc.on.doc")
        case "selection.cleanLink": return Tool(id: id, title: bar.actionCleanURL, symbol: "link")
        case "selection.upper": return Tool(id: id, title: bar.selectionUpper, symbol: "textformat.size.larger")
        // No symbol shows a lowercase letter on its own.
        case "selection.lower":
            return Tool(id: id, title: bar.selectionLower, symbol: "textformat.size.smaller", glyph: "a")
        case "selection.titleCase": return Tool(id: id, title: bar.selectionTitleCase, symbol: "textformat")
        case "selection.shelf": return Tool(id: id, title: bar.selectionShelf, symbol: "tray.full")
        case "selection.count": return Tool(id: id, title: bar.selectionCount, symbol: "number")
        default: return Tool(id: id, title: id, symbol: "questionmark")
        }
    }
}
