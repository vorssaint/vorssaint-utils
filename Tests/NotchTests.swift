// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics
import AppKit
import SwiftUI

enum NotchTests {
    private static func railContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-fan-only"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for feature in AppFeature.allCases { defaults.set(false, forKey: feature.availabilityKey) }
        suite.expect(!NotchModule.system.isAvailable(in: defaults), "System stays unavailable without an installed monitor")
        defaults.set(true, forKey: AppFeature.fanControl.availabilityKey)
        suite.expect(NotchModule.system.isAvailable(in: defaults)
                     && NotchSupport.systemCardCount(hasBattery: false, fans: 1, in: defaults) == 1,
                     "fan control alone makes its containing System page reachable")
        suite.expect(NotchModule.system.isAvailable(in: defaults)
                     && NotchSupport.systemCardCount(hasBattery: false, fans: 0, in: defaults) == 0,
                     "System remains reachable while waiting for the first fan sample")
        defaults.set(false, forKey: AppFeature.fanControl.availabilityKey)
        defaults.set(true, forKey: AppFeature.connectedDevices.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.menuBarConnectedDevices)
        suite.expect(NotchModule.system.isAvailable(in: defaults)
                     && NotchSupport.systemCardCount(hasBattery: false, in: defaults) == 1,
                     "connected devices alone keeps its System page and card reachable with the menu bar widget off")
        defaults.set(false, forKey: AppFeature.connectedDevices.availabilityKey)
        suite.expect(!NotchModule.system.isAvailable(in: defaults)
                     && NotchSupport.systemCardCount(hasBattery: false, in: defaults) == 0,
                     "uninstalling connected devices removes its System page and card")

        suite.expect(NotchLayout.systemRowRanges(count: 7, width: 504) == [0..<3, 3..<5, 5..<7],
                     "seven System metrics fill balanced rows instead of leaving a nearly empty column")
        suite.expect(NotchLayout.systemRowRanges(count: 7, width: 304) == [0..<2, 2..<4, 4..<6, 6..<7],
                     "narrow System rows keep readable cards and a full-width last card")
        for width: CGFloat in [20, 304, 424, 504, 744] {
            for count in 0...9 {
                let rows = NotchLayout.systemRowRanges(count: count, width: width)
                suite.expect(rows.flatMap { Array($0) } == Array(0..<count),
                             "System preserves every metric exactly once in reading order")
                let capacity = NotchLayout.railCapacity(width: width, itemWidth: NotchLayout.systemCardWidth,
                                                       spacing: NotchLayout.rowSpacing)
                suite.expect(rows.allSatisfy { !$0.isEmpty && $0.count <= capacity },
                             "System rows fit the available width for every combination of enabled metrics")
            }
        }

