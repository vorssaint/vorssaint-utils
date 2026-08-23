// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum DockClickAction: Equatable {
    case minimize
    case restore
    case hide
    case cycleWindows
    case passThrough
}

/// What a click should do given the app's last handled click.
enum DockClickRepeatDecision: Equatable {
    /// Inside the double-click gap: do nothing, or an accidental double-click
    /// would toggle twice and look like the click bounced.
    case swallow
    /// The opposite of the last action, taken from our own record: while the
    /// animation settles the AX minimized state is ambiguous and deriving the
    /// action from it re-fires the SAME action instead of toggling back.
    case toggle(DockClickAction)
    /// No recent action: derive from the app's actual window state.
    case deriveFromState
}

enum DockClickSupport {
    /// Both local and published builds may be running during development.
    /// Neither is ever a valid target for the other's global Dock click tap.
    static func isOwnBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.vorssaint.utils"
            || bundleIdentifier == "com.vorssaint.utils.dev"
    }

    /// The Option-Command-M chord is not unique to Minimize All. Only the
    /// standard menu action identifier proves that pressing it is safe.
    static func isVerifiedMinimizeAll(commandCharacter: String?,
                                      modifiers: Int?,
                                      identifier: String?) -> Bool {
        commandCharacter?.uppercased() == "M"
            && modifiers == 2
            && identifier == "miniaturizeAll:"
    }

    /// Clicks closer together than this count as one intent.
    static let repeatClickGap: TimeInterval = 0.25

    /// After a handled click, how long a follow-up click keeps toggling from
    /// our own record instead of trusting the still-settling AX state.
    static let toggleIntentWindow: TimeInterval = 1.5

    /// How far the cursor may wander during a press and still count as a
    /// click. Past this the press is a Dock icon drag: the down is replayed
    /// to the Dock and no action runs. Clicks jitter a pixel or two; a real
    /// drag crosses this within its first frames.
    static let dragSlop: CGFloat = 6

    /// Whether a press that started at `origin` has moved far enough at
    /// `point` to be a drag rather than a click.
    static func isDragMovement(from origin: CGPoint, to point: CGPoint) -> Bool {
        let dx = point.x - origin.x, dy = point.y - origin.y
        return (dx * dx + dy * dy).squareRoot() > dragSlop
    }

    /// Delay before sweeping up windows the Minimize All shortcut left behind
    /// (apps without the standard binding). Long enough for the batched
    /// animation to finish so the sweep sees the settled state.
    static let minimizeSweepDelay: TimeInterval = 0.9

    /// How long after a successful Minimize All menu press the per-window
    /// check runs for apps that report success but leave their windows
    /// untouched. Short enough to feel immediate, long enough for an honest
    /// app's batch to have flipped every window's AX state.
    static let minimizeMenuVerifyDelay: TimeInterval = 0.35

    /// Delay before re-asserting a restore on windows whose minimize was still
    /// in flight when the restore clicked in.
    static let restoreSweepDelay: TimeInterval = 0.6

    /// The order a restore should walk a batch of minimized windows: indices
    /// into `ids`, first restored to last, with duplicate windows dropped.
    ///
    /// `frontToBack` is the app's real window order captured from the
    /// WindowServer while the windows were still up, so the window that was
    /// frontmost — the one the user was working in — comes LAST. Restoring it
    /// last lets it animate in over the others and land on top on its own,
    /// which is the whole point: raising it afterwards to fix the stacking is
    /// exactly the flick the user sees (issue #357). The AX windows array
    /// order is deliberately not used to decide this; it does not reliably
    /// report the focused window first.
    ///
    /// `preferredFront` covers batches with no captured order (the app was
    /// minimized by other means): the caller's best guess at the front window
    /// is moved to the end and everything else keeps its given order.
    static func restoreSequence(ids: [CGWindowID?],
                                frontToBack: [CGWindowID],
                                preferredFront: CGWindowID? = nil) -> [Int] {
        var seen = Set<CGWindowID>()
        var candidates: [Int] = []
        for (index, id) in ids.enumerated() {
            if let id {
                guard !seen.contains(id) else { continue }
                seen.insert(id)
            }
            candidates.append(index)
        }

        guard !frontToBack.isEmpty else {
            guard let preferredFront,
                  let frontSlot = candidates.firstIndex(where: { ids[$0] == preferredFront })
            else { return candidates }
            candidates.append(candidates.remove(at: frontSlot))
            return candidates
        }

        // Windows missing from the captured order count as rearmost, so the
        // captured stacking always decides the top of the pile.
        func depth(_ index: Int) -> Int {
            guard let id = ids[index], let depth = frontToBack.firstIndex(of: id)
            else { return frontToBack.count }
            return depth
        }
        return candidates.sorted { first, second in
            let firstDepth = depth(first), secondDepth = depth(second)
            if firstDepth != secondDepth { return firstDepth > secondDepth }
            return first < second
        }
    }

    /// Whether a captured minimize still speaks for the app's current state.
    ///
    /// The capture is written when this feature minimizes an app and consumed
    /// when it restores one, so anything that brings those windows back some
    /// other way — the App Switcher, the window menu, the app itself — leaves
    /// it behind. Acting on a leftover later would claim a minimize this
    /// feature never performed, which is exactly what `ownsMinimize` exists to
    /// prevent. The capture holds only while at least one window it named is
    /// still down.
    static func capturedMinimizeStillHolds(captured: [CGWindowID],
                                           stillMinimized: Set<CGWindowID>) -> Bool {
        captured.contains { stillMinimized.contains($0) }
    }

    static func repeatDecision(lastAction: DockClickAction?,
                               elapsed: TimeInterval?) -> DockClickRepeatDecision {
        guard let lastAction, let elapsed, elapsed < toggleIntentWindow else { return .deriveFromState }
        if elapsed < repeatClickGap { return .swallow }
        switch lastAction {
        case .minimize: return .toggle(.restore)
        case .restore: return .toggle(.minimize)
        case .hide, .cycleWindows: return .deriveFromState
        case .passThrough: return .deriveFromState
        }
    }

    /// Dock click actions for the active app. Hide works at app level, while
    /// minimize acts on visible windows and restores them on the next click.
    ///
    /// Restore only reclaims what this feature itself put away — `ownsMinimize`.
    /// The toggle it advertises is that pair and nothing else, so a window the
    /// user minimized some other way (⌘M, the window's own button, the app)
    /// keeps the Dock's native restore. Taking those over bought nothing: the
    /// stacking this batch is rebuilt from was never captured for them, which
    /// the restore walk itself has to paper over by guessing at a front window.
    /// Modifier clicks always keep the
    /// Dock's native behaviors (⌘ reveals in Finder, ⌥ hides the previous
    /// app, ⌃ opens the menu). Fullscreen windows can't minimize, and restoring
    /// siblings from inside a fullscreen Space would yank the user to another
    /// Space, so fullscreen windows keep only the app-level hide action.
    /// Whether the click should treat the app as having windows to minimize.
    /// Apps with a busy or unresponsive accessibility server (Java and
    /// Eclipse apps like DBeaver, issue #200) answer the AX window list with
    /// nothing while the window server plainly shows their windows on
    /// screen. In that blind spot the minimize path must still engage — it
    /// runs through the app's own Minimize All menu item, which needs no
    /// per-window AX at all.
    static func effectiveHasUnminimized(unminimizedCount: Int,
                                        minimizedCount: Int,
                                        windowServerSeesWindows: Bool) -> Bool {
        unminimizedCount > 0 || (minimizedCount == 0 && windowServerSeesWindows)
    }

    static func action(appIsFrontmost: Bool,
                       hasUnminimizedWindows: Bool,
                       hasMinimizedWindows: Bool,
                       hasFullscreenWindows: Bool,
                       hasModifiers: Bool,
                       minimizeEnabled: Bool = true,
                       hideEnabled: Bool = false,
                       cycleWindowsEnabled: Bool = false,
                       unminimizedWindowCount: Int = 0,
                       ownsMinimize: Bool = false) -> DockClickAction {
        guard !hasModifiers else { return .passThrough }
        if cycleWindowsEnabled, appIsFrontmost, !hasFullscreenWindows, unminimizedWindowCount > 1 {
            return .cycleWindows
        }
        if hideEnabled, appIsFrontmost { return .hide }
        guard !hasFullscreenWindows else { return .passThrough }
        if minimizeEnabled, appIsFrontmost, hasUnminimizedWindows { return .minimize }
        if minimizeEnabled, ownsMinimize, !hasUnminimizedWindows, hasMinimizedWindows { return .restore }
        return .passThrough
    }

    /// Cheap geometric gate that runs before any Accessibility hit-test, in the
    /// event's top-left-origin coordinates. When the Dock reserves screen space
    /// (`visibleFrame` is inset on the bottom, left or right), the click must
    /// land inside that reserved strip — this keeps clicks on windows or panels
    /// hovering just above the Dock out, which matters because the AX item
    /// matching that follows can only trust the Dock's long axis. Without a
    /// reserved strip (auto-hide, or the Dock lives on another display) it
    /// falls back to a generous edge band.
    static func dockStripContains(_ point: CGPoint,
                                  screenFrame: CGRect,
                                  visibleFrame: CGRect,
                                  fallbackMargin: CGFloat = 120) -> Bool {
        // Small negative inset: the pointer clamps to the screen, but event
        // coordinates on the very edge can land fractionally outside.
        guard screenFrame.insetBy(dx: -8, dy: -8).contains(point) else { return false }

        let bottomGap = screenFrame.maxY - visibleFrame.maxY
        let leftGap = visibleFrame.minX - screenFrame.minX
        let rightGap = screenFrame.maxX - visibleFrame.maxX
        let reserved: CGFloat = 8

        if bottomGap > reserved || leftGap > reserved || rightGap > reserved {
            if bottomGap > reserved, point.y >= visibleFrame.maxY - 2 { return true }
            if leftGap > reserved, point.x <= visibleFrame.minX + 2 { return true }
            if rightGap > reserved, point.x >= visibleFrame.maxX - 2 { return true }
            return false
        }

        return point.y >= screenFrame.maxY - fallbackMargin
            || point.x <= screenFrame.minX + fallbackMargin
            || point.x >= screenFrame.maxX - fallbackMargin
    }
}
