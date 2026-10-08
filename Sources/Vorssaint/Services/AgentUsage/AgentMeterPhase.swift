// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentMeterSignal: Equatable {
    case tool(String)
    case toolResult
    case turnEnded(success: Bool)
    case codexStarted
    case codexFinished
}

struct AgentMeterPhase: Equatable {
    enum Phase: Equatable {
        case idle, working, waiting
    }

    private(set) var phase: Phase = .idle

    mutating func apply(_ signal: AgentMeterSignal) {
        switch signal {
        case .tool("AskUserQuestion"), .tool("AskQuestion"):
            phase = .waiting
        case .tool:
            phase = .working
        case .toolResult, .codexStarted:
            phase = .working
        case .turnEnded, .codexFinished:
            phase = .idle
        }
    }
}