        suite.expect(NotchLayout.railCapacity(width: 424, itemWidth: 76, spacing: 8) == 5
               && NotchLayout.railCapacity(width: 304, itemWidth: 76, spacing: 8) == 3
               && NotchLayout.railCapacity(width: 20, itemWidth: 76, spacing: 8) == 1
               && NotchLayout.railCapacity(width: .nan, itemWidth: 76, spacing: 8) == 1,
               "a rail fits whole columns of its width and never fewer than one")
        suite.expect(NotchLayout.railRows(count: 4, perRow: 5, rowHeight: 74, spacing: 8, height: 180) == 1
               && NotchLayout.railRows(count: 7, perRow: 5, rowHeight: 74, spacing: 8, height: 106) == 1
               && NotchLayout.railRows(count: 7, perRow: 5, rowHeight: 74, spacing: 8, height: 190) == 2
               && NotchLayout.railRows(count: 0, perRow: 0, rowHeight: 74, spacing: 8, height: 0) == 1
               && NotchLayout.railRows(count: 40, perRow: 5, rowHeight: 74, spacing: 8, height: .infinity) == 8,
               "rows follow the items that need them and stop where the height ends")
        suite.expect(NotchLayout.railHeight(rows: 1, rowHeight: 74, spacing: 8) == 74
               && NotchLayout.railHeight(rows: 3, rowHeight: 74, spacing: 8) == 238
               && NotchLayout.railHeight(rows: 0, rowHeight: 74, spacing: 8) == 74,
               "a rail's height is its rows and the gaps between them")
        suite.expect(NotchLayout.railColumns(count: 11, rows: 2) == 6
               && NotchLayout.railColumns(count: 8, rows: 2) == 4
               && NotchLayout.railColumns(count: 0, rows: 0) == 0
               && NotchLayout.railFits(columns: 6, itemWidth: 76, spacing: 8, width: 496)
               && !NotchLayout.railFits(columns: 6, itemWidth: 76, spacing: 8, width: 495),
               "a rail spreads its items over the fewest columns its rows allow and fits once they all do")
        let compact = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 32, cameraWidth: 180)
        suite.expect(compact.toolFlow(count: 8) == .rows(columns: 4) && compact.toolFlow(count: 12) == .columns(rows: 2),
                     "the launcher's arrows read across the rows that fit and follow the columns once the rail scrolls")
        let single = (0..<5).map { QuickToolsSupport.gridIndex(after: 2, count: 5, flow: .columns(rows: 1),
                                                                direction: [.left, .right, .up, .down, .left][$0]) }
        suite.expect(single == [1, 3, 2, 2, 1], "in one row the side arrows walk the tiles and the vertical pair stays put")
        suite.expect(QuickToolsSupport.gridIndex(after: 2, count: 7, flow: .rows(columns: 3), direction: .down) == 5
               && QuickToolsSupport.gridIndex(after: 2, count: 7, flow: .rows(columns: 3), direction: .right) == 2,
               "the row flow keeps the panel grid's own walk")
        suite.expect(QuickToolsSupport.gridIndex(after: 2, count: 7, flow: .columns(rows: 2), direction: .right) == 4
               && QuickToolsSupport.gridIndex(after: 2, count: 7, flow: .columns(rows: 2), direction: .left) == 0
               && QuickToolsSupport.gridIndex(after: 2, count: 7, flow: .columns(rows: 2), direction: .down) == 3
               && QuickToolsSupport.gridIndex(after: 3, count: 7, flow: .columns(rows: 2), direction: .down) == 3
               && QuickToolsSupport.gridIndex(after: 3, count: 7, flow: .columns(rows: 2), direction: .up) == 2
               && QuickToolsSupport.gridIndex(after: 6, count: 7, flow: .columns(rows: 2), direction: .down) == 6
               && QuickToolsSupport.gridIndex(after: 5, count: 7, flow: .columns(rows: 2), direction: .right) == 5
               && QuickToolsSupport.gridIndex(after: 9, count: 7, flow: .columns(rows: 2), direction: .up) == 6,
               "with two rows the arrows follow the columns the tiles fill, clamped to the last tile")
        let controls = NotchLayout.controls(hasCards: true, shortcutCount: 4, width: 424, height: NotchLayout.compactContentHeight)
        suite.expect(controls == NotchControlsLayout(cardRow: NotchLayout.cardHeight, shortcutRows: 1)
               && controls.height == NotchLayout.cardHeight + NotchLayout.rowSpacing + NotchLayout.shortcutHeight
               && controls.height < NotchLayout.compactContentHeight,
               "the default home page is the player's card row over one shortcut rail, shorter than the compact strip")
        let nineTiles = NotchLayout.controls(hasCards: false, shortcutCount: 9, width: 424, height: 154)
        suite.expect(NotchLayout.controls(hasCards: true, shortcutCount: 4, width: 424, height: 154)
               == NotchControlsLayout(cardRow: 154 - NotchLayout.shortcutHeight - NotchLayout.rowSpacing, shortcutRows: 1)
               && NotchLayout.controls(hasCards: false, shortcutCount: 0, width: 424, height: 154) == NotchControlsLayout(cardRow: 0, shortcutRows: 0)
               && NotchLayout.controls(hasCards: true, shortcutCount: 0, width: 424, height: 154).height == NotchLayout.cardHeight
               && nineTiles == NotchControlsLayout(cardRow: 0, shortcutRows: 2, shortcutRowSpacing: NotchLayout.shortcutLeastRowSpacing),
               "the smallest custom island shortens the cards to keep the rail, and rows nobody enabled cost nothing")
        let timerSetup = NotchLayout.timer(mode: .timer, hasSession: false, height: 180)
        let pomodoroSetup = NotchLayout.timer(mode: .pomodoro, hasSession: false, height: 180)
        let stopwatchSetup = NotchLayout.timer(mode: .stopwatch, hasSession: false, height: 180)
        suite.expect(stopwatchSetup == timerSetup && pomodoroSetup <= NotchLayout.compactContentHeight
               && timerSetup == NotchLayout.timerRulerHeight
               && pomodoroSetup == timerSetup + NotchLayout.timerRowSpacing + NotchLayout.timerSettingsRowHeight,
               "the modes and Start are in the top row, so every mode is the ruler's row; the Pomodoro adds one line of readouts under it")
        let tight: CGFloat = 154
        for mode in NotchTimerMode.allCases {
            suite.expect(NotchLayout.timer(mode: mode, hasSession: false, height: tight) <= tight
                   && NotchLayout.timer(mode: mode, hasSession: false, height: 400) == NotchLayout.timer(mode: mode, hasSession: false, height: 180),
                   "the shortest custom island still shows every timer row, and a taller one adds nothing: \(mode)")
        }
        let lowPage: CGFloat = 100
        suite.expect(NotchLayout.timerRulerHeight(mode: .pomodoro, height: lowPage) == lowPage
                   - NotchLayout.timerRowSpacing - NotchLayout.timerSettingsRowHeight
               && NotchLayout.timer(mode: .pomodoro, hasSession: false, height: lowPage) == lowPage
               && NotchLayout.timerRulerHeight(mode: .pomodoro, height: 60) == NotchLayout.timerMinimumRulerHeight
               && NotchLayout.timerRulerHeight(mode: .pomodoro, height: 400) == NotchLayout.timerRulerHeight
               && NotchLayout.timerRulerHeight(height: lowPage) == NotchLayout.timerRulerHeight
               && NotchLayout.timerRulerHeight(mode: .stopwatch, height: 60) == NotchLayout.timerRulerHeight,
               "the ruler gives the Pomodoro's readouts height down to a floor before anything is cut, and keeps its own alone")
        suite.expect(NotchTimerMode.allCases.allSatisfy {
                   NotchLayout.timer(mode: $0, hasSession: true, height: tight) == NotchLayout.timerRulerHeight
                       && NotchLayout.timer(mode: $0, hasSession: true, height: tight)
                           <= NotchLayout.timer(mode: $0, hasSession: false, height: tight)
               },
               "a running session's button and clock take the ruler row's height, so starting one never grows the island")
        // Lyrics and the queue grow the island; the player keeps the height it had.
        let extras: CGFloat = 216, resting = NotchLayout.musicPlayerHeight(band: 37.5)
        let grown = NotchLayout.musicSplit(height: resting + extras, extras: extras,
                                           resting: resting, keepsPlayer: true)
        suite.expect(grown.player == resting && grown.showsPlayer && grown.extra == extras - NotchLayout.rowSpacing,
                     "opening the queue leaves the player as tall as it was and gives the list the rest")
        for height in stride(from: resting, through: resting + extras, by: 12) {
            let growing = NotchLayout.musicSplit(height: height, extras: extras, resting: resting, keepsPlayer: true)
            suite.expect(growing.player == resting && growing.showsPlayer, "the player does not change size while the island grows")
        }
        let short = NotchLayout.musicSplit(height: 200, extras: extras, resting: resting, keepsPlayer: false)
        suite.expect(short.extra == 200 && !short.showsPlayer,
                     "where the island cannot hold both, the player still yields to the list")
        let closed = NotchLayout.musicSplit(height: resting, extras: extras, resting: resting, keepsPlayer: false, extraOpen: false)
        suite.expect(closed.player == resting && closed.extra == 0 && closed.showsPlayer, "with nothing open the player takes the page")
        // A custom island cannot grow: the player keeps its own height and
        // the list takes the rest, or the whole page once that is too short.
        for height in stride(from: CGFloat(200), through: 480, by: 4) {
            let custom = NotchLayout.musicSplit(height: height, extras: extras, resting: resting, keepsPlayer: false)
            suite.expect(custom.showsPlayer
                         ? custom.player == resting && custom.player + NotchLayout.rowSpacing + custom.extra <= height
                             && custom.extra >= NotchLayout.musicMinimumExtraHeight
                         : custom.extra <= height && height - resting - NotchLayout.rowSpacing < NotchLayout.musicMinimumExtraHeight,
                         "a custom island at \(height) pt holds the player and the list it shows: \(custom)")
        }
        // The page reads the player's height from the geometry; it must be
        // the room the island keeps for it at rest, under a notch or in a capsule.
        for layout: NotchSize in [.compact, .spacious] {
            for notched in [true, false] {
                var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: notched ? 32 : 0,
                                             cameraWidth: notched ? 210 : 0, layout: layout, silhouette: .capsule)
                geometry.pageTop = NotchModule.music.pageTop
                let player = geometry.musicPlayerHeight
                let rest = geometry.contentSize(for: geometry.expandedSize(module: .music)).height
                let open = geometry.contentSize(for: geometry.expandedSize(module: .music, musicExtraHeight: geometry.musicExtrasHeight)).height
                let split = NotchLayout.musicSplit(height: open, extras: geometry.musicExtrasHeight,
                                                   resting: player, keepsPlayer: true)
                suite.expect(geometry.floats != notched && player == NotchLayout.musicPlayerHeight(band: notched ? 36 : 0)
                             && rest == player && split.player == player && split.showsPlayer
                             && split.extra == geometry.musicExtrasHeight - NotchLayout.rowSpacing,
                             "the island grows by the list and the player keeps the height it has at rest: \(layout), notched \(notched)")
            }
        }
        // The cover tucks into the camera's row and the song sits below the
        // camera, so the player is as tall as the song needs below it, or
        // the cover's own height without a camera; every preset alike.
        suite.expect(NotchLayout.musicHeadHeight(band: 37.5) == 37.5 + NotchLayout.musicCameraClearance + NotchLayout.musicTitleHeight
               && NotchLayout.musicHeadHeight(band: 0) == NotchLayout.musicArtworkSize
               && NotchLayout.musicHeadHeight(band: 37.5) - 37.5 < NotchLayout.musicArtworkSize
               && NotchLayout.musicPlayerHeight(band: 0)
                   == NotchLayout.musicArtworkSize + NotchLayout.musicHeadSpacing + NotchLayout.musicTimelineHeight
                       + NotchLayout.rowSpacing + NotchLayout.musicTransportHeight + NotchLayout.musicBottomRoom
               && NotchLayout.musicPlayerHeight(band: 37.5, playing: false)
                   == NotchLayout.musicPlayerHeight(band: 37.5) - NotchLayout.musicTimelineHeight - NotchLayout.rowSpacing,
               "the player is a small cover beside the camera, the song below it, the timeline and one row of buttons")
    }

    private static func presentationSpacingContracts(_ suite: TestSuite) {
        let screen = CGRect(x: -1470, y: 80, width: 1470, height: 956)
        for width in [360.0, 480, 560, 720] {
            for cameraHeight: CGFloat in [24, 32, 40, 64] {
                let geometry = NotchGeometry(screen: screen, safeAreaTop: cameraHeight, cameraWidth: 210,
                                             layout: .custom, customWidth: width, customHeight: 400)
                suite.expect(geometry.pageTopInset >= cameraHeight, "the page always begins below the physical camera")
                let area = geometry.activationArea(in: geometry.expanded, hasHeader: true,
                                                   compactActivity: false, expandedHeader: true)
                if width >= 480 {
                    suite.expect(geometry.headerCameraGap == 210 && geometry.headerTopInset == 0,
                                 "wide islands use the space beside the camera without reserving a blank top row")
                    suite.expect(area.width == 210 && area.height == cameraHeight
                                 && area.midX == geometry.expanded.width / 2,
                                 "the collapse target covers only the camera, leaving the row's controls clickable")
                } else {
                    suite.expect(geometry.headerCameraGap == 0 && geometry.headerTopInset >= cameraHeight,
                                 "narrow islands keep a complete usable row below the camera")
                }
                let content = geometry.contentSize(for: geometry.expandedSize(module: .system, systemCards: 1))
                let inset = NotchLayout.systemHoverInset(width: content.width)
                suite.expect((content.width - inset * 2) * 1.028 <= content.width
                             && NotchLayout.systemCardHeight * 1.028 <= NotchLayout.systemCardHeight + inset * 2,
                             "even a full-width system card can grow on hover inside its viewport")
            }
        }
        for layout: NotchSize in [.compact, .spacious] {
            let geometry = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 210, layout: layout)
            suite.expect(geometry.headerTopInset == 0 && geometry.headerCameraGap == 210,
                         "both presets place the top row beside the camera without a blank row above it")
            suite.expect(geometry.quickAccessCenterY - NotchQuickAccessLayout.diameter / 2 == 38,
                         "floating buttons keep six points of clearance below the menu bar in both presets")
        }
        let simulated = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: .spacious)
        suite.expect(simulated.headerTopInset == 0 && simulated.headerCameraGap == 0,
                     "a display without a camera does not reserve a blank row above the open page's own")
        suite.expect(simulated.activationArea(in: simulated.expanded, hasHeader: true,
                                             compactActivity: false, expandedHeader: true).isEmpty,
                     "a simulated island's top row is never covered by an invisible collapse button")
        var bare = simulated
        bare.pageTop = .none
        suite.expect(bare.headerRowHeight == 0 && bare.headerTopInset == NotchLayout.bottomInset
                     && bare.pageTopInset == NotchLayout.bottomInset
                     && bare.activationArea(in: bare.expanded, hasHeader: true, compactActivity: false,
                                            expandedHeader: true).isEmpty,
                     "a page with nothing for the row starts as far from the top as it ends from the bottom")
    }

    private static func captureControlsLayoutContracts(_ suite: TestSuite) {
        func titleWidth(_ language: AppLanguage) -> CGFloat {
            NotchCaptureControlsLayout.titleWidth(FeatureStrings.screenshot(language).screenCaptureTitle)
        }
        for language in AppLanguage.allCases {
            let host = NSHostingView(rootView: Text(FeatureStrings.screenshot(language).screenCaptureTitle)
                .font(Font(NotchCaptureControlsLayout.titleFont as CTFont)).fixedSize())
            host.layoutSubtreeIfNeeded()
            suite.expect(host.fittingSize.width <= titleWidth(language),
                         "the measured capture title covers the \(language.rawValue) title as drawn (\(host.fittingSize.width))")
        }
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        var geometries: [NotchGeometry] = []
        for camera: CGFloat in [180, 185, 210, 240] {
            for cameraHeight: CGFloat in [32, 38] {
                for layout: NotchSize in [.compact, .spacious] {
                    geometries.append(NotchGeometry(screen: screen, safeAreaTop: cameraHeight,
                                                    cameraWidth: camera, layout: layout))
                }
                for width in stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 10) {
                    geometries.append(NotchGeometry(screen: screen, safeAreaTop: cameraHeight, cameraWidth: camera,
                                                    layout: .custom, customWidth: width))
                }
            }
        }
        let clearance = NotchCaptureControlsLayout.cameraClearance
        for geometry in geometries {
            let previousHeight = geometry.safeContentTop + 28 + 12 + NotchLayout.shortcutHeight + 16
            for language in AppLanguage.allCases {
                let title = titleWidth(language)
                let layout = NotchCaptureControlsLayout(geometry: geometry, titleWidth: title, capturesAudio: false)
                suite.expect(layout.size.width == geometry.expandedWidth
                             && layout.headerTop + layout.headerHeight + 12 >= geometry.cameraHeight,
                             "capture tools keep the island's width and begin below the camera")
                if layout.cameraGap > 0 {
                    suite.expect(layout.headerTop == 0 && layout.headerHeight == geometry.headerRowHeight
                                 && layout.cameraGap == geometry.cameraWidth
                                 && layout.sideWidth * 2 + layout.cameraGap == geometry.contentWidth,
                                 "capture controls beside the camera share the open header's row and sides")
                    suite.expect(title + clearance <= layout.sideWidth
                                 && NotchCaptureControlsLayout.narrowButtonsWidth + clearance <= layout.sideWidth,
                                 "the \(language.rawValue) capture title and buttons stay clear of the camera")
                    suite.expect(layout.size.height < previousHeight,
                                 "capture controls beside the camera cover less of the screen")
                } else {
                    suite.expect(layout.headerTop == geometry.safeContentTop
                                 && layout.headerHeight == NotchCaptureControlsLayout.rowHeight
                                 && layout.size.height == previousHeight,
                                 "a capture title too wide for the camera's side keeps its row below the camera")
                }
            }
        }
        for layout: NotchSize in [.compact, .spacious] {
            for camera: CGFloat in [185, 210] {
                let geometry = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: camera, layout: layout)
                suite.expect(NotchCaptureControlsLayout(geometry: geometry, titleWidth: titleWidth(.enUS),
                                                        capturesAudio: false).cameraGap == camera,
                             "both presets put the English capture title beside the camera")
            }
        }
        let roomy = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 180, layout: .spacious)
        suite.expect(AppLanguage.allCases.allSatisfy {
            NotchCaptureControlsLayout(geometry: roomy, titleWidth: titleWidth($0), capturesAudio: false).cameraGap > 0
        }, "every capture title fits beside a narrow camera in the spacious preset")
        let crowded = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 210, layout: .compact)
        suite.expect(NotchCaptureControlsLayout(geometry: crowded, titleWidth: titleWidth(.es),
                                                capturesAudio: false).cameraGap == 0,
                     "the longest capture title keeps its row below a wide camera in the compact preset")
        let audio = NotchCaptureControlsLayout(geometry: roomy, titleWidth: titleWidth(.enUS), capturesAudio: true)
        let silent = NotchCaptureControlsLayout(geometry: roomy, titleWidth: titleWidth(.enUS), capturesAudio: false)
        suite.expect(audio.size.height == silent.size.height + 40, "recording keeps room for its audio switches")
        let simulated = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: .spacious)
        let top = NotchCaptureControlsLayout(geometry: simulated, titleWidth: titleWidth(.es), capturesAudio: false)
        suite.expect(top.headerTop == 0 && top.cameraGap == 0 && top.headerHeight == NotchLayout.headerHeight
                     && top.size.height < simulated.safeContentTop + 28 + 12 + NotchLayout.shortcutHeight + 16,
                     "without a camera the capture title and buttons take the top row, as the open header does")
    }

    /// The island names no page: its top row holds the page's own controls,
    /// wrapping the camera wherever each side keeps a 100-point wing, and a
    /// row below the camera elsewhere. A page with nothing for the row starts
    /// below the camera, or at the top of an island without one, and the
    /// player starts at the top of the row, wrapping the camera itself.
    private static func pageTopContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        var geometries: [NotchGeometry] = []
        for camera: CGFloat in [180, 185, 208, 210, 224, 240] {
            for layout: NotchSize in [.compact, .spacious] {
                geometries.append(NotchGeometry(screen: screen, safeAreaTop: 37.5, cameraWidth: camera, layout: layout))
            }
            for width in stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 10) {
                geometries.append(NotchGeometry(screen: screen, safeAreaTop: 37.5, cameraWidth: camera,
                                                layout: .custom, customWidth: width))
            }
        }
        for geometry in geometries {
            let place = "beside a \(Int(geometry.cameraWidth))-point camera in a \(Int(geometry.expandedWidth))-point island"
            var aside = true, below = true, bands = true
            for module in NotchModule.allCases {
                var page = geometry
                page.pageTop = module.pageTop
                let wraps = page.contentWidth >= page.cameraWidth + page.pageBandSide * 2
                let band = NotchBand(geometry: page, contentWidth: page.contentWidth)
                if wraps {
                    aside = aside && page.headerCameraGap == geometry.cameraWidth && page.headerTopInset == 0
                        && page.headerRowHeight == max(page.cameraHeight, NotchLayout.headerHeight)
                        && page.pageTopInset == (module.pageTop == .wrapsCamera ? 0
                            : page.headerRowHeight + NotchLayout.spacing)
                    bands = bands && band.besideCamera && band.side >= page.pageBandSide - NotchBand.cameraClearance
                } else {
                    below = below && page.headerCameraGap == 0 && page.headerTopInset == page.safeContentTop
                        && page.headerRowHeight == (module.pageTop == .row ? NotchLayout.headerHeight : 0)
                        && page.pageTopInset >= page.safeContentTop
                    bands = bands && !band.besideCamera && band.side == page.contentWidth
                }
                let size = page.expandedSize(module: module)
                bands = bands && page.contentSize(for: size).height
                    == size.height - page.pageTopInset - NotchLayout.bottomInset
            }
            suite.expect(aside, "every page's row wraps the camera where its sides fit \(place)")
            suite.expect(below, "every page's row takes the full width below the camera where its sides do not \(place)")
            suite.expect(bands, "the row's sides and the page below it add up \(place)")
        }
        // The report: a 1710 by 1112 point display with a 208 by 37.5 point camera, in the compact preset.
        var reported = NotchGeometry(screen: screen, safeAreaTop: 37.5, cameraWidth: 208)
        reported.pageTop = NotchModule.camera.pageTop
        suite.expect(reported.headerCameraGap == 208 && reported.headerTopInset == 0,
                     "Camera mirror keeps its row beside a 208-point camera in the compact preset, as Controls does")
        for silhouette in NotchSilhouette.allCases {
            let plain = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, silhouette: silhouette)
            for module in NotchModule.allCases {
                var page = plain
                page.pageTop = module.pageTop
                let row = module.pageTop == .row
                suite.expect(page.headerCameraGap == 0 && page.headerRowHeight == (row ? NotchLayout.headerHeight : 0)
                             && page.headerTopInset == (row ? plain.headerTopInset : NotchLayout.bottomInset)
                             && page.pageTopInset == (row ? plain.pageTopInset : NotchLayout.bottomInset)
                             && page.activationArea(in: page.expandedSize(module: module), hasHeader: true,
                                                    compactActivity: false, expandedHeader: true).isEmpty,
                             "the \(module.rawValue) page's top in a \(silhouette.rawValue) island without a camera")
            }
        }
    }

    /// Under a preset each page takes the width it needs, up to the preset's:
    /// the player about 380 points between its sides, still wrapping the
    /// camera, the home page its row of shortcuts, and lists the whole width.
    /// A width set by hand is the island's on every page, so a wider one
    /// makes the player, the timer and the home page wider too.
    private static func pageWidthContracts(_ suite: TestSuite) {
        let screens: [(CGFloat, CGFloat)] = [(0, 0), (156, 28), (179, 32), (185, 37.5), (210, 37.5), (224, 37.5)]
        for (camera, top) in screens {
            for layout: NotchSize in [.compact, .spacious] {
                var player = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1710, height: 1112), safeAreaTop: top,
                                           cameraWidth: camera, layout: layout,
                                           silhouette: camera == 0 ? .capsule : .notch)
                let chosen = player.expandedWidth
                player.pageTop = NotchModule.music.pageTop
                player.pageContentWidth = NotchLayout.naturalContentWidth(.music, controls: [], within: player.contentWidth)
                let expected = max(NotchLayout.musicContentWidth, camera > 0 ? camera + NotchLayout.musicBandSide * 2 : 0)
                    + NotchLayout.horizontalInset * 2
                suite.expect(player.expandedWidth == min(chosen, expected) && player.expandedWidth < chosen
                             && (camera == 0 || player.headerCameraGap == camera),
                             "the player is no wider than it needs, around a \(Int(camera))-point camera in \(layout)")
                var list = player
                list.pageTop = NotchModule.clipboard.pageTop
                list.pageContentWidth = NotchLayout.naturalContentWidth(.clipboard, controls: [], within: player.contentWidth)
                suite.expect(list.expandedWidth == chosen, "a list keeps the chosen width in \(layout)")
            }
        }
        let shortcuts: [NotchControlItem] = [.volume, .brightness, .mixer, .keepAwake, .timer, .calendar, .microphone]
        let home = NotchLayout.naturalContentWidth(.controls, controls: shortcuts, within: 504)
        suite.expect(home == 5 * NotchLayout.shortcutWidth + 4 * NotchLayout.shortcutSpacing,
                     "the home page is as wide as its one row of shortcuts: \(home ?? 0)")
        suite.expect(NotchLayout.naturalContentWidth(.controls, controls: shortcuts + [.screenshot, .recording, .speedTest,
                                                                                      .panel, .commandBar], within: 424) == nil,
                     "a home page whose shortcuts wrap keeps the chosen width")
        var custom = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1710, height: 1112), safeAreaTop: 32, cameraWidth: 210,
                                   layout: .custom, customWidth: 360)
        custom.pageTop = .wrapsCamera
        custom.pageContentWidth = NotchLayout.musicContentWidth
        suite.expect(custom.expandedWidth == 360 && custom.headerCameraGap == 0,
                     "a chosen width narrower than the player still limits it, and its row then sits below the camera")
        var handSet = true, wraps = true
        for (camera, top) in screens {
            let preset = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1710, height: 1112), safeAreaTop: top,
                                       cameraWidth: camera, layout: .spacious, silhouette: camera == 0 ? .capsule : .notch)
                .page(.music, controls: [], sectionsButton: false)
            for width in stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 20) {
                let base = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1710, height: 1112), safeAreaTop: top,
                                         cameraWidth: camera, layout: .custom, customWidth: width,
                                         silhouette: camera == 0 ? .capsule : .notch)
                for module: NotchModule in [.music, .timer, .controls] {
                    for sectionsButton in [false, true] {
                        let page = base.page(module, controls: shortcuts, sectionsButton: sectionsButton)
                        handSet = handSet && page.expandedWidth == CGFloat(width)
                    }
                }
                // As wide as the preset's player or wider, it still wraps the camera.
                let player = base.page(.music, controls: [], sectionsButton: false)
                if CGFloat(width) >= preset.expandedWidth {
                    wraps = wraps && player.headerCameraGap == preset.headerCameraGap
                }
            }
        }
        suite.expect(handSet, "a width set by hand is the island's on the player, the timer and the home page")
        suite.expect(wraps, "a player set wider by hand wraps the camera as the preset's does")
        // The Layout tab previews the home page at the width the island opens
        // it at, never a preset's wider island around it.
        let editor = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Settings/NotchLayoutEditor.swift", encoding: .utf8)) ?? ""
        suite.expect(editor.contains("private var actualWidth: CGFloat { previewGeometry.expandedWidth }")
                     && editor.contains("return geometry.page(.controls, controls: NotchSupport.controls(),"),
                     "the Layout preview opens the home page as the island does")
    }

    /// Without a floating Explore button each page's row starts with the
    /// island's own way to the sections, and the player's row ends with it
    /// after its toggles. A page with a width of its own grows by it beside a
    /// camera, up to the chosen width, so its controls keep the room they
    /// have while the button floats; the player grows only when its toggles
    /// leave no room, and never changes where it wraps the camera; the home
    /// page's levels keep their narrowest past it, or share the row below the
    /// camera; a page with nothing for the row still gets one for the button;
    /// and a level reading drops only its percentage where a side has no room.
    private static func sectionsButtonContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let home: [NotchControlItem] = [.volume, .brightness, .music, .mixer, .keepAwake, .timer, .calendar]
        let button = NotchBand.sectionsButtonRoom
        let least = NotchLayout.bandLevelMinimumWidth
        var sizes: [(NotchSize, Double)] = [(.compact, NotchSize.defaultWidth), (.spacious, NotchSize.defaultWidth)]
        sizes += stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 20).map { (.custom, $0) }
        var unchanged = true, widths = true, sides = true, levels = true, below = true, rows = true
        var readings = true, player = true, reached = true, bare = true
        var playerWraps = true, playerWidths = true, playerRow = true
        var narrowestPlayer = CGFloat.infinity
        var movedLevels = 0
        for camera: CGFloat in [0, 156, 170, 180, 185, 190, 200, 208, 210, 224] {
            for (size, custom) in sizes {
                let base = NotchGeometry(screen: screen, safeAreaTop: camera > 0 ? 32 : 0, cameraWidth: camera, layout: size,
                                         customWidth: custom, silhouette: camera > 0 ? .notch : .capsule)
                for module in NotchModule.allCases {
                    let floating = base.page(module, controls: home, sectionsButton: false)
                    let leading = base.page(module, controls: home, sectionsButton: true)
                    let floatingBand = NotchBand(geometry: floating, contentWidth: floating.contentWidth)
                    let band = NotchBand(geometry: leading, contentWidth: leading.contentWidth)
                    unchanged = unchanged && !floatingBand.sectionsButton && !floatingBand.trailingSectionsButton
                        && !floatingBand.pageSectionsButton && floatingBand.leadingRoom == floatingBand.side
                        && floating.expandedWidth == {
                            var plain = base
                            plain.pageTop = module.pageTop
                            plain.pageContentWidth = NotchLayout.naturalContentWidth(module, controls: home, within: base.contentWidth)
                            return plain.expandedWidth
                        }()
                    // The player lays out its leading side itself: its row ends
                    // with the button, or the page shows it where the row cannot.
                    let wraps = module.pageTop == .wrapsCamera
                    sides = sides && band.sectionsButton == !wraps
                        && (band.trailingSectionsButton || band.pageSectionsButton) == wraps
                        && !(band.trailingSectionsButton && band.pageSectionsButton)
                        && band.leadingRoom == band.side - (band.sectionsButton ? button : 0)
                    // Every page leads to the sections: from a row it has, or from the page.
                    reached = reached && (band.pageSectionsButton || leading.headerRowHeight > 0)
                    if module.pageTop == .none, !floatingBand.besideCamera {
                        // A page with nothing for the row starts below the button's row,
                        // keeping the content it has while the button floats.
                        let content = { (page: NotchGeometry) -> CGFloat in page.contentSize(for: page.expandedSize(module: module)).height }
                        bare = bare && floating.headerRowHeight == 0 && leading.headerRowHeight == NotchLayout.headerHeight
                            && leading.pageTopInset == leading.headerTopInset + NotchLayout.headerHeight + NotchLayout.spacing
                            && (size == .custom || content(leading) == content(floating))
                    }
                    if wraps {
                        for count in 0...2 {
                            var page = leading
                            page.pageTrailingControls = count
                            let row = NotchBand(geometry: page, contentWidth: page.contentWidth)
                            let need: CGFloat = CGFloat(count) * button + 28
                            let grew = page.expandedWidth - floating.expandedWidth
                            let roomy = !floatingBand.besideCamera || floatingBand.side >= need
                            // The button never changes whether the player wraps the camera.
                            playerWraps = playerWraps && row.besideCamera == floatingBand.besideCamera
                            // It grows only when the toggles leave no room, and only to hold it there.
                            playerWidths = playerWidths
                                && (roomy ? grew == 0 : grew == 0 || (grew <= button * 2 && row.trailingSectionsButton))
                            // The row holds it where it fits after them, presets beside
                            // common cameras included; elsewhere the page shows it.
                            playerRow = playerRow && row.trailingSectionsButton != row.pageSectionsButton
                                && (!row.trailingSectionsButton || row.side >= need)
                                && (size == .custom || camera > 210 || !row.besideCamera || row.trailingSectionsButton)
                        }
                    } else if band.besideCamera, band.sectionsButton, floating.pageContentWidth != nil {
                        // Each side past the button keeps what a page's row keeps
                        // beside a camera, unless the chosen width stops the island.
                        widths = widths && leading.expandedWidth <= floating.expandedWidth + button * 2
                            && (band.leadingRoom >= floating.pageBandSide - NotchBand.cameraClearance
                                || leading.expandedWidth == base.expandedWidth)
                    } else {
                        // Lists keep the chosen width, and a full row holds the button.
                        widths = widths && leading.expandedWidth == floating.expandedWidth
                    }
                    if band.besideCamera, module.pageTop != .wrapsCamera {
                        readings = readings && band.side >= NotchLayout.levelReadingDetailWidth
                    }
                }
                let page = base.page(.controls, controls: home, sectionsButton: true)
                let band = NotchBand(geometry: page, contentWidth: page.contentWidth)
                let floating = base.page(.controls, controls: home, sectionsButton: false)
                for count in 1...3 {
                    let inRow = NotchLayout.bandLevelCount(count, band: band)
                    if band.besideCamera {
                        // In the row the first level keeps its narrowest past the button.
                        levels = levels && (inRow == 0 || (inRow == count && band.side - button >= least))
                            && (count == 3 || inRow == count || band.side - button < least)
                        // A preset adds the row below the camera to the island when the levels move there.
                        let moved = inRow == 0 && NotchLayout.bandLevelCount(count, band: NotchBand(
                            geometry: floating, contentWidth: floating.contentWidth)) == count
                        if moved, size != .custom {
                            movedLevels += 1
                            below = below && page.expandedSize(module: .controls, sliderCount: count).height
                                - floating.expandedSize(module: .controls, sliderCount: count).height
                                == NotchLayout.levelRowHeight + NotchLayout.rowSpacing
                        }
                    } else {
                        // Across the top every level keeps its narrowest after the button.
                        let held = CGFloat(count) * least + CGFloat(count - 1) * NotchLayout.bandLevelSpacing
                        let used = button + held + NotchLayout.bandLevelSpacing
                        let reading = NotchLayout.homeReadingWidth(levels: count, side: band.leadingRoom)
                        rows = rows && inRow == count && used <= band.side && used + (reading ?? 0) <= band.side
                    }
                }
                let music = base.page(.music, controls: home, sectionsButton: true)
                let musicBand = NotchBand(geometry: music, contentWidth: music.contentWidth)
                if musicBand.besideCamera {
                    // Across from the cover the reading keeps its glyph and a
                    // meter: a preset's player is only as wide as it needs, and
                    // only a wider width set by hand leaves room for the percentage.
                    narrowestPlayer = min(narrowestPlayer, musicBand.side)
                    player = player && (size == .custom || musicBand.side < NotchLayout.levelReadingDetailWidth)
                        && musicBand.side - 18 - 8 >= 36
                }
            }
        }
        suite.expect(unchanged, "with Explore floating the row and every page's width stay as they were")
        suite.expect(sides, "every page but the player starts its row with the sections button, and its controls follow it; the player shows it itself")
        suite.expect(reached, "every page leads to the sections without the floating Explore button")
        suite.expect(bare, "a page with nothing for the row gets one for the sections button where no camera's row holds it")
        suite.expect(widths,
                     "a page with a width of its own grows by the sections button beside a camera, up to the chosen width; lists and full rows keep theirs")
        suite.expect(playerWraps, "the sections button never changes where the player wraps the camera")
        suite.expect(playerWidths, "the player grows by the sections button only when its toggles leave the row no room, and only to hold it there")
        suite.expect(playerRow, "the player's row ends with the sections button where it fits after the toggles; elsewhere the page shows it")
        suite.expect(levels, "a level beside the camera keeps its narrowest past the sections button, or the levels share the row below")
        suite.expect(below && movedLevels > 0,
                     "a preset island grows by the row below the camera when the levels move there: \(movedLevels) islands")
        suite.expect(rows, "a full row holds every level at its narrowest after the sections button, a reading too")
        suite.expect(readings, "every page's row but the player's keeps a level reading's percentage beside a camera")
        suite.expect(player && narrowestPlayer.isFinite,
                     "across from the player's cover a reading keeps its glyph and a meter at least 36 points long: \(narrowestPlayer)")
    }

    /// The views put the island's way to the sections where the band says:
    /// every fallback of the row's trailing side ends a wrapping page's
    /// controls with it, and the player shows it where the row does not.
    private static func sectionsButtonPlacementContracts(_ suite: TestSuite) {
        func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
        let island = source("Sources/Vorssaint/UI/Notch/NotchView.swift")
        let row = (island.components(separatedBy: "private func bandRow(").dropFirst().first ?? "")
            .components(separatedBy: "private func updateControl(").first ?? ""
        let fallbacks = row.components(separatedBy: "HStack(spacing: 6) {").count - 1
        let ends = row.components(separatedBy: "items.trailing; trailingSections(band)").count - 1
        suite.expect(fallbacks == 4 && ends == fallbacks
                     && row.contains("if band.trailingSectionsButton { NotchSectionsButton(action: service.toggleSections) }"),
                     "every fallback of the row's trailing side ends a wrapping page's controls with the sections button")
        let player = source("Sources/Vorssaint/UI/Notch/NotchMusicView.swift")
        let corners = player.components(separatedBy: "} corner: {").dropFirst().map { $0.components(separatedBy: "}").first ?? "" }
        let cornersShowIt = corners.count == 2 && corners.allSatisfy { $0.contains("sectionsButton") }
        let rowItems = (player.components(separatedBy: ".notchBand(trailing: {").dropFirst().first ?? "")
            .components(separatedBy: "})").first ?? ""
        suite.expect(player.contains("if band.pageSectionsButton { NotchSectionsButton(action: NotchService.shared.toggleSections) }")
                     && cornersShowIt && player.contains("extraButtons; sectionsButton }")
                     && player.contains("if band.besideCamera { sectionsButton }") && !rowItems.contains("sectionsButton")
                     && player.contains(".overlay(alignment: .topLeading) { sectionsButton.frame(height: band.height) }"),
                     "the player shows the sections button in its corners, its row of toggles, beside its bars and on the cover's side of the row while it is away, where the row does not")
    }

    /// The home page's rail never scrolls a tile it could show whole. Where
    /// its tiles would just miss the island's width it closes the gaps
    /// between them, so four fit across at every allowed width, beside a
    /// camera and in a capsule; a rail that fit already keeps its gaps.
    private static func homeRailContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let levels: [NotchControlItem] = [.volume, .brightness, .keyboardLight]
        let tiles: [NotchControlItem] = [.mixer, .keepAwake, .timer, .calendar, .microphone, .screenshot, .recording,
                                         .speedTest, .panel, .commandBar, .scratchpad]
        let tile = NotchLayout.shortcutWidth, spacing = NotchLayout.shortcutSpacing
        var sizes: [(NotchSize, Double, Double)] = [(.compact, NotchSize.defaultWidth, NotchSize.defaultHeight),
                                                    (.spacious, NotchSize.defaultWidth, NotchSize.defaultHeight)]
        let heights: [Double] = [NotchSize.heightRange.lowerBound, 340, NotchSize.defaultHeight, NotchSize.heightRange.upperBound]
        for width in stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 10) {
            for height in heights { sizes.append((.custom, width, height)) }
        }
        var whole: String?, kept: String?, inside: String?
        var closed = 0
        let surfaces: [(CGFloat, NotchSilhouette)] = [(0, .capsule), (0, .notch), (185, .notch), (224, .notch)]
        for (camera, silhouette) in surfaces {
            for (size, width, height) in sizes {
                let base = NotchGeometry(screen: screen, safeAreaTop: camera > 0 ? 32 : 0, cameraWidth: camera, layout: size,
                                         customWidth: width, customHeight: height, silhouette: silhouette)
                for count in 0...tiles.count {
                    for music in [false, true] {
                        for levelCount in 0...levels.count {
                            for button in [false, true] {
                                // One part per line: Swift 6.0.3 cannot type-check them as one sum in time.
                                var controls = Array(levels.prefix(levelCount))
                                if music { controls.append(.music) }
                                controls += tiles.prefix(count)
                                // The page as the island draws it: the height it is given, its levels and its rows.
                                let page = base.page(.controls, controls: controls, sectionsButton: button)
                                let content = page.contentSize(for: page.expandedSize(module: .controls, shortcutCount: count,
                                                                                      sliderCount: levelCount,
                                                                                      controlsHaveMusic: music))
                                let band = NotchBand(geometry: page, contentWidth: content.width)
                                let below = NotchLayout.bandLevelCount(levelCount, band: band) < levelCount
                                let pageHeight = max(content.height, NotchLayout.controls(
                                    hasCards: music, levelRow: below, shortcutCount: count,
                                    width: content.width, height: content.height).height)
                                let rows = NotchLayout.controls(hasCards: music, levelRow: below, shortcutCount: count,
                                                                width: content.width, height: pageHeight).shortcutRows
                                guard rows > 0 else { continue }
                                let columns = NotchLayout.railColumns(count: count, rows: rows)
                                let gap = NotchLayout.railGap(columns: columns, itemWidth: tile, spacing: spacing,
                                                              least: NotchLayout.shortcutLeastSpacing, width: content.width)
                                func name() -> String {
                                    let surface: String = camera > 0 ? "\(Int(camera))-point camera" : silhouette == .capsule ? "capsule" : "no camera"
                                    let island: String = size == .custom ? "custom \(Int(width))×\(Int(height))" : size.rawValue
                                    return "\(surface), \(island), \(count) tiles, \(columns) across \(content.width) points"
                                }
                                if gap == nil, columns <= 4 || CGFloat(columns) * tile <= content.width {
                                    whole = whole ?? name()
                                }
                                if NotchLayout.railFits(columns: columns, itemWidth: tile, spacing: spacing, width: content.width),
                                   gap != spacing {
                                    kept = kept ?? name()
                                }
                                if let gap {
                                    if gap < spacing { closed += 1 }
                                    let used: CGFloat = CGFloat(columns) * tile + CGFloat(columns - 1) * gap
                                    if gap < NotchLayout.shortcutLeastSpacing || used > content.width + 0.001 {
                                        inside = inside ?? name()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        suite.expect(whole == nil,
                     "the home page's tiles never scroll while they fit side by side, four across at every allowed width: \(whole ?? "")")
        suite.expect(kept == nil, "a home page rail that fit with its gaps keeps them: \(kept ?? "")")
        suite.expect(inside == nil && closed > 0,
                     "a rail that closes its gaps stays inside the page and keeps at least the least gap: \(inside ?? "") (\(closed) closed)")
        // The narrowest island in the reported setup: eight tiles, three
        // levels across the capsule's row and no player, two rows of four.
        var narrowControls = levels
        narrowControls += tiles.prefix(8)
        let narrowest = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: .custom,
                                      customWidth: NotchSize.widthRange.lowerBound,
                                      customHeight: NotchSize.heightRange.lowerBound, silhouette: .capsule)
            .page(.controls, controls: narrowControls, sectionsButton: false)
        let content = narrowest.contentSize(for: narrowest.expandedSize(module: .controls, shortcutCount: 8, sliderCount: 3,
                                                                        controlsHaveMusic: false))
        let rows = NotchLayout.controls(hasCards: false, shortcutCount: 8, width: content.width, height: content.height).shortcutRows
        let narrowGap = NotchLayout.railGap(columns: NotchLayout.railColumns(count: 8, rows: rows), itemWidth: tile,
                                            spacing: spacing, least: NotchLayout.shortcutLeastSpacing, width: content.width)
        suite.expect(content.width == CGFloat(304) && rows == 2 && narrowGap == CGFloat(0),
                     "at the narrowest width eight tiles sit in two rows of four with their gaps closed")
        // The island and its Layout preview hand the rail the same least gap.
        for path in ["Sources/Vorssaint/UI/Notch/NotchControlsView.swift", "Sources/Vorssaint/UI/Settings/NotchLayoutEditor.swift"] {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            suite.expect(source.components(separatedBy: "leastSpacing: NotchLayout.shortcutLeastSpacing").count == 2,
                         "the home page's rail closes its gaps before it scrolls in \(path)")
        }
    }

    /// A home page rail a few points short of its next row closes its rows,
    /// as it closes its columns, before it scrolls sideways: down to 6 points,
    /// where a title on two lines sits as near the circle under it as its own
    /// circle above. Any other rail keeps its rows and gaps, presets included.
    private static func homeRailRowContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let levels: [NotchControlItem] = [.volume, .brightness, .keyboardLight]
        let tiles: [NotchControlItem] = [.mixer, .keepAwake, .timer, .calendar, .microphone, .screenshot, .recording,
                                         .speedTest, .panel, .commandBar, .scratchpad]
        let tile = NotchLayout.shortcutWidth, row = NotchLayout.shortcutHeight, spacing = NotchLayout.shortcutSpacing
        var sizes: [(NotchSize, Double, Double)] = [(.compact, NotchSize.defaultWidth, NotchSize.defaultHeight),
                                                    (.spacious, NotchSize.defaultWidth, NotchSize.defaultHeight)]
        // The slider's lowest steps, heights the Layout tab's corner reaches
        // between them, and taller islands.
        let heights: [Double] = [NotchSize.heightRange.lowerBound, 261, 262.5, 264, 266, 268, 270, 340,
                                 NotchSize.heightRange.upperBound]
        for width in stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 20) {
            for height in heights { sizes.append((.custom, width, height)) }
        }
        // Cameras from a scaled display's short one to a tall menu bar's.
        var surfaces: [(CGFloat, CGFloat, NotchSilhouette)] = [(0, 0, .capsule), (0, 0, .notch)]
        for top: CGFloat in [28, 32, 38] {
            surfaces += [(top, 156, .notch), (top, 224, .notch)]
        }
        var taken: String?, kept: String?, tight: String?, filled: String?
        var closed = 0
        for (top, camera, silhouette) in surfaces {
            for (size, width, height) in sizes {
                let base = NotchGeometry(screen: screen, safeAreaTop: top, cameraWidth: camera, layout: size,
                                         customWidth: width, customHeight: height, silhouette: silhouette)
                for count in 1...tiles.count {
                    for music in [false, true] {
                        // No levels, one on each side of a camera, or three in a row below it.
                        for levelCount in [0, 2, 3] {
                            for button in [false, true] {
                                // One part per line: Swift 6.0.3 cannot type-check them as one sum in time.
                                var controls = Array(levels.prefix(levelCount))
                                if music { controls.append(.music) }
                                controls += tiles.prefix(count)
                                let page = base.page(.controls, controls: controls, sectionsButton: button)
                                let content = page.contentSize(for: page.expandedSize(module: .controls, shortcutCount: count,
                                                                                      sliderCount: levelCount,
                                                                                      controlsHaveMusic: music))
                                let band = NotchBand(geometry: page, contentWidth: content.width)
                                let below = NotchLayout.bandLevelCount(levelCount, band: band) < levelCount
                                // The page as the island draws it, from the height it is given.
                                let pageHeight = max(content.height, NotchLayout.controls(
                                    hasCards: music, levelRow: below, shortcutCount: count,
                                    width: content.width, height: content.height).height)
                                let layout = NotchLayout.controls(hasCards: music, levelRow: below, shortcutCount: count,
                                                                  width: content.width, height: pageHeight)
                                // The most the island gives the rail, and the rows that held at the full gap.
                                let levelRow: CGFloat = NotchLayout.levelRowHeight + NotchLayout.rowSpacing
                                let card: CGFloat = NotchLayout.minimumCardHeight + NotchLayout.rowSpacing
                                var room = page.contentBudget
                                if below && size != .custom { room += levelRow }
                                var rail = room
                                if below { rail -= levelRow }
                                if music { rail -= card }
                                let perRow = NotchLayout.railCapacity(width: content.width, itemWidth: tile, spacing: spacing)
                                let full = NotchLayout.railRows(count: count, perRow: perRow, rowHeight: row,
                                                                spacing: spacing, height: rail)
                                let scrolls = NotchLayout.railGap(columns: NotchLayout.railColumns(count: count, rows: full),
                                                                  itemWidth: tile, spacing: spacing,
                                                                  least: NotchLayout.shortcutLeastSpacing, width: content.width) == nil
                                func name() -> String {
                                    let surface: String = camera > 0 ? "\(Int(camera))×\(top) camera" : silhouette == .capsule ? "capsule" : "no camera"
                                    let island: String = size == .custom ? "custom \(Int(width))×\(height)" : size.rawValue
                                    return "\(surface), \(island), \(count) tiles, music \(music), \(levelCount) levels, sections button \(button)"
                                }
                                let closedRows: CGFloat = CGFloat(full + 1) * row + CGFloat(full) * 6
                                if scrolls, closedRows <= rail {
                                    closed += 1
                                    if layout.shortcutRows != full + 1 { taken = taken ?? name() }
                                    if abs(content.height - room) > 0.001 { filled = filled ?? name() }
                                } else if layout.shortcutRows != full || layout.shortcutRowSpacing != spacing {
                                    kept = kept ?? name()
                                }
                                let rowGap = layout.shortcutRowSpacing
                                let outside = rowGap < CGFloat(6) || rowGap > spacing
                                let presetMoved = size != .custom && rowGap != spacing
                                if outside || presetMoved || layout.height > pageHeight + CGFloat(0.001) {
                                    tight = tight ?? name()
                                }
                            }
                        }
                    }
                }
            }
        }
        suite.expect(taken == nil && closed > 0,
                     "a home page rail that would scroll takes the row it is a few points short of, its rows closed: \(taken ?? "") (\(closed) closed)")
        suite.expect(kept == nil, "any other home page rail keeps its rows and their gaps: \(kept ?? "")")
        suite.expect(tight == nil,
                     "rows close no further than 6 points, never in a preset, and stay inside the page: \(tight ?? "")")
        suite.expect(filled == nil, "an island whose rows close takes the height chosen for it: \(filled ?? "")")
        // The report: eight shortcuts and no player in the smallest custom
        // island, its row below a 32-point camera, 2 points short of a second
        // row. Its rows close to 6 points and hold all eight, four across.
        for camera: CGFloat in [156, 185, 224] {
            var cameraControls = Array(levels.prefix(2))
            cameraControls += tiles.prefix(8)
            let page = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: camera, layout: .custom,
                                     customWidth: NotchSize.widthRange.lowerBound,
                                     customHeight: NotchSize.heightRange.lowerBound)
                .page(.controls, controls: cameraControls, sectionsButton: false)
            let island = page.expandedSize(module: .controls, shortcutCount: 8, sliderCount: 2, controlsHaveMusic: false)
            let content = page.contentSize(for: island)
            let layout = NotchLayout.controls(hasCards: false, shortcutCount: 8, width: content.width, height: content.height)
            let gap = NotchLayout.railGap(columns: NotchLayout.railColumns(count: 8, rows: layout.shortcutRows),
                                          itemWidth: tile, spacing: spacing, least: NotchLayout.shortcutLeastSpacing,
                                          width: content.width)
            let fills = page.headerCameraGap == 0 && island.height == CGFloat(NotchSize.heightRange.lowerBound)
            let twoRows = layout == NotchControlsLayout(cardRow: 0, shortcutRows: 2, shortcutRowSpacing: 6)
            suite.expect(fills && content == CGSize(width: 304, height: 154) && twoRows && gap == CGFloat(0),
                         "below a \(Int(camera))-point camera the smallest island holds eight shortcuts in two rows of four")
        }
        // The island and its Layout preview space the rows as the layout does.
        for (path, call) in [("Sources/Vorssaint/UI/Notch/NotchControlsView.swift", "rowSpacing: layout.shortcutRowSpacing"),
                             ("Sources/Vorssaint/UI/Settings/NotchLayoutEditor.swift", "rowSpacing: controls.shortcutRowSpacing")] {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            suite.expect(source.components(separatedBy: call).count == 2,
                         "the home page's rail spaces its rows as its layout does in \(path)")
        }
    }

    /// The Tools page's rail never scrolls a column it could show whole
    /// either. Its titles span their cells, so where it closes its gaps they
    /// give up what was closed and stay as far apart as anywhere else, and
    /// the arrows walk rows exactly when the rail draws rows.
    private static func toolRailContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let tile = NotchLayout.toolWidth, spacing = NotchLayout.toolSpacing
        var sizes: [(NotchSize, Double, Double)] = [(.compact, NotchSize.defaultWidth, NotchSize.defaultHeight),
                                                    (.spacious, NotchSize.defaultWidth, NotchSize.defaultHeight)]
        let heights: [Double] = [NotchSize.heightRange.lowerBound, 280, 300, 340, 400, NotchSize.defaultHeight,
                                 NotchSize.heightRange.upperBound]
        for width in stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 5) {
            for height in heights { sizes.append((.custom, width, height)) }
        }
        let surfaces: [(CGFloat, NotchSilhouette)] = [(0, .capsule), (0, .notch), (156, .notch), (185, .notch), (210, .notch),
                                                      (224, .notch)]
        let tools = QuickLauncherContract.QuickLauncherItem.allCases.count
        var whole: String?, kept: String?, apart: String?, walk: String?
        var closed = 0
        for (camera, silhouette) in surfaces {
            for (size, width, height) in sizes {
                let base = NotchGeometry(screen: screen, safeAreaTop: camera > 0 ? 32 : 0, cameraWidth: camera, layout: size,
                                         customWidth: width, customHeight: height, silhouette: silhouette)
                for button in [false, true] {
                    // The page as the island draws it, for as many tools as the launcher lists.
                    let page = base.page(.tools, controls: [], sectionsButton: button)
                    for count in 1...tools {
                        let content = page.contentSize(for: page.expandedSize(module: .tools, toolCount: count))
                        let perRow = NotchLayout.railCapacity(width: content.width, itemWidth: tile, spacing: spacing)
                        let rows = NotchLayout.railRows(count: count, perRow: perRow, rowHeight: NotchLayout.toolHeight,
                                                        spacing: spacing, height: content.height)
                        let columns = NotchLayout.railColumns(count: count, rows: rows)
                        let side = CGFloat(columns) * tile
                        let gap = NotchLayout.railGap(columns: columns, itemWidth: tile, spacing: spacing,
                                                      least: NotchLayout.toolLeastSpacing, width: content.width)
                        let inset = NotchLayout.toolTitleInset(count: count, rows: rows, width: content.width)
                        func name() -> String {
                            let surface = camera > 0 ? "\(Int(camera))-point camera" : "\(silhouette.rawValue)"
                            let chosen = size == .custom ? "custom \(Int(width))×\(Int(height))" : size.rawValue
                            return "\(surface), \(chosen), \(count) tools, \(columns) across \(content.width) points"
                        }
                        if gap == nil, side <= content.width {
                            whole = whole ?? name()
                        }
                        let fitsWithGaps = NotchLayout.railFits(columns: columns, itemWidth: tile, spacing: spacing,
                                                                width: content.width)
                        if fitsWithGaps, gap != spacing || inset != 0 {
                            kept = kept ?? name()
                        }
                        if gap == nil, inset != 0 {
                            kept = kept ?? name()
                        }
                        if let gap {
                            if gap < spacing { closed += 1 }
                            let used: CGFloat = side + CGFloat(columns - 1) * gap
                            let titlesApart: CGFloat = gap + inset * 2
                            let inside = gap >= NotchLayout.toolLeastSpacing && used <= content.width + 0.001
                            if !inside || abs(titlesApart - spacing) > 0.001 {
                                apart = apart ?? name()
                            }
                        }
                        let drawn: QuickToolsSupport.GridFlow = gap == nil ? .columns(rows: rows) : .rows(columns: columns)
                        if page.toolFlow(count: count) != drawn || page.toolRows(count: count) != rows {
                            walk = walk ?? name()
                        }
                    }
                }
            }
        }
        suite.expect(whole == nil,
                     "the Tools page's tiles never scroll while they fit side by side, four across at every allowed width: \(whole ?? "")")
        suite.expect(kept == nil,
                     "a Tools rail that fits with its gaps, or scrolls, keeps its gaps and its titles' full width: \(kept ?? "")")
        suite.expect(apart == nil && closed > 0,
                     "titles in a Tools rail that closed its gaps stay as far apart as its spacing keeps them: \(apart ?? "") (\(closed) closed)")
        suite.expect(walk == nil, "the Tools arrows walk rows exactly when the rail draws rows: \(walk ?? "")")
        // The reported setup: eight tools at the narrowest island, in a
        // capsule and beside cameras, two rows of four.
        for camera: CGFloat in [0, 185, 224] {
            let page = NotchGeometry(screen: screen, safeAreaTop: camera > 0 ? 32 : 0, cameraWidth: camera, layout: .custom,
                                     customWidth: NotchSize.widthRange.lowerBound,
                                     customHeight: NotchSize.heightRange.lowerBound,
                                     silhouette: camera > 0 ? .notch : .capsule)
                .page(.tools, controls: [], sectionsButton: false)
            let content = page.contentSize(for: page.expandedSize(module: .tools, toolCount: 8))
            let rows = page.toolRows(count: 8)
            let gap = NotchLayout.railGap(columns: 4, itemWidth: tile, spacing: spacing,
                                          least: NotchLayout.toolLeastSpacing, width: content.width)
            let inset = NotchLayout.toolTitleInset(count: 8, rows: rows, width: content.width)
            let twoRowsOfFour = content.width == 304 && rows == 2
            let closedAndInset = gap == CGFloat(0) && inset == spacing / 2
            suite.expect(twoRowsOfFour && closedAndInset,
                         "at the narrowest width eight tools sit in two rows of four, gaps closed and titles inset: \(camera)")
            suite.expect(page.toolFlow(count: 8) == .rows(columns: 4),
                         "at the narrowest width the Tools arrows walk two rows of four: \(camera)")
        }
        // The island's page and the Content tab's preview share the view.
        let source = (try? String(contentsOfFile: "Sources/Vorssaint/UI/QuickLauncher/QuickLauncherView.swift",
                                  encoding: .utf8)) ?? ""
        let rail = source.contains("leastSpacing: NotchLayout.toolLeastSpacing")
        let titles = source.contains("cell(item, titleInset: titleInset)") && source.contains(".padding(.horizontal, titleInset)")
        suite.expect(rail && titles, "the Tools page's rail closes its gaps before it scrolls and insets its titles by them")
    }

    private static func noticeLayoutContracts(_ suite: TestSuite) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let screen = CGRect(x: -1470, y: 100, width: 1470, height: 956)
        for language in AppLanguage.allCases {
            let text = FeatureStrings.notch(language)
            let activities = FeatureStrings.notchActivities(language)
            let notices = [text.onBattery, text.charging, text.charged, text.lowBattery].map {
                NotchNotice(event: .battery, title: $0, detail: "100%", symbol: "battery.100percent.bolt")
            } + [NotchNotice(event: .accessory, title: activities.connected, detail: "Wireless Headphones", symbol: "headphones"),
                 NotchNotice(event: .accessory, title: "Wireless Keyboard", detail: activities.lowBattery + " · 15%",
                             symbol: "keyboard", level: 0.15)]
            for physical in [false, true] {
                for height: CGFloat in [16, 24, 32, 40, 64] {
                    let geometry = NotchGeometry(screen: screen, safeAreaTop: physical ? height : 0,
                                                 cameraWidth: physical ? 180 : 0, menuBarHeight: height)
                    for notice in notices {
                        let wings = notice.wings(in: geometry)
                        func content(_ wing: CGFloat) -> CGFloat { wing - notice.inset(wing: wing) - notice.cameraGap }
                        suite.expect(width(notice.level == nil ? notice.title : notice.detail) + 18 + 8 <= content(wings.leading),
                               "power labels and connection status fit beside their icon in \(language)")
                        suite.expect(notice.level != nil || width(notice.detail) <= content(wings.trailing),
                               "a device name and a charge percentage fit the opposite wing in \(language)")
                        let size = geometry.noticeSize(wings: wings)
                        var shifted = geometry
                        shifted.surfaceShift = geometry.noticeShift(wings)
                        let frame = shifted.frame(for: size)
                        suite.expect(size.width == wings.leading + wings.trailing + geometry.cameraWidth && size.height == height
                               && screen.contains(frame)
                               && abs(frame.minX + wings.leading - (screen.midX - geometry.cameraWidth / 2)) < 0.001,
                               "content-sized notices keep the camera's gap over it, the menu height and the display bounds")
                    }
                }
            }
        }
        for event in [NotchEvent.volume, .brightness, .keyboardLight] {
            for percent in 0...100 {
                let notice = NotchNotice(event: event, title: "Level", detail: "\(percent)%",
                                         symbol: "speaker.wave.2", level: Double(percent) / 100)
                let wing = notice.preferredWingWidth
                let content = width(notice.detail) + 18 + 8
                suite.expect(content + NotchNotice.levelInset <= wing && wing < content + NotchNotice.levelInset + 1
                             && notice.inset(wing: wing) == NotchNotice.levelInset,
                             "a level's wings fit its mark and reading, with no empty black at the end")
                suite.expect(wing - NotchNotice.levelInset >= 40,
                             "the opposite meter remains readable beside the shortest reading")
            }
        }
        let long = NotchNotice(event: .accessory, title: "Connected",
                               detail: String(repeating: "Device ", count: 100), symbol: "headphones")
        suite.expect(long.preferredWingWidth == 160 && long.accessibilityText.contains(long.detail),
               "very long device names have bounded visual width and retain their full accessible name")
        // The name takes a wing of its own instead of sharing one with the
        // icon, so a common name no longer needs shortening.
        let trackpad = NotchNotice(event: .accessory, title: "Connected", detail: "Alex’s Magic Trackpad",
                                   symbol: "rectangle.and.hand.point.up.left")
        suite.expect(trackpad.preferredWingWidth < 160
               && width(trackpad.detail) + 16 + trackpad.cameraGap <= trackpad.preferredWingWidth,
               "a device name fits its wing whole, with the gap its text keeps from the camera")
        suite.expect(trackpad.readsFromEnds && trackpad.cameraGap > 0
               && !NotchNotice(event: .volume, title: "Volume", detail: "40%", symbol: "speaker", level: 0.4).readsFromEnds
               && NotchNotice(event: .volume, title: "Volume", detail: "40%", symbol: "speaker", level: 0.4).cameraGap == 0
               && NotchNotice(event: .battery, title: "Charging", detail: "80%", symbol: "battery.100percent.bolt").cameraGap == 16,
               "text reads from the island's ends while levels keep hugging the camera")
        let narrow = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 640, height: 480),
                                   safeAreaTop: 32, cameraWidth: 210)
        let size = narrow.noticeSize(wingWidth: long.preferredWingWidth)
        suite.expect(size.width <= narrow.screen.width - 24 && size.height == narrow.menuBarHeight,
               "long device names cannot push a notice past a narrow display")
        notificationBannerContracts(suite, screen: screen)
    }

    /// Mirrored banners take the width their longer side needs, as the other
    /// notices do, instead of one wide strip for every message (issue #2266).
    private static func notificationBannerContracts(_ suite: TestSuite, screen: CGRect) {
        let layout = NotchNotificationBannerLayout.self
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        func banner(app: String = "Messages", _ title: String, subtitle: String = "", _ body: String) -> NotchNotice {
            NotchNotice(event: .systemNotification, title: title, detail: body, symbol: "bell.fill",
                        notification: NotchNotificationContent(app: app, title: title, subtitle: subtitle, body: body),
                        notificationID: UUID())
        }
        let short = banner("Alex", "done")
        let fitted = [short, banner("Verification code", "Your code is 482913"),
                      banner(app: "Reminders", "", "Stand up"), banner("Alex", "ok\nsee you at the station"),
                      banner(app: "Calendar", "会议提醒", subtitle: "明天", "项目评审 🚀")]
        for notice in fitted {
            guard let content = notice.notification else { continue }
            let wings = notice.preferredWings
            suite.expect(layout.iconSize + layout.spacing + width(content.compactTitle, layout.titleFont) <= wings.leading - layout.inset
                         && width(content.compactDetail, layout.messageFont) <= wings.trailing - layout.inset
                         && wings.widest < layout.wingRange.upperBound,
                         "a short message and its title fit whole in a banner narrower than the widest one")
        }
        // Issue: a one-word reply beside a long sender left a band of empty
        // black after the word; each side now takes only what it shows.
        let reply = banner("+55 11 90000-0000", "Oi")
        suite.expect(reply.preferredWings.trailing == max(layout.wingRange.lowerBound,
                                                          width("Oi", layout.messageFont).rounded(.up) + layout.inset + layout.air)
                     && reply.preferredWings.trailing < reply.preferredWings.leading
                     && short.preferredWings.trailing < short.preferredWings.leading,
                     "a one-word message leaves no band of empty black beside it")
        let wrapping = banner("Ana", "Chego em 10 minutos, me espera na entrada")
        let wrapped = wrapping.preferredWings(wrapsMessage: true).trailing
        suite.expect(wrapping.preferredWings.trailing == layout.wingRange.upperBound
                     && wrapped < layout.wingRange.upperBound && wrapped > layout.wingRange.upperBound / 2,
                     "a message wrapped onto two lines takes the width of its lines, not the whole side")
        // The wing is measured with AppKit; SwiftUI draws the text. The air
        // has to cover any difference, in every script a banner can carry.
        for sample in ["done", "Your code is 482913", "会议提醒 项目评审", "🚀🎉 launch", "مرحبا بالعالم", "שלום עולם"] {
            for font in [layout.titleFont, layout.messageFont] {
                let drawn = NSHostingView(rootView: Text(sample).font(Font(font as CTFont)).lineLimit(1).fixedSize())
                    .fittingSize.width
                suite.expect(drawn <= width(sample, font).rounded(.up) + layout.air,
                             "a banner's text draws within the width measured for it")
            }
        }
        let long = banner(app: "Mail", "Quarterly planning", subtitle: "Agenda",
                          String(repeating: "Notes for the meeting ", count: 800))
        suite.expect(long.preferredWingWidth == layout.wingRange.upperBound,
                     "a long message keeps the widest banner and wraps or truncates within it")
        var replacement = short
        replacement.minimumWings = long.preferredWings
        suite.expect(replacement.preferredWings.trailing == long.preferredWings.trailing
                     && replacement.preferredWings.leading >= long.preferredWings.leading,
                     "a banner replacing a wider one keeps each of its sides")
        for physical in [false, true] {
            let geometry = NotchGeometry(screen: screen, safeAreaTop: physical ? 32 : 0,
                                         cameraWidth: physical ? 180 : 0, menuBarHeight: 32)
            let compact = geometry.noticeSize(wings: short.preferredWings)
            let widest = geometry.noticeSize(wings: long.preferredWings)
            var shifted = geometry
            shifted.surfaceShift = geometry.noticeShift(long.preferredWings)
            suite.expect(compact.width == geometry.cameraWidth + short.preferredWings.leading + short.preferredWings.trailing
                         && compact.width < widest.width && screen.contains(shifted.frame(for: widest)),
                         "a short banner narrows around the camera, and the widest stays on the display")
        }
    }

    private static func simulatedMenuBoundsContracts(_ suite: TestSuite) {
        let screen = CGRect(x: -1470, y: 100, width: 1470, height: 956)
        for height: CGFloat in [16, 22, 24, 32, 40, 64] {
            let bar = CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
            for room: CGFloat? in [nil, 0, 12, 43, 44, 56, 64] {
                let geometry = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0,
                                             menuBarHeight: height, compactSideRoom: room)
                let sizes = [geometry.restingSize(showsContent: false), geometry.collapsed,
                             geometry.notice, geometry.noticeSize(wingWidth: 190),
                             geometry.compactMusicGeometry.compactActivitySize,
                             geometry.compactTimerGeometry(showsDownloads: false).compactActivitySize,
                             geometry.compactTimerGeometry(showsDownloads: true).compactActivitySize,
                             geometry.compactActivitySize]
                for size in sizes {
                    suite.expect(bar.contains(geometry.frame(for: size)),
                           "every closed or compact simulated surface stays entirely within the actual menu bar")
                }
                suite.expect(abs(geometry.cameraWidth / geometry.cameraHeight - 180.0 / 32) < 0.001,
                       "fitting a shorter menu bar scales the whole simulated camera profile proportionally")
            }
            var crowded = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: height)
            let camera = crowded.frame(for: crowded.restingSize(showsContent: false))
            let occupied = [CGRect(x: screen.minX, y: bar.minY, width: camera.minX - screen.minX - 10, height: height),
                            CGRect(x: camera.maxX + 10, y: bar.minY, width: screen.maxX - camera.maxX - 10, height: height)]
            crowded.compactSideRoom = NotchMenuBarLayout.sideRoom(screen: screen, cameraWidth: crowded.cameraWidth,
                                                                 barHeight: height, occupied: occupied)
            for size in [crowded.collapsed, crowded.compactMusicGeometry.compactActivitySize,
                         crowded.compactTimerGeometry(showsDownloads: true).compactActivitySize] {
                suite.expect(!occupied.contains(where: { $0.intersects(crowded.frame(for: size)) }),
                       "simulated idle, music and timer wings never cover measured neighboring menus")
            }
        }
    }

    private static func simulatedDisplayContracts(_ suite: TestSuite) {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: -100, width: 1920, height: 1080),
                       CGRect(x: 100, y: 982, width: 900, height: 1440),
                       CGRect(x: 0, y: 0, width: 640, height: 480)]
        let rooms: [CGFloat?] = [nil, 0, 43, 64, 200, .nan, .infinity]
        for screen in screens {
            for barHeight: CGFloat in [16, 24, 32, 40, 64] {
                let physical = NotchGeometry(screen: screen, safeAreaTop: barHeight, cameraWidth: 180 * barHeight / 32,
                                             menuBarHeight: barHeight)
                for room in rooms {
                    let geometry = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0,
                                                 menuBarHeight: barHeight, compactSideRoom: room)
                    suite.expect(!geometry.isNotched && geometry.cameraWidth == physical.cameraWidth
                           && geometry.cameraHeight == physical.cameraHeight
                           && geometry.safeContentTop == physical.safeContentTop,
                           "a simulated notch keeps the physical profile and content clearance without claiming hardware exists")
                    suite.expect(geometry.restingSize(showsContent: false) == physical.restingSize(showsContent: false)
                           && geometry.notice == physical.notice && geometry.expanded.width == physical.expanded.width
                           && geometry.contentSize(for: geometry.expanded) == physical.contentSize(for: physical.expanded),
                           "simulated and physical cutouts share compact proportions and the same usable page budget")
                    let sizes = [geometry.restingSize(showsContent: false), geometry.collapsed, geometry.peek,
                                 geometry.notice, geometry.noticeSize(wingWidth: 190)]
                        + NotchModule.allCases.map { geometry.expandedSize(module: $0) }
                        + [geometry.sectionPickerSize(count: NotchModule.allCases.count)]
                    for size in sizes {
                        let positioned = geometry.frame(for: size)
                        suite.expect(screen.contains(positioned) && positioned.midX == screen.midX
                               && positioned.maxY == screen.maxY,
                               "every simulated presentation grows directly from the screen edge and stays within its display")
                    }
                    for activity in [geometry, geometry.compactMusicGeometry,
                                     geometry.compactTimerGeometry(showsDownloads: false),
                                     geometry.compactTimerGeometry(showsDownloads: true)] {
                        let positioned = activity.frame(for: activity.compactActivitySize)
                        let activation = activity.activationArea(in: activity.compactActivitySize, hasHeader: false,
                                                                 compactActivity: true)
                        suite.expect(positioned.maxY == screen.maxY && screen.contains(positioned)
                               && (activity.compactActivityWingWidth == 0 || activity.compactActivityWingWidth >= 44)
                               && activity.compactActivityContentHeight == barHeight,
                               "simulated activities keep complete measured wings or just the cutout, within the menu bar")
                        suite.expect(activity.compactActivityCameraGap == physical.cameraWidth && !activity.compactActivityUsesFooter
                               && activation.width == physical.cameraWidth
                               && activation.midX == activity.compactActivitySize.width / 2,
                               "the simulated camera opens the island while its neighboring controls keep their own click targets")
                    }
                }
            }
        }
    }

    private static func menuSpaceReuseContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let previous = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 24, compactSideRoom: 0)
        let largerBar = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 32)
        let menu = CGRect(x: screen.midX + previous.cameraWidth / 2 + 4, y: screen.maxY - 24, width: 80, height: 24)
        suite.expect(NotchMenuBarLayout.sideRoom(screen: screen, cameraWidth: previous.cameraWidth, barHeight: 24, occupied: [menu]) != nil
               && NotchMenuBarLayout.sideRoom(screen: screen, cameraWidth: largerBar.cameraWidth, barHeight: 32, occupied: [menu]) == nil,
               "a taller simulated cutout can occupy a menu that was clear before the bar changed")
        suite.expect(!largerBar.hasSameMenuBar(as: previous),
               "a changed menu bar cannot reuse clearance from a narrower simulated camera")
        let moved = NotchGeometry(screen: screen.offsetBy(dx: -1440, dy: 900), safeAreaTop: 0, cameraWidth: 0)
        suite.expect(!moved.hasSameMenuBar(as: previous), "another display cannot reuse the previous menu measurement")
        for layout in NotchSize.allCases {
            let resized = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: layout)
            suite.expect(resized.hasSameMenuBar(as: previous),
                   "changing the expanded size preserves valid menu clearance without flicker")
        }
    }

    private static func menuBarHeightContracts(_ suite: TestSuite) {
        var measurements = NotchMenuBarMeasurements()
        let screen = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        func read(_ id: UInt32, gap: CGFloat, frame: CGRect = CGRect(x: -1440, y: -900, width: 1440, height: 900),
                  scale: CGFloat = 2, fallback: CGFloat = 22) -> CGFloat {
            measurements.height(displayID: id, frame: frame, visibleTop: frame.maxY - gap,
                                scale: scale, statusBarThickness: fallback)
        }
        for gap: CGFloat in [16, 24, 37, 64] {
            suite.expect(NotchMenuBarMeasurements.showsBar(frame: screen, visibleTop: screen.maxY - gap),
                   "a bar reserving its height at the top of the visible frame is on screen")
        }
        for gap: CGFloat in [0, 1, -10, 15, 65, 600, .nan, .infinity] {
            suite.expect(!NotchMenuBarMeasurements.showsBar(frame: screen, visibleTop: screen.maxY - gap),
                   "a bar that hides until revealed, or a display without one, reserves no room")
        }
        for height: CGFloat in [16, 22, 24, 28, 30, 32, 33, 37, 64] {
            suite.expect(read(1, gap: height) == height, "the selected display's current visible bar supplies its height")
            let geometry = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: height)
            suite.expect(geometry.collapsed.height == height && geometry.compactMusicGeometry.compactActivitySize.height == height,
                   "the simulated cutout and music strip stay within the measured bar")
            for gap: CGFloat in [0, 1, -10, 15, 65, 600, .nan, .infinity] {
                suite.expect(read(1, gap: gap) == height, "hiding or an unavailable reading retains this display's measured height")
            }
        }
        suite.expect(read(1, gap: 24) == 24 && read(2, gap: 33) == 33,
               "displays with different menu bars keep independent measurements")
        for _ in 0..<3 {
            suite.expect(read(1, gap: 0) == 24 && read(2, gap: 0) == 33,
                   "switching displays and changing other preferences while bars are hidden preserves both heights")
        }
        suite.expect(read(3, gap: 0) == 22 && read(3, gap: 0, fallback: .nan) == 24,
               "a display first seen with a hidden bar uses a safe native fallback, never another display's height")
        suite.expect(read(3, gap: 30) == 30 && read(3, gap: 0) == 30,
               "revealing a previously unknown bar replaces the fallback and survives hiding again")
        suite.expect(read(1, gap: 0, frame: screen.offsetBy(dx: 1440, dy: 1800)) == 24,
               "moving a display in the arrangement preserves its mode's measured height")
        suite.expect(read(1, gap: 0, scale: 1) == 22 && read(1, gap: 0, scale: 2) == 22,
               "a scale change invalidates the old height even after changing back while the bar stays hidden")
        _ = read(1, gap: 30)
        suite.expect(read(1, gap: 0, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)) == 22,
               "a new screen resolution cannot inherit a previous mode's height")
        measurements.retainDisplays([1, 3])
        suite.expect(read(2, gap: 0) == 22 && read(3, gap: 0) == 30,
               "disconnecting a display drops its history without affecting the remaining display")
        suite.expect(read(0, gap: 37) == 37 && read(0, gap: 0) == 22,
               "an unknown display identity can use its current reading but cannot share remembered measurements")
        _ = read(1, gap: 30, scale: .nan)
        suite.expect(read(1, gap: 0) == 22, "an invalid display mode cannot seed remembered height")
        var fresh = NotchMenuBarMeasurements()
        for invalid: CGFloat in [0, -1, 15, 65, .nan, .infinity] {
            suite.expect(fresh.height(displayID: 1, frame: screen, visibleTop: screen.maxY,
                                scale: 2, statusBarThickness: invalid) == 24,
                   "invalid fallback heights never escape the safe range")
        }
    }

    /// By default the island is the housing macOS reports; covering the menu bar below it is opt-in.
    private static func physicalStripContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        for safeTop: CGFloat in [24, 32, 37.5, 40] {
            for barHeight: CGFloat in [24, 32, 33, 37, 38, 39, 40, 64] {
                let geometry = NotchGeometry(screen: screen, safeAreaTop: safeTop, cameraWidth: 179,
                                             menuBarHeight: barHeight, compactSideRoom: 100)
                let strips = [geometry.restingSize(showsContent: false), geometry.restingSize(showsContent: true),
                              geometry.collapsed, geometry.bareCutout, geometry.notice,
                              geometry.noticeSize(wingWidth: 190), geometry.compactMusicGeometry.compactActivitySize,
                              geometry.compactTimerGeometry(showsDownloads: true).compactActivitySize]
                for size in strips {
                    suite.expect(size.height == safeTop && size.height == geometry.stripHeight,
                           "every physical strip is exactly as tall as the cutout, so it never reaches below the notch")
                }
                suite.expect(geometry.menuBarHeight == max(safeTop, barHeight),
                       "the bar's own height remains available for measuring menu space")
                let covering = NotchGeometry(screen: screen, safeAreaTop: safeTop, cameraWidth: 179,
                                             menuBarHeight: barHeight, compactSideRoom: 100, hideMenuBarGap: true)
                let covered = [covering.restingSize(showsContent: false), covering.restingSize(showsContent: true),
                               covering.collapsed, covering.bareCutout, covering.notice,
                               covering.noticeSize(wingWidth: 190), covering.compactMusicGeometry.compactActivitySize,
                               covering.compactTimerGeometry(showsDownloads: true).compactActivitySize]
                for size in covered {
                    suite.expect(size.height == max(safeTop, barHeight) && size.height == covering.stripHeight
                           && covering.frame(for: size).minY <= screen.maxY - barHeight,
                           "hiding the gap covers the bar's bottom edge without leaving a wallpaper seam")
                }
            }
        }
        for silhouette in NotchSilhouette.allCases {
            let enabled = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0,
                                        silhouette: silhouette, hideMenuBarGap: true)
            let disabled = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0,
                                         silhouette: silhouette, hideMenuBarGap: false)
            suite.expect(enabled == disabled, "gap hiding leaves simulated notches and floating capsules unchanged")
        }
        let closed = NotchLayout.surfaceRadius(height: 32)
        suite.expect(closed >= 8 && closed <= 12 && NotchLayout.shoulder(height: 32) >= 5 && NotchLayout.shoulder(height: 32) <= 8,
               "a closed island keeps corners like the cutout's, so a collapse settles inside the notch")
        suite.expect(NotchLayout.surfaceRadius(height: 286) == 28 && NotchLayout.shoulder(height: 286) == NotchLayout.shoulder,
               "an open island keeps its full corner radius and shoulder")
    }

    /// macOS rounds the camera housing it reports, so an edge of the real
    /// notch can show past the island. A fit set by hand moves whatever
    /// follows the cutout and nothing else, and stays on the Mac it was set on.
    private static func cameraFitContracts(_ suite: TestSuite) {
        let handWritten = NotchCameraFit(width: 2.4, height: 0.3)
        let negative = NotchCameraFit(width: -2.6, height: -1.3)
        suite.expect(handWritten.width == 2 && handWritten.height == 0.5
                     && negative.width == -3 && negative.height == -1.5
                     && NotchCameraFit(width: 40, height: -9).width == 10 && NotchCameraFit(width: 40, height: -9).height == -6,
                     "a notch fit written by hand is brought back to whole-point widths and half-point heights within range")
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let reported = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 179,
                                     menuBarHeight: 33, compactSideRoom: 100)
        let fitted = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 179,
                                   menuBarHeight: 33, compactSideRoom: 100,
                                   cameraFit: NotchCameraFit(width: 2, height: 0.5))
        suite.expect(reported.cameraWidth == 179 && reported.cameraHeight == 32,
               "without a fit the island matches the housing macOS reports")
        suite.expect(fitted.cameraWidth == 181 && fitted.cameraHeight == 32.5,
               "a fit widens and lengthens the camera housing the island covers")
        let strips = [fitted.restingSize(showsContent: false), fitted.restingSize(showsContent: true), fitted.collapsed,
                      fitted.notice, fitted.noticeSize(wingWidth: 190), fitted.compactMusicGeometry.compactActivitySize,
                      fitted.compactTimerGeometry(showsDownloads: true).compactActivitySize]
        suite.expect(strips.allSatisfy { $0.height == 32.5 && $0.height == fitted.stripHeight },
               "every strip beside the camera, the volume and brightness notice included, follows the fitted height")
        suite.expect(fitted.restingSize(showsContent: false).width == 181
               && fitted.noticeCameraGap == 181 && fitted.musicCameraGap == 181,
               "the closed island and the gap between wings follow the fitted width")
        suite.expect(fitted.notice.width == reported.notice.width + 2
               && fitted.noticeWingWidth(preferred: 80) == reported.noticeWingWidth(preferred: 80),
               "a notice keeps its wings beside a wider camera")
        suite.expect(fitted.expandedWidth == reported.expandedWidth && fitted.contentBudget == reported.contentBudget,
               "the open island keeps its chosen size")
        let shorter = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 179,
                                    cameraFit: NotchCameraFit(width: -3, height: -1))
        suite.expect(shorter.cameraWidth == 176 && shorter.notice.height == 31,
               "a housing reported too large can be narrowed and shortened")

        let plain = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 24)
        let simulated = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 24,
                                      cameraFit: NotchCameraFit(width: 10, height: 6))
        suite.expect(simulated == plain, "a display without a camera keeps its simulated cutout")

        let extreme = NotchCameraFit(width: 100, height: -100)
        suite.expect(extreme.width == 10 && extreme.height == -6, "a fit stays within its ranges")
        suite.expect(NotchCameraFit(width: .nan, height: .infinity) == .zero, "an unreadable fit means none")

        let domain = "com.vorssaint.tests.notch-camera-fit"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchCameraFitWidth] as? Double == 0
               && Defaults.registeredDefaults[DefaultsKey.notchCameraFitHeight] as? Double == 0
               && NotchCameraFit.current(in: defaults) == .zero,
               "the island follows the reported housing until someone fits it")
        defaults.set(-3.0, forKey: DefaultsKey.notchCameraFitWidth)
        defaults.set(1.5, forKey: DefaultsKey.notchCameraFitHeight)
        suite.expect(NotchCameraFit.current(in: defaults) == NotchCameraFit(width: -3, height: 1.5),
               "the stored fit is read back as set")

        let keys = [DefaultsKey.notchCameraFitWidth, DefaultsKey.notchCameraFitHeight]
        suite.expect(SettingsBackupSupport.exportKeys().isDisjoint(with: keys),
               "a fit for one Mac's camera does not travel in backups")
        let restored = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [DefaultsKey.notchCameraFitWidth: 4.0,
                                                DefaultsKey.notchCameraFitHeight: 1.0,
                                                DefaultsKey.notchSize: "custom"],
        ])
        suite.expect(restored?[DefaultsKey.notchSize] as? String == "custom"
               && keys.allSatisfy { restored?[$0] == nil },
               "a backup from another Mac leaves this Mac's fit alone")
        suite.expect(SettingsBackupSupport.keysToClear(whenImporting: [DefaultsKey.notchSize: "custom"]).isDisjoint(with: keys),
               "restoring a backup keeps the fit already set here")
    }

    /// The outline is drawn inside the island's edge, so an island that only
    /// covers a physical camera hides its line behind the housing.
    private static func outlineRoomContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let room = NotchLayout.outlineWidth
        let bare = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 179,
                                 menuBarHeight: 33, compactSideRoom: 100)
        let outlined = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 179,
                                     menuBarHeight: 33, compactSideRoom: 100, outline: true)
        suite.expect(bare.outlineRoom == 0 && outlined.outlineRoom == room
               && outlined.restingSize(showsContent: false) == CGSize(width: 179 + room * 2, height: 32 + room),
               "an outlined island reaches past the camera by the line's width, so the line shows around the notch")
        suite.expect([outlined.restingSize(showsContent: true), outlined.notice,
                      outlined.compactMusicGeometry.compactActivitySize].allSatisfy { $0.height == 32 + room },
               "every strip beside the camera keeps its line clear of the housing")
        suite.expect(!outlined.hasSameMenuBar(as: bare), "turning the outline on measures the menus again for the wider island")
        suite.expect(outlined.bareCutout == bare.restingSize(showsContent: false)
               && bare.bareCutout == bare.restingSize(showsContent: false),
               "full screen and the Lock Screen draw no outline, so their cutout keeps to the camera")
        let fitted = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 179,
                                   cameraFit: NotchCameraFit(width: -3, height: -1), outline: true)
        suite.expect(fitted.cameraWidth == 176 + room * 2 && fitted.cameraHeight == 31 + room,
               "the outline's room adds to a notch fit")
        for silhouette in [NotchSilhouette.notch, .capsule] {
            let plain = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 24, silhouette: silhouette)
            let simulated = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 24,
                                          silhouette: silhouette, outline: true)
            suite.expect(simulated == plain, "a cutout without a camera already shows its outline on the menu bar")
        }
    }

    private static func musicLabelContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for height: CGFloat in [16, 22, 24, 28, 30, 33, 37, 64] {
            for room: CGFloat? in [nil, 0, 43, 44, 56, 0, 56] {
                let geometry = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0,
                                             menuBarHeight: height, compactSideRoom: room).compactMusicGeometry
                let contentLeft = geometry.compactActivityWingWidth + geometry.compactMusicLabelInset
                let bottomCurveEnd = NotchLayout.shoulder(height: height) + NotchLayout.surfaceRadius(height: height)
                suite.expect(contentLeft >= bottomCurveEnd + 4,
                       "center text clears the entire curved silhouette even after the music wings disappear")
                suite.expect(geometry.compactActivityCameraGap - geometry.compactMusicLabelInset * 2 >= 50,
                       "protecting the curves still leaves useful room for a truncated track name")
                if geometry.compactActivityWingWidth >= 44 {
                    suite.expect(geometry.compactMusicLabelInset == 4,
                           "available music wings preserve the original center text budget")
                }
            }
        }
    }

    /// Resting on the cover names the song: the left side grows from the
    /// island's curved end with the words, and the cover and the bars stay
    /// where they rest beside the camera.
    private static func namedMusicStripChecks(_ suite: TestSuite, compactMusic: NotchGeometry, screen: CGRect) {
        typealias Layout = NotchMusicStripLayout
        let wing = compactMusic.compactActivityWingWidth
        let inset = Layout.coverInset(compactMusic), side = Layout.coverSide(compactMusic)
        suite.expect(inset == compactMusic.compactMusicArtworkInset && side == compactMusic.compactMusicArtworkSide
               && Layout.innerInset(compactMusic) == 0,
               "a physical camera's cover keeps its full size and concentric inset")
        let words = Layout.wordsWidth(title: "Midnight City", artist: "M83")
        suite.expect(Layout.wordsWidth(title: "Midnight City", artist: "M83") == words
               && words > Layout.wordsWidth(title: "Midnight City", artist: nil) - 0.001
               && Layout.wordsWidth(title: "Hi", artist: "A much longer artist name") > Layout.wordsWidth(title: "Hi", artist: nil),
               "the words take the wider of the title and the artist, measured once per song")
        let named = Layout.namedWings(title: "Midnight City", artist: " M83 ", geometry: compactMusic, room: .infinity)
        let expected = (Layout.endInset + words + Layout.spacing + wing - inset).rounded(.up)
        suite.expect(named == NotchNoticeWings(leading: expected, trailing: wing),
               "the named side holds the words and the cover as it rests, and the bars keep their side")
        if let named {
            // The view keeps the cover's gap to the camera, wing - inset - side, and gives the words the rest.
            let room = named.leading - Layout.endInset - Layout.spacing - (wing - inset)
            suite.expect(room >= words && room < words + 1,
                   "with the cover as far from the camera as it rests, the words keep their whole width")
        }
        let long = Layout.namedWings(title: String(repeating: "A very long song title ", count: 12), artist: nil,
                                     geometry: compactMusic, room: .infinity)
        suite.expect(long == NotchNoticeWings(leading: Layout.maximumWing, trailing: wing),
               "a long title stops at a notice's widest side and ends in an ellipsis")
        suite.expect(Layout.namedWings(title: String(repeating: "A very long song title ", count: 12), artist: nil,
                                       geometry: compactMusic, room: 120.6) == NotchNoticeWings(leading: 120, trailing: wing)
               && Layout.namedWings(title: "Midnight City", artist: "M83", geometry: compactMusic, room: wing) == nil
               && Layout.namedWings(title: "Midnight City", artist: "M83", geometry: compactMusic, room: -1) == nil,
               "the named side stops at the menus beside the island, and with no room past the cover the song stays unnamed")
        let narrowScreen = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 420, height: 300), safeAreaTop: 32,
                                         cameraWidth: 180, menuBarHeight: 24, compactSideRoom: 100).compactMusicGeometry
        let edge = Layout.namedWings(title: String(repeating: "Long ", count: 40), artist: nil, geometry: narrowScreen,
                                     room: .infinity)
        suite.expect(edge.map { narrowScreen.cameraWidth / 2 + $0.leading <= narrowScreen.screen.width / 2 - 12 } == true,
               "the named side stops short of the display's edge")
        suite.expect(Layout.namedWings(title: nil, artist: "M83", geometry: compactMusic, room: .infinity) == nil
               && Layout.namedWings(title: "", artist: "M83", geometry: compactMusic, room: .infinity) == nil,
               "a song without a title is not named")
        suite.expect(Layout.namedWings(title: "Midnight City", artist: "   ", geometry: compactMusic, room: .infinity)
                     == Layout.namedWings(title: "Midnight City", artist: nil, geometry: compactMusic, room: .infinity),
               "a blank artist leaves only the title to measure")
        var crowded = compactMusic
        crowded.compactSideRoom = 0
        suite.expect(Layout.namedWings(title: "Midnight City", artist: "M83", geometry: crowded.compactMusicGeometry,
                                       room: .infinity) == nil,
               "a strip whose wings gave way to the menus has no cover to name the song beside")
        let simulated = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 24,
                                      compactSideRoom: 100).compactMusicGeometry
        suite.expect(Layout.fillsCameraGap(simulated)
               && Layout.namedWings(title: "Midnight City", artist: "M83", geometry: simulated, room: .infinity) == nil,
               "a simulated camera already names the song between its wings")
        let short = NotchGeometry(screen: screen, safeAreaTop: 24, cameraWidth: 180, menuBarHeight: 24,
                                  compactSideRoom: 100).compactMusicGeometry
        let titleOnly = Layout.wordsWidth(title: "Midnight City", artist: nil)
        suite.expect(!Layout.showsArtist(short) && Layout.showsArtist(compactMusic)
               && Layout.namedWings(title: "Midnight City", artist: "A much longer artist name", geometry: short, room: .infinity)?.leading
                  == (Layout.endInset + titleOnly + Layout.spacing + short.compactActivityWingWidth - Layout.coverInset(short))
                     .rounded(.up),
               "a strip too short for a second line names only the title and measures only it")
    }

    private static func activitySelectionContracts(_ suite: TestSuite) {
        for mask in 0..<64 {
            let available = NotchSupport.compactActivities(
                timer: mask & 1 != 0, downloads: mask & 2 != 0, agents: mask & 4 != 0,
                calendar: mask & 8 != 0, music: mask & 16 != 0, keepAwake: mask & 32 != 0)
            var selection = NotchActivitySelection()
            suite.expect(selection.current(available: available) == available.first,
                         "available activities keep automatic priority until a choice is made")
            for activity in available {
                selection.select(activity, available: available)
                selection.reconcile(available: available)
                suite.expect(selection.current(available: available) == activity,
                             "every live activity can remain selected through refreshes")
                let remaining = available.filter { $0 != activity }
                selection.reconcile(available: remaining)
                suite.expect(selection.current(available: remaining) == remaining.first,
                             "while the chosen activity pauses, the island shows the next one")
                if !remaining.isEmpty {
                    suite.expect(selection.current(available: available) == activity,
                                 "a song changing or an agent between turns keeps the choice")
                } else {
                    suite.expect(selection.preferred == nil,
                                 "the choice ends once the island has nothing left to show")
                }
                selection.reconcile(available: [])
                suite.expect(selection.current(available: available) == available.first,
                             "activities returning to an empty island start from the automatic order")
            }
        }
        var selection = NotchActivitySelection()
        selection.select(.music, available: [.agents, .music])
        selection.reconcile(available: [.timer, .agents, .music])
        suite.expect(selection.current(available: [.timer, .agents, .music]) == .music,
                     "starting another activity does not steal an explicit choice")
        // Skipping a track leaves the timer alone on the island for a moment.
        selection.select(.music, available: [.timer, .agents, .music])
        selection.reconcile(available: [.timer, .agents])
        suite.expect(selection.current(available: [.timer, .agents]) == .timer,
                     "the timer fills in while the next song loads")
        selection.reconcile(available: [.timer, .agents, .music])
        suite.expect(selection.current(available: [.timer, .agents, .music]) == .music,
                     "the next song brings the chosen music back instead of the timer")
        selection.select(.downloads, available: [.agents, .music])
        suite.expect(selection.preferred == .music, "a late click on a removed choice is ignored")
        let all: [NotchCompactActivity] = [.timer, .downloads, .agents, .calendar, .music, .keepAwake]
        let pairs: [NotchCompactActivity] = [.downloads, .agents, .calendar, .music]
        for companion in pairs {
            selection.select(.timer, companion: companion, available: all, companions: pairs)
            selection.reconcile(available: all)
            suite.expect(selection.current(available: all) == .timer && selection.companion(available: pairs) == companion,
                         "each supported pair is an explicit, stable choice")
            selection.select(.timer, available: all)
            suite.expect(selection.companion(available: pairs) == nil, "choosing Timer always means Timer alone")
            selection.select(.timer, companion: companion, available: all, companions: pairs)
            selection.select(.music, available: all)
            suite.expect(selection.companion(available: pairs) == nil && selection.preferred == .music,
                         "an individual choice always replaces the combination")
            selection.select(.timer, companion: companion, available: all, companions: pairs)
            selection.reconcile(available: all.filter { $0 != companion })
            suite.expect(selection.preferred == .timer && selection.companion(available: []) == nil,
                         "a missing companion leaves the timer alone")
            suite.expect(selection.companion(available: pairs) == companion,
                         "a companion that returns pairs with the timer again")
            selection.reconcile(available: all.filter { $0 != .timer })
            suite.expect(selection.current(available: all.filter { $0 != .timer }) == .downloads,
                         "a dismissed timer leaves the island to the automatic order")
            selection.reconcile(available: [])
            suite.expect(selection.preferred == nil && selection.companion(available: pairs) == nil,
                         "an empty island clears the entire combination")
        }
        selection.select(.music, available: all)
        selection.select(.agents, companion: .music, available: all, companions: [])
        suite.expect(selection.preferred == .music && selection.companion(available: pairs) == nil,
                     "unsupported pairs cannot displace the current choice")
        let eventPairs: [NotchCompactActivity] = [.downloads, .agents, .music]
        for companion in eventPairs {
            selection.select(.calendar, companion: companion, available: all, companions: eventPairs)
            selection.reconcile(available: all)
            suite.expect(selection.current(available: all) == .calendar
                         && selection.companion(available: eventPairs) == companion,
                         "an event leads a pair of its own, keeping its clock beside the camera")
            suite.expect(selection.preferred == .calendar
                         && selection.companion(available: eventPairs.filter { $0 != companion }) == nil
                         && selection.companion(available: eventPairs) == companion,
                         "a companion that pauses leaves the event alone until it returns")
            selection.reconcile(available: all.filter { $0 != .calendar })
            suite.expect(selection.current(available: all.filter { $0 != .calendar }) == .timer,
                         "the event's countdown ending leaves the island to the automatic order")
            selection.reconcile(available: [])
            suite.expect(selection.preferred == nil && selection.companion(available: eventPairs) == nil,
                         "an empty island clears the event's pair")
        }
        for height: CGFloat in [16, 22, 32, 40, 64] {
            for width: CGFloat in [200, 320, 560] {
                for combinations in [false, true] {
                    let strip = CGSize(width: width, height: height)
                    let layout = NotchActivityPickerLayout(count: 2, labelWidth: 60, stripSize: strip,
                                                           screenWidth: 1024, hasCombinations: combinations)
                    let shape = NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: layout.size.height))
                        .path(in: CGRect(origin: .zero, size: layout.size))
                    let inset = (layout.size.width - width) / 2
                    for x in [inset, inset + width] {
                        for y in [CGFloat(1), height - 1] {
                            suite.expect(shape.contains(CGPoint(x: x, y: y)),
                                         "the full strip, including edge artwork and timer suffixes, fits inside the picker silhouette")
                        }
                    }
                }
            }
        }
        for language in AppLanguage.allCases {
            let activities: [NotchCompactActivity] = [.timer, .downloads, .agents, .calendar, .music, .keepAwake]
            let font = NSFont.systemFont(ofSize: 12, weight: .medium)
            let width = activities.map {
                ($0.title(language) as NSString).size(withAttributes: [.font: font]).width
            }.max()!
            for count in 2...6 {
                let layout = NotchActivityPickerLayout(count: count, labelWidth: width,
                    stripSize: CGSize(width: 300, height: 32), screenWidth: 1024)
                let cell = (layout.size.width - NotchActivityPickerLayout.horizontalInset * 2
                            - CGFloat(layout.columns - 1) * 6) / CGFloat(layout.columns)
                suite.expect(cell >= width + 48 && layout.size.width <= 1000
                             && layout.headerHeight == 32,
                             "named activity buttons fit without truncation below the camera in \(language.rawValue)")
            }
        }
    }

    private static func shortcutContracts(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchShortcutEnabled] as? Bool == false,
               "the island shortcut ships off, so no key is taken until the user asks")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchShortcut] as? String
                == "control+option+command:34",
               "the default island shortcut is control option command I")
        suite.expect(!GlobalShortcutRole.allCases.contains { $0 != .notch && $0.defaultShortcut == .notchDefault },
               "the default island shortcut is not another feature's default")
        func active(_ keys: Set<String>) -> Bool {
            GlobalShortcutRole.activeRoles(isOn: { keys.contains($0) }).contains(.notch)
        }
        suite.expect(active([DefaultsKey.notchEnabled, DefaultsKey.notchShortcutEnabled])
                && !active([DefaultsKey.notchShortcutEnabled])
                && !active([DefaultsKey.notchEnabled]),
               "the island shortcut is live only while both the island and its shortcut are on")
        suite.expect(!GlobalShortcutRole.activeRoles(isOn: { _ in true },
                                                     isAvailable: { $0 != .notch }).contains(.notch),
               "an island removed in the hub does not reserve its shortcut")
        let backupKeys = SettingsBackupSupport.exportKeys()
        suite.expect(backupKeys.contains(DefaultsKey.notchShortcut)
                && backupKeys.contains(DefaultsKey.notchShortcutEnabled),
               "the island shortcut travels with the settings backup")
        let domain = "com.vorssaint.tests.notch-shortcut-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        func holds(installed: Bool = true, island: Bool = true, shortcut: Bool = true) -> Bool {
            defaults.set(installed, forKey: AppFeature.notch.availabilityKey)
            defaults.set(island, forKey: DefaultsKey.notchEnabled)
            defaults.set(shortcut, forKey: DefaultsKey.notchShortcutEnabled)
            return NotchSupport.holdsShortcut(in: defaults)
        }
        suite.expect(holds(), "the island shortcut holds its key while the island and its shortcut are on")
        suite.expect(!holds(island: false), "the island shortcut is not wanted while the island is off")
        suite.expect(!holds(installed: false), "the island shortcut is not wanted while the island is removed in the hub")
        suite.expect(!holds(shortcut: false), "turning the island shortcut off releases its key")
        // The service is a singleton holding a real Carbon hotkey, so its
        // wiring is checked in the source, like the launch hooks below.
        let service = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Notch/NotchService.swift",
                                   encoding: .utf8)) ?? ""
        suite.expect(service.contains("hotkey.onPress = { [weak self] in self?.toggleFromShortcut() }"),
               "the island shortcut answers like a click on the island")
        suite.expect(service.contains("guard NotchSupport.isEnabled() else { stop(); return }")
                && service.contains("        syncShortcut()\n        if !NotchTimerSupport.isEnabled()"),
               "every preference sync of a running island registers or releases its shortcut")
        suite.expect(service.contains("preferenceSyncWork?.cancel(); preferenceSyncWork = nil\n        hotkey.unregister()"),
               "stopping the island releases its shortcut")
    }

    static func run(_ suite: TestSuite) {
        shortcutContracts(suite)
        let previewStrip: CGFloat = 37
        suite.expect(NotchTranslucentTint.opacity(atDepth: previewStrip, stripHeight: previewStrip,
                                                  openness: 1, increasedContrast: false) == 1
                && NotchTranslucentTint.opacity(atDepth: 0, stripHeight: previewStrip,
                                                openness: 1, increasedContrast: false) == 1,
               "the translucent background stays black down to the camera strip in the hover preview")
        suite.expect(abs(NotchTranslucentTint.opacity(atDepth: previewStrip + 62, stripHeight: previewStrip,
                                                      openness: 1, increasedContrast: false) - 0.38) < 0.001
                && NotchTranslucentTint.opacity(atDepth: previewStrip + 62, stripHeight: previewStrip,
                                                openness: 1, increasedContrast: true) > 0.69,
               "below the strip the translucent body opens, less with Increase Contrast")
        func stripIsBlack(islandHeight: CGFloat) -> Bool {
            let stops = NotchTranslucentTint.stops(height: islandHeight, stripHeight: previewStrip,
                                                   openness: 1, increasedContrast: false)
            let stripEnd = Double(previewStrip / islandHeight)
            return stops.filter { $0.location <= stripEnd + 1e-9 }.allSatisfy { $0.opacity == 1 }
                && stops.contains { abs($0.location - stripEnd) < 1e-9 }
        }
        suite.expect(stripIsBlack(islandHeight: previewStrip + 62) && stripIsBlack(islandHeight: 400),
               "the strip stays black at every island height, tall or at the preview's")

        NotchMissionControlPollingTests.run(suite)
        activitySelectionContracts(suite)
        railContracts(suite)
        presentationSpacingContracts(suite)
        captureControlsLayoutContracts(suite)
        pageTopContracts(suite)
        pageWidthContracts(suite)
        sectionsButtonContracts(suite)
        sectionsButtonPlacementContracts(suite)
        homeRailContracts(suite)
        homeRailRowContracts(suite)
        toolRailContracts(suite)
        noticeLayoutContracts(suite)
        simulatedMenuBoundsContracts(suite)
        simulatedDisplayContracts(suite)
        menuSpaceReuseContracts(suite)
        menuBarHeightContracts(suite)
        physicalStripContracts(suite)
        cameraFitContracts(suite)
        outlineRoomContracts(suite)
        musicLabelContracts(suite)
        NotchPanelTests.run { suite.expect($0, $1) }
        NotchHoverTests.run(suite)
        NotchScreenEdgeClickTests.run(suite)
        NotchPresentationRefreshContract.run(suite)
        NotchScreenRefreshContract.run(suite)
        NotchMirrorContract.run(suite)
        NotchFullscreenTests.run(suite)
        NotchDestinationContract.run(suite)
        NotchMusicVisibilityTests.run(suite)
        NotchEqualizerTests.run { suite.expect($0, $1) }
        WindowVisibilityTests.run { suite.expect($0, $1) }
        NotchLyricsTimelineTests.run { suite.expect($0, $1) }
        NotchUpdateTests.run(suite)
        NotchCaptureKeyboardTests.run(suite)
        NotchKeyMonitorTests.run(suite)
        NotchDownloadProgressTests.run(suite)
        NotchSliderEditingTests.run(suite)
        NotchFileToolsTests.run(suite)
        NotchAudioLevelTests.run { suite.expect($0, $1) }
        calendarContracts(suite)
        NotchNotificationTests.run(suite)
        NotchNotificationReaderTests.run(suite)
        NotchGestureTests.run(suite)
        NotchSectionPagingTests.run(suite)
        NotchKeyboardLightTests.run(suite)
        NotchActivityTests.run(suite)
        NotchWatchTests.run(suite)
        NotchMascotTests.run(suite)
        NotchMascotHidingContract.run(suite)
        NotchMusicExtrasTests.run(suite)
        NotchLockScreenTests.run(suite)
        NowPlayingOpenContract.run(suite)
        NotchClipboardPageTests.run(suite)
        for language in AppLanguage.allCases {
            let strings = Mirror(reflecting: FeatureStrings.notchClipboardSize(language)).children.compactMap { $0.value as? String }
            suite.expect(strings.count == 4 && strings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                         "the clipboard entry size has complete strings in \(language.rawValue)")
        }
        let sizeDomain = "com.vorssaint.tests.notch-clipboard-size"
        let sizeDefaults = UserDefaults(suiteName: sizeDomain)!
        sizeDefaults.removePersistentDomain(forName: sizeDomain)
        defer { sizeDefaults.removePersistentDomain(forName: sizeDomain) }
        // Existing users keep the entries they had until they choose compact ones.
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchClipboardCardSize] as? String
                        == NotchClipboardCardSize.comfortable.rawValue,
                     "clipboard entries are registered comfortable, the size they had before compact ones")
        suite.expect(NotchClipboardCardSize.current(in: sizeDefaults) == .comfortable
                     && NotchClipboardCardSize(stored: nil) == .comfortable,
                     "clipboard entries start comfortable with nothing stored")
        sizeDefaults.set("compact", forKey: DefaultsKey.notchClipboardCardSize)
        suite.expect(NotchClipboardCardSize.current(in: sizeDefaults) == .compact
                     && NotchClipboardCardSize(stored: "compact") == .compact, "the chosen entry size is read")
        sizeDefaults.set("huge", forKey: DefaultsKey.notchClipboardCardSize)
        suite.expect(NotchClipboardCardSize.current(in: sizeDefaults) == .comfortable
                     && NotchClipboardCardSize(stored: "huge") == .comfortable,
                     "an unknown entry size falls back to comfortable")
        typealias Size = NotchClipboardCardSize
        suite.expect(Size.openLines(for: "one line", width: 400) == 1
                     && Size.openLines(for: "a\nb\nc", width: 400) == 3
                     && Size.openLines(for: String(repeating: "x", count: 130), width: 400) == 3
                     && Size.openLines(for: String(repeating: "word ", count: 1000), width: 400) == Size.maximumOpenLines
                     && Size.openLines(for: "", width: 400) == 1,
                     "an open entry shows its lines, counting wrapped ones, up to a limit")
        // A Chinese, Japanese or Korean character is about twice as wide as a
        // Latin letter: 100 of them wrap to four lines in 400 points.
        suite.expect(Size.openLines(for: String(repeating: "漢", count: 100), width: 400) == 4
                     && Size.openLines(for: String(repeating: "日本語のテキスト", count: 10), width: 400) == 3,
                     "an open entry measures wide characters as drawn, not as Latin letters")
        // The history window edits an entry's text and keeps its id.
        let measured = UUID()
        suite.expect(Size.openHeight(text: "short", width: 400, id: measured) == Size.openLineHeight + Size.openChrome
                     && Size.openHeight(text: String(repeating: "x\n", count: 50), width: 400, id: measured)
                        == CGFloat(Size.maximumOpenLines) * Size.openLineHeight + Size.openChrome
                     && Size.openHeight(text: "short", width: 400, id: measured) == Size.openLineHeight + Size.openChrome
                     && Size.openHeight(text: String(repeating: "漢", count: 100), width: 100, id: measured)
                        == CGFloat(Size.maximumOpenLines) * Size.openLineHeight + Size.openChrome,
                     "an open clipboard entry measures its text again once edited, and at each width")
        suite.expect(Size.openHeight(text: "short", width: 400) == Size.openLineHeight + Size.openChrome
                     && Size.openHeight(text: String(repeating: "x\n", count: 50), width: 400)
                        == CGFloat(Size.maximumOpenLines) * Size.openLineHeight + Size.openChrome,
                     "an open text entry is as tall as its lines, up to a limit")
        suite.expect(Size.openHeight(aspectRatio: 1.6, width: 400) == Size.maximumOpenImage + Size.openChrome,
                     "a wide image opens at the tallest it may")
        suite.expect(Size.openHeight(aspectRatio: 20, width: 400) == Size.minimumOpenImage + Size.openChrome
                     && Size.openHeight(aspectRatio: 1, width: 100) == 100 + Size.openChrome
                     && Size.openHeight(aspectRatio: nil, width: 300) == Size.maximumOpenImage + Size.openChrome,
                     "an open image keeps its proportions within a range, and one with none is taken as wide")
        suite.expect(NotchLayout.clipboardCompactCardHeight < NotchLayout.clipboardCardHeight && NotchClipboardCardSize.dwell > 0,
                     "a compact entry is shorter than an open one and opens after a pause")
        let domain = "com.vorssaint.tests.notch"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        // Registration defaults are shared across suites within the process.
        // Keep this fixture inside its own persistent domain so migration
        // tests later in the harness still see a genuinely untouched setup.
        for (key, value) in Defaults.registeredDefaults
        where key.hasPrefix("notch") || key == DefaultsKey.clipboardHistoryEnabled
            || key == DefaultsKey.brightnessControlEnabled {
            defaults.set(value, forKey: key)
        }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        let firstInstall = "com.vorssaint.tests.notch-new-\(UUID().uuidString)"
        let fresh = UserDefaults(suiteName: firstInstall)!
        defer { fresh.removePersistentDomain(forName: firstInstall) }
        fresh.set(NotchControlItem.defaultHidden, forKey: DefaultsKey.notchHiddenControls)
        fresh.set(true, forKey: DefaultsKey.notchScratchpadControlHidden)
        Defaults.migrateExistingNotchDefaults(in: fresh, domainName: firstInstall)
        let firstDefaults = Defaults.registeredDefaults
        suite.expect(fresh.string(forKey: DefaultsKey.notchSize) == NotchSize.spacious.rawValue
                     && !fresh.bool(forKey: DefaultsKey.notchInitialExtensionsInstalled)
                     && firstDefaults[DefaultsKey.notchSize] as? String == NotchSize.spacious.rawValue
                     && firstDefaults[DefaultsKey.notchOpenOnHover] as? Bool == false
                     && firstDefaults[DefaultsKey.notchAppPanel] as? Bool == false,
                     "a first island setup starts spacious, opens by click and uses a separate app panel")
        suite.expect(firstDefaults[DefaultsKey.notchGesturesEnabled] as? Bool == true
                     && firstDefaults[DefaultsKey.notchHapticFeedback] as? Bool == true
                     && firstDefaults[DefaultsKey.notchReturnHome] as? Bool == false
                     && firstDefaults[DefaultsKey.notchCoversMenus] as? Bool == true,
                     "gestures, haptics, last page and coverage over menus start selected")
        let enabledByDefault = [DefaultsKey.notchNotificationsEnabled, DefaultsKey.notchCameraEnabled,
                                DefaultsKey.notchDownloadsEnabled,
                                DefaultsKey.notchLyricsEnabled, DefaultsKey.notchQueueEnabled,
                                DefaultsKey.notchKeyboardLight, DefaultsKey.notchMicrophone,
                                DefaultsKey.notchAccessoriesEnabled, DefaultsKey.notchClipboard,
                                DefaultsKey.notchCapture, DefaultsKey.notchTrackChange]
        suite.expect(enabledByDefault.allSatisfy { firstDefaults[$0] as? Bool == true },
                     "installed island sections and activity indicators start enabled")
        suite.expect(firstDefaults[DefaultsKey.notchLiveEqualizer] as? Bool == false,
                     "the live equalizer starts off because it asks for system audio recording")
        suite.expect(firstDefaults[DefaultsKey.notchAgentsEnabled] as? Bool == false,
                     "new island setups leave local agent history reading off until chosen")
        suite.expect(firstDefaults[DefaultsKey.notchIncludeOtherPlayers] as? Bool == true,
                     "new island setups follow every player unless limited to music apps")

        let priorInstall = "com.vorssaint.tests.notch-existing-\(UUID().uuidString)"
        let existing = UserDefaults(suiteName: priorInstall)!
        defer { existing.removePersistentDomain(forName: priorInstall) }
        existing.set(true, forKey: DefaultsKey.notchEnabled)
        existing.set(NotchSize.custom.rawValue, forKey: DefaultsKey.notchSize)
        existing.set(true, forKey: DefaultsKey.notchNotificationsEnabled)
        Defaults.migrateExistingNotchDefaults(in: existing, domainName: priorInstall)
        suite.expect(existing.string(forKey: DefaultsKey.notchSize) == NotchSize.custom.rawValue
                     && existing.bool(forKey: DefaultsKey.notchInitialExtensionsInstalled)
                     && existing.bool(forKey: DefaultsKey.notchNotificationsEnabled)
                     && existing.bool(forKey: DefaultsKey.notchOpenOnHover)
                     && existing.bool(forKey: DefaultsKey.notchAppPanel)
                     && !existing.bool(forKey: DefaultsKey.notchAgentsEnabled),
                     "updating a configured island keeps explicit choices and previous implicit defaults")
        Defaults.migrateExistingNotchDefaults(in: fresh, domainName: firstInstall)
        suite.expect(fresh.string(forKey: DefaultsKey.notchSize) == NotchSize.spacious.rawValue,
                     "a new Spacious setup keeps its size on subsequent launches")
        for size in NotchSize.allCases {
            existing.set(size.rawValue, forKey: DefaultsKey.notchSize)
            Defaults.migrateExistingNotchDefaults(in: existing, domainName: priorInstall)
            suite.expect(existing.string(forKey: DefaultsKey.notchSize) == size.rawValue,
                         "every explicit island size survives the default change")
        }
        existing.removeObject(forKey: DefaultsKey.notchSize)
        Defaults.migrateExistingNotchDefaults(in: existing, domainName: priorInstall)
        suite.expect(existing.string(forKey: DefaultsKey.notchSize) == NotchSize.compact.rawValue,
                     "an initialized profile preserves its previous implicit Compact size")
        existing.removeObject(forKey: DefaultsKey.notchAppPanel)
        Defaults.migrateExistingNotchDefaults(in: existing, domainName: priorInstall)
        suite.expect(!existing.bool(forKey: DefaultsKey.notchAppPanel),
                     "the one-time migration does not run again after a later preference change")

        let priorChoice = "com.vorssaint.tests.notch-choice-\(UUID().uuidString)"
        let configured = UserDefaults(suiteName: priorChoice)!
        defer { configured.removePersistentDomain(forName: priorChoice) }
        configured.set(true, forKey: DefaultsKey.notchReturnHome)
        Defaults.migrateExistingNotchDefaults(in: configured, domainName: priorChoice)
        suite.expect(configured.bool(forKey: DefaultsKey.notchOpenOnHover)
                     && configured.bool(forKey: DefaultsKey.notchReturnHome),
                     "a saved island choice stays configured even if the master switch was never used")

        suite.expect(!NotchSupport.isEnabled(in: defaults), "notch is opt-in")
        suite.expect(NotchSupport.controls(in: defaults) == [.volume, .brightness, .music, .mixer, .keepAwake, .timer, .calendar],
               "home defaults prioritize playback and everyday system controls")
        defaults.set(false, forKey: DefaultsKey.notchTimerEnabled)
        defaults.set(false, forKey: DefaultsKey.notchCalendarEnabled)
        suite.expect(!NotchSupport.controls(in: defaults).contains(.timer)
               && !NotchSupport.controls(in: defaults).contains(.calendar),
               "explicitly disabled utilities stay absent from home controls")
        defaults.set(true, forKey: DefaultsKey.notchTimerEnabled)
        defaults.set(true, forKey: DefaultsKey.notchCalendarEnabled)
        defaults.set("music,timer,calendar", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchSupport.controls(in: defaults).contains(.music)
               && !NotchSupport.controls(in: defaults).contains(.timer)
               && !NotchSupport.controls(in: defaults).contains(.calendar),
               "home controls respect hidden destinations")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        // A capsule's row runs across the island; the 13-inch camera at the
        // compact width and the spacious one both wrap the camera.
        let capsuleHome = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0,
                                        cameraWidth: 0, menuBarHeight: 24, silhouette: .capsule)
        let narrowHome = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956), safeAreaTop: 32, cameraWidth: 180)
        let wideHome = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1280, height: 832), safeAreaTop: 28,
                                     cameraWidth: 156, layout: .spacious, menuBarHeight: 28)
        func homeHeight(_ geometry: NotchGeometry, sliders: Int, music: Bool = true) -> CGFloat {
            geometry.expandedSize(module: .controls, sliderCount: sliders, controlsHaveMusic: music).height
        }
        suite.expect([capsuleHome, narrowHome, wideHome].allSatisfy { geometry in
                   (0...3).allSatisfy { sliders in
                       homeHeight(geometry, sliders: sliders) - homeHeight(geometry, sliders: sliders, music: false)
                           == NotchLayout.cardHeight + NotchLayout.rowSpacing
                   }
               },
               "home playback is the card row and its spacing whatever the levels, which never take a card")
        suite.expect(homeHeight(capsuleHome, sliders: 3) == homeHeight(capsuleHome, sliders: 0)
               && homeHeight(wideHome, sliders: 2) == homeHeight(wideHome, sliders: 0)
               && homeHeight(narrowHome, sliders: 2) == homeHeight(narrowHome, sliders: 0)
               && [narrowHome, wideHome].allSatisfy { geometry in
                   homeHeight(geometry, sliders: 3) - homeHeight(geometry, sliders: 2)
                       == NotchLayout.levelRowHeight + NotchLayout.rowSpacing
               },
               "the levels sit in the top row, and three beside a camera share one slim row below it")
        func levelBand(side: CGFloat, besideCamera: Bool, sectionsButton: Bool = false) -> NotchBand {
            var band = NotchBand()
            band.besideCamera = besideCamera
            band.side = side
            band.sectionsButton = sectionsButton
            return band
        }
        let fullRow = levelBand(side: 304, besideCamera: false)
        suite.expect(NotchLayout.bandLevelCount(3, band: fullRow) == 3 && NotchLayout.bandLevelCount(0, band: fullRow) == 0
               && NotchLayout.bandLevelCount(3, band: levelBand(side: 166, besideCamera: true)) == 0
               && NotchLayout.bandLevelCount(2, band: levelBand(side: 114, besideCamera: true)) == 2
               && NotchLayout.bandLevelCount(1, band: levelBand(side: 114, besideCamera: true)) == 1,
               "a full row holds every level, and a camera's sides only levels they split evenly")
        suite.expect(NotchLayout.bandLevelCount(3, band: levelBand(side: 304, besideCamera: false, sectionsButton: true)) == 3
               && NotchLayout.bandLevelCount(3, band: levelBand(side: 290, besideCamera: false, sectionsButton: true)) == 0
               && NotchLayout.bandLevelCount(2, band: levelBand(side: 114, besideCamera: true, sectionsButton: true)) == 2
               && NotchLayout.bandLevelCount(2, band: levelBand(side: 104, besideCamera: true, sectionsButton: true)) == 0
               && NotchLayout.bandLevelCount(1, band: levelBand(side: 104, besideCamera: true, sectionsButton: true)) == 0
               && NotchLayout.bandLevelCount(2, band: levelBand(side: 104, besideCamera: true)) == 2,
               "past the sections button a level keeps its narrowest, or the levels move to the row below")
        suite.expect(NotchLayout.homeReadingWidth(levels: 3, side: 504) == NotchLayout.homeReadingWidth
               && NotchLayout.homeReadingWidth(levels: 3, side: 440) == 440 - 12 - 252
               && NotchLayout.homeReadingWidth(levels: 3, side: 304) == nil
               && NotchLayout.homeReadingWidth(levels: 0, side: 304) == NotchLayout.homeReadingWidth,
               "a reading on the home page's full row leaves every level its narrowest, or covers them where both cannot fit")

        suite.expect(!NotchSupport.routesAppPanel(in: defaults) && !NotchSupport.routesQuickPanel(in: defaults)
               && !NotchSupport.routesShelf(in: defaults) && !NotchSupport.routesCaptureControls(in: defaults)
               && !NotchSupport.routesClipboardWindow(in: defaults),
               "separate panels remain the default until the notch is explicitly enabled")
        suite.expect(NotchSupport.showsInCaptures(in: defaults), "notch appears in screenshots and recordings by default")
        defaults.set(true, forKey: DefaultsKey.notchHideInCaptures)
        suite.expect(NotchSupport.showsInCaptures(in: defaults), "the old inverse default cannot silently hide the notch")
        defaults.set(false, forKey: DefaultsKey.notchShowInCaptures)
        suite.expect(!NotchSupport.showsInCaptures(in: defaults), "capture visibility remains an explicit opt-out")
        defaults.set(true, forKey: DefaultsKey.notchShowInCaptures)
        suite.expect(!NotchSupport.hidesUntilHover(in: defaults), "the closed island stays in sight by default")
        defaults.set(true, forKey: DefaultsKey.notchHideUntilHover)
        suite.expect(!NotchSupport.hidesUntilHover(in: defaults), "click to open does not hide the island until hover")
        defaults.set(true, forKey: DefaultsKey.notchOpenOnHover)
        suite.expect(NotchSupport.hidesUntilHover(in: defaults), "hidden until hover waits out of sight for the pointer")
        suite.expect(NotchSupport.hidesNoticesUntilHover(in: defaults) && !NotchSupport.hiddenShowsActivity(in: defaults),
               "hidden until hover keeps activity and notices out of sight by default")
        defaults.set(true, forKey: DefaultsKey.notchHiddenShowsActivity)
        suite.expect(NotchSupport.hiddenShowsActivity(in: defaults) && !NotchSupport.hidesNoticesUntilHover(in: defaults),
               "a hidden island set to show activity takes notices while it waits for the pointer")
        defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
        suite.expect(!NotchSupport.hiddenShowsActivity(in: defaults), "showing activity only applies while hidden until hover")
        defaults.set(true, forKey: DefaultsKey.notchOpenOnHover)
        defaults.set(false, forKey: DefaultsKey.notchHiddenShowsActivity)
        defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
        suite.expect(!NotchSupport.hidesUntilHover(in: defaults), "an island that opens by click never waits for hover")
        defaults.set(false, forKey: DefaultsKey.notchHideUntilHover)
        suite.expect(NotchEvent.allCases.allSatisfy { !NotchSupport.routes($0, in: defaults) },
               "disabled notch cannot consume any existing presentation")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchSupport.isEnabled(in: defaults), "master switch enables notch")
        suite.expect(NotchSupport.usesHapticFeedback(in: defaults), "the enabled island starts with tactile feedback")
        defaults.set(false, forKey: DefaultsKey.notchHapticFeedback)
        suite.expect(!NotchSupport.usesHapticFeedback(in: defaults), "tactile feedback can still be turned off independently")
        defaults.set(true, forKey: DefaultsKey.notchHapticFeedback)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchSupport.usesHapticFeedback(in: defaults) && !NotchSupport.routesAppPanel(in: defaults)
               && !NotchSupport.routesQuickPanel(in: defaults) && !NotchSupport.routesShelf(in: defaults),
               "turning the notch off restores separate panels and suppresses tactile feedback")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchSupport.usesHapticFeedback(in: defaults), "disabling the notch preserves the user's tactile preference")
        suite.expect(NotchSupport.idleContent(in: defaults) == .music, "a new island shows playing music at rest")
        suite.expect(defaults.string(forKey: DefaultsKey.notchSize) == NotchSize.spacious.rawValue
               && !defaults.bool(forKey: DefaultsKey.notchOpenOnHover),
               "a new island starts spacious and opens by click")
        suite.expect(!defaults.bool(forKey: DefaultsKey.notchHideUntilHover), "hidden hover is opt-in")
        suite.expect(!defaults.bool(forKey: DefaultsKey.notchOutlineEnabled), "the island outline is opt-in")
        suite.expect(!defaults.bool(forKey: DefaultsKey.notchHideMenuBarGap),
                     "the island matches the physical notch's height unless covering the gap below it is chosen")
        suite.expect(defaults.double(forKey: DefaultsKey.notchHoverDelay) == 0.25,
               "hover activation defaults to a deliberate quarter-second pause")
        for value in [0.10, 0.25, 0.65, 1.0] {
            suite.expect(NotchSupport.sanitizedHoverDelay(value) == value, "valid hover activation times are preserved")
        }
        suite.expect(NotchSupport.sanitizedHoverDelay(-1) == 0.10
               && NotchSupport.sanitizedHoverDelay(9) == 1.0,
               "hover activation times stay within usable bounds")
        suite.expect([Double.nan, .infinity, -.infinity].allSatisfy { NotchSupport.sanitizedHoverDelay($0) == 0.25 },
               "non-finite hover activation times fall back to the default")
        suite.expect(defaults.double(forKey: DefaultsKey.notchCloseDelay) == 0.18
               && NotchSupport.sanitizedCloseDelay(0.65) == 0.65
               && NotchSupport.sanitizedCloseDelay(-1) == 0.10 && NotchSupport.sanitizedCloseDelay(9) == 2.0
               && NotchSupport.sanitizedCloseDelay(.nan) == 0.18,
               "closing after the pointer leaves keeps its old pause and stays within usable bounds")
        defaults.set(1.5, forKey: DefaultsKey.notchCloseDelay)
        suite.expect(NotchSupport.closeDelay(in: defaults) == 1.5,
                     "the closing delay reads the saved preference")
        defaults.set("invalid", forKey: DefaultsKey.notchCloseDelay)
        suite.expect(NotchSupport.closeDelay(in: defaults) == 0.18,
                     "a closing delay stored with the wrong type uses the default")
        defaults.removeObject(forKey: DefaultsKey.notchCloseDelay)
        suite.expect(NotchSupport.closeDelay(in: defaults) == 0.18,
                     "removing the closing preference restores the original delay")
        suite.expect(!NotchSupport.routesAppPanel(in: defaults) && NotchSupport.routesQuickPanel(in: defaults)
               && NotchSupport.routesClipboardWindow(in: defaults) && NotchSupport.routesShelf(in: defaults)
               && NotchSupport.routesCaptureControls(in: defaults),
               "enabling a fresh island keeps the app panel separate and routes the other available panels into it")
        suite.expect(NotchSupport.routes(.track, in: defaults), "a new song shows by default while music is on")
        defaults.set("music", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchSupport.routes(.track, in: defaults), "a hidden music section announces no new song")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(NotchSupport.routes(.microphone, in: defaults), "the microphone switch reports in the island by default")
        defaults.set(false, forKey: DefaultsKey.notchMicrophone)
        suite.expect(!NotchSupport.routes(.microphone, in: defaults),
                     "turning microphone notices off keeps the switch's own confirmation")
        defaults.set(true, forKey: DefaultsKey.notchMicrophone)
        defaults.set(false, forKey: AppFeature.micMute.availabilityKey)
        suite.expect(!NotchSupport.routes(.microphone, in: defaults), "a removed microphone mute announces nothing in the island")
        defaults.set(true, forKey: AppFeature.micMute.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.notchTrackChange)
        let initialLayout = NotchQuickAccessConfiguration.current(in: defaults)
        suite.expect(initialLayout.buttons.filter { $0.side == .left }.compactMap(\.action) == [.explore, .module(.timer)]
               && initialLayout.buttons.filter { $0.side == .right }.compactMap(\.action) == [.settings, .module(.mixer)]
               && initialLayout.buttons.filter { $0.side == .bottom }.compactMap(\.action) == [.module(.music)],
               "a fresh layout places Explore and Timer left, Settings and Mixer right, and music below")
        suite.expect(initialLayout == NotchQuickAccessConfiguration.current(in: defaults),
               "default buttons keep stable identities across preference refreshes")
        defaults.set(false, forKey: AppFeature.mixer.availabilityKey)
        defaults.set(false, forKey: AppFeature.notchTimer.availabilityKey)
        suite.expect(NotchQuickAccessConfiguration.current(in: defaults).actions == [.explore, .settings, .module(.music)]
               && !NotchQuickAction.module(.mixer).isAvailable(in: defaults)
               && !NotchQuickAction.control(.mixer).isAvailable(in: defaults),
               "uninstalled utilities leave no default buttons or available mixer actions")
        suite.expect(NotchQuickAccessConfiguration.stored(in: defaults) == initialLayout,
               "uninstalling a utility preserves its configured position")
        defaults.set(true, forKey: AppFeature.mixer.availabilityKey)
        defaults.set(true, forKey: AppFeature.notchTimer.availabilityKey)
        suite.expect(NotchQuickAccessConfiguration.current(in: defaults) == initialLayout,
               "reinstalled utilities return to their original positions")
        defaults.set("music", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(NotchQuickAccessConfiguration.current(in: defaults).actions == [.explore, .module(.timer), .settings, .module(.mixer)],
               "a section switched off takes its button out of the island")
        var held = NotchQuickAccessConfiguration(side: .left, actions: [.explore, .module(.music), .settings])
        let incoming = NotchQuickButton(action: .control(.panel), side: .right)
        held.buttons.append(incoming)
        held.move(incoming.id, to: .left)
        suite.expect(!held.hasRoom(on: .left) && held.buttons.first(where: { $0.id == incoming.id })?.side == .right
               && held.buttons.filter { $0.side == .left }.compactMap(\.action) == [.explore, .module(.music), .settings],
               "a hidden button keeps its place, so a side it fills takes no other")
        var reordered = NotchQuickAccessConfiguration(side: .left, actions: [.explore, .module(.music), .settings])
        let ids = reordered.buttons.map(\.id)
        let swapped = reordered.reorder(ids[2], by: -1)
        let pastTheTop = reordered.reorder(ids[0], by: -1)
        suite.expect(swapped && !pastTheTop && reordered.actions == [.explore, .settings, .module(.music)],
               "moving a button swaps it with its neighbour, hidden or not, and a move past either end changes nothing")
        let savedIdle = defaults.object(forKey: DefaultsKey.notchIdleContent)
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        suite.expect(!NotchSupport.canRest(with: .music, in: defaults) && NotchSupport.idleContent(in: defaults) == .none
               && defaults.string(forKey: DefaultsKey.notchIdleContent) == NotchIdleContent.music.rawValue,
               "a resting choice whose section is off waits, still chosen, while the island rests empty")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(NotchQuickAccessConfiguration.current(in: defaults) == initialLayout,
               "a section switched back on returns its button to its place")
        suite.expect(NotchSupport.canRest(with: .music, in: defaults) && NotchSupport.idleContent(in: defaults) == .music,
               "the island rests with a waiting choice again once its section is back")
        let saved = [DefaultsKey.notchEnabled, AppFeature.notchAgents.availabilityKey, DefaultsKey.notchAgentsEnabled,
                     AppFeature.monitorPower.availabilityKey].map { ($0, defaults.object(forKey: $0)) }
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: AppFeature.notchAgents.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        defaults.set(NotchIdleContent.agents.rawValue, forKey: DefaultsKey.notchIdleContent)
        suite.expect(NotchSupport.canRest(with: .agents, in: defaults) && NotchSupport.idleContent(in: defaults) == .agents,
               "the island's own switch leaves an AI resting choice as it is")
        defaults.set(false, forKey: DefaultsKey.notchAgentsEnabled)
        suite.expect(!NotchSupport.canRest(with: .agents, in: defaults) && NotchSupport.idleContent(in: defaults) == .none,
               "an AI resting choice waits while its section is off, and the island rests empty meanwhile")
        defaults.set(false, forKey: AppFeature.monitorPower.availabilityKey)
        defaults.set(NotchIdleContent.battery.rawValue, forKey: DefaultsKey.notchIdleContent)
        suite.expect(!NotchSupport.canRest(with: .battery, in: defaults) && NotchSupport.idleContent(in: defaults) == .none,
               "a battery resting choice waits while power monitoring is uninstalled")
        for (key, value) in saved { defaults.set(value, forKey: key) }
        defaults.set(savedIdle, forKey: DefaultsKey.notchIdleContent)
        defaults.set("right", forKey: DefaultsKey.notchQuickAccessSide)
        suite.expect(NotchQuickAccessConfiguration.stored(in: defaults) == .init(side: .right, actions: [.explore, .settings]),
               "a saved legacy side retains the former Settings companion")
        defaults.set("", forKey: DefaultsKey.notchQuickAccessSecond)
        suite.expect(NotchQuickAccessConfiguration.stored(in: defaults) == .init(side: .right, actions: [.explore]),
               "an explicitly empty legacy action stays empty under the new defaults")
        defaults.removeObject(forKey: DefaultsKey.notchQuickAccessSide)
        defaults.removeObject(forKey: DefaultsKey.notchQuickAccessSecond)
        suite.expect(NotchSupport.watchesMusicActivity(in: defaults), "enabled music activity can detect playback while the panel is closed")
        suite.expect(NotchSupport.showsMusicActivity(isPlaying: true, in: defaults)
               && !NotchSupport.showsMusicActivity(isPlaying: false, in: defaults),
               "automatic music presentation requires active playback and clears on pause or stop")
        defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
        suite.expect(!NotchSupport.showsMusicActivity(isPlaying: true, in: defaults), "automatic music presentation can be disabled")
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        suite.expect(NotchSupport.visibleIdleContent(isPlaying: false, in: defaults) == .none
               && NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .none,
               "idle music cannot bypass disabled automatic music presentation")
        suite.expect(NotchSupport.idleContent(in: defaults) == .music,
               "disabling automatic music preserves the user's saved resting choice")
        defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
        suite.expect(NotchSupport.visibleIdleContent(isPlaying: false, in: defaults) == .none
               && NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .music,
               "re-enabling automatic music restores the selected music only during playback")
        let idleGeometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                        safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 100)
        suite.expect(idleGeometry.restingSize(showsContent: NotchSupport.visibleIdleContent(isPlaying: false, in: defaults) != .none)
               == CGSize(width: 180, height: 32),
               "stopped idle music shrinks to the physical camera without reserving empty side space")
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
        let savedMascotAvailability = defaults.object(forKey: AppFeature.notchMascot.availabilityKey)
        let savedMascotEnabled = defaults.object(forKey: DefaultsKey.notchMascotEnabled)
        let savedMascotHideWhenIdle = defaults.object(forKey: DefaultsKey.notchMascotHidesWhenIdle)
        defaults.set(false, forKey: AppFeature.notchMascot.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.notchMascotEnabled)
        suite.expect(!NotchSupport.watchesMusicActivity(in: defaults)
               && !NotchSupport.showsMusicActivity(isPlaying: true, in: defaults)
               && NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .none,
               "Nothing at rest suppresses playing music and its background observer without disabling the island")
        suite.expect(NotchSupport.isEnabled(in: defaults) && NotchSupport.modules(in: defaults).contains(.music),
               "Nothing at rest keeps the island and its on-demand music section available")
        defaults.set(true, forKey: AppFeature.notchMascot.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.notchMascotEnabled)
        defaults.set(false, forKey: DefaultsKey.notchMascotHidesWhenIdle)
        suite.expect(NotchSupport.watchesMusicActivity(in: defaults)
               && NotchSupport.visibleIdleContent(isPlaying: false, in: defaults) == .none
               && NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .music,
               "playing music takes the idle companion's place and the companion returns when the island is empty")
        let companionAndMusic = NotchSupport.compactActivities(
            timer: false, downloads: false, agents: true, calendar: false,
            music: NotchSupport.showsMusicActivity(isPlaying: true, in: defaults))
        suite.expect(companionAndMusic == [.agents, .music],
                     "music remains selectable beside a live AI activity while the companion yields")
        defaults.set(savedMascotAvailability, forKey: AppFeature.notchMascot.availabilityKey)
        defaults.set(savedMascotEnabled, forKey: DefaultsKey.notchMascotEnabled)
        defaults.set(savedMascotHideWhenIdle, forKey: DefaultsKey.notchMascotHidesWhenIdle)
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set("music", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchSupport.watchesMusicActivity(in: defaults)
               && NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .none,
               "hidden music cannot keep an activity observer or resting content")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set(true, forKey: DefaultsKey.notchMusicActivity)
        suite.expect(NotchSupport.idleContent(in: defaults) == .none
               && !NotchSupport.showsMusicActivity(isPlaying: true, in: defaults),
               "legacy music preference cannot populate a newly empty idle surface")
        defaults.set(NotchIdleContent.battery.rawValue, forKey: DefaultsKey.notchIdleContent)
        suite.expect(NotchSupport.visibleIdleContent(isPlaying: false, in: defaults) == .battery
               && NotchSupport.showsMusicActivity(isPlaying: true, in: defaults),
               "battery at rest preserves automatic music while playing")
        defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
        suite.expect(NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .battery
               && !NotchSupport.showsMusicActivity(isPlaying: true, in: defaults),
               "disabling automatic music leaves the selected battery visible during playback")
        defaults.set(false, forKey: AppFeature.monitorPower.availabilityKey)
        suite.expect(NotchSupport.idleContent(in: defaults) == .none, "unavailable battery cannot appear while idle")
        defaults.set(true, forKey: AppFeature.monitorPower.availabilityKey)
        defaults.set("clock", forKey: DefaultsKey.notchIdleContent)
        suite.expect(NotchSupport.visibleIdleContent(isPlaying: false, in: defaults) == .none,
               "the retired clock falls back to nothing, including restored settings")
        defaults.set("controls", forKey: DefaultsKey.notchIdleContent)
        suite.expect(NotchSupport.idleContent(in: defaults) == .none,
               "the retired controls idle option falls back to nothing")
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        suite.expect(NotchSupport.modules(in: defaults).contains(.mixer), "the full mixer has a direct destination")
        defaults.set(false, forKey: AppFeature.mixer.availabilityKey)
        suite.expect(!NotchSupport.modules(in: defaults).contains(.mixer)
               && !NotchSupport.controls(in: defaults).contains(.volume), "mixer availability gates its module and volume control")
        defaults.set(true, forKey: AppFeature.mixer.availabilityKey)
        suite.expect(NotchControlItem.allCases.filter { $0.setupRequirement == .none } == [.panel],
                     "every unavailable island control with a setup path has a navigation target")
        suite.expect(NotchControlItem.allCases.filter(\.isLevel) == [.volume, .brightness, .keyboardLight]
                     && !NotchQuickAction.optionalActions.contains(.control(.keyboardLight)),
                     "levels draw as sliders in the card row and are not offered as shortcuts")
        let savedHiddenControls = defaults.string(forKey: DefaultsKey.notchHiddenControls)
        let savedBrightness = defaults.object(forKey: AppFeature.brightness.availabilityKey)
        defaults.set(true, forKey: AppFeature.brightness.availabilityKey)
        defaults.removeObject(forKey: DefaultsKey.notchHiddenControls)
        let lightHiddenByDefault = !NotchSupport.controls(in: defaults).contains(.keyboardLight)
        defaults.set("", forKey: DefaultsKey.notchHiddenControls)
        let lightShown = NotchSupport.controls(in: defaults).contains(.keyboardLight)
        let supportsKeyboardLight = NotchControlItem.keyboardLightIsSupported
        NotchControlItem.keyboardLightIsSupported = { false }
        let lightNeedsHardware = !NotchSupport.controls(in: defaults).contains(.keyboardLight)
            && NotchSupport.controls(in: defaults).contains(.brightness)
        NotchControlItem.keyboardLightIsSupported = supportsKeyboardLight
        defaults.set(false, forKey: AppFeature.brightness.availabilityKey)
        let lightGated = !NotchSupport.controls(in: defaults).contains(.keyboardLight)
        suite.expect(lightHiddenByDefault && lightShown && lightGated
                     && NotchControlItem.keyboardLight.setupRequirement == .feature(.brightness),
                     "the keyboard light level is opt-in and follows the brightness feature")
        suite.expect(lightNeedsHardware,
                     "a level restored from a Mac with a keyboard light stays out of an island without one")
        let launch = (try? String(contentsOfFile: "Sources/Vorssaint/main.swift", encoding: .utf8)) ?? ""
        suite.expect(launch.contains("NotchControlItem.keyboardLightIsSupported = { BrightnessService.keyboardLightIsSupported }"),
                     "launch asks the brightness service whether this Mac has a keyboard light")
        let controlsView = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Notch/NotchControlsView.swift", encoding: .utf8)) ?? ""
        let layoutEditor = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Settings/NotchLayoutEditor.swift", encoding: .utf8)) ?? ""
        suite.expect(["NotchBandLevels(band: band, levels: bandLevels, side: .leading)",
                      "NotchBandLevels(band: band, levels: bandLevels, side: .trailing)",
                      "NotchLevelRow(levels: belowLevels)"].allSatisfy { layout in
                         controlsView.contains(layout) && layoutEditor.contains(layout)
                     },
                     "the island and its Settings preview lay the levels out in the top row the same way")
        defaults.set(savedHiddenControls, forKey: DefaultsKey.notchHiddenControls)
        defaults.set(savedBrightness, forKey: AppFeature.brightness.availabilityKey)
        suite.expect(NotchControlItem.brightness.setupRequirement == .feature(.brightness)
                     && NotchControlItem.recording.setupRequirement == .feature(.screenRecorder)
                     && NotchControlItem.scratchpad.setupRequirement == .feature(.scratchpad),
                     "feature-gated controls lead to the matching feature in the hub")
        suite.expect(NotchControlItem.music.setupRequirement == .page(.music, feature: nil)
                     && NotchControlItem.mixer.setupRequirement == .page(.mixer, feature: .mixer)
                     && NotchControlItem.speedTest.setupRequirement == .page(.system, feature: .monitorNetwork),
                     "page-gated controls lead to their island section or the required feature")
        defaults.set("panel,panel,unknown,speedTest", forKey: DefaultsKey.notchControlOrder)
        defaults.set("volume,screenshot", forKey: DefaultsKey.notchHiddenControls)
        let controls = NotchSupport.controls(in: defaults)
        suite.expect(controls.first == .panel && Set(controls).count == controls.count,
               "shortcut ordering tolerates duplicate and obsolete identifiers")
        suite.expect(!controls.contains(.volume) && !controls.contains(.screenshot), "individual controls can be hidden")
        defaults.set("", forKey: DefaultsKey.notchHiddenControls)
        suite.expect(NotchSupport.controls(in: defaults).last == .scratchpad
               && NotchQuickAction(id: NotchQuickAction.control(.scratchpad).id) == .control(.scratchpad)
               && NotchQuickAction.optionalActions.contains(.control(.scratchpad)),
               "the scratchpad shortcut can be shown among the controls and placed as a floating button")
        defaults.set(false, forKey: AppFeature.scratchpad.availabilityKey)
        suite.expect(!NotchSupport.controls(in: defaults).contains(.scratchpad)
               && !NotchQuickAction.control(.scratchpad).isAvailable(in: defaults),
               "an uninstalled scratchpad leaves no island shortcut")
        defaults.set(true, forKey: AppFeature.scratchpad.availabilityKey)
        defaults.set("mixer,commandBar", forKey: DefaultsKey.notchHiddenControls)
        defaults.set("", forKey: DefaultsKey.notchControlOrder)
        let allModules = NotchModule.allCases
        suite.expect(Set(allModules.map(\.shortcutKey)).count == allModules.count,
               "every section has a unique direct shortcut, including destinations after the ninth")
        for module in allModules {
            suite.expect(NotchSupport.moduleShortcut(module.shortcutKey, modules: allModules.reversed()) == module
                   && NotchSupport.moduleShortcut(module.shortcutKey.uppercased(), modules: allModules) == module,
                   "direct section shortcuts remain stable across ordering and letter case")
            suite.expect(NotchSupport.moduleShortcut(module.shortcutKey, modules: allModules.filter { $0 != module }) == nil,
                   "hidden or unavailable sections cannot be opened by their shortcut")
        }
        for characters in ["", "0", "9", "10", "cc", "-1", " "] {
            suite.expect(NotchSupport.moduleShortcut(characters, modules: allModules) == nil,
                   "unassigned keys cannot navigate")
        }
        suite.expect(NotchSupport.moduleShortcut("c", modules: []) == nil,
               "direct shortcuts tolerate an empty gallery")
        var reached = Set<NotchModule>()
        var current: NotchModule? = allModules.first
        for _ in allModules {
            if let current { reached.insert(current) }
            current = NotchSupport.adjacentModule(to: current, modules: allModules, backwards: false)
        }
        suite.expect(reached == Set(allModules) && current == allModules.first,
               "keyboard cycling reaches every section and wraps without a nine-item limit")
        suite.expect(NotchSupport.adjacentModule(to: allModules.first, modules: allModules, backwards: true) == allModules.last
               && NotchSupport.adjacentModule(to: .camera, modules: [.files], backwards: true) == .files
               && NotchSupport.adjacentModule(to: nil, modules: [], backwards: false) == nil,
               "reverse cycling, removed selections and an empty gallery have safe destinations")
        suite.expect(NotchSupport.clipboardPasteTarget(highlighted: nil, in: [1, 2, 3]) == 1
                && NotchSupport.clipboardPasteTarget(highlighted: 2, in: [1, 2, 3]) == 2
                && NotchSupport.clipboardPasteTarget(highlighted: 9, in: [1, 2, 3]) == 1
                && NotchSupport.clipboardPasteTarget(highlighted: 2, in: [Int]()) == nil,
               "Return pastes the highlighted or first visible clipboard entry, and nothing from an empty list")
        // Opening the page highlights what was copied last, which is the first recent entry below any pinned ones.
        suite.expect(NotchSupport.restingClipboardHighlight([(1, true), (2, true), (3, false), (4, false)]) == 3
                && NotchSupport.restingClipboardHighlight([(1, true), (2, true)]) == 1
                && NotchSupport.restingClipboardHighlight([(5, false)]) == 5
                && NotchSupport.restingClipboardHighlight([(Int, Bool)]()) == nil,
               "the clipboard opens on the entry copied last, not on a pinned one, and on the top pinned one when only those exist")
        func key(_ code: UInt16, _ characters: String = "", _ modifiers: NSEvent.ModifierFlags = [],
                 composing: Bool = false) -> NotchClipboardKey? {
            NotchSupport.clipboardKey(keyCode: code, characters: characters, modifiers: modifiers, composing: composing)
        }
        suite.expect(key(126) == .move(backwards: true) && key(125) == .move(backwards: false)
                && key(36) == .paste && key(76) == .paste,
               "the arrow keys and Return drive the list while the search field has the focus")
        suite.expect(key(0, "a") == .reveal && key(0, "Ab") == .reveal && key(0, "ñ") == .reveal && key(40, "ㅎ") == .reveal
                && key(49, " ") == nil && key(48, "\t") == nil && key(51, "\u{7f}") == nil
                && key(125, "\u{F701}") == .move(backwards: false),
               "a typed letter shows the search field and goes on to it, while a space and control keys stay as they are")
        // Japanese, Chinese and Korean input and the accent keys compose in
        // the field: its keys, Return and the arrows included, are the input method's.
        suite.expect(key(36, composing: true) == .reveal && key(125, composing: true) == .reveal
                && key(0, "a", composing: true) == .reveal && key(36, "", .command, composing: true) == nil,
               "every key goes on to an input method while it composes")
        suite.expect(key(36, "", .command) == nil && key(18, "1", .command) == nil && key(0, "a", .command) == nil
                && key(0, "a", .control) == nil && key(0, "å", .option) == nil,
               "keys held with Command, Control or Option are left to their own shortcuts")
        // Arrow keys carry the numeric pad and function flags, which change nothing.
        suite.expect(key(125, "\u{F701}", [.shift, .numericPad, .function]) == nil && key(126, "", .shift) == nil
                && key(36, "\r", .shift) == nil && key(76, "\u{3}", .shift) == nil
                && key(0, "A", .shift) == .reveal && key(125, "\u{F701}", [.numericPad, .function]) == .move(backwards: false),
               "Shift with an arrow or Return is left to the search field, while a capital letter still shows it")
        // An open entry is drawn over the list from its row and stays in view
        // without the list scrolling: up where it would pass the bottom, down
        // to the top where its row is partly scrolled away.
        func openOffset(_ rowTop: CGFloat, _ height: CGFloat, in visible: CGFloat) -> CGFloat {
            NotchSupport.clipboardOpenOffset(rowTop: rowTop, rowHeight: 52, height: height, visibleHeight: visible)
        }
        suite.expect(openOffset(20, 120, in: 200) == 0 && openOffset(140, 120, in: 200) == -60
                && openOffset(170, 120, in: 200) == -90 && openOffset(-20, 120, in: 200) == 20
                && openOffset(60, 200, in: 200) == -60,
               "an open clipboard entry stays within the list over the row it opened from")
        // Once its row has scrolled out of the list, the open entry goes on
        // from the row's edge with it, instead of staying over other rows.
        suite.expect(openOffset(-52, 150, in: 300) == 52 && openOffset(-200, 150, in: 300) == 52
                && openOffset(300, 150, in: 300) == -150 && openOffset(400, 150, in: 300) == -150,
               "an open clipboard entry scrolls away with its row once the row has left the list")
        // As the page opens, the list is at its top: rows 8 apart, of which
        // the highlighted one needs 26 points in view.
        func openingScroll(_ index: Int, in visible: CGFloat, rowHeight: CGFloat = 104) -> Int {
            NotchSupport.clipboardOpeningScroll(index: index, rowHeight: rowHeight, spacing: 8, shown: 26,
                                                visibleHeight: visible)
        }
        suite.expect(openingScroll(1, in: 180) == 0 && openingScroll(2, in: 264) == 0 && openingScroll(2, in: 250) == 0
                && openingScroll(2, in: 172, rowHeight: 52) == 0 && openingScroll(0, in: 20) == 0,
               "a clipboard list opens at its top while the highlighted row shows its top")
        suite.expect(openingScroll(2, in: 249) == 1 && openingScroll(2, in: 180) == 1 && openingScroll(3, in: 264) == 1
                && openingScroll(4, in: 264, rowHeight: 52) == 1 && openingScroll(3, in: 20) == 3,
               "a clipboard list that must move to show the highlighted row moves by the fewest whole rows")
        suite.expect(NotchSupport.steppedItem(from: nil, in: [1, 2, 3], backwards: false) == 1
               && NotchSupport.steppedItem(from: nil, in: [1, 2, 3], backwards: true) == 1
               && NotchSupport.steppedItem(from: 1, in: [1, 2, 3], backwards: false) == 2
               && NotchSupport.steppedItem(from: 3, in: [1, 2, 3], backwards: false) == 3
               && NotchSupport.steppedItem(from: 1, in: [1, 2, 3], backwards: true) == 1
               && NotchSupport.steppedItem(from: 9, in: [1, 2, 3], backwards: true) == 1
               && NotchSupport.steppedItem(from: 1, in: [Int](), backwards: false) == nil,
               "clipboard arrow keys start at the top result, stop at the ends and recover from a filtered-out row")
        suite.expect(NotchSupport.searchHighlight(keeping: nil, in: [1, 2, 3], query: "note") == 1
               && NotchSupport.searchHighlight(keeping: nil, in: [1, 2, 3], query: " \n ") == nil
               && NotchSupport.searchHighlight(keeping: 2, in: [1, 2, 3], query: "note") == 2
               && NotchSupport.searchHighlight(keeping: 2, in: [1, 2, 3], query: "") == 2
               && NotchSupport.searchHighlight(keeping: 9, in: [1, 2, 3], query: "note") == 1
               && NotchSupport.searchHighlight(keeping: 9, in: [1, 2, 3], query: "") == nil
               && NotchSupport.searchHighlight(keeping: nil, in: [Int](), query: "note") == nil,
               "a typed clipboard search highlights its top result for Return, and an empty one waits for an arrow")
        suite.expect(NotchSupport.filteredModules([.controls, .music, .files], query: "  MÚSＩCA  ", title: {
            $0 == .music ? "Música" : "Arquivos"
        }) == [.music], "gallery search ignores accents, letter case, character width and surrounding spaces")
        suite.expect(NotchSupport.filteredModules([.files, .controls], query: "arquivo novo", title: {
            $0 == .files ? "Novo arquivo" : "Controles"
        }) == [.files], "gallery search matches every word independently of their order")
        suite.expect(NotchSupport.filteredModules(allModules, query: "", title: { $0.rawValue }) == allModules
               && NotchSupport.filteredModules(allModules, query: "unmatched", title: { $0.rawValue }).isEmpty,
               "empty queries preserve configured ordering and unmatched queries have no action")
        suite.expect(!NotchSupport.closesOnPointerExit(expanded: true, peeking: false, openedByHover: false),
               "menu bar and keyboard openings survive a pointer outside the notch")
        suite.expect(NotchSupport.closesOnPointerExit(expanded: true, peeking: false, openedByHover: true)
               && NotchSupport.closesOnPointerExit(expanded: false, peeking: true, openedByHover: false),
               "hover presentations still close when the pointer leaves")
        var hover = NotchHoverState()
        hover.close(pointerInside: true)
        for _ in 0..<4 { hover.update(pointerInside: true) }
        suite.expect(hover.suppressed, "closing under the pointer survives repeated hover events caused by resizing")
        hover.update(pointerInside: false)
        hover.update(pointerInside: true)
        suite.expect(!hover.suppressed, "leaving and returning rearms hover without a timer")
        hover.close(pointerInside: true)
        hover.open()
        suite.expect(!hover.suppressed, "an intentional opening remains possible while hover is suppressed")
        hover.close(pointerInside: false)
        suite.expect(!hover.suppressed, "closing away from the island does not block the next approach")
        let topArea = idleGeometry.activationArea(in: idleGeometry.expanded, hasHeader: true, compactActivity: false)
        let screenTop = CGPoint(x: idleGeometry.screen.midX, y: idleGeometry.screen.maxY)
        suite.expect(idleGeometry.contains(screenTop, in: idleGeometry.collapsed)
               && !idleGeometry.contains(CGPoint(x: screenTop.x, y: screenTop.y + 0.5), in: idleGeometry.collapsed)
               && !idleGeometry.contains(CGPoint(x: idleGeometry.screen.minX, y: screenTop.y), in: idleGeometry.collapsed),
               "hover includes the exact screen top without accepting points above or beside the island")
        hover.close(pointerInside: true)
        hover.update(pointerInside: idleGeometry.contains(screenTop, in: idleGeometry.collapsed))
        suite.expect(hover.suppressed, "the physical screen edge cannot rearm hover after an explicit close")
        suite.expect(topArea.contains(CGPoint(x: idleGeometry.expanded.width / 2, y: 1))
               && topArea.maxY == idleGeometry.safeContentTop,
               "the very top is clickable while section buttons below it keep their own actions")
        let footerGeometry = NotchGeometry(screen: idleGeometry.screen, safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 0)
        suite.expect(footerGeometry.activationArea(in: footerGeometry.compactActivitySize, hasHeader: false, compactActivity: true).maxY
               == footerGeometry.compactActivityTopPadding,
               "top activation does not cover timer and download controls in the footer")
        let plainGeometry = NotchGeometry(screen: idleGeometry.screen, safeAreaTop: 0, cameraWidth: 0, compactSideRoom: 0)
        suite.expect(plainGeometry.activationArea(in: plainGeometry.compactActivitySize, hasHeader: false, compactActivity: true).width == plainGeometry.cameraWidth,
               "the simulated camera leaves the activity controls beside it independently clickable")
        suite.expect(ScreenshotSupport.selectionDimAlpha(notchControls: true, isFrozen: true, isDragging: false) == 0,
               "opening capture controls in the notch does not darken the desktop")
        suite.expect(ScreenshotSupport.selectionDimAlpha(notchControls: true, isFrozen: true, isDragging: true) > 0,
               "dragging a capture region retains visual selection feedback")
        suite.expect(ScreenshotSupport.selectionDimAlpha(notchControls: false, isFrozen: true, isDragging: false) == 0.22,
               "the standalone capture chooser keeps its existing contrast")
        for tool in ScreenCaptureTool.allCases {
            suite.expect(tool.capturesAudio == (tool == .recording),
                   "only screen recording shows microphone and system-audio controls: \(tool.rawValue)")
        }
        suite.expect(!NotchSupport.routes(.clipboard, in: defaults) && NotchSupport.routes(.capture, in: defaults),
               "clipboard activity still needs history capture while installed captures start enabled")
        defaults.set(true, forKey: DefaultsKey.clipboardHistoryEnabled)
        suite.expect(NotchSupport.routes(.clipboard, in: defaults), "installed clipboard activity starts once history capture is enabled")
        suite.expect(NotchSupport.routesScratchpad(in: defaults), "Scratchpad defaults to its visible island page")
        defaults.set(false, forKey: DefaultsKey.notchScratchpad)
        suite.expect(!NotchSupport.routesScratchpad(in: defaults), "Scratchpad can use its separate window without hiding its page")
        defaults.set(true, forKey: DefaultsKey.notchScratchpad)
        defaults.set("scratchpad", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchSupport.routesScratchpad(in: defaults), "a hidden Scratchpad page falls back to its window")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(false, forKey: AppFeature.scratchpad.availabilityKey)
        suite.expect(!NotchSupport.routesScratchpad(in: defaults), "an unavailable Scratchpad cannot be routed to the island")
        defaults.set(true, forKey: AppFeature.scratchpad.availabilityKey)
        suite.expect(NotchSupport.routesClipboardWindow(in: defaults), "clipboard opening defaults to the enabled island")
        defaults.set(false, forKey: DefaultsKey.notchClipboardWindow)
        suite.expect(!NotchSupport.routesClipboardWindow(in: defaults), "clipboard can still use its separate window")
        defaults.set(true, forKey: DefaultsKey.notchClipboardWindow)
        defaults.set("clipboard,unknown", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchSupport.routesClipboardWindow(in: defaults), "hidden clipboard keeps the ordinary history available")
        suite.expect(!NotchSupport.routes(.clipboard, in: defaults), "hidden module cannot leak an activity")
        defaults.set("system,music,music,unknown", forKey: DefaultsKey.notchModuleOrder)
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        suite.expect(NotchSupport.modules(in: defaults) == [.system, .music, .controls, .mixer, .captures, .files, .tools, .calendar, .notifications, .timer, .camera, .downloads, .scratchpad, .agents, .watch],
               "module order ignores unknown ids and duplicates, preserving newly added modules")
        suite.expect(NotchSupport.routesShelf(in: defaults) && NotchSupport.revealsShelfDrag(in: defaults),
               "the enabled notch replaces the file destination and reveals active drags")
        defaults.set(false, forKey: DefaultsKey.notchDragReveal)
        suite.expect(NotchSupport.routesShelf(in: defaults) && !NotchSupport.revealsShelfDrag(in: defaults),
               "drag reveal can be disabled without moving the shelf")
        defaults.set(false, forKey: DefaultsKey.notchShelf)
        suite.expect(NotchSupport.showsFiles(in: defaults) && !NotchSupport.routesShelf(in: defaults),
               "choosing a separate window keeps the choice on offer while the shelf stays out of the island")
        defaults.set(true, forKey: DefaultsKey.notchShelf)
        defaults.set(false, forKey: DefaultsKey.notchCaptureControls)
        suite.expect(!NotchSupport.routesCaptureControls(in: defaults), "capture controls retain an independent destination")
        defaults.set(false, forKey: AppFeature.quickLauncher.availabilityKey)
        suite.expect(!NotchSupport.modules(in: defaults).contains(.tools) && !NotchSupport.routesQuickPanel(in: defaults),
               "removing the quick panel also removes its embedded tools and shortcut routing")
        defaults.set(false, forKey: DefaultsKey.notchQuickPanel)
        suite.expect(!NotchSupport.routesQuickPanel(in: defaults), "quick panel shortcut can keep its original destination")
        defaults.set(false, forKey: AppFeature.shelf.availabilityKey)
        suite.expect(!NotchSupport.modules(in: defaults).contains(.files), "unavailable shelf leaves no notch surface")
        defaults.set(false, forKey: AppFeature.notch.availabilityKey)
        suite.expect(!NotchSupport.isEnabled(in: defaults), "hub is stronger than the notch master switch")
        suite.expect(!NotchSupport.usesHapticFeedback(in: defaults), "removing the feature also gates tactile feedback")
        suite.expect(NotchEvent.allCases.allSatisfy { !NotchSupport.routes($0, in: defaults) },
               "hub removal gates every notch event")

        let keys: Set<String> = [DefaultsKey.notchShowPlayingMusic, DefaultsKey.notchIncludeOtherPlayers, DefaultsKey.notchShowInCaptures, DefaultsKey.notchIdleContent, DefaultsKey.notchHiddenControls, DefaultsKey.notchControlOrder, DefaultsKey.notchSize, DefaultsKey.notchOutlineEnabled, DefaultsKey.notchHideMenuBarGap, DefaultsKey.notchShelf, DefaultsKey.notchDragReveal,
                                DefaultsKey.notchCustomWidth, DefaultsKey.notchCustomHeight, DefaultsKey.notchHapticFeedback,
                                DefaultsKey.notchCaptureControls, DefaultsKey.notchQuickPanel, DefaultsKey.notchAppPanel,
                                DefaultsKey.notchHidesMenuBarIcon, DefaultsKey.notchScratchpad,
                                DefaultsKey.notchHoverExpands, DefaultsKey.notchEnabled, DefaultsKey.notchDisplay,
                                DefaultsKey.notchOpenOnHover, DefaultsKey.notchHoverDelay, DefaultsKey.notchCloseDelay, DefaultsKey.notchHideUntilHover, DefaultsKey.notchHiddenModules,
                                DefaultsKey.notchModuleOrder, DefaultsKey.notchQuickAccessLayout, DefaultsKey.notchQuickAccessSide, DefaultsKey.notchQuickAccessSecond, DefaultsKey.notchQuickAccessThird, DefaultsKey.notchVolume,
                                DefaultsKey.notchMicrophone, DefaultsKey.notchBrightness, DefaultsKey.notchBattery,
                                DefaultsKey.notchClipboard, DefaultsKey.notchClipboardWindow, DefaultsKey.notchCapture,
                                DefaultsKey.notchTrackChange, DefaultsKey.notchMusicActivity, DefaultsKey.notchHideInCaptures, DefaultsKey.panelControlNotch,
                                AppFeature.notch.availabilityKey]
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: keys), "every portable notch preference travels in backup")
        let restored = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [DefaultsKey.notchEnabled: true,
                                                DefaultsKey.notchDisplay: "builtIn",
                                                DefaultsKey.notchSize: "custom",
                                                DefaultsKey.notchCustomWidth: 390.0,
                                                DefaultsKey.notchCustomHeight: 580.0,
                                                DefaultsKey.notchOutlineEnabled: true,
                                                DefaultsKey.notchHideMenuBarGap: false,
                                                DefaultsKey.notchHapticFeedback: true,
                                                DefaultsKey.notchIncludeOtherPlayers: true,
                                                DefaultsKey.notchHiddenModules: "clipboard",
                                                DefaultsKey.notchVolume: false,
                                                DefaultsKey.notchQuickAccessSide: "right",
                                                DefaultsKey.notchQuickAccessSecond: "timer",
                                                DefaultsKey.notchQuickAccessThird: "settings"],
        ])
        suite.expect(restored?[DefaultsKey.notchEnabled] as? Bool == true
               && restored?[DefaultsKey.notchDisplay] as? String == "builtIn"
               && restored?[DefaultsKey.notchVolume] as? Bool == false,
               "backup restores notch placement and event choices")
        suite.expect(restored?[DefaultsKey.notchSize] as? String == "custom"
               && restored?[DefaultsKey.notchCustomWidth] as? Double == 390
               && restored?[DefaultsKey.notchCustomHeight] as? Double == 580
               && restored?[DefaultsKey.notchOutlineEnabled] as? Bool == true
               && restored?[DefaultsKey.notchHideMenuBarGap] as? Bool == false
               && restored?[DefaultsKey.notchHapticFeedback] as? Bool == true
               && restored?[DefaultsKey.notchIncludeOtherPlayers] as? Bool == true,
               "backup restores custom dimensions, outline, gap hiding, haptics and playback scope together")
        suite.expect(restored?[DefaultsKey.notchQuickAccessSide] as? String == "right"
               && restored?[DefaultsKey.notchQuickAccessSecond] as? String == "timer"
               && restored?[DefaultsKey.notchQuickAccessThird] as? String == "settings",
               "backup restores both the side and the actions of floating quick access")
        suite.expect(!SettingsBackupSupport.valueLooksRight(DefaultsKey.notchQuickAccessSide, ["right"])
               && !SettingsBackupSupport.valueLooksRight(DefaultsKey.notchQuickAccessSecond, true)
               && !SettingsBackupSupport.valueLooksRight(DefaultsKey.notchQuickAccessThird, 3),
               "legacy layout keys retain string validation after leaving registered defaults")
        defaults.set("unknown", forKey: DefaultsKey.notchQuickAccessSide)
        defaults.set("settings", forKey: DefaultsKey.notchQuickAccessSecond)
        defaults.set("settings", forKey: DefaultsKey.notchQuickAccessThird)
        suite.expect(NotchQuickAccessConfiguration.current(in: defaults) == .init(side: .left, actions: [.explore, .settings]),
               "invalid placement falls back safely and duplicate quick actions are not repeated")
        defaults.set("timer", forKey: DefaultsKey.notchQuickAccessSecond)
        defaults.set("../../unknown", forKey: DefaultsKey.notchQuickAccessThird)
        defaults.set("timer", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(NotchQuickAccessConfiguration.current(in: defaults).actions == [.explore],
               "hidden destinations and unrecognized action identifiers cannot create a floating action")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        for side in [NotchQuickAccessSide.left, .right] {
            let edge: CGFloat = side == .left ? 72 : 632
            for index in 0..<3 {
                let point = NotchQuickAccessLayout.center(index: index, progress: 1, edge: edge, top: 60, side: side)
                suite.expect(NotchQuickAccessLayout.hitTest(point, count: 3, edge: edge, top: 60, side: side),
                       "every visible bubble accepts its own center on either side")
                let gap = CGPoint(x: edge + (side == .left ? -6 : 6), y: point.y)
                suite.expect(!NotchQuickAccessLayout.hitTest(gap, count: 3, edge: edge, top: 60, side: side),
                       "the transparent gap between a bubble and the notch does not claim clicks")
            }
        }
        suite.expect(NotchQuickAccessLayout.hoverRect(count: 0, edge: 72, top: 60, side: .left).isNull,
               "no floating actions means no extra hover surface")
        for side in [NotchQuickAccessSide.left, .right] {
            for count in 1...3 {
                let edge: CGFloat = side == .left ? 86 : 618
                let region = NotchQuickAccessLayout.hoverRect(count: count, edge: edge, top: 60, side: side)
                let first = NotchQuickAccessLayout.center(index: 0, progress: 1, edge: edge, top: 60, side: side)
                let last = NotchQuickAccessLayout.center(index: count - 1, progress: 1, edge: edge, top: 60, side: side)
                let start = side == .left ? first.x - 34 : edge - 12
                let end = side == .left ? edge + 12 : first.x + 34
                let pathIsCovered = stride(from: start, through: end, by: 1).allSatisfy { x in
                    stride(from: first.y - 30, through: last.y + 30, by: 1).allSatisfy { y in
                        region.contains(CGPoint(x: x, y: y))
                    }
                }
                suite.expect(pathIsCovered, "hover remains continuous through gaps, between buttons and around their edges")
                let outside = CGPoint(x: side == .left ? region.minX - 1 : region.maxX + 1, y: first.y)
                suite.expect(!region.contains(outside), "moving beyond the forgiving hover region still permits closing")
            }
        }
        for side in NotchQuickAccessSide.allCases {
            for count in 1...3 {
                for height: CGFloat in [120, 190, 280, 400] {
                    let body = CGRect(x: 72, y: 0, width: 440, height: height)
                    let configuration = NotchQuickAccessConfiguration(buttons:
                        (0..<count).map { _ in NotchQuickButton(action: .settings, side: side) })
                    let values = NotchQuickAccessLayout.placements(configuration, body: body, headerTop: 61)
                    let first = values.first!.center(progress: 1)
                    let last = values.last!.center(progress: 1)
                    if side == .bottom {
                        suite.expect((first.x + last.x) / 2 == body.midX && first.y == body.maxY + 34,
                                     "bottom actions stay centered beneath the island")
                    } else {
                        suite.expect(first.y >= 34 && first.y <= 61 && last.y - first.y == CGFloat(count - 1) * 54,
                                     "side actions retain their size and spacing without crossing the top edge")
                        if height == 190 && count == 3 {
                            suite.expect(first.y == 41 && last.y == 149,
                                         "three actions balance the margins of a short compact page")
                        }
                        if height >= 280 {
                            suite.expect(first.y == 61, "roomy pages retain their header-aligned actions")
                        }
                        let hover = NotchQuickAccessLayout.hoverRect(count: count, edge: values[0].edge,
                                                                    top: values[0].top, side: side)
                        suite.expect(values.allSatisfy { hover.contains($0.center(progress: 1)) },
                                     "the hover corridor follows the adapted button positions")
                    }
                }
            }
        }
        // Two on the left and three on the right, beside a short page.
        let uneven = NotchQuickAccessConfiguration(buttons:
            [NotchQuickAccessSide.left, .left, .right, .right, .right].map { NotchQuickButton(action: .settings, side: $0) })
        let level = NotchQuickAccessLayout.placements(uneven, body: CGRect(x: 72, y: 0, width: 440, height: 178), headerTop: 61)
        suite.expect(level[0].top == level[2].top && level[0].top < 61,
                     "a short page lifts both side columns together, so they start level")
        let legacy = NotchQuickAccessConfiguration.stored(in: defaults)
        suite.expect(legacy == NotchQuickAccessConfiguration.stored(in: defaults),
               "legacy quick-access migration keeps stable identities across refreshes")
        let placements = [NotchQuickButton(action: .explore, side: .left),
                          NotchQuickButton(action: .settings, side: .right),
                          NotchQuickButton(action: .control(.keepAwake), side: .bottom)]
        var layout = NotchQuickAccessConfiguration(buttons: placements)
        defaults.set(layout.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        suite.expect(NotchQuickAccessConfiguration.stored(in: defaults) == layout,
               "the visual layout stores all three edges and direct actions together")
        layout.move(placements[0].id, to: .bottom, before: placements[2].id)
        suite.expect(layout.buttons.first(where: { $0.id == placements[0].id })?.side == .bottom
               && layout.buttons.filter { $0.side == .bottom }.map(\.id) == [placements[0].id, placements[2].id],
               "moving a button preserves its identity and inserts it in the chosen order")
        let crowded = NotchQuickAccessConfiguration(buttons: (0..<12).map { _ in NotchQuickButton(action: .settings, side: .bottom) })
        defaults.set(crowded.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        suite.expect(crowded.sanitized().buttons.count == 3 && NotchQuickAccessConfiguration.current(in: defaults).buttons.count == 3,
               "restored layouts cannot overfill an edge")
        var invalidButton = NotchQuickButton(action: .settings, side: .left, label: "  Name\nwith line  ")
        invalidButton.actionID = "unrecognized-action"
        suite.expect(NotchQuickAccessConfiguration(buttons: [invalidButton]).sanitized().buttons.isEmpty,
               "unknown restored actions cannot run")
        let emptyLayout = NotchQuickAccessConfiguration(buttons: [])
        defaults.set(emptyLayout.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        suite.expect(NotchQuickAccessConfiguration.stored(in: defaults).buttons.isEmpty,
               "an intentionally empty layout does not resurrect legacy buttons")
        let recoveredLayout = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [DefaultsKey.notchQuickAccessLayout: layout.encoded]])
        suite.expect(recoveredLayout?[DefaultsKey.notchQuickAccessLayout] as? Data == layout.encoded,
               "backup preserves the visual layout and its stable button identities")
        defaults.removeObject(forKey: DefaultsKey.notchQuickAccessLayout)
        let bottomRegion = NotchQuickAccessLayout.hoverRect(count: 3, edge: 300, top: 150, side: .bottom)
        suite.expect(bottomRegion.contains(CGPoint(x: 204, y: 307)) && bottomRegion.contains(CGPoint(x: 204, y: 364)),
               "bottom buttons retain a continuous forgiving path back to the island")
        suite.expect(AppFeature.notch.settingsDestination.page == .notch, "hub routes to notch settings")
        suite.expect(!FeatureVisibilitySupport.isPageVisible(.notch, isAvailable: { !FeatureVisibilitySupport.features(for: .notch).contains($0) }),
               "notch settings disappear when uninstalled")

        for language in AppLanguage.allCases {
            for child in Mirror(reflecting: FeatureStrings.notch(language)).children {
                let value = child.value as? String ?? ""
                suite.expect(!value.isEmpty && !value.contains("—"),
                       "notch localized text is present and human-readable: \(language) \(child.label ?? "")")
            }
        }

        let frames = [CGRect(x: 0, y: 0, width: 1512, height: 982),
                      CGRect(x: -1920, y: -100, width: 1920, height: 1080),
                      CGRect(x: 100, y: 982, width: 900, height: 1440),
                      CGRect(x: 0, y: 0, width: 640, height: 480)]
        let compact = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210)
        let spacious = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210, layout: .spacious)
        let tall = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210, layout: .custom, customHeight: 640)
        for geometry in [compact, spacious, tall] {
            suite.expect(geometry.sectionPickerSize(count: 1).height < geometry.sectionPickerSize(count: allModules.count).height,
                   "a short search result shrinks the gallery instead of reserving empty rows")
        }
        suite.expect(compact.sectionRows(count: allModules.count) == 3 && spacious.sectionRows(count: allModules.count) == 3
               && compact.contentSize(for: compact.sectionPickerSize(count: allModules.count)).height <= compact.pageBudget
               && tall.sectionRows(count: allModules.count) > spacious.sectionRows(count: allModules.count)
               && tall.sectionRows(count: allModules.count)
                   <= NotchSectionPaging.rows(count: allModules.count, columns: tall.sectionColumns),
               "the gallery is a page: presets show three whole rows and a tall island shows more")
        suite.expect(compact.sectionColumns == 4 && spacious.sectionColumns == 5
               && compact.sectionColumns * compact.sectionRows(count: allModules.count) < allModules.count
               && spacious.sectionColumns * (spacious.sectionRows(count: allModules.count) + 1) >= allModules.count,
               "a compact island steps rows to reach its last sections and a spacious one steps at most one")
        suite.expect(NotchLayout.sectionTileHeight * 2 + NotchLayout.sectionSpacing <= NotchLayout.compactContentHeight
               && NotchLayout.sectionTileHeight * 3 + NotchLayout.sectionSpacing * 2 <= NotchLayout.pageContentHeight,
               "two rows fit the compact strip and three rows fit the gallery's page exactly or better")
        for geometry in [compact, spacious, tall] {
            let columns = geometry.sectionColumns
            let tileWidth = (geometry.contentWidth - NotchLayout.sectionIndicatorWidth
                             - CGFloat(columns - 1) * NotchLayout.sectionSpacing) / CGFloat(columns)
            suite.expect(tileWidth >= NotchLayout.sectionTileWidth,
                   "gallery tiles keep their readable width beside the row indicator")
            suite.expect(QuickToolsSupport.gridIndex(after: 0, count: allModules.count,
                                                     flow: .rows(columns: columns), direction: .down) == columns,
                   "gallery Down follows the next visible row rather than the old sideways rail")
        }
        for size in [CGSize(width: 304, height: 534), CGSize(width: 424, height: 180),
                     CGSize(width: 504, height: 264), CGSize(width: 304, height: 144),
                     CGSize(width: 424, height: 300)] {
            let preview = NotchLayout.cameraPreviewSize(in: size)
            let ratio = preview.width / preview.height
            suite.expect(preview.width <= size.width && preview.height <= size.height
                   && (preview.width == size.width || preview.height == size.height)
                   && ratio > 4.0 / 3.0 - 0.001 && ratio < 16.0 / 9.0 + 0.001,
                   "camera preview fills the page's width or height and crops no further than 16:9 or 4:3")
        }
        suite.expect(compact.contentSize(for: compact.sectionPickerSize(count: 0)).height == NotchLayout.emptyHeight
               && compact.contentSize(for: compact.sectionPickerSize(count: 1)).height == NotchLayout.sectionTileHeight,
               "an unmatched search keeps the recovery guidance's row and a match takes just its tiles, the search living in the header")
        for layout in NotchSize.allCases {
            let geometry = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210, layout: layout)
            for module in NotchModule.allCases {
                let content = geometry.contentSize(for: geometry.expandedSize(module: module)).height
                suite.expect(content <= geometry.contentBudget && content > 0,
                       "every page stays inside its preset's strip: \(layout) \(module)")
            }
            suite.expect(geometry.contentSize(for: geometry.expandedSize(module: .tools, panel: true)).height == geometry.pageBudget
                   && geometry.contentSize(for: geometry.expandedSize(module: .system, detail: true)).height == geometry.pageBudget
                   && geometry.pageBudget >= geometry.contentBudget,
                   "the app panel and a metric detail get a readable page even inside a short preset: \(layout)")
            let detail = { (height: CGFloat, panel: Bool) in
                geometry.contentSize(for: geometry.expandedSize(module: .system, detail: true, panel: panel,
                                                                detailHeight: height)).height
            }
            suite.expect(detail(140, false) == 144 && detail(900, false) == geometry.pageBudget
                   && detail(140, true) == geometry.pageBudget,
                   "a measured detail such as Fan Control fits its card within the page instead of a tall empty page: \(layout)")
        }
        suite.expect(compact.contentBudget == NotchLayout.compactContentHeight && spacious.contentBudget == NotchLayout.spaciousContentHeight
               && compact.expanded.height < compact.expanded.width && spacious.expanded.height < spacious.expanded.width,
               "both presets are strips wider than they are tall")
        let musicBase = compact.expandedSize(module: .music)
        let musicDetails = compact.expandedSize(module: .music, musicExtraHeight: 260)
        suite.expect(musicDetails.width == musicBase.width && musicDetails.height == musicBase.height + 260
               && compact.screen.contains(compact.frame(for: musicDetails)),
               "opening lyrics or the queue adds room while preserving width and screen bounds")
        suite.expect(compact.expanded.width >= 440 && spacious.expanded.width > compact.expanded.width,
               "the standard notch has room for side-by-side controls while spacious remains available")
        var compactPlayer = compact
        compactPlayer.pageTop = NotchModule.music.pageTop
        let idleMusic = compactPlayer.expandedSize(module: .music, musicHasContent: false)
        suite.expect(idleMusic.height < compactPlayer.expandedSize(module: .music).height
               && compactPlayer.contentSize(for: idleMusic).height
                   == NotchLayout.musicPlayerHeight(band: compactPlayer.musicBandHeight, playing: false),
               "empty music keeps its message and buttons without reserving a timeline")
        let fullControls = compact.expandedSize(module: .controls, shortcutCount: 10, sliderCount: 2, controlsHaveMusic: true)
        let fewerShortcuts = compact.expandedSize(module: .controls, shortcutCount: 3, sliderCount: 2, controlsHaveMusic: true)
        let onlyShortcuts = compact.expandedSize(module: .controls, shortcutCount: 3, sliderCount: 2, controlsHaveMusic: false)
        let onlyPlayer = compact.expandedSize(module: .controls, shortcutCount: 0, sliderCount: 2, controlsHaveMusic: true)
        let onlyLevels = compact.expandedSize(module: .controls, shortcutCount: 0, sliderCount: 2, controlsHaveMusic: false)
        suite.expect(fullControls == fewerShortcuts && fewerShortcuts.height > onlyShortcuts.height
               && fewerShortcuts.height > onlyPlayer.height && onlyPlayer.height > onlyLevels.height,
               "a compact island runs extra shortcuts sideways and drops the rows nobody enabled")
        suite.expect(compact.contentSize(for: onlyLevels).height == 0,
               "two levels alone sit in the top row and leave the page nothing to hold")
        suite.expect(compact.contentSize(for: fullControls).height
                   == NotchLayout.cardHeight + NotchLayout.rowSpacing + NotchLayout.shortcutHeight
               && compact.expanded == fullControls
               && spacious.expandedSize(module: .controls, shortcutCount: 10).height
                   > spacious.expandedSize(module: .controls, shortcutCount: 3).height,
               "the default home page is the player over one rail while a spacious island adds a second shortcut row first")
        suite.expect(compact.contentSize(for: compact.expandedSize(module: .controls, shortcutCount: 0, sliderCount: 0,
                                                                   controlsHaveMusic: false)).height == NotchLayout.emptyHeight,
               "hiding every control leaves the empty-state guidance its own row")
        for width in [360.0, 480.0, 600.0] {
            for height in [NotchSize.heightRange.lowerBound, 640.0] {
                let geometry = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210,
                                             layout: .custom, customWidth: width, customHeight: height)
                for shortcuts in 0...12 {
                    for (sliders, music) in (0...3).flatMap({ sliders in [(sliders, false), (sliders, true)] }) {
                        let size = geometry.expandedSize(module: .controls, shortcutCount: shortcuts, sliderCount: sliders,
                                                         controlsHaveMusic: music)
                        let content = geometry.contentSize(for: size)
                        // The levels sit in the top row; three beside a camera take a row below it.
                        let band = NotchBand(geometry: geometry, contentWidth: geometry.contentWidth)
                        let levelRow = NotchLayout.bandLevelCount(sliders, band: band) < sliders
                        let planned = NotchLayout.controls(hasCards: music, levelRow: levelRow, shortcutCount: shortcuts,
                                                           width: geometry.contentWidth, height: geometry.contentBudget)
                        let drawn = NotchLayout.controls(hasCards: music, levelRow: levelRow, shortcutCount: shortcuts,
                                                         width: content.width, height: content.height)
                        let empty = !music && sliders == 0 && shortcuts == 0
                        suite.expect(content.height == min(geometry.contentBudget, empty ? NotchLayout.emptyHeight : planned.height),
                               "the home page takes the rows it needs and never more than the custom budget")
                        suite.expect(planned == drawn, "the page rebuilds the same rows from the height it receives")
                        suite.expect(planned.shortcutRows == 0 || planned.height <= geometry.contentBudget || planned.cardRow == NotchLayout.minimumCardHeight,
                               "a tight budget shortens the card row before it drops the shortcut rail")
                        suite.expect(frames[0].contains(geometry.frame(for: size)),
                               "the full controls surface stays inside the display")
                    }
                }
            }
        }
        for frame in frames {
            for width in [360.0, 470.0, 600.0] {
                for height in [NotchSize.heightRange.lowerBound, 400.0, 520.0, 640.0] {
                    let custom = NotchGeometry(screen: frame, safeAreaTop: 32, cameraWidth: 210,
                                               layout: .custom, customWidth: width, customHeight: height)
                    let available = height - custom.headerTopInset - custom.headerChromeHeight
                    suite.expect(custom.contentBudget == available, "a custom island's budget is what its height leaves below the chrome")
                    for module in NotchModule.allCases {
                        let size = custom.expandedSize(module: module)
                        suite.expect(size.width == min(width, frame.width - 24 - NotchQuickAccessLayout.gutter * 2) && size.height <= height
                               && frame.contains(custom.frame(for: size)),
                               "custom dimensions fit every module and respect the display and height limit")
                        suite.expect(custom.contentSize(for: size).height <= available && custom.contentSize(for: size).height > 0,
                               "every page keeps inside the custom budget")
                    }
                    for count in [0, 1, 9, allModules.count] {
                        let picker = custom.sectionPickerSize(count: count)
                        suite.expect(picker.width == custom.expandedWidth && picker.height <= height
                               && frame.contains(custom.frame(for: picker)),
                               "gallery dimensions respect the display and the user's height limit at every item count")
                    }
                    suite.expect(custom.expandedSize(module: .clipboard).height == min(height, frame.height - 48),
                           "long lists use the chosen height without overflowing a shorter display")
                    var music = custom
                    music.pageTop = NotchModule.music.pageTop
                    suite.expect(music.contentSize(for: music.expandedSize(module: .music)).height
                           == NotchLayout.musicPlayerHeight(band: music.musicBandHeight),
                           "custom sizes keep the whole player, the same as the presets'")
                    suite.expect(music.contentSize(for: music.expandedSize(module: .music, musicHasContent: false)).height
                           == NotchLayout.musicPlayerHeight(band: music.musicBandHeight, playing: false),
                           "empty music keeps its message and buttons at every custom height")
                }
            }
        }
        for invalid in [Double.nan, .infinity, -.infinity, -200, 0, 1e9] {
            let custom = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210, layout: .custom,
                                       customWidth: invalid, customHeight: invalid)
            suite.expect(NotchSize.widthRange.contains(custom.customWidth) && NotchSize.heightRange.contains(custom.customHeight)
                   && frames[0].contains(custom.frame(for: custom.expandedSize(module: .tools))),
                   "invalid imported dimensions cannot create an unbounded or off-screen panel")
        }
        let wideCamera = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 390, layout: .custom,
                                       customWidth: 360)
        suite.expect(wideCamera.expanded.width > wideCamera.cameraWidth,
               "a requested narrow panel still clears a wider physical camera")
        for frame in frames {
            for notch in [false, true] {
                let geometry = NotchGeometry(screen: frame, safeAreaTop: notch ? 32 : 0,
                                             cameraWidth: notch ? 210 : 0)
                for size in [geometry.collapsed, geometry.notice, geometry.noticeSize(wingWidth: 190), geometry.expanded] {
                    let positioned = geometry.frame(for: size)
                    suite.expect(frame.contains(positioned), "notch fits displays in every coordinate quadrant")
                    suite.expect(positioned.midX == frame.midX, "notch stays centered while morphing")
                    suite.expect(positioned.maxY == frame.maxY,
                           "top edge does not jump across presentation states")
                }
                suite.expect(geometry.musicWingWidth * 2 + geometry.musicCameraGap == geometry.musicStrip.width,
                       "horizontal metadata uses equal wings around the camera")
                suite.expect(geometry.frame(for: geometry.musicStrip).maxY == frame.maxY,
                       "the lateral music strip remains attached to the same top edge")
                var music = geometry
                music.pageTop = NotchModule.music.pageTop
                suite.expect(music.contentSize(for: music.expandedSize(module: .music)).height
                       == NotchLayout.musicPlayerHeight(band: music.musicBandHeight),
                       "compact music is the player wrapped around the camera, no taller")
                let quiet = geometry.restingSize(showsContent: false)
                suite.expect(quiet.width == geometry.cameraWidth && quiet.height <= geometry.menuBarHeight,
                       "empty idle does not reserve wings or a footer for unsolicited widgets")
                suite.expect(geometry.contentSize(for: geometry.expanded).height
                       == geometry.expanded.height - geometry.headerTopInset - geometry.headerRowHeight
                           - NotchLayout.spacing - NotchLayout.bottomInset,
                       "content reserves one top navigation row, its spacing and the bottom inset")
                suite.expect(geometry.safeContentTop > geometry.cameraHeight, "controls always clear the physical camera")
                suite.expect(geometry.appPanelSize.width > 0 && geometry.appPanelSize.height >= 176
                       && geometry.appPanelSize.height == geometry.pageBudget
                       && geometry.appPanelSize.height < geometry.expandedSize(module: .tools, panel: true).height,
                       "embedded panel reserves room for its navigation, content and footer")
            }
        }
        for frame in frames {
            for layout in NotchSize.allCases {
                let geometry = NotchGeometry(screen: frame, safeAreaTop: 32, cameraWidth: 210, layout: layout)
                for module in NotchModule.allCases {
                    let target = geometry.expandedSize(module: module)
                    let envelope = NotchMotion.envelope(from: geometry.notice, to: target)
                    let position = geometry.frame(for: envelope)
                    suite.expect(position.maxY == frame.maxY && position.midX == frame.midX && frame.contains(position),
                           "the animation's backing window stays inside the display and attached to its top center")
                    suite.expect(envelope.width >= geometry.notice.width && envelope.height >= geometry.notice.height
                           && envelope.width >= target.width && envelope.height >= target.height,
                           "the backing window can reveal either endpoint without resizing each frame")
                    suite.expect(NotchMotion.envelope(from: envelope, to: geometry.collapsed) == envelope,
                           "an interrupted closing retains its backing area until the silhouette settles")
                }
                suite.expect(geometry.peek.height <= geometry.cameraHeight + NotchLayout.headerHeight + 32
                       && geometry.peek.height < geometry.expanded.height,
                       "hover reveals a small target instead of the entire panel")
            }
        }
        let menuScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let freeRoom = NotchMenuBarLayout.sideRoom(screen: menuScreen, cameraWidth: 180, barHeight: 32,
            occupied: [CGRect(x: 0, y: 924, width: 610, height: 32), CGRect(x: 950, y: 924, width: 520, height: 32)])
        suite.expect(freeRoom == 27, "compact wings stop before the app menu, including its spacing")
        suite.expect(NotchMenuBarLayout.sideRoom(screen: menuScreen, cameraWidth: 180, barHeight: 32,
            occupied: [CGRect(x: 630, y: 924, width: 60, height: 32)]) == nil,
               "occupied camera space cannot be treated as a free menu gap")
        let secondaryMenu = CGRect(x: 1480, y: 924, width: 420, height: 32)
        let primaryStatus = CGRect(x: 950, y: 924, width: 520, height: 32)
        suite.expect(NotchMenuBarLayout.measuredSideRoom(screen: menuScreen, cameraWidth: 180, barHeight: 32,
            menuItems: [secondaryMenu], statusItems: [primaryStatus]) == nil,
               "menus measured only on another display do not prove room on the selected display")
        suite.expect(NotchMenuBarLayout.measuredSideRoom(screen: menuScreen, cameraWidth: 180, barHeight: 32,
            menuItems: [CGRect(x: 0, y: 924, width: 610, height: 32), secondaryMenu],
            statusItems: [primaryStatus]) == 27,
               "menus on another display do not affect a measured gap on the selected display")
        suite.expect(NotchMenuBarLayout.measuredSideRoom(screen: menuScreen, cameraWidth: 180, barHeight: 32,
            menuItems: [], statusItems: [primaryStatus]) == nil,
               "missing menu geometry is not mistaken for an empty menu bar")
        suite.expect(NotchMenuBarLayout.measuredSideRoom(screen: menuScreen, cameraWidth: 180, barHeight: 32,
            menuItems: [CGRect(x: 690, y: 924, width: 80, height: 32)], statusItems: []) == nil,
               "a menu occupying the island's center still hides it")
        let constrained = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                        menuBarHeight: 24, compactSideRoom: freeRoom)
        suite.expect(constrained.collapsed.height == 32 && constrained.musicStrip.height == 32,
               "quiet idle and the lateral strip keep the menu bar's height")
        suite.expect(constrained.restingWingWidth == 0,
               "an indicator is omitted when there is not enough room to render it intact")
        let roomy = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                 menuBarHeight: 24, compactSideRoom: 100)
        let notificationSize = roomy.noticeSize(wingWidth: 190)
        suite.expect(notificationSize.height == roomy.menuBarHeight && roomy.notice.height == notificationSize.height
               && notificationSize.width > roomy.notice.width,
               "notifications use wider wings than level feedback without growing below the menu bar")
        for frame in frames {
            for notched in [false, true] {
                for barHeight: CGFloat in [16, 24, 32, 40, 64] {
                    let geometry = NotchGeometry(screen: frame, safeAreaTop: notched ? 32 : 0,
                        cameraWidth: notched ? 210 : 0, menuBarHeight: barHeight)
                    for wing in [CGFloat(112), 190, 240] {
                        let size = geometry.noticeSize(wingWidth: wing)
                        let wings = geometry.noticeWingWidth(preferred: wing)
                        suite.expect(size.height == geometry.stripHeight && size.height == geometry.cameraHeight
                               && geometry.frame(for: size).maxY == frame.maxY,
                               "feedback stays as tall as the camera cutout on physical and simulated notches")
                        suite.expect(wings > 0 && wings * 2 + geometry.noticeCameraGap == size.width,
                               "notice wings exactly fill their horizontal surface without entering the camera gap")
                        suite.expect(geometry.noticeCameraGap == geometry.cameraWidth,
                               "a simulated camera retains the same central gap as a physical camera")
                    }
                }
            }
        }
        let idle = roomy.restingSize(showsContent: false)
        suite.expect(NotchMotion.duration(from: idle, to: roomy.notice)
               == NotchMotion.duration(from: idle, to: roomy.expanded),
               "horizontal reveals use the opening curve even when their height stays unchanged")
        suite.expect(NotchMotion.duration(from: roomy.notice, to: idle)
               < NotchMotion.duration(from: idle, to: roomy.notice),
               "horizontal dismissal remains quicker than opening")
        // A level passing 99% or 9% keeps its notice and only fits the new width.
        for (from, to) in [(CGSize(width: 315, height: 33), CGSize(width: 329, height: 33)),
                           (CGSize(width: 315, height: 33), CGSize(width: 299, height: 33))] {
            let steady = NotchMotion.frames(from: from, to: to, steady: true)
            let widths = steady.sizes.map(\.width)
            let moving = zip(widths, widths.dropFirst()).allSatisfy { to.width > from.width ? $1 >= $0 : $1 <= $0 }
            suite.expect(moving && widths.allSatisfy { min(from.width, to.width) <= $0 && $0 <= max(from.width, to.width) }
                         && steady.sizes.last == to,
                         "a notice fitting a new reading eases to its width without swinging past it")
            let usual = NotchMotion.size(at: 0.1, from: from, to: to)
            let eased = NotchMotion.size(at: 0.1, from: from, to: to, steady: true)
            suite.expect(abs(eased.width - from.width) < abs(usual.width - from.width)
                         && steady.duration > NotchMotion.frames(from: from, to: to).duration,
                         "a notice fitting a new reading moves more gently than the island's springs")
        }
        // Equal total widths still move when the longer notice wing changes sides.
        let sameSize = CGSize(width: 380, height: 32)
        for start: CGFloat in [-120, 120] {
            let motion = NotchMotion.frames(from: sameSize, to: sameSize, offset: start)
            let offsets = motion.keyTimes.map {
                NotchMotion.offset(at: $0 * motion.duration, from: sameSize, to: sameSize, start: start)
            }
            suite.expect(motion.sizes.allSatisfy { $0 == sameSize }
                         && offsets.first == start && abs(offsets.last ?? .infinity) <= NotchMotion.settledDistance
                         && zip(offsets, offsets.dropFirst()).allSatisfy { abs($1) <= abs($0) }
                         && abs(NotchMotion.offset(at: 0.09, from: sameSize, to: sameSize, start: start)) < abs(start)
                         && motion.duration > 0.3,
                         "an equal-width notice moves its centre smoothly in either direction while its size stays put")
        }
        suite.expect(NotchMotion.offset(at: 0, from: sameSize, to: sameSize, start: 0) == 0,
                     "an unchanged notice with no shift stays in place")
        for (from, to) in [(CGSize(width: 315, height: 32), CGSize(width: 329, height: 32)),
                           (CGSize(width: 329, height: 32), CGSize(width: 315, height: 32))] {
            for steady in [false, true] {
                let time: TimeInterval = 0.09
                let size = NotchMotion.size(at: time, from: from, to: to, steady: steady)
                let expected = 60 * (1 - (size.width - from.width) / (to.width - from.width))
                suite.expect(abs(NotchMotion.offset(at: time, from: from, to: to, start: 60, steady: steady) - expected) < 0.001,
                             "a notice changing width still moves its centre with that same width spring")
            }
        }
        for (from, to) in [(roomy.collapsed, roomy.expanded), (idle, roomy.notice), (roomy.expanded, roomy.collapsed),
                           (roomy.notice, idle), (CGSize(width: roomy.collapsed.width, height: 0), roomy.peek),
                           (roomy.expanded, CGSize(width: roomy.collapsed.width, height: 0))] {
            let motion = NotchMotion.frames(from: from, to: to)
            let envelope = NotchMotion.envelope(from: from, to: to)
            let widest = motion.sizes.map(\.width).max() ?? 0
            let tallest = motion.sizes.map(\.height).max() ?? 0
            suite.expect(motion.sizes.first == from && motion.sizes.last == to
                   && motion.keyTimes.first == 0 && motion.keyTimes.last == 1 && motion.keyTimes.count == motion.sizes.count,
                   "the island's motion starts on screen and ends exactly at its target")
            suite.expect(widest <= envelope.width && tallest <= envelope.height,
                   "the reserved backing area holds every frame of the swing")
            suite.expect(envelope.width <= max(from.width, to.width) + NotchMotion.overshootLimit
                   && envelope.height <= max(from.height, to.height) + NotchMotion.overshootLimit,
                   "a long travel swings no farther than the room kept around the island")
            suite.expect(motion.duration > 0.1 && motion.duration < 0.6,
                   "the island settles within the time its surroundings wait for it: \(motion.duration)")
            suite.expect(motion.sizes.allSatisfy { $0.height >= 0 && $0.width >= 0 }, "no frame turns inside out")
            if to.width < from.width {
                suite.expect(motion.sizes.allSatisfy { $0.width >= to.width - 0.001 },
                       "a narrowing island never passes its resting width beside the camera")
            }
            if to.height < from.height {
                suite.expect(motion.sizes.allSatisfy { $0.height >= to.height - 0.001 },
                       "a shortening island never passes its resting height")
            }
            if to.width > from.width + 40 {
                suite.expect(widest > to.width, "a widening island stretches past its size before settling")
            }
            if to.height > from.height + 40 {
                suite.expect(tallest > to.height, "a lengthening island stretches past its size before settling")
            }
        }
        let long = NotchMotion.envelope(from: CGSize(width: 200, height: 32), to: CGSize(width: 1_400, height: 900))
        suite.expect(long.width <= 1_400 + NotchMotion.overshootLimit && long.height <= 900 + NotchMotion.overshootLimit
               && long.width > 1_400 && long.height > 900,
               "a long travel keeps its stretch within the room kept around the island")
        let drop = NotchMotion.frames(from: roomy.collapsed, to: roomy.expanded)
        let early = drop.sizes[drop.sizes.count / 8]
        suite.expect((early.height - roomy.collapsed.height) / (roomy.expanded.height - roomy.collapsed.height)
               > (early.width - roomy.collapsed.width) / (roomy.expanded.width - roomy.collapsed.width),
               "an opening island drops a little ahead of widening")
        let arrival = NotchMotion.arrivalTime(from: roomy.collapsed, to: roomy.expanded)
        let arrived = NotchMotion.size(at: arrival, from: roomy.collapsed, to: roomy.expanded)
        suite.expect(arrival > 0 && arrival < drop.duration
               && roomy.expanded.width - arrived.width <= (roomy.expanded.width - roomy.collapsed.width) * 0.01
               && roomy.expanded.height - arrived.height <= (roomy.expanded.height - roomy.collapsed.height) * 0.01,
               "floating controls emerge once the island reaches its size, before its swing settles")
        let horizontal = NotchMotion.frames(from: idle, to: roomy.notice)
        suite.expect(horizontal.sizes.allSatisfy { $0.height == idle.height },
               "horizontal feedback never swings below the menu bar")
        suite.expect(NotchMotion.envelope(from: roomy.expanded, to: roomy.expanded) == roomy.expanded,
               "an unchanged size reserves nothing more")
        for reserved in [CGSize(width: 571, height: 336), CGSize(width: 571.5, height: 40), CGSize(width: 300, height: 32)] {
            for size in [CGSize(width: 278, height: 32), CGSize(width: 277.5, height: 38), CGSize(width: 300, height: 32)] {
                let centred = NotchMotion.reservation(reserved, centring: size)
                let margin = (centred.width - size.width) / 2
                suite.expect(centred.width >= reserved.width && centred.height >= max(reserved.height, size.height)
                       && margin >= 0 && margin == margin.rounded(),
                       "a reserved window keeps whole, equal margins so the settled island does not shift a pixel")
            }
        }
        func near(_ value: CGFloat, _ expected: CGFloat) -> Bool { abs(value - expected) < 0.000_1 }
        let closing = NotchGlassFade.plan(from: 200, to: 32, endsInGlass: false, current: 1)
        suite.expect(near(closing.openness(atHeight: 200), 0) && near(closing.openness(atHeight: 80), 0)
                && near(closing.openness(atHeight: 32), 0),
               "settled glass closing into a black strip shuts at once, since its page has already left")
        let opening = NotchGlassFade.plan(from: 32, to: 200, endsInGlass: true, current: 0)
        suite.expect(near(opening.openness(atHeight: 32), 0) && near(opening.openness(atHeight: 152), 0)
                && near(opening.openness(atHeight: 176), 0.5) && near(opening.openness(atHeight: 200), 1),
               "glass leaving a black strip stays shut until the last stretch, where its page fades in")
        let short = NotchGlassFade.plan(from: 32, to: 56, endsInGlass: true, current: 0)
        suite.expect(near(short.openness(atHeight: 32), 0) && near(short.openness(atHeight: 56), 1),
               "glass growing less than the stretch opens over its whole travel")
        let reopened = NotchGlassFade.plan(from: 56, to: 200, endsInGlass: true, current: 0.5)
        suite.expect(near(reopened.openness(atHeight: 56), 0.5) && near(reopened.openness(atHeight: 200), 1),
               "a close reversed halfway reopens from the openness on screen and ends fully open")
        let partlyOpen = opening.openness(atHeight: 180)
        let retargeted = NotchGlassFade.plan(from: 180, to: 220, endsInGlass: true, current: partlyOpen)
        suite.expect(near(retargeted.openness(atHeight: 180), partlyOpen)
               && near(retargeted.openness(atHeight: 220), 1),
               "a changed target keeps the glass already on screen and releases its black before settling")
        let reclosed = NotchGlassFade.plan(from: 180, to: 32, endsInGlass: false, current: 0.5)
        suite.expect(near(reclosed.openness(atHeight: 180), 0) && near(reclosed.openness(atHeight: 32), 0),
               "an opening reversed late shuts as its page leaves and ends black")
        suite.expect(NotchGlassFade.plan(from: 100, to: 300, endsInGlass: true, current: 1) == .open
                && NotchGlassFade.plan(from: 300, to: 100, endsInGlass: true, current: 1) == .open
                && NotchGlassFade.plan(from: .nan, to: 100, endsInGlass: false, current: 1) == .open,
               "glass resizing into glass, or an unreadable height, stays fully open")
        let compactMusic = roomy.compactMusicGeometry
        suite.expect(compactMusic.compactActivityWingWidth == 34
               && compactMusic.compactActivityCameraGap == roomy.cameraWidth
               && compactMusic.compactActivitySize.width == roomy.cameraWidth + 68,
               "compact music wings beside a physical camera hold only the cover and the bars")
        for safeArea: CGFloat in [32, 33, 37.5, 38] {
            let music = NotchGeometry(screen: menuScreen, safeAreaTop: safeArea, cameraWidth: 185,
                                      menuBarHeight: 24, compactSideRoom: 100).compactMusicGeometry
            let height = music.compactActivitySize.height
            let shoulder = NotchLayout.shoulder(height: height)
            let corner = NotchLayout.surfaceRadius(height: height)
            let side = music.compactMusicArtworkSide
            let gap = (height - side) / 2
            let radius = music.compactMusicArtworkRadius
            let inset = music.compactMusicArtworkInset
            suite.expect(abs(inset - shoulder - gap) < 0.001 && abs(inset + radius - shoulder - corner) < 0.001
                   && abs(height - gap - radius - (height - corner)) < 0.001,
                   "the cover keeps one gap from the strip's end, top and bottom, its corners concentric with the strip's")
            let bars = music.compactMusicBarsInset + NotchLayout.compactMusicBarsWidth
            suite.expect(music.compactActivityWingWidth == max(inset + side, bars).rounded(.up)
                   && music.compactActivityWingWidth < 44,
                   "each music wing ends where the cover or the bars end, snug against the camera")
        }
        for available: CGFloat in [0, 27, 33, 34, 43, 44, 45, 55, 56, 100, .nan, .infinity] {
            var tight = roomy
            tight.compactSideRoom = available
            let music = tight.compactMusicGeometry
            suite.expect(!music.compactActivityUsesFooter && music.compactActivitySize.height == roomy.menuBarHeight
                   && music.compactActivityTopPadding == 0,
                   "compact music never grows or moves below the menu bar when space changes")
            if available.isFinite && available >= compactMusic.compactActivityWingWidth {
                suite.expect(music.compactActivityWingWidth == compactMusic.compactActivityWingWidth
                       && music.compactMusicArtworkSide == 22
                       && music.compactMusicArtworkInset + music.compactMusicArtworkSide <= music.compactActivityWingWidth
                       && music.compactActivityCameraGap == roomy.cameraWidth,
                       "fitted music wings keep a full cover and its outer margin beside the camera")
            } else {
                suite.expect(music.compactActivityWingWidth == 0,
                       "unavailable menu space cannot push music into the physical camera or adjacent menus")
            }
        }
        var moreRoom = roomy
        moreRoom.compactSideRoom = 200
        suite.expect(moreRoom.compactMusicGeometry == compactMusic,
               "menu measurements beyond the music width cannot resize the compact presentation")
        namedMusicStripChecks(suite, compactMusic: compactMusic, screen: menuScreen)
        suite.expect(constrained.compactMusicGeometry.compactActivitySize.height == constrained.menuBarHeight,
               "crowded music retains the same thin silhouette")
        suite.expect(roomy.musicStrip.width <= 380 && roomy.restingWingWidth == 44,
               "music and idle indicators both respect the same measured menu gap")
        let simulated = NotchGeometry(screen: menuScreen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 22)
        suite.expect(simulated.frame(for: simulated.collapsed).maxY == menuScreen.maxY
               && simulated.cameraHeight == 22 && simulated.cameraWidth == 180 * 22.0 / 32,
               "a simulated cutout has notebook proportions and attaches directly to the screen edge")
        let crowdedRooms: [CGFloat?] = [nil, -1, 0, 27, 43, CGFloat.nan, CGFloat.infinity]
        for available in crowdedRooms {
            let crowded = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                        menuBarHeight: 32, compactSideRoom: available)
            let size = crowded.compactActivitySize
            let window = crowded.frame(for: size)
            let visibleContentTop = window.maxY - crowded.compactActivityTopPadding
            suite.expect(crowded.compactActivityUsesFooter && crowded.compactActivityWingWidth >= 42,
                   "an active timer, paused timer or download has readable content with missing or crowded menu geometry")
            suite.expect(size.width == crowded.cameraWidth && visibleContentTop <= menuScreen.maxY - crowded.cameraHeight,
                   "fallback content stays below the physical camera and its backing window never expands over adjacent menus")
            suite.expect(crowded.compactActivityWingWidth * 2 + crowded.compactActivityCameraGap
                   + crowded.compactActivityHorizontalPadding * 2 == size.width,
                   "both compact actions fit entirely in the fallback strip")
            suite.expect(menuScreen.contains(window) && window.maxY == menuScreen.maxY
                   && crowded.restingSize(showsContent: false).height == 32,
                   "a notched fallback keeps the physical top anchor and does not change quiet idle")
        }
        for available in [CGFloat(44), 80, 100, 180] {
            let lateral = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                        menuBarHeight: 32, compactSideRoom: available)
            suite.expect(!lateral.compactActivityUsesFooter && lateral.compactActivitySize == lateral.musicStrip
                   && lateral.compactActivityCameraGap == lateral.cameraWidth
                   && lateral.compactActivityTopPadding == 0,
                   "confirmed lateral room retains the existing single-row presentation around the camera")
        }
        for frame in frames {
            let external = NotchGeometry(screen: frame, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 22,
                                          compactSideRoom: nil)
            let position = external.frame(for: external.compactActivitySize)
            suite.expect(position.maxY == frame.maxY && frame.contains(position)
                   && external.compactActivityWingWidth == 0 && external.compactActivityTopPadding == 0,
                   "a simulated notch stays attached to its own screen edge in every coordinate quadrant")
        }
        let mediaGeometry = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180)
        for layout in NotchSize.allCases {
            for customHeight in [400.0, 640.0] {
                let geometry = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                             layout: layout, customHeight: customHeight)
                let history = geometry.expandedSize(module: .captures)
                let preview = geometry.expandedSize(module: .captures, capturePreviewHeight: 210)
                let shared = geometry.expandedSize(module: .captures, capturePreviewHeight: 268)
                suite.expect(geometry.contentSize(for: preview).height == 214
                       && geometry.contentSize(for: history).height == geometry.contentBudget,
                       "a single capture reserves its measured preview and scroll inset while the history fills the strip in every layout")
                suite.expect(shared.height - preview.height == 58,
                       "sharing adds only the link row and removing it restores the compact preview height")
                suite.expect(geometry.expandedSize(module: .timer, capturePreviewHeight: 210)
                       == geometry.expandedSize(module: .timer),
                       "a retained capture preview does not change another section's height")
                suite.expect(menuScreen.contains(geometry.frame(for: shared)) && shared.height <= customHeight,
                       "the capture preview preserves the screen edge and respects the custom height limit")
            }
        }
        for layout in NotchSize.allCases {
            let fitting = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                        layout: layout, customHeight: 640)
            for measured: CGFloat in [120, 280, 370, 480] {
                let fileMedia = fitting.expandedSize(module: .files, fileMediaHeight: measured)
                suite.expect(fitting.contentSize(for: fileMedia).height == measured,
                       "embedded media fits its measured content without adding a fixed blank area")
            }
        }
        suite.expect(mediaGeometry.expandedSize(module: .music, fileMediaHeight: 600)
               == mediaGeometry.expandedSize(module: .music),
               "an open file-media session does not enlarge unrelated notch modules")
        for height in [400.0, 520.0, 640.0] {
            let custom = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                        layout: .custom, customHeight: height)
            let target = custom.expandedSize(module: .files, fileMediaHeight: 600)
            suite.expect(target.height <= height && menuScreen.contains(custom.frame(for: target)),
                   "the embedded media workspace respects the user's custom height")
        }
        let shortScreen = CGRect(x: 0, y: 0, width: 1024, height: 600)
        let shortMedia = NotchGeometry(screen: shortScreen, safeAreaTop: 0, cameraWidth: 0)
        let shortTarget = shortMedia.expandedSize(module: .files, fileMediaHeight: 600)
        suite.expect(shortTarget.height <= shortScreen.height - 48 && shortScreen.contains(shortMedia.frame(for: shortTarget)),
               "the larger media workspace preserves the screen margin on shorter displays")
        suite.expect(NotchSupport.screenIndex(preference: .automatic, builtIn: [false, true],
                                       notched: [false, true], main: 0) == 1,
               "automatic uses the notched built-in screen even with external main display")
        suite.expect(NotchSupport.screenIndex(preference: .builtIn, builtIn: [false],
                                       notched: [false], main: 0) == nil,
               "closed-lid mode hides the island when the selected built-in display is unavailable")
        suite.expect(NotchSupport.screenIndex(preference: .automatic, builtIn: [false, false],
                                       notched: [false, false], main: 1) == 1
                     && NotchSupport.screenIndex(preference: .builtIn, builtIn: [false, false],
                                       notched: [false, false], main: 1) == nil,
               "external-only setups use the primary display automatically but hide a built-in-only island")
        suite.expect(NotchSupport.screenIndex(preference: .builtIn, builtIn: [false, true],
                                       notched: [false, true], main: 0) == 1,
               "the built-in choice returns to the laptop display when the lid opens")
        suite.expect(NotchSupport.screenIndex(preference: .builtIn, builtIn: [false, false],
                                       notched: [false, false], main: 1, hasLid: false) == 1
                     && NotchSupport.screenIndex(preference: .builtIn, builtIn: [true, false],
                                       notched: [false, false], main: 1, hasLid: false) == 0,
               "a Mac without a lid keeps the built-in choice on the main display, or on its own built-in panel")
        suite.expect(NotchSupport.screenIndex(preference: .main, builtIn: [], notched: [], main: 0) == nil,
               "no connected displays means no panel")
        suite.expect(NotchSupport.screenIndex(preference: .main, builtIn: [true, false, false],
                                       notched: [true, false, false], main: 2) == 2,
               "the main display choice follows the display with the menu bar, even beside a notched built-in screen")
        suite.expect(NotchSupport.screenIndex(preference: .pointer, builtIn: [true, false],
                                       notched: [true, false], main: 0, pointer: 1) == 1
                     && NotchSupport.screenIndex(preference: .pointer, builtIn: [true, false],
                                       notched: [true, false], main: 0, pointer: 0) == 0,
               "the pointer choice uses the display it follows, notched or not")
        suite.expect(NotchSupport.screenIndex(preference: .pointer, builtIn: [false, false],
                                       notched: [false, false], main: 1) == 1
                     && NotchSupport.screenIndex(preference: .pointer, builtIn: [false, false],
                                       notched: [false, false], main: 1, pointer: 2) == 1,
               "without a display to follow, the pointer choice keeps the main display")
        suite.expect(NotchSupport.screenIndex(preference: .pointer, builtIn: [false],
                                       notched: [false], main: 0, pointer: 0) == 0,
               "the pointer choice still shows the island in closed-lid mode")
        let layouts: [([Bool], [Bool], Int)] = [([true, false], [true, false], 0), ([false, false], [false, false], 1),
                                                ([false], [false], 0), ([true, false, false], [true, false, false], 2), ([], [], 0)]
        for (builtIn, notched, main) in layouts {
            for pointer in [nil, 0, 1, 2, 5] as [Int?] {
                suite.expect(NotchSupport.screenIndex(preference: .all, builtIn: builtIn, notched: notched, main: main,
                                                      pointer: pointer)
                             == NotchSupport.screenIndex(preference: .pointer, builtIn: builtIn, notched: notched, main: main,
                                                         pointer: pointer),
                             "with every display chosen, the island that responds follows the pointer")
            }
        }
        // The shape for displays without a notch shows only where the island can rest.
        suite.expect(!NotchSupport.reachesDisplayWithoutNotch(preference: .automatic, builtIn: [true, false],
                                                              notched: [true, false], main: 1),
               "automatic keeps a notched laptop's island off its monitor, even the main one")
        suite.expect(NotchSupport.reachesDisplayWithoutNotch(preference: .automatic, builtIn: [false],
                                                             notched: [false], main: 0),
               "automatic reaches the monitor once the lid closes")
        suite.expect(!NotchSupport.reachesDisplayWithoutNotch(preference: .builtIn, builtIn: [true, false],
                                                              notched: [true, false], main: 1),
               "the built-in choice keeps the island on its camera")
        suite.expect(!NotchSupport.reachesDisplayWithoutNotch(preference: .builtIn, builtIn: [false],
                                                              notched: [false], main: 0),
               "the built-in choice reaches no monitor while the lid is closed")
        suite.expect(NotchSupport.reachesDisplayWithoutNotch(preference: .builtIn, builtIn: [true, false],
                                                             notched: [false, false], main: 1),
               "a built-in screen without a notch floats the island itself")
        suite.expect(NotchSupport.reachesDisplayWithoutNotch(preference: .builtIn, builtIn: [false, false],
                                                             notched: [false, false], main: 1, hasLid: false),
               "a Mac without a lid keeps the built-in choice on its main display")
        suite.expect(NotchSupport.reachesDisplayWithoutNotch(preference: .main, builtIn: [true, false],
                                                             notched: [true, false], main: 1)
                     && !NotchSupport.reachesDisplayWithoutNotch(preference: .main, builtIn: [true, false],
                                                                 notched: [true, false], main: 0),
               "the main display choice reaches a monitor only when it has the menu bar")
        for preference in [NotchDisplay.pointer, .all] {
            suite.expect(NotchSupport.reachesDisplayWithoutNotch(preference: preference, builtIn: [true, false],
                                                                 notched: [true, false], main: 0),
                   "the pointer can take the island to a monitor: \(preference)")
            suite.expect(!NotchSupport.reachesDisplayWithoutNotch(preference: preference, builtIn: [true],
                                                                  notched: [true], main: 0),
                   "no display without a notch is reached when none is connected: \(preference)")
        }
        // Settings asks that rule with the displays connected now, and its
        // button switches to every display (issue #1711).
        let notchSettings = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Settings/NotchSettings.swift",
                                         encoding: .utf8)) ?? ""
        let notchServiceSource = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Notch/NotchService.swift",
                                              encoding: .utf8)) ?? ""
        suite.expect(notchSettings.contains("if enabled, !NotchService.reachesDisplayWithoutNotch(NotchDisplay(rawValue: display) ?? .automatic) {")
                     && notchSettings.contains("Button(text.showOnAllDisplays) { display = NotchDisplay.all.rawValue }")
                     && notchServiceSource.contains("NotchSupport.reachesDisplayWithoutNotch(preference: preference, builtIn: layout.builtIn,")
                     && notchServiceSource.contains("notched: layout.notched, main: layout.main, hasLid: hasLid)"),
               "the Displays without a notch card offers All displays only while the chosen display keeps the island off them")
        suite.expect(NotchSupport.shouldReplace(.volume, with: .brightness), "continuous controls can replace each other")
        suite.expect(!NotchSupport.shouldReplace(.volume, with: .clipboard), "copy does not interrupt a volume adjustment")
        suite.expect(NotchSupport.shouldReplace(.battery, with: .capture), "a capture takes precedence over passive battery status")
        suite.expect(NotchSupport.volumeLevel(current: 0.99, direction: 1, fine: false) == 1
               && NotchSupport.volumeLevel(current: 0, direction: -1, fine: false) == 0,
               "hardware volume steps clamp to audible limits")
        suite.expect(NotchSupport.volumeLevel(current: 0.5, direction: 1, fine: true) == 0.515625,
               "fine volume preserves the system quarter-step")
        suite.expect((0..<9).map { NotchClipboardPastePress.index(
                    keyCode: [18, 19, 20, 21, 23, 22, 26, 28, 25][$0], commandOnly: true) } == (0..<9).map { $0 }
               && (0..<9).map { NotchClipboardPastePress.index(
                    keyCode: [83, 84, 85, 86, 87, 88, 89, 91, 92][$0], commandOnly: true) } == (0..<9).map { $0 }
               && NotchClipboardPastePress.index(keyCode: 18, commandOnly: false) == nil
               && NotchClipboardPastePress.index(keyCode: 29, commandOnly: true) == nil,
               "⌘1 to ⌘9 on the clipboard page name the first nine entries, and nothing else does")

        var session = NotchSessionState()
        session.locked = true
        session.sleeping = true
        session.sleeping = false
        suite.expect(!session.canPresent, "wake cannot reveal content over a locked screen")
        session.locked = false
        session.displaysSleeping = true
        suite.expect(!session.canPresent, "unlock alone cannot revive sleeping displays")
        session.displaysSleeping = false
        session.onConsole = false
        suite.expect(!session.canPresent, "another login session owns the display")
        session.onConsole = true
        suite.expect(session.canPresent, "presentation resumes after every privacy condition clears")

        suite.expect(NotchArtworkTint.from(red: 0.3, green: 0.3, blue: 0.3) == nil
               && NotchArtworkTint.from(red: 0.5, green: 0.5, blue: 0.55) == nil
               && NotchArtworkTint.from(red: 0, green: 0, blue: 0) == nil,
               "grey and black covers leave the notch without a coloured halo")
        suite.expect(NotchArtworkTint.from(red: .nan, green: 0.5, blue: 0.2) == nil
               && NotchArtworkTint.from(red: 2, green: 0.5, blue: 0.2) == nil
               && NotchArtworkTint.from(red: -1, green: 0.5, blue: 0.2) == nil,
               "impossible pixels cannot produce a halo")
        if let warm = NotchArtworkTint.from(red: 0.8, green: 0.3, blue: 0.25),
           let dim = NotchArtworkTint.from(red: 0.16, green: 0.06, blue: 0.05) {
            suite.expect(abs(warm.red - 0.92) < 0.001 && warm.blue < 0.2 && warm.green < warm.red,
                   "the cover's own hue survives, stretched onto a readable brightness")
            suite.expect(abs(dim.red - warm.red) < 0.001 && abs(dim.green - warm.green) < 0.001
                   && abs(dim.blue - warm.blue) < 0.001,
                   "a dark cover glows as strongly as a bright one of the same hue")
        } else {
            suite.expect(false, "a colourful cover always yields a halo")
        }

        let now = Date(timeIntervalSince1970: 100)
        let reply = Data("{\"pid\":12,\"isPlaying\":false,\"kMRMediaRemoteNowPlayingInfoTitle\":\"A track\",\"kMRMediaRemoteNowPlayingInfoDuration\":180,\"kMRMediaRemoteNowPlayingInfoElapsedTime\":20}".utf8)
        let playback = NotchPlayback.decode(reply, now: now)
        suite.expect(playback?.track.title == "A track" && playback?.isPlaying == false,
               "paused playback retains the track and its resume control")
        suite.expect(playback?.position(at: now.addingTimeInterval(20)) == 20, "paused progress never advances")
        let playingReply = Data(String(decoding: reply, as: UTF8.self).replacingOccurrences(of: "false", with: "true").utf8)
        let playing = NotchPlayback.decode(playingReply, now: now)
        suite.expect(playing?.position(at: now.addingTimeInterval(10)) == 30, "visible music progress follows elapsed time")
        suite.expect(playing?.position(at: now.addingTimeInterval(500)) == 180, "music progress stops at track duration")
        suite.expect(NotchPlayback.decode(Data("{\"pid\":0,\"isPlaying\":false}".utf8)) == nil,
               "empty system playback never fabricates a song")
        let fasterReply = Data(String(decoding: playingReply, as: UTF8.self)
            .replacingOccurrences(of: "\"pid\":12", with: "\"pid\":12,\"kMRMediaRemoteNowPlayingInfoPlaybackRate\":2").utf8)
        suite.expect(NotchPlayback.decode(fasterReply, now: now)?.position(at: now.addingTimeInterval(10)) == 40,
               "spoken content follows its actual playback speed")
        let unchangedArtwork = Data("{\"pid\":12,\"isPlaying\":true,\"artworkUnchanged\":true}".utf8)
        let cachedArtwork = Data([1, 2, 3])
        suite.expect(NotchPlayback.decode(unchangedArtwork, previousArtwork: cachedArtwork)?.track.artworkData == cachedArtwork,
               "metadata-only updates retain the existing artwork without retransmitting it")
        suite.expect(NotchPlayback.decode(playingReply, previousArtwork: cachedArtwork)?.track.artworkData == nil,
               "a new track without artwork clears the old cover")

        var coverCache = NotchArtworkCache<String>()
        coverCache.update("cover A", for: playing, now: now)
        coverCache.update(nil, for: playback, now: now.addingTimeInterval(10))
        suite.expect(coverCache.artwork == "cover A" && coverCache.expiresAt == nil,
               "pausing with a metadata-only reply retains the decoded cover of the same song")
        let nextReply = Data(String(decoding: playingReply, as: UTF8.self)
            .replacingOccurrences(of: "A track", with: "Next track").utf8)
        let next = NotchPlayback.decode(nextReply, now: now)
        coverCache.update(nil, for: next, now: now)
        let deadline = coverCache.expiresAt
        coverCache.update(nil, for: next, now: now.addingTimeInterval(0.5))
        suite.expect(coverCache.artwork == "cover A" && coverCache.expiresAt == deadline,
               "track changes bridge delayed artwork without extending the grace period on every update")
        coverCache.update("cover B", for: next, now: now.addingTimeInterval(1))
        coverCache.expire(at: now.addingTimeInterval(2))
        suite.expect(coverCache.artwork == "cover B" && coverCache.expiresAt == nil,
               "the new cover replaces the old cover and cancels its expiry")
        coverCache.update(nil, for: playing, now: now.addingTimeInterval(3))
        coverCache.expire(at: now.addingTimeInterval(5))
        suite.expect(coverCache.artwork == nil, "a song without artwork cannot retain another song's cover indefinitely")
        coverCache.update("cover A", for: playing, now: now)
        let otherPlayer = NotchPlayback.decode(Data(String(decoding: playingReply, as: UTF8.self)
            .replacingOccurrences(of: "\"pid\":12", with: "\"pid\":13").utf8))
        coverCache.update(nil, for: otherPlayer, now: now)
        suite.expect(coverCache.artwork == nil, "switching players never inherits the previous player's cover")
        coverCache.update("cover A", for: playing, now: now)
        coverCache.update(nil, for: nil, now: now)
        suite.expect(coverCache.artwork == nil && coverCache.expiresAt == nil,
               "ending playback releases the cached cover and its deadline")

        let seekableReply = Data(String(decoding: playingReply, as: UTF8.self)
            .replacingOccurrences(of: "\"pid\":12", with: "\"pid\":12,\"canSeek\":true").utf8)
        let seekable = NotchPlayback.decode(seekableReply, now: now)
        suite.expect(seekable?.seekPosition(95.5) == 95.5
               && seekable?.seekPosition(-10) == 0 && seekable?.seekPosition(300) == 180,
               "scrubbing retains fractions and stays within the current track")
        let videoReply = Data(String(decoding: playingReply, as: UTF8.self)
            .replacingOccurrences(of: "\"pid\":12", with: "\"pid\":12,\"canSkipNext\":false,\"canSkipPrevious\":true").utf8)
        let video = NotchPlayback.decode(videoReply, now: now)
        suite.expect(video?.canSkipNext == false && video?.canSkipPrevious == true && playing?.canSkipNext == nil,
               "the player's own skip commands reach playback, and a missing list stays unknown")
        suite.expect(playing?.seekPosition(30) == nil && seekable?.seekPosition(.nan) == nil
               && seekable?.seekPosition(.infinity) == nil,
               "unsupported playback and non-finite positions cannot produce seek commands")
        for command in [NotchPlaybackCommand.toggle, .next, .previous, .seek(0), .seek(12.75), .seek(604_800)] {
            suite.expect(command.message.flatMap(NotchPlaybackCommand.init(message:)) == command,
                   "playback commands survive their bounded pipe protocol")
        }
        for invalid in ["", "stop", "seek", "seek -1", "seek nan", "seek inf", "seek 604801", "seek 10\\ntoggle", "seek 1 2"] {
            suite.expect(NotchPlaybackCommand(message: invalid) == nil, "malformed playback input is refused: \(invalid)")
        }
        suite.expect(NotchPlaybackCommand.seek(.nan).message == nil
               && NotchPlaybackCommand.seek(-1).message == nil,
               "invalid internal positions cannot be serialized into adapter input")
    }
    private static func calendarContracts(_ suite: TestSuite) {
        let entitlements = NSDictionary(contentsOfFile: "Resources/Vorssaint.entitlements") as? [String: Any]
        let info = NSDictionary(contentsOfFile: "Resources/Info.plist") as? [String: Any]
        suite.expect(entitlements?["com.apple.security.personal-information.calendars"] as? Bool == true
               && !(info?["NSCalendarsFullAccessUsageDescription"] as? String ?? "").isEmpty,
               "the signed hardened app declares both the calendar capability and its permission explanation")
        let languages = info?["CFBundleLocalizations"] as? [String] ?? []
        suite.expect(languages.count == AppLanguage.allCases.count, "calendar prompts cover every supported app language")
        for language in languages where language != "en" {
            let localized = NSDictionary(contentsOfFile: "Resources/\(language).lproj/InfoPlist.strings")
            let prompt = localized?["NSCalendarsFullAccessUsageDescription"] as? String ?? ""
            suite.expect(!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                   && prompt != info?["NSCalendarsFullAccessUsageDescription"] as? String,
                   "\(language) ships its own readable calendar permission explanation")
        }
        suite.expect(NotchCalendarSupport.requestFailed(status: .notDetermined, hasError: false)
               && NotchCalendarSupport.requestFailed(status: .writeOnly, hasError: false),
               "a calendar request that silently fails to resolve read access surfaces an error")
        suite.expect(!NotchCalendarSupport.requestFailed(status: .fullAccess, hasError: false)
               && !NotchCalendarSupport.requestFailed(status: .denied, hasError: false)
               && !NotchCalendarSupport.requestFailed(status: .restricted, hasError: false),
               "successful grants and explicit system refusals keep their own calendar presentation")
        suite.expect(NotchCalendarSupport.requestFailed(status: .notDetermined, hasError: true),
               "calendar authorization errors remain visible and retryable")
        suite.expect(NotchSupport.keepsPermissionSurface(requesting: true, resolvedAt: nil, now: 0),
               "the calendar remains open while its system permission dialog is in use")
        suite.expect(NotchSupport.keepsPermissionSurface(requesting: false, resolvedAt: 10, now: 10.5)
               && !NotchSupport.keepsPermissionSurface(requesting: false, resolvedAt: 10, now: 11)
               && !NotchSupport.keepsPermissionSurface(requesting: false, resolvedAt: 10, now: 9),
               "permission resolution protects only the short reactivation interval")
        let defaults = UserDefaults(suiteName: "com.vorssaint.tests.notch-calendar")!
        defaults.removePersistentDomain(forName: "com.vorssaint.tests.notch-calendar")
        defer { defaults.removePersistentDomain(forName: "com.vorssaint.tests.notch-calendar") }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        suite.expect(!NotchCalendarSupport.isEnabled(in: defaults), "calendar starts off")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchSupport.modules(in: defaults).contains(.calendar), "calendar is available in the default home")
        defaults.set(false, forKey: DefaultsKey.notchCalendarEnabled)
        suite.expect(!NotchCalendarSupport.isEnabled(in: defaults), "calendar can still be explicitly disabled")
        defaults.set(true, forKey: DefaultsKey.notchCalendarEnabled)
        suite.expect(NotchCalendarSupport.isEnabled(in: defaults), "calendar can be enabled independently")
        suite.expect(!NotchCalendarSupport.showsCountdown(in: defaults) && !NotchCalendarSupport.showsTimeLeft(in: defaults),
                     "calendar titles stay out of the closed island until explicitly enabled")
        suite.expect(NotchCalendarSupport.showsCountdown(chosen: true, in: defaults),
                     "an event chosen from its menu counts down while the countdown for every event is off")
        defaults.set(true, forKey: DefaultsKey.notchCalendarCountdown)
        suite.expect(NotchCalendarSupport.showsCountdown(in: defaults) && !NotchCalendarSupport.showsTimeLeft(in: defaults),
                     "the compact countdown follows its own opt-in")
        defaults.set(false, forKey: DefaultsKey.notchCalendarCountdown)
        defaults.set(true, forKey: DefaultsKey.notchCalendarTimeLeft)
        suite.expect(!NotchCalendarSupport.showsCountdown(in: defaults) && NotchCalendarSupport.showsTimeLeft(in: defaults),
                     "time left in the event under way follows an opt-in of its own")
        defaults.set(true, forKey: DefaultsKey.notchCalendarCountdown)
        defaults.set("calendar", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchCalendarSupport.isEnabled(in: defaults), "hiding the calendar releases its resources")
        suite.expect(!NotchCalendarSupport.showsCountdown(in: defaults) && !NotchCalendarSupport.showsTimeLeft(in: defaults)
                     && !NotchCalendarSupport.showsCountdown(chosen: true, in: defaults),
                     "a hidden calendar cannot leave event titles in the island, even a chosen event's")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(false, forKey: AppFeature.notchCalendar.availabilityKey)
        suite.expect(!NotchCalendarSupport.isEnabled(in: defaults), "removing the calendar from the hub stops its reader")
        defaults.set(true, forKey: AppFeature.notchCalendar.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchCalendarSupport.isEnabled(in: defaults), "the master switch also stops calendar reads")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchCalendarEnabled,
                                                                 DefaultsKey.notchCalendarCountdown,
                                                                 DefaultsKey.notchCalendarTimeLeft,
                                                                 DefaultsKey.notchCalendarWeekNumbers,
                                                                 AppFeature.notchCalendar.availabilityKey]),
               "calendar preferences travel in backup")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchCalendarExcluded),
                     "hidden calendars travel in backup")
        suite.expect(NotchCalendarSupport.excludedCalendars(in: defaults).isEmpty,
                     "every calendar starts shown")
        let calendars = ["work", "home", "birthdays"]
        suite.expect(NotchCalendarSupport.calendarsToRead(calendars, excluded: [], identifier: { $0 }) == nil
                     && NotchCalendarSupport.calendarsToRead(calendars, excluded: ["gone"], identifier: { $0 }) == nil,
                     "with nothing hidden, or only calendars that no longer exist, every calendar is read")
        NotchCalendarSupport.setCalendar("home", shown: false, in: defaults)
        suite.expect(NotchCalendarSupport.calendarsToRead(calendars + ["added later"],
                                                          excluded: NotchCalendarSupport.excludedCalendars(in: defaults),
                                                          identifier: { $0 }) == ["work", "birthdays", "added later"],
                     "a hidden calendar is left out while calendars added later stay shown")
        suite.expect(NotchCalendarSupport.calendarsToRead(calendars, excluded: Set(calendars), identifier: { $0 }) == [],
                     "hiding every calendar reads none rather than falling back to all")
        NotchCalendarSupport.setCalendar("home", shown: true, in: defaults)
        suite.expect(NotchCalendarSupport.excludedCalendars(in: defaults).isEmpty, "a calendar can be shown again")
        let choices = [NotchCalendarChoice(id: "b", title: "Work", sourceID: "2", source: "iCloud"),
                       NotchCalendarChoice(id: "c", title: "Birthdays", sourceID: "1", source: "Other"),
                       NotchCalendarChoice(id: "a", title: "Home", sourceID: "2", source: "iCloud")]
        suite.expect(NotchCalendarSupport.grouped(choices).map { $0.map(\.id) } == [["a", "b"], ["c"]],
                     "calendars are grouped by account, both in name order")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String, _ start: Double, _ end: Double, allDay: Bool = false) -> NotchCalendarEvent {
            NotchCalendarEvent(id: id, title: id, calendar: "Personal", start: now.addingTimeInterval(start),
                               end: now.addingTimeInterval(end), allDay: allDay, location: "")
        }
        let allDay = event("all-day", -3600, 7200, allDay: true)
        let current = event("recurring:today", -300, 300)
        let tomorrow = event("recurring:tomorrow", 86400, 90000)
        let later = event("later", 600, 900)
        let entries = [tomorrow, allDay, later, current, current, event("ended", -60, 0),
                       event("invalid", 60, 30), event("infinite", .infinity, .infinity)]
        let upcoming = NotchCalendarSupport.upcoming(entries, now: now)
        suite.expect(upcoming.map(\.id) == [allDay.id, current.id, later.id, tomorrow.id],
               "calendar deduplicates occurrences, preserves ongoing and all-day events and excludes invalid or ended entries")
        suite.expect(NotchCalendarSupport.next(entries, now: now) == current,
               "an all-day event does not conceal the current appointment")
        suite.expect(NotchCalendarSupport.next(entries, now: now.addingTimeInterval(300)) == later,
               "the next appointment advances exactly when the previous one ends")
        suite.expect(NotchCalendarSupport.next([allDay], now: now) == nil,
               "an all-day-only calendar has no timed appointment")
        suite.expect(NotchCalendarSupport.nextRefresh(entries, now: now) == now.addingTimeInterval(300),
               "the next refresh chooses the nearest future event boundary")
        let hour = NotchCalendarSupport.countdownLeadTime
        func countdownFor(_ events: [NotchCalendarEvent], at offset: Double = 0, starts: Bool = true,
                          ends: Bool = false) -> NotchCalendarCountdown? {
            NotchCalendarSupport.countdown(events, now: now.addingTimeInterval(offset), starts: starts, ends: ends)
        }
        func transition(_ events: [NotchCalendarEvent], starts: Bool = true, ends: Bool = false) -> Date? {
            NotchCalendarSupport.countdownTransition(events, now: now, starts: starts, ends: ends)
        }
        suite.expect(countdownFor(entries) == NotchCalendarCountdown(event: later, ongoing: false)
                     && countdownFor([allDay, current]) == nil,
                     "the countdown chooses the next timed start, ignoring all-day and ongoing events")
        suite.expect(countdownFor([event("edge", hour, hour + 60)])?.event.id == "edge"
                     && countdownFor([event("outside", hour + 1, hour + 61)]) == nil,
                     "the countdown appears only in the hour before a start")
        suite.expect(NotchCalendarSupport.tileEvent(entries, now: now) == later
                     && NotchCalendarSupport.tileEvent([allDay, current, tomorrow], now: now) == tomorrow
                     && NotchCalendarSupport.tileEvent([allDay, current], now: now) == nil,
                     "the Controls tile names the next timed start at any distance, past ongoing and all-day events")
        suite.expect(NotchCalendarSupport.tileEvent([later], now: later.start) == nil,
                     "an appointment leaves the tile once it starts")
        let sixDays = event("in six days", 6 * 86_400, 6 * 86_400 + 600)
        suite.expect(NotchCalendarSupport.tileEvent([sixDays], now: now) == sixDays
                     && NotchCalendarSupport.tileEvent([event("next week", 8 * 86_400, 8 * 86_400 + 600)], now: now) == nil,
                     "the tile stops at the week read, where its weekday cannot be mistaken for this week's")
        suite.expect(transition([event("future", hour + 600, hour + 900)]) == now.addingTimeInterval(600)
                     && transition([later]) == later.start,
                     "a refresh is scheduled when the hour window opens and when an event starts")
        // A meeting that ends in 30 minutes, 15 minutes before the next one starts.
        let meeting = event("meeting", -1800, 1800)
        let afterGap = event("after gap", 2700, 4500)
        suite.expect(countdownFor([meeting, afterGap]) == NotchCalendarCountdown(event: afterGap, ongoing: false)
                     && countdownFor([meeting, afterGap], ends: true) == NotchCalendarCountdown(event: meeting, ongoing: true)
                     && countdownFor([meeting, afterGap], starts: false, ends: true)?.target == meeting.end,
                     "with time left on, a gap before the next event keeps the meeting under way counting to its end")
        suite.expect(countdownFor([meeting, afterGap], at: 1800, ends: true)
                     == NotchCalendarCountdown(event: afterGap, ongoing: false)
                     && countdownFor([meeting, afterGap], at: 1800, starts: false, ends: true) == nil,
                     "once the meeting ends the next start takes over, unless only time left is on")
        let overlapping = event("overlapping", 600, 3000)
        suite.expect(countdownFor([meeting, overlapping], ends: true) == NotchCalendarCountdown(event: overlapping, ongoing: false)
                     && countdownFor([meeting, overlapping], at: 600, ends: true)
                        == NotchCalendarCountdown(event: meeting, ongoing: true),
                     "whichever moment comes first leads, including a start before the current event ends")
        suite.expect(countdownFor([meeting, event("back to back", 1800, 5400)], ends: true)
                     == NotchCalendarCountdown(event: meeting, ongoing: true),
                     "a start at the moment of an end leaves the event under way in the island")
        let long = event("long", -3600, hour + 600)
        suite.expect(countdownFor([long], ends: true) == nil
                     && countdownFor([long], at: 600, ends: true) == NotchCalendarCountdown(event: long, ongoing: true)
                     && countdownFor([allDay], ends: true) == nil,
                     "time left appears only in the hour before a timed end")
        suite.expect(!NotchCalendarCountdown(event: later, ongoing: true).isShown(at: now)
                     && !NotchCalendarCountdown(event: meeting, ongoing: true).isShown(at: meeting.end),
                     "an end is never shown before its event begins or once it has passed")
        suite.expect(transition([long], ends: true) == now.addingTimeInterval(600)
                     && transition([afterGap], starts: false, ends: true) == afterGap.start,
                     "the hour before an end opens no earlier than the event's start")
        suite.expect(transition([meeting], starts: false, ends: true) == meeting.end
                     && transition([meeting], starts: false) == nil,
                     "a refresh is scheduled when the current event ends, and none when nothing is followed")
        chosenCountdownContracts(suite, defaults: defaults, now: now)
        let posix = Locale(identifier: "en_US_POSIX")
        let endText = NotchCalendarSupport.timeText(NotchCalendarCountdown(event: meeting, ongoing: true), locale: posix)
        suite.expect(NotchCalendarSupport.timeText(NotchCalendarCountdown(event: afterGap, ongoing: false), locale: posix)
                        .hasPrefix("·")
                     && endText == "→\u{2009}" + meeting.end.formatted(.dateTime.hour().minute().locale(posix)),
                     "the time beside the clock is when the next event starts or when the current one ends")
        suite.expect(NotchCalendarSupport.countdownText(until: now.addingTimeInterval(hour), now: now) == "60:00"
                     && NotchCalendarSupport.countdownText(until: now.addingTimeInterval(61), now: now) == "1:01"
                     && NotchCalendarSupport.countdownText(until: now, now: now) == "0:00",
                     "the compact clock includes seconds and never shows negative time")
        let physical = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 120)
        let calendarWings = physical.compactCalendarGeometry
        let calendarFooter = NotchGeometry(screen: physical.screen, safeAreaTop: 32,
                                           cameraWidth: 180, compactSideRoom: 30).compactCalendarGeometry
        suite.expect(calendarWings.compactActivityWingWidth == 120 && !calendarWings.compactActivityUsesFooter
                     && calendarFooter.compactActivityUsesFooter && calendarFooter.compactActivityCameraGap == 0,
                     "the event title uses the available wings or a full row below a crowded physical notch")
        suite.expect(physical.compactCalendarGeometry(wing: 90).compactActivityWingWidth == 90
                     && physical.compactCalendarGeometry(wing: 30).compactActivityWingWidth == 72
                     && physical.compactCalendarGeometry(wing: 500).compactActivityWingWidth == 120
                     && NotchGeometry(screen: physical.screen, safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 80)
                        .compactCalendarGeometry(wing: 100).compactActivityWingWidth == 80,
                     "the countdown wings fit the wider of the title and the clock, within the menus' room")
        func menus(_ room: CGFloat) -> NotchGeometry {
            NotchGeometry(screen: physical.screen, safeAreaTop: 32, cameraWidth: 180, compactSideRoom: room)
        }
        let pair = physical.compactCalendarGeometry(wing: 66, paired: true)
        suite.expect(pair.compactActivityWingWidth == 66 && !pair.compactActivityUsesFooter
                     && physical.compactCalendarGeometry(wing: 30, paired: true).compactActivityWingWidth == 44,
                     "paired, the event's clock and the other activity's mark set the wings, without a title's minimum")
        suite.expect(menus(68).compactCalendarGeometry(wing: 66, paired: true).compactActivityWingWidth == 66
                     && menus(68).compactCalendarGeometry(wing: 66).compactActivityUsesFooter
                     && menus(60).compactCalendarGeometry(wing: 66, paired: true).compactActivityUsesFooter
                     && menus(75).compactCalendarGeometry(wing: 80, paired: true).compactActivityWingWidth == 75,
                     "a pair stays beside the camera where the menus leave it room and moves below a crowded notch otherwise")
        // The service measures a pair in this geometry before it knows the wing.
        let measuring = menus(50).compactCalendarGeometry(wing: 0, paired: true)
        suite.expect(!measuring.compactActivityUsesFooter
                     && measuring.compactActivityEdgeInset(boxHeight: 9, radius: 0)
                        == pair.compactActivityEdgeInset(boxHeight: 9, radius: 0),
                     "a pair is measured beside the camera wherever its narrowest wing fits, with the inset its wings keep")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let late = calendar.date(byAdding: .hour, value: 22, to: midnight)!.addingTimeInterval(3540)
        let rollover = NotchCalendarSupport.nextRefresh([], now: late, calendar: calendar)
        suite.expect(rollover.timeIntervalSince(late) == 60 && calendar.component(.day, from: rollover) == 9,
               "calendar refresh reaches the next local day across daylight saving time")
        func start(day: Int, hour: Int, minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
        }
        let british = Locale(identifier: "en_GB")
        suite.expect(NotchCalendarSupport.tileStartText(start(day: 9, hour: 10, minute: 30), now: start(day: 9, hour: 9),
                                                        locale: british, calendar: calendar) == "10:30"
                     && NotchCalendarSupport.tileStartText(start(day: 10, hour: 9), now: start(day: 9, hour: 9),
                                                           locale: british, calendar: calendar) == "Tue 09:00",
                     "the tile reads a start today as its time and adds the weekday for a later day, in the calendar's zone")
        calendarMonthContracts(suite)
    }

    /// Events chosen from their menu in the island, with the countdown for
    /// every event off.
    private static func chosenCountdownContracts(_ suite: TestSuite, defaults: UserDefaults, now: Date) {
        let hour = NotchCalendarSupport.countdownLeadTime
        func event(_ key: String, _ start: Double, _ end: Double) -> NotchCalendarEvent {
            NotchCalendarEvent(id: key + ":" + String(start), title: key, calendar: "Personal",
                               start: now.addingTimeInterval(start), end: now.addingTimeInterval(end),
                               allDay: false, location: "", countdownKey: key)
        }
        let series = NotchCalendarSupport.countdownKey(identifier: "series", occurrence: now)
        suite.expect(NotchCalendarSupport.countdownKey(identifier: "single", occurrence: nil) == "single"
                     && series.hasPrefix("series@")
                     && series != NotchCalendarSupport.countdownKey(identifier: "series",
                                                                    occurrence: now.addingTimeInterval(86_400))
                     && NotchCalendarSupport.countdownKey(
                        identifier: "series", occurrence: Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude))
                        .hasPrefix("series@"),
                     "a single event is chosen by its identifier and each occurrence of a series by the date it fell on")
        let chosen = event("chosen", 1200, 2400)
        let other = event("other", 600, 900)
        let unkeyed = event("", 300, 600)
        func countdown(_ events: [NotchCalendarEvent], at offset: Double = 0, starts: Bool = false,
                       ends: Bool = false, choices: Set<String> = ["chosen"]) -> NotchCalendarCountdown? {
            NotchCalendarSupport.countdown(events, now: now.addingTimeInterval(offset), starts: starts, ends: ends,
                                           chosen: choices)
        }
        suite.expect(countdown([other, chosen]) == NotchCalendarCountdown(event: chosen, ongoing: false)
                     && countdown([other, chosen], choices: []) == nil,
                     "with the countdown for every event off, only an event chosen from its menu counts down")
        suite.expect(countdown([other, chosen], starts: true)?.event == other,
                     "with the countdown for every event on, the nearest start still leads")
        suite.expect(countdown([unkeyed], choices: [""]) == nil,
                     "an event read without a key is never taken for a chosen one")
        suite.expect(countdown([chosen], at: 1200) == nil
                     && countdown([chosen], at: 1200, ends: true) == NotchCalendarCountdown(event: chosen, ongoing: true),
                     "a chosen event counts down to its start; time left in it follows its own option")
        let ahead = event("ahead", hour + 1800, hour + 3600)
        suite.expect(NotchCalendarSupport.countdownTransition([ahead], now: now, starts: false, ends: false,
                                                              chosen: ["ahead"]) == now.addingTimeInterval(1800)
                     && NotchCalendarSupport.countdownTransition([ahead], now: now, starts: false, ends: false,
                                                                 chosen: []) == nil,
                     "a refresh is scheduled when a chosen event's hour opens, and none for an event not chosen")
        suite.expect(NotchCalendarSupport.chosenCountdowns(in: defaults).isEmpty, "no event starts chosen")
        NotchCalendarSupport.setCountdown(true, for: chosen, in: defaults)
        NotchCalendarSupport.setCountdown(true, for: unkeyed, in: defaults)
        suite.expect(NotchCalendarSupport.chosenCountdowns(in: defaults) == ["chosen": chosen.end],
                     "a chosen event is kept by its key with its end, and an event without a key cannot be chosen")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchCalendarChosenCountdowns),
                     "events chosen on this Mac stay out of settings backups")
        let moved = event("chosen", 1200 + hour, 2400 + hour)
        suite.expect(NotchCalendarSupport.refreshedChoices(["chosen": chosen.end], events: [moved], now: now)
                        == ["chosen": moved.end],
                     "a chosen event moved to another time stays chosen with its new end")
        suite.expect(NotchCalendarSupport.refreshedChoices(["chosen": chosen.end], events: [chosen, other], now: now) == nil,
                     "an unchanged read writes no preference")
        let nextWeek = now.addingTimeInterval(8 * 86_400)
        suite.expect(NotchCalendarSupport.refreshedChoices(["chosen": chosen.end, "ended": now,
                                                            "next week": nextWeek], events: [chosen], now: now)
                        == ["chosen": chosen.end, "next week": nextWeek],
                     "a choice is forgotten once its event ends, and one beyond the week read waits for its week")
        NotchCalendarSupport.setCountdown(false, for: chosen, in: defaults)
        suite.expect(defaults.object(forKey: DefaultsKey.notchCalendarChosenCountdowns) == nil,
                     "removing the last choice leaves no preference behind")
    }

    private static func calendarMonthContracts(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let leapDay = date(2028, 2, 29)
        for firstWeekday in [1, 2, 7] {
            calendar.firstWeekday = firstWeekday
            let days = NotchCalendarSupport.monthDays(containing: leapDay, calendar: calendar)
            suite.expect(days.count == 42 && Set(days).count == 42,
                   "the month has six stable complete weeks with no duplicated dates")
            suite.expect(calendar.component(.weekday, from: days[0]) == firstWeekday && days.contains(leapDay),
                   "the grid honors the user's first weekday and includes leap day")
            suite.expect(days.filter { calendar.component(.month, from: $0) == 2 }.count == 29,
                   "every date of a leap February appears exactly once")
        }
        for firstWeekday in [1, 2, 7] {
            calendar.firstWeekday = firstWeekday
            for day in [date(2026, 3, 1), date(2026, 3, 31, 12), date(2026, 10, 31), leapDay] {
                let week = NotchCalendarSupport.weekDays(containing: day, calendar: calendar)
                let grid = NotchCalendarSupport.monthDays(containing: day, calendar: calendar)
                suite.expect(week.count == 7 && calendar.component(.weekday, from: week[0]) == firstWeekday
                       && week.contains(calendar.startOfDay(for: day)) && week.allSatisfy(grid.contains),
                       "the week strip starts on the user's first weekday, holds its day and stays within the month read for it")
            }
        }
        for height in [NotchLayout.compactContentHeight, NotchLayout.spaciousContentHeight, 154] as [CGFloat] {
            let row = NotchLayout.calendarMonthRowHeight(height: height)
            let grid = NotchLayout.calendarMonthWeekdayHeight + row * 6
            suite.expect(row >= 16 && row <= 30 && row == row.rounded() && grid <= height,
                   "the strip's month grid keeps six readable rows inside every preset and the lowest custom height")
        }
        suite.expect(NotchLayout.calendarMonthMinimumHeight == NotchLayout.calendarMonthWeekdayHeight + 6 * 16
               && NotchLayout.calendarMonthRowHeight(height: NotchLayout.calendarMonthMinimumHeight) == 16
               && NotchLayout.calendarMonthRowHeight(height: NotchLayout.compactContentHeight) == 27,
               "with its title in the island's top row, the month grid gives the freed height to its rows")
        for (firstWeekday, minimumDays) in [(1, 1), (2, 4), (7, 1)] {
            calendar.firstWeekday = firstWeekday
            calendar.minimumDaysInFirstWeek = minimumDays
            for month in [date(2026, 12, 15), date(2027, 1, 15), leapDay] {
                let days = NotchCalendarSupport.monthDays(containing: month, calendar: calendar)
                let rows = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
                suite.expect(days.filter { NotchCalendarSupport.startsWeek($0, calendar: calendar) } == rows.compactMap(\.first),
                       "a week number is drawn once per row, ahead of the row's first day")
                suite.expect(rows.allSatisfy { row in
                    Set(row.map { NotchCalendarSupport.weekNumber(of: $0, calendar: calendar) }).count == 1
                }, "every day of a row shares the row's week number, whatever day the week starts on")
            }
        }
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        suite.expect(NotchCalendarSupport.weekNumber(of: date(2026, 12, 31), calendar: calendar) == 53
               && NotchCalendarSupport.weekNumber(of: date(2027, 1, 3), calendar: calendar) == 53
               && NotchCalendarSupport.weekNumber(of: date(2027, 1, 4), calendar: calendar) == 1,
               "a Monday-first calendar numbers the turn of the year as ISO weeks do")
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        suite.expect(NotchCalendarSupport.weekNumber(of: date(2026, 12, 26), calendar: calendar) == 52
               && NotchCalendarSupport.weekNumber(of: date(2027, 1, 1), calendar: calendar) == 1
               && NotchCalendarSupport.weekNumber(of: date(2026, 12, 27), calendar: calendar) == 1,
               "a Sunday-first calendar starts week 1 with the row that holds January 1")
        for language in AppLanguage.allCases {
            let text = FeatureStrings.notchCalendar(language)
            let label = NotchCalendarSupport.weekNumberLabel(of: date(2026, 12, 26), text: text, calendar: calendar)
            let words = label.replacingOccurrences(of: "52", with: "")
                .trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
            suite.expect(TestFormat.parse(text.weekNumber)?.conversions == ["d"]
                   && text.weekNumber.components(separatedBy: "%d").count == 2
                   && label.contains("52") && !words.isEmpty,
                   "VoiceOver reads a row's week number as that week in \(language.rawValue)")
        }
        let monthView = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Notch/NotchCalendarMonthView.swift",
                                     encoding: .utf8)) ?? ""
        let weekNumberView = monthView.components(separatedBy: "struct NotchCalendarWeekNumber: View {").last ?? ""
        suite.expect(monthView.components(separatedBy: "NotchCalendarWeekNumber(date: date, text: text,").count == 3
               && weekNumberView.contains(".accessibilityLabel(NotchCalendarSupport.weekNumberLabel(of: date, text: text))")
               && !weekNumberView.contains(".accessibilityHidden(true)"),
               "both month grids give VoiceOver each row's week number")
        suite.expect(!monthView.contains("Text(date, format: .dateTime.day())")
               && monthView.components(separatedBy: "Text(calendar.component(.day, from: date), format: .number)").count == 4,
               "the month grid, the week strip and the short month show each day's number without 日 or 일")
        let march = NotchCalendarSupport.monthDays(containing: date(2026, 3, 15), calendar: calendar)
        suite.expect(march.contains(date(2026, 3, 8)) && march.contains(date(2026, 3, 9))
               && date(2026, 3, 9).timeIntervalSince(date(2026, 3, 8)) == 23 * 3600,
               "month dates stay at local midnight through a daylight saving transition")
        let now = date(2026, 3, 31, 12)
        let interval = NotchCalendarSupport.readInterval(month: now, now: now, calendar: calendar)
        suite.expect(interval.start <= date(2026, 3, 1) && interval.end >= date(2026, 4, 7),
               "the visible month query also covers all seven upcoming days across month boundaries")
        let distant = NotchCalendarSupport.readInterval(month: date(2030, 12, 1), now: now, calendar: calendar)
        suite.expect(distant.duration <= 43 * 86400 && distant.start > now,
               "browsing a distant month reads only its grid, never every intervening event")
        let current = NotchCalendarSupport.readInterval(month: nil, now: now, calendar: calendar)
        suite.expect(!NotchCalendarSupport.needsCurrentRead(visible: interval, current: current,
                                                           countdownEnabled: true)
                     && NotchCalendarSupport.needsCurrentRead(visible: distant, current: current,
                                                              countdownEnabled: true)
                     && !NotchCalendarSupport.needsCurrentRead(visible: distant, current: current,
                                                               countdownEnabled: false),
                     "the countdown keeps today's events while browsing another month without extra reads when off")
        let resting = NotchCalendarSupport.readInterval(month: nil, now: now, calendar: calendar)
        suite.expect(resting.start == date(2026, 3, 31) && resting.end == date(2026, 4, 7),
               "closing the month returns the reader to today's seven-day interval")
        let allDay = NotchCalendarEvent(id: "all", title: "Holiday", calendar: "Personal",
            start: date(2026, 3, 8), end: date(2026, 3, 10), allDay: true, location: "")
        let overnight = NotchCalendarEvent(id: "overnight", title: "Travel", calendar: "Personal",
            start: date(2026, 3, 8, 23), end: date(2026, 3, 9, 2), allDay: false, location: "")
        let ended = NotchCalendarEvent(id: "ended", title: "Morning", calendar: "Personal",
            start: date(2026, 3, 8, 9), end: date(2026, 3, 8, 10), allDay: false, location: "")
        let entries = NotchCalendarSupport.ordered([overnight, allDay, ended, ended])
        suite.expect(NotchCalendarSupport.events(entries, on: date(2026, 3, 8), calendar: calendar).map(\.id)
               == ["all", "ended", "overnight"],
               "selected dates retain completed appointments and put all-day events first")
        suite.expect(NotchCalendarSupport.events(entries, on: date(2026, 3, 9), calendar: calendar).map(\.id)
               == ["all", "overnight"],
               "overnight and multi-day events appear on every day they overlap")
        suite.expect(NotchCalendarSupport.events(entries, on: date(2026, 3, 10), calendar: calendar).isEmpty,
               "exclusive midnight endings do not mark or populate the following date")
        suite.expect(NotchCalendarSupport.upcoming(entries, now: date(2026, 3, 8, 12)).map(\.id)
               == ["all", "overnight"],
               "upcoming mode still hides completed appointments after adding month history")
        func link(_ event: NotchCalendarEvent, identifier: String, recurring: Bool) -> String? {
            var event = event
            event.calendarItemIdentifier = identifier
            event.recurring = recurring
            return NotchCalendarSupport.eventURL(event, calendar: calendar)?.absoluteString
        }
        suite.expect(link(ended, identifier: "9F2A 1C", recurring: false)
               == "ical://ekevent/9F2A%201C?method=show&options=more",
               "a single appointment opens by its escaped identifier")
        suite.expect(link(ended, identifier: "9F2A", recurring: true)
               == "ical://ekevent/20260308T130000Z/9F2A?method=show&options=more",
               "a repeating appointment opens the clicked occurrence addressed in UTC")
        suite.expect(link(allDay, identifier: "9F2A", recurring: true)
               == "ical://ekevent/20260308T000000Z/9F2A?method=show&options=more",
               "a repeating all-day occurrence keeps its local day")
        suite.expect(link(ended, identifier: "", recurring: false) == nil,
               "an appointment without an identifier falls back to opening Calendar itself")
    }

}
