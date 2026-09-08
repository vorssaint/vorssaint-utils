// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Foundation

enum ShortcutTests {
    static func runDefaults(expect: (Bool, String) -> Void) {
        let registeredDefaults = Defaults.registeredDefaults
        expect(registeredDefaults[DefaultsKey.panelControlAutoQuit] as? Bool == true,
               "panel auto quit control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlShelf] as? Bool == true,
               "panel shelf control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlWindowMaximize] as? Bool == true,
               "panel window maximize control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlKeyDebounce] as? Bool == true,
               "panel keyboard debounce control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlTextSnippets] as? Bool == true,
               "panel text snippets control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelShowKeepAwake] as? Bool == true,
               "Keep Awake panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.panelShowBrightness] as? Bool == true,
               "brightness panel section is shown by default once the feature is on")
        expect(registeredDefaults[DefaultsKey.brightnessControlEnabled] as? Bool == false,
               "brightness control arrives switched off")
        expect(registeredDefaults[DefaultsKey.brightnessKeysEnabled] as? Bool == false,
               "pointer-following brightness keys arrive switched off")
        expect(registeredDefaults[DefaultsKey.brightnessOSDEnabled] as? Bool == false,
               "brightness adjustment overlay arrives switched off")
        expect(registeredDefaults[DefaultsKey.keyboardBrightnessDecreaseShortcut] as? String
                == GlobalShortcut.keyboardBrightnessDecreaseDefault.storageValue
                && registeredDefaults[DefaultsKey.keyboardBrightnessIncreaseShortcut] as? String
                == GlobalShortcut.keyboardBrightnessIncreaseDefault.storageValue,
               "keyboard brightness shortcuts ship with distinct defaults")
        expect(registeredDefaults[DefaultsKey.keyboardBrightnessShortcutsEnabled] as? Bool == false,
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
        expect(keyboardShortcutSettings.allSatisfy { key, value in
            (restoredKeyboardShortcuts?[key] as? NSObject) == (value as? NSObject)
        }, "keyboard brightness opt-in and custom shortcuts survive a settings backup")

        expect(registeredDefaults[DefaultsKey.screenshotOpenEditorDirectly] as? Bool == false,
               "capture keeps showing the preview unless the user opts into the editor")
        expect(registeredDefaults[DefaultsKey.screenshotDefaultAction] as? String == "",
               "captures keep asking what to do until an after-capture action is chosen")
        expect(registeredDefaults[DefaultsKey.screenshotSaveSubfolder] as? String == ""
                && registeredDefaults[DefaultsKey.screenshotFileNamePattern] as? String == "",
               "subfolder and file name patterns arrive empty, keeping the stock naming")
        expect(registeredDefaults[DefaultsKey.screenshotFileNumberStart] as? Int == 1
                && registeredDefaults[DefaultsKey.screenshotFileNumberNext] as? Int == 1,
               "the file number sequence starts counting at 1")
        expect(registeredDefaults[DefaultsKey.panelShowUtilities] as? Bool == true,
               "Utilities panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.panelShowControls] as? Bool == true,
               "Quick Controls panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.panelShowToggles] as? Bool == true,
               "Quick toggles panel section is shown by default")
        expect([DefaultsKey.panelToggleDarkMode, DefaultsKey.panelToggleKeyboardLight,
                DefaultsKey.panelToggleMicMute,
                DefaultsKey.panelToggleEmptyTrash,
                DefaultsKey.panelToggleEjectDisks, DefaultsKey.panelToggleHiddenFiles,
                DefaultsKey.panelToggleDesktopIcons, DefaultsKey.panelToggleLockScreen,
                DefaultsKey.panelToggleDisplayOff, DefaultsKey.panelToggleScreenSaver]
                .allSatisfy { registeredDefaults[$0] as? Bool == true },
               "every quick toggle row is visible by default")
        expect(registeredDefaults[DefaultsKey.monitorInterval] as? Int == 2,
               "monitor default interval stays at 2 seconds")
        expect(registeredDefaults[DefaultsKey.monitorShowDisk] as? Bool == true,
               "disk monitor panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorSysAlerts] as? Bool == true,
               "system alert controls are shown by default")
        expect(registeredDefaults[DefaultsKey.monitorGraphDisk] as? Bool == true,
               "disk monitor graph is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorNetApps] as? Bool == true,
               "network app usage block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskUsage] as? Bool == true,
               "disk usage block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskActivity] as? Bool == true,
               "disk activity block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskSMART] as? Bool == true,
               "disk SMART block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskProtection] as? Bool == true,
               "disk protection block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskTools] as? Bool == true,
               "disk tools block is shown by default")
        expect(registeredDefaults[DefaultsKey.temperatureUnit] as? String == TemperatureUnit.celsius.rawValue,
               "temperature defaults to Celsius")
        expect(registeredDefaults[DefaultsKey.menuBarCPUTemperature] as? Bool == false,
               "menu bar CPU temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarGPUTemperature] as? Bool == false,
               "menu bar GPU temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarBatteryTemperature] as? Bool == false,
               "menu bar battery temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarBatteryTime] as? Bool == false,
               "menu bar battery time is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarDiskUsage] as? Bool == false,
               "menu bar disk usage is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarDiskActivity] as? Bool == false,
               "menu bar disk activity is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarPeripheralBattery] as? Bool == false,
               "menu bar peripheral battery is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarFanSpeed] as? Bool == false,
               "menu bar fan speed is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarMetricOrder] as? String
               == "cpu,cpuTemperature,gpu,gpuTemperature,memory,battery,batteryTime,batteryTemperature,peripheralBattery,network,diskUsage,diskActivity,power,fanSpeed",
               "menu bar metric order keeps temperature sensors next to their components and disk near live I/O")
        expect(registeredDefaults[DefaultsKey.menuBarCombineTemperatures] as? Bool == true,
               "menu bar combines usage and temperature by default")
        expect(registeredDefaults[DefaultsKey.menuBarSeparateMetrics] as? Bool == false,
               "separate menu bar metric items are opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarNetworkUploadFirst] as? Bool == false,
               "network menu bar upload-first layout is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarLabelStyle] as? String == "compact",
               "menu bar label style defaults to compact")
        expect(registeredDefaults[DefaultsKey.menuBarMemoryStyle] as? String == "percent",
               "memory menu bar style defaults to percent")
        expect(registeredDefaults[DefaultsKey.monitorPwrTimeRemaining] as? Bool == true,
               "battery time is shown in the Power panel by default")
        expect(registeredDefaults[DefaultsKey.windowLayoutShortcutsEnabled] as? Bool == false,
               "window layout shortcuts stay off until enabled")
        expect(registeredDefaults[DefaultsKey.windowEdgeSnapEnabled] as? Bool == false,
               "dragging windows to screen edges is opt-in")
        expect(registeredDefaults[DefaultsKey.windowEdgeSnapDisabledZones] as? String == "",
               "every visual edge snap zone starts enabled")
        expect(registeredDefaults[DefaultsKey.windowGestureEnabled] as? Bool == false,
               "window move and resize gestures are opt-in")
        expect(registeredDefaults[DefaultsKey.mouseSpacesGestureEnabled] as? Bool == false
                && registeredDefaults[DefaultsKey.mouseSpacesGestureButton] as? Int == 0
                && registeredDefaults[DefaultsKey.mouseSpacesGestureFollowsDrag] as? Bool == false,
               "the Spaces and Mission Control drag ships off, with no button bound and the plain direction")
        expect(registeredDefaults[DefaultsKey.windowGestureModifiers] as? String == "control+command",
               "window gestures start with the deliberate control-command chord")
        expect(registeredDefaults[DefaultsKey.windowGestureRaiseWindow] as? Bool == false,
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
        expect(assignedLayoutShortcutValues.count == assignedLayoutShortcutKeys.count,
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
        expect(unassignedLayoutShortcutKeys.allSatisfy {
                   registeredDefaults[$0] as? String == WindowLayoutAction.clearedShortcutStorageValue
               },
               "new window layout shortcuts start unassigned")
        expect(Set(assignedLayoutShortcutValues).count == assignedLayoutShortcutValues.count,
               "window layout shortcuts do not conflict with each other by default")
        let globalShortcutValues = GlobalShortcutRole.allCases
            .compactMap { registeredDefaults[$0.storageKey] as? String }
        expect(Set(assignedLayoutShortcutValues).intersection(globalShortcutValues).isEmpty,
               "window layout shortcuts do not conflict with other global shortcuts by default")
        // Two features shipping the same combination means one of them is dead
        // on arrival: the second registration is simply refused by the system,
        // and which one loses depends on the order they happen to sync in.
        expect(Set(globalShortcutValues).count == globalShortcutValues.count,
               "no two features ship the same default combination")
        expect(globalShortcutValues.count == GlobalShortcutRole.allCases.count,
               "every role ships with a default combination registered")
    }

    static func run(expect: (Bool, String) -> Void) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String) {
            expect(actual == expected, "\(label): got \"\(actual)\", expected \"\(expected)\"")
        }

        let registeredDefaults = Defaults.registeredDefaults
        expect(GlobalShortcut(keyCode: Int64(kVK_ISO_Section),
                              modifiers: [.control, .option, .command]).isValid,
               "the extra ISO key (paragraph/caret above Tab) is recordable as a shortcut")
        GlobalShortcut.startObservingKeyboardLayout()
        GlobalShortcut.refreshLayoutLabels()
        let backgroundISOKeyIsValid = DispatchQueue.global().sync {
            GlobalShortcut(keyCode: Int64(kVK_ISO_Section),
                           modifiers: [.control, .option, .command]).isValid
        }
        expect(backgroundISOKeyIsValid,
               "layout-dependent shortcut labels are safe to read off the main thread")
        let shortcutM = GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: [.control, .option, .command])
        let shortcutSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: [.control, .option, .command])
        expect(shortcutM.isValid && !shortcutM.displayString.isEmpty,
               "letter shortcuts resolve valid caps on the active keyboard layout")
        expect(shortcutSemi.isValid && !shortcutSemi.displayString.isEmpty,
               "punctuation and layout-specific keys resolve valid caps on the active keyboard layout")

