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
    let magnifiedTileSize: CGFloat

    /// The tallest an icon under the cursor can get: the magnified size while
    /// magnification is on, the resting tile size otherwise. Geometry that must
    /// cover a hovered icon (like the proximity band) sizes against this.
    var hoverTileSize: CGFloat {
        magnification ? max(tileSize, magnifiedTileSize) : tileSize
    }

    static func sanitized(orientation rawOrientation: String?,
                          autohide: Bool?,
                          tileSize rawTileSize: Double?,
                          magnification: Bool?,
                          magnifiedTileSize rawMagnifiedTileSize: Double?) -> DockPreviewPreferences {
        let size = rawTileSize ?? 64
        // System Settings never writes largesize until the slider moves, so a
        // missing key defaults to the slider's maximum rather than undershooting.
        let magnifiedSize = rawMagnifiedTileSize ?? 128
        return DockPreviewPreferences(
            orientation: DockPreviewOrientation.sanitized(rawOrientation),
            autohide: autohide ?? false,
            tileSize: CGFloat(min(max(size, 16), 256)),
            magnification: magnification ?? false,
            magnifiedTileSize: CGFloat(min(max(magnifiedSize, 16), 256))
        )
    }
}

enum DockPreviewBlockedReason: String, Equatable {
    case missingAccessibility
    case missingScreenRecording
    case dockUnavailable
}

struct DockPreviewAvailability: Equatable {
    let canRun: Bool
    let blockedReason: DockPreviewBlockedReason?
}

struct DockPreviewCloseState: Equatable {
    let remainingWindowIDs: [CGWindowID]
    let selectedWindowID: CGWindowID?
    let shouldEndSession: Bool
}

struct DockPreviewMouseDownDecision: Equatable {
    let shouldEndSession: Bool
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
    /// How long the cursor must rest on an icon before its panel opens. Long
    /// enough that the Dock can be crossed on the way somewhere else, short
    /// enough that a cursor which stopped is answered. Adjustable: that line
    /// falls differently for every pointer speed.
    static let defaultOpenDelayMilliseconds = 200
    /// The floor keeps two properties: the window list is read `prefetchLead`
    /// earlier, so a shorter wait would read it the moment the cursor lands;
    /// and `switchDelay` plus its inline reading stays under it, so a switch is
    /// never slower than an open.
    static let openDelayMillisecondsRange: ClosedRange<Int> = 200 ... 900

    static func sanitizedOpenDelay(milliseconds: Int) -> Int {
        min(max(milliseconds, openDelayMillisecondsRange.lowerBound),
            openDelayMillisecondsRange.upperBound)
    }

    static func openDelay(milliseconds: Int) -> TimeInterval {
        TimeInterval(sanitizedOpenDelay(milliseconds: milliseconds)) / 1000
    }

    /// Handing an already open panel to the app under the cursor: the panel is
    /// on screen and only has to re-point. Kept under the shortest open delay
    /// on offer, so a switch is never slower than an open.
    static let switchDelay: TimeInterval = 0.1

    /// How far ahead of the panel the window list is read: far enough that an
    /// ordinary list is in hand when the panel opens, no further, so what it
    /// opens on is still true. Half the shortest wait.
    static let prefetchLead: TimeInterval = 0.1

    static func prefetchDelay(openDelay: TimeInterval) -> TimeInterval {
        max(0, openDelay - prefetchLead)
    }
    static let hideDelay: TimeInterval = 0.22
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
    /// Whether a preview card can be lifted out of the panel and dropped
    /// somewhere else. A minimized window has no on-screen position to aim at,
    /// and a fullscreen window owns its Space and ignores the position it is
    /// given — dragging either one would move nothing while still tearing the
    /// panel down.
    static func canDragToPlace(hasWindowID: Bool,
                               isOnScreen: Bool,
                               isMinimized: Bool,
                               isFullscreen: Bool) -> Bool {
        hasWindowID && isOnScreen && !isMinimized && !isFullscreen
    }

