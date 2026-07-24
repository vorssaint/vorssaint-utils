// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Languages the interface can use. The first launch defaults to the system
/// language; the onboarding and Settings let the user override it at any time.
enum AppLanguage: String, CaseIterable, Identifiable {
    case enUS = "en-US"
    case ptBR = "pt-BR"
    case tr = "tr"
    case ru = "ru"
    case es = "es"
    case de = "de"
    case fr = "fr"
    case it = "it"
    case ja = "ja"
    case ko = "ko"
    case zhHans = "zh-Hans"
    case zhTW = "zh-TW"
    case zhHK = "zh-HK"

    var id: String { rawValue }

    /// The language's own name, shown in its own script, the way macOS lists them.
    var displayName: String {
        switch self {
        case .enUS: return "English (US)"
        case .ptBR: return "Português (Brasil)"
        case .tr: return "Türkçe"
        case .ru: return "Русский"
        case .es: return "Español"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .it: return "Italiano"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .zhHans: return "简体中文"
        case .zhHK: return "繁體中文（香港）"
        case .zhTW: return "繁體中文（台灣）"
        }
    }

    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let p = preferred.lowercased()

        if p.hasPrefix("zh-hk") || p.hasPrefix("zh-hant-hk") {
            return .zhHK
        }

        if p.hasPrefix("zh-tw") || p.hasPrefix("zh-hant-tw") || p.hasPrefix("zh-hant") {
            return .zhTW
        }

        let matches: [(String, AppLanguage)] = [
            ("pt", .ptBR), ("tr", .tr), ("ru", .ru), ("es", .es), ("de", .de), ("fr", .fr),
            ("it", .it), ("ja", .ja), ("ko", .ko), ("zh", .zhHans),
        ]
        for (prefix, language) in matches where preferred.hasPrefix(prefix) { return language }
        return .enUS
    }
}

/// Source of every user-facing string. Views observe this object so the whole
/// interface re-renders immediately when the language changes.
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: DefaultsKey.language) }
    }

    var s: Strings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhHK: return .zhHK
        case .zhTW: return .zhTW
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.language),
           let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            language = .systemDefault
        }
    }
}

/// Flat, compiler-checked catalog of UI strings. Adding a field here forces
/// both translations to be provided.
struct Strings {
    // MARK: Menu bar & context menu
    let statusIdleTooltip: String
    let statusActiveUntil: String      // + time
    let statusActiveIndefinite: String
    let menuEnableAwake: String
    let menuDisableAwake: String
    let menuActivateFor: String
    let menuSettings: String
    let menuAbout: String
    let menuQuit: String
    // Standard application menu bar (App / Edit / Window) shown while one of the
    // app's own windows is focused. Without it, an accessory app has no main menu
    // and the standard shortcuts (Cmd+H/M/W/Q, Cmd+C/V/X/A) do nothing.
    let menuHide: String
    let menuHideOthers: String
    let menuShowAll: String
    let menuEdit: String
    let menuUndo: String
    let menuRedo: String
    let menuCut: String
    let menuCopy: String
    let menuPaste: String
    let menuSelectAll: String
    let menuWindow: String
    let menuMinimize: String
    let menuZoom: String
    let menuClose: String

    // MARK: Durations
    let minutes15: String
    let minutes30: String
    let hour1: String
    let hours2: String
    let hours4: String
    let hours8: String
    let indefinitely: String
    let indefinite: String

    // MARK: Panel — header & footer
    let panelSettings: String
    let panelQuit: String
    let panelHotkeyHint: String

    // MARK: Panel — keep awake card
    let keepAwakeTitle: String
    let keepAwakeEndsIn: String        // + remaining
    let keepAwakeUntilDisabled: String
    let keepAwakeNormalRules: String
    let keepAwakeOptions: String
    let keepAwakeMouseJiggle: String
    let keepAwakeMouseJiggleCaption: String
    let keepAwakeMouseJiggleInterval: String
    let keepAwakeActiveIconLabel: String
    let keepAwakeActiveIconVorssaint: String
    let keepAwakeActiveIconCoffee: String
    let keepAwakeActiveIconEye: String
    let keepAwakeActiveIconMoon: String
    let keepAwakeActiveIconLight: String
    let keepAwakeIconTintLabel: String
    let keepAwakeIconTintOrange: String
    let keepAwakeIconTintGreen: String
    let keepAwakeIconTintBlue: String
    let keepAwakeIconTintPurple: String
    let keepAwakeIconTintPink: String
    let keepAwakeIconTintNone: String
    let durationLabel: String
    let clamshellTitle: String
    let clamshellOnCaption: String
    let clamshellNeedsSession: String
    let clamshellReady: String
    let clamshellNeedsPassword: String

    // MARK: Panel — system monitor
    let systemSection: String
    let temperatures: String
    let cpuLabel: String
    let gpuLabel: String
    let batteryLabel: String
    let usageSection: String
    let memorySection: String
    let memoryPressure: String
    let pressureNormal: String
    let pressureWarning: String
    let pressureCritical: String
    let monitorUnavailable: String
    let energyAppsTitle: String
    let energyAppsIdle: String

    // MARK: Notifications
    let notifySessionEndedTitle: String
    let notifySessionEndedBody: String
    let notifyBatteryTitle: String
    let notifyBatteryBody: String

    // MARK: Administrator prompts (shown by macOS password dialogs)
    let adminPromptClamshellOn: String
    let adminPromptClamshellOff: String
    let adminPromptRecover: String
    let adminPromptUpdate: String
    let adminPromptSudoersInstall: String
    let adminPromptSudoersRemove: String

    // MARK: Settings — window & tabs
    let settingsTitle: String
    let tabGeneral: String
    let tabEnergy: String
    let tabMouse: String
    let tabSwitcher: String
    let tabAdvanced: String
    let tabAbout: String
    let tabReleaseNotes: String
    let releaseNotesOnUpdateToggle: String
    let whatsNewDontShowAgain: String
    let previewSizeLabel: String
    let previewSizeNormal: String
    let previewSizeLarge: String
    let previewSizeXLarge: String
    let settingsGroupFeatures: String

    // MARK: Settings — advanced
    let advancedResetSection: String
    let advancedResetDescription: String
    let advancedClearButton: String
    let advancedCleared: String
    let advancedClearConfirmTitle: String
    let advancedClearConfirmBody: String
    let advancedUninstallSection: String
    let advancedUninstallDescription: String
    let advancedUninstallButton: String
    let advancedUninstallConfirmTitle: String
    let advancedUninstallConfirmBody: String

    // MARK: Settings — general
    let launchAtLogin: String
    let languageLabel: String
    let menuBarSection: String
    let showCountdown: String
    let globalHotkeySection: String
    let hotkeyToggle: String
    let hotkeyCaption: String

    // MARK: Settings — energy
    let sessionSection: String
    let defaultDurationLabel: String
    let keepAwakeAutoStart: String
    let keepAwakeAutoStartCaption: String
    let batteryProtectionSection: String
    let batteryDisableBelow: String
    let batteryNever: String
    let batteryProtectionCaption: String
    let clamshellSection: String
    let configuring: String
    let sudoersFailed: String
    let clamshellExplanation: String

    // MARK: Settings — mouse
    let scrollSection: String
    let invertMouseScroll: String
    let invertMouseScrollCaption: String
    let scrollTrackpadNote: String
    let scrollActiveNow: String
    let mouseNavigationActiveNow: String
    let smoothScrollName: String
    let smoothScrollCaption: String
    let smoothScrollStepLabel: String
    let mouseNavigationSection: String
    let mouseNavigationEnable: String
    let mouseNavigationCaption: String
    let middleClickSection: String
    let middleClickEnable: String
    let middleClickEnableCaption: String
    let middleClickDragConflict: String
    let middleClickTapPicker: String
    let middleClickTapOff: String
    let middleClickTapThreeFingers: String
    let middleClickTapFourFingers: String
    let middleClickTapCaption: String
    let quickToolsTab: String
    let quickToolShortcutToggle: String
    let ocrName: String
    let ocrCaption: String
    let ocrCopied: String
    let ocrNoText: String
    let colorPickerName: String
    let colorPickerCaption: String
    let colorPickerFormatLabel: String
    let colorPickerBareHexToggle: String
    let colorPickerPickNow: String
    let micMuteName: String
    let micUnmuteName: String
    let micMuteCaption: String
    let micMutedHUD: String
    let micUnmutedHUD: String
    let micMuteMenuBarToggle: String
    let micMuteMenuBarCaption: String
    let pastePlainName: String
    let pastePlainCaption: String
    let launcherName: String
    let launcherCaption: String
    let launcherOpenNow: String
    let launcherEditHint: String
    let launcherEmptyState: String
    let launcherAddSection: String
    let launcherKeysHint: String

    // MARK: Settings — switcher
    let switcherSection: String
    let switcherEnable: String
    let switcherEnableCaption: String
    let switcherUsageHint: String
    let switcherNoWindows: String
    let switcherIconRowMode: String
    let switcherIconRowModeCaption: String
    let switcherSimpleMode: String
    let switcherSimpleModeCaption: String
    let switcherShortcutHintApps: String
    let switcherShortcutHintWindows: String
    let switcherWindowShortcutCaption: String
    let switcherMergeTabs: String
    let switcherMergeTabsCaption: String
    let switcherShowFinder: String
    let switcherShowFinderCaption: String
    let dockPreviewName: String
    let dockPreviewEnable: String
    let dockPreviewEnableCaption: String
    let dockClickMinimize: String
    let dockClickMinimizeCaption: String
    let dockClickCycleWindows: String
    let dockClickCycleWindowsCaption: String
    let dockPreviewActiveNow: String
    let dockPreviewDockUnavailable: String
    let dockPreviewAutohideBeta: String
    let dockPreviewOpenWindow: String
    let dockPreviewCloseWindow: String
    let dockPreviewMinimizeWindow: String
    let dockPreviewRestoreWindow: String
    let dockPreviewPinPanel: String
    let dockPreviewUnpinPanel: String
    let dockPreviewPinned: String
    let dockPreviewClosePanel: String
    let dockPreviewPreviousWindow: String
    let dockPreviewNextWindow: String
    let dockPreviewIntroPeek: String
    let dockPreviewIntroSettingsHint: String
    let dockPreviewIntroLater: String
    let dockPreviewIntroEnable: String

    // MARK: Feature — cut & paste in Finder
    let cutPasteName: String
    let cutPasteEnable: String
    let cutPasteEnableCaption: String
    let cutPasteHowTitle: String
    let cutPasteStep1: String
    let cutPasteStep2: String
    let cutPasteTextNote: String
    let cutPasteActiveNow: String
    let cutPasteAutomationNote: String
    let cutReadyTitle: String
    let cutReadyHint: String
    let cutCancel: String
    let cutDoneTitle: String
    let cutMovedSingular: String
    let cutMovedPluralFormat: String      // + count
    let cutSomeFailed: String
    let cutMovingTitle: String
    let cutMovingCountFormat: String      // + position, total

    // MARK: Feature — quit on last window close
    let autoQuitName: String
    let autoQuitEnable: String
    let autoQuitEnableCaption: String
    let autoQuitActiveNow: String
    let autoQuitHowTitle: String
    let autoQuitStep1: String
    let autoQuitStep2: String
    let autoQuitPredictableNote: String
    let autoQuitExceptionsTitle: String
    let autoQuitExceptionsCaption: String
    let autoQuitExceptionsEmpty: String
    let autoQuitAddApp: String

    // MARK: Feature — complete app uninstaller
    let uninstallerName: String
    let uninstallerEnableCaption: String
    let uninstallerStep1: String
    let uninstallerStep2: String
    let uninstallerStep3: String
    let uninstallerMenuItem: String
    let uninstallerDropTitle: String
    let uninstallerDropSubtitle: String
    let uninstallerChoose: String
    let uninstallerPickerTitle: String
    let uninstallerPickerSearch: String
    let uninstallerPickerEmpty: String
    let uninstallerEmptyNote: String
    let uninstallerFDANote: String
    let uninstallerFDAGrant: String
    let uninstallerFDAHint: String
    let uninstallerFDARelaunch: String
    let uninstallerScanning: String
    let uninstallerRemoving: String
    let uninstallerFoundTitle: String
    let uninstallerSelectedFormat: String   // + selected, total
    let uninstallerRemove: String
    let uninstallerCancel: String
    let uninstallerDoneTitle: String
    let uninstallerFreedFormat: String      // + size string
    let uninstallerSomeFailed: String
    let uninstallerAnother: String
    let uninstallerCatApp: String
    let uninstallerCatSupport: String
    let uninstallerCatCaches: String
    let uninstallerCatPreferences: String
    let uninstallerCatContainers: String
    let uninstallerCatLogs: String
    let uninstallerCatState: String
    let uninstallerCatOther: String

    // MARK: Feature — URL cleaner
    let urlCleanerName: String
    let urlCleanerEnable: String
    let urlCleanerEnableCaption: String
    let urlCleanerActiveNow: String
    let urlCleanerManualTitle: String
    let urlCleanerInputPlaceholder: String
    let urlCleanerOutputPlaceholder: String
    let urlCleanerCleanButton: String
    let urlCleanerPasteButton: String
    let urlCleanerCopyButton: String
    let urlCleanerClearButton: String
    let urlCleanerNoURL: String
    let urlCleanerNoChange: String
    let urlCleanerCleaned: String
    let urlCleanerCopied: String
    let urlCleanerLocalNote: String

    // MARK: Feature — Homebrew manager
    let homebrewName: String
    let homebrewEnableCaption: String
    let homebrewMissingTitle: String
    let homebrewMissingBody: String
    let homebrewInstallHomebrew: String
    let homebrewInstallHomebrewCaption: String
    let homebrewInstallHomebrewOpened: String
    let homebrewShellSetupTitle: String
    let homebrewShellSetupBody: String
    let homebrewShellSetupButton: String
    let homebrewShellSetupOpened: String
    let homebrewRefresh: String
    let homebrewCheckPackages: String
    let homebrewTrustTitle: String
    let homebrewTrustCaption: String
    let homebrewTrustButton: String
    let homebrewSearchPlaceholder: String
    let homebrewKeyboardHint: String
    let homebrewSearchButton: String
    let homebrewSearchResults: String
    let homebrewInstalled: String
    let homebrewAll: String
    let homebrewFormulas: String
    let homebrewCasks: String
    let homebrewNoPackages: String
    let homebrewNoSelection: String
    let homebrewDetailsTitle: String
    let homebrewInstall: String
    let homebrewUninstall: String
    let homebrewUpgrade: String
    let homebrewUpgradeAll: String
    let homebrewUpdateHomebrew: String
    let homebrewAllPackages: String
    let homebrewOpenTerminal: String
    let homebrewCancelOperation: String
    let homebrewClearLog: String
    let homebrewLogTitle: String
    let homebrewVersion: String
    let homebrewDescription: String
    let homebrewHomepage: String
    let homebrewPopularity: String
    let homebrewPopularityFormat: String
    let homebrewInstalledBadge: String
    let homebrewNotInstalledBadge: String
    let homebrewUpdates: String
    let homebrewUpdateAvailableBadge: String
    let homebrewLatestVersion: String
    let homebrewConfirmInstallTitle: String
    let homebrewConfirmInstallBodyFormat: String
    let homebrewConfirmUninstallTitle: String
    let homebrewConfirmUninstallBodyFormat: String
    let homebrewConfirmUpgradeTitle: String
    let homebrewConfirmUpgradeBodyFormat: String
    let homebrewConfirmUpgradeAllTitle: String
    let homebrewConfirmUpgradeAllBody: String
    let homebrewConfirmUpdateHomebrewTitle: String
    let homebrewConfirmUpdateHomebrewBody: String
    let homebrewTerminalFallback: String
    let homebrewLoading: String
    let homebrewSearchEmpty: String
    let homebrewOperationInstallFormat: String
    let homebrewOperationUninstallFormat: String
    let homebrewOperationUpgradeFormat: String
    let homebrewOperationUpgradeAll: String
    let homebrewOperationUpdateHomebrew: String
    let homebrewOperationInstalledFormat: String
    let homebrewOperationUninstalledFormat: String
    let homebrewOperationUpgradedFormat: String
    let homebrewOperationUpgradedAll: String
    let homebrewOperationUpdatedHomebrew: String
    let homebrewOperationFailedFormat: String
    let homebrewOperationCancelled: String
    let homebrewOperationPreparing: String
    let homebrewOperationDownloading: String
    let homebrewOperationInstalling: String
    let homebrewOperationUninstalling: String
    let homebrewOperationUpgrading: String
    let homebrewOperationFinalizing: String
    let homebrewOperationRefreshing: String
    let homebrewOperationTerminal: String
    let homebrewOperationElapsedFormat: String
    let homebrewOperationShowDetails: String
    let homebrewOperationHideDetails: String
    let homebrewOperationTechnicalLog: String
    let homebrewOperationProgressUnknown: String

    // MARK: Feature — local media tools
    let mediaName: String
    let mediaEnableCaption: String
    let mediaLocalNote: String
    let mediaToolVideo: String
    let mediaToolGIF: String
    let mediaToolImage: String
    let mediaToolText: String
    let mediaSelectFile: String
    let mediaDropHint: String
    let mediaOutput: String
    let mediaOutputAutomatic: String
    let mediaChooseOutput: String
    let mediaStartVideo: String
    let mediaStartGIF: String
    let mediaStartImage: String
    let mediaStartConvertPDF: String
    let mediaStartText: String
    let mediaCancel: String
    let mediaStartTime: String
    let mediaEndTime: String
    let mediaQuality: String
    let mediaCompressionLow: String
    let mediaCompressionMedium: String
    let mediaCompressionHigh: String
    let mediaMaxSize: String
    let mediaWidth: String
    let mediaFPS: String
    let mediaKeepAudio: String
    let mediaCodec: String
    let mediaFormat: String
    let mediaStripMetadata: String
    let mediaLoopGIF: String
    let mediaOCRMode: String
    let mediaOCRAccurate: String
    let mediaOCRFast: String
    let mediaLanguageCorrection: String
    let mediaTextOutputNote: String
    let mediaRunning: String
    let mediaCompleted: String
    let mediaCancelled: String
    let mediaOpenInFinder: String
    let mediaCopyText: String
    let mediaRunAgain: String
    let mediaEmptyText: String
    let mediaResultSavedFormat: String
    let mediaResultSizeFormat: String
    let mediaResultGrewCaption: String
    let mediaErrorNoFile: String
    let mediaErrorNoVideo: String
    let mediaErrorSameOutput: String
    let mediaErrorUnsupported: String

