// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics
import AppKit

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

        suite.expect(NotchLayout.systemRowRanges(count: 7, width: 504) == [0..<3, 3..<5, 5..<7],
                     "seven System metrics fill balanced rows instead of leaving a nearly empty column")
        suite.expect(NotchLayout.systemRowRanges(count: 7, width: 304) == [0..<2, 2..<4, 4..<6, 6..<7],
                     "narrow System rows keep readable cards and a full-width last card")
        for width: CGFloat in [20, 304, 424, 504, 744] {
            for count in 0...8 {
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
               && controls.height == NotchLayout.compactContentHeight,
               "the default home page is one card row over one shortcut rail, exactly the compact strip")
        suite.expect(NotchLayout.controls(hasCards: true, shortcutCount: 4, width: 424, height: 154)
               == NotchControlsLayout(cardRow: 154 - NotchLayout.shortcutHeight - NotchLayout.rowSpacing, shortcutRows: 1)
               && NotchLayout.controls(hasCards: false, shortcutCount: 0, width: 424, height: 154) == NotchControlsLayout(cardRow: 0, shortcutRows: 0)
               && NotchLayout.controls(hasCards: true, shortcutCount: 0, width: 424, height: 154).height == NotchLayout.cardHeight
               && NotchLayout.controls(hasCards: false, shortcutCount: 9, width: 424, height: 154).height == NotchLayout.shortcutHeight,
               "the smallest custom island shortens the cards to keep the rail, and rows nobody enabled cost nothing")
        let wideTimer = NotchLayout.timer(mode: .timer, hasSession: false, width: 424, height: 180)
        let widePomodoro = NotchLayout.timer(mode: .pomodoro, hasSession: false, width: 424, height: 180)
        let wideStopwatch = NotchLayout.timer(mode: .stopwatch, hasSession: false, width: 424, height: 180)
        suite.expect(wideStopwatch == wideTimer && widePomodoro <= NotchLayout.compactContentHeight
               && wideTimer == NotchLayout.timerTopRowHeight + NotchLayout.timerRowSpacing + NotchLayout.timerRulerHeight
               && widePomodoro == wideTimer + NotchLayout.timerRowSpacing + NotchLayout.timerSettingsRowHeight,
               "every mode shares the mode row and the ruler row; the Pomodoro adds one line of readouts under it")
        let tight: CGFloat = 154
        for mode in NotchTimerMode.allCases {
            for width in [304, 344, 424] as [CGFloat] {
                suite.expect(NotchLayout.timer(mode: mode, hasSession: false, width: width, height: tight) <= tight,
                       "the shortest custom island still shows every timer row: \(mode) at \(Int(width))")
            }
        }
        suite.expect(NotchLayout.timer(mode: .timer, hasSession: false, width: 304, height: tight) == tight
               && NotchLayout.timer(mode: .pomodoro, hasSession: false, width: 304, height: tight) == tight
               && NotchLayout.timer(mode: .pomodoro, hasSession: false, width: 424, height: tight) == tight
               && NotchLayout.timerRulerHeight(width: 304, height: tight) == tight - NotchLayout.timerTopRowHeight
                   - NotchLayout.timerRowSpacing * 2 - NotchLayout.timerStartHeight
               && NotchLayout.timerRulerHeight(mode: .pomodoro, width: 424, height: tight) == tight - NotchLayout.timerTopRowHeight
                   - NotchLayout.timerRowSpacing * 2 - NotchLayout.timerSettingsRowHeight
               && NotchLayout.timerRulerHeight(width: 304, height: 100) == NotchLayout.timerMinimumRulerHeight
               && NotchLayout.timerRulerHeight(width: 304, height: 400) == NotchLayout.timerRulerHeight
               && NotchLayout.timerRulerHeight(width: 424, height: tight) == NotchLayout.timerRulerHeight
               && NotchLayout.timerRulerHeight(mode: .stopwatch, width: 424, height: tight) == NotchLayout.timerRulerHeight,
               "a narrow island gives Start its own row, the Pomodoro its readouts, and the ruler gives up height down to a floor before anything is cut")
        suite.expect(NotchLayout.timer(mode: .pomodoro, hasSession: true, width: 424, height: 180) == 118
               && NotchLayout.timer(mode: .timer, hasSession: true, width: 304, height: tight) == 96,
               "a running session keeps its control row in every layout")
        suite.expect(NotchLayout.musicPlayerHeight(layout: .compact, height: 180) == 120
               && NotchLayout.musicPlayerHeight(layout: .spacious, height: 264) == 148
               && NotchLayout.musicPlayerHeight(layout: .custom, height: 154) == 112
               && NotchLayout.musicPlayerHeight(layout: .custom, height: 60) == 88,
               "the artwork grows with the preset and shrinks with a custom height down to a legible floor")
    }

    private static func presentationSpacingContracts(_ suite: TestSuite) {
        let screen = CGRect(x: -1470, y: 80, width: 1470, height: 956)
        for width in [360.0, 480, 560, 720] {
            for cameraHeight: CGFloat in [24, 32, 40, 64] {
                let geometry = NotchGeometry(screen: screen, safeAreaTop: cameraHeight, cameraWidth: 210,
                                             layout: .custom, customWidth: width, customHeight: 400)
                let top = geometry.headerTopInset + geometry.headerRowHeight + NotchLayout.spacing
                suite.expect(top >= cameraHeight, "the page always begins below the physical camera")
                let area = geometry.activationArea(in: geometry.expanded, hasHeader: true,
                                                   compactActivity: false, expandedHeader: true)
                if width >= 480 {
                    suite.expect(geometry.headerCameraGap == 210 && geometry.headerTopInset == 0,
                                 "wide headers use the space beside the camera without reserving a blank top row")
                    suite.expect(area.width == 210 && area.height == cameraHeight
                                 && area.midX == geometry.expanded.width / 2,
                                 "the collapse target covers only the camera, leaving header controls clickable")
                } else {
                    suite.expect(geometry.headerCameraGap == 0 && geometry.headerTopInset >= cameraHeight,
                                 "narrow headers keep a complete usable row below the camera")
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
                         "both presets place the title beside the camera without a blank top row")
            suite.expect(geometry.quickAccessCenterY - NotchQuickAccessLayout.diameter / 2 == 38,
                         "floating buttons keep six points of clearance below the menu bar in both presets")
        }
        let simulated = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: .spacious)
        suite.expect(simulated.headerTopInset == 0 && simulated.headerCameraGap == 0,
                     "a display without a camera does not reserve a blank expanded header row")
        suite.expect(simulated.activationArea(in: simulated.expanded, hasHeader: true,
                                             compactActivity: false, expandedHeader: true).isEmpty,
                     "simulated header controls are never covered by an invisible collapse button")
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
                        let wing = geometry.noticeWingWidth(preferred: notice.preferredWingWidth)
                        let content = wing - 16 - notice.cameraGap
                        suite.expect(width(notice.level == nil ? notice.title : notice.detail) + 18 + 8 <= content,
                               "power labels and connection status fit beside their icon in \(language)")
                        suite.expect(notice.level != nil || width(notice.detail) <= content,
                               "a device name and a charge percentage fit the opposite wing in \(language)")
                        let size = geometry.noticeSize(wingWidth: notice.preferredWingWidth)
                        suite.expect(size.width == wing * 2 + geometry.cameraWidth && size.height == height
                               && screen.contains(geometry.frame(for: size)),
                               "content-sized notices preserve camera clearance, menu height and display bounds")
                    }
                }
            }
        }
        for event in [NotchEvent.volume, .brightness, .keyboardLight] {
            for percent in 0...100 {
                let notice = NotchNotice(event: event, title: "Level", detail: "\(percent)%",
                                         symbol: "speaker.wave.2", level: Double(percent) / 100)
                let wing = notice.preferredWingWidth
                suite.expect(wing == 80, "level changes keep a stable compact width without an empty outer margin")
                suite.expect(width(notice.detail) + 18 + 8 + 16 <= wing && wing - 16 >= 64,
                             "every percentage fits beside its icon while the opposite meter remains readable")
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
        let notification = NotchNotice(event: .systemNotification, title: "Notice", detail: "Body", symbol: "bell",
            notification: NotchNotificationContent(app: "App", title: "Notice", subtitle: "", body: "Body"))
        suite.expect(notification.preferredWingWidth == 190, "mirrored notifications keep their existing text layout")
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

    /// The menu bar under a camera can be a point taller than the cutout.
    /// Every closed strip follows the cutout, or a dark line shows under it.
    private static func physicalStripContracts(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        for barHeight: CGFloat in [24, 32, 33, 37, 40, 64] {
            let geometry = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 179,
                                         menuBarHeight: barHeight, compactSideRoom: 100)
            let strips = [geometry.restingSize(showsContent: true), geometry.collapsed, geometry.notice,
                          geometry.noticeSize(wingWidth: 190), geometry.compactMusicGeometry.compactActivitySize,
                          geometry.compactTimerGeometry(showsDownloads: true).compactActivitySize]
            for size in strips {
                suite.expect(size.height == geometry.cameraHeight && size.height == geometry.stripHeight,
                       "a strip beside a physical camera is exactly as tall as the cutout")
            }
            suite.expect(geometry.menuBarHeight == max(32, barHeight),
                   "the bar's own height remains available for measuring menu space")
        }
        let closed = NotchLayout.surfaceRadius(height: 32)
        suite.expect(closed >= 8 && closed <= 12 && NotchLayout.shoulder(height: 32) >= 5 && NotchLayout.shoulder(height: 32) <= 8,
               "a closed island keeps corners like the cutout's, so a collapse settles inside the notch")
        suite.expect(NotchLayout.surfaceRadius(height: 286) == 28 && NotchLayout.shoulder(height: 286) == NotchLayout.shoulder,
               "an open island keeps its full corner radius and shoulder")
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

    static func run(_ suite: TestSuite) {
        railContracts(suite)
        presentationSpacingContracts(suite)
        noticeLayoutContracts(suite)
        simulatedMenuBoundsContracts(suite)
        simulatedDisplayContracts(suite)
        menuSpaceReuseContracts(suite)
        menuBarHeightContracts(suite)
        physicalStripContracts(suite)
        musicLabelContracts(suite)
        NotchPanelTests.run { suite.expect($0, $1) }
        NotchHoverTests.run(suite)
        NotchScreenEdgeClickTests.run(suite)
        NotchPresentationRefreshContract.run(suite)
        NotchScreenRefreshContract.run(suite)
        NotchFullscreenTests.run(suite)
        NotchDestinationContract.run(suite)
        NotchMusicVisibilityTests.run(suite)
        NotchEqualizerTests.run { suite.expect($0, $1) }
        NotchLyricsTimelineTests.run { suite.expect($0, $1) }
        NotchUpdateTests.run(suite)
        NotchCaptureKeyboardTests.run(suite)
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
        NotchMusicExtrasTests.run(suite)
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
        let homeGeometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956), safeAreaTop: 32, cameraWidth: 180)
        suite.expect(homeGeometry.expandedSize(module: .controls, controlsHaveMusic: true)
               == homeGeometry.expandedSize(module: .controls),
               "home playback shares the card row with the levels instead of adding one")
        suite.expect(homeGeometry.expandedSize(module: .controls, sliderCount: 0, controlsHaveMusic: true).height
               - homeGeometry.expandedSize(module: .controls, sliderCount: 0).height == NotchLayout.cardHeight + NotchLayout.rowSpacing,
               "without levels, home playback is the card row and its spacing")

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
        suite.expect(NotchSupport.hidesUntilHover(in: defaults), "hidden until hover waits out of sight for the pointer")
        defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
        suite.expect(!NotchSupport.hidesUntilHover(in: defaults), "an island that opens by click never waits for hover")
        defaults.set(true, forKey: DefaultsKey.notchOpenOnHover)
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
               && defaults.bool(forKey: DefaultsKey.notchOpenOnHover)
               && defaults.bool(forKey: DefaultsKey.notchHoverExpands),
               "a new island starts spacious and expands on hover")
        suite.expect(!defaults.bool(forKey: DefaultsKey.notchHideUntilHover), "hidden hover is opt-in")
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
        suite.expect(NotchSupport.routesAppPanel(in: defaults) && NotchSupport.routesQuickPanel(in: defaults)
               && NotchSupport.routesClipboardWindow(in: defaults) && NotchSupport.routesShelf(in: defaults)
               && NotchSupport.routesCaptureControls(in: defaults),
               "enabling a fresh island routes available panels into it")
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
        suite.expect(!NotchSupport.watchesMusicActivity(in: defaults)
               && !NotchSupport.showsMusicActivity(isPlaying: true, in: defaults)
               && NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .none,
               "Nothing at rest suppresses playing music and its background observer without disabling the island")
        suite.expect(NotchSupport.isEnabled(in: defaults) && NotchSupport.modules(in: defaults).contains(.music),
               "Nothing at rest keeps the island and its on-demand music section available")
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
        suite.expect(!NotchSupport.routes(.clipboard, in: defaults) && !NotchSupport.routes(.capture, in: defaults),
               "notch opt-in does not reveal copied content or move captures")
        defaults.set(true, forKey: DefaultsKey.notchClipboard)
        suite.expect(!NotchSupport.routes(.clipboard, in: defaults), "clipboard event respects the history capture switch")
        defaults.set(true, forKey: DefaultsKey.clipboardHistoryEnabled)
        suite.expect(NotchSupport.routes(.clipboard, in: defaults), "explicit clipboard activity opt-in is honored")
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
        suite.expect(NotchSupport.modules(in: defaults) == [.system, .music, .controls, .mixer, .captures, .files, .tools, .calendar, .timer, .downloads, .scratchpad],
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

        let keys: Set<String> = [DefaultsKey.notchShowPlayingMusic, DefaultsKey.notchShowInCaptures, DefaultsKey.notchIdleContent, DefaultsKey.notchHiddenControls, DefaultsKey.notchControlOrder, DefaultsKey.notchSize, DefaultsKey.notchShelf, DefaultsKey.notchDragReveal,
                                DefaultsKey.notchCustomWidth, DefaultsKey.notchCustomHeight, DefaultsKey.notchHapticFeedback,
                                DefaultsKey.notchCaptureControls, DefaultsKey.notchQuickPanel, DefaultsKey.notchAppPanel,
                                DefaultsKey.notchHidesMenuBarIcon, DefaultsKey.notchScratchpad,
                                DefaultsKey.notchHoverExpands, DefaultsKey.notchEnabled, DefaultsKey.notchDisplay,
                                DefaultsKey.notchOpenOnHover, DefaultsKey.notchHoverDelay, DefaultsKey.notchHideUntilHover, DefaultsKey.notchHiddenModules,
                                DefaultsKey.notchModuleOrder, DefaultsKey.notchQuickAccessLayout, DefaultsKey.notchQuickAccessSide, DefaultsKey.notchQuickAccessSecond, DefaultsKey.notchQuickAccessThird, DefaultsKey.notchVolume,
                                DefaultsKey.notchBrightness, DefaultsKey.notchBattery,
                                DefaultsKey.notchClipboard, DefaultsKey.notchClipboardWindow, DefaultsKey.notchCapture,
                                DefaultsKey.notchMusicActivity, DefaultsKey.notchHideInCaptures, DefaultsKey.panelControlNotch,
                                AppFeature.notch.availabilityKey]
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: keys), "every notch preference travels in backup")
        let restored = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [DefaultsKey.notchEnabled: true,
                                                DefaultsKey.notchDisplay: "builtIn",
                                                DefaultsKey.notchSize: "custom",
                                                DefaultsKey.notchCustomWidth: 390.0,
                                                DefaultsKey.notchCustomHeight: 580.0,
                                                DefaultsKey.notchHapticFeedback: true,
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
               && restored?[DefaultsKey.notchHapticFeedback] as? Bool == true,
               "backup restores custom dimensions and tactile feedback together")
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
        let crowded = NotchQuickAccessConfiguration(buttons: (0..<12).map { _ in NotchQuickButton(action: .settings, side: .bottom) }).sanitized()
        suite.expect(crowded.buttons.count == 3, "restored layouts cannot overfill an edge")
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
               && tall.sectionRows(count: allModules.count)
                   == NotchSectionPaging.rows(count: allModules.count, columns: tall.sectionColumns),
               "the gallery is a page: presets show three whole rows and a tall island shows every row")
        suite.expect(compact.sectionColumns == 4 && spacious.sectionColumns == 5
               && compact.sectionColumns * compact.sectionRows(count: allModules.count) < allModules.count
               && spacious.sectionColumns * spacious.sectionRows(count: allModules.count) >= allModules.count,
               "a compact island steps one row to reach its last sections and a spacious one shows them all")
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
                     CGSize(width: 504, height: 264)] {
            let preview = NotchLayout.cameraPreviewSize(in: size)
            suite.expect(preview.width <= size.width && preview.height + 28 + NotchLayout.rowSpacing <= size.height
                   && abs(preview.width / preview.height - 4.0 / 3.0) < 0.001,
                   "camera preview preserves its aspect ratio and leaves the stop button inside the page")
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
        let idleMusic = compact.expandedSize(module: .music, musicHasContent: false)
        suite.expect(idleMusic.height < compact.expandedSize(module: .music).height
               && compact.contentSize(for: idleMusic).height == NotchLayout.musicIdleHeight + NotchLayout.musicControlsRowHeight + NotchLayout.rowSpacing,
               "empty music keeps its message and volume controls without reserving a full player")
        suite.expect(compact.contentSize(for: compact.expandedSize(module: .music, musicHasControlsRow: false)).height
               == NotchLayout.musicPlayerHeight(layout: .compact, height: NotchLayout.compactContentHeight),
               "without a mixer or extras the player row is the whole page")
        let fullControls = compact.expandedSize(module: .controls, shortcutCount: 10, sliderCount: 2)
        let fewerShortcuts = compact.expandedSize(module: .controls, shortcutCount: 3, sliderCount: 2)
        let onlyShortcuts = compact.expandedSize(module: .controls, shortcutCount: 3, sliderCount: 0)
        let onlySliders = compact.expandedSize(module: .controls, shortcutCount: 0, sliderCount: 2)
        suite.expect(fullControls == fewerShortcuts && fewerShortcuts.height > onlyShortcuts.height
               && fewerShortcuts.height > onlySliders.height,
               "a compact island runs extra shortcuts sideways and drops the rows nobody enabled")
        suite.expect(compact.contentSize(for: fullControls).height == NotchLayout.compactContentHeight
               && spacious.expandedSize(module: .controls, shortcutCount: 10).height
                   > spacious.expandedSize(module: .controls, shortcutCount: 3).height,
               "the home page fills the compact strip while a spacious island adds a second shortcut row first")
        suite.expect(compact.contentSize(for: compact.expandedSize(module: .controls, shortcutCount: 0, sliderCount: 0)).height == NotchLayout.emptyHeight,
               "hiding every control leaves the empty-state guidance its own row")
        for width in [360.0, 480.0, 600.0] {
            for height in [NotchSize.heightRange.lowerBound, 640.0] {
                let geometry = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210,
                                             layout: .custom, customWidth: width, customHeight: height)
                for shortcuts in 0...12 {
                    for sliders in 0...2 {
                        let size = geometry.expandedSize(module: .controls, shortcutCount: shortcuts, sliderCount: sliders)
                        let content = geometry.contentSize(for: size)
                        let planned = NotchLayout.controls(hasCards: sliders > 0, shortcutCount: shortcuts,
                                                           width: geometry.contentWidth, height: geometry.contentBudget)
                        let drawn = NotchLayout.controls(hasCards: sliders > 0, shortcutCount: shortcuts,
                                                         width: content.width, height: content.height)
                        suite.expect(content.height == min(geometry.contentBudget, planned.height == 0 ? NotchLayout.emptyHeight : planned.height),
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
                    suite.expect(custom.contentSize(for: custom.expandedSize(module: .music)).height
                           == min(available, NotchLayout.musicPlayerHeight(layout: .custom, height: available)
                                  + NotchLayout.musicControlsRowHeight + NotchLayout.rowSpacing),
                           "custom sizes keep the player row and its volume controls, shrinking the artwork before anything scrolls")
                    suite.expect(custom.contentSize(for: custom.expandedSize(module: .music, musicHasContent: false)).height
                           >= min(available, NotchLayout.musicIdleHeight + NotchLayout.musicControlsRowHeight),
                           "empty music keeps its message and volume controls at every custom height")
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
                suite.expect(geometry.contentSize(for: geometry.expandedSize(module: .music)).height
                       == NotchLayout.musicPlayerHeight(layout: .compact, height: NotchLayout.compactContentHeight)
                           + NotchLayout.musicControlsRowHeight + NotchLayout.rowSpacing,
                       "compact music is one artwork-high player row over its volume controls")
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
        func near(_ value: CGFloat, _ expected: CGFloat) -> Bool { abs(value - expected) < 0.000_1 }
        let closing = NotchGlassFade.plan(from: 200, to: 32, endsInGlass: false, current: 1)
        suite.expect(near(closing.openness(atHeight: 200), 1) && near(closing.openness(atHeight: 80), 1)
                && near(closing.openness(atHeight: 56), 0.5) && near(closing.openness(atHeight: 32), 0),
               "settled glass closing into a black strip darkens only over the last stretch and arrives black")
        let opening = NotchGlassFade.plan(from: 32, to: 200, endsInGlass: true, current: 0)
        suite.expect(near(opening.openness(atHeight: 32), 0) && near(opening.openness(atHeight: 56), 0.5)
                && near(opening.openness(atHeight: 80), 1) && near(opening.openness(atHeight: 200), 1),
               "glass leaving a black strip opens up over the first stretch")
        let reopened = NotchGlassFade.plan(from: 56, to: 200, endsInGlass: true,
                                           current: closing.openness(atHeight: 56))
        suite.expect(near(reopened.openness(atHeight: 56), 0.5) && near(reopened.openness(atHeight: 200), 1),
               "a close reversed halfway reopens from the openness on screen and ends fully open")
        let reclosed = NotchGlassFade.plan(from: 44, to: 32, endsInGlass: false,
                                           current: opening.openness(atHeight: 44))
        suite.expect(near(reclosed.openness(atHeight: 44), 0.25) && near(reclosed.openness(atHeight: 32), 0),
               "an opening reversed early closes from the openness on screen and ends black")
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
                                       notched: [false], main: 0) == 0, "closed-lid mode falls back to an attached screen")
        suite.expect(NotchSupport.screenIndex(preference: .main, builtIn: [], notched: [], main: 0) == nil,
               "no connected displays means no panel")
        suite.expect(NotchSupport.shouldReplace(.volume, with: .brightness), "continuous controls can replace each other")
        suite.expect(!NotchSupport.shouldReplace(.volume, with: .clipboard), "copy does not interrupt a volume adjustment")
        suite.expect(NotchSupport.shouldReplace(.battery, with: .capture), "a capture takes precedence over passive battery status")
        suite.expect(NotchSupport.volumeLevel(current: 0.99, direction: 1, fine: false) == 1
               && NotchSupport.volumeLevel(current: 0, direction: -1, fine: false) == 0,
               "hardware volume steps clamp to audible limits")
        suite.expect(NotchSupport.volumeLevel(current: 0.5, direction: 1, fine: true) == 0.515625,
               "fine volume preserves the system quarter-step")

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
        defaults.set("calendar", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchCalendarSupport.isEnabled(in: defaults), "hiding the calendar releases its resources")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(false, forKey: AppFeature.notchCalendar.availabilityKey)
        suite.expect(!NotchCalendarSupport.isEnabled(in: defaults), "removing the calendar from the hub stops its reader")
        defaults.set(true, forKey: AppFeature.notchCalendar.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchCalendarSupport.isEnabled(in: defaults), "the master switch also stops calendar reads")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchCalendarEnabled,
                                                                 AppFeature.notchCalendar.availabilityKey]),
               "calendar preferences travel in backup")
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let late = calendar.date(byAdding: .hour, value: 22, to: midnight)!.addingTimeInterval(3540)
        let rollover = NotchCalendarSupport.nextRefresh([], now: late, calendar: calendar)
        suite.expect(rollover.timeIntervalSince(late) == 60 && calendar.component(.day, from: rollover) == 9,
               "calendar refresh reaches the next local day across daylight saving time")
        calendarMonthContracts(suite)
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
            let grid = NotchLayout.calendarMonthHeaderHeight + NotchLayout.calendarMonthWeekdayHeight
                + NotchLayout.calendarMonthSpacing * 2 + row * 6
            suite.expect(row >= 16 && row <= 30 && row == row.rounded() && grid <= height,
                   "the strip's month grid keeps six readable rows inside every preset and the lowest custom height")
        }
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
