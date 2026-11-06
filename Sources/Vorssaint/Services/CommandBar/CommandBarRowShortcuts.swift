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

    /// Candidate stable keys for an application defined by its bundle identifiers and paths.
    static func applicationStableKeys(bundleIDs: Set<String>, paths: Set<String>) -> Set<String> {
        var keys = Set<String>()
        for id in bundleIDs where !id.isEmpty {
            keys.insert("app.bundle.\(id)")
            keys.insert("uninstall.bundle.\(id)")
        }
        for path in paths where !path.isEmpty {
            keys.insert("app.\(path)")
            keys.insert("uninstall.\(path)")
        }
        return keys
    }

    /// The map after removing the specified row keys.
    static func removing(keys: Set<String>,
                         in shortcuts: [String: GlobalShortcut]) -> [String: GlobalShortcut] {
        guard !keys.isEmpty else { return shortcuts }
        return shortcuts.filter { !keys.contains($0.key) }
    }

    /// Whether a combination is worth registering at all. A bare letter would
    /// take that letter away from every app on the Mac.
    static func isUsable(_ shortcut: GlobalShortcut) -> Bool {
        !shortcut.modifiers.isEmpty
    }

    /// What one key press asks of an application: put it away, or bring it
    /// back. Both halves are `NSRunningApplication` calls the tree already
    /// makes — the Dock click hides at `DockClickService.commit(_:)`, the
    /// switcher unhides at `WindowActivator`.
    enum AppToggleAction: Equatable {
        case hide
        case activate
    }

    /// Hide what is showing, bring back what is away.
    ///
    /// Read from the live `isHidden` rather than from a remembered flag. A
    /// remembered flag goes stale the moment an app is unhidden from the Dock
    /// or a script, and the next press would then hide an app the person
    /// could already see.
    static func toggleAction(isHidden: Bool) -> AppToggleAction {
        isHidden ? .activate : .hide
    }

    /// What a press of an app row's own key asks for.
    ///
    /// `press` counts the presses of that one row's combination, so the first
    /// one is a launch and only a later one can mean "put it away".
    ///
    /// - A hidden app always activates. This branch is read before the press
    ///   count and before frontmost, and it is what makes the toggle
    ///   reversible at any press count: no sequence of presses can leave a
    ///   running app hidden with no way to call it back.
    /// - A later press hides only what is actually in front. Pressing the key
    ///   for an app the person is not looking at means "bring it here", and
    ///   hiding it instead would swallow the press.
    ///
    /// The rapid double press is why frontmost is not the only guard. A
    /// second press can land before the first has finished activating, when
    /// the app is neither in front nor hidden; "press two means hide" on its
    /// own would then hide something that was never shown.
    static func toggleAction(forPress press: Int,
                             isFrontmost: Bool,
                             isHidden: Bool) -> AppToggleAction {
        if isHidden { return .activate }
        if press <= 1 { return .activate }
        return isFrontmost ? .hide : .activate
    }
}
