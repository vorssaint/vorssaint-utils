// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

enum MenuBarTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

        let registeredDefaults = Defaults.registeredDefaults
        expect(Defaults.sanitizedMenuBarMetricSpacing("standard") == "standard",
               "standard menu bar spacing is a valid stored choice")
        expect(Defaults.sanitizedMenuBarMetricSpacing("banana") == "compact",
               "unknown menu bar spacing values fall back to the compact default")
        expect(Defaults.sanitizedMenuBarMetricAppearance("bars") == "bars",
               "bar appearance is a valid stored choice")
        expect(Defaults.sanitizedMenuBarMetricAppearance("banana") == "values",
               "unknown menu bar appearances fall back to numeric values")
        expect(MenuBarMetricAppearance.values.allowsCombinedTemperatures,
               "numeric menu bar values may combine usage and temperature")
        expect(!MenuBarMetricAppearance.bars.allowsCombinedTemperatures,
               "menu bar bars keep usage and temperature separate")
        expectClose(MenuBarUsageBarSupport.memoryFraction(used: 3, total: 4) ?? -1, 0.75,
                    "menu bar memory bars use the current used fraction")
        expect(MenuBarUsageBarSupport.memoryFraction(used: 3, total: 0) == nil,
               "menu bar memory bars keep missing totals unavailable")
        expectClose(MenuBarUsageBarSupport.clampedFraction(-0.2), 0,
                    "menu bar bars clamp negative readings")
        expectClose(MenuBarUsageBarSupport.clampedFraction(1.4), 1,
                    "menu bar bars clamp readings above full")
        expect(MenuBarUsageBarSupport.fillLevel(for: 0.5, steps: 16) == 8,
               "menu bar bars quantize fractions to visible fill steps")
        expect(MenuBarUsageBarSupport.level(for: 0.69) == .normal,
               "menu bar usage stays blue below seventy percent")
        expect(MenuBarUsageBarSupport.level(for: 0.70) == .elevated,
               "menu bar usage turns yellow at seventy percent")
        expect(MenuBarUsageBarSupport.level(for: 0.89) == .elevated,
               "menu bar usage stays yellow below ninety percent")
        expect(MenuBarUsageBarSupport.level(for: 0.90) == .critical,
               "menu bar usage turns red at ninety percent")
        expect(MenuBarUsageBarSupport.level(for: 0.50,
                                            mediumPercent: 40,
                                            highPercent: 80) == .elevated,
               "custom menu bar medium thresholds change the bar level")
        expect(MenuBarUsageBarSupport.level(for: 0.80,
                                            mediumPercent: 40,
                                            highPercent: 80) == .critical,
               "custom menu bar high thresholds change the bar level")
        let repairedBarThresholds = MenuBarUsageBarSupport.thresholds(medium: 100, high: 20)
        expect(repairedBarThresholds.medium == 99 && repairedBarThresholds.high == 100,
               "invalid menu bar thresholds keep medium below high")
        expect(MenuBarUsageBarSupport.sanitizedColorHex(" 64d2ff ", fallback: "#000000") == "#64D2FF",
               "menu bar colors normalize stored hex values")
        expect(MenuBarUsageBarSupport.sanitizedColorHex("bad", fallback: "#FFD60A") == "#FFD60A",
               "invalid menu bar colors use their visible fallback")
        let customBarRGB = MenuBarUsageBarSupport.rgb(for: "#804020", fallback: "#000000")
        expectClose(customBarRGB.red, 128.0 / 255.0, "menu bar color parses red")
        expectClose(customBarRGB.green, 64.0 / 255.0, "menu bar color parses green")
        expectClose(customBarRGB.blue, 32.0 / 255.0, "menu bar color parses blue")
        expect(MenuBarUsageBarSupport.hex(red: 1, green: 0.5, blue: 0) == "#FF8000",
               "menu bar color picker writes stable hex values")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "14%") == "88%",
               "compact spacing reserves the current digit count for percentages")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "999°") == "888°",
               "compact spacing reserves the current digit count for temperatures")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "1.5M") == "8.8M",
               "compact spacing keeps units and separators while widening digits")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "") == "",
               "compact spacing reserve of an empty value stays empty")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "4%", minimumDigits: 2) == "88%",
               "compact spacing pads single digits up to the stability floor")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "14%", minimumDigits: 2) == "88%",
               "a one and a two digit value reserve the same width, so 4% to 10% never moves the bar")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "100%", minimumDigits: 2) == "888%",
               "values above the floor keep their own digit count")
        expect(MenuBarSpacingSupport.compactFloor(currentDigits: 1, highWater: nil) == 2,
               "the compact floor starts at two digits")
        expect(MenuBarSpacingSupport.compactFloor(currentDigits: 3, highWater: 2) == 3,
               "a three digit value raises the floor")
        expect(MenuBarSpacingSupport.compactFloor(currentDigits: 2, highWater: 3) == 3,
               "the session high-water mark keeps a block from shrinking back and wobbling")
        expect(MenuBarSpacingSupport.blockGlue(readableStyle: false, spacing: .standard) == " ",
               "standard dense spacing keeps the full space between blocks")
        expect(MenuBarSpacingSupport.blockGlue(readableStyle: false, spacing: .compact) == "\u{200A}",
               "compact dense spacing joins blocks with a hair space")
        expect(MenuBarSpacingSupport.blockGlue(readableStyle: true, spacing: .compact) == " ",
               "compact readable spacing tightens the double space to a single one")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1135, reportedMidX: 1452, buttonWidth: 38) == -317,
               "a click far left of the status item's reported frame re-anchors the panel at the click")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1452, reportedMidX: 1135, buttonWidth: 38) == 317,
               "a click far right of the status item's reported frame re-anchors the panel at the click")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1150, reportedMidX: 1144, buttonWidth: 38) == nil,
               "a click inside the status button never counts as drift")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1186, reportedMidX: 1144, buttonWidth: 38) == nil,
               "a sloppy click just past the button edge stays within the drift slack")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1188, reportedMidX: 1144, buttonWidth: 38) == 44,
               "a click beyond the slack re-anchors by the full offset")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1240, reportedMidX: 1144, buttonWidth: 197) == nil,
               "clicks near the edge of a wide metrics item stay anchored to the item")

        // The built-in display and a taller one placed to its left.
        let builtInScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let secondScreen = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let attachedScreens = [builtInScreen, secondScreen]
        expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 932, width: 0, height: 0),
                                                                 screenFrames: attachedScreens),
               "a status item frame with no size is never an anchor")
        expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 950, width: 38, height: 37),
                                                                 screenFrames: attachedScreens),
               "a status item parked above the top edge is not an anchor")
        expect(StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 919, width: 38, height: 37),
                                                                screenFrames: attachedScreens),
               "a status item sitting in the menu bar band is a trustworthy anchor")
        expect(StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: -1000, y: 1143, width: 38, height: 37),
                                                                screenFrames: attachedScreens),
               "the menu bar band follows each screen's own top edge")
        expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 0, width: 38, height: 37),
                                                                 screenFrames: attachedScreens),
               "a frame down at the bottom of a screen is not a menu bar item")

        // A screen showing a fullscreen window reserves no menu bar: its
        // visible area is the whole frame. The band is a fixed thickness off
        // the screen's own top edge, so an item revealed on hover still counts;
        // a band measured as `frame.maxY - visibleFrame.maxY` would collapse to
        // nothing here and decline the icon while it is visible and clickable.
        let fullscreenScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let fullscreenVisibleFrame = fullscreenScreen
        expect(StatusItemAnchorSupport.menuBarBand > fullscreenScreen.maxY - fullscreenVisibleFrame.maxY,
               "the menu bar band does not shrink to what a fullscreen screen reserves")
        expect(StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 919, width: 38, height: 37),
                                                                screenFrames: [fullscreenScreen]),
               "a status item revealed over a fullscreen window is a trustworthy anchor")

        // These AppKit owners are not part of the pure-helper test binary, so
        // pin that neither caller can consume a parked status-item frame.
        let statusAnchorAppDelegateSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/AppDelegate.swift",
            encoding: .utf8)) ?? ""
        let stripCommentLines: (String) -> String = {
            $0.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }
        // Sliced at the closing brace of the closure/function itself, so the
        // slice can never run past it into an unrelated body that happens to
        // carry the same words.
        let shelfProviderCode = stripCommentLines((statusAnchorAppDelegateSource
            .components(separatedBy: "ShelfService.shared.statusItemFrameProvider =").last ?? "")
            .components(separatedBy: "\n        }").first ?? "")
        let statusControllerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/StatusItemController.swift",
            encoding: .utf8)) ?? ""
        let statusHitTestCode = stripCommentLines((statusControllerSource
            .components(separatedBy: "func containsStatusItem(at screenPoint: NSPoint) -> Bool {").last ?? "")
            .components(separatedBy: "\n    }").first ?? "")
        let statusFrameCall = "StatusItemAnchorSupport.isTrustworthyStatusFrame("
        expect(shelfProviderCode.contains("guard \(statusFrameCall)") && shelfProviderCode.contains("return nil"),
               "the Shelf provider rejects an untrustworthy status-item frame")
        expect(statusHitTestCode.contains(statusFrameCall) && statusHitTestCode.contains("return false"),
               "status-item hit testing rejects an untrustworthy frame")

        // The panel keeps its top edge and its center while its content resizes.
        let panelArea = CGRect(x: 0, y: 0, width: 1470, height: 932)
        let shortPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                                  anchorMidX: 1283, anchorTop: 932,
                                                                  visibleFrame: panelArea)
        let tallPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 633),
                                                                 anchorMidX: 1283, anchorTop: 932,
                                                                 visibleFrame: panelArea)
        let shrunkPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                                   anchorMidX: 1283, anchorTop: 932,
                                                                   visibleFrame: panelArea)
        expect(shortPanel.midX == 1283 && tallPanel.midX == 1283 && shrunkPanel.midX == 1283,
               "the pinned panel stays centered on its anchor through a content resize")
        expect(shortPanel.maxY == 932 && tallPanel.maxY == 932 && shrunkPanel.maxY == 932,
               "a taller panel grows downward instead of moving its top edge")
        expect(shortPanel == shrunkPanel,
               "going back to the first tab lands the panel exactly where it started")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: 20, anchorTop: 932,
                                                        visibleFrame: panelArea).minX == 8,
               "a panel anchored past the left edge stops at the margin")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: 1465, anchorTop: 932,
                                                        visibleFrame: panelArea).maxX == 1462,
               "a panel anchored past the right edge stops at the margin")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: -1910, anchorTop: 1155,
                                                        visibleFrame: CGRect(x: -1920, y: 100,
                                                                             width: 1920, height: 1055))
                == CGRect(x: -1912, y: 780, width: 332, height: 375),
               "a display left of the built-in one clamps against its own negative origin")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 633),
                                                        anchorMidX: 700, anchorTop: 300,
                                                        visibleFrame: CGRect(x: 0, y: 0,
                                                                             width: 1470, height: 300)).maxY == 300,
               "a screen too short for the panel still shows its top")
        expect(registeredDefaults[DefaultsKey.menuBarHideIconWithMetrics] as? Bool == false,
               "the menu bar icon stays visible by default")
        expect(MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                          metricsEnabled: true, renderedTitleLength: 12,
                                                          mustShowForSignal: false),
               "the glyph hides when metrics render in the title and the option is on")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: false, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 12,
                                                           mustShowForSignal: false),
               "the glyph never hides while the option is off")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 0,
                                                           mustShowForSignal: false),
               "an empty rendered title keeps the glyph, so the item can never turn invisible")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: false, renderedTitleLength: 6,
                                                           mustShowForSignal: false),
               "a countdown-only title keeps the glyph when no metric is enabled")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: true,
                                                           metricsEnabled: true, renderedTitleLength: 6,
                                                           mustShowForSignal: false),
               "separate metric items keep the glyph in the otherwise empty main item")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 12,
                                                           mustShowForSignal: true),
               "an available update or muted mic brings the glyph back to carry the signal")
        expect(MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                              metricItemsShown: 2, renderedTitleLength: 0,
                                                              mustShowForSignal: false),
               "with separate metric items installed the whole main item may step aside")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 0, renderedTitleLength: 0,
                                                               mustShowForSignal: false),
               "no installed metric items keep the main item, so the app never vanishes")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 2, renderedTitleLength: 5,
                                                               mustShowForSignal: false),
               "an active countdown renders in the main item and keeps it visible")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: false,
                                                               metricItemsShown: 2, renderedTitleLength: 0,
                                                               mustShowForSignal: false),
               "the whole-item hiding only applies to the separate-items mode")

        // A pinned metric that momentarily has nothing to show keeps its item
        // instead of being taken away and put back every tick.
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: true, itemExists: false),
               "a metric with something to show gets its own item")
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: false, itemExists: true,
                                                           consecutiveEmptyRenders: 1),
               "a reading that goes missing for a tick blanks its item instead of removing it")
        expect(!MenuBarSpacingSupport.keepsMetricStatusItem(
            hasRenderedTitle: false, itemExists: true,
            consecutiveEmptyRenders: MenuBarSpacingSupport.emptyMetricRendersBeforeRemoval),
               "a reading that stops for good takes its item away instead of leaving a gap")
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(
            hasRenderedTitle: true, itemExists: true,
            consecutiveEmptyRenders: 99),
               "a reading that comes back keeps its item whatever came before")
        expect(!MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: false, itemExists: false),
               "a metric with nothing to show yet gets no item at all")
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: true, itemExists: true),
               "an item already showing a reading stays")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 2, renderedTitleLength: 0,
                                                               mustShowForSignal: true),
               "a signal brings the main item back even in the separate-items mode")
        expect(MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: true,
                                                            showsCountdown: true,
                                                            hasEndDate: true),
               "a visible finite Keep Awake countdown owns the title timer")
        expect(!MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: false,
                                                             showsCountdown: true,
                                                             hasEndDate: true)
                && !MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: true,
                                                                  showsCountdown: false,
                                                                  hasEndDate: true)
                && !MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: true,
                                                                  showsCountdown: true,
                                                                  hasEndDate: false),
               "idle, hidden and indefinite Keep Awake titles need no timer")
        let statusPlacementSuite = "com.vorssaint.tests.statusItemPlacement"
        if let statusDefaults = UserDefaults(suiteName: statusPlacementSuite) {
            statusDefaults.removePersistentDomain(forName: statusPlacementSuite)
            expect(StatusItemPlacementSupport.placementGeneration(in: statusDefaults) == 0,
                   "initial placement generation is 0")
            expect(StatusItemPlacementSupport.mainAutosaveName(in: statusDefaults) == "VorssaintMenuBarItem",
                   "generation 0 uses base autosave name")

            // The coordinate macOS saves for the icon is what puts it back in
            // the same spot on the next launch. 3.3.3 deleted the one written
            // by the older recovery on every launch, which moved the icon to
            // where a first-time item goes and, on a full bar, out of sight.
            let legacyKey = "NSStatusItem Preferred Position VorssaintMenuBarItem"
            statusDefaults.set(64.0, forKey: legacyKey)
            StatusItemPlacementSupport.clearRememberedVisibility(in: statusDefaults)
            expect(statusDefaults.double(forKey: legacyKey) == 64.0,
                   "an icon placed by the older recovery keeps its spot through an update")

            statusDefaults.set(320.5, forKey: legacyKey)
            StatusItemPlacementSupport.clearRememberedVisibility(in: statusDefaults)
            expect(statusDefaults.double(forKey: legacyKey) == 320.5,
                   "an icon the person arranged themselves keeps its spot too")

            StatusItemPlacementSupport.bumpPlacementGeneration(in: statusDefaults)
            let gen1Name = StatusItemPlacementSupport.mainAutosaveName(in: statusDefaults)
            expect(gen1Name == "VorssaintMenuBarItem.1",
                   "bumped generation produces numbered autosave name")
            expect(statusDefaults.object(forKey: "NSStatusItem Preferred Position VorssaintMenuBarItem.1") == nil,
                   "bumpPlacementGeneration does not seed any hardcoded preferred position")

            // Recovery keeps the spot the person arranged and only drops the
            // hidden state macOS remembered: an item that starts over with no
            // saved position is born against the notch, the first place a
            // crowded bar hides.
            let gen1Position = "NSStatusItem Preferred Position VorssaintMenuBarItem.1"
            statusDefaults.set(280.0, forKey: gen1Position)
            statusDefaults.set(false, forKey: "NSStatusItem Visible VorssaintMenuBarItem.1")
            statusDefaults.set(false, forKey: "NSStatusItem VisibleCC VorssaintMenuBarItem.1")
            StatusItemPlacementSupport.clearRememberedVisibility(in: statusDefaults)
            expect(statusDefaults.double(forKey: gen1Position) == 280.0,
                   "clearing the remembered visibility keeps the arranged position")
            expect(StatusItemPlacementSupport.placementGeneration(in: statusDefaults) == 1
                    && StatusItemPlacementSupport.mainAutosaveName(in: statusDefaults) == gen1Name,
                   "recovery leaves the item's identity alone, so reopening cannot churn it")
            expect(statusDefaults.object(forKey: "NSStatusItem Visible VorssaintMenuBarItem.1") == nil
                    && statusDefaults.object(forKey: "NSStatusItem VisibleCC VorssaintMenuBarItem.1") == nil,
                   "clearing the remembered visibility drops both spellings macOS has used")

            // Giving the spot up is what an explicit recovery escalates to,
            // and only after keeping it has failed.
            expect(statusDefaults.object(forKey: gen1Position) == nil
                    || statusDefaults.double(forKey: gen1Position) == 280.0,
                   "only the identity reset gives up a saved position")
            StatusItemPlacementSupport.bumpPlacementGeneration(in: statusDefaults)
            expect(statusDefaults.object(forKey: gen1Position) == nil
                    && StatusItemPlacementSupport.mainAutosaveName(in: statusDefaults)
                        == "VorssaintMenuBarItem.2",
                   "the identity reset does give the saved position up")
            statusDefaults.removePersistentDomain(forName: statusPlacementSuite)
        }
    }
}
