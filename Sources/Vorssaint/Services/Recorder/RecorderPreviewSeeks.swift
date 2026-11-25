// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// An in-flight seek gets to show its frame. Any newer samples collapse to
/// the latest request, including an exact seek when the user releases a drag.
struct RecorderPreviewSeeks {
    struct Request: Equatable {
        let time: Double
        let exact: Bool
    }

    private var pending: Request?
    private var active: Request?
    private var sequence = 0

    var isBusy: Bool { active != nil || pending != nil }

    mutating func enqueue(_ request: Request) {
        pending = request == active ? nil : request
    }

    mutating func takeNext() -> (id: Int, request: Request)? {
        guard active == nil, let pending else { return nil }
        sequence += 1
        active = pending
        self.pending = nil
        return (sequence, pending)
    }

    mutating func finish(_ id: Int) -> Bool {
        guard active != nil, id == sequence else { return false }
        active = nil
        return true
    }

    mutating func reset() {
        pending = nil
        active = nil
    }
}
