// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Saved values are stable across settings backups. Unknown values do nothing.
enum StatusItemQuickAction: String, CaseIterable, Identifiable {
    case none, keepAwake, micMute, soundMute, screenRecorder, screenshot

    var id: String { rawValue }

    static func saved(_ key: String, in defaults: UserDefaults = .standard) -> Self {
        runnable(defaults.string(forKey: key) ?? "", in: defaults)
    }

    /// What a saved value runs: nothing for an unknown value or for a feature
    /// that is not installed. The value itself stays saved, so an assignment
    /// comes back with its feature, and until then the gesture holds no tap,
    /// no permission and no click.
    static func runnable(_ rawValue: String, in defaults: UserDefaults = .standard) -> Self {
        guard let action = Self(rawValue: rawValue), action != .none,
              action.feature.isAvailable(in: defaults) else { return .none }
        return action
    }

    var feature: AppFeature {
        switch self {
        case .none, .keepAwake: return .keepAwake
        case .micMute: return .micMute
        case .soundMute: return .mixer
        case .screenRecorder: return .screenRecorder
        case .screenshot: return .screenshot
        }
    }

    /// The glyph the failure notice shows, taken from the feature that would
    /// have run.
    var symbolName: String { feature.symbolName }

    /// A screen capture must not photograph this app's own panel, so these two
    /// wait for it to close. Every other action runs at once: it neither needs
    /// the panel gone nor closes it.
    var closesPanelBeforeRunning: Bool {
        self == .screenshot || self == .screenRecorder
    }
}

/// Pure arbitration for the two gestures the menu bar icon carries: a
/// middle-click and a press held past a threshold.
///
/// Nothing here touches AppKit. The adapter supplies event times, watches the
/// physical button for the release this status button never reports, and polls
/// the deadline below; the decisions themselves stay testable without a window.
struct StatusItemGesture {
    struct Settings: Equatable {
        var middle: StatusItemQuickAction = .none
        var hold: StatusItemQuickAction = .none
        static let holdInterval: TimeInterval = 0.5

        /// Reads the saved assignments.
        static func saved(defaults: UserDefaults = .standard) -> Self {
            Self(middle: .saved(DefaultsKey.statusItemMiddleClickAction, in: defaults),
                 hold: .saved(DefaultsKey.statusItemLongPressAction, in: defaults))
        }

        /// False when both gestures are off, in which case the status button
        /// keeps exactly its previous behaviour and nothing is installed.
        var isEnabled: Bool {
            middle != .none || hold != .none
        }

        /// Shared by the tap, permission polling and both settings surfaces.
        /// Built from runnable actions, so an assignment whose feature is not
        /// installed asks for nothing.
        var needsAccessibility: Bool { middle != .none }
    }

    /// Where a press may stray and still be on the icon: the icon itself, plus
    /// the slack the controller gives any click on its items.
    ///
    /// A trackpad button held still for half a second still drifts several
    /// points, so a few-point box around the press cancelled every long press
    /// there. A box sized by the item's width was no better: a countdown or a
    /// metric in the title widens the item, and a release far below the menu
    /// bar still committed. "Drag away" means leaving the icon.
    static func hitArea(of frame: CGRect?) -> CGRect? {
        guard let frame, frame.width > 0, frame.height > 0 else { return nil }
        return frame.insetBy(dx: -4, dy: -8)
    }

    /// Where a press on the icon may start: its own columns, over the whole
    /// height of the bar. The bar is taller than the button (on macOS 27 a
    /// 22 pt button sits 3 pt below the screen's top row), and a pointer
    /// thrown to the top of the screen still presses the icon under it.
    static func pressArea(of frame: CGRect?) -> CGRect? {
        guard let frame, frame.width > 0, frame.height > 0 else { return nil }
        return frame.insetBy(dx: 0, dy: -8)
    }

