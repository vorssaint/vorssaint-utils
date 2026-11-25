// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The keys that answer Claude Code's own prompts in its terminal, as a person
/// would press them. Each prompt opens with its first choice highlighted.
enum AgentTerminalKey: Equatable {
    case down, enter, escape, space

    /// The bytes a terminal sends for the key.
    var bytes: String {
        switch self {
        case .down: return "\u{1B}[B"
        case .enter: return "\r"
        case .escape: return "\u{1B}"
        case .space: return " "
        }
    }

    /// The Mac key code, for typing into the frontmost window.
    var keyCode: UInt16 {
        switch self {
        case .down: return 125
        case .enter: return 36
        case .escape: return 53
        case .space: return 49
        }
    }
}

enum AgentTerminalKeys {
    /// A permission prompt: its first choice is "Yes"; Escape is "No".
    static func permission(allow: Bool) -> [AgentTerminalKey] {
        allow ? [.enter] : [.escape]
    }

    /// Single-choice questions, answered in order: down to each chosen option,
    /// then Enter. A last Enter confirms the review Claude Code shows before
    /// sending; where there is none it lands in an empty prompt and does nothing.
    /// Nil when an answer is not one of the question's options.
    static func answers(_ chosen: [Int]) -> [AgentTerminalKey]? {
        answers(chosen.map { [$0] })
    }

    /// Each question's picks, in order. One pick is a single choice: down to it, Enter.
    /// A multi-select question's are ticked from the top with Space, then Down to its Submit row and Enter. `multiSelect` maps such a question to its option count.
    /// The last Enter confirms the review before sending.
    static func answers(_ chosen: [[Int]], multiSelect: [Int: Int] = [:]) -> [AgentTerminalKey]? {
        guard !chosen.isEmpty, chosen.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 >= 0 } }) else { return nil }
        var keys: [AgentTerminalKey] = []
        for (question, picks) in chosen.enumerated() {
            if multiSelect[question] == nil {
                guard picks.count == 1 else { return nil }
                keys += Array(repeating: .down, count: picks[0]) + [.enter]
            } else {
                var cursor = 0
                for pick in Set(picks).sorted() {
                    keys += Array(repeating: .down, count: pick - cursor) + [.space]
                    cursor = pick
                }
                // Below the options come "Type something" and then the question's own
                // Submit row; Enter on the last tick would not leave the question.
                keys += Array(repeating: .down, count: (multiSelect[question] ?? 0) + 1 - cursor) + [.enter]
            }
        }
        return keys + [.enter]
    }

    /// The hook's first line names the terminal Claude Code runs in.
    static func split(_ message: String) -> (tty: String?, payload: String) {
        guard message.hasPrefix("tty:"), let newline = message.firstIndex(of: "\n") else { return (nil, message) }
        let tty = String(message[message.index(message.startIndex, offsetBy: 4)..<newline])
            .trimmingCharacters(in: .whitespaces)
        return (tty.hasPrefix("/dev/tty") ? tty : nil, String(message[message.index(after: newline)...]))
    }
}