    /// How far the pointer must travel before a press on a card becomes a
    /// drag. Large enough that a click with a shaky hand still opens the
    /// window, small enough that the lift feels immediate.
    static let dragLiftDistance: CGFloat = 6

    /// Keeps the dropped window fully reachable on the screen under the
    /// pointer. Oversized windows align to the visible frame instead of
    /// leaving their title bar beyond an edge.
    static func dragOrigin(pointer: CGPoint,
                           windowSize: CGSize,
                           visibleFrame: CGRect) -> CGPoint {
        guard visibleFrame.width > 0, visibleFrame.height > 0,
              windowSize.width > 0, windowSize.height > 0
        else { return pointer }

        let visibleWidth = min(windowSize.width, visibleFrame.width)
        let visibleHeight = min(windowSize.height, visibleFrame.height)
        return CGPoint(
            x: min(max(pointer.x, visibleFrame.minX), visibleFrame.maxX - visibleWidth),
            y: min(max(pointer.y, visibleFrame.minY + visibleHeight), visibleFrame.maxY)
        )
    }

    /// Card metrics. The thumbnail gets whatever the fixed chrome does not
    /// take, so the card can be resized or the title band retuned without
    /// leaving a stale magic number behind — the old code hard-coded a 54pt
    /// deduction that no longer matched the parts it stood for.
    static var cardWidth: CGFloat { 176 * PreviewSizing.scale }
    static var cardHeight: CGFloat { 134 * PreviewSizing.scale }
    static var cardPadding: CGFloat { 8 * PreviewSizing.scale }
    static var cardTitleSpacing: CGFloat { 5 * PreviewSizing.scale }
    /// One line of 12pt semibold, with just enough room for descenders.
    static var cardTitleHeight: CGFloat { 17 * PreviewSizing.scale }
    static var cardThumbnailHeight: CGFloat {
        cardHeight - cardPadding * 2 - cardTitleSpacing - cardTitleHeight
    }
    static var cardSpacing: CGFloat { 8 * PreviewSizing.scale }
    static var panelPadding: CGFloat { 12 * PreviewSizing.scale }
    static let panelHeaderHeight: CGFloat = 28

    /// How solid the panel's frosted background is drawn, as a fraction. The
    /// floor is not zero on purpose: the panel's title sits straight on the
    /// material, so past a certain point it is reading against the desktop and
    /// the panel stops looking like a panel. Anything the slider can reach has
    /// to still look finished.
    static let backgroundOpacityRange: ClosedRange<Double> = 0.4...1

    static func sanitizedBackgroundOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return backgroundOpacityRange.upperBound }
        return min(max(value, backgroundOpacityRange.lowerBound), backgroundOpacityRange.upperBound)
    }

    /// How far in from the Dock's screen edge the cursor can be and still sit over
    /// a Dock item. Used to gate the per-mouse-move Accessibility hit-test to the
    /// Dock's strip instead of running it across the whole screen — that hit-test
    /// is a synchronous AX round-trip, and firing it on every move anywhere
    /// saturates the main thread and the process's AX access (which, among other
    /// things, starves other AX-driven features like quit-on-last-window-close).
    /// Size against `hoverTileSize` so magnified icons stay inside the band.
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
        guard preferences != nil else {
            return DockPreviewAvailability(canRun: false, blockedReason: .dockUnavailable)
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
                                  isInsidePanel: Bool) -> DockPreviewMouseDownDecision {
        guard isVisible, !isPinned, !isInsidePanel else {
            return DockPreviewMouseDownDecision(shouldEndSession: false)
        }
        return DockPreviewMouseDownDecision(shouldEndSession: true)
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

    static func closeState(afterRemoving closedWindowID: CGWindowID,
                           windowIDs: [CGWindowID],
                           selectedWindowID: CGWindowID?) -> DockPreviewCloseState {
        let remaining = windowIDs.filter { $0 != closedWindowID }
        let removedSelection = selectedWindowID == closedWindowID
        return DockPreviewCloseState(
            remainingWindowIDs: remaining,
            selectedWindowID: removedSelection ? nil : selectedWindowID,
            shouldEndSession: remaining.isEmpty
        )
    }
}
