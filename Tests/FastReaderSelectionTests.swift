// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FastReaderSelectionTests {
    static func run(_ suite: TestSuite) {
        suite.run("selection cap stays a parameter") { cap(suite) }
    }

    private static func cap(_ suite: TestSuite) {
        // Command Bar's own limit is what its callers still get, so raising the
        // cap for Fast Reader cannot quietly change what the bar reads.
        suite.expect(CommandBarSelectionReader.maximumLength == 20_000,
                     "the default selection cap is still twenty thousand characters")

        let long = String(repeating: "a", count: 30_000)
        suite.expect(CommandBarSelectionReader.truncate(long, maximumLength: 20_000).isEmpty,
                     "a selection over the cap is refused at the cap")
        suite.expect(CommandBarSelectionReader.truncate(long, maximumLength: 50_000) == long,
                     "the same selection passes under a larger cap")

        let short = "  a phrase  "
        suite.expect(CommandBarSelectionReader.truncate(short, maximumLength: 20_000) == "a phrase",
                     "surrounding whitespace is trimmed")
        suite.expect(CommandBarSelectionReader.truncate("   ", maximumLength: 20_000).isEmpty,
                     "whitespace alone comes back empty")
    }
}
