// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// The way a language agrees a noun with the number in front of it.
enum CountAgreement {
    /// One form for exactly one, another for every other count.
    case oneAndMany
    /// Russian and Ukrainian: the number's last digits decide. 21 takes the
    /// first form and 22 the middle one, while 11 through 14 fall back to the last.
    case byLastDigits
    /// Slovak: the whole number decides. Only one itself takes the first form
    /// and only two through four the middle one, so 21 and 22 read
    /// "21 súborov" and "22 súborov" the same way 25 does.
    case byWholeNumber
}

/// Languages the interface can use. The first launch defaults to the system
/// language; the onboarding and Settings let the user override it at any time.
enum AppLanguage: String, CaseIterable, Identifiable {
    case enUS = "en-US"
    case ptBR = "pt-BR"
    case tr = "tr"
    case ru = "ru"
    case es = "es"
    case sk = "sk"
    case de = "de"
    case fr = "fr"
    case it = "it"
    case ja = "ja"
    case ko = "ko"
    case uk = "uk"
    case zhHans = "zh-Hans"
    case zhTW = "zh-TW"
    case zhHK = "zh-HK"

    var id: String { rawValue }

    /// How this language agrees a counted noun with the number in front of
    /// it. Three of the fifteen put a distinct form between one and many, and
    /// they disagree on which numbers take it, so the count itself is not
    /// enough to pick a form without knowing the language's rule.
    var countAgreement: CountAgreement {
        switch self {
        case .ru, .uk: return .byLastDigits
        case .sk: return .byWholeNumber
        default: return .oneAndMany
        }
    }

    /// The language's own name, shown in its own script, the way macOS lists them.
    var displayName: String {
        switch self {
        case .enUS: return "English (US)"
        case .ptBR: return "Português (Brasil)"
        case .tr: return "Türkçe"
        case .ru: return "Русский"
        case .es: return "Español"
        case .sk: return "Slovenčina"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .it: return "Italiano"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .zhHans: return "简体中文"
        case .zhHK: return "繁體中文（香港）"
        case .zhTW: return "繁體中文（台灣）"
        case .uk: return "Українська"
        }
    }

    /// Dates and times in this language, arranged the way System Settings
    /// asks: region, 12- or 24-hour clock and first day of the week. A locale
    /// made from the language alone would bring that language's own clock.
    func formattingLocale(system: Locale = .autoupdatingCurrent) -> Locale {
        var components = Locale.Components(identifier: rawValue)
        components.region = system.region
        components.hourCycle = system.hourCycle
        components.firstDayOfWeek = system.firstDayOfWeek
        return Locale(components: components)
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
            ("pt", .ptBR), ("tr", .tr), ("ru", .ru), ("es", .es), ("sk", .sk), ("de", .de),
            ("fr", .fr), ("it", .it), ("ja", .ja), ("ko", .ko), ("uk", .uk), ("zh", .zhHans),
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

    var s: Strings { Strings.localized(language) }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.language),
           let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            language = .systemDefault
        }
    }
}

extension Strings {
    /// The catalog for a language other than the current one, as the
    /// feature string tables offer theirs.
    static func localized(_ language: AppLanguage) -> Strings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhHK: return .zhHK
        case .zhTW: return .zhTW
        case .uk: return .uk
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
    /// Named actions an icon-only control borrows so it can say what it
    /// does. No feature owns these, because half a dozen already share them.
    let actionClear: String
    let actionRemove: String
    let actionBack: String
    let actionSearch: String
    let actionMute: String
    let actionUnmute: String
    let actionPlay: String
    let actionPause: String
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
    let keepAwakeUntilLabel: String
    let keepAwakeUntilStart: String
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
    let memorySwapUsed: String
    let memoryCompressed: String
    let memoryCachedFiles: String
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
    let minimalWindowPreviews: String
    let minimalWindowPreviewsCaption: String
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
    let advancedClearFailed: String
    let advancedClearConfirmTitle: String
    let advancedClearConfirmBody: String
    let advancedUninstallSection: String
    let advancedUninstallDescription: String
    let advancedUninstallButton: String
    let advancedUninstallConfirmTitle: String
    let advancedUninstallConfirmBody: String
    let advancedUninstallFailedTitle: String
    let advancedUninstallFailedBody: String

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
    let dimScreenOnLidCloseTitle: String
    let dimScreenOnLidCloseCaption: String

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

