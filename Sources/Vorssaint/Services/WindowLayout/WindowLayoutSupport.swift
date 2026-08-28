// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowLayoutTargetCapability: Equatable {
    case position
    case frame
    case fullScreen
}

enum WindowLayoutAction: String, CaseIterable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case topLeftSixth, topCenterSixth, topRightSixth
    case bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, marginMaximize, fullScreen, center
    case previousDisplay, nextDisplay, restore

    var id: String { rawValue }

    static let shortcutActions: [WindowLayoutAction] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds,
        .topLeftSixth, .topCenterSixth, .topRightSixth,
        .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
        .topLeft, .topRight, .bottomLeft, .bottomRight,
        .maximize, .marginMaximize, .fullScreen, .center, .restore,
        .previousDisplay, .nextDisplay,
    ]

    var supportsShortcut: Bool {
        Self.shortcutActions.contains(self)
    }

    var targetCapability: WindowLayoutTargetCapability {
        switch self {
        case .center, .restore:
            return .position
        case .fullScreen:
            return .fullScreen
        default:
            return .frame
        }
    }

    var shortcutID: UInt32 {
        switch self {
        case .leftHalf: return 30
        case .rightHalf: return 31
        case .topHalf: return 32
        case .bottomHalf: return 33
        case .topLeft: return 34
        case .topRight: return 35
        case .bottomLeft: return 36
        case .bottomRight: return 37
        case .maximize: return 38
        case .center: return 39
        case .restore: return 40
        case .leftThird: return 41
        case .centerThird: return 42
        case .rightThird: return 43
        case .leftTwoThirds: return 44
        case .rightTwoThirds: return 45
        case .nextDisplay: return 46
        case .topLeftSixth: return 47
        case .topCenterSixth: return 48
        case .topRightSixth: return 49
        case .bottomLeftSixth: return 50
        case .bottomCenterSixth: return 51
        case .bottomRightSixth: return 52
        case .fullScreen: return 53
        case .previousDisplay: return 54
        case .marginMaximize: return 55
        }
    }

    init?(shortcutID: UInt32) {
        guard let action = Self.allCases.first(where: { $0.shortcutID == shortcutID }) else { return nil }
        self = action
    }

    var shortcutKey: String {
        switch self {
        case .leftHalf: return DefaultsKey.windowLayoutShortcutLeft
        case .rightHalf: return DefaultsKey.windowLayoutShortcutRight
        case .topHalf: return DefaultsKey.windowLayoutShortcutTop
        case .bottomHalf: return DefaultsKey.windowLayoutShortcutBottom
        case .topLeft: return DefaultsKey.windowLayoutShortcutTopLeft
        case .topRight: return DefaultsKey.windowLayoutShortcutTopRight
        case .bottomLeft: return DefaultsKey.windowLayoutShortcutBottomLeft
        case .bottomRight: return DefaultsKey.windowLayoutShortcutBottomRight
        case .maximize: return DefaultsKey.windowLayoutShortcutMaximize
        case .marginMaximize: return DefaultsKey.windowLayoutShortcutMarginMaximize
        case .fullScreen: return DefaultsKey.windowLayoutShortcutFullScreen
        case .center: return DefaultsKey.windowLayoutShortcutCenter
        case .restore: return DefaultsKey.windowLayoutShortcutRestore
        case .leftThird: return DefaultsKey.windowLayoutShortcutLeftThird
        case .centerThird: return DefaultsKey.windowLayoutShortcutCenterThird
        case .rightThird: return DefaultsKey.windowLayoutShortcutRightThird
        case .leftTwoThirds: return DefaultsKey.windowLayoutShortcutLeftTwoThirds
        case .rightTwoThirds: return DefaultsKey.windowLayoutShortcutRightTwoThirds
        case .previousDisplay: return DefaultsKey.windowLayoutShortcutPreviousDisplay
        case .nextDisplay: return DefaultsKey.windowLayoutShortcutNextDisplay
        case .topLeftSixth: return DefaultsKey.windowLayoutShortcutTopLeftSixth
        case .topCenterSixth: return DefaultsKey.windowLayoutShortcutTopCenterSixth
        case .topRightSixth: return DefaultsKey.windowLayoutShortcutTopRightSixth
        case .bottomLeftSixth: return DefaultsKey.windowLayoutShortcutBottomLeftSixth
        case .bottomCenterSixth: return DefaultsKey.windowLayoutShortcutBottomCenterSixth
        case .bottomRightSixth: return DefaultsKey.windowLayoutShortcutBottomRightSixth
        }
    }

    /// Existing actions keep their established shortcuts. New actions start
    /// unassigned so enabling Window Layout never claims extra system-wide
    /// combinations without an explicit choice.
    var defaultShortcut: GlobalShortcut? {
        switch self {
        case .leftHalf: return .windowLayoutLeftDefault
        case .rightHalf: return .windowLayoutRightDefault
        case .topHalf: return .windowLayoutTopDefault
        case .bottomHalf: return .windowLayoutBottomDefault
        case .topLeft: return .windowLayoutTopLeftDefault
        case .topRight: return .windowLayoutTopRightDefault
        case .bottomLeft: return .windowLayoutBottomLeftDefault
        case .bottomRight: return .windowLayoutBottomRightDefault
        case .maximize: return .windowLayoutMaximizeDefault
        case .center: return .windowLayoutCenterDefault
        case .restore: return .windowLayoutRestoreDefault
        case .leftThird: return .windowLayoutLeftThirdDefault
        case .centerThird: return .windowLayoutCenterThirdDefault
        case .rightThird: return .windowLayoutRightThirdDefault
        case .leftTwoThirds: return .windowLayoutLeftTwoThirdsDefault
        case .rightTwoThirds: return .windowLayoutRightTwoThirdsDefault
        case .nextDisplay: return .windowLayoutNextDisplayDefault
        case .topLeftSixth, .topCenterSixth, .topRightSixth,
                .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth,
                .marginMaximize, .fullScreen, .previousDisplay:
            // New actions must never claim a system-wide combination unasked.
            return nil
        }
    }

    /// Stored value meaning the user removed this action's shortcut (issue
    /// #169): most people use a handful of layouts, and every registered
    /// hotkey occupies a system-wide key combo other apps then cannot use.
    static let clearedShortcutStorageValue = "none"

    /// Resolves a stored shortcut value: the saved shortcut, the default when
    /// nothing was saved or the value is corrupt, or nil when the user
    /// explicitly cleared it.
    static func resolvedShortcut(storedValue: String?,
                                 defaultShortcut: GlobalShortcut?) -> GlobalShortcut? {
        guard let storedValue else { return defaultShortcut }
        if storedValue == clearedShortcutStorageValue { return nil }
        return GlobalShortcut(storageValue: storedValue) ?? defaultShortcut
    }

    /// The action's effective shortcut; nil when the user removed it.
    var savedShortcut: GlobalShortcut? {
        Self.resolvedShortcut(storedValue: UserDefaults.standard.string(forKey: shortcutKey),
                              defaultShortcut: defaultShortcut)
    }

    /// Which actions the user hid from the layout grid, parsed from the
    /// stored comma-separated list. Unknown names are dropped, so a value
    /// written by a newer version never corrupts the set. Hiding only
    /// declutters the grid; an assigned shortcut keeps working.
    static func hiddenActions(from storedValue: String) -> Set<WindowLayoutAction> {
        Set(storedValue.split(separator: ",")
            .compactMap { WindowLayoutAction(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }

    /// The storage value for a hidden set: sorted so equal sets always
    /// serialize identically.
    static func hiddenActionsStorageValue(_ actions: Set<WindowLayoutAction>) -> String {
        actions.map(\.rawValue).sorted().joined(separator: ",")
    }

    func title(_ text: WindowLayoutFeatureStrings) -> String {
        switch self {
        case .leftHalf: return text.leftHalf
        case .rightHalf: return text.rightHalf
        case .topHalf: return text.topHalf
        case .bottomHalf: return text.bottomHalf
        case .topLeft: return text.topLeft
        case .topRight: return text.topRight
        case .bottomLeft: return text.bottomLeft
        case .bottomRight: return text.bottomRight
        case .maximize: return text.maximize
        case .marginMaximize: return text.marginMaximize
        case .fullScreen: return text.fullScreen
        case .center: return text.center
        case .restore: return text.restore
        case .leftThird: return text.leftThird
        case .centerThird: return text.centerThird
        case .rightThird: return text.rightThird
        case .leftTwoThirds: return text.leftTwoThirds
        case .rightTwoThirds: return text.rightTwoThirds
        case .topLeftSixth: return text.topLeftSixth
        case .topCenterSixth: return text.topCenterSixth
        case .topRightSixth: return text.topRightSixth
        case .bottomLeftSixth: return text.bottomLeftSixth
        case .bottomCenterSixth: return text.bottomCenterSixth
        case .bottomRightSixth: return text.bottomRightSixth
        case .previousDisplay: return text.previousDisplay
        case .nextDisplay: return text.nextDisplay
        }
    }

    /// Shared by every place that presents an individual placement action.
    var symbolName: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.inset.filled"
        case .rightHalf: return "rectangle.righthalf.inset.filled"
        case .leftThird: return "rectangle.leftthird.inset.filled"
        case .rightThird: return "rectangle.rightthird.inset.filled"
        case .topHalf: return "rectangle.topthird.inset.filled"
        case .bottomHalf: return "rectangle.bottomthird.inset.filled"
        case .centerThird: return "rectangle.center.inset.filled"
        case .leftTwoThirds: return "rectangle.leadinghalf.filled"
        case .rightTwoThirds: return "rectangle.trailinghalf.filled"
        case .topLeftSixth, .topLeft: return "arrow.up.left"
        case .topCenterSixth: return "arrow.up"
        case .topRightSixth, .topRight: return "arrow.up.right"
        case .bottomLeftSixth, .bottomLeft: return "arrow.down.left"
        case .bottomCenterSixth: return "arrow.down"
        case .bottomRightSixth, .bottomRight: return "arrow.down.right"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .marginMaximize: return "rectangle.inset.filled"
        case .fullScreen: return "rectangle.fill"
        case .center: return "scope"
        case .previousDisplay: return "arrow.left.to.line"
        case .nextDisplay: return "arrow.right.to.line"
        case .restore: return "arrow.uturn.backward"
        }
    }
}

