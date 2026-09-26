// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum NotchSectionPagingTests {
    static func run(_ suite: TestSuite) {
        suite.expect(NotchSectionPaging.rows(count: 14, columns: 4) == 4 && NotchSectionPaging.rows(count: 12, columns: 4) == 3
               && NotchSectionPaging.rows(count: 0, columns: 4) == 1 && NotchSectionPaging.rows(count: 5, columns: 0) == 5,
               "rows round the last partial row up and never vanish")
        suite.expect(NotchSectionPaging.positions(rows: 4, visible: 3) == 2 && NotchSectionPaging.positions(rows: 2, visible: 3) == 1
               && NotchSectionPaging.positions(rows: 5, visible: 1) == 5 && NotchSectionPaging.positions(rows: 4, visible: 0) == 4,
               "a gallery rests on as many rows as can lead the visible ones")
        suite.expect(NotchSectionPaging.clamped(5, rows: 4, visible: 3) == 1 && NotchSectionPaging.clamped(-1, rows: 4, visible: 3) == 0
               && NotchSectionPaging.clamped(1, rows: 4, visible: 3) == 1,
               "the first row never rests past the last position")
        suite.expect(NotchSectionPaging.revealing(row: 3, first: 0, rows: 4, visible: 3) == 1
               && NotchSectionPaging.revealing(row: 0, first: 1, rows: 4, visible: 3) == 0
               && NotchSectionPaging.revealing(row: 1, first: 0, rows: 4, visible: 3) == 0
               && NotchSectionPaging.revealing(row: 2, first: 1, rows: 4, visible: 3) == 1
               && NotchSectionPaging.revealing(row: 4, first: 0, rows: 5, visible: 1) == 4
               && NotchSectionPaging.revealing(row: 2, first: 9, rows: 4, visible: 3) == 1,
               "a highlighted row comes into view with the least movement, from a clamped start")

        var scroll = NotchSectionScroll()
        var time = 10.0
        func feed(_ y: Double, began: Bool = false, ended: Bool = false, momentum: Bool = false,
                  precise: Bool = true, phased: Bool = true, after gap: TimeInterval = 0.01) -> Int {
            time += gap
            return scroll.steps(deltaY: y, timestamp: time, precise: precise, hasPhase: phased,
                                began: began, ended: ended, momentum: momentum)
        }
        suite.expect(feed(0, began: true) == 0 && feed(-5) == 0 && feed(-10) == 0 && feed(-10) == 1,
               "a short downward movement accumulates into one row below, matching the island's gesture distance")
        suite.expect(feed(-50) == 0 && feed(-50) == 1,
               "further rows in the same drag follow the row pitch rather than the short first step")
        suite.expect(feed(-300) == 3, "a long continuous drag steps several rows at once")
        suite.expect(feed(0, ended: true) == 0 && feed(-400, momentum: true) == 0 && feed(-400, momentum: true) == 0,
               "momentum after lifting the fingers never moves another row")
        suite.expect(feed(-30, began: true) == 1 && feed(30) == -1,
               "turning back answers with the short first step again, revealing the row above")
        for sign in [-1, 1] {
            for (distance, rows) in [(23.0, 0), (24.0, 1), (25.0, 1), (118.0, 2)] {
                suite.expect(feed(Double(sign) * distance, began: true) == -sign * rows
                       && feed(0) == 0 && feed(Double(-sign) * 24) == sign,
                       "reversing resets the first step in either direction, even with zero distance left after \(distance) points")
            }
            suite.expect(feed(Double(sign) * 24, began: true) == -sign
                   && feed(0) == 0 && feed(Double(sign) * 24) == 0
                   && feed(Double(sign) * 70) == -sign,
                   "zero remainder and resting fingers preserve the longer pitch when continuing in the same direction")
        }
        suite.expect(feed(0, ended: true) == 0 && feed(-20, began: true) == 0 && feed(0) == 0 && feed(-3) == 0 && feed(-2) == 1,
               "resting fingers and sideways events keep the accumulated distance")
        suite.expect(feed(-1, precise: false, phased: false) == 1 && feed(3, precise: false, phased: false) == -1
               && feed(0, precise: false, phased: false) == 0,
               "each wheel notch steps one row in its direction")
        suite.expect(feed(-8, phased: false) == 0 && feed(-8, phased: false) == 0 && feed(-8, phased: false) == 1
               && feed(-8, phased: false) == 0,
               "a smoothed wheel glide steps once for its notch")
        suite.expect(feed(-8, phased: false, after: 0.5) == 0 && feed(-8, phased: false) == 0 && feed(-8, phased: false) == 1,
               "a paused glide sequence starts over, so the next notch steps its own row")
        suite.expect(feed(-100, phased: false) == 1 && feed(-100, phased: false, after: -1) == 1,
               "a clock that runs backwards starts a fresh sequence instead of stalling")
        suite.expect(feed(.nan) == 0 && feed(-24, began: true) == 1,
               "an unreadable delta resets the sequence and the next gesture begins cleanly")
        suite.expect(feed(-10, began: true) == 0 && feed(-10, began: true) == 0 && feed(-10) == 0 && feed(-5) == 1,
               "a new beginning discards the previous gesture's distance")
        routing(suite)
    }

    // The generated Service uses the production scroll handlers verbatim.
    // Events stay inside this fixture and never post input to the desktop.
    struct NSEvent {
        var locationInWindow: CGPoint
        var scrollingDeltaY: CGFloat = -24
        var timestamp: TimeInterval = 10
        var hasPreciseScrollingDeltas = true
        var phase: AppKit.NSEvent.Phase = .began
        var momentumPhase: AppKit.NSEvent.Phase = []
        var modifierFlags: AppKit.NSEvent.ModifierFlags = []
    }
    final class Panel {
        let frame = CGRect(x: 173, y: 127, width: 600, height: 260)
        func convertPoint(toScreen point: CGPoint) -> CGPoint {
            CGPoint(x: frame.minX + point.x, y: frame.minY + point.y)
        }
    }
    final class Host {
        var acceptsPoint = true
        func containsSurface(_ point: CGPoint) -> Bool { acceptsPoint }
    }
    class State {
        var running = true, suspended = false, expanded = true, showingSections = true, trackingMenu = false
        var panel: Panel? = Panel()
        var windowHost: Host? = Host()
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                     safeAreaTop: 32, cameraWidth: 180)
        var expandedGeometry: NotchGeometry { geometry }
        var sectionScroll = NotchSectionScroll()
        var movedRows = 0, gestureCalls = 0
        func scrollSections(by rows: Int) { movedRows += rows }
        func handleGesture(_ event: NSEvent) -> Bool { gestureCalls += 1; return false }
    }

    private static func routing(_ suite: TestSuite) {
        for (width, cameraHeight) in [(600.0, 32.0), (400.0, 32.0), (600.0, 0.0), (600.0, 52.0)] {
            let service = Service()
            service.geometry = NotchGeometry(screen: service.geometry.screen, safeAreaTop: cameraHeight,
                                             cameraWidth: 180, layout: .custom, customWidth: width, customHeight: 260)
            let headerBottom = service.expandedGeometry.headerTopInset + service.expandedGeometry.headerRowHeight
            func event(fromTop top: CGFloat) -> NSEvent {
                NSEvent(locationInWindow: CGPoint(x: 100, y: service.panel!.frame.height - top))
            }
            suite.expect(!service.handleScroll(event(fromTop: headerBottom))
                         && service.gestureCalls == 1 && service.movedRows == 0,
                         "the actual header keeps its gesture for width \(width) and camera height \(cameraHeight)")
            for offset in [1.0, NotchLayout.spacing + 1, NotchLayout.spacing + NotchLayout.sectionTileHeight / 2] {
                let before = service.movedRows
                let gestures = service.gestureCalls
                suite.expect(service.handleScroll(event(fromTop: headerBottom + offset))
                             && service.movedRows == before + 1 && service.gestureCalls == gestures,
                             "every part of the body steps rows below the rendered header, including the top of the first tile")
            }
            var modified = event(fromTop: headerBottom + 20)
            modified.modifierFlags = .command
            let before = service.movedRows
            suite.expect(!service.handleScroll(modified) && service.movedRows == before,
                         "modified scrolling is not captured by the gallery")
            service.windowHost?.acceptsPoint = false
            suite.expect(!service.handleScroll(event(fromTop: headerBottom + 20)) && service.movedRows == before,
                         "transparent corners and floating controls are not captured by the gallery")
        }
    }
}
