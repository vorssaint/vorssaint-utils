// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum DockPreviewOrientation: String, Equatable {
    case bottom
    case left
    case right

    static func sanitized(_ raw: String?) -> DockPreviewOrientation {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "left": return .left
        case "right": return .right
        default: return .bottom
        }
    }
}

struct DockPreviewPreferences: Equatable {
    let orientation: DockPreviewOrientation
    let autohide: Bool
    let tileSize: CGFloat
    let magnification: Bool

    static func sanitized(orientation rawOrientation: String?,
                          autohide: Bool?,
                          tileSize rawTileSize: Double?,
                          magnification: Bool?) -> DockPreviewPreferences {
        let size = rawTileSize ?? 64
        return DockPreviewPreferences(
            orientation: DockPreviewOrientation.sanitized(rawOrientation),
            autohide: autohide ?? false,
            tileSize: CGFloat(min(max(size, 16), 256)),
            magnification: magnification ?? false
        )
    }
}

enum DockPreviewBlockedReason: String, Equatable {
    case missingAccessibility
    case missingScreenRecording
    case magnification
    case dockUnavailable
}

struct DockPreviewAvailability: Equatable {
    let canRun: Bool
    let blockedReason: DockPreviewBlockedReason?
}

struct DockPreviewCloseState: Equatable {
    let remainingWindowIDs: [CGWindowID]
    let selectedWindowID: CGWindowID?
    let activePeekWindowID: CGWindowID?
    let desiredWindowID: CGWindowID?
    let shouldEndSession: Bool
}

struct DockPreviewMouseDownDecision: Equatable {
    let shouldEndSession: Bool
    let restoreOrigin: Bool
}

/// A thin keep-alive region connecting a Dock icon to its preview panel.
///
/// Intentionally *not* the padded union of the icon and panel: a union spans the
/// panel's full width down at the Dock row, so it swallows neighbouring icons and
/// the session can never be handed over to another app (or closed) when the mouse
/// returns to the Dock. Instead this is the icon, the panel, and a narrow bridge
/// across the gap between them — wide enough to follow the cursor from icon to
/// panel, narrow enough that the next Dock icon stays outside it.
struct HoverCorridor: Equatable {
    let rects: [CGRect]

    func contains(_ point: CGPoint) -> Bool {
        rects.contains { $0.contains(point) }
    }
}

enum DockPreviewSupport {
    static let hoverDelay: TimeInterval = 0.4
    /// Shorter than the first-open delay: once a panel is already up, handing it
    /// to the app under the cursor should feel immediate, not like a fresh open.
    static let switchDelay: TimeInterval = 0.25
    static let hideDelay: TimeInterval = 0.22
    static let peekDelay: TimeInterval = 0.08
    /// A little slack around the panel so the cursor grazing its edge doesn't
    /// flicker the session between "inside" and "leaving".
    static let panelStayMargin: CGFloat = 6
    static let edgePadding: CGFloat = 8
    static let panelGap: CGFloat = 6
    static let autohidePanelGap: CGFloat = 0
    /// Forgiveness around the icon, panel and bridge so a slightly off-path
    /// cursor still keeps the session, while neighbouring Dock icons (one tile
    /// width away) stay clear of the corridor.
    static let corridorMargin: CGFloat = 12
    static var cardWidth: CGFloat { 190 * PreviewSizing.scale }
    static var cardHeight: CGFloat { 142 * PreviewSizing.scale }
    static let cardSpacing: CGFloat = 8
    static let panelPadding: CGFloat = 12
    static let panelHeaderHeight: CGFloat = 28

    /// How far in from the Dock's screen edge the cursor can be and still sit over
    /// a Dock item. Used to gate the per-mouse-move Accessibility hit-test to the
    /// Dock's strip instead of running it across the whole screen — that hit-test
    /// is a synchronous AX round-trip, and firing it on every move anywhere
    /// saturates the main thread and the process's AX access (which, among other
    /// things, starves other AX-driven features like quit-on-last-window-close).
    static func dockProximityBand(tileSize: CGFloat) -> CGFloat {
        max(160, tileSize * 1.5 + 60)
    }