enum WindowLayoutGeometry {
    /// Points the settle path allows a window to miss its target by. Display
    /// transfer uses the same value to treat a window as filling the source
    /// or flush with an edge, so tuning settle cannot split those checks.
    static let frameTolerance: CGFloat = 8

    static func effectiveAction(for action: WindowLayoutAction,
                                current _: CGRect,
                                visibleFrame _: CGRect,
                                previousAction: WindowLayoutAction? = nil) -> WindowLayoutAction {
        if action == .topHalf, previousAction == .topHalf {
            return .maximize
        }
        return action
    }

    static func rect(for action: WindowLayoutAction,
                     current: CGRect,
                     visibleFrame: CGRect) -> CGRect {
        let halfWidth = visibleFrame.width / 2
        let halfHeight = visibleFrame.height / 2
        let thirdWidth = visibleFrame.width / 3
        let twoThirdsWidth = thirdWidth * 2
        switch action {
        case .leftHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: halfWidth, height: visibleFrame.height).integral
        case .rightHalf:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.minY,
                          width: halfWidth, height: visibleFrame.height).integral
        case .topHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY,
                          width: visibleFrame.width, height: halfHeight).integral
        case .bottomHalf:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: visibleFrame.width, height: halfHeight).integral
        case .leftThird:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: thirdWidth, height: visibleFrame.height).integral
        case .centerThird:
            return CGRect(x: visibleFrame.minX + thirdWidth, y: visibleFrame.minY,
                          width: thirdWidth, height: visibleFrame.height).integral
        case .rightThird:
            return CGRect(x: visibleFrame.maxX - thirdWidth, y: visibleFrame.minY,
                          width: thirdWidth, height: visibleFrame.height).integral
        case .leftTwoThirds:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: twoThirdsWidth, height: visibleFrame.height).integral
        case .rightTwoThirds:
            return CGRect(x: visibleFrame.maxX - twoThirdsWidth, y: visibleFrame.minY,
                          width: twoThirdsWidth, height: visibleFrame.height).integral
        case .topLeftSixth:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY,
                          width: thirdWidth, height: halfHeight).integral
        case .topCenterSixth:
            return CGRect(x: visibleFrame.minX + thirdWidth, y: visibleFrame.midY,
                          width: thirdWidth, height: halfHeight).integral
        case .topRightSixth:
            return CGRect(x: visibleFrame.maxX - thirdWidth, y: visibleFrame.midY,
                          width: thirdWidth, height: halfHeight).integral
        case .bottomLeftSixth:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: thirdWidth, height: halfHeight).integral
        case .bottomCenterSixth:
            return CGRect(x: visibleFrame.minX + thirdWidth, y: visibleFrame.minY,
                          width: thirdWidth, height: halfHeight).integral
        case .bottomRightSixth:
            return CGRect(x: visibleFrame.maxX - thirdWidth, y: visibleFrame.minY,
                          width: thirdWidth, height: halfHeight).integral
        case .topLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.midY,
                          width: halfWidth, height: halfHeight).integral
        case .topRight:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.midY,
                          width: halfWidth, height: halfHeight).integral
        case .bottomLeft:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: halfWidth, height: halfHeight).integral
        case .bottomRight:
            return CGRect(x: visibleFrame.midX, y: visibleFrame.minY,
                          width: halfWidth, height: halfHeight).integral
        case .maximize:
            return visibleFrame.integral
        case .marginMaximize:
            return visibleFrame.insetBy(dx: visibleFrame.width * 0.05,
                                        dy: visibleFrame.height * 0.05).integral
        case .center:
            let width = min(current.width, visibleFrame.width)
            let height = min(current.height, visibleFrame.height)
            return CGRect(x: visibleFrame.midX - width / 2,
                          y: visibleFrame.midY - height / 2,
                          width: width,
                          height: height).integral
        case .previousDisplay, .nextDisplay:
            return current.integral
        case .restore:
            return current.integral
        case .fullScreen:
            // Handled by the system, not by a frame.
            return current.integral
        }
    }

    static func anchoredRect(for action: WindowLayoutAction,
                             targetRect: CGRect,
                             actualSize: CGSize,
                             visibleFrame: CGRect) -> CGRect {
        guard action != .maximize, action != .restore,
              action != .previousDisplay, action != .nextDisplay,
              action != .fullScreen else { return targetRect.integral }

        let size = CGSize(width: max(1, actualSize.width),
                          height: max(1, actualSize.height))
        var origin = targetRect.origin

        switch action {
        case .leftHalf:
            origin.x = targetRect.minX
            origin.y = visibleFrame.minY
        case .rightHalf:
            origin.x = targetRect.maxX - size.width
            origin.y = visibleFrame.minY
        case .topHalf:
            origin.x = visibleFrame.minX
            origin.y = targetRect.maxY - size.height
        case .bottomHalf:
            origin.x = visibleFrame.minX
            origin.y = targetRect.minY
        case .leftThird, .leftTwoThirds:
            origin.x = targetRect.minX
            origin.y = visibleFrame.minY
        case .centerThird:
            origin.x = targetRect.midX - size.width / 2
            origin.y = visibleFrame.minY
        case .rightThird, .rightTwoThirds:
            origin.x = targetRect.maxX - size.width
            origin.y = visibleFrame.minY
        case .topLeftSixth:
            origin.x = targetRect.minX
            origin.y = targetRect.maxY - size.height
        case .topCenterSixth:
            origin.x = targetRect.midX - size.width / 2
            origin.y = targetRect.maxY - size.height
        case .topRightSixth:
            origin.x = targetRect.maxX - size.width
            origin.y = targetRect.maxY - size.height
        case .bottomLeftSixth:
            origin.x = targetRect.minX
            origin.y = targetRect.minY
        case .bottomCenterSixth:
            origin.x = targetRect.midX - size.width / 2
            origin.y = targetRect.minY
        case .bottomRightSixth:
            origin.x = targetRect.maxX - size.width
            origin.y = targetRect.minY
        case .topLeft:
            origin.x = targetRect.minX
            origin.y = targetRect.maxY - size.height
        case .topRight:
            origin.x = targetRect.maxX - size.width
            origin.y = targetRect.maxY - size.height
        case .bottomLeft:
            origin.x = targetRect.minX
            origin.y = targetRect.minY
        case .bottomRight:
            origin.x = targetRect.maxX - size.width
            origin.y = targetRect.minY
        case .marginMaximize, .center:
            origin.x = targetRect.midX - size.width / 2
            origin.y = targetRect.midY - size.height / 2
        case .maximize, .previousDisplay, .nextDisplay, .restore, .fullScreen:
            break
        }

        if size.width <= visibleFrame.width {
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
        } else {
            origin.x = visibleFrame.minX
        }
        if size.height <= visibleFrame.height {
            origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        } else {
            origin.y = visibleFrame.minY
        }
        return CGRect(origin: origin, size: size).integral
    }

    static func accepts(actualRect: CGRect,
                        targetRect: CGRect,
                        action: WindowLayoutAction,
                        anchorTolerance: CGFloat) -> Bool {
        guard actualRect.width > 80, actualRect.height > 80 else { return false }
        let intersection = actualRect.intersection(targetRect)
        let overlap = area(intersection) / max(1, area(targetRect))
        let fullWidth = actualRect.width >= targetRect.width * 0.82
            || (abs(actualRect.minX - targetRect.minX) <= anchorTolerance
                && abs(actualRect.maxX - targetRect.maxX) <= anchorTolerance)
        let fullHeight = actualRect.height >= targetRect.height * 0.82
            || (abs(actualRect.minY - targetRect.minY) <= anchorTolerance
                && abs(actualRect.maxY - targetRect.maxY) <= anchorTolerance)

        switch action {
        case .leftHalf:
            return abs(actualRect.minX - targetRect.minX) <= anchorTolerance
                && fullHeight
                && overlap > 0.45
        case .rightHalf:
            return abs(actualRect.maxX - targetRect.maxX) <= anchorTolerance
                && fullHeight
                && overlap > 0.45
        case .topHalf:
            return abs(actualRect.maxY - targetRect.maxY) <= anchorTolerance
                && fullWidth
                && overlap > 0.45
        case .bottomHalf:
            return abs(actualRect.minY - targetRect.minY) <= anchorTolerance
                && fullWidth
                && overlap > 0.45
        case .leftThird, .leftTwoThirds:
            return abs(actualRect.minX - targetRect.minX) <= anchorTolerance
                && fullHeight
                && overlap > 0.45
        case .centerThird:
            return abs(actualRect.midX - targetRect.midX) <= anchorTolerance
                && fullHeight
                && overlap > 0.45
        case .rightThird, .rightTwoThirds:
            return abs(actualRect.maxX - targetRect.maxX) <= anchorTolerance
                && fullHeight
                && overlap > 0.45
        case .topLeftSixth:
            return abs(actualRect.minX - targetRect.minX) <= anchorTolerance
                && abs(actualRect.maxY - targetRect.maxY) <= anchorTolerance
                && overlap > 0.35
        case .topCenterSixth:
            return abs(actualRect.midX - targetRect.midX) <= anchorTolerance
                && abs(actualRect.maxY - targetRect.maxY) <= anchorTolerance
                && overlap > 0.35
        case .topRightSixth:
            return abs(actualRect.maxX - targetRect.maxX) <= anchorTolerance
                && abs(actualRect.maxY - targetRect.maxY) <= anchorTolerance
                && overlap > 0.35
        case .bottomLeftSixth:
            return abs(actualRect.minX - targetRect.minX) <= anchorTolerance
                && abs(actualRect.minY - targetRect.minY) <= anchorTolerance
                && overlap > 0.35
        case .bottomCenterSixth:
            return abs(actualRect.midX - targetRect.midX) <= anchorTolerance
                && abs(actualRect.minY - targetRect.minY) <= anchorTolerance
                && overlap > 0.35
        case .bottomRightSixth:
            return abs(actualRect.maxX - targetRect.maxX) <= anchorTolerance
                && abs(actualRect.minY - targetRect.minY) <= anchorTolerance
                && overlap > 0.35
        case .topLeft:
            return abs(actualRect.minX - targetRect.minX) <= anchorTolerance
                && abs(actualRect.maxY - targetRect.maxY) <= anchorTolerance
                && overlap > 0.35
        case .topRight:
            return abs(actualRect.maxX - targetRect.maxX) <= anchorTolerance
                && abs(actualRect.maxY - targetRect.maxY) <= anchorTolerance
                && overlap > 0.35
        case .bottomLeft:
            return abs(actualRect.minX - targetRect.minX) <= anchorTolerance
                && abs(actualRect.minY - targetRect.minY) <= anchorTolerance
                && overlap > 0.35
        case .bottomRight:
            return abs(actualRect.maxX - targetRect.maxX) <= anchorTolerance
                && abs(actualRect.minY - targetRect.minY) <= anchorTolerance
                && overlap > 0.35
        case .maximize:
            return overlap > 0.90
        case .marginMaximize:
            return abs(actualRect.midX - targetRect.midX) <= anchorTolerance
                && abs(actualRect.midY - targetRect.midY) <= anchorTolerance
                && overlap > 0.82
        case .center:
            return abs(actualRect.midX - targetRect.midX) <= anchorTolerance
                && abs(actualRect.midY - targetRect.midY) <= anchorTolerance
        case .previousDisplay, .nextDisplay:
            return overlap > 0.72
        case .restore:
            return false
        case .fullScreen:
            return false
        }
    }

    static func rectForDisplay(current: CGRect,
                               sourceVisibleFrame: CGRect,
                               destinationVisibleFrame: CGRect) -> CGRect {
        guard sourceVisibleFrame.width > 0,
              sourceVisibleFrame.height > 0,
              destinationVisibleFrame.width > 0,
              destinationVisibleFrame.height > 0
        else { return current.integral }

        // Scaling by each screen's size stretches a laptop window across an
        // ultrawide and squashes it onto a portrait panel. Keep the current
        // size, only shrinking to fit, and keep the same edge insets rather
        // than spreading leftover space. A window that already fills the
        // source still fills the destination, so Maximize stays Maximize.
        if current.width >= sourceVisibleFrame.width - frameTolerance,
           current.height >= sourceVisibleFrame.height - frameTolerance {
            return destinationVisibleFrame.integral
        }

        let width = min(destinationVisibleFrame.width, max(1, current.width))
        let height = min(destinationVisibleFrame.height, max(1, current.height))
        let x = unscaledOrigin(sourceMin: sourceVisibleFrame.minX,
                               sourceMax: sourceVisibleFrame.maxX,
                               currentMin: current.minX,
                               currentMax: current.maxX,
                               destinationMin: destinationVisibleFrame.minX,
                               destinationMax: destinationVisibleFrame.maxX,
                               size: width,
                               preferMax: false)
        let y = unscaledOrigin(sourceMin: sourceVisibleFrame.minY,
                               sourceMax: sourceVisibleFrame.maxY,
                               currentMin: current.minY,
                               currentMax: current.maxY,
                               destinationMin: destinationVisibleFrame.minY,
                               destinationMax: destinationVisibleFrame.maxY,
                               size: height,
                               preferMax: true)
        let clampedX = min(max(x, destinationVisibleFrame.minX),
                           destinationVisibleFrame.maxX - width)
        let clampedY = min(max(y, destinationVisibleFrame.minY),
                           destinationVisibleFrame.maxY - height)
        return CGRect(x: clampedX, y: clampedY, width: width, height: height).integral
    }

    /// Keeps the inset from the leading edge of an axis, unless the window is
    /// already flush with the trailing one. Horizontal placement prefers the
    /// left so a window in the middle of a laptop does not fly to the middle
    /// of an ultrawide; a right-half stays on the right. Vertical placement
    /// prefers the top (AppKit maxY, under the menu bar) so a full-height
    /// window is not dropped onto the dock of a taller display.
    private static func unscaledOrigin(sourceMin: CGFloat,
                                       sourceMax: CGFloat,
                                       currentMin: CGFloat,
                                       currentMax: CGFloat,
                                       destinationMin: CGFloat,
                                       destinationMax: CGFloat,
                                       size: CGFloat,
                                       preferMax: Bool) -> CGFloat {
        let minInset = currentMin - sourceMin
        let maxInset = sourceMax - currentMax
        let sourceSlack = (sourceMax - sourceMin) - (currentMax - currentMin)
        // Near-zero leftover space makes flush-edge detection a coin flip:
        // a 1pt jitter picks left vs right and becomes a thousand-point
        // jump on an ultrawide. Keep the preferred-edge inset instead;
        // the caller already clamps.
        if sourceSlack <= frameTolerance {
            if preferMax {
                return destinationMax - maxInset - size
            }
            return destinationMin + minInset
        }
        if preferMax {
            if minInset <= frameTolerance, minInset < maxInset {
                return destinationMin + minInset
            }
            return destinationMax - maxInset - size
        }
        if maxInset <= frameTolerance, maxInset < minInset {
            return destinationMax - maxInset - size
        }
        return destinationMin + minInset
    }

    static func adjacentDisplayIndex(currentIndex: Int,
                                     frames: [CGRect],
                                     movingForward: Bool) -> Int? {
        guard frames.count > 1, frames.indices.contains(currentIndex) else { return nil }
        let ordered = frames.indices.sorted { lhsIndex, rhsIndex in
            let lhs = frames[lhsIndex]
            let rhs = frames[rhsIndex]
            if lhs.minX != rhs.minX { return lhs.minX < rhs.minX }
            if lhs.minY != rhs.minY { return lhs.minY < rhs.minY }
            if lhs.width != rhs.width { return lhs.width < rhs.width }
            if lhs.height != rhs.height { return lhs.height < rhs.height }
            return lhsIndex < rhsIndex
        }
        guard let position = ordered.firstIndex(of: currentIndex) else { return nil }
        let destination = (position + (movingForward ? 1 : ordered.count - 1)) % ordered.count
        return ordered[destination]
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        guard !rect.isNull, !rect.isEmpty else { return 0 }
        return rect.width * rect.height
    }

}

