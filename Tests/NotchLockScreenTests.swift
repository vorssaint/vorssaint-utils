// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// When the lock screen shows the island's activities, the room it keeps for
/// the system's clock and login controls, and what gives way on a short
/// display. Nothing here locks the Mac or opens a window.
enum NotchLockScreenTests {
    static func run(_ suite: TestSuite) {
        sessionContracts(suite)
        preferenceContracts(suite)
        layoutContracts(suite)
        widgetChoiceContracts(suite)
        islandContracts(suite)
        widgetContracts(suite)
        contentContracts(suite)
        soundContracts(suite)
        wallpaperContracts(suite)
    }

    static func sessionContracts(_ suite: TestSuite) {
        var locked = NotchSessionState()
        suite.expect(!locked.showsLockScreen, "an unlocked Mac shows nothing over its lock screen")
        locked.locked = true
        suite.expect(locked.showsLockScreen && !locked.canPresent,
                     "locked with the display awake, the lock screen takes over from the island")
        let hidden: [(WritableKeyPath<NotchSessionState, Bool>, String)] = [
            (\.sleeping, "the Mac asleep"), (\.displaysSleeping, "the display asleep"),
            (\.screenSaverRunning, "a screen saver running"),
        ]
        for (change, reason) in hidden {
            var session = locked
            session[keyPath: change] = true
            suite.expect(!session.showsLockScreen, "nothing shows with \(reason)")
        }
        var switched = locked
        switched.onConsole = false
        suite.expect(!switched.showsLockScreen, "nothing shows while another user has the display")
        var saver = NotchSessionState()
        saver.screenSaverRunning = true
        suite.expect(saver.canPresent && saver.canRunTimer, "a screen saver alone leaves the island as it was")
        suite.expect(NotchSessionState().hearsLockChange && locked.hearsLockChange,
                     "a lock or unlock at the keyboard is heard")
        var closing = NotchSessionState()
        closing.sleeping = true
        var dark = NotchSessionState()
        dark.displaysSleeping = true
        suite.expect(!closing.hearsLockChange && !dark.hearsLockChange && !switched.hearsLockChange,
                     "closing the lid, a dark display or a switched user plays no padlock")
        suite.expect(!saver.hearsLockChange, "a lock that follows an idle screen saver plays no padlock")
    }

