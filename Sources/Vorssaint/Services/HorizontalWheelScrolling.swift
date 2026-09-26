// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Lets a mouse wheel move the strips that only scroll sideways: the island's
/// mixer and rails, the switcher, wallpaper and chip rows. Without it their
/// hidden items could only be reached with a trackpad or Shift.
enum HorizontalWheelScrolling {
    private static var monitor: Any?
    private static var lastGesturePhaseTimestamp: TimeInterval?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // The island first offers the wheel to its own gestures.
            guard !(event.window is NotchPanel) else { return event }
            return handle(event) ? nil : event
        }
    }

    /// Scrolls the strip under the pointer sideways and reports whether the
    /// event was used.
    static func handle(_ event: NSEvent) -> Bool {
        guard event.type == .scrollWheel, let cgEvent = event.cgEvent else { return false }
        let traits = ScrollWheelEventTraits(
            isContinuous: cgEvent.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: cgEvent.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: cgEvent.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: cgEvent.getIntegerValueField(.scrollWheelEventScrollCount))
        let secondsSinceGesturePhase = lastGesturePhaseTimestamp.map { event.timestamp - $0 }
        if traits.momentumPhase != 0 || traits.scrollPhase != 0 { lastGesturePhaseTimestamp = event.timestamp }
        // Trackpads swipe sideways on their own; modifier combinations keep
        // their meaning, Shift already turning the wheel sideways.
        guard ScrollWheelSupport.isMouseWheel(traits, secondsSinceLastGesturePhase: secondsSinceGesturePhase),
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              ScrollWheelSupport.isVerticalOnly(cgEvent),
              let contentView = event.window?.contentView,
              let hit = contentView.hitTest(
                contentView.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow),
              let strip = sidewaysStrip(at: hit) else { return false }
        return scroll(strip, sideways: cgEvent)
    }

    /// The strip holding `view`, when it scrolls only sideways and nothing
    /// around it scrolls down.
    static func sidewaysStrip(at view: NSView) -> NSScrollView? {
        guard let strip = (view as? NSScrollView) ?? view.enclosingScrollView else { return nil }
        var enclosing = strip.superview?.enclosingScrollView
        var enclosingScrollsVertically = false
        while let outer = enclosing, !enclosingScrollsVertically {
            enclosingScrollsVertically = scrolls(outer, vertically: true)
            enclosing = outer.superview?.enclosingScrollView
        }
        return ScrollWheelSupport.wheelMovesStripSideways(
            stripScrollsHorizontally: scrolls(strip, vertically: false),
            stripScrollsVertically: scrolls(strip, vertically: true),
            enclosingScrollsVertically: enclosingScrollsVertically) ? strip : nil
    }

    static func scroll(_ strip: NSScrollView, sideways event: CGEvent) -> Bool {
        guard let sideways = event.copy() else { return false }
        ScrollWheelSupport.moveVerticalToHorizontal(sideways)
        guard let converted = NSEvent(cgEvent: sideways) else { return false }
        strip.scrollWheel(with: converted)
        return true
    }

    private static func scrolls(_ view: NSScrollView, vertically: Bool) -> Bool {
        guard let document = view.documentView else { return false }
        let visible = view.contentView.bounds
        return vertically
            ? document.frame.height > visible.height + 1
            : document.frame.width > visible.width + 1
    }
}
