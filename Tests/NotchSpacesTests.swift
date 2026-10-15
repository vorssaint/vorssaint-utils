// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum NotchSpacesTests {
    static func run(_ suite: TestSuite) {
        NotchSpacesClickTests.run(suite)
        suite.expect(SpaceHopSupport.desktopHotKeyID(number: 1) == 118
                     && SpaceHopSupport.desktopHotKeyID(number: 9) == 126
                     && SpaceHopSupport.desktopHotKeyID(number: nil) == nil
                     && SpaceHopSupport.desktopHotKeyID(number: 0) == nil
                     && SpaceHopSupport.desktopHotKeyID(number: 10) == nil,
                     "only numbered desktops with a supported system shortcut use direct travel")
        let uuid = "A65092B1-A9A6-4E30-A905-7D4A020271DF"
        let secondUUID = "B65092B1-A9A6-4E30-A905-7D4A020271DF"
        let strings = FeatureStrings.notchSpaces(.enUS)
        let named = NotchSpace(id: 10, uuid: uuid, desktopNumber: 2, current: true, name: "Writing")
        suite.expect(named.currentLabel(strings) == "Space 2 - Writing" && named.compactLabel == "Writing",
                     "named Space pills show only the name while accessibility retains the desktop number")
        let unnamed = NotchSpace(id: 20, uuid: nil, desktopNumber: 3, current: false, name: nil)
        suite.expect(unnamed.currentLabel(strings) == "Space 3" && unnamed.compactLabel == "3",
                     "unnamed desktops retain a useful number without an empty separator")
        for height: CGFloat in [18, 24, 32, 40] {
            let badge = NotchSpacesLayout.badgeHeight(contentHeight: height)
            let gap = NotchSpacesLayout.edgeGap(contentHeight: height)
            suite.expect(badge + gap * 2 == height && badge <= 20,
                         "Space pills leave balanced top/bottom and end gaps in a \(height)-point strip")
        }
        suite.expect(NotchSpacesLayout.labelWidth("3") < NotchSpacesLayout.labelWidth("test")
                     && NotchSpacesLayout.labelWidth(String(repeating: "x", count: 80)) == NotchSpacesLayout.titleWidth,
                     "compact widths follow the actual labels and bound long names")
        suite.expect(NotchSpacesLayout.listWidth(count: 0) == 0
                     && NotchSpacesLayout.listWidth(count: 1) > 0
                     && NotchSpacesLayout.listWidth(count: 100) <= 150,
                     "many desktops stay inside the strip's scrollable width budget")
        suite.expect(NotchSupport.restingActivity(selected: nil, spacesEnabled: true, spacesAvailable: true) == .spaces
                     && NotchSupport.restingActivity(selected: .timer, spacesEnabled: true, spacesAvailable: true) == .timer
                     && NotchSupport.restingActivity(selected: nil, spacesEnabled: false, spacesAvailable: true) == nil
                     && NotchSupport.restingActivity(selected: nil, spacesEnabled: true, spacesAvailable: false) == nil,
                     "the independent toggle controls Spaces while preserving live activities")
        let first = NotchSpacesSupport.row(ids: [1], fullscreen: [], current: 1,
                                           uuids: [:], names: [:], displayIdentifier: "screen-A")[0]
        suite.expect(first.nameKey == "display:screen-A:desktop:1",
                     "Desktop 1 remains renamable when the window server omits its UUID")
        let fallbackNames = [first.nameKey!: "Main"]
        let renamed = NotchSpacesSupport.row(ids: [1], fullscreen: [], current: 1,
                                             uuids: [:], names: fallbackNames, displayIdentifier: "screen-A")
        let otherDisplay = NotchSpacesSupport.row(ids: [1], fullscreen: [], current: 1,
                                                  uuids: [:], names: fallbackNames, displayIdentifier: "screen-B")
        suite.expect(renamed.first?.name == "Main" && otherDisplay.first?.name == nil,
                     "UUID-less desktop names persist by display without leaking to another screen")
        suite.expect(NotchSpacesLayout.capsuleContentWidth(spaces: renamed, external: true) >= 44,
                     "external capsules reserve a usable width even for one short desktop name")
        let labels: [String?] = [nil, "test", "a longer desktop name"]
        let selections = labels.indices.map { current in
            labels.indices.map { index in
                NotchSpace(id: UInt64(index + 1), uuid: nil, desktopNumber: index + 1,
                           current: index == current, name: labels[index])
            }
        }
        let wings = selections.map { NotchSpacesLayout.wingWidth(spaces: $0) }
        suite.expect(Set(wings).count == 1,
                     "switching to Desktop 1 or any other desktop keeps the hanging island's width unchanged")
        for external in [false, true] {
            let widths = selections.map { NotchSpacesLayout.capsuleContentWidth(spaces: $0, external: external) }
            suite.expect(Set(widths).count == 1,
                         "switching Spaces keeps capsule width unchanged on built-in and external displays")
        }
        suite.expect(NotchSpacesLayout.wingWidth(spaces: Array(selections[0].reversed())) == wings[0],
                     "reordering the same named desktops does not change their width budget")
        let width = NotchSpacesLayout.expandedPillWidth(available: 320, count: 3)
        suite.expect(abs(width * 3 + NotchSpacesLayout.spacing * 2 - 320) < 0.01
                     && width > NotchSpacesLayout.badgeWidth,
                     "external-display pills expand equally to fill the available width")
        for scale: CGFloat in [1, 2] {
            let available: CGFloat = 385.5
            let pill = NotchSpacesLayout.expandedPillWidth(available: available, count: 3, scale: scale)
            let content = pill * 3 + NotchSpacesLayout.spacing * 2
            suite.expect(pill * scale == (pill * scale).rounded()
                         && content <= available && available - content < 3 / scale,
                         "fractional widths leave a small centered remainder instead of drifting to the left")
        }
        suite.expect(NotchSpacesLayout.expandedPillWidth(available: 80, count: 10) == 44
                     && NotchSpacesLayout.expandedPillWidth(available: 80, count: 0) == 0,
                     "crowded rows scroll with usable targets, and empty rows do not divide by zero")
        let names = [uuid: "Writing", secondUUID: "Mail"]
        let row = NotchSpacesSupport.row(ids: [5, 9, 8], fullscreen: [9], current: 9,
                                         uuids: [5: uuid.lowercased(), 8: secondUUID], names: names)
        suite.expect(row.map(\.desktopNumber) == [1, nil, 2]
                     && row.map(\.current) == [false, true, false],
                     "fullscreen Spaces are marked current without consuming desktop numbers")
        suite.expect(row.map(\.name) == ["Writing", nil, "Mail"],
                     "names resolve against normalized UUIDs")
        let reordered = NotchSpacesSupport.row(ids: [8, 5], fullscreen: [], current: 5,
                                               uuids: [5: uuid, 8: secondUUID], names: names)
        suite.expect(reordered.map(\.name) == ["Mail", "Writing"]
                     && reordered.map(\.desktopNumber) == [1, 2],
                     "renumbering desktops preserves the name attached to each Space")
        let restarted = NotchSpacesSupport.row(ids: [100], fullscreen: [], current: 100,
                                               uuids: [100: uuid], names: names)
        suite.expect(restarted.first?.name == "Writing", "a new runtime id retains the UUID's name")
        let missing = NotchSpacesSupport.row(ids: [1, 1, 2], fullscreen: [], current: 1,
                                             uuids: [1: "not a UUID"], names: ["1": "Wrong"], desktopOffset: 3)
        suite.expect(missing.map(\.desktopNumber) == [4, 5] && missing.allSatisfy { $0.uuid == nil && $0.name == nil },
                     "duplicates are ignored and missing identity never borrows an unrelated name")
        suite.expect(NotchSpacesSupport.adjacent(to: 5, in: row, forward: true) == 9
                     && NotchSpacesSupport.adjacent(to: 9, in: row, forward: true) == 8,
                     "adjacent travel includes full-screen Spaces in Mission Control order")
        suite.expect(NotchSpacesSupport.adjacent(to: 5, in: row, forward: false) == nil
                     && NotchSpacesSupport.adjacent(to: 8, in: row, forward: true) == nil
                     && NotchSpacesSupport.adjacent(to: 99, in: row, forward: true) == nil,
                     "row edges and removed Spaces do not wrap or guess")
        suite.expect(NotchSpacesSupport.normalizedName(" \nWriting  ") == "Writing"
                     && NotchSpacesSupport.normalizedName(" \n") == nil
                     && NotchSpacesSupport.normalizedName(String(repeating: "x", count: 90))?.count == 80,
                     "names trim whitespace, clear on empty input and have a bounded length")
        let domain = "com.vorssaint.tests.notch-spaces.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.register(defaults: Defaults.registeredDefaults)
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: AppFeature.notch.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchSpacesSupport.isEnabled(in: defaults), "Spaces runs as part of the installed island")
        defaults.set(NotchIdleContent.agents.rawValue, forKey: DefaultsKey.notchIdleContent)
        for enabled in [true, false, true] {
            defaults.set(enabled, forKey: DefaultsKey.notchSpacesIdleEnabled)
            suite.expect(defaults.string(forKey: DefaultsKey.notchIdleContent) == NotchIdleContent.agents.rawValue,
                         "toggling the independent Spaces preference preserves the saved AI limits choice")
        }
        suite.expect(NotchIdleContent.allCases == [.none, .battery, .music, .agents, .spaces],
                     "Spaces joins the existing At rest options")
        NotchSpacesSupport.selectResting(.spaces, in: defaults)
        suite.expect(NotchSpacesSupport.restingChoice(in: defaults) == .spaces
                     && defaults.string(forKey: DefaultsKey.notchIdleContent) == NotchIdleContent.agents.rawValue,
                     "choosing the Spaces card enables its independent toggle without overwriting AI idle settings")
        defaults.set(false, forKey: DefaultsKey.notchSpacesIdleEnabled)
        suite.expect(NotchSpacesSupport.restingChoice(in: defaults) != .spaces,
                     "turning the independent toggle off unselects the Spaces card")
        defaults.set(false, forKey: DefaultsKey.notchSpacesEnabled)
        suite.expect(!NotchSpacesSupport.isEnabled(in: defaults)
                     && defaults.string(forKey: DefaultsKey.notchIdleContent) == NotchIdleContent.agents.rawValue,
                     "disabling Spaces stops its work without changing the saved AI limits choice")
        defaults.set(false, forKey: DefaultsKey.notchSpacesIdleEnabled)
        NotchSpacesSupport.selectResting(.spaces, in: defaults)
        suite.expect(!defaults.bool(forKey: DefaultsKey.notchSpacesIdleEnabled)
                     && !NotchSupport.canRest(with: .spaces, in: defaults),
                     "disabled Spaces is absent from At rest and cannot be selected")
        defaults.set(true, forKey: DefaultsKey.notchSpacesEnabled)
        defaults.set("spaces", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchSpacesSupport.isEnabled(in: defaults), "a hidden Spaces page stops its work")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(false, forKey: AppFeature.notch.availabilityKey)
        suite.expect(!NotchSpacesSupport.isEnabled(in: defaults), "uninstalling the island stops its Spaces work")
        var builtIn = named
        builtIn.displayID = 1
        var external = unnamed
        external.displayID = 2
        let connected = [builtIn, external]
        suite.expect(NotchSpacesSupport.visibleSpaces(connected, on: 1, allDisplays: false) == [builtIn]
                     && NotchSpacesSupport.visibleSpaces(connected, on: 2, allDisplays: false) == [external],
                     "default scope follows the pointer display")
        suite.expect(NotchSpacesSupport.visibleSpaces(connected, on: 1, allDisplays: true) == connected
                     && NotchSpacesSupport.visibleSpaces(connected, on: 2, allDisplays: true) == connected,
                     "shared scope keeps every display's Spaces in stable order when the pointer moves")
        let externalSecond = NotchSpace(id: 30, uuid: nil, desktopNumber: 4, current: false, name: "Other",
                                   displayID: external.displayID)
        let desktops = [builtIn, external, externalSecond]
        let leftExternal: [CGDirectDisplayID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 1400, height: 900),
            2: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        ]
        suite.expect(NotchSpacesSupport.orderedByDisplayPosition(desktops, frames: leftExternal)
                     == [external, externalSecond, builtIn],
                     "left-hand display comes first without changing its desktop order, names or numbers")
        let rightExternal: [CGDirectDisplayID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 1400, height: 900),
            2: CGRect(x: 1400, y: 0, width: 1920, height: 1080),
        ]
        suite.expect(NotchSpacesSupport.orderedByDisplayPosition(desktops, frames: rightExternal) == desktops,
                     "rearranging a display to the right updates its group position")
        let stacked: [CGDirectDisplayID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 1400, height: 900),
            2: CGRect(x: 0, y: 900, width: 1920, height: 1080),
        ]
        suite.expect(NotchSpacesSupport.orderedByDisplayPosition(desktops, frames: stacked)
                     == [external, externalSecond, builtIn],
                     "vertically aligned displays use top-to-bottom order")
        suite.expect(NotchSpacesSupport.orderedByDisplayPosition(desktops, frames: [:]) == desktops
                     && NotchSpacesSupport.orderedByDisplayPosition(desktops, frames: [1: leftExternal[1]!]) == desktops,
                     "missing display frames retain stable source order after known displays")
        suite.expect(!defaults.bool(forKey: DefaultsKey.notchSpacesAllDisplays),
                     "sharing Spaces across displays is opt-in")
        let exported = SettingsBackupSupport.exportKeys()
        suite.expect(exported.contains(DefaultsKey.notchIdleContent)
                     && exported.contains(DefaultsKey.notchSpacesIdleEnabled)
                     && exported.contains(DefaultsKey.notchSpacesEnabled)
                     && exported.contains(DefaultsKey.notchSpacesShowCurrent)
                     && exported.contains(DefaultsKey.notchSpacesAllDisplays)
                     && !exported.contains(DefaultsKey.notchSpacesNames),
                     "display preferences travel in backups while machine-specific UUID names stay local")
        for language in AppLanguage.allCases {
            let text = FeatureStrings.notchSpaces(language)
            suite.expect(!text.title.isEmpty && !text.description.isEmpty && !text.shortcutHint.isEmpty
                         && !text.allDisplays.isEmpty && !text.allDisplaysHint.isEmpty
                         && !text.gestureHint.isEmpty && !text.showWhenIdle.isEmpty
                         && text.spaceFormat.contains("%d") && text.desktopFormat.contains("%d")
                         && row[1].title(text) == text.fullscreen,
                         "Spaces labels cover \(language.rawValue), including full-screen apps")
        }
        suite.expect(NotchSupport.compactActivities(timer: true, downloads: false, agents: false,
                                                    calendar: false, music: false, spaces: true) == [.timer, .spaces],
                     "the current Space is a resting activity behind an active timer")
    }
}
