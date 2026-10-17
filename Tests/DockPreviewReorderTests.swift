// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The arrangement a run is given by hand: which slot the pointer names, how
/// the arrangement survives windows coming and going, and when the panel is
/// too small to read a slot from its own edge.
enum DockPreviewReorderTests {
    private static func item(_ id: CGWindowID) -> SwitcherItem {
        SwitcherItem(id: "window-\(id)",
                     title: "Window \(id)",
                     appName: "App",
                     pid: 1,
                     windowOwnerPID: 1,
                     windowID: id,
                     isOnScreen: true,
                     isAppHidden: false,
                     isMinimized: false,
                     isFullscreen: false,
                     isOnHiddenSpace: false,
                     frame: .zero)
    }

    static func run(_ suite: TestSuite) {
        let windows = [item(1), item(2), item(3), item(4)]

        suite.expect(DockPreviewSupport.applyingManualOrder(windows, ids: []).map(\.windowID)
               == [1, 2, 3, 4],
               "a run nobody has arranged keeps the order its rule gave it")
        suite.expect(DockPreviewSupport.applyingManualOrder(windows, ids: [3, 1]).map(\.windowID)
               == [3, 1, 2, 4],
               "the windows arranged by hand lead, and the rest follow in their own order")
        suite.expect(DockPreviewSupport.applyingManualOrder(windows, ids: [9, 3]).map(\.windowID)
               == [3, 1, 2, 4],
               "a window that has closed drops out of the arrangement instead of leaving a gap")
        suite.expect(DockPreviewSupport.applyingManualOrder([], ids: [1, 2]).isEmpty,
               "an arrangement for an app with nothing open produces nothing")

        // A run of four cards along the bottom, laid out from the panel's
        // leading padding at the step the cards are placed with.
        let step = DockPreviewSupport.cardWidth + DockPreviewSupport.cardSpacing
        let width = DockPreviewSupport.panelPadding * 2 + step * 4 - DockPreviewSupport.cardSpacing
        let frame = CGRect(x: 100, y: 40, width: width, height: DockPreviewSupport.cardHeight + 20)
        func slot(atCard index: Int) -> Int {
            DockPreviewSupport.reorderIndex(
                pointer: CGPoint(x: frame.minX + DockPreviewSupport.panelPadding
                                    + step * CGFloat(index) + DockPreviewSupport.cardWidth / 2,
                                 y: frame.midY),
                panelFrame: frame, count: 4, stacksVertically: false)
        }
        suite.expect((0..<4).allSatisfy { slot(atCard: $0) == $0 },
               "the pointer over a card names that card's slot along a horizontal run")
        suite.expect(DockPreviewSupport.reorderIndex(pointer: CGPoint(x: frame.minX - 400, y: frame.midY),
                                                     panelFrame: frame, count: 4,
                                                     stacksVertically: false) == 0
               && DockPreviewSupport.reorderIndex(pointer: CGPoint(x: frame.maxX + 400, y: frame.midY),
                                                  panelFrame: frame, count: 4,
                                                  stacksVertically: false) == 3,
               "a pointer past either end of the run names the slot at that end")
        suite.expect(DockPreviewSupport.reorderIndex(pointer: CGPoint(x: frame.midX, y: frame.midY),
                                                     panelFrame: frame, count: 1,
                                                     stacksVertically: false) == 0,
               "a run of one window has only one slot to name")

        // A vertical run hangs from the panel's top edge, which AppKit counts
        // down from.
        let verticalStep = DockPreviewSupport.cardHeight + DockPreviewSupport.cardSpacing
        let height = DockPreviewSupport.panelPadding * 2 + verticalStep * 3 - DockPreviewSupport.cardSpacing
        let column = CGRect(x: 0, y: 200, width: DockPreviewSupport.cardWidth + 20, height: height)
        let topSlot = DockPreviewSupport.reorderIndex(
            pointer: CGPoint(x: column.midX, y: column.maxY - DockPreviewSupport.panelPadding - 1),
            panelFrame: column, count: 3, stacksVertically: true)
        let bottomSlot = DockPreviewSupport.reorderIndex(
            pointer: CGPoint(x: column.midX, y: column.minY + DockPreviewSupport.panelPadding + 1),
            panelFrame: column, count: 3, stacksVertically: true)
        suite.expect(topSlot == 0 && bottomSlot == 2,
               "a vertical run reads its first slot at the top and its last at the bottom")

        suite.expect(DockPreviewSupport.showsWholeRun(panelFrame: frame, count: 4,
                                                      stacksVertically: false),
               "a panel sized for its run shows every card")
        suite.expect(!DockPreviewSupport.showsWholeRun(panelFrame: frame, count: 5,
                                                       stacksVertically: false),
               "one card more than the panel was sized for means the run scrolls")
        suite.expect(DockPreviewSupport.showsWholeRun(panelFrame: .zero, count: 1,
                                                      stacksVertically: false),
               "a single card is always whole, whatever the panel measures")
    }
}