    // MARK: Settings — mouse navigation
    let mouseNavigationSection: String
    let mouseNavigationEnable: String
    let mouseNavigationCaption: String

    // MARK: Settings — middle click
    let middleClickSection: String
    let middleClickEnable: String
    let middleClickEnableCaption: String
    let middleClickDragConflict: String
    let middleClickNoTrackpad: String
    let middleClickTapPicker: String
    let middleClickTapOff: String
    let middleClickTapThreeFingers: String
    let middleClickTapFourFingers: String
    let middleClickTapCaption: String

    // MARK: Settings — quick tools
    let quickToolsTab: String
    let quickToolShortcutToggle: String

    // MARK: Quick tool — OCR
    let ocrName: String
    let ocrCaption: String
    let ocrCopied: String
    let ocrNoText: String

    // MARK: Quick tool — color picker
    let colorPickerName: String
    let colorPickerCaption: String
    let colorPickerFormatLabel: String
    let colorPickerBareHexToggle: String
    let colorPickerPickNow: String

    // MARK: Quick tool — microphone
    let micMuteName: String
    let micUnmuteName: String
    let micMuteCaption: String
    let micMutedHUD: String
    let micUnmutedHUD: String
    let micMutePartialHUD: String
    let micUnmutePartialHUD: String
    let micMuteMenuBarToggle: String
    let micMuteMenuBarCaption: String

    // MARK: Quick tool — paste plain text
    let pastePlainName: String
    let pastePlainCaption: String

    // MARK: Quick tool — launcher
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

    // MARK: Settings — switcher appearance & selection
    let switcherIconRowMode: String
    let switcherIconRowModeCaption: String
    let switcherSimpleModeCaption: String
    let switcherShortcutHintApps: String
    let switcherShortcutHintWindows: String
    let switcherWindowShortcutCaption: String
    let switcherTakeOverSystemShortcuts: String
    let switcherTakeOverSystemShortcutsCaption: String
    let switcherAppearanceDelay: String
    let switcherAppearanceDelayCaption: String
    let switcherMaxColumns: String
    let switcherMaxColumnsCaption: String
    let switcherMaxColumnsAuto: String
    let switcherInstantSelection: String
    let switcherInstantSelectionCaption: String
    let switcherIgnoreHoverSelection: String
    let switcherIgnoreHoverSelectionCaption: String
    let switcherMergeTabs: String
    let switcherMergeTabsCaption: String

    // MARK: Settings — switcher window handling
    let switcherWindowlessApps: String
    let switcherWindowlessAppsCaption: String
    let switcherWindowlessAppsOff: String
    let switcherWindowlessAppsFinder: String
    let switcherWindowlessAppsAll: String
    let switcherWindowlessAppsLockedFormat: String
    let switcherNoOpenWindow: String
    let switcherOtherDesktop: String

    // MARK: Settings — Dock preview
    let dockPreviewName: String
    let dockPreviewEnable: String
    let dockPreviewEnableCaption: String
    let dockPreviewCurrentSpaceOnlyCaption: String
    let dockPreviewBackgroundOpacity: String
    let dockPreviewBackgroundOpacityCaption: String
    let dockPreviewBackgroundOpacityGlassCaption: String
    let dockPreviewOpenDelay: String
    let dockPreviewOpenDelayCaption: String
    let dockPreviewQuitAppOnClose: String
    let dockPreviewQuitAppOnCloseCaption: String
    let dockPreviewKeepDockVisible: String
    let dockPreviewKeepDockVisibleCaption: String
    let dockPreviewOrderByCreation: String
    let dockPreviewOrderByCreationCaption: String
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

