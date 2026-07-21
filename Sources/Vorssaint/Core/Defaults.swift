// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Carbon.HIToolbox
import Foundation

/// Every UserDefaults key used by the app, in one place.
enum DefaultsKey {
    static let language = "appLanguage"                   // AppLanguage.rawValue
    static let clamshellPreferred = "clamshellPreferred"  // apply closed-lid mode to every session
    static let onboardingStep = "onboardingStep"          // resume point if onboarding is interrupted
    static let featuresOnboardingVersion = "featuresOnboardingVersion" // last feature-tour marker handled
    static let lastUpdateIntroVersion = "lastUpdateIntroVersion"
    static let dockPreviewIntroVersion = "dockPreviewIntroVersion"
    static let supportUpdateIntroVersion = "supportUpdateIntroVersion"
    static let updateHighlightsSeenVersion = "updateHighlightsSeenVersion"
    static let updateShowcaseIntroVersion = "updateShowcaseIntroVersion"
    static let updateShowcaseMediaOverride = "updateShowcaseMediaOverride"
    static let defaultDuration = "defaultDurationMinutes" // 0 = indefinite
    static let batteryLimit = "batteryLimitPercent"       // 0 = never
    static let keepAwakeAutoStart = "keepAwakeAutoStart"  // start Keep Awake when the app launches
    static let keepAwakeExternalDisplay = "keepAwakeExternalDisplay"
    static let keepAwakeConnectedToPower = "keepAwakeConnectedToPower"
    static let keepAwakeMouseJiggleEnabled = "keepAwakeMouseJiggleEnabled"
    static let keepAwakeMouseJiggleInterval = "keepAwakeMouseJiggleIntervalMinutes"
    static let hotkeyEnabled = "hotkeyEnabled"
    static let launchAtLoginWanted = "launchAtLoginWanted"  // the user's choice; the system record can be lost
    static let keepAwakeShortcut = "keepAwakeShortcut"    // GlobalShortcut storage value
    static let keepAwakeIconTint = "keepAwakeIconTint"    // KeepAwakeIconTint.rawValue
    static let keepAwakeActiveIcon = "keepAwakeActiveIcon" // KeepAwakeActiveIcon.rawValue
    static let showCountdown = "showCountdownInMenuBar"
    static let statusItemPlacementGeneration = "statusItemPlacementGeneration"
    static let hasOnboarded = "hasOnboarded"
    static let sleepDisabledFlag = "vorssDisabledSleep"   // internal guard for pmset disablesleep
    static let scrollInverterEnabled = "scrollInverterEnabled"
    static let smoothScrollEnabled = "smoothScrollEnabled"
    static let smoothScrollStep = "smoothScrollStep"      // pixels per wheel tick
    static let mouseNavigationEnabled = "mouseNavigationEnabled" // side buttons trigger Back and Forward
    static let switcherEnabled = "switcherEnabled"
    static let switcherShortcut = "switcherShortcut"      // GlobalShortcut storage value
    static let switcherWindowShortcut = "switcherWindowShortcut" // GlobalShortcut storage value
    static let switcherIconRowMode = "switcherIconRowMode"
    static let switcherSimpleMode = "switcherSimpleMode"  // app-only row without window captures
    static let switcherMergeTabs = "switcherMergeTabs"     // show one switcher entry per app (collapse all of an app's windows)
    static let switcherShowWindowlessFinder = "switcherShowWindowlessFinder"
    static let dockPreviewEnabled = "dockPreviewEnabled"
    static let dockClickMinimize = "dockClickMinimize"    // click the active app's Dock icon to minimize its windows
    static let dockClickCycleWindows = "dockClickCycleWindows" // click the active app's Dock icon to cycle through its windows
    static let middleClickEnabled = "middleClickEnabled"  // three-finger PHYSICAL click on the trackpad acts as a middle click
    static let middleClickTapFingers = "middleClickTapFingers"  // 0 = off (default); 3 or 4 = a light tap with that many fingers also middle-clicks (issue #161)
    static let previewSize = "previewSize"                // app switcher + dock preview thumbnail size
    static let autoCheckUpdates = "autoCheckUpdates"
    static let releaseNotesOnUpdate = "releaseNotesOnUpdate" // show What's New after an update
    static let appVolumes = "appVolumes"                  // [bundle id: 0...2]
    static let appOutputDevices = "appOutputDevices"      // [bundle id: audio device UID]
    static let mixerShowFinder = "mixerShowFinder"
    static let mixerLowerVolumeOnHeadphonesDisconnect = "mixerLowerVolumeOnHeadphonesDisconnect"
    static let mixerHeadphonesDisconnectVolumePercent = "mixerHeadphonesDisconnectVolumePercent"
    static let soundOutputSwitcherEnabled = "soundOutputSwitcherEnabled"
    static let soundOutputSwitcherShortcut = "soundOutputSwitcherShortcut"
    static let soundOutputSwitcherDeviceUIDs = "soundOutputSwitcherDeviceUIDs"
    static let preferredInputDevice = "preferredInputDevice" // audio input device UID
    static let finderCutPasteEnabled = "finderCutPasteEnabled"
    static let autoQuitEnabled = "autoQuitEnabled"
    static let autoQuitExceptions = "autoQuitExceptions"  // [bundle id] kept running
    static let shelfEnabled = "shelfEnabled"
    static let shelfShortcutEnabled = "shelfShortcutEnabled"
    static let shelfShortcut = "shelfShortcut"            // GlobalShortcut storage value
    static let shelfShakeToOpen = "shelfShakeToOpen"
    static let shelfDropZoneEnabled = "shelfDropZoneEnabled"
    static let shelfCloseAfterDrop = "shelfCloseAfterDrop"
    static let shelfRemoveAfterDrop = "shelfRemoveAfterDrop"
    static let shelfAutomaticExclusions = "shelfAutomaticExclusions" // [bundle id] blocks automatic opening only
    static let extraBrightnessEnabled = "extraBrightnessEnabled"
    static let extraBrightnessLevel = "extraBrightnessLevel"   // Int percent 0-100
    static let brightnessControlEnabled = "brightnessControlEnabled" // sliders for every display
    static let brightnessKeysEnabled = "brightnessKeysEnabled" // brightness keys act on the display under the pointer
    static let brightnessOSDEnabled = "brightnessOSDEnabled" // brightness adjustment overlay
    // Displays this app switched off, so a run that ends without putting them
    // back can be repaired on the next start instead of needing a replug.
    static let displaysSwitchedOff = "displaysSwitchedOff"
    // Set while a start is under way and cleared once the app has run
    // healthily for a while, or when it is quit properly. Found still set at
    // the next start, it means the previous one died on the way up.
    static let startupDidNotFinish = "startupDidNotFinish"
    static let musicBlockEnabled = "musicBlockEnabled"
    static let musicBlockReplacementPath = "musicBlockReplacementPath"  // app bundle path ("" = none)
    static let cleanerScheduleFrequency = "cleanerScheduleFrequency"    // off | daily | weekly
    static let cleanerScheduleHour = "cleanerScheduleHour"
    static let cleanerScheduleMinute = "cleanerScheduleMinute"
    static let cleanerScheduleWeekday = "cleanerScheduleWeekday"        // 1 Sunday ... 7 Saturday
    static let cleanerScheduleNotify = "cleanerScheduleNotify"
    static let cleanerLastAutoRun = "cleanerLastAutoRun"                // Double, epoch seconds
    static let cleanerLastAutoFreed = "cleanerLastAutoFreed"            // Int bytes
    static let cleanerBadgeSeen = "cleanerBadgeSeen"                    // red dot guiding to the new cleaner
    static let settingsWindowWidth = "settingsWindowWidth"     // last user-chosen content size (0 = unset)
    static let settingsWindowHeight = "settingsWindowHeight"
    static let shelfItems = "shelfItems"                  // Data: [ShelfPersistedItem] JSON
    static let urlCleanerEnabled = "urlCleanerEnabled"
    static let windowMaximizeEnabled = "windowMaximizeEnabled"
    static let keyboardDebounceEnabled = "keyboardDebounceEnabled"
    static let keyboardDebounceWindowMs = "keyboardDebounceWindowMs"
    static let keyboardDebounceKeyWindows = "keyboardDebounceKeyWindows" // comma-separated keyCode:ms
    static let panelUtilityCleaning = "panelUtilityCleaning"
    static let panelUtilityURLCleaner = "panelUtilityURLCleaner"
    static let panelUtilityUninstaller = "panelUtilityUninstaller"
    static let panelUtilityCleaner = "panelUtilityCleaner"
    static let panelUtilityHomebrew = "panelUtilityHomebrew"
    static let panelUtilityMedia = "panelUtilityMedia"
    static let panelUtilityClipboard = "panelUtilityClipboard"
    static let panelUtilityWindowLayout = "panelUtilityWindowLayout"
    static let panelControlMouseScroll = "panelControlMouseScroll"
    static let panelControlMouseNavigation = "panelControlMouseNavigation"
    static let panelControlSwitcher = "panelControlSwitcher"
    static let panelControlDockPreview = "panelControlDockPreview"
    static let panelControlCutPaste = "panelControlCutPaste"
    static let panelControlAutoQuit = "panelControlAutoQuit"
    static let panelControlShelf = "panelControlShelf"
    static let panelControlWindowMaximize = "panelControlWindowMaximize"
    static let panelControlKeyDebounce = "panelControlKeyDebounce"
    static let panelControlDockClick = "panelControlDockClick"
    static let panelControlDockClickCycle = "panelControlDockClickCycle"
    static let panelControlMiddleClick = "panelControlMiddleClick"
    static let panelControlTextSnippets = "panelControlTextSnippets"
    static let panelControlRadialMenu = "panelControlRadialMenu"
    // Quick-control categories start collapsed and remember being opened.
    static let panelControlWindowsExpanded = "panelControlWindowsExpanded"
    static let panelControlInputExpanded = "panelControlInputExpanded"
    static let panelControlFilesExpanded = "panelControlFilesExpanded"
    // Show/hide whole panel sections that have no monitorShow* key of their own.
    static let panelShowKeepAwake = "panelShowKeepAwake"
    static let panelShowBrightness = "panelShowBrightness"
    static let panelShowUtilities = "panelShowUtilities"
    static let panelShowControls = "panelShowControls"
    static let panelShowToggles = "panelShowToggles"
    // Quick toggles tab: per-action visibility (the order lives in panelToggleOrder).
    static let panelToggleDarkMode = "panelToggleDarkMode"
    static let panelToggleEmptyTrash = "panelToggleEmptyTrash"
    static let panelToggleEjectDisks = "panelToggleEjectDisks"
    static let panelToggleHiddenFiles = "panelToggleHiddenFiles"
    static let panelToggleDesktopIcons = "panelToggleDesktopIcons"
    static let panelToggleLockScreen = "panelToggleLockScreen"
    static let panelToggleDisplayOff = "panelToggleDisplayOff"
    static let panelToggleScreenSaver = "panelToggleScreenSaver"

