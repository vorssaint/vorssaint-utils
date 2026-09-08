// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Darwin
import Foundation

enum DefaultsTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Registered defaults

        let registeredDefaults = Defaults.registeredDefaults
        expect(registeredDefaults[DefaultsKey.monitorMemoryMetric] as? String == "used",
               "monitor memory metric defaults to memory used")
        expect(Defaults.sanitizedMonitorMemoryMetric("app") == "app",
               "app is an allowed memory metric")
        expect(Defaults.sanitizedMonitorMemoryMetric("bogus") == "used",
               "unknown memory metric values fall back to used")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.monitorMemoryMetric),
               "monitor memory metric is included in settings backups")
        expect(registeredDefaults[DefaultsKey.appearance] as? String == AppAppearance.system.rawValue,
               "the app follows the system appearance until the user picks a side")
        expect(registeredDefaults[DefaultsKey.liquidGlassEnabled] as? Bool == false,
               "liquid glass appearance is opt-in")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.liquidGlassEnabled),
               "liquid glass appearance follows settings backups")
        expect(AppAppearance.sanitized(nil) == .system
                && AppAppearance.sanitized("nonsense") == .system,
               "an unknown stored appearance falls back to the system one")
        expect(AppAppearance.sanitized("dark") == .dark && AppAppearance.sanitized("light") == .light,
               "stored appearance values survive a relaunch")
        expect(AppAppearance.allCases.map(\.rawValue) == ["system", "light", "dark"],
               "appearance raw values are persisted keys and their order is the picker order")
        expect(registeredDefaults[DefaultsKey.keepAwakeAutoStart] as? Bool == false,
               "Keep Awake launch restore is opt-in")
        expect(registeredDefaults[DefaultsKey.keepAwakeRightClickToggle] as? Bool == false,
               "right-click Keep Awake toggle is opt-in")
        expect(registeredDefaults[DefaultsKey.keepAwakeAllowDisplaySleep] as? Bool == false,
               "Keep Awake keeps the display on by default")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.keepAwakeRightClickToggle),
               "right-click Keep Awake preference follows settings backups")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.keepAwakeAllowDisplaySleep),
               "display sleep preference follows settings backups")
        expect(registeredDefaults[DefaultsKey.keepAwakeExternalDisplay] as? Bool == false,
               "external-display Keep Awake is opt-in")
        expect(registeredDefaults[DefaultsKey.keepAwakeConnectedToPower] as? Bool == false,
               "power-connected Keep Awake is opt-in")
        expect(registeredDefaults[DefaultsKey.keepAwakeRunningApps] as? Bool == false,
               "running-apps Keep Awake is opt-in")
        expect(registeredDefaults[DefaultsKey.keepAwakeRunningAppBundleIDs] as? [String] == [],
               "running-apps Keep Awake starts with an empty app list")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.keepAwakeRunningApps),
               "running-apps Keep Awake preference follows settings backups")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.keepAwakeRunningAppBundleIDs),
               "running-apps Keep Awake app list follows settings backups")
        expect(registeredDefaults[DefaultsKey.keepAwakePauseWhenLocked] as? Bool == false,
               "pausing Keep Awake on screen lock is opt-in")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.keepAwakePauseWhenLocked),
               "the Keep Awake screen-lock preference follows settings backups")
        expect(registeredDefaults[DefaultsKey.hotkeyEnabled] as? Bool == true,
               "global hotkey is on for clean installs")
        expect(registeredDefaults[DefaultsKey.keepAwakeShortcut] as? String == "control+option+command:40",
               "keep awake shortcut defaults to Ctrl+Opt+Cmd+K")
        expect(registeredDefaults[DefaultsKey.keepAwakeIconTint] as? String == KeepAwakeIconTint.orange.rawValue,
               "keep-awake active icon tint defaults to orange")
        expect(registeredDefaults[DefaultsKey.keepAwakeActiveIcon] as? String == KeepAwakeActiveIcon.vorssaint.rawValue,
               "keep-awake active icon defaults to the Vorssaint glyph")
        expect(registeredDefaults[DefaultsKey.keepAwakeMouseJiggleEnabled] as? Bool == false,
               "Keep Awake mouse movement is opt-in")
        expect(registeredDefaults[DefaultsKey.keepAwakeMouseJiggleInterval] as? Int == 5,
               "Keep Awake mouse movement defaults to five minutes")
        expect(Defaults.sanitizedKeepAwakeMouseJiggleInterval(10) == 10,
               "valid Keep Awake mouse movement interval is preserved")
        expect(Defaults.sanitizedKeepAwakeMouseJiggleInterval(3) == 5,
               "invalid Keep Awake mouse movement interval falls back to five minutes")
        expect(Defaults.sanitizedKeepAwakeIconTint("pink") == .pink,
               "valid keep-awake active icon tint is preserved")
        expect(Defaults.sanitizedKeepAwakeIconTint("bad") == .orange,
               "invalid keep-awake active icon tint falls back to orange")
        expect(Defaults.sanitizedKeepAwakeActiveIcon("coffee") == .coffee,
               "valid keep-awake active icon is preserved")
        expect(Defaults.sanitizedKeepAwakeActiveIcon("bad") == .vorssaint,
               "invalid keep-awake active icon falls back to the Vorssaint glyph")
        expect(KeepAwakeActiveIcon.eye.systemSymbolName == "eye.fill",
               "keep-awake eye option maps to its menu bar symbol")
        expect(!KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: []),
               "no online display does not count as an external display")
        expect(!KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: [true]),
               "the built-in screen does not count as an external display")
        expect(KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: [true, false]),
               "an online non-built-in screen counts as an external display")
        expect(!KeepAwakeAutomationSupport.selectedAppsAreRunning(
            selectedBundleIDs: [],
            runningBundleIDs: ["com.example.app"]
        ), "an empty selected-app list never matches a running app")
        expect(!KeepAwakeAutomationSupport.selectedAppsAreRunning(
            selectedBundleIDs: ["com.example.app"],
            runningBundleIDs: ["com.other.app"]
        ), "a selected app that is not running does not match")
        expect(KeepAwakeAutomationSupport.selectedAppsAreRunning(
            selectedBundleIDs: ["com.example.app", "com.other.app"],
            runningBundleIDs: ["com.helper", "com.example.app"]
        ), "any selected app that is running matches, focused or not")
        let combinedKeepAwakeConditions = KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: true,
            externalDisplayConnected: true,
            powerEnabled: true,
            connectedToPower: true,
            runningAppsEnabled: true,
            selectedAppsRunning: true
        )
        expect(combinedKeepAwakeConditions == [.externalDisplay, .power, .runningApps],
               "enabled Keep Awake conditions combine with OR behavior")
        expect(KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: false,
            externalDisplayConnected: false,
            powerEnabled: false,
            connectedToPower: false,
            runningAppsEnabled: true,
            selectedAppsRunning: true
        ) == [.runningApps], "a running selected app matches the running-apps condition")
        expect(KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: false,
            externalDisplayConnected: false,
            powerEnabled: false,
            connectedToPower: false,
            runningAppsEnabled: true,
            selectedAppsRunning: false
        ).isEmpty, "running-apps stays off when none of the selected apps are open")
        expect(KeepAwakeAutomationSupport.action(
            featureAvailable: true,
            matchingConditions: [.externalDisplay],
            sessionActive: false,
            automaticSessionActive: false
        ) == .activate, "an external display starts the automatic session")
        expect(KeepAwakeAutomationSupport.action(
            featureAvailable: true,
            matchingConditions: [],
            sessionActive: true,
            automaticSessionActive: true
        ) == .deactivate, "clearing every matching condition ends the automatic session")
        expect(KeepAwakeAutomationSupport.action(
            featureAvailable: true,
            matchingConditions: [],
            sessionActive: true,
            automaticSessionActive: false
        ) == .none, "clearing automatic conditions does not end a manual session")
        expect(KeepAwakeAutomationSupport.isScreenLocked(
            sessionDictionary: ["CGSSessionScreenIsLocked": true]
        ), "the Keep Awake lock guard reads a locked session")
        expect(!KeepAwakeAutomationSupport.isScreenLocked(
            sessionDictionary: ["CGSSessionScreenIsLocked": false]
        ), "the Keep Awake lock guard reads an unlocked session")
        expect(KeepAwakeAutomationSupport.isScreenLocked(
            sessionDictionary: ["CGSSessionScreenIsLocked": NSNumber(value: true)]
        ), "the Keep Awake lock guard accepts the session dictionary's numeric bridge")
        expect(!KeepAwakeAutomationSupport.isScreenLocked(sessionDictionary: nil),
               "an unreadable lock state does not strand Keep Awake in a pause")
        let sleepDisabledReport = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         standby              1
        """
        let sleepEnabledReport = """
        System-wide power settings:
         SleepDisabled\t\t0
        Currently in use:
         standby              1
        """
        expect(SudoersSupport.sleepDisabled(inPmsetOutput: sleepDisabledReport),
               "a pmset report with SleepDisabled 1 reads as lid sleep disabled")
        expect(!SudoersSupport.sleepDisabled(inPmsetOutput: sleepEnabledReport),
               "a pmset report with SleepDisabled 0 reads as lid sleep enabled")
        expect(!SudoersSupport.sleepDisabled(inPmsetOutput: ""),
               "an empty pmset report reads as lid sleep enabled")
        // The rule is granted by uid so every short name works, including the
        // email-style ones SSO enrollment produces (#915). The uid renders as
        // bare digits and the rest is a fixed literal, so the whole line must
        // stay inside a character set that neither sudoers nor a single-quoted
        // shell string can read as anything but itself.
        expect(SudoersSupport.clamshellRule(uid: 501)
               == "#501 ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0",
               "the closed-lid sudoers rule grants pmset disablesleep to the uid")
        expect(SudoersSupport.clamshellRule(uid: uid_t.max)
               .range(of: #"^#[0-9]+ [A-Za-z0-9()=:,./ ]+$"#, options: .regularExpression) != nil,
               "the closed-lid sudoers rule never contains shell or sudoers metacharacters")
    }

    static func runVisibilityMigration(expect: (Bool, String) -> Void) {
        let registeredDefaults = Defaults.registeredDefaults
        expect(registeredDefaults[DefaultsKey.minimalWindowPreviews] as? Bool == false,
               "minimal previews preserve the existing appearance until enabled")
        expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.minimalWindowPreviews,
                                                                  DefaultsKey.monitorPwrTemperature,
                                                                  DefaultsKey.monitorSysBattery]),
               "preview appearance and moved battery visibility travel in settings backups")
        let batteryVisibilitySuite = "com.vorssaint.tests.batteryVisibility.\(UUID().uuidString)"
        if let batteryVisibilityDefaults = UserDefaults(suiteName: batteryVisibilitySuite) {
            batteryVisibilityDefaults.removePersistentDomain(forName: batteryVisibilitySuite)
            batteryVisibilityDefaults.set(false, forKey: DefaultsKey.monitorSysTemps)
            Defaults.migrateBatteryTemperatureVisibility(in: batteryVisibilityDefaults)
            expect(!batteryVisibilityDefaults.bool(forKey: DefaultsKey.monitorPwrTemperature),
                   "moving battery temperature preserves a hidden temperature section")
            batteryVisibilityDefaults.set(true, forKey: DefaultsKey.monitorSysTemps)
            Defaults.migrateBatteryTemperatureVisibility(in: batteryVisibilityDefaults)
            expect(!batteryVisibilityDefaults.bool(forKey: DefaultsKey.monitorPwrTemperature),
                   "subsequent System visibility changes cannot overwrite the Power choice")
            batteryVisibilityDefaults.removePersistentDomain(forName: batteryVisibilitySuite)
            Defaults.migrateBatteryTemperatureVisibility(in: batteryVisibilityDefaults)
            expect(batteryVisibilityDefaults.bool(forKey: DefaultsKey.monitorPwrTemperature),
                   "a fresh installation keeps battery temperature visible in Power")
            batteryVisibilityDefaults.set(false, forKey: DefaultsKey.monitorSysTemps)
            Defaults.migrateBatteryTemperatureVisibility(in: batteryVisibilityDefaults)
            expect(batteryVisibilityDefaults.bool(forKey: DefaultsKey.monitorPwrTemperature),
                   "a restored Power preference wins over the previous temperature section")
            batteryVisibilityDefaults.removePersistentDomain(forName: batteryVisibilitySuite)
        } else {
            expect(false, "battery visibility migration has isolated preferences")
        }
    }

    static func runFeatureDefaults(expect: (Bool, String) -> Void) {
        let registeredDefaults = Defaults.registeredDefaults
        expect(registeredDefaults[DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect] as? Bool == false,
               "headphone disconnect volume lowering is opt-in")
        expect(registeredDefaults[DefaultsKey.mixerHeadphonesDisconnectVolumePercent] as? Int
               == Defaults.defaultMixerHeadphonesDisconnectVolumePercent,
               "headphone disconnect protection starts at an audible volume, never at silence")
        expect(Defaults.defaultMixerHeadphonesDisconnectVolumePercent
               >= Defaults.minimumMixerHeadphonesDisconnectVolumePercent
               && Defaults.defaultMixerHeadphonesDisconnectVolumePercent < 100,
               "the headphone disconnect default is a real reduction that can still be heard")
        expect(registeredDefaults[DefaultsKey.mixerShowFinder] as? Bool == true,
               "Finder returns to the mixer by default")
        expect(registeredDefaults[DefaultsKey.mixerHideInactiveApps] as? Bool == false,
               "inactive mixer apps remain visible by default")
        expect(registeredDefaults[DefaultsKey.soundOutputSwitcherEnabled] as? Bool == false,
               "sound output switcher is opt-in")
        expect(registeredDefaults[DefaultsKey.soundOutputSwitcherShortcut] as? String
               == GlobalShortcut.soundOutputSwitcherDefault.storageValue,
               "sound output switcher shortcut has a registered default")
        expect(registeredDefaults[DefaultsKey.shelfShortcutEnabled] as? Bool == true,
               "shelf shortcut is on by default once shelf is enabled")
        expect(registeredDefaults[DefaultsKey.shelfShortcut] as? String == "control+option+command:2",
               "shelf shortcut defaults to Ctrl+Opt+Cmd+D")
        expect(registeredDefaults[DefaultsKey.shelfShakeToOpen] as? Bool == true,
               "shelf shake opens by default once shelf is enabled")
        expect(registeredDefaults[DefaultsKey.shelfEdgeDragEnabled] as? Bool == false,
               "new shelf edge opening stays off by default")
        expect(registeredDefaults[DefaultsKey.shelfCloseAfterDrop] as? Bool == false,
               "closing after a drop is new behavior and must arrive off in an update")
        expect(registeredDefaults[DefaultsKey.shelfRemoveAfterDrop] as? Bool == true,
               "shelf removes accepted items after a drop by default")
        expect(registeredDefaults[DefaultsKey.shelfClearOnClose] as? Bool == false
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.shelfClearOnClose),
               "clearing the shelf on close is opt-in and travels with settings backups")
        expect((registeredDefaults[DefaultsKey.shelfAutomaticExclusions] as? [String])?.isEmpty == true,
               "shelf automatic exclusions start empty")
        expect(registeredDefaults[DefaultsKey.mouseNavigationEnabled] as? Bool == false,
               "mouse side-button navigation is opt-in")
        expect(registeredDefaults[DefaultsKey.mouseAccelerationDisabled] as? Bool == false
                && registeredDefaults[DefaultsKey.panelControlMouseAcceleration] as? Bool == true,
               "mouse acceleration control is opt-in and visible in the panel when installed")
        expect(registeredDefaults[DefaultsKey.mouseClickDebounceEnabled] as? Bool == false,
               "mouse click debounce is opt-in")
        expect(registeredDefaults[DefaultsKey.mouseClickDebounceWindowMs] as? Int
               == Defaults.defaultMouseClickDebounceWindowMs,
               "mouse click debounce registers its conservative filter window")
        expect(registeredDefaults[DefaultsKey.panelControlMouseClickDebounce] as? Bool == true,
               "mouse click debounce is visible in the panel when installed")
        expect(registeredDefaults[DefaultsKey.clipboardHistoryShortcutEnabled] as? Bool == true,
               "clipboard history shortcut is ready when clipboard history is enabled")
        expect(registeredDefaults[DefaultsKey.clipboardHistoryShortcut] as? String
               == GlobalShortcut.clipboardDefault.storageValue,
               "clipboard history shortcut defaults to Ctrl+Opt+Cmd+V")
        expect(registeredDefaults[DefaultsKey.finderCutPasteShowHUD] as? Bool == true,
               "the Finder cut and paste floating panel starts enabled")
        expect(registeredDefaults[DefaultsKey.finderRenameEnabled] as? Bool == false,
               "the Finder rename shortcut is opt-in")
        expect(registeredDefaults[DefaultsKey.finderRenameShortcut] as? String == ":120",
               "the Finder rename shortcut starts on bare F2")
        expect(GlobalShortcut(keyCode: Int64(kVK_ANSI_V), modifiers: [.command])
                   .isStandardPasteCommand,
               "Cmd+V is recognized when plain-text paste must release its own hotkey")
        expect(!GlobalShortcut.pastePlainDefault.isStandardPasteCommand,
               "the default plain-text paste shortcut does not intercept synthesized Cmd+V")
        expect(!GlobalShortcut(keyCode: Int64(kVK_ANSI_C), modifiers: [.command])
                   .isStandardPasteCommand,
               "other Command shortcuts never release the plain-text paste hotkey")
        expect(registeredDefaults[DefaultsKey.urlCleanerEnabled] as? Bool == false,
               "URL cleaner clipboard watching is opt-in")
        expect(registeredDefaults[DefaultsKey.windowMaximizeEnabled] as? Bool == false,
               "green button maximize override is opt-in")
        expect(registeredDefaults[DefaultsKey.keyboardDebounceEnabled] as? Bool == false,
               "keyboard debounce is opt-in")
        expect(registeredDefaults[DefaultsKey.keyboardDebounceWindowMs] as? Int == 5,
               "keyboard debounce default window starts low")
        expect(registeredDefaults[DefaultsKey.keyboardDebounceKeyWindows] as? String == "",
               "keyboard debounce per-key windows start empty")
        expect(registeredDefaults[DefaultsKey.panelUtilityCleaning] as? Bool == true,
               "panel cleaning utility is visible by default")
        expect(registeredDefaults[DefaultsKey.cleaningModeKeepScreenVisible] as? Bool == false,
               "cleaning mode keep screen visible is disabled by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityURLCleaner] as? Bool == true,
               "panel URL cleaner utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityUninstaller] as? Bool == true,
               "panel uninstaller utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityHomebrew] as? Bool == true,
               "panel Homebrew utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityMedia] as? Bool == true,
               "panel Media utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlMouseScroll] as? Bool == true,
               "panel mouse scroll control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlMouseNavigation] as? Bool == true,
               "panel mouse navigation control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlSwitcher] as? Bool == true,
               "panel switcher control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlDockPreview] as? Bool == true,
               "panel Dock Preview control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlDockClickHide] as? Bool == true,
               "panel Dock hide control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlCutPaste] as? Bool == true,
               "panel cut and paste control is visible by default")
        expect(registeredDefaults[DefaultsKey.colorPickerBareHex] as? Bool == false,
               "color picker keeps the # prefix by default")
        expect(registeredDefaults[DefaultsKey.screenOCRRemoveLineBreaks] as? Bool == false,
               "copy text from screen keeps line breaks by default")
        expect(registeredDefaults[DefaultsKey.screenOCRDetectQRCodes] as? Bool == true,
               "copy text from screen reads QR codes by default")
        expect(registeredDefaults[DefaultsKey.micMuteMenuBarIndicator] as? Bool == true,
               "mic mute menu bar indicator ships on by default (badge only shows while muted)")
        expect(registeredDefaults[DefaultsKey.menuBarMetricSpacing] as? String == "compact",
               "menu bar metric spacing defaults to the compact look")
        expect(registeredDefaults[DefaultsKey.menuBarMetricAppearance] as? String == "values",
               "menu bar usage metrics keep numeric values by default")
        expect(registeredDefaults[DefaultsKey.menuBarUsageBarNormalColor] as? String == "#64D2FF",
               "menu bar bars use a bright normal color by default")
        expect(registeredDefaults[DefaultsKey.menuBarUsageBarElevatedColor] as? String == "#FFD60A"
               && registeredDefaults[DefaultsKey.menuBarUsageBarCriticalColor] as? String == "#FF453A",
               "menu bar bars keep visible elevated and critical defaults")
        expect(registeredDefaults[DefaultsKey.menuBarUsageBarMediumThreshold] as? Int == 70
               && registeredDefaults[DefaultsKey.menuBarUsageBarHighThreshold] as? Int == 90,
               "menu bar bar thresholds default to seventy and ninety percent")
        expect(Defaults.sanitizedMonitorAlertCooldown(2) == 2,
               "the two minute alert cooldown is a valid stored choice")
        expect(Defaults.sanitizedMonitorAlertCooldown(7) == 15,
               "unknown alert cooldowns fall back to fifteen minutes")
        expect(registeredDefaults[DefaultsKey.monitorAlertBatteryTemperature] as? Bool == false,
               "battery temperature alerts are opt-in")
        expect(registeredDefaults[DefaultsKey.monitorAlertBatteryTemperatureThreshold] as? Int == 40,
               "battery temperature alerts default to forty degrees")
    }

    static func runSanitization(expect: (Bool, String) -> Void) {
        let registeredDefaults = Defaults.registeredDefaults
        expect(registeredDefaults[DefaultsKey.mediaLastTool] as? String == MediaTool.videoCompressor.rawValue,
               "Media defaults to video compressor")
        expect(registeredDefaults[DefaultsKey.mediaVideoCodec] as? String == MediaVideoCodec.h264.rawValue,
               "Media video codec defaults to H.264")
        expect(registeredDefaults[DefaultsKey.mediaImageFormat] as? String == MediaImageFormat.jpeg.rawValue,
               "Media image format defaults to JPEG")
        expect(registeredDefaults[DefaultsKey.mediaImageResizeKind] as? String == MediaImageResizeKind.maxDimension.rawValue,
               "Media image resize defaults to max side")
        expect(registeredDefaults[DefaultsKey.mediaImageExactResizeMode] as? String == MediaImageExactResizeMode.stretch.rawValue,
               "Media image exact resize defaults to stretch for existing behavior")
        expect(registeredDefaults[DefaultsKey.mediaImageWatermarkKind] as? String == MediaImageWatermarkKind.off.rawValue,
               "Media image watermark starts off")
        expect(registeredDefaults[DefaultsKey.mediaImageBackground] as? String == MediaImageBackground.transparent.rawValue,
               "Media image background starts transparent")
        expect(registeredDefaults[DefaultsKey.mediaImagePreserveModificationDate] as? Bool == false,
               "Media image conversion does not preserve modification dates by default")
        expect(registeredDefaults[DefaultsKey.mediaImageProfiles] as? String == "[]",
               "Media image profiles start empty")
        expect((registeredDefaults[DefaultsKey.autoQuitExceptions] as? [String]) == Defaults.mandatoryAutoQuitExceptionBundleIDs,
               "Finder stays in the default auto-quit exception list")
        expect(registeredDefaults[DefaultsKey.panelCollapsedSections] == nil,
               "panel collapsed sections intentionally has no registered default")
        expect(registeredDefaults[DefaultsKey.panelUtilityOrder] == nil,
               "panel utility order intentionally has no registered default")
        expect(registeredDefaults[DefaultsKey.panelToggleOrder] == nil,
               "panel toggle order intentionally has no registered default")
        expect(Defaults.sanitizedDefaultDuration(60) == 60, "valid default duration is preserved")
        expect(Defaults.sanitizedDefaultDuration(999) == 0, "invalid default duration falls back to indefinite")
        expect(Defaults.sanitizedBatteryLimit(15) == 15, "valid battery limit is preserved")
        expect(Defaults.sanitizedBatteryLimit(100) == 10, "invalid battery limit falls back to default")
        expect(Defaults.sanitizedClipboardHistoryLimit(1_000) == 1_000,
               "larger clipboard history limits are preserved")
        expect(Defaults.sanitizedClipboardHistoryLimit(999) == 50,
               "unsupported clipboard history limits fall back to default")
        expect(Defaults.sanitizedMonitorInterval(5) == 5, "valid monitor interval is preserved")
        expect(Defaults.sanitizedMonitorInterval(7) == 2, "invalid monitor interval falls back to default")
        expect(Defaults.sanitizedKeyboardDebounceWindow(80) == 80,
               "valid debounce window is preserved")
        expect(Defaults.sanitizedKeyboardDebounceWindow(999) == Defaults.defaultKeyboardDebounceWindowMs,
               "invalid debounce window falls back to default")
        expect(Defaults.sanitizedMenuBarLabelStyle("classic") == "classic", "valid label style is preserved")
        expect(Defaults.sanitizedMenuBarLabelStyle("bad") == "compact", "invalid label style falls back to compact")
        expect(Defaults.sanitizedMenuBarMemoryStyle("percent") == "percent", "percent memory style is preserved")
        expect(Defaults.sanitizedMenuBarMemoryStyle("dot") == "dot", "valid memory style is preserved")
        expect(Defaults.sanitizedMenuBarMemoryStyle("both") == "both", "combined memory style is preserved")
        expect(Defaults.sanitizedMenuBarMemoryStyle("bad") == "percent", "invalid memory style falls back to percent")
        expect(Defaults.sanitizedMenuBarMetricOrder("cpu,gpu,memory,network,battery,power")
               == ["cpu", "gpu", "memory", "network", "battery", "power",
                   "cpuTemperature", "gpuTemperature", "batteryTime", "batteryTemperature", "peripheralBattery", "diskUsage", "diskActivity", "fanSpeed"],
               "menu bar metric order appends temperature sensors without rewriting existing saved order")
        expect(Defaults.sanitizedMenuBarMetricOrder("temperature,cpu,cpu,bad")
               == ["cpuTemperature", "gpuTemperature", "batteryTemperature",
                   "cpu", "gpu", "memory", "battery", "batteryTime", "peripheralBattery", "network", "diskUsage", "diskActivity", "power", "fanSpeed"],
               "menu bar metric order migrates the old generic temperature value")
        expect(Defaults.sanitizedBundleIdentifierList([" com.example.One ", "", "com.example.One", "com.example.Two"])
               == ["com.example.One", "com.example.Two"],
               "bundle id lists are trimmed and deduplicated")
        expect(Defaults.sanitizedAutoQuitExceptions(["com.example.One", Defaults.finderBundleIdentifier])
               == [Defaults.finderBundleIdentifier, "com.example.One"],
               "Finder is mandatory in the auto-quit exception list")
    }
}
