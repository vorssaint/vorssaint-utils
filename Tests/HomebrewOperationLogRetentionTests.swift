// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// The completion timer used to wipe the technical log after 6 – 20 seconds
// (issue #566) while people were still reading it. It now only dismisses a
// succeeded or cancelled card; failure and terminal fallback cards stay.
enum HomebrewOperationLogRetentionTests {
    static func run(_ suite: TestSuite) {
        let expectations: [(HomebrewOperationResult, TimeInterval?, String)] = [
            (.succeeded, 8, "a succeeded card still hides itself after 8 seconds"),
            (.cancelled, 6, "a cancelled card still hides itself after 6 seconds"),
            (.running, nil, "a running operation has no completion timer"),
            (.failed, nil, "a failed card keeps its reason instead of a timed wipe"),
            (.needsTerminal, nil, "a terminal fallback card keeps its command instead of a timed wipe"),
        ]
        for (result, delay, message) in expectations {
            suite.expect(HomebrewCompletedOperationCleanup.cardDismissalDelay(result: result) == delay,
                         "#566: \(message), got \(String(describing: HomebrewCompletedOperationCleanup.cardDismissalDelay(result: result)))")
        }
    }
}
