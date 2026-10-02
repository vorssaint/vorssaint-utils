// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// The combinations the person tied to single rows of the bar.
///
/// An alias makes something faster to find; a shortcut makes it instant, with
/// no bar at all. Both matter, and which one a command deserves is a decision
/// only its owner can make: the thing you run four times a day earns a key,
/// the thing you run weekly does not. Nothing is registered unless the person
/// asked for it, so an untouched install pays nothing.
enum CommandBarRowShortcuts {
    /// Bound global hotkey registrations while leaving room for a shortcut
    /// for every letter and for other commands.
    static let limit = 64

    /// Surfaces that can hold an unanswered row take-over offer. Kept beside
    /// the pure slot store so source isolation is testable without the UI
    /// service singleton.
    enum TakeOverSource: Hashable {
        case captureCard
        case appShortcutsSettings
    }

    /// One unanswered offer per surface. Clearing one question cannot discard
    /// another surface's question.
    struct TakeOverOffers<Value> {
        private var values: [TakeOverSource: Value] = [:]

        subscript(_ source: TakeOverSource) -> Value? {
            get { values[source] }
            set { values[source] = newValue }
        }
    }

    /// A cold catalog may arrive after the person changed their shortcut.
    /// Only the latest request, with its original binding still intact, runs.
    struct PendingAppLaunch {
        private var pending: (key: String, shortcut: GlobalShortcut)?

        mutating func schedule(_ key: String, in shortcuts: [String: GlobalShortcut]) {
            pending = shortcuts[key].map { (key, $0) }
        }

        mutating func cancel() { pending = nil }

        mutating func take(in shortcuts: [String: GlobalShortcut], isAvailable: Bool) -> String? {
            defer { pending = nil }
            guard isAvailable, let pending, shortcuts[pending.key] == pending.shortcut else { return nil }
            return pending.key
        }
    }

    enum AssignmentIssue: Equatable {
        case invalid
        case occupied(String)
        case full
    }

    static func assignmentIssue(_ shortcut: GlobalShortcut, for key: String,
                                in shortcuts: [String: GlobalShortcut]) -> AssignmentIssue? {
        guard isUsable(shortcut) else { return .invalid }
        if let owner = self.key(for: shortcut, in: shortcuts), owner != key {
            return .occupied(owner)
        }
        return hasRoom(for: key, in: shortcuts) ? nil : .full
    }

    static func decode(_ raw: String?) -> [String: GlobalShortcut] {
        guard let raw, let data = raw.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return stored.compactMapValues(GlobalShortcut.init(storageValue:))
    }

