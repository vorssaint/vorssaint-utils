// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

struct MenuBarItemDescriptor: Equatable {
    let id: String
    let bundleID: String
    let pid: Int32
    let title: String
    let frame: CGRect
}

enum MenuBarItemSupport {
    static func cocoaFrame(accessibilityFrame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: accessibilityFrame.minX, y: primaryTop - accessibilityFrame.maxY,
               width: accessibilityFrame.width, height: accessibilityFrame.height)
    }

    /// MenuBarAgent can recreate an item's AX identifier when it becomes
    /// visible. Resolve within the same process, and never guess among several
    /// equally named items belonging to that process.
    static func activationIndex(for item: MenuBarItemDescriptor,
                                in current: [MenuBarItemDescriptor]) -> Int? {
        let candidates = current.indices.filter {
            current[$0].bundleID == item.bundleID && current[$0].pid == item.pid
        }
        let titled = candidates.filter { current[$0].title == item.title }
        if let exact = titled.first(where: { current[$0].id == item.id }) { return exact }
        if titled.count == 1 { return titled[0] }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// A physical click fallback must hit the freshly resolved status control,
    /// never a covering window or an adjacent icon.
    static func activationHitMatches(frame: CGRect, itemPID: Int32, hitFrame: CGRect,
                                     hitPID: Int32, menuBarAgentPID: Int32?) -> Bool {
        guard frame.width > 0, frame.height > 0, hitFrame.width > 0, hitFrame.height > 0,
              hitPID == itemPID || hitPID == menuBarAgentPID else { return false }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        return hitFrame.contains(point) && frame.insetBy(dx: -2, dy: -2).contains(hitFrame)
    }

    static func canKeepRecoveryIcon(bundleURL: URL, registeredURL: URL?) -> Bool {
        guard let registeredURL else { return false }
        return bundleURL.standardizedFileURL.resolvingSymlinksInPath()
            == registeredURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func section(at x: CGFloat, hiddenBoundary: CGFloat,
                        alwaysBoundary: CGFloat) -> MenuBarOrganizerSection {
        if x < alwaysBoundary { return .alwaysHidden }
        if x < hiddenBoundary { return .hidden }
        return .visible
    }

    /// An assessment removes hidden items from Accessibility. Keep only items
    /// actually seen before hiding, and only for that same running process.
    static func retainedItems(current: [MenuBarItemDescriptor], previous: [MenuBarItemDescriptor],
                              runningPIDs: Set<Int32>, hiddenBundles: Set<String>) -> [MenuBarItemDescriptor] {
        let currentIDs = Set(current.map(\.id))
        return current + previous.filter { old in
            guard !currentIDs.contains(old.id), runningPIDs.contains(old.pid),
                  hiddenBundles.contains(old.bundleID) else { return false }
            let freshOwner = current.filter { $0.bundleID == old.bundleID && $0.pid == old.pid }
            let oldOwner = previous.filter { $0.bundleID == old.bundleID && $0.pid == old.pid }
            if freshOwner.count == 1 && oldOwner.count == 1 { return false }
            let freshTitle = freshOwner.filter { $0.title == old.title }
            let oldTitle = oldOwner.filter { $0.title == old.title }
            // Replace a recreated control instead of accumulating old copies
            // after each reveal. Preserve distinct icons owned by the same app.
            return freshTitle.count != 1 || oldTitle.count != 1
        }
    }

    static func barFrame(size: CGSize, anchorX: CGFloat, screen: CGRect,
                         menuBarHeight: CGFloat) -> CGRect {
        let width = min(size.width, max(0, screen.width - 16))
        let x = min(max(anchorX - width / 2, screen.minX + 8), screen.maxX - width - 8)
        return CGRect(x: x, y: screen.maxY - menuBarHeight - 6 - size.height,
                      width: width, height: size.height)
    }
}
