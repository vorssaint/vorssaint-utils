// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production sampling plan against scripted surfaces and features.
enum SystemMonitorPlanTests {
    enum PowerSampler { static let hasInternalBattery = false }

    class Fixture {
        var menuPanelNeeds = SystemMonitorPanelNeeds.none
        var notchDetailNeeds = SystemMonitorPanelNeeds.none
        var fullMonitorVisible = false
        var notchVisible = false
        var notchAccessoryMonitoring = false
        static var fanTelemetryAvailable: Bool { true }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.system-monitor-plan"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: AppFeature.connectedDevices.availabilityKey)
        defaults.set(true, forKey: AppFeature.fanControl.availabilityKey)
        let monitor = Monitor()

        suite.expect(!monitor.currentPlan(defaults: defaults).needConnectedDevices,
                     "connected devices are not read while no surface shows them")
        monitor.menuPanelNeeds = SystemMonitorPanelNeeds(system: true)
        defaults.set(true, forKey: DefaultsKey.monitorSysConnectedDevices)
        suite.expect(monitor.currentPlan(defaults: defaults).needConnectedDevices,
                     "the panel's System card reads connected devices for its device row")
        defaults.set(false, forKey: DefaultsKey.monitorSysConnectedDevices)
        suite.expect(!monitor.currentPlan(defaults: defaults).needConnectedDevices,
                     "a hidden device row stops the System card's USB reads")
        monitor.menuPanelNeeds = SystemMonitorPanelNeeds(connectedDevices: true)
        suite.expect(monitor.currentPlan(defaults: defaults).needConnectedDevices,
                     "the device list still reads connected devices with the System row hidden")
        monitor.menuPanelNeeds = .none
        monitor.notchDetailNeeds = SystemMonitorPanelNeeds(connectedDevices: true)
        suite.expect(monitor.currentPlan(defaults: defaults).needConnectedDevices,
                     "the island System page's device card ignores the panel row's toggle")
        monitor.notchDetailNeeds = .none
        monitor.fullMonitorVisible = true
        let preview = monitor.currentPlan(defaults: defaults)
        suite.expect(preview.needConnectedDevices && preview.needFanSpeed,
                     "the Settings island preview reads connected devices for its card, like the fan card")
        defaults.set(false, forKey: AppFeature.connectedDevices.availabilityKey)
        suite.expect(!monitor.currentPlan(defaults: defaults).needConnectedDevices,
                     "an uninstalled connected devices feature is not read, even for the preview")
    }
}
