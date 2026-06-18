// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Every UserDefaults key used by the app, in one place.
enum DefaultsKey {
    static let language = "appLanguage"                   // AppLanguage.rawValue
    static let clamshellPreferred = "clamshellPreferred"  // apply closed-lid mode to every session
    static let onboardingStep = "onboardingStep"          // resume point if onboarding is interrupted
    static let featuresOnboardingVersion = "featuresOnboardingVersion" // last feature-tour version the user saw
    static let defaultDuration = "defaultDurationMinutes" // 0 = indefinite
    static let batteryLimit = "batteryLimitPercent"       // 0 = never
    static let hotkeyEnabled = "hotkeyEnabled"
    static let showCountdown = "showCountdownInMenuBar"
    static let hasOnboarded = "hasOnboarded"
    static let sleepDisabledFlag = "vorssDisabledSleep"   // internal guard for pmset disablesleep
    static let scrollInverterEnabled = "scrollInverterEnabled"
    static let switcherEnabled = "switcherEnabled"
    static let switcherMergeTabs = "switcherMergeTabs"     // show one switcher entry per app (collapse all of an app's windows)
    static let autoCheckUpdates = "autoCheckUpdates"
    static let appVolumes = "appVolumes"                  // [bundle id: 0...2]
    static let finderCutPasteEnabled = "finderCutPasteEnabled"
    static let autoQuitEnabled = "autoQuitEnabled"
    static let autoQuitExceptions = "autoQuitExceptions"  // [bundle id] kept running
    static let shelfEnabled = "shelfEnabled"
    static let shelfShakeToOpen = "shelfShakeToOpen"

    // System monitor — live metrics shown next to the menu bar icon (opt-in).
    static let menuBarCPU = "menuBarCPU"
    static let menuBarGPU = "menuBarGPU"
    static let menuBarMemory = "menuBarMemory"
    static let menuBarNetwork = "menuBarNetwork"
    static let menuBarPower = "menuBarPower"
    static let menuBarMemoryStyle = "menuBarMemoryStyle"   // dot | percent | both
    static let monitorInterval = "monitorIntervalSeconds"  // sampling cadence: 1/2/5
    static let temperatureUnit = "temperatureUnit"          // celsius | fahrenheit
    // System monitor — which blocks appear in the panel.
    static let monitorShowSystem = "monitorShowSystem"
    static let monitorShowNetwork = "monitorShowNetwork"
    static let monitorShowPower = "monitorShowPower"
    static let monitorShowMixer = "monitorShowMixer"
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
    static let panelCollapsedSections = "panelCollapsedSections"
    static let panelCollapsedResetVersion = "panelCollapsedResetVersion"

    // Dev-build only: force the "update available" UI for local testing.
    static let simulateUpdate = "simulateUpdate"

    // MemoryKill — auto-purge and power-user toggles.
    static let autoPurgeEnabled = "autoPurgeEnabled"
    static let autoPurgeThreshold = "autoPurgeThreshold"   // warning | critical
    static let autoPurgeNotify = "autoPurgeNotify"
    static let purgeHotkeyEnabled = "purgeHotkeyEnabled"
    static let optionClickPurge = "optionClickPurge"
}

/// Bump `currentFeatureSet` when the first-run tour changes. Existing users are
/// marked as caught up silently on update; the app should not open update popups.
enum OnboardingInfo {
    // 2: system monitor, configurable panel and menu bar metrics.
    // 3: app languages and Buy Me a Coffee support in first-run onboarding.
    static let currentFeatureSet = 3
}

enum Defaults {
    static let allowedDurations = [0, 15, 30, 60, 120, 240, 480]
    static let allowedBatteryLimits = [0, 5, 10, 15, 20]
    static let allowedMonitorIntervals = [1, 2, 5]
    static let allowedMenuBarMemoryStyles = ["dot", "percent", "both"]

    static let registeredDefaults: [String: Any] = [
        DefaultsKey.clamshellPreferred: false,
        DefaultsKey.defaultDuration: 0,
        DefaultsKey.batteryLimit: 10,
        DefaultsKey.hotkeyEnabled: true,
        DefaultsKey.showCountdown: false,
        DefaultsKey.switcherMergeTabs: false,
        // Finder never benefits from being "quit" (it just relaunches), so
        // it's excepted out of the box.
        DefaultsKey.autoQuitExceptions: ["com.apple.finder"],
        // When the shelf is on, the shake gesture is on too (still toggleable).
        DefaultsKey.shelfShakeToOpen: true,
        // Menu bar metrics start off (the icon stays clean) and are opt-in.
        // The panel shows every monitoring block by default; users hide what
        // they don't want.
        DefaultsKey.monitorInterval: 1,
        DefaultsKey.autoPurgeEnabled: true,
        DefaultsKey.autoPurgeThreshold: "warning",
        DefaultsKey.autoPurgeNotify: true,
        DefaultsKey.purgeHotkeyEnabled: true,
        DefaultsKey.optionClickPurge: true,
        DefaultsKey.temperatureUnit: TemperatureUnit.celsius.rawValue,
        DefaultsKey.menuBarMemoryStyle: "both",
        DefaultsKey.menuBarMemory: true,
        DefaultsKey.menuBarCPU: false,
        DefaultsKey.menuBarGPU: false,
        DefaultsKey.menuBarNetwork: false,
        DefaultsKey.menuBarPower: false,
        DefaultsKey.monitorShowSystem: true,
        DefaultsKey.monitorShowNetwork: false,
        DefaultsKey.monitorShowPower: false,
        DefaultsKey.monitorShowMixer: false,
        DefaultsKey.hasOnboarded: true,
        DefaultsKey.autoCheckUpdates: false,
        DefaultsKey.switcherEnabled: false,
        DefaultsKey.scrollInverterEnabled: false,
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

    static func sanitizedAppVolume(_ volume: Double) -> Double {
        guard volume.isFinite else { return 1 }
        return min(max(volume, 0), 2)
    }
}