    // MARK: Feature — temporary shelf
    let shelfName: String
    let shelfEnable: String
    let shelfEnableCaption: String
    let shelfHowTitle: String
    let shelfStep1: String
    let shelfStep2: String
    let shelfStep3: String
    let shelfShakeToggle: String
    let shelfShakeCaption: String
    let shelfDropZoneToggle: String
    let shelfDropZoneCaption: String
    let shelfDropZoneLabel: String
    let shelfCollapse: String
    let shelfBehaviorTitle: String
    let shelfCloseAfterDrop: String
    let shelfCloseAfterDropCaption: String
    let shelfRemoveAfterDrop: String
    let shelfRemoveAfterDropCaption: String
    let shelfExclusionsTitle: String
    let shelfExclusionsEmpty: String
    let shelfExclusionsCaption: String
    let shelfPin: String
    let shelfUnpin: String
    let extraBrightnessName: String
    let extraBrightnessCaption: String
    let extraBrightnessLevelLabel: String
    let extraBrightnessUnsupported: String
    let shelfHotkeyLabel: String
    let shelfOpenNow: String
    let shelfNoPermission: String
    let shelfMenuItem: String
    let shelfTitle: String
    let shelfEmpty: String
    let shelfClearAll: String
    let shelfRemoveSelected: String
    let shelfSelectedFormat: String      // + count
    let shelfHint: String
    let shelfItemImage: String
    let shelfActionOpen: String
    let shelfActionOpenWith: String
    let shelfActionAirDrop: String

    // MARK: Panel — per-app breakdown
    let breakdownMeasuring: String

    // MARK: Panel — volume mixer
    let mixerSection: String
    let mixerEmpty: String
    let mixerUnavailable: String
    let mixerPermissionBody: String
    let mixerResetTooltip: String
    let mixerOutputDefault: String
    let mixerOutputCurrent: String
    let mixerOutputUnavailable: String
    let mixerOutputFallback: String
    let mixerBypassedCaption: String
    let mixerOutputTooltip: String
    let mixerSystemOutputTitle: String
    let mixerSystemOutputNoDevices: String
    let mixerSystemOutputTooltip: String
    let mixerSystemOutputErrorFormat: String
    let mixerLowerOnHeadphonesDisconnect: String
    let mixerLowerOnHeadphonesDisconnectCaption: String
    let mixerHeadphonesDisconnectVolume: String
    let soundOutputSwitcherTitle: String
    let soundOutputSwitcherEnable: String
    let soundOutputSwitcherCaption: String
    let soundOutputSwitcherDevices: String
    let soundOutputSwitcherNoAvailableSelection: String
    let mixerInputTitle: String
    let mixerInputNoDevices: String
    let mixerInputUnavailable: String
    let mixerInputFallback: String
    let mixerInputTooltip: String
    let mixerInputErrorFormat: String
    let mixerVisibleApps: String
    let mixerAllShown: String
    let mixerHiddenCountLabel: String
    let mixerHideFromList: String

    // MARK: Settings — updates
    let updatesSection: String
    let autoCheckToggle: String
    let checkNowButton: String
    let updateChecking: String
    let updateUpToDate: String
    let updateAvailablePrefix: String  // + version
    let updateInstallButton: String
    let updateDownloading: String
    let updateInstalling: String
    let updateFailedPrefix: String
    let updateLastChecked: String
    let updateNotifyTitle: String
    let updateInstallFailedBody: String
    let updateNeedsApplicationsTitle: String
    let updateNeedsApplicationsBody: String
    let menuCheckUpdates: String

    // MARK: Permissions (shared by Settings & onboarding)
    let permissionRequired: String
    let permissionAccessibility: String
    let permissionScreenRecording: String
    let permissionGranted: String
    let permissionMissing: String
    let permissionOpenSettings: String
    let permissionRequest: String
    let permissionRestartNote: String

    // MARK: About
    let aboutDescription: String
    let versionPrefix: String
    let reviewIntro: String
    let viewOnGitHub: String

    // MARK: Onboarding
    let obContinue: String
    let obBack: String
    let obSkipStep: String
    let obStart: String
    let obStepWelcomeTitle: String
    let obStepWelcomeBody: String
    let obWelcomeBullet1Title: String
    let obWelcomeBullet1Body: String
    let obWelcomeBullet2Title: String
    let obWelcomeBullet2Body: String
    let obWelcomeBullet3Title: String
    let obWelcomeBullet3Body: String
    let obLanguageLabel: String
    let obStepAccessibilityTitle: String
    let obStepAccessibilityBody: String
    let obAccessibilityWhy: String
    let obStepRecordingTitle: String
    let obStepRecordingBody: String
    let obRecordingWhy: String
    let obStepMonitorTitle: String
    let obStepMonitorBody: String
    let obMonitorNoPermission: String
    let obStepOptionalTitle: String
    let obStepOptionalBody: String
    let obStepStatusTitle: String
    let obStepStatusBody: String
    let obStatusRecheck: String
    let obStepDoneTitle: String
    let obStepDoneBody: String
    let obDoneHint: String
    let obWhatsNewTitle: String
    let obWhatsNewFallback: String
    let obLanguageUpdateTitle: String
    let obLanguageUpdateBody: String
    let obPurposeTitle: String
    let obPurposeBody: String
    let obPurposeSkip: String

    // MARK: Settings — monitor / menu bar metrics
    let tabMonitor: String
    let monitorMenuBarSection: String
    let monitorMenuBarCaption: String
    let monitorCombineTemperatures: String
    let monitorCombineTemperaturesCaption: String
    let monitorSeparateMenuBarMetrics: String
    let monitorSeparateMenuBarMetricsCaption: String
    let monitorNetworkUploadFirst: String
    let monitorShowCPU: String
    let monitorShowMemory: String
    let monitorShowNetwork: String
    let monitorShowPowerLabel: String
    let monitorIntervalLabel: String
    let monitorInterval1: String
    let monitorInterval2: String
    let monitorInterval5: String
    let monitorPanelSection: String
    let panelNavigationMode: String
    let panelNavigationCaption: String
    let panelFooterSections: String
    let panelFooterList: String
    let fanControlBetaShow: String
    let fanControlBetaSection: String
    let fanControlBetaTitle: String
    let fanControlBetaStatus: String
    let fanControlBetaCaption: String
    let fanControlModeAutomatic: String
    let fanControlModeManual: String
    let betaBadge: String
    let betaFeatureWarning: String

    // MARK: Panel — network
    let networkSection: String
    let networkDownload: String
    let networkUpload: String
    let networkThisSession: String
    let networkMeasuring: String
    let networkApps: String
    let networkAppsIdle: String

    // MARK: Panel — disk
    let diskSection: String
    let diskUsed: String
    let diskFree: String
    let diskInternal: String
    let diskExternal: String
    let diskSelect: String
    let diskRead: String
    let diskWrite: String
    let diskSMARTStatus: String
    let diskSMARTUnavailable: String
    let diskTotalRead: String
    let diskTotalWritten: String
    let diskTemperature: String
    let diskHealth: String
    let diskPowerCycles: String
    let diskPowerOnHours: String
    let diskUnsafeShutdowns: String
    let diskMediaErrors: String
    let diskEject: String
    let diskEjectAll: String
    let diskEjecting: String
    let diskReadyToRemove: String
    let diskEjectFailed: String
    let diskProtectionCaption: String
    let diskNoExternal: String
    let diskOpenInFinder: String
    let diskStorageSettings: String
    let diskNoDisks: String

    // MARK: Panel — power
    let powerSection: String
    let powerSystem: String
    let powerAdapter: String
    let powerBattery: String
    let powerCharging: String
    let powerOnBattery: String
    let powerPluggedIn: String
    let powerUnavailable: String
    let powerAdapterMaxFormat: String   // + rated watts, e.g. "30 W max"
    let monitorShowGPU: String
    let monitorShowCPUTemperature: String
    let monitorShowGPUTemperature: String
    let monitorShowBatteryTemperature: String
    let monitorShowPeripheralBattery: String
    let peripheralBatteryNoDevices: String
    let monitorGraphsSection: String
    let monitorGraphsCaption: String

    // MARK: Update notification + onboarding menu bar setup
    let updateBannerTitle: String
    let updateBannerAction: String
    let obStepMenuBarTitle: String
    let obStepMenuBarBody: String
    let obStepMenuBarNote: String
    let monitorMenuBarPresetLabel: String
    let menuBarPresetReadable: String
    let menuBarPresetDense: String
    let menuBarSpacingLabel: String
    let menuBarSpacingStandard: String
    let menuBarSpacingCompact: String
    let menuBarHideIconToggle: String
    let menuBarHideIconCaption: String
    let monitorLabelStyleLabel: String
    let menuBarLabelStyleCompact: String
    let menuBarLabelStyleClassic: String
    let monitorMemoryStyleLabel: String
    let monitorMemoryPressureDot: String
    let memoryStyleDot: String
    let memoryStylePercent: String
    let memoryStyleBoth: String

    // MARK: System uptime, battery health, speed test
    let systemUptime: String
    let batteryCharge: String
    let powerHealth: String
    let powerCycles: String
    let speedTestRun: String
    let speedTestAgain: String
    let speedTestLatency: String
    let speedTestTesting: String
    let speedTestFailed: String

    // MARK: Per-item panel config (Settings + onboarding)
    let monitorShowInPanel: String
    let panelHideItem: String
    let panelShowItem: String
    let panelHiddenItem: String
    let monitorItemUptime: String
    let monitorItemNetSpeed: String
    let monitorItemNetTotals: String
    let monitorItemNetTest: String
    let monitorItemDiskUsage: String
    let monitorItemDiskActivity: String
    let monitorItemDiskSMART: String
    let monitorItemDiskProtection: String
    let monitorItemDiskTools: String
    let monitorPanelConfigHint: String
    let monitorOrderSection: String
    let monitorOrderHint: String
    let obStepPanelTitle: String
    let obStepPanelBody: String
    let obStepPanelNavigationTitle: String
    let obStepPanelNavigationBody: String

    // MARK: Cleaning mode
    let cleaningMenuItem: String
    let utilitiesSection: String
    let quickControlsSection: String
    let panelCategoryWindows: String
    let panelCategoryInput: String
    let panelCategoryFiles: String
    let windowMaximizeName: String
    let windowMaximizeCaption: String
    let windowMaximizeActiveNow: String
    let windowMaximizeNeedsAccessibility: String
    let keyDebounceName: String
    let keyDebounceEnable: String
    let keyDebounceCaption: String
    let keyDebounceActiveNow: String
    let keyDebounceGlobalWindow: String
    let keyDebouncePerKeySection: String
    let keyDebouncePerKeyCaption: String
    let keyDebounceKeyLabel: String
    let keyDebounceWindowLabel: String
    let keyDebounceAddKey: String
    let keyDebounceNoOverrides: String
    let keyDebounceRemoveKey: String
    let cleaningPanelCaption: String
    let cleaningOverlayTitle: String
    let cleaningOverlaySubtitle: String
    let cleaningOverlayUnlock: String
    let cleaningOverlayMouseHint: String
    let cleaningNeedsAxTitle: String
    let cleaningNeedsAxBody: String

    // MARK: Support / donate
    let tabSupport: String
    let shortcutsPageCaption: String
    let shortcutsPageTitle: String
    let settingsSearchPlaceholder: String
    let donateHeading: String
    let donateMessage: String
    let donateButton: String
    let donateThanks: String
    let supportIntroTitle: String
    let supportIntroMessage: String
    let supportIntroStarButton: String
    let supportIntroCoffeeButton: String
    let supportIntroLaterButton: String
    let supportIntroDoneButton: String
    let communityIntroTitle: String
    let communityIntroMessage: String
    let communityIntroFollowButton: String
    let homebrewOfficialIntroTitle: String
    let homebrewOfficialIntroMessage: String
    let homebrewOfficialIntroInstallLabel: String
    let homebrewOfficialIntroMigrationTitle: String
    let homebrewOfficialIntroMigrationMessage: String
    let homebrewOfficialIntroCopyButton: String
    let updateShowcaseTitle: String
    let updateShowcaseMessage: String
    let updateShowcaseUnavailable: String
    let updateShowcaseRestart: String
    let showMenuBarIcon: String
    let showMenuBarIconCaption: String
    let menuBarIconStillHiddenTitle: String
    let menuBarIconStillHiddenBody: String
    let menuBarIconManagerHintFormat: String  // + manager name (twice)

    // MARK: Configurable shortcuts
    let shortcutRecording: String
    let shortcutReset: String
    let shortcutNone: String
    let shortcutClear: String
    let shortcutInvalid: String
    let shortcutPressKeys: String
    let shortcutEscapeHint: String
    let shortcutDeleteHint: String
    let shortcutNotCaptured: String
    let shortcutConflictFormat: String
    let shortcutUnavailable: String
    let shelfShortcutToggle: String
    let switcherUsageHintFormat: String

    // MARK: Media keys
    let musicBlockSection: String
    let musicBlockTitle: String
    let musicBlockCaption: String
    let musicBlockReplacementLabel: String
    let musicBlockReplacementNone: String
    let musicBlockChooseApp: String

    // MARK: Cleaner
    let cleanerName: String
    let cleanerIntroTitle: String
    let cleanerIntroCaption: String
    let cleanerScan: String
    let cleanerScanning: String
    let cleanerCleaning: String
    let cleanerCatLeftovers: String
    let cleanerCatLoginItems: String
    let cleanerCatCaches: String
    let cleanerCatLogs: String
    let cleanerCatDeveloper: String
    let cleanerCatTrash: String
    let cleanerLeftoversNote: String
    let cleanerLoginItemsNote: String
    let cleanerTrashNote: String
    let cleanerCatDeviceBackups: String
    let cleanerDeviceBackupsCaption: String
    let cleanerNothingFound: String
    let cleanerClean: String
    let cleanerDoneNote: String
    let cleanerAgain: String
    let cleanerRevealInFinder: String
    let cleanerPanelCaption: String
    let cleanerSafeSection: String
    let cleanerOptionalSection: String
    let cleanerCatOtherCaches: String
    let cleanerCachesCaption: String
    let cleanerLogsCaption: String
    let cleanerDeveloperCaption: String
    let cleanerLoginItemsCaption: String
    let cleanerLeftoversCaption: String
    let cleanerOtherCachesCaption: String
    let cleanerCleanSizeFormat: String      // + size string
    let cleanerScheduleTitle: String
    let cleanerScheduleOff: String
    let cleanerScheduleDaily: String
    let cleanerScheduleWeekly: String
    let cleanerScheduleCaption: String
    let cleanerScheduleLastFormat: String   // + size string
    let cleanerAutoNotificationFormat: String  // + size string
    let cleanerScheduleNextFormat: String   // + relative date and time
    let cleanerScheduleRanFormat: String    // + relative date and time
    let cleanerScheduleNotifyToggle: String
    let cleanerNotifDenied: String
    let cleanerNotifOpenSettings: String
    let launchAtLoginNeedsApplications: String
    let ocrQRToggle: String
    let ocrQRCaption: String
    let ocrQRCopied: String
    let qrResultTitle: String
    let qrResultCopy: String
    let qrResultOpen: String
    let highlightsTitle: String
    let highlightsCaptionDockPreview: String
    let highlightsCaptionScreenshot: String
    let highlightsCaptionSnippetLibrary: String
    let highlightsConfigure: String
    let highlightsTry: String
    let highlightsSeeAll: String
    let switcherCurrentSpaceOnly: String
    let switcherCurrentSpaceOnlyCaption: String
    let shelfFileMissing: String
}

// MARK: - Português (Brasil)