    // MARK: Feature — cut & paste in Finder
    let cutPasteName: String
    let cutPasteEnable: String
    let cutPasteEnableCaption: String
    let cutPasteShowHUD: String
    let cutPasteShowHUDCaption: String
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
    let autoQuitOngoingWorkNote: String
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
    let uninstallerSelectAll: String
    let uninstallerRemove: String
    let uninstallerCancel: String
    let uninstallerConfirmationExpired: String
    let uninstallerDoneTitle: String
    let uninstallerFreedFormat: String      // + size string
    let uninstallerSomeFailed: String
    let uninstallerFailedNeedsFDA: String
    let uninstallerFailedMoreFormat: String
    let uninstallerAnother: String
    let uninstallerCatApp: String
    let uninstallerCatSupport: String
    let uninstallerCatCaches: String
    let uninstallerCatPreferences: String
    let uninstallerCatContainers: String
    let uninstallerCatLogs: String
    let uninstallerCatState: String
    let uninstallerCatOther: String
    let uninstallerCommandBarBrowseTitle: String
    let uninstallerCommandBarToggle: String
    let uninstallerCommandBarCaption: String
    let uninstallerWatchTrashToggle: String
    let uninstallerWatchTrashCaption: String
    let uninstallerConfirmTrashCleanup: String
    let uninstallerTrashUnavailable: String
    let uninstallerCommandBarFinderTitle: String
    let uninstallerSelectionUnavailable: String
    let uninstallerRefusedNotApp: String
    let uninstallerRefusedSystemFormat: String        // + app name
    let uninstallerRefusedSharedFormat: String        // + app name
    let uninstallerRefusedNestedFormat: String        // + app name
    let uninstallerRefusedSelfFormat: String          // + Advanced tab name
    let uninstallerRefusedLinkFormat: String          // + app name
    let uninstallerRefusedUnidentifiedFormat: String  // + app name
    let uninstallerPickerHiddenNote: String

    // MARK: Feature — URL cleaner
    let urlCleanerName: String
    let urlCleanerEnable: String
    let urlCleanerEnableCaption: String
    let urlCleanerActiveNow: String
    let urlCleanerManualTitle: String
    let urlCleanerInputPlaceholder: String
    let urlCleanerOutputPlaceholder: String
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

    // MARK: Homebrew — package search
    let homebrewSearchPlaceholder: String
    let homebrewKeyboardHint: String
    let homebrewSearchButton: String
    let homebrewSearchResults: String
    let homebrewInstalled: String
    let homebrewAll: String
    let homebrewFormulas: String
    let homebrewCasks: String
    let homebrewNoPackages: String
    let homebrewDependencies: String
    let homebrewGroupDependencies: String
    let homebrewOrphans: String
    let homebrewOrphansNote: String
    let homebrewDependencyUpdatesFormat: String
    let homebrewNoSelection: String

    // MARK: Homebrew — package details & actions
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
    let homebrewLastLogView: String
    let homebrewLastLogHide: String
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

    // MARK: Homebrew — confirmations
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

    // MARK: Homebrew — operation status
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

    // MARK: Media — file selection & output
    let mediaSelectFile: String
    let mediaDropHint: String
    let mediaOutput: String
    let mediaOutputAutomatic: String
    let mediaChooseOutput: String

    // MARK: Media — conversion options
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
    let mediaCompressionLowDescription: String
    let mediaCompressionMediumDescription: String
    let mediaCompressionHighDescription: String
    let mediaMaxSize: String
    let mediaSizingResolution: String
    let mediaSizingFileSize: String
    let mediaTargetSize: String
    let mediaTargetSizeHint: String
    let mediaErrorTargetTooSmall: String
    let mediaMegabytesSuffix: String
    let mediaWidth: String
    let mediaFPS: String
    let mediaKeepAudio: String
    let mediaCodec: String
    let mediaFormat: String
    let mediaStripMetadata: String
    let mediaLoopGIF: String

    // MARK: Media — text extraction
    let mediaOCRMode: String
    let mediaOCRAccurate: String
    let mediaOCRFast: String
    let mediaLanguageCorrection: String
    let mediaTextOutputNote: String

    // MARK: Media — results & errors
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
    let shelfDropZoneCaptionTopCenter: String
    let shelfDropZoneLabel: String
    let shelfDockPlacement: String
    let shelfDockMenuBar: String
    let shelfDockTopCenter: String
    let shelfDockIslandNote: String
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

    // MARK: Feature — extra brightness
    let extraBrightnessName: String
    let extraBrightnessCaption: String
    let extraBrightnessLevelLabel: String
    let extraBrightnessUnsupported: String
    let shelfHotkeyLabel: String
    let shelfOpenNow: String
    let shelfNoPermission: String
    let shelfMenuItem: String

