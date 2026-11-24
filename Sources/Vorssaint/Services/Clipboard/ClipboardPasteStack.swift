// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClipboardPasteStack {
    struct Request: Equatable {
        let entryID: UUID
        private let token = UUID()
    }

    private var entryIDs: [UUID] = []
    private var pending: Request?

    var count: Int { entryIDs.count }

    mutating func append(_ ids: [UUID]) {
        var queued = Set(entryIDs)
        entryIDs.append(contentsOf: ids.filter { queued.insert($0).inserted })
    }

    mutating func prune(keeping validIDs: Set<UUID>) {
        entryIDs.removeAll { !validIDs.contains($0) }
        if let pending, !validIDs.contains(pending.entryID) {
            self.pending = nil
        }
    }

    mutating func clear() {
        entryIDs.removeAll()
        pending = nil
    }

    mutating func beginPaste() -> Request? {
        guard pending == nil, let id = entryIDs.first else { return nil }
        let request = Request(entryID: id)
        pending = request
        return request
    }

    mutating func finishPaste(_ request: Request) {
        if pending == request { pending = nil }
    }

    // The pasteboard lane holds the stack lock across the post. Clearing or
    // pruning the stack can therefore cancel a request before it sends keys.
    mutating func post(_ request: Request, shortcut: () -> Bool) -> Bool {
        guard pending == request, shortcut() else { return false }
        entryIDs.removeFirst()
        pending = nil
        return true
    }
}
