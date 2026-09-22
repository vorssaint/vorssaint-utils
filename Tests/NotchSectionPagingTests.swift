// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

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
    }
}
