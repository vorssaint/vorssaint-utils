// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics
import AppKit

enum NotchTests {
    private static func noticeLayoutContracts(expect: (Bool, String) -> Void) {
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
            } + [NotchNotice(event: .accessory, title: "Wireless Headphones", detail: activities.connected, symbol: "headphones"),
                 NotchNotice(event: .accessory, title: "Wireless Keyboard", detail: activities.lowBattery + " · 15%",
                             symbol: "keyboard", level: 0.15)]
            for physical in [false, true] {
                for height: CGFloat in [16, 24, 32, 40, 64] {
                    let geometry = NotchGeometry(screen: screen, safeAreaTop: physical ? height : 0,
                                                 cameraWidth: physical ? 180 : 0, menuBarHeight: height)
                    for notice in notices {
                        let wing = geometry.noticeWingWidth(preferred: notice.preferredWingWidth)
                        let content = wing - 32
                        expect(width(notice.level == nil ? notice.title : notice.detail) + 18 + 8 <= content,
                               "power and accessory labels fit beside their icon without truncation in \(language)")
                        expect(notice.level != nil || width(notice.detail) <= content,
                               "connection status and charge percentage fit the opposite wing in \(language)")
                        let size = geometry.noticeSize(wingWidth: notice.preferredWingWidth)
                        expect(size.width == wing * 2 + geometry.cameraWidth && size.height == height
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
                expect(notice.preferredWingWidth == 112, "level changes keep a stable compact width")
            }
        }
        let long = NotchNotice(event: .accessory, title: String(repeating: "Device ", count: 100),
                               detail: "Connected", symbol: "headphones")
        expect(long.preferredWingWidth <= 240 && long.accessibilityText.contains(long.title),
               "very long device names have bounded visual width and retain their full accessible name")
        let narrow = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 640, height: 480),
                                   safeAreaTop: 32, cameraWidth: 210)
        let size = narrow.noticeSize(wingWidth: long.preferredWingWidth)
        expect(size.width <= narrow.screen.width - 24 && size.height == narrow.menuBarHeight,
               "long device names cannot push a notice past a narrow display")
        let notification = NotchNotice(event: .systemNotification, title: "Notice", detail: "Body", symbol: "bell",
            notification: NotchNotificationContent(app: "App", title: "Notice", subtitle: "", body: "Body"))
        expect(notification.preferredWingWidth == 190, "mirrored notifications keep their existing text layout")
    }

    private static func simulatedMenuBoundsContracts(expect: (Bool, String) -> Void) {
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
                    expect(bar.contains(geometry.frame(for: size)),
                           "every closed or compact simulated surface stays entirely within the actual menu bar")
                }
                expect(abs(geometry.cameraWidth / geometry.cameraHeight - 180.0 / 32) < 0.001,
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
                expect(!occupied.contains(where: { $0.intersects(crowded.frame(for: size)) }),
                       "simulated idle, music and timer wings never cover measured neighboring menus")
            }
        }
    }

    private static func simulatedDisplayContracts(expect: (Bool, String) -> Void) {
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
                    expect(!geometry.isNotched && geometry.cameraWidth == physical.cameraWidth
                           && geometry.cameraHeight == physical.cameraHeight
                           && geometry.safeContentTop == physical.safeContentTop,
                           "a simulated notch keeps the physical profile and content clearance without claiming hardware exists")
                    expect(geometry.restingSize(showsContent: false) == physical.restingSize(showsContent: false)
                           && geometry.notice == physical.notice && geometry.expanded == physical.expanded,
                           "idle, feedback and expanded simulations use the same proportions as a physical cutout")
                    let sizes = [geometry.restingSize(showsContent: false), geometry.collapsed, geometry.peek,
                                 geometry.notice, geometry.noticeSize(wingWidth: 190)]
                        + NotchModule.allCases.map { geometry.expandedSize(module: $0) }
                        + [geometry.sectionPickerSize(count: NotchModule.allCases.count)]
                    for size in sizes {
                        let positioned = geometry.frame(for: size)
                        expect(screen.contains(positioned) && positioned.midX == screen.midX
                               && positioned.maxY == screen.maxY,
                               "every simulated presentation grows directly from the screen edge and stays within its display")
                    }
                    for activity in [geometry, geometry.compactMusicGeometry,
                                     geometry.compactTimerGeometry(showsDownloads: false),
                                     geometry.compactTimerGeometry(showsDownloads: true)] {
                        let positioned = activity.frame(for: activity.compactActivitySize)
                        let activation = activity.activationArea(in: activity.compactActivitySize, hasHeader: false,
                                                                 compactActivity: true)
                        expect(positioned.maxY == screen.maxY && screen.contains(positioned)
                               && (activity.compactActivityWingWidth == 0 || activity.compactActivityWingWidth >= 44)
                               && activity.compactActivityContentHeight == barHeight,
                               "simulated activities keep complete measured wings or just the cutout, within the menu bar")
                        expect(activity.compactActivityCameraGap == physical.cameraWidth && !activity.compactActivityUsesFooter
                               && activation.width == physical.cameraWidth
                               && activation.midX == activity.compactActivitySize.width / 2,
                               "the simulated camera opens the island while its neighboring controls keep their own click targets")
                    }
                }
            }
        }
    }

    private static func menuSpaceReuseContracts(expect: (Bool, String) -> Void) {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let previous = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 24, compactSideRoom: 0)
        let largerBar = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 32)
        let menu = CGRect(x: screen.midX + previous.cameraWidth / 2 + 4, y: screen.maxY - 24, width: 80, height: 24)
        expect(NotchMenuBarLayout.sideRoom(screen: screen, cameraWidth: previous.cameraWidth, barHeight: 24, occupied: [menu]) != nil
               && NotchMenuBarLayout.sideRoom(screen: screen, cameraWidth: largerBar.cameraWidth, barHeight: 32, occupied: [menu]) == nil,
               "a taller simulated cutout can occupy a menu that was clear before the bar changed")
        expect(!largerBar.hasSameMenuBar(as: previous),
               "a changed menu bar cannot reuse clearance from a narrower simulated camera")
        let moved = NotchGeometry(screen: screen.offsetBy(dx: -1440, dy: 900), safeAreaTop: 0, cameraWidth: 0)
        expect(!moved.hasSameMenuBar(as: previous), "another display cannot reuse the previous menu measurement")
        for layout in NotchSize.allCases {
            let resized = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: layout)
            expect(resized.hasSameMenuBar(as: previous),
                   "changing the expanded size preserves valid menu clearance without flicker")
        }
    }

    private static func menuBarHeightContracts(expect: (Bool, String) -> Void) {
        var measurements = NotchMenuBarMeasurements()
        let screen = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        func read(_ id: UInt32, gap: CGFloat, frame: CGRect = CGRect(x: -1440, y: -900, width: 1440, height: 900),
                  scale: CGFloat = 2, fallback: CGFloat = 22) -> CGFloat {
            measurements.height(displayID: id, frame: frame, visibleTop: frame.maxY - gap,
                                scale: scale, statusBarThickness: fallback)
        }
        for height: CGFloat in [16, 22, 24, 28, 30, 32, 33, 37, 64] {
            expect(read(1, gap: height) == height, "the selected display's current visible bar supplies its height")
            let geometry = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: height)
            expect(geometry.collapsed.height == height && geometry.compactMusicGeometry.compactActivitySize.height == height,
                   "the simulated cutout and music strip stay within the measured bar")
            for gap: CGFloat in [0, 1, -10, 15, 65, 600, .nan, .infinity] {
                expect(read(1, gap: gap) == height, "hiding or an unavailable reading retains this display's measured height")
            }
        }
        expect(read(1, gap: 24) == 24 && read(2, gap: 33) == 33,
               "displays with different menu bars keep independent measurements")
        for _ in 0..<3 {
            expect(read(1, gap: 0) == 24 && read(2, gap: 0) == 33,
                   "switching displays and changing other preferences while bars are hidden preserves both heights")
        }
        expect(read(3, gap: 0) == 22 && read(3, gap: 0, fallback: .nan) == 24,
               "a display first seen with a hidden bar uses a safe native fallback, never another display's height")
        expect(read(3, gap: 30) == 30 && read(3, gap: 0) == 30,
               "revealing a previously unknown bar replaces the fallback and survives hiding again")
        expect(read(1, gap: 0, frame: screen.offsetBy(dx: 1440, dy: 1800)) == 24,
               "moving a display in the arrangement preserves its mode's measured height")
        expect(read(1, gap: 0, scale: 1) == 22 && read(1, gap: 0, scale: 2) == 22,
               "a scale change invalidates the old height even after changing back while the bar stays hidden")
        _ = read(1, gap: 30)
        expect(read(1, gap: 0, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)) == 22,
               "a new screen resolution cannot inherit a previous mode's height")
        measurements.retainDisplays([1, 3])
        expect(read(2, gap: 0) == 22 && read(3, gap: 0) == 30,
               "disconnecting a display drops its history without affecting the remaining display")
        expect(read(0, gap: 37) == 37 && read(0, gap: 0) == 22,
               "an unknown display identity can use its current reading but cannot share remembered measurements")
        _ = read(1, gap: 30, scale: .nan)
        expect(read(1, gap: 0) == 22, "an invalid display mode cannot seed remembered height")
        var fresh = NotchMenuBarMeasurements()
        for invalid: CGFloat in [0, -1, 15, 65, .nan, .infinity] {
            expect(fresh.height(displayID: 1, frame: screen, visibleTop: screen.maxY,
                                scale: 2, statusBarThickness: invalid) == 24,
                   "invalid fallback heights never escape the safe range")
        }
    }

    private static func musicLabelContracts(expect: (Bool, String) -> Void) {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for height: CGFloat in [16, 22, 24, 28, 30, 33, 37, 64] {
            for room: CGFloat? in [nil, 0, 43, 44, 56, 0, 56] {
                let geometry = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0,
                                             menuBarHeight: height, compactSideRoom: room).compactMusicGeometry
                let contentLeft = geometry.compactActivityWingWidth + geometry.compactMusicLabelInset
                let bottomCurveEnd = min(NotchLayout.shoulder, height * 0.28) + min(28, height / 2)
                expect(contentLeft >= bottomCurveEnd + 4,
                       "center text clears the entire curved silhouette even after the music wings disappear")
                expect(geometry.compactActivityCameraGap - geometry.compactMusicLabelInset * 2 >= 50,
                       "protecting the curves still leaves useful room for a truncated track name")
                if geometry.compactActivityWingWidth >= 44 {
                    expect(geometry.compactMusicLabelInset == 4,
                           "available music wings preserve the original center text budget")
                }
            }
        }
    }

    static func run(expect: (Bool, String) -> Void) {
        noticeLayoutContracts(expect: expect)
        simulatedMenuBoundsContracts(expect: expect)
        simulatedDisplayContracts(expect: expect)
        menuSpaceReuseContracts(expect: expect)
        menuBarHeightContracts(expect: expect)
        musicLabelContracts(expect: expect)
        NotchHoverTests.run(expect: expect)
        NotchScreenEdgeClickTests.run(expect: expect)
        NotchPresentationRefreshContract.run(expect: expect)
        NotchScreenRefreshContract.run(expect: expect)
        NotchDestinationContract.run(expect: expect)
        NotchMusicVisibilityTests.run(expect: expect)
        NotchUpdateTests.run(expect: expect)
        NotchCaptureKeyboardTests.run(expect: expect)
        NotchDownloadProgressTests.run(expect: expect)
        NotchSliderEditingTests.run(expect: expect)
        NotchFileToolsTests.run(expect: expect)
        calendarContracts(expect: expect)
        NotchNotificationTests.run(expect: expect)
        NotchNotificationReaderTests.run(expect: expect)
        NotchGestureTests.run(expect: expect)
        NotchKeyboardLightTests.run(expect: expect)
        NotchActivityTests.run(expect: expect)
        NotchMusicExtrasTests.run(expect: expect)
        let suite = "com.vorssaint.tests.notch"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        // Registration defaults are shared across suites within the process.
        // Keep this fixture inside its own persistent domain so migration
        // tests later in the harness still see a genuinely untouched setup.
        for (key, value) in Defaults.registeredDefaults
        where key.hasPrefix("notch") || key == DefaultsKey.clipboardHistoryEnabled
            || key == DefaultsKey.brightnessControlEnabled {
            defaults.set(value, forKey: key)
        }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        expect(!NotchSupport.isEnabled(in: defaults), "notch is opt-in")
        expect(NotchSupport.controls(in: defaults) == [.volume, .brightness, .music, .mixer, .keepAwake, .timer, .calendar],
               "home defaults prioritize playback and everyday system controls")
        defaults.set(false, forKey: DefaultsKey.notchTimerEnabled)
        defaults.set(false, forKey: DefaultsKey.notchCalendarEnabled)
        expect(!NotchSupport.controls(in: defaults).contains(.timer)
               && !NotchSupport.controls(in: defaults).contains(.calendar),
               "explicitly disabled utilities stay absent from home controls")
        defaults.set(true, forKey: DefaultsKey.notchTimerEnabled)
        defaults.set(true, forKey: DefaultsKey.notchCalendarEnabled)
        defaults.set("music,timer,calendar", forKey: DefaultsKey.notchHiddenModules)
        expect(!NotchSupport.controls(in: defaults).contains(.music)
               && !NotchSupport.controls(in: defaults).contains(.timer)
               && !NotchSupport.controls(in: defaults).contains(.calendar),
               "home controls respect hidden destinations")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        let homeGeometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956), safeAreaTop: 32, cameraWidth: 180)
        expect(homeGeometry.expandedSize(module: .controls, controlsHaveMusic: true).height
               - homeGeometry.expandedSize(module: .controls).height == NotchLayout.musicControlHeight + 18,
               "home playback reserves its actual height and spacing")

        expect(!NotchSupport.routesAppPanel(in: defaults) && !NotchSupport.routesQuickPanel(in: defaults)
               && !NotchSupport.routesShelf(in: defaults) && !NotchSupport.routesCaptureControls(in: defaults)
               && !NotchSupport.routesClipboardWindow(in: defaults),
               "separate panels remain the default until the notch is explicitly enabled")
        expect(NotchSupport.showsInCaptures(in: defaults), "notch appears in screenshots and recordings by default")
        defaults.set(true, forKey: DefaultsKey.notchHideInCaptures)
        expect(NotchSupport.showsInCaptures(in: defaults), "the old inverse default cannot silently hide the notch")
        defaults.set(false, forKey: DefaultsKey.notchShowInCaptures)
        expect(!NotchSupport.showsInCaptures(in: defaults), "capture visibility remains an explicit opt-out")
        defaults.set(true, forKey: DefaultsKey.notchShowInCaptures)
        expect(NotchEvent.allCases.allSatisfy { !NotchSupport.routes($0, in: defaults) },
               "disabled notch cannot consume any existing presentation")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        expect(NotchSupport.isEnabled(in: defaults), "master switch enables notch")
        expect(NotchSupport.usesHapticFeedback(in: defaults), "the enabled island starts with tactile feedback")
        defaults.set(false, forKey: DefaultsKey.notchHapticFeedback)
        expect(!NotchSupport.usesHapticFeedback(in: defaults), "tactile feedback can still be turned off independently")
        defaults.set(true, forKey: DefaultsKey.notchHapticFeedback)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        expect(!NotchSupport.usesHapticFeedback(in: defaults) && !NotchSupport.routesAppPanel(in: defaults)
               && !NotchSupport.routesQuickPanel(in: defaults) && !NotchSupport.routesShelf(in: defaults),
               "turning the notch off restores separate panels and suppresses tactile feedback")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        expect(NotchSupport.usesHapticFeedback(in: defaults), "disabling the notch preserves the user's tactile preference")
        expect(NotchSupport.idleContent(in: defaults) == .music, "a new island shows playing music at rest")
        expect(defaults.string(forKey: DefaultsKey.notchSize) == NotchSize.spacious.rawValue
               && defaults.bool(forKey: DefaultsKey.notchOpenOnHover)
               && defaults.bool(forKey: DefaultsKey.notchHoverExpands),
               "a new island starts spacious and expands on hover")
        expect(!defaults.bool(forKey: DefaultsKey.notchHideUntilHover), "hidden hover is opt-in")
        expect(defaults.double(forKey: DefaultsKey.notchHoverDelay) == 0.25,
               "hover activation defaults to a deliberate quarter-second pause")
        for value in [0.10, 0.25, 0.65, 1.0] {
            expect(NotchSupport.sanitizedHoverDelay(value) == value, "valid hover activation times are preserved")
        }
        expect(NotchSupport.sanitizedHoverDelay(-1) == 0.10
               && NotchSupport.sanitizedHoverDelay(9) == 1.0,
               "hover activation times stay within usable bounds")
        expect([Double.nan, .infinity, -.infinity].allSatisfy { NotchSupport.sanitizedHoverDelay($0) == 0.25 },
               "non-finite hover activation times fall back to the default")
        expect(NotchSupport.routesAppPanel(in: defaults) && NotchSupport.routesQuickPanel(in: defaults)
               && NotchSupport.routesClipboardWindow(in: defaults) && NotchSupport.routesShelf(in: defaults)
               && NotchSupport.routesCaptureControls(in: defaults),
               "enabling a fresh island routes available panels into it")
        let initialLayout = NotchQuickAccessConfiguration.current(in: defaults)
        expect(initialLayout.buttons.filter { $0.side == .left }.compactMap(\.action) == [.explore, .module(.timer)]
               && initialLayout.buttons.filter { $0.side == .right }.compactMap(\.action) == [.settings, .module(.mixer)]
               && initialLayout.buttons.filter { $0.side == .bottom }.compactMap(\.action) == [.module(.music)],
               "a fresh layout places Explore and Timer left, Settings and Mixer right, and music below")
        expect(initialLayout == NotchQuickAccessConfiguration.current(in: defaults),
               "default buttons keep stable identities across preference refreshes")
        defaults.set(false, forKey: AppFeature.mixer.availabilityKey)
        defaults.set(false, forKey: AppFeature.notchTimer.availabilityKey)
        expect(NotchQuickAccessConfiguration.current(in: defaults).actions == [.explore, .settings, .module(.music)]
               && !NotchQuickAction.module(.mixer).isAvailable(in: defaults)
               && !NotchQuickAction.control(.mixer).isAvailable(in: defaults),
               "uninstalled utilities leave no default buttons or available mixer actions")
        expect(NotchQuickAccessConfiguration.stored(in: defaults) == initialLayout,
               "uninstalling a utility preserves its configured position")
        defaults.set(true, forKey: AppFeature.mixer.availabilityKey)
        defaults.set(true, forKey: AppFeature.notchTimer.availabilityKey)
        expect(NotchQuickAccessConfiguration.current(in: defaults) == initialLayout,
               "reinstalled utilities return to their original positions")
        defaults.set("right", forKey: DefaultsKey.notchQuickAccessSide)
        expect(NotchQuickAccessConfiguration.stored(in: defaults) == .init(side: .right, actions: [.explore, .settings]),
               "a saved legacy side retains the former Settings companion")
        defaults.set("", forKey: DefaultsKey.notchQuickAccessSecond)
        expect(NotchQuickAccessConfiguration.stored(in: defaults) == .init(side: .right, actions: [.explore]),
               "an explicitly empty legacy action stays empty under the new defaults")
        defaults.removeObject(forKey: DefaultsKey.notchQuickAccessSide)
        defaults.removeObject(forKey: DefaultsKey.notchQuickAccessSecond)
        expect(NotchSupport.watchesMusicActivity(in: defaults), "enabled music activity can detect playback while the panel is closed")
        expect(NotchSupport.showsMusicActivity(isPlaying: true, in: defaults)
               && !NotchSupport.showsMusicActivity(isPlaying: false, in: defaults),
               "automatic music presentation requires active playback and clears on pause or stop")
        defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
        expect(!NotchSupport.showsMusicActivity(isPlaying: true, in: defaults), "automatic music presentation can be disabled")
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        expect(NotchSupport.visibleIdleContent(isPlaying: false, in: defaults) == .none
               && NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .none,
               "idle music cannot bypass disabled automatic music presentation")
        expect(NotchSupport.idleContent(in: defaults) == .music,
               "disabling automatic music preserves the user's saved resting choice")
        defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
        expect(NotchSupport.visibleIdleContent(isPlaying: false, in: defaults) == .none
               && NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .music,
               "re-enabling automatic music restores the selected music only during playback")
        let idleGeometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                        safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 100)
        expect(idleGeometry.restingSize(showsContent: NotchSupport.visibleIdleContent(isPlaying: false, in: defaults) != .none)
               == CGSize(width: 180, height: 32),
               "stopped idle music shrinks to the physical camera without reserving empty side space")
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set(true, forKey: DefaultsKey.notchShowPlayingMusic)
        expect(!NotchSupport.watchesMusicActivity(in: defaults)
               && !NotchSupport.showsMusicActivity(isPlaying: true, in: defaults)
               && NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .none,
               "Nothing at rest suppresses playing music and its background observer without disabling the island")
        expect(NotchSupport.isEnabled(in: defaults) && NotchSupport.modules(in: defaults).contains(.music),
               "Nothing at rest keeps the island and its on-demand music section available")
        defaults.set(NotchIdleContent.music.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set("music", forKey: DefaultsKey.notchHiddenModules)
        expect(!NotchSupport.watchesMusicActivity(in: defaults)
               && NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .none,
               "hidden music cannot keep an activity observer or resting content")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        defaults.set(true, forKey: DefaultsKey.notchMusicActivity)
        expect(NotchSupport.idleContent(in: defaults) == .none
               && !NotchSupport.showsMusicActivity(isPlaying: true, in: defaults),
               "legacy music preference cannot populate a newly empty idle surface")
        defaults.set(NotchIdleContent.battery.rawValue, forKey: DefaultsKey.notchIdleContent)
        expect(NotchSupport.visibleIdleContent(isPlaying: false, in: defaults) == .battery
               && NotchSupport.showsMusicActivity(isPlaying: true, in: defaults),
               "battery at rest preserves automatic music while playing")
        defaults.set(false, forKey: DefaultsKey.notchShowPlayingMusic)
        expect(NotchSupport.visibleIdleContent(isPlaying: true, in: defaults) == .battery
               && !NotchSupport.showsMusicActivity(isPlaying: true, in: defaults),
               "disabling automatic music leaves the selected battery visible during playback")
        defaults.set(false, forKey: AppFeature.monitorPower.availabilityKey)
        expect(NotchSupport.idleContent(in: defaults) == .none, "unavailable battery cannot appear while idle")
        defaults.set(true, forKey: AppFeature.monitorPower.availabilityKey)
        defaults.set("clock", forKey: DefaultsKey.notchIdleContent)
        expect(NotchSupport.visibleIdleContent(isPlaying: false, in: defaults) == .none,
               "the retired clock falls back to nothing, including restored settings")
        defaults.set("controls", forKey: DefaultsKey.notchIdleContent)
        expect(NotchSupport.idleContent(in: defaults) == .none,
               "the retired controls idle option falls back to nothing")
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        expect(NotchSupport.modules(in: defaults).contains(.mixer), "the full mixer has a direct destination")
        defaults.set(false, forKey: AppFeature.mixer.availabilityKey)
        expect(!NotchSupport.modules(in: defaults).contains(.mixer)
               && !NotchSupport.controls(in: defaults).contains(.volume), "mixer availability gates its module and volume control")
        defaults.set(true, forKey: AppFeature.mixer.availabilityKey)
        defaults.set("panel,panel,unknown,speedTest", forKey: DefaultsKey.notchControlOrder)
        defaults.set("volume,screenshot", forKey: DefaultsKey.notchHiddenControls)
        let controls = NotchSupport.controls(in: defaults)
        expect(controls.first == .panel && Set(controls).count == controls.count,
               "shortcut ordering tolerates duplicate and obsolete identifiers")
        expect(!controls.contains(.volume) && !controls.contains(.screenshot), "individual controls can be hidden")
        defaults.set("mixer,commandBar", forKey: DefaultsKey.notchHiddenControls)
        defaults.set("", forKey: DefaultsKey.notchControlOrder)
        let allModules = NotchModule.allCases
        expect(Set(allModules.map(\.shortcutKey)).count == allModules.count,
               "every section has a unique direct shortcut, including destinations after the ninth")
        for module in allModules {
            expect(NotchSupport.moduleShortcut(module.shortcutKey, modules: allModules.reversed()) == module
                   && NotchSupport.moduleShortcut(module.shortcutKey.uppercased(), modules: allModules) == module,
                   "direct section shortcuts remain stable across ordering and letter case")
            expect(NotchSupport.moduleShortcut(module.shortcutKey, modules: allModules.filter { $0 != module }) == nil,
                   "hidden or unavailable sections cannot be opened by their shortcut")
        }
        for characters in ["", "0", "9", "10", "cc", "-1", " "] {
            expect(NotchSupport.moduleShortcut(characters, modules: allModules) == nil,
                   "unassigned keys cannot navigate")
        }
        expect(NotchSupport.moduleShortcut("c", modules: []) == nil,
               "direct shortcuts tolerate an empty gallery")
        var reached = Set<NotchModule>()
        var current: NotchModule? = allModules.first
        for _ in allModules {
            if let current { reached.insert(current) }
            current = NotchSupport.adjacentModule(to: current, modules: allModules, backwards: false)
        }
        expect(reached == Set(allModules) && current == allModules.first,
               "keyboard cycling reaches every section and wraps without a nine-item limit")
        expect(NotchSupport.adjacentModule(to: allModules.first, modules: allModules, backwards: true) == allModules.last
               && NotchSupport.adjacentModule(to: .camera, modules: [.files], backwards: true) == .files
               && NotchSupport.adjacentModule(to: nil, modules: [], backwards: false) == nil,
               "reverse cycling, removed selections and an empty gallery have safe destinations")
        expect(NotchSupport.filteredModules([.controls, .music, .files], query: "  MÚSＩCA  ", title: {
            $0 == .music ? "Música" : "Arquivos"
        }) == [.music], "gallery search ignores accents, letter case, character width and surrounding spaces")
        expect(NotchSupport.filteredModules([.files, .controls], query: "arquivo novo", title: {
            $0 == .files ? "Novo arquivo" : "Controles"
        }) == [.files], "gallery search matches every word independently of their order")
        expect(NotchSupport.filteredModules(allModules, query: "", title: { $0.rawValue }) == allModules
               && NotchSupport.filteredModules(allModules, query: "unmatched", title: { $0.rawValue }).isEmpty,
               "empty queries preserve configured ordering and unmatched queries have no action")
        expect(!NotchSupport.closesOnPointerExit(expanded: true, peeking: false, openedByHover: false),
               "menu bar and keyboard openings survive a pointer outside the notch")
        expect(NotchSupport.closesOnPointerExit(expanded: true, peeking: false, openedByHover: true)
               && NotchSupport.closesOnPointerExit(expanded: false, peeking: true, openedByHover: false),
               "hover presentations still close when the pointer leaves")
        var hover = NotchHoverState()
        hover.close(pointerInside: true)
        for _ in 0..<4 { hover.update(pointerInside: true) }
        expect(hover.suppressed, "closing under the pointer survives repeated hover events caused by resizing")
        hover.update(pointerInside: false)
        hover.update(pointerInside: true)
        expect(!hover.suppressed, "leaving and returning rearms hover without a timer")
        hover.close(pointerInside: true)
        hover.open()
        expect(!hover.suppressed, "an intentional opening remains possible while hover is suppressed")
        hover.close(pointerInside: false)
        expect(!hover.suppressed, "closing away from the island does not block the next approach")
        let topArea = idleGeometry.activationArea(in: idleGeometry.expanded, hasHeader: true, compactActivity: false)
        let screenTop = CGPoint(x: idleGeometry.screen.midX, y: idleGeometry.screen.maxY)
        expect(idleGeometry.contains(screenTop, in: idleGeometry.collapsed)
               && !idleGeometry.contains(CGPoint(x: screenTop.x, y: screenTop.y + 0.5), in: idleGeometry.collapsed)
               && !idleGeometry.contains(CGPoint(x: idleGeometry.screen.minX, y: screenTop.y), in: idleGeometry.collapsed),
               "hover includes the exact screen top without accepting points above or beside the island")
        hover.close(pointerInside: true)
        hover.update(pointerInside: idleGeometry.contains(screenTop, in: idleGeometry.collapsed))
        expect(hover.suppressed, "the physical screen edge cannot rearm hover after an explicit close")
        expect(topArea.contains(CGPoint(x: idleGeometry.expanded.width / 2, y: 1))
               && topArea.maxY == idleGeometry.safeContentTop,
               "the very top is clickable while section buttons below it keep their own actions")
        let footerGeometry = NotchGeometry(screen: idleGeometry.screen, safeAreaTop: 32, cameraWidth: 180, compactSideRoom: 0)
        expect(footerGeometry.activationArea(in: footerGeometry.compactActivitySize, hasHeader: false, compactActivity: true).maxY
               == footerGeometry.compactActivityTopPadding,
               "top activation does not cover timer and download controls in the footer")
        let plainGeometry = NotchGeometry(screen: idleGeometry.screen, safeAreaTop: 0, cameraWidth: 0, compactSideRoom: 0)
        expect(plainGeometry.activationArea(in: plainGeometry.compactActivitySize, hasHeader: false, compactActivity: true).width == plainGeometry.cameraWidth,
               "the simulated camera leaves the activity controls beside it independently clickable")
        expect(ScreenshotSupport.selectionDimAlpha(notchControls: true, isFrozen: true, isDragging: false) == 0,
               "opening capture controls in the notch does not darken the desktop")
        expect(ScreenshotSupport.selectionDimAlpha(notchControls: true, isFrozen: true, isDragging: true) > 0,
               "dragging a capture region retains visual selection feedback")
        expect(ScreenshotSupport.selectionDimAlpha(notchControls: false, isFrozen: true, isDragging: false) == 0.22,
               "the standalone capture chooser keeps its existing contrast")
        for tool in ScreenCaptureTool.allCases {
            expect(tool.capturesAudio == (tool == .recording),
                   "only screen recording shows microphone and system-audio controls: \(tool.rawValue)")
        }
        expect(!NotchSupport.routes(.clipboard, in: defaults) && !NotchSupport.routes(.capture, in: defaults),
               "notch opt-in does not reveal copied content or move captures")
        defaults.set(true, forKey: DefaultsKey.notchClipboard)
        expect(!NotchSupport.routes(.clipboard, in: defaults), "clipboard event respects the history capture switch")
        defaults.set(true, forKey: DefaultsKey.clipboardHistoryEnabled)
        expect(NotchSupport.routes(.clipboard, in: defaults), "explicit clipboard activity opt-in is honored")
        expect(NotchSupport.routesClipboardWindow(in: defaults), "clipboard opening defaults to the enabled island")
        defaults.set(false, forKey: DefaultsKey.notchClipboardWindow)
        expect(!NotchSupport.routesClipboardWindow(in: defaults), "clipboard can still use its separate window")
        defaults.set(true, forKey: DefaultsKey.notchClipboardWindow)
        defaults.set("clipboard,unknown", forKey: DefaultsKey.notchHiddenModules)
        expect(!NotchSupport.routesClipboardWindow(in: defaults), "hidden clipboard keeps the ordinary history available")
        expect(!NotchSupport.routes(.clipboard, in: defaults), "hidden module cannot leak an activity")
        defaults.set("system,music,music,unknown", forKey: DefaultsKey.notchModuleOrder)
        expect(NotchSupport.modules(in: defaults) == [.system, .music, .controls, .mixer, .captures, .files, .tools, .calendar, .timer, .downloads],
               "module order ignores unknown ids and duplicates, preserving newly added modules")
        expect(NotchSupport.routesShelf(in: defaults) && NotchSupport.revealsShelfDrag(in: defaults),
               "the enabled notch replaces the file destination and reveals active drags")
        defaults.set(false, forKey: DefaultsKey.notchDragReveal)
        expect(NotchSupport.routesShelf(in: defaults) && !NotchSupport.revealsShelfDrag(in: defaults),
               "drag reveal can be disabled without moving the shelf")
        defaults.set(false, forKey: DefaultsKey.notchCaptureControls)
        expect(!NotchSupport.routesCaptureControls(in: defaults), "capture controls retain an independent destination")
        defaults.set(false, forKey: AppFeature.quickLauncher.availabilityKey)
        expect(!NotchSupport.modules(in: defaults).contains(.tools) && !NotchSupport.routesQuickPanel(in: defaults),
               "removing the quick panel also removes its embedded tools and shortcut routing")
        defaults.set(false, forKey: DefaultsKey.notchQuickPanel)
        expect(!NotchSupport.routesQuickPanel(in: defaults), "quick panel shortcut can keep its original destination")
        defaults.set(false, forKey: AppFeature.shelf.availabilityKey)
        expect(!NotchSupport.modules(in: defaults).contains(.files), "unavailable shelf leaves no notch surface")
        defaults.set(false, forKey: AppFeature.notch.availabilityKey)
        expect(!NotchSupport.isEnabled(in: defaults), "hub is stronger than the notch master switch")
        expect(!NotchSupport.usesHapticFeedback(in: defaults), "removing the feature also gates tactile feedback")
        expect(NotchEvent.allCases.allSatisfy { !NotchSupport.routes($0, in: defaults) },
               "hub removal gates every notch event")

        let keys: Set<String> = [DefaultsKey.notchShowPlayingMusic, DefaultsKey.notchShowInCaptures, DefaultsKey.notchIdleContent, DefaultsKey.notchHiddenControls, DefaultsKey.notchControlOrder, DefaultsKey.notchSize, DefaultsKey.notchShelf, DefaultsKey.notchDragReveal,
                                DefaultsKey.notchCustomWidth, DefaultsKey.notchCustomHeight, DefaultsKey.notchHapticFeedback,
                                DefaultsKey.notchCaptureControls, DefaultsKey.notchQuickPanel, DefaultsKey.notchAppPanel,
                                DefaultsKey.notchHoverExpands, DefaultsKey.notchEnabled, DefaultsKey.notchDisplay,
                                DefaultsKey.notchOpenOnHover, DefaultsKey.notchHoverDelay, DefaultsKey.notchHideUntilHover, DefaultsKey.notchHiddenModules,
                                DefaultsKey.notchModuleOrder, DefaultsKey.notchQuickAccessLayout, DefaultsKey.notchQuickAccessSide, DefaultsKey.notchQuickAccessSecond, DefaultsKey.notchQuickAccessThird, DefaultsKey.notchVolume,
                                DefaultsKey.notchBrightness, DefaultsKey.notchBattery,
                                DefaultsKey.notchClipboard, DefaultsKey.notchClipboardWindow, DefaultsKey.notchCapture,
                                DefaultsKey.notchMusicActivity, DefaultsKey.notchHideInCaptures, DefaultsKey.panelControlNotch,
                                AppFeature.notch.availabilityKey]
        expect(SettingsBackupSupport.exportKeys().isSuperset(of: keys), "every notch preference travels in backup")
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
        expect(restored?[DefaultsKey.notchEnabled] as? Bool == true
               && restored?[DefaultsKey.notchDisplay] as? String == "builtIn"
               && restored?[DefaultsKey.notchVolume] as? Bool == false,
               "backup restores notch placement and event choices")
        expect(restored?[DefaultsKey.notchSize] as? String == "custom"
               && restored?[DefaultsKey.notchCustomWidth] as? Double == 390
               && restored?[DefaultsKey.notchCustomHeight] as? Double == 580
               && restored?[DefaultsKey.notchHapticFeedback] as? Bool == true,
               "backup restores custom dimensions and tactile feedback together")
        expect(restored?[DefaultsKey.notchQuickAccessSide] as? String == "right"
               && restored?[DefaultsKey.notchQuickAccessSecond] as? String == "timer"
               && restored?[DefaultsKey.notchQuickAccessThird] as? String == "settings",
               "backup restores both the side and the actions of floating quick access")
        expect(!SettingsBackupSupport.valueLooksRight(DefaultsKey.notchQuickAccessSide, ["right"])
               && !SettingsBackupSupport.valueLooksRight(DefaultsKey.notchQuickAccessSecond, true)
               && !SettingsBackupSupport.valueLooksRight(DefaultsKey.notchQuickAccessThird, 3),
               "legacy layout keys retain string validation after leaving registered defaults")
        defaults.set("unknown", forKey: DefaultsKey.notchQuickAccessSide)
        defaults.set("settings", forKey: DefaultsKey.notchQuickAccessSecond)
        defaults.set("settings", forKey: DefaultsKey.notchQuickAccessThird)
        expect(NotchQuickAccessConfiguration.current(in: defaults) == .init(side: .left, actions: [.explore, .settings]),
               "invalid placement falls back safely and duplicate quick actions are not repeated")
        defaults.set("timer", forKey: DefaultsKey.notchQuickAccessSecond)
        defaults.set("../../unknown", forKey: DefaultsKey.notchQuickAccessThird)
        defaults.set("timer", forKey: DefaultsKey.notchHiddenModules)
        expect(NotchQuickAccessConfiguration.current(in: defaults).actions == [.explore],
               "hidden destinations and unrecognized action identifiers cannot create a floating action")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        for side in [NotchQuickAccessSide.left, .right] {
            let edge: CGFloat = side == .left ? 72 : 632
            for index in 0..<3 {
                let point = NotchQuickAccessLayout.center(index: index, progress: 1, edge: edge, top: 60, side: side)
                expect(NotchQuickAccessLayout.hitTest(point, count: 3, edge: edge, top: 60, side: side),
                       "every visible bubble accepts its own center on either side")
                let gap = CGPoint(x: edge + (side == .left ? -6 : 6), y: point.y)
                expect(!NotchQuickAccessLayout.hitTest(gap, count: 3, edge: edge, top: 60, side: side),
                       "the transparent gap between a bubble and the notch does not claim clicks")
            }
        }
        expect(NotchQuickAccessLayout.hoverRect(count: 0, edge: 72, top: 60, side: .left).isNull,
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
                expect(pathIsCovered, "hover remains continuous through gaps, between buttons and around their edges")
                let outside = CGPoint(x: side == .left ? region.minX - 1 : region.maxX + 1, y: first.y)
                expect(!region.contains(outside), "moving beyond the forgiving hover region still permits closing")
            }
        }
        let legacy = NotchQuickAccessConfiguration.stored(in: defaults)
        expect(legacy == NotchQuickAccessConfiguration.stored(in: defaults),
               "legacy quick-access migration keeps stable identities across refreshes")
        let placements = [NotchQuickButton(action: .explore, side: .left),
                          NotchQuickButton(action: .settings, side: .right),
                          NotchQuickButton(action: .control(.keepAwake), side: .bottom)]
        var layout = NotchQuickAccessConfiguration(buttons: placements)
        defaults.set(layout.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        expect(NotchQuickAccessConfiguration.stored(in: defaults) == layout,
               "the visual layout stores all three edges and direct actions together")
        layout.move(placements[0].id, to: .bottom, before: placements[2].id)
        expect(layout.buttons.first(where: { $0.id == placements[0].id })?.side == .bottom
               && layout.buttons.filter { $0.side == .bottom }.map(\.id) == [placements[0].id, placements[2].id],
               "moving a button preserves its identity and inserts it in the chosen order")
        let crowded = NotchQuickAccessConfiguration(buttons: (0..<12).map { _ in NotchQuickButton(action: .settings, side: .bottom) }).sanitized()
        expect(crowded.buttons.count == 3, "restored layouts cannot overfill an edge")
        var invalidButton = NotchQuickButton(action: .settings, side: .left, label: "  Name\nwith line  ")
        invalidButton.actionID = "unrecognized-action"
        expect(NotchQuickAccessConfiguration(buttons: [invalidButton]).sanitized().buttons.isEmpty,
               "unknown restored actions cannot run")
        let emptyLayout = NotchQuickAccessConfiguration(buttons: [])
        defaults.set(emptyLayout.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        expect(NotchQuickAccessConfiguration.stored(in: defaults).buttons.isEmpty,
               "an intentionally empty layout does not resurrect legacy buttons")
        let recoveredLayout = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [DefaultsKey.notchQuickAccessLayout: layout.encoded]])
        expect(recoveredLayout?[DefaultsKey.notchQuickAccessLayout] as? Data == layout.encoded,
               "backup preserves the visual layout and its stable button identities")
        defaults.removeObject(forKey: DefaultsKey.notchQuickAccessLayout)
        let bottomRegion = NotchQuickAccessLayout.hoverRect(count: 3, edge: 300, top: 150, side: .bottom)
        expect(bottomRegion.contains(CGPoint(x: 204, y: 307)) && bottomRegion.contains(CGPoint(x: 204, y: 364)),
               "bottom buttons retain a continuous forgiving path back to the island")
        expect(AppFeature.notch.settingsDestination.page == .notch, "hub routes to notch settings")
        expect(!FeatureVisibilitySupport.isPageVisible(.notch, isAvailable: { !FeatureVisibilitySupport.features(for: .notch).contains($0) }),
               "notch settings disappear when uninstalled")

        for language in AppLanguage.allCases {
            for child in Mirror(reflecting: FeatureStrings.notch(language)).children {
                let value = child.value as? String ?? ""
                expect(!value.isEmpty && !value.contains("—"),
                       "notch localized text is present and human-readable: \(language) \(child.label ?? "")")
            }
        }

        let frames = [CGRect(x: 0, y: 0, width: 1512, height: 982),
                      CGRect(x: -1920, y: -100, width: 1920, height: 1080),
                      CGRect(x: 100, y: 982, width: 900, height: 1440),
                      CGRect(x: 0, y: 0, width: 640, height: 480)]
        let compact = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210)
        let spacious = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210, layout: .spacious)
        expect(compact.sectionPickerSize(count: 1, searching: true).height < compact.sectionPickerSize(count: allModules.count).height,
               "a short search result shrinks the gallery instead of reserving empty rows")
        expect(compact.contentSize(for: compact.sectionPickerSize(count: 0, searching: true)).height >= 160,
               "an unmatched search still reserves room for recovery guidance")
        let musicBase = compact.expandedSize(module: .music)
        let musicDetails = compact.expandedSize(module: .music, musicExtraHeight: 260)
        expect(musicDetails.width == musicBase.width && musicDetails.height == musicBase.height + 260
               && compact.screen.contains(compact.frame(for: musicDetails)),
               "opening lyrics or the queue adds room while preserving width and screen bounds")
        expect(compact.expanded.width >= 440 && spacious.expanded.width > compact.expanded.width,
               "the standard notch has room for side-by-side controls while spacious remains available")
        let idleMusic = compact.expandedSize(module: .music, musicHasContent: false)
        expect(idleMusic.height < compact.expandedSize(module: .music).height
               && compact.contentSize(for: idleMusic).height >= 130,
               "empty music keeps its message and volume controls without reserving a full player")
        let fullControls = compact.expandedSize(module: .controls, controlRows: 2, sliderCount: 2)
        let fewerShortcuts = compact.expandedSize(module: .controls, controlRows: 1, sliderCount: 2)
        let onlyShortcuts = compact.expandedSize(module: .controls, controlRows: 1, sliderCount: 0)
        expect(fullControls.height > fewerShortcuts.height && fewerShortcuts.height > onlyShortcuts.height,
               "hiding shortcuts or sliders removes their unused vertical space")
        expect(compact.contentSize(for: compact.expandedSize(module: .controls, controlRows: 0, sliderCount: 0)).height >= 160,
               "hiding every control leaves enough room for the empty-state guidance")
        for width in [360.0, 480.0, 600.0] {
            let geometry = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210,
                                         layout: .custom, customWidth: width, customHeight: 640)
            for shortcuts in 1...8 {
                let rows = (shortcuts + geometry.controlColumns - 1) / geometry.controlColumns
                for sliders in 0...2 {
                    let size = geometry.expandedSize(module: .controls, controlRows: rows, sliderCount: sliders)
                    let levels = geometry.hasSideBySideLevels ? min(sliders, 1) : sliders
                    let requiredHeight = CGFloat(levels) * 94 + CGFloat(rows) * 52
                        + CGFloat(rows - 1) * 8 + CGFloat(levels) * 18
                    let availableHeight = 640 - geometry.safeContentTop - NotchLayout.chromeHeight
                    expect(geometry.contentSize(for: size).height == min(requiredHeight, availableHeight),
                           "action rows fit or receive a bounded scroll viewport at narrow widths and odd counts")
                    expect(frames[0].contains(geometry.frame(for: size)),
                           "the full controls surface stays inside the display")
                }
            }
        }
        for frame in frames {
            for width in [360.0, 470.0, 600.0] {
                for height in [400.0, 520.0, 640.0] {
                    let custom = NotchGeometry(screen: frame, safeAreaTop: 32, cameraWidth: 210,
                                               layout: .custom, customWidth: width, customHeight: height)
                    for module in NotchModule.allCases {
                        let size = custom.expandedSize(module: module)
                        expect(size.width == min(width, frame.width - 24 - NotchQuickAccessLayout.gutter * 2) && size.height <= height
                               && frame.contains(custom.frame(for: size)),
                               "custom dimensions fit every module and respect the display and height limit")
                    }
                    for count in [0, 1, 9, allModules.count] {
                        let picker = custom.sectionPickerSize(count: count)
                        expect(picker.width == custom.expandedWidth && picker.height <= height
                               && frame.contains(custom.frame(for: picker)),
                               "gallery dimensions respect the display and the user's height limit at every item count")
                    }
                    expect(custom.expandedSize(module: .clipboard).height == min(height, frame.height - 48),
                           "long lists use the chosen height without overflowing a shorter display")
                    expect(custom.contentSize(for: custom.expandedSize(module: .music)).height >= 212,
                           "custom sizes retain space for music and its essential volume controls")
                }
            }
        }
        for invalid in [Double.nan, .infinity, -.infinity, -200, 0, 1e9] {
            let custom = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 210, layout: .custom,
                                       customWidth: invalid, customHeight: invalid)
            expect(NotchSize.widthRange.contains(custom.customWidth) && NotchSize.heightRange.contains(custom.customHeight)
                   && frames[0].contains(custom.frame(for: custom.expandedSize(module: .tools))),
                   "invalid imported dimensions cannot create an unbounded or off-screen panel")
        }
        let wideCamera = NotchGeometry(screen: frames[0], safeAreaTop: 32, cameraWidth: 390, layout: .custom,
                                       customWidth: 360)
        expect(wideCamera.expanded.width > wideCamera.cameraWidth,
               "a requested narrow panel still clears a wider physical camera")
        for frame in frames {
            for notch in [false, true] {
                let geometry = NotchGeometry(screen: frame, safeAreaTop: notch ? 32 : 0,
                                             cameraWidth: notch ? 210 : 0)
                for size in [geometry.collapsed, geometry.notice, geometry.noticeSize(wingWidth: 190), geometry.expanded] {
                    let positioned = geometry.frame(for: size)
                    expect(frame.contains(positioned), "notch fits displays in every coordinate quadrant")
                    expect(positioned.midX == frame.midX, "notch stays centered while morphing")
                    expect(positioned.maxY == frame.maxY,
                           "top edge does not jump across presentation states")
                }
                expect(geometry.musicWingWidth * 2 + geometry.musicCameraGap == geometry.musicStrip.width,
                       "horizontal metadata uses equal wings around the camera")
                expect(geometry.frame(for: geometry.musicStrip).maxY == frame.maxY,
                       "the lateral music strip remains attached to the same top edge")
                expect(geometry.contentSize(for: geometry.expandedSize(module: .music)).height >= 212,
                       "compact music reserves room for metadata, transport, progress and volume together")
                let quiet = geometry.restingSize(showsContent: false)
                expect(quiet.width == geometry.cameraWidth && quiet.height <= geometry.menuBarHeight,
                       "empty idle does not reserve wings or a footer for unsolicited widgets")
                expect(geometry.contentSize(for: geometry.expanded).height
                       == geometry.expanded.height - geometry.safeContentTop - 36 - 18 - 22,
                       "content reserves one top navigation row, its spacing and the bottom inset")
                expect(geometry.safeContentTop > geometry.cameraHeight, "controls always clear the physical camera")
                expect(geometry.appPanelSize.width > 0 && geometry.appPanelSize.height >= 176
                       && geometry.appPanelSize.height < geometry.expandedSize(module: .tools).height,
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
                    expect(position.maxY == frame.maxY && position.midX == frame.midX && frame.contains(position),
                           "the animation's backing window stays inside the display and attached to its top center")
                    expect(envelope.width >= geometry.notice.width && envelope.height >= geometry.notice.height
                           && envelope.width >= target.width && envelope.height >= target.height,
                           "the backing window can reveal either endpoint without resizing each frame")
                    expect(NotchMotion.envelope(from: envelope, to: geometry.collapsed) == envelope,
                           "an interrupted closing retains its backing area until the silhouette settles")
                }
                expect(geometry.peek.height < geometry.expanded.height / 3,
                       "hover reveals a small target instead of the entire panel")
            }
        }
        let menuScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let freeRoom = NotchMenuBarLayout.sideRoom(screen: menuScreen, cameraWidth: 180, barHeight: 32,
            occupied: [CGRect(x: 0, y: 924, width: 610, height: 32), CGRect(x: 950, y: 924, width: 520, height: 32)])
        expect(freeRoom == 27, "compact wings stop before the app menu, including its spacing")
        expect(NotchMenuBarLayout.sideRoom(screen: menuScreen, cameraWidth: 180, barHeight: 32,
            occupied: [CGRect(x: 630, y: 924, width: 60, height: 32)]) == nil,
               "occupied camera space cannot be treated as a free menu gap")
        let constrained = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                        menuBarHeight: 24, compactSideRoom: freeRoom)
        expect(constrained.collapsed.height == 32 && constrained.musicStrip.height == 32,
               "quiet idle and the lateral strip keep the menu bar's height")
        expect(constrained.restingWingWidth == 0,
               "an indicator is omitted when there is not enough room to render it intact")
        let roomy = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                 menuBarHeight: 24, compactSideRoom: 100)
        let notificationSize = roomy.noticeSize(wingWidth: 190)
        expect(notificationSize.height == roomy.menuBarHeight && roomy.notice.height == notificationSize.height
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
                        expect(size.height == geometry.menuBarHeight
                               && geometry.frame(for: size).maxY == frame.maxY,
                               "feedback preserves the same camera clearance on physical and simulated notches")
                        expect(wings > 0 && wings * 2 + geometry.noticeCameraGap == size.width,
                               "notice wings exactly fill their horizontal surface without entering the camera gap")
                        expect(geometry.noticeCameraGap == geometry.cameraWidth,
                               "a simulated camera retains the same central gap as a physical camera")
                    }
                }
            }
        }
        let idle = roomy.restingSize(showsContent: false)
        expect(NotchMotion.duration(from: idle, to: roomy.notice)
               == NotchMotion.duration(from: idle, to: roomy.expanded),
               "horizontal reveals use the opening curve even when their height stays unchanged")
        expect(NotchMotion.duration(from: roomy.notice, to: idle)
               < NotchMotion.duration(from: idle, to: roomy.notice),
               "horizontal dismissal remains quicker than opening")
        let compactMusic = roomy.compactMusicGeometry
        expect(compactMusic.compactActivityWingWidth == 56
               && compactMusic.compactActivityCameraGap == roomy.cameraWidth
               && compactMusic.compactActivitySize.width == roomy.cameraWidth + 112,
               "compact music reserves full cover wings outside the physical camera")
        for available: CGFloat in [0, 27, 43, 44, 45, 55, 56, 100, .nan, .infinity] {
            var tight = roomy
            tight.compactSideRoom = available
            let music = tight.compactMusicGeometry
            expect(!music.compactActivityUsesFooter && music.compactActivitySize.height == roomy.menuBarHeight
                   && music.compactActivityTopPadding == 0,
                   "compact music never grows or moves below the menu bar when space changes")
            if available.isFinite && available >= 44 {
                let cover = min(26, music.menuBarHeight - 6, music.compactActivityWingWidth - 20)
                expect(cover >= 24 && cover + 20 <= music.compactActivityWingWidth
                       && music.compactActivityCameraGap == roomy.cameraWidth,
                       "narrow music wings keep a full cover, inner clearance and outer margin beside the camera")
            } else {
                expect(music.compactActivityWingWidth == 0,
                       "unavailable menu space cannot push music into the physical camera or adjacent menus")
            }
        }
        var moreRoom = roomy
        moreRoom.compactSideRoom = 200
        expect(moreRoom.compactMusicGeometry == compactMusic,
               "menu measurements beyond the music width cannot resize the compact presentation")
        expect(constrained.compactMusicGeometry.compactActivitySize.height == constrained.menuBarHeight,
               "crowded music retains the same thin silhouette")
        expect(roomy.musicStrip.width <= 380 && roomy.restingWingWidth == 44,
               "music and idle indicators both respect the same measured menu gap")
        let simulated = NotchGeometry(screen: menuScreen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 22)
        expect(simulated.frame(for: simulated.collapsed).maxY == menuScreen.maxY
               && simulated.cameraHeight == 22 && simulated.cameraWidth == 180 * 22.0 / 32,
               "a simulated cutout has notebook proportions and attaches directly to the screen edge")
        let crowdedRooms: [CGFloat?] = [nil, -1, 0, 27, 43, CGFloat.nan, CGFloat.infinity]
        for available in crowdedRooms {
            let crowded = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                        menuBarHeight: 32, compactSideRoom: available)
            let size = crowded.compactActivitySize
            let window = crowded.frame(for: size)
            let visibleContentTop = window.maxY - crowded.compactActivityTopPadding
            expect(crowded.compactActivityUsesFooter && crowded.compactActivityWingWidth >= 42,
                   "an active timer, paused timer or download has readable content with missing or crowded menu geometry")
            expect(size.width == crowded.cameraWidth && visibleContentTop <= menuScreen.maxY - crowded.cameraHeight,
                   "fallback content stays below the physical camera and its backing window never expands over adjacent menus")
            expect(crowded.compactActivityWingWidth * 2 + crowded.compactActivityCameraGap
                   + crowded.compactActivityHorizontalPadding * 2 == size.width,
                   "both compact actions fit entirely in the fallback strip")
            expect(menuScreen.contains(window) && window.maxY == menuScreen.maxY
                   && crowded.restingSize(showsContent: false).height == 32,
                   "a notched fallback keeps the physical top anchor and does not change quiet idle")
        }
        for available in [CGFloat(44), 80, 100, 180] {
            let lateral = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                        menuBarHeight: 32, compactSideRoom: available)
            expect(!lateral.compactActivityUsesFooter && lateral.compactActivitySize == lateral.musicStrip
                   && lateral.compactActivityCameraGap == lateral.cameraWidth
                   && lateral.compactActivityTopPadding == 0,
                   "confirmed lateral room retains the existing single-row presentation around the camera")
        }
        for frame in frames {
            let external = NotchGeometry(screen: frame, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 22,
                                          compactSideRoom: nil)
            let position = external.frame(for: external.compactActivitySize)
            expect(position.maxY == frame.maxY && frame.contains(position)
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
                expect(geometry.contentSize(for: preview).height == 214 && preview.height < history.height,
                       "a single capture reserves its preview and scroll inset instead of the larger history area in every layout")
                expect(shared.height - preview.height == 58,
                       "sharing adds only the link row and removing it restores the compact preview height")
                expect(geometry.expandedSize(module: .timer, capturePreviewHeight: 210)
                       == geometry.expandedSize(module: .timer),
                       "a retained capture preview does not change another section's height")
                expect(menuScreen.contains(geometry.frame(for: shared)) && shared.height <= customHeight,
                       "the capture preview preserves the screen edge and respects the custom height limit")
            }
        }
        for layout in NotchSize.allCases {
            let fitting = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                        layout: layout, customHeight: 640)
            for measured: CGFloat in [120, 280, 370, 480] {
                let fileMedia = fitting.expandedSize(module: .files, fileMediaHeight: measured)
                expect(fitting.contentSize(for: fileMedia).height == measured,
                       "embedded media fits its measured content without adding a fixed blank area")
            }
        }
        expect(mediaGeometry.expandedSize(module: .music, fileMediaHeight: 600)
               == mediaGeometry.expandedSize(module: .music),
               "an open file-media session does not enlarge unrelated notch modules")
        for height in [400.0, 520.0, 640.0] {
            let custom = NotchGeometry(screen: menuScreen, safeAreaTop: 32, cameraWidth: 180,
                                        layout: .custom, customHeight: height)
            let target = custom.expandedSize(module: .files, fileMediaHeight: 600)
            expect(target.height <= height && menuScreen.contains(custom.frame(for: target)),
                   "the embedded media workspace respects the user's custom height")
        }
        let shortScreen = CGRect(x: 0, y: 0, width: 1024, height: 600)
        let shortMedia = NotchGeometry(screen: shortScreen, safeAreaTop: 0, cameraWidth: 0)
        let shortTarget = shortMedia.expandedSize(module: .files, fileMediaHeight: 600)
        expect(shortTarget.height <= shortScreen.height - 48 && shortScreen.contains(shortMedia.frame(for: shortTarget)),
               "the larger media workspace preserves the screen margin on shorter displays")
        expect(NotchSupport.screenIndex(preference: .automatic, builtIn: [false, true],
                                       notched: [false, true], main: 0) == 1,
               "automatic uses the notched built-in screen even with external main display")
        expect(NotchSupport.screenIndex(preference: .builtIn, builtIn: [false],
                                       notched: [false], main: 0) == 0, "closed-lid mode falls back to an attached screen")
        expect(NotchSupport.screenIndex(preference: .main, builtIn: [], notched: [], main: 0) == nil,
               "no connected displays means no panel")
        expect(NotchSupport.shouldReplace(.volume, with: .brightness), "continuous controls can replace each other")
        expect(!NotchSupport.shouldReplace(.volume, with: .clipboard), "copy does not interrupt a volume adjustment")
        expect(NotchSupport.shouldReplace(.battery, with: .capture), "a capture takes precedence over passive battery status")
        expect(NotchSupport.volumeLevel(current: 0.99, direction: 1, fine: false) == 1
               && NotchSupport.volumeLevel(current: 0, direction: -1, fine: false) == 0,
               "hardware volume steps clamp to audible limits")
        expect(NotchSupport.volumeLevel(current: 0.5, direction: 1, fine: true) == 0.515625,
               "fine volume preserves the system quarter-step")

        var session = NotchSessionState()
        session.locked = true
        session.sleeping = true
        session.sleeping = false
        expect(!session.canPresent, "wake cannot reveal content over a locked screen")
        session.locked = false
        session.displaysSleeping = true
        expect(!session.canPresent, "unlock alone cannot revive sleeping displays")
        session.displaysSleeping = false
        session.onConsole = false
        expect(!session.canPresent, "another login session owns the display")
        session.onConsole = true
        expect(session.canPresent, "presentation resumes after every privacy condition clears")

        expect(NotchArtworkTint.from(red: 0.3, green: 0.3, blue: 0.3) == nil
               && NotchArtworkTint.from(red: 0.5, green: 0.5, blue: 0.55) == nil
               && NotchArtworkTint.from(red: 0, green: 0, blue: 0) == nil,
               "grey and black covers leave the notch without a coloured halo")
        expect(NotchArtworkTint.from(red: .nan, green: 0.5, blue: 0.2) == nil
               && NotchArtworkTint.from(red: 2, green: 0.5, blue: 0.2) == nil
               && NotchArtworkTint.from(red: -1, green: 0.5, blue: 0.2) == nil,
               "impossible pixels cannot produce a halo")
        if let warm = NotchArtworkTint.from(red: 0.8, green: 0.3, blue: 0.25),
           let dim = NotchArtworkTint.from(red: 0.16, green: 0.06, blue: 0.05) {
            expect(abs(warm.red - 0.92) < 0.001 && warm.blue < 0.2 && warm.green < warm.red,
                   "the cover's own hue survives, stretched onto a readable brightness")
            expect(abs(dim.red - warm.red) < 0.001 && abs(dim.green - warm.green) < 0.001
                   && abs(dim.blue - warm.blue) < 0.001,
                   "a dark cover glows as strongly as a bright one of the same hue")
        } else {
            expect(false, "a colourful cover always yields a halo")
        }

        let now = Date(timeIntervalSince1970: 100)
        let reply = Data("{\"pid\":12,\"isPlaying\":false,\"kMRMediaRemoteNowPlayingInfoTitle\":\"A track\",\"kMRMediaRemoteNowPlayingInfoDuration\":180,\"kMRMediaRemoteNowPlayingInfoElapsedTime\":20}".utf8)
        let playback = NotchPlayback.decode(reply, now: now)
        expect(playback?.track.title == "A track" && playback?.isPlaying == false,
               "paused playback retains the track and its resume control")
        expect(playback?.position(at: now.addingTimeInterval(20)) == 20, "paused progress never advances")
        let playingReply = Data(String(decoding: reply, as: UTF8.self).replacingOccurrences(of: "false", with: "true").utf8)
        let playing = NotchPlayback.decode(playingReply, now: now)
        expect(playing?.position(at: now.addingTimeInterval(10)) == 30, "visible music progress follows elapsed time")
        expect(playing?.position(at: now.addingTimeInterval(500)) == 180, "music progress stops at track duration")
        expect(NotchPlayback.decode(Data("{\"pid\":0,\"isPlaying\":false}".utf8)) == nil,
               "empty system playback never fabricates a song")
        let fasterReply = Data(String(decoding: playingReply, as: UTF8.self)
            .replacingOccurrences(of: "\"pid\":12", with: "\"pid\":12,\"kMRMediaRemoteNowPlayingInfoPlaybackRate\":2").utf8)
        expect(NotchPlayback.decode(fasterReply, now: now)?.position(at: now.addingTimeInterval(10)) == 40,
               "spoken content follows its actual playback speed")
        let unchangedArtwork = Data("{\"pid\":12,\"isPlaying\":true,\"artworkUnchanged\":true}".utf8)
        let cachedArtwork = Data([1, 2, 3])
        expect(NotchPlayback.decode(unchangedArtwork, previousArtwork: cachedArtwork)?.track.artworkData == cachedArtwork,
               "metadata-only updates retain the existing artwork without retransmitting it")
        expect(NotchPlayback.decode(playingReply, previousArtwork: cachedArtwork)?.track.artworkData == nil,
               "a new track without artwork clears the old cover")

        let seekableReply = Data(String(decoding: playingReply, as: UTF8.self)
            .replacingOccurrences(of: "\"pid\":12", with: "\"pid\":12,\"canSeek\":true").utf8)
        let seekable = NotchPlayback.decode(seekableReply, now: now)
        expect(seekable?.seekPosition(95.5) == 95.5
               && seekable?.seekPosition(-10) == 0 && seekable?.seekPosition(300) == 180,
               "scrubbing retains fractions and stays within the current track")
        expect(playing?.seekPosition(30) == nil && seekable?.seekPosition(.nan) == nil
               && seekable?.seekPosition(.infinity) == nil,
               "unsupported playback and non-finite positions cannot produce seek commands")
        for command in [NotchPlaybackCommand.toggle, .next, .previous, .seek(0), .seek(12.75), .seek(604_800)] {
            expect(command.message.flatMap(NotchPlaybackCommand.init(message:)) == command,
                   "playback commands survive their bounded pipe protocol")
        }
        for invalid in ["", "stop", "seek", "seek -1", "seek nan", "seek inf", "seek 604801", "seek 10\\ntoggle", "seek 1 2"] {
            expect(NotchPlaybackCommand(message: invalid) == nil, "malformed playback input is refused: \(invalid)")
        }
        expect(NotchPlaybackCommand.seek(.nan).message == nil
               && NotchPlaybackCommand.seek(-1).message == nil,
               "invalid internal positions cannot be serialized into adapter input")
    }
    private static func calendarContracts(expect: (Bool, String) -> Void) {
        let entitlements = NSDictionary(contentsOfFile: "Resources/Vorssaint.entitlements") as? [String: Any]
        let info = NSDictionary(contentsOfFile: "Resources/Info.plist") as? [String: Any]
        expect(entitlements?["com.apple.security.personal-information.calendars"] as? Bool == true
               && !(info?["NSCalendarsFullAccessUsageDescription"] as? String ?? "").isEmpty,
               "the signed hardened app declares both the calendar capability and its permission explanation")
        let languages = info?["CFBundleLocalizations"] as? [String] ?? []
        expect(languages.count == AppLanguage.allCases.count, "calendar prompts cover every supported app language")
        for language in languages where language != "en" {
            let localized = NSDictionary(contentsOfFile: "Resources/\(language).lproj/InfoPlist.strings")
            let prompt = localized?["NSCalendarsFullAccessUsageDescription"] as? String ?? ""
            expect(!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                   && prompt != info?["NSCalendarsFullAccessUsageDescription"] as? String,
                   "\(language) ships its own readable calendar permission explanation")
        }
        expect(NotchCalendarSupport.requestFailed(status: .notDetermined, hasError: false)
               && NotchCalendarSupport.requestFailed(status: .writeOnly, hasError: false),
               "a calendar request that silently fails to resolve read access surfaces an error")
        expect(!NotchCalendarSupport.requestFailed(status: .fullAccess, hasError: false)
               && !NotchCalendarSupport.requestFailed(status: .denied, hasError: false)
               && !NotchCalendarSupport.requestFailed(status: .restricted, hasError: false),
               "successful grants and explicit system refusals keep their own calendar presentation")
        expect(NotchCalendarSupport.requestFailed(status: .notDetermined, hasError: true),
               "calendar authorization errors remain visible and retryable")
        expect(NotchSupport.keepsPermissionSurface(requesting: true, resolvedAt: nil, now: 0),
               "the calendar remains open while its system permission dialog is in use")
        expect(NotchSupport.keepsPermissionSurface(requesting: false, resolvedAt: 10, now: 10.5)
               && !NotchSupport.keepsPermissionSurface(requesting: false, resolvedAt: 10, now: 11)
               && !NotchSupport.keepsPermissionSurface(requesting: false, resolvedAt: 10, now: 9),
               "permission resolution protects only the short reactivation interval")
        let defaults = UserDefaults(suiteName: "com.vorssaint.tests.notch-calendar")!
        defaults.removePersistentDomain(forName: "com.vorssaint.tests.notch-calendar")
        defer { defaults.removePersistentDomain(forName: "com.vorssaint.tests.notch-calendar") }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        expect(!NotchCalendarSupport.isEnabled(in: defaults), "calendar starts off")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        expect(NotchSupport.modules(in: defaults).contains(.calendar), "calendar is available in the default home")
        defaults.set(false, forKey: DefaultsKey.notchCalendarEnabled)
        expect(!NotchCalendarSupport.isEnabled(in: defaults), "calendar can still be explicitly disabled")
        defaults.set(true, forKey: DefaultsKey.notchCalendarEnabled)
        expect(NotchCalendarSupport.isEnabled(in: defaults), "calendar can be enabled independently")
        defaults.set("calendar", forKey: DefaultsKey.notchHiddenModules)
        expect(!NotchCalendarSupport.isEnabled(in: defaults), "hiding the calendar releases its resources")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(false, forKey: AppFeature.notchCalendar.availabilityKey)
        expect(!NotchCalendarSupport.isEnabled(in: defaults), "removing the calendar from the hub stops its reader")
        defaults.set(true, forKey: AppFeature.notchCalendar.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        expect(!NotchCalendarSupport.isEnabled(in: defaults), "the master switch also stops calendar reads")
        expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchCalendarEnabled,
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
        expect(upcoming.map(\.id) == [allDay.id, current.id, later.id, tomorrow.id],
               "calendar deduplicates occurrences, preserves ongoing and all-day events and excludes invalid or ended entries")
        expect(NotchCalendarSupport.next(entries, now: now) == current,
               "an all-day event does not conceal the current appointment")
        expect(NotchCalendarSupport.next(entries, now: now.addingTimeInterval(300)) == later,
               "the next appointment advances exactly when the previous one ends")
        expect(NotchCalendarSupport.next([allDay], now: now) == nil,
               "an all-day-only calendar has no timed appointment")
        expect(NotchCalendarSupport.nextRefresh(entries, now: now) == now.addingTimeInterval(300),
               "the next refresh chooses the nearest future event boundary")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let late = calendar.date(byAdding: .hour, value: 22, to: midnight)!.addingTimeInterval(3540)
        let rollover = NotchCalendarSupport.nextRefresh([], now: late, calendar: calendar)
        expect(rollover.timeIntervalSince(late) == 60 && calendar.component(.day, from: rollover) == 9,
               "calendar refresh reaches the next local day across daylight saving time")
        calendarMonthContracts(expect: expect)
    }

    private static func calendarMonthContracts(expect: (Bool, String) -> Void) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let leapDay = date(2028, 2, 29)
        for firstWeekday in [1, 2, 7] {
            calendar.firstWeekday = firstWeekday
            let days = NotchCalendarSupport.monthDays(containing: leapDay, calendar: calendar)
            expect(days.count == 42 && Set(days).count == 42,
                   "the month has six stable complete weeks with no duplicated dates")
            expect(calendar.component(.weekday, from: days[0]) == firstWeekday && days.contains(leapDay),
                   "the grid honors the user's first weekday and includes leap day")
            expect(days.filter { calendar.component(.month, from: $0) == 2 }.count == 29,
                   "every date of a leap February appears exactly once")
        }
        let march = NotchCalendarSupport.monthDays(containing: date(2026, 3, 15), calendar: calendar)
        expect(march.contains(date(2026, 3, 8)) && march.contains(date(2026, 3, 9))
               && date(2026, 3, 9).timeIntervalSince(date(2026, 3, 8)) == 23 * 3600,
               "month dates stay at local midnight through a daylight saving transition")
        let now = date(2026, 3, 31, 12)
        let interval = NotchCalendarSupport.readInterval(month: now, now: now, calendar: calendar)
        expect(interval.start <= date(2026, 3, 1) && interval.end >= date(2026, 4, 7),
               "the visible month query also covers all seven upcoming days across month boundaries")
        let distant = NotchCalendarSupport.readInterval(month: date(2030, 12, 1), now: now, calendar: calendar)
        expect(distant.duration <= 43 * 86400 && distant.start > now,
               "browsing a distant month reads only its grid, never every intervening event")
        let resting = NotchCalendarSupport.readInterval(month: nil, now: now, calendar: calendar)
        expect(resting.start == date(2026, 3, 31) && resting.end == date(2026, 4, 7),
               "closing the month returns the reader to today's seven-day interval")
        let allDay = NotchCalendarEvent(id: "all", title: "Holiday", calendar: "Personal",
            start: date(2026, 3, 8), end: date(2026, 3, 10), allDay: true, location: "")
        let overnight = NotchCalendarEvent(id: "overnight", title: "Travel", calendar: "Personal",
            start: date(2026, 3, 8, 23), end: date(2026, 3, 9, 2), allDay: false, location: "")
        let ended = NotchCalendarEvent(id: "ended", title: "Morning", calendar: "Personal",
            start: date(2026, 3, 8, 9), end: date(2026, 3, 8, 10), allDay: false, location: "")
        let entries = NotchCalendarSupport.ordered([overnight, allDay, ended, ended])
        expect(NotchCalendarSupport.events(entries, on: date(2026, 3, 8), calendar: calendar).map(\.id)
               == ["all", "ended", "overnight"],
               "selected dates retain completed appointments and put all-day events first")
        expect(NotchCalendarSupport.events(entries, on: date(2026, 3, 9), calendar: calendar).map(\.id)
               == ["all", "overnight"],
               "overnight and multi-day events appear on every day they overlap")
        expect(NotchCalendarSupport.events(entries, on: date(2026, 3, 10), calendar: calendar).isEmpty,
               "exclusive midnight endings do not mark or populate the following date")
        expect(NotchCalendarSupport.upcoming(entries, now: date(2026, 3, 8, 12)).map(\.id)
               == ["all", "overnight"],
               "upcoming mode still hides completed appointments after adding month history")
    }

}
