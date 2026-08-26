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
            return isCollapsed ? "line.diagonal" : "line.diagonal.arrow.down.right"
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

    /// Computes the spacing length required to push hidden icons off-screen.
    static func expansionLength(for screenWidth: Double?) -> Double {
        let base = screenWidth ?? 2560.0
        return max(base * 4.0, 10000.0)
    }

    /// Computes the length of the standard separator item given the current state.
    static func separatorLength(state: DisplayState, screenWidth: Double?) -> Double {
        switch state {
        case .collapsed:
            return expansionLength(for: screenWidth)
        case .expanded, .showAll:
            return normalSeparatorWidth
        }
    }

    /// Computes the length of the always-hidden separator item given current state.
    static func alwaysHiddenLength(state: DisplayState, screenWidth: Double?, isEnabled: Bool) -> Double {
        guard isEnabled else { return 0.0 }
        switch state {
        case .collapsed, .expanded:
            return expansionLength(for: screenWidth)
        case .showAll:
            return normalAlwaysHiddenWidth
        }
    }

    /// SF Symbol icon name for the toggle button based on state and style.
    static func toggleSymbolName(isCollapsed: Bool, style: MenuBarHiderIconStyle = .chevron) -> String {
        style.symbolName(isCollapsed: isCollapsed)
    }

    /// Tooltip for the toggle button based on collapse state and always-hidden status.
    static func toggleTooltip(isCollapsed: Bool, isShowingAll: Bool, alwaysHiddenEnabled: Bool) -> String {
        if isCollapsed {
            return "Vorssaint: Click to expand hidden icons"
        }
        if alwaysHiddenEnabled {
            return isShowingAll
                ? "Vorssaint: Click to collapse (Double-click or Right-click to toggle always-hidden)"
                : "Vorssaint: Click to collapse (Double-click or Right-click to show all)"
        }
        return "Vorssaint: Click to collapse hidden icons"
    }

    /// Sorts status item identifiers or roles by horizontal screen position (left to right).
    static func sortedRoles<T: Comparable>(positions: [(role: String, x: T)]) -> [String] {
        positions.sorted { $0.x < $1.x }.map(\.role)
    }
}



