// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Vorssaint

final class PanelKeyboardNavigatorTests: XCTestCase {
    private let navigator = PanelKeyboardNavigator.shared
    private let section: PanelSectionID = .keepAwake

    override func setUp() {
        super.setUp()
        navigator.clearFocus()
        navigator.configureTabs([section], active: section, select: { _ in })
        navigator.configureChrome(leading: [.headerFeedback], trailing: [.footerSettings, .footerQuit])
        navigator.configureRowOrder([
            (PanelRowID(section, "first"), .zero),
            (PanelRowID(section, "second"), .zero),
        ])
    }

    func testVerticalNavigationFollowsPanelOrder() {
        XCTAssertFalse(navigator.handleKeyDown(key(kVK_DownArrow)))
        XCTAssertNil(navigator.focus)

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_Tab)))
        XCTAssertEqual(navigator.focus, .tab(section))

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_UpArrow)))
        XCTAssertEqual(navigator.focus, .chrome(.headerFeedback))

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_DownArrow)))
        XCTAssertEqual(navigator.focus, .tab(section))

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_DownArrow)))
        XCTAssertEqual(navigator.focus, .row(PanelRowID(section, "first")))

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_DownArrow)))
        XCTAssertEqual(navigator.focus, .row(PanelRowID(section, "second")))

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_DownArrow)))
        XCTAssertEqual(navigator.focus, .chrome(.footerSettings))
    }

    /// The first press only brings the ring on screen. A single-tab panel
    /// cannot tell that apart from a wrap-around, so this one uses two.
    func testFirstTabPressLandsOnTheActiveSection() {
        var selected: [PanelSectionID] = []
        navigator.clearFocus()
        navigator.configureTabs([.system, .disk], active: .disk, select: { selected.append($0) })

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_Tab)))
        XCTAssertEqual(navigator.focus, .tab(.disk))
        XCTAssertEqual(selected, [.disk])

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_Tab)))
        XCTAssertEqual(navigator.focus, .tab(.system))
        XCTAssertEqual(selected, [.disk, .system])

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_Tab, modifiers: .shift)))
        XCTAssertEqual(navigator.focus, .tab(.disk))
    }

    /// Metric detail reports no tabs, so Tab has no tab bar to cycle and walks
    /// the panel instead of being swallowed.
    func testTabWalksThePanelWhereThereIsNoTabBar() {
        navigator.clearFocus()
        navigator.configureTabs([], active: section, select: { _ in })

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_Tab)))
        XCTAssertEqual(navigator.focus, .chrome(.headerFeedback))

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_Tab)))
        XCTAssertEqual(navigator.focus, .row(PanelRowID(section, "first")))

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_Tab, modifiers: .shift)))
        XCTAssertEqual(navigator.focus, .chrome(.headerFeedback))
    }

    func testHorizontalKeyOnChromeWithNowhereToGoIsNotConsumed() {
        XCTAssertTrue(navigator.handleKeyDown(key(kVK_Tab)))
        XCTAssertTrue(navigator.handleKeyDown(key(kVK_UpArrow)))
        XCTAssertEqual(navigator.focus, .chrome(.headerFeedback))

        XCTAssertFalse(navigator.handleKeyDown(key(kVK_LeftArrow)))
        XCTAssertFalse(navigator.handleKeyDown(key(kVK_RightArrow)))
        XCTAssertEqual(navigator.focus, .chrome(.headerFeedback))
    }

    func testFooterLeftAndRightMoveBetweenFooterControls() {
        navigator.focusRow(PanelRowID(section, "second"))
        XCTAssertTrue(navigator.handleKeyDown(key(kVK_DownArrow)))
        XCTAssertEqual(navigator.focus, .chrome(.footerSettings))

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_RightArrow)))
        XCTAssertEqual(navigator.focus, .chrome(.footerQuit))

        XCTAssertTrue(navigator.handleKeyDown(key(kVK_LeftArrow)))
        XCTAssertEqual(navigator.focus, .chrome(.footerSettings))
    }

    func testFocusedRowReceivesFineAndRegularAdjustments() {
        var adjustments: [(PanelAdjustDirection, Bool)] = []
        let row = PanelRowID(section, "first")
        navigator.registerRow(row, actions: PanelRowActions(adjust: { direction, fine in
            adjustments.append((direction, fine))
            return true
        }))
        defer { navigator.unregisterRow(row) }

        navigator.focusRow(row)
        XCTAssertTrue(navigator.handleKeyDown(key(kVK_LeftArrow, modifiers: .shift)))
        XCTAssertTrue(navigator.handleKeyDown(key(kVK_RightArrow)))
        XCTAssertEqual(adjustments.count, 2)
        XCTAssertEqual(adjustments[0].0, .decrease)
        XCTAssertTrue(adjustments[0].1)
        XCTAssertEqual(adjustments[1].0, .increase)
        XCTAssertFalse(adjustments[1].1)
    }

    func testUnhandledHorizontalKeyIsNotConsumed() {
        let row = PanelRowID(section, "first")
        navigator.registerRow(row, actions: PanelRowActions(activate: {}))
        defer { navigator.unregisterRow(row) }

        navigator.focusRow(row)
        XCTAssertFalse(navigator.handleKeyDown(key(kVK_LeftArrow)))
        XCTAssertFalse(navigator.handleKeyDown(key(kVK_RightArrow)))
    }

    func testAdjustmentBoundaryIsNotConsumed() {
        let row = PanelRowID(section, "first")
        navigator.registerRow(row, actions: PanelRowActions(adjust: { _, _ in false }))
        defer { navigator.unregisterRow(row) }

        navigator.focusRow(row)
        XCTAssertFalse(navigator.handleKeyDown(key(kVK_LeftArrow)))
        XCTAssertFalse(navigator.handleKeyDown(key(kVK_RightArrow)))
    }

    func testActivationWithoutActionIsNotConsumed() {
        let row = PanelRowID(section, "first")
        navigator.registerRow(row, actions: PanelRowActions(adjust: { _, _ in true }))
        defer { navigator.unregisterRow(row) }

        navigator.focusRow(row)
        XCTAssertFalse(navigator.handleKeyDown(key(kVK_Return)))
        XCTAssertFalse(navigator.handleKeyDown(key(kVK_Space)))

        navigator.focusRow(PanelRowID(section, "second"))
        XCTAssertTrue(navigator.handleKeyDown(key(kVK_DownArrow)))
        XCTAssertEqual(navigator.focus, .chrome(.footerSettings))
        XCTAssertFalse(navigator.handleKeyDown(key(kVK_Return)))
        XCTAssertFalse(navigator.handleKeyDown(key(kVK_Space)))
    }

    private func key(_ keyCode: Int, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown,
                         location: .zero,
                         modifierFlags: modifiers,
                         timestamp: 0,
                         windowNumber: 0,
                         context: nil,
                         characters: "",
                         charactersIgnoringModifiers: "",
                         isARepeat: false,
                         keyCode: UInt16(keyCode))!
    }
}
