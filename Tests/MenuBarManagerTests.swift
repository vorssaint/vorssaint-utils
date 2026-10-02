// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum MenuBarManagerTests {
    static func run(_ suite: TestSuite) {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        suite.expect(MenuBarManagerSupport.hiddenLength(
            osMajor: 26, shownMaxX: 1332, screenFrame: display, chrome: 16, observedFloor: nil)
            == MenuBarManagerSupport.offscreenHiddenLength,
            "up to macOS 26 the divider pushes hidden items past the display edge")
        suite.expect(MenuBarManagerSupport.hiddenLength(
            osMajor: 14, shownMaxX: 1332, screenFrame: display, chrome: 16, observedFloor: nil)
            == MenuBarManagerSupport.offscreenHiddenLength,
            "Sonoma uses the same off-screen divider")

        // Measured on macOS 27 with a 1920 point display: the divider's left
        // edge stops at 408, and a divider reaching past it is dropped.
        let length27 = MenuBarManagerSupport.hiddenLength(
            osMajor: 27, shownMaxX: 1332, screenFrame: display, chrome: 16, observedFloor: nil)
        let leftEdge = 1332 - length27 - 16
        suite.expect(leftEdge >= 408 && leftEdge <= 424,
                     "on macOS 27 the divider stops just short of the measured floor")
        suite.expect(length27 < 924,
                     "on macOS 27 the divider stays below the length that got it evicted")

        let secondDisplay = CGRect(x: -1920, y: -267, width: 1920, height: 1080)
        let lengthOnSecond = MenuBarManagerSupport.hiddenLength(
            osMajor: 27, shownMaxX: -588, screenFrame: secondDisplay, chrome: 16, observedFloor: nil)
        suite.expect(lengthOnSecond == length27,
                     "the floor follows the display the divider is on")

        let corrected = MenuBarManagerSupport.hiddenLength(
            osMajor: 27, shownMaxX: 1332, screenFrame: display, chrome: 16, observedFloor: 600)
        suite.expect(1332 - corrected - 16 >= 600,
                     "a floor reported by a clamped frame wins over the estimate")
        suite.expect(MenuBarManagerSupport.hiddenLength(
            osMajor: 27, shownMaxX: 300, screenFrame: display, chrome: 16, observedFloor: nil)
            == MenuBarManagerSupport.materializationLength,
            "a divider already left of the floor never gets a negative length")

        suite.expect(MenuBarManagerSupport.clampedFloor(
            frame: CGRect(x: 408, y: 1049, width: 1116, height: 33), shownMaxX: 1332) == 408,
            "a frame spilling past its shown edge reports the floor it stopped at")
        suite.expect(MenuBarManagerSupport.clampedFloor(
            frame: CGRect(x: 408, y: 1049, width: 916, height: 33), shownMaxX: 1332) == nil,
            "a divider that fits is not treated as clamped")

        suite.expect(MenuBarManagerSupport.seedPosition(
            leftOf: CGRect(x: 1400, y: 1049, width: 129, height: 33), screenFrame: display, gap: 2) == 522,
            "new items are seeded just left of the main icon, counted from the right edge")
        suite.expect(MenuBarManagerSupport.seedPosition(
            leftOf: CGRect(x: 1400, y: 1049, width: 0, height: 33), screenFrame: display, gap: 2) == nil,
            "an unplaced main icon gives no seed")
        suite.expect(MenuBarManagerSupport.seedPosition(
            leftOf: CGRect(x: 3000, y: 1049, width: 40, height: 33), screenFrame: display, gap: 2) == nil,
            "an icon on another display gives no seed for this one")

        suite.expect(MenuBarManagerSupport.wouldHide(
            CGRect(x: 1000, y: 0, width: 40, height: 24), dividerMinX: 1100),
            "the main icon left of the divider would be hidden")
        suite.expect(!MenuBarManagerSupport.wouldHide(
            CGRect(x: 1250, y: 0, width: 40, height: 24), dividerMinX: 1100),
            "the main icon right of the divider stays visible")
        suite.expect(!MenuBarManagerSupport.wouldHide(nil, dividerMinX: 1100),
                     "a main icon out of the bar never blocks hiding")

        suite.expect(MenuBarManagerSupport.pointerIsOnMenuBar(
            CGPoint(x: 900, y: 1070), screenFrames: [display], barHeight: 33),
            "a pointer on the menu bar postpones hiding")
        suite.expect(!MenuBarManagerSupport.pointerIsOnMenuBar(
            CGPoint(x: 900, y: 500), screenFrames: [display], barHeight: 33),
            "a pointer elsewhere lets hiding happen")

        suite.expect(MenuBarManagerSupport.sanitizedRehideSeconds(7) == MenuBarManagerSupport.defaultRehideSeconds
            && MenuBarManagerSupport.sanitizedRehideSeconds(0) == 0
            && MenuBarManagerSupport.sanitizedRehideSeconds(30) == 30,
            "only the offered rehide delays are kept")
        suite.expect(MenuBarManagerSupport.rehideChoices.contains(MenuBarManagerSupport.defaultRehideSeconds),
                     "the default rehide delay is one of the choices")

        // Measured on macOS 27: the system « at x = 1226...1244 on the main
        // display, center 685 points from its right edge; the same bar is
        // drawn on the second display.
        let barHeight: CGFloat = 33
        let chevron: CGFloat = 685
        suite.expect(MenuBarManagerSupport.isOverflowChevronClick(
            CGPoint(x: 1235, y: 1070), clickScreen: display, chevronCenterFromRight: chevron, barHeight: barHeight),
            "a click on the system « counts")
        suite.expect(MenuBarManagerSupport.isOverflowChevronClick(
            CGPoint(x: -685, y: 803), clickScreen: secondDisplay, chevronCenterFromRight: chevron, barHeight: barHeight),
            "a click on the « of the other display counts too")
        suite.expect(!MenuBarManagerSupport.isOverflowChevronClick(
            CGPoint(x: 1270, y: 1070), clickScreen: display, chevronCenterFromRight: chevron, barHeight: barHeight),
            "a click on the neighbouring Vorssaint icon does not reveal")
        suite.expect(!MenuBarManagerSupport.isOverflowChevronClick(
            CGPoint(x: 1235, y: 600), clickScreen: display, chevronCenterFromRight: chevron, barHeight: barHeight),
            "a click below the menu bar does not reveal")
        suite.expect(MenuBarManagerSupport.estimatedChevronCenterFromRight(shownMaxX: 1236, dividerScreen: display) == 684,
                     "without Accessibility the « is expected where the divider ended")

        let zones = MenuBarManagerSupport.overflowChevronZones(
            screens: [display, secondDisplay], mainMaxY: 1080, chevronCenterFromRight: chevron, barHeight: barHeight)
        suite.expect(zones.count == 2
            && zones[0].contains(CGPoint(x: 1235, y: 12))
            && zones[1].contains(CGPoint(x: -685, y: 280))
            && !zones[0].contains(CGPoint(x: 1270, y: 12))
            && !zones[0].contains(CGPoint(x: 1235, y: 60)),
            "the tap claims the « on every display, in top-left coordinates, and nothing else")

        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        suite.expect(AppFeature.menuBarManager.energyProfile
            == (MenuBarManagerSupport.usesOverflowMenu(osMajor: osMajor) ? .mouse : .idle),
            "the « click watch counts as mouse input on macOS 27, where it runs while icons are hidden")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.menuBarManager(language)
            suite.expect(!strings.title.isEmpty && !strings.howTo.isEmpty && !strings.arrowHint.isEmpty
                && !strings.ownIconWarning.isEmpty && !strings.arrowWarning.isEmpty
                && strings.rehideSecondsFormat.contains("%d"),
                "menu bar manager strings are complete for \(language.rawValue)")
        }
    }
}
