// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Visual style options for the Menu Bar Hider toggle icon.
enum MenuBarHiderIconStyle: String, CaseIterable, Identifiable {
    case chevron
    case dots
    case eye
    case slash

    var id: String { rawValue }

    func symbolName(isCollapsed: Bool) -> String {
        switch self {
        case .chevron:
            return isCollapsed ? "chevron.left" : "chevron.right"
        case .dots:
            return isCollapsed ? "ellipsis.circle" : "ellipsis.circle.fill"
        case .eye:
            return isCollapsed ? "eye.slash" : "eye"
        case .slash:
            return isCollapsed ? "line.diagonal" : "line.diagonal.arrow"
        }
    }
}

/// Pure calculations and constants for the Menu Bar Hider feature.
/// Lives in Services without importing SwiftUI or AppKit window servers,
/// keeping logic directly testable by unit tests.
enum MenuBarHiderSupport {
    static let toggleAutosaveName = "VorssaintMenuBarHider.toggle"
    static let separatorAutosaveName = "VorssaintMenuBarHider.separator"
    static let alwaysHiddenAutosaveName = "VorssaintMenuBarHider.alwaysHidden"

    static let defaultToggleWidth: Double = 24.0
    static let normalSeparatorWidth: Double = 10.0
    static let normalAlwaysHiddenWidth: Double = 12.0

    static let defaultAutoCollapseDelay = 5
    static let allowedAutoCollapseDelays = [3, 5, 10, 15, 30]

    enum DisplayState: Equatable {
        case collapsed
        case expanded
        case showAll
    }

    /// Sanitizes the auto-collapse delay in seconds against allowed options.
    static func sanitizeAutoCollapseDelay(_ delay: Int) -> Int {
        if allowedAutoCollapseDelays.contains(delay) {
            return delay
        }
        return defaultAutoCollapseDelay
    }

    /// Slack added on top of the usable width so the last item clears the edge.
    static let expansionMargin: Double = 8.0

    /// Fallback usable width when no screen can be measured.
    static let fallbackUsableWidth: Double = 1440.0

    /// Length the separator needs so every item to its left is pushed past the
    /// leading edge of the menu bar.
    ///
    /// This is sized to the strip the items actually live in, not to a large
    /// constant. On a notched Mac the strip left of the notch is a fraction of
    /// the screen — 790 pt of an 1800 pt display on a 14" MacBook Pro — and an
    /// item an order of magnitude wider than its own bar leaves nothing
    /// reachable to drag back out. Covering the strip is sufficient: no item to
    /// the separator's left can be further away than the strip is wide.
    static func expansionLength(for usableWidth: Double?) -> Double {
        let base = usableWidth ?? fallbackUsableWidth
        return max(base, 0) + expansionMargin
    }

    /// Computes the length of the standard separator item given the current state.
    static func separatorLength(state: DisplayState, usableWidth: Double?) -> Double {
        switch state {
        case .collapsed:
            return expansionLength(for: usableWidth)
        case .expanded, .showAll:
            return normalSeparatorWidth
        }
    }

    /// Computes the length of the always-hidden separator item given current state.
    static func alwaysHiddenLength(state: DisplayState, usableWidth: Double?, isEnabled: Bool) -> Double {
        guard isEnabled else { return 0.0 }
        switch state {
        case .collapsed, .expanded:
            return expansionLength(for: usableWidth)
        case .showAll:
            return normalAlwaysHiddenWidth
        }
    }

    /// Grace period between the cursor leaving the toggle and the bar closing
    /// again, so brushing past on the way somewhere else does not collapse it.
    static let hoverCollapseDelay: Double = 0.8

    /// Upper bound on the gap between the two clicks of a reveal gesture.
    static let revealGestureCeiling: Double = 0.30

    /// How close together the two clicks of a reveal gesture must land.
    ///
    /// Deliberately capped below the system double-click interval. That interval
    /// is a comfort setting that can sit at a second or more, while this button's
    /// single click is a toggle people press repeatedly — two deliberate
    /// collapse/expand presses land well inside it and would otherwise be read
    /// as one reveal gesture. A real double click is far faster than pressing,
    /// looking at the result, and pressing again. A system interval shorter than
    /// the ceiling still wins, since AppKit will not report a second click past
    /// it anyway.
    static func revealGestureInterval(systemDoubleClickInterval: Double) -> Double {
        min(max(systemDoubleClickInterval, 0), revealGestureCeiling)
    }

    /// SF Symbol icon name for the toggle button based on state and style.
    static func toggleSymbolName(isCollapsed: Bool, style: MenuBarHiderIconStyle = .chevron) -> String {
        style.symbolName(isCollapsed: isCollapsed)
    }

    /// Tooltip for the toggle button based on collapse state and always-hidden status.
    /// Takes the strings so the choice stays a pure function the tests can drive
    /// for every language, instead of baking English into the service.
    static func toggleTooltip(isCollapsed: Bool,
                              isShowingAll: Bool,
                              alwaysHiddenEnabled: Bool,
                              strings: MenuBarHiderStrings) -> String {
        if isCollapsed {
            return strings.tooltipExpand
        }
        if alwaysHiddenEnabled {
            return isShowingAll ? strings.tooltipCollapseHideAlways : strings.tooltipCollapseShowAll
        }
        return strings.tooltipCollapse
    }

    /// Sorts status item identifiers or roles by horizontal screen position (left to right).
    static func sortedRoles<T: Comparable>(positions: [(role: String, x: T)]) -> [String] {
        positions.sorted { $0.x < $1.x }.map(\.role)
    }
}



