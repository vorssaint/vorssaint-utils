// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchHomeTests {
    static func run(_ suite: TestSuite) {
        let home = NotchHomeSupport.self

        suite.expect(home.leftFaces(agents: false, musicPlaying: false, agentsWorking: true) == [.music],
                     "without the agents page the player card has no second face")
        suite.expect(home.leftFaces(agents: true, musicPlaying: false, agentsWorking: false) == [.music, .agents],
                     "at rest the player leads and the agents are a swipe away")
        suite.expect(home.leftFaces(agents: true, musicPlaying: false, agentsWorking: true) == [.agents, .music],
                     "an agent at work with nothing playing comes first")
        suite.expect(home.leftFaces(agents: true, musicPlaying: true, agentsWorking: true) == [.music, .agents],
                     "music playing keeps the player first while agents work")

        suite.expect(home.rightFaces(calendar: false, eventSoon: true) == [.levels],
                     "without the calendar page the levels card has no second face")
        suite.expect(home.rightFaces(calendar: true, eventSoon: false) == [.levels, .calendar],
                     "at rest the levels lead and the calendar is a swipe away")
        suite.expect(home.rightFaces(calendar: true, eventSoon: true) == [.calendar, .levels],
                     "an event about to start comes first")
        suite.expect(home.rightFaces(calendar: true, eventSoon: false, files: true) == [.files, .levels, .calendar],
                     "files sent to the island add their own face, first")
        suite.expect(home.rightFaces(calendar: true, eventSoon: false, files: false) == [.levels, .calendar],
                     "with no files only the levels and the calendar remain")
        suite.expect(home.rightFaces(calendar: true, eventSoon: true, files: true) == [.calendar, .files, .levels],
                     "an event about to start still leads ahead of files")
        suite.expect(home.rightFaces(calendar: false, eventSoon: false, files: true) == [.files, .levels],
                     "files get their face without the calendar page")

        typealias Launch = NotchHomeSupport.Launch
        for launch in [Launch.tool("colorPicker"), .page(.clipboard)] {
            suite.expect(Launch(stored: launch.stored) == launch, "a launch survives being stored")
        }
        suite.expect(Launch(stored: "page:nowhere") == nil && Launch(stored: "colorPicker") == nil,
                     "a stored launch that no longer names anything is ignored")

        let controls: [NotchControlItem] = [.volume, .music, .mixer, .keepAwake, .timer, .calendar]
        let opened = Date(timeIntervalSinceReferenceDate: 1_000_000)
        func recent(_ launch: Launch?, after seconds: TimeInterval, available: Bool = true) -> NotchHomeSupport.Slot? {
            home.recentSlot(launch, at: opened, now: opened.addingTimeInterval(seconds), shortcuts: controls,
                            available: { _ in available })
        }
        suite.expect(recent(.tool("colorPicker"), after: 5) == .tool("colorPicker"),
                     "a tool just opened from Tools takes the place")
        suite.expect(recent(.page(.clipboard), after: 5) == .page(.clipboard),
                     "a page just opened from Explore takes the place")
        suite.expect(recent(.tool("colorPicker"), after: home.launchLifetime - 1) == .tool("colorPicker")
                     && recent(.tool("colorPicker"), after: home.launchLifetime) == nil,
                     "after three minutes the place returns to Tools")
        suite.expect(recent(.tool("colorPicker"), after: -60) == nil, "a launch dated in the future is ignored")
        suite.expect(recent(.tool("keepAwake"), after: 5) == nil && recent(.page(.mixer), after: 5) == nil
                     && recent(.page(.calendar), after: 5) == nil,
                     "a tool or page the row already reaches does not take the place")
        suite.expect(recent(.page(.home), after: 5) == nil && recent(.page(.tools), after: 5) == nil
                     && recent(.page(.controls), after: 5) == nil,
                     "Home, Controls and Tools never take the place")
        suite.expect(recent(.page(.timer), after: 5) == .page(.timer),
                     "the timer's page may take the place, the timer being off Home's row")
        suite.expect(recent(.tool("colorPicker"), after: 5, available: false) == nil,
                     "a launch no longer available is ignored")
        suite.expect(home.recentSlot(nil, at: nil, now: opened, shortcuts: controls, available: { _ in true }) == nil,
                     "nothing opened, nothing recent")

        suite.expect(home.rail(controls: controls, recent: .tool("colorPicker"), toolsPage: true)
                        == [.control(.mixer), .control(.keepAwake), .tool("colorPicker"), .control(.calendar)],
                     "the last launch takes the timer's place on Home's row")
        suite.expect(home.rail(controls: controls, recent: .page(.clipboard), toolsPage: true)
                        == [.control(.mixer), .control(.keepAwake), .page(.clipboard), .control(.calendar)],
                     "a page from Explore takes the same place")
        suite.expect(home.rail(controls: controls, recent: nil, toolsPage: true)
                        == [.control(.mixer), .control(.keepAwake), .tools, .control(.calendar)],
                     "with nothing recent, Tools holds the place")
        suite.expect(home.rail(controls: [.mixer, .calendar], recent: .tool("colorPicker"), toolsPage: true)
                        == [.control(.mixer), .control(.calendar), .tool("colorPicker")],
                     "without the timer the place joins the end of the row")
        suite.expect(home.rail(controls: controls, recent: nil, toolsPage: false)
                        == [.control(.mixer), .control(.keepAwake), .control(.calendar)],
                     "without the Tools page and nothing recent there is no place, and the timer stays off Home")

        suite.expect(home.page(.music, in: [.home, .music]) == .music, "a visible page opens as itself")
        suite.expect(home.page(.controls, in: [.home, .music]) == .home,
                     "a link to hidden Controls opens Home, which carries its controls")
        suite.expect(home.page(.home, in: [.controls, .music]) == .controls,
                     "a link to hidden Home opens Controls")
        suite.expect(home.page(.timer, in: [.home]) == nil && home.page(.home, in: [.music]) == nil,
                     "any other hidden page stays closed")

        suite.expect(NotchModule.allCases.first == .home, "Home leads the default page order")
        let keys = NotchModule.allCases.map(\.shortcutKey)
        suite.expect(Set(keys).count == keys.count, "Home's shortcut takes no other page's key")
        suite.expect(NotchModule.home.isAvailable(in: UserDefaults(suiteName: "com.vorssaint.tests.notch-home")!),
                     "Home needs no optional feature")
        let hidden = (Defaults.registeredDefaults[DefaultsKey.notchHiddenModules] as? String ?? "").split(separator: ",")
        suite.expect(hidden.contains("controls") && !hidden.contains("home"),
                     "Home replaces Controls by default; Controls stays one switch away")
    }
}