    // MARK: Panel — temporary shelf contents
    let shelfTitle: String
    let shelfEmpty: String
    let shelfClearAll: String
    let shelfRemoveSelected: String
    let shelfSelectedFormat: String      // + count
    let shelfHint: String
    let shelfItemImage: String

    // MARK: Panel — temporary shelf item tooltips
    // Three forms, not two: Russian and Ukrainian agree a noun with the number
    // in front of it as one, as two through four, and as five or more. Every other
    // language here needs only the first and the last, and repeats the last
    // in the middle slot. A pile always holds two or more, so the items count
    // has no singular of its own.
    let shelfTooltipItemsFormat: String      // + count, five or more
    let shelfTooltipItemsFew: String         // + count, two through four
    let shelfTooltipImageSingular: String    // + count == 1
    let shelfTooltipImageFew: String         // + count, two through four
    let shelfTooltipImagePlural: String      // + count
    let shelfTooltipFileSingular: String     // + count == 1
    let shelfTooltipFileFew: String          // + count, two through four
    let shelfTooltipFilePlural: String       // + count
    let shelfTooltipNoteSingular: String     // + count == 1
    let shelfTooltipNoteFew: String          // + count, two through four
    let shelfTooltipNotePlural: String       // + count
    let shelfTooltipLinkSingular: String     // + count == 1
    let shelfTooltipLinkFew: String          // + count, two through four
    let shelfTooltipLinkPlural: String       // + count

    // MARK: Panel — temporary shelf actions
    let shelfActionOpen: String
    let shelfActionOpenWith: String
    let shelfActionShare: String
    let shelfActionPin: String
    let shelfActionUnpin: String

    // MARK: Panel — per-app breakdown
    let breakdownMeasuring: String

    // MARK: Panel — volume mixer
    let mixerSection: String
    let mixerEmpty: String
    let mixerUnavailable: String
    let mixerPermissionBody: String
    let mixerResetTooltip: String

    // MARK: Volume mixer — output devices
    let mixerOutputDefault: String
    let mixerOutputCurrent: String
    let mixerOutputUnavailable: String
    let mixerOutputFallback: String
    let mixerBypassedCaption: String
    let mixerOutputTooltip: String
    let mixerAirPlayChooseSpeaker: String
    let mixerSystemOutputTitle: String
    let mixerSystemOutputNoDevices: String
    let mixerSystemOutputTooltip: String
    let mixerSystemOutputErrorFormat: String

    // MARK: Volume mixer — volume behavior
    let mixerLowerOnHeadphonesDisconnect: String
    let mixerLowerOnHeadphonesDisconnectCaption: String
    let mixerHeadphonesDisconnectVolume: String
    let preciseVolumeRollerEnable: String
    let preciseVolumeRollerCaption: String
    let preciseVolumeRollerTapFailed: String

    // MARK: Volume mixer — output switcher
    let soundOutputSwitcherTitle: String
    let soundOutputSwitcherEnable: String
    let soundOutputSwitcherCaption: String
    let soundOutputSwitcherDevices: String
    let soundOutputSwitcherNoAvailableSelection: String

    // MARK: Volume mixer — input devices
    let mixerInputTitle: String
    let mixerInputNoDevices: String
    let mixerInputUnavailable: String
    let mixerInputFallback: String
    let mixerInputTooltip: String
    let mixerInputErrorFormat: String

    // MARK: Volume mixer — app visibility
    let mixerVisibleApps: String
    let mixerAllShown: String
    let mixerHiddenCountLabel: String
    let mixerHideFromList: String

    // MARK: Panel — audio device priority
    let audioPrioritySection: String
    let audioPriorityOutputEnable: String
    let audioPriorityInputEnable: String
    let audioPriorityOutputList: String
    let audioPriorityInputList: String
    let audioPriorityMoveUp: String
    let audioPriorityMoveDown: String
    let audioPriorityUnavailable: String
    let audioPriorityCurrent: String
    let audioPriorityCaption: String

    // MARK: Settings — updates
    let updatesSection: String
    let autoCheckToggle: String
    let includeBetaUpdatesToggle: String
    let includeBetaUpdatesCaption: String
    let betaBadgeLabel: String
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

