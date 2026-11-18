// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Placing a status item by writing "NSStatusItem Preferred Position" before
// creating it follows Ice (https://github.com/jordanbaird/Ice, GPL-3.0).

import AppKit
import QuartzCore

/// The empty, disabled status item that keeps the menu bar's status items
/// out from under the island. It belongs to the island alone: the menu bar
/// item controller never lists it, and the island's menu measurements leave
/// it out.
final class NotchMenuBarGapItem {
    /// A shrinking island hands its room back over about as long as its own
    /// narrowing takes, in steps the menu bar can lay out without strain.
    static let shrinkDuration: CFTimeInterval = 0.3
    private static let stepInterval: TimeInterval = 1.0 / 30

    private var item: NSStatusItem?
    /// The display the gap was placed on and how it was asked to sit.
    private(set) var placedScreen: CGRect?
    private var requested: NotchMenuBarGap?
    private var shrink: (from: CGFloat, to: CGFloat, start: CFTimeInterval)?
    private var shrinkTimer: Timer?

    var isPlaced: Bool { item != nil }

    var windowNumber: Int {
        guard let number = item?.button?.window?.windowNumber, number > 0 else { return -1 }
        return number
    }

    /// Where the gap is drawn now; nil before macOS has placed it.
    var frame: CGRect? {
        guard let frame = item?.button?.window?.frame, frame.width > 0, frame.minY > 0 else { return nil }
        return frame
    }

    /// The gap as last asked for, for measurements made before it is drawn.
    func requestedFrame(barHeight: CGFloat) -> CGRect? {
        guard let requested, let placedScreen else { return nil }
        return requested.frame(on: placedScreen, barHeight: barHeight)
    }

    /// Where the items to its right begin: as drawn, or as asked for.
    var rightEnd: CGFloat? {
        if let frame { return frame.maxX }
        guard let requested, let placedScreen else { return nil }
        return placedScreen.maxX - requested.position
    }

    /// The length the gap is heading for.
    var targetLength: CGFloat? { shrink?.to ?? item?.length }

    /// macOS reads a status item's position only as it appears, so a gap
    /// whose right end has to move is created again. Removing and adding it
    /// in the same turn lays the menu bar out once.
    func place(_ wanted: NotchMenuBarGap, on screen: CGRect) {
        hide()
        let name = NotchMenuBarGap.autosaveName
        let defaults = UserDefaults.standard
        defaults.set(Double(wanted.position), forKey: StatusItemPlacementSupport.preferredPositionKey(for: name))
        // A gap remembered as removed from the bar would never appear.
        defaults.removeObject(forKey: "NSStatusItem Visible \(name)")
        let item = NSStatusBar.system.statusItem(withLength: wanted.length)
        item.autosaveName = name
        item.behavior = []
        if let button = item.button {
            button.title = ""
            button.image = nil
            button.isEnabled = false
            button.setAccessibilityElement(false)
        }
        self.item = item
        placedScreen = screen
        requested = wanted
    }

    /// A wider island takes its room at once, ahead of its own growth; a
    /// narrower one hands it back in steps.
    func setLength(_ length: CGFloat) {
        guard let item, let target = targetLength,
              NotchMenuBarGap.needsLength(current: target, wanted: length) else { return }
        if length > item.length || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            stopShrinking()
            item.length = length
            return
        }
        shrink = (item.length, length, CACurrentMediaTime())
        guard shrinkTimer == nil else { return }
        let timer = Timer(timeInterval: Self.stepInterval, repeats: true) { [weak self] _ in self?.stepShrink() }
        shrinkTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        stepShrink()
    }

    private func stepShrink() {
        guard let item, let shrink else { stopShrinking(); return }
        let progress = min(1, (CACurrentMediaTime() - shrink.start) / Self.shrinkDuration)
        let eased = 1 - pow(1 - progress, 3)
        let length = (shrink.from + (shrink.to - shrink.from) * eased).rounded()
        if progress >= 1 {
            item.length = shrink.to
            stopShrinking()
        } else if NotchMenuBarGap.needsLength(current: item.length, wanted: length) {
            item.length = length
        }
    }

    private func stopShrinking() {
        shrinkTimer?.invalidate()
        shrinkTimer = nil
        shrink = nil
    }

    func hide() {
        stopShrinking()
        placedScreen = nil
        requested = nil
        guard let item else { return }
        self.item = nil
        NSStatusBar.system.removeStatusItem(item)
    }
}