    // System monitor — live metrics shown next to the menu bar icon (opt-in).
    static let menuBarCPU = "menuBarCPU"
    static let menuBarGPU = "menuBarGPU"
    static let menuBarMemory = "menuBarMemory"
    static let menuBarCPUTemperature = "menuBarCPUTemperature"
    static let menuBarGPUTemperature = "menuBarGPUTemperature"
    static let menuBarBatteryTemperature = "menuBarBatteryTemperature"
    static let menuBarTemperature = "menuBarTemperature" // legacy Developer key for the old generic temperature metric
    static let menuBarNetwork = "menuBarNetwork"
    static let menuBarDiskUsage = "menuBarDiskUsage"
    static let menuBarDiskActivity = "menuBarDiskActivity"
    static let menuBarBattery = "menuBarBattery"
    static let menuBarBatteryTime = "menuBarBatteryTime"
    static let menuBarPeripheralBattery = "menuBarPeripheralBattery"
    static let menuBarPower = "menuBarPower"
    static let menuBarPreset = "menuBarPreset"           // dense
    static let menuBarMetricSpacing = "menuBarMetricSpacing" // standard | compact
    static let menuBarMetricAppearance = "menuBarMetricAppearance" // values | bars
    static let menuBarUsageBarNormalColor = "menuBarUsageBarNormalColor" // #RRGGBB
    static let menuBarUsageBarElevatedColor = "menuBarUsageBarElevatedColor" // #RRGGBB
    static let menuBarUsageBarCriticalColor = "menuBarUsageBarCriticalColor" // #RRGGBB
    static let menuBarUsageBarMediumThreshold = "menuBarUsageBarMediumThreshold" // percent
    static let menuBarUsageBarHighThreshold = "menuBarUsageBarHighThreshold" // percent
    static let menuBarHideIconWithMetrics = "menuBarHideIconWithMetrics" // glyph hides while metrics render in the main item
    static let menuBarMetricOrder = "menuBarMetricOrder" // comma-separated MenuBarMetric raw values
    static let menuBarCombineTemperatures = "menuBarCombineTemperatures" // usage/charge + temperature in one block when possible
    static let menuBarSeparateMetrics = "menuBarSeparateMetrics" // one status item per active metric
    static let menuBarNetworkUploadFirst = "menuBarNetworkUploadFirst" // network menu bar block shows upload above download
    static let menuBarLabelStyle = "menuBarLabelStyle"     // compact | classic
    static let menuBarMemoryStyle = "menuBarMemoryStyle"   // dot | percent | both
    static let monitorInterval = "monitorIntervalSeconds"  // sampling cadence: 1/2/5
    static let temperatureUnit = "temperatureUnit"          // celsius | fahrenheit
    // System monitor — which blocks appear in the panel.
    static let monitorShowSystem = "monitorShowSystem"
    static let monitorShowNetwork = "monitorShowNetwork"
    static let monitorShowDisk = "monitorShowDisk"
    static let monitorShowPower = "monitorShowPower"
    static let monitorShowMixer = "monitorShowMixer"
    static let monitorShowFanControlBeta = "monitorShowFanControlBeta"
    // System monitor — per-metric history graphs (each independently toggleable).
    static let monitorGraphCPU = "monitorGraphCPU"
    static let monitorGraphGPU = "monitorGraphGPU"
    static let monitorGraphMemory = "monitorGraphMemory"
    static let monitorGraphNetwork = "monitorGraphNetwork"
    static let monitorGraphDisk = "monitorGraphDisk"
    static let monitorGraphPower = "monitorGraphPower"
    static let monitorGraphBattery = "monitorGraphBattery"
    // System monitor — per-item visibility inside each panel section.
    static let monitorSysTemps = "monitorSysTemps"
    static let monitorSysCPU = "monitorSysCPU"
    static let monitorSysGPU = "monitorSysGPU"
    static let monitorSysBattery = "monitorSysBattery"
    static let monitorSysMemory = "monitorSysMemory"
    static let monitorSysAlerts = "monitorSysAlerts"
    static let monitorSysUptime = "monitorSysUptime"
    static let monitorNetSpeed = "monitorNetSpeed"
    static let monitorNetApps = "monitorNetApps"
    static let monitorNetTotals = "monitorNetTotals"
    static let monitorNetTest = "monitorNetTest"
    static let monitorDiskUsage = "monitorDiskUsage"
    static let monitorDiskActivity = "monitorDiskActivity"
    static let monitorDiskSMART = "monitorDiskSMART"
    static let monitorDiskProtection = "monitorDiskProtection"
    static let monitorDiskTools = "monitorDiskTools"
    static let monitorPwrSystem = "monitorPwrSystem"
    static let monitorPwrAdapter = "monitorPwrAdapter"
    static let monitorPwrBattery = "monitorPwrBattery"
    static let monitorPwrTimeRemaining = "monitorPwrTimeRemaining"
    static let monitorPwrHealth = "monitorPwrHealth"
    // System monitor — optional notifications for sustained or actionable conditions.
    static let monitorAlertCPU = "monitorAlertCPU"
    static let monitorAlertCPUTemperature = "monitorAlertCPUTemperature"
    static let monitorAlertMemory = "monitorAlertMemory"
    static let monitorAlertDisk = "monitorAlertDisk"
    static let monitorAlertBattery = "monitorAlertBattery"
    static let monitorAlertCPUThreshold = "monitorAlertCPUThreshold"
    static let monitorAlertCPUTemperatureThreshold = "monitorAlertCPUTemperatureThreshold"
    static let monitorAlertDiskFreePercent = "monitorAlertDiskFreePercent"
    static let monitorAlertBatteryPercent = "monitorAlertBatteryPercent"
    static let monitorAlertCooldownMinutes = "monitorAlertCooldownMinutes"
    // Menu panel layout — the order the major sections appear in and which are
    // collapsed, both comma-joined section ids (see PanelSectionID). Absent keys
    // mean the canonical order and nothing collapsed, so no defaults registration.
    static let panelSectionOrder = "panelSectionOrder"
    static let panelUtilityOrder = "panelUtilityOrder"
    static let panelControlOrder = "panelControlOrder"
    static let panelToggleOrder = "panelToggleOrder"
    static let panelSystemOrder = "panelSystemOrder"
    static let panelNetworkOrder = "panelNetworkOrder"
    static let panelDiskOrder = "panelDiskOrder"
    static let panelPowerOrder = "panelPowerOrder"
    static let panelNavigationEnabled = "panelNavigationEnabled" // legacy: the panel always navigates by sections since 3.1.8
    static let updateLastInstallFailure = "updateLastInstallFailure" // last installer step that failed (fail-copy etc.)
    static let windowLayoutHiddenActions = "windowLayoutHiddenActions" // comma-separated action ids hidden from the grid
    static let panelCollapsedSections = "panelCollapsedSections"
    static let panelCollapsedResetVersion = "panelCollapsedResetVersion"

