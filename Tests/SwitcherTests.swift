// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Darwin
import Foundation

enum SwitcherTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

        let registeredDefaults = Defaults.registeredDefaults
        expect(registeredDefaults[DefaultsKey.switcherEnabled] as? Bool == true,
               "window switcher is on for clean installs")
        expect(registeredDefaults[DefaultsKey.switcherShortcut] as? String == "command:48",
               "switcher shortcut defaults to Cmd+Tab")
        expect(registeredDefaults[DefaultsKey.switcherWindowShortcut] as? String
               == GlobalShortcut.switcherWindowDefault.storageValue,
               "switcher window shortcut defaults to Cmd+Grave")
        let shortcutSuite = "vorss.tests.switcher.shortcut"
        if let migrationDefaults = UserDefaults(suiteName: shortcutSuite) {
            migrationDefaults.removePersistentDomain(forName: shortcutSuite)
            migrationDefaults.set("control+option+command:50", forKey: DefaultsKey.switcherWindowShortcut)
            Defaults.migrateLegacySwitcherWindowShortcut(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.switcherWindowShortcut)
                   == GlobalShortcut.switcherWindowDefault.storageValue,
                   "switcher window shortcut migrates the accidental Ctrl+Option+Cmd+Grave default back to Cmd+Grave")
            migrationDefaults.removeObject(forKey: DefaultsKey.scrollInverterHorizontalEnabled)
            migrationDefaults.set(true, forKey: DefaultsKey.scrollInverterEnabled)
            Defaults.migrateScrollInverterAxes(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled),
                   "the former combined scroll switch keeps both directions on after updating")
            migrationDefaults.set(false, forKey: DefaultsKey.scrollInverterHorizontalEnabled)
            Defaults.migrateScrollInverterAxes(in: migrationDefaults)
            expect(!migrationDefaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled),
                   "the direction migration preserves a newer horizontal choice")
            migrationDefaults.set("option:50", forKey: DefaultsKey.switcherWindowShortcut)
            Defaults.migrateLegacySwitcherWindowShortcut(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.switcherWindowShortcut) == "option:50",
                   "switcher window shortcut migration preserves real custom shortcuts")
            migrationDefaults.set(30, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(false, forKey: DefaultsKey.keyboardDebounceEnabled)
            migrationDefaults.set("", forKey: DefaultsKey.keyboardDebounceKeyWindows)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs)
                   == Defaults.defaultKeyboardDebounceWindowMs,
                   "keyboard debounce migration updates the old disabled Developer default")
            migrationDefaults.set(10, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(false, forKey: DefaultsKey.keyboardDebounceEnabled)
            migrationDefaults.set("", forKey: DefaultsKey.keyboardDebounceKeyWindows)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs)
                   == Defaults.defaultKeyboardDebounceWindowMs,
                   "keyboard debounce migration updates the old disabled 10 ms default")
            migrationDefaults.set(30, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(true, forKey: DefaultsKey.keyboardDebounceEnabled)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs) == 30,
                   "keyboard debounce migration preserves active user choices")
            migrationDefaults.set(10, forKey: DefaultsKey.keyboardDebounceWindowMs)
            migrationDefaults.set(true, forKey: DefaultsKey.keyboardDebounceEnabled)
            Defaults.migrateLegacyKeyboardDebounceWindow(in: migrationDefaults)
            expect(migrationDefaults.integer(forKey: DefaultsKey.keyboardDebounceWindowMs) == 10,
                   "keyboard debounce migration preserves active 10 ms user choices")
            migrationDefaults.removeObject(forKey: DefaultsKey.panelUtilityOrder)
            Defaults.migrateUtilityOrderForScreenshot(in: migrationDefaults)
            expect(migrationDefaults.object(forKey: DefaultsKey.panelUtilityOrder) == nil,
                   "utility migration leaves a clean default order unpersisted")
            migrationDefaults.set("quickLauncher,cleaner,homebrew",
                                  forKey: DefaultsKey.panelUtilityOrder)
            Defaults.migrateUtilityOrderForScreenshot(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.panelUtilityOrder)
                   == "screenshot,quickLauncher,cleaner,homebrew",
                   "utility migration puts the newly added screenshot first")
            migrationDefaults.set("homebrew,screenshot,cleaner",
                                  forKey: DefaultsKey.panelUtilityOrder)
            Defaults.migrateUtilityOrderForScreenshot(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.panelUtilityOrder)
                   == "homebrew,screenshot,cleaner",
                   "utility migration preserves a screenshot position already chosen")
            migrationDefaults.set(true, forKey: DefaultsKey.screenshotOpenEditorDirectly)
            Defaults.migrateScreenshotOpenEditorDirectly(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.screenshotDefaultAction)
                   == ScreenshotDefaultAction.edit.rawValue
                   && migrationDefaults.bool(forKey: DefaultsKey.screenshotOpenEditorDirectly) == false,
                   "direct-to-editor migrates into the Edit after-capture action")
            migrationDefaults.set(true, forKey: DefaultsKey.screenshotOpenEditorDirectly)
            migrationDefaults.set(ScreenshotDefaultAction.save.rawValue,
                                  forKey: DefaultsKey.screenshotDefaultAction)
            Defaults.migrateScreenshotOpenEditorDirectly(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.screenshotDefaultAction)
                   == ScreenshotDefaultAction.save.rawValue,
                   "direct-to-editor migration never overrides a newer picker choice")
            migrationDefaults.removeObject(forKey: DefaultsKey.screenshotOpenEditorDirectly)
            migrationDefaults.removeObject(forKey: DefaultsKey.screenshotDefaultAction)
            Defaults.migrateScreenshotOpenEditorDirectly(in: migrationDefaults)
            expect(migrationDefaults.object(forKey: DefaultsKey.screenshotDefaultAction) == nil,
                   "a setup that never used direct-to-editor keeps asking after capture")
            migrationDefaults.set(false, forKey: DefaultsKey.switcherShowWindowlessFinder)
            Defaults.migrateSwitcherWindowlessFinder(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.switcherWindowlessApps)
                   == SwitcherWindowlessApps.off.rawValue
                   && migrationDefaults.bool(forKey: DefaultsKey.switcherShowWindowlessFinder),
                   "hiding the windowless desktop app migrates into showing no windowless app at all")
            migrationDefaults.set(SwitcherWindowlessApps.all.rawValue,
                                  forKey: DefaultsKey.switcherWindowlessApps)
            Defaults.migrateSwitcherWindowlessFinder(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.switcherWindowlessApps)
                   == SwitcherWindowlessApps.all.rawValue,
                   "the windowless apps migration runs once and never fights a later choice")
            migrationDefaults.removeObject(forKey: DefaultsKey.switcherShowWindowlessFinder)
            migrationDefaults.removeObject(forKey: DefaultsKey.switcherWindowlessApps)
            migrationDefaults.set(true, forKey: DefaultsKey.switcherShowWindowlessFinder)
            Defaults.migrateSwitcherWindowlessFinder(in: migrationDefaults)
            expect(migrationDefaults.object(forKey: DefaultsKey.switcherWindowlessApps) == nil,
                   "a setup that kept the windowless desktop app is left exactly as it was")

            migrationDefaults.removeObject(
                forKey: DefaultsKey.unifiedScreenCaptureShortcutMigrated)
            migrationDefaults.set(false, forKey: DefaultsKey.screenshotShortcutEnabled)
            migrationDefaults.set(true, forKey: DefaultsKey.recorderShortcutEnabled)
            migrationDefaults.set("control+option:42", forKey: DefaultsKey.recorderShortcut)
            Defaults.migrateUnifiedScreenCaptureShortcut(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
                   && migrationDefaults.string(forKey: DefaultsKey.screenshotShortcut)
                        == "control+option:42"
                   && migrationDefaults.bool(
                        forKey: DefaultsKey.unifiedScreenCaptureShortcutMigrated),
                   "the combined capture shortcut preserves an enabled recording shortcut")
            Defaults.migrateRestoredScreenCaptureShortcuts(in: migrationDefaults)
            expect(!migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
                   && migrationDefaults.bool(forKey: DefaultsKey.recorderShortcutEnabled)
                   && migrationDefaults.bool(
                        forKey: DefaultsKey.restoredScreenCaptureShortcutsMigrated),
                   "restoring dedicated shortcuts removes the duplicate general registration")
            migrationDefaults.set(true, forKey: DefaultsKey.screenshotShortcutEnabled)
            migrationDefaults.set("command:12", forKey: DefaultsKey.recorderShortcut)
            Defaults.migrateUnifiedScreenCaptureShortcut(in: migrationDefaults)
            expect(migrationDefaults.string(forKey: DefaultsKey.screenshotShortcut)
                   == "control+option:42",
                   "the capture shortcut migration runs once and preserves later choices")
            migrationDefaults.removeObject(
                forKey: DefaultsKey.restoredScreenCaptureShortcutsMigrated)
            Defaults.migrateRestoredScreenCaptureShortcuts(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled),
                   "a distinct general capture shortcut stays enabled when dedicated ones return")
            migrationDefaults.set(true, forKey: AppFeature.screenRecorder.availabilityKey)
            migrationDefaults.set(true, forKey: AppFeature.screenOCR.availabilityKey)
            Defaults.migrateOrphanedCaptureShortcut(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.screenOCRShortcutEnabled)
                   && migrationDefaults.string(forKey: DefaultsKey.screenOCRShortcut)
                        == "control+option:42"
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
                   && migrationDefaults.string(forKey: DefaultsKey.recorderShortcut)
                        == "command:12",
                   "an orphaned capture shortcut moves to the first available tool without its own")
            migrationDefaults.set(true, forKey: DefaultsKey.screenshotShortcutEnabled)
            migrationDefaults.set(false, forKey: DefaultsKey.screenOCRShortcutEnabled)
            Defaults.migrateOrphanedCaptureShortcut(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenOCRShortcutEnabled),
                   "the orphaned capture shortcut migration runs once")
            migrationDefaults.removeObject(forKey: DefaultsKey.orphanedCaptureShortcutMigrated)
            migrationDefaults.set(true, forKey: AppFeature.screenshot.availabilityKey)
            Defaults.migrateOrphanedCaptureShortcut(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled)
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenOCRShortcutEnabled)
                   && migrationDefaults.bool(
                        forKey: DefaultsKey.orphanedCaptureShortcutMigrated),
                   "a setup that kept the screenshot tool keeps its capture shortcut untouched")
            migrationDefaults.removeObject(forKey: DefaultsKey.orphanedCaptureShortcutMigrated)
            migrationDefaults.removeObject(forKey: DefaultsKey.screenshotShortcut)
            migrationDefaults.removeObject(forKey: DefaultsKey.screenOCRShortcut)
            migrationDefaults.set(false, forKey: AppFeature.screenshot.availabilityKey)
            Defaults.migrateOrphanedCaptureShortcut(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.screenOCRShortcutEnabled)
                   && migrationDefaults.string(forKey: DefaultsKey.screenOCRShortcut)
                        == GlobalShortcut.screenshotDefault.storageValue
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled),
                   "a never-customized capture combination moves as the default combination")
            migrationDefaults.removeObject(forKey: DefaultsKey.orphanedCaptureShortcutMigrated)
            migrationDefaults.set(true, forKey: DefaultsKey.screenshotShortcutEnabled)
            migrationDefaults.set(false, forKey: DefaultsKey.screenOCRShortcutEnabled)
            migrationDefaults.set(true, forKey: AppFeature.colorPicker.availabilityKey)
            Defaults.migrateOrphanedCaptureShortcut(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.colorPickerShortcutEnabled)
                   && migrationDefaults.string(forKey: DefaultsKey.colorPickerShortcut)
                        == GlobalShortcut.screenshotDefault.storageValue
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenOCRShortcutEnabled)
                   && !migrationDefaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled),
                   "a switched-off but customized shortcut is kept and the next tool takes over")
            migrationDefaults.removePersistentDomain(forName: shortcutSuite)
        } else {
            expect(false, "test suite defaults are available")
        }
        expect(registeredDefaults[DefaultsKey.switcherIconRowMode] as? Bool == false,
               "App Switcher icon-row mode is optional")
        expect(registeredDefaults[DefaultsKey.switcherSimpleMode] as? Bool == false,
               "App Switcher simple mode preserves previews until requested")
        expect(registeredDefaults[DefaultsKey.switcherShowShortcutHints] as? Bool == true
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherShowShortcutHints),
               "App Switcher keeps shortcut hints visible by default and carries the choice in backups")
        expect(registeredDefaults[DefaultsKey.switcherAppearanceDelay] as? Int
               == SwitcherSupport.defaultAppearanceDelayMilliseconds
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherAppearanceDelay),
               "App Switcher keeps the current appearance delay by default and carries the choice in backups")
        expect(SwitcherSupport.appearanceDelayMillisecondsRange
               .contains(SwitcherSupport.defaultAppearanceDelayMilliseconds),
               "the default App Switcher appearance delay is one the slider accepts")
        expect(SwitcherSupport.sanitizedAppearanceDelay(milliseconds: 0) == 0,
               "the App Switcher can appear immediately when requested")
        expect(SwitcherSupport.sanitizedAppearanceDelay(milliseconds: -1)
               == SwitcherSupport.appearanceDelayMillisecondsRange.lowerBound
               && SwitcherSupport.sanitizedAppearanceDelay(milliseconds: 9_000)
               == SwitcherSupport.appearanceDelayMillisecondsRange.upperBound,
               "an App Switcher appearance delay outside the range is clamped to it")
        expectClose(SwitcherSupport.appearanceDelay(milliseconds: 125), 0.125,
                    "the stored App Switcher milliseconds drive the panel timer in seconds")
        expect(SwitcherSupport.usesIconRowLayout(iconRowMode: false, simpleMode: true),
               "App Switcher simple mode always uses the app icon row")
        expect(SwitcherSupport.usesWindowRow(simpleMode: true,
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
        expect(finishSessionParts.count > 1,
               "the App Switcher ordering guard finds the end of finishPendingSession")
        let switcherCode = finishSessionBody
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let scopeAssign = switcherCode.range(of: "sessionScope = pending.scope")
        let startLayout = switcherCode.range(of: "recomputeLayouts(for: list)")
        expect(!finishSessionBody.isEmpty,
               "the App Switcher session-start ordering guard finds finishPendingSession")
        expect(scopeAssign != nil && startLayout != nil
               && scopeAssign!.lowerBound < startLayout!.lowerBound,
               "the App Switcher session scope is assigned before the session-start layout pass")
        // Trimming the list to one display (issue #1391) can drop the window
        // that was in front, and then index 0 is no longer where the session
        // started. The initial selection has to follow what the list holds.
        expect(!switcherCode.contains("hasForegroundItem: source != nil")
               && switcherCode.contains("hasForegroundItem: listedSource != nil"),
               "the App Switcher initial selection follows the window the trimmed list still holds")
        expect(!SwitcherSupport.usesAppGroupsForMainShortcut(iconRowLayout: true,
                                                              windowRow: true)
               && SwitcherSupport.usesAppGroupsForMainShortcut(iconRowLayout: true,
                                                                windowRow: false),
               "App Switcher main shortcut steps through simple window rows without app grouping")
        expect(SwitcherSupport.preservesGroupedWindowsDuringEnumeration(allApps: true,
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
        expect(!SwitcherSupport.capturesPreviews(simpleMode: true),
               "App Switcher simple mode never captures window previews")
        expect(!SwitcherSupport.needsScreenRecording(switcherEnabled: true,
                                                      simpleMode: true,
                                                      dockPreviewEnabled: false),
               "App Switcher simple mode alone does not request Screen Recording")
        expect(SwitcherSupport.needsScreenRecording(switcherEnabled: true,
                                                    simpleMode: false,
                                                    dockPreviewEnabled: false)
               && SwitcherSupport.needsScreenRecording(switcherEnabled: false,
                                                        simpleMode: true,
                                                        dockPreviewEnabled: true),
               "window previews still request Screen Recording where needed")
        expect(SwitcherSupport.shouldPausePreviewCapture(
            frontmostBundleIdentifier: "com.example.focused",
            excludedBundleIdentifiers: ["com.example.focused"]),
               "window preview capture pauses while a chosen app is in front")
        expect(!SwitcherSupport.shouldPausePreviewCapture(
            frontmostBundleIdentifier: "com.example.other",
            excludedBundleIdentifiers: ["com.example.focused"])
               && !SwitcherSupport.shouldPausePreviewCapture(
                   frontmostBundleIdentifier: nil,
                   excludedBundleIdentifiers: ["com.example.focused"]),
               "window preview capture continues away from chosen apps or without a foreground app")
        expect(SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [4], visibleSpaces: [3]),
               "a window whose only Space is not visible is parked on a hidden Space")
        expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [3], visibleSpaces: [3]),
               "a window on the visible Space is not parked")
        expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [], visibleSpaces: [3]),
               "a surface on no Space is a leftover, never a parked window")
        expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [4], visibleSpaces: []),
               "an unreadable visible-Space set never claims a parked window")
        expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [3, 4], visibleSpaces: [3]),
               "a window pinned to several Spaces including a visible one is reachable")
        expect(SpaceHopSupport.isOnFullscreenSpace(windowSpaces: [4, 8], fullscreenSpaces: [8])
               && !SpaceHopSupport.isOnFullscreenSpace(windowSpaces: [4], fullscreenSpaces: [8])
               && !SpaceHopSupport.isOnFullscreenSpace(windowSpaces: [], fullscreenSpaces: [8]),
               "App Switcher identifies fullscreen from Space type instead of window size")
        expect(SpaceHopSupport.isExcludedFromWindowCycle(windowTagsLow: 1 << 18),
               "a window-server surface marked to ignore cycling is excluded from the switcher")
        expect(!SpaceHopSupport.isExcludedFromWindowCycle(windowTagsLow: (1 << 19) | (1 << 22)),
               "other window-server tags do not hide a legitimate cross-Space window")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4, 5]],
                                          visibleSpaces: [3],
                                          target: 5) == 2,
               "space travel counts the presses to the right")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4, 5]],
                                          visibleSpaces: [5],
                                          target: 3) == -2,
               "space travel counts the presses to the left")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4]],
                                          visibleSpaces: [3],
                                          target: 3) == nil,
               "space travel is never suggested toward a visible Space")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4]],
                                          visibleSpaces: [3],
                                          target: 9) == nil,
               "space travel is never suggested toward an unknown Space")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4], [8, 9]],
                                          visibleSpaces: [3, 8],
                                          target: 9) == 1,
               "space travel counts the presses on the target display when multiple displays exist")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [(0...40).map { UInt64($0) }],
                                          visibleSpaces: [0],
                                          target: 40) == nil,
               "space travel refuses hops beyond the press cap")
        expect(SpaceHopSupport.firstStage(appHasWindowOnVisibleSpace: true) == .moveASpace,
               "an app with a window on the visible Space cannot travel by being activated, so the move is asked for right away")
        expect(SpaceHopSupport.firstStage(appHasWindowOnVisibleSpace: false) == .waitForActivationTravel,
               "an app with no window on the visible Space travels on activation, so that travel is waited on")
        expect(SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x840000) == [.maskControl, .maskSecondaryFn],
               "the registered control+function mask replays with both flags")
        expect(SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x20000 | 0x100000) == [.maskShift, .maskCommand],
               "shift and command translate independently")
        expect(SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x80000) == [.maskAlternate],
               "option translates to the alternate flag")
        let regularBundlePaths: [pid_t: String] = [101: "/Applications/Primary.app"]
        expect(SwitcherSupport.embeddedHostPID(
            helperBundlePath: "/Applications/Primary.app/Contents/Frameworks/Window Helper.app",
            regularBundlePaths: regularBundlePaths
        ) == 101,
               "App Switcher associates an embedded window helper with its regular host app")
        expect(SwitcherSupport.embeddedHostPID(
            helperBundlePath: "/Applications/Primary Tools.app/Contents/Helper.app",
            regularBundlePaths: regularBundlePaths
        ) == nil,
               "App Switcher does not associate apps whose paths only share a prefix")
        expect(SwitcherSupport.embeddedHostPID(
            helperBundlePath: "/Applications/Independent Helper.app",
            regularBundlePaths: regularBundlePaths
        ) == nil,
               "App Switcher leaves unrelated accessory apps independent")
        let embeddedHostPIDs: [pid_t: pid_t] = [202: 101, 203: 101, 302: 301]
        expect(SwitcherSupport.accessibilityPIDs(
            regularAppPIDs: Set<pid_t>([101, 301, 999]),
            embeddedHostPIDs: embeddedHostPIDs,
            ownPID: 999,
            filterPID: nil
        ) == Set<pid_t>([101, 202, 203, 301, 302]),
               "App Switcher keeps embedded helpers eligible for Accessibility-only windows")
        expect(SwitcherSupport.accessibilityPIDs(
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
        expect(embeddedWindow.pid == 101
               && embeddedWindow.windowOwnerPID == 202
               && embeddedWindow.previewWindowID == 77,
               "App Switcher keeps regular app identity separate from the window owner")
        let windowlessEntry = SwitcherItem.appOnly(appName: "Primary", pid: 101)
        expect(embeddedWindow.windowLabel(noOpenWindow: "No open window") == "Project"
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
        expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: dockIconBundle,
                                                       resourceName: "chosen-light.png",
                                                       darkMode: true) == darkDockIcon,
               "App Switcher uses the dark sibling of an explicitly declared Dock icon")
        expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: dockIconBundle,
                                                       resourceName: "chosen-light.png",
                                                       darkMode: false) == lightDockIcon,
               "App Switcher keeps the declared Dock icon in its matching appearance")
        expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: dockIconBundle,
                                                       resourceName: "chosen-dark-color.png",
                                                       darkMode: false) == lightDockIcon,
               "App Switcher finds the light sibling when the declared icon is dark")
        let outsideDockIcon = dockIconBundle.appendingPathComponent("outside.png")
        expect(FileManager.default.createFile(atPath: outsideDockIcon.path, contents: Data([2])),
               "the rejected icon exists so confinement is actually exercised")
        try? FileManager.default.createSymbolicLink(
            at: dockIconResources.appendingPathComponent("escape.png"),
            withDestinationURL: outsideDockIcon)
        for unsafeName in ["../../outside.png", outsideDockIcon.path, "escape.png", ".", "", "missing.png"] {
            expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: dockIconBundle,
                                                           resourceName: unsafeName,
                                                           darkMode: true) == nil,
                   "App Switcher rejects an invalid or out-of-resources icon: \(unsafeName)")
        }
        try? FileManager.default.removeItem(at: darkDockIcon)
        expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: dockIconBundle,
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
        expect(SwitcherAppIconCache.declaredDockIconURL(bundleURL: linkedDockIconBundle,
                                                       resourceName: "chosen-light.png",
                                                       darkMode: false) == nil,
               "App Switcher rejects a Resources directory pointing outside its app bundle")
        try? FileManager.default.removeItem(at: dockIconBundle)
        let hiddenSpaceWindow = embeddedWindow.withHiddenSpaceState(true)
        let minimizedHiddenSpaceWindow = hiddenSpaceWindow.withMinimized(true)
        expect(hiddenSpaceWindow.isOnHiddenSpace
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
        expect(hiddenAppWindow.isAppHidden
               && hiddenAppWindow.withMinimized(true).isAppHidden
               && SwitcherItem.appOnly(appName: "Primary", pid: 101,
                                       isAppHidden: true).isAppHidden,
               "App Switcher carries a hidden app's state through every entry shape")
        expect(SwitcherSupport.isConfirmedHiddenAppWindow(appIsHidden: true,
                                                          windowSpaces: [3])
               && !SwitcherSupport.isConfirmedHiddenAppWindow(appIsHidden: false,
                                                              windowSpaces: [3])
               && !SwitcherSupport.isConfirmedHiddenAppWindow(appIsHidden: true,
                                                              windowSpaces: []),
               "App Switcher keeps only hidden-app surfaces assigned to a real desktop")

        // MARK: Stale surfaces without an Accessibility witness (issue #807)

        expect(!SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: true,
                                                             canResolveSpaces: true,
                                                             windowSpacesCount: 0),
               "App Switcher keeps a visible surface even when its app never answered Accessibility")
        expect(!SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: false,
                                                             canResolveSpaces: true,
                                                             windowSpacesCount: 2),
               "App Switcher keeps an off-screen surface the window server parked on a desktop")
        expect(!SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: false,
                                                             canResolveSpaces: true,
                                                             windowSpacesCount: 7),
               "App Switcher keeps an off-screen surface assigned to any desktop, visible or not")
        expect(SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: false,
                                                            canResolveSpaces: true,
                                                            windowSpacesCount: 0),
               "App Switcher drops an off-screen surface that belongs to no desktop at all")
        expect(!SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: true,
                                                             canResolveSpaces: true,
                                                             windowSpacesCount: 0)
               && !SwitcherSupport.unwitnessedSurfaceIsLeftover(isOnScreen: false,
                                                                canResolveSpaces: false,
                                                                windowSpacesCount: 0),
               "App Switcher keeps the old behavior when the desktop queries are unavailable")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow])?.id == embeddedWindow.id,
               "App Switcher can start when the foreground app is represented")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 202,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow])?.id == embeddedWindow.id,
               "App Switcher can start when an embedded helper owns the foreground window")
        let offscreenWindow = SwitcherItem.window(id: 78,
                                                  title: "Archive",
                                                  appName: "Primary",
                                                  pid: 101,
                                                  isOnScreen: false,
                                                  frame: CGRect(x: 20, y: 20, width: 900, height: 600))
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: nil,
                                                 items: [offscreenWindow]) == nil,
               "App Switcher does not treat an old off-screen window as the foreground surface")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: 78,
                                                 items: [offscreenWindow])?.id == offscreenWindow.id,
               "App Switcher accepts an Accessibility-focused window from outside the CG list")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: nil,
                                                 items: [offscreenWindow, embeddedWindow])?.id == embeddedWindow.id,
               "App Switcher chooses the on-screen source over an older window from the same app")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 101,
                                                 focusedWindowID: 78,
                                                 items: [offscreenWindow, embeddedWindow])?.id == offscreenWindow.id,
               "App Switcher gives the exact focused source priority over CG ordering")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 404,
                                                 focusedWindowID: nil,
                                                 items: [.appOnly(appName: "Desktop", pid: 404)])?.id == "a:404",
               "App Switcher accepts its intentional app-only desktop entry")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 303,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow]) == nil,
               "App Switcher reports no foreground window when the app in front owns none")
        expect(SwitcherSupport.needsFocusedWindowLookup(frontmostPID: 101,
                                                        items: [offscreenWindow]),
               "App Switcher resolves the focused window when no foreground window is visible")
        expect(!SwitcherSupport.needsFocusedWindowLookup(frontmostPID: 101,
                                                         items: [embeddedWindow, offscreenWindow]),
               "App Switcher skips focused-window AX lookup for one visible foreground window")
        let secondVisibleWindow = SwitcherItem.window(id: 79,
                                                      title: "Second",
                                                      appName: "Primary",
                                                      pid: 101,
                                                      isOnScreen: true,
                                                      frame: CGRect(x: 40, y: 40,
                                                                    width: 800, height: 500))
        expect(SwitcherSupport.needsFocusedWindowLookup(frontmostPID: 101,
                                                        items: [embeddedWindow, secondVisibleWindow]),
               "App Switcher resolves the focused window for multiple visible foreground windows")
        expect(SwitcherSupport.initialSelectionPosition(pids: [101, 202, 303],
                                                        hasForegroundEntry: true,
                                                        frontmostPID: 101,
                                                        reversed: false) == 1,
               "App Switcher starts one step past the foreground window")
        expect(SwitcherSupport.initialSelectionPosition(pids: [101],
                                                        hasForegroundEntry: true,
                                                        frontmostPID: 101,
                                                        reversed: false) == 0,
               "App Switcher stays on the only entry there is")
        expect(SwitcherSupport.initialSelectionPosition(pids: [101, 202, 303],
                                                        hasForegroundEntry: true,
                                                        frontmostPID: 101,
                                                        reversed: true) == 2,
               "App Switcher starts from the far end when the session opens backward")
        expect(SwitcherSupport.initialSelectionPosition(pids: [202, 303],
                                                        hasForegroundEntry: false,
                                                        frontmostPID: 101,
                                                        reversed: false) == 0,
               "App Switcher opens on the first entry when the app in front has no window (issue #324)")
        expect(SwitcherSupport.initialSelectionPosition(pids: [101, 101, 202],
                                                        hasForegroundEntry: false,
                                                        frontmostPID: 101,
                                                        reversed: false) == 2,
               "App Switcher skips the windows the app in front left minimized or on another Space")
        expect(SwitcherSupport.initialSelectionPosition(pids: [101, 101],
                                                        hasForegroundEntry: false,
                                                        frontmostPID: 101,
                                                        reversed: false) == 0,
               "App Switcher still opens when every window belongs to the app in front")
        expect(SwitcherSupport.initialSelectionPosition(pids: [],
                                                        hasForegroundEntry: false,
                                                        frontmostPID: 101,
                                                        reversed: false) == 0,
               "App Switcher keeps the selection in range with nothing to show")
        expect(SwitcherSupport.appPID(forFrontmost: 202, items: [embeddedWindow]) == 101
               && SwitcherSupport.appPID(forFrontmost: 303, items: [embeddedWindow]) == 303,
               "App Switcher reads the app behind an embedded window helper")
        expect(SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: "/usr/local/bin/wine64-preloader",
            localizedName: "wine64-preloader"),
               "App Switcher recognizes a bare compatibility-layer loader process")
        expect(SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: "/Users/u/Library/Bottles/games/winetemp-8f3a21/Launcher",
            localizedName: "Launcher"),
               "App Switcher recognizes a bottle loader renamed after its hosted program")
        expect(!SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: "com.example.native",
            executablePath: "/Applications/Native.app/Contents/MacOS/wine64-preloader",
            localizedName: "wine64-preloader"),
               "App Switcher never relaxes window rules for bundled apps")
        expect(!SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: "/usr/bin/python3",
            localizedName: "python3"),
               "App Switcher leaves ordinary unbundled processes alone")
        expect(SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: nil,
            localizedName: "wine-preloader"),
               "App Switcher falls back to the process name when the executable is unknown")
        expect(!SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: nil,
            executablePath: nil,
            localizedName: nil),
               "App Switcher requires a positive signal before relaxing window rules")
        expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.AfterEffects.application",
            subrole: "AXFloatingWindow"),
               "App Switcher accepts supported media windows with current bundle suffixes")
        expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.PremierePro.26",
            subrole: "AXFloatingWindow"),
               "App Switcher accepts versioned supported media windows")
        expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.premierepro.2024",
            subrole: "AXFloatingWindow"),
               "App Switcher accepts lowercase supported media bundle identifiers")
        expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.Premiere.15",
            subrole: "AXFloatingWindow"),
               "App Switcher accepts short-form supported media bundle identifiers")
        expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.PremierePro.26",
            subrole: "AXUnknown"),
               "App Switcher accepts undescribed workspace windows from supported media apps")
        expect(SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.mediaencoder.2024",
            subrole: "AXUnknown"),
               "App Switcher accepts helper media engine workspace windows")
        expect(!SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.adobe.AfterEffects.application",
            subrole: "AXDialog"),
               "App Switcher does not relax ordinary dialogs from supported media apps")
        expect(!SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.example.editor",
            subrole: "AXFloatingWindow"),
               "App Switcher keeps floating windows from unrelated apps filtered")
        expect(!SwitcherSupport.isSupportedMediaFloatingWindow(
            bundleIdentifier: "com.example.editor",
            subrole: "AXUnknown"),
               "App Switcher keeps undescribed windows from unrelated apps filtered")
        expect(SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXUnknown",
            fillsScreen: true,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: false),
               "App Switcher accepts a screen-sized window with a nonstandard subrole")
        expect(SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXFloatingWindow",
            fillsScreen: true,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: false),
               "App Switcher accepts a screen-sized floating playback surface")
        expect(!SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXUnknown",
            fillsScreen: false,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: false),
               "App Switcher filters a smaller window with a nonstandard subrole")
        expect(!SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXGroup",
            subrole: "AXUnknown",
            fillsScreen: true,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: false),
               "App Switcher requires a real window role for a full-screen surface")
        expect(!SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXDialog",
            fillsScreen: true,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: false),
               "App Switcher does not turn a screen-sized dialog into a playback window")
        expect(SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXUnknown",
            fillsScreen: false,
            hasNormalWindowLevel: false,
            acceptsUndescribedSubroles: true),
               "App Switcher preserves hosted windows with custom chrome")
        expect(SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXUnknown",
            fillsScreen: false,
            hasNormalWindowLevel: true,
            acceptsUndescribedSubroles: false),
               "App Switcher accepts an ordinary window from an app that describes none")
        expect(!SwitcherSupport.isSwitchableNonstandardWindow(
            role: "AXWindow",
            subrole: "AXFloatingWindow",
            fillsScreen: false,
            hasNormalWindowLevel: true,
            acceptsUndescribedSubroles: false),
               "App Switcher keeps a described floating panel filtered at the normal window level")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: nil,
                                                 focusedWindowID: nil,
                                                 items: [embeddedWindow]) == nil,
               "App Switcher leaves the system shortcut alone without a foreground app")
        expect(registeredDefaults[DefaultsKey.switcherShowWindowlessFinder] as? Bool == true,
               "the retired windowless Finder toggle keeps its shipped value so the migration can read it")
        expect(registeredDefaults[DefaultsKey.switcherWindowlessApps] as? String
               == SwitcherWindowlessApps.finder.rawValue,
               "the switcher offers the desktop app without windows, and nothing else, by default")
        expect((registeredDefaults[DefaultsKey.switcherAppRules] as? [String: String])?.isEmpty == true,
               "per-app switcher rules start empty, so existing choices stay unchanged")
        expect(registeredDefaults[DefaultsKey.switcherCurrentSpaceOnly] as? Bool == false,
               "the switcher keeps showing every desktop unless the user opts out (issue #337)")
        expect(registeredDefaults[DefaultsKey.switcherTakeOverSystemShortcuts] as? Bool == false
               && SettingsBackupSupport.exportKeys().contains(
                    DefaultsKey.switcherTakeOverSystemShortcuts)
               && registeredDefaults[DefaultsKey.switcherNativeHotkeysSuppressed] == nil
               && !SettingsBackupSupport.exportKeys().contains(
                    DefaultsKey.switcherNativeHotkeysSuppressed)
               && registeredDefaults[DefaultsKey.systemShortcutsSuppressed] == nil
               && !SettingsBackupSupport.exportKeys().contains(
                    DefaultsKey.systemShortcutsSuppressed),
               "native shortcut takeover is opt-in while both crash markers stay on this Mac")
        expect(registeredDefaults[DefaultsKey.switcherSearchPinEnabled] as? Bool == false
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherSearchPinEnabled),
               "the optional pinned search starts off and travels with the user's settings backup")
        expect(registeredDefaults[DefaultsKey.switcherMinimizedPlacement] as? String
               == WindowSwitchMinimizedPlacement.normal.rawValue
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherMinimizedPlacement),
               "App Switcher leaves minimized windows in normal order by default and carries the choice in backups")
        expect(registeredDefaults[DefaultsKey.switcherShowFullscreenWindows] as? Bool == true
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherShowFullscreenWindows),
               "App Switcher keeps fullscreen windows visible by default and carries the choice in backups")
        expect(WindowSwitchMinimizedPlacement.allCases.map(\.rawValue) == ["normal", "end", "hidden"],
               "every minimized placement case has a stable raw value")

        // MARK: Which display the switcher opens on
        expect(registeredDefaults[DefaultsKey.switcherScreenPlacement] as? String
               == SwitcherScreenPlacement.pointer.rawValue
               && SettingsBackupSupport.exportKeys().contains(DefaultsKey.switcherScreenPlacement),
               "App Switcher keeps opening on the pointer's screen by default and carries the choice in backups")
        expect(SwitcherScreenPlacement.placement(storedValue: nil) == .pointer
               && SwitcherScreenPlacement.placement(storedValue: "") == .pointer
               && SwitcherScreenPlacement.placement(storedValue: "bogus") == .pointer,
               "an unset or unreadable screen placement falls back to the pointer's screen")
        expect(SwitcherScreenPlacement.allCases.map(\.rawValue) == ["pointer", "menuBar", "activeWindow"]
               && SwitcherScreenPlacement.allCases.allSatisfy {
                   SwitcherScreenPlacement.placement(storedValue: $0.rawValue) == $0
               },
               "every screen placement choice has a stable raw value that survives preferences")
        let leftDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rightDisplay = CGRect(x: 1920, y: 0, width: 1440, height: 900)
        expect(SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 2000, y: 100, width: 800, height: 600),
                                            displayBounds: [leftDisplay, rightDisplay]) == 1,
               "a window inside one display resolves to that display")
        expect(SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 1500, y: 100, width: 1000, height: 600),
                                            displayBounds: [leftDisplay, rightDisplay]) == 1
               && SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 1500, y: 100, width: 700, height: 600),
                                               displayBounds: [leftDisplay, rightDisplay]) == 0,
               "a window straddling two displays belongs to the one showing more of it, whichever comes first")
        // Window-server coordinates grow downward, so a display below the
        // menu bar display has a positive y origin. An AppKit frame for the
        // same window would carry a negative y and land on the wrong display.
        let upperDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let lowerDisplay = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        expect(SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 200, y: 1300, width: 800, height: 600),
                                            displayBounds: [upperDisplay, lowerDisplay]) == 1
               && SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 200, y: -800, width: 800, height: 600),
                                               displayBounds: [upperDisplay, lowerDisplay]) == nil,
               "stacked displays resolve by window-server y, and a bottom-left-origin frame would touch no display")
        expect(SwitcherSupport.displayIndex(showingMostOf: CGRect(x: 5000, y: 100, width: 800, height: 600),
                                            displayBounds: [leftDisplay, rightDisplay]) == nil
               && SwitcherSupport.displayIndex(showingMostOf: .zero, displayBounds: [leftDisplay, rightDisplay]) == nil
               && SwitcherSupport.displayIndex(showingMostOf: leftDisplay, displayBounds: []) == nil,
               "a window touching no display, an entry without a frame, or no display at all leave the screen to the fallback")

        // MARK: The switcher list held to one display (issue #1391)
        expect(registeredDefaults[DefaultsKey.switcherCurrentDisplayOnly] as? Bool == false
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
        expect(SwitcherSupport.itemsOnDisplay([onLeftDisplay, onRightDisplay],
                                              displayBounds: bothDisplays,
                                              targetIndex: 1).map(\.id) == ["right"],
               "holding the switcher to one display drops what the other monitor is showing")
        expect(SwitcherSupport.itemsOnDisplay([onLeftDisplay, onRightDisplay, withoutWindow, onNoDisplay],
                                              displayBounds: bothDisplays,
                                              targetIndex: 0).map(\.id) == ["left"],
               "display filtering excludes windowless apps and windows outside every display")
        expect(SwitcherSupport.itemsOnDisplay([onLeftDisplay, onRightDisplay],
                                              displayBounds: bothDisplays,
                                              targetIndex: 5).isEmpty
               && SwitcherSupport.itemsOnDisplay([onLeftDisplay, onRightDisplay],
                                                 displayBounds: [],
                                                 targetIndex: 0).isEmpty,
               "a missing display never falls back to windows on other monitors")

        expect(SwitcherSupport.itemsOnDisplay([onLeftDisplay, withoutWindow, onNoDisplay],
                                              displayBounds: bothDisplays,
                                              targetIndex: 1).isEmpty,
               "an empty monitor has no switch targets, including windowless apps")
        let displayFilterBody = (switcherSource.components(separatedBy: "private var currentDisplayScope")
            .last ?? "").components(separatedBy: "private var placementVisibleFrame").first ?? ""
        expect(displayFilterBody.contains("NSScreen.withMouse?.displayID")
               && displayFilterBody.contains("?? -1"),
               "display filtering follows the cursor and leaves no target when the display disappears")
        expect(switcherCode.contains("guard !windows.isEmpty else {\n            discardPendingSessionStart(generation: generation)"),
               "an empty display discards the pending session before opening a panel or committing a window")
        let otherScreenRepresentative = SwitcherSupport.groupWindowsByApp([onLeftDisplay, onRightDisplay])
        expect(SwitcherSupport.itemsOnDisplay(otherScreenRepresentative,
                                               displayBounds: bothDisplays, targetIndex: 1).isEmpty,
               "regression fixture reproduces a local window lost when grouping precedes display filtering")
        let localWindows = SwitcherSupport.itemsOnDisplay([onLeftDisplay, onRightDisplay],
                                                          displayBounds: bothDisplays, targetIndex: 1)
        expect(SwitcherSupport.groupWindowsByApp(localWindows).map(\.id) == ["right"],
               "grouping after display filtering retains the same app's window on the target monitor")
        let crowdedOtherDisplay = Array(repeating: onLeftDisplay, count: 24) + [onRightDisplay]
        expect(Array(SwitcherSupport.itemsOnDisplay(crowdedOtherDisplay,
                                                    displayBounds: bothDisplays, targetIndex: 1)
            .prefix(24)).map(\.id) == ["right"],
               "windows on other monitors cannot exhaust the local display's entry limit")
        let enumeratorCode = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Switcher/WindowEnumerator.swift",
            encoding: .utf8)) ?? ""
        let displayFilter = enumeratorCode.range(of: "SwitcherSupport.itemsOnDisplay(filtered,")
        let grouping = enumeratorCode.range(of: "SwitcherSupport.groupWindowsByApp(orderedPrimary)")
        let entryCap = enumeratorCode.range(of: "ordered.prefix(maximumCount)")
        expect(displayFilter != nil && grouping != nil && entryCap != nil
               && displayFilter!.lowerBound < grouping!.lowerBound
               && displayFilter!.lowerBound < entryCap!.lowerBound,
               "enumeration applies the display scope before grouping and capping the list")
        expect(SwitcherSupport.sessionSourceItem(frontmostPID: 1, focusedWindowID: 1,
                                                 items: [onLeftDisplay, onRightDisplay])?.id == "left"
               && !localWindows.contains(where: { $0.id == "left" })
               && switcherCode.contains("items: sourceItems)")
               && enumeratorCode.contains("sourceItems: sourceItems ?? result"),
               "activation retains the foreground window even when the displayed list excludes its monitor")
        let displaySnapshot = switcherSource.range(of: "let displayScope = currentDisplayScope")
        let enumerationDispatch = switcherSource.range(of: "enumerationQueue.async")
        expect(displaySnapshot != nil && enumerationDispatch != nil
               && displaySnapshot!.lowerBound < enumerationDispatch!.lowerBound,
               "the target display is captured before window enumeration can delay the session")

        // MARK: Switcher entries for apps with no window (issue #351)
        expect(SwitcherWindowlessApps.mode(storedValue: nil,
                                           takeOverSystemShortcuts: false) == .finder
               && SwitcherWindowlessApps.mode(storedValue: "",
                                              takeOverSystemShortcuts: false) == .finder
               && SwitcherWindowlessApps.mode(storedValue: "bogus",
                                              takeOverSystemShortcuts: false) == .finder,
               "an unset or unreadable windowless apps choice falls back to what the app shipped with")
        expect(SwitcherWindowlessApps.mode(storedValue: "off",
                                           takeOverSystemShortcuts: false) == .off
               && SwitcherWindowlessApps.mode(storedValue: "finder",
                                              takeOverSystemShortcuts: false) == .finder
               && SwitcherWindowlessApps.mode(storedValue: "all",
                                              takeOverSystemShortcuts: false) == .all,
               "every windowless apps choice survives a round trip through preferences")
        expect(SwitcherWindowlessApps.mode(storedValue: "off",
                                           takeOverSystemShortcuts: true) == .all,
               "native shortcut takeover keeps every running app reachable")
        expect(SwitcherWindowlessApps.migrated(showsWindowlessFinder: true) == .finder
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
        expect(sanitizedAppRules == [
            "com.example.editor": .showWithoutWindows,
            "com.example.notes": .hidden,
        ], "per-app switcher rules trim identities and drop unreadable entries")
        expect(SwitcherAppRule.storedValue(sanitizedAppRules) == [
            "com.example.editor": SwitcherAppRule.showWithoutWindows.rawValue,
            "com.example.notes": SwitcherAppRule.hidden.rawValue,
        ], "per-app switcher rules keep only portable bundle identities and known choices")
        expect(SwitcherSupport.windowlessAppPIDs(mode: .off,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [],
                                                 pidsWithWithheldWindows: [],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier).isEmpty,
               "asking for no windowless apps adds none of them")
        expect(SwitcherSupport.windowlessAppPIDs(mode: .finder,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [],
                                                 pidsWithWithheldWindows: [],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier) == [501],
               "asking for the desktop app alone leaves every other windowless app out")
        expect(SwitcherSupport.windowlessAppPIDs(mode: .all,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [],
                                                 pidsWithWithheldWindows: [],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier) == [501, 502, 503],
               "asking for every windowless app keeps them in the order the window server gave")
        expect(SwitcherSupport.windowlessAppPIDs(mode: .all,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [502],
                                                 pidsWithWithheldWindows: [],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier) == [501, 503],
               "an app that already has a window in the list never gets a second entry for itself")
        expect(SwitcherSupport.windowlessAppPIDs(mode: .all,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [],
                                                 pidsWithWithheldWindows: [503],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier) == [501, 502],
               "an app whose windows were held back for being on another desktop stays out (issue #337)")
        expect(SwitcherSupport.windowlessAppPIDs(mode: .finder,
                                                 candidates: windowlessCandidates,
                                                 pidsWithWindows: [501],
                                                 pidsWithWithheldWindows: [],
                                                 desktopAppBundleIdentifier: Defaults.finderBundleIdentifier).isEmpty,
               "the desktop app with a window of its own does not also get an entry for itself")
        expect(SwitcherSupport.windowlessAppPIDs(
                mode: .off,
                candidates: windowlessCandidates,
                pidsWithWindows: [],
                pidsWithWithheldWindows: [],
                desktopAppBundleIdentifier: Defaults.finderBundleIdentifier,
                appRules: ["com.example.editor": .showWithoutWindows]) == [502],
               "an app rule can add one windowless app without turning the global list on")
        expect(SwitcherSupport.windowlessAppPIDs(
                mode: .off,
                candidates: windowlessCandidates,
                pidsWithWindows: [502],
                pidsWithWithheldWindows: [],
                desktopAppBundleIdentifier: Defaults.finderBundleIdentifier,
                appRules: ["com.example.editor": .showWithoutWindows]).isEmpty,
               "an explicit show rule never duplicates an app that already has a window entry")
        expect(SwitcherSupport.windowlessAppPIDs(
                mode: .all,
                candidates: windowlessCandidates,
                pidsWithWindows: [],
                pidsWithWithheldWindows: [],
                desktopAppBundleIdentifier: Defaults.finderBundleIdentifier,
                appRules: ["com.example.editor": .windowsOnly,
                           "com.example.notes": .hidden]) == [501],
               "window-only and hidden rules both keep an app-only entry out of the global list")
        expect(SwitcherSupport.windowlessAppPIDs(
                mode: .off,
                candidates: windowlessCandidates,
                pidsWithWindows: [],
                pidsWithWithheldWindows: [502],
                desktopAppBundleIdentifier: Defaults.finderBundleIdentifier,
                appRules: ["com.example.editor": .showWithoutWindows]).isEmpty,
               "a show rule never restores an app whose windows were withheld on another desktop")
        expect(SwitcherSupport.hidesApp(
                    bundleIdentifier: "com.example.notes",
                    appRules: ["com.example.notes": .hidden])
               && !SwitcherSupport.hidesApp(
                    bundleIdentifier: "com.example.notes",
                    appRules: ["com.example.notes": .windowsOnly])
               && !SwitcherSupport.hidesApp(
                    bundleIdentifier: nil,
                    appRules: ["com.example.notes": .hidden]),
               "only the hidden rule removes an identified app's real windows")

        expect(WindowUseOrder.promoting(target: 7, previous: 3, in: [3, 5, 7]) == [7, 3, 5],
               "committing to a window puts it first and the one left behind second")
        expect(WindowUseOrder.promoting(target: nil, previous: 3, in: [5, 3, 9]) == [3, 5, 9],
               "committing to an app with no window leaves the window behind as the most recent one")
        expect(WindowUseOrder.promoting(target: nil, previous: nil, in: [5, 3]) == [5, 3],
               "committing to an app with no window and coming from none changes no history")
    }

    static func runGroupingAndSearch(expect: (Bool, String) -> Void) {
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let repeatedProcessValues = SwitcherSupport.firstValuesByPID([(pid_t(1678), "first"),
                                                                      (pid_t(1678), "duplicate"),
                                                                      (pid_t(2048), "other")])
        expect(repeatedProcessValues == [1678: "first", 2048: "other"],
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
        expect(appGroups.count == 2
               && appGroups[0].representativeIndex == 0
               && appGroups[0].windowCount == 2
               && appGroups[1].representativeIndex == 2,
               "App Switcher icon-row mode keeps one row entry per app")
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
        expect(expandedCappedApps.count == 26
               && expandedCappedApps.prefix(3).map(\.windowID) == [10, 11, 12]
               && Set(expandedCappedApps.map(\.pid)) == Set((1...24).map { pid_t($0) })
               && !expandedCappedApps.contains { $0.pid == 25 },
               "App Switcher expands every backing window without displacing a capped app")
        expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 0,
                                                     delta: 1) == 2,
               "App Switcher icon-row app navigation skips duplicate windows from the same app")
        expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 2,
                                                     delta: -1) == 0,
               "App Switcher icon-row app navigation wraps backward by app")
        expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 2,
                                                     delta: 1,
                                                     wrapping: false) == 2,
               "held key stops at the last app instead of wrapping, like the system switcher")
        expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 0,
                                                     delta: -1,
                                                     wrapping: false) == 0,
               "held key stops at the first app when navigating backward")
        expect(SwitcherSupport.nextAppSelectionIndex(items: groupedSwitcherItems,
                                                     selectedIndex: 0,
                                                     delta: 1,
                                                     wrapping: false) == 2,
               "non-wrapping navigation still advances while not at the edge")
        expect(SwitcherSupport.nextWindowSelectionIndexWithinApp(items: groupedSwitcherItems,
                                                                 selectedIndex: 0,
                                                                 delta: 1) == 1,
               "App Switcher icon-row window navigation moves within the selected app")
        expect(SwitcherSupport.nextWindowSelectionIndexWithinApp(items: groupedSwitcherItems,
                                                                 selectedIndex: 1,
                                                                 delta: 1) == 0,
               "App Switcher icon-row window navigation wraps within the selected app")
        expect(SwitcherSupport.nextWindowSelectionIndexWithinApp(items: groupedSwitcherItems,
                                                                 selectedIndex: 2,
                                                                 delta: 1) == 2,
               "App Switcher icon-row window navigation stays put when the app has one window")
        expect(SwitcherSupport.iconRowEdgeHoverInterval > SwitcherSupport.iconRowEdgeHoverAnimationDuration
               && SwitcherSupport.iconRowEdgeHoverRepeatInterval >= SwitcherSupport.iconRowEdgeHoverAnimationDuration
               && SwitcherSupport.iconRowEdgeHoverRepeatInterval < SwitcherSupport.iconRowEdgeHoverInterval
               && SwitcherSupport.iconRowEdgeHoverAnimationDuration > 0.15,
               "App Switcher overflow hover waits to start, then steps with the slide")
        expect(SwitcherSupport.clampedIconRowFirstVisibleIndex(itemCount: 12,
                                                              visibleCount: 6,
                                                              firstVisibleIndex: -2) == 0
               && SwitcherSupport.clampedIconRowFirstVisibleIndex(itemCount: 12,
                                                                 visibleCount: 6,
                                                                 firstVisibleIndex: 20) == 6
               && SwitcherSupport.clampedIconRowFirstVisibleIndex(itemCount: 5,
                                                                 visibleCount: 6,
                                                                 firstVisibleIndex: 3) == 0,
               "App Switcher overflow row never scrolls past either end")
        expect(SwitcherSupport.iconRowFirstVisibleIndex(revealing: 8,
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
        expect(SwitcherSupport.iconRowEdgeHoverDelta(hoveredIndex: 5,
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
        expect(SwitcherSupport.iconRowIndexAfterEdgeHoverStep(firstVisibleIndex: 1,
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
        expect(frontmostScoped.count == 2
               && frontmostScoped.allSatisfy { $0.pid == 101 },
               "Window-scoped session keeps only the frontmost app's windows")
        expect(SwitcherSupport.frontmostAppWindows(allItems: groupedSwitcherItems,
                                                   frontmostPID: 999).isEmpty,
               "Window-scoped session has no entries when the frontmost app has no windows")
        expect(SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: 3,
                                                                 hasForegroundItem: true,
                                                                 reversed: false) == 1,
               "Window-scoped session starts on the next window when several are open")
        expect(SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: 1,
                                                                 hasForegroundItem: true,
                                                                 reversed: false) == 0,
               "Window-scoped session keeps the lone window selected")
        expect(SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: 3,
                                                                 hasForegroundItem: true,
                                                                 reversed: true) == 2,
               "Window-scoped session starts at the far end when Shift reverses")
        expect(SwitcherSupport.windowNavigationDelta(positionalMatch: true,
                                                      shiftIsNavigationModifier: true,
                                                      shiftHeld: true) == -1,
               "Window shortcut Shift reverses a positional match")
        expect(SwitcherSupport.windowNavigationDelta(positionalMatch: false,
                                                      shiftIsNavigationModifier: true,
                                                      shiftHeld: true) == 1,
               "Window shortcut Shift stays forward when the layout needs it for the character")
        let afterFirstSwitch = WindowUseOrder.promoting(2, previous: 1, in: [])
        expect(afterFirstSwitch == [2, 1],
               "App Switcher use history records the previous window immediately after a switch")
        let afterSecondSwitch = WindowUseOrder.promoting(1, previous: 2, in: afterFirstSwitch)
        expect(afterSecondSwitch == [1, 2],
               "App Switcher use history toggles back after two consecutive switcher uses")

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
        expect(mouseOrder.map(\.windowID) == [13, 12, 11, 10],
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
        expect(sameAppOrder.map(\.windowID) == [21, 22, 20],
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
        expect(unseenOrder.map(\.windowID) == [30, 31, 32, nil],
               "App Switcher places never-focused windows after used ones, by app and then by depth")

        // Cold start: nothing has been used yet, so front-to-back order is the
        // only account of what came last, and it has to be used as one.
        expect(WindowUseOrder.reconciled([], existing: [40, 41, 42], frontToBack: [42, 40, 41])
               == [42, 40, 41],
               "App Switcher seeds its use history from the window server instead of starting arbitrary")
        expect(WindowUseOrder.reconciled([50, 51], existing: [51, 52], frontToBack: [52, 51])
               == [51, 52],
               "App Switcher use history drops closed windows and files new ones behind what was used")
        expect(WindowUseOrder.reconciled([60, 61, 62], existing: [60, 61, 62], frontToBack: [62])
               == [60, 61, 62],
               "App Switcher use history is not reshuffled by the window server once it knows better")
        expect(WindowUseOrder.reconciled([70, 71, 72], existing: [70, 71, 72], frontToBack: [], limit: 2)
               == [70, 71],
               "App Switcher use history stays bounded")
        expect(WindowUseOrder.reconciled([], running: [80, 81, 82], frontToBack: [81, 82, 80])
               == [81, 82, 80],
               "App Switcher seeds its application history from the window server too")
        expect(WindowUseOrder.reconciled([90, 91], running: [91, 92], frontToBack: [92, 91])
               == [91, 92],
               "App Switcher application history drops closed apps and files new ones behind")
        let groupedIconLayout = SwitcherIconRowLayout.compute(appCount: appGroups.count,
                                                              selectedWindowCount: appGroups[0].windowCount,
                                                              screenVisibleFrame: screen)
        expect(groupedIconLayout.appRowContentWidth
               >= CGFloat(appGroups.count) * SwitcherIconRowLayout.appTileWidth,
               "App Switcher icon-row layout uses full app tile width")
        expect(groupedIconLayout.previewContentWidth
               >= CGFloat(appGroups[0].windowCount) * SwitcherIconRowLayout.previewCardWidth,
               "App Switcher icon-row layout reserves room for selected app previews")
        expectClose(Double(groupedIconLayout.appRowSurfaceWidth),
                    Double(groupedIconLayout.appRowContentWidth + SwitcherIconRowLayout.rowHorizontalPadding * 2),
                    "App Switcher icon-row layout keeps horizontal padding inside the app row surface")
        expectClose(Double(groupedIconLayout.previewSurfaceWidth),
                    Double(groupedIconLayout.previewContentWidth + SwitcherIconRowLayout.previewPanelPadding * 2),
                    "App Switcher icon-row layout keeps preview cards away from the surface border")
        let simpleWindowLayout = SwitcherIconRowLayout.compute(
            appCount: groupedSwitcherItems.count,
            selectedWindowCount: 1,
            screenVisibleFrame: screen,
            tileWidth: SwitcherIconRowLayout.windowTileWidth
        )
        expect(simpleWindowLayout.appRowContentWidth
               >= CGFloat(groupedSwitcherItems.count) * SwitcherIconRowLayout.windowTileWidth,
               "App Switcher simple window row gives every window title its own tile width")
        expectClose(Double(simpleWindowLayout.simplePanelSize.height
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
        expect(groupedWindowShortcutLayout.simpleTitleSurfaceWidth
               >= SwitcherIconRowLayout.simpleTitleChipMaxWidth * 2
                    + SwitcherIconRowLayout.simpleTitleSpacing,
               "App Switcher grouped window shortcut leaves both window titles visible")
        expectClose(Double(groupedWindowShortcutLayout.simplePanelSize.width),
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
        expectClose(Double(issue128LeftPlacement.leading),
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
        expectClose(Double(issue128SecondWindowPlacement.leading),
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
        expectClose(Double(issue128CenterPlacement.leading),
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
        expectClose(Double(scrollingPreviewPlacement.leading),
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
        expectClose(Double(scrollingWindowPreviewPlacement.leading), Double(centeredPreviewLeading),
                    "App Switcher icon-row preview stays centered when the window preview row scrolls")
        let singleWindowAppLayout = SwitcherIconRowLayout.compute(appCount: appGroups.count,
                                                                  selectedWindowCount: appGroups[1].windowCount,
                                                                  screenVisibleFrame: screen)
        expect(singleWindowAppLayout.previewContentWidth == SwitcherIconRowLayout.previewCardWidth,
               "App Switcher icon-row layout does not reserve empty preview slots for a one-window app")
        expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: 22,
                                                   windowIDs: [11, 22, 33],
                                                   offset: 1) == 33,
               "Dock Preview next button selects the next window")
        expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: 11,
                                                   windowIDs: [11, 22, 33],
                                                   offset: -1) == 33,
               "Dock Preview previous button wraps from the first window to the last")
        expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: nil,
                                                   windowIDs: [11, 22, 33],
                                                   offset: 1) == 11,
               "Dock Preview next button starts from the first window when none is selected")
        expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: nil,
                                                   windowIDs: [11, 22, 33],
                                                   offset: -1) == 33,
               "Dock Preview previous button starts from the last window when none is selected")
        expect(DockPreviewSupport.adjacentWindowID(selectedWindowID: nil,
                                                   windowIDs: [],
                                                   offset: 1) == nil,
               "Dock Preview navigation handles an empty window list")
        expect(DockPreviewSupport.mouseDownDecision(isVisible: true,
                                                    isPinned: true,
                                                    isInsidePanel: false)
               == DockPreviewMouseDownDecision(shouldEndSession: false),
               "Dock Preview pinned panel ignores outside clicks")
        expect(DockPreviewSupport.mouseDownDecision(isVisible: true,
                                                    isPinned: false,
                                                    isInsidePanel: true)
               == DockPreviewMouseDownDecision(shouldEndSession: false),
               "Dock Preview panel clicks are handled by the panel")
        expect(DockPreviewSupport.mouseDownDecision(isVisible: true,
                                                    isPinned: false,
                                                    isInsidePanel: false)
               == DockPreviewMouseDownDecision(shouldEndSession: true),
               "Dock Preview outside clicks close the panel")
        let closeMiddle = DockPreviewSupport.closeState(afterRemoving: 22,
                                                        windowIDs: [11, 22, 33],
                                                        selectedWindowID: 22)
        expect(closeMiddle.remainingWindowIDs == [11, 33],
               "Dock Preview close removes only the closed window")
        expect(closeMiddle.selectedWindowID == nil,
               "Dock Preview close clears selection for the closed window")
        expect(!closeMiddle.shouldEndSession,
               "Dock Preview close keeps the panel open when other windows remain")
        let closeUnselected = DockPreviewSupport.closeState(afterRemoving: 22,
                                                            windowIDs: [11, 22, 33],
                                                            selectedWindowID: 11)
        expect(closeUnselected.selectedWindowID == 11,
               "Dock Preview close preserves selection for other windows")
        let closeLast = DockPreviewSupport.closeState(afterRemoving: 44,
                                                      windowIDs: [44],
                                                      selectedWindowID: 44)
        expect(closeLast.shouldEndSession && closeLast.remainingWindowIDs.isEmpty,
               "Dock Preview close ends the panel when the last window is removed")
        let dockPreviewWindow = SwitcherItem.window(id: 77,
                                                    title: "Preview",
                                                    appName: "Demo",
                                                    pid: 123,
                                                    isOnScreen: true,
                                                    frame: CGRect(x: 10, y: 20, width: 300, height: 200))
        let minimizedDockPreviewWindow = dockPreviewWindow.withMinimized(true)
        expect(minimizedDockPreviewWindow.id == dockPreviewWindow.id
               && minimizedDockPreviewWindow.windowID == dockPreviewWindow.windowID
               && minimizedDockPreviewWindow.isMinimized
               && !minimizedDockPreviewWindow.isOnScreen,
               "Dock Preview minimize state keeps the same window identity")
        let restoredDockPreviewWindow = minimizedDockPreviewWindow.withMinimized(false)
        expect(restoredDockPreviewWindow.id == dockPreviewWindow.id
               && !restoredDockPreviewWindow.isMinimized
               && restoredDockPreviewWindow.isOnScreen,
               "Dock Preview restore clears the minimized state without changing identity")
        expect(SwitcherSupport.activationPlan(targetsSpecificWindow: true)
               == SwitcherActivationPlan(activateAllWindows: false,
                                         makeAppFrontmostAfterActivation: false,
                                         restoreSourceWhenTargetMinimizes: true),
               "App Switcher keeps specific-window activation scoped to one window")
        expect(SwitcherSupport.activationPlan(targetsSpecificWindow: false)
               == SwitcherActivationPlan(activateAllWindows: true,
                                         makeAppFrontmostAfterActivation: true,
                                         restoreSourceWhenTargetMinimizes: false),
               "App Switcher can activate the full app for app-only entries")
        expect(!SwitcherSupport.shouldActivateAllWindows(targetsSpecificWindow: true),
               "App Switcher activates only the selected window when a window target exists")
        expect(SwitcherSupport.shouldActivateAllWindows(targetsSpecificWindow: false),
               "App Switcher can activate the full app for app-only entries")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                      sourcePID: 20,
                                                                      frontmostPID: 10,
                                                                      targetIsMinimized: true,
                                                                      ownPID: 99),
               "App Switcher restores the previous app when a specific target window is minimized")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                       sourcePID: 10,
                                                                       frontmostPID: 10,
                                                                       targetIsMinimized: true,
                                                                       ownPID: 99),
               "App Switcher does not restore when the source is another window from the same app")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                       sourcePID: 20,
                                                                       frontmostPID: 30,
                                                                       targetIsMinimized: true,
                                                                       ownPID: 99),
               "App Switcher does not steal focus if the user already moved to another app")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                      sourcePID: 20,
                                                                      frontmostPID: 30,
                                                                      targetIsMinimized: true,
                                                                      ownPID: 99,
                                                                      frontmostMatchesTargetBundle: true),
               "App Switcher restores the previous app if a sibling app instance is promoted after minimize")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                      sourcePID: 20,
                                                                      frontmostPID: 30,
                                                                      targetIsMinimized: true,
                                                                      ownPID: 99,
                                                                      frontmostCanBeSystemPromotion: true),
               "App Switcher restores the previous app if the system promotes another window during minimize")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: 10,
                                                                       sourcePID: 20,
                                                                       frontmostPID: 10,
                                                                       targetIsMinimized: false,
                                                                       ownPID: 99),
               "App Switcher restores the previous app only after the target window is minimized")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 10,
                                                                            focusedWindowID: 44,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: true,
                                                                            ownPID: 99),
               "App Switcher restores the source after a minimize-button intent once the target is minimized")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 10,
                                                                            focusedWindowID: 55,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: false,
                                                                            ownPID: 99),
               "App Switcher restores the source if the target app focuses another window after minimize intent")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                             sourcePID: 20,
                                                                             frontmostPID: 10,
                                                                             focusedWindowID: 44,
                                                                             targetWindowID: 44,
                                                                             targetIsMinimized: false,
                                                                             ownPID: 99),
               "App Switcher waits when minimize intent is observed but the target remains focused and unminimized")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                             sourcePID: 20,
                                                                             frontmostPID: 30,
                                                                             focusedWindowID: 55,
                                                                             targetWindowID: 44,
                                                                             targetIsMinimized: false,
                                                                             ownPID: 99),
               "App Switcher does not restore source after minimize intent if a third app is already active")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 30,
                                                                            focusedWindowID: 55,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: true,
                                                                            ownPID: 99,
                                                                            frontmostMatchesTargetBundle: true),
               "App Switcher restores after minimize intent if a sibling app instance is promoted")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
                                                                            sourcePID: 20,
                                                                            frontmostPID: 30,
                                                                            focusedWindowID: 55,
                                                                            targetWindowID: 44,
                                                                            targetIsMinimized: true,
                                                                            ownPID: 99,
                                                                            frontmostCanBeSystemPromotion: true),
               "App Switcher restores after minimize intent if the system promotes another app")
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: 10,
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
        expect(!SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(
                    targetPID: 10,
                    sourcePID: 20,
                    frontmostPID: 20,
                    focusedWindowID: minimizeIntentFocused(55),
                    targetWindowID: 44,
                    targetIsMinimized: minimizeIntentMinimized(true),
                    ownPID: 99),
               "App Switcher stops a minimize restore pulse once the source is already frontmost")
        expect(minimizeIntentMinimizedReads == 0 && minimizeIntentFocusedReads == 0,
               "App Switcher reads no window state on a minimize pulse the frontmost check alone settles")
        expect(SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(
                    targetPID: 10,
                    sourcePID: 20,
                    frontmostPID: 10,
                    focusedWindowID: minimizeIntentFocused(55),
                    targetWindowID: 44,
                    targetIsMinimized: minimizeIntentMinimized(true),
                    ownPID: 99),
               "App Switcher restores the source once the target window reports itself minimized")
        expect(minimizeIntentMinimizedReads == 1 && minimizeIntentFocusedReads == 0,
               "App Switcher skips the focused-window read when the target is already minimized")
        expect(SwitcherSupport.shouldStageSourceBehindTarget(targetPID: 10,
                                                             sourcePID: 20,
                                                             sourceWindowID: 44,
                                                             ownPID: 99),
               "App Switcher can keep the source window directly behind a selected target window")
        expect(!SwitcherSupport.shouldStageSourceBehindTarget(targetPID: 10,
                                                              sourcePID: 10,
                                                              sourceWindowID: 44,
                                                              ownPID: 99),
               "App Switcher does not stage a source window from the same app")
        expect(!SwitcherSupport.shouldStageSourceBehindTarget(targetPID: 10,
                                                              sourcePID: 99,
                                                              sourceWindowID: 44,
                                                              ownPID: 99),
               "App Switcher does not raise its own editor back over the selected window")
        expect(!SwitcherSupport.shouldStageSourceBehindTarget(targetPID: 10,
                                                              sourcePID: 20,
                                                              sourceWindowID: nil,
                                                              ownPID: 99),
               "App Switcher does not stage without a concrete source window")
        expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 10,
                                                        targetIsMinimized: false,
                                                        targetStartedMinimized: false,
                                                        ownPID: 99),
               "App Switcher focus retries can continue while the selected target app is still active")
        expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 20,
                                                        targetIsMinimized: false,
                                                        targetStartedMinimized: false,
                                                        ownPID: 99),
               "App Switcher focus retries can continue during the source-target handoff")
        expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 20,
                                                         targetIsMinimized: true,
                                                         targetStartedMinimized: false,
                                                         ownPID: 99),
               "App Switcher focus retries stop once the selected target window was minimized")
        expect(SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                        sourcePID: 20,
                                                        frontmostPID: 20,
                                                        targetIsMinimized: true,
                                                        targetStartedMinimized: true,
                                                        ownPID: 99),
               "App Switcher retries restoration when the selected target started minimized")
        expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 10,
                                                         targetIsMinimized: true,
                                                         targetStartedMinimized: true,
                                                         targetWasObservedRestored: true,
                                                         ownPID: 99),
               "App Switcher does not reopen a target the user minimized again after activation")
        expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 30,
                                                         targetIsMinimized: false,
                                                         targetStartedMinimized: false,
                                                         ownPID: 99),
               "App Switcher focus retries do not steal focus after the user moves to another app")
        expect(!SwitcherSupport.shouldContinueFocusRetry(targetPID: 10,
                                                         sourcePID: 20,
                                                         frontmostPID: 30,
                                                         targetIsMinimized: true,
                                                         targetStartedMinimized: true,
                                                         ownPID: 99),
               "App Switcher does not restore a minimized target after the user moves to another app")
        expect(SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                sourcePID: 20,
                                                                frontmostPID: 20,
                                                                targetWasObservedFrontmost: false,
                                                                ownPID: 99),
               "App Switcher can retry an app-only target during a fullscreen handoff")
        expect(SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                sourcePID: 20,
                                                                frontmostPID: 10,
                                                                targetWasObservedFrontmost: true,
                                                                ownPID: 99),
               "App Switcher can settle repeated activation on the app-only target")
        expect(!SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 frontmostPID: 20,
                                                                 targetWasObservedFrontmost: true,
                                                                 ownPID: 99),
               "App Switcher cancels app-only retries when the user returns to the fullscreen source")
        expect(!SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 frontmostPID: 30,
                                                                 targetWasObservedFrontmost: false,
                                                                 ownPID: 99),
               "App Switcher app-only retries do not steal focus from another app")
        expect(!SwitcherSupport.shouldContinueAppActivationRetry(targetPID: 10,
                                                                 sourcePID: nil,
                                                                 frontmostPID: 30,
                                                                 targetWasObservedFrontmost: false,
                                                                 ownPID: 99),
               "App Switcher app-only retries fail closed without a known source app")
        expect(SwitcherSupport.isCurrentSessionStart(generation: 8, pendingGeneration: 8)
               && !SwitcherSupport.isCurrentSessionStart(generation: 8, pendingGeneration: 9)
               && !SwitcherSupport.isCurrentSessionStart(generation: 8, pendingGeneration: nil),
               "App Switcher publishes only the current asynchronous session start")
        expect(SwitcherSupport.pendingKeyDecision(sessionIsActive: false,
                                                  hasPendingStart: true,
                                                  commitWhenReady: false,
                                                  matchesShortcut: false) == .swallow
               && SwitcherSupport.pendingKeyDecision(sessionIsActive: false,
                                                      hasPendingStart: true,
                                                      commitWhenReady: true,
                                                      matchesShortcut: false) == .cancelAndSwallow,
               "App Switcher owns keys during enumeration and cancels a late commit before typing leaks")
        expect(SwitcherSupport.pendingKeyDecision(sessionIsActive: false,
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
        expect(SwitcherSupport.nativeHotkeysToSuppress(
                    takeOverSystemShortcuts: false,
                    appsShortcut: .switcherDefault,
                    windowShortcut: .switcherWindowDefault,
                    nativeShortcuts: nativeSwitcherShortcuts).isEmpty,
               "the App Switcher never changes macOS shortcuts without explicit opt-in")
        expect(SwitcherSupport.nativeHotkeysToSuppress(
                    takeOverSystemShortcuts: true,
                    appsShortcut: .switcherDefault,
                    windowShortcut: .switcherWindowDefault,
                    nativeShortcuts: nativeSwitcherShortcuts)
               == Set(SwitcherNativeSymbolicHotKey.allCases),
               "opt-in covers both app and window switcher directions")
        expect(SwitcherSupport.nativeHotkeysToSuppress(
                    takeOverSystemShortcuts: true,
                    appsShortcut: GlobalShortcut(keyCode: Int64(kVK_Tab), modifiers: [.option]),
                    windowShortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave), modifiers: [.option]),
                    nativeShortcuts: nativeSwitcherShortcuts).isEmpty,
               "non-colliding shortcuts leave the macOS switchers in place")
        let remappedNativeShortcuts = nativeSwitcherShortcuts.mapValues {
            GlobalShortcut(keyCode: $0.keyCode,
                           modifiers: $0.modifiers.subtracting(.command).union(.option))
        }
        expect(SwitcherSupport.nativeHotkeysToSuppress(
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
        expect(mappedSwitcherShortcuts[.previousWindow]
               == GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave), modifiers: [.command, .shift]),
               "the reverse window switcher resolves to Command-Shift-Backtick in the live table")
        expect(SwitcherSupport.nativeHotkeysToSuppress(
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
        expect(threeKeyTakeover == [.nextWindow, .previousWindow]
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
        expect(SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: true,
                                               appsShortcut: .switcherDefault,
                                               windowShortcut: .switcherWindowDefault,
                                               liveEntries: liveSwitcherEntries) == [1, 2, 27, 220],
               "the switcher asks the shared take-over for exactly its four ids, never the screenshot key")
        expect(SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: false,
                                               appsShortcut: .switcherDefault,
                                               windowShortcut: .switcherWindowDefault,
                                               liveEntries: liveSwitcherEntries).isEmpty,
               "without opt-in the switcher asks for nothing")
        expect(SwitcherSupport.nativeHotkeyIDs(takeOverSystemShortcuts: true,
                                               appsShortcut: .switcherDefault,
                                               windowShortcut: .switcherWindowDefault,
                                               liveEntries: liveSwitcherEntries.filter { $0.id != 220 })
               == [1, 2, 27],
               "an id missing from the live table is never asked for")

        // The shared take-over works on raw WindowServer ids. Same transition
        // rule as the switcher had: suppress only what is enabled now, restore
        // only what we own and no longer want.
        expect(SystemShortcutTakeoverSupport.transition(from: [], to: [1, 2, 30], currentlyEnabled: [1, 30])
               == SystemShortcutTransition(suppress: [1, 30], restore: [])
               && SystemShortcutTakeoverSupport.transition(from: [1, 30], to: [], currentlyEnabled: [])
               == SystemShortcutTransition(suppress: [], restore: [1, 30]),
               "the shared take-over suppresses only enabled ids and restores only owned ones")
        expect(SystemShortcutTakeoverSupport.migratedMarker(old: [27, 28], new: [30]) == [27, 28, 30]
               && SystemShortcutTakeoverSupport.migratedMarker(old: nil, new: nil).isEmpty
               && SystemShortcutTakeoverSupport.migratedMarker(old: [99_999_999_999], new: nil).isEmpty,
               "the old switcher marker folds into the shared one once, dropping anything that is not an id")
        // #1357's contracts, now carried by the shared rule. Launch gives back
        // every id the marker still holds, including when the App Switcher is
        // off: a feature that is off claims none of them, so all of them are
        // restored without the switcher's tap or the feature being installed.
        let legacyMarker = SystemShortcutTakeoverSupport.migratedMarker(old: [27, 28, 220], new: nil)
        expect(SystemShortcutTakeoverSupport.recoveryTransition(from: legacyMarker, keeping: [])
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
        expect(cleanLaunchOwnership.isEmpty && recoveryWrites.isEmpty,
               "clean launch leaves system shortcuts working until the replacement tap is live")
        let recoveredOwnership = SystemShortcutTakeoverSupport.apply(
            SystemShortcutTakeoverSupport.recoveryTransition(from: legacyMarker, keeping: [1, 27, 220]),
            owned: legacyMarker, setEnabled: recordRecoveryWrite, persist: { _ in })
        expect(recoveredOwnership == [27, 220] && recoveryWrites == [28],
               "crash recovery gives back stale keys without toggling retained keys or taking new ones")
        // Say the WindowServer refused 28: `apply` leaves it in the marker, so
        // every later transition asks for it again and the give-back finishes
        // at the next take-over or in the next process.
        expect(SystemShortcutTakeoverSupport.transition(from: [28], to: [1], currentlyEnabled: [1])
               == SystemShortcutTransition(suppress: [1], restore: [28]),
               "an id whose give-back failed stays owned and is retried while another key is taken over")
        expect(SystemShortcutTakeoverSupport.transition(from: [1, 28], to: [], currentlyEnabled: [])
               == SystemShortcutTransition(suppress: [], restore: [1, 28]),
               "a marker that survived a failed give-back is retried in full by the next process")
        expect(SystemShortcutTakeoverSupport.transition(from: [], to: [], currentlyEnabled: [1, 28])
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
        expect(afterRefusedDisable == [1] && fakeEnabled == [27] && markers.last == [1]
               && markers.contains(where: { $0.contains(27) }),
               "a refused disable rolls the key back out of the marker it was written ahead into")
        refused = [1]
        let afterRefusedEnable = SystemShortcutTakeoverSupport.apply(
            SystemShortcutTransition(suppress: [], restore: [1]), owned: afterRefusedDisable,
            setEnabled: fakeSetEnabled, persist: record)
        expect(afterRefusedEnable == [1] && !fakeEnabled.contains(1),
               "a refused enable keeps the key in the marker for the next pass to retry")
        refused = []
        expect(SystemShortcutTakeoverSupport.apply(
                   SystemShortcutTransition(suppress: [], restore: [1]), owned: afterRefusedEnable,
                   setEnabled: fakeSetEnabled, persist: record).isEmpty && fakeEnabled == [1, 27],
               "the retry finishes the give-back")
        expect(!writeAheadMissing, "ownership is persisted before every disable")

        expect(SwitcherSupport.isCurrentActivationGeneration(12, current: 12)
               && !SwitcherSupport.isCurrentActivationGeneration(11, current: 12),
               "App Switcher ignores retries left by an older activation")
        expect(SwitcherSupport.shouldRestoreHiddenApp(revealGeneration: 12,
                                                      currentGeneration: 12,
                                                      appWasReactivated: false)
               && !SwitcherSupport.shouldRestoreHiddenApp(revealGeneration: 12,
                                                           currentGeneration: 13,
                                                           appWasReactivated: false)
               && !SwitcherSupport.shouldRestoreHiddenApp(revealGeneration: 12,
                                                           currentGeneration: 12,
                                                           appWasReactivated: true),
               "closing a hidden window restores hiding only before a later activation of that app")
        expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 10,
                                                                 ownPID: 99),
               "App Switcher keeps the minimize observer when the target app remains active")
        expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 20,
                                                                 ownPID: 99),
               "App Switcher keeps the minimize observer when the source app is staged behind the target")
        expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 99,
                                                                 ownPID: 99),
               "App Switcher keeps the minimize observer through its own activation handoff")
        expect(!SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                  sourcePID: 20,
                                                                  activatedPID: 30,
                                                                  ownPID: 99),
               "App Switcher cancels the minimize observer when the user moves to a third app")
        expect(SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: 10,
                                                                 sourcePID: 20,
                                                                 activatedPID: 30,
                                                                 ownPID: 99,
                                                                 activatedMatchesTargetBundle: true),
               "App Switcher keeps the minimize observer when a sibling app instance activates")
        let switcherCloseSelected = SwitcherSupport.closeState(afterRemoving: "b",
                                                               itemIDs: ["a", "b", "c"],
                                                               selectedIndex: 1)
        expect(switcherCloseSelected.remainingItemIDs == ["a", "c"]
               && switcherCloseSelected.selectedIndex == 1
               && !switcherCloseSelected.shouldEndSession,
               "App Switcher close selects the next window after closing the selected one")
        let switcherCloseBeforeSelection = SwitcherSupport.closeState(afterRemoving: "a",
                                                                      itemIDs: ["a", "b", "c"],
                                                                      selectedIndex: 2)
        expect(switcherCloseBeforeSelection.remainingItemIDs == ["b", "c"]
               && switcherCloseBeforeSelection.selectedIndex == 1,
               "App Switcher close preserves the same logical selection after removing an earlier window")
        let switcherCloseLast = SwitcherSupport.closeState(afterRemoving: "only",
                                                           itemIDs: ["only"],
                                                           selectedIndex: 0)
        expect(switcherCloseLast.didRemove
               && switcherCloseLast.shouldEndSession
               && switcherCloseLast.remainingItemIDs.isEmpty,
               "App Switcher close ends the session after the last item is removed")
        let switcherCloseMissing = SwitcherSupport.closeState(afterRemoving: "missing",
                                                              itemIDs: ["a", "b"],
                                                              selectedIndex: 1)
        expect(!switcherCloseMissing.didRemove
               && switcherCloseMissing.remainingItemIDs == ["a", "b"]
               && switcherCloseMissing.selectedIndex == 1,
               "App Switcher close leaves selection intact when the item is not present")
        expect(SwitcherSupport.commitTargetID(itemIDs: ["a", "b", "c"],
                                              selectedIndex: 1,
                                              closingItemIDs: []) == "b",
               "App Switcher release activates the highlighted window")
        expect(SwitcherSupport.commitTargetID(itemIDs: ["a", "b", "c"],
                                              selectedIndex: 1,
                                              closingItemIDs: ["b"]) == "c",
               "App Switcher release skips the window that is closing")
        expect(SwitcherSupport.commitTargetID(itemIDs: ["a", "b", "c"],
                                              selectedIndex: 2,
                                              closingItemIDs: ["b", "c"]) == "a",
               "App Switcher release falls back to the last window left when several are closing")
        expect(SwitcherSupport.commitTargetID(itemIDs: ["a", "b"],
                                              selectedIndex: 1,
                                              closingItemIDs: ["a", "b"]) == nil,
               "App Switcher release activates nothing when every window is closing")
        expect(SwitcherSupport.commitTargetID(itemIDs: [],
                                              selectedIndex: 0,
                                              closingItemIDs: []) == nil,
               "App Switcher release activates nothing with an empty list")
        expect(SwitcherSupport.letterAction(typedCharacter: "w", keyCode: 13, pinSearchEnabled: false) == .closeWindow
               && SwitcherSupport.letterAction(typedCharacter: "q", keyCode: 12, pinSearchEnabled: false) == .quitApp,
               "App Switcher panel closes a window with W and quits an app with Q")
        expect(SwitcherSupport.letterAction(typedCharacter: "W", keyCode: 13, pinSearchEnabled: false) == .closeWindow,
               "App Switcher panel treats the letter the same in either case")
        expect(SwitcherSupport.letterAction(typedCharacter: "e", keyCode: 14, pinSearchEnabled: false) == nil
               && SwitcherSupport.letterAction(typedCharacter: "1", keyCode: 18, pinSearchEnabled: false) == nil,
               "App Switcher panel leaves every other key to the search field")
        // A French keyboard types z where the US one types w, and its own w
        // sits on another key: both answer by the letter, not the position.
        expect(SwitcherSupport.letterAction(typedCharacter: "z", keyCode: 13, pinSearchEnabled: false) == nil
               && SwitcherSupport.letterAction(typedCharacter: "w", keyCode: 6, pinSearchEnabled: false) == .closeWindow,
               "App Switcher panel follows the letters printed on the keyboard")
        expect(SwitcherSupport.letterAction(typedCharacter: "a", keyCode: 12, pinSearchEnabled: false) == nil
               && SwitcherSupport.letterAction(typedCharacter: "q", keyCode: 0, pinSearchEnabled: false) == .quitApp,
               "App Switcher panel quits from the Q key wherever the layout puts it")
        // Cyrillic and Greek type no Latin letter at all, so the key position
        // stands in, the same place macOS puts their command shortcuts.
        expect(SwitcherSupport.letterAction(typedCharacter: "ц", keyCode: 13, pinSearchEnabled: false) == .closeWindow
               && SwitcherSupport.letterAction(typedCharacter: "й", keyCode: 12, pinSearchEnabled: false) == .quitApp,
               "App Switcher panel falls back to the key position on non-Latin layouts")
        expect(SwitcherSupport.letterAction(typedCharacter: nil, keyCode: 13, pinSearchEnabled: false) == .closeWindow
               && SwitcherSupport.letterAction(typedCharacter: "", keyCode: 12, pinSearchEnabled: false) == .quitApp,
               "App Switcher panel falls back to the key position when a key types nothing")
        expect(SwitcherSupport.letterAction(typedCharacter: "ç", keyCode: 13, pinSearchEnabled: false) == nil,
               "App Switcher panel counts an accented letter as a letter of its own")
        // S only pins the search field once the opt-in preference is on, so
        // existing users who search by typing "s" first see no change.
        expect(SwitcherSupport.letterAction(typedCharacter: "s", keyCode: 1, pinSearchEnabled: false) == nil
               && SwitcherSupport.letterAction(typedCharacter: "ß", keyCode: 1, pinSearchEnabled: false) == nil,
               "App Switcher panel leaves S to the search field when the pin preference is off")
        expect(SwitcherSupport.letterAction(typedCharacter: "s", keyCode: 1, pinSearchEnabled: true) == .pinSearch
               && SwitcherSupport.letterAction(typedCharacter: "ß", keyCode: 1, pinSearchEnabled: true) == .pinSearch,
               "App Switcher panel pins the search field from S once the preference is on, even when the modifier turns it into a special character")
        // Caps Lock alongside the session's ⌥ turns S into "Í" instead of "ß" —
        // an accented letter that folds cleanly to "i", an unrelated letter, so
        // the pin must still fire from the key's position (issue: ⌥S + Caps Lock).
        expect(SwitcherSupport.letterAction(typedCharacter: "Í", keyCode: 1, pinSearchEnabled: true) == .pinSearch,
               "App Switcher panel pins the search field from S even when Caps Lock folds it to an unrelated letter")
        expect(SwitcherSupport.letterAction(typedCharacter: "Í", keyCode: 1, pinSearchEnabled: false) == nil,
               "App Switcher panel leaves S to the search field when the pin preference is off, even under Caps Lock")
        expect(SwitcherSupport.letterAction(typedCharacter: "o", keyCode: 1, pinSearchEnabled: true) == nil,
               "App Switcher panel follows a remapped Latin letter instead of the physical S position")
        expect(SwitcherSupport.letterAction(typedCharacter: "ы", keyCode: 1, pinSearchEnabled: true) == .pinSearch,
               "App Switcher panel falls back to the physical S position on a non-Latin layout")
        let switcherPanelFrame = CGRect(x: 400, y: 300, width: 600, height: 400)
        expect(SwitcherSupport.shouldDismissForClick(panelIsVisible: true,
                                                     panelFrame: switcherPanelFrame,
                                                     location: CGPoint(x: 200, y: 200)),
               "App Switcher cancels synchronously when a mouse-down starts outside it")
        expect(!SwitcherSupport.shouldDismissForClick(panelIsVisible: true,
                                                      panelFrame: switcherPanelFrame,
                                                      location: CGPoint(x: 700, y: 500)),
               "App Switcher panel stays for a click on one of its windows")
        expect(!SwitcherSupport.shouldDismissForClick(panelIsVisible: true,
                                                      panelFrame: switcherPanelFrame,
                                                      location: CGPoint(x: 401, y: 301)),
               "App Switcher panel counts its own edge as part of it")
        expect(!SwitcherSupport.shouldDismissForClick(panelIsVisible: false,
                                                      panelFrame: switcherPanelFrame,
                                                      location: CGPoint(x: 200, y: 200)),
               "App Switcher ignores clicks while a quick switch shows no panel")
        expect(SwitcherSupport.isMiddleClickInsidePanel(eventType: .otherMouseDown,
                                                        buttonNumber: 2,
                                                        panelIsVisible: true,
                                                        panelFrame: switcherPanelFrame,
                                                        location: CGPoint(x: 700, y: 500),
                                                        itemIsHovered: true),
               "App Switcher detects middle-click on a card to close that window")
        expect(!SwitcherSupport.isMiddleClickInsidePanel(eventType: .otherMouseDown,
                                                         buttonNumber: 2,
                                                         panelIsVisible: true,
                                                         panelFrame: switcherPanelFrame,
                                                         location: CGPoint(x: 700, y: 500),
                                                         itemIsHovered: false),
               "App Switcher leaves middle-click on panel chrome alone")
        expect(!SwitcherSupport.isMiddleClickInsidePanel(eventType: .otherMouseDown,
                                                         buttonNumber: 2,
                                                         panelIsVisible: true,
                                                         panelFrame: switcherPanelFrame,
                                                         location: CGPoint(x: 200, y: 200),
                                                         itemIsHovered: true),
               "App Switcher leaves middle-click outside panel to regular dismissal")
        expect(!SwitcherSupport.isMiddleClickInsidePanel(eventType: .leftMouseDown,
                                                         buttonNumber: 0,
                                                         panelIsVisible: true,
                                                         panelFrame: switcherPanelFrame,
                                                         location: CGPoint(x: 700, y: 500),
                                                         itemIsHovered: true),
               "App Switcher ignores non-middle clicks for direct window close")
        expect(!SwitcherSupport.isMiddleClickInsidePanel(eventType: .otherMouseDown,
                                                         buttonNumber: 3,
                                                         panelIsVisible: true,
                                                         panelFrame: switcherPanelFrame,
                                                         location: CGPoint(x: 700, y: 500),
                                                         itemIsHovered: true),
               "App Switcher ignores extra mouse buttons for direct window close")
        expect(!SwitcherSupport.isMiddleClickInsidePanel(eventType: .otherMouseDown,
                                                         buttonNumber: 2,
                                                         panelIsVisible: false,
                                                         panelFrame: switcherPanelFrame,
                                                         location: CGPoint(x: 700, y: 500),
                                                         itemIsHovered: true),
               "App Switcher ignores middle-click when panel is not visible")
        expect(SwitcherSupport.shouldSwallowMiddleMouseUp(eventType: .otherMouseUp,
                                                          buttonNumber: 2,
                                                          swallowedMouseDown: true),
               "App Switcher swallows the release after closing a card")
        expect(!SwitcherSupport.shouldSwallowMiddleMouseUp(eventType: .otherMouseUp,
                                                           buttonNumber: 2,
                                                           swallowedMouseDown: false),
               "App Switcher leaves unrelated middle-mouse-up events alone")
        let searchRecords = [
            SwitcherSearchRecord(id: "alpha", title: "Inbox", appName: "Alpha"),
            SwitcherSearchRecord(id: "beta", title: "Vorssaint Roadmap", appName: "Beta"),
            SwitcherSearchRecord(id: "gamma", title: "Café notes", appName: "Gamma"),
        ]
        expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "") == ["alpha", "beta", "gamma"],
               "App Switcher search keeps all windows for an empty query")
        expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "beta roadmap") == ["beta"],
               "App Switcher search matches multiple tokens across app name and window title")
        expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "cafe") == ["gamma"],
               "App Switcher search ignores accents")
        expect(SwitcherSupport.filteredSearchIDs(records: searchRecords, query: "missing").isEmpty,
               "App Switcher search can return no matches")
        expect(SwitcherSupport.searchSelectionIndex(itemIDs: ["alpha", "beta"],
                                                    preferredID: "beta",
                                                    previousIndex: 0) == 1,
               "App Switcher search preserves the selected item when it remains visible")
        expect(SwitcherSupport.searchSelectionIndex(itemIDs: ["alpha"],
                                                    preferredID: "beta",
                                                    previousIndex: 2) == 0,
               "App Switcher search falls back to a valid selection")
    }
}
