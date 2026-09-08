// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum SettingsBackupTests {
    static func run(expect: (Bool, String) -> Void) {
        let profileOptions = MediaImageOptions(quality: 0.8,
                                               maxDimension: 1400,
                                               format: .png,
                                               stripMetadata: false,
                                               resizeMode: .exact(width: 900, height: 600, mode: .fit),
                                               watermark: MediaImageWatermark(kind: .text,
                                                                              text: "Sample",
                                                                              opacity: 0.5),
                                               renamePattern: MediaImageRenamePattern("{name}-{index}"))
        // MARK: Settings backup

        let backupKeys = SettingsBackupSupport.exportKeys()
        expect(backupKeys.contains(DefaultsKey.switcherEnabled)
                && backupKeys.contains(DefaultsKey.menuBarCPU)
                && backupKeys.contains(DefaultsKey.language)
                && backupKeys.contains(DefaultsKey.appVolumes)
                && backupKeys.contains(DefaultsKey.mixerShowFinder)
                && backupKeys.contains(DefaultsKey.mixerHideInactiveApps)
                && backupKeys.contains(DefaultsKey.keepAwakeActiveIcon)
                && backupKeys.contains(AppFeature.dockPreview.availabilityKey),
               "backup carries preferences, menu bar pins, Keep Awake appearance, language and hub availability")
        expect(backupKeys.contains(DefaultsKey.launchAtLoginWanted),
               "the launch at login choice travels with the settings backup")
        expect(backupKeys.contains(DefaultsKey.cleaningModeKeepScreenVisible),
               "the cleaning mode keep screen visible choice travels with the settings backup")
        expect(backupKeys.contains(DefaultsKey.appearance),
               "the light or dark choice travels with the settings backup")
        expect(Set([
            DefaultsKey.mediaImageResizeKind,
            DefaultsKey.mediaImageResizeWidth,
            DefaultsKey.mediaImageResizeHeight,
            DefaultsKey.mediaImageExactResizeMode,
            DefaultsKey.mediaImageWatermarkKind,
            DefaultsKey.mediaImageWatermarkText,
            DefaultsKey.mediaImageWatermarkPosition,
            DefaultsKey.mediaImageWatermarkOpacity,
            DefaultsKey.mediaImageWatermarkMargin,
            DefaultsKey.mediaImageWatermarkScale,
            DefaultsKey.mediaImageRenamePattern,
            DefaultsKey.mediaImageBackground,
            DefaultsKey.mediaImagePreserveModificationDate,
            DefaultsKey.mediaImageProfiles,
            DefaultsKey.mediaImageSelectedProfileID,
        ]).isSubset(of: backupKeys),
               "image converter choices and profiles travel with the settings backup")
        expect(!backupKeys.contains(DefaultsKey.mediaImageWatermarkLogoPath),
               "a local watermark file path never travels in a settings backup")
        expect(backupKeys.contains(DefaultsKey.dockClickHide)
                && backupKeys.contains(DefaultsKey.panelControlDockClickHide),
               "Dock hiding and its panel visibility travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.finderRenameEnabled)
                && backupKeys.contains(DefaultsKey.finderRenameShortcut),
               "the Finder rename choice and shortcut travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.textSnippets)
                && backupKeys.contains(DefaultsKey.textSnippetsEnabled),
               "snippets travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.windowGestureEnabled)
                && backupKeys.contains(DefaultsKey.windowEdgeSnapEnabled)
                && backupKeys.contains(DefaultsKey.windowEdgeSnapDisabledZones)
                && backupKeys.contains(DefaultsKey.windowGestureModifiers)
                && backupKeys.contains(DefaultsKey.windowGestureRaiseWindow)
                && backupKeys.contains(DefaultsKey.windowLayoutShortcutPreviousDisplay)
                && backupKeys.contains(DefaultsKey.windowLayoutShortcutMarginMaximize),
               "window layout choices travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.screenshotFreeze)
                && backupKeys.contains(DefaultsKey.screenshotSaveFolder)
                && backupKeys.contains(DefaultsKey.screenshotFullScreenShortcutEnabled)
                && backupKeys.contains(DefaultsKey.screenshotFullScreenShortcut)
                && backupKeys.contains(DefaultsKey.screenshotShowLastRegion)
                && backupKeys.contains(DefaultsKey.screenshotToolOrder)
                && backupKeys.contains(DefaultsKey.screenshotToolShortcutsEnabled)
                && backupKeys.contains(DefaultsKey.screenshotLastCaptureShortcutEnabled)
                && backupKeys.contains(DefaultsKey.screenshotLastCaptureShortcut)
                && backupKeys.contains(DefaultsKey.recentCapturesShortcutEnabled)
                && backupKeys.contains(DefaultsKey.recentCapturesShortcut)
                && backupKeys.contains(DefaultsKey.screenshotClipboardShortcutEnabled)
                && backupKeys.contains(DefaultsKey.screenshotClipboardShortcut)
                && backupKeys.contains(DefaultsKey.screenshotPreviewPosition)
                && backupKeys.contains(DefaultsKey.screenshotPreviewTakesFocus)
                && backupKeys.contains(DefaultsKey.screenshotLoupeRememberZoom)
                && backupKeys.contains(DefaultsKey.screenshotLoupeDefaultZoom)
                && backupKeys.contains(DefaultsKey.screenshotLoupeSteppedZoomByDefault)
                && backupKeys.contains(DefaultsKey.panelUtilityScreenshot),
               "screenshot preferences travel with the settings backup")
        expect(!backupKeys.contains(DefaultsKey.screenshotLoupeLastZoom),
               "the magnifier's last session zoom stays on its own Mac")
        expect(backupKeys.contains(DefaultsKey.whatsAppDownloadsEnabled)
                && backupKeys.contains(DefaultsKey.whatsAppDownloadsAutomaticEnabled)
                && backupKeys.contains(DefaultsKey.whatsAppDownloadsCategories)
                && backupKeys.contains(DefaultsKey.whatsAppDownloadsRetentionDays)
                && backupKeys.contains(DefaultsKey.whatsAppDownloadsNotify),
               "portable WhatsApp cleanup choices travel with settings backup")
        expect(backupKeys.contains(DefaultsKey.whatsAppOrganizerEnabled)
                && backupKeys.contains(DefaultsKey.whatsAppOrganizerDelayMinutes)
                && backupKeys.contains(DefaultsKey.whatsAppOrganizerCategories)
                && backupKeys.contains(DefaultsKey.whatsAppOrganizerLayout)
                && backupKeys.contains(DefaultsKey.whatsAppOrganizerDuplicateAction),
               "portable WhatsApp organizer choices travel with settings backup")
        expect(!backupKeys.contains(DefaultsKey.whatsAppDownloadsAutomaticStartDate)
                && !backupKeys.contains(DefaultsKey.whatsAppDownloadsLastCleanup)
                && !backupKeys.contains(DefaultsKey.whatsAppDownloadsExclusions)
                && !backupKeys.contains(DefaultsKey.whatsAppDownloadsAccessConfirmed),
               "machine-specific WhatsApp cleanup state never travels")
        expect(!backupKeys.contains(DefaultsKey.whatsAppOrganizerDestinationPath)
                && !backupKeys.contains(DefaultsKey.whatsAppOrganizerRecords)
                && !backupKeys.contains(DefaultsKey.whatsAppOrganizerUndoTransaction)
                && !backupKeys.contains(DefaultsKey.whatsAppOrganizerLastRun),
               "organizer paths, digests and activity never travel to another Mac")
        expect(backupKeys.contains(DefaultsKey.cameraPreviewShortcut)
                && backupKeys.contains(DefaultsKey.cameraPreviewShortcutEnabled)
                && backupKeys.contains(DefaultsKey.panelUtilityCameraPreview),
               "camera preview preferences travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.scratchpadShortcut)
                && backupKeys.contains(DefaultsKey.scratchpadShortcutEnabled)
                && backupKeys.contains(DefaultsKey.scratchpadRetention)
                && backupKeys.contains(DefaultsKey.scratchpadCloseOnClickOutside)
                && backupKeys.contains(DefaultsKey.scratchpadBackgroundOpacity)
                && backupKeys.contains(DefaultsKey.panelUtilityScratchpad)
                // The pad's own text is the user's material, kept in the app's
                // private container instead (issue #1197).
                && !backupKeys.contains(DefaultsKey.scratchpadDocument),
               "scratchpad preferences travel with the settings backup, its text does not")
        expect(backupKeys.contains(DefaultsKey.radialMenuEnabled)
                && backupKeys.contains(DefaultsKey.radialMenuShortcut)
                && backupKeys.contains(DefaultsKey.radialMenuAtPointer)
                && backupKeys.contains(DefaultsKey.radialMenuMouseButton)
                && backupKeys.contains(DefaultsKey.radialMenuActivationMode)
                && backupKeys.contains(DefaultsKey.radialMenuItems)
                && backupKeys.contains(DefaultsKey.panelControlRadialMenu),
               "the radial menu wheel and choices travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.mouseButtonShortcutsEnabled)
                && backupKeys.contains(DefaultsKey.mouseButtonShortcuts)
                && backupKeys.contains(DefaultsKey.panelControlMouseButtonShortcuts),
               "mouse button shortcuts travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.mouseClickDebounceEnabled)
                && backupKeys.contains(DefaultsKey.mouseClickDebounceWindowMs)
                && backupKeys.contains(DefaultsKey.panelControlMouseClickDebounce),
               "mouse click debounce preferences travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.mouseAccelerationDisabled)
                && backupKeys.contains(DefaultsKey.panelControlMouseAcceleration),
               "mouse acceleration preferences travel with the settings backup")
        expect(MouseExceptionScope.allCases.allSatisfy { backupKeys.contains($0.defaultsKey) },
               "the apps each mouse feature leaves alone travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.clipboardHistoryIgnoredApps),
               "the apps the clipboard history skips travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.switcherAppRules),
               "per-app switcher rules travel with the settings backup")
        expect(Defaults.registeredDefaults[DefaultsKey.finderPasteImageAsFile] as? Bool == false
                && backupKeys.contains(DefaultsKey.finderPasteImageAsFile),
               "pasting copied images as files is opt-in and travels with settings backup")
        expect(Defaults.registeredDefaults[DefaultsKey.finderCutPasteShowHUD] as? Bool == true
                && backupKeys.contains(DefaultsKey.finderCutPasteShowHUD),
               "the Finder cut and paste floating panel default is on and travels with settings backup")
        expect(Defaults.registeredDefaults[DefaultsKey.diskImageInstallerTrashesDownload] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.diskImageInstallerRevealsApp] as? Bool == false
                && backupKeys.contains(DefaultsKey.diskImageInstallerTrashesDownload)
                && backupKeys.contains(DefaultsKey.diskImageInstallerRevealsApp),
               "the disk image installer keeps trashing downloads by default, reveals apps only on request and both choices travel with settings backup")
        expect(backupKeys.contains(DefaultsKey.windowPreviewExcludedApps)
                && (Defaults.registeredDefaults[DefaultsKey.windowPreviewExcludedApps] as? [String]) == [],
               "the window preview exclusion list starts empty and travels with the settings backup")
        expect(backupKeys.contains(DefaultsKey.panelShowToggles)
                && backupKeys.contains(DefaultsKey.panelToggleOrder)
                && backupKeys.contains(DefaultsKey.panelToggleDarkMode)
                && backupKeys.contains(DefaultsKey.panelToggleKeyboardLight)
                && backupKeys.contains(DefaultsKey.panelToggleMicMute),
               "the quick toggles layout travels with the settings backup")
        expect(backupKeys.contains(DefaultsKey.panelShowFanControl)
                && backupKeys.contains(DefaultsKey.fanControlMode)
                && backupKeys.contains(DefaultsKey.fanControlCoolingLevel)
                && backupKeys.contains(DefaultsKey.fanControlCurves)
                && backupKeys.contains(DefaultsKey.menuBarFanSpeed)
                && !backupKeys.contains(DefaultsKey.fanControlRecoveryNeeded)
                && !backupKeys.contains(DefaultsKey.fanControlHelperVersion),
               "fan display and cooling preferences travel while helper recovery state stays on one Mac")
        expect(backupKeys.contains(DefaultsKey.screenshotSharingEnabled),
               "the temporary screenshot links preference travels with settings backup")
        expect(!backupKeys.contains(DefaultsKey.clipboardHistoryEntries)
                && !backupKeys.contains(DefaultsKey.shelfItems)
                && !backupKeys.contains(DefaultsKey.sleepDisabledFlag)
                && !backupKeys.contains(DefaultsKey.micMuteActive)
                && !backupKeys.contains(DefaultsKey.micMuteSavedVolumes)
                && !backupKeys.contains(DefaultsKey.micMuteMutedDevices)
                && !backupKeys.contains(DefaultsKey.cleanerLastAutoRun)
                && !backupKeys.contains(DefaultsKey.statusItemPlacementGeneration)
                && !backupKeys.contains(DefaultsKey.displaysSwitchedOff)
                && !backupKeys.contains(DefaultsKey.screenshotSharingDeveloperEndpoint),
               "backup never carries private content, live state or machine markers")
        expect(Defaults.registeredDefaults[DefaultsKey.displaysSwitchedOff] == nil,
               "a display switched off is a repair note for this machine, not a setting")
        expect(Defaults.registeredDefaults[DefaultsKey.startupDidNotFinish] == nil,
               "a start that did not finish is a note for this machine, not a setting")

        // A stored shortcut is text on disk and can arrive edited or through
        // an imported settings file, so the number is checked before it ever
        // reaches an API that takes a narrower type.
        expect(GlobalShortcut(storageValue: "command:-1") == nil,
               "a negative key code never becomes a shortcut")
        expect(GlobalShortcut(storageValue: "command:99999999") == nil,
               "a key code past the end of the range never becomes a shortcut")
        expect(GlobalShortcut(storageValue: "command:\(Int64.min)") == nil,
               "the smallest possible number never becomes a shortcut")
        expect(!GlobalShortcut(keyCode: -1, modifiers: [.command]).isValid
                && !GlobalShortcut(keyCode: 70000, modifiers: [.command]).isValid,
               "a shortcut built with a number out of range is not valid")
        expect(GlobalShortcut(keyCode: -1, modifiers: [.command]).carbonKeyCode == 0,
               "a number out of range converts to nothing instead of trapping")
        expect(GlobalShortcut(storageValue: "control+option+command:40") != nil,
               "an ordinary stored shortcut still reads back")
        expect(!backupKeys.contains(DefaultsKey.startupDidNotFinish),
               "the backup never carries a note about a start that did not finish")
        expect(backupKeys.contains(DefaultsKey.hasOnboarded)
                && backupKeys.contains(DefaultsKey.featuresOnboardingVersion)
                && backupKeys.contains(DefaultsKey.lastUpdateIntroVersion),
               "a restored Mac does not replay onboarding or the intros already seen")
        let backupPayload = SettingsBackupSupport.payload(appVersion: "test") { key in
            key == DefaultsKey.switcherEnabled ? true : nil
        }
        expect(backupPayload[SettingsBackupSupport.formatVersionKey] as? Int
                == SettingsBackupSupport.formatVersion,
               "backup envelope carries the format version")
        let roundTrip = SettingsBackupSupport.sanitizedSettings(from: backupPayload)
        expect(roundTrip?[DefaultsKey.switcherEnabled] as? Bool == true,
               "a backup round-trips its settings")
        var logoProfileOptions = profileOptions
        logoProfileOptions.watermark = MediaImageWatermark(kind: .textAndLogo,
                                                           text: "Portable",
                                                           logoPath: "/Users/private/Brand.png")
        let logoProfilesRaw = String(data: try! JSONEncoder().encode([
            MediaImageProfile(id: "logo", name: "Logo", options: logoProfileOptions),
        ]), encoding: .utf8)!
        let portableMediaBackup = SettingsBackupSupport.payload(appVersion: "test") { key in
            switch key {
            case DefaultsKey.mediaImageWatermarkLogoPath: return "/Users/private/Brand.png"
            case DefaultsKey.mediaImageWatermarkKind: return MediaImageWatermarkKind.textAndLogo.rawValue
            case DefaultsKey.mediaImageWatermarkText: return "Portable"
            case DefaultsKey.mediaImageProfiles: return logoProfilesRaw
            default: return nil
            }
        }
        let portableMediaSettings = SettingsBackupSupport.sanitizedSettings(from: portableMediaBackup)
        let portableProfiles = (portableMediaSettings?[DefaultsKey.mediaImageProfiles] as? String)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([MediaImageProfile].self, from: $0) }
        expect(portableMediaSettings?[DefaultsKey.mediaImageWatermarkLogoPath] == nil
               && portableMediaSettings?[DefaultsKey.mediaImageWatermarkKind] as? String
                    == MediaImageWatermarkKind.text.rawValue
               && portableProfiles?.first?.options.watermark.logoPath.isEmpty == true
               && portableProfiles?.first?.options.watermark.kind == .text,
               "media backups remove local logo paths while preserving portable watermark text")
        // A mouse exception list holds bundle ids and, since issue #1009, the
        // resolved path of a program that has none. The path carries the short
        // username and names nothing on another Mac, and `valueLooksRight`
        // cannot see it: ["com.apple.Safari", "/Users/.../java"] is a perfectly
        // good [String]. Driven from allCases, so a scope that renames its key
        // or two scopes that come to share one stay covered.
        let localJavaPath = "/Users/tester/Library/Application Support/RuntimeLauncher"
            + "/java/jre-legacy/zulu-8.jre/Contents/Home/bin/java"
        let exceptionKeys = Set(MouseExceptionScope.allCases.map(\.defaultsKey))
        let mixedExceptionBackup = SettingsBackupSupport.payload(appVersion: "test") { key in
            exceptionKeys.contains(key) ? ["com.apple.Safari", localJavaPath] : nil
        }
        let exportedExceptions = mixedExceptionBackup[SettingsBackupSupport.settingsKey] as? [String: Any]
        expect(!exceptionKeys.isEmpty
                && exceptionKeys.allSatisfy { exportedExceptions?[$0] as? [String] == ["com.apple.Safari"] },
               "every mouse exception list exports its bundle ids and drops the machine-local paths")
        let handEditedExceptions = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: Dictionary(uniqueKeysWithValues:
                exceptionKeys.map { ($0, ["com.apple.Safari", localJavaPath] as Any) }),
        ])
        expect(exceptionKeys.allSatisfy {
                    handEditedExceptions?[$0] as? [String] == ["com.apple.Safari"]
               },
               "a hand-edited backup cannot restore a machine-local path into an exception list")
        // The complement, so the filter cannot be mutated into dropping the
        // whole list and stay green.
        let bundleOnlyBackup = SettingsBackupSupport.payload(appVersion: "test") { key in
            key == MouseExceptionScope.smoothScroll.defaultsKey
                ? ["com.apple.Safari", "com.apple.Terminal"] : nil
        }
        expect((bundleOnlyBackup[SettingsBackupSupport.settingsKey] as? [String: Any])?[
                    MouseExceptionScope.smoothScroll.defaultsKey] as? [String]
                    == ["com.apple.Safari", "com.apple.Terminal"],
               "an exception list of only bundle ids survives a backup unchanged")
        // Filtering the export is only half the job: applying a backup clears
        // every exported key before writing the file's values, and the file no
        // longer carries the path half -- so a restore would delete those
        // entries, including on the Mac the backup came from. The two halves
        // of carrying them across are pure, so they are asserted directly.
        expect(SettingsBackupSupport.pathIdentities(
                    in: ["com.apple.Safari", localJavaPath, "com.apple.Terminal"]) == [localJavaPath],
               "only the machine-local paths are carried across a settings restore")
        expect(SettingsBackupSupport.restoredExceptionList(
                    restored: ["com.apple.Safari"], carried: [localJavaPath])
                    == ["com.apple.Safari", localJavaPath],
               "a restore puts the machine-local entries back beside the restored bundle ids")
        expect(SettingsBackupSupport.restoredExceptionList(
                    restored: ["com.apple.Safari", localJavaPath], carried: [localJavaPath])
                    == ["com.apple.Safari", localJavaPath],
               "applying the same backup twice does not double a carried path")
        // SettingsBackup.swift is not in the test binary, and the fix is an
        // ORDER: capture before the clear, put back after the write. Either
        // one moved leaves the code present and the entries still deleted.
        // Strip comments before asserting: "X appears before Y" would otherwise
        // be satisfied by a doc comment mentioning either.
        let backupServiceLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/SettingsBackup.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
        let captureAt = backupServiceLines.firstIndex {
            isCodeLine($0) && $0.contains("SettingsBackupSupport.pathIdentities(")
        }
        let clearAt = backupServiceLines.firstIndex {
            isCodeLine($0) && $0.contains("defaults.removeObject(forKey: key)")
        }
        let putBackAt = backupServiceLines.firstIndex {
            isCodeLine($0) && $0.contains("SettingsBackupSupport.restoredExceptionList(")
        }
        let writeAt = backupServiceLines.firstIndex {
            isCodeLine($0) && $0.contains("defaults.set(value, forKey: key)")
        }
        expect([captureAt, clearAt, putBackAt, writeAt].allSatisfy { $0 != nil }
                && captureAt! < clearAt! && writeAt! < putBackAt!,
               "a settings restore reads the machine-local entries before clearing "
                   + "and writes them back after the file's values")
        expect(SettingsBackupSupport.sanitizedSettings(from: [SettingsBackupSupport.settingsKey: [String: Any]()]) == nil,
               "a file without the version envelope is rejected")
        let tampered: [String: Any] = [
            SettingsBackupSupport.formatVersionKey: 1,
            SettingsBackupSupport.settingsKey: ["evilKey": "x", DefaultsKey.autoQuitEnabled: true] as [String: Any],
        ]
        let filteredImport = SettingsBackupSupport.sanitizedSettings(from: tampered)
        expect(filteredImport?["evilKey"] == nil
                && filteredImport?[DefaultsKey.autoQuitEnabled] as? Bool == true,
               "unknown keys are dropped on import")
        expect(SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: 99,
            SettingsBackupSupport.settingsKey: [String: Any](),
        ]) == nil, "a future format version is rejected")
        expect(SettingsBackupSupport.formatVersion(from: [SettingsBackupSupport.formatVersionKey: 1]) == 1
                && SettingsBackupSupport.formatVersion(from: [SettingsBackupSupport.formatVersionKey: NSNumber(value: 1)]) == 1
                && SettingsBackupSupport.formatVersion(from: [SettingsBackupSupport.formatVersionKey: "1"]) == 1
                && SettingsBackupSupport.formatVersion(from: [SettingsBackupSupport.formatVersionKey: " 1 \n"]) == 1
                && SettingsBackupSupport.formatVersion(from: [SettingsBackupSupport.formatVersionKey: "invalid"]) == nil,
               "backup format version accepts integer, NSNumber and string representations")
        let stringVersionBackup: [String: Any] = [
            SettingsBackupSupport.formatVersionKey: "1",
            SettingsBackupSupport.settingsKey: [
                DefaultsKey.smoothScrollStep: 60,
            ] as [String: Any],
        ]
        expect(SettingsBackupSupport.sanitizedSettings(from: stringVersionBackup)?[DefaultsKey.smoothScrollStep] as? Int == 60,
               "a backup with a string-encoded format version restores correctly")

        // A backup file can be edited by hand, and a value of the wrong shape
        // would reach code that trusts its own settings.
        let wrongShapes: [String: Any] = [
            SettingsBackupSupport.formatVersionKey: 1,
            SettingsBackupSupport.settingsKey: [
                DefaultsKey.smoothScrollEnabled: "yes please",
                DefaultsKey.monitorInterval: "soon",
                DefaultsKey.smoothScrollStep: 60,
                DefaultsKey.switcherAppRules: "not a rule dictionary",
            ] as [String: Any],
        ]
        let shapeChecked = SettingsBackupSupport.sanitizedSettings(from: wrongShapes)
        expect(shapeChecked?[DefaultsKey.smoothScrollEnabled] == nil,
               "text where a switch belongs is dropped on import")
        expect(shapeChecked?[DefaultsKey.monitorInterval] == nil,
               "text where a number belongs is dropped on import")
        expect(shapeChecked?[DefaultsKey.switcherAppRules] == nil,
               "text where a per-app rule dictionary belongs is dropped on import")
        expect(shapeChecked?[DefaultsKey.smoothScrollStep] as? Int == 60,
               "a value of the right shape still restores")
        let bridgedInput: [String: Any] = [
            SettingsBackupSupport.formatVersionKey: 1,
            SettingsBackupSupport.settingsKey: [
                DefaultsKey.switcherEnabled: 1,
                DefaultsKey.monitorInterval: true,
                DefaultsKey.dockPreviewBackgroundOpacity: true,
                DefaultsKey.smoothScrollStep: 60,
                DefaultsKey.scratchpadBackgroundOpacity: 0.5,
                DefaultsKey.smoothScrollExceptions: [1],
                DefaultsKey.autoQuitExceptions: ["com.example.editor"],
                DefaultsKey.switcherAppRules: ["com.example.editor": 1],
                DefaultsKey.mouseButtonShortcuts: ["4": "command:0"],
            ] as [String: Any],
        ]
        var bridgedSettings: [String: Any]?
        if let data = try? PropertyListSerialization.data(fromPropertyList: bridgedInput,
                                                          format: .binary,
                                                          options: 0),
           let parsed = try? PropertyListSerialization.propertyList(from: data,
                                                                     options: [],
                                                                     format: nil),
           let payload = parsed as? [String: Any] {
            bridgedSettings = SettingsBackupSupport.sanitizedSettings(from: payload)
        }
        expect(bridgedSettings?[DefaultsKey.switcherEnabled] == nil
                && bridgedSettings?[DefaultsKey.monitorInterval] == nil
                && bridgedSettings?[DefaultsKey.dockPreviewBackgroundOpacity] == nil,
               "property-list numbers and booleans do not cross scalar setting types")
        expect(bridgedSettings?[DefaultsKey.smoothScrollExceptions] == nil
                && bridgedSettings?[DefaultsKey.switcherAppRules] == nil,
               "wrong collection element types are dropped on import")
        expect(bridgedSettings?[DefaultsKey.smoothScrollStep] as? Int == 60
                && bridgedSettings?[DefaultsKey.scratchpadBackgroundOpacity] as? Double == 0.5
                && bridgedSettings?[DefaultsKey.autoQuitExceptions] as? [String]
                    == ["com.example.editor"]
                && bridgedSettings?[DefaultsKey.mouseButtonShortcuts] as? [String: String]
                    == ["4": "command:0"],
               "property-list values of the declared scalar and collection types still restore")
        let switcherRulesBackup: [String: Any] = [
            SettingsBackupSupport.formatVersionKey: 1,
            SettingsBackupSupport.settingsKey: [
                DefaultsKey.switcherAppRules: [
                    "com.example.editor": SwitcherAppRule.windowsOnly.rawValue,
                ] as [String: Any],
            ] as [String: Any],
        ]
        let restoredSwitcherRules = SettingsBackupSupport.sanitizedSettings(from: switcherRulesBackup)?[
            DefaultsKey.switcherAppRules
        ] as? [String: Any]
        expect(restoredSwitcherRules?["com.example.editor"] as? String
                == SwitcherAppRule.windowsOnly.rawValue,
               "per-app Switcher rules keep their bundle identity and behavior through backup import")
        expect(Defaults.registeredDefaults[DefaultsKey.preciseVolumeRollerEnabled] as? Bool == false,
               "precise volume roller is opt-in")
    }
}
