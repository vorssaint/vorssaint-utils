// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PreciseVolumeRollerDirection: Equatable {
    case up, down
}

struct PreciseVolumeRollerGate {
    var minimumSpacing: TimeInterval = 0.03
    var reversalWindow: TimeInterval = 0.30
    var reversalConfirmations = 2

    private var lastAcceptedAt: TimeInterval?
    private var lastDirection: PreciseVolumeRollerDirection?
    private var reversalDirection: PreciseVolumeRollerDirection?
    private var reversalCount = 0

    mutating func reset() {
        lastAcceptedAt = nil
        lastDirection = nil
        reversalDirection = nil
        reversalCount = 0
    }

    mutating func accepts(_ direction: PreciseVolumeRollerDirection,
                          at time: TimeInterval) -> Bool {
        if let lastAcceptedAt, time - lastAcceptedAt <= minimumSpacing {
            return false
        }

        if let lastDirection, direction != lastDirection,
           let lastAcceptedAt, time - lastAcceptedAt < reversalWindow {
            if reversalDirection == direction {
                reversalCount += 1
            } else {
                reversalDirection = direction
                reversalCount = 1
            }
            guard reversalCount > reversalConfirmations else { return false }
        } else {
            reversalDirection = nil
            reversalCount = 0
        }

        lastDirection = direction
        lastAcceptedAt = time
        reversalDirection = nil
        reversalCount = 0
        return true
    }
}

enum PreciseVolumeMediaKey: Int32 {
    case volumeUp = 0
    case volumeDown = 1
    case mute = 7
    case play = 16

    var rollerDirection: PreciseVolumeRollerDirection? {
        switch self {
        case .volumeUp: return .up
        case .volumeDown: return .down
        case .mute, .play: return nil
        }
    }
}