    // Media utility — local video, GIF, image and OCR tools.
    static let mediaLastTool = "mediaLastTool"
    static let mediaVideoStart = "mediaVideoStart"
    static let mediaVideoEnd = "mediaVideoEnd"
    static let mediaVideoQuality = "mediaVideoQuality"
    static let mediaVideoMaxDimension = "mediaVideoMaxDimension"
    static let mediaVideoFPS = "mediaVideoFPS"
    static let mediaVideoKeepAudio = "mediaVideoKeepAudio"
    static let mediaVideoCodec = "mediaVideoCodec"
    static let mediaGIFStart = "mediaGIFStart"
    static let mediaGIFEnd = "mediaGIFEnd"
    static let mediaGIFQuality = "mediaGIFQuality"
    static let mediaGIFWidth = "mediaGIFWidth"
    static let mediaGIFFPS = "mediaGIFFPS"
    static let mediaGIFLoops = "mediaGIFLoops"
    static let mediaImageQuality = "mediaImageQuality"
    static let mediaImageMaxDimension = "mediaImageMaxDimension"
    static let mediaImageFormat = "mediaImageFormat"
    static let mediaImageStripMetadata = "mediaImageStripMetadata"
    static let mediaTextAccurate = "mediaTextAccurate"
    static let mediaTextLanguageCorrection = "mediaTextLanguageCorrection"

    // Clipboard history — text only, opt-in and local.
    static let clipboardHistoryEnabled = "clipboardHistoryEnabled"
    static let clipboardHistoryEntries = "clipboardHistoryEntries"
    static let clipboardHistoryLimit = "clipboardHistoryLimit"
    static let clipboardHistorySkipSensitive = "clipboardHistorySkipSensitive"
    static let clipboardHistoryIncludeImagesFiles = "clipboardHistoryIncludeImagesFiles" // capture copied images and files too
    // Quick tools: paste as plain text, color picker, screen OCR, mic mute.
    static let pastePlainEnabled = "pastePlainEnabled"
    static let pastePlainShortcut = "pastePlainShortcut"
    static let colorPickerShortcutEnabled = "colorPickerShortcutEnabled"
    static let colorPickerShortcut = "colorPickerShortcut"
    static let colorPickerFormat = "colorPickerFormat"       // hex | rgb | hsl | swiftui
    static let colorPickerBareHex = "colorPickerBareHex"     // copy HEX without the leading #
    static let screenOCRShortcutEnabled = "screenOCRShortcutEnabled"
    static let screenOCRShortcut = "screenOCRShortcut"
    static let screenOCRDetectQRCodes = "screenOCRDetectQRCodes" // QR content wins over OCR text
    static let micMuteShortcutEnabled = "micMuteShortcutEnabled"
    static let micMuteShortcut = "micMuteShortcut"
    static let cameraPreviewShortcutEnabled = "cameraPreviewShortcutEnabled"
    static let cameraPreviewShortcut = "cameraPreviewShortcut"
    static let scratchpadShortcutEnabled = "scratchpadShortcutEnabled"
    static let scratchpadShortcut = "scratchpadShortcut"
    static let scratchpadRetention = "scratchpadRetention"   // never | day | week | month
    static let micMuteActive = "micMuteActive"               // mic muted by the app (survives relaunch)
    static let micMuteSavedVolume = "micMuteSavedVolume"     // input volume to restore on unmute
    static let micMuteMenuBarIndicator = "micMuteMenuBarIndicator" // badge the status icon while muted
    static let quickLauncherShortcutEnabled = "quickLauncherShortcutEnabled"
    static let quickLauncherShortcut = "quickLauncherShortcut"
    static let quickLauncherItemOrder = "quickLauncherItemOrder"
    static let quickLauncherHiddenItems = "quickLauncherHiddenItems"
    static let panelUtilityQuickLauncher = "panelUtilityQuickLauncher"
    static let panelUtilityColorPicker = "panelUtilityColorPicker"
    static let panelUtilityScreenOCR = "panelUtilityScreenOCR"
    static let panelUtilityMicMute = "panelUtilityMicMute"
    static let panelUtilityCameraPreview = "panelUtilityCameraPreview"
    static let panelUtilityScratchpad = "panelUtilityScratchpad"
    static let clipboardHistoryShortcutEnabled = "clipboardHistoryShortcutEnabled"
    static let clipboardHistoryShortcut = "clipboardHistoryShortcut"
    // Screenshot capture and editor.
    static let screenshotShortcutEnabled = "screenshotShortcutEnabled"
    static let screenshotShortcut = "screenshotShortcut"
    static let screenshotFreeze = "screenshotFreeze"
    static let screenshotSaveFolder = "screenshotSaveFolder"
    static let screenshotIncludePointer = "screenshotIncludePointer"
    static let screenshotDownscale = "screenshotDownscale"
    static let screenshotDelay = "screenshotDelay"
    static let screenshotLastTool = "screenshotLastTool"
    static let screenshotLastColor = "screenshotLastColor"
    static let screenshotLastStroke = "screenshotLastStroke"
    static let screenshotLastSticker = "screenshotLastSticker"
    static let screenshotAnnotationShadows = "screenshotAnnotationShadows"
    static let screenshotToolOrder = "screenshotToolOrder"
    static let screenshotToolShortcutsEnabled = "screenshotToolShortcutsEnabled"
    static let screenshotBackdropStyle = "screenshotBackdropStyle"
    static let screenshotBackdropPresets = "screenshotBackdropPresets"
    static let screenshotOpenEditorDirectly = "screenshotOpenEditorDirectly"
    static let panelUtilityScreenshot = "panelUtilityScreenshot"

