// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

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

    /// An app's own combination puts it away only when the app is in front
    /// and the window in front of every other app's is its own. Otherwise
    /// the app comes forward, raising or opening a window as the combination
    /// always did, since hiding it would make that take a second press.
    /// That covers Finder made active by a click on the desktop, with its
    /// windows buried under another app's or with none, and an app whose
    /// last window was closed, minimized or left on another Space. The window
    /// list is read only for an app already in front, so bringing an app
    /// forward, the common press, never waits on the window server.
    static func hidesAppInFront(isFrontmost: Bool, isHidden: Bool,
                                ownsFrontWindow: @autoclosure () -> Bool) -> Bool {
        isFrontmost && !isHidden && ownsFrontWindow()
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

    /// The row an app is listed under in the bar: its bundle ID when it has
    /// one, otherwise where it lives.
    static func appKey(bundleID: String?, path: String) -> String {
        bundleID.map { "app.bundle.\($0)" } ?? "app.\(path)"
    }

    /// The row whose combination goes with an app the uninstaller removed.
    /// Another copy with the same bundle ID still answers to that row, so it
    /// keeps the keys.
    static func keyFreed(byRemovingAppAt path: String, bundleID: String?,
                         remainingBundleIDs: Set<String>) -> String? {
        if let bundleID, remainingBundleIDs.contains(bundleID) { return nil }
        return appKey(bundleID: bundleID, path: path)
    }

    /// The name a row's hotkey is claimed under, and so the name its take-over
    /// choice is kept under. Row combinations live inside one dictionary, so a
    /// claim is named by the row it belongs to.
    static func takeOverKey(for key: String) -> String {
        "\(DefaultsKey.commandBarRowShortcuts).\(key)"
    }

    /// What a row does with a combination macOS may answer, once every
    /// Vorssaint-side check has passed: the same rule every other shortcut
    /// field follows, so the row can offer to take the key over instead of
    /// refusing a combination another field would accept.
    static func takeOverDecision(_ shortcut: GlobalShortcut, for key: String,
                                 in shortcuts: [String: GlobalShortcut],
                                 conflictsWithMacOS: Bool,
                                 isTakenOver: (String) -> Bool) -> RecorderTakeOverDecision {
        SystemShortcutTakeoverSupport.recorderDecision(shortcut: shortcut,
                                                       conflictsWithMacOS: conflictsWithMacOS,
                                                       takenOver: isTakenOver(takeOverKey(for: key)),
                                                       current: shortcuts[key])
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

    /// The panel-monitor drain for a recording whose event tap could not
    /// exist (no Accessibility). A captured key's repeats and release stay
    /// with the recording after it ends; a fresh press of the same key is
    /// never swallowed for a release the monitor did not see. Debts survive
    /// another capture until their own release, or until a fresh press steps
    /// aside. The tap-based drain does the same inside `ShortcutRecordingTap`.
    struct FallbackKeyRouter {
        enum DownRoute: Equatable { case swallow, record }

        /// Keys whose keyDown the recording handled: their repeats and release
        /// belong to that hold, not to the bar.
        private var swallowed = Set<Int64>()

        mutating func routeDown(keyCode: Int64, captureIsActive: Bool,
                                isRepeat: Bool) -> DownRoute {
            if isRepeat {
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
            swallowed.remove(keyCode)
            if captureIsActive {
                // The capture handles the press itself; the hold it leaves
                // behind stays with the recording, the way `end` drains it.
                swallowed.insert(keyCode)
                return .record
            }
            return .record
        }

        /// Whether the release belongs to a key the capture handled.
        mutating func swallowsUp(_ keyCode: Int64) -> Bool {
            swallowed.remove(keyCode) != nil
        }

        var isEmpty: Bool { swallowed.isEmpty }

        mutating func reset() {
            swallowed.removeAll()
        }
    }

    /// Whether a combination is worth registering at all. A bare letter would
    /// take that letter away from every app on the Mac.
    static func isUsable(_ shortcut: GlobalShortcut) -> Bool {
        !shortcut.modifiers.isEmpty
    }
}
