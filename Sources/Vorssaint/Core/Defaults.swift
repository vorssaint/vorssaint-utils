// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Every UserDefaults key used by the app, in one place.
enum DefaultsKey {
    static let language = "appLanguage"                   // AppLanguage.rawValue
    static let clamshellPreferred = "clamshellPreferred"  // apply closed-lid mode to every session
    static let onboardingStep = "onboardingStep"          // resume point if onboarding is interrupted
    static let featuresOnboardingVersion = "featuresOnboardingVersion" // last feature-tour marker handled
    static let lastUpdateIntroVersion = "lastUpdateIntroVersion"
    static let defaultDuration = "defaultDurationMinutes" // 0 = indefinite
    static let batteryLimit = "batteryLimitPercent"       // 0 = never
    static let hotkeyEnabled = "hotkeyEnabled"
    static let showCountdown = "showCountdownInMenuBar"
    static let hasOnboarded = "hasOnboarded"
    static let sleepDisabledFlag = "vorssDisabledSleep"   // internal guard for pmset disablesleep
    static let scrollInverterEnabled = "scrollInverterEnabled"
    static let switcherEnabled = "switcherEnabled"
    static let switcherMergeTabs = "switcherMergeTabs"     // show one switcher entry per app (collapse all of an app's windows)
    static let switcherCurrentSpaceOnly   = "switcherCurrentSpaceOnly"   // hide windows on other Spaces
    static let switcherCurrentMonitorOnly = "switcherCurrentMonitorOnly" // hide windows on other monitors
    static let switcherHideMinimized      = "switcherHideMinimized"      // hide minimized windows
    static let switcherHideFinder         = "switcherHideFinder"         // hide Finder from the switcher
    static let switcherIconsOnly          = "switcherIconsOnly"          // skip live thumbnails, show app icons only
    static let autoCheckUpdates = "autoCheckUpdates"
    static let appVolumes = "appVolumes"                  // [bundle id: 0...2]
    static let finderCutPasteEnabled = "finderCutPasteEnabled"
    static let autoQuitEnabled = "autoQuitEnabled"
    static let autoQuitExceptions = "autoQuitExceptions"  // [bundle id] kept running
    static let shelfEnabled = "shelfEnabled"
    static let shelfShakeToOpen = "shelfShakeToOpen"
    static let urlCleanerEnabled = "urlCleanerEnabled"
    static let windowMaximizeEnabled = "windowMaximizeEnabled"
    static let panelUtilityCleaning = "panelUtilityCleaning"
    static let panelUtilityURLCleaner = "panelUtilityURLCleaner"
    static let panelUtilityUninstaller = "panelUtilityUninstaller"
    static let panelControlMouseScroll = "panelControlMouseScroll"
    static let panelControlSwitcher = "panelControlSwitcher"
    static let panelControlCutPaste = "panelControlCutPaste"
    static let panelControlAutoQuit = "panelControlAutoQuit"
    static let panelControlShelf = "panelControlShelf"
    static let panelControlWindowMaximize = "panelControlWindowMaximize"

