// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The keys that answer Claude Code's own prompts in its terminal, as a person
/// would press them. Each prompt opens with its first choice highlighted.
enum AgentTerminalKey: Equatable {
    case down, enter, escape

    /// The bytes a terminal sends for the key.
    var bytes: String {
        switch self {
        case .down: return "\u{1B}[B"
        case .enter: return "\r"
        case .escape: return "\u{1B}"
        }
    }

    /// The Mac key code, for typing into the frontmost window.
    var keyCode: UInt16 {
        switch self {
        case .down: return 125
        case .enter: return 36
        case .escape: return 53
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
        guard !chosen.isEmpty, chosen.allSatisfy({ $0 >= 0 }) else { return nil }
        return chosen.flatMap { Array(repeating: AgentTerminalKey.down, count: $0) + [.enter] } + [.enter]
    }

    /// The hook's first line names the terminal Claude Code runs in.
    static func split(_ message: String) -> (tty: String?, payload: String) {
        guard message.hasPrefix("tty:"), let newline = message.firstIndex(of: "\n") else { return (nil, message) }
        let tty = String(message[message.index(message.startIndex, offsetBy: 4)..<newline])
            .trimmingCharacters(in: .whitespaces)
        return (tty.hasPrefix("/dev/tty") ? tty : nil, String(message[message.index(after: newline)...]))
    }
}