    static func preferenceContracts(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchLockScreen] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.notchLockSounds] as? Bool == false,
                     "the lock screen and its sounds are both opt-in")
        suite.expect([DefaultsKey.notchLockScreenAgents, DefaultsKey.notchLockScreenAgentsHideProjects,
                      DefaultsKey.notchLockScreenAgentsHideAmounts].allSatisfy { Defaults.registeredDefaults[$0] as? Bool == false },
                     "the AI page on the lock screen and its privacy options are opt-in")
        suite.expect([DefaultsKey.notchLockScreenMac, DefaultsKey.notchLockScreenMacHideEvents]
                        .allSatisfy { Defaults.registeredDefaults[$0] as? Bool == false },
                     "This Mac on the lock screen is opt-in and shows event titles until they are hidden")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchLockScreen, DefaultsKey.notchLockSounds,
                                                                        DefaultsKey.notchLockScreenAgents,
                                                                        DefaultsKey.notchLockScreenMac,
                                                                        DefaultsKey.notchLockScreenMacHideEvents]),
                     "settings backups carry the lock screen preferences")
        let domain = "com.vorssaint.tests.notch-lock-screen"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        // These checks cover the sections and the floating buttons.
        defaults.set(NotchNavigationStyle.sideButtons.rawValue, forKey: DefaultsKey.notchNavigationStyle)
        defaults.set(true, forKey: DefaultsKey.notchLockScreen)
        defaults.set(true, forKey: DefaultsKey.notchLockSounds)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchLockScreenSupport.isEnabled(in: defaults) && !NotchLockScreenSupport.playsSounds(in: defaults),
                     "the island's own switch turns off the lock screen and the sounds")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchLockScreenSupport.isEnabled(in: defaults) && NotchLockScreenSupport.playsSounds(in: defaults),
                     "with the island on, each follows its own switch")
        defaults.set(false, forKey: DefaultsKey.notchLockScreen)
        suite.expect(!NotchLockScreenSupport.isEnabled(in: defaults) && NotchLockScreenSupport.playsSounds(in: defaults),
                     "the sounds do not need the lock screen")
        suite.expect(NotchLockScreenSupport.showsMusic(in: defaults), "music shows while the island has its Music section")
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        suite.expect(NotchLockScreenSupport.showsMusic(in: defaults), "an island resting empty still shows music when locked")
        defaults.set(NotchModule.music.rawValue, forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchLockScreenSupport.showsMusic(in: defaults), "hiding the Music section hides the player")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchLockWallpaper] as? Bool == false
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchLockWallpaper),
                     "the moon wallpaper is opt-in and travels with backups")
        defaults.set(true, forKey: DefaultsKey.notchLockWallpaper)
        suite.expect(!NotchLockScreenSupport.showsWallpaper(in: defaults), "the moon wallpaper moves only with the lock screen on")
        defaults.set(true, forKey: DefaultsKey.notchLockScreen)
        suite.expect(NotchLockScreenSupport.showsWallpaper(in: defaults), "with the lock screen on, it follows its own switch")
    }

    static func layoutContracts(_ suite: TestSuite) {
        typealias Layout = NotchLockScreenLayout
        // Measured on the lock screen of a 1470 by 956 point display: the
        // clock ends 236 points from the top, the login controls take 218.
        let measured = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let full = Layout.scene(in: measured, calendar: true, mac: true, ai: true)
        if let row = full.row, let player = full.player, let calendar = full.calendar {
            suite.expect(measured.maxY - row.maxY >= 236 + 12 && measured.maxY - row.maxY <= 236 + 30,
                         "the activities read as a line just under the clock")
            suite.expect(player.minY - measured.minY >= 218 + 24, "the stage clears the name, picture, password field and hint")
            suite.expect(calendar.maxY <= row.minY - Layout.stageGap && calendar.minY == player.maxY + Layout.stageGap,
                         "the calendar sits under the line and over the player")
        } else {
            suite.expect(false, "the measured display has room for the line, the calendar and the player")
        }

        // The six built-in displays, two of them at a larger text setting.
        let builtIns = [
            CGRect(x: 0, y: 0, width: 1280, height: 832), CGRect(x: 0, y: 0, width: 1352, height: 878),
            CGRect(x: 0, y: 0, width: 1470, height: 956), CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 0, y: 0, width: 1710, height: 1112), CGRect(x: 0, y: 0, width: 1728, height: 1117),
        ]
        for display in builtIns {
            let name = "\(Int(display.width))x\(Int(display.height))"
            let scene = Layout.scene(in: display, calendar: true, mac: true, ai: true)
            guard let row = scene.row, let calendar = scene.calendar else {
                suite.expect(false, "a \(name) display has room for the line and the calendar")
                continue
            }
            // A hair under the clock's edge is floating point, not overlap.
            let clock = Layout.clockBottom(screenHeight: display.height) - 0.001
            suite.expect(display.maxY - row.maxY >= clock, "the line keeps the clock's room on \(name)")
            suite.expect(calendar.width == Layout.stageWidth && abs(calendar.midX - display.midX) <= 0.5
                         && calendar.maxY <= row.minY - Layout.stageGap && calendar.height >= Layout.calendarMinimum,
                         "the stage stands 460 points wide and centred under the line on \(name)")
            if let player = scene.player, let fit = scene.playerFit {
                suite.expect(player.minY - display.minY == Layout.loginClearance && player.height == fit.height
                             && player.width == Layout.stageWidth && calendar.minY == player.maxY + Layout.stageGap,
                             "the player ends 250 points from the bottom, 10 under the calendar, on \(name)")
            } else {
                suite.expect(calendar.minY - display.minY == Layout.loginClearance,
                             "without the player the calendar keeps the stage's foot on \(name)")
            }
            let column = (display.width - Layout.stageWidth) / 2
            guard column >= Layout.railWidth + Layout.railMargin * 2 else {
                suite.expect(scene.mac == nil && scene.ai == nil && scene.widgets.isEmpty,
                             "a column under 488 points keeps both rails off on \(name)")
                continue
            }
            guard let mac = scene.mac, let claude = scene.frame(of: .claude), let codex = scene.frame(of: .codex),
                  let lifetime = scene.frame(of: .lifetime), let agents = scene.frame(of: .agents),
                  let streak = scene.frame(of: .streak), let gauge = scene.frame(of: .cpu)?.height else {
                suite.expect(false, "a \(name) display has room for both rails")
                continue
            }
            let cards = claude.union(codex).union(lifetime)
            suite.expect(mac.width == Layout.railWidth && cards.width == Layout.railWidth
                         && abs(mac.midX - (display.minX + column / 2)) <= 0.5
                         && abs(cards.midX - (display.maxX - column / 2)) <= 0.5,
                         "each rail stands 440 points wide, centred in its free column, on \(name)")
            suite.expect(display.maxY - mac.maxY == Layout.railTop && display.maxY - cards.maxY == Layout.railTop,
                         "both rails start 72 points from the top on \(name)")
            suite.expect(mac.minY - display.minY == Layout.loginClearance && streak.minY - display.minY == Layout.loginClearance,
                         "both rails end level with the player on \(name)")
            suite.expect(mac.height == gauge * 2 + Layout.accessoriesHeight + Layout.batteryHeight + Layout.cardGap * 3
                         && gauge >= Layout.gaugeMinimum,
                         "This Mac's gauges, Accessories and Battery fill its rail on \(name)")
            suite.expect(agents.minY == streak.maxY + Layout.cardGap && cards.minY == agents.maxY + Layout.cardGap
                         && cards.height == Layout.claudeHeight + Layout.cardGap + Layout.pairHeight
                         && codex.minY == lifetime.minY && codex.width == Layout.halfCard
                         && lifetime.minX == codex.maxX + Layout.cardGap
                         && streak.height == Layout.streakHeight && agents.height >= Layout.agentsMinimum,
                         "Claude, the pair, Agents at work and Streak stack 16 apart on \(name)")
            suite.expect(mac.maxX + Layout.railMargin <= calendar.minX && cards.minX - Layout.railMargin >= calendar.maxX
                         && row.minX >= mac.maxX + Layout.railMargin && row.maxX <= cards.minX - Layout.railMargin,
                         "the stage and the line keep clear of the rails on \(name)")
            suite.expect([mac, cards, agents, streak, calendar, row].allSatisfy(display.contains),
                         "every part stays on \(name)")
        }

        // The 14-inch, as the board draws it: the gauges 180 tall, Agents at
        // work 202, and the calendar what the stage leaves over the player.
        let pro = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let proScene = Layout.scene(in: pro, calendar: true, mac: true, ai: true)
        suite.expect(proScene.frame(of: .cpu)?.height == 180 && proScene.frame(of: .agents)?.height == 202
                     && proScene.playerFit == .regular && proScene.mac?.minX == 43 && proScene.ai?.minX == 1029
                     && proScene.calendar?.height == 231,
                     "the 14-inch lays out as the board: gauges 180, Agents at work 202, the player at its compact fit")
        let air = Layout.scene(in: CGRect(x: 0, y: 0, width: 1470, height: 956), calendar: true, mac: true, ai: true)
        suite.expect(air.frame(of: .cpu)?.height == 167 && air.frame(of: .agents)?.height == 176,
                     "a shorter display takes its room back from the gauges and Agents at work first")
        let sixteen = Layout.scene(in: CGRect(x: 0, y: 0, width: 1728, height: 1117), calendar: true, mac: true, ai: true)
        suite.expect((sixteen.frame(of: .cpu)?.height ?? 0) > 180 && (sixteen.frame(of: .agents)?.height ?? 0) > 202,
                     "a taller display gives its extra height to the gauges and Agents at work")

        // Fallbacks.
        let larger = Layout.scene(in: CGRect(x: 0, y: 0, width: 1352, height: 878), calendar: true, mac: true, ai: true)
        suite.expect(larger.player == nil && larger.calendar?.height == 334 && larger.mac == nil && larger.ai == nil,
                     "the 14-inch at Larger Text shows the calendar alone, with the rails off")
        let short = Layout.scene(in: CGRect(x: 0, y: 0, width: 1512, height: 930), calendar: true, mac: true, ai: true)
        suite.expect(short.playerFit == .short && short.player?.height == Layout.shortPlayerHeight
                     && (short.calendar?.height ?? 0) >= Layout.calendarMinimum,
                     "a short stage drops the player to its 150 fit before the calendar goes")
        let low = Layout.scene(in: CGRect(x: 0, y: 0, width: 1512, height: 700), calendar: true, mac: true, ai: true)
        suite.expect(low.player == nil && low.calendar == nil && low.row != nil,
                     "a stage too short for the calendar leaves the lock screen to the line")
        let squat = Layout.scene(in: CGRect(x: 0, y: 0, width: 1512, height: 900), calendar: true, mac: true, ai: true)
        suite.expect(squat.mac == nil && squat.ai == nil && squat.calendar != nil,
                     "a rail too short for its cards' least heights stays off")
        let wide = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let big = Layout.scene(in: wide, calendar: true, mac: true, ai: true)
        if let mac = big.mac, let cards = big.ai, let calendar = big.calendar {
            suite.expect(big.frame(of: .cpu)?.height == Layout.gaugeMaximum
                         && big.frame(of: .agents)?.height == Layout.agentsMaximum
                         && mac.minY - wide.minY == Layout.loginClearance && wide.maxY - mac.maxY > Layout.railTop
                         && wide.maxY - cards.maxY > Layout.railTop,
                         "on a large display the rails stop growing and keep their foot level with the player")
            suite.expect(calendar.height == Layout.calendarMaximum && wide.contains(mac) && wide.contains(cards),
                         "on a large display the calendar stops growing and every part stays on it")
        } else {
            suite.expect(false, "a large display has room for every part")
        }
        let noMac = Layout.scene(in: pro, calendar: true, mac: false, ai: true)
        suite.expect(noMac.mac == nil && noMac.calendar == nil && noMac.ai != nil && noMac.player != nil,
                     "with This Mac off neither its rail nor the calendar shows")
        let noCalendar = Layout.scene(in: pro, calendar: false, mac: true, ai: false)
        suite.expect(noCalendar.calendar == nil && noCalendar.mac != nil && noCalendar.ai == nil,
                     "without the Calendar section the stage holds the player alone")
        suite.expect(Layout.scene(in: pro, calendar: true, mac: false, ai: false).row?.width == 1000,
                     "without the rails the activities line keeps its width")
        suite.expect(Layout.scene(in: CGRect(x: 0, y: 0, width: 400, height: 956), calendar: true, mac: true, ai: true)
                        == NotchLockScreenScene()
                     && Layout.scene(in: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 956), calendar: true, mac: true, ai: true)
                        == NotchLockScreenScene(),
                     "a narrow or unreadable display keeps the lock screen as it is")

        typealias Support = NotchLockScreenSupport
        suite.expect(Support.loadLevel(0.49) == .good && Support.loadLevel(0.5) == .warning
                     && Support.loadLevel(0.79) == .warning && Support.loadLevel(0.8) == .critical,
                     "use is green under 50%, yellow from 50 to 80%, red above")
        suite.expect(Support.temperatureLevel(69.9) == .good && Support.temperatureLevel(70) == .warning
                     && Support.temperatureLevel(84.9) == .warning && Support.temperatureLevel(85) == .critical,
                     "temperature is green under 70 °C, yellow from 70 to 85, red above")
        suite.expect(Support.chargeLevel(100) == .good && Support.chargeLevel(50) == .good
                     && Support.chargeLevel(49) == .warning && Support.chargeLevel(20) == .warning
                     && Support.chargeLevel(19) == .critical && Support.chargeLevel(0) == .critical,
                     "charge is green from 50%, yellow from 20%, red under it")
        suite.expect(Support.temperatureFill(54) == 0.54 && Support.temperatureFill(120) == 1
                     && Support.ringFill(1.4) == 1 && Support.ringFill(-1) == 0 && Support.ringFill(.nan) == 0,
                     "a ring is full at 100% or 100 °C and never runs past it")
    }

    /// Which widgets show and in what order: the saved choice, what each
    /// place shows, and how the rails and the stage close up around a
    /// widget hidden or moved.
    static func widgetChoiceContracts(_ suite: TestSuite) {
        typealias Layout = NotchLockScreenLayout
        typealias Widgets = NotchLockScreenWidgets
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchLockScreenWidgetOrder] as? String == ""
                     && Defaults.registeredDefaults[DefaultsKey.notchLockScreenHiddenWidgets] as? String == ""
                     && SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchLockScreenWidgetOrder,
                                                                           DefaultsKey.notchLockScreenHiddenWidgets]),
                     "the widgets' order and hidden set start empty and travel with backups")
        let domain = "com.vorssaint.tests.notch-lock-screen-widgets"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let fresh = Widgets.stored(in: defaults)
        suite.expect(fresh == .initial && Widgets.initial.hidden.isEmpty
                     && Widgets.initial.order == NotchLockScreenWidget.allCases,
                     "with nothing saved every widget shows, in the order the lock screen first had")
        suite.expect(Widgets.initial.shown(in: .mac) == [.cpu, .gpu, .memory, .network, .accessories, .battery]
                     && Widgets.initial.shown(in: .stage) == [.calendar, .nowPlaying]
                     && Widgets.initial.shown(in: .ai) == [.claude, .codex, .lifetime, .agents, .streak],
                     "This Mac, the stage and the AI rail each list their own widgets, top to bottom")

        // Decoding.
        let odd = Widgets(order: "streak,sundial,cpu,cpu,,claude", hidden: "gone,battery,battery")
        suite.expect(odd.order(in: .ai) == [.streak, .claude, .codex, .lifetime, .agents]
                     && odd.order(in: .mac) == [.cpu, .gpu, .memory, .network, .accessories, .battery]
                     && odd.order.count == NotchLockScreenWidget.allCases.count,
                     "unknown and repeated entries drop out, and a widget the order misses joins the end of its place")
        suite.expect(odd.hidden == [.battery] && odd.shown(in: .mac).last == .accessories,
                     "a removed widget in the hidden set is ignored, and a hidden one leaves its place's list")

        // Round trips.
        let chosen = Widgets.initial.arranging([.battery, .network, .cpu, .gpu, .memory, .accessories])
            .showing(.lifetime, false).showing(.gpu, false).moving(.nowPlaying, by: -1)
        suite.expect(Widgets(order: chosen.encodedOrder, hidden: chosen.encodedHidden) == chosen
                     && chosen.encodedHidden == "gpu,lifetime",
                     "a saved order and hidden set read back as they were, the hidden set in display order")
        chosen.save(in: defaults)
        suite.expect(Widgets.stored(in: defaults) == chosen, "the choice saved in preferences reads back the same")
        suite.expect(Widgets(order: Widgets.initial.encodedOrder, hidden: "") == .initial
                     && Widgets.initial.showing(.gpu, false).showing(.gpu, true) == .initial,
                     "the first order reads back as itself, and showing a hidden widget restores it")

        // Reordering stays within a place.
        let reversed = Widgets.initial.arranging([.streak, .agents, .lifetime, .codex, .claude])
        suite.expect(reversed.order(in: .ai) == [.streak, .agents, .lifetime, .codex, .claude]
                     && reversed.order(in: .mac) == Widgets.initial.order(in: .mac)
                     && reversed.order(in: .stage) == Widgets.initial.order(in: .stage),
                     "arranging one place leaves the others as they were")
        suite.expect(Widgets.initial.arranging([.cpu, .claude]) == .initial
                     && Widgets.initial.arranging([.claude, .codex]) == .initial
                     && Widgets.initial.arranging([.claude, .claude, .codex, .lifetime, .agents]) == .initial
                     && Widgets.initial.arranging([]) == .initial,
                     "an arrangement mixing places, missing widgets or repeating one changes nothing")
        suite.expect(Widgets.initial.moving(.gpu, by: -1).order(in: .mac).prefix(2) == [.gpu, .cpu]
                     && Widgets.initial.moving(.calendar, by: 1).order(in: .stage) == [.nowPlaying, .calendar]
                     && Widgets.initial.moving(.cpu, by: -1) == .initial
                     && Widgets.initial.moving(.battery, by: 1) == .initial
                     && Widgets.initial.moving(.streak, by: 1) == .initial,
                     "VoiceOver's moves swap neighbours within a place and stop at either end")

        // The rails close up.
        let pro = CGRect(x: 0, y: 0, width: 1512, height: 982)
        guard let rails = Layout.railColumns(in: pro) else {
            suite.expect(false, "the 14-inch has room for both rails")
            return
        }
        func scene(_ widgets: Widgets, in screen: CGRect = pro) -> NotchLockScreenScene {
            Layout.scene(in: screen, calendar: true, mac: true, ai: true, widgets: widgets)
        }
        func hiding(_ hidden: [NotchLockScreenWidget]) -> Widgets { Widgets(order: [], hidden: Set(hidden)) }
        /// Each rail's rows 16 apart, top to bottom, with no hole between them.
        func packed(_ scene: NotchLockScreenScene, _ place: NotchLockScreenWidget.Place) -> Bool {
            let frames = scene.widgets.filter { $0.widget.place == place }.map(\.frame)
            let rows = Dictionary(grouping: frames, by: \.minY).values.map { $0[0] }.sorted { $0.minY > $1.minY }
            return zip(rows, rows.dropFirst()).allSatisfy { $0.minY == $1.maxY + Layout.cardGap }
                && rows.last?.minY == rails.left.minY
        }
        suite.expect(scene(fresh) == Layout.scene(in: pro, calendar: true, mac: true, ai: true),
                     "with nothing chosen the lock screen lays out exactly as before")
        let noMac = scene(hiding(NotchLockScreenWidget.Place.mac.widgets))
        suite.expect(noMac.mac == nil && !noMac.widgets.contains { $0.widget.place == .mac }
                     && noMac.ai != nil && noMac.calendar != nil,
                     "hiding every This Mac widget takes its rail off and keeps the calendar on the stage")
        let bare = scene(hiding(NotchLockScreenWidget.Place.mac.widgets + NotchLockScreenWidget.Place.ai.widgets))
        let off = Layout.scene(in: pro, calendar: true, mac: false, ai: false)
        suite.expect(bare.mac == nil && bare.ai == nil && bare.widgets.isEmpty && bare.row == off.row
                     && bare.row?.width == 1000 && bare.player == off.player,
                     "with every rail widget hidden the line widens as with both rails switched off")
        let noAI = scene(hiding(NotchLockScreenWidget.Place.ai.widgets))
        suite.expect(noAI.ai == nil && noAI.mac == scene(.initial).mac,
                     "hiding every AI widget takes the AI rail off and leaves This Mac's as it was")

        let roomy = scene(hiding([.accessories]))
        suite.expect(roomy.frame(of: .cpu)?.height == 251 && roomy.mac?.height == rails.left.height
                     && packed(roomy, .mac),
                     "a hidden card gives its height to the gauges, with no hole where it stood")
        let tall = scene(hiding([.accessories, .battery]))
        suite.expect(tall.frame(of: .cpu)?.height == Layout.gaugeMaximum && packed(tall, .mac)
                     && (tall.mac?.maxY ?? .infinity) < rails.left.maxY,
                     "gauges stop at their tallest, the rail standing on the stage's foot with the room over it left open")
        let quiet = scene(hiding([.agents]))
        suite.expect(quiet.ai?.height == Layout.claudeHeight + Layout.pairHeight + Layout.streakHeight + Layout.cardGap * 2
                     && packed(quiet, .ai),
                     "without Agents at work the AI rail is its fixed cards, standing on the stage's foot")
        suite.expect([roomy, tall, quiet, scene(.initial)].allSatisfy { scene in
            scene.widgets.allSatisfy { rails.left.contains($0.frame) || rails.right.contains($0.frame) }
        }, "every widget stays inside its rail's column")

        // Half cards pair in order and widen alone.
        let lone = scene(hiding([.lifetime, .gpu]))
        suite.expect(lone.frame(of: .codex)?.width == Layout.railWidth && lone.frame(of: .cpu)?.width == Layout.halfCard
                     && lone.frame(of: .memory)?.minY == lone.frame(of: .cpu)?.minY
                     && lone.frame(of: .memory)?.minX == rails.left.minX + Layout.halfCard + Layout.cardGap
                     && lone.frame(of: .network)?.width == Layout.railWidth && packed(lone, .mac),
                     "a half card pairs with the next one shown, and one left alone widens to the whole rail")
        let parted = Widgets.initial.arranging([.claude, .codex, .agents, .lifetime, .streak])
        let wide = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let apart = scene(parted, in: wide)
        if let codex = apart.frame(of: .codex), let lifetime = apart.frame(of: .lifetime), let agents = apart.frame(of: .agents) {
            suite.expect(codex.width == Layout.railWidth && lifetime.width == Layout.railWidth
                         && lifetime.height == Layout.pairHeight && codex.minY > agents.maxY && lifetime.maxY < agents.minY,
                         "with room, Codex and Lifetime moved apart each take a whole row where they were put")
        } else {
            suite.expect(false, "a large display has room for Codex and Lifetime apart")
        }
        let short = scene(parted)
        suite.expect(short.ai == scene(.initial).ai && short.frame(of: .lifetime) == scene(.initial).frame(of: .lifetime)
                     && short.frame(of: .agents) == scene(.initial).frame(of: .agents),
                     "a rail too short for Codex and Lifetime apart pairs them again rather than lose a card")
        let between = scene(Widgets.initial.arranging([.cpu, .accessories, .gpu, .memory, .network, .battery]))
        if let cpu = between.frame(of: .cpu), let gpu = between.frame(of: .gpu), let accessories = between.frame(of: .accessories),
           let memory = between.frame(of: .memory) {
            suite.expect(cpu.minY == gpu.minY && cpu.height == 180 && accessories.maxY + Layout.cardGap == cpu.minY
                         && memory.maxY + Layout.cardGap == accessories.minY && packed(between, .mac),
                         "on the 14-inch a gauge parted from its partner by a whole card pairs with the next gauge, in its place")
        } else {
            suite.expect(false, "the 14-inch keeps every This Mac card with Accessories between the gauges")
        }
        let swapped = scene(Widgets.initial.arranging([.claude, .lifetime, .codex, .agents, .streak]))
        suite.expect(swapped.frame(of: .lifetime)?.minX == rails.right.minX
                     && swapped.frame(of: .codex)?.minX == rails.right.minX + Layout.halfCard + Layout.cardGap,
                     "a pair keeps the order chosen, left to right")
        let squat = CGRect(x: 0, y: 0, width: 1512, height: 900)
        suite.expect(scene(.initial, in: squat).mac == nil && scene(hiding([.accessories]), in: squat).mac != nil,
                     "a rail too short for every card shows once a hidden card leaves the rest room")

        // The stage.
        let flipped = scene(Widgets.initial.moving(.nowPlaying, by: -1))
        if let calendar = flipped.calendar, let player = flipped.player, let row = flipped.row {
            suite.expect(calendar.minY == pro.minY + Layout.loginClearance && calendar.height == 231
                         && player.minY == calendar.maxY + Layout.stageGap && player.maxY <= row.minY - Layout.stageGap
                         && flipped.playerFit == .regular,
                     "with Now Playing first it stands over the calendar, which takes the stage's foot")
        } else {
            suite.expect(false, "the 14-inch has room for the player over the calendar")
        }
        let silent = scene(hiding([.nowPlaying]))
        suite.expect(silent.player == nil && silent.playerFit == nil
                     && silent.calendar?.minY == pro.minY + Layout.loginClearance
                     && silent.calendar?.height == Layout.calendarMaximum,
                     "a hidden player gives the calendar the stage's foot and its room")
        let larger = CGRect(x: 0, y: 0, width: 1352, height: 878)
        let noCalendar = scene(hiding([.calendar]), in: larger)
        suite.expect(noCalendar.calendar == nil && noCalendar.playerFit == .regular
                     && noCalendar.player?.minY == larger.minY + Layout.loginClearance,
                     "with the calendar hidden the player takes the room it kept for it, even at Larger Text")
        suite.expect(scene(hiding([.calendar, .nowPlaying])).calendar == nil && scene(hiding([.calendar, .nowPlaying])).player == nil,
                     "a stage with both widgets hidden stays empty")

        // Windows.
        let panels = scene(.initial).panels
        suite.expect(panels.map { $0.widgets.map(\.widget) }
                        == [Array(NotchLockScreenWidget.Place.mac.widgets), [.claude, .codex, .lifetime], [.agents], [.streak]]
                     && panels.map(\.interactive) == [false, false, true, true]
                     && panels.first?.frame == scene(.initial).mac,
                     "read-only widgets in a row share a window; Agents at work and Streak each have their own")
        let split = scene(Widgets.initial.arranging([.claude, .agents, .codex, .lifetime, .streak])).panels
        suite.expect(split.map { $0.widgets.map(\.widget) } == [Array(NotchLockScreenWidget.Place.mac.widgets), [.claude], [.agents],
                                                                 [.codex, .lifetime], [.streak]],
                     "a widget that takes the pointer splits the read-only run around it")
        suite.expect(split.allSatisfy { panel in
            panel.widgets.allSatisfy { CGRect(origin: .zero, size: panel.frame.size).contains($0.frame) }
                && panel.widgets.first?.frame.minY == 0
        } && split.indices.allSatisfy { i in split.indices.allSatisfy { j in i == j || !split[i].frame.intersects(split[j].frame) } },
                     "each window holds its widgets from its top left, and no two windows overlap")
    }

    static func widgetContracts(_ suite: TestSuite) {
        typealias Support = NotchLockScreenSupport
        suite.expect(Support.dayWindow(count: 6, upcoming: 2, fits: 4) == 1..<5,
                     "the calendar keeps the last event past above the next one")
        suite.expect(Support.dayWindow(count: 6, upcoming: 0, fits: 4) == 0..<4
                     && Support.dayWindow(count: 3, upcoming: 1, fits: 4) == 0..<3,
                     "with nothing past the calendar starts at the next event, and a short day shows it all")
        suite.expect(Support.dayWindow(count: 6, upcoming: 5, fits: 4) == 2..<6
                     && Support.dayWindow(count: 6, upcoming: 2, fits: 0) == 0..<0,
                     "near the day's end the calendar reaches back rather than leave rows empty")
        let today = Support.streak([true, true, false, true, true, true])
        suite.expect(today.current == 3 && today.best == 3, "a streak counts the days in a row ending today")
        let waiting = Support.streak([true, true, true, true, false])
        suite.expect(waiting.current == 4 && waiting.best == 4, "a day not yet used leaves yesterday's streak standing")
        let broken = Support.streak([true, true, true, false, false])
        suite.expect(broken.current == 0 && broken.best == 3 && Support.streak([]) == (0, 0),
                     "a day missed before today breaks the streak, and the best run stays")
    }

    static func islandContracts(_ suite: TestSuite) {
        typealias Layout = NotchLockScreenLayout
        let measured = CGRect(x: 0, y: 0, width: 1470, height: 956)
        // The fit a person sets moves the island's camera. The locked island
        // is drawn at exactly the fitted camera's height and the music strip's
        // size, even when the fit leaves half a point or the width is odd; only
        // its window grows out to whole points, with the extra room clear.
        let fits = [NotchCameraFit(width: 6, height: 3), NotchCameraFit(width: 0, height: 0.5),
                    NotchCameraFit(width: 0, height: -0.5), NotchCameraFit(width: 1, height: 1.5)]
        for fit in fits {
            let fitted = NotchGeometry(screen: measured, safeAreaTop: 32, cameraWidth: 179, cameraFit: fit)
            let music = fitted.lockScreenMusicGeometry
            let camera = fitted.bareCutout
            guard let surface = Layout.islandSurface(in: measured, cameraWidth: camera.width, cameraHeight: camera.height,
                                                     wing: music.compactActivityWingWidth) else {
                suite.expect(false, "a notched display has room for the padlock with a fit of \(fit)")
                continue
            }
            let window = Layout.islandFrame(around: surface)
            suite.expect(surface.height == 32 + fit.height && surface.height == camera.height
                         && surface.size == music.compactActivitySize
                         && surface.maxY == measured.maxY && surface.midX == measured.midX,
                         "with a fit of \(fit) the padlock's island is the fitted camera's height and the strip's size, centred on the camera")
            suite.expect(window == window.integral && window.contains(surface) && window.maxY == surface.maxY
                         && window.width - surface.width < 2 && window.height - surface.height < 1,
                         "with a fit of \(fit) the island's window lands on whole points around it, the island at its top")
        }
        var crowded = NotchGeometry(screen: measured, safeAreaTop: 32, cameraWidth: 179)
        let wing = crowded.lockScreenMusicGeometry.compactActivityWingWidth
        crowded.compactSideRoom = 0
        suite.expect(crowded.lockScreenMusicGeometry.compactActivityWingWidth == wing && wing < 44,
                     "menus beside the camera while unlocked do not narrow the locked island")
        suite.expect(Layout.islandSurface(in: measured, cameraWidth: 0, cameraHeight: 32, wing: wing) == nil
                     && Layout.islandSurface(in: measured, cameraWidth: 179, cameraHeight: .nan, wing: wing) == nil
                     && Layout.islandSurface(in: measured, cameraWidth: 179, cameraHeight: 32, wing: 0) == nil
                     && Layout.islandSurface(in: measured, cameraWidth: 1460, cameraHeight: 32, wing: wing) == nil,
                     "no padlock without a camera to hang it from, or room beside it")
    }

    static func contentContracts(_ suite: TestSuite) {
        suite.expect(NotchLockScreenSupport.activities(timer: true, calendar: true, agents: true, downloads: true)
                        == NotchLockScreenActivity.allCases,
                     "the line reads the timer, the next event, agents and downloads, in that order")
        suite.expect(NotchLockScreenSupport.activities(timer: false, calendar: false, agents: true, downloads: true)
                        == [.agents, .downloads],
                     "only live activities are read out")

        let hidden = NotchAgentPrivacy(hidesProjects: false, hidesAmounts: true)
        suite.expect(NotchLockScreenSupport.lineReadout(.cost, privacy: hidden) == .elapsed
                     && NotchLockScreenSupport.lineReadout(.cost, privacy: NotchAgentPrivacy()) == .cost
                     && NotchLockScreenSupport.lineReadout(.tokens, privacy: hidden) == .tokens,
                     "with amounts hidden the line reads the time worked instead of the cost")

        var countdown = NotchTimerSession()
        countdown.start(mode: .timer, minutes: 5, now: 100)
        suite.expect(!NotchLockScreenSupport.timerFinished(countdown, at: 399)
                     && NotchLockScreenSupport.timerFinished(countdown, at: 400),
                     "a countdown that runs out while locked reads as finished")
        countdown.pause(at: 200)
        suite.expect(!NotchLockScreenSupport.timerFinished(countdown, at: 10_000), "a paused countdown never finishes")
        var stopwatch = NotchTimerSession()
        stopwatch.start(mode: .stopwatch, minutes: 0, now: 100)
        suite.expect(!NotchLockScreenSupport.timerFinished(stopwatch, at: 100_000), "a stopwatch never finishes")

        let stamps: [(TimeInterval, String)] = [
            (0, "0:00"), (61.9, "1:01"), (3661, "1:01:01"), (-5, "0:00"), (.nan, "0:00"), (.infinity, "0:00"),
        ]
        for (interval, expected) in stamps {
            suite.expect(NotchLockScreenSupport.timestamp(interval) == expected,
                         "a song position of \(interval) s reads \(expected)")
        }
    }

    static func soundContracts(_ suite: TestSuite) {
        let lock = NotchLockScreenSupport.soundURL(locking: true)
        let unlock = NotchLockScreenSupport.soundURL(locking: false)
        suite.expect(lock != nil && unlock != nil && lock != unlock, "locking and unlocking each have their own sound")
        suite.expect([lock, unlock].allSatisfy { $0.map { FileManager.default.fileExists(atPath: $0.path) } == true },
                     "both sounds are files this Mac has")
    }

    /// The moon wallpaper's sky, the phase it shows and where anything may
    /// move. Nothing here draws a whole frame or sets a desktop picture.
    static func wallpaperContracts(_ suite: TestSuite) {
        typealias Scene = NotchLockWallpaperScene
        // A full moon: 25 January 2024, 17:54 UTC.
        let full = Scene.phase(at: Date(timeIntervalSince1970: 1_706_205_240))
        suite.expect(abs(full - 0.5) < 0.02, "a known full moon reads as full, got \(full)")
        suite.expect(Scene.phase(at: Date(timeIntervalSince1970: 947_182_440)) < 0.001,
                     "the reference new moon reads as new")
        suite.expect(Scene.sun(phase: 0).z < -0.9 && Scene.sun(phase: 0.5).z > 0.9,
                     "a new moon is lit from behind and a full one from the front")
        suite.expect(Scene.sun(phase: 0.25).x > 0.9 && Scene.sun(phase: 0.75).x < -0.9,
                     "it waxes on the right and wanes on the left")
        suite.expect(Scene.earthshine(phase: 0) > Scene.earthshine(phase: 0.5),
                     "earthshine is brightest at new moon")

        // The built-in displays and their scaled sizes, in points.
        let sizes: [(Double, Double)] = [(1470, 956), (1512, 982), (1728, 1117), (1800, 1169), (2056, 1329), (1280, 832)]
        for (width, height) in sizes {
            let scene = Scene(width: width, height: height, scale: 2)
            let label = "\(Int(width))×\(Int(height))"
            let moon = scene.moonCentre, r = scene.moonRadius
            // The crest clears the rails, and the disc the login controls.
            suite.expect(Double(moon.y) - r > scene.railBottom, "\(label): the moon crests under the rails")
            let login = scene.systemZones.last!
            let corner = (x: login.x + login.w, y: login.y + login.h)
            var clearOfLogin = true
            var y = login.y
            while y <= corner.y {
                let dx = corner.x - Double(moon.x), dy = y - Double(moon.y)
                if (dx * dx + dy * dy).squareRoot() < r + Scene.moonFade { clearOfLogin = false }
                y += 4
            }
            suite.expect(clearOfLogin, "\(label): the moon and its fade keep off the login controls")
            suite.expect(Double(moon.x) - r < width - 120, "\(label): enough of the moon stays on the display")
            let stars = scene.sparklingStars()
            suite.expect(!stars.isEmpty, "\(label): some stars are bright enough to sparkle")
            suite.expect(stars.allSatisfy { scene.isOpenSky($0.x, $0.y, clearance: 20) },
                         "\(label): every sparkle is out in open sky")
            for zone in scene.wells + scene.systemZones {
                let centre = (x: zone.x + zone.w / 2, y: zone.y + zone.h / 2)
                suite.expect(!scene.isOpenSky(centre.x, centre.y, clearance: 0),
                             "\(label): nothing moves over a widget or the system's controls")
            }
        }
    }
}
