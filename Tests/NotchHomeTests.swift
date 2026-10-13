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
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchHomeEnabled] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.notchHomeModule] as? String == NotchModule.controls.rawValue,
                     "Home is a page to choose: off by default, and the island keeps opening where it did")
        let defaults = UserDefaults(suiteName: "com.vorssaint.tests.notch-home-enabled")!
        defaults.removePersistentDomain(forName: "com.vorssaint.tests.notch-home-enabled")
        defer { defaults.removePersistentDomain(forName: "com.vorssaint.tests.notch-home-enabled") }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        suite.expect(!NotchSupport.modules(in: defaults).contains(.home), "Home is not a page until chosen")
        defaults.set(true, forKey: DefaultsKey.notchHomeEnabled)
        suite.expect(NotchSupport.modules(in: defaults).first == .home, "once chosen, Home leads the pages")
    }
}