    static func availability(enabled: Bool,
                             hasAccessibility: Bool,
                             hasScreenRecording: Bool,
                             preferences: DockPreviewPreferences?) -> DockPreviewAvailability {
        guard enabled else {
            return DockPreviewAvailability(canRun: false, blockedReason: nil)
        }
        guard hasAccessibility else {
            return DockPreviewAvailability(canRun: false, blockedReason: .missingAccessibility)
        }
        guard hasScreenRecording else {
            return DockPreviewAvailability(canRun: false, blockedReason: .missingScreenRecording)
        }
        guard let preferences else {
            return DockPreviewAvailability(canRun: false, blockedReason: .dockUnavailable)
        }
        guard !preferences.magnification else {
            return DockPreviewAvailability(canRun: false, blockedReason: .magnification)
        }
        return DockPreviewAvailability(canRun: true, blockedReason: nil)
    }

    static func panelFrame(anchor: CGRect,
                           panelSize: CGSize,
                           screenVisibleFrame: CGRect,
                           orientation: DockPreviewOrientation,
                           gap: CGFloat = panelGap,
                           padding: CGFloat = edgePadding) -> CGRect {
        let width = min(panelSize.width, max(1, screenVisibleFrame.width - padding * 2))
        let height = min(panelSize.height, max(1, screenVisibleFrame.height - padding * 2))

        func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            min(max(value, lower), max(lower, upper))
        }