    // Window Layout — snapping, global shortcuts and optional pointer gestures.
    static let windowLayoutShortcutsEnabled = "windowLayoutShortcutsEnabled"
    static let windowGestureEnabled = "windowGestureEnabled"
    static let windowGestureModifiers = "windowGestureModifiers"
    static let windowGestureRaiseWindow = "windowGestureRaiseWindow"
    static let windowLayoutShortcutLeft = "windowLayoutShortcutLeft"
    static let windowLayoutShortcutRight = "windowLayoutShortcutRight"
    static let windowLayoutShortcutTop = "windowLayoutShortcutTop"
    static let windowLayoutShortcutBottom = "windowLayoutShortcutBottom"
    static let windowLayoutShortcutTopLeft = "windowLayoutShortcutTopLeft"
    static let windowLayoutShortcutTopRight = "windowLayoutShortcutTopRight"
    static let windowLayoutShortcutBottomLeft = "windowLayoutShortcutBottomLeft"
    static let windowLayoutShortcutBottomRight = "windowLayoutShortcutBottomRight"
    static let windowLayoutShortcutMaximize = "windowLayoutShortcutMaximize"
    static let windowLayoutShortcutCenter = "windowLayoutShortcutCenter"
    static let windowLayoutShortcutRestore = "windowLayoutShortcutRestore"
    static let windowLayoutShortcutLeftThird = "windowLayoutShortcutLeftThird"
    static let windowLayoutShortcutCenterThird = "windowLayoutShortcutCenterThird"
    static let windowLayoutShortcutRightThird = "windowLayoutShortcutRightThird"
    static let windowLayoutShortcutLeftTwoThirds = "windowLayoutShortcutLeftTwoThirds"
    static let windowLayoutShortcutRightTwoThirds = "windowLayoutShortcutRightTwoThirds"
    static let windowLayoutShortcutNextDisplay = "windowLayoutShortcutNextDisplay"
    static let windowLayoutShortcutTopLeftSixth = "windowLayoutShortcutTopLeftSixth"
    static let windowLayoutShortcutTopCenterSixth = "windowLayoutShortcutTopCenterSixth"
    static let windowLayoutShortcutTopRightSixth = "windowLayoutShortcutTopRightSixth"
    static let windowLayoutShortcutBottomLeftSixth = "windowLayoutShortcutBottomLeftSixth"
    static let windowLayoutShortcutBottomCenterSixth = "windowLayoutShortcutBottomCenterSixth"
    static let windowLayoutShortcutBottomRightSixth = "windowLayoutShortcutBottomRightSixth"

    // Text snippets: type a trigger, get the expansion.
    static let textSnippetsEnabled = "textSnippetsEnabled"
    static let textSnippets = "textSnippets"              // Data: [TextSnippet] JSON

    // Radial menu: a wheel of actions on a shortcut.
    static let radialMenuEnabled = "radialMenuEnabled"
    static let radialMenuShortcut = "radialMenuShortcut"
    static let radialMenuAtPointer = "radialMenuAtPointer" // false: screen center
    static let radialMenuMouseButton = "radialMenuMouseButton" // RadialMenuMouseTrigger.rawValue
    static let radialMenuItems = "radialMenuItems"        // Data: [RadialMenuItem] JSON

    // Dev-build only: force the "update available" UI for local testing.
    static let simulateUpdate = "simulateUpdate"

    /// Features hub availability layer, one key per AppFeature raw value.
    /// Registered true: unavailable features vanish from every surface and
    /// hold no resources, without ever touching their own enable keys.
    static func featureAvailable(_ id: String) -> String { "featureAvailable.\(id)" }
}

/// Bump `currentFeatureSet` when first-run feature defaults need a quiet marker.
enum OnboardingInfo {
    // 2: system monitor, configurable panel and menu bar metrics.
    // 3: app languages and support settings.
    // 4: navigable menu panel sections.
    static let currentFeatureSet = 4
}

enum DockPreviewIntroInfo {
    static let releaseVersion = "3.0.4"
}

/// The one-time tour of a release's headline features, shown right after the
/// update. Each row deep links to the exact Settings page or opens the tool
/// itself, so a new feature is one click from being tried instead of buried.
enum UpdateHighlightsInfo {
    /// The single release whose first launch shows the tour; any other
    /// version never shows it. Bump deliberately for releases with headline
    /// features worth a tour.
    static let releaseVersion = "3.1.14"

    static func shouldShow(appVersion: String, lastSeenVersion: String?) -> Bool {
        appVersion == releaseVersion && lastSeenVersion != releaseVersion
    }
}

enum SupportUpdateIntroInfo {
    /// The single release whose first launch shows the update intro. It used
    /// to track AppInfo.version, which re-showed the ask on every update; now a
    /// release only shows it when this constant is deliberately bumped.
    static let releaseVersion = "3.1.13"
    static let installCommand = "brew install --cask vorssaint"
    static let migrationCommand = "brew untap --force vorssaint/tap"

    static func shouldShow(appVersion: String, lastSeenVersion: String?) -> Bool {
        appVersion == releaseVersion && lastSeenVersion != releaseVersion
    }
}

enum SupportUpdateIntroStep: Equatable {
    case homebrew
    case community
    case support

    var next: SupportUpdateIntroStep? {
        switch self {
        case .homebrew: return .community
        case .community: return .support
        case .support: return nil
        }
    }

    var previous: SupportUpdateIntroStep? {
        switch self {
        case .homebrew: return nil
        case .community: return .homebrew
        case .support: return .community
        }
    }
}

enum KeepAwakeIconTint: String, CaseIterable, Identifiable {
    case orange, green, blue, purple, pink, none

    var id: String { rawValue }

    static var current: KeepAwakeIconTint {
        Defaults.sanitizedKeepAwakeIconTint(
            UserDefaults.standard.string(forKey: DefaultsKey.keepAwakeIconTint)
        )
    }

    func title(_ strings: Strings) -> String {
        switch self {
        case .orange: return strings.keepAwakeIconTintOrange
        case .green: return strings.keepAwakeIconTintGreen
        case .blue: return strings.keepAwakeIconTintBlue
        case .purple: return strings.keepAwakeIconTintPurple
        case .pink: return strings.keepAwakeIconTintPink
        case .none: return strings.keepAwakeIconTintNone
        }
    }
}

enum KeepAwakeActiveIcon: String, CaseIterable, Identifiable {
    case vorssaint, coffee, eye, moon, light

    var id: String { rawValue }

    static var current: KeepAwakeActiveIcon {
        Defaults.sanitizedKeepAwakeActiveIcon(
            UserDefaults.standard.string(forKey: DefaultsKey.keepAwakeActiveIcon)
        )
    }

    var systemSymbolName: String? {
        switch self {
        case .vorssaint: return nil
        case .coffee: return "cup.and.saucer.fill"
        case .eye: return "eye.fill"
        case .moon: return "moon.fill"
        case .light: return "lightbulb.fill"
        }
    }

    func title(_ strings: Strings) -> String {
        switch self {
        case .vorssaint: return strings.keepAwakeActiveIconVorssaint
        case .coffee: return strings.keepAwakeActiveIconCoffee
        case .eye: return strings.keepAwakeActiveIconEye
        case .moon: return strings.keepAwakeActiveIconMoon
        case .light: return strings.keepAwakeActiveIconLight
        }
    }
}

