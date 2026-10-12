// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// Recognizes deliberate alternating travel, not tiny jitters or a normal drag.
struct PreviewShakeDetector {
    private var baseline: CGPoint?
    private var direction: CGFloat = 0
    private var reversals = 0
    private var firstReversal: Double = 0
    mutating func sample(_ point: CGPoint, at time: Double) -> Bool {
        guard point.x.isFinite, point.y.isFinite, time.isFinite else { self = .init(); return false }
        guard let baseline else { self.baseline = point; return false }
        let dx = point.x - baseline.x, dy = point.y - baseline.y
        let along = abs(dx) >= abs(dy) ? dx : dy
        guard abs(along) >= 25 else { return false }
        self.baseline = point
        let next: CGFloat = along > 0 ? 1 : -1
        if direction != 0, next != direction {
            if reversals == 0 || time - firstReversal > 0.8 { reversals = 0; firstReversal = time }
            reversals += 1
        }
        direction = next
        return reversals >= 3 && time - firstReversal <= 0.8
    }
}