    /// Display coordinates (origin at the top left of the primary display)
    /// mapped to AppKit screen coordinates (origin at its bottom left).
    ///
    /// This is the one conversion that decides whether a middle-click hits the
    /// icon, and it is deliberately pure: an event tap reports display
    /// coordinates that no AppKit geometry can be compared against directly.
    static func appKitPoint(displayPoint: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: displayPoint.x, y: primaryHeight - displayPoint.y)
    }

    /// Whether a click at `point` belongs to `frame`: the button, or one of
    /// the areas around it.
    ///
    /// This is the adapter's "swallow the event or run the normal click"
    /// decision, so it lives here as a pure predicate: an unknown or empty
    /// frame claims nothing, and the caller then runs the original click
    /// instead of losing it.
    static func claims(_ point: CGPoint, frame: CGRect?) -> Bool {
        guard let frame, frame.width > 0, frame.height > 0 else { return false }
        // The screen's top row reports maxY, which CGRect.contains excludes.
        return point.x >= frame.minX && point.x < frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }

    enum Result: Equatable {
        case single(CGPoint)
        case quick(StatusItemQuickAction)
    }

    private enum Phase {
        case idle
        case pressed(CGPoint, TimeInterval)
        case held
        case middlePressed
    }

    private var phase: Phase = .idle
    /// Where the press in flight may stray, from `hitArea(of:)`.
    private var area: CGRect = .infinite

    var isActive: Bool {
        if case .idle = phase { return false }
        return true
    }

    /// True while a left press is in flight.
    ///
    /// The status button reports its press and never its release, so the
    /// adapter watches the physical button for as long as this is true. A press
    /// either becomes a long press or ends as one ordinary click.
    var watchesForRelease: Bool {
        switch phase {
        case .pressed, .held: return true
        case .idle, .middlePressed: return false
        }
    }

    /// True while a middle press waits for its release.
    var awaitsMiddleRelease: Bool {
        if case .middlePressed = phase { return true }
        return false
    }

    /// The only deadline this machine has: when a held press becomes a long
    /// press. Everything else is driven by the release.
    func deadline(_ settings: Settings) -> TimeInterval? {
        switch phase {
        case .pressed(_, let at) where settings.hold != .none:
            return at + Settings.holdInterval
        default:
            return nil
        }
    }

    mutating func leftDown(at point: CGPoint, time: TimeInterval,
                           within area: CGRect = .infinite) -> [Result] {
        phase = .pressed(point, time)
        self.area = area
        return []
    }

    mutating func leftUp(at point: CGPoint, time: TimeInterval, settings: Settings) -> [Result] {
        guard contains(point) else { cancel(); return [] }
        guard watchesForRelease else { return [] }
        // The watcher turns the press into a long press at the threshold,
        // but a release that beats it is still judged on its own timing.
        let result: Result = holds(releasedAt: time, settings: settings) ? .quick(settings.hold) : .single(point)
        phase = .idle
        return [result]
    }

    /// Whether a release at `time` commits the long press.
    func holds(releasedAt time: TimeInterval, settings: Settings) -> Bool {
        guard settings.hold != .none else { return false }
        switch phase {
        case .held: return true
        case .pressed(_, let at): return time - at >= Settings.holdInterval
        case .idle, .middlePressed: return false
        }
    }

    /// A left press in flight keeps the icon: the button has already taken
    /// that click, and dropping it here would leave it with no outcome.
    mutating func middleDown(settings: Settings, within area: CGRect = .infinite) {
        guard !watchesForRelease else { return }
        cancel()
        guard settings.middle != .none else { return }
        self.area = area
        phase = .middlePressed
    }

    mutating func middleUp(at point: CGPoint, settings: Settings) -> [Result] {
        guard case .middlePressed = phase, contains(point) else {
            cancelMiddle()
            return []
        }
        phase = .idle
        return settings.middle == .none ? [] : [.quick(settings.middle)]
    }

    /// Drops the press once it leaves its area.
    mutating func moved(to point: CGPoint) {
        if isActive && !contains(point) { cancel() }
    }

    /// Advances a held press to the long press once its threshold passes.
    mutating func expired(at now: TimeInterval, settings: Settings) -> [Result] {
        switch phase {
        case .pressed where settings.hold != .none:
            if let end = deadline(settings), now >= end { phase = .held }
        default:
            break
        }
        return []
    }

    /// Losing the middle tap or its hit target must not discard a left hold.
    mutating func cancelMiddle() {
        if case .middlePressed = phase { phase = .idle }
    }

    mutating func cancel() {
        phase = .idle
    }

    private func contains(_ point: CGPoint) -> Bool {
        area.isInfinite || Self.claims(point, frame: area)
    }
}