/// Thumbnail size for the app switcher and Dock preview, scaled from one user
/// preference so both grow together. Captures scale by the same factor, so
/// larger previews stay sharp.
enum PreviewSizing {
    static func sanitized(_ value: String) -> String {
        Defaults.allowedPreviewSizes.contains(value) ? value : "normal"
    }

    static var scale: CGFloat {
        switch sanitized(UserDefaults.standard.string(forKey: DefaultsKey.previewSize) ?? "normal") {
        case "large": return 1.4
        case "xlarge": return 1.8
        default: return 1.0
        }
    }
}

enum Defaults {
    static let finderBundleIdentifier = "com.apple.finder"
    static let mandatoryAutoQuitExceptionBundleIDs = [finderBundleIdentifier]

    static let allowedDurations = [0, 15, 30, 60, 120, 240, 480]
    static let allowedKeepAwakeMouseJiggleIntervals = [1, 2, 5, 10, 15]
    static let allowedBatteryLimits = [0, 5, 10, 15, 20]
    static let allowedMonitorIntervals = [1, 2, 5]
    static let defaultKeyboardDebounceWindowMs = 5
    static let allowedKeyboardDebounceWindowRange = 0...500
    static let allowedMenuBarPresets = ["dense"]
    static let allowedMenuBarMetricSpacings = ["standard", "compact"]
    static let allowedMenuBarMetricAppearances = ["values", "bars"]
    static let defaultMenuBarMetricOrder = [
        "cpu", "cpuTemperature",
        "gpu", "gpuTemperature",
        "memory",
        "battery", "batteryTime", "batteryTemperature", "peripheralBattery",
        "network", "diskUsage", "diskActivity", "power",
    ]
    static let allowedMenuBarLabelStyles = ["compact", "classic"]
    static let allowedMenuBarMemoryStyles = ["dot", "percent", "both"]
    static let allowedPreviewSizes = ["normal", "large", "xlarge"]
    static let allowedClipboardHistoryLimits = [20, 50, 100, 250, 500, 1_000]
    static let allowedMonitorAlertCooldowns = [2, 5, 15, 30, 60]