    // System monitor — live metrics shown next to the menu bar icon (opt-in).
    static let menuBarCPU = "menuBarCPU"
    static let menuBarGPU = "menuBarGPU"
    static let menuBarMemory = "menuBarMemory"
    static let menuBarNetwork = "menuBarNetwork"
    static let menuBarBattery = "menuBarBattery"
    static let menuBarPower = "menuBarPower"
    static let menuBarLabelStyle = "menuBarLabelStyle"     // compact | classic
    static let menuBarMemoryStyle = "menuBarMemoryStyle"   // dot | percent | both
    static let monitorInterval = "monitorIntervalSeconds"  // sampling cadence: 1/2/5
    static let temperatureUnit = "temperatureUnit"          // celsius | fahrenheit
    // System monitor — which blocks appear in the panel.
    static let monitorShowSystem = "monitorShowSystem"
    static let monitorShowNetwork = "monitorShowNetwork"
    static let monitorShowPower = "monitorShowPower"
    static let monitorShowMixer = "monitorShowMixer"
    static let monitorShowFanControlBeta = "monitorShowFanControlBeta"
    // System monitor — per-metric history graphs (each independently toggleable).
    static let monitorGraphCPU = "monitorGraphCPU"
    static let monitorGraphGPU = "monitorGraphGPU"
    static let monitorGraphMemory = "monitorGraphMemory"
    static let monitorGraphNetwork = "monitorGraphNetwork"
    static let monitorGraphPower = "monitorGraphPower"
    static let monitorGraphBattery = "monitorGraphBattery"
    // System monitor — per-item visibility inside each panel section.
    static let monitorSysTemps = "monitorSysTemps"
    static let monitorSysCPU = "monitorSysCPU"
    static let monitorSysGPU = "monitorSysGPU"
    static let monitorSysBattery = "monitorSysBattery"
    static let monitorSysMemory = "monitorSysMemory"
    static let monitorSysUptime = "monitorSysUptime"
    static let monitorNetSpeed = "monitorNetSpeed"
    static let monitorNetTotals = "monitorNetTotals"
    static let monitorNetTest = "monitorNetTest"
    static let monitorPwrSystem = "monitorPwrSystem"
    static let monitorPwrAdapter = "monitorPwrAdapter"
    static let monitorPwrBattery = "monitorPwrBattery"
    static let monitorPwrHealth = "monitorPwrHealth"
    // Menu panel layout — the order the major sections appear in and which are
    // collapsed, both comma-joined section ids (see PanelSectionID). Absent keys
    // mean the canonical order and nothing collapsed, so no defaults registration.
    static let panelSectionOrder = "panelSectionOrder"
    static let panelNavigationEnabled = "panelNavigationEnabled"
    static let panelCollapsedSections = "panelCollapsedSections"
    static let panelCollapsedResetVersion = "panelCollapsedResetVersion"

    // Dev-build only: force the "update available" UI for local testing.
    static let simulateUpdate = "simulateUpdate"
}

/// Bump `currentFeatureSet` when first-run feature defaults need a quiet marker.
enum OnboardingInfo {
    // 2: system monitor, configurable panel and menu bar metrics.
    // 3: app languages and support settings.
    // 4: navigable menu panel sections.
    static let currentFeatureSet = 4
}

enum Defaults {
    static let finderBundleIdentifier = "com.apple.finder"
    static let mandatoryAutoQuitExceptionBundleIDs = [finderBundleIdentifier]

    static let allowedDurations = [0, 15, 30, 60, 120, 240, 480]
    static let allowedBatteryLimits = [0, 5, 10, 15, 20]
    static let allowedMonitorIntervals = [1, 2, 5]
    static let allowedMenuBarLabelStyles = ["compact", "classic"]
    static let allowedMenuBarMemoryStyles = ["dot", "percent", "both"]