    // MARK: Secure input
    let secureInputTitle: String
    let secureInputHeldFormat: String
    let secureInputUnattributed: String
    let secureInputUnidentified: String
    let secureInputRevealFormat: String

    // MARK: Secure input — switcher
    // The switcher page's captions: there secure input costs the switcher its
    // keys rather than typing, and ⌘Tab reaches the macOS switcher until it ends.
    let secureInputSwitcherHeldFormat: String
    let secureInputSwitcherUnattributed: String
    let secureInputSwitcherUnidentified: String

    // MARK: About
    let aboutDescription: String
    let versionPrefix: String
    let reviewIntro: String
    let reviewHighlights: String
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

    // MARK: Onboarding — permissions
    let obStepAccessibilityTitle: String
    let obStepAccessibilityBody: String
    let obAccessibilityWhy: String
    let obStepRecordingTitle: String
    let obStepRecordingBody: String
    let obRecordingWhy: String

    // MARK: Onboarding — monitor
    let obStepMonitorTitle: String
    let obStepMonitorBody: String
    let obMonitorNoPermission: String

    // MARK: Onboarding — optional features
    let obStepOptionalTitle: String
    let obStepOptionalBody: String
    let obStepStatusTitle: String
    let obStepStatusBody: String
    let obStatusRecheck: String

    // MARK: Onboarding — completion
    let obStepDoneTitle: String
    let obStepDoneBody: String
    let obDoneHint: String

    // MARK: Onboarding — updates & purpose
    let obWhatsNewTitle: String
    let obWhatsNewFallback: String
    let obLanguageUpdateTitle: String
    let obLanguageUpdateBody: String
    let obPurposeTitle: String
    let obPurposeBody: String
    let obPurposeSkip: String

    // MARK: Settings — monitor / menu bar metrics
    let tabMonitor: String

    // MARK: Monitor — menu bar
    let monitorMenuBarSection: String
    let monitorMenuBarPreview: String
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

    // MARK: Monitor — panel
    let monitorPanelSection: String
    let panelNavigationMode: String
    let panelNavigationCaption: String
    let panelFooterSections: String
    let panelFooterList: String
    let betaBadge: String
    let betaFeatureWarning: String

    // MARK: Panel — network
    let networkSection: String
    let networkIPAddresses: String
    let networkLocalIP: String
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
    let diskMenuBarStyleLabel: String
    let diskMenuBarUsedPercentage: String
    let diskMenuBarAvailableSpace: String
    let diskMenuBarUsedSpace: String
    let diskAvailable: String
    let diskPurgeable: String
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
    let disclosureExpanded: String
    let disclosureCollapsed: String
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
    let monitorOrderHint: String

    // MARK: Onboarding — panel setup
    let obStepPanelTitle: String
    let obStepPanelBody: String
    let obStepPanelNavigationTitle: String
    let obStepPanelNavigationBody: String

    // MARK: Cleaning mode
    let cleaningMenuItem: String

    // MARK: Cleaning mode — panel categories
    let utilitiesSection: String
    let quickControlsSection: String
    let panelCategoryWindows: String
    let panelCategoryInput: String
    let panelCategoryFiles: String

    // MARK: Cleaning mode — window controls
    let windowMaximizeName: String
    let windowMaximizeCaption: String
    let windowMaximizeActiveNow: String
    let windowMaximizeNeedsAccessibility: String

    // MARK: Cleaning mode — key debounce
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

    // MARK: Cleaning mode — overlay
    let cleaningPanelCaption: String
    let cleaningOverlayTitle: String
    let cleaningOverlaySubtitle: String
    let cleaningOverlayUnlock: String
    let cleaningOverlayMouseHint: String
    let cleaningKeepScreenVisibleToggle: String
    let cleaningKeepScreenVisibleCaption: String
    let cleaningStartNow: String
    let cleaningNeedsAxTitle: String
    let cleaningNeedsAxBody: String

    // MARK: Support / donate
    let tabSupport: String
    let shortcutsPageCaption: String
    let shortcutsPageTitle: String
    let settingsSearchPlaceholder: String

    // MARK: Support — donations
    let donateHeading: String
    let donateMessage: String
    let donateButton: String
    let donateThanks: String

