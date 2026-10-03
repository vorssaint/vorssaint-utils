// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Saved values are stable across settings backups. Unknown values do nothing.
enum StatusItemQuickAction: String, CaseIterable, Identifiable {
    case none, keepAwake, micMute, soundMute, screenRecorder, screenshot

    var id: String { rawValue }

    static func saved(_ key: String, in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: key) ?? "") ?? .none
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

extension DefaultsKey {
    static let statusItemMiddleClickAction = "statusItemMiddleClickAction"
    static let statusItemLongPressAction = "statusItemLongPressAction"
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
        static let dragTolerance: CGFloat = 4

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
        /// The assignment still needs a grant if its target is uninstalled.
        var needsAccessibility: Bool { middle != .none }
    }

    /// The margin a held press may drift within before it counts as a drag
    /// away.
    ///
    /// A trackpad button held still for half a second still drifts several
    /// points, so a few-point box cancelled every long press on a trackpad.
    /// "Drag away" has to mean leaving the icon instead.
    static func dragMargin(iconWidth: CGFloat) -> CGFloat {
        max(Settings.dragTolerance, iconWidth / 2)
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

    /// Whether a click at `point` belongs to the button's frame, expanded by
    /// `inset` so a release just off the edge is still the same click.
    ///
    /// This is the adapter's "swallow the event or run the normal click"
    /// decision, so it lives here as a pure predicate: an unknown or empty
    /// frame claims nothing, and the caller then runs the original click
    /// instead of losing it.
    static func claims(_ point: CGPoint, frame: CGRect?, inset: CGFloat = 0) -> Bool {
        guard let frame, frame.width > 0, frame.height > 0 else { return false }
        let hitFrame = frame.insetBy(dx: -inset, dy: -inset)
        // The screen's top row reports maxY, which CGRect.contains excludes.
        return point.x >= hitFrame.minX && point.x < hitFrame.maxX
            && point.y >= hitFrame.minY && point.y <= hitFrame.maxY
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
    private var startPoint: CGPoint = .zero

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

    /// A short label for the current phase. The tests pin the transitions this
    /// state machine owns, and a phase is the only honest way to read them.
    var phaseName: String {
        switch phase {
        case .idle: return "idle"
        case .pressed: return "pressed"
        case .held: return "held"
        case .middlePressed: return "middle"
        }
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

    mutating func leftDown(at point: CGPoint, time: TimeInterval) -> [Result] {
        phase = .pressed(point, time)
        startPoint = point
        return []
    }

    mutating func leftUp(at point: CGPoint, time: TimeInterval,
                         settings: Settings,
                         tolerance: CGFloat = Settings.dragTolerance) -> [Result] {
        guard insideDragTolerance(point, tolerance: tolerance) else { cancel(); return [] }
        switch phase {
        case .held:
            phase = .idle
            return settings.hold == .none ? [] : [.quick(settings.hold)]
        case .pressed(_, let at):
            phase = .idle
            // The watcher turns the press into a long press at the threshold,
            // but a release that beats it is still judged on its own timing.
            if settings.hold != .none && time - at >= Settings.holdInterval {
                return [.quick(settings.hold)]
            }
            return [.single(point)]
        default:
            return []
        }
    }

    mutating func middleDown(at point: CGPoint, settings: Settings) {
        cancel()
        guard settings.middle != .none else { return }
        startPoint = point
        phase = .middlePressed
    }

    mutating func middleUp(at point: CGPoint, settings: Settings,
                           tolerance: CGFloat = Settings.dragTolerance) -> [Result] {
        guard case .middlePressed = phase,
              insideDragTolerance(point, tolerance: tolerance) else {
            cancelMiddle()
            return []
        }
        phase = .idle
        return settings.middle == .none ? [] : [.quick(settings.middle)]
    }

    /// Drops the press once it has moved further than `tolerance` from where it
    /// started. The caller chooses that margin: a few points is far too strict
    /// for a held trackpad button, where staying still for half a second still
    /// drifts, and a press must survive that to become a long press.
    mutating func moved(to point: CGPoint, tolerance: CGFloat = Settings.dragTolerance) {
        if isActive && !insideDragTolerance(point, tolerance: tolerance) { cancel() }
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

    private func insideDragTolerance(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        abs(startPoint.x - point.x) <= tolerance
            && abs(startPoint.y - point.y) <= tolerance
    }
}
