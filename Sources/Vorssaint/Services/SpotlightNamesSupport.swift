// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Which of the names macOS keeps for an app are worth searching by. Pure, so
/// the rule is pinned by tests instead of being rediscovered on one Mac.
enum SpotlightNamesSupport {
    /// The aliases worth indexing, out of everything Spotlight lists.
    ///
    /// Spotlight mixes junk in with the real ones, and indexing it would make
    /// short queries match the whole catalog: every bundle lists its own file
    /// name, several system apps ship untranslated `ALTERNATE_NAME_1`
    /// placeholders, and some simply repeat the name already under the icon.
    static func usableAlternateNames(_ raw: [String],
                                     displayName: String,
                                     fileName: String) -> [String] {
        var seen = Set<String>()
        // Neither the name nor the file name earns a row anything: they are
        // already what the row is called.
        for known in [displayName, fileName, (fileName as NSString).deletingPathExtension] {
            seen.insert(folded(known))
        }
        var names: [String] = []
        for name in raw {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !isPlaceholder(trimmed),
                  // A file name teaches nothing the name above the icon does
                  // not already say, and every bundle lists its own.
                  !trimmed.lowercased().hasSuffix(".app"),
                  seen.insert(folded(trimmed)).inserted
            else { continue }
            names.append(trimmed)
        }
        return names
    }

    /// An alias Apple left untranslated: the key itself, shipped as the value.
    private static func isPlaceholder(_ value: String) -> Bool {
        let upper = value.uppercased()
        return upper.hasPrefix("ALTERNATE_NAME") || upper.hasPrefix("CFBUNDLE")
    }

    private static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: nil)
    }
}
