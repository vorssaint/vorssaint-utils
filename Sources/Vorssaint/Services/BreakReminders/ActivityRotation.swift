// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// In-order rotation per kind. The index advances only when a prompt ends
/// as taken (done, skip, timeout after being seen, absence while seen).
struct ActivityRotation: Equatable {
    var indices: [BreakKind: Int] = [:]

    func current(_ kind: BreakKind, in list: [BreakActivity]) -> BreakActivity? {
        guard !list.isEmpty else { return nil }
        return list[min(max(indices[kind] ?? 0, 0), list.count - 1)]
    }

    mutating func advance(_ kind: BreakKind, count: Int) {
        guard count > 0 else { indices[kind] = 0; return }
        let clamped = min(max(indices[kind] ?? 0, 0), count - 1)
        indices[kind] = (clamped + 1) % count
    }
}
