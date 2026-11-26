// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A right-click that lands while the shelf is still resolving files must not
/// vanish: it shares the running resolution and produces exactly one menu.
enum ShelfContextMenuRequestTests {
    static func run(_ suite: TestSuite) {
        var requests = ShelfContextMenuRequests<String>()
        suite.expect(requests.begin("first"), "the first click starts the resolution")
        suite.expect(requests.finish(windowIsOpen: true) == "first",
               "a click with no rival shows its own menu once")
        suite.expect(requests.finish(windowIsOpen: true) == nil,
               "a finished resolution cannot show a second menu")

        requests = ShelfContextMenuRequests<String>()
        suite.expect(requests.begin("first"), "the first click starts the resolution")
        suite.expect(!requests.begin("second"),
               "a click during the resolution waits instead of being swallowed")
        suite.expect(!requests.begin("third"), "later clicks wait on the same resolution")
        suite.expect(requests.finish(windowIsOpen: true) == "third",
               "the waiters produce exactly one menu, for the latest click")
        suite.expect(requests.finish(windowIsOpen: true) == nil,
               "the remembered clicks never produce a second menu")

        requests = ShelfContextMenuRequests<String>()
        _ = requests.begin("first")
        _ = requests.begin("second")
        suite.expect(requests.finish(windowIsOpen: false) == nil,
               "a window closed while resolving shows no menu")
        suite.expect(requests.begin("after"), "the queue is clean for the next click")
        suite.expect(requests.finish(windowIsOpen: true) == "after",
               "a later click still gets its menu after a closed window")
    }
}