    // MARK: Support — introduction
    let supportIntroTitle: String
    let supportIntroMessage: String
    let supportIntroStarButton: String
    let supportIntroStarMessage: String
    /// A quiet line under the donation button inviting a GitHub star instead.
    let supportIntroStarHint: String
    let supportIntroCoffeeButton: String
    let supportIntroLaterButton: String
    let supportIntroDoneButton: String

    // MARK: Support — community
    let discordIntroTitle: String
    let discordIntroMessage: String
    let discordIntroJoinButton: String
    let communityIntroTitle: String
    let communityIntroMessage: String
    let communityIntroFollowButton: String

    // MARK: Support — Homebrew setup
    let homebrewOfficialIntroTitle: String
    let homebrewOfficialIntroMessage: String
    let homebrewOfficialIntroInstallLabel: String
    let homebrewOfficialIntroMigrationTitle: String
    let homebrewOfficialIntroMigrationMessage: String
    let homebrewOfficialIntroCopyButton: String

    // MARK: Support — update showcase
    let updateShowcaseTitle: String
    let updateShowcaseMessage: String
    let updateShowcaseUnavailable: String
    let updateShowcaseRestart: String

    // MARK: Support — menu bar icon
    let showMenuBarIcon: String
    let menuBarIconStillHiddenTitle: String
    let menuBarIconStillHiddenBody: String
    let menuBarIconManagerHintFormat: String  // + manager name (twice)
    let menuBarIconDisallowedBody: String

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
    let shortcutTakeOverOffer: String
    let shortcutTakeOverAction: String
    let shortcutTakeOverCaption: String
    let shortcutTakeOverDismiss: String
    let shortcutUnavailable: String
    let shelfShortcutToggle: String
    let switcherUsageHintFormat: String

    // MARK: Media keys
    let musicBlockSection: String
    let musicBlockTitle: String
    let musicBlockCaption: String
    let musicBlockUnavailable: String
    let musicBlockReplacementLabel: String
    let musicBlockReplacementNone: String
    let musicBlockReplacementBlocked: String
    let musicBlockChooseApp: String
    let musicBlockPlayReplacement: String

    // MARK: Cleaner
    let cleanerName: String
    let cleanerIntroTitle: String
    let cleanerIntroCaption: String

    // MARK: Cleaner — scan & categories
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
    let cleanerCatScreenshots: String
    let cleanerScreenshotsCaptionFormat: String
    let cleanerScreenshotsSettingCaption: String
    let cleanerScreenshotsAfterFormat: String

    // MARK: Cleaner — results
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

    // MARK: Cleaner — schedule
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

    // MARK: Cleaner — notifications
    let cleanerNotifDenied: String
    let cleanerNotifOpenSettings: String

    // MARK: Settings — launch at login
    let launchAtLoginNeedsApplications: String
    let launchAtLoginNeedsApproval: String

    // MARK: Settings — OCR
    let ocrRemoveLineBreaksToggle: String
    let ocrRemoveLineBreaksCaption: String
    let ocrQRToggle: String
    let ocrQRCaption: String
    let ocrQRCopied: String
    let qrResultTitle: String
    let qrResultCopy: String
    let qrResultOpen: String

    // MARK: Release notes — highlights
    let highlightsTitle: String
    let highlightsTitleClipboardRedesign: String
    let highlightsTitleWindowLayout: String
    let highlightsTitleQuitProtection: String
    let highlightsTitleRecorderBlur: String
    let highlightsCaptionDockPreview: String
    let highlightsCaptionScreenshot: String
    let highlightsCaptionSnippetLibrary: String
    let highlightsCaptionCapturePalette: String
    let highlightsCaptionClipboardRedesign: String
    let highlightsCaptionWindowLayout: String
    let highlightsCaptionQuitProtection: String
    let highlightsCaptionRecorderBlur: String
    let highlightsConfigure: String
    let highlightsTry: String
    let highlightsSeeAll: String

    // MARK: Settings — switcher space behavior
    let switcherCurrentSpaceOnly: String
    let switcherCurrentSpaceOnlyCaption: String

    // MARK: Panel — temporary shelf item status
    let shelfFileMissing: String

    // MARK: Settings — window previews
    let previewSizeSmall: String

