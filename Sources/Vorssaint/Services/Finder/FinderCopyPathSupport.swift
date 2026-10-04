// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderCopyPathSupport {
    /// Finder returns selections in visual order. Preserve that order and use
    /// one POSIX path per line so a single selection pastes naturally into a
    /// terminal while a multiple selection remains unambiguous and editable.
    static func text(for urls: [URL]) -> String? {
        guard !urls.isEmpty else { return nil }
        return urls.map(\.path).joined(separator: "\n")
    }
}