struct WindowLayoutFrame: Equatable {
    var origin: CGPoint
    var size: CGSize

    func isClose(to other: WindowLayoutFrame, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance
            && abs(size.height - other.size.height) <= tolerance
    }
}

struct WindowLayoutWindowKey: Hashable {
    let processID: pid_t
    let processLaunchTime: TimeInterval
    let windowID: CGWindowID
}

/// Recent placements for each window. It stays in memory for this app session
/// and is bounded so repeated layout shortcuts cannot grow it indefinitely.
struct WindowLayoutHistory {
    static let perWindowLimit = 20

    private var framesByWindow: [WindowLayoutWindowKey: [WindowLayoutFrame]] = [:]

    mutating func record(_ frame: WindowLayoutFrame, for window: WindowLayoutWindowKey) {
        var frames = framesByWindow[window] ?? []
        frames.append(frame)
        if frames.count > Self.perWindowLimit {
            frames.removeFirst(frames.count - Self.perWindowLimit)
        }
        framesByWindow[window] = frames
    }

    mutating func popPrevious(for window: WindowLayoutWindowKey,
                              current: WindowLayoutFrame) -> WindowLayoutFrame? {
        guard var frames = framesByWindow[window] else { return nil }
        defer {
            if frames.isEmpty {
                framesByWindow.removeValue(forKey: window)
            } else {
                framesByWindow[window] = frames
            }
        }
        while let previous = frames.popLast() {
            if !previous.isClose(to: current, tolerance: 1) {
                return previous
            }
        }
        return nil
    }

    mutating func discardLatest(for window: WindowLayoutWindowKey) {
        guard var frames = framesByWindow[window] else { return }
        frames.removeLast()
        if frames.isEmpty {
            framesByWindow.removeValue(forKey: window)
        } else {
            framesByWindow[window] = frames
        }
    }

    mutating func removeStaleWindows(keeping activeWindows: Set<WindowLayoutWindowKey>) {
        framesByWindow = framesByWindow.filter { activeWindows.contains($0.key) }
    }
}