    // MARK: Volume mixer — sound effects
    let mixerSoundEffectsOutputTitle: String
    let mixerSoundEffectsOutputTooltip: String

    // MARK: Monitor — actions
    let monitorOpenActivityMonitor: String

    // MARK: Settings — Dock click behavior
    let dockClickHide: String
    let dockClickHideCaption: String

    // MARK: Monitor — memory metric
    let monitorMemoryMetricLabel: String
    let memoryMetricUsed: String
    let memoryMetricApp: String

    // MARK: Panel — keep awake menu
    let keepAwakeRightClickToggle: String
    let keepAwakeRightClickToggleCaption: String

    // MARK: URL cleaner — site rules
    let urlCleanerRulesTitle: String
    let urlCleanerRulesCaption: String
    let urlCleanerRulesCoverageCaption: String
    let urlCleanerRulesAllSites: String
    let urlCleanerRulesCountSingular: String
    let urlCleanerRulesCountPluralFormat: String   // + count
    let urlCleanerRulesAddSite: String
    let urlCleanerRulesParameterPlaceholder: String
    let urlCleanerRulesMatchCaption: String
    let urlCleanerRulesAddButton: String
    let urlCleanerRulesRemoveButton: String
    let urlCleanerRulesRemoveSiteButton: String
    let urlCleanerRulesRestoreSiteButton: String
    let urlCleanerRemovedFormat: String            // + comma separated names

    // MARK: Settings — switcher search
    let switcherSearchPin: String
    let switcherSearchPinCaption: String

    // MARK: Settings — scroll direction
    let invertVerticalScroll: String
    let invertHorizontalScroll: String

    // MARK: Settings — horizontal scrolling
    let scrollHorizontalName: String

    // MARK: Settings — zoom
    let zoomSection: String
    let zoomControlNote: String
    let pinchZoom: String
    let scrollHorizontalModifierLabel: String
    let scrollHorizontalCommandKey: String
    let scrollHorizontalCaption: String
    let switcherShowShortcutHints: String
    let switcherShowShortcutHintsCaption: String

    // MARK: Uninstaller — Homebrew packages
    let uninstallerHomebrewPackageFormat: String
    let uninstallerHomebrewCheckFailed: String

    // MARK: Settings — temporary shelf placement
    let shelfEdgeToggle: String
    let shelfEdgeCaption: String

    // MARK: Settings — focus follows mouse
    let focusFollowsMouseName: String
    let focusFollowsMouseCaption: String
    let focusFollowsMouseDelay: String
    let focusFollowsMouseRaise: String
    let focusFollowsMouseWaitForStop: String

    // MARK: Settings — switcher window placement
    let switcherMinimizedPlacementLabel: String
    let switcherTreatHiddenAppsLikeMinimized: String
    let switcherMinimizedPlacementNormal: String
    let switcherMinimizedPlacementEnd: String
    let switcherMinimizedPlacementHidden: String
    let switcherShowFullscreenWindows: String
    let switcherScreenPlacementLabel: String
    let switcherScreenPlacementPointer: String
    let switcherScreenPlacementMenuBar: String
    let switcherScreenPlacementActiveWindow: String
    let switcherScreenPlacementCaption: String
    let switcherCurrentDisplayOnly: String
    let switcherCurrentDisplayOnlyCaption: String

    // MARK: Settings — smooth scrolling
    let smoothScrollResponseLabel: String
    let smoothScrollCoastLabel: String

    // MARK: Settings — mouse acceleration
    let mouseAccelerationName: String
    let mouseAccelerationCaption: String

    // MARK: Settings — linear scrolling
    let linearScrollName: String
    let linearScrollCaption: String
    let linearScrollLinesLabel: String
    // MARK: Settings — scroll speed
    let scrollSpeedName: String
    let scrollSpeedCaption: String
    let scrollSpeedMultiplierLabel: String

    // MARK: Settings — temporary shelf behavior
    let shelfClearOnClose: String
    let shelfClearOnCloseCaption: String
    let shelfShortcutFinderSelection: String
    let shelfShortcutFinderSelectionCaption: String

    // MARK: Settings — Spaces order
    let spacesOrderName: String
    let spacesOrderCaption: String

    // MARK: Feature — quit applications
    let quitAppsName: String
    let quitAppsCaption: String
}