    static let registeredDefaults: [String: Any] = [
        DefaultsKey.clamshellPreferred: false,
        DefaultsKey.defaultDuration: 0,
        DefaultsKey.batteryLimit: 10,
        DefaultsKey.hotkeyEnabled: true,
        DefaultsKey.showCountdown: false,
        DefaultsKey.scrollInverterEnabled: false,
        DefaultsKey.switcherEnabled: true,
        DefaultsKey.switcherMergeTabs: false,
        DefaultsKey.switcherCurrentSpaceOnly: false,
        DefaultsKey.switcherCurrentMonitorOnly: false,
        DefaultsKey.switcherHideMinimized: false,
        DefaultsKey.switcherHideFinder: false,
        DefaultsKey.switcherIconsOnly: false,
        DefaultsKey.autoCheckUpdates: true,
        // Finder never benefits from being "quit" (it just relaunches), so
        // it's excepted out of the box.
        DefaultsKey.autoQuitExceptions: mandatoryAutoQuitExceptionBundleIDs,
        // When the shelf is on, the shake gesture is on too (still toggleable).
        DefaultsKey.shelfShakeToOpen: true,
        DefaultsKey.urlCleanerEnabled: false,
        DefaultsKey.windowMaximizeEnabled: false,
        DefaultsKey.panelUtilityCleaning: true,
        DefaultsKey.panelUtilityURLCleaner: true,
        DefaultsKey.panelUtilityUninstaller: true,
        DefaultsKey.panelControlMouseScroll: true,
        DefaultsKey.panelControlSwitcher: true,
        DefaultsKey.panelControlCutPaste: true,
        DefaultsKey.panelControlAutoQuit: true,
        DefaultsKey.panelControlShelf: true,
        DefaultsKey.panelControlWindowMaximize: true,
        // Menu bar metrics start off (the icon stays clean) and are opt-in.
        // The panel shows every monitoring block by default; users hide what
        // they don't want.
        DefaultsKey.monitorInterval: 2,
        DefaultsKey.temperatureUnit: TemperatureUnit.celsius.rawValue,
        DefaultsKey.menuBarLabelStyle: "compact",
        DefaultsKey.menuBarMemoryStyle: "percent",
        DefaultsKey.monitorShowSystem: true,
        DefaultsKey.monitorShowNetwork: true,
        DefaultsKey.monitorShowPower: true,
        DefaultsKey.monitorShowMixer: true,
        DefaultsKey.monitorShowFanControlBeta: false,
        DefaultsKey.panelNavigationEnabled: true,
        DefaultsKey.monitorGraphCPU: true,
        DefaultsKey.monitorGraphGPU: true,
        DefaultsKey.monitorGraphMemory: true,
        DefaultsKey.monitorGraphNetwork: true,
        DefaultsKey.monitorGraphPower: true,
        DefaultsKey.monitorGraphBattery: true,
        // Every per-item block shows by default; users hide what they don't want.
        DefaultsKey.monitorSysTemps: true,
        DefaultsKey.monitorSysCPU: true,
        DefaultsKey.monitorSysGPU: true,
        DefaultsKey.monitorSysBattery: true,
        DefaultsKey.monitorSysMemory: true,
        DefaultsKey.monitorSysUptime: true,
        DefaultsKey.monitorNetSpeed: true,
        DefaultsKey.monitorNetTotals: true,
        DefaultsKey.monitorNetTest: true,
        DefaultsKey.monitorPwrSystem: true,
        DefaultsKey.monitorPwrAdapter: true,
        DefaultsKey.monitorPwrBattery: true,
        DefaultsKey.monitorPwrHealth: true,
    ]

    static func register() {
        UserDefaults.standard.register(defaults: registeredDefaults)
    }

    static func sanitizedDefaultDuration(_ minutes: Int) -> Int {
        allowedDurations.contains(minutes) ? minutes : 0
    }

    static func sanitizedBatteryLimit(_ percent: Int) -> Int {
        allowedBatteryLimits.contains(percent) ? percent : 10
    }

    static func sanitizedMonitorInterval(_ seconds: Int) -> Int {
        allowedMonitorIntervals.contains(seconds) ? seconds : 2
    }

    static func sanitizedMenuBarLabelStyle(_ style: String) -> String {
        allowedMenuBarLabelStyles.contains(style) ? style : "compact"
    }

    static func sanitizedMenuBarMemoryStyle(_ style: String) -> String {
        allowedMenuBarMemoryStyles.contains(style) ? style : "percent"
    }

    static func sanitizedBundleIdentifierList(_ bundleIDs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in bundleIDs {
            let bundleID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty, !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            result.append(bundleID)
        }
        return result
    }

    static func sanitizedAutoQuitExceptions(_ bundleIDs: [String]) -> [String] {
        sanitizedBundleIdentifierList(mandatoryAutoQuitExceptionBundleIDs + bundleIDs)
    }

    static func sanitizedAppVolume(_ volume: Double) -> Double {
        guard volume.isFinite else { return 1 }
        return min(max(volume, 0), 2)
    }
}