        // Multi-layout dynamic keycap resolution tests
        let layoutTestModifiers: GlobalShortcutModifiers = [.control, .option, .command]

        if let frenchData = testLayoutData(for: "com.apple.keylayout.French") {
            GlobalShortcut.refreshLayoutLabels(layoutData: frenchData)
            let frenchM = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            let frenchComma = GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: layoutTestModifiers)
            let frenchA = GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: layoutTestModifiers)
            let frenchQ = GlobalShortcut(keyCode: Int64(kVK_ANSI_A), modifiers: layoutTestModifiers)
            let frenchZ = GlobalShortcut(keyCode: Int64(kVK_ANSI_W), modifiers: layoutTestModifiers)
            let frenchW = GlobalShortcut(keyCode: Int64(kVK_ANSI_Z), modifiers: layoutTestModifiers)
            expectEqual(frenchM.displayString, "⌃⌥⌘M", "French AZERTY resolves physical semicolon key as M")
            expectEqual(frenchComma.displayString, "⌃⌥⌘ ,", "French AZERTY resolves physical M key as comma")
            expectEqual(frenchA.displayString, "⌃⌥⌘A", "French AZERTY resolves physical Q key as A")
            expectEqual(frenchQ.displayString, "⌃⌥⌘Q", "French AZERTY resolves physical A key as Q")
            expectEqual(frenchZ.displayString, "⌃⌥⌘Z", "French AZERTY resolves physical W key as Z")
            expectEqual(frenchW.displayString, "⌃⌥⌘W", "French AZERTY resolves physical Z key as W")
        }

        if let germanData = testLayoutData(for: "com.apple.keylayout.German") {
            GlobalShortcut.refreshLayoutLabels(layoutData: germanData)
            let germanZ = GlobalShortcut(keyCode: Int64(kVK_ANSI_Y), modifiers: layoutTestModifiers)
            let germanY = GlobalShortcut(keyCode: Int64(kVK_ANSI_Z), modifiers: layoutTestModifiers)
            let germanOuml = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            expectEqual(germanZ.displayString, "⌃⌥⌘Z", "German QWERTZ resolves physical Y key as Z")
            expectEqual(germanY.displayString, "⌃⌥⌘Y", "German QWERTZ resolves physical Z key as Y")
            expectEqual(germanOuml.displayString, "⌃⌥⌘Ö", "German QWERTZ resolves physical semicolon key as Ö")
        }

        if let abntData = testLayoutData(for: "com.apple.keylayout.Brazilian-ABNT2") {
            GlobalShortcut.refreshLayoutLabels(layoutData: abntData)
            let abntC = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            expectEqual(abntC.displayString, "⌃⌥⌘Ç", "Brazilian ABNT2 resolves physical semicolon key as Ç")
        }

        if let usData = testLayoutData(for: "com.apple.keylayout.US") {
            GlobalShortcut.refreshLayoutLabels(layoutData: usData)
            let usM = GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: layoutTestModifiers)
            let usSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            expectEqual(usM.displayString, "⌃⌥⌘M", "US layout resolves physical M key as M")
            expectEqual(usSemi.displayString, "⌃⌥⌘ ;", "US layout resolves physical semicolon key as semicolon")
        }

        // A keycap names a combination, not a key, and macOS resolves a Command
        // combination through the layout's Command table. Layouts that type a
        // non-Latin script answer differently there than they do bare, and
        // DVORAK-QWERTYCMD exists for nothing but that difference, so both
        // tables have to come out of the same layout.
        if let russianData = testLayoutData(for: "com.apple.keylayout.Russian") {
            GlobalShortcut.refreshLayoutLabels(layoutData: russianData)
            let russianCommandQ = GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: layoutTestModifiers)
            let russianBareQ = GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: [.control, .option])
            expectEqual(russianCommandQ.displayString, "⌃⌥⌘Q",
                        "Russian reads a Command shortcut off the layout's Command table")
            expectEqual(russianBareQ.displayString, "⌃⌥Й",
                        "Russian reads a shortcut without Command off the character the key types")
        }

        if let dvorakCommandData = testLayoutData(for: "com.apple.keylayout.DVORAK-QWERTYCMD") {
            GlobalShortcut.refreshLayoutLabels(layoutData: dvorakCommandData)
            let dvorakCommandSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon),
                                                   modifiers: layoutTestModifiers)
            let dvorakBareSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon),
                                                modifiers: [.control, .option])
            expectEqual(dvorakCommandSemi.displayString, "⌃⌥⌘ ;",
                        "Dvorak with QWERTY Command keeps Command shortcuts on the QWERTY cap")
            expectEqual(dvorakBareSemi.displayString, "⌃⌥S",
                        "Dvorak with QWERTY Command keeps the rest on the Dvorak cap")
        }

        // The ANSI table answers when no layout can be read at all. On a live
        // system that is a caller off the main thread meeting a cold cache:
        // Text Input Services cannot be asked from there, so nothing derives a
        // cap and nothing warms the entry either.
        GlobalShortcut.refreshLayoutLabels(layoutData: nil)
        var coldCacheCaps: [String] = []
        let coldCacheDone = DispatchSemaphore(value: 0)
        // A thread of its own, not `sync`: dispatch runs a synchronous block on
        // whichever thread called it, so `sync` would still be the main thread
        // and would reach Text Input Services after all.
        Thread {
            coldCacheCaps = [
                GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: layoutTestModifiers).displayString,
                GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers).displayString,
            ]
            coldCacheDone.signal()
        }.start()
        coldCacheDone.wait()
        expectEqual(coldCacheCaps.first ?? "", "⌃⌥⌘M",
                    "a cold cache off the main thread falls back to ANSI M")
        expectEqual(coldCacheCaps.last ?? "", "⌃⌥⌘ ;",
                    "a cold cache off the main thread falls back to ANSI semicolon")

        GlobalShortcut.refreshLayoutLabels()

        // Every assertion above compares labels the live input source produced,
        // so on a Latin-layout Mac they all pass whichever source the keycaps
        // are read from, and the one thing that made them wrong is invisible:
        // an input method answers the current-layout call with the layout it
        // types through, not the one printed on the keys. Pinned on the public
        // symbols rather than on the private member holding them, so renaming
        // it stays green and dropping the ASCII-capable lookup goes red.
        let shortcutSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Core/GlobalShortcut.swift",
            encoding: .utf8)) ?? ""
        let shortcutCode = shortcutSource.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(shortcutCode.contains("TISCopyCurrentASCIICapableKeyboardLayoutInputSource")
                && shortcutCode.contains("TISCopyCurrentKeyboardInputSource")
                && shortcutCode.contains("kTISPropertyInputSourceType"),
               "keycaps come from the ASCII-capable layout while an input method is active")

        // The native full screen action, wired like the sixths: real strings,
        // a stable id, and no system-wide key claimed until someone asks.
        expect(WindowLayoutAction.allCases.contains(.fullScreen)
                && WindowLayoutAction.fullScreen.shortcutID == 53
                && WindowLayoutAction(shortcutID: 53) == .fullScreen,
               "full screen exists and answers to its own shortcut id")
        expect(WindowLayoutAction.fullScreen.defaultShortcut == nil
                && Defaults.registeredDefaults[DefaultsKey.windowLayoutShortcutFullScreen] as? String
                    == WindowLayoutAction.clearedShortcutStorageValue,
               "full screen starts with no combination of its own")
        expect(WindowLayoutAction.allCases.contains(.previousDisplay)
                && WindowLayoutAction.previousDisplay.shortcutID == 54
                && WindowLayoutAction(shortcutID: 54) == .previousDisplay,
               "previous display exists and answers to its own shortcut id")
        expect(WindowLayoutAction.previousDisplay.defaultShortcut == nil,
               "previous display does not claim a new system-wide combination")
        expect(WindowLayoutAction.allCases.contains(.marginMaximize)
                && WindowLayoutAction.marginMaximize.shortcutID == 55
                && WindowLayoutAction(shortcutID: 55) == .marginMaximize,
               "margin maximize exists and answers to its own shortcut id")
        expect(WindowLayoutAction.marginMaximize.defaultShortcut == nil
                && Defaults.registeredDefaults[DefaultsKey.windowLayoutShortcutMarginMaximize] as? String
                    == WindowLayoutAction.clearedShortcutStorageValue,
               "margin maximize starts with no combination of its own")
        expect(WindowLayoutAction.allCases.contains(.centerHalf)
                && WindowLayoutAction.centerHalf.shortcutID == 57
                && WindowLayoutAction(shortcutID: 57) == .centerHalf,
               "center half exists and answers to its own shortcut id")
        expect(WindowLayoutAction.centerHalf.defaultShortcut == nil
                && Defaults.registeredDefaults[DefaultsKey.windowLayoutShortcutCenterHalf] as? String
                    == WindowLayoutAction.clearedShortcutStorageValue,
               "center half starts with no combination of its own")
        expect(Set(WindowLayoutAction.allCases.map(\.shortcutID)).count
                == WindowLayoutAction.allCases.count,
               "every layout action keeps a distinct shortcut id")
        for language in AppLanguage.allCases {
            let layoutStrings = FeatureStrings.windowLayout(language)
            expect(!layoutStrings.fullScreen.isEmpty && !layoutStrings.previousDisplay.isEmpty
                    && !layoutStrings.marginMaximize.isEmpty
                    && !layoutStrings.centerHalf.isEmpty,
                   "\(language.rawValue) names the latest window layout actions")
        }
        expect(WindowLayoutGeometry.accepts(actualRect: .zero, targetRect: .zero,
                                            action: .fullScreen, anchorTolerance: 10) == false,
               "full screen never joins the frame-based gesture acceptance")
        expect(WindowLayoutAction.center.targetCapability == .position
                && WindowLayoutAction.fullScreen.targetCapability == .fullScreen
                && WindowLayoutAction.maximize.targetCapability == .frame
                && WindowLayoutAction.restore.targetCapability == .position,
               "window layout targets only the attributes each action changes")

        // MARK: Editing, navigation and upper function keys as shortcuts (#308)

        let recorderModifiers: GlobalShortcutModifiers = [.control, .option, .command]
        let editingAndNavigationKeys: [(Int, String)] = [
            (kVK_Delete, "delete"), (kVK_ForwardDelete, "forward delete"),
            (kVK_Home, "home"), (kVK_End, "end"),
            (kVK_PageUp, "page up"), (kVK_PageDown, "page down"),
            (kVK_ANSI_KeypadEnter, "keypad enter"),
        ]
        for (keyCode, name) in editingAndNavigationKeys {
            let shortcut = GlobalShortcut(keyCode: Int64(keyCode), modifiers: recorderModifiers)
            expect(shortcut.isValid, "\(name) is recordable as a shortcut")
            expect(!shortcut.displayString.isEmpty
                   && shortcut.displayString != "Key \(keyCode)",
                   "\(name) prints a real cap instead of a raw key code")
        }
        let upperFunctionKeys: [(Int, String)] = [
            (kVK_F13, "F13"), (kVK_F14, "F14"), (kVK_F15, "F15"), (kVK_F16, "F16"),
            (kVK_F17, "F17"), (kVK_F18, "F18"), (kVK_F19, "F19"), (kVK_F20, "F20"),
        ]
        for (keyCode, name) in upperFunctionKeys {
            let shortcut = GlobalShortcut(keyCode: Int64(keyCode), modifiers: recorderModifiers)
            expect(shortcut.isValid, "\(name) is recordable as a shortcut")
            expect(shortcut.displayString.hasSuffix(name), "\(name) prints its own cap")
        }
        expect(Set(editingAndNavigationKeys.map {
                   GlobalShortcut(keyCode: Int64($0.0), modifiers: recorderModifiers).displayString
               }).count == editingAndNavigationKeys.count,
               "each editing and navigation key prints a cap of its own")

        // Delete on its own clears the field; held with a real modifier it is
        // an ordinary key and records like any other.
        expect(GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_Delete), modifiers: []),
               "delete alone clears the shortcut")
        expect(GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_ForwardDelete), modifiers: [.shift]),
               "forward delete with only Shift still clears the shortcut")
        expect(!GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_Delete), modifiers: recorderModifiers),
               "delete with a real modifier records instead of clearing")
        expect(!GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_ANSI_D), modifiers: []),
               "an ordinary key never clears the shortcut")
        expect(GlobalShortcut.finderRenameDefault.isValid
                && GlobalShortcut.finderRenameDefault.displayString == "F2"
                && GlobalShortcut(storageValue: GlobalShortcut.finderRenameDefault.storageValue)
                    == .finderRenameDefault,
               "a standalone function key records, displays and survives storage")
        expect(!GlobalShortcut(keyCode: Int64(kVK_ANSI_F), modifiers: []).isValid,
               "a bare letter still cannot become a shortcut")
        expect(GlobalShortcut.finderRenameDefault.matches(keyCode: Int64(kVK_F2), modifiers: [])
                && !GlobalShortcut.finderRenameDefault.matches(
                    keyCode: Int64(kVK_F2), modifiers: [.command]),
               "Finder rename matches the chosen key and no extra modifiers")

        // MARK: Shortcuts the app silences while a field is listening (#308)

        let silenced = GlobalShortcutRole.featuresToSilenceWhileRecording
        expect(Set(silenced).count == silenced.count,
               "the list of features to silence has no repeats")
        expect(GlobalShortcutRole.allCases.allSatisfy { silenced.contains($0.feature) },
               "every configurable shortcut's feature is silenced while recording")
        expect(silenced.contains(.windowLayout),
               "the window layout keys are silenced too, though they have no role")
        expect(silenced.contains(.finderRename),
               "the scoped Finder key steps aside while its recorder is listening")
        expect(silenced.contains(.switcher) && silenced.contains(.radialMenu)
               && silenced.contains(.keepAwake) && silenced.contains(.clipboardHistory),
               "the features that hold a global key are all in the silenced list")
        expect(silenced.allSatisfy { AppFeature.allCases.contains($0) },
               "the silenced list only names real features, so re-syncing them restores the keys")
        expect(registeredDefaults[DefaultsKey.extraBrightnessEnabled] as? Bool == false,
               "extra brightness is opt-in")
        expect(registeredDefaults[DefaultsKey.extraBrightnessLevel] as? Int == 100,
               "extra brightness starts at full intensity once enabled")
        expect(registeredDefaults[DefaultsKey.bluetoothSleepEnabled] as? Bool == false,
               "switching Bluetooth off on sleep is opt-in")
        expect(registeredDefaults[DefaultsKey.bluetoothSleepRestoreOnWake] as? Bool == true,
               "an enabled Bluetooth sleep feature puts Bluetooth back on wake")
        expect(registeredDefaults[DefaultsKey.bluetoothSleepRestorePending] as? Bool == false,
               "no Bluetooth restore is owed before the first sleep")
        expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.bluetoothSleepRestorePending),
               "a Bluetooth restore owed by one sleeping Mac never travels to another")
        expect(registeredDefaults[DefaultsKey.musicBlockEnabled] as? Bool == false,
               "blocking the music app from launching is opt-in")
        expect(registeredDefaults[DefaultsKey.musicBlockReplacementPath] as? String == "",
               "the music replacement app starts unset")
        expect(registeredDefaults[DefaultsKey.panelUtilityCleaner] as? Bool == true,
               "the cleaner row is visible in the panel utilities like its siblings")
        expect(registeredDefaults[DefaultsKey.cleanerScheduleFrequency] as? String == "off",
               "automatic cleanup is opt-in")
        expect(registeredDefaults[DefaultsKey.cleanerScheduleHour] as? Int == 9
               && registeredDefaults[DefaultsKey.cleanerScheduleMinute] as? Int == 0
               && registeredDefaults[DefaultsKey.cleanerScheduleWeekday] as? Int == 2,
               "the schedule defaults to nine in the morning on Mondays")
        expect(registeredDefaults[DefaultsKey.cleanerScheduleNotify] as? Bool == true,
               "the schedule reports its outcome unless the user opts out")
        expect(registeredDefaults[DefaultsKey.whatsAppDownloadsEnabled] as? Bool == false,
               "WhatsApp downloads stay hidden until the user turns them on")
        expect(registeredDefaults[DefaultsKey.whatsAppDownloadsAutomaticEnabled] as? Bool == false,
               "WhatsApp automatic cleanup is opt-in")
        expect(registeredDefaults[DefaultsKey.whatsAppDownloadsCategories] as? String
               == "image,video,audio",
               "WhatsApp cleanup starts with conservative media categories")
        expect(registeredDefaults[DefaultsKey.whatsAppDownloadsRetentionDays] as? Int == 7,
               "WhatsApp downloads keep a seven day default window")
        expect(registeredDefaults[DefaultsKey.whatsAppDownloadsAccessConfirmed] as? Bool == false,
               "WhatsApp cleanup never probes Downloads in the background before explicit access")
        expect(registeredDefaults[DefaultsKey.whatsAppOrganizerEnabled] as? Bool == false,
               "the experimental WhatsApp organizer is opt-in")
        expect(registeredDefaults[DefaultsKey.whatsAppOrganizerDelayMinutes] as? Int == 5
                && registeredDefaults[DefaultsKey.whatsAppOrganizerLayout] as? String == "flat"
                && registeredDefaults[DefaultsKey.whatsAppOrganizerDuplicateAction] as? String
                    == "trashNew",
               "the organizer starts with a five minute grace period and safe duplicate policy")
    }

    static func runSystemConflicts(expect: (Bool, String) -> Void) {
        // MARK: Update installer helpers

        expect(GlobalShortcutRole.activeRoles(isOn: { _ in false }).isEmpty,
               "no enabled gates means no active shortcuts")
        expect(GlobalShortcutRole.activeRoles(isOn: { $0 == DefaultsKey.hotkeyEnabled })
                   == [.keepAwake],
               "keep awake activates on its own gate alone")
        expect(!GlobalShortcutRole.activeRoles(isOn: { $0 == DefaultsKey.clipboardHistoryShortcutEnabled })
                   .contains(.clipboard),
               "the clipboard shortcut needs the feature on too")
        expect(GlobalShortcutRole.activeRoles(isOn: {
                   $0 == DefaultsKey.clipboardHistoryEnabled
                       || $0 == DefaultsKey.clipboardHistoryShortcutEnabled
               }).contains(.clipboard),
               "the clipboard shortcut activates with both gates on")
        expect(GlobalShortcutRole.conflict(for: .commandBarDefault,
                                           excluding: .quickLauncher,
                                           isOn: { _ in false },
                                           isAvailable: { _ in true }) == nil,
               "a disabled feature does not reserve its saved shortcut")
        expect(GlobalShortcutRole.conflict(for: .commandBarDefault,
                                           excluding: .quickLauncher,
                                           isOn: { $0 == DefaultsKey.commandBarShortcutEnabled },
                                           isAvailable: { _ in true }) == .commandBar,
               "an enabled feature keeps its saved shortcut reserved")
        expect(GlobalShortcutRole.conflict(for: .commandBarDefault,
                                           excluding: .quickLauncher,
                                           isOn: { _ in true },
                                           isAvailable: { $0 != .commandBar }) == nil,
               "a feature hidden from the hub does not reserve its shortcut")

        // macOS stores its own shortcuts as [character, key code, modifier mask],
        // the mask in NSEvent.ModifierFlags bits. 1 is S, 655360 is shift+option
        // — the combination "save picture of selected area as a file" carries
        // when someone moves it off its factory keys.
        func systemHotKey(_ id: String, enabled: Bool,
                          keyCode: Int, mask: Int, type: String = "standard") -> [String: Any] {
            [id: ["enabled": NSNumber(value: enabled),
                  "value": ["type": type,
                            "parameters": [NSNumber(value: 115),
                                           NSNumber(value: keyCode),
                                           NSNumber(value: mask)]]]]
        }
        let systemAreaShot = systemHotKey("30", enabled: true, keyCode: 1, mask: 655360)
        let optionShiftS = GlobalShortcut(keyCode: 1, modifiers: [.option, .shift])

        expect(GlobalShortcut.matchesSystemShortcut(optionShiftS,
                                                    symbolicHotKeys: systemAreaShot),
               "a combination macOS already answers is reported as taken")
        expect(!GlobalShortcut.matchesSystemShortcut(.screenshotDefault,
                                                     symbolicHotKeys: systemAreaShot),
               "the default screenshot shortcut stays clear of the system list")
        expect(!GlobalShortcut.matchesSystemShortcut(
                    GlobalShortcut(keyCode: 1, modifiers: [.command, .shift]),
                    symbolicHotKeys: systemAreaShot),
               "the same key with other modifiers is a different shortcut")
        expect(!GlobalShortcut.matchesSystemShortcut(
                    optionShiftS,
                    symbolicHotKeys: systemHotKey("30", enabled: false, keyCode: 1, mask: 655360)),
               "a system shortcut the user switched off is not in the way")
        expect(!GlobalShortcut.matchesSystemShortcut(
                    GlobalShortcut(keyCode: 0xFFFF, modifiers: [.option, .shift]),
                    symbolicHotKeys: systemHotKey("30", enabled: true,
                                                  keyCode: 0xFFFF, mask: 655360)),
               "an entry with no key assigned matches nothing")
        expect(!GlobalShortcut.matchesSystemShortcut(
                    optionShiftS,
                    symbolicHotKeys: systemHotKey("30", enabled: true, keyCode: 1,
                                                  mask: 655360, type: "modifier")),
               "an entry that is not a plain key combination is left alone")
        expect(!GlobalShortcut.matchesSystemShortcut(
                    optionShiftS,
                    symbolicHotKeys: ["30": ["enabled": NSNumber(value: true)]]),
               "an entry with no parameters is ignored rather than guessed at")
        expect(!GlobalShortcut.matchesSystemShortcut(optionShiftS, symbolicHotKeys: nil),
               "an unreadable system list reserves nothing")

        // The WindowServer table stores Carbon modifier bits. Arrow and F keys
        // carry the function-key bit there as well; it is a property of the key,
        // not a modifier the recorder ever records, so it must drop out.
        expect(GlobalShortcutModifiers(
                    cgFlags: SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x20000 | 0x100000))
               == [.shift, .command],
               "Carbon shift and command bits convert to the recorder's modifiers")
        expect(GlobalShortcutModifiers(
                    cgFlags: SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x40000 | 0x800000))
               == [.control],
               "the function-key bit on arrow and F keys is not a recorded modifier")

        // The live table is the authority. The preferences plist only lists
        // customised entries, so a factory ⌘⇧4 is absent from it and used to
        // pass the check while macOS still answered the key.
        let liveAreaShot = LiveSystemShortcut(
            id: 30, shortcut: GlobalShortcut(keyCode: 21, modifiers: [.command, .shift]), enabled: true)
        let liveSpotlightOff = LiveSystemShortcut(
            id: 64, shortcut: GlobalShortcut(keyCode: 49, modifiers: [.command]), enabled: false)
        // An unassigned row never reaches a real snapshot, but the matcher must refuse it even if one did.
        let liveUnassigned = LiveSystemShortcut(
            id: 99, shortcut: GlobalShortcut(keyCode: 0xFFFF, modifiers: [.command, .shift]), enabled: true)
        let liveTable = [liveAreaShot, liveSpotlightOff, liveUnassigned]
        expect(GlobalShortcut.matchesLiveSystemShortcut(
                    GlobalShortcut(keyCode: 21, modifiers: [.command, .shift]), entries: liveTable),
               "a factory screenshot key macOS still answers is reported as taken")
        expect(!GlobalShortcut.matchesLiveSystemShortcut(
                    GlobalShortcut(keyCode: 49, modifiers: [.command]), entries: liveTable),
               "a system shortcut switched off in the live table is not in the way")
        expect(!GlobalShortcut.matchesLiveSystemShortcut(
                    GlobalShortcut(keyCode: 21, modifiers: [.command, .shift, .control]), entries: liveTable),
               "the same key with other modifiers is a different shortcut in the live table")
        expect(!GlobalShortcut.matchesLiveSystemShortcut(
                    GlobalShortcut(keyCode: 0xFFFF, modifiers: [.command, .shift]), entries: liveTable),
               "an unassigned key code never matches a live entry")
        expect(!GlobalShortcut.matchesLiveSystemShortcut(.screenshotDefault, entries: liveTable),
               "the default screenshot shortcut stays clear of the live table")
        expect(!GlobalShortcut.matchesLiveSystemShortcut(
                    GlobalShortcut(keyCode: 21, modifiers: [.command, .shift]), entries: []),
               "an empty live table reserves nothing")

        // The decision between the two sources: a populated live table is the
        // authority; a missing or empty one hands the question to the plist.
        expect(GlobalShortcut.conflictsWithSystemShortcut(optionShiftS,
                                                          liveEntries: nil,
                                                          symbolicHotKeys: systemAreaShot),
               "without the private calls the plist still answers")
        expect(GlobalShortcut.conflictsWithSystemShortcut(optionShiftS,
                                                          liveEntries: [],
                                                          symbolicHotKeys: systemAreaShot),
               "an empty live read falls back to the plist instead of clearing everything")
        expect(!GlobalShortcut.conflictsWithSystemShortcut(optionShiftS,
                                                           liveEntries: liveTable,
                                                           symbolicHotKeys: systemAreaShot),
               "a populated live table is the authority even where the plist disagrees")
        expect(GlobalShortcut.conflictsWithSystemShortcut(
                    GlobalShortcut(keyCode: 21, modifiers: [.command, .shift]),
                    liveEntries: liveTable,
                    symbolicHotKeys: nil),
               "a live match needs no plist at all")

        let nativeShortcutRecordingCases: [(GlobalShortcutRole, Int32, GlobalShortcut)] = [
            (.switcher, 1, .switcherDefault),
            (.switcher, 2, GlobalShortcut(keyCode: Int64(kVK_Tab), modifiers: [.command, .shift])),
            (.switcherWindow, 27, .switcherWindowDefault),
            (.switcherWindow, 220, GlobalShortcut(keyCode: 94, modifiers: [.command, .shift])),
        ]
        for (role, id, shortcut) in nativeShortcutRecordingCases {
            let live = [LiveSystemShortcut(id: id, shortcut: shortcut, enabled: true)]
            let fallback = systemHotKey(String(id), enabled: true, keyCode: Int(shortcut.keyCode),
                                        mask: Int(shortcut.modifiers.cgFlags.rawValue))
            expect(!GlobalShortcut.conflictsWithSystemShortcut(
                shortcut, liveEntries: live, symbolicHotKeys: nil, role: role),
                   "the switcher can record its own enabled native shortcut without system takeover")
            expect(!GlobalShortcut.conflictsWithSystemShortcut(
                shortcut, liveEntries: [], symbolicHotKeys: fallback, role: role),
                   "the switcher shortcut exception also respects remapped keys in the fallback table")
            expect(GlobalShortcut.conflictsWithSystemShortcut(
                shortcut, liveEntries: live, symbolicHotKeys: fallback, role: .screenshot),
                   "other tools cannot take the switcher's native shortcuts")
            let overlapping = live + [LiveSystemShortcut(id: 30, shortcut: shortcut, enabled: true)]
            expect(GlobalShortcut.conflictsWithSystemShortcut(
                shortcut, liveEntries: overlapping, symbolicHotKeys: nil, role: role),
                   "the switcher still reports an unrelated system action assigned to the same keys")
        }
        expect(GlobalShortcut.conflictsWithSystemShortcut(
            .switcherWindowDefault,
            liveEntries: [LiveSystemShortcut(id: 27, shortcut: .switcherWindowDefault, enabled: true)],
            symbolicHotKeys: nil, role: .switcher),
               "the native exception stays scoped to the corresponding switcher action")
    }
}