    static let registeredDefaults: [String: Any] = [
        DefaultsKey.clamshellPreferred: false,
        DefaultsKey.defaultDuration: 0,
        DefaultsKey.batteryLimit: 10,
        DefaultsKey.keepAwakeAutoStart: false,
        DefaultsKey.keepAwakeExternalDisplay: false,
        DefaultsKey.keepAwakeConnectedToPower: false,
        DefaultsKey.keepAwakeMouseJiggleEnabled: false,
        DefaultsKey.keepAwakeMouseJiggleInterval: 5,
        DefaultsKey.hotkeyEnabled: true,
        DefaultsKey.launchAtLoginWanted: false,
        DefaultsKey.keepAwakeShortcut: "control+option+command:40",
        DefaultsKey.keepAwakeIconTint: KeepAwakeIconTint.orange.rawValue,
        DefaultsKey.keepAwakeActiveIcon: KeepAwakeActiveIcon.vorssaint.rawValue,
        DefaultsKey.showCountdown: false,
        DefaultsKey.scrollInverterEnabled: false,
        DefaultsKey.smoothScrollEnabled: false,
        DefaultsKey.smoothScrollStep: 40,
        DefaultsKey.mouseNavigationEnabled: false,
        DefaultsKey.switcherEnabled: true,
        DefaultsKey.switcherShortcut: "command:48",
        DefaultsKey.switcherWindowShortcut: GlobalShortcut.switcherWindowDefault.storageValue,
        DefaultsKey.switcherIconRowMode: false,
        DefaultsKey.switcherSimpleMode: false,
        DefaultsKey.switcherMergeTabs: false,
        DefaultsKey.switcherShowWindowlessFinder: true,
        DefaultsKey.dockPreviewEnabled: false,
        DefaultsKey.dockClickMinimize: false,
        DefaultsKey.dockClickCycleWindows: false,
        DefaultsKey.middleClickEnabled: false,
        DefaultsKey.middleClickTapFingers: 0,
        DefaultsKey.previewSize: "normal",
        DefaultsKey.autoCheckUpdates: true,
        DefaultsKey.releaseNotesOnUpdate: true,
        DefaultsKey.updateShowcaseIntroVersion: "",
        DefaultsKey.updateShowcaseMediaOverride: "",
        DefaultsKey.mixerShowFinder: true,
        DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect: false,
        DefaultsKey.mixerHeadphonesDisconnectVolumePercent: defaultMixerHeadphonesDisconnectVolumePercent,
        DefaultsKey.soundOutputSwitcherEnabled: false,
        DefaultsKey.soundOutputSwitcherShortcut: GlobalShortcut.soundOutputSwitcherDefault.storageValue,
        // Finder never benefits from being "quit" (it just relaunches), so
        // it's excepted out of the box.
        DefaultsKey.autoQuitExceptions: mandatoryAutoQuitExceptionBundleIDs,
        // When the shelf is on, the shake gesture is on too (still toggleable).
        DefaultsKey.shelfShortcutEnabled: true,
        DefaultsKey.shelfShortcut: "control+option+command:2",
        DefaultsKey.shelfShakeToOpen: true,
        // On by default (owner's call): it costs nothing until the shelf itself
        // is on, and then the shelf lives handily under the menu bar icon.
        DefaultsKey.shelfDropZoneEnabled: true,
        // Closing after a drop is new behavior, so it arrives OFF for people
        // who already rely on the panel staying put; removing after a drop
        // keeps the value shipped releases always had.
        DefaultsKey.shelfCloseAfterDrop: false,
        DefaultsKey.shelfRemoveAfterDrop: true,
        DefaultsKey.shelfAutomaticExclusions: [],
        DefaultsKey.extraBrightnessEnabled: false,
        DefaultsKey.extraBrightnessLevel: 100,
        DefaultsKey.brightnessControlEnabled: false,
        DefaultsKey.brightnessKeysEnabled: false,
        DefaultsKey.brightnessOSDEnabled: false,
        DefaultsKey.musicBlockEnabled: false,
        DefaultsKey.musicBlockReplacementPath: "",
        DefaultsKey.cleanerScheduleFrequency: "off",
        DefaultsKey.cleanerScheduleHour: 9,
        DefaultsKey.cleanerScheduleMinute: 0,
        DefaultsKey.cleanerScheduleWeekday: 2,
        DefaultsKey.cleanerScheduleNotify: true,
        DefaultsKey.cleanerLastAutoRun: 0.0,
        DefaultsKey.cleanerLastAutoFreed: 0,
        DefaultsKey.cleanerBadgeSeen: false,
        DefaultsKey.urlCleanerEnabled: false,
        DefaultsKey.textSnippetsEnabled: false,
        DefaultsKey.radialMenuEnabled: false,
        DefaultsKey.radialMenuShortcut: GlobalShortcut.radialMenuDefault.storageValue,
        DefaultsKey.radialMenuAtPointer: true,
        DefaultsKey.radialMenuMouseButton: RadialMenuMouseTrigger.off.rawValue,
        DefaultsKey.windowMaximizeEnabled: false,
        DefaultsKey.keyboardDebounceEnabled: false,
        DefaultsKey.keyboardDebounceWindowMs: defaultKeyboardDebounceWindowMs,
        DefaultsKey.keyboardDebounceKeyWindows: "",
        DefaultsKey.panelUtilityCleaning: true,
        DefaultsKey.panelUtilityURLCleaner: true,
        DefaultsKey.panelUtilityUninstaller: true,
        DefaultsKey.panelUtilityCleaner: true,
        DefaultsKey.panelUtilityHomebrew: true,
        DefaultsKey.panelUtilityMedia: true,
        DefaultsKey.panelUtilityClipboard: true,
        DefaultsKey.panelUtilityWindowLayout: true,
        DefaultsKey.panelControlMouseScroll: true,
        DefaultsKey.panelControlMouseNavigation: true,
        DefaultsKey.panelControlSwitcher: true,
        DefaultsKey.panelControlDockPreview: true,
        DefaultsKey.panelControlCutPaste: true,
        DefaultsKey.panelControlAutoQuit: true,
        DefaultsKey.panelControlShelf: true,
        DefaultsKey.panelControlWindowMaximize: true,
        DefaultsKey.panelControlKeyDebounce: true,
        DefaultsKey.panelControlDockClick: true,
        DefaultsKey.panelControlDockClickCycle: true,
        DefaultsKey.panelControlMiddleClick: true,
        DefaultsKey.panelControlTextSnippets: true,
        DefaultsKey.panelControlRadialMenu: true,
        DefaultsKey.panelControlWindowsExpanded: false,
        DefaultsKey.panelControlInputExpanded: false,
        DefaultsKey.panelControlFilesExpanded: false,
        DefaultsKey.panelShowKeepAwake: true,
        DefaultsKey.panelShowBrightness: true,
        DefaultsKey.panelShowUtilities: true,
        DefaultsKey.panelShowControls: true,
        DefaultsKey.panelShowToggles: true,
        DefaultsKey.panelToggleDarkMode: true,
        DefaultsKey.panelToggleEmptyTrash: true,
        DefaultsKey.panelToggleEjectDisks: true,
        DefaultsKey.panelToggleHiddenFiles: true,
        DefaultsKey.panelToggleDesktopIcons: true,
        DefaultsKey.panelToggleLockScreen: true,
        DefaultsKey.panelToggleDisplayOff: true,
        DefaultsKey.panelToggleScreenSaver: true,
        // Menu bar metrics start off (the icon stays clean) and are opt-in.
        // The panel shows every monitoring block by default; users hide what
        // they don't want.
        DefaultsKey.monitorInterval: 2,
        DefaultsKey.temperatureUnit: TemperatureUnit.celsius.rawValue,
        DefaultsKey.menuBarCPUTemperature: false,
        DefaultsKey.menuBarGPUTemperature: false,
        DefaultsKey.menuBarBatteryTemperature: false,
        DefaultsKey.menuBarBatteryTime: false,
        DefaultsKey.menuBarDiskUsage: false,
        DefaultsKey.menuBarDiskActivity: false,
        DefaultsKey.menuBarPeripheralBattery: false,
        DefaultsKey.menuBarPreset: "dense",
        DefaultsKey.menuBarMetricSpacing: "compact",  // owner's call: compact by default in 3.1.8
        DefaultsKey.menuBarMetricAppearance: "values",
        DefaultsKey.menuBarUsageBarNormalColor: "#64D2FF",
        DefaultsKey.menuBarUsageBarElevatedColor: "#FFD60A",
        DefaultsKey.menuBarUsageBarCriticalColor: "#FF453A",
        DefaultsKey.menuBarUsageBarMediumThreshold: 70,
        DefaultsKey.menuBarUsageBarHighThreshold: 90,
        DefaultsKey.menuBarHideIconWithMetrics: false,
        DefaultsKey.windowLayoutHiddenActions: "",
        DefaultsKey.menuBarMetricOrder: defaultMenuBarMetricOrder.joined(separator: ","),
        DefaultsKey.menuBarCombineTemperatures: true,
        DefaultsKey.menuBarSeparateMetrics: false,
        DefaultsKey.menuBarNetworkUploadFirst: false,
        DefaultsKey.menuBarLabelStyle: "compact",
        DefaultsKey.menuBarMemoryStyle: "percent",
        DefaultsKey.monitorShowSystem: true,
        DefaultsKey.monitorShowNetwork: true,
        DefaultsKey.monitorShowDisk: true,
        DefaultsKey.monitorShowPower: true,
        DefaultsKey.monitorShowMixer: true,
        DefaultsKey.monitorShowFanControlBeta: false,
        DefaultsKey.panelNavigationEnabled: true,
        DefaultsKey.monitorGraphCPU: true,
        DefaultsKey.monitorGraphGPU: true,
        DefaultsKey.monitorGraphMemory: true,
        DefaultsKey.monitorGraphNetwork: true,
        DefaultsKey.monitorGraphDisk: true,
        DefaultsKey.monitorGraphPower: true,
        DefaultsKey.monitorGraphBattery: true,
        // Every per-item block shows by default; users hide what they don't want.
        DefaultsKey.monitorSysTemps: true,
        DefaultsKey.monitorSysCPU: true,
        DefaultsKey.monitorSysGPU: true,
        DefaultsKey.monitorSysBattery: true,
        DefaultsKey.monitorSysMemory: true,
        DefaultsKey.monitorSysAlerts: true,
        DefaultsKey.monitorSysUptime: true,
        DefaultsKey.monitorNetSpeed: true,
        DefaultsKey.monitorNetApps: true,
        DefaultsKey.monitorNetTotals: true,
        DefaultsKey.monitorNetTest: true,
        DefaultsKey.monitorDiskUsage: true,
        DefaultsKey.monitorDiskActivity: true,
        DefaultsKey.monitorDiskSMART: true,
        DefaultsKey.monitorDiskProtection: true,
        DefaultsKey.monitorDiskTools: true,
        DefaultsKey.monitorPwrSystem: true,
        DefaultsKey.monitorPwrAdapter: true,
        DefaultsKey.monitorPwrBattery: true,
        DefaultsKey.monitorPwrTimeRemaining: true,
        DefaultsKey.monitorPwrHealth: true,
        DefaultsKey.monitorAlertCPU: false,
        DefaultsKey.monitorAlertCPUTemperature: false,
        DefaultsKey.monitorAlertMemory: false,
        DefaultsKey.monitorAlertDisk: false,
        DefaultsKey.monitorAlertBattery: false,
        DefaultsKey.monitorAlertCPUThreshold: 90,
        DefaultsKey.monitorAlertCPUTemperatureThreshold: 90,
        DefaultsKey.monitorAlertDiskFreePercent: 10,
        DefaultsKey.monitorAlertBatteryPercent: 15,
        DefaultsKey.monitorAlertCooldownMinutes: 15,
        DefaultsKey.mediaLastTool: MediaTool.videoCompressor.rawValue,
        DefaultsKey.mediaVideoStart: 0.0,
        DefaultsKey.mediaVideoEnd: 0.0,
        DefaultsKey.mediaVideoQuality: 0.68,
        DefaultsKey.mediaVideoMaxDimension: 1280,
        DefaultsKey.mediaVideoFPS: 30.0,
        DefaultsKey.mediaVideoKeepAudio: true,
        DefaultsKey.mediaVideoCodec: MediaVideoCodec.h264.rawValue,
        DefaultsKey.mediaGIFStart: 0.0,
        DefaultsKey.mediaGIFEnd: 0.0,
        DefaultsKey.mediaGIFQuality: 0.74,
        DefaultsKey.mediaGIFWidth: 720,
        DefaultsKey.mediaGIFFPS: 12.0,
        DefaultsKey.mediaGIFLoops: true,
        DefaultsKey.mediaImageQuality: 0.72,
        DefaultsKey.mediaImageMaxDimension: 1600,
        DefaultsKey.mediaImageFormat: MediaImageFormat.jpeg.rawValue,
        DefaultsKey.mediaImageStripMetadata: true,
        DefaultsKey.mediaTextAccurate: true,
        DefaultsKey.mediaTextLanguageCorrection: true,
        DefaultsKey.clipboardHistoryEnabled: false,
        DefaultsKey.clipboardHistoryLimit: 50,
        DefaultsKey.clipboardHistorySkipSensitive: true,
        DefaultsKey.clipboardHistoryIncludeImagesFiles: true,
        DefaultsKey.pastePlainEnabled: false,
        DefaultsKey.pastePlainShortcut: GlobalShortcut.pastePlainDefault.storageValue,
        DefaultsKey.colorPickerShortcutEnabled: false,
        DefaultsKey.colorPickerShortcut: GlobalShortcut.colorPickerDefault.storageValue,
        DefaultsKey.colorPickerFormat: "hex",
        DefaultsKey.colorPickerBareHex: false,
        DefaultsKey.screenOCRShortcutEnabled: false,
        DefaultsKey.screenOCRShortcut: GlobalShortcut.screenOCRDefault.storageValue,
        DefaultsKey.screenOCRDetectQRCodes: true,
        DefaultsKey.micMuteShortcutEnabled: false,
        DefaultsKey.micMuteShortcut: GlobalShortcut.micMuteDefault.storageValue,
        DefaultsKey.cameraPreviewShortcutEnabled: false,
        DefaultsKey.cameraPreviewShortcut: GlobalShortcut.cameraPreviewDefault.storageValue,
        DefaultsKey.scratchpadShortcutEnabled: false,
        DefaultsKey.scratchpadShortcut: GlobalShortcut.scratchpadDefault.storageValue,
        DefaultsKey.scratchpadRetention: ScratchpadRetention.never.rawValue,
        DefaultsKey.micMuteActive: false,
        DefaultsKey.micMuteSavedVolume: 0.75,
        DefaultsKey.micMuteMenuBarIndicator: true,  // owner's call: on by default in 3.1.8 (badge only shows while muted)
        DefaultsKey.quickLauncherShortcutEnabled: true,
        DefaultsKey.quickLauncherShortcut: GlobalShortcut.quickLauncherDefault.storageValue,
        DefaultsKey.quickLauncherHiddenItems: "",
        DefaultsKey.panelUtilityQuickLauncher: true,
        DefaultsKey.panelUtilityColorPicker: true,
        DefaultsKey.panelUtilityScreenOCR: true,
        DefaultsKey.panelUtilityMicMute: true,
        DefaultsKey.panelUtilityCameraPreview: true,
        DefaultsKey.panelUtilityScratchpad: true,
        DefaultsKey.clipboardHistoryShortcutEnabled: true,
        DefaultsKey.clipboardHistoryShortcut: GlobalShortcut.clipboardDefault.storageValue,
        DefaultsKey.screenshotShortcutEnabled: false,
        DefaultsKey.screenshotShortcut: GlobalShortcut.screenshotDefault.storageValue,
        DefaultsKey.screenshotFreeze: true,
        DefaultsKey.screenshotSaveFolder: "",
        DefaultsKey.screenshotIncludePointer: false,
        DefaultsKey.screenshotDownscale: false,
        DefaultsKey.screenshotDelay: 0,
        DefaultsKey.screenshotLastTool: "arrow",
        DefaultsKey.screenshotLastColor: "red",
        DefaultsKey.screenshotLastStroke: "medium",
        DefaultsKey.screenshotLastSticker: "check",
        DefaultsKey.screenshotAnnotationShadows: false,
        DefaultsKey.screenshotToolOrder: ScreenshotSupport.Tool.defaultOrderStorage,
        DefaultsKey.screenshotToolShortcutsEnabled: true,
        DefaultsKey.screenshotBackdropStyle: "",
        DefaultsKey.screenshotBackdropPresets: "[]",
        DefaultsKey.screenshotOpenEditorDirectly: false,
        DefaultsKey.panelUtilityScreenshot: true,
        DefaultsKey.windowLayoutShortcutsEnabled: false,
        DefaultsKey.windowGestureEnabled: false,
        DefaultsKey.windowGestureModifiers: WindowGestureSupport.defaultModifierStorageValue,
        DefaultsKey.windowGestureRaiseWindow: false,
        DefaultsKey.windowLayoutShortcutLeft: GlobalShortcut.windowLayoutLeftDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRight: GlobalShortcut.windowLayoutRightDefault.storageValue,
        DefaultsKey.windowLayoutShortcutTop: GlobalShortcut.windowLayoutTopDefault.storageValue,
        DefaultsKey.windowLayoutShortcutBottom: GlobalShortcut.windowLayoutBottomDefault.storageValue,
        DefaultsKey.windowLayoutShortcutTopLeft: GlobalShortcut.windowLayoutTopLeftDefault.storageValue,
        DefaultsKey.windowLayoutShortcutTopRight: GlobalShortcut.windowLayoutTopRightDefault.storageValue,
        DefaultsKey.windowLayoutShortcutBottomLeft: GlobalShortcut.windowLayoutBottomLeftDefault.storageValue,
        DefaultsKey.windowLayoutShortcutBottomRight: GlobalShortcut.windowLayoutBottomRightDefault.storageValue,
        DefaultsKey.windowLayoutShortcutMaximize: GlobalShortcut.windowLayoutMaximizeDefault.storageValue,
        DefaultsKey.windowLayoutShortcutCenter: GlobalShortcut.windowLayoutCenterDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRestore: GlobalShortcut.windowLayoutRestoreDefault.storageValue,
        DefaultsKey.windowLayoutShortcutLeftThird: GlobalShortcut.windowLayoutLeftThirdDefault.storageValue,
        DefaultsKey.windowLayoutShortcutCenterThird: GlobalShortcut.windowLayoutCenterThirdDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRightThird: GlobalShortcut.windowLayoutRightThirdDefault.storageValue,
        DefaultsKey.windowLayoutShortcutLeftTwoThirds: GlobalShortcut.windowLayoutLeftTwoThirdsDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRightTwoThirds: GlobalShortcut.windowLayoutRightTwoThirdsDefault.storageValue,
        DefaultsKey.windowLayoutShortcutNextDisplay: GlobalShortcut.windowLayoutNextDisplayDefault.storageValue,
        DefaultsKey.windowLayoutShortcutTopLeftSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopCenterSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopRightSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomLeftSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomCenterSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomRightSixth: WindowLayoutAction.clearedShortcutStorageValue,
    ]

