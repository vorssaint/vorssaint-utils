// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One Settings page as the sidebar and the command bar present it.
struct SettingsDirectoryItem: Identifiable {
    let page: SettingsPage
    let title: String
    let icon: String
    /// Labels of options living inside the page, so a search finds a page by
    /// what it contains, in the user's language.
    var keywords: [String] = []
    var id: SettingsPage { page }
}

/// The single map of the Settings window: sections, pages, icons and search
/// keywords. The sidebar renders it; the command bar searches it. One list,
/// so a page added here is findable everywhere at once.
enum SettingsDirectory {
    static func sections(_ s: Strings,
                         language: AppLanguage,
                         superKeySource: SuperKeySource = SuperKeyService.shared.source)
        -> [(title: String, items: [SettingsDirectoryItem])] {
        let categories = FeatureStrings.settingsCategories(language)
        return [
            (categories.essentials, [
                SettingsDirectoryItem(page: .general, title: s.tabGeneral, icon: "gearshape",
                                      keywords: [s.launchAtLogin, s.languageLabel, s.showMenuBarIcon,
                                                 s.musicBlockTitle, s.musicBlockSection,
                                                 FeatureStrings.appearance(language).label,
                                                 FeatureStrings.appearance(language).dark]),
                // Searching any feature name lands here even when the feature
                // is hidden, so the hub is always the way back.
                SettingsDirectoryItem(page: .features, title: FeatureStrings.hub(language).pageTitle,
                                      icon: "square.grid.2x2",
                                      keywords: AppFeature.allCases.map {
                                          $0.hubTitle(s, hub: FeatureStrings.hub(language))
                                      }),
                SettingsDirectoryItem(page: .energy, title: s.tabEnergy, icon: "bolt.fill",
                                      keywords: [s.keepAwakeTitle, s.clamshellTitle,
                                                 s.defaultDurationLabel, s.showCountdown,
                                                 s.extraBrightnessName,
                                                 s.keepAwakeActiveIconLabel,
                                                 s.keepAwakeActiveIconCoffee,
                                                 s.keepAwakeActiveIconEye,
                                                 FeatureStrings.brightness(language).pageTitle,
                                                 FeatureStrings.brightness(language).osdToggle,
                                                 FeatureStrings.keepAwakeAutomation(language)
                                                     .externalDisplayToggle,
                                                 FeatureStrings.keepAwakeAutomation(language).powerToggle,
                                                 FeatureStrings.keepAwakeDisplaySleep(language)
                                                     .allowDisplaySleep,
                                                 FeatureStrings.bluetoothSleep(language).pageTitle,
                                                 FeatureStrings.bluetoothSleep(language).enable]),
                SettingsDirectoryItem(page: .monitor, title: s.tabMonitor, icon: "chart.line.uptrend.xyaxis",
                                      keywords: [s.menuBarSpacingLabel, s.menuBarHideIconToggle,
                                                 s.monitorMemoryPressureDot,
                                                 FeatureStrings.fanControl(language).menuBarTitle]),
            ]),
            (categories.windowsControls, [
                SettingsDirectoryItem(page: .mouse, title: s.tabMouse, icon: "computermouse",
                                      keywords: [s.invertMouseScroll, s.invertVerticalScroll,
                                                 s.invertHorizontalScroll, s.middleClickTapPicker,
                                                 s.focusFollowsMouseName, s.focusFollowsMouseDelay,
                                                 s.smoothScrollName, s.mouseNavigationEnable,
                                                 FeatureStrings.mouseButtons(language).pageTitle,
                                                 FeatureStrings.mouseButtons(language).sideWheelLeftName,
                                                 FeatureStrings.mouseButtons(language).sideWheelRightName,
                                                 FeatureStrings.mouseExceptions(language).listTitle]),
                SettingsDirectoryItem(page: .switcher, title: s.tabSwitcher, icon: "rectangle.on.rectangle",
                                      keywords: [s.switcherEnable, s.dockClickMinimize, s.dockClickHide,
                                                 s.dockClickCycleWindows, s.switcherWindowlessApps,
                                                 s.switcherShowShortcutHints,
                                                 FeatureStrings.switcherAppRules(language).listTitle,
                                                 FeatureStrings.switcherAppRules(language).showWithoutWindows,
                                                 FeatureStrings.switcherAppRules(language).windowsOnly,
                                                 FeatureStrings.switcherAppRules(language).hidden,
                                                 FeatureStrings.windowPreviewExclusions(language).listTitle]),
                SettingsDirectoryItem(page: .windowLayout,
                                      title: FeatureStrings.windowLayout(language).title,
                                      icon: "rectangle.3.group",
                                      keywords: [s.dockClickCycleWindows,
                                                 FeatureStrings.windowLayout(language).edgeSnapEnable,
                                                 FeatureStrings.windowLayout(language).gestureEnable,
                                                 FeatureStrings.windowLayout(language).gestureResize]),
                SettingsDirectoryItem(page: .autoQuit, title: s.autoQuitName, icon: "xmark.rectangle",
                                      keywords: [s.autoQuitEnable]),
            ]),
            (categories.files, [
                SettingsDirectoryItem(page: .clipboard, title: FeatureStrings.clipboard(language).title,
                                      icon: "doc.on.clipboard",
                                      keywords: [FeatureStrings.clipboard(language).limit,
                                                 FeatureStrings.clipboard(language).skipSensitive,
                                                 FeatureStrings.clipboard(language).pasteImageAsFile,
                                                 FeatureStrings.clipboard(language).autoClearEnable,
                                                 FeatureStrings.clipboard(language).autoClearOnSleep,
                                                 FeatureStrings.clipboard(language).autoClearOnDisplaySleep,
                                                 FeatureStrings.clipboard(language).autoClearOnScreenLock,
                                                 FeatureStrings.clipboardIgnoredApps(language).listTitle]),
                SettingsDirectoryItem(page: .cutPaste,
                                      title: FeatureStrings.finderRename(language).pageTitle,
                                      icon: "filemenu.and.selection",
                                      keywords: [s.cutPasteEnable,
                                                 FeatureStrings.finderRename(language).enableLabel]),
                SettingsDirectoryItem(page: .shelf, title: s.shelfName, icon: "tray.full",
                                      keywords: [s.shelfEnable, s.shelfDropZoneToggle, s.shelfEdgeToggle]),
                SettingsDirectoryItem(page: .media, title: s.mediaName, icon: "photo.on.rectangle.angled",
                                      keywords: ["PDF", "GIF", "PNG", "JPEG", "convert", "resize", "watermark",
                                                 "rename", "profile", "fit", "fill", "crop",
                                                 s.mediaStartConvertPDF, s.ocrName]),
            ]),
            // Everything about the apps installed on the Mac lives together:
            // what is out of date, what is junk and what should go.
            (categories.appManagement, [
                SettingsDirectoryItem(page: .appUpdates,
                                      title: FeatureStrings.appUpdates(language).pageTitle,
                                      icon: "arrow.down.app",
                                      keywords: [FeatureStrings.appUpdates(language).checkNow,
                                                 FeatureStrings.appUpdates(language).frequencyLabel,
                                                 FeatureStrings.appUpdates(language).appStoreBadge,
                                                 s.homebrewName]),
                SettingsDirectoryItem(page: .cleaner, title: s.cleanerName, icon: "sparkles",
                                      keywords: [s.cleanerScheduleTitle,
                                                 FeatureStrings.whatsAppDownloads(language).title,
                                                 FeatureStrings.whatsAppDownloads(language).automatic,
                                                 FeatureStrings.whatsAppDownloads(language).fileTypes]),
                SettingsDirectoryItem(page: .homebrew, title: s.homebrewName, icon: "shippingbox"),
                SettingsDirectoryItem(page: .uninstaller, title: s.uninstallerName, icon: "trash"),
                SettingsDirectoryItem(page: .killProcess,
                                      title: FeatureStrings.killProcess(language).pageTitle,
                                      icon: "xmark.octagon",
                                      keywords: ["force quit", "process", "cpu", "memory", "kill"]),
            ]),
            (categories.utilities, [
                SettingsDirectoryItem(page: .commandBar,
                                      title: FeatureStrings.commandBar(language).pageTitle,
                                      icon: "command",
                                      keywords: [FeatureStrings.commandBar(language).openButton,
                                                 FeatureStrings.commandBar(language).searchPlaceholder]),
                SettingsDirectoryItem(page: .quickTools, title: s.quickToolsTab, icon: "wand.and.rays",
                                      keywords: [s.launcherName, s.micMuteName,
                                                 s.micMuteMenuBarToggle,
                                                 FeatureStrings.quickToggles(language).pageTitle,
                                                 FeatureStrings.quickToggles(language).darkModeToDark,
                                                 FeatureStrings.quickToggles(language).emptyTrashTitle,
                                                 FeatureStrings.brightness(language).keyboardLight,
                                                 FeatureStrings.cameraPreview(language).pageTitle,
                                                 FeatureStrings.scratchpad(language).pageTitle]),
                SettingsDirectoryItem(page: .screenshot,
                                      title: FeatureStrings.screenshot(language).screenCaptureTitle,
                                      icon: "camera.viewfinder",
                                      keywords: SettingsSearchSupport.screenCaptureKeywords(
                                        s, language: language)),
                SettingsDirectoryItem(page: .urlCleaner, title: s.urlCleanerName, icon: "link"),
                SettingsDirectoryItem(page: .keyDebounce, title: s.keyDebounceName, icon: "keyboard"),
                SettingsDirectoryItem(page: .superKey,
                                      title: FeatureStrings.superKey(language).pageTitle,
                                      icon: superKeySource.systemImage,
                                      keywords: SuperKeySource.allCases.map {
                                          FeatureStrings.superKey(language).sourceLabel($0)
                                      }),
                SettingsDirectoryItem(page: .textSnippets,
                                      title: FeatureStrings.snippets(language).pageTitle,
                                      icon: "text.append",
                                      keywords: [FeatureStrings.snippets(language).triggerLabel,
                                                 FeatureStrings.snippets(language).addButton]),
                SettingsDirectoryItem(page: .radialMenu,
                                      title: FeatureStrings.radialMenu(language).pageTitle,
                                      icon: "circle.grid.cross",
                                      keywords: [FeatureStrings.radialMenu(language).addButton,
                                                 FeatureStrings.radialMenu(language).kindApp,
                                                 FeatureStrings.radialMenu(language).kindMedia,
                                                 FeatureStrings.radialMenu(language).kindSubmenu]),
            ]),
            (categories.app, [
                SettingsDirectoryItem(page: .shortcuts, title: s.shortcutsPageTitle, icon: "command",
                                      keywords: [s.hotkeyToggle]),
                SettingsDirectoryItem(page: .advanced, title: s.tabAdvanced, icon: "wrench.and.screwdriver"),
                SettingsDirectoryItem(page: .about, title: s.tabAbout, icon: "info.circle",
                                      keywords: [s.reviewIntro, s.reviewHighlights]),
                SettingsDirectoryItem(page: .releaseNotes, title: s.tabReleaseNotes, icon: "sparkles"),
                SettingsDirectoryItem(page: .support, title: s.tabSupport, icon: "heart.fill",
                                      keywords: [s.donateButton, s.supportIntroStarButton,
                                                 s.discordIntroJoinButton,
                                                 s.communityIntroFollowButton]),
            ]),
        ]
    }
}
