// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Which link previews fetch now and which wait: at most `capacity` at a
/// time, the rest in the order they were asked for. A card asks once, when it
/// comes on screen, so a link turned away instead would never be fetched.
struct ClipboardLinkPreviewQueue {
    let capacity: Int
    private(set) var running: Set<URL> = []
    private(set) var waiting: [URL] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    func contains(_ url: URL) -> Bool {
        running.contains(url) || waiting.contains(url)
    }

    /// True when the link may start now; otherwise it waits its turn, once.
    mutating func admit(_ url: URL) -> Bool {
        guard !contains(url) else { return false }
        guard running.count < capacity else {
            waiting.append(url)
            return false
        }
        running.insert(url)
        return true
    }

    /// Frees the link's place and returns the waiting links that start now.
    mutating func finish(_ url: URL) -> [URL] {
        running.remove(url)
        var started: [URL] = []
        while running.count < capacity, !waiting.isEmpty {
            let next = waiting.removeFirst()
            running.insert(next)
            started.append(next)
        }
        return started
    }

    /// Forgets the links still waiting; the running ones finish on their own.
    mutating func dropWaiting() {
        waiting = []
    }
}
