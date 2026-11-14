// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A small dot-matrix animation for an agent's mark: frames of rows, each
/// cell "1" for a dot, "2" for a dimmer one, "0" for none. Vorssaint draws
/// the dots in the agent's color, so the frames carry no color of their own.
/// The frames live in AgentDotAnimationData.swift, generated from the JSON
/// files in Tools/agent-animations.
struct AgentDotAnimation: Equatable, Identifiable {
    let id: String
    let fps: Int
    /// A looping animation repeats; one that does not holds its last frame.
    let loops: Bool
    /// The frame shown alone when the person asked for reduced motion.
    let still: Int
    let frames: [[String]]

    var rows: Int { frames.first?.count ?? 0 }
    var columns: Int { frames.first?.first?.count ?? 0 }
    var duration: TimeInterval { Double(frames.count) / Double(max(1, fps)) }

    /// The frame at a time since the animation started.
    func frameIndex(elapsed: TimeInterval) -> Int {
        guard !frames.isEmpty else { return 0 }
        let frame = max(0, Int((elapsed * Double(fps)).rounded(.down)))
        return loops ? frame % frames.count : min(frame, frames.count - 1)
    }

    /// How strong a dot is: 1 on, a dim dot less, 0 none.
    func level(frame: Int, column: Int, row: Int) -> Double {
        guard frames.indices.contains(frame), frames[frame].indices.contains(row) else { return 0 }
        let line = Array(frames[frame][row])
        guard line.indices.contains(column) else { return 0 }
        switch line[column] {
        case "1": return 1
        case "2": return Self.dimLevel
        default: return 0
        }
    }

    static let dimLevel = 0.45

    /// The setting's value for the agents' own breathing mark.
    static let classicID = "classic"
    /// A notice whose symbol names one of these draws its dots.
    static let noticeSymbolPrefix = "agentdots."

    static var all: [AgentDotAnimation] { thinking + [question, done] }

    static func named(_ id: String) -> AgentDotAnimation? {
        all.first { $0.id == id }
    }

    var noticeSymbol: String { Self.noticeSymbolPrefix + id }

    static func forNotice(symbol: String) -> AgentDotAnimation? {
        guard symbol.hasPrefix(noticeSymbolPrefix) else { return nil }
        return named(String(symbol.dropFirst(noticeSymbolPrefix.count)))
    }

    /// The thinking animation the person chose; nil keeps the classic mark.
    static func chosenThinking(in defaults: UserDefaults = .standard) -> AgentDotAnimation? {
        let id = defaults.string(forKey: DefaultsKey.notchAgentsAnimation) ?? classicID
        return thinking.first { $0.id == id }
    }
}
