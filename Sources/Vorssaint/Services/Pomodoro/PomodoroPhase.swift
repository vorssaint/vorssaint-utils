// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

public enum PomodoroPhase: String, CaseIterable, Identifiable, Codable {
    case focus
    case shortBreak
    case longBreak

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .focus: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "beach.umbrella.fill"
        }
    }

    public var emoji: String {
        switch self {
        case .focus: return "🍅"
        case .shortBreak: return "☕️"
        case .longBreak: return "🌴"
        }
    }
}

public enum PomodoroState: String, Codable {
    case idle
    case running
    case paused
    case completed

    public var isRunning: Bool { self == .running }
    public var isPaused: Bool { self == .paused }
}
