// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Experimental Accessibility actions. None of them has a default shortcut:
/// Phase 0 did not find the chords, and the window-title format is unverified.
enum CursorExperimentalAction: String, CaseIterable {
    case sendNow
    case stop
    case keepAll
    case undoAll
}

enum CursorExperimentalBlock: Equatable {
    case remote
    case needsTrust
    case notFront
    case titleUnverified
    case severalWindows
    case noShortcut
}

struct CursorExperimentalCheck: Equatable {
    var trusted: Bool
    var frontIsCursor: Bool
    /// How many Cursor windows contain the verified title format.
    var windowCount: Int
    var shortcutConfigured: Bool
    var remote: Bool
    /// The focused Cursor window contains the same format.
    var focusedMatches: Bool
}

enum CursorExperimental {
    /// S0.17 never read a macOS window-title format. An empty format aborts.
    static let verifiedTitleFormat = ""

    static func permissions(experimental: Bool) -> [AppPermission] {
        experimental ? [.accessibility] : []
    }

    /// Nil means the action may run. Trust and the front app are checked
    /// before the missing title format, so a test can say which one failed.
    static func evaluate(_ check: CursorExperimentalCheck,
                         titleFormat: String = verifiedTitleFormat) -> CursorExperimentalBlock? {
        if check.remote { return .remote }
        if !check.trusted { return .needsTrust }
        if !check.frontIsCursor { return .notFront }
        if titleFormat.isEmpty { return .titleUnverified }
        if check.windowCount <= 0 || !check.focusedMatches { return .titleUnverified }
        if check.windowCount > 1 { return .severalWindows }
        if !check.shortcutConfigured { return .noShortcut }
        return nil
    }

    /// Titles that contain the verified format. An empty format matches nothing.
    static func matchCount(_ titles: [String], format: String) -> Int {
        let needle = format.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return 0 }
        return titles.reduce(0) { count, title in
            count + (title.localizedCaseInsensitiveContains(needle) ? 1 : 0)
        }
    }
}

enum CursorShortcutStore {
    static func stored(_ chords: [CursorExperimentalAction: String]) -> String {
        CursorExperimentalAction.allCases
            .map { "\($0.rawValue)=\(chords[$0] ?? "")" }
            .joined(separator: "\n")
    }

    static func chords(in stored: String) -> [CursorExperimentalAction: String] {
        var map: [CursorExperimentalAction: String] = [:]
        for line in stored.split(separator: "\n", omittingEmptySubsequences: false) {
            let pieces = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard pieces.count == 2, let action = CursorExperimentalAction(rawValue: pieces[0]) else { continue }
            map[action] = pieces[1]
        }
        return map
    }

    static func chord(_ action: CursorExperimentalAction, in stored: String) -> GlobalShortcut? {
        guard let raw = chords(in: stored)[action], !raw.isEmpty else { return nil }
        return GlobalShortcut(storageValue: raw)
    }
}

enum CursorBuddyPose: Equatable {
    case idle
    case thinking
    case reading
    case editing
    case running
    case waiting
    case done
    case failed
    case quiet
    case wave

    static func pose(for state: CursorLiveState) -> CursorBuddyPose {
        switch state {
        case .idle, .sent: return .idle
        case .thinking: return .thinking
        case .reading, .searching: return .reading
        case .editing: return .editing
        case .running, .subagent: return .running
        case .waiting: return .waiting
        case .done: return .done
        case .failed, .stopped: return .failed
        case .quiet: return .quiet
        }
    }
}

/// Reveals a whole reply at about 90 characters a second, never longer than
/// 2.5 seconds, and never past the first 600 characters.
enum CursorTypewriter {
    static let rate = 90.0
    static let cap = 2.5
    static let preview = 600

    static func shownCount(elapsed: TimeInterval, length: Int) -> Int {
        let target = min(max(0, length), preview)
        guard target > 0 else { return 0 }
        let duration = min(cap, Double(target) / rate)
        let progress = min(1, max(0, elapsed / duration))
        return min(target, Int((Double(target) * progress).rounded(.down)))
    }

    /// The caret blinks twice a second while the reveal is still running.
    static func showsCaret(elapsed: TimeInterval) -> Bool {
        Int(max(0, elapsed) * 2).isMultiple(of: 2)
    }
}
