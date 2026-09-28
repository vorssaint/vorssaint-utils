// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// On a display without a camera the island can float in the menu bar as a
/// capsule. The capsule sits centred inside the bar; closed, it runs its
/// content from end to end and is as wide as that content, within limits the
/// bar and its kind set; open, it keeps the island's sizes with its header
/// clear of the rounded corners. A physical camera never floats.
enum NotchCapsuleTests {
    static func run(_ suite: TestSuite) {
        preferenceContracts(suite)
        placementContracts(suite)
        outlineContracts(suite)
        stripContracts(suite)
        measureContracts(suite)
        openContracts(suite)
        targetContracts(suite)
        fitContracts(suite)
        symbolContracts(suite)
    }

    private static let screen = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
    private typealias Layout = NotchCapsuleLayout

    private static func capsule(bar: CGFloat, room: CGFloat? = 300, layout: NotchSize = .spacious,
                                customWidth: Double = NotchSize.defaultWidth,
                                customHeight: Double = NotchSize.defaultHeight) -> NotchGeometry {
        NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: layout, menuBarHeight: bar,
                      compactSideRoom: room, customWidth: customWidth, customHeight: customHeight, silhouette: .capsule)
    }

    private static func body(_ size: CGSize, _ geometry: NotchGeometry) -> CGRect {
        NotchLayout.capsuleBody(in: CGRect(origin: .zero, size: size), gap: geometry.floatingGap ?? 0)
    }

    /// Every closed strip a capsule can show, with long and short content.
    private static func strips(_ geometry: NotchGeometry) -> [(String, CGSize)] {
        let language = AppLanguage.enUS
        let long = String(repeating: "A long title that keeps going ", count: 6)
        var result: [(String, CGSize)] = [
            ("rest", geometry.restingSize(showsContent: false)),
            ("music", Layout.musicSurface(title: "Song", geometry: geometry)),
            ("long music", Layout.musicSurface(title: long, geometry: geometry)),
            ("timer", Layout.timerSurface(reading: "25min", companion: nil, workingAgents: 0, downloadPercent: false,
                                          geometry: geometry, language: language)),
            ("timer and download", Layout.timerSurface(reading: "1h02", companion: .downloads, workingAgents: 0,
                                                       downloadPercent: true, geometry: geometry, language: language)),
            ("timer and agents", Layout.timerSurface(reading: "12:04", companion: .agents, workingAgents: 2,
                                                     downloadPercent: false, geometry: geometry, language: language)),
            ("timer and music", Layout.timerSurface(reading: "9m", companion: .music, workingAgents: 0,
                                                    downloadPercent: false, geometry: geometry, language: language)),
            ("agents", Layout.agentSurface(reading: "1:02:33", working: 2, geometry: geometry)),
            ("download", Layout.downloadSurface(name: "Installer.dmg", hasProgress: true, geometry: geometry, language: language)),
            ("long download", Layout.downloadSurface(name: long, hasProgress: false, geometry: geometry, language: language)),
            ("calendar", Layout.calendarSurface(title: "Design review", time: "· 19:15", geometry: geometry)),
            ("long calendar", Layout.calendarSurface(title: long, time: "→ 19:15", geometry: geometry)),
            ("capture", Layout.captureSurface(geometry: geometry)),
        ]
        for (title, detail, level) in [("Volume", "60%", true), ("Charging", "80%", false),
                                       ("Connected", "Wireless Headphones Pro", false), (long, long, false)] {
            result.append(("notice \(title.prefix(12))",
                           Layout.surface(content: Layout.noticeContent(title: title, detail: detail, level: level),
                                          maximum: Layout.Maximum.notice, geometry: geometry)))
        }
        result.append(("banner", Layout.surface(content: Layout.notificationContent(title: "Alex", message: long, geometry: geometry),
                                                maximum: Layout.Maximum.notification, geometry: geometry)))
        return result
    }

    private static func preferenceContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-capsule"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchSilhouette] as? String == NotchSilhouette.capsule.rawValue
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchSilhouette),
                     "the capsule is the registered shape without a notch and travels with a backup")
        suite.expect(NotchSilhouette.current(in: defaults) == .capsule, "a display without a notch floats a capsule by default")
        defaults.set(NotchSilhouette.notch.rawValue, forKey: DefaultsKey.notchSilhouette)
        suite.expect(NotchSilhouette.current(in: defaults) == .notch, "the simulated notch stays available")
        defaults.set("oval", forKey: DefaultsKey.notchSilhouette)
        suite.expect(NotchSilhouette.current(in: defaults) == .capsule, "an unknown shape falls back to the capsule")

        for safeArea: CGFloat in [24, 32, 38] {
            let hanging = NotchGeometry(screen: screen, safeAreaTop: safeArea, cameraWidth: 185, menuBarHeight: 33)
            let asked = NotchGeometry(screen: screen, safeAreaTop: safeArea, cameraWidth: 185, menuBarHeight: 33,
                                      silhouette: .capsule)
            suite.expect(asked == hanging && !asked.floats && asked.floatingGap == nil,
                         "a physical camera keeps the cutout it covers, whatever the shape without a notch")
        }
        let simulated = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0)
        suite.expect(!simulated.floats && simulated == NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0,
                                                                    silhouette: .notch),
                     "the simulated notch is unchanged when chosen")
    }

    /// The capsule is centred in the bar with the same margin above and
    /// below, and the same capsule shows whether or not the bar is visible.
    private static func placementContracts(_ suite: TestSuite) {
        let standard = capsule(bar: 24)
        let hiddenBar = capsule(bar: 22)
        suite.expect(standard.floatingGap == 2 && standard.stripBodyHeight == 20
                     && hiddenBar.floatingGap == 1 && hiddenBar.stripBodyHeight == 20
                     && standard.cameraWidth == hiddenBar.cameraWidth
                     && abs(body(standard.restingSize(showsContent: false), standard).width
                            - body(hiddenBar.restingSize(showsContent: false), hiddenBar).width) < 1,
                     "a standard bar and a display without one draw the same 20-point capsule")
        suite.expect(capsule(bar: 16).floatingGap == 0 && capsule(bar: 21).floatingGap == 0
                     && capsule(bar: 37).floatingGap == 2 && capsule(bar: .nan).floatingGap == 2,
                     "a bar too short for margins keeps the capsule inside it, and taller bars keep two points")
        for bar: CGFloat in [16, 20, 22, 24, 26, 30, 37, 44, 64] {
            for room: CGFloat? in [nil, 0, 43, 44, 56, 64, 200] {
                let geometry = capsule(bar: bar, room: room)
                let gap = geometry.floatingGap ?? -1
                let barRect = CGRect(x: screen.minX, y: screen.maxY - geometry.menuBarHeight,
                                     width: screen.width, height: geometry.menuBarHeight)
                let resting = geometry.restingSize(showsContent: false)
                let hover = NotchHoverEmphasis.size(from: resting, geometry: geometry)
                for (name, size) in strips(geometry) + [("hover", hover)] {
                    let drawn = body(size, geometry)
                    suite.expect(barRect.contains(geometry.frame(for: size)) && size.height == geometry.menuBarHeight
                                 && abs(geometry.frame(for: size).midX - screen.midX) < 0.001
                                 && abs(drawn.minY - gap) < 0.001 && abs(geometry.menuBarHeight - drawn.maxY - gap) < 0.001
                                 && abs(drawn.midX - size.width / 2) < 0.001,
                                 "a closed capsule sits centred in the menu bar, as far from its top as its bottom: \(name), bar \(bar)")
                    guard drawn.height <= 56 else { continue }
                    suite.expect(min(NotchLayout.capsuleRadius(height: drawn.height), drawn.width / 2) == drawn.height / 2,
                                 "a closed capsule has round ends: \(name)")
                }
                suite.expect(hover.height == resting.height,
                             "the capsule stretches along the bar on hover instead of growing below it")
            }
        }
        let resting = standard.restingSize(showsContent: false)
        suite.expect(resting.width < standard.cameraWidth && resting.width == resting.width.rounded()
                     && abs(body(resting, standard).width - NotchLayout.capsuleRestingAspect * 20) < 1,
                     "bare at rest the capsule is short, on whole points")
    }

    /// The outline's inverse gives back the surface it was drawn for, so a
    /// resize always starts from the size on screen.
    private static func outlineContracts(_ suite: TestSuite) {
        for gap: CGFloat in [0, 1, 2] {
            for height: CGFloat in [0, 0.5, 1, 2, 3, 4, 5, 20, 24, 27.5, 68, 180, 412.25, 640] {
                for width: CGFloat in [109, 135, 247.5, 440, 560.5] {
                    let size = CGSize(width: width, height: height)
                    let drawn = NotchLayout.capsulePath(in: CGRect(origin: .zero, size: size), gap: gap).boundingBoxOfPath
                    let back = NotchLayout.capsuleSurface(ofBody: drawn, gap: gap)
                    suite.expect(abs(back.width - width) < 0.001 && abs(back.height - height) < 0.001,
                                 "a capsule's drawn bounds give back its surface: \(size) with gap \(gap)")
                    suite.expect(drawn.minY >= min(gap, height / 2) - 0.001 && drawn.maxY <= height - min(gap, height / 2) + 0.001,
                                 "a capsule stays inside the margins of its surface")
                }
            }
        }
        let shape = NotchShape(attached: true, radius: 8, floatingGap: 2)
        let rect = CGRect(x: 0, y: 0, width: 247, height: 24)
        suite.expect(shape.path(in: rect).boundingRect == NotchLayout.capsuleBody(in: rect, gap: 2)
                     && NotchShape(attached: true, radius: 8).path(in: rect).boundingRect == rect,
                     "the island's shape floats as a capsule only when asked, and hangs otherwise")
        let geometry = capsule(bar: 24)
        suite.expect(NotchShape.island(height: 24, geometry: geometry).floatingGap == 2
                     && NotchShape.island(height: 24, geometry: NotchGeometry(screen: screen, safeAreaTop: 32,
                                                                              cameraWidth: 185)).floatingGap == nil,
                     "the island draws its display's outline")
    }

    /// Closed strips hug their content: never shorter than the bare capsule,
    /// never wider than their kind allows or than the menus leave free, and
    /// on whole points, like the window around them.
    private static func stripContracts(_ suite: TestSuite) {
        for bar: CGFloat in [22, 24, 30] {
            for room: CGFloat? in [nil, 0, 20, 60, 120, 300, .infinity, .nan] {
                let geometry = capsule(bar: bar, room: room)
                let resting = geometry.restingSize(showsContent: false).width
                let available = Layout.availableWidth(geometry)
                let side = Layout.side(geometry)
                for (name, size) in strips(geometry) {
                    suite.expect(size.width >= resting && size.width == size.width.rounded()
                                 && (size.width <= available || size.width == resting)
                                 && size.width <= Layout.Maximum.notification + side * 2 + 1,
                                 "a closed capsule stays between the bare capsule, its kind's limit and the bar's room: \(name), room \(String(describing: room))")
                }
                let room = geometry.compactSideRoom ?? 0
                suite.expect(available <= geometry.screen.width - 24
                             && available <= geometry.cameraWidth + 2 * (room.isFinite ? max(0, room) : 0) + 0.001,
                             "the capsule only widens into the menu bar's free room")
            }
        }
        let geometry = capsule(bar: 24)
        let side = Layout.side(geometry)
        func visible(_ size: CGSize) -> CGFloat { size.width - side * 2 }
        // Content is hugged with the capsule's end padding, and a level notice
        // keeps one width for every value.
        let volume = Layout.surface(content: Layout.noticeContent(title: "Volume", detail: "60%", level: true),
                                    maximum: Layout.Maximum.notice, geometry: geometry)
        suite.expect(abs(visible(volume) - (Layout.noticeContent(title: "Volume", detail: "60%", level: true)
                                            + Layout.endPadding * 2)) < 1,
                     "a level notice is as wide as its mark, meter and reading, with no band of empty black")
        for value in 0...100 {
            let other = Layout.surface(content: Layout.noticeContent(title: "Volume", detail: "\(value)%", level: true),
                                       maximum: Layout.Maximum.notice, geometry: geometry)
            suite.expect(other == volume, "a level notice keeps one width while the value changes: \(value)%")
        }
        for (first, second) in [("25min", "24min"), ("9m", "8m"), ("1h02", "1h59"), ("12:04", "59:59")] {
            let a = Layout.timerSurface(reading: first, companion: nil, workingAgents: 0, downloadPercent: false,
                                        geometry: geometry, language: .enUS)
            let b = Layout.timerSurface(reading: second, companion: nil, workingAgents: 0, downloadPercent: false,
                                        geometry: geometry, language: .enUS)
            suite.expect(a == b && Layout.agentSurface(reading: first, working: 1, geometry: geometry)
                            == Layout.agentSurface(reading: second, working: 1, geometry: geometry),
                         "a reading keeps its capsule while its digits change: \(first) and \(second)")
        }
        let music = Layout.musicSurface(title: "Song", geometry: geometry)
        let unnamed = Layout.musicSurface(title: nil, geometry: geometry)
        suite.expect(unnamed.width == geometry.restingSize(showsContent: false).width
                     && Layout.musicSurface(title: String(repeating: "Song ", count: 40), geometry: geometry).width > unnamed.width,
                     "a song past its first moments keeps only its cover and bars, in the bare capsule")
        let longMusic = Layout.musicSurface(title: String(repeating: "Song ", count: 40), geometry: geometry)
        suite.expect(music.width < longMusic.width && longMusic.width == (Layout.Maximum.music + side * 2).rounded(.down),
                     "a song's capsule fits its title up to the widest music strip, which then truncates the title")
        let cover = Layout.artworkSide(geometry)
        suite.expect(abs(Layout.artworkInset(geometry) + cover / 2 - geometry.stripBodyHeight / 2) < 0.001 && cover >= 12,
                     "the cover is a circle concentric with the capsule's round end, an even gap inside it")
        for font in [Layout.titleFont, Layout.detailFont, Layout.levelFont, Layout.readingFont, Layout.smallFont] {
            suite.expect((geometry.stripBodyHeight - font.capHeight) / 2 >= 4,
                         "the capsule's text keeps clear of its top and bottom: \(font.pointSize) pt")
        }
        suite.expect((geometry.stripBodyHeight - Layout.notificationIconSide(geometry)) / 2 >= 2
                     && (geometry.stripBodyHeight - Layout.barsHeight(geometry)) / 2 >= 4,
                     "a banner's icon and the music bars keep clear of the capsule's top and bottom")
        // Crowded menus narrow every capsule to what they leave, and the bare
        // capsule stays whole.
        let crowded = capsule(bar: 24, room: 10)
        for (name, size) in strips(crowded) {
            suite.expect(size.width <= max(crowded.restingSize(showsContent: false).width, crowded.cameraWidth + 20),
                         "crowded menus keep a capsule within their free room: \(name)")
        }
    }

    /// AppKit measures what SwiftUI draws; the air keeps any difference from
    /// cutting a word, in every script a strip can carry.
    private static func measureContracts(_ suite: TestSuite) {
        let samples = ["Bohemian Rhapsody", "Wireless Headphones Pro", "Carregando", "Подключено", "会议提醒 项目评审",
                       "🚀🎉 launch", "مرحبا بالعالم", "שלום עולם", "25min", "1:02:33", "100%", "Xcode_27.xip"]
        for sample in samples {
            for font in [Layout.titleFont, Layout.detailFont, Layout.levelFont, Layout.readingFont, Layout.smallFont] {
                let drawn = NSHostingView(rootView: Text(sample).font(Font(font as CTFont)).lineLimit(1).fixedSize())
                    .fittingSize.width
                suite.expect(drawn <= Layout.width(sample, font: font) + 0.5,
                             "the capsule measures \(sample) as wide as it draws (\(drawn))")
            }
        }
        suite.expect(Layout.width("", font: Layout.titleFont) == 0, "an empty text takes no room")
    }

    /// The open capsule hangs from the same margin as the closed one, its
    /// header clear of the rounded top corners and its page inside it.
    private static func openContracts(_ suite: TestSuite) {
        var geometries = [capsule(bar: 24, layout: .compact), capsule(bar: 24, layout: .spacious), capsule(bar: 22)]
        for width in stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 40) {
            for height in [NotchSize.heightRange.lowerBound, 400, NotchSize.heightRange.upperBound] {
                geometries.append(capsule(bar: 24, layout: .custom, customWidth: width, customHeight: height))
            }
        }
        for geometry in geometries {
            let gap = geometry.floatingGap ?? 0
            let simulated = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: .spacious,
                                          menuBarHeight: geometry.menuBarHeight)
            suite.expect(geometry.headerTopInset == gap + 2 && geometry.headerCameraGap == 0
                         && geometry.quickAccessCenterY == simulated.quickAccessCenterY,
                         "the open capsule's header starts below its top edge and its floating buttons keep their row")
            suite.expect(geometry.activationArea(in: geometry.expanded, hasHeader: true, compactActivity: false,
                                                 expandedHeader: true).isEmpty,
                         "no invisible collapse button covers the capsule's header controls")
            let strip = geometry.restingSize(showsContent: false)
            suite.expect(geometry.activationArea(in: strip, hasHeader: false, compactActivity: true)
                            == CGRect(origin: .zero, size: strip),
                         "a click anywhere on a closed capsule opens the island")
            let sizes = NotchModule.allCases.map { geometry.expandedSize(module: $0) }
                + [geometry.sectionPickerSize(count: NotchModule.allCases.count), geometry.peek,
                   geometry.notificationPreviewSize(contentHeight: 120)]
            for size in sizes {
                let capsule = body(size, geometry)
                let corner = min(NotchLayout.capsuleRadius(height: capsule.height), capsule.width / 2)
                suite.expect(screen.contains(geometry.frame(for: size)) && capsule.minY == gap
                             && abs(capsule.maxY - (size.height - gap)) < 0.001,
                             "the open capsule floats at the closed one's margin and stays on its display")
                // The header's last button, a rounded 28-point square, clear
                // of the top right corner by a few points.
                let button = CGRect(x: size.width - NotchLayout.horizontalInset - 28,
                                    y: geometry.headerTopInset + (geometry.headerRowHeight - 28) / 2, width: 28, height: 28)
                let arc = CGPoint(x: capsule.maxX - corner, y: capsule.minY + corner)
                let buttonCorner = CGPoint(x: button.maxX - 9, y: button.minY + 9)
                let clear = buttonCorner.x <= arc.x || buttonCorner.y >= arc.y
                    || corner - hypot(buttonCorner.x - arc.x, buttonCorner.y - arc.y) - 9 >= 4
                suite.expect(size.height < 80 || clear, "the header's buttons clear the capsule's rounded corner: \(size)")
                suite.expect(capsule.minX == NotchLayout.shoulder(height: size.height)
                             && abs(capsule.width + NotchLayout.shoulder(height: size.height) * 2 - size.width) < 0.001,
                             "the capsule is as wide as the hanging island's body, which its page and buttons are laid around")
            }
            // The peek's row is as tall as its navigation, 36 points.
            suite.expect(geometry.safeContentTop - gap == geometry.peek.height - geometry.safeContentTop - 36 - gap
                         && geometry.safeContentTop == NotchLayout.bottomInset,
                         "a peek, a drop or a notification card keeps even margins inside the capsule")
            let controls = NotchCaptureControlsLayout(geometry: geometry, titleWidth: 120, capturesAudio: false)
            suite.expect(controls.headerTop == geometry.headerTopInset && controls.headerHeight == geometry.headerRowHeight
                         && controls.cameraGap == 0,
                         "capture controls take the capsule's header row, below its top edge")
        }
    }

    /// The open capsule's rounded corners are not the island's: clicks there
    /// reach what lies beneath, and only the capsule is painted.
    private static func targetContracts(_ suite: TestSuite) {
        let geometry = capsule(bar: 24)
        let strip = Layout.musicSurface(title: "Song", geometry: geometry)
        let stripPath = NotchLayout.capsulePath(in: CGRect(origin: .zero, size: strip), gap: 2)
        suite.expect(stripPath.contains(CGPoint(x: strip.width / 2, y: strip.height / 2))
                     && !stripPath.contains(CGPoint(x: strip.width / 2, y: 1))
                     && !stripPath.contains(CGPoint(x: strip.width / 2, y: strip.height - 1))
                     && !stripPath.contains(CGPoint(x: 0.5, y: strip.height / 2)),
                     "a closed capsule paints only between its margins and inside its ends")
        let open = geometry.expanded
        let openPath = NotchLayout.capsulePath(in: CGRect(origin: .zero, size: open), gap: 2)
        let capsule = body(open, geometry)
        suite.expect(openPath.contains(CGPoint(x: open.width / 2, y: 3))
                     && !openPath.contains(CGPoint(x: capsule.minX + 2, y: capsule.minY + 2))
                     && !openPath.contains(CGPoint(x: capsule.maxX - 2, y: capsule.maxY - 2)),
                     "the open capsule's rounded corners let clicks through to what lies beneath")
    }

    /// A fitted capsule grows from its top edge, keeps its margins, lowers
    /// open and closed alike, and leaves every other island untouched.
    private static func fitContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-capsule-fit"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let keys = [DefaultsKey.notchCapsuleFitWidth, DefaultsKey.notchCapsuleFitHeight, DefaultsKey.notchCapsuleFitDrop]
        suite.expect(keys.allSatisfy { Defaults.registeredDefaults[$0] as? Double == 0 }
                     && keys.allSatisfy(SettingsBackupSupport.exportKeys().contains)
                     && NotchCapsuleFit.current(in: defaults) == .zero,
                     "an untouched capsule has no fit, and a fit travels with a backup")
        defaults.set(7.0, forKey: DefaultsKey.notchCapsuleFitWidth)
        defaults.set(2.6, forKey: DefaultsKey.notchCapsuleFitHeight)
        defaults.set(12.4, forKey: DefaultsKey.notchCapsuleFitDrop)
        let stored = NotchCapsuleFit.current(in: defaults)
        suite.expect(stored.width == 8 && stored.height == 3 && stored.drop == 12,
                     "a fit written by hand lands on even widths and whole points")
        let wild = NotchCapsuleFit(width: 1_000, height: -.infinity, drop: .nan)
        suite.expect(wild.width == 80 && wild.height == 0 && wild.drop == 0
                     && NotchCapsuleFit(width: -1_000, height: -9, drop: -5) == NotchCapsuleFit(width: -40, height: -4, drop: 0),
                     "a fit stays inside its ranges")

        for safeArea: CGFloat in [0, 32] {
            let plain = NotchGeometry(screen: screen, safeAreaTop: safeArea, cameraWidth: safeArea > 0 ? 185 : 0,
                                      menuBarHeight: 24, silhouette: safeArea > 0 ? .capsule : .notch)
            let fitted = NotchGeometry(screen: screen, safeAreaTop: safeArea, cameraWidth: safeArea > 0 ? 185 : 0,
                                       menuBarHeight: 24, silhouette: safeArea > 0 ? .capsule : .notch,
                                       capsuleFit: NotchCapsuleFit(width: 20, height: 6, drop: 8))
            suite.expect(plain == fitted && fitted.floatingDrop == 0,
                         "a camera cutout and the simulated notch ignore the capsule's fit")
        }
        for bar: CGFloat in [16, 22, 24, 30, 37] {
            let base = capsule(bar: bar)
            suite.expect(base == NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: .spacious,
                                               menuBarHeight: bar, compactSideRoom: 300, silhouette: .capsule,
                                               capsuleFit: .zero),
                         "no fit is the capsule as it was")
            for width in stride(from: -40.0, through: 80, by: 20) {
                for height in stride(from: -4.0, through: 12, by: 4) {
                    for drop in [0.0, 1, 7, 20] {
                        let fit = NotchCapsuleFit(width: width, height: height, drop: drop)
                        let geometry = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, layout: .spacious,
                                                     menuBarHeight: bar, compactSideRoom: 300, silhouette: .capsule,
                                                     capsuleFit: fit)
                        let gap = geometry.floatingGap ?? -1
                        let resting = geometry.restingSize(showsContent: false)
                        let restingBody = body(resting, geometry)
                        let baseBody = body(base.restingSize(showsContent: false), base)
                        suite.expect(gap == base.floatingGap && geometry.stripBodyHeight == max(12, base.stripBodyHeight + fit.height)
                                     && geometry.stripHeight == geometry.stripBodyHeight + gap * 2
                                     && restingBody.minY == gap && resting.height == geometry.stripHeight,
                                     "a taller or shorter capsule grows from its top edge and keeps its margins")
                        let aspect = NotchLayout.capsuleRestingAspect
                        let expectedWidth = max(aspect * geometry.stripBodyHeight + fit.width, geometry.stripBodyHeight * 2)
                        suite.expect(abs(restingBody.width - expectedWidth) <= 1
                                     && resting.width == resting.width.rounded()
                                     && resting.width <= geometry.cameraWidth,
                                     "a fitted width widens or narrows the capsule at rest, on whole points")
                        if fit.height == 0 {
                            suite.expect(abs(restingBody.width - baseBody.width - fit.width) <= 1
                                         || expectedWidth == geometry.stripBodyHeight * 2,
                                         "a width fit adds exactly its points to the bare capsule")
                        }
                        for size in [resting, geometry.peek, geometry.expanded] {
                            let frame = geometry.frame(for: size)
                            suite.expect(frame.maxY == screen.maxY - fit.drop && frame.midX == screen.midX
                                         && geometry.contains(CGPoint(x: frame.midX, y: frame.maxY - 0.5), in: size)
                                         && !geometry.contains(CGPoint(x: frame.midX, y: frame.maxY + 0.5), in: size),
                                         "the whole island, closed or open, lowers by the fitted distance")
                        }
                        suite.expect(geometry.headerTopInset == gap + 2,
                                     "the open capsule keeps its header clear of its corners at any fit")
                        for (name, size) in strips(geometry) {
                            suite.expect(size.width >= resting.width && size.width <= max(resting.width, Layout.availableWidth(geometry))
                                         && size.height == geometry.stripHeight,
                                         "a fitted \(name) strip stays between the capsule at rest and the room the bar leaves")
                        }
                    }
                }
            }
        }
    }

    /// Symbols are measured from their own drawing, so each one's ink meets
    /// the row's middle line; the frame alone left a circle a pixel low.
    private static func symbolContracts(_ suite: TestSuite) {
        let circles = ["timer", "pause.circle", "checkmark.circle", "arrow.down.circle.fill"]
        suite.expect(circles.allSatisfy { (0.2...0.7).contains(Layout.symbolDrop($0)) },
                     "a circle symbol's ink sits below its frame's middle, and is lifted by that much")
        suite.expect(abs(Layout.symbolDrop("chevron.down")) < 0.2 && Layout.symbolDrop("no.such.symbol") == 0,
                     "a symbol with centred ink, or none at all, stays where its frame puts it")
        let symbols = circles + ["stopwatch", "speaker.wave.2.fill", "sun.max.fill", "moon.fill", "bell.fill", "keyboard",
                                 "light.max", "mic.fill", "headphones", "airpods", "bolt.fill", "chevron.down"]
        suite.expect(symbols.allSatisfy { abs(Layout.symbolDrop($0)) < 1.5 }
                     && symbols.allSatisfy { Layout.symbolDrop($0) == Layout.symbolDrop($0) }
                     && abs(Layout.symbolDrop("battery.100percent", weight: .regular)) < 1.5,
                     "every capsule symbol moves by less than a point and a half, the same each time")
    }
}
