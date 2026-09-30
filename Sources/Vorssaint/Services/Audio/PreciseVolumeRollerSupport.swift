// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

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

struct PreciseVolumeKeyOwnership {
    private var leftToSystem = [Int32: Bool]()

    mutating func leavesToSystem(keyCode: Int32, isDown: Bool, isRepeat: Bool,
                                 option: Bool, commandOrControl: Bool) -> Bool {
        guard isDown else { return leftToSystem.removeValue(forKey: keyCode) ?? true }
        if !isRepeat {
            leftToSystem[keyCode] = option || commandOrControl
        }
        return leftToSystem[keyCode] ?? true
    }
}

enum PreciseVolumeKeyEvents {
    static let postedMarker: Int64 = 0x564F4C4E

    static func isPosted(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == postedMarker
    }

    static func fineStep(_ keyCode: Int32) -> [CGEvent] {
        let fineFlags: UInt = 0x80000 | 0x20000
        return [0x0a, 0x0b].compactMap { state in
            let event = NSEvent.otherEvent(with: .systemDefined,
                                           location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8) | fineFlags),
                                           timestamp: 0,
                                           windowNumber: 0,
                                           context: nil,
                                           subtype: 8,
                                           data1: Int((keyCode << 16) | Int32(state << 8)),
                                           data2: -1)?.cgEvent
            event?.setIntegerValueField(.eventSourceUserData, value: postedMarker)
            return event
        }
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