        let x: CGFloat
        let y: CGFloat
        switch orientation {
        case .bottom:
            x = clamped(anchor.midX - width / 2,
                        lower: screenVisibleFrame.minX + padding,
                        upper: screenVisibleFrame.maxX - width - padding)
            y = clamped(anchor.maxY + gap,
                        lower: screenVisibleFrame.minY + padding,
                        upper: screenVisibleFrame.maxY - height - padding)
        case .left:
            x = clamped(anchor.maxX + gap,
                        lower: screenVisibleFrame.minX + padding,
                        upper: screenVisibleFrame.maxX - width - padding)
            y = clamped(anchor.midY - height / 2,
                        lower: screenVisibleFrame.minY + padding,
                        upper: screenVisibleFrame.maxY - height - padding)
        case .right:
            x = clamped(anchor.minX - width - gap,
                        lower: screenVisibleFrame.minX + padding,
                        upper: screenVisibleFrame.maxX - width - padding)
            y = clamped(anchor.midY - height / 2,
                        lower: screenVisibleFrame.minY + padding,
                        upper: screenVisibleFrame.maxY - height - padding)
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func panelSize(itemCount: Int,
                          screenVisibleFrame: CGRect,
                          padding: CGFloat = panelPadding,
                          cardWidth: CGFloat = cardWidth,
                          cardHeight: CGFloat = cardHeight,
                          spacing: CGFloat = cardSpacing) -> CGSize {
        let count = max(1, itemCount)
        let maxWidth = max(cardWidth + padding * 2,
                           min(screenVisibleFrame.width * 0.9, screenVisibleFrame.width - edgePadding * 2))
        let availableCards = max(1, Int((maxWidth - padding * 2 + spacing) / (cardWidth + spacing)))
        let visibleCards = min(count, availableCards)
        let width = CGFloat(visibleCards) * cardWidth + CGFloat(max(0, visibleCards - 1)) * spacing + padding * 2
        return CGSize(width: min(width, maxWidth), height: cardHeight + padding * 2 + panelHeaderHeight)
    }

    static func windowPositionText(selectedWindowID: CGWindowID?, windowIDs: [CGWindowID]) -> String? {
        guard windowIDs.count > 1 else { return nil }
        guard let selectedWindowID,
              let index = windowIDs.firstIndex(of: selectedWindowID) else {
            return "\(windowIDs.count)"
        }
        return "\(index + 1)/\(windowIDs.count)"
    }

    static func adjacentWindowID(selectedWindowID: CGWindowID?,
                                 windowIDs: [CGWindowID],
                                 offset: Int) -> CGWindowID? {
        guard !windowIDs.isEmpty else { return nil }
        guard windowIDs.count > 1 else { return windowIDs.first }

        let currentIndex: Int
        if let selectedWindowID,
           let index = windowIDs.firstIndex(of: selectedWindowID) {
            currentIndex = index
        } else {
            currentIndex = offset < 0 ? 0 : -1
        }
        let nextIndex = (currentIndex + offset + windowIDs.count) % windowIDs.count
        return windowIDs[nextIndex]
    }

    static func mouseDownDecision(isVisible: Bool,
                                  isPinned: Bool,
                                  isInsidePanel: Bool,
                                  clickedDock: Bool) -> DockPreviewMouseDownDecision {
        guard isVisible, !isPinned, !isInsidePanel else {
            return DockPreviewMouseDownDecision(shouldEndSession: false, restoreOrigin: false)
        }
        return DockPreviewMouseDownDecision(shouldEndSession: true, restoreOrigin: !clickedDock)
    }

    static func shouldRestoreOriginAfterMinimize(originPID: pid_t?,
                                                 originWindowID: CGWindowID?,
                                                 targetPID: pid_t,
                                                 targetWindowID: CGWindowID) -> Bool {
        guard let originPID else { return false }
        return originPID != targetPID || originWindowID != targetWindowID
    }

    /// The keep-alive corridor for a session: the icon and panel (each with a
    /// little forgiveness) plus a narrow bridge spanning the gap between them,
    /// laid along the cursor's natural path for the Dock's orientation.
    ///
    /// The icon rect is captured while the Dock is revealed and sits at the
    /// screen edge, so with Dock auto-hide its padded rect still covers the strip
    /// the cursor crosses to re-reveal the Dock — no extra handling needed.
    static func hoverCorridor(iconFrame: CGRect,
                              panelFrame: CGRect,
                              orientation: DockPreviewOrientation,
                              margin: CGFloat = corridorMargin) -> HoverCorridor {
        let icon = iconFrame.insetBy(dx: -margin, dy: -margin)
        let panel = panelFrame.insetBy(dx: -margin, dy: -margin)

        let bridge: CGRect
        switch orientation {
        case .bottom:
            let lowerY = min(iconFrame.maxY, panelFrame.minY)
            let upperY = max(iconFrame.maxY, panelFrame.minY)
            bridge = CGRect(x: iconFrame.minX - margin,
                            y: lowerY,
                            width: iconFrame.width + margin * 2,
                            height: max(0, upperY - lowerY))
        case .left:
            let lowerX = min(iconFrame.maxX, panelFrame.minX)
            let upperX = max(iconFrame.maxX, panelFrame.minX)
            bridge = CGRect(x: lowerX,
                            y: iconFrame.minY - margin,
                            width: max(0, upperX - lowerX),
                            height: iconFrame.height + margin * 2)
        case .right:
            let lowerX = min(panelFrame.maxX, iconFrame.minX)
            let upperX = max(panelFrame.maxX, iconFrame.minX)
            bridge = CGRect(x: lowerX,
                            y: iconFrame.minY - margin,
                            width: max(0, upperX - lowerX),
                            height: iconFrame.height + margin * 2)
        }

        return HoverCorridor(rects: [icon, panel, bridge])
    }

    static func shouldRestoreOnEnd(committed: Bool) -> Bool {
        !committed
    }

    static func closeState(afterRemoving closedWindowID: CGWindowID,
                           windowIDs: [CGWindowID],
                           selectedWindowID: CGWindowID?,
                           activePeekWindowID: CGWindowID?,
                           desiredWindowID: CGWindowID?) -> DockPreviewCloseState {
        let remaining = windowIDs.filter { $0 != closedWindowID }
        let removedSelection = selectedWindowID == closedWindowID
        let removedPeek = activePeekWindowID == closedWindowID
        let removedDesired = desiredWindowID == closedWindowID
        return DockPreviewCloseState(
            remainingWindowIDs: remaining,
            selectedWindowID: removedSelection ? nil : selectedWindowID,
            activePeekWindowID: removedPeek ? nil : activePeekWindowID,
            desiredWindowID: removedDesired ? nil : desiredWindowID,
            shouldEndSession: remaining.isEmpty
        )
    }
}
