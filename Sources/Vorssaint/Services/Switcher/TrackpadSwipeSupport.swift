// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024-2026 ejbills and DockDoor contributors
// Copyright (C) 2026 Vorssaint
// Detector adapted from DockDoor Utilities/TrackpadSwipeTrigger.swift.

import AppKit

struct SwipeTouch {
    let id: Int
    let position: CGPoint
}

enum TrackpadSwipeEvent: Equatable {
    case open
    case cycleForward
    case cycleBackward
    case release
}

struct TrackpadSwipeDetector {
    static let openDistance: CGFloat = 0.03
    static let firstCycleDistance: CGFloat = 0.15
    static let cycleDistance: CGFloat = 0.04
    static let maxOffAxisDistance: CGFloat = 0.1
    static let axisDominanceRatio: CGFloat = 1.5

    private var startPositions: [Int: CGPoint] = [:]
    private var isSpent = false
    private var hasCycled = false
    private(set) var isSwitching = false

    mutating func handle(_ touches: [SwipeTouch], fingers: Int, horizontal: Bool) -> TrackpadSwipeEvent? {
        if isSwitching {
            if touches.count < fingers {
                isSwitching = false
                isSpent = touches.count > 1
                startPositions.removeAll()
                return .release
            }
            guard let deltas = travel(touches) else { return nil }
            let averageAlong = deltas.map { horizontal ? $0.x : $0.y }.reduce(0, +) / CGFloat(deltas.count)
            let threshold = hasCycled ? Self.cycleDistance : Self.firstCycleDistance
            guard abs(averageAlong) >= threshold else { return nil }
            hasCycled = true
            rebase(touches)
            return averageAlong > 0 ? .cycleForward : .cycleBackward
        }

        if touches.count <= 1 {
            isSpent = false
            startPositions.removeAll()
            return nil
        }
        if isSpent {
            return nil
        }
        if touches.count > fingers {
            isSpent = true
            return nil
        }
        guard touches.count == fingers else {
            startPositions.removeAll()
            return nil
        }
        guard let deltas = travel(touches) else { return nil }

        let alongAxis = deltas.map { horizontal ? $0.x : $0.y }
        let acrossAxis = deltas.map { horizontal ? abs($0.y) : abs($0.x) }
        if acrossAxis.contains(where: { $0 >= Self.maxOffAxisDistance }) {
            isSpent = true
            return nil
        }
        let allPositive = alongAxis.allSatisfy { $0 >= Self.openDistance }
        let allNegative = alongAxis.allSatisfy { $0 <= -Self.openDistance }
        guard allPositive || allNegative else { return nil }
        guard zip(alongAxis.map(abs), acrossAxis).allSatisfy({ $0 > $1 * Self.axisDominanceRatio }) else { return nil }

        isSwitching = true
        hasCycled = false
        rebase(touches)
        return .open
    }

    private mutating func travel(_ touches: [SwipeTouch]) -> [CGPoint]? {
        let deltas = touches.compactMap { touch -> CGPoint? in
            guard let start = startPositions[touch.id] else { return nil }
            return CGPoint(x: touch.position.x - start.x, y: touch.position.y - start.y)
        }
        guard !deltas.isEmpty, deltas.count == touches.count else {
            rebase(touches)
            return nil
        }
        return deltas
    }

    private mutating func rebase(_ touches: [SwipeTouch]) {
        startPositions = Dictionary(touches.map { ($0.id, $0.position) }, uniquingKeysWith: { first, _ in first })
    }
}
