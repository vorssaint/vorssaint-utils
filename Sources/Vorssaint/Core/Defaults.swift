import Foundation

/// Every UserDefaults key used by the app, in one place.
enum DefaultsKey {
    static let language = "appLanguage"                   // AppLanguage.rawValue
    static let clamshellPreferred = "clamshellPreferred"  // apply closed-lid mode to every session
    static let onboardingStep = "onboardingStep"          // resume point if onboarding is interrupted
    static let featuresOnboardingVersion = "featuresOnboardingVersion" // last feature-tour version the user saw
    static let lastUpdatePromptVersion = "lastUpdatePromptVersion"     // app version that last showed the post-update note
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
    static let appVolumes = "appVolumes"                  // [bundle id: 0...1]
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
}

/// Bump `currentFeatureSet` when a release introduces new features worth a
/// one-time tour. Users who onboarded under an older value are shown the
/// "what's new" pass once, then their stored value catches up.
enum OnboardingInfo {
    // 2: system monitor — network, power, history graphs and the configurable
    // menu bar. Existing users see the one-time "what's new" pass for it, opening
    // straight on the menu bar setup page.
    // 3: Buy Me a Coffee support. Updaters see a one-time, gentle announcement
    // that the project now accepts donations (and stays free), with a link.
    static let currentFeatureSet = 3
}

enum Defaults {
    static func register() {
        UserDefaults.standard.register(defaults: [
            DefaultsKey.clamshellPreferred: false,
            DefaultsKey.defaultDuration: 0,
            DefaultsKey.batteryLimit: 10,
            DefaultsKey.hotkeyEnabled: true,
            DefaultsKey.showCountdown: false,
            DefaultsKey.scrollInverterEnabled: false,
            DefaultsKey.switcherEnabled: true,
            DefaultsKey.switcherMergeTabs: false,
            DefaultsKey.autoCheckUpdates: true,
            // Finder never benefits from being "quit" (it just relaunches), so
            // it's excepted out of the box.
            DefaultsKey.autoQuitExceptions: ["com.apple.finder"],
            // When the shelf is on, the shake gesture is on too (still toggleable).
            DefaultsKey.shelfShakeToOpen: true,
            // Menu bar metrics start off (the icon stays clean) and are opt-in.
            // The panel shows every monitoring block by default; users hide what
            // they don't want.
            DefaultsKey.monitorInterval: 2,
            DefaultsKey.menuBarMemoryStyle: "percent",
            DefaultsKey.monitorShowSystem: true,
            DefaultsKey.monitorShowNetwork: true,
            DefaultsKey.monitorShowPower: true,
            DefaultsKey.monitorShowMixer: true,
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
        ])
    }
}