    static func register() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: registeredDefaults)
        defaults.register(defaults: AppFeature.availabilityDefaults)
        migrateLegacyMenuBarTemperatureMetric(in: defaults)
        migrateLegacySwitcherWindowShortcut(in: defaults)
        migrateLegacyKeyboardDebounceWindow(in: defaults)
        migrateUtilityOrderForScreenshot(in: defaults)
        migrateSilentHeadphonesDisconnectVolume(in: defaults)
    }

    static func migrateLegacySwitcherWindowShortcut(in defaults: UserDefaults) {
        let wrongDeveloperDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave),
                                                   modifiers: [.control, .option, .command]).storageValue
        guard defaults.string(forKey: DefaultsKey.switcherWindowShortcut) == wrongDeveloperDefault else {
            return
        }
        defaults.set(GlobalShortcut.switcherWindowDefault.storageValue,
                     forKey: DefaultsKey.switcherWindowShortcut)
    }

    static func migrateLegacyKeyboardDebounceWindow(in defaults: UserDefaults) {
        guard let storedWindow = defaults.object(forKey: DefaultsKey.keyboardDebounceWindowMs) as? Int,
              storedWindow == 30 || storedWindow == 10,
              defaults.bool(forKey: DefaultsKey.keyboardDebounceEnabled) == false,
              (defaults.string(forKey: DefaultsKey.keyboardDebounceKeyWindows) ?? "").isEmpty
        else { return }
        defaults.set(defaultKeyboardDebounceWindowMs, forKey: DefaultsKey.keyboardDebounceWindowMs)
    }

    static func migrateUtilityOrderForScreenshot(in defaults: UserDefaults) {
        guard let storedOrder = defaults.object(forKey: DefaultsKey.panelUtilityOrder) as? String else {
            return
        }
        let ids = storedOrder.split(separator: ",").map(String.init)
        guard !ids.contains("screenshot") else { return }
        defaults.set((["screenshot"] + ids).joined(separator: ","),
                     forKey: DefaultsKey.panelUtilityOrder)
    }

    static func sanitizedDefaultDuration(_ minutes: Int) -> Int {
        allowedDurations.contains(minutes) ? minutes : 0
    }

    static func sanitizedBatteryLimit(_ percent: Int) -> Int {
        allowedBatteryLimits.contains(percent) ? percent : 10
    }

    static func sanitizedKeepAwakeMouseJiggleInterval(_ minutes: Int) -> Int {
        allowedKeepAwakeMouseJiggleIntervals.contains(minutes) ? minutes : 5
    }

    static func sanitizedKeepAwakeIconTint(_ rawValue: String?) -> KeepAwakeIconTint {
        guard let rawValue,
              let tint = KeepAwakeIconTint(rawValue: rawValue) else {
            return .orange
        }
        return tint
    }

    static func sanitizedKeepAwakeActiveIcon(_ rawValue: String?) -> KeepAwakeActiveIcon {
        guard let rawValue,
              let icon = KeepAwakeActiveIcon(rawValue: rawValue) else {
            return .vorssaint
        }
        return icon
    }

    static func sanitizedMonitorInterval(_ seconds: Int) -> Int {
        allowedMonitorIntervals.contains(seconds) ? seconds : 2
    }

    /// Tap-to-middle-click accepts exactly three or four fingers; anything
    /// else means the option is off.
    static func sanitizedMiddleClickTapFingers(_ raw: Int) -> Int {
        raw == 3 || raw == 4 ? raw : 0
    }

    static func sanitizedKeyboardDebounceWindow(_ milliseconds: Int) -> Int {
        allowedKeyboardDebounceWindowRange.contains(milliseconds)
            ? milliseconds
            : defaultKeyboardDebounceWindowMs
    }

    static func sanitizedMenuBarPreset(_ preset: String) -> String {
        allowedMenuBarPresets.contains(preset) ? preset : "dense"
    }

    static func sanitizedMenuBarMetricSpacing(_ spacing: String) -> String {
        // Corrupt values fall back to the registered default (compact).
        allowedMenuBarMetricSpacings.contains(spacing) ? spacing : "compact"
    }

    static func sanitizedMenuBarMetricAppearance(_ appearance: String) -> String {
        allowedMenuBarMetricAppearances.contains(appearance) ? appearance : "values"
    }

    static func sanitizedMenuBarMetricOrder(_ raw: String) -> [String] {
        let defaults = defaultMenuBarMetricOrder
        var seen = Set<String>()
        var result: [String] = []
        for rawValue in raw.split(separator: ",").map({ String($0) }) {
            let values = rawValue == "temperature"
                ? ["cpuTemperature", "gpuTemperature", "batteryTemperature"]
                : [rawValue]
            for value in values {
                guard defaults.contains(value), !seen.contains(value) else { continue }
                seen.insert(value)
                result.append(value)
            }
        }
        for value in defaults where !seen.contains(value) {
            result.append(value)
        }
        return result
    }

    private static func migrateLegacyMenuBarTemperatureMetric(in defaults: UserDefaults) {
        guard let domainName = Bundle.main.bundleIdentifier,
              let domain = defaults.persistentDomain(forName: domainName),
              let legacyEnabled = domain[DefaultsKey.menuBarTemperature] as? Bool
        else { return }

        let newKeys = [
            DefaultsKey.menuBarCPUTemperature,
            DefaultsKey.menuBarGPUTemperature,
            DefaultsKey.menuBarBatteryTemperature,
        ]
        let alreadyMigrated = newKeys.contains { domain[$0] != nil }
        if legacyEnabled, !alreadyMigrated {
            for key in newKeys {
                defaults.set(true, forKey: key)
            }
        }
        if let rawOrder = domain[DefaultsKey.menuBarMetricOrder] as? String {
            defaults.set(sanitizedMenuBarMetricOrder(rawOrder).joined(separator: ","),
                         forKey: DefaultsKey.menuBarMetricOrder)
        }
        defaults.removeObject(forKey: DefaultsKey.menuBarTemperature)
    }

    static func sanitizedMenuBarLabelStyle(_ style: String) -> String {
        allowedMenuBarLabelStyles.contains(style) ? style : "compact"
    }

    static func sanitizedMenuBarMemoryStyle(_ style: String) -> String {
        allowedMenuBarMemoryStyles.contains(style) ? style : "percent"
    }

    static func sanitizedClipboardHistoryLimit(_ value: Int) -> Int {
        allowedClipboardHistoryLimits.contains(value) ? value : 50
    }

    static func sanitizedMonitorAlertCooldown(_ value: Int) -> Int {
        allowedMonitorAlertCooldowns.contains(value) ? value : 15
    }

    static func sanitizedPercent(_ value: Int, fallback: Int, range: ClosedRange<Int>) -> Int {
        range.contains(value) ? value : fallback
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

    static func sanitizedPanelItemOrder(_ raw: String, defaultOrder: [String]) -> [String] {
        let allowed = Set(defaultOrder)
        var seen = Set<String>()
        var result: [String] = []
        for id in raw.split(separator: ",").map(String.init) {
            guard allowed.contains(id), seen.insert(id).inserted else { continue }
            result.append(id)
        }
        for id in defaultOrder where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    static func sanitizedAppVolume(_ volume: Double) -> Double {
        guard volume.isFinite else { return 1 }
        return min(max(volume, 0), 2)
    }

    /// The volume the speakers are set to when headphones disconnect. It is a
    /// protection against a sudden blast, not a mute, so it never goes low
    /// enough to leave the sound inaudible.
    static let minimumMixerHeadphonesDisconnectVolumePercent = 10
    static let defaultMixerHeadphonesDisconnectVolumePercent = 25

    static func sanitizedMixerHeadphonesDisconnectVolumePercent(_ percent: Int) -> Int {
        min(max(percent, minimumMixerHeadphonesDisconnectVolumePercent), 100)
    }

    /// The option shipped with a stored value of 0, so ticking the box without
    /// touching the stepper silenced the speakers on the next disconnect. A
    /// value below the floor becomes the sane default.
    static func migrateSilentHeadphonesDisconnectVolume(in defaults: UserDefaults) {
        guard let stored = defaults.object(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent) as? Int,
              stored < minimumMixerHeadphonesDisconnectVolumePercent else { return }
        defaults.set(defaultMixerHeadphonesDisconnectVolumePercent,
                     forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
    }

    static func sanitizedAppOutputDeviceUID(_ value: Any?) -> String? {
        MixerRoutingSupport.sanitizedDeviceUID(value)
    }

    static func sanitizedAppOutputDevices(_ raw: [String: Any]) -> [String: String] {
        MixerRoutingSupport.sanitizedRouteMap(raw)
    }

    static func sanitizedSoundOutputSwitcherDeviceUIDs(_ raw: [Any]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in raw {
            guard let uid = MixerRoutingSupport.sanitizedDeviceUID(value),
                  seen.insert(uid).inserted else { continue }
            result.append(uid)
        }
        return result
    }

    static func sanitizedPreferredInputDeviceUID(_ value: Any?) -> String? {
        MixerRoutingSupport.sanitizedDeviceUID(value)
    }
}
