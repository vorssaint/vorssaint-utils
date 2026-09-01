// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox

/// Pure policy used by the selection reader. The actual pasteboard work still
/// runs through GeneralPasteboardAccess; keeping the destructive restore guard
/// here makes it independently testable.
enum SelectionTranslationPasteboardSupport {
    static let copyKeyCode = CGKeyCode(kVK_ANSI_C)

    static func shouldRestore(originalChangeCount: Int,
                              copyChangeCount: Int,
                              currentChangeCount: Int) -> Bool {
        copyChangeCount != originalChangeCount && currentChangeCount == copyChangeCount
    }

}

/// Keeps the continuation and clipboard-history cleanup gates independent.
/// A watchdog may resolve the read before the pasteboard lane finishes, but it
/// must never prevent that lane from releasing the capture deferral later.
struct SelectionTranslationPasteboardTransactionState: Sendable {
    private(set) var didStartPosting = false
    private(set) var didResume = false
    private(set) var didEndDeferral = false

    mutating func claimPostStart() -> Bool {
        guard !didStartPosting else { return false }
        didStartPosting = true
        return true
    }

    mutating func claimResume() -> Bool {
        guard !didResume else { return false }
        didResume = true
        return true
    }

    mutating func claimDeferralEnd() -> Bool {
        guard didStartPosting, !didEndDeferral else { return false }
        didEndDeferral = true
        return true
    }
}

enum SelectionTranslationShortcutFlowAction: Equatable, Sendable {
    case none
    case translate(String)
    case readPasteboard
}

enum SelectionTranslationShortcutReleaseDecision: Equatable, Sendable {
    case released
    case wait
    case timedOut
}

enum SelectionTranslationShortcutReleaseSupport {
    static let pollIntervalNanoseconds: UInt64 = 15_000_000
    static let maximumAttempts = 100

    static func decision(modifiersHeld: Bool,
                         keyHeld: Bool,
                         attempt: Int) -> SelectionTranslationShortcutReleaseDecision {
        if !modifiersHeld && !keyHeld { return .released }
        return attempt >= maximumAttempts ? .timedOut : .wait
    }
}

/// Coordinates the independent accessibility, release and hold-deadline
/// callbacks. Each action can be claimed at most once.
struct SelectionTranslationShortcutFlowState: Sendable {
    private var accessibilityResult: String?
    private var deadlineReached = false
    private var released = false
    private var actionClaimed = false

    mutating func accessibilityCompleted(_ text: String) -> SelectionTranslationShortcutFlowAction {
        guard accessibilityResult == nil else { return .none }
        accessibilityResult = text
        return claimActionIfReady()
    }

    mutating func deadlineReachedNow() -> SelectionTranslationShortcutFlowAction {
        guard !deadlineReached else { return .none }
        deadlineReached = true
        return claimActionIfReady()
    }

    mutating func shortcutReleased() -> SelectionTranslationShortcutFlowAction {
        guard !released else { return .none }
        released = true
        return claimActionIfReady()
    }

    private mutating func claimActionIfReady() -> SelectionTranslationShortcutFlowAction {
        guard !actionClaimed else { return .none }
        guard let accessibilityResult else { return .none }
        if accessibilityResult.isEmpty {
            guard released else { return .none }
        } else {
            guard released || deadlineReached else { return .none }
        }
        actionClaimed = true
        return accessibilityResult.isEmpty ? .readPasteboard : .translate(accessibilityResult)
    }
}

enum SelectionTranslationConstants {
    static let quickToolHotkeyID: UInt32 = 21
}
