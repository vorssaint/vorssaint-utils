// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum SwitcherModelFeatureTests {
    static func run(_ suite: TestSuite) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        let registeredDefaults = Defaults.registeredDefaults
        func sourceBody(of source: String, from opening: String, to closing: String) -> String {
            guard let start = source.range(of: opening),
                  let end = source.range(of: closing, range: start.upperBound..<source.endIndex)
            else { return "" }
            return String(source[start.upperBound..<end.lowerBound])
        }

        suite.expect(registeredDefaults[DefaultsKey.switcherEnabled] as? Bool == true,
               "window switcher is on for clean installs")
        suite.expect(registeredDefaults[DefaultsKey.switcherShortcut] as? String == "command:48",
               "switcher shortcut defaults to Cmd+Tab")
        suite.expect(registeredDefaults[DefaultsKey.switcherWindowShortcut] as? String
               == GlobalShortcut.switcherWindowDefault.storageValue,
               "switcher window shortcut defaults to Cmd+Grave")
        let shortcutSuite = "vorss.tests.switcher.shortcut"
        if let migrationDefaults = UserDefaults(suiteName: shortcutSuite) {
            migrationDefaults.removePersistentDomain(forName: shortcutSuite)
            migrationDefaults.set("control+option+command:50", forKey: DefaultsKey.switcherWindowShortcut)
            Defaults.migrateLegacySwitcherWindowShortcut(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: DefaultsKey.switcherWindowShortcut)
                   == GlobalShortcut.switcherWindowDefault.storageValue,
                   "switcher window shortcut migrates the accidental Ctrl+Option+Cmd+Grave default back to Cmd+Grave")
            migrationDefaults.removeObject(forKey: DefaultsKey.scrollInverterHorizontalEnabled)
            migrationDefaults.set(true, forKey: DefaultsKey.scrollInverterEnabled)
            Defaults.migrateScrollInverterAxes(in: migrationDefaults)
            suite.expect(migrationDefaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled),
                   "the former combined scroll switch keeps both directions on after updating")
            migrationDefaults.set(false, forKey: DefaultsKey.scrollInverterHorizontalEnabled)
            Defaults.migrateScrollInverterAxes(in: migrationDefaults)
            suite.expect(!migrationDefaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled),
                   "the direction migration preserves a newer horizontal choice")
            migrationDefaults.set("option:50", forKey: DefaultsKey.switcherWindowShortcut)
            Defaults.migrateLegacySwitcherWindowShortcut(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: DefaultsKey.switcherWindowShortcut) == "option:50",
                   "switcher window shortcut migration preserves real custom shortcuts")
            migrationDefaults.set(30, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(false, forKey: DefaultsKey.keyboardDebounceEnabled)
            migrationDefaults.set("", forKey: DefaultsKey.keyboardDebounceKeyWindows)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            suite.expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs)
                   == Defaults.defaultKeyboardDebounceWindowMs,
                   "keyboard debounce migration updates the old disabled Developer default")
            migrationDefaults.set(10, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(false, forKey: DefaultsKey.keyboardDebounceEnabled)
            migrationDefaults.set("", forKey: DefaultsKey.keyboardDebounceKeyWindows)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            suite.expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs)
                   == Defaults.defaultKeyboardDebounceWindowMs,
                   "keyboard debounce migration updates the old disabled 10 ms default")
            migrationDefaults.set(30, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(true, forKey: DefaultsKey.keyboardDebounceEnabled)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            suite.expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs) == 30,
                   "keyboard debounce migration preserves active user choices")
            migrationDefaults.set(10, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(true, forKey: DefaultsKey.keyboardDebounceEnabled)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            suite.expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs) == 10,
                   "keyboard debounce migration preserves active 10 ms user choices")
            migrationDefaults.removeObject(forKey: DefaultsKey.panelUtilityOrder)
            Defaults.migrateUtilityOrderForScreenshot(in: migrationDefaults)
            suite.expect(migrationDefaults.object(forKey: DefaultsKey.panelUtilityOrder) == nil,
                   "utility migration leaves a clean default order unpersisted")
            migrationDefaults.set("quickLauncher,cleaner,homebrew",
                                  forKey: DefaultsKey.panelUtilityOrder)
            Defaults.migrateUtilityOrderForScreenshot(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: DefaultsKey.panelUtilityOrder)
                   == "screenshot,quickLauncher,cleaner,homebrew",
                   "utility migration puts the newly added screenshot first")
            migrationDefaults.set("homebrew,screenshot,cleaner",
                                  forKey: DefaultsKey.panelUtilityOrder)
            Defaults.migrateUtilityOrderForScreenshot(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: DefaultsKey.panelUtilityOrder)
                   == "homebrew,screenshot,cleaner",
                   "utility migration preserves a screenshot position already chosen")
            migrationDefaults.set(true, forKey: DefaultsKey.screenshotOpenEditorDirectly)
            Defaults.migrateScreenshotOpenEditorDirectly(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: DefaultsKey.screenshotDefaultAction)
                   == ScreenshotDefaultAction.edit.rawValue
                   && migrationDefaults.bool(forKey: DefaultsKey.screenshotOpenEditorDirectly) == false,
                   "direct-to-editor migrates into the Edit after-capture action")
            migrationDefaults.set(true, forKey: DefaultsKey.screenshotOpenEditorDirectly)
            migrationDefaults.set(ScreenshotDefaultAction.save.rawValue,
                                  forKey: DefaultsKey.screenshotDefaultAction)
            Defaults.migrateScreenshotOpenEditorDirectly(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: DefaultsKey.screenshotDefaultAction)
                   == ScreenshotDefaultAction.save.rawValue,
                   "direct-to-editor migration never overrides a newer picker choice")
            migrationDefaults.removeObject(forKey: DefaultsKey.screenshotOpenEditorDirectly)
            migrationDefaults.removeObject(forKey: DefaultsKey.screenshotDefaultAction)
            Defaults.migrateScreenshotOpenEditorDirectly(in: migrationDefaults)
            suite.expect(migrationDefaults.object(forKey: DefaultsKey.screenshotDefaultAction) == nil,
                   "a setup that never used direct-to-editor keeps asking after capture")
            migrationDefaults.set(false, forKey: DefaultsKey.switcherShowWindowlessFinder)
            Defaults.migrateSwitcherWindowlessFinder(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: DefaultsKey.switcherWindowlessApps)
                   == SwitcherWindowlessApps.off.rawValue
                   && migrationDefaults.bool(forKey: DefaultsKey.switcherShowWindowlessFinder),
                   "hiding the windowless desktop app migrates into showing no windowless app at all")
            migrationDefaults.set(SwitcherWindowlessApps.all.rawValue,
                                  forKey: DefaultsKey.switcherWindowlessApps)
            Defaults.migrateSwitcherWindowlessFinder(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: DefaultsKey.switcherWindowlessApps)
                   == SwitcherWindowlessApps.all.rawValue,
                   "the windowless apps migration runs once and never fights a later choice")
            migrationDefaults.removeObject(forKey: DefaultsKey.switcherShowWindowlessFinder)
            migrationDefaults.removeObject(forKey: DefaultsKey.switcherWindowlessApps)
            migrationDefaults.set(true, forKey: DefaultsKey.switcherShowWindowlessFinder)
            Defaults.migrateSwitcherWindowlessFinder(in: migrationDefaults)
            suite.expect(migrationDefaults.object(forKey: DefaultsKey.switcherWindowlessApps) == nil,
                   "a setup that kept the windowless desktop app is left exactly as it was")

            migrationDefaults.set(["display|port"],
                                  forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
            Defaults.recheckBrightnessDDCWriteOnlyPaths(in: migrationDefaults)
            suite.expect(migrationDefaults.object(forKey: DefaultsKey.brightnessDDCWriteOnlyPaths) == nil
                   && migrationDefaults.bool(
                    forKey: DefaultsKey.brightnessDDCWriteOnlyPathsRechecked),
                   "verdicts cached before paired discovery requests are classified again")
            migrationDefaults.set(["display|port"],
                                  forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
            Defaults.recheckBrightnessDDCWriteOnlyPaths(in: migrationDefaults)
            suite.expect(migrationDefaults.stringArray(forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
                   == ["display|port"],
                   "the recheck runs once and keeps later verdicts")

            migrationDefaults.set("microphone,panel", forKey: DefaultsKey.notchHiddenControls)
            Defaults.hideScratchpadControlOnce(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: DefaultsKey.notchHiddenControls)
                   == "microphone,panel,scratchpad"
                   && migrationDefaults.bool(forKey: DefaultsKey.notchScratchpadControlHidden),
                   "a hidden-controls list saved before the Scratchpad tile existed hides it once")
            migrationDefaults.set("microphone,panel", forKey: DefaultsKey.notchHiddenControls)
            Defaults.hideScratchpadControlOnce(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: DefaultsKey.notchHiddenControls) == "microphone,panel",
                   "showing the Scratchpad tile afterwards is kept")
            migrationDefaults.removeObject(forKey: DefaultsKey.notchScratchpadControlHidden)
            migrationDefaults.removeObject(forKey: DefaultsKey.notchHiddenControls)
            Defaults.hideScratchpadControlOnce(in: migrationDefaults)
            suite.expect(migrationDefaults.object(forKey: DefaultsKey.notchHiddenControls) == nil
                   && migrationDefaults.bool(forKey: DefaultsKey.notchScratchpadControlHidden),
                   "a setup that never customized the controls keeps the registered default")
            let hiddenControlsKey = DefaultsKey.notchHiddenControls
            let scratchpadMigrationKey = DefaultsKey.notchScratchpadControlHidden
            suite.expect(SettingsBackupSupport.exportKeys().contains(scratchpadMigrationKey),
                   "the migration marker travels with a later choice to show the Scratchpad tile")
            suite.expect(!SettingsBackupSupport.valueLooksRight(scratchpadMigrationKey, "true"),
                   "an imported migration marker must be a boolean")
            for shown in [false, true] {
                migrationDefaults.set(shown ? "microphone,panel" : "microphone,panel,scratchpad",
                                      forKey: hiddenControlsKey)
                let backup = SettingsBackupSupport.payload(appVersion: "3.4.0") {
                    migrationDefaults.object(forKey: $0)
                }
                let restored = SettingsBackupSupport.sanitizedSettings(from: backup) ?? [:]
                for key in SettingsBackupSupport.exportKeys() { migrationDefaults.removeObject(forKey: key) }
                for (key, value) in restored { migrationDefaults.set(value, forKey: key) }
                Defaults.hideScratchpadControlOnce(in: migrationDefaults)
                suite.expect(migrationDefaults.string(forKey: hiddenControlsKey)?.contains("scratchpad") == !shown,
                       "restoring a current backup preserves the explicit Scratchpad visibility choice")
            }
            // A restore clears every exportable key before applying the backup.
            // Old backups have a controls list but no migration marker.
            for key in SettingsBackupSupport.exportKeys() { migrationDefaults.removeObject(forKey: key) }
            migrationDefaults.set("microphone,panel", forKey: hiddenControlsKey)
            Defaults.hideScratchpadControlOnce(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: hiddenControlsKey) == "microphone,panel,scratchpad",
                   "an old backup restored after the first launch still hides the new Scratchpad tile")

            migrationDefaults.removeObject(
                forKey: DefaultsKey.unifiedScreenCaptureShortcutMigrated)
            migrationDefaults.set(false, forKey: DefaultsKey.screenshotShortcutEnabled)
            migrationDefaults.set(true, forKey: DefaultsKey.recorderShortcutEnabled)
            migrationDefaults.set("control+option:42", forKey: DefaultsKey.recorderShortcut)
            Defaults.migrateUnifiedScreenCaptureShortcut(in: migrationDefaults)
            suite.expect(migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
                   && migrationDefaults.string(forKey: DefaultsKey.screenshotShortcut)
                        == "control+option:42"
                   && migrationDefaults.bool(
                        forKey: DefaultsKey.unifiedScreenCaptureShortcutMigrated),
                   "the combined capture shortcut preserves an enabled recording shortcut")
            Defaults.migrateRestoredScreenCaptureShortcuts(in: migrationDefaults)
            suite.expect(!migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
                   && migrationDefaults.bool(forKey: DefaultsKey.recorderShortcutEnabled)
                   && migrationDefaults.bool(
                        forKey: DefaultsKey.restoredScreenCaptureShortcutsMigrated),
                   "restoring dedicated shortcuts removes the duplicate general registration")
            migrationDefaults.set(true, forKey: DefaultsKey.screenshotShortcutEnabled)
            migrationDefaults.set("command:12", forKey: DefaultsKey.recorderShortcut)
            Defaults.migrateUnifiedScreenCaptureShortcut(in: migrationDefaults)
            suite.expect(migrationDefaults.string(forKey: DefaultsKey.screenshotShortcut)
                   == "control+option:42",
                   "the capture shortcut migration runs once and preserves later choices")
            migrationDefaults.removeObject(
                forKey: DefaultsKey.restoredScreenCaptureShortcutsMigrated)
            Defaults.migrateRestoredScreenCaptureShortcuts(in: migrationDefaults)
            suite.expect(migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled),
                   "a distinct general capture shortcut stays enabled when dedicated ones return")
            migrationDefaults.set(true, forKey: AppFeature.screenRecorder.availabilityKey)
            migrationDefaults.set(true, forKey: AppFeature.screenOCR.availabilityKey)
            Defaults.migrateOrphanedCaptureShortcut(in: migrationDefaults)
            suite.expect(migrationDefaults.bool(forKey: DefaultsKey.screenOCRShortcutEnabled)
                   && migrationDefaults.string(forKey: DefaultsKey.screenOCRShortcut)
                        == "control+option:42"
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
                   && migrationDefaults.string(forKey: DefaultsKey.recorderShortcut)
                        == "command:12",
                   "an orphaned capture shortcut moves to the first available tool without its own")
            migrationDefaults.set(true, forKey: DefaultsKey.screenshotShortcutEnabled)
            migrationDefaults.set(false, forKey: DefaultsKey.screenOCRShortcutEnabled)
            Defaults.migrateOrphanedCaptureShortcut(in: migrationDefaults)
            suite.expect(migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenOCRShortcutEnabled),
                   "the orphaned capture shortcut migration runs once")
            migrationDefaults.removeObject(forKey: DefaultsKey.orphanedCaptureShortcutMigrated)
            migrationDefaults.set(true, forKey: AppFeature.screenshot.availabilityKey)
            Defaults.migrateOrphanedCaptureShortcut(in: migrationDefaults)
            suite.expect(migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenOCRShortcutEnabled)
                   && migrationDefaults.bool(
                        forKey: DefaultsKey.orphanedCaptureShortcutMigrated),
                   "a setup that kept the screenshot tool keeps its capture shortcut untouched")
            migrationDefaults.removeObject(forKey: DefaultsKey.orphanedCaptureShortcutMigrated)
            migrationDefaults.removeObject(forKey: DefaultsKey.screenshotShortcut)
            migrationDefaults.removeObject(forKey: DefaultsKey.screenOCRShortcut)
            migrationDefaults.set(false, forKey: AppFeature.screenshot.availabilityKey)
            Defaults.migrateOrphanedCaptureShortcut(in: migrationDefaults)
            suite.expect(migrationDefaults.bool(forKey: DefaultsKey.screenOCRShortcutEnabled)
                   && migrationDefaults.string(forKey: DefaultsKey.screenOCRShortcut)
                        == GlobalShortcut.screenshotDefault.storageValue
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled),
                   "a never-customized capture combination moves as the default combination")
            migrationDefaults.removeObject(forKey: DefaultsKey.orphanedCaptureShortcutMigrated)
            migrationDefaults.set(true, forKey: DefaultsKey.screenshotShortcutEnabled)
            migrationDefaults.set(false, forKey: DefaultsKey.screenOCRShortcutEnabled)
            migrationDefaults.set(true, forKey: AppFeature.colorPicker.availabilityKey)
            Defaults.migrateOrphanedCaptureShortcut(in: migrationDefaults)
            suite.expect(migrationDefaults.bool(forKey: DefaultsKey.colorPickerShortcutEnabled)
                   && migrationDefaults.string(forKey: DefaultsKey.colorPickerShortcut)
                        == GlobalShortcut.screenshotDefault.storageValue
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenOCRShortcutEnabled)
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled),
                   "a switched-off but customized shortcut is kept and the next tool takes over")
            migrationDefaults.removePersistentDomain(forName: shortcutSuite)
        } else {
            suite.expect(false, "test suite defaults are available")
        }
        suite.expect(registeredDefaults[DefaultsKey.switcherIconRowMode] as? Bool == false,
               "App Switcher icon-row mode is optional")
        suite.expect(registeredDefaults[DefaultsKey.switcherSimpleMode] as? Bool == false,
               "App Switcher simple mode preserves previews until requested")
        suite.expect(registeredDefaults[DefaultsKey.switcherShowShortcutHints] as? Bool == true
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherShowShortcutHints),
               "App Switcher keeps shortcut hints visible by default and carries the choice in backups")
        suite.expect(registeredDefaults[DefaultsKey.switcherAppearanceDelay] as? Int
               == SwitcherSupport.defaultAppearanceDelayMilliseconds
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherAppearanceDelay),
               "App Switcher keeps the current appearance delay by default and carries the choice in backups")
        suite.expect(SwitcherSupport.appearanceDelayMillisecondsRange
               .contains(SwitcherSupport.defaultAppearanceDelayMilliseconds),
               "the default App Switcher appearance delay is one the slider accepts")
        suite.expect(SwitcherSupport.sanitizedAppearanceDelay(milliseconds: 0) == 0,
               "the App Switcher can appear immediately when requested")
        suite.expect(SwitcherSupport.sanitizedAppearanceDelay(milliseconds: -1)
               == SwitcherSupport.appearanceDelayMillisecondsRange.lowerBound
               && SwitcherSupport.sanitizedAppearanceDelay(milliseconds: 9_000)
               == SwitcherSupport.appearanceDelayMillisecondsRange.upperBound,
               "an App Switcher appearance delay outside the range is clamped to it")
        suite.expectClose(SwitcherSupport.appearanceDelay(milliseconds: 125), 0.125,
                    "the stored App Switcher milliseconds drive the panel timer in seconds")
        suite.expect(SwitcherSupport.usesIconRowLayout(iconRowMode: false, simpleMode: true),
               "App Switcher simple mode always uses the app icon row")
        suite.expect(SwitcherSupport.usesWindowRow(simpleMode: true,
                                             mergeWindowsByApp: false,
                                             sessionScope: .allApps)
               && !SwitcherSupport.usesWindowRow(simpleMode: true,
                                                  mergeWindowsByApp: true,
                                                  sessionScope: .allApps)
               && SwitcherSupport.usesWindowRow(simpleMode: true,
                                                 mergeWindowsByApp: true,
                                                 sessionScope: .frontmostApp)
               && !SwitcherSupport.usesWindowRow(simpleMode: false,
                                                  mergeWindowsByApp: false,
                                                  sessionScope: .allApps),
               "App Switcher groups all-app sessions but keeps window-scoped simple sessions per-window")
        // The session-start layout pass reads usesWindowRow, which now depends
        // on the session scope; teardown resets the scope to .allApps, so the
        // scope must be assigned before the layout pass or a window-scoped
        // panel is sized for the grouped layout on its first frame.
        let switcherSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Switcher/AppSwitcher.swift",
            encoding: .utf8)) ?? ""
        // Ends on whatever declaration comes next rather than naming the
        // neighbour: a rename would find no separator, leave the slice running
        // to end of file, and quietly restore the whole-file search this
        // replaced — a failure that makes the slice bigger, so an empty check
        // cannot see it. Hence the count assertion below.
        let finishSessionParts = (switcherSource.components(separatedBy: "private func finishPendingSession")
            .last ?? "").components(separatedBy: "\n    private func ")
        let finishSessionBody = finishSessionParts.first ?? ""
        suite.expect(finishSessionParts.count > 1,
               "the App Switcher ordering guard finds the end of finishPendingSession")
        let switcherCode = finishSessionBody
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let scopeAssign = switcherCode.range(of: "sessionScope = pending.scope")
        let startLayout = switcherCode.range(of: "recomputeLayouts(for: list)")
        suite.expect(!finishSessionBody.isEmpty,
               "the App Switcher session-start ordering guard finds finishPendingSession")
        suite.expect(scopeAssign != nil && startLayout != nil
               && scopeAssign!.lowerBound < startLayout!.lowerBound,
               "the App Switcher session scope is assigned before the session-start layout pass")
        // Trimming the list to one display (issue #1391) can drop the window
        // that was in front, and then index 0 is no longer where the session
        // started. The initial selection has to follow what the list holds.
        suite.expect(!switcherCode.contains("hasForegroundItem: source != nil")
               && switcherCode.contains("hasForegroundItem: listedSource != nil"),
               "the App Switcher initial selection follows the window the trimmed list still holds")
        suite.expect(!SwitcherSupport.usesAppGroupsForMainShortcut(iconRowLayout: true,
                                                              windowRow: true)
               && SwitcherSupport.usesAppGroupsForMainShortcut(iconRowLayout: true,
                                                                windowRow: false),
               "App Switcher main shortcut steps through simple window rows without app grouping")
        suite.expect(SwitcherSupport.preservesGroupedWindowsDuringEnumeration(allApps: true,
                                                                        mergeWindowsByApp: true,
                                                                        simpleMode: true)
               && !SwitcherSupport.preservesGroupedWindowsDuringEnumeration(allApps: true,
                                                                             mergeWindowsByApp: true,
                                                                             simpleMode: false)
               && !SwitcherSupport.preservesGroupedWindowsDuringEnumeration(allApps: false,
                                                                             mergeWindowsByApp: true,
                                                                             simpleMode: true)
               && !SwitcherSupport.preservesGroupedWindowsDuringEnumeration(allApps: true,
                                                                             mergeWindowsByApp: false,
                                                                             simpleMode: true),
               "App Switcher preserves backing windows only for the grouped simple row")
        suite.expect(!SwitcherSupport.capturesPreviews(simpleMode: true),
               "App Switcher simple mode never captures window previews")
        suite.expect(!SwitcherSupport.needsScreenRecording(switcherEnabled: true,
                                                      simpleMode: true,
                                                      dockPreviewEnabled: false),
               "App Switcher simple mode alone does not request Screen Recording")
        suite.expect(SwitcherSupport.needsScreenRecording(switcherEnabled: true,
                                                    simpleMode: false,
                                                    dockPreviewEnabled: false)
               && SwitcherSupport.needsScreenRecording(switcherEnabled: false,
                                                        simpleMode: true,
                                                        dockPreviewEnabled: true),
               "window previews still request Screen Recording where needed")
        suite.expect(SwitcherSupport.shouldPausePreviewCapture(
            frontmostBundleIdentifier: "com.example.focused",
            excludedBundleIdentifiers: ["com.example.focused"]),
               "window preview capture pauses while a chosen app is in front")
        suite.expect(!SwitcherSupport.shouldPausePreviewCapture(
            frontmostBundleIdentifier: "com.example.other",
            excludedBundleIdentifiers: ["com.example.focused"])
               && !SwitcherSupport.shouldPausePreviewCapture(
                   frontmostBundleIdentifier: nil,
                   excludedBundleIdentifiers: ["com.example.focused"]),
               "window preview capture continues away from chosen apps or without a foreground app")
        suite.expect(SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [4], visibleSpaces: [3]),
               "a window whose only Space is not visible is parked on a hidden Space")
        suite.expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [3], visibleSpaces: [3]),
               "a window on the visible Space is not parked")
        suite.expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [], visibleSpaces: [3]),
               "a surface on no Space is a leftover, never a parked window")
        suite.expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [4], visibleSpaces: []),
               "an unreadable visible-Space set never claims a parked window")
        suite.expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [3, 4], visibleSpaces: [3]),
               "a window pinned to several Spaces including a visible one is reachable")
        suite.expect(SpaceHopSupport.isOnFullscreenSpace(windowSpaces: [4, 8], fullscreenSpaces: [8])
               && !SpaceHopSupport.isOnFullscreenSpace(windowSpaces: [4], fullscreenSpaces: [8])
               && !SpaceHopSupport.isOnFullscreenSpace(windowSpaces: [], fullscreenSpaces: [8]),
               "App Switcher identifies fullscreen from Space type instead of window size")
        suite.expect(SpaceHopSupport.isExcludedFromWindowCycle(windowTagsLow: 1 << 18),
               "a window-server surface marked to ignore cycling is excluded from the switcher")
        suite.expect(!SpaceHopSupport.isExcludedFromWindowCycle(windowTagsLow: (1 << 19) | (1 << 22)),
               "other window-server tags do not hide a legitimate cross-Space window")
        suite.expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4, 5]],
                                          visibleSpaces: [3],
                                          target: 5) == 2,
               "space travel counts the presses to the right")
        suite.expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4, 5]],
                                          visibleSpaces: [5],
                                          target: 3) == -2,
               "space travel counts the presses to the left")
        suite.expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4]],
                                          visibleSpaces: [3],
                                          target: 3) == nil,
               "space travel is never suggested toward a visible Space")
        suite.expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4]],
                                          visibleSpaces: [3],
                                          target: 9) == nil,
               "space travel is never suggested toward an unknown Space")
        suite.expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4], [8, 9]],
                                          visibleSpaces: [3, 8],
                                          target: 9) == 1,
               "space travel counts the presses on the target display when multiple displays exist")
        suite.expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [(0...40).map { UInt64($0) }],
                                          visibleSpaces: [0],
                                          target: 40) == nil,
               "space travel refuses hops beyond the press cap")
        suite.expect(SpaceHopSupport.firstStage(appHasWindowOnVisibleSpace: true) == .moveASpace,
               "an app with a window on the visible Space cannot travel by being activated, so the move is asked for right away")
        suite.expect(SpaceHopSupport.firstStage(appHasWindowOnVisibleSpace: false) == .waitForActivationTravel,
               "an app with no window on the visible Space travels on activation, so that travel is waited on")
        suite.expect(SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x840000) == [.maskControl, .maskSecondaryFn],
               "the registered control+function mask replays with both flags")
        suite.expect(SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x20000 | 0x100000) == [.maskShift, .maskCommand],
               "shift and command translate independently")
        suite.expect(SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x80000) == [.maskAlternate],
               "option translates to the alternate flag")
        let regularBundlePaths: [pid_t: String] = [101: "/Applications/Primary.app"]
        suite.expect(SwitcherSupport.embeddedHostPID(
            helperBundlePath: "/Applications/Primary.app/Contents/Frameworks/Window Helper.app",
            regularBundlePaths: regularBundlePaths
        ) == 101,
               "App Switcher associates an embedded window helper with its regular host app")
        suite.expect(SwitcherSupport.embeddedHostPID(
            helperBundlePath: "/Applications/Primary Tools.app/Contents/Helper.app",
            regularBundlePaths: regularBundlePaths
        ) == nil,
               "App Switcher does not associate apps whose paths only share a prefix")
        suite.expect(SwitcherSupport.embeddedHostPID(
            helperBundlePath: "/Applications/Independent Helper.app",
            regularBundlePaths: regularBundlePaths
        ) == nil,
               "App Switcher leaves unrelated accessory apps independent")
        let embeddedHostPIDs: [pid_t: pid_t] = [202: 101, 203: 101, 302: 301]
        suite.expect(SwitcherSupport.accessibilityPIDs(
            regularAppPIDs: Set<pid_t>([101, 301, 999]),
            embeddedHostPIDs: embeddedHostPIDs,
            ownPID: 999,
            filterPID: nil
        ) == Set<pid_t>([101, 202, 203, 301, 302]),
               "App Switcher keeps embedded helpers eligible for Accessibility-only windows")
        suite.expect(SwitcherSupport.accessibilityPIDs(
            regularAppPIDs: Set<pid_t>([101, 301, 999]),
            embeddedHostPIDs: embeddedHostPIDs,
            ownPID: 999,
            filterPID: 101
        ) == Set<pid_t>([101, 202, 203]),
               "a single-app enumeration keeps that app and all of its embedded helpers")
        let embeddedWindow = SwitcherItem.window(id: 77,
                                                 title: "Project",
                                                 appName: "Primary",
                                                 pid: 101,
                                                 windowOwnerPID: 202,
                                                 isOnScreen: true,
                                                 frame: CGRect(x: 20, y: 20, width: 900, height: 600))
        suite.expect(embeddedWindow.pid == 101
               && embeddedWindow.windowOwnerPID == 202
               && embeddedWindow.previewWindowID == 77,
               "App Switcher keeps regular app identity separate from the window owner")
        let windowlessEntry = SwitcherItem.appOnly(appName: "Primary", pid: 101)
        suite.expect(embeddedWindow.windowLabel(noOpenWindow: "No open window") == "Project"
               && windowlessEntry.windowLabel(noOpenWindow: "No open window") == "No open window",
               "App Switcher preview labels name a window or explain that there is none")
        let dockIconBundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-dock-icon-\(UUID().uuidString).app")
        let dockIconResources = dockIconBundle.appendingPathComponent("Contents/Resources")
        try? FileManager.default.createDirectory(at: dockIconResources,
                                                 withIntermediateDirectories: true)
        let lightDockIcon = dockIconResources.appendingPathComponent("chosen-light.png")
        let darkDockIcon = dockIconResources.appendingPathComponent("chosen-dark-color.png")
        FileManager.default.createFile(atPath: lightDockIcon.path, contents: Data([0]))
        FileManager.default.createFile(atPath: darkDockIcon.path, contents: Data([1]))
        suite.expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: dockIconBundle,
                                                       resourceName: "chosen-light.png",
                                                       darkMode: true) == darkDockIcon,
               "App Switcher uses the dark sibling of an explicitly declared Dock icon")
        suite.expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: dockIconBundle,
                                                       resourceName: "chosen-light.png",
                                                       darkMode: false) == lightDockIcon,
               "App Switcher keeps the declared Dock icon in its matching appearance")
        suite.expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: dockIconBundle,
                                                       resourceName: "chosen-dark-color.png",
                                                       darkMode: false) == lightDockIcon,
               "App Switcher finds the light sibling when the declared icon is dark")
        let outsideDockIcon = dockIconBundle.appendingPathComponent("outside.png")
        suite.expect(FileManager.default.createFile(atPath: outsideDockIcon.path, contents: Data([2])),
               "the rejected icon exists so confinement is actually exercised")
        try? FileManager.default.createSymbolicLink(
            at: dockIconResources.appendingPathComponent("escape.png"),
            withDestinationURL: outsideDockIcon)
        for unsafeName in ["../../outside.png", outsideDockIcon.path, "escape.png", ".", "", "missing.png"] {
            suite.expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: dockIconBundle,
                                                           resourceName: unsafeName,
                                                           darkMode: true) == nil,
                   "App Switcher rejects an invalid or out-of-resources icon: \(unsafeName)")
        }
        try? FileManager.default.removeItem(at: darkDockIcon)
        suite.expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: dockIconBundle,
                                                       resourceName: "chosen-light.png",
                                                       darkMode: true) == lightDockIcon,
               "App Switcher preserves the declared icon when no appearance sibling exists")
        let linkedDockIconBundle = dockIconBundle.appendingPathComponent("Linked.app")
        try? FileManager.default.createDirectory(
            at: linkedDockIconBundle.appendingPathComponent("Contents"),
            withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(
            at: linkedDockIconBundle.appendingPathComponent("Contents/Resources"),
            withDestinationURL: dockIconResources)
        suite.expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: linkedDockIconBundle,
                                                       resourceName: "chosen-light.png",
                                                       darkMode: false) == nil,
               "App Switcher rejects a Resources directory pointing outside its app bundle")
        try? FileManager.default.removeItem(at: dockIconBundle)
        let hiddenSpaceWindow = embeddedWindow.withHiddenSpaceState(true)
        let minimizedHiddenSpaceWindow = hiddenSpaceWindow.withMinimized(true)
        suite.expect(hiddenSpaceWindow.isOnHiddenSpace
               && minimizedHiddenSpaceWindow.windowOwnerPID == 202
               && minimizedHiddenSpaceWindow.isOnHiddenSpace,
               "App Switcher preserves window ownership and other-desktop state across updates")

        // MARK: Hidden app windows (issue #656)
        let hiddenAppWindow = SwitcherItem.window(id: 79,
                                                  title: "Hidden Project",
                                                  appName: "Primary",
                                                  pid: 101,
                                                  isOnScreen: false,
                                                  isAppHidden: true,
                                                  frame: CGRect(x: 20, y: 20, width: 900, height: 600))
        suite.expect(hiddenAppWindow.isAppHidden
               && hiddenAppWindow.withMinimized(true).isAppHidden
               && SwitcherItem.appOnly(appName: "Primary", pid: 101,
                                       isAppHidden: true).isAppHidden,
               "App Switcher carries a hidden app's state through every entry shape")
        suite.expect(SwitcherSupport.isConfirmedHiddenAppWindow(appIsHidden: true,
                                                          windowSpaces: [3])
               && !SwitcherSupport.isConfirmedHiddenAppWindow(appIsHidden: false,
                                                              windowSpaces: [3])
               && !SwitcherSupport.isConfirmedHiddenAppWindow(appIsHidden: true,
                                                              windowSpaces: []),
               "App Switcher keeps only hidden-app surfaces assigned to a real desktop")

        // MARK: Hidden apps follow the minimized-windows placement (issue #1512)
        suite.expect(hiddenAppWindow.isMinimizedOrAppHidden
               && SwitcherItem.appOnly(appName: "Primary", pid: 101,
                                       isAppHidden: true).isMinimizedOrAppHidden
               && embeddedWindow.withMinimized(true).isMinimizedOrAppHidden
               && !embeddedWindow.isMinimizedOrAppHidden,
               "the minimized-windows placement sets aside an app hidden with Cmd+H exactly as it does a minimized window")
        let placementCode = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Switcher/WindowEnumerator.swift",
            encoding: .utf8)) ?? ""
        suite.expect(placementCode.contains(".isMinimizedOrAppHidden"),
               "window enumeration decides the minimized-windows placement through the shared predicate")

        // Real parked windows remain ordered in; a dismissed surface can
        // retain the same desktop assignment but is explicitly ordered out.
        for visibleSpaces: Set<UInt64> in [[1], [2]] {
            let hidden = SpaceHopSupport.isParkedOnHiddenSpace(
                windowSpaces: [visibleSpaces.contains(1) ? 2 : 1], visibleSpaces: visibleSpaces)
            for ordered in [true, false] {
                for fallback in [true, false] {
                    suite.expect(SwitcherSupport.keepsUnmatchedWindow(
                        isOnHiddenSpace: hidden, isConfirmedHiddenAppWindow: false,
                        isExcludedFromWindowCycle: false, isOrderedIn: ordered,
                        allowsUnverifiedHiddenSpace: fallback) == (ordered || fallback),
                           "ordering recovers parked siblings without removing the earlier minimized or fullscreen exceptions")
                }
            }
        }
        for hidden in [true, false] {
            for hiddenApp in [true, false] {
                for excluded in [true, false] {
                    for ordered: Bool? in [true, false, nil] {
                        for fallback in [true, false] {
                            let keep = SwitcherSupport.keepsUnmatchedWindow(
                                isOnHiddenSpace: hidden, isConfirmedHiddenAppWindow: hiddenApp,
                                isExcludedFromWindowCycle: excluded, isOrderedIn: ordered,
                                allowsUnverifiedHiddenSpace: fallback)
                            if excluded { suite.expect(!keep, "cycle-excluded helpers never reappear") }
                            else if hiddenApp { suite.expect(keep, "hiding an app is not closing its windows") }
                            else if !hidden { suite.expect(!keep, "an unmatched visible-desktop surface is not a parked window") }
                            else if ordered == nil {
                                suite.expect(keep == fallback, "an unavailable ordering query preserves the earlier desktop fallback")
                            }
                        }
                    }
                }
            }
        }
        DockPreviewScopeTests.run(suite)

        // MARK: Stale surfaces without an Accessibility witness (issue #807)

        suite.expect(!SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: true,
                                                             canResolveSpaces: true,
                                                             windowSpacesCount: 0),
               "App Switcher keeps a visible surface even when its app never answered Accessibility")
        suite.expect(!SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: false,
                                                             canResolveSpaces: true,
                                                             windowSpacesCount: 2),
               "App Switcher keeps an off-screen surface the window server parked on a desktop")
        suite.expect(!SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: false,
                                                             canResolveSpaces: true,
                                                             windowSpacesCount: 7),
               "App Switcher keeps an off-screen surface assigned to any desktop, visible or not")
        suite.expect(SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: false,
                                                            canResolveSpaces: true,
                                                            windowSpacesCount: 0),
               "App Switcher drops an off-screen surface that belongs to no desktop at all")
        suite.expect(!SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: true,
                                                             canResolveSpaces: true,
                                                             windowSpacesCount: 0)
               && !SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: false,
                                                                canResolveSpaces: false,
                                                                windowSpacesCount: 0),
               "App Switcher keeps the old behavior when the desktop queries are unavailable")
        suite.expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow])?.id == embeddedWindow.id,
               "App Switcher can start when the foreground app is represented")
        suite.expect(SwitcherSupport.sessionSourceItem(frontmostPID: 202,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow])?.id == embeddedWindow.id,
               "App Switcher can start when an embedded helper owns the foreground window")
        let offscreenWindow = SwitcherItem.window(id: 78,
                                                  title: "Archive",
                                                  appName: "Primary",
                                                  pid: 101,
                                                  isOnScreen: false,
                                                  frame: CGRect(x: 20, y: 20, width: 900, height: 600))
        suite.expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: nil,
                                                 items: [offscreenWindow]) == nil,
               "App Switcher does not treat an old off-screen window as the foreground surface")
        suite.expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: 78,
                                                 items: [offscreenWindow])?.id == offscreenWindow.id,
               "App Switcher accepts an Accessibility-focused window from outside the CG list")
        suite.expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: nil,
                                                 items: [offscreenWindow, embeddedWindow])?.id == embeddedWindow.id,
               "App Switcher chooses the on-screen source over an older window from the same app")
        suite.expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: 78,
                                                 items: [offscreenWindow, embeddedWindow])?.id == offscreenWindow.id,
               "App Switcher gives the exact focused source priority over CG ordering")
        suite.expect(SwitcherSupport.sessionSourceItem(frontmostPID: 404,
                                                 focusedWindowID: nil,
                                                 items: [.appOnly(appName: "Desktop", pid: 404)])?.id == "a:404",
               "App Switcher accepts its intentional app-only desktop entry")
        suite.expect(SwitcherSupport.sessionSourceItem(frontmostPID: 303,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow]) == nil,
               "App Switcher reports no foreground window when the app in front owns none")
        suite.expect(SwitcherSupport.needsFocusedWindowLookup(frontmostPID: 101,
                                                        items: [offscreenWindow]),
               "App Switcher resolves the focused window when no foreground window is visible")
        suite.expect(!SwitcherSupport.needsFocusedWindowLookup(frontmostPID: 101,
                                                         items: [embeddedWindow, offscreenWindow]),
               "App Switcher skips focused-window AX lookup for one visible foreground window")
        let secondVisibleWindow = SwitcherItem.window(id: 79,
                                                      title: "Second",
                                                      appName: "Primary",
                                                      pid: 101,
                                                      isOnScreen: true,
                                                      frame: CGRect(x: 40, y: 40,
                                                                    width: 800, height: 500))
        suite.expect(SwitcherSupport.needsFocusedWindowLookup(frontmostPID: 101,
                                                        items: [embeddedWindow, secondVisibleWindow]),
               "App Switcher resolves the focused window for multiple visible foreground windows")
        suite.expect(SwitcherSupport.initialSelectionPosition(pids: [101, 202, 303],
                                                        hasForegroundEntry: true,
                                                        frontmostPID: 101,
                                                        reversed: false) == 1,
               "App Switcher starts one step past the foreground window")
        suite.expect(SwitcherSupport.initialSelectionPosition(pids: [101],
                                                        hasForegroundEntry: true,
                                                        frontmostPID: 101,
                                                        reversed: false) == 0,
               "App Switcher stays on the only entry there is")
        suite.expect(SwitcherSupport.initialSelectionPosition(pids: [101, 202, 303],
                                                        hasForegroundEntry: true,
                                                        frontmostPID: 101,
                                                        reversed: true) == 2,
               "App Switcher starts from the far end when the session opens backward")
        suite.expect(SwitcherSupport.initialSelectionPosition(pids: [202, 303],
                                                        hasForegroundEntry: false,
                                                        frontmostPID: 101,
                                                        reversed: false) == 0,
               "App Switcher opens on the first entry when the app in front has no window (issue #324)")
        suite.expect(SwitcherSupport.initialSelectionPosition(pids: [101, 101, 202],
                                                        hasForegroundEntry: false,
                                                        frontmostPID: 101,
                                                        reversed: false) == 2,
               "App Switcher skips the windows the app in front left minimized or on another Space")
        suite.expect(SwitcherSupport.initialSelectionPosition(pids: [101, 101],
                                                        hasForegroundEntry: false,
                                                        frontmostPID: 101,
                                                        reversed: false) == 0,
               "App Switcher still opens when every window belongs to the app in front")
        suite.expect(SwitcherSupport.initialSelectionPosition(pids: [],
                                                        hasForegroundEntry: false,
                                                        frontmostPID: 101,
                                                        reversed: false) == 0,
               "App Switcher keeps the selection in range with nothing to show")
        suite.expect(SwitcherSupport.appPID(forFrontmost: 202, items: [embeddedWindow]) == 101
               && SwitcherSupport.appPID(forFrontmost: 303, items: [embeddedWindow]) == 303,
               "App Switcher reads the app behind an embedded window helper")
        suite.expect(SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: "/usr/local/bin/wine64-preloader",
            localizedName: "wine64-preloader"),
               "App Switcher recognizes a bare compatibility-layer loader process")
        suite.expect(SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: "/Users/u/Library/Bottles/games/winetemp-8f3a21/Launcher",
            localizedName: "Launcher"),
               "App Switcher recognizes a bottle loader renamed after its hosted program")
        suite.expect(!SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: "com.example.native",
            executablePath: "/Applications/Native.app/Contents/MacOS/wine64-preloader",
            localizedName: "wine64-preloader"),
               "App Switcher never relaxes window rules for bundled apps")
        suite.expect(!SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: "/usr/bin/python3",
            localizedName: "python3"),
               "App Switcher leaves ordinary unbundled processes alone")
        suite.expect(SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: nil,
            localizedName: "wine-preloader"),
               "App Switcher falls back to the process name when the executable is unknown")
        suite.expect(!SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: nil,
            localizedName: nil),
               "App Switcher requires a positive signal before relaxing window rules")
        suite.expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.AfterEffects.application",
            subrole: "AXFloatingWindow"),
               "App Switcher accepts supported media windows with current bundle suffixes")
        suite.expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.PremierePro.26",
            subrole: "AXFloatingWindow"),
               "App Switcher accepts versioned supported media windows")
        suite.expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.premierepro.2024",
            subrole: "AXFloatingWindow"),
               "App Switcher accepts lowercase supported media bundle identifiers")
        suite.expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.Premiere.15",
            subrole: "AXFloatingWindow"),
               "App Switcher accepts short-form supported media bundle identifiers")
        suite.expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.PremierePro.26",
            subrole: "AXUnknown"),
               "App Switcher accepts undescribed workspace windows from supported media apps")
        suite.expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.mediaencoder.2024",
            subrole: "AXUnknown"),
               "App Switcher accepts helper media engine workspace windows")
        suite.expect(!SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.AfterEffects.application",
            subrole: "AXDialog"),
               "App Switcher does not relax ordinary dialogs from supported media apps")
        suite.expect(!SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.example.editor",
            subrole: "AXFloatingWindow"),
               "App Switcher keeps floating windows from unrelated apps filtered")
        suite.expect(!SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.example.editor",
            subrole: "AXUnknown"),
               "App Switcher keeps undescribed windows from unrelated apps filtered")
        for tags: UInt32 in [786946, 795138] {
            suite.expect(!SwitcherSupport.isSwitchableNonstandardWindow(
                role: "AXWindow",
                subrole: "AXUnknown",
                fillsScreen: false,
                hasNormalWindowLevel: true,
                acceptsUndescribedSubroles: false,
                isExcludedFromWindowCycle: SpaceHopSupport.isExcludedFromWindowCycle(windowTagsLow: tags)),
                   "App Switcher excludes helper windows that opt out of window cycling")
        }
        suite.expect(SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXUnknown",
            fillsScreen: true,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: false),
               "App Switcher accepts a screen-sized window with a nonstandard subrole")
        suite.expect(SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXFloatingWindow",
            fillsScreen: true,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: false),
               "App Switcher accepts a screen-sized floating playback surface")
        suite.expect(!SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXUnknown",
            fillsScreen: false,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: false),
               "App Switcher filters a smaller window with a nonstandard subrole")
        suite.expect(!SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXGroup",
            subrole: "AXUnknown",
            fillsScreen: true,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: false),
               "App Switcher requires a real window role for a full-screen surface")
        suite.expect(!SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXDialog",
            fillsScreen: true,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: false),
               "App Switcher does not turn a screen-sized dialog into a playback window")
        suite.expect(SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXUnknown",
            fillsScreen: false,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: true),
               "App Switcher preserves hosted windows with custom chrome")
        suite.expect(SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXUnknown",
            fillsScreen: false,
            hasNormalWindowLevel: true,
            acceptsUndescribedSubroles: false),
               "App Switcher accepts an ordinary window from an app that describes none")
        suite.expect(!SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXFloatingWindow",
            fillsScreen: false,
            hasNormalWindowLevel: true,
            acceptsUndescribedSubroles: false),
               "App Switcher keeps a described floating panel filtered at the normal window level")
        suite.expect(SwitcherSupport.sessionSourceItem(frontmostPID: nil,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow]) == nil,
               "App Switcher leaves the system shortcut alone without a foreground app")
        suite.expect(registeredDefaults[DefaultsKey.switcherShowWindowlessFinder] as? Bool == true,
               "the retired windowless Finder toggle keeps its shipped value so the migration can read it")
        suite.expect(registeredDefaults[DefaultsKey.switcherWindowlessApps] as? String
               == SwitcherWindowlessApps.finder.rawValue,
               "the switcher offers the desktop app without windows, and nothing else, by default")
        suite.expect((registeredDefaults[DefaultsKey.switcherAppRules] as? [String: String])?.isEmpty == true,
               "per-app switcher rules start empty, so existing choices stay unchanged")
        suite.expect(registeredDefaults[DefaultsKey.switcherCurrentSpaceOnly] as? Bool == false,
               "the switcher keeps showing every desktop unless the user opts out (issue #337)")
        suite.expect(registeredDefaults[DefaultsKey.switcherTakeOverSystemShortcuts] as? Bool == false
               && SettingsBackupSupport.exportKeys().contains(
                    DefaultsKey.switcherTakeOverSystemShortcuts)
               && registeredDefaults[DefaultsKey.switcherNativeHotkeysSuppressed] == nil
               && !SettingsBackupSupport.exportKeys().contains(
                    DefaultsKey.switcherNativeHotkeysSuppressed)
               && registeredDefaults[DefaultsKey.systemShortcutsSuppressed] == nil
               && !SettingsBackupSupport.exportKeys().contains(
                    DefaultsKey.systemShortcutsSuppressed),
               "native shortcut takeover is opt-in while both crash markers stay on this Mac")
        suite.expect(registeredDefaults[DefaultsKey.switcherSearchPinEnabled] as? Bool == false
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherSearchPinEnabled),
               "the optional pinned search starts off and travels with the user's settings backup")
        suite.expect(registeredDefaults[DefaultsKey.switcherMinimizedPlacement] as? String
               == WindowSwitchMinimizedPlacement.normal.rawValue
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherMinimizedPlacement),
               "App Switcher leaves minimized windows in normal order by default and carries the choice in backups")
        suite.expect(registeredDefaults[DefaultsKey.switcherShowFullscreenWindows] as? Bool == true
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherShowFullscreenWindows),
               "App Switcher keeps fullscreen windows visible by default and carries the choice in backups")
        suite.expect(WindowSwitchMinimizedPlacement.allCases.map(\.rawValue) == ["normal", "end", "hidden"],
               "every minimized placement case has a stable raw value")

        // MARK: Which display the switcher opens on
        suite.expect(registeredDefaults[DefaultsKey.switcherScreenPlacement] as? String
               == SwitcherScreenPlacement.pointer.rawValue
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherScreenPlacement),
               "App Switcher keeps opening on the pointer's screen by default and carries the choice in backups")
        suite.expect(SwitcherScreenPlacement.placement(storedValue: nil) == .pointer
               && SwitcherScreenPlacement.placement(storedValue: "") == .pointer
               && SwitcherScreenPlacement.placement(storedValue: "bogus") == .pointer,
               "an unset or unreadable screen placement falls back to the pointer's screen")
        suite.expect(SwitcherScreenPlacement.allCases.map(\.rawValue) == ["pointer", "menuBar", "activeWindow"]
               && SwitcherScreenPlacement.allCases.allSatisfy {
                   SwitcherScreenPlacement.placement(storedValue: $0.rawValue) == $0
               },
               "every screen placement choice has a stable raw value that survives preferences")
        let leftDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rightDisplay = CGRect(x: 1920, y: 0, width: 1440, height: 900)
        suite.expect(SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 2000, y: 100, width: 800, height: 600),
                                            displayBounds: [leftDisplay, rightDisplay]) == 1,
               "a window inside one display resolves to that display")
        suite.expect(SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 1500, y: 100, width: 1000, height: 600),
                                            displayBounds: [leftDisplay, rightDisplay]) == 1
               && SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 1500, y: 100, width: 700, height: 600),
                                               displayBounds: [leftDisplay, rightDisplay]) == 0,
               "a window straddling two displays belongs to the one showing more of it, whichever comes first")
        // Window-server coordinates grow downward, so a display below the
        // menu bar display has a positive y origin. An AppKit frame for the
        // same window would carry a negative y and land on the wrong display.
        let upperDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let lowerDisplay = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        suite.expect(SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 200, y: 1300, width: 800, height: 600),
                                            displayBounds: [upperDisplay, lowerDisplay]) == 1
               && SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 200, y: -800, width: 800, height: 600),
                                               displayBounds: [upperDisplay, lowerDisplay]) == nil,
               "stacked displays resolve by window-server y, and a bottom-left-origin frame would touch no display")
        suite.expect(SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 5000, y: 100, width: 800, height: 600),
                                            displayBounds: [leftDisplay, rightDisplay]) == nil
               && SwitcherSupport.displayIndex(showingMostOf: .zero, displayBounds: [leftDisplay, rightDisplay]) == nil
               && SwitcherSupport.displayIndex(showingMostOf: leftDisplay, displayBounds: []) == nil,
               "a window touching no display, an entry without a frame, or no display at all leave the screen to the fallback")

        // MARK: The switcher list held to one display (issue #1391)
        suite.expect(registeredDefaults[DefaultsKey.switcherCurrentDisplayOnly] as? Bool == false
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherCurrentDisplayOnly),
               "the App Switcher lists every display by default and carries the choice in backups")
        func displayScopedItem(_ name: String, frame: CGRect, windowID: CGWindowID?) -> SwitcherItem {
            SwitcherItem(id: name, title: name, appName: name,
                         pid: 1, windowOwnerPID: 1, windowID: windowID,
                         isOnScreen: true, isAppHidden: false, isMinimized: false,
                         isFullscreen: false, isOnHiddenSpace: false, frame: frame)
        }
        let onLeftDisplay = displayScopedItem("left",
                                              frame: CGRect(x: 100, y: 100, width: 800, height: 600),
                                              windowID: 1)
        let onRightDisplay = displayScopedItem("right",
                                               frame: CGRect(x: 2100, y: 100, width: 800, height: 600),
                                               windowID: 2)
        let withoutWindow = displayScopedItem("windowless", frame: .zero, windowID: nil)
        let onNoDisplay = displayScopedItem("parked",
                                            frame: CGRect(x: 6000, y: 100, width: 800, height: 600),
                                            windowID: 3)
        let bothDisplays = [leftDisplay, rightDisplay]
        suite.expect(SwitcherSupport.itemsOnDisplay([onLeftDisplay, onRightDisplay],
                                              displayBounds: bothDisplays,
                                              targetIndex: 1).map(\.id) == ["right"],
               "holding the switcher to one display drops what the other monitor is showing")
        suite.expect(SwitcherSupport.itemsOnDisplay([onLeftDisplay, onRightDisplay, withoutWindow, onNoDisplay],
                                              displayBounds: bothDisplays,
                                              targetIndex: 0).map(\.id) == ["left"],
               "display filtering excludes windowless apps and windows outside every display")
        suite.expect(SwitcherSupport.itemsOnDisplay([onLeftDisplay, onRightDisplay],
                                              displayBounds: bothDisplays,
                                              targetIndex: 5).isEmpty
               && SwitcherSupport.itemsOnDisplay([onLeftDisplay, onRightDisplay],
                                                 displayBounds: [],
                                                 targetIndex: 0).isEmpty,
               "a missing display never falls back to windows on other monitors")

        suite.expect(SwitcherSupport.itemsOnDisplay([onLeftDisplay, withoutWindow, onNoDisplay],
                                              displayBounds: bothDisplays,
                                              targetIndex: 1).isEmpty,
               "an empty monitor has no switch targets, including windowless apps")
        let displayFilterBody = (switcherSource.components(separatedBy: "private var currentDisplayScope")
            .last ?? "").components(separatedBy: "private var placementVisibleFrame").first ?? ""
        suite.expect(displayFilterBody.contains("NSScreen.withMouse?.displayID")
               && displayFilterBody.contains("?? -1"),
               "display filtering follows the cursor and leaves no target when the display disappears")
        suite.expect(switcherCode.contains("guard !windows.isEmpty else {\n            discardPendingSessionStart(generation: generation)"),
               "an empty display discards the pending session before opening a panel or committing a window")
        let otherScreenRepresentative = SwitcherSupport.groupWindowsByApp([onLeftDisplay, onRightDisplay])
        suite.expect(SwitcherSupport.itemsOnDisplay(otherScreenRepresentative,
                                               displayBounds: bothDisplays, targetIndex: 1).isEmpty,
               "regression fixture reproduces a local window lost when grouping precedes display filtering")
        let localWindows = SwitcherSupport.itemsOnDisplay([onLeftDisplay, onRightDisplay],
                                                          displayBounds: bothDisplays, targetIndex: 1)
        suite.expect(SwitcherSupport.groupWindowsByApp(localWindows).map(\.id) == ["right"],
               "grouping after display filtering retains the same app's window on the target monitor")
        let crowdedOtherDisplay = Array(repeating: onLeftDisplay, count: 24) + [onRightDisplay]
        suite.expect(Array(SwitcherSupport.itemsOnDisplay(crowdedOtherDisplay,
                                                    displayBounds: bothDisplays, targetIndex: 1)
            .prefix(24)).map(\.id) == ["right"],
               "windows on other monitors cannot exhaust the local display's entry limit")
        let enumeratorCode = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Switcher/WindowEnumerator.swift",
            encoding: .utf8)) ?? ""
        let displayFilter = enumeratorCode.range(of: "SwitcherSupport.itemsOnDisplay(filtered,")
        let grouping = enumeratorCode.range(of: "SwitcherSupport.groupWindowsByApp(orderedPrimary)")
        let entryCap = enumeratorCode.range(of: "limit: maximumCount")
        suite.expect(displayFilter != nil && grouping != nil && entryCap != nil
               && displayFilter!.lowerBound < grouping!.lowerBound
               && displayFilter!.lowerBound < entryCap!.lowerBound,
               "enumeration applies the display scope before grouping and capping the list")
        suite.expect(SwitcherSupport.sessionSourceItem(frontmostPID: 1, focusedWindowID: 1,
                                                 items: [onLeftDisplay, onRightDisplay])?.id == "left"
               && !localWindows.contains(where: { $0.id == "left" })
               && switcherCode.contains("items: sourceItems)")
               && enumeratorCode.contains("sourceItems: sourceCandidates"),
               "activation retains the foreground window even when the displayed list excludes its monitor")
        let displaySnapshot = switcherSource.range(of: "let displayScope = currentDisplayScope")
        let enumerationDispatch = switcherSource.range(of: "enumerationQueue.async")
        suite.expect(displaySnapshot != nil && enumerationDispatch != nil
               && displaySnapshot!.lowerBound < enumerationDispatch!.lowerBound,
               "the target display is captured before window enumeration can delay the session")

        // MARK: Switcher entries for apps with no window (issue #351)
        suite.expect(SwitcherWindowlessApps.mode(storedValue: nil,
                                           takeOverSystemShortcuts: false) == .finder
               && SwitcherWindowlessApps.mode(storedValue: "",
                                              takeOverSystemShortcuts: false) == .finder
               && SwitcherWindowlessApps.mode(storedValue: "bogus",
                                              takeOverSystemShortcuts: false) == .finder,
               "an unset or unreadable windowless apps choice falls back to what the app shipped with")
        suite.expect(SwitcherWindowlessApps.mode(storedValue: "off",
                                           takeOverSystemShortcuts: false) == .off
               && SwitcherWindowlessApps.mode(storedValue: "finder",
                                              takeOverSystemShortcuts: false) == .finder
               && SwitcherWindowlessApps.mode(storedValue: "all",
                                              takeOverSystemShortcuts: false) == .all,
               "every windowless apps choice survives a round trip through preferences")
        suite.expect(SwitcherWindowlessApps.mode(storedValue: "off",
                                           takeOverSystemShortcuts: true) == .all,
               "native shortcut takeover keeps every running app reachable")
        suite.expect(SwitcherWindowlessApps.migrated(showsWindowlessFinder: true) == .finder
               && SwitcherWindowlessApps.migrated(showsWindowlessFinder: false) == .off,
               "the old windowless Finder toggle maps onto the choice that keeps its behavior")

        let desktopApp = SwitcherAppCandidate(pid: 501, bundleIdentifier: Defaults.finderBundleIdentifier)
        let plainApp = SwitcherAppCandidate(pid: 502, bundleIdentifier: "com.example.editor")
        let otherApp = SwitcherAppCandidate(pid: 503, bundleIdentifier: "com.example.notes")
        let windowlessCandidates = [desktopApp, plainApp, otherApp]
        let sanitizedAppRules = SwitcherAppRule.rules(storedValue: [
            " com.example.editor ": SwitcherAppRule.showWithoutWindows.rawValue,
            "com.example.notes": SwitcherAppRule.hidden.rawValue,
            "com.example.broken": "unknown",
            "": SwitcherAppRule.windowsOnly.rawValue,
        ])
        suite.expect(sanitizedAppRules == [
            "com.example.editor": .showWithoutWindows,
            "com.example.notes": .hidden,
        ], "per-app switcher rules trim identities and drop unreadable entries")
        suite.expect(SwitcherAppRule.storedValue(sanitizedAppRules) == [
            "com.example.editor": SwitcherAppRule.showWithoutWindows.rawValue,
            "com.example.notes": SwitcherAppRule.hidden.rawValue,
        ], "per-app switcher rules keep only portable bundle identities and known choices")
        suite.expect(SwitcherSupport.windowlessAppPIDs(mode: .off,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [],
                                                 pidsWithWithheldWindows: [],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier).isEmpty,
               "asking for no windowless apps adds none of them")
        suite.expect(SwitcherSupport.windowlessAppPIDs(mode: .finder,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [],
                                                 pidsWithWithheldWindows: [],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier) == [501],
               "asking for the desktop app alone leaves every other windowless app out")
        suite.expect(SwitcherSupport.windowlessAppPIDs(mode: .all,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [],
                                                 pidsWithWithheldWindows: [],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier) == [501, 502, 503],
               "asking for every windowless app keeps them in the order the window server gave")
        suite.expect(SwitcherSupport.windowlessAppPIDs(mode: .all,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [502],
                                                 pidsWithWithheldWindows: [],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier) == [501, 503],
               "an app that already has a window in the list never gets a second entry for itself")
        suite.expect(SwitcherSupport.windowlessAppPIDs(mode: .all,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [],
                                                 pidsWithWithheldWindows: [503],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier) == [501, 502],
               "an app whose windows were held back for being on another desktop stays out (issue #337)")
        suite.expect(SwitcherSupport.windowlessAppPIDs(mode: .finder,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [501],
                                                 pidsWithWithheldWindows: [],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier).isEmpty,
               "the desktop app with a window of its own does not also get an entry for itself")
        suite.expect(SwitcherSupport.windowlessAppPIDs(
                mode: .off,
                candidates: windowlessCandidates,
                pidsWithWindows: [],
                pidsWithWithheldWindows: [],
                desktopAppBundleIdentifier: Defaults.finderBundleIdentifier,
                appRules: ["com.example.editor": .showWithoutWindows]) == [502],
               "an app rule can add one windowless app without turning the global list on")
        suite.expect(SwitcherSupport.windowlessAppPIDs(
                mode: .off,
                candidates: windowlessCandidates,
                pidsWithWindows: [502],
                pidsWithWithheldWindows: [],
                desktopAppBundleIdentifier: Defaults.finderBundleIdentifier,
                appRules: ["com.example.editor": .showWithoutWindows]).isEmpty,
               "an explicit show rule never duplicates an app that already has a window entry")
        suite.expect(SwitcherSupport.windowlessAppPIDs(
                mode: .all,
                candidates: windowlessCandidates,
                pidsWithWindows: [],
                pidsWithWithheldWindows: [],
                desktopAppBundleIdentifier: Defaults.finderBundleIdentifier,
                appRules: ["com.example.editor": .windowsOnly,
                           "com.example.notes": .hidden]) == [501],
               "window-only and hidden rules both keep an app-only entry out of the global list")
        suite.expect(SwitcherSupport.windowlessAppPIDs(
                mode: .off,
                candidates: windowlessCandidates,
                pidsWithWindows: [],
                pidsWithWithheldWindows: [502],
                desktopAppBundleIdentifier: Defaults.finderBundleIdentifier,
                appRules: ["com.example.editor": .showWithoutWindows]).isEmpty,
               "a show rule never restores an app whose windows were withheld on another desktop")
        suite.expect(SwitcherSupport.hidesApp(
                    bundleIdentifier: "com.example.notes",
                    appRules: ["com.example.notes": .hidden])
               && !SwitcherSupport.hidesApp(
                    bundleIdentifier: "com.example.notes",
                    appRules: ["com.example.notes": .windowsOnly])
               && !SwitcherSupport.hidesApp(
                    bundleIdentifier: nil,
                    appRules: ["com.example.notes": .hidden]),
               "only the hidden rule removes an identified app's real windows")

        // MARK: The visible cap spends its slots across apps (issue #172)
        suite.expect(SwitcherSupport.visibleSelectionIndices(appPIDs: [7, 7, 9], limit: 5) == [0, 1, 2],
               "a list that fits under the cap keeps every entry")
        suite.expect(SwitcherSupport.visibleSelectionIndices(appPIDs: [], limit: 5).isEmpty
               && SwitcherSupport.visibleSelectionIndices(appPIDs: [7, 9], limit: 0).isEmpty,
               "an empty list or a cap of nothing selects nothing")
        // The shape that made whole applications disappear: one browser with
        // many windows ahead of every other app in the use order.
        let crowdedPIDs = Array(repeating: pid_t(101), count: 18) + [202, 303, 404, 505]
        let crowdedSurvivors = SwitcherSupport.visibleSelectionIndices(appPIDs: crowdedPIDs, limit: 6)
        suite.expect(Set(crowdedSurvivors.map { crowdedPIDs[$0] }) == [101, 202, 303, 404, 505],
               "an app with many windows never pushes another running app off the list")
        suite.expect(crowdedSurvivors.count == 6,
               "the cap still spends every slot it has")
        suite.expect(crowdedSurvivors == crowdedSurvivors.sorted(),
               "survivors keep the use order they came in, so the toggle target stays put")
        suite.expect(crowdedSurvivors.first == 0,
               "the window the user is looking at stays first")
        suite.expect(crowdedSurvivors.filter { crowdedPIDs[$0] == 101 } == [0, 1],
               "slots left over after every app is represented go to the most recent windows")
        // More apps than slots: the apps compete with each other, in order.
        let manyApps = (1...10).map { pid_t($0 * 11) }
        suite.expect(SwitcherSupport.visibleSelectionIndices(appPIDs: manyApps, limit: 4) == [0, 1, 2, 3],
               "with more apps than slots the least recently used apps are the ones that drop")
        // An app that appears again further down does not claim a second slot
        // before an app that has none yet.
        let interleaved: [pid_t] = [1, 2, 1, 3, 1, 4]
        suite.expect(SwitcherSupport.visibleSelectionIndices(appPIDs: interleaved, limit: 4) == [0, 1, 3, 5],
               "each app is represented once before any app is represented twice")
        // Dock previews and the preview refresh ask for one app's windows, where
        // the selection has to stay exactly what it always was.
        suite.expect(SwitcherSupport.visibleSelectionIndices(appPIDs: Array(repeating: pid_t(7), count: 20),
                                                       limit: 12) == Array(0..<12),
               "a single app's own window list is capped from the front, as before")
        // Review of #1473: with every slot claimed by an app of its own, the
        // window before the current one must still be there, or a quick flick
        // in the grid layout opens another app instead of returning to it.
        let appsFillEverySlot: [pid_t] = [1, 1] + (2...60).map { pid_t($0) }
        let fullListSurvivors = SwitcherSupport.visibleSelectionIndices(appPIDs: appsFillEverySlot, limit: 48)
        suite.expect(Array(fullListSurvivors.prefix(2)) == [0, 1],
               "the window before the current one survives a list where every slot goes to an app")
        suite.expect(fullListSurvivors.count == 48 && fullListSurvivors == fullListSurvivors.sorted(),
               "keeping the toggle target still spends the cap exactly and keeps the use order")
        // Review of #1473: the window shortcut shows the front app alone, so
        // other apps must not take places in its list. 24 recently used
        // windows of that app ahead of 26 other apps used to keep all 24.
        let frontAppWindows = (1...24).map { index in
            SwitcherItem.window(id: CGWindowID(1000 + index), title: "w\(index)", appName: "Front",
                                pid: 1, isOnScreen: true, frame: .zero)
        }
        let otherApps = (2...27).map { pid in
            SwitcherItem.window(id: CGWindowID(2000 + pid), title: "o\(pid)", appName: "Other",
                                pid: pid_t(pid), isOnScreen: true, frame: .zero)
        }
        let windowScopeItems = frontAppWindows + otherApps
        let scopedSurvivors = SwitcherSupport.visibleSelectionIndices(items: windowScopeItems,
                                                                      limit: 48, frontmostPID: 1)
        suite.expect(scopedSurvivors == Array(0..<24),
               "the window shortcut keeps every window of the front app when other apps are running")
        let unscopedSurvivors = SwitcherSupport.visibleSelectionIndices(items: windowScopeItems,
                                                                        limit: 48, frontmostPID: nil)
        suite.expect(unscopedSurvivors.filter { windowScopeItems[$0].pid == 1 }.count < 24
               && Set(unscopedSurvivors.map { windowScopeItems[$0].pid }).count == 27,
               "the all-apps list still spreads its slots so every app stays reachable")
        // The keyboard can belong to a helper process that renders the app's
        // window; the scope resolves it to the app the same way the session does.
        let helperOwned = SwitcherItem.window(id: 3001, title: "h", appName: "Front",
                                              pid: 1, windowOwnerPID: 91, isOnScreen: true, frame: .zero)
        let helperScoped = SwitcherSupport.visibleSelectionIndices(items: [helperOwned] + otherApps,
                                                                   limit: 48, frontmostPID: 91)
        suite.expect(helperScoped == [0],
               "a window-scoped list follows a helper-owned front window to its app")

        // A newly focused window can still have an older rank while the focus
        // watcher catches up. A current server order does not rewrite known history.
        let previousFocusHistory = windowScopeItems.compactMap(\.windowID)
        let currentFocusID = frontAppWindows.last!.windowID!
        let currentServerOrder = [currentFocusID] + previousFocusHistory.filter { $0 != currentFocusID }
        let reconciledFocusHistory = WindowUseOrder.reconciled(previousFocusHistory,
            existing: Set(previousFocusHistory), frontToBack: currentServerOrder)
        suite.expect(reconciledFocusHistory == previousFocusHistory,
               "a fresh server observation can coexist with the previous known focus history")
        let unorderedFocusItems = Array(windowScopeItems.reversed())
        let focusOrder = WindowUseOrder.order(
            unorderedFocusItems.map { WindowUseOrder.Entry(windowID: $0.windowID, pid: $0.pid) },
            windowHistory: reconciledFocusHistory, appHistory: (1...27).map { pid_t($0) },
            frontToBack: currentServerOrder)
        let focusCandidates = focusOrder.map { unorderedFocusItems[$0] }
        let currentSource = SwitcherSupport.sessionSourceItem(frontmostPID: 1,
            focusedWindowID: currentFocusID, items: focusCandidates)
        let preparedFocusItems = SwitcherSupport.orderedForSession(focusCandidates, currentID: currentSource?.id)
        let visibleFocusItems = SwitcherSupport.visibleSelectionIndices(
            items: preparedFocusItems, limit: 48, frontmostPID: nil).map { preparedFocusItems[$0] }
        suite.expect(visibleFocusItems.first?.windowID == currentFocusID,
               "a crowded list keeps the actual current window even when its history rank is old")
        let quickFocusIndex = SwitcherSupport.initialSelectionPosition(pids: visibleFocusItems.map(\.pid),
            hasForegroundEntry: currentSource != nil, frontmostPID: 1, reversed: false)
        suite.expect(visibleFocusItems[quickFocusIndex].windowID == previousFocusHistory.first,
               "a fresh source reading preserves the previous-window target before the cap")
        suite.expect(visibleFocusItems.count == 48 && Set(visibleFocusItems.map(\.pid)).count == 27,
               "retaining the actual source still shares the bounded list across other apps")
        let scopedFocusItems = SwitcherSupport.visibleSelectionIndices(
            items: preparedFocusItems, limit: 48, frontmostPID: 1).map { preparedFocusItems[$0] }
        suite.expect(scopedFocusItems.count == 24 && scopedFocusItems.first?.windowID == currentFocusID,
               "source correction and the app's own window budget work together")
        suite.expect(SwitcherSupport.orderedForSession(focusCandidates, currentID: nil) == focusCandidates
               && SwitcherSupport.orderedForSession(focusCandidates, currentID: "missing") == focusCandidates,
               "an unavailable or removed source leaves the legitimate candidate order unchanged")
        let focusSourceOnOtherDisplay = SwitcherSupport.sessionSourceItem(frontmostPID: onRightDisplay.pid,
            focusedWindowID: onRightDisplay.windowID, items: [onRightDisplay, onLeftDisplay])
        let displayFocusCandidates = SwitcherSupport.itemsOnDisplay([onRightDisplay, onLeftDisplay],
            displayBounds: bothDisplays, targetIndex: 0)
        suite.expect(SwitcherSupport.orderedForSession(displayFocusCandidates,
                                                currentID: focusSourceOnOtherDisplay?.id) == [onLeftDisplay],
               "correcting the source never restores a window excluded by the display filter")
        let groupedFocusItems = SwitcherSupport.expandGroupedWindows(
            orderedWindows: focusCandidates, representatives: SwitcherSupport.groupWindowsByApp(focusCandidates))
        suite.expect(SwitcherSupport.needsFocusedWindowLookup(frontmostPID: 1, items: groupedFocusItems)
               && SwitcherSupport.sessionSourceItem(frontmostPID: 1, focusedWindowID: currentFocusID,
                                                     items: groupedFocusItems)?.windowID == currentFocusID,
               "the grouped simple row keeps its backing windows available for actual focus resolution")
        let sourceResolution = enumeratorCode.range(of: "resolveSource?(sourceCandidates)")
        let sourcePromotion = enumeratorCode.range(of: "SwitcherSupport.orderedForSession(ordered, currentID: source?.id)")
        suite.expect(sourceResolution != nil && sourcePromotion != nil && entryCap != nil
               && sourceResolution!.lowerBound < sourcePromotion!.lowerBound
               && sourcePromotion!.lowerBound < entryCap!.lowerBound,
               "the production enumeration resolves and promotes the current source before limiting entries")

        suite.expect(WindowUseOrder.promoting(target: 7, previous: 3, in: [3, 5, 7]) == [7, 3, 5],
               "committing to a window puts it first and the one left behind second")
        suite.expect(WindowUseOrder.promoting(target: nil, previous: 3, in: [5, 3, 9]) == [3, 5, 9],
               "committing to an app with no window leaves the window behind as the most recent one")
        suite.expect(WindowUseOrder.promoting(target: nil, previous: nil, in: [5, 3]) == [5, 3],
               "committing to an app with no window and coming from none changes no history")
        suite.expect(registeredDefaults[DefaultsKey.minimalWindowPreviews] as? Bool == false,
               "minimal previews preserve the existing appearance until enabled")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.minimalWindowPreviews,
                                                                  DefaultsKey.monitorPwrTemperature,
                                                                  DefaultsKey.monitorSysBattery]),
               "preview appearance and moved battery visibility travel in settings backups")
        let batteryVisibilitySuite = "com.vorssaint.tests.batteryVisibility.\(UUID().uuidString)"
        if let batteryVisibilityDefaults = UserDefaults(suiteName: batteryVisibilitySuite) {
            batteryVisibilityDefaults.removePersistentDomain(forName: batteryVisibilitySuite)
            batteryVisibilityDefaults.set(false, forKey: DefaultsKey.monitorSysTemps)
            Defaults.migrateBatteryTemperatureVisibility(in: batteryVisibilityDefaults)
            suite.expect(!batteryVisibilityDefaults.bool(forKey: DefaultsKey.monitorPwrTemperature),
                   "moving battery temperature preserves a hidden temperature section")
            batteryVisibilityDefaults.set(true, forKey: DefaultsKey.monitorSysTemps)
            Defaults.migrateBatteryTemperatureVisibility(in: batteryVisibilityDefaults)
            suite.expect(!batteryVisibilityDefaults.bool(forKey: DefaultsKey.monitorPwrTemperature),
                   "subsequent System visibility changes cannot overwrite the Power choice")
            batteryVisibilityDefaults.removePersistentDomain(forName: batteryVisibilitySuite)
            Defaults.migrateBatteryTemperatureVisibility(in: batteryVisibilityDefaults)
            suite.expect(batteryVisibilityDefaults.bool(forKey: DefaultsKey.monitorPwrTemperature),
                   "a fresh installation keeps battery temperature visible in Power")
            batteryVisibilityDefaults.set(false, forKey: DefaultsKey.monitorSysTemps)
            Defaults.migrateBatteryTemperatureVisibility(in: batteryVisibilityDefaults)
            suite.expect(batteryVisibilityDefaults.bool(forKey: DefaultsKey.monitorPwrTemperature),
                   "a restored Power preference wins over the previous temperature section")
            batteryVisibilityDefaults.removePersistentDomain(forName: batteryVisibilitySuite)
        } else {
            suite.expect(false, "battery visibility migration has isolated preferences")
        }
        let visibleDockCard = CGRect(x: 0, y: 25, width: 120, height: 80)
        for eventType: NSEvent.EventType in [.leftMouseDown, .rightMouseDown, .otherMouseDown, .otherMouseUp, .mouseMoved] {
            for button in [0, 1, 2, 3, 4] {
                let handles = DockPreviewSupport.handlesMiddleClick(eventType: eventType,
                    buttonNumber: button, point: CGPoint(x: 60, y: 50),
                    visibleRect: visibleDockCard, isHidden: false)
                suite.expect(handles == (button == 2 && (eventType == .otherMouseDown || eventType == .otherMouseUp)),
                       "Dock preview reserves only middle-button presses and releases")
            }
        }
        for point in [CGPoint(x: 60, y: 10), CGPoint(x: 130, y: 50), CGPoint(x: 60, y: 110)] {
            suite.expect(!DockPreviewSupport.handlesMiddleClick(eventType: .otherMouseDown,
                buttonNumber: 2, point: point, visibleRect: visibleDockCard, isHidden: false),
                   "clipped and off-card preview areas cannot close a window")
        }
        suite.expect(!DockPreviewSupport.handlesMiddleClick(eventType: .otherMouseDown,
            buttonNumber: 2, point: CGPoint(x: 60, y: 50), visibleRect: visibleDockCard, isHidden: true),
               "hidden preview cards cannot close a window")
        suite.expect(registeredDefaults[DefaultsKey.dockPreviewEnabled] as? Bool == false,
               "Dock Preview is opt-in for clean installs")
        suite.expect(registeredDefaults[DefaultsKey.dockPreviewCurrentSpaceOnly] as? Bool == false,
               "Dock Preview shows all desktops by default")
        for currentDesktopOnly in [false, true] {
            let backup = SettingsBackupSupport.payload(appVersion: "test") { key in
                switch key {
                case DefaultsKey.dockPreviewCurrentSpaceOnly: return currentDesktopOnly
                case DefaultsKey.switcherCurrentSpaceOnly: return !currentDesktopOnly
                default: return nil
                }
            }
            let restored = SettingsBackupSupport.sanitizedSettings(from: backup)
            suite.expect(restored?[DefaultsKey.dockPreviewCurrentSpaceOnly] as? Bool == currentDesktopOnly
                   && restored?[DefaultsKey.switcherCurrentSpaceOnly] as? Bool == !currentDesktopOnly,
                   "backup preserves independent Dock Preview and Switcher desktop choices")
        }
        suite.expect(registeredDefaults[DefaultsKey.dockPreviewBackgroundOpacity] as? Double == 1.0,
               "the Dock Preview panel starts fully solid")
        suite.expect(registeredDefaults[DefaultsKey.dockPreviewQuitAppOnClose] as? Bool == false,
               "the Dock Preview close button closes one window by default")
        suite.expect(registeredDefaults[DefaultsKey.dockPreviewOrderByCreation] as? Bool == false,
               "Dock Preview keeps last-use window order by default")
        func dockPreviewWindow(id: CGWindowID) -> SwitcherItem {
            SwitcherItem(id: "w.\(id)", title: "Window \(id)", appName: "App",
                         pid: 1, windowOwnerPID: 1, windowID: id,
                         isOnScreen: true, isAppHidden: false, isMinimized: false,
                         isFullscreen: false, isOnHiddenSpace: false, frame: .zero)
        }
        let lastUseOrder = [dockPreviewWindow(id: 30), dockPreviewWindow(id: 10), dockPreviewWindow(id: 20)]
        suite.expect(DockPreviewSupport.orderedWindows(lastUseOrder, order: .lastUse).map(\.windowID)
                == [30, 10, 20],
               "last-use order leaves the enumerated window list unchanged")
        suite.expect(DockPreviewSupport.orderedWindows(lastUseOrder, order: .creation).map(\.windowID)
                == [10, 20, 30],
               "creation order sorts windows by ascending window ID")
        suite.expect(DockPreviewSupport.orderedWindows([], order: .creation).isEmpty,
               "creation order keeps an empty list empty")
        suite.expect(DockPreviewSupport.closeAction(quitAppOnClose: false) == .closeWindow
                && DockPreviewSupport.closeAction(quitAppOnClose: true) == .quitApp,
               "the Dock Preview close preference selects exactly one close action")
        var dockPreviewQuitRequests = 0
        var dockPreviewWindowCloseRequests = 0
        DockPreviewSupport.performCloseAction(
            quitAppOnClose: false,
            requestQuit: {
                dockPreviewQuitRequests += 1
                return true
            },
            closeWindow: { dockPreviewWindowCloseRequests += 1 }
        )
        DockPreviewSupport.performCloseAction(
            quitAppOnClose: true,
            requestQuit: {
                dockPreviewQuitRequests += 1
                return true
            },
            closeWindow: { dockPreviewWindowCloseRequests += 1 }
        )
        DockPreviewSupport.performCloseAction(
            quitAppOnClose: true,
            requestQuit: {
                dockPreviewQuitRequests += 1
                return false
            },
            closeWindow: { dockPreviewWindowCloseRequests += 1 }
        )
        suite.expect(dockPreviewQuitRequests == 2 && dockPreviewWindowCloseRequests == 2,
               "Dock Preview closes a window normally, waits after an accepted quit, and falls back after refusal")
        suite.expect(registeredDefaults[DefaultsKey.dockClickHide] as? Bool == false,
               "hiding the active app from its Dock icon is opt-in")
        suite.expect(DockPreviewSupport.sanitizedBackgroundOpacity(0.7) == 0.7,
               "a Dock Preview background opacity inside the range is kept")
        // A card is dragged for the same reason whatever state its window is in:
        // the user wants that window here. Minimized and parked-on-another-Space
        // used to refuse the gesture, which read as the drag doing nothing --
        // releasing then counted as a click and the window went back to its own
        // old place instead of the drop point.
        suite.expect(DockPreviewSupport.canDragToPlace(hasWindowID: true, isFullscreen: false),
               "an ordinary preview card can be dragged out of the panel")
        suite.expect(DockPreviewSupport.canDragToPlace(hasWindowID: true, isFullscreen: false),
               "a minimized or parked window is dragged like any other")
        suite.expect(!DockPreviewSupport.canDragToPlace(hasWindowID: true, isFullscreen: true),
               "a fullscreen window owns its Space and ignores a dropped position")
        suite.expect(!DockPreviewSupport.canDragToPlace(hasWindowID: false, isFullscreen: false),
               "an entry without a window has nothing to move")
        // The preview size setting sizes the thumbnail, not the writing around
        // it. Both halves of that are checked across every size on offer: the
        // picture tracks the setting exactly, and the chrome does not move at
        // all — a title band that scaled with the card once left a 12pt line
        // adrift in 31pt of nothing at the largest setting.
        let previewScales = Defaults.allowedPreviewSizes.map { PreviewSizing.scale(for: $0) }
        suite.expect(previewScales.count == 4 && previewScales.contains(1.0),
               "every preview size on offer has a scale, including the unscaled one")
        suite.expect(previewScales.allSatisfy { scale in
                   let thumbnail = DockPreviewSupport.cardThumbnailSize(scale: scale)
                   let base = DockPreviewSupport.cardThumbnailSize(scale: 1)
                   return abs(thumbnail.width - base.width * scale) < 0.0001
                       && abs(thumbnail.height - base.height * scale) < 0.0001
               },
               "a Dock Preview thumbnail is exactly the chosen preview size")
        suite.expect(previewScales.allSatisfy { scale in
                   let card = DockPreviewSupport.cardSize(scale: scale)
                   let thumbnail = DockPreviewSupport.cardThumbnailSize(scale: scale)
                   return card.height - thumbnail.height - 13 * scale >= DockPreviewSupport.cardTitleHeight
               },
               "a card keeps a full title band at every preview size, never a scaled-down one")
        suite.expect(DockPreviewSupport.cardTitleHeight >= 20,
               "the title band holds one line of 12pt semibold beside two 16pt controls")
        // The well is cut to the shape of the screen the capture came from, so
        // a full-height window fills it instead of sitting between two bars.
        suite.expect(previewScales.allSatisfy { scale in
                   let picture = DockPreviewSupport.cardPictureSize(scale: scale)
                   return abs(picture.width / picture.height - 1.6) < 0.001
               },
               "the picture inside a thumbnail is 16:10 at every preview size")
        suite.expect(previewScales.allSatisfy { scale in
                   let picture = DockPreviewSupport.cardPictureSize(scale: scale)
                   let thumbnail = DockPreviewSupport.cardThumbnailSize(scale: scale)
                   return picture.width < thumbnail.width && picture.height < thumbnail.height
               },
               "the picture keeps its inset inside the thumbnail well at every size")
        suite.expect(previewScales.allSatisfy {
                   DockPreviewSupport.cardFallbackIconSize(scale: $0)
                       < DockPreviewSupport.cardThumbnailSize(scale: $0).height
               },
               "the stand-in app icon stays inside the thumbnail it stands in for at every size")
        // Every window takes the same steps on a drop, whatever state it was
        // in. A branch on `isMinimized` made that drop feel like a different
        // gesture from an ordinary one -- which is the thing being fixed, so a
        // branch is what this guards against.
        let placeSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Switcher/WindowActivator.swift",
            encoding: .utf8)) ?? ""
        let placeBody = (placeSource.components(separatedBy: "static func place(_ item: SwitcherItem")
            .last ?? "").components(separatedBy: "\n    @discardableResult").first ?? ""
        let placeCode = placeBody
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(!placeCode.isEmpty && !placeCode.contains("isMinimized"),
               "a drop takes the same steps for a minimized window as for any other")
        // The thumbnail is derived from the card, so a constant changed on its
        // own must not silently eat into it or leave the card short.
        suite.expectClose(Double(DockPreviewSupport.cardThumbnailHeight
                            + DockPreviewSupport.cardPadding * 2
                            + DockPreviewSupport.cardTitleSpacing
                            + DockPreviewSupport.cardTitleHeight),
                    Double(DockPreviewSupport.cardHeight),
                    "a Dock Preview card's chrome and thumbnail add up to the card")
        suite.expect(DockPreviewSupport.cardThumbnailHeight
                > DockPreviewSupport.cardHeight * 0.7,
               "the thumbnail keeps most of the Dock Preview card")

        // The card used to draw the app icon on every thumbnail and the window
        // title both over the thumbnail and under it. In a panel every card
        // belongs to one app, so both said the same thing once per window.
        let dockPreviewCardSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Switcher/DockPreviewPanelView.swift",
            encoding: .utf8)) ?? ""
        let dockPreviewCardCode = dockPreviewCardSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(dockPreviewCardCode.components(separatedBy: "window.displayTitle").count - 1 == 1,
               "a Dock Preview card names its window once")
        // Nothing is drawn on top of the picture any more. The close and
        // minimize buttons sat in a 28pt capsule in its top-right corner --
        // over a third of its height -- and the pinned badge sat beside them.
        suite.expect(!dockPreviewCardCode.contains("previewControlBar"),
               "no control bar floats over a Dock Preview thumbnail")
        let titleBandBody = dockPreviewCardCode
            .components(separatedBy: "private var titleBand: some View {").last ?? ""
        let bandDeclaration = titleBandBody.components(separatedBy: "private var").first ?? ""
        suite.expect(bandDeclaration.contains("closeButton") && bandDeclaration.contains("minimizeButton"),
               "both window controls sit in the title band, beside the name")
        suite.expect(!DockPreviewSupport.showsCardControls(isHovering: false, isSelected: false),
               "a card with no pointer on it and no selection draws no window controls")
        suite.expect(DockPreviewSupport.showsCardControls(isHovering: true, isSelected: false),
               "the pointer summons a card's window controls")
        let contextMenuBody = dockPreviewCardCode
            .components(separatedBy: "private var cardContextMenu: some View {").last ?? ""
        suite.expect((contextMenuBody.components(separatedBy: "private var").first ?? "")
                   .contains("dockPreviewPinPanel"),
               "pinning is offered by name in the card menu, not by a bare pushpin")
        suite.expect(DockPreviewSupport.showsCardAppBadge(hasPreview: true),
               "a card with a capture badges it with the app's icon, as the App Switcher does")
        suite.expect(!DockPreviewSupport.showsCardAppBadge(hasPreview: false),
               "a card without one already shows that icon as its watermark, so it takes no badge")
        suite.expect(dockPreviewCardSource.contains("window.isOnHiddenSpace"),
               "a Dock Preview card badges a window that lives on another desktop")

        let dockDropScreen = CGRect(x: -1440, y: 24, width: 1440, height: 876)
        suite.expect(DockPreviewSupport.dragOrigin(pointer: CGPoint(x: -700, y: 500),
                                             windowSize: CGSize(width: 600, height: 400),
                                             visibleFrame: dockDropScreen)
               == CGPoint(x: -700, y: 500),
               "a Dock Preview drop inside the screen keeps the pointer origin")
        suite.expect(DockPreviewSupport.dragOrigin(pointer: CGPoint(x: -20, y: 100),
                                             windowSize: CGSize(width: 600, height: 400),
                                             visibleFrame: dockDropScreen)
               == CGPoint(x: -600, y: 424),
               "a Dock Preview edge drop keeps the whole window reachable")
        suite.expect(DockPreviewSupport.dragOrigin(pointer: CGPoint(x: -700, y: 500),
                                             windowSize: CGSize(width: 1800, height: 1000),
                                             visibleFrame: dockDropScreen)
               == CGPoint(x: -1440, y: 900),
               "an oversized dropped window keeps its title bar on the destination screen")
        suite.expect(DockPreviewSupport.sanitizedBackgroundOpacity(0)
               == DockPreviewSupport.backgroundOpacityRange.lowerBound
               && DockPreviewSupport.sanitizedBackgroundOpacity(-3)
               == DockPreviewSupport.backgroundOpacityRange.lowerBound,
               "the Dock Preview panel never fades past the floor that keeps it looking like a panel")
        suite.expect(DockPreviewSupport.sanitizedBackgroundOpacity(4) == 1.0
               && DockPreviewSupport.sanitizedBackgroundOpacity(.nan) == 1.0
               && DockPreviewSupport.sanitizedBackgroundOpacity(.infinity) == 1.0,
               "a broken stored Dock Preview opacity falls back to solid")
        suite.expect(registeredDefaults[DefaultsKey.dockPreviewOpenDelay] as? Int
               == DockPreviewSupport.defaultOpenDelayMilliseconds,
               "a clean install waits the default before opening a Dock Preview")
        suite.expect(DockPreviewSupport.openDelayMillisecondsRange
               .contains(DockPreviewSupport.defaultOpenDelayMilliseconds),
               "the default Dock Preview delay is one the field accepts")
        suite.expect(DockPreviewSupport.sanitizedOpenDelay(milliseconds: 350) == 350,
               "a typed Dock Preview delay inside the range is kept")
        suite.expect(DockPreviewSupport.sanitizedOpenDelay(milliseconds: -1)
               == DockPreviewSupport.openDelayMillisecondsRange.lowerBound
               && DockPreviewSupport.sanitizedOpenDelay(milliseconds: 9_000)
               == DockPreviewSupport.openDelayMillisecondsRange.upperBound,
               "a Dock Preview delay outside the range is clamped to it")
        suite.expect(DockPreviewSupport.sanitizedOpenDelay(milliseconds: 0)
               >= DockPreviewSupport.openDelayMillisecondsRange.lowerBound,
               "an unset or zeroed Dock Preview delay cannot disarm the wait entirely")
        suite.expectClose(DockPreviewSupport.openDelay(milliseconds: 250), 0.25,
                    "the stored milliseconds drive the timer in seconds")
        let openDelays = DockPreviewSupport.openDelayMillisecondsRange
            .map { DockPreviewSupport.openDelay(milliseconds: $0) }
        suite.expect(openDelays.allSatisfy { DockPreviewSupport.switchDelay <= $0 },
               "no chosen delay makes switching slower than opening")
        suite.expect(openDelays.allSatisfy { DockPreviewSupport.prefetchDelay(openDelay: $0) <= $0 },
               "the window list is never read after the panel it is read for has opened")
        suite.expect(openDelays.allSatisfy {
                   $0 - DockPreviewSupport.prefetchDelay(openDelay: $0)
                       <= DockPreviewSupport.prefetchLead + 0.0001
               },
               "the window list is never read further ahead than the lead, so what opens is still true")
        suite.expectClose(DockPreviewSupport.prefetchDelay(
                        openDelay: DockPreviewSupport.openDelay(
                            milliseconds: DockPreviewSupport.defaultOpenDelayMilliseconds)),
                    0.1,
                    "at the default the window list is read halfway through the wait")
        suite.expect(openDelays.allSatisfy {
                   DockPreviewSupport.prefetchDelay(openDelay: $0) >= DockPreviewSupport.prefetchLead
               },
               "no setting reads the window list before the cursor has held still")
        suite.expect(DockPreviewSupport.switchDelay + 0.06
               < DockPreviewSupport.openDelay(
                   milliseconds: DockPreviewSupport.openDelayMillisecondsRange.lowerBound),
               "a switch, reading its window list inline, still lands before the shortest fresh open")
        suite.expect(registeredDefaults[DefaultsKey.autoCheckUpdates] as? Bool == true,
               "update checks are on for clean installs")
        suite.expect(registeredDefaults[DefaultsKey.updateShowcaseIntroVersion] as? String == "",
               "update showcase intro starts unseen")
        suite.expect(registeredDefaults[DefaultsKey.updateShowcaseMediaOverride] as? String == "",
               "update showcase media override is empty by default")
        suite.expect(SupportUpdateIntroInfo.releaseVersion == "3.3.2",
               "support prompt is deliberately pinned to 3.3.2")
        suite.expect(SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.2", lastSeenVersion: "3.3.1"),
               "support prompt shows once after updating to its pinned release")
        suite.expect(!SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.2", lastSeenVersion: "3.3.2"),
               "support prompt stays hidden after it is seen")
        suite.expect(!SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.0", lastSeenVersion: nil)
               && !SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.1", lastSeenVersion: nil)
               && !SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.3", lastSeenVersion: nil),
               "support prompt never leaks into another release")
        suite.expect(SupportUpdateIntroStep.support.next == .social
               && SupportUpdateIntroStep.social.next == nil,
               "update intro moves from support to social updates")
        suite.expect(SupportUpdateIntroStep.support.previous == nil
               && SupportUpdateIntroStep.social.previous == .support,
               "update intro navigates back without closing")
        suite.expect(SupportUpdateIntroStep.allCases == [.support, .social],
               "update intro page indicators follow the navigation order")
        suite.expect(AppInfo.discordURL.absoluteString == "https://discord.gg/M6BwWH4BJp",
               "the community action uses the permanent Discord invitation")
        suite.expect(AppInfo.coffeeURL.absoluteString == "https://buymeacoffee.com/vorssaint",
               "financial support uses Buy Me a Coffee")
        suite.expect(AppInfo.socialURL.absoluteString == "https://x.com/vorssaint",
               "social previews keep the official X profile")
        // AppInfo.version falls back to "dev" in this bare harness, so read
        // the plist the shipped app will actually carry. The pin is a
        // per-release decision: this check fails on every version bump so the
        // decision above is made consciously, never by omission.
        let releasePlist = NSDictionary(contentsOfFile: "Resources/Info.plist")
        let plistVersion = (releasePlist?["CFBundleShortVersionString"] as? String) ?? ""
        suite.expect(plistVersion == "3.4.0-beta.4",
               "bumping the app version requires re-deciding the support prompt pin above")
        let plistBuild = (releasePlist?["CFBundleVersion"] as? String) ?? ""
        suite.expect(plistBuild == "91",
               "every app version needs its own incremented bundle build")
        suite.expect(SupportUpdateIntroInfo.releaseVersion == "3.3.2",
               "the support prompt remains deliberately pinned to 3.3.2")
        suite.expect(UpdateHighlightsInfo.releaseVersion == "3.4.0-beta.1",
               "the prepared tour belongs to the first 3.4 beta without changing the installed version")
        for version in ["3.4.0-beta.1", "3.4.0-beta.2", "3.4.0-beta.2.1", "3.4.0-beta.3", "3.4.0-beta.4", "3.4.0-beta.10"] {
            suite.expect(UpdateHighlightsInfo.shouldShow(appVersion: version, lastSeenVersion: nil)
                   && UpdateHighlightsInfo.shouldShow(appVersion: version, lastSeenVersion: "3.3.3"),
                   "the notch tour introduces this beta cycle to new and returning users")
            suite.expect(!UpdateHighlightsInfo.shouldShow(appVersion: version, lastSeenVersion: UpdateHighlightsInfo.releaseVersion),
                   "the beta tour does not repeat after it has been seen")
            suite.expect(!SupportUpdateIntroInfo.shouldShow(appVersion: version, lastSeenVersion: nil),
                   "beta updates do not request the support and social introduction")
        }
        for version in ["3.3.5", "3.4.0", "3.4.1", "3.4.0-rc.1", "3.4.0-beta.0", "3.4.0-beta.no", "3.4.0-beta.2.no", "3.4.0-beta.2.1.1", "3.5.0-beta.1", "4.0.0"] {
            suite.expect(!UpdateHighlightsInfo.matchesRelease(version)
                   && !UpdateHighlightsInfo.shouldShow(appVersion: version, lastSeenVersion: nil),
                   "previewing from the current build and other release cycles cannot consume the future beta tour")
        }
        suite.expect(FileManager.default.fileExists(atPath: "Resources/Images/highlights-notch.png"),
               "the notch tour bundles its static layout illustration")
        suite.expect(registeredDefaults[DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect] as? Bool == false,
               "headphone disconnect volume lowering is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.mixerHeadphonesDisconnectVolumePercent] as? Int
               == Defaults.defaultMixerHeadphonesDisconnectVolumePercent,
               "headphone disconnect protection starts at an audible volume, never at silence")
        suite.expect(Defaults.defaultMixerHeadphonesDisconnectVolumePercent
               >= Defaults.minimumMixerHeadphonesDisconnectVolumePercent
               && Defaults.defaultMixerHeadphonesDisconnectVolumePercent < 100,
               "the headphone disconnect default is a real reduction that can still be heard")
        suite.expect(registeredDefaults[DefaultsKey.mixerShowFinder] as? Bool == true,
               "Finder returns to the mixer by default")
        suite.expect(registeredDefaults[DefaultsKey.mixerHideInactiveApps] as? Bool == false,
               "inactive mixer apps remain visible by default")
        suite.expect(registeredDefaults[DefaultsKey.soundOutputSwitcherEnabled] as? Bool == false,
               "sound output switcher is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.soundOutputSwitcherShortcut] as? String
               == GlobalShortcut.soundOutputSwitcherDefault.storageValue,
               "sound output switcher shortcut has a registered default")
        suite.expect(registeredDefaults[DefaultsKey.shelfShortcutEnabled] as? Bool == true,
               "shelf shortcut is on by default once shelf is enabled")
        suite.expect(registeredDefaults[DefaultsKey.shelfShortcut] as? String == "control+option+command:2",
               "shelf shortcut defaults to Ctrl+Opt+Cmd+D")
        suite.expect(registeredDefaults[DefaultsKey.shelfShakeToOpen] as? Bool == true,
               "shelf shake opens by default once shelf is enabled")
        suite.expect(registeredDefaults[DefaultsKey.shelfEdgeDragEnabled] as? Bool == false,
               "new shelf edge opening stays off by default")
        suite.expect(registeredDefaults[DefaultsKey.shelfCloseAfterDrop] as? Bool == false,
               "closing after a drop is new behavior and must arrive off in an update")
        suite.expect(registeredDefaults[DefaultsKey.shelfRemoveAfterDrop] as? Bool == true,
               "shelf removes accepted items after a drop by default")
        suite.expect(registeredDefaults[DefaultsKey.shelfClearOnClose] as? Bool == false
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.shelfClearOnClose),
               "clearing the shelf on close is opt-in and travels with settings backups")
        suite.expect((registeredDefaults[DefaultsKey.shelfAutomaticExclusions] as? [String])?.isEmpty == true,
               "shelf automatic exclusions start empty")
        suite.expect(registeredDefaults[DefaultsKey.mouseNavigationEnabled] as? Bool == false,
               "mouse side-button navigation is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.mouseAccelerationDisabled] as? Bool == false
                && registeredDefaults[DefaultsKey.panelControlMouseAcceleration] as? Bool == true,
               "mouse acceleration control is opt-in and visible in the panel when installed")
        suite.expect(registeredDefaults[DefaultsKey.mouseClickDebounceEnabled] as? Bool == false,
               "mouse click debounce is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.mouseClickDebounceWindowMs] as? Int
               == Defaults.defaultMouseClickDebounceWindowMs,
               "mouse click debounce registers its conservative filter window")
        suite.expect(registeredDefaults[DefaultsKey.panelControlMouseClickDebounce] as? Bool == true,
               "mouse click debounce is visible in the panel when installed")
        suite.expect(registeredDefaults[DefaultsKey.clipboardHistoryShortcutEnabled] as? Bool == true,
               "clipboard history shortcut is ready when clipboard history is enabled")
        suite.expect(registeredDefaults[DefaultsKey.clipboardHistoryShortcut] as? String
               == GlobalShortcut.clipboardDefault.storageValue,
               "clipboard history shortcut defaults to Ctrl+Opt+Cmd+V")
        suite.expect(registeredDefaults[DefaultsKey.finderCutPasteShowHUD] as? Bool == true,
               "the Finder cut and paste floating panel starts enabled")
        suite.expect(registeredDefaults[DefaultsKey.finderRenameEnabled] as? Bool == false,
               "the Finder rename shortcut is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.finderRenameShortcut] as? String == ":120",
               "the Finder rename shortcut starts on bare F2")
        suite.expect(GlobalShortcut(keyCode: Int64(kVK_ANSI_V), modifiers: [.command])
                   .isStandardPasteCommand,
               "Cmd+V is recognized when plain-text paste must release its own hotkey")
        suite.expect(!GlobalShortcut.pastePlainDefault.isStandardPasteCommand,
               "the default plain-text paste shortcut does not intercept synthesized Cmd+V")
        suite.expect(!GlobalShortcut(keyCode: Int64(kVK_ANSI_C), modifiers: [.command])
                   .isStandardPasteCommand,
               "other Command shortcuts never release the plain-text paste hotkey")
        suite.expect(registeredDefaults[DefaultsKey.urlCleanerEnabled] as? Bool == false,
               "URL cleaner clipboard watching is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.windowMaximizeEnabled] as? Bool == false,
               "green button maximize override is opt-in")
        suite.expect(WindowMaximizerSupport.excludes(bundleIdentifier: "com.example.game",
                                                     excludedBundleIdentifiers: [" com.example.game "])
                && !WindowMaximizerSupport.excludes(bundleIdentifier: "com.example.editor",
                                                    excludedBundleIdentifiers: ["com.example.game"])
                && !WindowMaximizerSupport.excludes(bundleIdentifier: nil,
                                                    excludedBundleIdentifiers: ["com.example.game"]),
               "only apps on the exception list keep the native green button")
        suite.expect(registeredDefaults[DefaultsKey.keyboardDebounceEnabled] as? Bool == false,
               "keyboard debounce is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.keyboardDebounceWindowMs] as? Int == 5,
               "keyboard debounce default window starts low")
        suite.expect(registeredDefaults[DefaultsKey.keyboardDebounceKeyWindows] as? String == "",
               "keyboard debounce per-key windows start empty")
        suite.expect(registeredDefaults[DefaultsKey.panelUtilityCleaning] as? Bool == true,
               "panel cleaning utility is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.cleaningModeKeepScreenVisible] as? Bool == false,
               "cleaning mode keep screen visible is disabled by default")
        suite.expect(registeredDefaults[DefaultsKey.panelUtilityURLCleaner] as? Bool == true,
               "panel URL cleaner utility is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelUtilityUninstaller] as? Bool == true,
               "panel uninstaller utility is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelUtilityHomebrew] as? Bool == true,
               "panel Homebrew utility is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelUtilityMedia] as? Bool == true,
               "panel Media utility is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelControlMouseScroll] as? Bool == true,
               "panel mouse scroll control is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelControlMouseNavigation] as? Bool == true,
               "panel mouse navigation control is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelControlSwitcher] as? Bool == true,
               "panel switcher control is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelControlDockPreview] as? Bool == true,
               "panel Dock Preview control is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelControlDockClickHide] as? Bool == true,
               "panel Dock hide control is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelControlCutPaste] as? Bool == true,
               "panel cut and paste control is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.colorPickerBareHex] as? Bool == false,
               "color picker keeps the # prefix by default")
        suite.expect(registeredDefaults[DefaultsKey.screenOCRRemoveLineBreaks] as? Bool == false,
               "copy text from screen keeps line breaks by default")
        suite.expect(registeredDefaults[DefaultsKey.screenOCRDetectQRCodes] as? Bool == true,
               "copy text from screen reads QR codes by default")
        suite.expect(registeredDefaults[DefaultsKey.micMuteMenuBarIndicator] as? Bool == true,
               "mic mute menu bar indicator ships on by default (badge only shows while muted)")
        suite.expect(registeredDefaults[DefaultsKey.menuBarMetricSpacing] as? String == "compact",
               "menu bar metric spacing defaults to the compact look")
        suite.expect(registeredDefaults[DefaultsKey.menuBarMetricAppearance] as? String == "values",
               "menu bar usage metrics keep numeric values by default")
        suite.expect(registeredDefaults[DefaultsKey.menuBarUsageBarNormalColor] as? String == "#64D2FF",
               "menu bar bars use a bright normal color by default")
        suite.expect(registeredDefaults[DefaultsKey.menuBarUsageBarElevatedColor] as? String == "#FFD60A"
               && registeredDefaults[DefaultsKey.menuBarUsageBarCriticalColor] as? String == "#FF453A",
               "menu bar bars keep visible elevated and critical defaults")
        suite.expect(registeredDefaults[DefaultsKey.menuBarUsageBarMediumThreshold] as? Int == 70
               && registeredDefaults[DefaultsKey.menuBarUsageBarHighThreshold] as? Int == 90,
               "menu bar bar thresholds default to seventy and ninety percent")
        suite.expect(Defaults.sanitizedMonitorAlertCooldown(2) == 2,
               "the two minute alert cooldown is a valid stored choice")
        suite.expect(Defaults.sanitizedMonitorAlertCooldown(7) == 15,
               "unknown alert cooldowns fall back to fifteen minutes")
        suite.expect(registeredDefaults[DefaultsKey.monitorAlertBatteryTemperature] as? Bool == false,
               "battery temperature alerts are opt-in")
        suite.expect(registeredDefaults[DefaultsKey.monitorAlertBatteryTemperatureThreshold] as? Int == 40,
               "battery temperature alerts default to forty degrees")
        suite.expect(Defaults.sanitizedMenuBarMetricSpacing("standard") == "standard",
               "standard menu bar spacing is a valid stored choice")
        suite.expect(Defaults.sanitizedMenuBarMetricSpacing("banana") == "compact",
               "unknown menu bar spacing values fall back to the compact default")
        suite.expect(Defaults.sanitizedMenuBarMetricAppearance("bars") == "bars",
               "bar appearance is a valid stored choice")
        suite.expect(Defaults.sanitizedMenuBarMetricAppearance("banana") == "values",
               "unknown menu bar appearances fall back to numeric values")
        suite.expect(MenuBarMetricAppearance.values.allowsCombinedTemperatures,
               "numeric menu bar values may combine usage and temperature")
        suite.expect(!MenuBarMetricAppearance.bars.allowsCombinedTemperatures,
               "menu bar bars keep usage and temperature separate")
        suite.expectClose(MenuBarUsageBarSupport.memoryFraction(used: 3, total: 4) ?? -1, 0.75,
                    "menu bar memory bars use the current used fraction")
        suite.expect(MenuBarUsageBarSupport.memoryFraction(used: 3, total: 0) == nil,
               "menu bar memory bars keep missing totals unavailable")
        suite.expectClose(MenuBarUsageBarSupport.clampedFraction(-0.2), 0,
                    "menu bar bars clamp negative readings")
        suite.expectClose(MenuBarUsageBarSupport.clampedFraction(1.4), 1,
                    "menu bar bars clamp readings above full")
        suite.expect(MenuBarUsageBarSupport.fillLevel(for: 0.5, steps: 16) == 8,
               "menu bar bars quantize fractions to visible fill steps")
        suite.expect(MenuBarUsageBarSupport.level(for: 0.69) == .normal,
               "menu bar usage stays blue below seventy percent")
        suite.expect(MenuBarUsageBarSupport.level(for: 0.70) == .elevated,
               "menu bar usage turns yellow at seventy percent")
        suite.expect(MenuBarUsageBarSupport.level(for: 0.89) == .elevated,
               "menu bar usage stays yellow below ninety percent")
        suite.expect(MenuBarUsageBarSupport.level(for: 0.90) == .critical,
               "menu bar usage turns red at ninety percent")
        suite.expect(MenuBarUsageBarSupport.level(for: 0.50,
                                            mediumPercent: 40,
                                            highPercent: 80) == .elevated,
               "custom menu bar medium thresholds change the bar level")
        suite.expect(MenuBarUsageBarSupport.level(for: 0.80,
                                            mediumPercent: 40,
                                            highPercent: 80) == .critical,
               "custom menu bar high thresholds change the bar level")
        let repairedBarThresholds = MenuBarUsageBarSupport.thresholds(medium: 100, high: 20)
        suite.expect(repairedBarThresholds.medium == 99 && repairedBarThresholds.high == 100,
               "invalid menu bar thresholds keep medium below high")
        suite.expect(MenuBarUsageBarSupport.sanitizedColorHex(" 64d2ff ", fallback: "#000000") == "#64D2FF",
               "menu bar colors normalize stored hex values")
        suite.expect(MenuBarUsageBarSupport.sanitizedColorHex("bad", fallback: "#FFD60A") == "#FFD60A",
               "invalid menu bar colors use their visible fallback")
        let customBarRGB = MenuBarUsageBarSupport.rgb(for: "#804020", fallback: "#000000")
        suite.expectClose(customBarRGB.red, 128.0 / 255.0, "menu bar color parses red")
        suite.expectClose(customBarRGB.green, 64.0 / 255.0, "menu bar color parses green")
        suite.expectClose(customBarRGB.blue, 32.0 / 255.0, "menu bar color parses blue")
        suite.expect(MenuBarUsageBarSupport.hex(red: 1, green: 0.5, blue: 0) == "#FF8000",
               "menu bar color picker writes stable hex values")
        suite.expect(MenuBarSpacingSupport.digitMatchedReserve(for: "14%") == "88%",
               "compact spacing reserves the current digit count for percentages")
        suite.expect(MenuBarSpacingSupport.digitMatchedReserve(for: "999°") == "888°",
               "compact spacing reserves the current digit count for temperatures")
        suite.expect(MenuBarSpacingSupport.digitMatchedReserve(for: "1.5M") == "8.8M",
               "compact spacing keeps units and separators while widening digits")
        suite.expect(MenuBarSpacingSupport.digitMatchedReserve(for: "") == "",
               "compact spacing reserve of an empty value stays empty")
        suite.expect(MenuBarSpacingSupport.digitMatchedReserve(for: "4%", minimumDigits: 2) == "88%",
               "compact spacing pads single digits up to the stability floor")
        suite.expect(MenuBarSpacingSupport.digitMatchedReserve(for: "14%", minimumDigits: 2) == "88%",
               "a one and a two digit value reserve the same width, so 4% to 10% never moves the bar")
        suite.expect(MenuBarSpacingSupport.digitMatchedReserve(for: "100%", minimumDigits: 2) == "888%",
               "values above the floor keep their own digit count")
        suite.expect(MenuBarSpacingSupport.compactFloor(currentDigits: 1, highWater: nil) == 2,
               "the compact floor starts at two digits")
        suite.expect(MenuBarSpacingSupport.compactFloor(currentDigits: 3, highWater: 2) == 3,
               "a three digit value raises the floor")
        suite.expect(MenuBarSpacingSupport.compactFloor(currentDigits: 2, highWater: 3) == 3,
               "the session high-water mark keeps a block from shrinking back and wobbling")
        suite.expect(MenuBarSpacingSupport.blockGlue(readableStyle: false, spacing: .standard) == " ",
               "standard dense spacing keeps the full space between blocks")
        suite.expect(MenuBarSpacingSupport.blockGlue(readableStyle: false, spacing: .compact) == "\u{200A}",
               "compact dense spacing joins blocks with a hair space")
        suite.expect(MenuBarSpacingSupport.blockGlue(readableStyle: true, spacing: .compact) == " ",
               "compact readable spacing tightens the double space to a single one")
        suite.expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1135, reportedMidX: 1452, buttonWidth: 38) == -317,
               "a click far left of the status item's reported frame re-anchors the panel at the click")
        suite.expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1452, reportedMidX: 1135, buttonWidth: 38) == 317,
               "a click far right of the status item's reported frame re-anchors the panel at the click")
        suite.expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1150, reportedMidX: 1144, buttonWidth: 38) == nil,
               "a click inside the status button never counts as drift")
        suite.expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1186, reportedMidX: 1144, buttonWidth: 38) == nil,
               "a sloppy click just past the button edge stays within the drift slack")
        suite.expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1188, reportedMidX: 1144, buttonWidth: 38) == 44,
               "a click beyond the slack re-anchors by the full offset")
        suite.expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1240, reportedMidX: 1144, buttonWidth: 197) == nil,
               "clicks near the edge of a wide metrics item stay anchored to the item")

        MenuPanelRecoveryTests.run { suite.expect($0, $1) }

        // The built-in display and a taller one placed to its left.
        let builtInScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let secondScreen = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let attachedScreens = [builtInScreen, secondScreen]
        suite.expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 932, width: 0, height: 0),
                                                                 screenFrames: attachedScreens),
               "a status item frame with no size is never an anchor")
        suite.expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 950, width: 38, height: 37),
                                                                 screenFrames: attachedScreens),
               "a status item parked above the top edge is not an anchor")
        suite.expect(StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 919, width: 38, height: 37),
                                                                screenFrames: attachedScreens),
               "a status item sitting in the menu bar band is a trustworthy anchor")
        suite.expect(StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: -1000, y: 1143, width: 38, height: 37),
                                                                screenFrames: attachedScreens),
               "the menu bar band follows each screen's own top edge")
        suite.expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 0, width: 38, height: 37),
                                                                 screenFrames: attachedScreens),
               "a frame down at the bottom of a screen is not a menu bar item")

        // A screen showing a fullscreen window reserves no menu bar: its
        // visible area is the whole frame. The band is a fixed thickness off
        // the screen's own top edge, so an item revealed on hover still counts;
        // a band measured as `frame.maxY - visibleFrame.maxY` would collapse to
        // nothing here and decline the icon while it is visible and clickable.
        let fullscreenScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let fullscreenVisibleFrame = fullscreenScreen
        suite.expect(StatusItemAnchorSupport.menuBarBand > fullscreenScreen.maxY - fullscreenVisibleFrame.maxY,
               "the menu bar band does not shrink to what a fullscreen screen reserves")
        suite.expect(StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 919, width: 38, height: 37),
                                                                screenFrames: [fullscreenScreen]),
               "a status item revealed over a fullscreen window is a trustworthy anchor")

        // These AppKit owners are not part of the pure-helper test binary, so
        // pin that neither caller can consume a parked status-item frame.
        let statusAnchorAppDelegateSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/AppDelegate.swift",
            encoding: .utf8)) ?? ""
        let stripCommentLines: (String) -> String = {
            $0.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }
        // Sliced at the closing brace of the closure/function itself, so the
        // slice can never run past it into an unrelated body that happens to
        // carry the same words.
        let shelfProviderCode = stripCommentLines((statusAnchorAppDelegateSource
            .components(separatedBy: "ShelfService.shared.statusItemFrameProvider =").last ?? "")
            .components(separatedBy: "\n        }").first ?? "")
        let statusControllerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/StatusItemController.swift",
            encoding: .utf8)) ?? ""
        let statusHitTestCode = stripCommentLines((statusControllerSource
            .components(separatedBy: "func containsStatusItem(at screenPoint: NSPoint) -> Bool {").last ?? "")
            .components(separatedBy: "\n    }").first ?? "")
        let statusFrameCall = "StatusItemAnchorSupport.isTrustworthyStatusFrame("
        suite.expect(shelfProviderCode.contains("guard \(statusFrameCall)") && shelfProviderCode.contains("return nil"),
               "the Shelf provider rejects an untrustworthy status-item frame")
        suite.expect(statusHitTestCode.contains(statusFrameCall) && statusHitTestCode.contains("return false"),
               "status-item hit testing rejects an untrustworthy frame")
        suite.expect(statusHitTestCode.contains("clipboardPreviewStatusItem"),
               "status-item hit testing also covers the clipboard preview item")

        // MARK: The panel surface reaches the popover arrow (issue #1030)

        // AppKit hands the hosted panel a safe area for the popover's border and
        // draws the arrow on the frame itself, so a surface that stopped at the
        // panel would leave the tip in the plain system material. None of these
        // owners compiles into this binary, so pin the three pieces that together
        // carry the panel's own surface out to the tip.
        let popoverSetUpCode = stripCommentLines((statusAnchorAppDelegateSource
            .components(separatedBy: "private func setUpPopover() {").last ?? "")
            .components(separatedBy: "\n    }").first ?? "")
        suite.expect(popoverSetUpCode.contains("popover.hasFullSizeContent = true"),
               "the panel is hosted across the whole popover, arrow band included")
        let panelThemeSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Theme.swift",
            encoding: .utf8)) ?? ""
        let panelGlassCode = stripCommentLines((panelThemeSource
            .components(separatedBy: "private struct PanelGlassSurface: View {").last ?? "")
            .components(separatedBy: "\n}").first ?? "")
        suite.expect(panelGlassCode.contains("surface.ignoresSafeArea()"),
               "the panel surface paints past the safe area, up into the arrow")
        suite.expect(!panelGlassCode.isEmpty
                   && !panelGlassCode.contains("RoundedRectangle")
                   && !panelGlassCode.contains("cornerRadius"),
               "the panel surface leaves the rounding to the popover balloon that clips it")
        suite.expect(panelGlassCode.contains(".glassEffect(.regular, in: Rectangle())")
                   && panelGlassCode.contains("Rectangle()\n            .fill(.regularMaterial)"),
               "both the standard and the Liquid Glass surface fill the whole balloon, no shape of their own")
        let panelViewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift",
            encoding: .utf8)) ?? ""
        let panelBodyCode: (String) -> String = { header in
            stripCommentLines((panelViewSource.components(separatedBy: header).last ?? "")
                .components(separatedBy: "\n    }").first ?? "")
        }
        suite.expect(panelBodyCode("private var navigablePanel: some View {").contains(".panelGlassSurface()")
                   && panelBodyCode("private var metricPanel: some View {").contains(".panelGlassSurface()"),
               "both the navigable panel and the metric panel wear that surface")

        // The panel keeps its top edge and its center while its content resizes.
        let panelArea = CGRect(x: 0, y: 0, width: 1470, height: 932)
        let shortPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                                  anchorMidX: 1283, anchorTop: 932,
                                                                  visibleFrame: panelArea)
        let tallPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 633),
                                                                 anchorMidX: 1283, anchorTop: 932,
                                                                 visibleFrame: panelArea)
        let shrunkPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                                   anchorMidX: 1283, anchorTop: 932,
                                                                   visibleFrame: panelArea)
        suite.expect(shortPanel.midX == 1283 && tallPanel.midX == 1283 && shrunkPanel.midX == 1283,
               "the pinned panel stays centered on its anchor through a content resize")
        suite.expect(shortPanel.maxY == 932 && tallPanel.maxY == 932 && shrunkPanel.maxY == 932,
               "a taller panel grows downward instead of moving its top edge")
        suite.expect(shortPanel == shrunkPanel,
               "going back to the first tab lands the panel exactly where it started")
        suite.expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: 20, anchorTop: 932,
                                                        visibleFrame: panelArea).minX == 8,
               "a panel anchored past the left edge stops at the margin")
        suite.expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: 1465, anchorTop: 932,
                                                        visibleFrame: panelArea).maxX == 1462,
               "a panel anchored past the right edge stops at the margin")
        suite.expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: -1910, anchorTop: 1155,
                                                        visibleFrame: CGRect(x: -1920, y: 100,
                                                                             width: 1920, height: 1055))
                == CGRect(x: -1912, y: 780, width: 332, height: 375),
               "a display left of the built-in one clamps against its own negative origin")
        suite.expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 633),
                                                        anchorMidX: 700, anchorTop: 300,
                                                        visibleFrame: CGRect(x: 0, y: 0,
                                                                             width: 1470, height: 300)).maxY == 300,
               "a screen too short for the panel still shows its top")
        suite.expect(registeredDefaults[DefaultsKey.menuBarHideIconWithMetrics] as? Bool == false,
               "the menu bar icon stays visible by default")
        suite.expect(MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                          metricsEnabled: true, renderedTitleLength: 12,
                                                          mustShowForSignal: false),
               "the glyph hides when metrics render in the title and the option is on")
        suite.expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: false, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 12,
                                                           mustShowForSignal: false),
               "the glyph never hides while the option is off")
        suite.expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 0,
                                                           mustShowForSignal: false),
               "an empty rendered title keeps the glyph, so the item can never turn invisible")
        suite.expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: false, renderedTitleLength: 6,
                                                           mustShowForSignal: false),
               "a countdown-only title keeps the glyph when no metric is enabled")
        suite.expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: true,
                                                           metricsEnabled: true, renderedTitleLength: 6,
                                                           mustShowForSignal: false),
               "separate metric items keep the glyph in the otherwise empty main item")
        suite.expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 12,
                                                           mustShowForSignal: true),
               "an available update or muted mic brings the glyph back to carry the signal")
        suite.expect(MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                              metricItemsShown: 2, renderedTitleLength: 0,
                                                              mustShowForSignal: false),
               "with separate metric items installed the whole main item may step aside")
        suite.expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 0, renderedTitleLength: 0,
                                                               mustShowForSignal: false),
               "no installed metric items keep the main item, so the app never vanishes")
        suite.expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 2, renderedTitleLength: 5,
                                                               mustShowForSignal: false),
               "an active countdown renders in the main item and keeps it visible")
        suite.expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: false,
                                                               metricItemsShown: 2, renderedTitleLength: 0,
                                                               mustShowForSignal: false),
               "the whole-item hiding only applies to the separate-items mode")

        // Dynamic Island may take the icon's place, but only while it runs:
        // with the island off or removed, nothing else on screen would lead
        // back to the app.
        suite.expect(registeredDefaults[DefaultsKey.notchHidesMenuBarIcon] as? Bool == false,
               "Dynamic Island only takes the icon's place when asked")
        let islandIconSuite = "com.vorssaint.tests.islandMenuBarIcon"
        if let islandDefaults = UserDefaults(suiteName: islandIconSuite) {
            islandDefaults.removePersistentDomain(forName: islandIconSuite)
            defer { islandDefaults.removePersistentDomain(forName: islandIconSuite) }
            islandDefaults.set(true, forKey: AppFeature.notch.availabilityKey)
            islandDefaults.set(true, forKey: DefaultsKey.notchEnabled)
            suite.expect(!MenuBarSpacingSupport.islandHidesStatusIcon(in: islandDefaults),
                   "a running island leaves the icon alone until asked")
            islandDefaults.set(true, forKey: DefaultsKey.notchHidesMenuBarIcon)
            suite.expect(MenuBarSpacingSupport.islandHidesStatusIcon(in: islandDefaults),
                   "a running island takes the icon's place when asked")
            islandDefaults.set(false, forKey: DefaultsKey.notchEnabled)
            suite.expect(!MenuBarSpacingSupport.islandHidesStatusIcon(in: islandDefaults),
                   "switching the island off brings the icon back")
            islandDefaults.set(true, forKey: DefaultsKey.notchEnabled)
            islandDefaults.set(false, forKey: AppFeature.notch.availabilityKey)
            suite.expect(!MenuBarSpacingSupport.islandHidesStatusIcon(in: islandDefaults),
                   "removing the island in the hub brings the icon back")
        }

        // A pinned metric that momentarily has nothing to show keeps its item
        // instead of being taken away and put back every tick.
        suite.expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: true, itemExists: false),
               "a metric with something to show gets its own item")
        suite.expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: false, itemExists: true,
                                                           consecutiveEmptyRenders: 1),
               "a reading that goes missing for a tick blanks its item instead of removing it")
        suite.expect(!MenuBarSpacingSupport.keepsMetricStatusItem(
            hasRenderedTitle: false, itemExists: true,
            consecutiveEmptyRenders: MenuBarSpacingSupport.emptyMetricRendersBeforeRemoval),
               "a reading that stops for good takes its item away instead of leaving a gap")
        suite.expect(MenuBarSpacingSupport.keepsMetricStatusItem(
            hasRenderedTitle: true, itemExists: true,
            consecutiveEmptyRenders: 99),
               "a reading that comes back keeps its item whatever came before")
        suite.expect(!MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: false, itemExists: false),
               "a metric with nothing to show yet gets no item at all")
        suite.expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: true, itemExists: true),
               "an item already showing a reading stays")
        suite.expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 2, renderedTitleLength: 0,
                                                               mustShowForSignal: true),
               "a signal brings the main item back even in the separate-items mode")
        suite.expect(MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: true,
                                                            showsCountdown: true,
                                                            hasEndDate: true),
               "a visible finite Keep Awake countdown owns the title timer")
        suite.expect(!MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: false,
                                                             showsCountdown: true,
                                                             hasEndDate: true)
                && !MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: true,
                                                                  showsCountdown: false,
                                                                  hasEndDate: true)
                && !MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: true,
                                                                  showsCountdown: true,
                                                                  hasEndDate: false),
               "idle, hidden and indefinite Keep Awake titles need no timer")
        let statusPlacementSuite = "com.vorssaint.tests.statusItemPlacement"
        if let statusDefaults = UserDefaults(suiteName: statusPlacementSuite) {
            statusDefaults.removePersistentDomain(forName: statusPlacementSuite)
            suite.expect(StatusItemPlacementSupport.placementGeneration(in: statusDefaults) == 0,
                   "initial placement generation is 0")
            suite.expect(StatusItemPlacementSupport.mainAutosaveName(in: statusDefaults) == "VorssaintMenuBarItem",
                   "generation 0 uses base autosave name")

            // The coordinate macOS saves for the icon is what puts it back in
            // the same spot on the next launch. 3.3.3 deleted the one written
            // by the older recovery on every launch, which moved the icon to
            // where a first-time item goes and, on a full bar, out of sight.
            let legacyKey = "NSStatusItem Preferred Position VorssaintMenuBarItem"
            statusDefaults.set(64.0, forKey: legacyKey)
            StatusItemPlacementSupport.clearRememberedVisibility(in: statusDefaults)
            suite.expect(statusDefaults.double(forKey: legacyKey) == 64.0,
                   "an icon placed by the older recovery keeps its spot through an update")

            statusDefaults.set(320.5, forKey: legacyKey)
            StatusItemPlacementSupport.clearRememberedVisibility(in: statusDefaults)
            suite.expect(statusDefaults.double(forKey: legacyKey) == 320.5,
                   "an icon the person arranged themselves keeps its spot too")

            StatusItemPlacementSupport.bumpPlacementGeneration(in: statusDefaults)
            let gen1Name = StatusItemPlacementSupport.mainAutosaveName(in: statusDefaults)
            suite.expect(gen1Name == "VorssaintMenuBarItem.1",
                   "bumped generation produces numbered autosave name")
            suite.expect(statusDefaults.object(forKey: "NSStatusItem Preferred Position VorssaintMenuBarItem.1") == nil,
                   "a reset lets macOS place the full item without a machine-specific position")
            suite.expect(statusDefaults.object(forKey: "NSStatusItem Preferred Position VorssaintMenuBarItem") == nil,
                   "bumping drops the previous identity's preferred position")

            // Recovery keeps the spot the person arranged and only drops the
            // hidden state macOS remembered: an item that starts over with no
            // saved position is born against the notch, the first place a
            // crowded bar hides.
            let gen1Position = "NSStatusItem Preferred Position VorssaintMenuBarItem.1"
            statusDefaults.set(280.0, forKey: gen1Position)
            statusDefaults.set(false, forKey: "NSStatusItem Visible VorssaintMenuBarItem.1")
            statusDefaults.set(false, forKey: "NSStatusItem VisibleCC VorssaintMenuBarItem.1")
            StatusItemPlacementSupport.clearRememberedVisibility(in: statusDefaults)
            suite.expect(statusDefaults.double(forKey: gen1Position) == 280.0,
                   "clearing the remembered visibility keeps the arranged position")
            suite.expect(StatusItemPlacementSupport.placementGeneration(in: statusDefaults) == 1
                    && StatusItemPlacementSupport.mainAutosaveName(in: statusDefaults) == gen1Name,
                   "recovery leaves the item's identity alone, so reopening cannot churn it")
            suite.expect(statusDefaults.object(forKey: "NSStatusItem Visible VorssaintMenuBarItem.1") == nil
                    && statusDefaults.object(forKey: "NSStatusItem VisibleCC VorssaintMenuBarItem.1") == nil,
                   "clearing the remembered visibility drops both spellings macOS has used")

            // Giving the spot up is what an explicit recovery escalates to,
            // and only after keeping it has failed.
            suite.expect(statusDefaults.object(forKey: gen1Position) == nil
                    || statusDefaults.double(forKey: gen1Position) == 280.0,
                   "only the identity reset gives up a saved position")
            // Leave orphan keys for older generations the way a long-running
            // install accumulates them, then confirm a bump sweeps them.
            statusDefaults.set(11.0, forKey: "NSStatusItem Preferred Position VorssaintMenuBarItem")
            statusDefaults.set(false, forKey: "NSStatusItem Visible VorssaintMenuBarItem")
            statusDefaults.set(false, forKey: "NSStatusItem VisibleCC VorssaintMenuBarItem.1")
            let metricPosition = "NSStatusItem Preferred Position VorssaintMetric.cpu"
            statusDefaults.set(42.0, forKey: metricPosition)
            StatusItemPlacementSupport.bumpPlacementGeneration(in: statusDefaults)
            suite.expect(statusDefaults.object(forKey: gen1Position) == nil
                    && statusDefaults.object(forKey: "NSStatusItem Preferred Position VorssaintMenuBarItem") == nil
                    && statusDefaults.object(forKey: "NSStatusItem Visible VorssaintMenuBarItem") == nil
                    && statusDefaults.object(forKey: "NSStatusItem VisibleCC VorssaintMenuBarItem.1") == nil
                    && StatusItemPlacementSupport.mainAutosaveName(in: statusDefaults)
                        == "VorssaintMenuBarItem.2"
                    && statusDefaults.object(forKey: "NSStatusItem Preferred Position VorssaintMenuBarItem.2") == nil,
                   "the identity reset gives the saved position up and sweeps orphaned identities")
            suite.expect(statusDefaults.double(forKey: metricPosition) == 42.0,
                   "recovering the main item leaves metric-item positions alone")
            statusDefaults.set(StatusItemPlacementSupport.maxPlacementGeneration,
                               forKey: DefaultsKey.statusItemPlacementGeneration)
            statusDefaults.set(false, forKey: "NSStatusItem Visible VorssaintMenuBarItem.9999")
            StatusItemPlacementSupport.bumpPlacementGeneration(in: statusDefaults)
            suite.expect(StatusItemPlacementSupport.mainAutosaveName(in: statusDefaults) == "VorssaintMenuBarItem.1"
                    && statusDefaults.object(forKey: "NSStatusItem Visible VorssaintMenuBarItem.9999") == nil
                    && statusDefaults.double(forKey: metricPosition) == 42.0,
                   "generation wrap clears old main-item state without touching metric placements")
            suite.expect(StatusItemAnchorSupport.isSettlingStatusFrame(CGRect(x: 0, y: 0, width: 36, height: 0)),
                   "a newborn status window with zero height is still settling")
            suite.expect(StatusItemAnchorSupport.isSettlingStatusFrame(nil),
                   "a status item without a window yet is still settling")
            suite.expect(!StatusItemAnchorSupport.isSettlingStatusFrame(CGRect(x: 2098, y: 1410, width: 36, height: 30)),
                   "a real on-bar frame is not settling")
            suite.expect(StatusItemPlacementSupport.shouldKeepWaitingForSettlement(
                       isOnScreen: false, isSettling: true, settlingGraceLeft: 3),
                   "settling frames keep the recovery waiting instead of declaring failure")
            suite.expect(!StatusItemPlacementSupport.shouldKeepWaitingForSettlement(
                        isOnScreen: false, isSettling: true, settlingGraceLeft: 0),
                   "settling grace eventually ends so recovery can escalate")
            suite.expect(!StatusItemPlacementSupport.shouldKeepWaitingForSettlement(
                        isOnScreen: true, isSettling: false, settlingGraceLeft: 3),
                   "an on-screen icon does not keep waiting")
            statusDefaults.removePersistentDomain(forName: statusPlacementSuite)
        }

        // MARK: An item macOS never placed is not "on screen" (issue #1394)

        // Measured on macOS 26 with the app switched off under System Settings
        // > Menu Bar > "Allow in the Menu Bar": AppKit builds the status window
        // at the bottom-left origin of the main display (AX reports it at
        // -1,1295 38x24) and never moves it. That rectangle intersects the
        // screen, which is all the recovery used to ask, so it logged
        // "appeared" for an icon nobody could see and never said why.
        let tahoeMain = CGRect(x: 0, y: 0, width: 2304, height: 1296)
        let tahoePortrait = CGRect(x: -1080, y: -173, width: 1080, height: 1920)
        let tahoeScreens = [tahoeMain, tahoePortrait]
        let unplacedFrame = CGRect(x: -1, y: -23, width: 38, height: 24)
        suite.expect(tahoeMain.intersects(unplacedFrame),
               "the unplaced frame does intersect the main screen, which is why intersection alone passed it")
        suite.expect(!StatusItemAnchorSupport.isSettlingStatusFrame(unplacedFrame),
               "the unplaced frame has real size, so the settling grace does not cover it")
        suite.expect(!StatusItemPlacementSupport.isPlacedStatusFrame(unplacedFrame, screenFrames: tahoeScreens),
               "a status window parked at the bottom-left origin is not a placed icon")
        suite.expect(StatusItemPlacementSupport.isPlacedStatusFrame(CGRect(x: 1792, y: 1269, width: 38, height: 24),
                                                                    screenFrames: tahoeScreens),
               "the same item placed in the main display's menu bar is")
        suite.expect(StatusItemPlacementSupport.isPlacedStatusFrame(CGRect(x: -900, y: 1710, width: 38, height: 24),
                                                                    screenFrames: tahoeScreens),
               "a placement in the portrait display's own menu bar counts too")
        suite.expect(!StatusItemPlacementSupport.isPlacedStatusFrame(CGRect(x: 1792, y: 1269, width: 0, height: 0),
                                                                     screenFrames: tahoeScreens),
               "a sizeless frame is not a placement")
        let iconIsOnScreenCode = stripCommentLines((statusAnchorAppDelegateSource
            .components(separatedBy: "private func iconIsOnScreen() -> Bool {").last ?? "")
            .components(separatedBy: "\n    }").first ?? "")
        suite.expect(iconIsOnScreenCode.contains("StatusItemPlacementSupport.isPlacedStatusFrame("),
               "the recovery judges placement by the menu bar band, not by screen intersection")
        suite.expect(iconIsOnScreenCode.contains("statusItem.isVisible == true"),
               "a hidden item never counts as on screen, whatever frame its window kept")
        // An item the app keeps out of the bar for Dynamic Island is not
        // missing, and a rebuild on reopen could strand the panel's anchor.
        let reopenCode = stripCommentLines((statusAnchorAppDelegateSource
            .components(separatedBy: "func applicationShouldHandleReopen(").last ?? "")
            .components(separatedBy: "\n    }").first ?? "")
        suite.expect(reopenCode.contains("mainItemHiddenByChoice != true, !iconIsOnScreen()"),
               "reopening the app leaves an item hidden by choice alone and opens Settings")
        let reshowCode = stripCommentLines((statusAnchorAppDelegateSource
            .components(separatedBy: "func reshowStatusItem() {").last ?? "")
            .components(separatedBy: "\n    }").first ?? "")
        suite.expect(reshowCode.contains("DefaultsKey.menuBarHideIconWithMetrics")
                     && reshowCode.contains("DefaultsKey.notchHidesMenuBarIcon"),
               "Show menu bar icon turns off both ways of hiding it")

        // macOS 26 lets the person switch an app's menu bar items off per app,
        // and remembers the choice in Control Center's group container. The
        // app cannot override it, so recovery must recognise it and say so
        // instead of resetting the item's identity for nothing.
        func tracked(_ bundleID: String, allowed: Bool?) -> [[String: Any]] {
            var entry: [String: Any] = ["location": ["bundle": ["_0": bundleID]],
                                        "menuItemLocations": [["bundle": ["_0": bundleID]]]]
            if let allowed { entry["isAllowed"] = allowed }
            return [["bundle": ["_0": bundleID]], entry]
        }
        let trackedApplications: [Any] = tracked("com.lowtechguys.Clop", allowed: true)
            + tracked("com.vorssaint.utils", allowed: false)
            + tracked("com.vorssaint.utils.dev", allowed: true)
            + tracked("com.example.legacy", allowed: nil)
        suite.expect(MenuBarAllowanceSupport.allowance(forBundleID: "com.vorssaint.utils",
                                                       trackedApplications: trackedApplications) == .disallowed,
               "an app switched off under Allow in the Menu Bar reads as disallowed")
        suite.expect(MenuBarAllowanceSupport.allowance(forBundleID: "com.vorssaint.utils.dev",
                                                       trackedApplications: trackedApplications) == .allowed,
               "a sibling bundle id with its own entry does not bleed over")
        suite.expect(MenuBarAllowanceSupport.allowance(forBundleID: "com.example.legacy",
                                                       trackedApplications: trackedApplications) == .unknown,
               "an entry without the flag is unknown, never a verdict")
        suite.expect(MenuBarAllowanceSupport.allowance(forBundleID: "com.example.absent",
                                                       trackedApplications: trackedApplications) == .unknown,
               "an app Control Center has never tracked is unknown")
        suite.expect(MenuBarAllowanceSupport.allowance(forBundleID: "com.vorssaint.utils",
                                                       trackedApplications: ["garbage", 3]) == .unknown,
               "a malformed store is unknown rather than a crash or a verdict")
        // The on-disk shape: an outer plist whose trackedApplications value is
        // itself a binary plist, serialized as data.
        let innerData = try? PropertyListSerialization.data(fromPropertyList: trackedApplications,
                                                            format: .binary, options: 0)
        let outerData = innerData.flatMap {
            try? PropertyListSerialization.data(fromPropertyList: ["trackedApplications": $0,
                                                                   "showSpotlight": false],
                                                format: .binary, options: 0)
        }
        suite.expect(outerData.map {
                MenuBarAllowanceSupport.allowance(forBundleID: "com.vorssaint.utils", groupContainerPlist: $0)
            } == .disallowed,
               "the nested Control Center store decodes down to the per-app verdict")
        suite.expect(MenuBarAllowanceSupport.allowance(forBundleID: "com.vorssaint.utils",
                                                       groupContainerPlist: Data([0x00, 0x01])) == .unknown,
               "an unreadable store is unknown")
        let verifyIconCode = stripCommentLines((statusAnchorAppDelegateSource
            .components(separatedBy: "private func verifyIconReappeared(").last ?? "")
            .components(separatedBy: "\n    }").first ?? "")
        suite.expect(verifyIconCode.contains("MenuBarAllowanceSupport.currentAllowance(")
                    && verifyIconCode.contains("menuBarIconDisallowedBody"),
               "recovery names the Allow in the Menu Bar setting instead of blaming a full bar")
        let allowanceCheck = verifyIconCode.range(of: "MenuBarAllowanceSupport.currentAllowance(")
        let identityReset = verifyIconCode.range(of: "resetStatusItemPlacementIdentity()")
        suite.expect(allowanceCheck != nil && identityReset != nil
                    && allowanceCheck!.lowerBound < identityReset!.lowerBound,
               "the setting is checked before the identity reset burns the arranged spot")
        suite.expect(!Strings.enUS.menuBarIconDisallowedBody.isEmpty
                    && !Strings.ptBR.menuBarIconDisallowedBody.isEmpty
                    && Strings.enUS.menuBarIconDisallowedBody.contains("Allow in the Menu Bar"),
               "the hint names the System Settings switch by its own label")
        suite.expect(registeredDefaults[DefaultsKey.panelControlAutoQuit] as? Bool == true,
               "panel auto quit control is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelControlShelf] as? Bool == true,
               "panel shelf control is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelControlWindowMaximize] as? Bool == true,
               "panel window maximize control is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelControlKeyDebounce] as? Bool == true,
               "panel keyboard debounce control is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelControlTextSnippets] as? Bool == true,
               "panel text snippets control is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.panelShowKeepAwake] as? Bool == true,
               "Keep Awake panel section is shown by default")
        suite.expect(registeredDefaults[DefaultsKey.panelShowBrightness] as? Bool == true,
               "brightness panel section is shown by default once the feature is on")
        suite.expect(registeredDefaults[DefaultsKey.brightnessControlEnabled] as? Bool == false,
               "brightness control arrives switched off")
        suite.expect(registeredDefaults[DefaultsKey.brightnessKeysEnabled] as? Bool == false,
               "pointer-following brightness keys arrive switched off")
        suite.expect(registeredDefaults[DefaultsKey.brightnessOSDEnabled] as? Bool == false,
               "brightness adjustment overlay arrives switched off")
        suite.expect(registeredDefaults[DefaultsKey.keyboardBrightnessDecreaseShortcut] as? String
                == GlobalShortcut.keyboardBrightnessDecreaseDefault.storageValue
                && registeredDefaults[DefaultsKey.keyboardBrightnessIncreaseShortcut] as? String
                == GlobalShortcut.keyboardBrightnessIncreaseDefault.storageValue,
               "keyboard brightness shortcuts ship with distinct defaults")
        suite.expect(registeredDefaults[DefaultsKey.keyboardBrightnessShortcutsEnabled] as? Bool == false,
               "keyboard brightness shortcuts arrive switched off")
        let keyboardShortcutSettings: [String: Any] = [
            DefaultsKey.keyboardBrightnessShortcutsEnabled: true,
            DefaultsKey.keyboardBrightnessDecreaseShortcut: "control+command:27",
            DefaultsKey.keyboardBrightnessIncreaseShortcut: "control+command:24",
        ]
        let keyboardShortcutBackup = SettingsBackupSupport.payload(appVersion: "test") {
            keyboardShortcutSettings[$0]
        }
        let restoredKeyboardShortcuts = SettingsBackupSupport.sanitizedSettings(from: keyboardShortcutBackup)
        suite.expect(keyboardShortcutSettings.allSatisfy { key, value in
            (restoredKeyboardShortcuts?[key] as? NSObject) == (value as? NSObject)
        }, "keyboard brightness opt-in and custom shortcuts survive a settings backup")

        for enabled in [false, true] {
            let displayShortcutSettings: [String: Any] = [
                DefaultsKey.brightnessControlEnabled: enabled,
                DefaultsKey.brightnessKeysEnabled: enabled,
                DefaultsKey.brightnessOSDEnabled: enabled,
                DefaultsKey.displayBrightnessShortcutsEnabled: enabled,
                DefaultsKey.displayBrightnessDecreaseShortcut: "control+command:27",
                DefaultsKey.displayBrightnessIncreaseShortcut: "control+command:24",
            ]
            let backup = SettingsBackupSupport.payload(appVersion: "test") {
                displayShortcutSettings[$0]
            }
            let data = try? JSONSerialization.data(withJSONObject: backup)
            let decoded = data.flatMap {
                (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
            }
            let restored = decoded.flatMap { SettingsBackupSupport.sanitizedSettings(from: $0) }
            suite.expect(displayShortcutSettings.allSatisfy { key, value in
                (restored?[key] as? NSObject) == (value as? NSObject)
            }, "display controls and custom brightness shortcuts survive JSON backup and restore, enabled=\(enabled)")
        }

        suite.expect(registeredDefaults[DefaultsKey.screenshotOpenEditorDirectly] as? Bool == false,
               "capture keeps showing the preview unless the user opts into the editor")
        suite.expect(registeredDefaults[DefaultsKey.screenshotDefaultAction] as? String == "",
               "captures keep asking what to do until an after-capture action is chosen")
        suite.expect(registeredDefaults[DefaultsKey.screenshotSaveSubfolder] as? String == ""
                && registeredDefaults[DefaultsKey.screenshotFileNamePattern] as? String == "",
               "subfolder and file name patterns arrive empty, keeping the stock naming")
        suite.expect(registeredDefaults[DefaultsKey.screenshotFileNumberStart] as? Int == 1
                && registeredDefaults[DefaultsKey.screenshotFileNumberNext] as? Int == 1,
               "the file number sequence starts counting at 1")
        suite.expect(registeredDefaults[DefaultsKey.panelShowUtilities] as? Bool == true,
               "Utilities panel section is shown by default")
        suite.expect(registeredDefaults[DefaultsKey.panelShowControls] as? Bool == true,
               "Quick Controls panel section is shown by default")
        suite.expect(registeredDefaults[DefaultsKey.panelShowToggles] as? Bool == true,
               "Quick toggles panel section is shown by default")
        suite.expect([DefaultsKey.panelToggleDarkMode, DefaultsKey.panelToggleKeyboardLight,
                DefaultsKey.panelToggleMicMute,
                DefaultsKey.panelToggleEmptyTrash,
                DefaultsKey.panelToggleEjectDisks, DefaultsKey.panelToggleHiddenFiles,
                DefaultsKey.panelToggleDesktopIcons, DefaultsKey.panelToggleLockScreen,
                DefaultsKey.panelToggleDisplayOff, DefaultsKey.panelToggleScreenSaver]
                .allSatisfy { registeredDefaults[$0] as? Bool == true },
               "every quick toggle row is visible by default")
        suite.expect(registeredDefaults[DefaultsKey.monitorInterval] as? Int == 2,
               "monitor default interval stays at 2 seconds")
        suite.expect(registeredDefaults[DefaultsKey.monitorShowDisk] as? Bool == true,
               "disk monitor panel section is shown by default")
        suite.expect(registeredDefaults[DefaultsKey.monitorSysAlerts] as? Bool == true,
               "system alert controls are shown by default")
        suite.expect(registeredDefaults[DefaultsKey.monitorGraphDisk] as? Bool == true,
               "disk monitor graph is shown by default")
        suite.expect(registeredDefaults[DefaultsKey.monitorNetApps] as? Bool == true,
               "network app usage block is shown by default")
        suite.expect(registeredDefaults[DefaultsKey.monitorNetAddresses] as? Bool == true,
               "local address block is shown by default and travels in backups")
        suite.expect(registeredDefaults[DefaultsKey.monitorDiskUsage] as? Bool == true,
               "disk usage block is shown by default")
        suite.expect(registeredDefaults[DefaultsKey.monitorDiskActivity] as? Bool == true,
               "disk activity block is shown by default")
        suite.expect(registeredDefaults[DefaultsKey.monitorDiskSMART] as? Bool == true,
               "disk SMART block is shown by default")
        suite.expect(registeredDefaults[DefaultsKey.monitorDiskProtection] as? Bool == true,
               "disk protection block is shown by default")
        suite.expect(registeredDefaults[DefaultsKey.monitorDiskTools] as? Bool == true,
               "disk tools block is shown by default")
        suite.expect(registeredDefaults[DefaultsKey.temperatureUnit] as? String == TemperatureUnit.celsius.rawValue,
               "temperature defaults to Celsius")
        suite.expect(registeredDefaults[DefaultsKey.menuBarCPUTemperature] as? Bool == false,
               "menu bar CPU temperature is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.menuBarGPUTemperature] as? Bool == false,
               "menu bar GPU temperature is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.menuBarBatteryTemperature] as? Bool == false,
               "menu bar battery temperature is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.menuBarBatteryTime] as? Bool == false,
               "menu bar battery time is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.menuBarDiskUsage] as? Bool == false,
               "menu bar disk usage is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.menuBarDiskActivity] as? Bool == false,
               "menu bar disk activity is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.menuBarPeripheralBattery] as? Bool == false,
               "menu bar peripheral battery is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.menuBarFanSpeed] as? Bool == false,
               "menu bar fan speed is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.menuBarMetricOrder] as? String
               == "cpu,cpuTemperature,gpu,gpuTemperature,memory,battery,batteryTime,batteryTemperature,peripheralBattery,network,diskUsage,diskActivity,power,fanSpeed",
               "menu bar metric order keeps temperature sensors next to their components and disk near live I/O")
        suite.expect(registeredDefaults[DefaultsKey.menuBarCombineTemperatures] as? Bool == true,
               "menu bar combines usage and temperature by default")
        suite.expect(registeredDefaults[DefaultsKey.menuBarSeparateMetrics] as? Bool == false,
               "separate menu bar metric items are opt-in")
        suite.expect(registeredDefaults[DefaultsKey.menuBarNetworkUploadFirst] as? Bool == false,
               "network menu bar upload-first layout is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.menuBarLabelStyle] as? String == "compact",
               "menu bar label style defaults to compact")
        suite.expect(registeredDefaults[DefaultsKey.menuBarMemoryStyle] as? String == "percent",
               "memory menu bar style defaults to percent")
        suite.expect(registeredDefaults[DefaultsKey.monitorPwrTimeRemaining] as? Bool == true,
               "battery time is shown in the Power panel by default")
        suite.expect(registeredDefaults[DefaultsKey.windowLayoutShortcutsEnabled] as? Bool == false,
               "window layout shortcuts stay off until enabled")
        suite.expect(registeredDefaults[DefaultsKey.windowEdgeSnapEnabled] as? Bool == false,
               "dragging windows to screen edges is opt-in")
        suite.expect(registeredDefaults[DefaultsKey.windowEdgeSnapDisabledZones] as? String == "",
               "every visual edge snap zone starts enabled")
        suite.expect(registeredDefaults[DefaultsKey.windowGestureEnabled] as? Bool == false,
               "window move and resize gestures are opt-in")
        suite.expect(registeredDefaults[DefaultsKey.mouseSpacesGestureEnabled] as? Bool == false
                && registeredDefaults[DefaultsKey.mouseSpacesGestureButton] as? Int == 0
                && registeredDefaults[DefaultsKey.mouseSpacesGestureFollowsDrag] as? Bool == false,
               "the Spaces and Mission Control drag ships off, with no button bound and the plain direction")
        suite.expect(registeredDefaults[DefaultsKey.windowGestureModifiers] as? String == "control+command",
               "window gestures start with the deliberate control-command chord")
        suite.expect(registeredDefaults[DefaultsKey.windowGestureRaiseWindow] as? Bool == false,
               "window gestures do not change app focus unless requested")
        let assignedLayoutShortcutKeys = [
            DefaultsKey.windowLayoutShortcutLeft,
            DefaultsKey.windowLayoutShortcutRight,
            DefaultsKey.windowLayoutShortcutTop,
            DefaultsKey.windowLayoutShortcutBottom,
            DefaultsKey.windowLayoutShortcutTopLeft,
            DefaultsKey.windowLayoutShortcutTopRight,
            DefaultsKey.windowLayoutShortcutBottomLeft,
            DefaultsKey.windowLayoutShortcutBottomRight,
            DefaultsKey.windowLayoutShortcutMaximize,
            DefaultsKey.windowLayoutShortcutCenter,
            DefaultsKey.windowLayoutShortcutRestore,
            DefaultsKey.windowLayoutShortcutLeftThird,
            DefaultsKey.windowLayoutShortcutCenterThird,
            DefaultsKey.windowLayoutShortcutRightThird,
            DefaultsKey.windowLayoutShortcutLeftTwoThirds,
            DefaultsKey.windowLayoutShortcutRightTwoThirds,
            DefaultsKey.windowLayoutShortcutNextDisplay,
        ]
        let assignedLayoutShortcutValues = assignedLayoutShortcutKeys.compactMap {
            registeredDefaults[$0] as? String
        }
        suite.expect(assignedLayoutShortcutValues.count == assignedLayoutShortcutKeys.count,
               "every established window layout action has a registered shortcut")
        let unassignedLayoutShortcutKeys = [
            DefaultsKey.windowLayoutShortcutTopLeftSixth,
            DefaultsKey.windowLayoutShortcutTopCenterSixth,
            DefaultsKey.windowLayoutShortcutTopRightSixth,
            DefaultsKey.windowLayoutShortcutBottomLeftSixth,
            DefaultsKey.windowLayoutShortcutBottomCenterSixth,
            DefaultsKey.windowLayoutShortcutBottomRightSixth,
            DefaultsKey.windowLayoutShortcutPreviousDisplay,
            DefaultsKey.windowLayoutShortcutMarginMaximize,
        ]
        suite.expect(unassignedLayoutShortcutKeys.allSatisfy {
                   registeredDefaults[$0] as? String == WindowLayoutAction.clearedShortcutStorageValue
               },
               "new window layout shortcuts start unassigned")
        suite.expect(Set(assignedLayoutShortcutValues).count == assignedLayoutShortcutValues.count,
               "window layout shortcuts do not conflict with each other by default")
        let globalShortcutValues = GlobalShortcutRole.allCases
            .compactMap { registeredDefaults[$0.storageKey] as? String }
        suite.expect(Set(assignedLayoutShortcutValues).intersection(globalShortcutValues).isEmpty,
               "window layout shortcuts do not conflict with other global shortcuts by default")
        // Two features shipping the same combination means one of them is dead
        // on arrival: the second registration is simply refused by the system,
        // and which one loses depends on the order they happen to sync in.
        suite.expect(Set(globalShortcutValues).count == globalShortcutValues.count,
               "no two features ship the same default combination")
        suite.expect(globalShortcutValues.count == GlobalShortcutRole.allCases.count,
               "every role ships with a default combination registered")
        suite.expect(GlobalShortcut(keyCode: Int64(kVK_ISO_Section),
                              modifiers: [.control, .option, .command]).isValid,
               "the extra ISO key (paragraph/caret above Tab) is recordable as a shortcut")
        // MARK: Dock Preview helpers

        let dockPrefs = DockPreviewPreferences.sanitized(orientation: "left",
                                                         autohide: true,
                                                         tileSize: 81,
                                                         magnification: false,
                                                         magnifiedTileSize: 100)
        suite.expect(dockPrefs == DockPreviewPreferences(orientation: .left,
                                                   autohide: true,
                                                   tileSize: 81,
                                                   magnification: false,
                                                   magnifiedTileSize: 100),
               "Dock Preview preferences preserve valid Dock values")
        let fallbackDockPrefs = DockPreviewPreferences.sanitized(orientation: "bad",
                                                                 autohide: nil,
                                                                 tileSize: 999,
                                                                 magnification: nil,
                                                                 magnifiedTileSize: nil)
        suite.expect(fallbackDockPrefs == DockPreviewPreferences(orientation: .bottom,
                                                           autohide: false,
                                                           tileSize: 256,
                                                           magnification: false,
                                                           magnifiedTileSize: 128),
               "Dock Preview preferences sanitize missing and out-of-range values")
        suite.expect(DockPreviewSupport.availability(enabled: false,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs)
               == DockPreviewAvailability(canRun: false, blockedReason: nil),
               "disabled Dock Preview does not report an error")
        suite.expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: false,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs).blockedReason == .missingAccessibility,
               "Dock Preview requires Accessibility")
        suite.expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: false,
                                               preferences: dockPrefs).blockedReason == .missingScreenRecording,
               "Dock Preview requires Screen Recording")
        let magnifiedPrefs = DockPreviewPreferences(orientation: .bottom,
                                                    autohide: false,
                                                    tileSize: 64,
                                                    magnification: true,
                                                    magnifiedTileSize: 128)
        suite.expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: magnifiedPrefs).canRun,
               "Dock Preview runs with Dock magnification enabled")
        suite.expect(magnifiedPrefs.hoverTileSize == 128,
               "hover tile size follows the magnified size while magnification is on")
        suite.expect(dockPrefs.hoverTileSize == 81,
               "hover tile size stays at the resting size while magnification is off")
        suite.expect(DockPreviewSupport.dockProximityBand(tileSize: magnifiedPrefs.hoverTileSize)
               > magnifiedPrefs.magnifiedTileSize,
               "Dock proximity band covers a fully magnified icon")
        suite.expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs).canRun,
               "Dock Preview can run when enabled and permitted")

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let iconBottom = CGRect(x: 660, y: 0, width: 80, height: 80)
        let panelSize = CGSize(width: 400, height: 160)
        let bottomFrame = DockPreviewSupport.panelFrame(anchor: iconBottom,
                                                        panelSize: panelSize,
                                                        screenVisibleFrame: screen,
                                                        orientation: .bottom)
        suite.expectClose(Double(bottomFrame.midX), Double(iconBottom.midX), "Dock Preview bottom panel centers on icon")
        suite.expect(bottomFrame.minY > iconBottom.maxY,
               "Dock Preview bottom panel sits above the Dock icon")
        let leftFrame = DockPreviewSupport.panelFrame(anchor: CGRect(x: 0, y: 380, width: 80, height: 80),
                                                      panelSize: panelSize,
                                                      screenVisibleFrame: screen,
                                                      orientation: .left)
        suite.expect(leftFrame.minX > 80,
               "Dock Preview left panel sits to the right of the Dock")
        let rightFrame = DockPreviewSupport.panelFrame(anchor: CGRect(x: 1360, y: 380, width: 80, height: 80),
                                                       panelSize: panelSize,
                                                       screenVisibleFrame: screen,
                                                       orientation: .right)
        suite.expect(rightFrame.maxX < 1360,
               "Dock Preview right panel sits to the left of the Dock")
        let hiddenLeftFrame = DockPreviewSupport.panelFrameWhenDockHidden(
            leftFrame, screenVisibleFrame: screen, orientation: .left)
        suite.expect(hiddenLeftFrame.minX == screen.minX + DockPreviewSupport.edgePadding
               && hiddenLeftFrame.minY == leftFrame.minY,
               "Dock Preview fills a left auto-hidden Dock's vacated edge without jumping vertically")
        let hiddenRightFrame = DockPreviewSupport.panelFrameWhenDockHidden(
            rightFrame, screenVisibleFrame: screen, orientation: .right)
        suite.expect(hiddenRightFrame.maxX == screen.maxX - DockPreviewSupport.edgePadding
               && hiddenRightFrame.minY == rightFrame.minY,
               "Dock Preview fills a right auto-hidden Dock's vacated edge without jumping vertically")
        let hiddenBottomFrame = DockPreviewSupport.panelFrameWhenDockHidden(
            bottomFrame, screenVisibleFrame: screen, orientation: .bottom)
        suite.expect(hiddenBottomFrame.minY == screen.minY + DockPreviewSupport.edgePadding
               && hiddenBottomFrame.minX == bottomFrame.minX,
               "Dock Preview fills a bottom auto-hidden Dock's vacated edge without jumping horizontally")
        let resizedDockFrame = DockPreviewSupport.panelFrame(
            anchor: iconBottom,
            panelSize: DockPreviewSupport.panelSize(itemCount: 1,
                                                    screenVisibleFrame: screen,
                                                    isPinned: false),
            screenVisibleFrame: screen,
            orientation: .bottom
        )
        let expectedResizedEdgeFrame = DockPreviewSupport.panelFrameWhenDockHidden(
            resizedDockFrame, screenVisibleFrame: screen, orientation: .bottom)
        suite.expect(DockPreviewSupport.resizedPanelFrame(
                resizedDockFrame,
                didReattachForSession: true,
                screenVisibleFrame: screen,
                orientation: .bottom) == expectedResizedEdgeFrame,
               "resizing a reattached Dock Preview keeps it at the vacated screen edge")
        suite.expect(!DockPreviewSupport.shouldStartDockVisibilityTimer(
                hasActiveTimer: false,
                didReattachForSession: true,
                autohide: true),
               "a reattached Dock Preview does not re-arm its visibility watcher")
        // Both complements, so neither helper can be mutated into a constant
        // and stay green: an always-edge frame would strand a panel that was
        // never reattached, and an always-false watcher would never fire once.
        suite.expect(DockPreviewSupport.resizedPanelFrame(
                resizedDockFrame,
                didReattachForSession: false,
                screenVisibleFrame: screen,
                orientation: .bottom) == resizedDockFrame,
               "a preview that never reattached keeps resizing to the Dock-anchored frame")
        suite.expect(DockPreviewSupport.shouldStartDockVisibilityTimer(
                hasActiveTimer: false,
                didReattachForSession: false,
                autohide: true),
               "an auto-hiding Dock still arms the visibility watcher the first time")
        let dockPreviewServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/DockPreview/DockPreviewService.swift",
            encoding: .utf8)) ?? ""
        let dockPreviewServiceCode = dockPreviewServiceSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(dockPreviewServiceCode.contains("startDockVisibilityTimerIfNeeded()")
               && dockPreviewServiceCode.contains("CGWindowListCopyWindowInfo(.optionOnScreenOnly")
               && dockPreviewServiceCode.contains("DockPreviewSupport.panelFrameWhenDockHidden("),
               "an entered auto-hide Dock Preview follows the Dock's live window to the vacated edge")
        suite.expect(dockPreviewServiceCode.contains("if accepted { self?.endSession() }")
                && dockPreviewServiceCode.contains("if accepted { self?.closePreviewPanel() }"),
               "an accepted app quit closes both hover and pinned previews immediately")
        // The jump is the Dock's thickness, an order of magnitude past
        // panelStayMargin, so a pointer that never moved would otherwise read as
        // outside the panel on its next twitch and dismiss the preview.
        suite.expect(dockPreviewServiceCode.contains("reattachGraceFrame = frame")
               && dockPreviewServiceCode.contains("reattachGraceFrame?.insetBy("),
               "the frame a reattached Dock Preview left behind keeps counting until the pointer reaches the new one")
        // The tap this service owns is served by the main run loop, so an
        // animated setFrame would queue every mouse event behind the slide.
        suite.expect(!dockPreviewServiceCode.contains("setFrame(edgeFrame, display: true, animate: true)")
               && dockPreviewServiceCode.contains("clampedPanelFrame(DockPreviewSupport.panelFrameWhenDockHidden("),
               "a reattached Dock Preview lands clamped, without animating the main run loop")
        let corridor = DockPreviewSupport.hoverCorridor(iconFrame: iconBottom,
                                                        panelFrame: bottomFrame,
                                                        orientation: .bottom)
        suite.expect(corridor.contains(CGPoint(x: iconBottom.midX, y: (iconBottom.maxY + bottomFrame.minY) / 2)),
               "Dock Preview corridor keeps the path from Dock icon to panel alive")
        // A neighbouring Dock icon, one tile to the side, must fall OUTSIDE the
        // corridor; otherwise returning to the Dock can never hand the session to
        // another app and the panel stays stuck on the previous one.
        let neighborIcon = CGRect(x: iconBottom.maxX + 8, y: 0, width: 80, height: 80)
        suite.expect(!corridor.contains(CGPoint(x: neighborIcon.midX, y: neighborIcon.midY)),
               "Dock Preview corridor excludes the neighbouring Dock icon so app switching works")
        suite.expect(DockPreviewSupport.dockProximityBand(tileSize: 64) >= 160,
               "Dock proximity band covers a default-size Dock")
        suite.expect(DockPreviewSupport.dockProximityBand(tileSize: 200)
               > DockPreviewSupport.dockProximityBand(tileSize: 64),
               "Dock proximity band grows with the Dock tile size")
        let onePreviewSize = DockPreviewSupport.panelSize(itemCount: 1, screenVisibleFrame: screen,
                                                          isPinned: false)
        let twoPreviewSize = DockPreviewSupport.panelSize(itemCount: 2, screenVisibleFrame: screen,
                                                          isPinned: false)
        suite.expect(twoPreviewSize.width > onePreviewSize.width,
               "Dock Preview panel size shrinks when a card is removed")
        // The header carries the window counter and the steppers that move
        // between windows, so one window leaves it with nothing to say. It used
        // to name the app instead, back at a pointer resting on that app's Dock
        // icon. A pinned panel keeps it: there it is the drag handle, and the
        // only way to unpin or close.
        // A long name is clipped at rest and scrolled under the pointer. The
        // measurement runs off the font rather than a layout pass, so it holds
        // before the band has ever been drawn.
        let bandWidth = DockPreviewSupport.cardTitleTextWidth
        suite.expect(bandWidth > 0 && bandWidth < DockPreviewSupport.cardThumbnailWidth,
               "the name's room is the band less the two controls beside it")
        suite.expect(!SwitcherSupport.titleOverflows("Mail", width: bandWidth),
               "a short window name is not scrolled")
        suite.expect(SwitcherSupport.titleOverflows(String(repeating: "measurement ", count: 8),
                                              width: bandWidth),
               "a name longer than the band is")
        suite.expect(!SwitcherSupport.titleOverflows("anything", width: 0),
               "a band with no room to measure against scrolls nothing")
        suite.expect(SwitcherSupport.titleWidth("Preferences", weight: .semibold)
               > SwitcherSupport.titleWidth("Preferences", weight: .regular),
               "the selected card's heavier name is measured as the heavier name")
        // Both panels show windows of the same kind, so a name too long for its
        // room behaves the same in each. One view, two callers, two widths.
        let scrollingTitleSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Switcher/ScrollingTitle.swift",
            encoding: .utf8)) ?? ""
        suite.expect(scrollingTitleSource.contains("struct ScrollingTitle: View"),
               "the scrolling name is one view, not a copy in each panel")
        let switcherCardSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Switcher/SwitcherView.swift",
            encoding: .utf8)) ?? ""
        suite.expect(switcherCardSource.contains("ScrollingTitle(")
               && dockPreviewCardSource.contains("ScrollingTitle("),
               "the App Switcher and the Dock preview both draw their name through it")
        // One view, hung differently by each panel. Pinning it to the leading
        // edge in both left a grid card's name and the app name under it on two
        // different axes, which reads as a broken card rather than a choice.
        suite.expect(scrollingTitleSource.contains(".frame(width: width, alignment: alignment)"),
               "the shared name view is told where to sit instead of always taking the leading edge")
        suite.expect(sourceBody(of: switcherCardSource, from: "ScrollingTitle(", to: "scrolls:")
                .contains("alignment: .center"),
               "a grid card centres the window's name over the app name under it")
        suite.expect(sourceBody(of: dockPreviewCardSource, from: "ScrollingTitle(", to: "scrolls:")
                .contains("alignment: .leading"),
               "a Dock preview card keeps the name on the leading edge, beside its two buttons")
        suite.expect(!DockPreviewSupport.showsPanelHeader(isPinned: false),
               "a hovered panel draws no header, whatever it is showing")
        suite.expect(DockPreviewSupport.showsPanelHeader(isPinned: true),
               "a pinned panel keeps the header that names it and moves it")
        // Cards run along the Dock's own edge. A row beside a side Dock grew
        // away from it across the screen, which is the one direction the
        // pointer is not coming from.
        suite.expect(!DockPreviewSupport.stacksVertically(orientation: .bottom, isPinned: false),
               "a Dock at the bottom gets a row of cards")
        suite.expect(DockPreviewSupport.stacksVertically(orientation: .left, isPinned: false)
               && DockPreviewSupport.stacksVertically(orientation: .right, isPinned: false),
               "a Dock at either side gets a column of cards")
        suite.expect(!DockPreviewSupport.stacksVertically(orientation: .right, isPinned: true),
               "a pinned panel is detached from the Dock, so it keeps the row")
        let sideSize = DockPreviewSupport.panelSize(itemCount: 3, screenVisibleFrame: screen,
                                                    isPinned: false, orientation: .right)
        let bottomSize = DockPreviewSupport.panelSize(itemCount: 3, screenVisibleFrame: screen,
                                                      isPinned: false, orientation: .bottom)
        suite.expect(sideSize.width == DockPreviewSupport.cardWidth + DockPreviewSupport.panelPadding * 2,
               "a side Dock's panel is one card wide however many windows it holds")
        suite.expect(sideSize.height > bottomSize.height && sideSize.width < bottomSize.width,
               "the same three windows make a tall narrow panel beside a side Dock")
        suite.expect(DockPreviewSupport.visibleCardCount(itemCount: 99, screenVisibleFrame: screen,
                                                   orientation: .bottom, isPinned: false) < 99,
               "the panel reports how many cards it can show before it has to scroll")
        suite.expect(DockPreviewSupport.visibleCardCount(itemCount: 2, screenVisibleFrame: screen,
                                                   orientation: .bottom, isPinned: false) == 2,
               "two cards that fit are both counted, so the panel does not scroll for them")
        suite.expect(onePreviewSize.height == DockPreviewSupport.cardHeight
               + DockPreviewSupport.panelPadding * 2,
               "a headerless panel is the card and the padding, nothing more")
        suite.expect(DockPreviewSupport.panelSize(itemCount: 1, screenVisibleFrame: screen, isPinned: true).height
               == onePreviewSize.height + DockPreviewSupport.panelHeaderHeight,
               "the header is the whole difference a pinned panel makes to the height")
        suite.expect(DockPreviewSupport.windowPositionText(selectedWindowID: nil, windowIDs: [11]) == nil,
               "Dock Preview hides the window counter for a single window")
        suite.expect(DockPreviewSupport.windowPositionText(selectedWindowID: nil, windowIDs: [11, 22, 33]) == "3",
               "Dock Preview header shows the window count before a card is selected")
        suite.expect(DockPreviewSupport.windowPositionText(selectedWindowID: 22, windowIDs: [11, 22, 33]) == "2/3",
               "Dock Preview header shows selected window position")
        let iconRowLayout = SwitcherIconRowLayout.compute(count: 6, screenVisibleFrame: screen)
        suite.expect(iconRowLayout.visibleIconCount == 6,
               "App Switcher icon-row mode can show all icons when they fit")
        suite.expect(iconRowLayout.panelSize.width <= screen.width * 0.96 + SwitcherIconRowLayout.padding * 2,
               "App Switcher icon-row mode stays within the visible screen")
        suite.expect(iconRowLayout.panelSize.height
               == SwitcherIconRowLayout.previewHeight
               + SwitcherIconRowLayout.previewGap
               + SwitcherIconRowLayout.rowHeight
               + SwitcherIconRowLayout.hintGap
               + SwitcherIconRowLayout.hintHeight
               + SwitcherIconRowLayout.padding * 2,
               "App Switcher icon-row mode reserves preview, icon row and shortcut hint height")
        suite.expect(iconRowLayout.simplePanelSize.height
               == SwitcherIconRowLayout.simpleTitleHeight
               + SwitcherIconRowLayout.simpleTitleGap
               + SwitcherIconRowLayout.rowHeight
               + SwitcherIconRowLayout.hintGap
               + SwitcherIconRowLayout.hintHeight
               + SwitcherIconRowLayout.padding * 2,
               "App Switcher simple mode replaces previews with a compact title rail")
        suite.expect(iconRowLayout.simplePanelSize.width
               == max(iconRowLayout.appRowSurfaceWidth,
                      iconRowLayout.simpleTitleSurfaceWidth,
                      SwitcherIconRowLayout.hintBarWidth)
               + SwitcherIconRowLayout.padding * 2,
               "App Switcher simple mode fits its app row, title rail and shortcut hints")
        let compactIconRowLayout = SwitcherIconRowLayout.compute(
            appCount: 1,
            selectedWindowCount: 1,
            screenVisibleFrame: screen,
            showsShortcutHints: false
        )
        suite.expect(compactIconRowLayout.panelSize.height
               == iconRowLayout.panelSize.height
               - SwitcherIconRowLayout.hintGap
               - SwitcherIconRowLayout.hintHeight,
               "App Switcher removes the shortcut hint bar and its vertical space")
        suite.expect(compactIconRowLayout.simplePanelSize.width
               == max(compactIconRowLayout.appRowSurfaceWidth,
                      compactIconRowLayout.simpleTitleSurfaceWidth)
                    + SwitcherIconRowLayout.padding * 2,
               "App Switcher without shortcut hints still fits its title rail")
        // Two apps leave the icon row narrower than the hint bar, the case that
        // used to lay rows out against a width the panel was never sized for.
        let twoAppLayout = SwitcherIconRowLayout.compute(appCount: 2,
                                                         selectedWindowCount: 1,
                                                         screenVisibleFrame: screen,
                                                         showsShortcutHints: false)
        suite.expect(twoAppLayout.appRowSurfaceWidth < SwitcherIconRowLayout.hintBarWidth
               && twoAppLayout.contentWidth(simpleMode: true, windowRow: false)
                    == twoAppLayout.simplePanelSize.width - SwitcherIconRowLayout.padding * 2
               && twoAppLayout.contentWidth(simpleMode: true, windowRow: true)
                    == twoAppLayout.simpleWindowPanelSize.width - SwitcherIconRowLayout.padding * 2,
               "App Switcher rows fit the panel with fewer apps than the hint bar is wide")
        // Stepping through apps must not resize the panel. The window is
        // re-centred on every selection change, so a width that follows the
        // selected app's window count drags the whole panel, icon row
        // included, across the screen on every press (#783).
        let onePreviewPanel = SwitcherIconRowLayout.compute(appCount: 6,
                                                            selectedWindowCount: 1,
                                                            screenVisibleFrame: screen)
        let manyPreviewPanel = SwitcherIconRowLayout.compute(appCount: 6,
                                                             selectedWindowCount: 8,
                                                             screenVisibleFrame: screen)
        suite.expect(onePreviewPanel.panelSize.width == manyPreviewPanel.panelSize.width,
               "App Switcher panel keeps one width while stepping through apps")
        suite.expect(SwitcherSupport.gridColumnCount(itemCount: 10, maxColumns: 8) == 5,
               "App Switcher wrapping splits ten windows across two even rows")
        suite.expect(SwitcherSupport.gridColumnCount(itemCount: 9, maxColumns: 8) == 5,
               "App Switcher wrapping keeps nine windows on five plus four")
        suite.expect(SwitcherSupport.gridColumnCount(itemCount: 17, maxColumns: 8) == 6,
               "App Switcher wrapping balances three rows instead of leaving one leftover")
        suite.expect(SwitcherSupport.gridColumnCount(itemCount: 8, maxColumns: 8) == 8,
               "App Switcher keeps a single full row when everything fits")
        suite.expect(SwitcherSupport.gridColumnCount(itemCount: 3, maxColumns: 8) == 3,
               "App Switcher width still follows the window count on one row")
        suite.expect(SwitcherSupport.gridColumnCount(itemCount: 16, maxColumns: 8) == 8,
               "App Switcher keeps the packed width when two rows are already even")
        suite.expect(SwitcherSupport.gridSelectionIndex(after: 1,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: true) == 6,
               "App Switcher down navigation keeps the same column when it exists")
        suite.expect(SwitcherSupport.gridSelectionIndex(after: 4,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: true) == 7,
               "App Switcher down navigation lands on the last item of a shorter row")
        suite.expect(SwitcherSupport.gridSelectionIndex(after: 7,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: true) == 7,
               "App Switcher down navigation stays put on the final row")
        suite.expect(SwitcherSupport.gridSelectionIndex(after: 6,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: false) == 1,
               "App Switcher up navigation keeps its existing column behavior")
        let previousPreviewSize = UserDefaults.standard.object(forKey: DefaultsKey.previewSize)
        let previousSwitcherPreviewSize = UserDefaults.standard.object(forKey: DefaultsKey.switcherPreviewSize)
        UserDefaults.standard.set("small", forKey: DefaultsKey.previewSize)
        UserDefaults.standard.set("small", forKey: DefaultsKey.switcherPreviewSize)
        suite.expectClose(Double(PreviewSizing.scale), 0.75,
                    "Preview sizing accepts the Small option")
        suite.expectClose(Double(SwitcherIconRowLayout.scale), 0.75,
                    "App Switcher icon-row mode honors the Small option")
        suite.expectClose(Double(SwitcherIconRowLayout.appEntryIconSize), 49.5,
                    "App Switcher Small keeps a windowless app icon inside its preview")
        let selectedIconTileHeight = SwitcherIconRowLayout.selectedIconSize
            + SwitcherIconRowLayout.iconTileSpacing
            + SwitcherIconRowLayout.iconTitleHeight
            + SwitcherIconRowLayout.iconTileVerticalPadding * 2
        suite.expectClose(Double(SwitcherIconRowLayout.rowHeight - selectedIconTileHeight),
                    Double(SwitcherIconRowLayout.iconTileVerticalMargin * 2),
                    "App Switcher Small keeps the selection outline inside its icon row")
        suite.expectClose(Double(DockPreviewSupport.cardSpacing), 6,
                    "Dock Preview Small previews tighten card spacing")
        suite.expectClose(Double(DockPreviewSupport.panelPadding),
                    Double(DockPreviewSupport.cardPadding),
                    "Dock Preview Small previews tighten panel padding with the card's")
        // The grid card's chrome is two lines of text that do not change with
        // the preview size. The card does, so the thumbnail has to take every
        // point the chrome leaves, at whichever size is stored.
        let smallGridScale = PreviewSizing.switcherScale
        let smallGridCardHeight = SwitcherGridCard.height
        let smallGridCardChrome = smallGridCardHeight - SwitcherGridCard.thumbnailHeight
        suite.expect(SwitcherGridCard.fallbackIconSize < SwitcherGridCard.thumbnailHeight,
               "App Switcher Small keeps the stand-in app icon inside its grid card thumbnail")
        UserDefaults.standard.set("xlarge", forKey: DefaultsKey.switcherPreviewSize)
        suite.expect(SwitcherIconRowLayout.scale > 1 && DockPreviewSupport.cardSpacing == 6,
               "the switcher and Dock Preview each follow their own preview size")
        suite.expectClose(Double(SwitcherGridCard.height / smallGridCardHeight),
                    Double(PreviewSizing.switcherScale / smallGridScale),
                    "an App Switcher grid card's height follows the preview size")
        suite.expectClose(Double(SwitcherGridCard.height - SwitcherGridCard.thumbnailHeight),
                    Double(smallGridCardChrome),
                    "an App Switcher grid card spends the same chrome at every preview size")
        suite.expectClose(Double(smallGridCardChrome),
                    Double(SwitcherGridCard.padding * 2
                            + SwitcherGridCard.titleSpacing
                            + SwitcherGridCard.titleHeight),
                    "the grid card's chrome is exactly the parts it is made of, not a number standing in for them")
        suite.expect(SwitcherGridCard.titleHeight >= 31,
               "the grid card title band holds a 13pt line over a 10.5pt line without clipping")
        suite.expect(SwitcherGridCard.fallbackIconSize < SwitcherGridCard.thumbnailHeight,
               "App Switcher Extra Large keeps the stand-in app icon inside its grid card thumbnail")
        let xlargeIconRowLayout = SwitcherIconRowLayout.compute(appCount: 6,
                                                                 selectedWindowCount: 1,
                                                                 screenVisibleFrame: screen)
        suite.expect(SwitcherIconRowLayout.scale <= 1.15,
               "App Switcher icon-row mode caps Extra High preview scaling")
        suite.expect(xlargeIconRowLayout.panelSize.height < 540,
               "App Switcher icon-row mode stays compact with Extra High previews")
        suite.expect(xlargeIconRowLayout.panelSize.width < 950,
               "App Switcher icon-row mode avoids a giant empty backdrop with six apps")
        let xlargeSingleWindowLayout = SwitcherIconRowLayout.compute(appCount: 1,
                                                                     selectedWindowCount: 1,
                                                                     screenVisibleFrame: screen)
        suite.expectClose(Double(xlargeSingleWindowLayout.previewContentWidth),
                    Double(SwitcherIconRowLayout.previewCardWidth),
                    "App Switcher icon-row mode keeps a one-window preview card compact")
        suite.expectClose(Double(xlargeSingleWindowLayout.previewSurfaceWidth),
                    Double(SwitcherIconRowLayout.previewCardWidth + SwitcherIconRowLayout.previewPanelPadding * 2),
                    "App Switcher icon-row mode keeps padding around a one-window preview card")
        suite.expect(xlargeSingleWindowLayout.panelSize.width < 430,
               "App Switcher icon-row mode avoids a giant horizontal panel for one app with one window")
        if let previousPreviewSize {
            UserDefaults.standard.set(previousPreviewSize, forKey: DefaultsKey.previewSize)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.previewSize)
        }
        if let previousSwitcherPreviewSize {
            UserDefaults.standard.set(previousSwitcherPreviewSize, forKey: DefaultsKey.switcherPreviewSize)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.switcherPreviewSize)
        }
        let previewSizeSuite = "com.vorssaint.tests.switcher-preview-size.\(UUID().uuidString)"
        if let previewSizeDefaults = UserDefaults(suiteName: previewSizeSuite) {
            previewSizeDefaults.set("large", forKey: DefaultsKey.previewSize)
            Defaults.migrateSwitcherPreviewSize(in: previewSizeDefaults)
            let upgradedSwitcherSize = previewSizeDefaults.string(forKey: DefaultsKey.switcherPreviewSize)
            previewSizeDefaults.set("small", forKey: DefaultsKey.switcherPreviewSize)
            Defaults.migrateSwitcherPreviewSize(in: previewSizeDefaults)
            suite.expect(upgradedSwitcherSize == "large"
                    && previewSizeDefaults.string(forKey: DefaultsKey.switcherPreviewSize) == "small",
                   "an upgrade keeps the switcher at the preview size it shared with Dock Preview, once")
            previewSizeDefaults.removePersistentDomain(forName: previewSizeSuite)
        }
        let defaultSwitcherHints = SwitcherSupport.shortcutHints(for: .switcherDefault,
                                                                 windowShortcut: .switcherWindowDefault)
        // Grave and J print the cap the active keyboard layout carries, not the
        // US one: that is what #1047 changed. Pinning "⌘ `" and "⌘J" here made
        // the check fail on Turkish QWERTY and every other layout that moves
        // them. Ask the layout, and keep the rule the hint depends on: a lone
        // symbol takes a space after the modifiers, a letter does not.
        let commandKeyHint: (String, Int64, String) -> String = { modifiers, keyCode, ansiCap in
            let cap = GlobalShortcut.layoutKeyLabel(for: keyCode, usesCommand: true) ?? ansiCap
            let needsSeparator = cap.count == 1
                && cap.rangeOfCharacter(from: .alphanumerics) == nil
            return modifiers + (needsSeparator ? " " : "") + cap
        }
        suite.expect(defaultSwitcherHints.apps == "⌘Tab"
                && defaultSwitcherHints.windows == commandKeyHint("⌘", Int64(kVK_ANSI_Grave), "`"),
               "App Switcher icon-row hints describe default app and window shortcuts")
        let customSwitcherHints = SwitcherSupport.shortcutHints(
            for: GlobalShortcut(keyCode: Int64(kVK_Tab), modifiers: [.option]),
            windowShortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_J), modifiers: [.command])
        )
        suite.expect(customSwitcherHints.apps == "⌥Tab"
                && customSwitcherHints.windows == commandKeyHint("⌘", Int64(kVK_ANSI_J), "J"),
               "App Switcher icon-row hints show custom app and window shortcuts independently")
        suite.expect(SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: true,
                                                                  wasShiftHeld: false,
                                                                  isShiftHeld: true),
               "App Switcher shift-only back navigation fires when Shift is pressed")
        suite.expect(!SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: true,
                                                                   wasShiftHeld: true,
                                                                   isShiftHeld: true),
               "App Switcher shift-only back navigation does not repeat while Shift is held")
        suite.expect(!SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: true,
                                                                   wasShiftHeld: true,
                                                                   isShiftHeld: false),
               "App Switcher shift-only back navigation does not fire on Shift release")
        suite.expect(!SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: false,
                                                                   wasShiftHeld: false,
                                                                   isShiftHeld: true),
               "App Switcher shift-only back navigation stays off when Shift belongs to the shortcut")

        func syntheticCapture(_ draw: (CGContext, CGSize) -> Void) -> CGImage? {
            let size = CGSize(width: 320, height: 200)
            guard let context = CGContext(data: nil,
                                          width: Int(size.width),
                                          height: Int(size.height),
                                          bitsPerComponent: 8,
                                          bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            draw(context, size)
            return context.makeImage()
        }
        let opaqueCapture = syntheticCapture { context, size in
            context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }
        let roundedCapture = syntheticCapture { context, size in
            let path = CGPath(roundedRect: CGRect(origin: .zero, size: size),
                              cornerWidth: 12, cornerHeight: 12, transform: nil)
            context.addPath(path)
            context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            context.fillPath()
        }
        let shearedCapture = syntheticCapture { context, size in
            context.translateBy(x: size.width * 0.35, y: size.height * 0.3)
            context.concatenate(CGAffineTransform(a: 0.35, b: 0.12, c: -0.18, d: 0.35, tx: 0, ty: 0))
            context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }
        // A sheared capture whose bounding box hugs the artwork: only the two
        // corners outside the parallelogram stay transparent.
        let tightShearCapture = syntheticCapture { context, size in
            context.move(to: CGPoint(x: size.width * 0.25, y: 0))
            context.addLine(to: CGPoint(x: size.width, y: 0))
            context.addLine(to: CGPoint(x: size.width * 0.75, y: size.height))
            context.addLine(to: CGPoint(x: 0, y: size.height))
            context.closePath()
            context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            context.fillPath()
        }
        if let opaqueCapture, let grid = SwitcherSupport.alphaGrid(of: opaqueCapture) {
            suite.expect(!SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher keeps captures of fully opaque windows")
        } else {
            suite.expect(false, "switcher alpha grid renders an opaque synthetic capture")
        }
        if let roundedCapture, let grid = SwitcherSupport.alphaGrid(of: roundedCapture) {
            suite.expect(!SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher keeps captures of windows with rounded corners")
        } else {
            suite.expect(false, "switcher alpha grid renders a rounded synthetic capture")
        }
        if let shearedCapture, let grid = SwitcherSupport.alphaGrid(of: shearedCapture) {
            suite.expect(SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher rejects the small sheared snapshot Stage Manager renders for parked windows")
        } else {
            suite.expect(false, "switcher alpha grid renders a sheared synthetic capture")
        }
        if let tightShearCapture, let grid = SwitcherSupport.alphaGrid(of: tightShearCapture) {
            suite.expect(SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher rejects sheared captures even when the bounding box hugs the artwork")
        } else {
            suite.expect(false, "switcher alpha grid renders a tight sheared synthetic capture")
        }
        suite.expect(!SwitcherSupport.captureLooksTransformed(alphaGrid: [], gridSize: 8),
               "switcher capture classifier tolerates a malformed alpha grid")

        // Pixel counts measured on a 620 by 452 point window: whole on screen,
        // hanging over the bottom edge, and hanging past the side edge.
        let probeWindow = CGSize(width: 620, height: 452)
        suite.expect(SwitcherSupport.captureCoversWindow(imageWidth: 1240, imageHeight: 904,
                                                   windowSize: probeWindow),
               "switcher keeps a capture that covers the whole window")
        suite.expect(!SwitcherSupport.captureCoversWindow(imageWidth: 1240, imageHeight: 144,
                                                    windowSize: probeWindow),
               "switcher rejects the band captured for a window hanging over the bottom edge")
        suite.expect(!SwitcherSupport.captureCoversWindow(imageWidth: 120, imageHeight: 904,
                                                    windowSize: probeWindow),
               "switcher rejects the band captured for a window hanging past the side edge")
        suite.expect(SwitcherSupport.captureCoversWindow(imageWidth: 620, imageHeight: 452,
                                                   windowSize: probeWindow),
               "switcher coverage check ignores the display scale, so a plain screen passes")
        suite.expect(SwitcherSupport.captureCoversWindow(imageWidth: 2200, imageHeight: 424,
                                                   windowSize: CGSize(width: 1100, height: 212)),
               "switcher keeps the capture of a window that really is that wide")
        suite.expect(SwitcherSupport.captureCoversWindow(imageWidth: 1240, imageHeight: 144,
                                                   windowSize: .zero),
               "switcher coverage check passes when the window size says nothing")
        suite.expect(SwitcherSupport.captureCoversWindow(imageWidth: 0, imageHeight: 904,
                                                   windowSize: probeWindow),
               "switcher coverage check passes when a capture reports no pixels")

        suite.expect(SwitcherSupport.staleCacheVictims(ids: [1, 2, 3], active: [], lastTouched: [:], limit: 3).isEmpty,
               "switcher preview cache keeps everything under the limit")
        suite.expect(SwitcherSupport.staleCacheVictims(ids: [1, 2, 3, 4],
                                                 active: [1],
                                                 lastTouched: [2: 10, 3: 5, 4: 20],
                                                 limit: 3) == [3],
               "switcher preview cache evicts the least recently used entry beyond the limit")
        suite.expect(SwitcherSupport.staleCacheVictims(ids: [1, 2, 3, 4],
                                                 active: [3],
                                                 lastTouched: [1: 1, 2: 2, 4: 4],
                                                 limit: 2) == [1, 2],
               "switcher preview cache never evicts entries being refreshed right now")
        suite.expect(SwitcherSupport.cacheByteBudgetVictims(sizes: [1: 30, 2: 30],
                                                      active: [],
                                                      lastTouched: [1: 1, 2: 2],
                                                      budget: 100).isEmpty,
               "preview byte budget keeps everything while under budget")
        suite.expect(SwitcherSupport.cacheByteBudgetVictims(sizes: [1: 60, 2: 60, 3: 60],
                                                      active: [],
                                                      lastTouched: [1: 1, 2: 2, 3: 3],
                                                      budget: 100) == [1, 2],
               "preview byte budget evicts least recently used entries until the bytes fit")
        suite.expect(SwitcherSupport.cacheByteBudgetVictims(sizes: [1: 60, 2: 60, 3: 60],
                                                      active: [1],
                                                      lastTouched: [1: 1, 2: 2, 3: 3],
                                                      budget: 100) == [2, 3],
               "preview byte budget never evicts entries being refreshed right now")

        // Sheared alpha mask (rows shift right going down): corner detection
        // must find the parallelogram's extremes so rectification can undo it.
        let quadWidth = 120, quadHeight = 100
        var shearAlpha = [UInt8](repeating: 0, count: quadWidth * quadHeight)
        for y in 0..<quadHeight {
            let shift = y * 20 / quadHeight
            for x in shift..<(80 + shift) {
                shearAlpha[y * quadWidth + x] = 255
            }
        }
        if let corners = SwitcherSupport.opaqueQuadCorners(alpha: shearAlpha,
                                                           width: quadWidth,
                                                           height: quadHeight) {
            suite.expect(corners.topLeft == CGPoint(x: 0, y: 0)
                   && corners.topRight == CGPoint(x: 79, y: 0)
                   && corners.bottomRight == CGPoint(x: 98, y: 99)
                   && corners.bottomLeft == CGPoint(x: 19, y: 99),
                   "switcher quad corners land on the sheared mask extremes")
        } else {
            suite.expect(false, "switcher quad corners resolve for a sheared mask")
        }
        suite.expect(SwitcherSupport.opaqueQuadCorners(alpha: [UInt8](repeating: 0, count: quadWidth * quadHeight),
                                                 width: quadWidth,
                                                 height: quadHeight) == nil,
               "switcher quad corners reject an empty capture")

        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false) == .minimize,
               "dock click minimizes the frontmost app with visible windows")
        suite.expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false) == .passThrough,
               "dock click lets the Dock activate apps that are not frontmost")
        // The tap swallows a restoring click so the Dock will not open a new
        // window, which leaves raising the app to this service. Since macOS 14
        // that only lands if the request is cooperative, so pin the sequence
        // rather than the bare call it replaced. Asserted positively: the call
        // it must not use is named in the doc comment right above it.
        let dockClickSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/DockClick/DockClickService.swift",
            encoding: .utf8)) ?? ""
        suite.expect(dockClickSource.contains("ActivationHandoff.yield(to: app)"),
               "a Dock click restore yields this app's activation first")
        suite.expect(dockClickSource.contains("app.activate(from: NSRunningApplication.current, options: [])"),
               "a Dock click restore asks cooperatively before falling back")
        // A yield only hands over activation this app holds, and it usually
        // holds none when a switch commits, so the helper self-activates first
        // and every yield goes through it. A bare yield added on a new path
        // would bring the refused-handoff bug back on that path alone.
        let activationHandoffSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/ActivationHandoff.swift",
            encoding: .utf8)) ?? ""
        let selfActivation = activationHandoffSource.range(of: "NSApp.activate(ignoringOtherApps: true)")
        let yieldOnward = activationHandoffSource.range(of: "NSApp.yieldActivation(to: app)")
        suite.expect(selfActivation != nil && yieldOnward != nil
                && selfActivation!.lowerBound < yieldOnward!.lowerBound,
               "the activation handoff self-activates before it yields onward")
        let handoffStamp = activationHandoffSource.range(of: "lastSelfActivation = CFAbsoluteTimeGetCurrent()")
        suite.expect(handoffStamp != nil && selfActivation != nil
                && handoffStamp!.lowerBound < selfActivation!.lowerBound,
               "the activation handoff stamps the self-activation before asking for it")
        // Only the activation the handoff caused stays out of the history; the
        // Dock icon, Settings and Vorssaint's own windows are real uses.
        let useTrackerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Switcher/WindowUseTracker.swift",
            encoding: .utf8)) ?? ""
        suite.expect(useTrackerSource.contains(
                   "pid == ProcessInfo.processInfo.processIdentifier && ActivationHandoff.isHandingOff"),
               "only an activation the handoff caused is left out of the use history")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       ownsMinimize: true) == .restore,
               "dock click restores when every window is minimized")
        suite.expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       ownsMinimize: true) == .restore,
               "dock click restores minimized windows of background apps too")
        suite.expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       ownsMinimize: false) == .passThrough,
               "dock click leaves windows minimized by other means to the Dock")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       ownsMinimize: false) == .passThrough,
               "the frontmost app's own minimize is the Dock's to undo as well")
        suite.expect(DockClickSupport.capturedMinimizeStillHolds(captured: [7, 8], stillMinimized: [8, 9]),
               "a capture holds while one of the windows it named is still down")
        suite.expect(!DockClickSupport.capturedMinimizeStillHolds(captured: [7, 8], stillMinimized: [9]),
               "a capture whose windows all came back another way is stale")
        suite.expect(!DockClickSupport.capturedMinimizeStillHolds(captured: [], stillMinimized: [9]),
               "a capture that named nothing claims nothing")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false) == .passThrough,
               "dock click passes through for windowless apps")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: true,
                                       hasModifiers: false) == .passThrough,
               "dock click stays hands-off while the app has a fullscreen window")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: true) == .passThrough,
               "dock click keeps the Dock's native modifier shortcuts")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: true,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 3) == .cycleWindows,
               "dock click cycles instead of minimizing when both are on and there are windows to cycle")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: true,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 1) == .minimize,
               "dock click still minimizes a single-window app with cycling on")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 1) == .passThrough,
               "cycling alone never minimizes a single-window app")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .hide,
               "dock click hides the frontmost app when hiding is enabled")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .hide,
               "hiding also works for a frontmost app with no windows")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .hide,
               "hiding is app-level even when every window is minimized")
        suite.expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .passThrough,
               "hiding lets the Dock activate a background app")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: true,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .hide,
               "hiding follows the app-level command even with a fullscreen window")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: true,
                                       minimizeEnabled: false,
                                       hideEnabled: true) == .passThrough,
               "hiding preserves every native modifier click")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: true,
                                       hideEnabled: true) == .hide,
               "hiding wins safely if imported preferences enable both actions")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true,
                                       cycleWindowsEnabled: false,
                                       cycleCandidateCount: 3) == .hide,
               "hiding treats a multi-window app as one app when cycling is off")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       hideEnabled: true,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 3) == .cycleWindows,
               "window cycling stays ahead of hiding when several windows are available")
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: false,
                                       hasMinimizedWindows: true,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 0) == .passThrough,
               "cycling alone never restores minimized windows")
        suite.expect(DockClickSupport.action(appIsFrontmost: false,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: false,
                                       hasModifiers: false,
                                       minimizeEnabled: false,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 3) == .passThrough,
               "cycling lets the Dock activate apps that are not frontmost")
        // The two assertions above and below are what lets the service skip
        // counting candidates unless the app is frontmost and has no
        // fullscreen window: on those paths the ladder ignores the count, so
        // paying for it inside the event tap buys nothing.
        suite.expect(DockClickSupport.action(appIsFrontmost: true,
                                       hasUnminimizedWindows: true,
                                       hasMinimizedWindows: false,
                                       hasFullscreenWindows: true,
                                       hasModifiers: false,
                                       minimizeEnabled: true,
                                       cycleWindowsEnabled: true,
                                       cycleCandidateCount: 3) == .passThrough,
               "cycling stays out of an app with a fullscreen window however many candidates there are")
        // Issue #1204's report: one app, four unminimized windows spread over
        // three desktops, two of them on the desktop being looked at. The AX
        // window list holds all four; the window server's on-screen list holds
        // only the two.
        let windowsAcrossDesktops: [CGWindowID?] = [1, 2, 3, 4]
        suite.expect(DockClickSupport.cycleCandidateIndices(windowIDs: windowsAcrossDesktops,
                                                      onScreenFrontToBack: [1, 2]) == [0, 1],
               "cycling only considers the windows on the desktop being looked at")
        suite.expect(DockClickSupport.cycleCandidateIndices(windowIDs: windowsAcrossDesktops,
                                                      onScreenFrontToBack: [1, 2]).last == 1,
               "the click raises the rearmost window of the current desktop")
        suite.expect(DockClickSupport.cycleCandidateIndices(windowIDs: windowsAcrossDesktops,
                                                      onScreenFrontToBack: [2, 1]).last == 0,
               "the next click raises the other one back, rotating in place")
        suite.expect(DockClickSupport.cycleCandidateIndices(windowIDs: windowsAcrossDesktops,
                                                      onScreenFrontToBack: [3]).count == 1,
               "a desktop holding one window offers nothing to cycle, so the click cannot jump to another desktop")
        suite.expect(DockClickSupport.cycleCandidateIndices(windowIDs: [1, 2, 3],
                                                      onScreenFrontToBack: [3, 1, 2]).last == 1,
               "three windows on one desktop rotate through all of them, not just the front two")
        suite.expect(DockClickSupport.cycleCandidateIndices(windowIDs: [nil, nil],
                                                      onScreenFrontToBack: [1, 2]).isEmpty,
               "windows whose ids cannot be resolved are never guessed at")
        suite.expect(DockClickSupport.repeatDecision(lastAction: .cycleWindows, elapsed: 0.5) == .deriveFromState,
               "a repeated click after a cycle keeps cycling from live state")
        suite.expect(DockClickSupport.repeatDecision(lastAction: .hide, elapsed: 0.5) == .deriveFromState,
               "a click after hiding lets the Dock bring the app back")
        suite.expect(DockClickSupport.repeatDecision(lastAction: .hide, elapsed: 0.1) == .swallow,
               "an accidental double-click never hides and immediately reopens the app")
        suite.expect(DockClickSupport.isOwnBundleIdentifier("com.vorssaint.utils")
                && DockClickSupport.isOwnBundleIdentifier("com.vorssaint.utils.dev")
                && !DockClickSupport.isOwnBundleIdentifier("com.example.editor")
                && !DockClickSupport.isOwnBundleIdentifier(nil),
               "Dock clicks never target either build of this app")

        suite.expect(DockClickSupport.repeatDecision(lastAction: nil, elapsed: nil) == .deriveFromState,
               "dock click derives the first click from window state")
        suite.expect(DockClickSupport.repeatDecision(lastAction: .minimize, elapsed: 0.1) == .swallow,
               "dock click swallows accidental double-clicks")
        suite.expect(DockClickSupport.repeatDecision(lastAction: .minimize, elapsed: 0.5) == .toggle(.restore),
               "dock click right after a minimize toggles straight back to restore")
        suite.expect(DockClickSupport.repeatDecision(lastAction: .restore, elapsed: 0.5) == .toggle(.minimize),
               "dock click right after a restore toggles back to minimize")
        suite.expect(DockClickSupport.repeatDecision(lastAction: .minimize, elapsed: 2.0) == .deriveFromState,
               "dock click trusts settled window state once the intent window passes")

        suite.expect(DockClickSupport.isVerifiedMinimizeAll(commandCharacter: "M",
                                                       modifiers: 2,
                                                       identifier: "miniaturizeAll:"),
               "dock click recognizes the standard Minimize All menu action")
        suite.expect(!DockClickSupport.isVerifiedMinimizeAll(commandCharacter: "M",
                                                        modifiers: 2,
                                                        identifier: "toggleCompactWindow:"),
               "dock click rejects an unrelated action that shares the Minimize All shortcut")
        suite.expect(!DockClickSupport.isVerifiedMinimizeAll(commandCharacter: "M",
                                                        modifiers: 2,
                                                        identifier: nil),
               "dock click never guesses when an Option-Command-M action has no identifier")

        // Bottom Dock reserving ~70 pt: only the reserved strip counts, so a
        // click on a preview panel floating just above the Dock passes through.
        let dockScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let bottomDockVisible = CGRect(x: 0, y: 24, width: 1512, height: 888)
        suite.expect(DockClickSupport.dockStripContains(CGPoint(x: 700, y: 950),
                                                  screenFrame: dockScreen,
                                                  visibleFrame: bottomDockVisible),
               "dock strip accepts clicks inside the reserved bottom strip")
        suite.expect(!DockClickSupport.dockStripContains(CGPoint(x: 700, y: 880),
                                                   screenFrame: dockScreen,
                                                   visibleFrame: bottomDockVisible),
               "dock strip rejects clicks hovering above the Dock, like a preview panel")
        suite.expect(!DockClickSupport.dockStripContains(CGPoint(x: 700, y: 20),
                                                   screenFrame: dockScreen,
                                                   visibleFrame: bottomDockVisible),
               "dock strip ignores the top edge where the Dock never lives")
        let leftDockVisible = CGRect(x: 70, y: 24, width: 1442, height: 958)
        suite.expect(DockClickSupport.dockStripContains(CGPoint(x: 40, y: 500),
                                                  screenFrame: dockScreen,
                                                  visibleFrame: leftDockVisible),
               "dock strip accepts clicks inside a left Dock's reserved strip")
        suite.expect(!DockClickSupport.dockStripContains(CGPoint(x: 700, y: 950),
                                                   screenFrame: dockScreen,
                                                   visibleFrame: leftDockVisible),
               "dock strip rejects bottom clicks when the Dock lives on the left")
        suite.expect(DockClickSupport.dockStripContains(CGPoint(x: 700, y: 950),
                                                  screenFrame: dockScreen,
                                                  visibleFrame: CGRect(x: 0, y: 24, width: 1512, height: 958)),
               "dock strip falls back to an edge band when auto-hide reserves nothing")
        let dockStripWindow = MouseAppExceptionSupport.Window(frame: dockScreen, layer: 20,
                                                              processID: 1267)
        let coveringWindow = MouseAppExceptionSupport.Window(frame: dockScreen, layer: 24,
                                                             processID: 4242)
        let dockPoint = CGPoint(x: 90, y: 930)
        var dockAccessibilityLookups = 0
        func unexpectedDockAccessibilityLookup() -> pid_t? {
            dockAccessibilityLookups += 1
            return 1267
        }
        suite.expect(DockClickSupport.dockOwnsPoint(dockPoint,
                                              windows: [dockStripWindow],
                                              dockProcessID: 1267,
                                              dockLayer: 20,
                                              ownProcessID: 501,
                                              accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "Dock click accepts a visible unobstructed Dock strip")
        suite.expect(!DockClickSupport.dockOwnsPoint(dockPoint,
                                               windows: [coveringWindow, dockStripWindow],
                                               dockProcessID: 1267,
                                               dockLayer: 20,
                                               ownProcessID: 501,
                                               accessibilityHitProcessID: { 4242 }),
               "Dock click leaves a point covered by fullscreen content untouched")
        suite.expect(DockClickSupport.dockOwnsPoint(
            dockPoint,
            windows: [MouseAppExceptionSupport.Window(frame: dockScreen, layer: 24,
                                                       processID: 501), dockStripWindow],
            dockProcessID: 1267,
            dockLayer: 20,
            ownProcessID: 501,
            accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "this app's own panel never hides the Dock below it from the ownership check")
        // A screen recording overlay reports a full-display, opaque layer-24
        // window even while Accessibility reaches the Dock underneath it.
        // Its window-server geometry is identical to real fullscreen content.
        suite.expect(DockClickSupport.dockOwnsPoint(
            dockPoint, windows: [coveringWindow, dockStripWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: { 1267 }),
               "Dock actions and previews work through an input-transparent recording overlay")
        suite.expect(!DockClickSupport.dockOwnsPoint(
            dockPoint, windows: [coveringWindow, dockStripWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: { nil }),
               "an unavailable Accessibility answer cannot allow actions through a covering window")
        suite.expect(!DockClickSupport.dockOwnsPoint(
            dockPoint, windows: [coveringWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "a hidden Dock never accepts a click through the parked icon layout")
        suite.expect(!DockClickSupport.dockOwnsPoint(
            CGPoint(x: dockScreen.maxX + 100, y: dockPoint.y),
            windows: [coveringWindow, dockStripWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "the Dock on another display does not accept a pointer outside its visible bounds")
        suite.expect(DockClickSupport.dockOwnsPoint(
            dockPoint, windows: [dockStripWindow, coveringWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "a window behind the Dock cannot block it")
        suite.expect(DockClickSupport.dockOwnsPoint(
            dockPoint,
            windows: [MouseAppExceptionSupport.Window(frame: dockScreen, layer: 24,
                                                       alpha: 0, processID: 4242), dockStripWindow],
            dockProcessID: 1267, dockLayer: 20, ownProcessID: 501,
            accessibilityHitProcessID: unexpectedDockAccessibilityLookup),
               "an invisible window does not trigger an Accessibility lookup")
        suite.expect(dockAccessibilityLookups == 0,
               "Dock ownership only asks Accessibility for an overlapping window above a visible Dock")
        suite.expect(DockPreviewSupport.mouseMoveSampleInterval > 0
               && DockPreviewSupport.mouseMoveSampleInterval <= 1.0 / 60
               && DockPreviewSupport.mouseMoveSampleInterval < DockPreviewSupport.switchDelay,
               "Dock Preview samples high-rate mouse movement faster than hover intent")
        let dockPreviewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/DockPreview/DockPreviewService.swift",
            encoding: .utf8)) ?? ""
        suite.expect(dockPreviewSource.contains("DockClickSupport.dockOwnsPoint("),
               "Dock Preview does not open through fullscreen content covering the Dock")

        // Both window server scans read the same list and must keep
        // disagreeing where they disagree today. A point exactly on a
        // window's far edge is inside for the click lookup and outside for
        // the traffic lights, and a window whose app the traffic lights are
        // told to leave alone ends that scan instead of handing the click to
        // whatever sits behind it.
        func windowServerEntry(_ frame: CGRect, pid: Int32, number: UInt32) -> [String: Any] {
            [kCGWindowBounds as String: ["X": NSNumber(value: Double(frame.minX)),
                                         "Y": NSNumber(value: Double(frame.minY)),
                                         "Width": NSNumber(value: Double(frame.width)),
                                         "Height": NSNumber(value: Double(frame.height))] as [String: Any],
             kCGWindowLayer as String: NSNumber(value: 0),
             kCGWindowAlpha as String: NSNumber(value: 1.0),
             kCGWindowOwnerPID as String: NSNumber(value: pid),
             kCGWindowNumber as String: NSNumber(value: number)]
        }
        let scannedWindow = CGRect(x: 0, y: 0, width: 200, height: 200)
        let scannedNeighbour = CGRect(x: 200, y: 96, width: 200, height: 200)
        let scannedEdgePoint = CGPoint(x: 200, y: 100)
        let scannedNeighbours = [windowServerEntry(scannedWindow, pid: 1001, number: 11),
                                 windowServerEntry(scannedNeighbour, pid: 1002, number: 12)]
        suite.expect(WindowServerSupport.bounds(from: scannedNeighbours[0]) == scannedWindow
                && WindowServerSupport.bounds(from: [:]) == nil,
               "a window's rectangle comes from its bounds entry and from nothing else")
        suite.expect(WindowServerSupport.windowCandidate(in: scannedNeighbours, at: scannedEdgePoint,
                                                   ownProcessID: 501,
                                                   pidIsEligible: { _ in true })?.pid == 1001,
               "a click on a window's far edge still belongs to that window")
        suite.expect(WindowServerSupport.trafficLightCandidate(in: scannedNeighbours, at: scannedEdgePoint,
                                                         button: .close,
                                                         ownProcessID: 501,
                                                         pidIsEligible: { _ in true })?.pid == 1002,
               "a traffic light on a window's far edge belongs to the window that owns the pixel")
        let scannedStack = [windowServerEntry(scannedWindow, pid: 1001, number: 11),
                            windowServerEntry(scannedWindow, pid: 1002, number: 12)]
        let scannedCloseButtonPoint = CGPoint(x: 20, y: 20)
        suite.expect(WindowServerSupport.trafficLightCandidate(in: scannedStack, at: scannedCloseButtonPoint,
                                                         button: .close,
                                                         ownProcessID: 501,
                                                         pidIsEligible: { $0 != 1001 }) == nil,
               "a traffic light click stops at the window in front, never reaching one behind it")
        suite.expect(WindowServerSupport.windowCandidate(in: scannedStack, at: scannedCloseButtonPoint,
                                                   ownProcessID: 501,
                                                   pidIsEligible: { $0 != 1001 })?.pid == 1002,
               "the click lookup carries on behind a window it was told to leave alone")

        // Unlike the click scan, hover must stop at our interactive surfaces
        // before making any Accessibility call, even for a tiny raised panel.
        let focusHitPoint = CGPoint(x: -200, y: -100)
        let focusHitFrame = CGRect(x: -300, y: -200, width: 400, height: 400)
        let foreignFocusWindow = windowServerEntry(focusHitFrame, pid: 1001, number: 11)
        let ownFocusWindow = windowServerEntry(focusHitFrame, pid: 501, number: 12)
        var focusQueryPIDs: [pid_t] = []
        func queryFocusWindow(_ windows: [[String: Any]],
                              pointerWindowID: CGWindowID = 11,
                              clickThroughWindowIDs: Set<CGWindowID> = [],
                              querySucceeds: Bool = true) -> pid_t? {
            focusQueryPIDs.removeAll()
            return FocusFollowsMouseSupport.queryWindow(
                in: windows, at: focusHitPoint, pointerWindowID: pointerWindowID,
                ownProcessID: 501,
                clickThroughWindowIDs: clickThroughWindowIDs
            ) { pid in
                focusQueryPIDs.append(pid)
                return querySucceeds ? pid : nil
            }
        }
        for layer in [0, 3, 25, 1_000] {
            var panel = windowServerEntry(
                CGRect(x: -210, y: -110, width: 20, height: 20), pid: 501, number: 12)
            panel[kCGWindowLayer as String] = NSNumber(value: layer)
            suite.expect(queryFocusWindow([panel, foreignFocusWindow]) == nil && focusQueryPIDs.isEmpty,
                   "hover issues no Accessibility query through an own panel at layer \(layer)")
        }
        suite.expect(queryFocusWindow([ownFocusWindow, foreignFocusWindow]) == nil && focusQueryPIDs.isEmpty,
               "hover leaves both its own ordinary window and the app behind it untouched")
        suite.expect(queryFocusWindow([foreignFocusWindow, ownFocusWindow]) == 1001 && focusQueryPIDs == [1001],
               "a foreign window covering our panel receives exactly one scoped query on an offset display")
        suite.expect(queryFocusWindow([]) == nil && focusQueryPIDs.isEmpty,
               "an empty or unavailable window list never falls back to a global Accessibility query")
        var unknownOwner = foreignFocusWindow
        unknownOwner.removeValue(forKey: kCGWindowOwnerPID as String)
        suite.expect(queryFocusWindow([unknownOwner, foreignFocusWindow]) == nil && focusQueryPIDs.isEmpty,
               "an unknown surface owner blocks hover without querying an app behind it")
        for invalidPID: Int32 in [0, -1] {
            let invalidWindow = windowServerEntry(focusHitFrame, pid: invalidPID, number: 13)
            suite.expect(queryFocusWindow([invalidWindow, foreignFocusWindow]) == nil && focusQueryPIDs.isEmpty,
                   "hover never queries an invalid process identifier")
        }
        var transparentPanel = ownFocusWindow
        transparentPanel[kCGWindowAlpha as String] = NSNumber(value: 0.0)
        suite.expect(queryFocusWindow([transparentPanel, foreignFocusWindow]) == 1001 && focusQueryPIDs == [1001],
               "a fully invisible own surface does not block the app under the pointer")
        transparentPanel[kCGWindowAlpha as String] = NSNumber(value: 0.1)
        suite.expect(queryFocusWindow([transparentPanel, foreignFocusWindow]) == nil && focusQueryPIDs.isEmpty,
               "a translucent own panel still blocks hover before Accessibility")
        let distantPanel = windowServerEntry(CGRect(x: 0, y: 0, width: 400, height: 400), pid: 501, number: 14)
        suite.expect(queryFocusWindow([distantPanel, foreignFocusWindow]) == 1001 && focusQueryPIDs == [1001],
               "our panel elsewhere on the displays does not disable hover")
        suite.expect(queryFocusWindow([ownFocusWindow, foreignFocusWindow], clickThroughWindowIDs: [12]) == 1001
                && focusQueryPIDs == [1001],
               "a known own click-through overlay passes hover to the foreign app without querying itself")
        suite.expect(queryFocusWindow([ownFocusWindow, foreignFocusWindow], clickThroughWindowIDs: [14]) == nil
                && focusQueryPIDs.isEmpty,
               "only the exact own window marked click-through may be skipped")
        var ownPanelWithoutID = ownFocusWindow
        ownPanelWithoutID.removeValue(forKey: kCGWindowNumber as String)
        suite.expect(queryFocusWindow([ownPanelWithoutID, foreignFocusWindow], clickThroughWindowIDs: [12]) == nil
                && focusQueryPIDs.isEmpty,
               "an unidentified own panel is never assumed to be click-through")
        let brightnessOverlay = windowServerEntry(focusHitFrame, pid: 501, number: 15)
        suite.expect(queryFocusWindow([brightnessOverlay, ownFocusWindow, foreignFocusWindow],
                                clickThroughWindowIDs: [15]) == nil && focusQueryPIDs.isEmpty,
               "a click-through overlay does not hide an interactive own panel from the guard")
        suite.expect(queryFocusWindow([brightnessOverlay, ownFocusWindow, foreignFocusWindow],
                                clickThroughWindowIDs: [12, 15]) == 1001 && focusQueryPIDs == [1001],
               "stacked own click-through overlays still allow normal hover focus")
        suite.expect(queryFocusWindow([foreignFocusWindow, ownFocusWindow], clickThroughWindowIDs: [11]) == 1001
                && focusQueryPIDs == [1001],
               "the click-through allowlist never skips another app's surface")
        let secondForeignWindow = windowServerEntry(focusHitFrame, pid: 1002, number: 16)
        var recordingOverlay = windowServerEntry(focusHitFrame, pid: 1003, number: 17)
        recordingOverlay[kCGWindowLayer as String] = NSNumber(value: 24)
        suite.expect(queryFocusWindow([recordingOverlay, foreignFocusWindow]) == 1001
                && focusQueryPIDs == [1001],
               "hover follows the native mouse target through a recording overlay without querying the overlay")
        suite.expect(queryFocusWindow([recordingOverlay, foreignFocusWindow], pointerWindowID: 17) == nil
                && focusQueryPIDs.isEmpty,
               "a recording overlay that actually receives input still blocks hover")
        suite.expect(queryFocusWindow([foreignFocusWindow, secondForeignWindow], pointerWindowID: 16) == 1002
                && focusQueryPIDs == [1002],
               "an input-transparent ordinary window does not obscure the native target either")
        suite.expect(queryFocusWindow([foreignFocusWindow], pointerWindowID: 0) == nil
                && focusQueryPIDs.isEmpty,
               "an unavailable native target never falls back to visual window order")
        suite.expect(queryFocusWindow([foreignFocusWindow], pointerWindowID: 16) == nil
                && focusQueryPIDs.isEmpty,
               "a native target missing from the current window list never selects another window")
        suite.expect(queryFocusWindow([ownFocusWindow, foreignFocusWindow], pointerWindowID: 12) == nil
                && focusQueryPIDs.isEmpty,
               "a native target owned by this app is never queried through Accessibility")
        suite.expect(queryFocusWindow([ownFocusWindow, foreignFocusWindow], pointerWindowID: 12,
                                clickThroughWindowIDs: [12]) == nil && focusQueryPIDs.isEmpty,
               "a mismatched native target and own overlay list never redirects focus behind it")
        suite.expect(queryFocusWindow([foreignFocusWindow, secondForeignWindow], querySucceeds: false) == nil
                && focusQueryPIDs == [1001],
               "an unanswered scoped query never falls through to another app")
        for foreignLayer in [-2_147_483_623, 4, 20, 24, 25] {
            var furniture = foreignFocusWindow
            furniture[kCGWindowLayer as String] = NSNumber(value: foreignLayer)
            suite.expect(queryFocusWindow([furniture, secondForeignWindow]) == nil && focusQueryPIDs.isEmpty,
                   "hover stops at a surface outside the app window layers, at layer \(foreignLayer)")
        }
        var unknownDepth = foreignFocusWindow
        unknownDepth.removeValue(forKey: kCGWindowLayer as String)
        suite.expect(queryFocusWindow([unknownDepth, secondForeignWindow]) == nil && focusQueryPIDs.isEmpty,
               "a surface of unknown depth is never taken for an app window")

        suite.expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .transform,
               "middle click transforms a settled three-finger press")
        suite.expect(MiddleClickSupport.actionForClick(fingerCount: 2, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click leaves two-finger clicks alone")
        suite.expect(MiddleClickSupport.actionForClick(fingerCount: 4, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click leaves four-finger clicks alone")
        suite.expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 1.0, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click ignores stale contact frames (fingers already lifted)")
        suite.expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.01,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click rejects a click arriving with the third finger's touchdown")
        suite.expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: 0.1,
                                                 systemDragGestureEnabled: false) == .swallow,
               "middle click drops the tap-to-click bounce right after a transform")
        suite.expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: 0.5,
                                                 systemDragGestureEnabled: false) == .transform,
               "middle click accepts a deliberate second press after the guard window")
        suite.expect(MiddleClickSupport.actionForClick(fingerCount: 1, frameAge: 0.05, settledFor: 0,
                                                 sinceLastTransformEnd: 0.1,
                                                 systemDragGestureEnabled: false) == .passThrough,
               "middle click never swallows ordinary one-finger clicks")
        suite.expect(MiddleClickSupport.actionForClick(fingerCount: 3, frameAge: 0.05, settledFor: 0.2,
                                                 sinceLastTransformEnd: nil,
                                                 systemDragGestureEnabled: true) == .passThrough,
               "middle click stands down while the system three-finger drag owns the gesture")

        expectEqual(QuickToolsSupport.colorString(red: 1, green: 0, blue: 0, format: .hex), "#FF0000",
                    "color picker formats pure red as hex")
        expectEqual(QuickToolsSupport.colorString(red: 0.2, green: 0.4, blue: 0.6, format: .rgb),
                    "rgb(51, 102, 153)",
                    "color picker formats components as CSS rgb")
        expectEqual(QuickToolsSupport.colorString(red: 1, green: 0, blue: 0, format: .hsl),
                    "hsl(0, 100%, 50%)",
                    "color picker formats pure red as hsl")
        expectEqual(QuickToolsSupport.colorString(red: 0, green: 0.5, blue: 0, format: .hsl),
                    "hsl(120, 100%, 25%)",
                    "color picker formats dark green as hsl")
        expectEqual(QuickToolsSupport.colorString(red: 0.25, green: 0.5, blue: 0.75, format: .swiftui),
                    "Color(red: 0.250, green: 0.500, blue: 0.750)",
                    "color picker formats components as SwiftUI code")
        expectEqual(QuickToolsSupport.colorString(red: 1.4, green: -0.2, blue: 0.5, format: .hex), "#FF0080",
                    "color picker clamps extended-gamut components")
        suite.expect(ColorCopyFormat.sanitized("banana") == .hex,
               "color picker falls back to hex for unknown stored formats")
        expectEqual(QuickToolsSupport.colorString(red: 1, green: 0, blue: 0, format: .hex, bareHex: true),
                    "FF0000",
                    "color picker drops the leading # when the bare hex option is on")
        expectEqual(QuickToolsSupport.colorString(red: 0.2, green: 0.4, blue: 0.6, format: .rgb, bareHex: true),
                    "rgb(51, 102, 153)",
                    "bare hex option leaves the other copy formats untouched")

        // Sample known pixels, including an ICC profile, through the same
        // path used by color confirmation and the magnifier's readout/copy.
        for profile in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
            let space = CGColorSpace(name: profile)!
            let bytes: [UInt8] = [0, 0, 255, 255, 153, 102, 51, 255]
            let image = CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: 8, space: space,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                                    .union(.byteOrder32Little),
                                provider: CGDataProvider(data: Data(bytes) as CFData)!,
                                decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let sampled = QuickToolsSupport.sampledColor(in: image, x: 1, y: 0)?.usingColorSpace(.sRGB)
            let expected = NSColor(cgColor: CGColor(colorSpace: space,
                                                   components: [0.2, 0.4, 0.6, 1])!)!
                .usingColorSpace(.sRGB)!
            suite.expect(sampled != nil, "color picker reads the chosen pixel in \(profile)")
            if let sampled {
                suite.expectClose(sampled.redComponent, expected.redComponent, "sampled red respects \(profile)")
                suite.expectClose(sampled.greenComponent, expected.greenComponent, "sampled green respects \(profile)")
                suite.expectClose(sampled.blueComponent, expected.blueComponent, "sampled blue respects \(profile)")
                if profile == CGColorSpace.sRGB {
                    expectEqual(QuickToolsSupport.colorString(red: sampled.redComponent,
                                                             green: sampled.greenComponent,
                                                             blue: sampled.blueComponent,
                                                             format: .hex),
                                "#336699", "color picker preserves a known sRGB hex")
                }
            }
        }

        let ocrLines = [
            QuickToolsSupport.RecognizedLine(text: "world", x: 0.5, y: 0.8),
            QuickToolsSupport.RecognizedLine(text: "hello", x: 0.1, y: 0.81),
            QuickToolsSupport.RecognizedLine(text: "below", x: 0.1, y: 0.4),
            QuickToolsSupport.RecognizedLine(text: "   ", x: 0.2, y: 0.6),
        ]
        expectEqual(QuickToolsSupport.joinedRecognizedText(ocrLines, removingLineBreaks: false),
                    "hello\nworld\nbelow",
                    "screen OCR joins lines top to bottom, left to right, dropping blanks")
        expectEqual(QuickToolsSupport.joinedRecognizedText(ocrLines, removingLineBreaks: true),
                    "hello world below",
                    "screen OCR can join lines with spaces")
        let joinedOCRPair: (String, String, Bool) -> String = { first, second, removingLineBreaks in
            QuickToolsSupport.joinedRecognizedText([
                .init(text: first, x: 0.1, y: 0.8),
                .init(text: second, x: 0.1, y: 0.4),
            ], removingLineBreaks: removingLineBreaks)
        }
        expectEqual(joinedOCRPair("这是", "测试", true), "这是测试",
                    "screen OCR joins Chinese lines without spaces")
        expectEqual(joinedOCRPair("これは", "テストです", true), "これはテストです",
                    "screen OCR joins Japanese lines without spaces")
        expectEqual(joinedOCRPair("これは", "ﾃｽﾄです", true), "これはﾃｽﾄです",
                    "screen OCR joins halfwidth Japanese kana without spaces")
        expectEqual(joinedOCRPair("이것은", "테스트입니다", true), "이것은 테스트입니다",
                    "screen OCR keeps Korean word spaces at line seams")
        expectEqual(joinedOCRPair("ㅋㅋ", "ㅎㅎ", true), "ㅋㅋ ㅎㅎ",
                    "screen OCR keeps spaces between Hangul compatibility jamo")
        expectEqual(joinedOCRPair("version", "版本", true), "version 版本",
                    "screen OCR separates mixed Latin and CJK seams")
        expectEqual(joinedOCRPair("Hello ", " world", true), "Hello world",
                    "screen OCR normalizes spaced-script boundary whitespace")
        expectEqual(joinedOCRPair("这是 ", " 测试", true), "这是测试",
                    "screen OCR trims boundary whitespace before a tight CJK seam")
        expectEqual(joinedOCRPair("이것은 ", " 테스트", true), "이것은 테스트",
                    "screen OCR normalizes Korean boundary whitespace to one separator")
        expectEqual(joinedOCRPair("这是", "测试", false), "这是\n测试",
                    "screen OCR preserves Chinese line breaks when removal is off")
        expectEqual(joinedOCRPair("这是 ", " 测试", false), "这是 \n 测试",
                    "screen OCR preserves boundary whitespace when line removal is off")
        expectEqual(QuickToolsSupport.joinedRecognizedText([], removingLineBreaks: false), "",
                    "screen OCR joins an empty result to an empty string")

        // QR codes: several join top to bottom, left to right, blanks dropped.
        let qrCodes = [
            QuickToolsSupport.DecodedBarcode(payload: "second", x: 0.6, y: 0.8),
            QuickToolsSupport.DecodedBarcode(payload: "first", x: 0.1, y: 0.81),
            QuickToolsSupport.DecodedBarcode(payload: "bottom", x: 0.1, y: 0.3),
            QuickToolsSupport.DecodedBarcode(payload: "  ", x: 0.2, y: 0.5),
        ]
        expectEqual(QuickToolsSupport.joinedBarcodePayloads(qrCodes), "first\nsecond\nbottom",
                    "QR codes join top to bottom, left to right, dropping blanks")
        expectEqual(QuickToolsSupport.joinedBarcodePayloads([]), "",
                    "no QR codes joins to an empty string")

        // Open link is limited to http and https so a scanned code can never
        // launch another scheme.
        suite.expect(QuickToolsSupport.openableURL(from: "https://example.com/menu")?.absoluteString
                    == "https://example.com/menu",
               "an https payload is offered as an open link")
        suite.expect(QuickToolsSupport.openableURL(from: " http://example.com ")?.host == "example.com",
               "surrounding whitespace does not stop a plain web link")
        suite.expect(QuickToolsSupport.openableURL(from: "WIFI:S:Net;T:WPA;P:secret;;") == nil,
               "a Wi-Fi payload is copied, never opened")
        suite.expect(QuickToolsSupport.openableURL(from: "mailto:a@b.com") == nil,
               "a mailto payload is not treated as an open link")
        suite.expect(QuickToolsSupport.openableURL(from: "just some text") == nil,
               "plain text is never an open link")
        suite.expect(QuickToolsSupport.openableURL(from: "example.com") == nil,
               "a bare host with no scheme is not opened")

        // Paste plain delegates only to the universal ⌥⇧⌘V equivalent
        // (shift = 1, option = 2 in the AX modifier mask); anything else in
        // an app's menus is some other edit command and must not be pressed.
        suite.expect(QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                        modifierMask: 3,
                                                        isEnabled: true),
               "V with shift+option is an app's own matching-style paste")
        suite.expect(QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "v",
                                                        modifierMask: 3,
                                                        isEnabled: true),
               "the command character match ignores case")
        suite.expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 0,
                                                         isEnabled: true),
               "plain ⌘V is the regular paste, never pressed as match style")
        suite.expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 1,
                                                         isEnabled: true),
               "⇧⌘V alone is a different command in several apps")
        suite.expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 3 | 4,
                                                         isEnabled: true),
               "a control variant is not the matching-style paste")
        suite.expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 3 | 8,
                                                         isEnabled: true),
               "an equivalent without the command key does not qualify")
        suite.expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "C",
                                                         modifierMask: 3,
                                                         isEnabled: true),
               "other command characters never match")
        suite.expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: nil,
                                                         modifierMask: 3,
                                                         isEnabled: true),
               "an item with no key equivalent never matches")
        suite.expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: nil,
                                                         isEnabled: true),
               "an unreadable modifier mask never matches")
        suite.expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 3,
                                                         isEnabled: false),
               "a disabled item is left alone so the fallback paste still runs")

        // Launcher grid: 8 items in 3 columns (rows of 3, 3, 2).
        suite.expect(QuickToolsSupport.gridIndex(after: 0, count: 8, columns: 3, direction: .right) == 1,
               "launcher grid moves right within a row")
        suite.expect(QuickToolsSupport.gridIndex(after: 2, count: 8, columns: 3, direction: .right) == 2,
               "launcher grid does not wrap at the row's right edge")
        suite.expect(QuickToolsSupport.gridIndex(after: 3, count: 8, columns: 3, direction: .left) == 3,
               "launcher grid does not wrap at the row's left edge")
        suite.expect(QuickToolsSupport.gridIndex(after: 1, count: 8, columns: 3, direction: .down) == 4,
               "launcher grid moves down one row")
        suite.expect(QuickToolsSupport.gridIndex(after: 7, count: 8, columns: 3, direction: .down) == 7,
               "launcher grid stays put when there is no row below")
        suite.expect(QuickToolsSupport.gridIndex(after: 4, count: 8, columns: 3, direction: .up) == 1,
               "launcher grid moves up one row")
        suite.expect(QuickToolsSupport.gridIndex(after: 6, count: 8, columns: 3, direction: .right) == 7,
               "launcher grid moves right in the last partial row")
        suite.expect(QuickToolsSupport.gridIndex(after: 99, count: 8, columns: 3, direction: .left) == 6,
               "launcher grid clamps an out-of-range index")
        suite.expect(QuickToolsSupport.gridIndex(after: 0, count: 0, columns: 3, direction: .down) == 0,
               "launcher grid survives an empty item list")

        suite.expect(QuickToolsSupport.hiddenIDs(from: "a,b,,c") == Set(["a", "b", "c"]),
               "launcher hidden set parses and drops empties")
        expectEqual(QuickToolsSupport.serializeHiddenIDs(Set(["b", "a"])), "a,b",
                    "launcher hidden set serializes deterministically")
        suite.expect(QuickToolsSupport.hiddenIDs(from: QuickToolsSupport.serializeHiddenIDs(Set(["x", "y"])))
                   == Set(["x", "y"]),
               "launcher hidden set round-trips")
        let repeatedProcessValues = SwitcherSupport.firstValuesByPID([(pid_t(1678), "first"),
                                                                      (pid_t(1678), "duplicate"),
                                                                      (pid_t(2048), "other")])
        suite.expect(repeatedProcessValues == [1678: "first", 2048: "other"],
               "window enumeration keeps the first value when the system repeats a process")
        let groupedSwitcherItems = [
            SwitcherItem.window(id: 1, title: "One", appName: "Alpha", pid: 101,
                                isOnScreen: true, frame: .zero),
            SwitcherItem.window(id: 2, title: "Two", appName: "Alpha", pid: 101,
                                isOnScreen: true, frame: .zero),
            SwitcherItem.window(id: 3, title: "Main", appName: "Beta", pid: 202,
                                isOnScreen: true, frame: .zero),
        ]
        let appGroups = SwitcherSupport.appGroups(items: groupedSwitcherItems)
        suite.expect(appGroups.count == 2
               && appGroups[0].representativeIndex == 0
               && appGroups[0].windowCount == 2
               && appGroups[1].representativeIndex == 2,
               "App Switcher icon-row mode keeps one row entry per app")
        let windowlessApps = [SwitcherItem.appOnly(appName: "Gamma", pid: 303),
                              SwitcherItem.appOnly(appName: "Delta", pid: 404)]
        let dividerViewSource = switcherCardSource
            .replacingOccurrences(of: #"(?s)/\*.*?\*/|//[^\n]*"#, with: "", options: .regularExpression)
            .filter { !$0.isWhitespace }
        suite.expect(dividerViewSource.contains("SwitcherSupport.windowlessAppDividerPIDs("),
               "the switcher view uses the windowless-app boundary decision")
        let dividerPresentation = sourceBody(of: dividerViewSource, from: ".separatorColor", to: ".onHover")
        suite.expect(dividerPresentation.contains(".allowsHitTesting(false)")
               && dividerPresentation.contains(".accessibilityHidden(true)"),
               "the switcher renders a system-colored windowless-app divider without pointer or accessibility targets")
        suite.expect(SwitcherSupport.windowlessAppDividerPIDs(items: []) == [],
               "an empty app row has no windowless divider")
        suite.expect(SwitcherSupport.windowlessAppDividerPIDs(items: groupedSwitcherItems) == []
               && SwitcherSupport.windowlessAppDividerPIDs(items: windowlessApps) == [],
               "a row with only one kind of app has no divider")
        suite.expect(SwitcherSupport.windowlessAppDividerPIDs(items: groupedSwitcherItems + windowlessApps) == [303],
               "windowless apps are separated once after all windows of the preceding apps")
        suite.expect(SwitcherSupport.windowlessAppDividerPIDs(items: [groupedSwitcherItems[0],
                                                               windowlessApps[0],
                                                               groupedSwitcherItems[2],
                                                               windowlessApps[1]]) == [303, 202, 404],
               "dividers follow each windowless boundary without changing recent-use order")
        suite.expect(SwitcherSupport.windowlessAppDividerPIDs(items: [windowlessApps[0],
                                                               groupedSwitcherItems[0]]) == [101],
               "a leading windowless group has a divider after it, never before the first icon")
        let dividerHiddenWindow = SwitcherItem.window(id: 4, title: "Hidden", appName: "Hidden", pid: 505,
                                                      isOnScreen: false, isAppHidden: true, frame: .zero)
        suite.expect(SwitcherSupport.windowlessAppDividerPIDs(items: [groupedSwitcherItems[0].withMinimized(true),
                                                               dividerHiddenWindow] + windowlessApps) == [303],
               "minimized and hidden windows still belong to apps with windows")
        suite.expect(SwitcherSupport.windowlessAppDividerPIDs(items: [SwitcherItem.appOnly(appName: "Alpha", pid: 101)]
                                                        + groupedSwitcherItems + windowlessApps) == [303],
               "an app with any real window is never marked windowless by an app-only entry")
        var cappedAppWindows: [SwitcherItem] = []
        var cappedAppRepresentatives: [SwitcherItem] = []
        for appIndex in 1...25 {
            let pid = pid_t(appIndex)
            let primary = SwitcherItem.window(id: CGWindowID(appIndex * 10),
                                              title: "Primary \(appIndex)",
                                              appName: "App \(appIndex)",
                                              pid: pid,
                                              isOnScreen: true,
                                              frame: .zero)
            cappedAppWindows.append(primary)
            if appIndex == 1 {
                cappedAppWindows.append(
                    SwitcherItem.window(id: 11, title: "Secondary 1", appName: "App 1",
                                        pid: pid, isOnScreen: true, frame: .zero))
                cappedAppWindows.append(
                    SwitcherItem.window(id: 12, title: "Tertiary 1", appName: "App 1",
                                        pid: pid, isOnScreen: true, frame: .zero))
            }
            if appIndex <= 24 {
                cappedAppRepresentatives.append(primary)
            }
        }
        let expandedCappedApps = SwitcherSupport.expandGroupedWindows(
            orderedWindows: cappedAppWindows,
            representatives: cappedAppRepresentatives)
        suite.expect(expandedCappedApps.count == 26
               && expandedCappedApps.prefix(3).map(\.windowID) == [10, 11, 12]
               && Set(expandedCappedApps.map(\.pid)) == Set((1...24).map { pid_t($0) })
               && !expandedCappedApps.contains { $0.pid == 25 },
               "App Switcher expands every backing window without displacing a capped app")
        suite.expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 0,
                                                     delta: 1) == 2,
               "App Switcher icon-row app navigation skips duplicate windows from the same app")
        suite.expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 2,
                                                     delta: -1) == 0,
               "App Switcher icon-row app navigation wraps backward by app")
        suite.expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 2,
                                                     delta: 1,
                                                     wrapping: false) == 2,
               "held key stops at the last app instead of wrapping, like the system switcher")
        suite.expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 0,
                                                     delta: -1,
                                                     wrapping: false) == 0,
               "held key stops at the first app when navigating backward")
        suite.expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 0,
                                                     delta: 1,
                                                     wrapping: false) == 2,
               "non-wrapping navigation still advances while not at the edge")
        suite.expect(SwitcherSupport.nextWindowSelectionIndexWithinApp(items: groupedSwitcherItems,
                                                                 selectedIndex: 0,
                                                                 delta: 1) == 1,
               "App Switcher icon-row window navigation moves within the selected app")
        suite.expect(SwitcherSupport.nextWindowSelectionIndexWithinApp(items: groupedSwitcherItems,
                                                                 selectedIndex: 1,
                                                                 delta: 1) == 0,
               "App Switcher icon-row window navigation wraps within the selected app")
        suite.expect(SwitcherSupport.nextWindowSelectionIndexWithinApp(items: groupedSwitcherItems,
                                                                 selectedIndex: 2,
                                                                 delta: 1) == 2,
               "App Switcher icon-row window navigation stays put when the app has one window")
        suite.expect(SwitcherSupport.iconRowEdgeHoverInterval > SwitcherSupport.iconRowEdgeHoverAnimationDuration
               && SwitcherSupport.iconRowEdgeHoverRepeatInterval >= SwitcherSupport.iconRowEdgeHoverAnimationDuration
               && SwitcherSupport.iconRowEdgeHoverRepeatInterval < SwitcherSupport.iconRowEdgeHoverInterval
               && SwitcherSupport.iconRowEdgeHoverAnimationDuration > 0.15,
               "App Switcher overflow hover waits to start, then steps with the slide")
        suite.expect(SwitcherSupport.clampedIconRowFirstVisibleIndex(itemCount: 12,
                                                              visibleCount: 6,
                                                              firstVisibleIndex: -2) == 0
               && SwitcherSupport.clampedIconRowFirstVisibleIndex(itemCount: 12,
                                                                 visibleCount: 6,
                                                                 firstVisibleIndex: 20) == 6
               && SwitcherSupport.clampedIconRowFirstVisibleIndex(itemCount: 5,
                                                                 visibleCount: 6,
                                                                 firstVisibleIndex: 3) == 0,
               "App Switcher overflow row never scrolls past either end")
        suite.expect(SwitcherSupport.iconRowFirstVisibleIndex(revealing: 8,
                                                        itemCount: 12,
                                                        visibleCount: 6,
                                                        currentFirstVisibleIndex: 0) == 3
               && SwitcherSupport.iconRowFirstVisibleIndex(revealing: 1,
                                                           itemCount: 12,
                                                           visibleCount: 6,
                                                           currentFirstVisibleIndex: 3) == 1
               && SwitcherSupport.iconRowFirstVisibleIndex(revealing: 4,
                                                           itemCount: 12,
                                                           visibleCount: 6,
                                                           currentFirstVisibleIndex: 3) == 3,
               "App Switcher overflow row slides just far enough to keep the selection visible")
        suite.expect(SwitcherSupport.iconRowEdgeHoverDelta(hoveredIndex: 5,
                                                     firstVisibleIndex: 0,
                                                     visibleCount: 6,
                                                     itemCount: 12) == 1
               && SwitcherSupport.iconRowEdgeHoverDelta(hoveredIndex: 3,
                                                        firstVisibleIndex: 3,
                                                        visibleCount: 6,
                                                        itemCount: 12) == -1
               && SwitcherSupport.iconRowEdgeHoverDelta(hoveredIndex: 2,
                                                        firstVisibleIndex: 0,
                                                        visibleCount: 6,
                                                        itemCount: 12) == nil
               && SwitcherSupport.iconRowEdgeHoverDelta(hoveredIndex: 5,
                                                        firstVisibleIndex: 6,
                                                        visibleCount: 6,
                                                        itemCount: 12) == nil
               && SwitcherSupport.iconRowEdgeHoverDelta(hoveredIndex: 3,
                                                        firstVisibleIndex: 0,
                                                        visibleCount: 6,
                                                        itemCount: 5) == nil,
               "App Switcher overflow hover only steps from the last visible icon on a side")
        suite.expect(SwitcherSupport.iconRowIndexAfterEdgeHoverStep(firstVisibleIndex: 1,
                                                              visibleCount: 6,
                                                              itemCount: 12,
                                                              delta: 1) == 6
               && SwitcherSupport.iconRowIndexAfterEdgeHoverStep(firstVisibleIndex: 2,
                                                                 visibleCount: 6,
                                                                 itemCount: 12,
                                                                 delta: -1) == 2,
               "App Switcher overflow hover lands on the newly revealed last visible icon")
        let frontmostScoped = SwitcherSupport.frontmostAppWindows(allItems: groupedSwitcherItems,
                                                                    frontmostPID: 101)
        suite.expect(frontmostScoped.count == 2
               && frontmostScoped.allSatisfy { $0.pid == 101 },
               "Window-scoped session keeps only the frontmost app's windows")
        suite.expect(SwitcherSupport.frontmostAppWindows(allItems: groupedSwitcherItems,
                                                   frontmostPID: 999).isEmpty,
               "Window-scoped session has no entries when the frontmost app has no windows")
        suite.expect(SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: 3,
                                                                 hasForegroundItem: true,
                                                                 reversed: false) == 1,
               "Window-scoped session starts on the next window when several are open")
        suite.expect(SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: 1,
                                                                 hasForegroundItem: true,
                                                                 reversed: false) == 0,
               "Window-scoped session keeps the lone window selected")
        suite.expect(SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: 3,
                                                                 hasForegroundItem: true,
                                                                 reversed: true) == 2,
               "Window-scoped session starts at the far end when Shift reverses")
        suite.expect(SwitcherSupport.windowNavigationDelta(positionalMatch: true,
                                                      shiftIsNavigationModifier: true,
                                                      shiftHeld: true) == -1,
               "Window shortcut Shift reverses a positional match")
        suite.expect(SwitcherSupport.windowNavigationDelta(positionalMatch: false,
                                                      shiftIsNavigationModifier: true,
                                                      shiftHeld: true) == 1,
               "Window shortcut Shift stays forward when the layout needs it for the character")
        let afterFirstSwitch = WindowUseOrder.promoting(2, previous: 1, in: [])
        suite.expect(afterFirstSwitch == [2, 1],
               "App Switcher use history records the previous window immediately after a switch")
        let afterSecondSwitch = WindowUseOrder.promoting(1, previous: 2, in: afterFirstSwitch)
        suite.expect(afterSecondSwitch == [1, 2],
               "App Switcher use history toggles back after two consecutive switcher uses")

        WindowFocusHistoryTests.run { suite.expect($0, $1) }

        // Issue #388: the switcher put the app the user had just used far down
        // the list. The order used to come from a history that only the
        // switcher's own commits ever wrote to, so windows picked with the
        // mouse were invisible to it and windows picked once through the
        // switcher stayed ahead of them forever.
        let mouseEntries = [WindowUseOrder.Entry(windowID: 10, pid: 1),   // used through the switcher, long ago
                            WindowUseOrder.Entry(windowID: 11, pid: 2),   // used through the switcher, long ago
                            WindowUseOrder.Entry(windowID: 12, pid: 3),   // clicked a moment ago
                            WindowUseOrder.Entry(windowID: 13, pid: 4)]   // clicked just now, in front
        let mouseOrder = WindowUseOrder.ordered(mouseEntries,
                                                windowHistory: [13, 12, 11, 10],
                                                appHistory: [4, 3, 2, 1],
                                                frontToBack: [13, 12, 11, 10])
        suite.expect(mouseOrder.map(\.windowID) == [13, 12, 11, 10],
               "App Switcher orders by real window use, so windows picked with the mouse keep their place")

        // Two windows of the same app: the system posts no activation for a
        // switch between them, so only the focus history can order them.
        let sameAppEntries = [WindowUseOrder.Entry(windowID: 20, pid: 1),
                              WindowUseOrder.Entry(windowID: 21, pid: 1),
                              WindowUseOrder.Entry(windowID: 22, pid: 2)]
        let sameAppOrder = WindowUseOrder.ordered(sameAppEntries,
                                                  windowHistory: [21, 22, 20],
                                                  appHistory: [1, 2],
                                                  frontToBack: [21, 22, 20])
        suite.expect(sameAppOrder.map(\.windowID) == [21, 22, 20],
               "App Switcher toggles back to the last window used even when it belongs to the current app")

        // A window that was never focused cannot be ranked by use: it follows
        // everything that was, ordered by its app and then by how deep it sits.
        let unseenEntries = [WindowUseOrder.Entry(windowID: 30, pid: 1),
                             WindowUseOrder.Entry(windowID: 31, pid: 2),
                             WindowUseOrder.Entry(windowID: 32, pid: 3),
                             WindowUseOrder.Entry(windowID: nil, pid: 3)]
        let unseenOrder = WindowUseOrder.ordered(unseenEntries,
                                                 windowHistory: [30],
                                                 appHistory: [1, 2, 3],
                                                 frontToBack: [30, 31, 32])
        suite.expect(unseenOrder.map(\.windowID) == [30, 31, 32, nil],
               "App Switcher places never-focused windows after used ones, by app and then by depth")

        // Cold start: nothing has been used yet, so front-to-back order is the
        // only account of what came last, and it has to be used as one.
        suite.expect(WindowUseOrder.reconciled([], existing: [40, 41, 42], frontToBack: [42, 40, 41])
               == [42, 40, 41],
               "App Switcher seeds its use history from the window server instead of starting arbitrary")
        suite.expect(WindowUseOrder.reconciled([50, 51], existing: [51, 52], frontToBack: [52, 51])
               == [51, 52],
               "App Switcher use history drops closed windows and files new ones behind what was used")
        suite.expect(WindowUseOrder.reconciled([60, 61, 62], existing: [60, 61, 62], frontToBack: [62])
               == [60, 61, 62],
               "App Switcher use history is not reshuffled by the window server once it knows better")
        suite.expect(WindowUseOrder.reconciled([70, 71, 72], existing: [70, 71, 72], frontToBack: [], limit: 2)
               == [70, 71],
               "App Switcher use history stays bounded")
        suite.expect(WindowUseOrder.reconciled([], running: [80, 81, 82], frontToBack: [81, 82, 80])
               == [81, 82, 80],
               "App Switcher seeds its application history from the window server too")
        suite.expect(WindowUseOrder.reconciled([90, 91], running: [91, 92], frontToBack: [92, 91])
               == [91, 92],
               "App Switcher application history drops closed apps and files new ones behind")
        let focusedWindowLayout = SwitcherIconRowLayout.compute(
            appCount: 1, selectedWindowCount: 4, maximumWindowCount: 4,
            sessionScope: .frontmostApp,
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        suite.expect(focusedWindowLayout.previewFitsWithoutScrolling(cardCount: 4),
               "Focused-app switcher shows all four previews when the display has room")
        let crowdedFocusedLayout = SwitcherIconRowLayout.compute(
            appCount: 1, selectedWindowCount: 20, maximumWindowCount: 20,
            sessionScope: .frontmostApp,
            screenVisibleFrame: CGRect(x: 0, y: 0, width: 640, height: 900))
        suite.expect(!crowdedFocusedLayout.previewFitsWithoutScrolling(cardCount: 20)
               && crowdedFocusedLayout.panelSize.width <= 640,
               "Focused-app previews keep overflow scrollable within the display")
        let groupedIconLayout = SwitcherIconRowLayout.compute(appCount: appGroups.count,
                                                              selectedWindowCount: appGroups[0].windowCount,
                                                              screenVisibleFrame: screen)
        suite.expect(groupedIconLayout.appRowContentWidth
               >= CGFloat(appGroups.count) * SwitcherIconRowLayout.appTileWidth,
               "App Switcher icon-row layout uses full app tile width")
        suite.expect(groupedIconLayout.previewFitsWithoutScrolling(cardCount: 2),
               "App Switcher shows a pair of windows even with a short icon row")
        do {
            let savedPreviewSize = UserDefaults.standard.object(forKey: DefaultsKey.switcherPreviewSize)
            defer {
                if let savedPreviewSize {
                    UserDefaults.standard.set(savedPreviewSize, forKey: DefaultsKey.switcherPreviewSize)
                } else {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.switcherPreviewSize)
                }
            }
            for size in Defaults.allowedPreviewSizes {
                UserDefaults.standard.set(size, forKey: DefaultsKey.switcherPreviewSize)
                for width in [640.0, 800.0, 1440.0] {
                    for hints in [false, true] {
                        let frame = CGRect(x: 0, y: 0, width: width, height: 900)
                        let pair = SwitcherIconRowLayout.compute(appCount: 2, selectedWindowCount: 2,
                            maximumWindowCount: 8, screenVisibleFrame: frame, showsShortcutHints: hints)
                        let single = SwitcherIconRowLayout.compute(appCount: 2, selectedWindowCount: 1,
                            maximumWindowCount: 8, screenVisibleFrame: frame, showsShortcutHints: hints)
                        let many = SwitcherIconRowLayout.compute(appCount: 2, selectedWindowCount: 8,
                            maximumWindowCount: 8, screenVisibleFrame: frame, showsShortcutHints: hints)
                        suite.expect(pair.previewFitsWithoutScrolling(cardCount: 2),
                               "App Switcher keeps two windows visible at every preview size")
                        suite.expect(pair.panelSize.width == single.panelSize.width
                               && pair.panelSize.width == many.panelSize.width,
                               "App Switcher keeps short icon rows stationary when changing apps")
                        suite.expect(pair.panelSize.width <= width * 0.96
                               && !many.previewFitsWithoutScrolling(cardCount: 8),
                               "App Switcher bounds multi-window previews to the display and keeps overflow scrollable")
                        suite.expect(single.previewContentWidth == SwitcherIconRowLayout.previewCardWidth,
                               "App Switcher keeps single-window surfaces compact within the stable panel")
                    }
                }
            }
        }
        // A capped viewport can hold fewer cards than it looks like, because the
        // row puts spacing between them. Counting by card width alone reports a
        // fit while the last card is still clipped, and the scroll view then
        // refuses to scroll to it (#783).
        let cappedPreview = SwitcherIconRowLayout.compute(appCount: 6,
                                                          selectedWindowCount: 8,
                                                          screenVisibleFrame: screen)
        var fittingCardCount = 0
        while CGFloat(fittingCardCount + 1) * SwitcherIconRowLayout.previewCardWidth
                + CGFloat(fittingCardCount) * SwitcherIconRowLayout.spacing
                <= cappedPreview.previewContentWidth {
            fittingCardCount += 1
        }
        suite.expect(fittingCardCount >= 1
               && cappedPreview.previewContentWidth
                    < SwitcherIconRowLayout.naturalPreviewWidth(cardCount: 8)
               && cappedPreview.previewFitsWithoutScrolling(cardCount: fittingCardCount)
               && !cappedPreview.previewFitsWithoutScrolling(cardCount: fittingCardCount + 1),
               "App Switcher preview counts card spacing before it stops scrolling")
        suite.expectClose(Double(groupedIconLayout.appRowSurfaceWidth),
                    Double(groupedIconLayout.appRowContentWidth + SwitcherIconRowLayout.rowHorizontalPadding * 2),
                    "App Switcher icon-row layout keeps horizontal padding inside the app row surface")
        suite.expectClose(Double(groupedIconLayout.previewSurfaceWidth),
                    Double(groupedIconLayout.previewContentWidth + SwitcherIconRowLayout.previewPanelPadding * 2),
                    "App Switcher icon-row layout keeps preview cards away from the surface border")
        let simpleWindowLayout = SwitcherIconRowLayout.compute(
            appCount: groupedSwitcherItems.count,
            selectedWindowCount: 1,
            screenVisibleFrame: screen,
            tileWidth: SwitcherIconRowLayout.windowTileWidth
        )
        suite.expect(simpleWindowLayout.appRowContentWidth
               >= CGFloat(groupedSwitcherItems.count) * SwitcherIconRowLayout.windowTileWidth,
               "App Switcher simple window row gives every window title its own tile width")
        suite.expectClose(Double(simpleWindowLayout.simplePanelSize.height
                           - simpleWindowLayout.simpleWindowPanelSize.height),
                    Double(SwitcherIconRowLayout.simpleTitleHeight
                           + SwitcherIconRowLayout.simpleTitleGap),
                    "App Switcher simple window row removes the redundant grouped title strip")
        let groupedWindowShortcutLayout = SwitcherIconRowLayout.compute(
            appCount: 1,
            selectedWindowCount: 2,
            screenVisibleFrame: screen,
            showsShortcutHints: false
        )
        suite.expect(groupedWindowShortcutLayout.simpleTitleSurfaceWidth
               >= SwitcherIconRowLayout.simpleTitleChipMaxWidth * 2
                    + SwitcherIconRowLayout.simpleTitleSpacing,
               "App Switcher grouped window shortcut leaves both window titles visible")
        suite.expectClose(Double(groupedWindowShortcutLayout.simplePanelSize.width),
                    Double(groupedWindowShortcutLayout.simpleTitleSurfaceWidth
                           + SwitcherIconRowLayout.padding * 2),
                    "App Switcher grouped simple panel follows its window title width")
        let issue128Layout = SwitcherIconRowLayout.compute(appCount: 7,
                                                           selectedWindowCount: 2,
                                                           screenVisibleFrame: screen)
        let issue128LeftPlacement = SwitcherSupport.selectedPreviewPlacement(
            appCount: 7,
            selectedAppIndex: 1,
            selectedWindowIndex: 0,
            selectedWindowCount: 2,
            visibleIconCount: issue128Layout.visibleIconCount,
            appRowContentWidth: issue128Layout.appRowContentWidth,
            appRowSurfaceWidth: issue128Layout.appRowSurfaceWidth,
            previewContentWidth: issue128Layout.previewContentWidth,
            previewSurfaceWidth: issue128Layout.previewSurfaceWidth
        )
        let leftAppCenter = SwitcherIconRowLayout.appTileWidth / 2
            + SwitcherIconRowLayout.appTileWidth
            + SwitcherIconRowLayout.spacing
        func expectedPreviewLeading(selectedCenterInRow: CGFloat,
                                    layout: SwitcherIconRowLayout) -> CGFloat {
            let contentWidth = max(layout.appRowSurfaceWidth, layout.previewSurfaceWidth)
            let rawLeading = selectedCenterInRow - layout.previewSurfaceWidth / 2
            return min(max(0, rawLeading), contentWidth - layout.previewSurfaceWidth)
        }
        let issue128ContentWidth = max(issue128Layout.appRowSurfaceWidth, issue128Layout.previewSurfaceWidth)
        let issue128RowLeading = max(0, (issue128ContentWidth - issue128Layout.appRowSurfaceWidth) / 2)
            + SwitcherIconRowLayout.rowHorizontalPadding
        let leftPreviewLeading = expectedPreviewLeading(selectedCenterInRow: issue128RowLeading + leftAppCenter,
                                                        layout: issue128Layout)
        suite.expectClose(Double(issue128LeftPlacement.leading),
                    Double(leftPreviewLeading),
                    "App Switcher icon-row preview anchors to a left-side selected app")
        let issue128SecondWindowPlacement = SwitcherSupport.selectedPreviewPlacement(
            appCount: 7,
            selectedAppIndex: 1,
            selectedWindowIndex: 1,
            selectedWindowCount: 2,
            visibleIconCount: issue128Layout.visibleIconCount,
            appRowContentWidth: issue128Layout.appRowContentWidth,
            appRowSurfaceWidth: issue128Layout.appRowSurfaceWidth,
            previewContentWidth: issue128Layout.previewContentWidth,
            previewSurfaceWidth: issue128Layout.previewSurfaceWidth
        )
        suite.expectClose(Double(issue128SecondWindowPlacement.leading),
                    Double(issue128LeftPlacement.leading),
                    "App Switcher icon-row preview does not move when switching windows inside one app")
        let issue128CenterPlacement = SwitcherSupport.selectedPreviewPlacement(
            appCount: 7,
            selectedAppIndex: 3,
            selectedWindowIndex: 0,
            selectedWindowCount: 2,
            visibleIconCount: issue128Layout.visibleIconCount,
            appRowContentWidth: issue128Layout.appRowContentWidth,
            appRowSurfaceWidth: issue128Layout.appRowSurfaceWidth,
            previewContentWidth: issue128Layout.previewContentWidth,
            previewSurfaceWidth: issue128Layout.previewSurfaceWidth
        )
        let centerAppCenter = SwitcherIconRowLayout.appTileWidth / 2
            + 3 * (SwitcherIconRowLayout.appTileWidth + SwitcherIconRowLayout.spacing)
        let centerPreviewLeading = expectedPreviewLeading(selectedCenterInRow: issue128RowLeading + centerAppCenter,
                                                          layout: issue128Layout)
        suite.expectClose(Double(issue128CenterPlacement.leading),
                    Double(centerPreviewLeading),
                    "App Switcher icon-row preview anchors to a centered selected app")
        let scrollingPreviewPlacement = SwitcherSupport.selectedPreviewPlacement(
            appCount: 20,
            selectedAppIndex: 1,
            selectedWindowIndex: 0,
            selectedWindowCount: 2,
            visibleIconCount: 6,
            appRowContentWidth: issue128Layout.appRowContentWidth,
            appRowSurfaceWidth: issue128Layout.appRowSurfaceWidth,
            previewContentWidth: issue128Layout.previewContentWidth,
            previewSurfaceWidth: issue128Layout.previewSurfaceWidth
        )
        let scrollingPreviewLeading = expectedPreviewLeading(
            selectedCenterInRow: issue128RowLeading + issue128Layout.appRowContentWidth / 2,
            layout: issue128Layout
        )
        suite.expectClose(Double(scrollingPreviewPlacement.leading),
                    Double(scrollingPreviewLeading),
                    "App Switcher icon-row preview anchors to the visible app row when the app row scrolls")
        let manyWindowLayout = SwitcherIconRowLayout.compute(appCount: 20,
                                                             selectedWindowCount: 12,
                                                             screenVisibleFrame: screen)
        let scrollingWindowPreviewPlacement = SwitcherSupport.selectedPreviewPlacement(
            appCount: 20,
            selectedAppIndex: 1,
            selectedWindowIndex: 6,
            selectedWindowCount: 12,
            visibleIconCount: manyWindowLayout.visibleIconCount,
            appRowContentWidth: manyWindowLayout.appRowContentWidth,
            appRowSurfaceWidth: manyWindowLayout.appRowSurfaceWidth,
            previewContentWidth: manyWindowLayout.previewContentWidth,
            previewSurfaceWidth: manyWindowLayout.previewSurfaceWidth
        )
        let centeredPreviewLeading = (scrollingWindowPreviewPlacement.contentWidth - manyWindowLayout.previewSurfaceWidth) / 2
        suite.expectClose(Double(scrollingWindowPreviewPlacement.leading), Double(centeredPreviewLeading),
                    "App Switcher icon-row preview stays centered when the window preview row scrolls")
        let singleWindowAppLayout = SwitcherIconRowLayout.compute(appCount: appGroups.count,
                                                                  selectedWindowCount: appGroups[1].windowCount,
                                                                  screenVisibleFrame: screen)
        suite.expect(singleWindowAppLayout.previewContentWidth == SwitcherIconRowLayout.previewCardWidth,
               "App Switcher icon-row layout does not reserve empty preview slots for a one-window app")
        suite.expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: 22,
                                                   windowIDs: [11, 22, 33],
                                                   offset: 1) == 33,
               "Dock Preview next button selects the next window")
        suite.expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: 11,
                                                   windowIDs: [11, 22, 33],
                                                   offset: -1) == 33,
               "Dock Preview previous button wraps from the first window to the last")
        suite.expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: nil,
                                                   windowIDs: [11, 22, 33],
                                                   offset: 1) == 11,
               "Dock Preview next button starts from the first window when none is selected")
        suite.expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: nil,
                                                   windowIDs: [11, 22, 33],
                                                   offset: -1) == 33,
               "Dock Preview previous button starts from the last window when none is selected")
        suite.expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: nil,
                                                   windowIDs: [],
                                                   offset: 1) == nil,
               "Dock Preview navigation handles an empty window list")
        suite.expect(DockPreviewSupport.mouseDownDecision(isVisible: true,
                                                    isPinned: true,
                                                    isInsidePanel: false)
               == DockPreviewMouseDownDecision(shouldEndSession: false),
               "Dock Preview pinned panel ignores outside clicks")
        suite.expect(DockPreviewSupport.mouseDownDecision(isVisible: true,
                                                    isPinned: false,
                                                    isInsidePanel: true)
               == DockPreviewMouseDownDecision(shouldEndSession: false),
               "Dock Preview panel clicks are handled by the panel")
        suite.expect(DockPreviewSupport.mouseDownDecision(isVisible: true,
                                                    isPinned: false,
                                                    isInsidePanel: false)
               == DockPreviewMouseDownDecision(shouldEndSession: true),
               "Dock Preview outside clicks close the panel")
        let closeMiddle = DockPreviewSupport.closeState(afterRemoving: 22,
                                                        windowIDs: [11, 22, 33],
                                                        selectedWindowID: 22)
        suite.expect(closeMiddle.remainingWindowIDs == [11, 33],
               "Dock Preview close removes only the closed window")
        suite.expect(closeMiddle.selectedWindowID == nil,
               "Dock Preview close clears selection for the closed window")
        suite.expect(!closeMiddle.shouldEndSession,
               "Dock Preview close keeps the panel open when other windows remain")
        let closeUnselected = DockPreviewSupport.closeState(afterRemoving: 22,
                                                            windowIDs: [11, 22, 33],
                                                            selectedWindowID: 11)
        suite.expect(closeUnselected.selectedWindowID == 11,
               "Dock Preview close preserves selection for other windows")
        let closeLast = DockPreviewSupport.closeState(afterRemoving: 44,
                                                      windowIDs: [44],
                                                      selectedWindowID: 44)
        suite.expect(closeLast.shouldEndSession && closeLast.remainingWindowIDs.isEmpty,
               "Dock Preview close ends the panel when the last window is removed")
        let dockPreviewWindow = SwitcherItem.window(id: 77,
                                                    title: "Preview",
                                                    appName: "Demo",
                                                    pid: 123,
                                                    isOnScreen: true,
                                                    frame: CGRect(x: 10, y: 20, width: 300, height: 200))
        let minimizedDockPreviewWindow = dockPreviewWindow.withMinimized(true)
        suite.expect(minimizedDockPreviewWindow.id == dockPreviewWindow.id
               && minimizedDockPreviewWindow.windowID == dockPreviewWindow.windowID
               && minimizedDockPreviewWindow.isMinimized
               && !minimizedDockPreviewWindow.isOnScreen,
               "Dock Preview minimize state keeps the same window identity")
        let restoredDockPreviewWindow = minimizedDockPreviewWindow.withMinimized(false)
        suite.expect(restoredDockPreviewWindow.id == dockPreviewWindow.id
               && !restoredDockPreviewWindow.isMinimized
               && restoredDockPreviewWindow.isOnScreen,
               "Dock Preview restore clears the minimized state without changing identity")
        suite.expect(SwitcherSupport.activationPlan(targetsSpecificWindow: true)
               == SwitcherActivationPlan(activateAllWindows: false,
                                         makeAppFrontmostAfterActivation: false,
                                         restoreSourceWhenTargetMinimizes: true),
               "App Switcher keeps specific-window activation scoped to one window")
        suite.expect(SwitcherSupport.activationPlan(targetsSpecificWindow: false)
               == SwitcherActivationPlan(activateAllWindows: true,
                                         makeAppFrontmostAfterActivation: true,
                                         restoreSourceWhenTargetMinimizes: false),
               "App Switcher can activate the full app for app-only entries")
        let windowScopedPlan = SwitcherSupport.activationPlan(targetsSpecificWindow: true)
        let appScopedPlan = SwitcherSupport.activationPlan(targetsSpecificWindow: false)
        suite.expect(SwitcherSupport.appActivationRoute(plan: windowScopedPlan, windowID: 77)
               == .exactWindow(77),
               "a selected window is fronted by the window server, not by activating its app")
        suite.expect(SwitcherSupport.appActivationRoute(plan: appScopedPlan, windowID: 77) == .wholeApp,
               "an app entry still activates the whole app the way Command-Tab does")
        suite.expect(SwitcherSupport.appActivationRoute(plan: windowScopedPlan, windowID: nil) == .wholeApp,
               "a window-scoped plan without a window id has only the app to activate")
        suite.expect(!SwitcherSupport.shouldActivateAllWindows(targetsSpecificWindow: true),
               "App Switcher activates only the selected window when a window target exists")
        suite.expect(SwitcherSupport.shouldActivateAllWindows(targetsSpecificWindow: false),
               "App Switcher can activate the full app for app-only entries")
        suite.expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                      sourcePID: 20,
                                                                      frontmostPID: 10,
                                                                      targetIsMinimized: true,
                                                                      ownPID: 99),
               "App Switcher restores the previous app when a specific target window is minimized")
        suite.expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                       sourcePID: 10,
                                                                       frontmostPID: 10,
                                                                       targetIsMinimized: true,
                                                                       ownPID: 99),
               "App Switcher does not restore when the source is another window from the same app")
        suite.expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                       sourcePID: 20,
                                                                       frontmostPID: 30,
                                                                       targetIsMinimized: true,
                                                                       ownPID: 99),
               "App Switcher does not steal focus if the user already moved to another app")
        suite.expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                      sourcePID: 20,
                                                                      frontmostPID: 30,
                                                                      targetIsMinimized: true,
                                                                      ownPID: 99,
                                                                      frontmostMatchesTargetBundle: true),
               "App Switcher restores the previous app if a sibling app instance is promoted after minimize")
        suite.expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                      sourcePID: 20,
                                                                      frontmostPID: 30,
                                                                      targetIsMinimized: true,
                                                                      ownPID: 99,
                                                                      frontmostCanBeSystemPromotion: true),
               "App Switcher restores the previous app if the system promotes another window during minimize")
        suite.expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                       sourcePID: 20,
                                                                       frontmostPID: 10,
                                                                       targetIsMinimized: false,
                                                                       ownPID: 99),
               "App Switcher restores the previous app only after the target window is minimized")
        suite.expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 10,
                                                                            focusedWindowID: 44,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: true,
                                                                            ownPID: 99),
               "App Switcher restores the source after a minimize-button intent once the target is minimized")
        suite.expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 10,
                                                                            focusedWindowID: 55,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: false,
                                                                            ownPID: 99),
               "App Switcher restores the source if the target app focuses another window after minimize intent")
        suite.expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                             sourcePID: 20,
                                                                             frontmostPID: 10,
                                                                             focusedWindowID: 44,
                                                                             targetWindowID: 44,
                                                                             targetIsMinimized: false,
                                                                             ownPID: 99),
               "App Switcher waits when minimize intent is observed but the target remains focused and unminimized")
        suite.expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                             sourcePID: 20,
                                                                             frontmostPID: 30,
                                                                             focusedWindowID: 55,
                                                                             targetWindowID: 44,
                                                                             targetIsMinimized: false,
                                                                             ownPID: 99),
               "App Switcher does not restore source after minimize intent if a third app is already active")
        suite.expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 30,
                                                                            focusedWindowID: 55,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: true,
                                                                            ownPID: 99,
                                                                            frontmostMatchesTargetBundle: true),
               "App Switcher restores after minimize intent if a sibling app instance is promoted")
        suite.expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 30,
                                                                            focusedWindowID: 55,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: true,
                                                                            ownPID: 99,
                                                                            frontmostCanBeSystemPromotion: true),
               "App Switcher restores after minimize intent if the system promotes another app")
        suite.expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                             sourcePID: 10,
                                                                             frontmostPID: 10,
                                                                             focusedWindowID: 55,
                                                                             targetWindowID: 44,
                                                                             targetIsMinimized: true,
                                                                             ownPID: 99),
               "App Switcher does not restore source after minimize intent within the same app")
        var minimizeIntentMinimizedReads = 0
        var minimizeIntentFocusedReads = 0
        func minimizeIntentMinimized(_ value: Bool) -> Bool {
            minimizeIntentMinimizedReads += 1
            return value
        }
        func minimizeIntentFocused(_ value: UInt32?) -> UInt32? {
            minimizeIntentFocusedReads += 1
            return value
        }
        suite.expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(
                    targetPID: 10,
                    sourcePID: 20,
                    frontmostPID: 20,
                    focusedWindowID: minimizeIntentFocused(55),
                    targetWindowID: 44,
                    targetIsMinimized: minimizeIntentMinimized(true),
                    ownPID: 99),
               "App Switcher stops a minimize restore pulse once the source is already frontmost")
        suite.expect(minimizeIntentMinimizedReads == 0 && minimizeIntentFocusedReads == 0,
               "App Switcher reads no window state on a minimize pulse the frontmost check alone settles")
        suite.expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(
                    targetPID: 10,
                    sourcePID: 20,
                    frontmostPID: 10,
                    focusedWindowID: minimizeIntentFocused(55),
                    targetWindowID: 44,
                    targetIsMinimized: minimizeIntentMinimized(true),
                    ownPID: 99),
               "App Switcher restores the source once the target window reports itself minimized")
        suite.expect(minimizeIntentMinimizedReads == 1 && minimizeIntentFocusedReads == 0,
               "App Switcher skips the focused-window read when the target is already minimized")
        suite.expect(SwitcherSupport.shouldStageSourceBehindTarget(targetPID: 10,
                                                             sourcePID: 20,
                                                             sourceWindowID: 44,
                                                             ownPID: 99),
               "App Switcher can keep the source window directly behind a selected target window")
        suite.expect(!SwitcherSupport.shouldStageSourceBehindTarget(targetPID: 10,
                                                              sourcePID: 10,
                                                              sourceWindowID: 44,
                                                              ownPID: 99),
               "App Switcher does not stage a source window from the same app")
        suite.expect(!SwitcherSupport.shouldStageSourceBehindTarget(targetPID: 10,
                                                              sourcePID: 99,
                                                              sourceWindowID: 44,
                                                              ownPID: 99),
               "App Switcher does not raise its own editor back over the selected window")
        suite.expect(!SwitcherSupport.shouldStageSourceBehindTarget(targetPID: 10,
                                                              sourcePID: 20,
                                                              sourceWindowID: nil,
                                                              ownPID: 99),
               "App Switcher does not stage without a concrete source window")
        suite.expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 10,
                                                        targetIsMinimized: false,
                                                        targetStartedMinimized: false,
                                                        ownPID: 99),
               "App Switcher focus retries can continue while the selected target app is still active")
        suite.expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 20,
                                                        targetIsMinimized: false,
                                                        targetStartedMinimized: false,
                                                        ownPID: 99),
               "App Switcher focus retries can continue during the source-target handoff")
        suite.expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 20,
                                                         targetIsMinimized: true,
                                                         targetStartedMinimized: false,
                                                         ownPID: 99),
               "App Switcher focus retries stop once the selected target window was minimized")
        suite.expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 20,
                                                        targetIsMinimized: true,
                                                        targetStartedMinimized: true,
                                                        ownPID: 99),
               "App Switcher retries restoration when the selected target started minimized")
        suite.expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                          sourcePID: 20,
                                                          frontmostPID: 10,
                                                         targetIsMinimized: true,
                                                         targetStartedMinimized: true,
                                                         targetWasObservedRestored: true,
                                                         ownPID: 99),
               "App Switcher does not reopen a target the user minimized again after activation")
        suite.expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 30,
                                                         targetIsMinimized: false,
                                                         targetStartedMinimized: false,
                                                         ownPID: 99),
               "App Switcher focus retries do not steal focus after the user moves to another app")
        switcherFocusRetryChecks(suite)
        // A window opened after the switch (Command-N in the app the switcher
        // just raised) keeps the app frontmost, so the checks above cannot see
        // it; the retry has to recognize the window itself.
        suite.expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 10,
                                                         targetIsMinimized: false,
                                                         targetStartedMinimized: false,
                                                         knownWindowIDs: [101, 102],
                                                         targetAppWindowIDs: [777],
                                                         targetAppFocusedWindowID: 777,
                                                          ownPID: 99),
               "App Switcher focus retries let go of a window the app opened after the switch")
        // The guard only reads Accessibility once the cheap window-server list
        // shows the app gained something. Both lists must therefore be taken
        // in the same scope: the on-screen list lags a newly opened window,
        // and comparing it against an all-windows snapshot reported nothing
        // new in exactly the race the guard exists for. Comments are stripped
        // first, so the one explaining that lag cannot satisfy the check.
        let activatorSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Switcher/WindowActivator.swift",
            encoding: .utf8)) ?? ""
        let activatorCode = activatorSource
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let windowScopes = activatorCode
            .components(separatedBy: "windowIDs(ownerPID:")
            .dropFirst()
            .compactMap { $0.components(separatedBy: ")").first }
            .filter { $0.contains("options: .") }
        suite.expect(windowScopes.count >= 2 && windowScopes.allSatisfy { $0.contains(".optionAll") },
               "the retry's live window list is gathered in the same scope as the snapshot it is compared against")
        // A switch away from a fullscreen app reaches its target through a hop,
        // whose arrival pulses raise it for up to a second. They must ask the
        // same guard before raising, or Command-N in the app just reached is
        // covered by the target on the next pulse. Comments are stripped, so a
        // doc comment naming the guard cannot stand in for the call.
        let hopFocusBody: String = {
            guard let start = activatorCode.range(of: "static func focusAfterSpaceHop(") else { return "" }
            let rest = activatorCode[start.upperBound...]
            let end = rest.range(of: "static func ")?.lowerBound ?? rest.endIndex
            return String(rest[..<end])
        }()
        let hopGuard = hopFocusBody.range(of: "shouldContinueFocusRetry(")
        // Whatever the pass uses to bring the window forward, the guard comes
        // first. Naming one of those calls would pin today's spelling and go
        // red on a refactor that broke nothing.
        let hopRaise = ["prepareWindowForActivation(", "activateApp(", "focusWindow("]
            .compactMap { hopFocusBody.range(of: $0)?.lowerBound }
            .min()
        suite.expect(hopGuard != nil && hopRaise != nil && hopGuard!.lowerBound < hopRaise!,
               "the hop's arrival pass consults the retry guard before it raises the target")
        let spaceHopCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Switcher/SpaceHop.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(spaceHopCode.contains("state: self.focusState")
               && spaceHopCode.contains("knownWindowIDs: WindowActivator.focusSnapshot(ownerPID:"),
               "a hop snapshots the app's windows when it begins and hands that state to every pulse")
        // Review of #1578: a hop across two or more desktops arrives with
        // whatever tops each desktop it passed in front. Reading that as "the
        // user moved on" would leave the window they picked behind that app,
        // so a hop's pass judges the app's own focus instead.
        suite.expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 30,
                                                        targetIsMinimized: false,
                                                        targetStartedMinimized: false,
                                                        knownWindowIDs: [101],
                                                        targetAppWindowIDs: [101],
                                                        targetAppFocusedWindowID: 101,
                                                        ignoresForeground: true,
                                                        ownPID: 99),
               "a hop still raises its target when another desktop's app arrived in front")
        suite.expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 30,
                                                         targetIsMinimized: false,
                                                         targetStartedMinimized: false,
                                                         knownWindowIDs: [101],
                                                         targetAppWindowIDs: [101, 777],
                                                         targetAppFocusedWindowID: 777,
                                                         ignoresForeground: true,
                                                         ownPID: 99),
               "a hop still gives up once the app itself moved to a window it opened later")
        suite.expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 30,
                                                         targetIsMinimized: false,
                                                         targetStartedMinimized: false,
                                                         knownWindowIDs: [101],
                                                         targetAppWindowIDs: [101],
                                                         targetAppFocusedWindowID: 101,
                                                         ownPID: 99),
               "the ordinary passes still stand down when the user moved to another app")
        let hopFocusCall: String = {
            guard let start = activatorCode.range(of: "static func focusAfterSpaceHop(") else { return "" }
            let rest = activatorCode[start.upperBound...]
            let end = rest.range(of: "static func ")?.lowerBound ?? rest.endIndex
            return String(rest[..<end])
        }()
        suite.expect(hopFocusCall.contains("ignoresForeground: true"),
               "the hop's arrival pass asks the guard in the mode that ignores who is in front")
        suite.expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 10,
                                                        targetIsMinimized: false,
                                                        targetStartedMinimized: false,
                                                        knownWindowIDs: [101, 102],
                                                        targetAppWindowIDs: [102],
                                                        targetAppFocusedWindowID: 102,
                                                        ownPID: 99),
               "a window the app already had does not cancel the retry, so the pass still settles the target")
        suite.expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 10,
                                                        targetIsMinimized: false,
                                                        targetStartedMinimized: false,
                                                        knownWindowIDs: [101, 102],
                                                        targetAppWindowIDs: [],
                                                        targetAppFocusedWindowID: nil,
                                                        ownPID: 99),
               "an app with nothing on screen yet is the case the retry exists for, and still runs")
        suite.expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 10,
                                                        targetIsMinimized: false,
                                                        targetStartedMinimized: false,
                                                        knownWindowIDs: [],
                                                        targetAppWindowIDs: [777],
                                                        targetAppFocusedWindowID: 777,
                                                        ownPID: 99),
               "without a snapshot of the app's windows the retry behaves exactly as before")
        suite.expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 30,
                                                         targetIsMinimized: true,
                                                         targetStartedMinimized: true,
                                                         ownPID: 99),
               "App Switcher does not restore a minimized target after the user moves to another app")
        suite.expect(SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                sourcePID: 20,
                                                                frontmostPID: 20,
                                                                targetWasObservedFrontmost: false,
                                                                ownPID: 99),
               "App Switcher can retry an app-only target during a fullscreen handoff")
        suite.expect(SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                sourcePID: 20,
                                                                frontmostPID: 10,
                                                                targetWasObservedFrontmost: true,
                                                                ownPID: 99),
               "App Switcher can settle repeated activation on the app-only target")
        suite.expect(!SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 frontmostPID: 20,
                                                                 targetWasObservedFrontmost: true,
                                                                 ownPID: 99),
               "App Switcher cancels app-only retries when the user returns to the fullscreen source")
        suite.expect(!SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 frontmostPID: 30,
                                                                 targetWasObservedFrontmost: false,
                                                                 ownPID: 99),
               "App Switcher app-only retries do not steal focus from another app")
        suite.expect(!SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                 sourcePID: nil,
                                                                 frontmostPID: 30,
                                                                 targetWasObservedFrontmost: false,
                                                                 ownPID: 99),
               "App Switcher app-only retries fail closed without a known source app")
        suite.expect(SwitcherSupport.isCurrentSessionStart(generation: 8, pendingGeneration: 8)
               && !SwitcherSupport.isCurrentSessionStart(generation: 8, pendingGeneration: 9)
               && !SwitcherSupport.isCurrentSessionStart(generation: 8, pendingGeneration: nil),
               "App Switcher publishes only the current asynchronous session start")
        suite.expect(SwitcherSupport.pendingKeyDecision(sessionIsActive: false,
                                                  hasPendingStart: true,
                                                  commitWhenReady: false,
                                                  matchesShortcut: false) == .swallow
               && SwitcherSupport.pendingKeyDecision(sessionIsActive: false,
                                                      hasPendingStart: true,
                                                      commitWhenReady: true,
                                                      matchesShortcut: false) == .cancelAndSwallow,
               "App Switcher owns keys during enumeration and cancels a late commit before typing leaks")
        suite.expect(SwitcherSupport.pendingKeyDecision(sessionIsActive: false,
                                                  hasPendingStart: true,
                                                  commitWhenReady: false,
                                                  matchesShortcut: true) == .routeShortcut
               && SwitcherSupport.pendingKeyDecision(sessionIsActive: true,
                                                      hasPendingStart: false,
                                                      commitWhenReady: false,
                                                      matchesShortcut: false) == .handleActiveSession,
               "App Switcher still routes repeated shortcuts and keys from a session that just became active")
        let nativeSwitcherShortcuts: [SwitcherNativeSymbolicHotKey: GlobalShortcut] = [
            .commandTab: .switcherDefault,
            .commandShiftTab: GlobalShortcut(keyCode: Int64(kVK_Tab),
                                             modifiers: [.command, .shift]),
            .nextWindow: .switcherWindowDefault,
            .previousWindow: GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave),
                                            modifiers: [.command, .shift]),
        ]
        suite.expect(SwitcherSupport.nativeHotkeysToSuppress(
                    takeOverSystemShortcuts: false,
                    appsShortcut: .switcherDefault,
                    windowShortcut: .switcherWindowDefault,
                    nativeShortcuts: nativeSwitcherShortcuts).isEmpty,
               "the App Switcher never changes macOS shortcuts without explicit opt-in")
        suite.expect(SwitcherSupport.nativeHotkeysToSuppress(
                    takeOverSystemShortcuts: true,
                    appsShortcut: .switcherDefault,
                    windowShortcut: .switcherWindowDefault,
                    nativeShortcuts: nativeSwitcherShortcuts)
               == Set(SwitcherNativeSymbolicHotKey.allCases),
               "opt-in covers both app and window switcher directions")
        suite.expect(SwitcherSupport.nativeHotkeysToSuppress(
                    takeOverSystemShortcuts: true,
                    appsShortcut: GlobalShortcut(keyCode: Int64(kVK_Tab), modifiers: [.option]),
                    windowShortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave), modifiers: [.option]),
                    nativeShortcuts: nativeSwitcherShortcuts).isEmpty,
               "non-colliding shortcuts leave the macOS switchers in place")
        let remappedNativeShortcuts = nativeSwitcherShortcuts.mapValues {
            GlobalShortcut(keyCode: $0.keyCode,
                           modifiers: $0.modifiers.subtracting(.command).union(.option))
        }
        suite.expect(SwitcherSupport.nativeHotkeysToSuppress(
                    takeOverSystemShortcuts: true,
                    appsShortcut: GlobalShortcut(keyCode: Int64(kVK_Tab), modifiers: [.option]),
                    windowShortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave), modifiers: [.option]),
                    nativeShortcuts: remappedNativeShortcuts)
               == Set(SwitcherNativeSymbolicHotKey.allCases),
               "takeover follows the current macOS shortcut mappings instead of hardcoded keys")

        // The ids come from the WindowServer's own table: 27 and 220 are the
        // two window-cycling keys, 28 is "save picture of screen as a file".
        // Mapping from raw ids the way `configuredShortcuts()` does keeps a
        // wrong id from silently pointing the take-over at the wrong key.
        let liveSwitcherTable: [Int32: GlobalShortcut] = [
            1: .switcherDefault,
            2: GlobalShortcut(keyCode: Int64(kVK_Tab), modifiers: [.command, .shift]),
            27: .switcherWindowDefault,
            28: GlobalShortcut(keyCode: Int64(kVK_ANSI_3), modifiers: [.command, .shift]),
            220: GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave), modifiers: [.command, .shift]),
        ]
        let mappedSwitcherShortcuts = Dictionary(uniqueKeysWithValues:
            SwitcherNativeSymbolicHotKey.allCases.compactMap { id in
                liveSwitcherTable[id.rawValue].map { (id, $0) }
            })
        let screenshotToFile = GlobalShortcut(keyCode: Int64(kVK_ANSI_3), modifiers: [.command, .shift])
        suite.expect(mappedSwitcherShortcuts[.previousWindow]
               == GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave), modifiers: [.command, .shift]),
               "the reverse window switcher resolves to Command-Shift-Backtick in the live table")
        suite.expect(SwitcherSupport.nativeHotkeysToSuppress(
                    takeOverSystemShortcuts: true,
                    appsShortcut: .switcherDefault,
                    windowShortcut: .switcherWindowDefault,
                    nativeShortcuts: mappedSwitcherShortcuts)
               == Set(SwitcherNativeSymbolicHotKey.allCases),
               "with the real ids, Command-Shift-Backtick is taken over together with Command-Backtick")
        let threeKeyTakeover = SwitcherSupport.nativeHotkeysToSuppress(
            takeOverSystemShortcuts: true,
            appsShortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_3), modifiers: [.command]),
            windowShortcut: .switcherWindowDefault,
            nativeShortcuts: mappedSwitcherShortcuts)
        suite.expect(threeKeyTakeover == [.nextWindow, .previousWindow]
               && !threeKeyTakeover.contains { mappedSwitcherShortcuts[$0] == screenshotToFile },
               "a switcher shortcut on the 3 key takes over only the two window-cycling keys, never the screenshot key")
        // The switcher is the take-over's caller: it resolves its own ids out
        // of the live table and hands them over, so a wrong id can no longer
        // reach the WindowServer through a hardcoded enum.
        let liveSwitcherEntries: [LiveSystemShortcut] = [
            LiveSystemShortcut(id: 1, shortcut: .switcherDefault, enabled: true),
            LiveSystemShortcut(id: 2, shortcut: GlobalShortcut(keyCode: Int64(kVK_Tab), modifiers: [.command, .shift]), enabled: true),
            LiveSystemShortcut(id: 27, shortcut: .switcherWindowDefault, enabled: true),
            LiveSystemShortcut(id: 28, shortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_3), modifiers: [.command, .shift]), enabled: true),
            LiveSystemShortcut(id: 220, shortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave), modifiers: [.command, .shift]), enabled: true),
        ]
        suite.expect(SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: true,
                                               appsShortcut: .switcherDefault,
                                               windowShortcut: .switcherWindowDefault,
                                               liveEntries: liveSwitcherEntries) == [1, 2, 27, 220],
               "the switcher asks the shared take-over for exactly its four ids, never the screenshot key")
        suite.expect(SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: false,
                                               appsShortcut: .switcherDefault,
                                               windowShortcut: .switcherWindowDefault,
                                               liveEntries: liveSwitcherEntries).isEmpty,
               "without opt-in the switcher asks for nothing")
        suite.expect(SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: true,
                                               appsShortcut: .switcherDefault,
                                               windowShortcut: .switcherWindowDefault,
                                               liveEntries: liveSwitcherEntries.filter { $0.id != 220 })
               == [1, 2, 27],
               "an id missing from the live table is never asked for")

        // The shared take-over works on raw WindowServer ids. Same transition
        // rule as the switcher had: suppress only what is enabled now, restore
        // only what we own and no longer want.
        suite.expect(SystemShortcutTakeoverSupport.transition(from: [], to: [1, 2, 30], currentlyEnabled: [1, 30])
               == SystemShortcutTransition(suppress: [1, 30], restore: [])
               && SystemShortcutTakeoverSupport.transition(from: [1, 30], to: [], currentlyEnabled: [])
               == SystemShortcutTransition(suppress: [], restore: [1, 30]),
               "the shared take-over suppresses only enabled ids and restores only owned ones")
        suite.expect(SystemShortcutTakeoverSupport.migratedMarker(old: [27, 28], new: [30]) == [27, 28, 30]
               && SystemShortcutTakeoverSupport.migratedMarker(old: nil, new: nil).isEmpty
               && SystemShortcutTakeoverSupport.migratedMarker(old: [99_999_999_999], new: nil).isEmpty,
               "the old switcher marker folds into the shared one once, dropping anything that is not an id")
        // #1357's contracts, now carried by the shared rule. Launch gives back
        // every id the marker still holds, including when the App Switcher is
        // off: a feature that is off claims none of them, so all of them are
        // restored without the switcher's tap or the feature being installed.
        let legacyMarker = SystemShortcutTakeoverSupport.migratedMarker(old: [27, 28, 220], new: nil)
        suite.expect(SystemShortcutTakeoverSupport.recoveryTransition(from: legacyMarker, keeping: [])
               == SystemShortcutTransition(suppress: [], restore: [27, 28, 220]),
               "launch gives back a marker left by an earlier build even with the switcher off")
        var recoveryWrites: [Int32] = []
        let recordRecoveryWrite: (Int32, Bool) -> Bool = { id, _ in
            recoveryWrites.append(id)
            return true
        }
        let cleanLaunchOwnership = SystemShortcutTakeoverSupport.apply(
            SystemShortcutTakeoverSupport.recoveryTransition(from: [], keeping: [1, 2, 27, 220]),
            owned: [], setEnabled: recordRecoveryWrite, persist: { _ in })
        suite.expect(cleanLaunchOwnership.isEmpty && recoveryWrites.isEmpty,
               "clean launch leaves system shortcuts working until the replacement tap is live")
        let recoveredOwnership = SystemShortcutTakeoverSupport.apply(
            SystemShortcutTakeoverSupport.recoveryTransition(from: legacyMarker, keeping: [1, 27, 220]),
            owned: legacyMarker, setEnabled: recordRecoveryWrite, persist: { _ in })
        suite.expect(recoveredOwnership == [27, 220] && recoveryWrites == [28],
               "crash recovery gives back stale keys without toggling retained keys or taking new ones")
        // The switcher is not the only source by the time recovery runs: a
        // feature that claimed first holds its ids too, so launch keeps what
        // every source wants together rather than the switcher's ids alone.
        var earlyClaimWrites: [Int32] = []
        let earlyClaimOwnership = SystemShortcutTakeoverSupport.apply(
            SystemShortcutTakeoverSupport.recoveryTransition(
                from: [1, 28, 30],
                keeping: SystemShortcutTakeoverSupport.union(
                    of: ["switcher": [1], "keepAwakeShortcut": [30]])),
            owned: [1, 28, 30],
            setEnabled: { id, _ in
                earlyClaimWrites.append(id)
                return true
            },
            persist: { _ in })
        suite.expect(earlyClaimOwnership == [1, 30] && earlyClaimWrites == [28],
               "launch keeps a claim made before recovery ran alongside the switcher's ids")
        // Say the WindowServer refused 28: `apply` leaves it in the marker, so
        // every later transition asks for it again and the give-back finishes
        // at the next take-over or in the next process.
        suite.expect(SystemShortcutTakeoverSupport.transition(from: [28], to: [1], currentlyEnabled: [1])
               == SystemShortcutTransition(suppress: [1], restore: [28]),
               "an id whose give-back failed stays owned and is retried while another key is taken over")
        suite.expect(SystemShortcutTakeoverSupport.transition(from: [1, 28], to: [], currentlyEnabled: [])
               == SystemShortcutTransition(suppress: [], restore: [1, 28]),
               "a marker that survived a failed give-back is retried in full by the next process")
        suite.expect(SystemShortcutTakeoverSupport.transition(from: [], to: [], currentlyEnabled: [1, 28])
               == SystemShortcutTransition(suppress: [], restore: []),
               "an id given back successfully leaves the marker and is never switched on again")
        // The pass itself, against a fake table: the marker must be on disk
        // before a key is switched off, a refused disable must take the key
        // back out, and a refused enable must leave it in for the retry.
        var fakeEnabled: Set<Int32> = [1, 27]
        var refused: Set<Int32> = []
        var markers: [Set<Int32>] = []
        var writeAheadMissing = false
        let fakeSetEnabled: (Int32, Bool) -> Bool = { id, on in
            if !on, !(markers.last?.contains(id) ?? false) { writeAheadMissing = true }
            guard !refused.contains(id) else { return false }
            if on { fakeEnabled.insert(id) } else { fakeEnabled.remove(id) }
            return true
        }
        let record: (Set<Int32>) -> Void = { markers.append($0) }
        refused = [27]
        let afterRefusedDisable = SystemShortcutTakeoverSupport.apply(
            SystemShortcutTransition(suppress: [1, 27], restore: []), owned: [],
            setEnabled: fakeSetEnabled, persist: record)
        suite.expect(afterRefusedDisable == [1] && fakeEnabled == [27] && markers.last == [1]
               && markers.contains(where: { $0.contains(27) }),
               "a refused disable rolls the key back out of the marker it was written ahead into")
        refused = [1]
        let afterRefusedEnable = SystemShortcutTakeoverSupport.apply(
            SystemShortcutTransition(suppress: [], restore: [1]), owned: afterRefusedDisable,
            setEnabled: fakeSetEnabled, persist: record)
        suite.expect(afterRefusedEnable == [1] && !fakeEnabled.contains(1),
               "a refused enable keeps the key in the marker for the next pass to retry")
        refused = []
        suite.expect(SystemShortcutTakeoverSupport.apply(
                   SystemShortcutTransition(suppress: [], restore: [1]), owned: afterRefusedEnable,
                   setEnabled: fakeSetEnabled, persist: record).isEmpty && fakeEnabled == [1, 27],
               "the retry finishes the give-back")
        suite.expect(!writeAheadMissing, "ownership is persisted before every disable")

        // A claimed shortcut resolves to every live id that is exactly that
        // combination - the two screenshot rows share Shift-Command on different keys and
        // must not be confused; a disabled row still counts, `apply` sorts it out.
        let liveForClaims: [LiveSystemShortcut] = [
            LiveSystemShortcut(id: 28, shortcut: GlobalShortcut(keyCode: 20, modifiers: [.command, .shift]), enabled: true),
            LiveSystemShortcut(id: 30, shortcut: GlobalShortcut(keyCode: 21, modifiers: [.command, .shift]), enabled: true),
            LiveSystemShortcut(id: 64, shortcut: GlobalShortcut(keyCode: 49, modifiers: [.command]), enabled: false),
        ]
        suite.expect(SystemShortcutTakeoverSupport.ids(matching: GlobalShortcut(keyCode: 21, modifiers: [.command, .shift]),
                                                 in: liveForClaims) == [30]
               && SystemShortcutTakeoverSupport.ids(matching: GlobalShortcut(keyCode: 49, modifiers: [.command]),
                                                    in: liveForClaims) == [64]
               && SystemShortcutTakeoverSupport.ids(matching: .screenshotDefault, in: liveForClaims).isEmpty,
               "a claimed shortcut maps to exactly the live ids that equal it")
        suite.expect(SystemShortcutTakeoverSupport.union(of: ["switcher": [1, 2], "screenshotShortcut": [30], "shelf": []]) == [1, 2, 30]
               && SystemShortcutTakeoverSupport.union(of: [:]).isEmpty,
               "the service applies what every source wants, together")
        suite.expect(SystemShortcutTakeoverSupport.transition(from: [1, 30], to: [], currentlyEnabled: [])
               == SystemShortcutTransition(suppress: [], restore: [1, 30]),
               "quitting hands back every key any feature took over")
        // Launch recovery records the ids it kept as the switcher's own, so the
        // first claim of the launch - a row with no opt-in of its own resolves
        // to nothing - asks for those ids too and hands none of them back.
        suite.expect(SystemShortcutTakeoverSupport.transition(
                   from: [1, 2],
                   to: SystemShortcutTakeoverSupport.union(of: ["switcher": [1, 2]]),
                   currentlyEnabled: []) == SystemShortcutTransition(suppress: [], restore: []),
               "a claim with no opt-in leaves the marker launch recovery is holding alone")
        // A key already taken over is switched off in the live table, so the
        // table alone calls it free. What the recorder asks instead counts the
        // ids the service is holding as macOS's, and falls back to the table
        // for a key it is not holding.
        let areaShot = GlobalShortcut(keyCode: 21, modifiers: [.command, .shift])
        let liveWhileHeld: [LiveSystemShortcut] = [
            LiveSystemShortcut(id: 30, shortcut: areaShot, enabled: false),
            LiveSystemShortcut(id: 28, shortcut: GlobalShortcut(keyCode: 20, modifiers: [.command, .shift]), enabled: true),
        ]
        let areaShotIsMacOS = SystemShortcutTakeoverSupport.conflictsWithMacOS(
            areaShot, liveEntries: liveWhileHeld, symbolicHotKeys: nil, held: [30])
        suite.expect(areaShotIsMacOS
               && !SystemShortcutTakeoverSupport.conflictsWithMacOS(
                   areaShot, liveEntries: liveWhileHeld, symbolicHotKeys: nil, held: [1, 2])
               && SystemShortcutTakeoverSupport.conflictsWithMacOS(
                   GlobalShortcut(keyCode: 20, modifiers: [.command, .shift]),
                   liveEntries: liveWhileHeld, symbolicHotKeys: nil, held: []),
               "a key this app is holding still counts as macOS's, and one it is not holding follows the live table")
        // The switcher's rows may record the native keys the switcher itself holds
        // (main permits them per role); every other row sees them as macOS's.
        let commandTab = GlobalShortcut(keyCode: 48, modifiers: [.command])
        let liveWithSwitcherKey = [LiveSystemShortcut(id: 1, shortcut: commandTab, enabled: false)]
        suite.expect(!SystemShortcutTakeoverSupport.conflictsWithMacOS(
                   commandTab, liveEntries: liveWithSwitcherKey, symbolicHotKeys: nil, held: [1], role: .switcher)
               && SystemShortcutTakeoverSupport.conflictsWithMacOS(
                   commandTab, liveEntries: liveWithSwitcherKey, symbolicHotKeys: nil, held: [1], role: nil),
               "the switcher's own row may record the native key it is holding; any other row sees it as macOS's")
        // The recorder's one rule for a combination macOS answers: ask unless the
        // user already agreed to exactly this key on this row; tidy the entry
        // once the row moves to a key macOS does not want.
        suite.expect(SystemShortcutTakeoverSupport.recorderDecision(shortcut: areaShot, conflictsWithMacOS: true,
                                                              takenOver: false, current: .screenshotDefault) == .offer
               && SystemShortcutTakeoverSupport.recorderDecision(shortcut: areaShot,
                                                                 conflictsWithMacOS: areaShotIsMacOS,
                                                                 takenOver: true, current: areaShot) == .save(clearTakeOver: false)
               && SystemShortcutTakeoverSupport.recorderDecision(shortcut: GlobalShortcut(keyCode: 49, modifiers: [.command]),
                                                                 conflictsWithMacOS: true, takenOver: true, current: areaShot) == .offer
               && SystemShortcutTakeoverSupport.recorderDecision(shortcut: areaShot, conflictsWithMacOS: true,
                                                                 takenOver: true, current: nil) == .offer
               && SystemShortcutTakeoverSupport.recorderDecision(shortcut: .screenshotDefault, conflictsWithMacOS: false,
                                                                 takenOver: true, current: areaShot) == .save(clearTakeOver: true),
               "a taken-over row re-records its own key silently, is asked again for any other macOS key or when no key is recorded, and forgets the take-over when it leaves macOS keys")
        suite.expect(GlobalShortcutRole.allCases.filter { !$0.supportsTakeOver } == [.switcher, .switcherWindow, .radialMenu]
               && GlobalShortcutRole.keepAwake.supportsTakeOver && GlobalShortcutRole.finderRename.supportsTakeOver,
               "only the rows whose key a feature claims may offer to take a macOS shortcut over")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.systemShortcutTakeOverKeys)
               && registeredDefaults[DefaultsKey.systemShortcutTakeOverKeys] == nil,
               "which shortcuts to take over is a preference that travels with a settings backup")
        suite.expect(SwitcherSupport.isCurrentActivationGeneration(12, current: 12)
               && !SwitcherSupport.isCurrentActivationGeneration(11, current: 12),
               "App Switcher ignores retries left by an older activation")
        suite.expect(SwitcherSupport.shouldRestoreHiddenApp(revealGeneration: 12,
                                                      currentGeneration: 12,
                                                      appWasReactivated: false)
               && !SwitcherSupport.shouldRestoreHiddenApp(revealGeneration: 12,
                                                           currentGeneration: 13,
                                                           appWasReactivated: false)
               && !SwitcherSupport.shouldRestoreHiddenApp(revealGeneration: 12,
                                                           currentGeneration: 12,
                                                           appWasReactivated: true),
               "closing a hidden window restores hiding only before a later activation of that app")
        suite.expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 10,
                                                                 ownPID: 99),
               "App Switcher keeps the minimize observer when the target app remains active")
        suite.expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 20,
                                                                 ownPID: 99),
               "App Switcher keeps the minimize observer when the source app is staged behind the target")
        suite.expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 99,
                                                                 ownPID: 99),
               "App Switcher keeps the minimize observer through its own activation handoff")
        suite.expect(!SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                  sourcePID: 20,
                                                                  activatedPID: 30,
                                                                  ownPID: 99),
               "App Switcher cancels the minimize observer when the user moves to a third app")
        suite.expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 30,
                                                                 ownPID: 99,
                                                                 activatedMatchesTargetBundle: true),
               "App Switcher keeps the minimize observer when a sibling app instance activates")
        let switcherCloseSelected = SwitcherSupport.closeState(afterRemoving: "b",
                                                               itemIDs: ["a", "b", "c"],
                                                               selectedIndex: 1)
        suite.expect(switcherCloseSelected.remainingItemIDs == ["a", "c"]
               && switcherCloseSelected.selectedIndex == 1
               && !switcherCloseSelected.shouldEndSession,
               "App Switcher close selects the next window after closing the selected one")
        let switcherCloseBeforeSelection = SwitcherSupport.closeState(afterRemoving: "a",
                                                                      itemIDs: ["a", "b", "c"],
                                                                      selectedIndex: 2)
        suite.expect(switcherCloseBeforeSelection.remainingItemIDs == ["b", "c"]
               && switcherCloseBeforeSelection.selectedIndex == 1,
               "App Switcher close preserves the same logical selection after removing an earlier window")
        let switcherCloseLast = SwitcherSupport.closeState(afterRemoving: "only",
                                                           itemIDs: ["only"],
                                                           selectedIndex: 0)
        suite.expect(switcherCloseLast.didRemove
               && switcherCloseLast.shouldEndSession
               && switcherCloseLast.remainingItemIDs.isEmpty,
               "App Switcher close ends the session after the last item is removed")
        let switcherCloseMissing = SwitcherSupport.closeState(afterRemoving: "missing",
                                                              itemIDs: ["a", "b"],
                                                              selectedIndex: 1)
        suite.expect(!switcherCloseMissing.didRemove
               && switcherCloseMissing.remainingItemIDs == ["a", "b"]
               && switcherCloseMissing.selectedIndex == 1,
               "App Switcher close leaves selection intact when the item is not present")
        suite.expect(SwitcherSupport.commitTargetID(itemIDs: ["a", "b", "c"],
                                              selectedIndex: 1,
                                              closingItemIDs: []) == "b",
               "App Switcher release activates the highlighted window")
        suite.expect(SwitcherSupport.commitTargetID(itemIDs: ["a", "b", "c"],
                                              selectedIndex: 1,
                                              closingItemIDs: ["b"]) == "c",
               "App Switcher release skips the window that is closing")
        suite.expect(SwitcherSupport.commitTargetID(itemIDs: ["a", "b", "c"],
                                              selectedIndex: 2,
                                              closingItemIDs: ["b", "c"]) == "a",
               "App Switcher release falls back to the last window left when several are closing")
        suite.expect(SwitcherSupport.commitTargetID(itemIDs: ["a", "b"],
                                              selectedIndex: 1,
                                              closingItemIDs: ["a", "b"]) == nil,
               "App Switcher release activates nothing when every window is closing")
        suite.expect(SwitcherSupport.commitTargetID(itemIDs: [],
                                              selectedIndex: 0,
                                              closingItemIDs: []) == nil,
               "App Switcher release activates nothing with an empty list")
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "w", keyCode: 13, pinSearchEnabled: false) == .closeWindow
               && SwitcherSupport.letterAction(typedCharacter: "q", keyCode: 12, pinSearchEnabled: false) == .quitApp,
               "App Switcher panel closes a window with W and quits an app with Q")
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "W", keyCode: 13, pinSearchEnabled: false) == .closeWindow,
               "App Switcher panel treats the letter the same in either case")
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "e", keyCode: 14, pinSearchEnabled: false) == nil
               && SwitcherSupport.letterAction(typedCharacter: "1", keyCode: 18, pinSearchEnabled: false) == nil,
               "App Switcher panel leaves every other key to the search field")
        // A French keyboard types z where the US one types w, and its own w
        // sits on another key: both answer by the letter, not the position.
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "z", keyCode: 13, pinSearchEnabled: false) == nil
               && SwitcherSupport.letterAction(typedCharacter: "w", keyCode: 6, pinSearchEnabled: false) == .closeWindow,
               "App Switcher panel follows the letters printed on the keyboard")
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "a", keyCode: 12, pinSearchEnabled: false) == nil
               && SwitcherSupport.letterAction(typedCharacter: "q", keyCode: 0, pinSearchEnabled: false) == .quitApp,
               "App Switcher panel quits from the Q key wherever the layout puts it")
        // Cyrillic and Greek type no Latin letter at all, so the key position
        // stands in, the same place macOS puts their command shortcuts.
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "ц", keyCode: 13, pinSearchEnabled: false) == .closeWindow
               && SwitcherSupport.letterAction(typedCharacter: "й", keyCode: 12, pinSearchEnabled: false) == .quitApp,
               "App Switcher panel falls back to the key position on non-Latin layouts")
        suite.expect(SwitcherSupport.letterAction(typedCharacter: nil, keyCode: 13, pinSearchEnabled: false) == .closeWindow
               && SwitcherSupport.letterAction(typedCharacter: "", keyCode: 12, pinSearchEnabled: false) == .quitApp,
               "App Switcher panel falls back to the key position when a key types nothing")
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "ç", keyCode: 13, pinSearchEnabled: false) == nil,
               "App Switcher panel counts an accented letter as a letter of its own")
        // S only pins the search field once the opt-in preference is on, so
        // existing users who search by typing "s" first see no change.
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "s", keyCode: 1, pinSearchEnabled: false) == nil
               && SwitcherSupport.letterAction(typedCharacter: "ß", keyCode: 1, pinSearchEnabled: false) == nil,
               "App Switcher panel leaves S to the search field when the pin preference is off")
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "s", keyCode: 1, pinSearchEnabled: true) == .pinSearch
               && SwitcherSupport.letterAction(typedCharacter: "ß", keyCode: 1, pinSearchEnabled: true) == .pinSearch,
               "App Switcher panel pins the search field from S once the preference is on, even when the modifier turns it into a special character")
        // Caps Lock alongside the session's ⌥ turns S into "Í" instead of "ß" —
        // an accented letter that folds cleanly to "i", an unrelated letter, so
        // the pin must still fire from the key's position (issue: ⌥S + Caps Lock).
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "Í", keyCode: 1, pinSearchEnabled: true) == .pinSearch,
               "App Switcher panel pins the search field from S even when Caps Lock folds it to an unrelated letter")
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "Í", keyCode: 1, pinSearchEnabled: false) == nil,
               "App Switcher panel leaves S to the search field when the pin preference is off, even under Caps Lock")
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "o", keyCode: 1, pinSearchEnabled: true) == nil,
               "App Switcher panel follows a remapped Latin letter instead of the physical S position")
        suite.expect(SwitcherSupport.letterAction(typedCharacter: "ы", keyCode: 1, pinSearchEnabled: true) == .pinSearch,
               "App Switcher panel falls back to the physical S position on a non-Latin layout")
        let switcherPanelFrame = CGRect(x: 400, y: 300, width: 600, height: 400)
        suite.expect(SwitcherSupport.shouldDismissForClick(panelIsVisible: true,
                                                     panelFrame: switcherPanelFrame,
                                                     location: CGPoint(x: 200, y: 200)),
               "App Switcher cancels synchronously when a mouse-down starts outside it")
        suite.expect(!SwitcherSupport.shouldDismissForClick(panelIsVisible: true,
                                                      panelFrame: switcherPanelFrame,
                                                      location: CGPoint(x: 700, y: 500)),
               "App Switcher panel stays for a click on one of its windows")
        suite.expect(!SwitcherSupport.shouldDismissForClick(panelIsVisible: true,
                                                      panelFrame: switcherPanelFrame,
                                                      location: CGPoint(x: 401, y: 301)),
               "App Switcher panel counts its own edge as part of it")
        suite.expect(!SwitcherSupport.shouldDismissForClick(panelIsVisible: false,
                                                      panelFrame: switcherPanelFrame,
                                                      location: CGPoint(x: 200, y: 200)),
               "App Switcher ignores clicks while a quick switch shows no panel")
        suite.expect(SwitcherSupport.isMiddleClickInsidePanel(eventType: .otherMouseDown,
                                                        buttonNumber: 2,
                                                        panelIsVisible: true,
                                                        panelFrame: switcherPanelFrame,
                                                        location: CGPoint(x: 700, y: 500),
                                                        itemIsHovered: true),
               "App Switcher detects middle-click on a card to close that window")
        suite.expect(!SwitcherSupport.isMiddleClickInsidePanel(eventType: .otherMouseDown,
                                                         buttonNumber: 2,
                                                         panelIsVisible: true,
                                                         panelFrame: switcherPanelFrame,
                                                         location: CGPoint(x: 700, y: 500),
                                                         itemIsHovered: false),
               "App Switcher leaves middle-click on panel chrome alone")
        suite.expect(!SwitcherSupport.isMiddleClickInsidePanel(eventType: .otherMouseDown,
                                                         buttonNumber: 2,
                                                         panelIsVisible: true,
                                                         panelFrame: switcherPanelFrame,
                                                         location: CGPoint(x: 200, y: 200),
                                                         itemIsHovered: true),
               "App Switcher leaves middle-click outside panel to regular dismissal")
        suite.expect(!SwitcherSupport.isMiddleClickInsidePanel(eventType: .leftMouseDown,
                                                         buttonNumber: 0,
                                                         panelIsVisible: true,
                                                         panelFrame: switcherPanelFrame,
                                                         location: CGPoint(x: 700, y: 500),
                                                         itemIsHovered: true),
               "App Switcher ignores non-middle clicks for direct window close")
        suite.expect(!SwitcherSupport.isMiddleClickInsidePanel(eventType: .otherMouseDown,
                                                         buttonNumber: 3,
                                                         panelIsVisible: true,
                                                         panelFrame: switcherPanelFrame,
                                                         location: CGPoint(x: 700, y: 500),
                                                         itemIsHovered: true),
               "App Switcher ignores extra mouse buttons for direct window close")
        suite.expect(!SwitcherSupport.isMiddleClickInsidePanel(eventType: .otherMouseDown,
                                                         buttonNumber: 2,
                                                         panelIsVisible: false,
                                                         panelFrame: switcherPanelFrame,
                                                         location: CGPoint(x: 700, y: 500),
                                                         itemIsHovered: true),
               "App Switcher ignores middle-click when panel is not visible")
        suite.expect(SwitcherSupport.shouldSwallowMiddleMouseUp(eventType: .otherMouseUp,
                                                          buttonNumber: 2,
                                                          swallowedMouseDown: true),
               "App Switcher swallows the release after closing a card")
        suite.expect(!SwitcherSupport.shouldSwallowMiddleMouseUp(eventType: .otherMouseUp,
                                                           buttonNumber: 2,
                                                           swallowedMouseDown: false),
               "App Switcher leaves unrelated middle-mouse-up events alone")
        let searchRecords = [
            SwitcherSearchRecord(id: "alpha", title: "Inbox", appName: "Alpha"),
            SwitcherSearchRecord(id: "beta", title: "Vorssaint Roadmap", appName: "Beta"),
            SwitcherSearchRecord(id: "gamma", title: "Café notes", appName: "Gamma"),
        ]
        suite.expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "") == ["alpha", "beta", "gamma"],
               "App Switcher search keeps all windows for an empty query")
        suite.expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "beta roadmap") == ["beta"],
               "App Switcher search matches multiple tokens across app name and window title")
        suite.expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "cafe") == ["gamma"],
               "App Switcher search ignores accents")
        suite.expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "missing").isEmpty,
               "App Switcher search can return no matches")
        suite.expect(SwitcherSupport.searchSelectionIndex(itemIDs: ["alpha", "beta"],
                                                    preferredID: "beta",
                                                    previousIndex: 0) == 1,
               "App Switcher search preserves the selected item when it remains visible")
        suite.expect(SwitcherSupport.searchSelectionIndex(itemIDs: ["alpha"],
                                                    preferredID: "beta",
                                                    previousIndex: 2) == 0,
               "App Switcher search falls back to a valid selection")
    }

    private static func switcherFocusRetryChecks(_ suite: TestSuite) {
        func window(_ id: CGWindowID, pid: pid_t = 10, layer: Int = 0,
                    onscreen: Bool = true, alpha: Double = 1) -> [String: Any] {
            [kCGWindowNumber as String: NSNumber(value: id),
             kCGWindowOwnerPID as String: NSNumber(value: pid),
             kCGWindowLayer as String: NSNumber(value: layer),
             kCGWindowIsOnscreen as String: NSNumber(value: onscreen),
             kCGWindowAlpha as String: NSNumber(value: alpha)]
        }
        let snapshot = SwitcherSupport.focusRetryWindowIDs(in: [
            window(101), window(102, onscreen: false), window(103, layer: 8),
            window(104, alpha: 0), window(101), window(900, pid: 20),
            [kCGWindowOwnerPID as String: NSNumber(value: 10)],
            [kCGWindowNumber as String: NSNumber(value: 901)]
        ], ownerPID: 10)
        suite.expect(snapshot == [101, 102, 103, 104],
               "focus snapshots retain offscreen and auxiliary identities without mixing owners")

        let cases: [(String, pid_t?, Set<CGWindowID>, CGWindowID?, Set<CGWindowID>, Bool, Int, Int)] = [
            ("new keyboard window cancels", 10, [101, 500], 500, snapshot, false, 1, 1),
            ("new transparent helper leaves existing keyboard focus alone", 10, [101, 500], 101, snapshot, true, 1, 1),
            ("new helper cannot hide a new focused window behind it", 10, [101, 500, 501], 501, snapshot, false, 1, 1),
            ("existing dialog remains eligible", 10, [103], 103, snapshot, true, 1, 0),
            ("restored offscreen window remains eligible", 10, [102], 102, snapshot, true, 1, 0),
            ("unavailable focus does not treat an auxiliary surface as user intent", 10, [500], nil, snapshot, true, 1, 1),
            ("unavailable window list preserves existing behavior", 10, [], 500, snapshot, true, 1, 0),
            ("unavailable initial snapshot makes no later queries", 10, [500], 500, [], true, 0, 0),
            ("source handoff ignores windows created in the background", 20, [500], 500, snapshot, true, 0, 0),
            ("own app handoff makes no window queries", 99, [500], 500, snapshot, true, 0, 0),
            ("unrelated app cancels before window queries", 30, [500], 500, snapshot, false, 0, 0),
            ("unknown foreground does not infer a new user action", nil, [500], 500, snapshot, true, 0, 0)
        ]
        for (label, frontmost, visible, focused, known, expected, expectedWindowReads, expectedFocusReads) in cases {
            var windowReads = 0
            var focusReads = 0
            func readWindows() -> Set<CGWindowID> { windowReads += 1; return visible }
            func readFocus() -> CGWindowID? { focusReads += 1; return focused }
            let actual = SwitcherSupport.shouldContinueFocusRetry(
                targetPID: 10, sourcePID: 20, frontmostPID: frontmost,
                targetIsMinimized: false, targetStartedMinimized: false,
                knownWindowIDs: known, targetAppWindowIDs: readWindows(),
                targetAppFocusedWindowID: readFocus(), ownPID: 99)
            suite.expect(actual == expected, "focus retry: " + label)
            suite.expect(windowReads == expectedWindowReads && focusReads == expectedFocusReads,
                   "focus retry bounds its queries: " + label)
        }

        let helper = window(500, alpha: 0)
        let withHelper = SwitcherSupport.focusRetryWindowIDs(in: [helper, window(101)], ownerPID: 10)
        let state = SwitcherWindowFocusRetryState(targetWindowID: 101,
                                                  targetStartedMinimized: false,
                                                  knownWindowIDs: snapshot)
        suite.expect(state.shouldContinue(targetPID: 10, sourcePID: 20, frontmostPID: 10,
                                    targetMinimizedState: false, targetAppWindowIDs: withHelper,
                                    targetAppFocusedWindowID: 101, ownPID: 99),
               "a transparent helper does not cancel the fullscreen focus chain")
        suite.expect(!state.shouldContinue(targetPID: 10, sourcePID: 20, frontmostPID: 10,
                                     targetMinimizedState: false, targetAppWindowIDs: [500],
                                     targetAppFocusedWindowID: 500, ownPID: 99),
               "a new focused window cancels the remaining fullscreen passes")
        var lateReads = 0
        func lateWindows() -> Set<CGWindowID> { lateReads += 1; return [102] }
        func lateFocus() -> CGWindowID? { lateReads += 1; return 102 }
        suite.expect(!state.shouldContinue(targetPID: 10, sourcePID: 20, frontmostPID: 10,
                                     targetMinimizedState: false, targetAppWindowIDs: lateWindows(),
                                     targetAppFocusedWindowID: lateFocus(), ownPID: 99),
               "a later pass cannot reclaim focus after the new window closes")
        suite.expect(lateReads == 0, "a cancelled focus chain performs no later window queries")

        for destination in [20, 30, 99, nil] as [pid_t?] {
            for focusResult in [101, nil] as [CGWindowID?] {
                var foreground: pid_t? = 10
                func focusAfterSwitchingAway() -> CGWindowID? {
                    foreground = destination
                    return focusResult
                }
                let pending = SwitcherWindowFocusRetryState(targetWindowID: 101,
                                                            targetStartedMinimized: false,
                                                            knownWindowIDs: snapshot)
                suite.expect(!pending.shouldContinue(targetPID: 10, sourcePID: 20, frontmostPID: foreground,
                                                targetMinimizedState: false, targetAppWindowIDs: [500],
                                                targetAppFocusedWindowID: focusAfterSwitchingAway(), ownPID: 99),
                       "a slow focus query cannot reclaim the app after the user leaves it")
            }
        }

        let partial = SwitcherWindowFocusRetryState(targetWindowID: 101,
                                                    targetStartedMinimized: false,
                                                    knownWindowIDs: [102])
        suite.expect(partial.shouldContinue(targetPID: 10, sourcePID: 20, frontmostPID: 10,
                                      targetMinimizedState: false, targetAppWindowIDs: [101],
                                      targetAppFocusedWindowID: 101, ownPID: 99),
               "the selected target is not new when a partial snapshot missed it")
        let minimized = SwitcherWindowFocusRetryState(targetWindowID: 101,
                                                      targetStartedMinimized: true,
                                                      knownWindowIDs: snapshot)
        suite.expect(minimized.shouldContinue(targetPID: 10, sourcePID: 20, frontmostPID: 20,
                                        targetMinimizedState: true, targetAppWindowIDs: [],
                                        targetAppFocusedWindowID: nil, ownPID: 99),
               "a minimized target can finish its first restoration")
        suite.expect(minimized.shouldContinue(targetPID: 10, sourcePID: 20, frontmostPID: 10,
                                        targetMinimizedState: false, targetAppWindowIDs: [101],
                                        targetAppFocusedWindowID: 101, ownPID: 99),
               "the focus chain observes successful restoration")
        suite.expect(!minimized.shouldContinue(targetPID: 10, sourcePID: 20, frontmostPID: 10,
                                         targetMinimizedState: true, targetAppWindowIDs: [101],
                                         targetAppFocusedWindowID: 101, ownPID: 99),
               "minimizing the restored target cancels remaining passes")
        suite.expect(!minimized.shouldContinue(targetPID: 10, sourcePID: 20, frontmostPID: 10,
                                         targetMinimizedState: false, targetAppWindowIDs: [101],
                                         targetAppFocusedWindowID: 101, ownPID: 99),
               "later restoration cannot restart a cancelled focus chain")
    }
}
