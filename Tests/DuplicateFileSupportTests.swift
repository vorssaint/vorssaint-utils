// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The duplicate finder's pure rules: one copy always stays, the oldest copy is
/// the default keeper, and a copy edited after the scan is never removed.
enum DuplicateFileSupportTests {
    static func run(_ suite: TestSuite) {
        suite.expect(DuplicateFileSupport.mayTick(tickedCount: 0, groupCount: 2)
                     && DuplicateFileSupport.mayTick(tickedCount: 1, groupCount: 3),
                     "a copy may be ticked while another stays unticked")
        suite.expect(!DuplicateFileSupport.mayTick(tickedCount: 1, groupCount: 2)
                     && !DuplicateFileSupport.mayTick(tickedCount: 2, groupCount: 3)
                     && !DuplicateFileSupport.mayTick(tickedCount: 0, groupCount: 1),
                     "the last remaining copy can never be ticked")

        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        suite.expect(DuplicateFileSupport.defaultKeepIndex(modified: [late, early, late]) == 1,
                     "the oldest copy is kept by default")
        suite.expect(DuplicateFileSupport.defaultKeepIndex(modified: [nil, late, early]) == 2
                     && DuplicateFileSupport.defaultKeepIndex(modified: [nil, nil]) == 0
                     && DuplicateFileSupport.defaultKeepIndex(modified: [early, early]) == 0,
                     "a copy with no date loses to a dated one, and ties keep the first")

        suite.expect(DuplicateFileSupport.unchanged(scannedSize: 10, scannedModified: early,
                                                    currentSize: 10, currentModified: early),
                     "an untouched copy still matches the scan")
        suite.expect(!DuplicateFileSupport.unchanged(scannedSize: 10, scannedModified: early,
                                                     currentSize: 11, currentModified: early)
                     && !DuplicateFileSupport.unchanged(scannedSize: 10, scannedModified: early,
                                                        currentSize: 10, currentModified: late)
                     && !DuplicateFileSupport.unchanged(scannedSize: 10, scannedModified: early,
                                                        currentSize: nil, currentModified: nil),
                     "a copy that changed size or date, or vanished, no longer matches")

        struct G { let size: Int64; let copies: Int }
        let ranked = DuplicateFileSupport.ranked([G(size: 10, copies: 2), G(size: 5, copies: 10), G(size: 100, copies: 1)],
                                                 size: { $0.size }, copies: { $0.copies })
        suite.expect(ranked.map(\.size) == [5, 10, 100],
                     "groups are ordered by space that removing the extras would free")
    }
}
