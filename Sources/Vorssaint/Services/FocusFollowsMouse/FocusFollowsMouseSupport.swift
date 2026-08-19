// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum FocusFollowsMouseSupport {
    static let defaultDelayMilliseconds = 250
    static let delayRange = 100...1_000

    static func sanitizedDelay(_ milliseconds: Int) -> Int {
        min(max(milliseconds, delayRange.lowerBound), delayRange.upperBound)
    }
}

struct FocusFollowsMouseEvaluation: Equatable {
    let point: CGPoint
    let generation: UInt64
}

struct FocusFollowsMouseState: Equatable {
    private(set) var point: CGPoint?
    private(set) var movedAt: TimeInterval = 0
    private(set) var generation: UInt64 = 0
    private var evaluatedGeneration: UInt64?

    mutating func recordMovement(to point: CGPoint, at time: TimeInterval) {
        self.point = point
        movedAt = time
        generation &+= 1
        evaluatedGeneration = nil
    }

    mutating func reset() {
        point = nil
        generation &+= 1
        evaluatedGeneration = nil
    }

    mutating func nextEvaluation(at time: TimeInterval,
                                 delayMilliseconds: Int) -> FocusFollowsMouseEvaluation? {
        guard let point,
              evaluatedGeneration != generation,
              time - movedAt >= Double(FocusFollowsMouseSupport.sanitizedDelay(delayMilliseconds)) / 1_000
        else { return nil }
        evaluatedGeneration = generation
        return FocusFollowsMouseEvaluation(point: point, generation: generation)
    }

    func isCurrent(_ evaluation: FocusFollowsMouseEvaluation) -> Bool {
        evaluation.generation == generation
    }
}
