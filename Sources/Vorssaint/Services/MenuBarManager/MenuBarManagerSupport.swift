// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Geometry and timing rules for the menu bar manager, kept free of AppKit so
/// they can be tested with plain numbers.
///
/// Hiding works the way macOS itself lays out status items: a divider item
/// grows to the left and takes the items beyond it with it. Nothing is ever
/// moved on the user's behalf; items change side only when the user drags them
/// across the divider with Command held.
enum MenuBarManagerSupport {
    static let dividerAutosaveName = "VorssaintMenuBarDivider"
    static let toggleAutosaveName = "VorssaintMenuBarToggle"

    /// A zero-length item can stay a synthetic AppKit window that never gets
    /// a WindowServer frame, so items are born one point wide.
    static let materializationLength: CGFloat = 1

    /// Up to macOS 26 a divider this wide pushes every item on its left past
    /// the screen edge, whatever the display width.
    static let offscreenHiddenLength: CGFloat = 10_000

    /// macOS 27 no longer pushes items off the screen: items that stop
    /// fitting move into the system overflow menu, and a divider whose left
    /// edge would cross about a fifth of the display is dropped by itself,
    /// which brings every hidden item back. Measured on a 1920 point display:
    /// the frame stops at x = 408 and a longer divider is evicted.
    static let overflowFloorFraction: CGFloat = 0.2
    static let overflowFloorInset: CGFloat = 24
    /// Keeps the divider clear of the floor so rounding never evicts it.
    static let overflowFloorMargin: CGFloat = 8
    /// What a status item window adds around its length on macOS 27; a
    /// clamped frame corrects it when a release changes it.
    static let windowChrome: CGFloat = 16

    static let rehideChoices = [0, 5, 10, 30, 60]
    static let defaultRehideSeconds = 10
    /// While the pointer rests on the menu bar the user is about to click a
    /// revealed item, so hiding waits this long and checks again.
    static let rehidePostponeSeconds: TimeInterval = 2

    static func usesOverflowMenu(osMajor: Int) -> Bool {
        osMajor >= 27
    }

    static func sanitizedRehideSeconds(_ value: Int) -> Int {
        rehideChoices.contains(value) ? value : defaultRehideSeconds
    }

    /// The x a divider may not cross on macOS 27, estimated from the display
    /// until a clamped frame reports the real one.
    static func estimatedOverflowFloor(screenFrame: CGRect) -> CGFloat {
        screenFrame.minX + (screenFrame.width * overflowFloorFraction).rounded() + overflowFloorInset
    }

    /// The divider length that hides the items on its left.
    ///
    /// - Parameters:
    ///   - shownMaxX: the divider's right edge while it is shown. The divider
    ///     grows leftwards, so this edge does not move while it is hidden.
    ///   - chrome: what the item window adds around its length.
    ///   - observedFloor: the floor a clamped frame reported, if any.
    static func hiddenLength(osMajor: Int,
                             shownMaxX: CGFloat,
                             screenFrame: CGRect,
                             chrome: CGFloat,
                             observedFloor: CGFloat?) -> CGFloat {
        guard usesOverflowMenu(osMajor: osMajor) else { return offscreenHiddenLength }
        let estimate = estimatedOverflowFloor(screenFrame: screenFrame)
        let floor = observedFloor.map { max($0, estimate) } ?? estimate
        let length = shownMaxX - floor - overflowFloorMargin - max(0, chrome)
        return max(materializationLength, length.rounded(.down))
    }

    /// The floor macOS 27 enforced, when the frame shows the divider was
    /// clamped: its left edge stopped and the window spilled past the edge
    /// it had while shown.
    static func clampedFloor(frame: CGRect, shownMaxX: CGFloat) -> CGFloat? {
        frame.maxX > shownMaxX + 2 ? frame.minX : nil
    }

    /// The saved position that places a new item just left of `anchor`.
    /// macOS counts positions in points from the right edge of the display.
    static func seedPosition(leftOf anchor: CGRect, screenFrame: CGRect, gap: CGFloat) -> Double? {
        guard anchor.width > 0, screenFrame.intersects(anchor) else { return nil }
        return Double((screenFrame.maxX - anchor.minX + gap).rounded())
    }

    /// Half the width of the area around the system « that counts as a click
    /// on it; the chevron itself is 18 points wide.
    static let overflowChevronReach: CGFloat = 14
    /// How long after a reveal a click on the divider is taken as the release
    /// of the click that revealed, not as a request to hide.
    static let revealClickGrace: TimeInterval = 0.6
    /// The » divider's width on macOS 27, close to the system « it replaces.
    static let shownDividerLength: CGFloat = 24
    /// Room added above and below our » so it lines up with the system « it
    /// replaces. Measured on macOS 27: glyph rows 8-18 without it, 10-20
    /// with it, the same rows as the system chevron.
    static let overflowChevronDrop: CGFloat = 1
    /// Room added on the left for the same reason: without it our » sat
    /// three points left of the system «.
    static let overflowChevronShift: CGFloat = 3
    /// How long macOS 27 takes to slide revealed items into place.
    static let revealSettleDelay: TimeInterval = 0.3

    /// Whether a click lands on the system « of any display. macOS 27 draws
    /// the same items on every menu bar, aligned to its right edge, so the
    /// chevron is placed by the distance of its center from that edge.
    static func isOverflowChevronClick(_ point: CGPoint,
                                       clickScreen: CGRect,
                                       chevronCenterFromRight: CGFloat,
                                       barHeight: CGFloat) -> Bool {
        guard point.y <= clickScreen.maxY, point.y >= clickScreen.maxY - barHeight else { return false }
        let clickFromRight = clickScreen.maxX - point.x
        return abs(clickFromRight - chevronCenterFromRight) <= overflowChevronReach
    }

    /// Where the « is expected when Accessibility cannot say: just right of
    /// the edge the divider had while shown.
    static func estimatedChevronCenterFromRight(shownMaxX: CGFloat, dividerScreen: CGRect) -> CGFloat {
        dividerScreen.maxX - shownMaxX
    }

    /// Where the system « sits on every display, in the top-left coordinates
    /// that event taps report, so a tap can claim the click before the
    /// overflow menu opens. `screens` are AppKit frames; `mainMaxY` is the
    /// top of the main display.
    static func overflowChevronZones(screens: [CGRect],
                                     mainMaxY: CGFloat,
                                     chevronCenterFromRight: CGFloat,
                                     barHeight: CGFloat) -> [CGRect] {
        screens.map { screen in
            CGRect(x: screen.maxX - chevronCenterFromRight - overflowChevronReach,
                   y: mainMaxY - screen.maxY,
                   width: overflowChevronReach * 2,
                   height: barHeight)
        }
    }

    /// Whether hiding should wait because the pointer is on the menu bar,
    /// where the user is likely reaching for a revealed item.
    static func pointerIsOnMenuBar(_ point: CGPoint, screenFrames: [CGRect], barHeight: CGFloat) -> Bool {
        screenFrames.contains { frame in
            point.x >= frame.minX && point.x <= frame.maxX
                && point.y <= frame.maxY && point.y >= frame.maxY - barHeight
        }
    }

    /// An item of our own left of the divider would be hidden with the rest,
    /// which for the main icon means losing the way back into the app.
    static func wouldHide(_ frame: CGRect?, dividerMinX: CGFloat) -> Bool {
        guard let frame, frame.width > 0 else { return false }
        return frame.maxX <= dividerMinX + 1
    }
}
