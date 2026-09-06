// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure selection rules for the optional Command Bar Latin-layout switch.
/// Callers inject source ids and flags so the harness can pin behavior without
/// talking to Text Input Services.
enum CommandBarASCIILayoutSupport {
    struct Source: Equatable {
        let id: String
        let isASCIICapable: Bool
        let isSelectCapable: Bool
        /// Keyboard layouts only — input methods and palettes stay out even
        /// when they happen to be ASCII-capable.
        let isKeyboardLayout: Bool
    }

    static func isEligible(_ source: Source) -> Bool {
        source.isKeyboardLayout && source.isSelectCapable && source.isASCIICapable
    }

    static func firstEligibleID(in sources: [Source]) -> String? {
        sources.first(where: isEligible)?.id
    }

    /// The layout to select when the bar opens, or `nil` when nothing should
    /// change. Without a known current id there is nothing safe to restore, so
    /// the bar leaves the input source alone.
    static func openSelection(currentID: String?, sources: [Source]) -> String? {
        guard let currentID else { return nil }
        guard let target = firstEligibleID(in: sources), target != currentID else { return nil }
        return target
    }

    /// The layout to select when the bar closes, or `nil` when there is nothing
    /// to put back.
    static func closeSelection(previousID: String?, currentID: String?) -> String? {
        guard let previousID, previousID != currentID else { return nil }
        return previousID
    }
}
