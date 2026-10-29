// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import Foundation

struct VoiceActivityDetector {
    private let activationLevel: CGFloat
    private let immediateActivationLevel: CGFloat
    private let requiredActiveFrames: Int
    private let hangoverDuration: TimeInterval
    private var consecutiveActiveFrames = 0
    private var activeUntil = -TimeInterval.infinity

    init(
        activationLevel: CGFloat = 0.012,
        immediateActivationLevel: CGFloat = 0.04,
        requiredActiveFrames: Int = 2,
        hangoverDuration: TimeInterval = 0.75
    ) {
        self.activationLevel = activationLevel
        self.immediateActivationLevel = immediateActivationLevel
        self.requiredActiveFrames = requiredActiveFrames
        self.hangoverDuration = hangoverDuration
    }

    mutating func process(level: CGFloat, at timestamp: TimeInterval) {
        if level >= immediateActivationLevel {
            consecutiveActiveFrames = requiredActiveFrames
            extendActivity(at: timestamp)
        } else if level >= activationLevel {
            consecutiveActiveFrames += 1
            if consecutiveActiveFrames >= requiredActiveFrames {
                extendActivity(at: timestamp)
            }
        } else {
            consecutiveActiveFrames = 0
        }
    }

    func isActive(at timestamp: TimeInterval) -> Bool {
        timestamp < activeUntil
    }

    mutating func reset() {
        consecutiveActiveFrames = 0
        activeUntil = -TimeInterval.infinity
    }

    private mutating func extendActivity(at timestamp: TimeInterval) {
        activeUntil = max(activeUntil, timestamp + hangoverDuration)
    }
}
