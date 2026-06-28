// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowLayoutAction: String, CaseIterable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, center, nextDisplay, restore

    var id: String { rawValue }

    static let shortcutActions: [WindowLayoutAction] = [
        .leftHalf, .rightHalf, .topHalf, .bottomHalf,
        .topLeft, .topRight, .bottomLeft, .bottomRight,
        .maximize, .center, .restore,
    ]

    var supportsShortcut: Bool {
        Self.shortcutActions.contains(self)
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
        case .center: return DefaultsKey.windowLayoutShortcutCenter
        case .restore: return DefaultsKey.windowLayoutShortcutRestore
        case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds, .nextDisplay:
            return ""
        }
    }

    var defaultShortcut: GlobalShortcut {
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
        case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds, .nextDisplay:
            return .windowLayoutCenterDefault
        }
    }

    var savedShortcut: GlobalShortcut {
        GlobalShortcut.saved(for: shortcutKey, fallback: defaultShortcut)
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
        case .center: return text.center
        case .restore: return text.restore
        case .leftThird: return text.leftThird
        case .centerThird: return text.centerThird
        case .rightThird: return text.rightThird
        case .leftTwoThirds: return text.leftTwoThirds
        case .rightTwoThirds: return text.rightTwoThirds
        case .nextDisplay: return text.nextDisplay
        }
    }
}

enum WindowLayoutGeometry {
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
        case .center:
            let width = min(current.width, visibleFrame.width)
            let height = min(current.height, visibleFrame.height)
            return CGRect(x: visibleFrame.midX - width / 2,
                          y: visibleFrame.midY - height / 2,
                          width: width,
                          height: height).integral
        case .nextDisplay:
            return current.integral
        case .restore:
            return current.integral
        }
    }

    static func anchoredRect(for action: WindowLayoutAction,
                             targetRect: CGRect,
                             actualSize: CGSize,
                             visibleFrame: CGRect) -> CGRect {
        guard action != .maximize, action != .restore, action != .nextDisplay else { return targetRect.integral }

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
        case .center:
            origin.x = targetRect.midX - size.width / 2
            origin.y = targetRect.midY - size.height / 2
        case .maximize, .nextDisplay, .restore:
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
        case .center:
            return abs(actualRect.midX - targetRect.midX) <= anchorTolerance
                && abs(actualRect.midY - targetRect.midY) <= anchorTolerance
        case .nextDisplay:
            return overlap > 0.72
        case .restore:
            return false
        }
    }

    static func rectForNextDisplay(current: CGRect,
                                   sourceVisibleFrame: CGRect,
                                   destinationVisibleFrame: CGRect) -> CGRect {
        guard sourceVisibleFrame.width > 0,
              sourceVisibleFrame.height > 0,
              destinationVisibleFrame.width > 0,
              destinationVisibleFrame.height > 0
        else { return current.integral }

        let widthRatio = min(max(current.width / sourceVisibleFrame.width, 0.08), 1)
        let heightRatio = min(max(current.height / sourceVisibleFrame.height, 0.08), 1)
        let xRatio = (current.minX - sourceVisibleFrame.minX) / sourceVisibleFrame.width
        let yRatio = (current.minY - sourceVisibleFrame.minY) / sourceVisibleFrame.height

        let width = min(destinationVisibleFrame.width, max(1, destinationVisibleFrame.width * widthRatio))
        let height = min(destinationVisibleFrame.height, max(1, destinationVisibleFrame.height * heightRatio))
        let unclampedX = destinationVisibleFrame.minX + destinationVisibleFrame.width * xRatio
        let unclampedY = destinationVisibleFrame.minY + destinationVisibleFrame.height * yRatio
        let x = min(max(unclampedX, destinationVisibleFrame.minX), destinationVisibleFrame.maxX - width)
        let y = min(max(unclampedY, destinationVisibleFrame.minY), destinationVisibleFrame.maxY - height)

        return CGRect(x: x, y: y, width: width, height: height).integral
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        guard !rect.isNull, !rect.isEmpty else { return 0 }
        return rect.width * rect.height
    }

}
