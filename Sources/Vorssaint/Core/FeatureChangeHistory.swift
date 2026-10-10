// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Feature actions retain only the preferences they changed. Undoing an older
/// action must not overwrite unrelated settings edited since that action.
struct FeatureChangeHistory {
    struct Change {
        let keys: Set<String>
        let values: [String: Bool]
    }

    private struct Entry {
        let keys: Set<String>
        let before: [String: Bool]
        let after: [String: Bool]
    }

    private var past: [Entry] = []
    private var future: [Entry] = []
    private let limit = 50

    var undoCount: Int { past.count }
    var redoCount: Int { future.count }

    mutating func record(before: [String: Bool], after: [String: Bool]) {
        let keys = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
        guard !keys.isEmpty else { return }
        past.append(Entry(keys: keys, before: before.filter { keys.contains($0.key) },
                          after: after.filter { keys.contains($0.key) }))
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    mutating func undo() -> Change? {
        guard let entry = past.popLast() else { return nil }
        future.append(entry)
        return Change(keys: entry.keys, values: entry.before)
    }

    mutating func redo() -> Change? {
        guard let entry = future.popLast() else { return nil }
        past.append(entry)
        return Change(keys: entry.keys, values: entry.after)
    }
}
