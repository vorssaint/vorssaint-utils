// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowEdgeSnapRestoreTests {
    static func run(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.windowEdgeSnapRestoreOnDrag] as? Bool == false,
                     "restoring the size on a drag away stays off until it is turned on")

        let maximized = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let earlier = CGSize(width: 800, height: 500)

        suite.expect(WindowEdgeSnapSupport.needsSizeRestore(from: maximized.size, to: earlier),
                     "a snapped window that differs from its earlier size is restored")
        suite.expect(!WindowEdgeSnapSupport.needsSizeRestore(from: earlier, to: CGSize(width: 801, height: 499)),
                     "a size within the tolerance is left alone")
        suite.expect(!WindowEdgeSnapSupport.needsSizeRestore(from: maximized.size, to: .zero),
                     "an empty remembered size is never restored")

        let middle = WindowEdgeSnapSupport.restoredFrame(snapped: maximized,
                                                         restoreSize: earlier,
                                                         pointerStart: CGPoint(x: 720, y: 40),
                                                         pointerNow: CGPoint(x: 800, y: 60),
                                                         screenFrame: screen)
        suite.expect(middle == CGRect(x: 400, y: 45, width: 800, height: 500),
                     "the pointer keeps its relative spot on the title bar and its depth below the top")

        let leftEnd = WindowEdgeSnapSupport.restoredFrame(snapped: maximized,
                                                          restoreSize: earlier,
                                                          pointerStart: CGPoint(x: 0, y: 40),
                                                          pointerNow: CGPoint(x: 30, y: 60),
                                                          screenFrame: screen)
        suite.expect(leftEnd.minX == 30 && leftEnd.minY == 45,
                     "a grab at the left end of the title bar keeps the window at the pointer's left")

        let rightEnd = WindowEdgeSnapSupport.restoredFrame(snapped: maximized,
                                                           restoreSize: earlier,
                                                           pointerStart: CGPoint(x: 1440, y: 40),
                                                           pointerNow: CGPoint(x: 1400, y: 60),
                                                           screenFrame: screen)
        suite.expect(rightEnd.maxX == 1400 && rightEnd.minY == 45,
                     "a grab at the right end of the title bar keeps the window at the pointer's right")

        let pastRight = WindowEdgeSnapSupport.restoredFrame(snapped: maximized,
                                                            restoreSize: earlier,
                                                            pointerStart: CGPoint(x: 1440, y: 40),
                                                            pointerNow: CGPoint(x: 1300, y: 60),
                                                            screenFrame: CGRect(x: 0, y: 0, width: 1320, height: 900))
        suite.expect(pastRight.maxX <= 1320 && pastRight.minX >= 0,
                     "the restored window stays inside the display under the pointer")

        let nextDisplay = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let overThere = WindowEdgeSnapSupport.restoredFrame(snapped: maximized,
                                                            restoreSize: earlier,
                                                            pointerStart: CGPoint(x: 720, y: 40),
                                                            pointerNow: CGPoint(x: 1500, y: 60),
                                                            screenFrame: nextDisplay)
        suite.expect(overThere.minX >= nextDisplay.minX && overThere.minY == 45,
                     "a pointer that crossed to another display clamps to that display")

        let tooTall = WindowEdgeSnapSupport.restoredFrame(snapped: maximized,
                                                          restoreSize: CGSize(width: 800, height: 20),
                                                          pointerStart: CGPoint(x: 720, y: 400),
                                                          pointerNow: CGPoint(x: 800, y: 500),
                                                          screenFrame: screen)
        suite.expect(tooTall.minY >= 480 && tooTall.contains(CGPoint(x: 800, y: tooTall.maxY - 1)),
                     "a grab deeper than the restored height stays on the window")

        let noScreen = WindowEdgeSnapSupport.restoredFrame(snapped: maximized,
                                                           restoreSize: earlier,
                                                           pointerStart: CGPoint(x: 720, y: 40),
                                                           pointerNow: CGPoint(x: 800, y: 60),
                                                           screenFrame: nil)
        suite.expect(noScreen == middle,
                     "without a known display the pointer position alone places the window")
    }
}
