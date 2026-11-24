// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MenuBarMetric: String, CaseIterable {
    // PRODUCTION_METRIC_CASES
    func title(_ strings: Strings) -> String { rawValue }
}
struct Strings {
    let monitorShowCPU = "CPU"
    let monitorShowGPU = "GPU"
    let batteryLabel = "Battery"
}
enum DefaultsKey { static let menuBarCombineTemperatures = "combine" }
enum ReviewDefaults { static var current: UserDefaults! }
struct MenuBarMetricAppearance {
    var allowsCombinedTemperatures: Bool
    static var current = MenuBarMetricAppearance(allowsCombinedTemperatures: true)
}
enum Groups {
    struct MetricStatusGroup {
        let id: String
        let metrics: [MenuBarMetric]
        let focusMetric: MenuBarMetric
        let title: String
    }
    // PRODUCTION_GROUPS_METHOD
}

@main struct TMobileMenuBarGroupsHarness {
    static func main() {
        let domain = "com.vorssaint.tests.tmobile-groups.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        ReviewDefaults.current = defaults
        defer { defaults.removePersistentDomain(forName: domain) }
        for combines in [false, true] {
            defaults.set(combines, forKey: DefaultsKey.menuBarCombineTemperatures)
            let groups = Groups.metricStatusGroups(for: [.tMobile], strings: Strings())
            precondition(groups.count == 1 && groups[0].id == "tMobile"
                         && groups[0].metrics == [.tMobile] && groups[0].focusMetric == .tMobile
                         && !groups[0].title.isEmpty,
                         "The gateway pin is one clickable connected-radio item")
        }
        defaults.set(true, forKey: DefaultsKey.menuBarCombineTemperatures)
        let mixed = Groups.metricStatusGroups(for: [.cpu, .cpuTemperature, .tMobile], strings: Strings())
        precondition(mixed.count == 2 && mixed.first?.metrics == [.cpu, .cpuTemperature]
                     && mixed.last?.metrics == [.tMobile],
                     "CPU temperature grouping remains separate from the single cellular connection")
        print("PASS: the gateway pin groups as one independently clickable connection")
    }
}