    static func encode(_ shortcuts: [String: GlobalShortcut]) -> String? {
        let stored = shortcuts.mapValues(\.storageValue)
        guard let data = try? JSONEncoder().encode(stored) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The map after binding (or clearing, with nil) one row. A combination
    /// already tied to another row moves, because a person pressing keys means
    /// the last thing they said: two rows answering to one combination would
    /// leave one of them dead with no way to tell which.
    static func setting(_ shortcut: GlobalShortcut?,
                        for key: String,
                        in shortcuts: [String: GlobalShortcut]) -> [String: GlobalShortcut] {
        var next = shortcuts
        guard let shortcut else {
            next.removeValue(forKey: key)
            return next
        }
        for (otherKey, other) in next where other == shortcut && otherKey != key {
            next.removeValue(forKey: otherKey)
        }
        guard next[key] != nil || next.count < limit else { return next }
        next[key] = shortcut
        return next
    }

    /// Whether one more row can still be bound. Asked before the keys are
    /// taken, so a full list can say so instead of swallowing the combination.
    static func hasRoom(for key: String, in shortcuts: [String: GlobalShortcut]) -> Bool {
        shortcuts[key] != nil || shortcuts.count < limit
    }

    /// The row a combination belongs to, so the press can be routed without
    /// walking the whole catalog twice.
    static func key(for shortcut: GlobalShortcut, in shortcuts: [String: GlobalShortcut]) -> String? {
        shortcuts.first { $0.value == shortcut }?.key
    }

    /// Whether a paused recording hands this press to the app. Only the keys
    /// the offer's buttons and its keyboard walk use pass through, bare or
    /// with Shift alone (⇧Tab walks focus back): tabbing between the buttons,
    /// activating one, the arrows, and Escape as the standing way out. A
    /// modifier-led combination never does — above all the combination the
    /// question names, whose system action must not fire while the offer
    /// waits. Pure, so the tests can pin the list.
    static func passesWhilePaused(keyCode: Int64, modifiers: GlobalShortcutModifiers) -> Bool {
        let onlyShift = modifiers == [.shift]
        guard modifiers.isEmpty || (onlyShift && keyCode == Int64(kVK_Tab)) else { return false }
        switch Int(keyCode) {
        case kVK_Tab, kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter,
             kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
             kVK_Escape:
            return true
        default:
            return false
        }
    }

    /// Routes keys at the take-over offer boundary. Every keyDown the tap
    /// passes or swallows owes its matching keyUp, even if the offer closes
    /// first. Repeats are passed only to the offer that received the original
    /// press; a later offer cannot inherit an old key's autorepeat.
    struct PausedKeyRouter {
        enum Phase { case down, up }
        enum Route: Equatable { case pass, swallow, record }

        /// Keys the app saw; their releases must also reach it.
        private var passedKeyUps: [Int64: UUID] = [:]
        /// Keys the tap swallowed; their releases must stay swallowed too.
        private var swallowedKeyUps = Set<Int64>()

        mutating func route(_ phase: Phase, keyCode: Int64,
                            modifiers: GlobalShortcutModifiers,
                            offerID: UUID?) -> Route {
            switch phase {
            case .up:
                if passedKeyUps.removeValue(forKey: keyCode) != nil { return .pass }
                if swallowedKeyUps.remove(keyCode) != nil { return .swallow }
                return offerID == nil ? .record : .swallow
            case .down:
                if let originalOffer = passedKeyUps[keyCode] {
                    return offerID == originalOffer
                        && passesWhilePaused(keyCode: keyCode, modifiers: modifiers)
                        ? .pass : .swallow
                }
                if swallowedKeyUps.contains(keyCode) { return .swallow }
                guard let offerID else { return .record }
                guard passesWhilePaused(keyCode: keyCode, modifiers: modifiers) else {
                    swallowedKeyUps.insert(keyCode)
                    return .swallow
                }
                // Escape is handled by the recording itself, not handed to
                // the local monitor. The tap then drains its keyUp with the
                // same held-key path as any other captured press.
                if keyCode == Int64(kVK_Escape) { return .record }
                passedKeyUps[keyCode] = offerID
                return .pass
            }
        }

        mutating func reset() {
            passedKeyUps.removeAll()
            swallowedKeyUps.removeAll()
        }

        /// True while no passed or swallowed key still owes its release.
        var isEmpty: Bool { passedKeyUps.isEmpty && swallowedKeyUps.isEmpty }

        /// The key codes whose release the tap still owes or must swallow.
        var owedKeyCodes: Set<Int64> {
            Set(passedKeyUps.keys).union(swallowedKeyUps)
        }

        /// Drops only the named key's debt: a release the tab technically
        /// owes but the keyboard no longer holds is a lost keyUp, not a key
        /// still held, and must stop costing the app its tap.
        mutating func settleOwedRelease(_ keyCode: Int64) {
            passedKeyUps.removeValue(forKey: keyCode)
            swallowedKeyUps.remove(keyCode)
        }
    }

    /// The panel-monitor drain for a recording whose event tap could not
    /// exist (no Accessibility). Without the tap the local monitor owns the
    /// offer's keys: a safe keyDown that reaches the app owes its release,
    /// a keyDown the recording or the offer swallowed (Escape included —
    /// the capture handles it, the app never sees the press) keeps its
    /// repeats and release, and both kinds of debt outlive the recording —
    /// across a new capture started before the release, too — until their
    /// own release, or until a fresh press of that key arrives, which is a
    /// new press, not the hold (a lost keyUp never swallows fresh presses).
    /// The tap-based drain does the same inside `ShortcutRecordingTap`;
    /// this is its monitor-side twin. Pure, so the tests can walk it
    /// without a panel.
    struct FallbackKeyRouter {
        enum Route: Equatable { case pass, swallow, record }

        /// Keys whose keyDown the monitors let through to the app: the app
        /// owns them until their release, and the release must follow it.
        private var forwarded: [Int64: UUID] = [:]
        /// Keys whose keyDown the recording or the offer swallowed: their
        /// repeats and release belong to that hold, not to the person.
        private var swallowed = Set<Int64>()

        mutating func routeDown(keyCode: Int64, modifiers: GlobalShortcutModifiers,
                                offerID: UUID?, captureIsActive: Bool,
                                isRepeat: Bool) -> Route {
            if isRepeat {
                // A repeat belongs to whichever hold produced it, and the
                // monitor sees the whole hold: nothing else can answer it.
                if let originalOffer = forwarded[keyCode] {
                    // Keep autorepeat inside the offer that received the
                    // original press; a newly opened offer cannot inherit it.
                    return offerID == originalOffer ? .pass : .swallow
                }
                if swallowed.contains(keyCode) { return .swallow }
                if captureIsActive {
                    // A hold that predates or survives this capture: the
                    // recording owns it, the way the tap swallows every
                    // repeat while a field records.
                    swallowed.insert(keyCode)
                    return .swallow
                }
                return .record
            }
            // A fresh press of a key we still owe or still hold is a press
            // whose release the monitor never saw: the debt is dead, and
            // this one routes as new.
            forwarded.removeValue(forKey: keyCode)
            swallowed.remove(keyCode)
            if let offerID {
                if Int(keyCode) == Int(kVK_Escape) {
                    // Escape still means "never mind", and the capture
                    // handles it: the app never sees the press, so the pair
                    // stays swallowed and ends at the release.
                    swallowed.insert(keyCode)
                    return .record
                }
                if CommandBarRowShortcuts.passesWhilePaused(keyCode: keyCode,
                                                            modifiers: modifiers) {
                    forwarded[keyCode] = offerID
                    return .pass
                }
                swallowed.insert(keyCode)
                return .swallow
            }
            if captureIsActive {
                // The capture handles the press itself (it may save, offer
                // or step back); the hold it leaves behind stays with the
                // recording, the way `end` drains a key left held.
                swallowed.insert(keyCode)
                return .record
            }
            return .record
        }

        /// The release of a forwarded key passes to the app; the release of
        /// a swallowed one ends its hold instead. Any other keyUp passes.
        mutating func routeUp(_ keyCode: Int64) -> Route {
            if forwarded.removeValue(forKey: keyCode) != nil { return .pass }
            if swallowed.remove(keyCode) != nil { return .swallow }
            return .pass
        }

        var isEmpty: Bool { forwarded.isEmpty && swallowed.isEmpty }

        mutating func reset() {
            forwarded.removeAll()
            swallowed.removeAll()
        }
    }

    /// Whether a combination is worth registering at all. A bare letter would
    /// take that letter away from every app on the Mac.
    static func isUsable(_ shortcut: GlobalShortcut) -> Bool {
        !shortcut.modifiers.isEmpty
    }
}
