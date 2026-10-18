// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI

/// Production panel state and Command Bar builders run against isolated
/// defaults and services, without installing taps or requesting permission.
enum ScrollDirectionControlsTests {
    static let keys = [DefaultsKey.scrollInverterEnabled,
                       DefaultsKey.scrollInverterHorizontalEnabled,
                       DefaultsKey.scrollInverterTrackpadEnabled,
                       DefaultsKey.scrollInverterTrackpadHorizontalEnabled]
    static let commandIDs = ["toggle.scrollInverter.vertical", "toggle.scrollInverter.horizontal",
                             "toggle.scrollInverter.trackpad.vertical", "toggle.scrollInverter.trackpad.horizontal"]

    enum DefaultsHost { static var standard = Foundation.UserDefaults() }
    final class Access {
        static let shared = Access()
        var accessibility = true
        var requests = 0
    }
    final class Runtime {
        static let shared = Runtime()
        var synced: [[AppFeature]] = []
        func sync(_ features: [AppFeature]) { synced.append(features) }
    }
    enum HUD {
        static func show(icon: String, message: String) {}
    }
    struct Entry {
        enum Icon { case symbol(String) }
        enum Trouble { case needsPermission }
        let id: String
        let title: String
        let subtitle: String
        let keywords: String
        let icon: Icon
        let isActive: Bool
        let trouble: Trouble?
        let run: (Int?) -> Void
    }
    enum Catalog {
        typealias UserDefaults = DefaultsHost
        typealias Permissions = Access
        typealias FeatureRuntime = Runtime
        typealias QuickToolHUD = HUD
        typealias CommandBarEntry = Entry
    }
    @propertyWrapper struct State<Value> {
        final class Storage {
            var value: Value
            init(_ value: Value) { self.value = value }
        }
        private let storage: Storage
        init(wrappedValue: Value) { storage = Storage(wrappedValue) }
        var wrappedValue: Value {
            get { storage.value }
            nonmutating set { storage.value = newValue }
        }
        var projectedValue: Binding<Value> {
            Binding(get: { storage.value }, set: { storage.value = $0 })
        }
    }
    final class Inverter {
        static let shared = Inverter()
        var syncs = 0
        func syncWithPreferences() { syncs += 1 }
    }
    struct Panel {
        typealias ScrollInverter = Inverter
        @State var invertVertical = false
        @State var invertHorizontal = false
        @State var invertTrackpadVertical = false
        @State var invertTrackpadHorizontal = false
        let permissions = Access.shared
        func grantAccessibility() { permissions.requests += 1 }
        var values: [Bool] {
            [invertVertical, invertHorizontal, invertTrackpadVertical, invertTrackpadHorizontal]
        }
    }
    enum Directory {}
    enum Direction {
        typealias ScrollHIDDirection = HID
        static let horizontalRedirectTag = ScrollWheelSupport.horizontalRedirectTag
        static func redirectVerticalScroll(_ event: CGEvent, modifier: ScrollHorizontalModifier,
                                           targetsOwnWindow: Bool) -> Bool {
            ScrollWheelSupport.redirectVerticalScroll(event, modifier: modifier,
                                                       targetsOwnWindow: targetsOwnWindow)
        }
    }
    enum HID {
        static var captures = 0
        static var available = true
        static var writes: [ScrollWheelInversionPlan] = []
        struct Snapshot {
            func reverse(vertical: Bool, horizontal: Bool) {
                writes.append(ScrollWheelInversionPlan(vertical: vertical, horizontal: horizontal))
            }
        }
        static func capture(_ event: CGEvent) -> Snapshot? {
            captures += 1
            return available ? Snapshot() : nil
        }
    }

    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.scroll-controls.\(UUID().uuidString)"
        let defaults = Foundation.UserDefaults(suiteName: name)!
        DefaultsHost.standard = defaults
        defer {
            defaults.removePersistentDomain(forName: name)
            Access.shared.accessibility = true
        }
        defaults.set(true, forKey: AppFeature.scrollInverter.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.scrollHorizontalEnabled)
        suite.expect(!Panel().scrollDirectionEnabled,
                     "modifier-only horizontal scrolling does not make reversal active")
        let strings = Strings.enUS
        let bar = FeatureStrings.commandBar(.enUS)
        for mask in 0..<16 {
            let panel = Panel()
            panel.invertVertical = mask & 1 != 0
            panel.invertHorizontal = mask & 2 != 0
            panel.invertTrackpadVertical = mask & 4 != 0
            panel.invertTrackpadHorizontal = mask & 8 != 0
            suite.expect(panel.scrollDirectionEnabled == (mask != 0),
                         "quick-panel activity includes every mouse and trackpad axis (\(mask))")
            for granted in [false, true] {
                Access.shared.accessibility = granted
                for (index, setting) in ScrollDirectionSetting.allCases.enumerated() {
                    let before = panel.values
                    Inverter.shared.syncs = 0
                    Access.shared.requests = 0
                    let binding = panel.scrollDirectionBinding(for: setting)
                    suite.expect(binding.wrappedValue == before[index], "the panel reads its selected axis")
                    binding.wrappedValue.toggle()
                    var expected = before
                    expected[index].toggle()
                    suite.expect(panel.values == expected && Inverter.shared.syncs == 1,
                                 "a panel switch changes only its own axis and syncs the normal service")
                    suite.expect(Access.shared.requests == (!granted && expected[index] ? 1 : 0),
                                 "the panel requests Accessibility only when an axis is enabled without a grant")
                    binding.wrappedValue = before[index]
                }
            }
        }
        Access.shared.accessibility = true
        let actions = Catalog.toggleEntries(strings, language: .enUS, bar: bar)
        suite.expect(actions.count == 4 && Set(actions.map(\.id)) == Set(commandIDs),
                     "Command Bar offers four device axes while preserving the mouse action IDs")
        for (index, id) in commandIDs.enumerated() {
            guard let action = actions.first(where: { $0.id == id }) else {
                suite.expect(false, "Command Bar includes \(id)")
                continue
            }
            let device = index < 2 ? strings.scrollMouseLabel : strings.scrollTrackpadLabel
            suite.expect(action.title.contains(device) && action.keywords.contains(device),
                         "the action and its search terms identify the device")
            for key in keys { defaults.set(false, forKey: key) }
            Runtime.shared.synced = []
            action.run(nil)
            suite.expect(keys.filter { defaults.bool(forKey: $0) } == [keys[index]]
                && Runtime.shared.synced == [[.scrollInverter]]
                && defaults.bool(forKey: DefaultsKey.scrollHorizontalEnabled),
                "a Command Bar action changes only its axis and uses the normal runtime sync")
        }
        defaults.set(false, forKey: AppFeature.scrollInverter.availabilityKey)
        suite.expect(Catalog.toggleEntries(strings, language: .enUS, bar: bar).isEmpty,
                     "uninstalled scroll reversal contributes no actions")
        defaults.set(true, forKey: AppFeature.scrollInverter.availabilityKey)
        for mask in 0..<16 {
            func restore() {
                for (index, key) in keys.enumerated() { defaults.set(mask & (1 << index) != 0, forKey: key) }
            }
            for granted in [false, true] {
                restore()
                Access.shared.accessibility = granted
                let entries = Catalog.toggleEntries(strings, language: .enUS, bar: bar)
                for (index, id) in commandIDs.enumerated() {
                    guard let entry = entries.first(where: { $0.id == id }) else { continue }
                    let wasOn = mask & (1 << index) != 0
                    suite.expect(entry.isActive == wasOn
                        && (entry.trouble != nil) == !granted,
                        "Command Bar uses the ordinary active and permission presentation")
                    restore()
                    entry.run(nil)
                    suite.expect(keys.enumerated().allSatisfy { position, key in
                        defaults.bool(forKey: key) == (position == index ? !wasOn : mask & (1 << position) != 0)
                    }, "Command Bar toggles exactly the selected axis for every saved combination")
                }
            }
        }
        for (language, localized) in LocalizationTests.languages {
            let titles = ScrollDirectionSetting.allCases.map { $0.title(localized) }
            suite.expect(Set(titles).count == 4
                && titles.prefix(2).allSatisfy { $0.contains(localized.scrollMouseLabel) }
                && titles.suffix(2).allSatisfy { $0.contains(localized.scrollTrackpadLabel) },
                "each locale gives the four actions and accessible switch labels distinct device names")
            let localizedActions = Catalog.toggleEntries(localized, language: language,
                                                         bar: FeatureStrings.commandBar(language))
            suite.expect(localizedActions.count == 4
                && localizedActions.enumerated().allSatisfy { $0.element.title.contains(titles[$0.offset]) },
                "Command Bar formats the shared localized labels using its normal turn-on/off strings")
            search(suite, strings: localized, language: language)
        }
        hidScope(suite)
        suite.expect(MenuPanelSectionGateContract.ControlPanelItem.mouseScroll.id == "mouseScroll"
            && MenuPanelSectionGateContract.ControlPanelItem.mouseScroll.feature == .scrollInverter,
            "the whole quick-control group keeps its saved layout and availability identity")
    }

    private static func search(_ suite: TestSuite, strings: Strings, language: AppLanguage) {
        let pages = Directory.sections(strings, language: language).flatMap(\.items)
        guard let page = pages.first(where: { $0.page == .mouse }) else {
            suite.expect(false, "the settings directory contains Mouse & Trackpad")
            return
        }
        let item = SettingsSearchItem(id: .page(.mouse), destination: FeatureSettingsDestination(.mouse),
                                     title: page.title, icon: page.icon,
                                     keywords: page.keywords, keywordFeatures: page.keywordFeatures)
        let queries = [strings.scrollTrackpadLabel] + ScrollDirectionSetting.allCases.map { $0.title(strings) }
            + (language == .enUS ? ["trackpad scrolling"] : [])
        for query in queries {
            let groups = SettingsSearchSupport.groupedMatchingItems(query: query, items: [item],
                                                                    isAvailable: { $0 == .scrollInverter })
            suite.expect(groups.flatMap(\.suggestions).contains {
                $0.item.feature == .scrollInverter
                    && SettingsSearchSupport.route(for: $0, isAvailable: { _ in true }).destination
                        == AppFeature.scrollInverter.settingsDestination
            }, "device/axis search finds the owned scroll-direction section in \(language.rawValue)")
        }
        let feature = SettingsSearchItem(id: .feature(.scrollInverter),
            destination: AppFeature.scrollInverter.settingsDestination,
            title: strings.invertMouseScroll, icon: "computermouse", feature: .scrollInverter)
        suite.expect(SettingsSearchSupport.route(for: feature, isAvailable: { _ in false }).targetFeature
            == .scrollInverter, "an uninstalled search result still leads to the correct hub feature")
    }

    private static func hidScope(_ suite: TestSuite) {
        for continuous in [false, true] {
            for updatesHID in [false, true] {
                for mask in 0..<4 {
                    let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                        wheelCount: 2, wheel1: 20, wheel2: 10, wheel3: 0)!
                    HID.captures = 0
                    HID.writes = []
                    HID.available = true
                    Direction.applyDirection(to: event, isContinuous: continuous,
                        invertVertical: mask & 1 != 0, invertHorizontal: mask & 2 != 0,
                        horizontalModifier: nil, updatesHID: updatesHID)
                    let updates = continuous && updatesHID && mask != 0
                    suite.expect(HID.captures == (updates ? 1 : 0)
                        && HID.writes == (updates ? [ScrollWheelInversionPlan(
                            vertical: mask & 1 != 0, horizontal: mask & 2 != 0)] : []),
                        "only explicitly opted-in touch reversal reaches the HID adapter")
                }
            }
        }
        HID.available = false
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                            wheelCount: 2, wheel1: 20, wheel2: 10, wheel3: 0)!
        Direction.applyDirection(to: event, isContinuous: true, invertVertical: true,
            invertHorizontal: true, horizontalModifier: nil, updatesHID: true)
        suite.expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -20
            && event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == -10,
            "missing HID support leaves Quartz reversal working on both axes")
        HID.available = true
    }
}
