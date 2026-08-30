// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DictationShortcutSlot: String, CaseIterable, Identifiable {
    case primary
    case secondary

    var id: String { rawValue }
}

enum DictationShortcutMode: String, CaseIterable, Identifiable {
    case toggle
    case pushToTalk
    case hybrid

    var id: String { rawValue }
}

struct DictationShortcutProfile: Equatable {
    let slot: DictationShortcutSlot
    let mode: DictationShortcutMode
    let provider: DictationProvider
    let model: DictationModel
    let language: DictationLanguage
}

enum DictationShortcutAction: Equatable {
    case begin
    case stop
}

/// Pure key gesture state. Carbon does not report autorepeat for registered
/// hotkeys consistently, so duplicate downs are rejected here as well.
struct DictationShortcutGesture: Equatable {
    static let hybridHoldThreshold: TimeInterval = 0.5

    private(set) var pressedAt: TimeInterval?
    private(set) var pressedMode: DictationShortcutMode?

    mutating func keyDown(at time: TimeInterval,
                          mode: DictationShortcutMode,
                          sessionIsActive: Bool) -> DictationShortcutAction? {
        guard pressedAt == nil else { return nil }
        pressedAt = time
        pressedMode = mode
        switch mode {
        case .toggle:
            return sessionIsActive ? .stop : .begin
        case .pushToTalk, .hybrid:
            return sessionIsActive ? nil : .begin
        }
    }

    mutating func keyUp(at time: TimeInterval,
                        sessionIsActive: Bool) -> DictationShortcutAction? {
        guard let pressedAt, let mode = pressedMode else { return nil }
        self.pressedAt = nil
        pressedMode = nil
        guard sessionIsActive else { return nil }
        switch mode {
        case .toggle: return nil
        case .pushToTalk: return .stop
        case .hybrid:
            return time - pressedAt >= Self.hybridHoldThreshold ? .stop : nil
        }
    }

    mutating func cancel() {
        pressedAt = nil
        pressedMode = nil
    }
}
