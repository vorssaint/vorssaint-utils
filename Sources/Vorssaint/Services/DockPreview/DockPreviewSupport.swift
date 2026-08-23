// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
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
    /// A minimized window, or one parked on another desktop, is still a window
    /// the user wants somewhere: the drop restores it and brings it here rather
    /// than refusing the gesture. Fullscreen is the one refusal left -- it owns
    /// a Space of its own and discards any position it is given, so a drag of
    /// it could only ever pretend to work.
    static func canDragToPlace(hasWindowID: Bool, isFullscreen: Bool) -> Bool {
        hasWindowID && !isFullscreen
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

    // Card metrics. The preview size setting sizes what the card shows, so the
    // thumbnail and the icon standing in for it follow it, and so do the gaps
    // around them, which hold nothing of their own. What does not follow it is
    // anything sized by fixed content: the title band is one line of 12pt
    // semibold at every setting, and the panel header holds a 16pt icon beside
    // the same 12pt. Scaling the band with the card left that line adrift in
    // 31pt of nothing at the largest size and squeezed into 13pt at the
    // smallest, which is the one thing here that was actually wrong.
    static var cardPadding: CGFloat { 10 * PreviewSizing.scale }
    static var cardTitleSpacing: CGFloat { 7 * PreviewSizing.scale }
    /// A 13pt name over a 10.5pt subtitle, beside the two 16pt window controls
    /// -- the App Switcher's title block, to the point. Fixed: what it holds is
    /// the same at every preview size.
    static let cardTitleHeight: CGFloat = 29
    static var cardSpacing: CGFloat { 8 * PreviewSizing.scale }
    static var panelPadding: CGFloat { 10 * PreviewSizing.scale }
    static let panelHeaderHeight: CGFloat = 28

    /// 16:10, the shape of the screen the captured window came from, so a
    /// full-height window fills the well instead of sitting between two bars.
    /// The picture inside keeps a 5pt inset, which is why this is 210x135
    /// rather than 200x125.
    static func cardThumbnailSize(scale: CGFloat) -> CGSize {
        CGSize(width: 210 * scale, height: 135 * scale)
    }

    static func cardSize(scale: CGFloat) -> CGSize {
        let thumbnail = cardThumbnailSize(scale: scale)
        let padding = 10 * scale
        return CGSize(width: thumbnail.width + padding * 2,
                      height: thumbnail.height + padding * 2 + 7 * scale + cardTitleHeight)
    }

    /// The picture's inset inside the thumbnail well. It scales with the well,
    /// so the 16:10 the well is cut to survives every preview size.
    static func cardPictureSize(scale: CGFloat) -> CGSize {
        let thumbnail = cardThumbnailSize(scale: scale)
        let inset = 5 * scale
        return CGSize(width: thumbnail.width - inset * 2, height: thumbnail.height - inset * 2)
    }

    static var cardThumbnailInset: CGFloat { 5 * PreviewSizing.scale }

    /// The app's icon along the bottom edge of the picture, the size the App
    /// Switcher draws it. App artwork sits on the system icon grid with a clear
    /// margin around it, so the frame hangs past the row by that margin and the
    /// artwork, not its empty edge, lines up with the picture.
    static var cardAppBadgeSize: CGFloat { 32 * PreviewSizing.scale }
    static var cardAppBadgeArtworkInset: CGFloat { (cardAppBadgeSize * 0.094).rounded() }

    /// Stands in for the thumbnail when there is no capture, so it follows the
    /// thumbnail rather than staying the one fixed picture on a scaling card.
    static func cardFallbackIconSize(scale: CGFloat) -> CGFloat {
        52 * scale
    }

    static var cardThumbnailWidth: CGFloat { cardThumbnailSize(scale: PreviewSizing.scale).width }
    static var cardThumbnailHeight: CGFloat { cardThumbnailSize(scale: PreviewSizing.scale).height }
    static var cardWidth: CGFloat { cardSize(scale: PreviewSizing.scale).width }
    static var cardHeight: CGFloat { cardSize(scale: PreviewSizing.scale).height }
    static var cardFallbackIconSize: CGFloat { cardFallbackIconSize(scale: PreviewSizing.scale) }

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

    /// Whether the panel draws a header row. A hovered panel has no use for
    /// one: it named the app whose Dock icon the pointer is resting on, and
    /// carried steppers for walking windows the pointer is already on top of.
    /// A pinned panel keeps it -- there it is the drag handle, the only way to
    /// unpin or close, and the only place that says which app it belongs to
    /// once the pointer has gone.
    static func showsPanelHeader(isPinned: Bool) -> Bool {
        isPinned
    }

    /// The room the window's name has in the title band: the band less the two
    /// controls beside it, whose place is held whether or not they are drawn.
    static var cardTitleTextWidth: CGFloat { cardThumbnailWidth - 40 }

    /// Whether a name is longer than the room it has. Measured against the font
    /// it is drawn in rather than a layout pass, so the answer is the same
    /// before the band has ever been on screen and can be checked without one.
    /// Whether a card draws the app's icon in the corner of its picture. With
    /// no capture the icon already fills the well as a watermark, so the badge
    /// would only repeat it.
    static func showsCardAppBadge(hasPreview: Bool) -> Bool {
        hasPreview
    }

    /// Whether a card draws its close and minimize buttons. A pinned panel
    /// counted as permanent hover, which held both open on every card it
    /// showed for as long as it stayed up.
    static func showsCardControls(isHovering: Bool, isSelected: Bool) -> Bool {
        isHovering || isSelected
    }

    /// Cards run along the Dock's own edge. A Dock at the bottom gets a row; a
    /// Dock at the side gets a column, because a row there grows away from the
    /// Dock across the screen, which is the one direction the pointer is not
    /// coming from. A pinned panel is detached from the Dock, so it keeps the
    /// row at any Dock position.
    static func stacksVertically(orientation: DockPreviewOrientation, isPinned: Bool) -> Bool {
        !isPinned && (orientation == .left || orientation == .right)
    }

    /// How many cards the panel can show before it has to scroll.
    static func visibleCardCount(itemCount: Int,
                                 screenVisibleFrame: CGRect,
                                 orientation: DockPreviewOrientation,
                                 isPinned: Bool,
                                 padding: CGFloat = panelPadding,
                                 cardWidth: CGFloat = cardWidth,
                                 cardHeight: CGFloat = cardHeight,
                                 spacing: CGFloat = cardSpacing) -> Int {
        let vertical = stacksVertically(orientation: orientation, isPinned: isPinned)
        let cardExtent = vertical ? cardHeight : cardWidth
        let screenExtent = vertical ? screenVisibleFrame.height : screenVisibleFrame.width
        let maxExtent = max(cardExtent + padding * 2,
                            min(screenExtent * 0.9, screenExtent - edgePadding * 2))
        let available = max(1, Int((maxExtent - padding * 2 + spacing) / (cardExtent + spacing)))
        return min(max(1, itemCount), available)
    }

    static func panelSize(itemCount: Int,
                          screenVisibleFrame: CGRect,
                          isPinned: Bool,
                          orientation: DockPreviewOrientation = .bottom,
                          padding: CGFloat = panelPadding,
                          cardWidth: CGFloat = cardWidth,
                          cardHeight: CGFloat = cardHeight,
                          spacing: CGFloat = cardSpacing) -> CGSize {
        let count = max(1, itemCount)
        let vertical = stacksVertically(orientation: orientation, isPinned: isPinned)
        let visibleCards = visibleCardCount(itemCount: count,
                                            screenVisibleFrame: screenVisibleFrame,
                                            orientation: orientation,
                                            isPinned: isPinned,
                                            padding: padding,
                                            cardWidth: cardWidth,
                                            cardHeight: cardHeight,
                                            spacing: spacing)
        let run = CGFloat(visibleCards) * (vertical ? cardHeight : cardWidth)
            + CGFloat(max(0, visibleCards - 1)) * spacing + padding * 2
        let header = showsPanelHeader(isPinned: isPinned) ? panelHeaderHeight : 0
        if vertical {
            let maxHeight = max(cardHeight + padding * 2,
                                min(screenVisibleFrame.height * 0.9,
                                    screenVisibleFrame.height - edgePadding * 2))
            return CGSize(width: cardWidth + padding * 2,
                          height: min(run + header, maxHeight + header))
        }
        let maxWidth = max(cardWidth + padding * 2,
                           min(screenVisibleFrame.width * 0.9,
                               screenVisibleFrame.width - edgePadding * 2))
        return CGSize(width: min(run, maxWidth), height: cardHeight + padding * 2 + header)
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
