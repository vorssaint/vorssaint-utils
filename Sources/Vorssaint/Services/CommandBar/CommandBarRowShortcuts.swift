// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The combinations the person tied to single rows of the bar.
///
/// An alias makes something faster to find; a shortcut makes it instant, with
/// no bar at all. Both matter, and which one a command deserves is a decision
/// only its owner can make: the thing you run four times a day earns a key,
/// the thing you run weekly does not. Nothing is registered unless the person
/// asked for it, so an untouched install pays nothing.
enum CommandBarRowShortcuts {
    /// Few enough that the keyboard is still the person's, and that the list
    /// in Settings stays readable.
    static let limit = 20

    static func decode(_ raw: String?) -> [String: GlobalShortcut] {
        guard let raw, let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return stored.compactMapValues(GlobalShortcut.init(storageValue:))
    }

    static func encode(_ shortcuts: [String: GlobalShortcut]) -> String? {
        let stored = shortcuts.mapValues(\.storageValue)
        guard let data = try? JSONEncoder().encode(stored) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The map after binding (or clearing, with nil) one row. A combination
    /// already tied to another row moves, because a person pressing keys means
    /// the last thing they said: two rows answering to one combination would
    /// leave one of them dead with no way to tell which.
    static func setting(_ shortcut: GlobalShortcut?,
                        for key: String,
                        in shortcuts: [String: GlobalShortcut]) -> [String: GlobalShortcut] {
        var next = shortcuts
        guard let shortcut else {
            next.removeValue(forKey: key)
            return next
        }
        for (otherKey, other) in next where other == shortcut && otherKey != key {
            next.removeValue(forKey: otherKey)
        }
        guard next[key] != nil || next.count < limit else { return next }
        next[key] = shortcut
        return next
    }

    /// Whether one more row can still be bound. Asked before the keys are
    /// taken, so a full list can say so instead of swallowing the combination.
    static func hasRoom(for key: String, in shortcuts: [String: GlobalShortcut]) -> Bool {
        shortcuts[key] != nil || shortcuts.count < limit
    }

    /// The row a combination belongs to, so the press can be routed without
    /// walking the whole catalog twice.
    static func key(for shortcut: GlobalShortcut, in shortcuts: [String: GlobalShortcut]) -> String? {
        shortcuts.first { $0.value == shortcut }?.key
    }

    /// Whether a combination is worth registering at all. A bare letter would
    /// take that letter away from every app on the Mac.
    static func isUsable(_ shortcut: GlobalShortcut) -> Bool {
        !shortcut.modifiers.isEmpty
    }
}