extension Strings {
    static let ptBR = Strings(
        statusIdleTooltip: "Vorssaint: suspensão normal",
        statusActiveUntil: "Vorssaint: ativo até",
        statusActiveIndefinite: "Vorssaint: ativo indefinidamente",
        menuEnableAwake: "Ativar manter acordado",
        menuDisableAwake: "Desativar manter acordado",
        menuActivateFor: "Ativar por…",
        menuSettings: "Ajustes…",
        menuAbout: "Sobre o Vorssaint",
        menuQuit: "Sair do Vorssaint",
        menuHide: "Ocultar o Vorssaint",
        menuHideOthers: "Ocultar Outros",
        menuShowAll: "Mostrar Tudo",
        menuEdit: "Editar",
        menuUndo: "Desfazer",
        menuRedo: "Refazer",
        menuCut: "Recortar",
        menuCopy: "Copiar",
        menuPaste: "Colar",
        menuSelectAll: "Selecionar Tudo",
        menuWindow: "Janela",
        menuMinimize: "Minimizar",
        menuZoom: "Zoom",
        menuClose: "Fechar",

        minutes15: "15 minutos",
        minutes30: "30 minutos",
        hour1: "1 hora",
        hours2: "2 horas",
        hours4: "4 horas",
        hours8: "8 horas",
        indefinitely: "Indefinidamente",
        indefinite: "Indefinida",

        panelSettings: "Ajustes",
        panelQuit: "Sair",
        panelHotkeyHint: "Atalho alterna",

        keepAwakeTitle: "Manter acordado",
        keepAwakeEndsIn: "Termina em",
        keepAwakeUntilDisabled: "Ativo até você desativar",
        keepAwakeNormalRules: "O Mac segue as regras normais de energia",
        keepAwakeOptions: "Opções",
        keepAwakeMouseJiggle: "Mover cursor levemente",
        keepAwakeMouseJiggleCaption: "Durante uma sessão, move o cursor um pouco no intervalo escolhido.",
        keepAwakeMouseJiggleInterval: "Intervalo",
        keepAwakeActiveIconLabel: "Ícone ativo",
        keepAwakeActiveIconVorssaint: "Vorssaint",
        keepAwakeActiveIconCoffee: "Café",
        keepAwakeActiveIconEye: "Olho",
        keepAwakeActiveIconMoon: "Lua",
        keepAwakeActiveIconLight: "Lâmpada",
        keepAwakeIconTintLabel: "Cor do ícone ativo",
        keepAwakeIconTintOrange: "Laranja",
        keepAwakeIconTintGreen: "Verde",
        keepAwakeIconTintBlue: "Azul",
        keepAwakeIconTintPurple: "Roxo",
        keepAwakeIconTintPink: "Rosa",
        keepAwakeIconTintNone: "Sem cor",
        durationLabel: "Duração",
        clamshellTitle: "Continuar com a tampa fechada",
        clamshellOnCaption: "Suspensão totalmente desativada. Atenção à energia",
        clamshellNeedsSession: "Será aplicada sempre que “Manter acordado” estiver ativo",
        clamshellReady: "Pronto. Liga e desliga sem senha",
        clamshellNeedsPassword: "Pedirá a senha de administrador uma vez",

        systemSection: "Sistema",
        temperatures: "Temperaturas",
        cpuLabel: "CPU",
        gpuLabel: "GPU",
        batteryLabel: "Bateria",
        usageSection: "Uso de hardware",
        memorySection: "Memória",
        memoryPressure: "Pressão",
        pressureNormal: "Normal",
        pressureWarning: "Atenção",
        pressureCritical: "Crítico",
        monitorUnavailable: "Sensores indisponíveis neste Mac",
        energyAppsTitle: "Uso significativo de energia",
        energyAppsIdle: "Sem uso significativo de energia",

        notifySessionEndedTitle: "Sessão encerrada",
        notifySessionEndedBody: "O tempo acabou. O Mac voltará a suspender normalmente.",
        notifyBatteryTitle: "Vorssaint desativado",
        notifyBatteryBody: "Bateria baixa. A suspensão normal foi restaurada para proteger a carga.",
        adminPromptClamshellOn: "O Vorssaint precisa da sua senha para manter o Mac ativo com a tampa fechada.",
        adminPromptClamshellOff: "O Vorssaint precisa da sua senha para reativar a suspensão normal do Mac.",
        adminPromptRecover: "O Vorssaint foi encerrado com a suspensão do Mac desativada. Digite a senha para restaurar a suspensão normal.",
        adminPromptUpdate: "O Vorssaint precisa da sua senha para instalar a atualização.",
        adminPromptSudoersInstall: "O Vorssaint vai criar uma regra restrita (somente pmset disablesleep) para alternar a tampa fechada sem pedir senha. Esta é a única vez que a senha será necessária.",
        adminPromptSudoersRemove: "O Vorssaint vai remover a regra de tampa fechada sem senha.",

        settingsTitle: "Ajustes do Vorssaint",
        tabGeneral: "Geral",
        tabEnergy: "Energia",
        tabMouse: "Mouse e Trackpad",
        tabSwitcher: "Alternador",
        tabAdvanced: "Avançado",
        tabAbout: "Sobre",
        tabReleaseNotes: "Novidades",
        releaseNotesOnUpdateToggle: "Mostrar novidades ao atualizar",
        whatsNewDontShowAgain: "Não mostrar novamente",
        previewSizeLabel: "Tamanho dos previews",
        previewSizeNormal: "Normal",
        previewSizeLarge: "Grande",
        previewSizeXLarge: "Extra grande",
        settingsGroupFeatures: "Recursos",
        advancedResetSection: "Permissões",
        advancedResetDescription: "Remove todas as permissões que você concedeu ao Vorssaint (Acessibilidade, Gravação de Tela, Acesso Total ao Disco e outras), o item de início e a regra de tampa fechada. Útil para começar do zero ou antes de desinstalar. O app continua instalado.",
        advancedClearButton: "Limpar todas as permissões",
        advancedCleared: "Permissões limpas.",
        advancedClearConfirmTitle: "Limpar todas as permissões?",
        advancedClearConfirmBody: "Os recursos que dependem de permissão vão parar de funcionar até você conceder de novo. As suas configurações são mantidas.",
        advancedUninstallSection: "Desinstalar",
        advancedUninstallDescription: "Faz tudo acima e ainda apaga as preferências e move o Vorssaint para a Lixeira, sem deixar rastro no sistema. O app fecha ao final. Você pode reinstalar quando quiser.",
        advancedUninstallButton: "Desinstalar o Vorssaint completamente",
        advancedUninstallConfirmTitle: "Desinstalar o Vorssaint?",
        advancedUninstallConfirmBody: "O Vorssaint vai limpar as permissões, apagar as preferências e ir para a Lixeira, e então fechar. Esta ação não pode ser desfeita pelo app, mas ele fica na Lixeira até você esvaziá-la.",

        launchAtLogin: "Iniciar junto com o Mac",
        languageLabel: "Idioma",
        menuBarSection: "Barra de menus",
        showCountdown: "Mostrar tempo restante ao lado do ícone",
        globalHotkeySection: "Atalho global",
        hotkeyToggle: "Ativar atalho para “Manter acordado”",
        hotkeyCaption: "Funciona em qualquer app, sem permissões extras.",

        sessionSection: "Sessão",
        defaultDurationLabel: "Duração padrão",
        keepAwakeAutoStart: "Manter acordado ao abrir o Vorssaint",
        keepAwakeAutoStartCaption: "Inicia uma sessão com a duração padrão.",
        batteryProtectionSection: "Proteção de bateria",
        batteryDisableBelow: "Desativar com bateria abaixo de",
        batteryNever: "Nunca",
        batteryProtectionCaption: "Evita que uma sessão esquecida drene a bateria do MacBook.",
        clamshellSection: "Tampa fechada",
        configuring: "Configurando…",
        sudoersFailed: "Não foi possível ativar a tampa fechada. Tente de novo.",
        clamshellExplanation: "“Continuar com a tampa fechada” desativa completamente a suspensão enquanto “Manter acordado” estiver ativo e é revertido automaticamente quando a sessão termina ou o app é encerrado. Prefira usá-lo conectado à energia.",

        scrollSection: "Rolagem",
        invertMouseScroll: "Inverter rolagem do mouse",
        invertMouseScrollCaption: "Inverte a direção da roda do mouse.",
        scrollTrackpadNote: "O trackpad não muda: continua com a rolagem natural do macOS.",
        scrollActiveNow: "Invertendo a rolagem do mouse agora",
        mouseNavigationActiveNow: "Botões laterais ativos agora",
        smoothScrollName: "Rolagem suave",
        smoothScrollCaption: "Transforma cada passo da rodinha do mouse em um deslize curto e macio. O trackpad não muda.",
        smoothScrollStepLabel: "Distância por passo",
        mouseNavigationSection: "Navegação",
        mouseNavigationEnable: "Usar botões laterais para voltar e avançar",
        mouseNavigationCaption: "Converte os botões Voltar e Avançar do mouse em comandos de navegação no Finder, navegadores e apps compatíveis.",
        middleClickSection: "Botão do meio",
        middleClickEnable: "Clique com três dedos vira botão do meio",
        middleClickEnableCaption: "Pressionar o trackpad com três dedos funciona como o clique da rodinha do mouse: abre links em nova aba, fecha abas e tudo mais que o botão do meio faz.",
        middleClickDragConflict: "O arrastar com três dedos do macOS está ativado e usa esse mesmo gesto. Desative-o nos Ajustes do Sistema em Acessibilidade, Controle do Cursor, Opções do Trackpad, e o clique do meio vai funcionar.",
        middleClickTapPicker: "Toque leve também clica",
        middleClickTapOff: "Desligado",
        middleClickTapThreeFingers: "3 dedos",
        middleClickTapFourFingers: "4 dedos",
        middleClickTapCaption: "Um toque leve com esse número de dedos, sem pressionar, também dispara o clique do meio. Deslizar nunca conta. Se o toque de três dedos do macOS estiver atribuído à Busca, desative-o para os dois não abrirem juntos.",
        quickToolsTab: "Ferramentas rápidas",
        quickToolShortcutToggle: "Atalho global",
        ocrName: "Copiar texto da tela",
        ocrCaption: "Selecione uma área da tela e o texto reconhecido é copiado, pronto para colar.",
        ocrCopied: "Texto copiado",
        ocrNoText: "Nenhum texto encontrado",
        colorPickerName: "Conta-gotas de cor",
        colorPickerCaption: "Capture a cor de qualquer pixel da tela e copie no formato que preferir.",
        colorPickerFormatLabel: "Formato copiado",
        colorPickerBareHexToggle: "Copiar sem o prefixo #",
        colorPickerPickNow: "Capturar cor",
        micMuteName: "Silenciar microfone",
        micUnmuteName: "Reativar microfone",
        micMuteCaption: "Corta o microfone do Mac com um clique ou atalho, valendo para qualquer app.",
        micMutedHUD: "Microfone silenciado",
        micUnmutedHUD: "Microfone reativado",
        micMuteMenuBarToggle: "Mostrar na barra de menus enquanto silenciado",
        micMuteMenuBarCaption: "Um microfone cortado em vermelho aparece ao lado do ícone do app na barra de menus.",
        pastePlainName: "Colar como texto puro",
        pastePlainCaption: "Cola o que foi copiado sem cores, fontes ou formatação. O conteúdo original continua no clipboard.",
        launcherName: "Painel rápido",
        launcherCaption: "Um painel flutuante com suas ferramentas favoritas, aberto por atalho de qualquer lugar.",
        launcherOpenNow: "Abrir painel rápido",
        launcherEditHint: "Use o botão de ajustes para escolher, ocultar e arrastar as ferramentas.",
        launcherEmptyState: "Todas as ferramentas estão ocultas. Use o botão de ajustes para trazê-las de volta.",
        launcherAddSection: "Adicionar de volta",
        launcherKeysHint: "Setas navegam, Enter abre, 1 a 9 abrem direto",

        switcherSection: "Alternador de apps",
        switcherEnable: "Usar o alternador do Vorssaint",
        switcherEnableCaption: "Troque de app ou janela, inclusive janelas minimizadas e várias janelas do mesmo app.",
        switcherUsageHint: "Segure o atalho para navegar; solte para ativar a janela. Shift ou ← volta; Q fecha o app selecionado; Esc cancela.",
        switcherNoWindows: "Nenhuma janela aberta",
        switcherIconRowMode: "Mostrar ⌘Tab com ícones grandes",
        switcherIconRowModeCaption: "Mostra um ícone por app com os previews das janelas do app acima.",
        switcherSimpleMode: "Alternador simples",
        switcherSimpleModeCaption: "Mostra ícones de apps e títulos das janelas, sem previews nem captura da tela pelo alternador.",
        switcherShortcutHintApps: "Apps",
        switcherShortcutHintWindows: "Janelas",
        switcherWindowShortcutCaption: "Com o seletor aberto, pula entre as janelas do app selecionado.",
        switcherMergeTabs: "Mostrar uma entrada por app",
        switcherMergeTabsCaption: "Junta todas as janelas de um app em uma só entrada no alternador, em vez de uma por janela.",
        switcherShowFinder: "Mostrar Finder sem janelas",
        switcherShowFinderCaption: "Mostra o Finder no alternador mesmo quando nenhuma janela do Finder estiver aberta.",
        dockPreviewName: "Dock Preview",
        dockPreviewEnable: "Pré-visualizar janelas no Dock",
        dockPreviewEnableCaption: "Passe o mouse em um app aberto no Dock para ver e espiar suas janelas.",
        dockClickMinimize: "Clicar no Dock minimiza",
        dockClickMinimizeCaption: "As janelas do app ativo são minimizadas ao clicar no ícone dele no Dock. Clique de novo para trazê-las de volta.",
        dockClickCycleWindows: "Clicar no Dock alterna janelas",
        dockClickCycleWindowsCaption: "Clique no ícone do Dock do app ativo para alternar entre suas janelas, como ⌘`.",
        dockPreviewActiveNow: "Ativo no Dock",
        dockPreviewDockUnavailable: "Não foi possível ler os itens do Dock.",
        dockPreviewAutohideBeta: "Beta. Você pode encontrar alguns bugs.",
        dockPreviewOpenWindow: "Abrir janela",
        dockPreviewCloseWindow: "Fechar janela",
        dockPreviewMinimizeWindow: "Minimizar janela",
        dockPreviewRestoreWindow: "Restaurar janela",
        dockPreviewPinPanel: "Fixar prévia",
        dockPreviewUnpinPanel: "Desfixar prévia",
        dockPreviewPinned: "Fixado",
        dockPreviewClosePanel: "Fechar prévia",
        dockPreviewPreviousWindow: "Janela anterior",
        dockPreviewNextWindow: "Próxima janela",
        dockPreviewIntroPeek: "Passe o mouse em uma miniatura para espiar. Clique para abrir a janela.",
        dockPreviewIntroSettingsHint: "Você pode mudar isso depois em Ajustes › Switcher.",
        dockPreviewIntroLater: "Agora não",
        dockPreviewIntroEnable: "Ativar Dock Preview",

        cutPasteName: "Recortar e colar",
        cutPasteEnable: "Recortar e colar arquivos no Finder",
        cutPasteEnableCaption: "Use ⌘X para recortar e ⌘V para mover arquivos e pastas no Finder.",
        cutPasteHowTitle: "Como usar",
        cutPasteStep1: "Selecione itens no Finder e pressione ⌘X para recortá-los.",
        cutPasteStep2: "Abra a pasta de destino e pressione ⌘V para movê-los para lá.",
        cutPasteTextNote: "Em campos de texto (como ao renomear), ⌘X e ⌘V continuam funcionando normalmente.",
        cutPasteActiveNow: "Pronto para recortar no Finder",
        cutPasteAutomationNote: "Na primeira vez, o macOS pede permissão para controlar o Finder.",
        cutReadyTitle: "Recortado",
        cutReadyHint: "na pasta de destino para mover",
        cutCancel: "Cancelar recorte",
        cutDoneTitle: "Movido!",
        cutMovedSingular: "1 item movido",
        cutMovedPluralFormat: "%d itens movidos",
        cutSomeFailed: "Alguns itens não puderam ser movidos",
        cutMovingTitle: "Movendo…",
        cutMovingCountFormat: "%d de %d",

        autoQuitName: "Encerrar ao fechar",
        autoQuitEnable: "Encerrar o app ao fechar a última janela",
        autoQuitEnableCaption: "Fechar a última janela de um app também o encerra.",
        autoQuitActiveNow: "Ativo agora",
        autoQuitHowTitle: "Como funciona",
        autoQuitStep1: "Feche a última janela de um app (⌘W ou o botão vermelho).",
        autoQuitStep2: "O app é encerrado sozinho. Diálogos de “salvar?” continuam aparecendo.",
        autoQuitPredictableNote: "Apps que normalmente rodam sem janela nunca são encerrados.",
        autoQuitExceptionsTitle: "Exceções",
        autoQuitExceptionsCaption: "Apps nesta lista continuam abertos mesmo sem nenhuma janela.",
        autoQuitExceptionsEmpty: "Nenhuma exceção",
        autoQuitAddApp: "Adicionar app…",

        uninstallerName: "Desinstalador",
        uninstallerEnableCaption: "Remove um app junto com os caches, preferências, logs e resíduos que ele deixa para trás.",
        uninstallerStep1: "Arraste um app para os Ajustes ou escolha um da lista.",
        uninstallerStep2: "Revise os arquivos encontrados e quanto espaço ocupam.",
        uninstallerStep3: "Mova o que quiser para a Lixeira. Nada é apagado de forma definitiva.",
        uninstallerMenuItem: "Desinstalar um app…",
        uninstallerDropTitle: "Arraste um app aqui",
        uninstallerDropSubtitle: "ou escolha um para analisar",
        uninstallerChoose: "Escolher app…",
        uninstallerPickerTitle: "Escolher app",
        uninstallerPickerSearch: "Buscar apps",
        uninstallerPickerEmpty: "Nenhum app encontrado",
        uninstallerEmptyNote: "Nada é removido sem a sua confirmação.",
        uninstallerFDANote: "Conceda Acesso Total ao Disco para uma análise mais completa.",
        uninstallerFDAGrant: "Conceder acesso…",
        uninstallerFDAHint: "Ative o Vorssaint na lista. Se ele não aparecer, clique no + e escolha o Vorssaint em Aplicativos. O acesso só vale depois de reabrir o app.",
        uninstallerFDARelaunch: "Reabrir agora",
        uninstallerScanning: "Analisando arquivos…",
        uninstallerRemoving: "Movendo para a Lixeira…",
        uninstallerFoundTitle: "encontrado",
        uninstallerSelectedFormat: "%d de %d selecionados",
        uninstallerRemove: "Mover para a Lixeira",
        uninstallerCancel: "Cancelar",
        uninstallerDoneTitle: "Pronto!",
        uninstallerFreedFormat: "%@ recuperados",
        uninstallerSomeFailed: "Alguns itens não puderam ser movidos para a Lixeira.",
        uninstallerAnother: "Desinstalar outro",
        uninstallerCatApp: "Aplicativo",
        uninstallerCatSupport: "Suporte",
        uninstallerCatCaches: "Caches",
        uninstallerCatPreferences: "Preferências",
        uninstallerCatContainers: "Contêineres",
        uninstallerCatLogs: "Logs",
        uninstallerCatState: "Estado salvo",
        uninstallerCatOther: "Outros",

        urlCleanerName: "Limpar URL",
        urlCleanerEnable: "Limpar URLs copiadas",
        urlCleanerEnableCaption: "Remove parâmetros de rastreamento de links copiados.",
        urlCleanerActiveNow: "Ativo agora",
        urlCleanerManualTitle: "Limpar agora",
        urlCleanerInputPlaceholder: "Cole uma URL",
        urlCleanerOutputPlaceholder: "A URL limpa aparece aqui",
        urlCleanerCleanButton: "Limpar",
        urlCleanerPasteButton: "Colar",
        urlCleanerCopyButton: "Copiar",
        urlCleanerClearButton: "Limpar campo",
        urlCleanerNoURL: "Cole uma URL válida.",
        urlCleanerNoChange: "Nada para limpar.",
        urlCleanerCleaned: "URL limpa.",
        urlCleanerCopied: "Copiado.",
        urlCleanerLocalNote: "Local. Sem rede.",

        homebrewName: "Homebrew",
        homebrewEnableCaption: "Pesquise, instale e remova fórmulas e casks.",
        homebrewMissingTitle: "Homebrew não encontrado",
        homebrewMissingBody: "O Vorssaint pode abrir o Terminal com o instalador oficial do Homebrew. O Terminal mostra os passos e pede sua senha se precisar.",
        homebrewInstallHomebrew: "Instalar Homebrew",
        homebrewInstallHomebrewCaption: "Depois que terminar no Terminal, volte aqui e clique em Atualizar.",
        homebrewInstallHomebrewOpened: "Instalador aberto no Terminal.",
        homebrewShellSetupTitle: "Finalizar configuração do Terminal",
        homebrewShellSetupBody: "O Homebrew está instalado, mas o Terminal ainda pode não encontrar o comando brew. O Vorssaint pode abrir o Terminal com o comando de configuração.",
        homebrewShellSetupButton: "Configurar Terminal",
        homebrewShellSetupOpened: "Comando aberto no Terminal. Depois volte aqui e clique em Atualizar.",
        homebrewRefresh: "Atualizar",
        homebrewCheckPackages: "Verificar pacotes",
        homebrewTrustTitle: "Tap ainda não confiável",
        homebrewTrustCaption: "O Homebrew agora pede sua confirmação antes de usar taps de terceiros. Confie em %@ para continuar.",
        homebrewTrustButton: "Confiar e continuar",
        homebrewSearchPlaceholder: "Pesquisar pacotes",
        homebrewKeyboardHint: "Espaço ou Enter fecham o painel do macOS. Use o botão de busca.",
        homebrewSearchButton: "Pesquisar",
        homebrewSearchResults: "Resultados",
        homebrewInstalled: "Instalados",
        homebrewAll: "Todos",
        homebrewFormulas: "Fórmulas",
        homebrewCasks: "Casks",
        homebrewNoPackages: "Nenhum pacote encontrado",
        homebrewNoSelection: "Selecione um pacote instalado ou pesquise um novo.",
        homebrewDetailsTitle: "Detalhes do pacote",
        homebrewInstall: "Instalar",
        homebrewUninstall: "Desinstalar",
        homebrewUpgrade: "Atualizar",
        homebrewUpgradeAll: "Atualizar tudo",
        homebrewUpdateHomebrew: "Atualizar Homebrew",
        homebrewAllPackages: "pacotes",
        homebrewOpenTerminal: "Abrir Terminal",
        homebrewCancelOperation: "Cancelar",
        homebrewClearLog: "Limpar log",
        homebrewLogTitle: "Log",
        homebrewVersion: "Versão",
        homebrewDescription: "Tipo",
        homebrewHomepage: "Abrir site",
        homebrewPopularity: "Popularidade",
        homebrewPopularityFormat: "%@ instalações em %@ dias",
        homebrewInstalledBadge: "Instalado",
        homebrewNotInstalledBadge: "Não instalado",
        homebrewUpdates: "Atualizações",
        homebrewUpdateAvailableBadge: "Atualização disponível",
        homebrewLatestVersion: "Mais recente",
        homebrewConfirmInstallTitle: "Instalar pelo Homebrew?",
        homebrewConfirmInstallBodyFormat: "O Homebrew vai baixar e instalar %@. Dependências também podem ser instaladas.",
        homebrewConfirmUninstallTitle: "Desinstalar pelo Homebrew?",
        homebrewConfirmUninstallBodyFormat: "O Homebrew vai desinstalar %@. Arquivos de configuração podem permanecer no sistema.",
        homebrewConfirmUpgradeTitle: "Atualizar pelo Homebrew?",
        homebrewConfirmUpgradeBodyFormat: "O Homebrew vai baixar e aplicar a versão mais recente de %@. Dependências também podem ser atualizadas.",
        homebrewConfirmUpgradeAllTitle: "Atualizar todos pelo Homebrew?",
        homebrewConfirmUpgradeAllBody: "O Homebrew vai baixar e aplicar as versões mais recentes dos pacotes com atualização disponível. Dependências também podem ser atualizadas.",
        homebrewConfirmUpdateHomebrewTitle: "Atualizar Homebrew?",
        homebrewConfirmUpdateHomebrewBody: "O Homebrew vai buscar as informações mais recentes e depois recarregar seus pacotes.",
        homebrewTerminalFallback: "Esta operação precisa do Terminal para pedir a senha de administrador. O Vorssaint não captura senhas.",
        homebrewLoading: "Carregando…",
        homebrewSearchEmpty: "Nenhum resultado",
        homebrewOperationInstallFormat: "Instalando %@",
        homebrewOperationUninstallFormat: "Desinstalando %@",
        homebrewOperationUpgradeFormat: "Atualizando %@",
        homebrewOperationUpgradeAll: "Atualizando pacotes",
        homebrewOperationUpdateHomebrew: "Atualizando Homebrew",
        homebrewOperationInstalledFormat: "%@ instalado.",
        homebrewOperationUninstalledFormat: "%@ desinstalado.",
        homebrewOperationUpgradedFormat: "%@ atualizado.",
        homebrewOperationUpgradedAll: "Pacotes atualizados.",
        homebrewOperationUpdatedHomebrew: "Homebrew atualizado.",
        homebrewOperationFailedFormat: "Não foi possível concluir %@.",
        homebrewOperationCancelled: "Operação cancelada.",
        homebrewOperationPreparing: "Preparando...",
        homebrewOperationDownloading: "Baixando arquivos...",
        homebrewOperationInstalling: "Instalando arquivos...",
        homebrewOperationUninstalling: "Removendo arquivos...",
        homebrewOperationUpgrading: "Atualizando arquivos...",
        homebrewOperationFinalizing: "Finalizando...",
        homebrewOperationRefreshing: "Atualizando lista...",
        homebrewOperationTerminal: "Continue no Terminal.",
        homebrewOperationElapsedFormat: "%@ decorridos",
        homebrewOperationShowDetails: "Mostrar detalhes",
        homebrewOperationHideDetails: "Ocultar detalhes",
        homebrewOperationTechnicalLog: "Detalhes técnicos",
        homebrewOperationProgressUnknown: "O Homebrew ainda não informou uma porcentagem.",

        mediaName: "Media",
        mediaEnableCaption: "Comprima vídeos e imagens, crie GIFs e extraia texto localmente.",
        mediaLocalNote: "Local. Sem rede.",
        mediaToolVideo: "Vídeo",
        mediaToolGIF: "GIF",
        mediaToolImage: "Imagem",
        mediaToolText: "Texto",
        mediaSelectFile: "Escolher arquivo",
        mediaDropHint: "Arraste um arquivo aqui ou clique para escolher.",
        mediaOutput: "Saída",
        mediaOutputAutomatic: "Automática",
        mediaChooseOutput: "Destino",
        mediaStartVideo: "Comprimir vídeo",
        mediaStartGIF: "Criar GIF",
        mediaStartImage: "Comprimir imagem",
        mediaStartConvertPDF: "Converter em PDF",
        mediaStartText: "Extrair texto",
        mediaCancel: "Cancelar",
        mediaStartTime: "Início",
        mediaEndTime: "Fim",
        mediaQuality: "Compressão",
        mediaCompressionLow: "Baixa",
        mediaCompressionMedium: "Média",
        mediaCompressionHigh: "Alta",
        mediaMaxSize: "Tamanho",
        mediaWidth: "Largura",
        mediaFPS: "FPS",
        mediaKeepAudio: "Manter áudio",
        mediaCodec: "Codec",
        mediaFormat: "Formato",
        mediaStripMetadata: "Remover metadados",
        mediaLoopGIF: "Repetir GIF",
        mediaOCRMode: "OCR",
        mediaOCRAccurate: "Preciso",
        mediaOCRFast: "Rápido",
        mediaLanguageCorrection: "Correção de idioma",
        mediaTextOutputNote: "O texto extraído pode ser copiado e salvo em TXT.",
        mediaRunning: "Processando",
        mediaCompleted: "Concluído",
        mediaCancelled: "Cancelado.",
        mediaOpenInFinder: "Mostrar",
        mediaCopyText: "Copiar texto",
        mediaRunAgain: "Rodar de novo",
        mediaEmptyText: "Nenhum texto encontrado.",
        mediaResultSavedFormat: "Salvo como %@",
        mediaResultSizeFormat: "%@ para %@",
        mediaResultGrewCaption: "O arquivo convertido ficou maior que o original.",
        mediaErrorNoFile: "Escolha um arquivo primeiro.",
        mediaErrorNoVideo: "Este arquivo não tem trilha de vídeo.",
        mediaErrorSameOutput: "Escolha um destino diferente do arquivo original.",
        mediaErrorUnsupported: "Formato não suportado pelo macOS.",

        shelfName: "Área temporária",
        shelfEnable: "Área temporária para arrastar arquivos",
        shelfEnableCaption: "Um espaço flutuante para juntar arquivos, imagens e textos e arrastá-los depois para qualquer app.",
        shelfHowTitle: "Como usar",
        shelfStep1: "Abra a área com o atalho ou sacudindo o mouse durante um arraste.",
        shelfStep2: "Solte arquivos, imagens, links ou texto sobre ela para guardá-los.",
        shelfStep3: "Arraste cada item de volta para qualquer app quando precisar.",
        shelfShakeToggle: "Abrir sacudindo o mouse durante o arraste",
        shelfShakeCaption: "Sacuda o ponteiro rapidamente segurando um item para chamar a área perto do cursor.",
        shelfDropZoneToggle: "Guardar arquivos na barra de menus ao arrastar",
        shelfDropZoneCaption: "Ao arrastar um arquivo, a área aparece embaixo do ícone na barra de menus. O que você soltar fica guardado ali, num botão que você encolhe e abre com um clique e que some quando a área fica vazia.",
        shelfDropZoneLabel: "Solte aqui",
        shelfCollapse: "Encolher",
        shelfBehaviorTitle: "Depois de usar",
        shelfCloseAfterDrop: "Fechar depois de soltar em outro app",
        shelfCloseAfterDropCaption: "Fecha a área quando o destino aceita os itens. O alfinete no painel a mantém aberta.",
        shelfRemoveAfterDrop: "Remover itens depois de soltar",
        shelfRemoveAfterDropCaption: "Itens aceitos por outro app saem da área. Desative para manter uma cópia nela.",
        shelfExclusionsTitle: "Exceções automáticas",
        shelfExclusionsEmpty: "Nenhum app adicionado.",
        shelfExclusionsCaption: "Sacudir e a área da barra de menus não abrem durante arrastes iniciados nesses apps. O atalho e Abrir agora continuam funcionando.",
        shelfPin: "Manter aberta",
        shelfUnpin: "Deixar fechar após o uso",
        extraBrightnessName: "Brilho extra",
        extraBrightnessCaption: "Usa a reserva HDR da tela para passar do brilho máximo. Consome mais bateria e o Mac pode esquentar.",
        extraBrightnessLevelLabel: "Intensidade",
        extraBrightnessUnsupported: "Disponível apenas em telas XDR, como as dos MacBook Pro de 14 e 16 polegadas.",
        shelfHotkeyLabel: "Atalho",
        shelfOpenNow: "Abrir agora",
        shelfNoPermission: "Não requer nenhuma permissão.",
        shelfMenuItem: "Abrir área temporária",
        shelfTitle: "Área temporária",
        shelfEmpty: "Arraste itens aqui",
        shelfClearAll: "Limpar tudo",
        shelfRemoveSelected: "Remover selecionados",
        shelfSelectedFormat: "%d selecionados",
        shelfHint: "Clique para selecionar. Arraste para usar ou clique com o botão direito para mais ações.",
        shelfItemImage: "Imagem",
        shelfActionOpen: "Abrir",
        shelfActionOpenWith: "Abrir com",
        shelfActionAirDrop: "Compartilhar por AirDrop",

        breakdownMeasuring: "Medindo…",

        mixerSection: "Mixer de volume",
        mixerEmpty: "Apps que usam áudio aparecem aqui",
        mixerUnavailable: "Disponível a partir do macOS 14.4",
        mixerPermissionBody: "Para ajustar o volume por app, permita “Gravação de Tela e Áudio do Sistema” nos Ajustes do Sistema. O áudio nunca é gravado.",
        mixerResetTooltip: "Voltar para 100%",
        mixerOutputDefault: "Padrão",
        mixerOutputCurrent: "atual",
        mixerOutputUnavailable: "Saída indisponível",
        mixerOutputFallback: "Usando o padrão até esse dispositivo voltar.",
        mixerBypassedCaption: "Este app controla o próprio áudio.",
        mixerOutputTooltip: "Escolher saída",
        mixerSystemOutputTitle: "Saída",
        mixerSystemOutputNoDevices: "Nenhuma saída encontrada",
        mixerSystemOutputTooltip: "Escolher saída do sistema",
        mixerSystemOutputErrorFormat: "Não foi possível trocar: %@",
        mixerLowerOnHeadphonesDisconnect: "Baixar volume ao desconectar fones",
        mixerLowerOnHeadphonesDisconnectCaption: "Ajusta a saída quando fones com fio ou Bluetooth desconectam.",
        mixerHeadphonesDisconnectVolume: "Volume ao desconectar",
        soundOutputSwitcherTitle: "Alternador de saída",
        soundOutputSwitcherEnable: "Alternar saídas por atalho",
        soundOutputSwitcherCaption: "Escolha as saídas e use o atalho para passar para a próxima disponível.",
        soundOutputSwitcherDevices: "Saídas no ciclo",
        soundOutputSwitcherNoAvailableSelection: "Selecione pelo menos uma saída disponível.",
        mixerInputTitle: "Microfone",
        mixerInputNoDevices: "Nenhum microfone encontrado",
        mixerInputUnavailable: "Microfone indisponível",
        mixerInputFallback: "Usando o padrão até esse microfone voltar.",
        mixerInputTooltip: "Escolher microfone",
        mixerInputErrorFormat: "Não foi possível trocar: %@",
        mixerVisibleApps: "Apps na lista",
        mixerAllShown: "Todos",
        mixerHiddenCountLabel: "Escondidos",
        mixerHideFromList: "Esconder da lista",

        updatesSection: "Atualizações",
        autoCheckToggle: "Procurar atualizações automaticamente",
        checkNowButton: "Procurar agora",
        updateChecking: "Procurando…",
        updateUpToDate: "Você está na versão mais recente.",
        updateAvailablePrefix: "Atualização disponível:",
        updateInstallButton: "Baixar e instalar",
        updateDownloading: "Baixando atualização…",
        updateInstalling: "Instalando e reiniciando…",
        updateFailedPrefix: "Não foi possível verificar:",
        updateLastChecked: "Última verificação:",
        updateNotifyTitle: "Atualização do Vorssaint",
        updateInstallFailedBody: "A atualização foi baixada, mas não pôde ser aplicada. Baixe a versão mais recente na página de releases do GitHub e arraste o app por cima do atual.",
        updateNeedsApplicationsTitle: "Mova o Vorssaint para Aplicativos",
        updateNeedsApplicationsBody: "O app está rodando de um lugar que não dá para atualizar, como a imagem de disco ou uma área temporária do sistema. Arraste o Vorssaint para a pasta Aplicativos, abra de lá e tente de novo.",
        menuCheckUpdates: "Procurar atualizações…",

        permissionRequired: "Permissão necessária",
        permissionAccessibility: "Acessibilidade",
        permissionScreenRecording: "Gravação de Tela",
        permissionGranted: "Concedida",
        permissionMissing: "Não concedida",
        permissionOpenSettings: "Abrir Ajustes do Sistema…",
        permissionRequest: "Conceder acesso",
        permissionRestartNote: "O macOS pode pedir para reabrir o app depois de conceder.",

        aboutDescription: "Central de utilidades para o seu Mac.\nEnergia, monitor do sistema, rolagem e alternador de janelas, direto na barra de menus.",
        versionPrefix: "Versão",
        reviewIntro: "Rever introdução",
        viewOnGitHub: "Ver no GitHub",

        obContinue: "Continuar",
        obBack: "Voltar",
        obSkipStep: "Pular esta etapa",
        obStart: "Abrir o Vorssaint",
        obStepWelcomeTitle: "Bem-vindo ao Vorssaint",
        obStepWelcomeBody: "Um utilitário discreto na barra de menus que deixa o macOS mais prático no dia a dia.",
        obWelcomeBullet1Title: "Energia sob controle",
        obWelcomeBullet1Body: "Mantenha o Mac acordado por quanto tempo quiser, até com a tampa fechada.",
        obWelcomeBullet2Title: "Visão clara do sistema",
        obWelcomeBullet2Body: "Temperaturas, uso de CPU e GPU e pressão de memória em tempo real.",
        obWelcomeBullet3Title: "Mouse e janelas do seu jeito",
        obWelcomeBullet3Body: "Rolagem invertida no mouse e um alternador de janelas com miniaturas.",
        obLanguageLabel: "Idioma",
        obStepAccessibilityTitle: "Acessibilidade",
        obStepAccessibilityBody: "Necessária para inverter a rolagem do mouse e para o alternador de janelas responder ao teclado.",
        obAccessibilityWhy: "O app só observa a roda do mouse e o atalho do alternador. Nada é gravado nem enviado a lugar algum.",
        obStepRecordingTitle: "Gravação de Tela",
        obStepRecordingBody: "Permite mostrar miniaturas reais das janelas no alternador, em vez de apenas ícones.",
        obRecordingWhy: "As miniaturas são geradas na hora, ficam só na memória e nunca saem do seu Mac. Sem ela, o alternador funciona com ícones.",
        obStepMonitorTitle: "Monitor do sistema",
        obStepMonitorBody: "O painel mostra as temperaturas de CPU, GPU e bateria, o uso de hardware e a pressão de memória.",
        obMonitorNoPermission: "Não precisa de permissão. Os sensores são lidos direto do sistema.",
        obStepOptionalTitle: "Recursos opcionais",
        obStepOptionalBody: "Ative agora o que quiser usar. Tudo pode ser mudado depois nos Ajustes.",
        obStepStatusTitle: "Verificação",
        obStepStatusBody: "Confira se está tudo pronto para os recursos que você quer usar.",
        obStatusRecheck: "Verificar novamente",
        obStepDoneTitle: "Tudo pronto!",
        obStepDoneBody: "O Vorssaint já está cuidando do seu Mac.",
        obDoneHint: "Procure o buraco negro na barra de menus, no canto superior direito da tela.",
        obWhatsNewTitle: "Novidades nesta versão",
        obWhatsNewFallback: "Esta atualização inclui as correções e melhorias mais recentes.",
        obLanguageUpdateTitle: "Agora no seu idioma",
        obLanguageUpdateBody: "O Vorssaint agora fala vários idiomas. Escolha o que você prefere usar; dá para mudar quando quiser nos Ajustes.",
        obPurposeTitle: "O que te trouxe aqui?",
        obPurposeBody: "Escolha uma opção e o app se monta sozinho. O resto continua a um clique nos Ajustes.",
        obPurposeSkip: "Deixar tudo à mão",

        tabMonitor: "Monitor",
        monitorMenuBarSection: "Na barra de menus",
        monitorMenuBarCaption: "Escolha o que aparece ao lado do ícone na barra de menus.",
        monitorCombineTemperatures: "Combinar uso e temperatura",
        monitorCombineTemperaturesCaption: "Quando uso e temperatura do mesmo item estiverem ativos, mostra tudo em um bloco só.",
        monitorSeparateMenuBarMetrics: "Separar métricas em itens próprios",
        monitorSeparateMenuBarMetricsCaption: "Separa os blocos ativos na barra de menus e mantém uso e temperatura juntos quando combinar estiver ativo.",
        monitorNetworkUploadFirst: "Upload acima do download",
        monitorShowCPU: "CPU",
        monitorShowMemory: "Memória",
        monitorShowNetwork: "Rede",
        monitorShowPowerLabel: "Energia",
        monitorIntervalLabel: "Atualizar a cada",
        monitorInterval1: "1 segundo",
        monitorInterval2: "2 segundos",
        monitorInterval5: "5 segundos",
        monitorPanelSection: "No painel",
        panelNavigationMode: "Navegar por seções no painel",
        panelNavigationCaption: "Mostra uma seção por vez. Escolha Lista para ver tudo em uma rolagem contínua.",
        panelFooterSections: "Seções",
        panelFooterList: "Lista",
        fanControlBetaShow: "Mostrar Fan Control (Beta) no painel",
        fanControlBetaSection: "Fan Control",
        fanControlBetaTitle: "Fan Control",
        fanControlBetaStatus: "Automático",
        fanControlBetaCaption: "Beta. O controle manual fica desativado até validação por modelo de Mac.",
        fanControlModeAutomatic: "Automático",
        fanControlModeManual: "Manual",
        betaBadge: "BETA",
        betaFeatureWarning: "Beta. Você pode encontrar alguns bugs.",

        networkSection: "Rede",
        networkDownload: "Download",
        networkUpload: "Upload",
        networkThisSession: "Nesta sessão",
        networkMeasuring: "Medindo…",
        networkApps: "Apps usando rede",
        networkAppsIdle: "Nenhum app usando rede agora",

        diskSection: "Discos",
        diskUsed: "usado",
        diskFree: "livre",
        diskInternal: "Interno",
        diskExternal: "Externo",
        diskSelect: "Selecionar disco",
        diskRead: "Leitura",
        diskWrite: "Escrita",
        diskSMARTStatus: "Status",
        diskSMARTUnavailable: "SMART indisponível para este disco",
        diskTotalRead: "Total lido",
        diskTotalWritten: "Total escrito",
        diskTemperature: "Temperatura",
        diskHealth: "Saúde",
        diskPowerCycles: "Ciclos",
        diskPowerOnHours: "Horas ligado",
        diskUnsafeShutdowns: "Desligamentos inseguros",
        diskMediaErrors: "Erros de mídia",
        diskEject: "Ejetar",
        diskEjectAll: "Ejetar todos",
        diskEjecting: "Ejetando…",
        diskReadyToRemove: "Pronto para remover",
        diskEjectFailed: "Não foi possível ejetar",
        diskProtectionCaption: "Ejete antes de desconectar.",
        diskNoExternal: "Nenhum disco externo pronto para ejeção.",
        diskOpenInFinder: "Abrir",
        diskStorageSettings: "Armazenamento",
        diskNoDisks: "Nenhum disco montado encontrado.",

        powerSection: "Energia",
        powerSystem: "Sistema",
        powerAdapter: "Adaptador",
        powerBattery: "Bateria",
        powerCharging: "Carregando",
        powerOnBattery: "Na bateria",
        powerPluggedIn: "Na tomada",
        powerUnavailable: "Métricas de energia indisponíveis neste Mac",
        powerAdapterMaxFormat: "%@ máx.",
        monitorShowGPU: "GPU",
        monitorShowCPUTemperature: "Temperatura da CPU",
        monitorShowGPUTemperature: "Temperatura da GPU",
        monitorShowBatteryTemperature: "Temperatura da bateria",
        monitorShowPeripheralBattery: "Bateria dos periféricos",
        peripheralBatteryNoDevices: "Nenhum periférico encontrado",
        monitorGraphsSection: "Gráficos",
        monitorGraphsCaption: "Escolha quais métricas mostram um gráfico ao longo do tempo.",

        updateBannerTitle: "Atualização disponível",
        updateBannerAction: "Atualizar",
        obStepMenuBarTitle: "Métricas na barra de menus",
        obStepMenuBarBody: "Escolha o que mostrar ao lado do ícone. A prévia acima muda em tempo real.",
        obStepMenuBarNote: "Novidade: blocos de Rede e Energia e gráficos no painel. Ajuste tudo depois em Ajustes › Monitor.",
        monitorMenuBarPresetLabel: "Estilo",
        menuBarPresetReadable: "Legível",
        menuBarPresetDense: "Denso",
        menuBarSpacingLabel: "Espaçamento na barra",
        menuBarSpacingStandard: "Padrão",
        menuBarSpacingCompact: "Compacto",
        menuBarHideIconToggle: "Ocultar o ícone do app enquanto houver métricas",
        menuBarHideIconCaption: "O ícone volta sozinho quando as métricas saem da barra e quando há algo a avisar (atualização pronta ou microfone silenciado).",
        monitorLabelStyleLabel: "Rótulos",
        menuBarLabelStyleCompact: "Compactos",
        menuBarLabelStyleClassic: "Clássicos",
        monitorMemoryStyleLabel: "Mostrar memória como",
        monitorMemoryPressureDot: "Ponto de pressão",
        memoryStyleDot: "Ponto",
        memoryStylePercent: "%",
        memoryStyleBoth: "Ambos",

        systemUptime: "Ativo há",
        batteryCharge: "Carga",
        powerHealth: "Saúde da bateria",
        powerCycles: "Ciclos",
        speedTestRun: "Testar velocidade",
        speedTestAgain: "Testar de novo",
        speedTestLatency: "Latência",
        speedTestTesting: "Testando…",
        speedTestFailed: "Falha no teste",

        monitorShowInPanel: "Mostrar no painel",
        panelHideItem: "Ocultar do painel",
        panelShowItem: "Mostrar no painel",
        panelHiddenItem: "Oculto",
        monitorItemUptime: "Tempo ativo",
        monitorItemNetSpeed: "Velocidade ao vivo",
        monitorItemNetTotals: "Totais da sessão",
        monitorItemNetTest: "Teste de velocidade",
        monitorItemDiskUsage: "Uso do disco",
        monitorItemDiskActivity: "Atividade ao vivo",
        monitorItemDiskSMART: "SMART",
        monitorItemDiskProtection: "Proteção externa",
        monitorItemDiskTools: "Ferramentas",
        monitorPanelConfigHint: "Abra um bloco para escolher o que ele mostra.",
        monitorOrderSection: "Ordem das seções",
        monitorOrderHint: "Arraste para reordenar as seções do painel e use o olho para mostrar ou ocultar cada uma.",
        obStepPanelTitle: "O que aparece no painel",
        obStepPanelBody: "Abra cada bloco e escolha exatamente o que mostrar quando você clica no ícone.",
        obStepPanelNavigationTitle: "Painel por seções",
        obStepPanelNavigationBody: "O painel agora pode mostrar uma seção por vez. Você pode mudar entre Seções e Lista nos Ajustes.",

        cleaningMenuItem: "Modo de limpeza",
        utilitiesSection: "Utilidades",
        quickControlsSection: "Controles",
        panelCategoryWindows: "Janelas",
        panelCategoryInput: "Mouse e teclado",
        panelCategoryFiles: "Arquivos",
        windowMaximizeName: "Maximizar janelas",
        windowMaximizeCaption: "O botão verde maximiza sem criar outro Espaço.",
        windowMaximizeActiveNow: "Ativo no botão verde",
        windowMaximizeNeedsAccessibility: "Precisa de Acessibilidade para funcionar.",
        keyDebounceName: "Debounce",
        keyDebounceEnable: "Filtrar teclas duplicadas",
        keyDebounceCaption: "Filtra toques duplicados muito rápidos.",
        keyDebounceActiveNow: "Filtro ativo",
        keyDebounceGlobalWindow: "Janela global",
        keyDebouncePerKeySection: "Teclas específicas",
        keyDebouncePerKeyCaption: "Valores por tecla substituem a janela global. Use 0 ms para não filtrar uma tecla.",
        keyDebounceKeyLabel: "Tecla",
        keyDebounceWindowLabel: "Janela",
        keyDebounceAddKey: "Adicionar tecla",
        keyDebounceNoOverrides: "Nenhuma tecla específica configurada.",
        keyDebounceRemoveKey: "Remover tecla",
        cleaningPanelCaption: "Bloqueia o teclado para limpar com segurança.",
        cleaningOverlayTitle: "Teclado bloqueado para limpeza",
        cleaningOverlaySubtitle: "Pressione a mesma tecla 5 vezes para desbloquear",
        cleaningOverlayUnlock: "Desbloquear",
        cleaningOverlayMouseHint: "O mouse e o trackpad continuam funcionando",
        cleaningNeedsAxTitle: "Precisa de Acessibilidade",
        cleaningNeedsAxBody: "Para bloquear o teclado com segurança, o Vorssaint precisa da permissão de Acessibilidade. Conceda em Ajustes do Sistema e tente de novo.",

        tabSupport: "Apoiar",
        shortcutsPageCaption: "Todos os atalhos globais ativos no app agora. Cada um é configurado na página do próprio recurso.",
        shortcutsPageTitle: "Atalhos de teclado",
        settingsSearchPlaceholder: "Buscar ajustes",
        donateHeading: "Apoie o Vorssaint",
        donateMessage: "Todos os meus projetos públicos são, e sempre serão, totalmente gratuitos: sem assinatura, sem anúncios. O apoio da comunidade é a única forma de manter tudo vivo. Se o Vorssaint te ajuda, um café faz diferença de verdade.",
        donateButton: "Buy me a coffee",
        donateThanks: "Obrigado por estar aqui. 🖤",
        supportIntroTitle: "O Vorssaint é 100% gratuito e sempre será",
        supportIntroMessage: "Eu sigo cuidando do app no meu tempo livre. Se ele te ajuda, você pode me ajudar de um jeito simples, divulgando, deixando uma estrela no GitHub ou pagando um café. Isso me ajuda muito a continuar trazendo melhorias.",
        supportIntroStarButton: "Dar uma estrela",
        supportIntroCoffeeButton: "Buy me a coffee",
        supportIntroLaterButton: "Agora não",
        supportIntroDoneButton: "Concluir",
        communityIntroTitle: "Vem ver antes de todo mundo",
        communityIntroMessage: "Quem já me seguia no X viu várias novidades desta atualização antes de todo mundo. Lá eu posto prévias do que vem depois e mostro como funciona, para você já saber o básico antes mesmo da atualização sair. Segue lá e veja o que vem depois!",
        communityIntroFollowButton: "Seguir @vorssaint no X",
        homebrewOfficialIntroTitle: "Agora no catálogo oficial do Homebrew",
        homebrewOfficialIntroMessage: "O Vorssaint agora pode ser instalado direto do catálogo oficial do Homebrew.",
        homebrewOfficialIntroInstallLabel: "Nova instalação",
        homebrewOfficialIntroMigrationTitle: "Usava o tap antigo?",
        homebrewOfficialIntroMigrationMessage: "Remova o tap uma vez. O app e seus ajustes continuam no lugar.",
        homebrewOfficialIntroCopyButton: "Copiar comando",
        updateShowcaseTitle: "Novidades da 3.1.4",
        updateShowcaseMessage: "Veja uma prévia rápida das principais melhorias desta atualização.",
        updateShowcaseUnavailable: "Não foi possível carregar o vídeo agora. Você ainda pode continuar.",
        updateShowcaseRestart: "Voltar ao início",
        showMenuBarIcon: "Mostrar ícone na barra de menus",
        showMenuBarIconCaption: "Se o ícone do Vorssaint sumir (o macOS pode esconder ícones quando a barra de menus fica sem espaço, comum em Macs com notch), reabra o Vorssaint pela pasta Aplicativos ou pelo Spotlight: isso recria o ícone e, se ele ainda estiver escondido, abre esta janela. O botão acima faz o mesmo quando você já consegue chegar aqui. Manter menos ícones na barra, ou menos métricas no Vorssaint, reduz bastante a chance.",
        menuBarIconStillHiddenTitle: "O ícone continua escondido",
        menuBarIconStillHiddenBody: "O ícone foi recriado, mas o macOS não deu um lugar visível a ele. A barra de menus provavelmente está sem espaço: remova alguns ícones da barra (ou feche apps com menus longos) e tente de novo.",
        menuBarIconManagerHintFormat: "O %@ está aberto e pode estar guardando o ícone na seção oculta dele. Procure o Vorssaint lá, ou configure o %@ para sempre mostrar o Vorssaint.",
        shortcutRecording: "Pressione o novo atalho",
        shortcutReset: "Redefinir",
        shortcutNone: "Nenhum",
        shortcutClear: "Remover atalho",
        shortcutInvalid: "Use pelo menos Control, Option ou Command junto com uma tecla.",
        shortcutPressKeys: "Pressione",
        shortcutEscapeHint: "Esc cancela.",
        shortcutDeleteHint: "Delete remove.",
        shortcutNotCaptured: "Nada foi capturado. O macOS ou outro app já usa essa combinação. Tente outra.",
        shortcutConflictFormat: "Este atalho já está em uso por %@.",
        shortcutUnavailable: "O macOS recusou este atalho. Escolha outro.",
        shelfShortcutToggle: "Atalho da área temporária",
        switcherUsageHintFormat: "Segure %@ para navegar; solte para ativar a janela. Shift ou ← volta; Q fecha o app selecionado; Esc cancela.",
        musicBlockSection: "Teclas de mídia",
        musicBlockTitle: "Impedir que o Música abra sozinho",
        musicBlockCaption: "O app Música deixa de abrir ao tocar nas teclas de mídia. Desative para voltar a usar o Música.",
        musicBlockReplacementLabel: "Abrir no lugar",
        musicBlockReplacementNone: "Nenhum",
        musicBlockChooseApp: "Escolher app…",
        cleanerName: "Limpeza",
        cleanerIntroTitle: "Limpe o lixo do Mac",
        cleanerIntroCaption: "Procura restos de apps desinstalados, caches, registros e a Lixeira. Você revisa tudo antes e os itens removidos vão para a Lixeira.",
        cleanerScan: "Verificar",
        cleanerScanning: "Verificando…",
        cleanerCleaning: "Limpando…",
        cleanerCatLeftovers: "Restos de apps desinstalados",
        cleanerCatLoginItems: "Itens de início órfãos",
        cleanerCatCaches: "Caches",
        cleanerCatLogs: "Registros",
        cleanerCatDeveloper: "Lixo de desenvolvimento",
        cleanerCatTrash: "Lixeira",
        cleanerLeftoversNote: "Encontrados por análise e começam desmarcados. Confira o caminho antes de marcar.",
        cleanerLoginItemsNote: "A entrada em Itens de Início some depois de reiniciar o Mac.",
        cleanerTrashNote: "Esvaziar a Lixeira é permanente.",
        cleanerCatDeviceBackups: "Backups de iPhone",
        cleanerDeviceBackupsCaption: "Backups antigos de iPhone e iPad ocupam boa parte do que o macOS chama de Outros. Remova só os que você não precisa mais; um novo backup é feito quando o aparelho for conectado de novo.",
        cleanerNothingFound: "Nada para limpar. Seu Mac está em ordem.",
        cleanerClean: "Limpar",
        cleanerDoneNote: "Os itens foram para a Lixeira e podem ser recuperados de lá.",
        cleanerAgain: "Verificar de novo",
        cleanerRevealInFinder: "Mostrar no Finder",
        cleanerPanelCaption: "Restos de apps, caches e logs",
        cleanerSafeSection: "Limpeza segura",
        cleanerOptionalSection: "Opcional, revise antes",
        cleanerCatOtherCaches: "Outros caches",
        cleanerCachesCaption: "Arquivos temporários que os apps refazem sozinhos.",
        cleanerLogsCaption: "Registros antigos de diagnóstico.",
        cleanerDeveloperCaption: "Restos de compilações e simuladores do Xcode.",
        cleanerLoginItemsCaption: "Entradas de início deixadas por apps que não existem mais.",
        cleanerLeftoversCaption: "Arquivos deixados por apps que você desinstalou.",
        cleanerOtherCachesCaption: "Seguro apagar, nada quebra. Apps podem abrir mais devagar na primeira vez e conteúdo baixado, como músicas offline, baixa de novo.",
        cleanerCleanSizeFormat: "Limpar %@",
        cleanerScheduleTitle: "Limpeza automática",
        cleanerScheduleOff: "Desativada",
        cleanerScheduleDaily: "Diária",
        cleanerScheduleWeekly: "Semanal",
        cleanerScheduleCaption: "Limpa sozinha só a parte segura no horário escolhido e manda tudo para a Lixeira.",
        cleanerScheduleLastFormat: "A última limpeza automática liberou %@.",
        cleanerAutoNotificationFormat: "%@ liberados e enviados para a Lixeira.",
        cleanerScheduleNextFormat: "Próxima limpeza %@.",
        cleanerScheduleRanFormat: "Última limpeza automática %@.",
        cleanerScheduleNotifyToggle: "Avisar quando terminar",
        cleanerNotifDenied: "As notificações do Vorssaint estão desativadas no sistema.",
        cleanerNotifOpenSettings: "Abrir Ajustes de Notificações…",
        launchAtLoginNeedsApplications: "O app está rodando de um lugar que não permite abrir no login. Arraste o Vorssaint para a pasta Aplicativos, abra de lá e ligue de novo.",
        ocrQRToggle: "Ler QR codes",
        ocrQRCaption: "Se a área tiver um QR code, o conteúdo dele aparece para copiar ou abrir.",
        ocrQRCopied: "QR code copiado",
        qrResultTitle: "QR code",
        qrResultCopy: "Copiar",
        qrResultOpen: "Abrir link",
        highlightsTitle: "Novidades desta versão",
        highlightsCaptionDockPreview: "O Dock Preview agora funciona com a ampliação do Dock ligada",
        highlightsCaptionScreenshot: "A captura de tela ganhou uma lupa de pixels e leitura de QR codes",
        highlightsCaptionSnippetLibrary: "Um menu de snippets com busca digita qualquer snippet direto no cursor",
        highlightsConfigure: "Configurar",
        highlightsTry: "Experimentar",
        highlightsSeeAll: "Ver todas as mudanças",
        switcherCurrentSpaceOnly: "Mostrar só a Mesa atual",
        switcherCurrentSpaceOnlyCaption: "Mostra no alternador apenas as janelas da Mesa em que você está. Escolher uma janela nunca leva você para outra Mesa.",
        shelfFileMissing: "The file no longer exists"
    )
}

