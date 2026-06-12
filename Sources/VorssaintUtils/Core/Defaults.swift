import Foundation

/// Every UserDefaults key used by the app, in one place.
enum DefaultsKey {
    static let language = "appLanguage"                   // AppLanguage.rawValue
    static let keepDisplayOn = "keepDisplayOn"
    static let clamshellPreferred = "clamshellPreferred"  // apply closed-lid mode to every session
    static let onboardingStep = "onboardingStep"          // resume point if onboarding is interrupted
    static let defaultDuration = "defaultDurationMinutes" // 0 = indefinite
    static let batteryLimit = "batteryLimitPercent"       // 0 = never
    static let hotkeyEnabled = "hotkeyEnabled"
    static let showCountdown = "showCountdownInMenuBar"
    static let hasOnboarded = "hasOnboarded"
    static let sleepDisabledFlag = "vorssDisabledSleep"   // internal guard for pmset disablesleep
    static let scrollInverterEnabled = "scrollInverterEnabled"
    static let switcherEnabled = "switcherEnabled"
    static let switcherShowBrowserTabs = "switcherShowBrowserTabs"
    static let autoCheckUpdates = "autoCheckUpdates"
    static let appVolumes = "appVolumes"                  // [bundle id: 0...1]
    static let finderCutPasteEnabled = "finderCutPasteEnabled"
    static let autoQuitEnabled = "autoQuitEnabled"
    static let autoQuitExceptions = "autoQuitExceptions"  // [bundle id] kept running
    static let uninstallerEnabled = "uninstallerEnabled"
    static let shelfEnabled = "shelfEnabled"
    static let shelfShakeToOpen = "shelfShakeToOpen"
}

enum Defaults {
    static func register() {
        UserDefaults.standard.register(defaults: [
            DefaultsKey.keepDisplayOn: true,
            DefaultsKey.clamshellPreferred: false,
            DefaultsKey.defaultDuration: 0,
            DefaultsKey.batteryLimit: 10,
            DefaultsKey.hotkeyEnabled: true,
            DefaultsKey.showCountdown: false,
            DefaultsKey.scrollInverterEnabled: false,
            DefaultsKey.switcherEnabled: true,
            DefaultsKey.switcherShowBrowserTabs: true,
            DefaultsKey.autoCheckUpdates: true,
            // Finder never benefits from being "quit" (it just relaunches), so
            // it's excepted out of the box.
            DefaultsKey.autoQuitExceptions: ["com.apple.finder"],
            // When the shelf is on, the shake gesture is on too (still toggleable).
            DefaultsKey.shelfShakeToOpen: true,
        ])
    }
}