// MARK: - English (US)

extension Strings {
    static let enUS = Strings(
        statusIdleTooltip: "Vorssaint: normal sleep",
        statusActiveUntil: "Vorssaint: awake until",
        statusActiveIndefinite: "Vorssaint: awake indefinitely",
        menuEnableAwake: "Enable keep awake",
        menuDisableAwake: "Disable keep awake",
        menuActivateFor: "Activate for…",
        menuSettings: "Settings…",
        menuAbout: "About Vorssaint",
        menuQuit: "Quit Vorssaint",
        menuHide: "Hide Vorssaint",
        menuHideOthers: "Hide Others",
        menuShowAll: "Show All",
        menuEdit: "Edit",
        menuUndo: "Undo",
        menuRedo: "Redo",
        menuCut: "Cut",
        menuCopy: "Copy",
        menuPaste: "Paste",
        menuSelectAll: "Select All",
        menuWindow: "Window",
        menuMinimize: "Minimize",
        menuZoom: "Zoom",
        menuClose: "Close",

        minutes15: "15 minutes",
        minutes30: "30 minutes",
        hour1: "1 hour",
        hours2: "2 hours",
        hours4: "4 hours",
        hours8: "8 hours",
        indefinitely: "Indefinitely",
        indefinite: "Indefinite",

        panelSettings: "Settings",
        panelQuit: "Quit",
        panelHotkeyHint: "Shortcut toggles",

        keepAwakeTitle: "Keep awake",
        keepAwakeEndsIn: "Ends in",
        keepAwakeUntilDisabled: "Active until you turn it off",
        keepAwakeNormalRules: "The Mac follows its normal energy rules",
        keepAwakeOptions: "Options",
        keepAwakeMouseJiggle: "Move pointer slightly",
        keepAwakeMouseJiggleCaption: "During a session, moves the pointer a little at the chosen interval.",
        keepAwakeMouseJiggleInterval: "Interval",
        keepAwakeActiveIconLabel: "Active icon",
        keepAwakeActiveIconVorssaint: "Vorssaint",
        keepAwakeActiveIconCoffee: "Coffee",
        keepAwakeActiveIconEye: "Eye",
        keepAwakeActiveIconMoon: "Moon",
        keepAwakeActiveIconLight: "Lightbulb",
        keepAwakeIconTintLabel: "Active icon color",
        keepAwakeIconTintOrange: "Orange",
        keepAwakeIconTintGreen: "Green",
        keepAwakeIconTintBlue: "Blue",
        keepAwakeIconTintPurple: "Purple",
        keepAwakeIconTintPink: "Pink",
        keepAwakeIconTintNone: "No color",
        durationLabel: "Duration",
        clamshellTitle: "Keep going with the lid closed",
        clamshellOnCaption: "Sleep fully disabled. Mind the power",
        clamshellNeedsSession: "Applied whenever “Keep awake” is active",
        clamshellReady: "Ready. Toggles without a password",
        clamshellNeedsPassword: "Will ask for the administrator password once",

        systemSection: "System",
        temperatures: "Temperatures",
        cpuLabel: "CPU",
        gpuLabel: "GPU",
        batteryLabel: "Battery",
        usageSection: "Hardware usage",
        memorySection: "Memory",
        memoryPressure: "Pressure",
        pressureNormal: "Normal",
        pressureWarning: "Caution",
        pressureCritical: "Critical",
        monitorUnavailable: "Sensors unavailable on this Mac",
        energyAppsTitle: "Apps using significant energy",
        energyAppsIdle: "No significant energy use",

        notifySessionEndedTitle: "Session ended",
        notifySessionEndedBody: "Time is up. The Mac will sleep normally again.",
        notifyBatteryTitle: "Vorssaint disabled",
        notifyBatteryBody: "Low battery. Normal sleep was restored to protect the charge.",
        adminPromptClamshellOn: "Vorssaint needs your password to keep the Mac going with the lid closed.",
        adminPromptClamshellOff: "Vorssaint needs your password to restore the Mac's normal sleep.",
        adminPromptRecover: "Vorssaint quit while the Mac's sleep was disabled. Enter the password to restore normal sleep.",
        adminPromptUpdate: "Vorssaint needs your password to install the update.",
        adminPromptSudoersInstall: "Vorssaint will create a restricted rule (pmset disablesleep only) to toggle closed-lid mode without asking for a password. This is the only time the password is needed.",
        adminPromptSudoersRemove: "Vorssaint will remove the password-free closed-lid rule.",

        settingsTitle: "Vorssaint Settings",
        tabGeneral: "General",
        tabEnergy: "Energy",
        tabMouse: "Mouse & Trackpad",
        tabSwitcher: "Switcher",
        tabAdvanced: "Advanced",
        tabAbout: "About",
        tabReleaseNotes: "What's New",
        releaseNotesOnUpdateToggle: "Show what's new after updating",
        whatsNewDontShowAgain: "Don't show again",
        previewSizeLabel: "Preview size",
        previewSizeNormal: "Normal",
        previewSizeLarge: "Large",
        previewSizeXLarge: "Extra large",
        settingsGroupFeatures: "Features",
        advancedResetSection: "Permissions",
        advancedResetDescription: "Removes every permission you granted Vorssaint (Accessibility, Screen Recording, Full Disk Access and others), the login item and the closed-lid rule. Useful to start fresh or before uninstalling. The app stays installed.",
        advancedClearButton: "Clear all permissions",
        advancedCleared: "Permissions cleared.",
        advancedClearConfirmTitle: "Clear all permissions?",
        advancedClearConfirmBody: "Features that need permissions will stop working until you grant them again. Your settings are kept.",
        advancedUninstallSection: "Uninstall",
        advancedUninstallDescription: "Does all of the above, then removes the preferences and moves Vorssaint to the Trash, leaving nothing behind. The app quits when done. You can reinstall anytime.",
        advancedUninstallButton: "Uninstall Vorssaint completely",
        advancedUninstallConfirmTitle: "Uninstall Vorssaint?",
        advancedUninstallConfirmBody: "Vorssaint will clear its permissions, remove its preferences and move to the Trash, then quit. This can't be undone from the app, but it stays in the Trash until you empty it.",

        launchAtLogin: "Launch at login",
        languageLabel: "Language",
        menuBarSection: "Menu bar",
        showCountdown: "Show remaining time next to the icon",
        globalHotkeySection: "Global shortcut",
        hotkeyToggle: "Enable shortcut for “Keep awake”",
        hotkeyCaption: "Works in any app, no extra permissions.",

        sessionSection: "Session",
        defaultDurationLabel: "Default duration",
        keepAwakeAutoStart: "Keep Awake when Vorssaint opens",
        keepAwakeAutoStartCaption: "Starts a session with the default duration.",
        batteryProtectionSection: "Battery protection",
        batteryDisableBelow: "Disable when battery drops below",
        batteryNever: "Never",
        batteryProtectionCaption: "Keeps a forgotten session from draining the MacBook battery.",
        clamshellSection: "Closed lid",
        configuring: "Configuring…",
        sudoersFailed: "Couldn't turn on closed-lid mode. Try again.",
        clamshellExplanation: "“Keep going with the lid closed” fully disables sleep while “Keep awake” is active and is reverted automatically when the session ends or the app quits. Prefer using it plugged in.",

        scrollSection: "Scrolling",
        invertMouseScroll: "Invert mouse scrolling",
        invertMouseScrollCaption: "Reverses the mouse wheel direction.",
        scrollTrackpadNote: "The trackpad is untouched: it keeps macOS natural scrolling.",
        scrollActiveNow: "Inverting mouse scrolling right now",
        mouseNavigationActiveNow: "Side buttons active right now",
        smoothScrollName: "Smooth scrolling",
        smoothScrollCaption: "Turns each mouse wheel step into a short, gentle glide. The trackpad is not affected.",
        smoothScrollStepLabel: "Distance per step",
        mouseNavigationSection: "Navigation",
        mouseNavigationEnable: "Use side buttons for Back and Forward",
        mouseNavigationCaption: "Turns the mouse Back and Forward buttons into navigation commands in Finder, browsers and compatible apps.",
        middleClickSection: "Middle click",
        middleClickEnable: "Three-finger click acts as middle click",
        middleClickEnableCaption: "Pressing the trackpad with three fingers works like a mouse wheel click: open links in a new tab, close tabs and everything else the middle button does.",
        middleClickDragConflict: "macOS three-finger drag is turned on and uses this same gesture. Turn it off in System Settings under Accessibility, Pointer Control, Trackpad Options, and the middle click will work.",
        middleClickTapPicker: "A light tap also clicks",
        middleClickTapOff: "Off",
        middleClickTapThreeFingers: "3 fingers",
        middleClickTapFourFingers: "4 fingers",
        middleClickTapCaption: "A light tap with that many fingers, without pressing, also fires the middle click. Sliding never counts. If the macOS three-finger tap is assigned to Look Up, turn it off so both do not fire together.",
        quickToolsTab: "Quick tools",
        quickToolShortcutToggle: "Global shortcut",
        ocrName: "Copy text from screen",
        ocrCaption: "Select an area of the screen and the recognized text is copied, ready to paste.",
        ocrCopied: "Text copied",
        ocrNoText: "No text found",
        colorPickerName: "Color picker",
        colorPickerCaption: "Grab the color of any pixel on screen and copy it in your favorite format.",
        colorPickerFormatLabel: "Copied format",
        colorPickerBareHexToggle: "Copy without the # prefix",
        colorPickerPickNow: "Pick color",
        micMuteName: "Mute microphone",
        micUnmuteName: "Unmute microphone",
        micMuteCaption: "Cuts the Mac's microphone with a click or shortcut, across every app.",
        micMutedHUD: "Microphone muted",
        micUnmutedHUD: "Microphone back on",
        micMuteMenuBarToggle: "Show in the menu bar while muted",
        micMuteMenuBarCaption: "A red crossed-out mic appears beside the app's icon in the menu bar.",
        pastePlainName: "Paste as plain text",
        pastePlainCaption: "Pastes what you copied without colors, fonts or formatting. The original stays on the clipboard.",
        launcherName: "Quick panel",
        launcherCaption: "A floating panel with your favorite tools, summoned by a shortcut from anywhere.",
        launcherOpenNow: "Open quick panel",
        launcherEditHint: "Use the tune button to choose, hide and drag the tools around.",
        launcherEmptyState: "All tools are hidden. Use the tune button to add them back.",
        launcherAddSection: "Add back",
        launcherKeysHint: "Arrows navigate, Enter opens, 1 to 9 open directly",

        switcherSection: "App switcher",
        switcherEnable: "Use the Vorssaint switcher",
        switcherEnableCaption: "Switch between apps and windows, including minimized windows and multiple windows from the same app.",
        switcherUsageHint: "Hold the shortcut to navigate; release to activate the window. Shift or ← goes back; Q quits the selected app; Esc cancels.",
        switcherNoWindows: "No open windows",
        switcherIconRowMode: "Show ⌘Tab with large icons",
        switcherIconRowModeCaption: "Shows one icon per app with that app's window previews above it.",
        switcherSimpleMode: "Simple app switcher",
        switcherSimpleModeCaption: "Shows app icons and window titles, without previews or screen capture by the switcher.",
        switcherShortcutHintApps: "Apps",
        switcherShortcutHintWindows: "Windows",
        switcherWindowShortcutCaption: "While the switcher is open, jumps between the selected app's windows.",
        switcherMergeTabs: "Show one entry per app",
        switcherMergeTabsCaption: "Collapses all of an app's windows into one entry in the switcher, instead of one entry per window.",
        switcherShowFinder: "Show Finder without windows",
        switcherShowFinderCaption: "Shows Finder in the switcher even when no Finder window is open.",
        dockPreviewName: "Dock Preview",
        dockPreviewEnable: "Preview windows from the Dock",
        dockPreviewEnableCaption: "Hover over an open app in the Dock to preview and peek at its windows.",
        dockClickMinimize: "Click the Dock icon to minimize",
        dockClickMinimizeCaption: "The active app's windows minimize when you click its Dock icon. Click again to bring them back.",
        dockClickCycleWindows: "Click the Dock icon to cycle windows",
        dockClickCycleWindowsCaption: "Click an active app's Dock icon to rotate through its windows, like ⌘`.",
        dockPreviewActiveNow: "Active in the Dock",
        dockPreviewDockUnavailable: "Could not read Dock items.",
        dockPreviewAutohideBeta: "Beta. You may run into some bugs.",
        dockPreviewOpenWindow: "Open window",
        dockPreviewCloseWindow: "Close window",
        dockPreviewMinimizeWindow: "Minimize window",
        dockPreviewRestoreWindow: "Restore window",
        dockPreviewPinPanel: "Pin preview",
        dockPreviewUnpinPanel: "Unpin preview",
        dockPreviewPinned: "Pinned",
        dockPreviewClosePanel: "Close preview",
        dockPreviewPreviousWindow: "Previous window",
        dockPreviewNextWindow: "Next window",
        dockPreviewIntroPeek: "Hover over a thumbnail to peek. Click to open the window.",
        dockPreviewIntroSettingsHint: "You can change this later in Settings › Switcher.",
        dockPreviewIntroLater: "Not now",
        dockPreviewIntroEnable: "Enable Dock Preview",

        cutPasteName: "Cut & paste",
        cutPasteEnable: "Cut & paste files in Finder",
        cutPasteEnableCaption: "Use ⌘X to cut and ⌘V to move files and folders in Finder.",
        cutPasteHowTitle: "How to use",
        cutPasteStep1: "Select items in Finder and press ⌘X to cut them.",
        cutPasteStep2: "Open the destination folder and press ⌘V to move them there.",
        cutPasteTextNote: "In text fields (like when renaming), ⌘X and ⌘V keep working as usual.",
        cutPasteActiveNow: "Ready to cut in Finder",
        cutPasteAutomationNote: "The first time, macOS asks for permission to control Finder.",
        cutReadyTitle: "Cut",
        cutReadyHint: "in the destination folder to move",
        cutCancel: "Cancel cut",
        cutDoneTitle: "Moved!",
        cutMovedSingular: "1 item moved",
        cutMovedPluralFormat: "%d items moved",
        cutSomeFailed: "Some items couldn’t be moved",
        cutMovingTitle: "Moving…",
        cutMovingCountFormat: "%d of %d",

        autoQuitName: "Quit on close",
        autoQuitEnable: "Quit an app when its last window closes",
        autoQuitEnableCaption: "Closing an app's last window also quits it.",
        autoQuitActiveNow: "Active now",
        autoQuitHowTitle: "How it works",
        autoQuitStep1: "Close an app's last window (⌘W or the red button).",
        autoQuitStep2: "The app quits on its own. “Save changes?” dialogs still appear.",
        autoQuitPredictableNote: "Apps that normally run without a window are never quit.",
        autoQuitExceptionsTitle: "Exceptions",
        autoQuitExceptionsCaption: "Apps on this list stay open even with no windows.",
        autoQuitExceptionsEmpty: "No exceptions",
        autoQuitAddApp: "Add app…",

        uninstallerName: "Uninstaller",
        uninstallerEnableCaption: "Removes an app together with the caches, preferences, logs and leftovers it leaves behind.",
        uninstallerStep1: "Drag an app onto Settings, or pick one from the list.",
        uninstallerStep2: "Review the files found and how much space they take.",
        uninstallerStep3: "Move what you want to the Trash. Nothing is deleted permanently.",
        uninstallerMenuItem: "Uninstall an app…",
        uninstallerDropTitle: "Drag an app here",
        uninstallerDropSubtitle: "or choose one to scan",
        uninstallerChoose: "Choose app…",
        uninstallerPickerTitle: "Choose app",
        uninstallerPickerSearch: "Search apps",
        uninstallerPickerEmpty: "No apps found",
        uninstallerEmptyNote: "Nothing is removed without your confirmation.",
        uninstallerFDANote: "Grant Full Disk Access for a more thorough scan.",
        uninstallerFDAGrant: "Grant access…",
        uninstallerFDAHint: "Turn Vorssaint on in the list. If it isn't there, click + and pick Vorssaint from Applications. Access only applies after you reopen the app.",
        uninstallerFDARelaunch: "Relaunch now",
        uninstallerScanning: "Scanning files…",
        uninstallerRemoving: "Moving to the Trash…",
        uninstallerFoundTitle: "found",
        uninstallerSelectedFormat: "%d of %d selected",
        uninstallerRemove: "Move to Trash",
        uninstallerCancel: "Cancel",
        uninstallerDoneTitle: "Done!",
        uninstallerFreedFormat: "%@ recovered",
        uninstallerSomeFailed: "Some items couldn't be moved to the Trash.",
        uninstallerAnother: "Uninstall another",
        uninstallerCatApp: "Application",
        uninstallerCatSupport: "Support",
        uninstallerCatCaches: "Caches",
        uninstallerCatPreferences: "Preferences",
        uninstallerCatContainers: "Containers",
        uninstallerCatLogs: "Logs",
        uninstallerCatState: "Saved state",
        uninstallerCatOther: "Other",

        urlCleanerName: "Clean URL",
        urlCleanerEnable: "Clean copied URLs",
        urlCleanerEnableCaption: "Removes tracking parameters from copied links.",
        urlCleanerActiveNow: "Active now",
        urlCleanerManualTitle: "Clean now",
        urlCleanerInputPlaceholder: "Paste a URL",
        urlCleanerOutputPlaceholder: "The clean URL appears here",
        urlCleanerCleanButton: "Clean",
        urlCleanerPasteButton: "Paste",
        urlCleanerCopyButton: "Copy",
        urlCleanerClearButton: "Clear field",
        urlCleanerNoURL: "Paste a valid URL.",
        urlCleanerNoChange: "Nothing to clean.",
        urlCleanerCleaned: "URL cleaned.",
        urlCleanerCopied: "Copied.",
        urlCleanerLocalNote: "Local. No network.",

        homebrewName: "Homebrew",
        homebrewEnableCaption: "Search, install and remove formulae and casks.",
        homebrewMissingTitle: "Homebrew not found",
        homebrewMissingBody: "Vorssaint can open Terminal with the official Homebrew installer. Terminal shows the steps and asks for your password if needed.",
        homebrewInstallHomebrew: "Install Homebrew",
        homebrewInstallHomebrewCaption: "When Terminal finishes, come back here and click Refresh.",
        homebrewInstallHomebrewOpened: "Installer opened in Terminal.",
        homebrewShellSetupTitle: "Finish Terminal setup",
        homebrewShellSetupBody: "Homebrew is installed, but Terminal may not find the brew command yet. Vorssaint can open Terminal with the setup command.",
        homebrewShellSetupButton: "Set up Terminal",
        homebrewShellSetupOpened: "Command opened in Terminal. Then come back here and click Refresh.",
        homebrewRefresh: "Refresh",
        homebrewCheckPackages: "Check packages",
        homebrewTrustTitle: "Tap not trusted yet",
        homebrewTrustCaption: "Homebrew now asks for your confirmation before using third party taps. Trust %@ to continue.",
        homebrewTrustButton: "Trust and continue",
        homebrewSearchPlaceholder: "Search packages",
        homebrewKeyboardHint: "Space or Return closes the macOS panel. Use the search button.",
        homebrewSearchButton: "Search",
        homebrewSearchResults: "Results",
        homebrewInstalled: "Installed",
        homebrewAll: "All",
        homebrewFormulas: "Formulae",
        homebrewCasks: "Casks",
        homebrewNoPackages: "No packages found",
        homebrewNoSelection: "Select an installed package or search for a new one.",
        homebrewDetailsTitle: "Package details",
        homebrewInstall: "Install",
        homebrewUninstall: "Uninstall",
        homebrewUpgrade: "Update",
        homebrewUpgradeAll: "Update all",
        homebrewUpdateHomebrew: "Update Homebrew",
        homebrewAllPackages: "packages",
        homebrewOpenTerminal: "Open Terminal",
        homebrewCancelOperation: "Cancel",
        homebrewClearLog: "Clear log",
        homebrewLogTitle: "Log",
        homebrewVersion: "Version",
        homebrewDescription: "Type",
        homebrewHomepage: "Open website",
        homebrewPopularity: "Popularity",
        homebrewPopularityFormat: "%@ installs in %@ days",
        homebrewInstalledBadge: "Installed",
        homebrewNotInstalledBadge: "Not installed",
        homebrewUpdates: "Updates",
        homebrewUpdateAvailableBadge: "Update available",
        homebrewLatestVersion: "Latest",
        homebrewConfirmInstallTitle: "Install with Homebrew?",
        homebrewConfirmInstallBodyFormat: "Homebrew will download and install %@. Dependencies may also be installed.",
        homebrewConfirmUninstallTitle: "Uninstall with Homebrew?",
        homebrewConfirmUninstallBodyFormat: "Homebrew will uninstall %@. Configuration files may remain on the system.",
        homebrewConfirmUpgradeTitle: "Update with Homebrew?",
        homebrewConfirmUpgradeBodyFormat: "Homebrew will download and apply the latest version of %@. Dependencies may also be updated.",
        homebrewConfirmUpgradeAllTitle: "Update all with Homebrew?",
        homebrewConfirmUpgradeAllBody: "Homebrew will download and apply the latest versions for packages with updates available. Dependencies may also be updated.",
        homebrewConfirmUpdateHomebrewTitle: "Update Homebrew?",
        homebrewConfirmUpdateHomebrewBody: "Homebrew will fetch the latest information and then reload your packages.",
        homebrewTerminalFallback: "This operation needs Terminal to ask for the administrator password. Vorssaint does not capture passwords.",
        homebrewLoading: "Loading…",
        homebrewSearchEmpty: "No results",
        homebrewOperationInstallFormat: "Installing %@",
        homebrewOperationUninstallFormat: "Uninstalling %@",
        homebrewOperationUpgradeFormat: "Updating %@",
        homebrewOperationUpgradeAll: "Updating packages",
        homebrewOperationUpdateHomebrew: "Updating Homebrew",
        homebrewOperationInstalledFormat: "%@ installed.",
        homebrewOperationUninstalledFormat: "%@ uninstalled.",
        homebrewOperationUpgradedFormat: "%@ updated.",
        homebrewOperationUpgradedAll: "Packages updated.",
        homebrewOperationUpdatedHomebrew: "Homebrew updated.",
        homebrewOperationFailedFormat: "Could not finish %@.",
        homebrewOperationCancelled: "Operation cancelled.",
        homebrewOperationPreparing: "Preparing...",
        homebrewOperationDownloading: "Downloading files...",
        homebrewOperationInstalling: "Installing files...",
        homebrewOperationUninstalling: "Removing files...",
        homebrewOperationUpgrading: "Updating files...",
        homebrewOperationFinalizing: "Finishing...",
        homebrewOperationRefreshing: "Refreshing list...",
        homebrewOperationTerminal: "Continue in Terminal.",
        homebrewOperationElapsedFormat: "%@ elapsed",
        homebrewOperationShowDetails: "Show details",
        homebrewOperationHideDetails: "Hide details",
        homebrewOperationTechnicalLog: "Technical details",
        homebrewOperationProgressUnknown: "Homebrew has not reported a percentage yet.",

        mediaName: "Media",
        mediaEnableCaption: "Compress videos and images, make GIFs and extract text locally.",
        mediaLocalNote: "Local. No network.",
        mediaToolVideo: "Video",
        mediaToolGIF: "GIF",
        mediaToolImage: "Image",
        mediaToolText: "Text",
        mediaSelectFile: "Choose file",
        mediaDropHint: "Drop a file here or click to choose one.",
        mediaOutput: "Output",
        mediaOutputAutomatic: "Automatic",
        mediaChooseOutput: "Destination",
        mediaStartVideo: "Compress video",
        mediaStartGIF: "Make GIF",
        mediaStartImage: "Compress image",
        mediaStartConvertPDF: "Convert to PDF",
        mediaStartText: "Extract text",
        mediaCancel: "Cancel",
        mediaStartTime: "Start",
        mediaEndTime: "End",
        mediaQuality: "Compression",
        mediaCompressionLow: "Low",
        mediaCompressionMedium: "Medium",
        mediaCompressionHigh: "High",
        mediaMaxSize: "Size",
        mediaWidth: "Width",
        mediaFPS: "FPS",
        mediaKeepAudio: "Keep audio",
        mediaCodec: "Codec",
        mediaFormat: "Format",
        mediaStripMetadata: "Remove metadata",
        mediaLoopGIF: "Loop GIF",
        mediaOCRMode: "OCR",
        mediaOCRAccurate: "Accurate",
        mediaOCRFast: "Fast",
        mediaLanguageCorrection: "Language correction",
        mediaTextOutputNote: "Extracted text can be copied and saved as TXT.",
        mediaRunning: "Processing",
        mediaCompleted: "Done",
        mediaCancelled: "Cancelled.",
        mediaOpenInFinder: "Show",
        mediaCopyText: "Copy text",
        mediaRunAgain: "Run again",
        mediaEmptyText: "No text found.",
        mediaResultSavedFormat: "Saved as %@",
        mediaResultSizeFormat: "%@ to %@",
        mediaResultGrewCaption: "The converted file came out larger than the original.",
        mediaErrorNoFile: "Choose a file first.",
        mediaErrorNoVideo: "This file has no video track.",
        mediaErrorSameOutput: "Choose a destination different from the original file.",
        mediaErrorUnsupported: "Format not supported by macOS.",

        shelfName: "Shelf",
        shelfEnable: "Temporary area for dragging files",
        shelfEnableCaption: "A floating spot to gather files, images and text, then drag them anywhere later.",
        shelfHowTitle: "How to use",
        shelfStep1: "Open it with the shortcut, or by shaking the mouse during a drag.",
        shelfStep2: "Drop files, images, links or text onto it to hold them.",
        shelfStep3: "Drag each item back out to any app when you need it.",
        shelfShakeToggle: "Open by shaking the mouse while dragging",
        shelfShakeCaption: "Shake the pointer quickly while holding an item to summon it near the cursor.",
        shelfDropZoneToggle: "Keep dragged files in the menu bar",
        shelfDropZoneCaption: "While you drag a file, the shelf appears below the menu bar icon. Whatever you drop is kept right there, in a button you shrink and open with a click that goes away once the shelf is empty.",
        shelfDropZoneLabel: "Drop here",
        shelfCollapse: "Collapse",
        shelfBehaviorTitle: "After use",
        shelfCloseAfterDrop: "Close after dropping into another app",
        shelfCloseAfterDropCaption: "Closes the shelf when the destination accepts the items. The pin in the panel keeps it open.",
        shelfRemoveAfterDrop: "Remove items after dropping",
        shelfRemoveAfterDropCaption: "Items accepted by another app leave the shelf. Turn this off to keep a copy there.",
        shelfExclusionsTitle: "Automatic exceptions",
        shelfExclusionsEmpty: "No apps added.",
        shelfExclusionsCaption: "Shake and the menu bar drop zone stay off for drags started in these apps. The shortcut and Open now still work.",
        shelfPin: "Keep open",
        shelfUnpin: "Allow closing after use",
        extraBrightnessName: "Extra brightness",
        extraBrightnessCaption: "Uses the display's HDR headroom to go past the maximum brightness. Uses more battery and the Mac can run warm.",
        extraBrightnessLevelLabel: "Intensity",
        extraBrightnessUnsupported: "Available only on XDR displays, such as the ones on the 14 and 16 inch MacBook Pro.",
        shelfHotkeyLabel: "Shortcut",
        shelfOpenNow: "Open now",
        shelfNoPermission: "Requires no permissions.",
        shelfMenuItem: "Open shelf",
        shelfTitle: "Shelf",
        shelfEmpty: "Drag items here",
        shelfClearAll: "Clear all",
        shelfRemoveSelected: "Remove selected",
        shelfSelectedFormat: "%d selected",
        shelfHint: "Click to select. Drag out to use or right-click for more actions.",
        shelfItemImage: "Image",
        shelfActionOpen: "Open",
        shelfActionOpenWith: "Open With",
        shelfActionAirDrop: "Share with AirDrop",

        breakdownMeasuring: "Measuring…",

        mixerSection: "Volume mixer",
        mixerEmpty: "Apps that use audio show up here",
        mixerUnavailable: "Available on macOS 14.4 and later",
        mixerPermissionBody: "To adjust per-app volume, allow “Screen & System Audio Recording” in System Settings. Audio is never recorded.",
        mixerResetTooltip: "Reset to 100%",
        mixerOutputDefault: "Default",
        mixerOutputCurrent: "current",
        mixerOutputUnavailable: "Output unavailable",
        mixerOutputFallback: "Using default until this device returns.",
        mixerBypassedCaption: "This app manages its own audio.",
        mixerOutputTooltip: "Choose output",
        mixerSystemOutputTitle: "Output",
        mixerSystemOutputNoDevices: "No outputs found",
        mixerSystemOutputTooltip: "Choose system output",
        mixerSystemOutputErrorFormat: "Could not switch: %@",
        mixerLowerOnHeadphonesDisconnect: "Lower volume when headphones disconnect",
        mixerLowerOnHeadphonesDisconnectCaption: "Adjusts output when wired or Bluetooth headphones disconnect.",
        mixerHeadphonesDisconnectVolume: "Volume after disconnect",
        soundOutputSwitcherTitle: "Output switcher",
        soundOutputSwitcherEnable: "Switch outputs with shortcut",
        soundOutputSwitcherCaption: "Choose outputs and use the shortcut to move to the next available one.",
        soundOutputSwitcherDevices: "Outputs in cycle",
        soundOutputSwitcherNoAvailableSelection: "Select at least one available output.",
        mixerInputTitle: "Microphone",
        mixerInputNoDevices: "No microphones found",
        mixerInputUnavailable: "Microphone unavailable",
        mixerInputFallback: "Using default until this microphone returns.",
        mixerInputTooltip: "Choose microphone",
        mixerInputErrorFormat: "Could not switch: %@",
        mixerVisibleApps: "Apps in the list",
        mixerAllShown: "All",
        mixerHiddenCountLabel: "Hidden",
        mixerHideFromList: "Hide from the list",

        updatesSection: "Updates",
        autoCheckToggle: "Check for updates automatically",
        checkNowButton: "Check now",
        updateChecking: "Checking…",
        updateUpToDate: "You're on the latest version.",
        updateAvailablePrefix: "Update available:",
        updateInstallButton: "Download and install",
        updateDownloading: "Downloading update…",
        updateInstalling: "Installing and restarting…",
        updateFailedPrefix: "Couldn't check:",
        updateLastChecked: "Last checked:",
        updateNotifyTitle: "Vorssaint update",
        updateInstallFailedBody: "The update was downloaded but could not be applied. Download the latest version from the GitHub releases page and drag the app over the current one.",
        updateNeedsApplicationsTitle: "Move Vorssaint to Applications",
        updateNeedsApplicationsBody: "The app is running from a place that cannot be updated, such as the disk image or a temporary system location. Drag Vorssaint to the Applications folder, open it from there and try again.",
        menuCheckUpdates: "Check for updates…",

        permissionRequired: "Permission required",
        permissionAccessibility: "Accessibility",
        permissionScreenRecording: "Screen Recording",
        permissionGranted: "Granted",
        permissionMissing: "Not granted",
        permissionOpenSettings: "Open System Settings…",
        permissionRequest: "Grant access",
        permissionRestartNote: "macOS may ask to reopen the app after granting.",

        aboutDescription: "A utility hub for your Mac.\nEnergy, system monitor, scrolling and a window switcher, right in the menu bar.",
        versionPrefix: "Version",
        reviewIntro: "Review introduction",
        viewOnGitHub: "View on GitHub",

        obContinue: "Continue",
        obBack: "Back",
        obSkipStep: "Skip this step",
        obStart: "Open Vorssaint",
        obStepWelcomeTitle: "Welcome to Vorssaint",
        obStepWelcomeBody: "A discreet menu bar utility that makes everyday macOS more practical.",
        obWelcomeBullet1Title: "Energy under control",
        obWelcomeBullet1Body: "Keep the Mac awake for as long as you want, even with the lid closed.",
        obWelcomeBullet2Title: "A clear view of the system",
        obWelcomeBullet2Body: "CPU, GPU and battery temperatures, hardware usage and memory pressure in real time.",
        obWelcomeBullet3Title: "Mouse and windows, your way",
        obWelcomeBullet3Body: "Reversed mouse scrolling and a window switcher with thumbnails.",
        obLanguageLabel: "Language",
        obStepAccessibilityTitle: "Accessibility",
        obStepAccessibilityBody: "Needed to invert mouse scrolling and for the window switcher to respond to the keyboard.",
        obAccessibilityWhy: "The app only watches the mouse wheel and the switcher shortcut. Nothing is recorded or sent anywhere.",
        obStepRecordingTitle: "Screen Recording",
        obStepRecordingBody: "Lets the switcher show real window thumbnails instead of icons only.",
        obRecordingWhy: "Thumbnails are generated on the fly, stay in memory and never leave your Mac. Without it, the switcher still works with icons.",
        obStepMonitorTitle: "System monitor",
        obStepMonitorBody: "The panel shows CPU, GPU and battery temperatures, hardware usage and memory pressure.",
        obMonitorNoPermission: "No permission needed. Sensors are read straight from the system.",
        obStepOptionalTitle: "Optional features",
        obStepOptionalBody: "Turn on what you want to use now. Everything can be changed later in Settings.",
        obStepStatusTitle: "Checkup",
        obStepStatusBody: "Make sure everything is ready for the features you want.",
        obStatusRecheck: "Check again",
        obStepDoneTitle: "All set!",
        obStepDoneBody: "Vorssaint is already looking after your Mac.",
        obDoneHint: "Look for the black hole in the menu bar, at the top right of the screen.",
        obWhatsNewTitle: "What's new in this version",
        obWhatsNewFallback: "This update includes the latest fixes and improvements.",
        obLanguageUpdateTitle: "Now in your language",
        obLanguageUpdateBody: "Vorssaint now speaks several languages. Choose the one you’d like to use; you can change it anytime in Settings.",
        obPurposeTitle: "What brought you here?",
        obPurposeBody: "Pick one and the app sets itself up. Everything else stays one click away in Settings.",
        obPurposeSkip: "Keep everything at hand",

        tabMonitor: "Monitor",
        monitorMenuBarSection: "In the menu bar",
        monitorMenuBarCaption: "Choose what appears next to the icon in the menu bar.",
        monitorCombineTemperatures: "Combine usage and temperature",
        monitorCombineTemperaturesCaption: "When usage and temperature for the same item are enabled, show them in one block.",
        monitorSeparateMenuBarMetrics: "Separate metrics into their own items",
        monitorSeparateMenuBarMetricsCaption: "Separates active blocks in the menu bar and keeps usage and temperature together when combine is on.",
        monitorNetworkUploadFirst: "Upload above download",
        monitorShowCPU: "CPU",
        monitorShowMemory: "Memory",
        monitorShowNetwork: "Network",
        monitorShowPowerLabel: "Power",
        monitorIntervalLabel: "Update every",
        monitorInterval1: "1 second",
        monitorInterval2: "2 seconds",
        monitorInterval5: "5 seconds",
        monitorPanelSection: "In the panel",
        panelNavigationMode: "Navigate panel by sections",
        panelNavigationCaption: "Shows one section at a time. Choose List to see everything in one continuous scroll.",
        panelFooterSections: "Sections",
        panelFooterList: "List",
        fanControlBetaShow: "Show Fan Control (Beta) in the panel",
        fanControlBetaSection: "Fan Control",
        fanControlBetaTitle: "Fan Control",
        fanControlBetaStatus: "Automatic",
        fanControlBetaCaption: "Beta. Manual control stays disabled until each Mac model is validated.",
        fanControlModeAutomatic: "Automatic",
        fanControlModeManual: "Manual",
        betaBadge: "BETA",
        betaFeatureWarning: "Beta. You may run into some bugs.",

        networkSection: "Network",
        networkDownload: "Download",
        networkUpload: "Upload",
        networkThisSession: "This session",
        networkMeasuring: "Measuring…",
        networkApps: "Apps using network",
        networkAppsIdle: "No apps using network now",

        diskSection: "Disks",
        diskUsed: "used",
        diskFree: "free",
        diskInternal: "Internal",
        diskExternal: "External",
        diskSelect: "Select disk",
        diskRead: "Read",
        diskWrite: "Write",
        diskSMARTStatus: "Status",
        diskSMARTUnavailable: "SMART unavailable for this disk",
        diskTotalRead: "Total read",
        diskTotalWritten: "Total written",
        diskTemperature: "Temperature",
        diskHealth: "Health",
        diskPowerCycles: "Power cycles",
        diskPowerOnHours: "Power on hours",
        diskUnsafeShutdowns: "Unsafe shutdowns",
        diskMediaErrors: "Media errors",
        diskEject: "Eject",
        diskEjectAll: "Eject all",
        diskEjecting: "Ejecting…",
        diskReadyToRemove: "Ready to remove",
        diskEjectFailed: "Could not eject",
        diskProtectionCaption: "Eject before unplugging.",
        diskNoExternal: "No external disk ready to eject.",
        diskOpenInFinder: "Open",
        diskStorageSettings: "Storage",
        diskNoDisks: "No mounted disks found.",

        powerSection: "Power",
        powerSystem: "System",
        powerAdapter: "Adapter",
        powerBattery: "Battery",
        powerCharging: "Charging",
        powerOnBattery: "On battery",
        powerPluggedIn: "Plugged in",
        powerUnavailable: "Power metrics unavailable on this Mac",
        powerAdapterMaxFormat: "%@ max",
        monitorShowGPU: "GPU",
        monitorShowCPUTemperature: "CPU temperature",
        monitorShowGPUTemperature: "GPU temperature",
        monitorShowBatteryTemperature: "Battery temperature",
        monitorShowPeripheralBattery: "Peripheral battery",
        peripheralBatteryNoDevices: "No devices found",
        monitorGraphsSection: "Graphs",
        monitorGraphsCaption: "Choose which metrics show a graph over time.",

        updateBannerTitle: "Update available",
        updateBannerAction: "Update",
        obStepMenuBarTitle: "Metrics in the menu bar",
        obStepMenuBarBody: "Pick what to show next to the icon. The preview above updates live.",
        obStepMenuBarNote: "New: Network and Power blocks and graphs in the panel. Fine-tune it all later in Settings › Monitor.",
        monitorMenuBarPresetLabel: "Style",
        menuBarPresetReadable: "Readable",
        menuBarPresetDense: "Dense",
        menuBarSpacingLabel: "Menu bar spacing",
        menuBarSpacingStandard: "Standard",
        menuBarSpacingCompact: "Compact",
        menuBarHideIconToggle: "Hide the app icon while metrics are shown",
        menuBarHideIconCaption: "The icon returns by itself when metrics leave the bar and when there is something to signal (an update ready or the microphone muted).",
        monitorLabelStyleLabel: "Labels",
        menuBarLabelStyleCompact: "Compact",
        menuBarLabelStyleClassic: "Classic",
        monitorMemoryStyleLabel: "Show memory as",
        monitorMemoryPressureDot: "Pressure dot",
        memoryStyleDot: "Dot",
        memoryStylePercent: "%",
        memoryStyleBoth: "Both",

        systemUptime: "Up for",
        batteryCharge: "Charge",
        powerHealth: "Battery health",
        powerCycles: "Cycles",
        speedTestRun: "Speed test",
        speedTestAgain: "Test again",
        speedTestLatency: "Latency",
        speedTestTesting: "Testing…",
        speedTestFailed: "Test failed",

        monitorShowInPanel: "Show in panel",
        panelHideItem: "Hide from panel",
        panelShowItem: "Show in panel",
        panelHiddenItem: "Hidden",
        monitorItemUptime: "Uptime",
        monitorItemNetSpeed: "Live speed",
        monitorItemNetTotals: "Session totals",
        monitorItemNetTest: "Speed test",
        monitorItemDiskUsage: "Disk usage",
        monitorItemDiskActivity: "Live activity",
        monitorItemDiskSMART: "SMART",
        monitorItemDiskProtection: "External protection",
        monitorItemDiskTools: "Tools",
        monitorPanelConfigHint: "Open a block to choose what it shows.",
        monitorOrderSection: "Section order",
        monitorOrderHint: "Drag to reorder the panel sections and use the eye to show or hide each one.",
        obStepPanelTitle: "What's in the panel",
        obStepPanelBody: "Open each block and pick exactly what shows when you click the icon.",
        obStepPanelNavigationTitle: "Section-based panel",
        obStepPanelNavigationBody: "The panel can now show one section at a time. You can switch between Sections and List in Settings.",

        cleaningMenuItem: "Cleaning Mode",
        utilitiesSection: "Utilities",
        quickControlsSection: "Controls",
        panelCategoryWindows: "Windows",
        panelCategoryInput: "Mouse and keyboard",
        panelCategoryFiles: "Files",
        windowMaximizeName: "Maximize windows",
        windowMaximizeCaption: "The green button maximizes without creating another Space.",
        windowMaximizeActiveNow: "Green button override active",
        windowMaximizeNeedsAccessibility: "Needs Accessibility to work.",
        keyDebounceName: "Debounce",
        keyDebounceEnable: "Filter duplicate keys",
        keyDebounceCaption: "Filters very fast duplicate key presses.",
        keyDebounceActiveNow: "Filter active",
        keyDebounceGlobalWindow: "Global window",
        keyDebouncePerKeySection: "Specific keys",
        keyDebouncePerKeyCaption: "Per-key values override the global window. Use 0 ms to stop filtering a key.",
        keyDebounceKeyLabel: "Key",
        keyDebounceWindowLabel: "Window",
        keyDebounceAddKey: "Add key",
        keyDebounceNoOverrides: "No specific keys configured.",
        keyDebounceRemoveKey: "Remove key",
        cleaningPanelCaption: "Locks the keyboard so you can clean safely.",
        cleaningOverlayTitle: "Keyboard locked for cleaning",
        cleaningOverlaySubtitle: "Press the same key 5 times to unlock",
        cleaningOverlayUnlock: "Unlock",
        cleaningOverlayMouseHint: "Your mouse and trackpad still work",
        cleaningNeedsAxTitle: "Accessibility needed",
        cleaningNeedsAxBody: "To lock the keyboard safely, Vorssaint needs Accessibility permission. Grant it in System Settings and try again.",

        tabSupport: "Support",
        shortcutsPageCaption: "Every global shortcut active in the app right now. Each one is configured on its feature's own page.",
        shortcutsPageTitle: "Keyboard shortcuts",
        settingsSearchPlaceholder: "Search settings",
        donateHeading: "Support Vorssaint",
        donateMessage: "Every one of my public projects is, and always will be, completely free: no subscription, no ads. Community support is the only thing that keeps it alive. If Vorssaint helps you, a coffee genuinely makes a difference.",
        donateButton: "Buy me a coffee",
        donateThanks: "Thank you for being here. 🖤",
        supportIntroTitle: "Vorssaint is 100% free and always will be",
        supportIntroMessage: "I keep taking care of the app in my free time. If it helps you, you can help me in a simple way by sharing it, leaving a star on GitHub or buying me a coffee. It helps me a lot to keep improving it.",
        supportIntroStarButton: "Leave a star",
        supportIntroCoffeeButton: "Buy me a coffee",
        supportIntroLaterButton: "Not now",
        supportIntroDoneButton: "Done",
        communityIntroTitle: "See it before everyone else",
        communityIntroMessage: "People who already followed me on X saw several changes in this update before anyone else. I post previews of what is coming and show how it works, so you already know the basics before the update ships. Follow along and see what comes next!",
        communityIntroFollowButton: "Follow @vorssaint on X",
        homebrewOfficialIntroTitle: "Now in the official Homebrew catalog",
        homebrewOfficialIntroMessage: "Vorssaint can now be installed directly from the official Homebrew catalog.",
        homebrewOfficialIntroInstallLabel: "New installation",
        homebrewOfficialIntroMigrationTitle: "Used the old tap?",
        homebrewOfficialIntroMigrationMessage: "Remove the tap once. The app and your settings stay in place.",
        homebrewOfficialIntroCopyButton: "Copy command",
        updateShowcaseTitle: "What's new in 3.1.4",
        updateShowcaseMessage: "Take a quick look at the main improvements in this update.",
        updateShowcaseUnavailable: "The video could not load right now. You can still continue.",
        updateShowcaseRestart: "Restart",
        showMenuBarIcon: "Show menu bar icon",
        showMenuBarIconCaption: "If Vorssaint's icon disappears (macOS can hide menu bar icons when the bar runs out of room, common on Macs with a notch), reopen Vorssaint from Applications or Spotlight: that rebuilds the icon and, if it's still hidden, opens this window. The button above does the same when you can already get here. Keeping fewer menu bar icons, or fewer Vorssaint metrics, makes it far less likely.",
        menuBarIconStillHiddenTitle: "The icon is still hidden",
        menuBarIconStillHiddenBody: "The icon was rebuilt, but macOS did not give it a visible spot. The menu bar is probably out of room: remove some menu bar icons (or close apps with long menus) and try again.",
        menuBarIconManagerHintFormat: "%@ is open and may be keeping the icon in its hidden section. Look for Vorssaint there, or set %@ to always show Vorssaint.",
        shortcutRecording: "Press the new shortcut",
        shortcutReset: "Reset",
        shortcutNone: "None",
        shortcutClear: "Remove shortcut",
        shortcutInvalid: "Use at least Control, Option or Command with a key.",
        shortcutPressKeys: "Press keys",
        shortcutEscapeHint: "Escape cancels.",
        shortcutDeleteHint: "Delete clears.",
        shortcutNotCaptured: "Nothing was captured. macOS or another app already uses that combination. Try another one.",
        shortcutConflictFormat: "This shortcut is already used by %@.",
        shortcutUnavailable: "macOS rejected this shortcut. Choose another one.",
        shelfShortcutToggle: "Shelf shortcut",
        switcherUsageHintFormat: "Hold %@ to navigate; release to activate the window. Shift or ← goes back; Q quits the selected app; Esc cancels.",
        musicBlockSection: "Media keys",
        musicBlockTitle: "Stop Music from opening on its own",
        musicBlockCaption: "The Music app no longer opens when you press the media keys. Turn this off to use Music again.",
        musicBlockReplacementLabel: "Open instead",
        musicBlockReplacementNone: "None",
        musicBlockChooseApp: "Choose app…",
        cleanerName: "Cleaner",
        cleanerIntroTitle: "Clean up your Mac",
        cleanerIntroCaption: "Scans for leftovers from uninstalled apps, caches, logs and the Trash. You review everything first and removed items go to the Trash.",
        cleanerScan: "Scan",
        cleanerScanning: "Scanning…",
        cleanerCleaning: "Cleaning…",
        cleanerCatLeftovers: "Leftovers from uninstalled apps",
        cleanerCatLoginItems: "Orphaned startup items",
        cleanerCatCaches: "Caches",
        cleanerCatLogs: "Logs",
        cleanerCatDeveloper: "Developer junk",
        cleanerCatTrash: "Trash",
        cleanerLeftoversNote: "Found by analysis and left unchecked. Check the path before ticking.",
        cleanerLoginItemsNote: "The entry under Login Items disappears after restarting the Mac.",
        cleanerTrashNote: "Emptying the Trash is permanent.",
        cleanerCatDeviceBackups: "iPhone backups",
        cleanerDeviceBackupsCaption: "Old iPhone and iPad backups take a big slice of the storage macOS calls Other. Remove only the ones you no longer need; a new backup is made when you plug the device in again.",
        cleanerNothingFound: "Nothing to clean. Your Mac is tidy.",
        cleanerClean: "Clean",
        cleanerDoneNote: "Items went to the Trash and can be recovered from there.",
        cleanerAgain: "Scan again",
        cleanerRevealInFinder: "Reveal in Finder",
        cleanerPanelCaption: "App leftovers, caches and logs",
        cleanerSafeSection: "Safe cleanup",
        cleanerOptionalSection: "Optional, review first",
        cleanerCatOtherCaches: "Other caches",
        cleanerCachesCaption: "Temporary files apps rebuild on their own.",
        cleanerLogsCaption: "Old diagnostic logs.",
        cleanerDeveloperCaption: "Xcode build and simulator leftovers.",
        cleanerLoginItemsCaption: "Startup entries left by apps that no longer exist.",
        cleanerLeftoversCaption: "Files left behind by apps you uninstalled.",
        cleanerOtherCachesCaption: "Safe to remove, nothing breaks. Apps may open slower once and downloaded content, like offline music, downloads again.",
        cleanerCleanSizeFormat: "Clean %@",
        cleanerScheduleTitle: "Automatic cleanup",
        cleanerScheduleOff: "Off",
        cleanerScheduleDaily: "Daily",
        cleanerScheduleWeekly: "Weekly",
        cleanerScheduleCaption: "Cleans only the safe part on its own at the chosen time and sends everything to the Trash.",
        cleanerScheduleLastFormat: "The last automatic cleanup freed %@.",
        cleanerAutoNotificationFormat: "%@ freed and sent to the Trash.",
        cleanerScheduleNextFormat: "Next cleanup %@.",
        cleanerScheduleRanFormat: "Last automatic cleanup %@.",
        cleanerScheduleNotifyToggle: "Notify when done",
        cleanerNotifDenied: "Vorssaint notifications are turned off in the system.",
        cleanerNotifOpenSettings: "Open Notification Settings…",
        launchAtLoginNeedsApplications: "The app is running from a place that cannot open at login. Drag Vorssaint to the Applications folder, open it from there and turn this on again.",
        ocrQRToggle: "Read QR codes",
        ocrQRCaption: "If the area has a QR code, its content is shown to copy or open.",
        ocrQRCopied: "QR code copied",
        qrResultTitle: "QR code",
        qrResultCopy: "Copy",
        qrResultOpen: "Open link",
        highlightsTitle: "New in this update",
        highlightsCaptionDockPreview: "Dock Preview now works with Dock magnification turned on",
        highlightsCaptionScreenshot: "The screenshot tool gained a pixel loupe and QR code reading",
        highlightsCaptionSnippetLibrary: "A searchable snippet menu types any snippet right at your cursor",
        highlightsConfigure: "Set up",
        highlightsTry: "Try it",
        highlightsSeeAll: "See all changes",
        switcherCurrentSpaceOnly: "Show only the current desktop",
        switcherCurrentSpaceOnlyCaption: "Lists only windows from the desktop you are on. Picking a window never moves you to another desktop.",
        shelfFileMissing: "O arquivo não existe mais"
    )
}
