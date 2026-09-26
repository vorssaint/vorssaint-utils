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

enum UpdateFeatureTests {
    static func run(_ suite: TestSuite) {
        func activeSet(_ permission: AppPermission,
                       available: Set<AppFeature> = Set(AppFeature.allCases),
                       on: Set<String> = [],
                       strings: [String: String] = [:]) -> Set<AppFeature> {
            Set(AppFeature.activeFeatures(using: permission,
                                          isAvailable: { available.contains($0) },
                                          boolFor: { on.contains($0) },
                                          stringFor: { strings[$0] }))
        }
        // MARK: Update installer helpers

        suite.expect(GlobalShortcutRole.activeRoles(isOn: { _ in false }).isEmpty,
               "no enabled gates means no active shortcuts")
        suite.expect(GlobalShortcutRole.activeRoles(isOn: { $0 == DefaultsKey.hotkeyEnabled })
                   == [.keepAwake],
               "keep awake activates on its own gate alone")
        suite.expect(!GlobalShortcutRole.activeRoles(isOn: { $0 == DefaultsKey.clipboardHistoryShortcutEnabled })
                   .contains(.clipboard),
               "the clipboard shortcut needs the feature on too")
        suite.expect(GlobalShortcutRole.activeRoles(isOn: {
                   $0 == DefaultsKey.clipboardHistoryEnabled
                       || $0 == DefaultsKey.clipboardHistoryShortcutEnabled
               }).contains(.clipboard),
               "the clipboard shortcut activates with both gates on")
        suite.expect(GlobalShortcutRole.conflict(for: .commandBarDefault,
                                           excluding: .quickLauncher,
                                           isOn: { _ in false },
                                           isAvailable: { _ in true }) == nil,
               "a disabled feature does not reserve its saved shortcut")
        suite.expect(GlobalShortcutRole.conflict(for: .commandBarDefault,
                                           excluding: .quickLauncher,
                                           isOn: { $0 == DefaultsKey.commandBarShortcutEnabled },
                                           isAvailable: { _ in true }) == .commandBar,
               "an enabled feature keeps its saved shortcut reserved")
        suite.expect(GlobalShortcutRole.conflict(for: .commandBarDefault,
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

        suite.expect(GlobalShortcut.matchesSystemShortcut(optionShiftS,
                                                    symbolicHotKeys: systemAreaShot),
               "a combination macOS already answers is reported as taken")
        suite.expect(!GlobalShortcut.matchesSystemShortcut(.screenshotDefault,
                                                     symbolicHotKeys: systemAreaShot),
               "the default screenshot shortcut stays clear of the system list")
        suite.expect(!GlobalShortcut.matchesSystemShortcut(
                    GlobalShortcut(keyCode: 1, modifiers: [.command, .shift]),
                    symbolicHotKeys: systemAreaShot),
               "the same key with other modifiers is a different shortcut")
        suite.expect(!GlobalShortcut.matchesSystemShortcut(
                    optionShiftS,
                    symbolicHotKeys: systemHotKey("30", enabled: false, keyCode: 1, mask: 655360)),
               "a system shortcut the user switched off is not in the way")
        suite.expect(!GlobalShortcut.matchesSystemShortcut(
                    GlobalShortcut(keyCode: 0xFFFF, modifiers: [.option, .shift]),
                    symbolicHotKeys: systemHotKey("30", enabled: true,
                                                  keyCode: 0xFFFF, mask: 655360)),
               "an entry with no key assigned matches nothing")
        suite.expect(!GlobalShortcut.matchesSystemShortcut(
                    optionShiftS,
                    symbolicHotKeys: systemHotKey("30", enabled: true, keyCode: 1,
                                                  mask: 655360, type: "modifier")),
               "an entry that is not a plain key combination is left alone")
        suite.expect(!GlobalShortcut.matchesSystemShortcut(
                    optionShiftS,
                    symbolicHotKeys: ["30": ["enabled": NSNumber(value: true)]]),
               "an entry with no parameters is ignored rather than guessed at")
        suite.expect(!GlobalShortcut.matchesSystemShortcut(optionShiftS, symbolicHotKeys: nil),
               "an unreadable system list reserves nothing")

        // The WindowServer table stores Carbon modifier bits. Arrow and F keys
        // carry the function-key bit there as well; it is a property of the key,
        // not a modifier the recorder ever records, so it must drop out.
        suite.expect(GlobalShortcutModifiers(
                    cgFlags: SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x20000 | 0x100000))
               == [.shift, .command],
               "Carbon shift and command bits convert to the recorder's modifiers")
        suite.expect(GlobalShortcutModifiers(
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
        suite.expect(GlobalShortcut.matchesLiveSystemShortcut(
                    GlobalShortcut(keyCode: 21, modifiers: [.command, .shift]), entries: liveTable),
               "a factory screenshot key macOS still answers is reported as taken")
        suite.expect(!GlobalShortcut.matchesLiveSystemShortcut(
                    GlobalShortcut(keyCode: 49, modifiers: [.command]), entries: liveTable),
               "a system shortcut switched off in the live table is not in the way")
        suite.expect(!GlobalShortcut.matchesLiveSystemShortcut(
                    GlobalShortcut(keyCode: 21, modifiers: [.command, .shift, .control]), entries: liveTable),
               "the same key with other modifiers is a different shortcut in the live table")
        suite.expect(!GlobalShortcut.matchesLiveSystemShortcut(
                    GlobalShortcut(keyCode: 0xFFFF, modifiers: [.command, .shift]), entries: liveTable),
               "an unassigned key code never matches a live entry")
        suite.expect(!GlobalShortcut.matchesLiveSystemShortcut(.screenshotDefault, entries: liveTable),
               "the default screenshot shortcut stays clear of the live table")
        suite.expect(!GlobalShortcut.matchesLiveSystemShortcut(
                    GlobalShortcut(keyCode: 21, modifiers: [.command, .shift]), entries: []),
               "an empty live table reserves nothing")

        // The decision between the two sources: a populated live table is the
        // authority; a missing or empty one hands the question to the plist.
        suite.expect(GlobalShortcut.conflictsWithSystemShortcut(optionShiftS,
                                                          liveEntries: nil,
                                                          symbolicHotKeys: systemAreaShot),
               "without the private calls the plist still answers")
        suite.expect(GlobalShortcut.conflictsWithSystemShortcut(optionShiftS,
                                                          liveEntries: [],
                                                          symbolicHotKeys: systemAreaShot),
               "an empty live read falls back to the plist instead of clearing everything")
        suite.expect(!GlobalShortcut.conflictsWithSystemShortcut(optionShiftS,
                                                           liveEntries: liveTable,
                                                           symbolicHotKeys: systemAreaShot),
               "a populated live table is the authority even where the plist disagrees")
        suite.expect(GlobalShortcut.conflictsWithSystemShortcut(
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
            suite.expect(!GlobalShortcut.conflictsWithSystemShortcut(
                shortcut, liveEntries: live, symbolicHotKeys: nil, role: role),
                   "the switcher can record its own enabled native shortcut without system takeover")
            suite.expect(!GlobalShortcut.conflictsWithSystemShortcut(
                shortcut, liveEntries: [], symbolicHotKeys: fallback, role: role),
                   "the switcher shortcut exception also respects remapped keys in the fallback table")
            suite.expect(GlobalShortcut.conflictsWithSystemShortcut(
                shortcut, liveEntries: live, symbolicHotKeys: fallback, role: .screenshot),
                   "other tools cannot take the switcher's native shortcuts")
            let overlapping = live + [LiveSystemShortcut(id: 30, shortcut: shortcut, enabled: true)]
            suite.expect(GlobalShortcut.conflictsWithSystemShortcut(
                shortcut, liveEntries: overlapping, symbolicHotKeys: nil, role: role),
                   "the switcher still reports an unrelated system action assigned to the same keys")
        }
        suite.expect(GlobalShortcut.conflictsWithSystemShortcut(
            .switcherWindowDefault,
            liveEntries: [LiveSystemShortcut(id: 27, shortcut: .switcherWindowDefault, enabled: true)],
            symbolicHotKeys: nil, role: .switcher),
               "the native exception stays scoped to the corresponding switcher action")

        suite.expect(UpdateInstallerSupport.progressStepAdvanced(from: nil, to: 0.004),
               "the first known download fraction always publishes")
        suite.expect(!UpdateInstallerSupport.progressStepAdvanced(from: 0.011, to: 0.019),
               "fractions inside the same percent stay quiet")
        suite.expect(UpdateInstallerSupport.progressStepAdvanced(from: 0.019, to: 0.021),
               "crossing into the next percent publishes")
        suite.expect(!UpdateInstallerSupport.progressStepAdvanced(from: 0.5, to: 0.5),
               "an unchanged fraction stays quiet")

        let updateCeiling = UpdateInstallerSupport.downloadCeilingBytes
        suite.expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: 9_638_011) == 9_638_011,
               "a download stops at the size the release advertises")
        suite.expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: nil) == updateCeiling,
               "an asset with no size still stops at the ceiling")
        suite.expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: 0) == updateCeiling,
               "a zero size is not a limit of zero")
        suite.expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: updateCeiling + 1) == updateCeiling,
               "an advertised size beyond the ceiling cannot raise it")

        suite.expect(UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                       receivedBytes: 9_638_011,
                                                       expectedBytes: 9_638_011),
               "a complete asset download is handed to the installer")
        suite.expect(!UpdateInstallerSupport.downloadIsUsable(status: 404,
                                                        receivedBytes: 1_200,
                                                        expectedBytes: 9_638_011),
               "an error page is refused whatever it contains")
        suite.expect(!UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                        receivedBytes: 4_000_000,
                                                        expectedBytes: 9_638_011),
               "a truncated body is refused")
        suite.expect(!UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                        receivedBytes: 0,
                                                        expectedBytes: nil),
               "an empty body is refused even with no advertised size")
        suite.expect(!UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                        receivedBytes: updateCeiling + 1,
                                                        expectedBytes: nil),
               "a body past the ceiling is refused with no advertised size")
        suite.expect(UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                       receivedBytes: 9_638_011,
                                                       expectedBytes: nil),
               "a plausible body with no advertised size is accepted")

        // The showcase loader is a @StateObject, so it can be released without
        // `.onDisappear` running. Its session holds the download delegate, and
        // that delegate's deinit is what deletes the scratch file, so the
        // release path has to invalidate the session too.
        let showcaseSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Update/UpdateShowcaseMedia.swift",
            encoding: .utf8)) ?? ""
        let showcaseDeinitBody = (showcaseSource.components(separatedBy: "\n    deinit {")
            .dropFirst().first ?? "").components(separatedBy: "\n    }").first ?? ""
        suite.expect(showcaseDeinitBody.contains("session?.invalidateAndCancel()"),
               "a released showcase loader invalidates its session, freeing the delegate and its scratch file")
        suite.expect(!showcaseDeinitBody.contains("finishTasksAndInvalidate"),
               "a released showcase loader cancels its download instead of letting it finish")

        suite.expect(SettingsSearchSupport.matches(query: "", title: "Monitor"),
               "a blank settings search matches everything")
        suite.expect(SettingsSearchSupport.matches(query: "moni", title: "Monitor"),
               "settings search is case-insensitive prefix-friendly")
        suite.expect(SettingsSearchSupport.matches(query: "musica", title: "Música"),
               "settings search ignores accents")
        suite.expect(!SettingsSearchSupport.matches(query: "shelf", title: "Monitor"),
               "settings search filters out non-matches")
        suite.expect(SettingsSearchSupport.matches(query: "  switcher ", title: "Switcher"),
               "settings search trims surrounding whitespace")
        suite.expect(SettingsSearchSupport.filteredIndices(query: "mo",
                                                     sections: [["Monitor", "Shelf"], ["Mouse"]])
                   == [[0], [0]],
               "settings search keeps matching rows per section")
        suite.expect(SettingsSearchSupport.matches(query: "lid", title: "Energy",
                                             keywords: ["Keep going with the lid closed"]),
               "settings search finds a page by an option living inside it")
        suite.expect(!SettingsSearchSupport.matches(query: "lid", title: "Energy", keywords: []),
               "without keywords the same query stays a miss")
        suite.expect(SettingsSearchSupport.matches(
            query: "preview position",
            title: FeatureStrings.screenshot(.enUS).pageTitle,
            keywords: [FeatureStrings.screenshot(.enUS).previewPositionLabel]),
               "preview position is a searchable Screenshot keyword")
        suite.expect(SettingsSearchSupport.matches(query: "hide",
                                             title: Strings.enUS.tabSwitcher,
                                             keywords: [Strings.enUS.dockClickHide]),
               "Dock hiding is findable through a localized Settings keyword")
        let captureSearchKeywords = SettingsSearchSupport.screenCaptureKeywords(
            Strings.enUS, language: .enUS)
        suite.expect(SettingsSearchSupport.matches(
                    query: "screenshot",
                    title: FeatureStrings.screenshot(.enUS).screenCaptureTitle,
                    keywords: captureSearchKeywords)
                && SettingsSearchSupport.matches(
                    query: "screen recording",
                    title: FeatureStrings.screenshot(.enUS).screenCaptureTitle,
                    keywords: captureSearchKeywords)
                && SettingsSearchSupport.matches(
                    query: "line breaks",
                    title: FeatureStrings.screenshot(.enUS).screenCaptureTitle,
                    keywords: captureSearchKeywords),
               "Screen capture tools and their options find the one settings page")

        let quickToolFeatures: [AppFeature] = [.quickLauncher, .micMute, .scratchpad, .cleaningMode]
        let quickToolRows = SettingsSidebarSupport.items(
            page: .quickTools, title: "Quick panel", icon: "wand.and.rays",
            preferredFeatures: quickToolFeatures, includePage: false,
            isAvailable: { quickToolFeatures.contains($0) },
            featureTitle: { $0.rawValue })
        let generalFeatures: [AppFeature] = [
            .musicBlock, .mixer, .soundOutputSwitcher, .audioPriority,
        ]
        let generalRows = SettingsSidebarSupport.items(
            page: .general, title: "General", icon: "gearshape",
            preferredFeatures: [.musicBlock], includePage: true,
            isAvailable: { generalFeatures.contains($0) },
            featureTitle: { $0.rawValue })
        let toolRows = generalRows + quickToolRows
        func toolRow(_ feature: AppFeature) -> SettingsSidebarItem? {
            toolRows.first { $0.id == .feature(feature) }
        }
        suite.expect(toolRow(.musicBlock)?.icon == AppFeature.musicBlock.symbolName
                && toolRow(.mixer)?.icon == AppFeature.mixer.symbolName
                && toolRow(.soundOutputSwitcher)?.icon == AppFeature.soundOutputSwitcher.symbolName
                && toolRow(.audioPriority)?.icon == AppFeature.audioPriority.symbolName
                && toolRow(.micMute)?.icon == AppFeature.micMute.symbolName
                && toolRow(.scratchpad)?.icon == AppFeature.scratchpad.symbolName
                && toolRow(.cleaningMode)?.icon == AppFeature.cleaningMode.symbolName,
               "shared Settings pages expose every anchored tool with its own symbol")
        suite.expect(toolRows.count == Set(toolRows.map(\.id)).count
                && !quickToolRows.contains { $0.id == .page(.quickTools) }
                && toolRow(.mixer)?.destination
                    == FeatureSettingsDestination(.general, sectionAnchor: .mixer)
                && toolRow(.soundOutputSwitcher)?.destination
                    == FeatureSettingsDestination(.general, sectionAnchor: .soundOutputSwitcher)
                && toolRow(.audioPriority)?.destination
                    == FeatureSettingsDestination(.general, sectionAnchor: .audioPriority)
                && SettingsSidebarSupport.selection(for: AppFeature.scratchpad.settingsDestination,
                                                    in: toolRows) == .feature(.scratchpad)
                && SettingsSidebarSupport.selection(for: AppFeature.audioPriority.settingsDestination,
                                                    in: toolRows, preferredID: .feature(.audioPriority))
                    == .feature(.audioPriority),
               "flat tool rows keep unique identities and select the clicked tool")
        let menuBarDestination = FeatureSettingsDestination(
            .general, sectionAnchor: .panelConfiguration)
        let menuBarRow = SettingsSidebarItem(
            id: .setting(.panelConfiguration), destination: menuBarDestination,
            title: "Menu bar", icon: "menubar.rectangle")
        suite.expect(SettingsSidebarSupport.selection(
            for: FeatureSettingsDestination(.general),
            in: generalRows + [menuBarRow]) == .page(.general)
            && SettingsSidebarSupport.selection(
                for: menuBarDestination,
                in: generalRows + [menuBarRow]) == .setting(.panelConfiguration),
            "General and its menu bar editor keep distinct sidebar selections")
        let scratchpadOnlyRows = SettingsSidebarSupport.items(
            page: .quickTools, title: "Quick panel", icon: "wand.and.rays",
            preferredFeatures: quickToolFeatures, includePage: false,
            isAvailable: { $0 == .scratchpad },
            featureTitle: { $0.rawValue })
        suite.expect(scratchpadOnlyRows.count == 1
                && scratchpadOnlyRows.first?.id == .feature(.scratchpad)
                && SettingsSidebarSupport.selection(for: AppFeature.micMute.settingsDestination,
                                                    in: scratchpadOnlyRows) == .feature(.scratchpad),
               "the sidebar hides unavailable tools and keeps a visible selection for their page")
        let scrollingRows = SettingsSidebarSupport.items(
            page: .mouse, title: "Mouse", icon: "computermouse",
            preferredFeatures: [.scrollInverter, .scrollHorizontal], includePage: false,
            isAvailable: { [.scrollInverter, .scrollHorizontal].contains($0) },
            featureTitle: { $0.rawValue })
        let sidewaysOnlyRows = SettingsSidebarSupport.items(
            page: .mouse, title: "Mouse", icon: "computermouse",
            preferredFeatures: [.scrollInverter, .scrollHorizontal], includePage: false,
            isAvailable: { $0 == .scrollHorizontal }, featureTitle: { $0.rawValue })
        suite.expect(scrollingRows.count == 2
                && Set(scrollingRows.map(\.id)) == [.feature(.scrollInverter),
                                                    .feature(.scrollHorizontal)]
                && scrollingRows[0].destination == scrollingRows[1].destination
                && sidewaysOnlyRows.first?.id == .feature(.scrollHorizontal),
               "tools sharing a section keep separate named rows")
        let keyboardDestination = FeatureSettingsDestination(
            .shortcuts, sectionAnchor: .keyboardBrightnessShortcuts)
        let keyboardShortcutItem = SettingsSearchSupport.keyboardBrightnessShortcutItem(language: .enUS)
        let shortcutPageItem = SettingsSearchItem(
            id: .page(.shortcuts), destination: FeatureSettingsDestination(.shortcuts),
            title: "Shortcuts", icon: "command")
        let keyboardShortcutGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "keyboard brightness shortcuts",
            items: [shortcutPageItem, keyboardShortcutItem],
            isAvailable: { _ in true })
        suite.expect(keyboardShortcutGroups.first?.id == .shortcuts
                && keyboardShortcutGroups.first?.suggestions.first.map {
                    SettingsSearchSupport.route(for: $0, isAvailable: { _ in true }).destination
                } == keyboardDestination,
               "keyboard brightness shortcut search reveals its own Shortcuts section")
        let keyboardLightGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "keyboard light", items: [shortcutPageItem, keyboardShortcutItem],
            isAvailable: { _ in true })
        suite.expect(keyboardLightGroups.first?.suggestions.first.map {
            SettingsSearchSupport.route(for: $0, isAvailable: { _ in true }).destination
        } == keyboardDestination,
               "searching the sidebar label also opens keyboard brightness shortcuts")
        suite.expect(AppLanguage.allCases.allSatisfy { language in
            let item = SettingsSearchSupport.keyboardBrightnessShortcutItem(language: language)
            return SettingsSearchSupport.matches(
                query: FeatureStrings.brightness(language).keyboardLight,
                title: item.title, keywords: item.keywords)
        }, "search finds keyboard brightness shortcuts by their sidebar name in every language")

        let settingsFeatureTitles: [AppFeature: String] = [
            .homebrew: "Homebrew",
            .cameraPreview: "Camera Preview",
            .screenRecorder: "Screen Recorder",
            .micMute: "Mic Mute",
            .diskImageInstaller: "Disk Image Installer",
        ]
        let featureSearchItems = SettingsSearchSupport.featureItems(language: .enUS) { feature in
            settingsFeatureTitles[feature] ?? feature.rawValue
        }
        let expectedFeatureSearchDestinations: [(AppFeature, FeatureSettingsDestination)] = [
            (.homebrew, FeatureSettingsDestination(.homebrew)),
            (.cameraPreview, FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview)),
            (.screenRecorder, FeatureSettingsDestination(.screenshot, sectionAnchor: .screenRecorder)),
            (.micMute, FeatureSettingsDestination(.quickTools, sectionAnchor: .micMute)),
            (.diskImageInstaller, FeatureSettingsDestination(.features)),
        ]
        for (feature, destination) in expectedFeatureSearchDestinations {
            let item = featureSearchItems.first { $0.id == .feature(feature) }
            suite.expect(item?.destination == destination,
                   "\(settingsFeatureTitles[feature] ?? feature.rawValue) keeps its exact Settings destination")
            suite.expect(item?.icon == feature.symbolName,
                   "\(settingsFeatureTitles[feature] ?? feature.rawValue) uses its feature symbol")
        }
        suite.expect(featureSearchItems.count == AppFeature.allCases.count
                && Set(featureSearchItems.map(\.id)).count == AppFeature.allCases.count,
               "generated Settings feature results have one stable identity per feature")

        for language in AppLanguage.allCases {
            let pageTitle = FeatureStrings.clipboard(language).title
            let clipboardPage = SettingsSearchItem(
                id: .page(.clipboard), destination: FeatureSettingsDestination(.clipboard),
                title: pageTitle, icon: "doc.on.clipboard")
            let featureItems = SettingsSearchSupport.featureItems(language: language) {
                $0 == .clipboardHistory ? pageTitle : $0.rawValue
            }
            let items = SettingsSearchSupport.combinedItems(
                pageItems: [clipboardPage], featureItems: featureItems)
            let clipboardHistory = items.first { $0.id == .feature(.clipboardHistory) }
            suite.expect(clipboardHistory?.title == FeatureStrings.commandBar(language).sourceClipboard
                    && clipboardHistory?.destination
                        == FeatureSettingsDestination(.clipboard, sectionAnchor: .clipboardHistory),
                   "\(language.rawValue) labels and routes Clipboard history as a section result")
            suite.expect(items.contains { $0.id == .page(.clipboard) }
                    && clipboardPage.title != clipboardHistory?.title,
                   "\(language.rawValue) distinguishes Clipboard page and history search labels")
        }

        // MARK: Settings search structural deduplication
        let structuralPage = SettingsSearchItem(
            id: .page(.homebrew), destination: FeatureSettingsDestination(.homebrew),
            title: "Dedicated Packages Page", icon: "shippingbox", keywords: ["Formulae"])
        let structuralFeature = SettingsSearchItem(
            id: .feature(.homebrew), destination: FeatureSettingsDestination(.homebrew),
            title: "Generated Homebrew Feature", icon: "externaldrive", feature: .homebrew)
        let structurallyMerged = SettingsSearchSupport.combinedItems(
            pageItems: [structuralPage], featureItems: [structuralFeature])
        suite.expect(structurallyMerged.map(\.id) == [.page(.homebrew)]
                && structurallyMerged.first?.title == "Dedicated Packages Page"
                && structurallyMerged.first?.icon == "shippingbox"
                && structurallyMerged.first?.keywords == ["Formulae"]
                && structurallyMerged.first?.feature == .homebrew,
               "differently titled Homebrew rows merge into the stable page row")

        let monitorPage = SettingsSearchItem(id: .page(.monitor),
                                             destination: FeatureSettingsDestination(.monitor),
                                             title: "Monitor", icon: "display")
        let monitorCPUFeature = SettingsSearchSupport.featureItems(language: .enUS) {
            $0 == .monitorCPU ? "Generated CPU Monitor" : $0.rawValue
        }.first { $0.id == .feature(.monitorCPU) }!
        let multiFeatureMerged = SettingsSearchSupport.combinedItems(
            pageItems: [monitorPage], featureItems: [monitorCPUFeature])
        suite.expect(monitorPage.destination == monitorCPUFeature.destination
                && monitorCPUFeature.destination == AppFeature.monitorCPU.settingsDestination
                && monitorCPUFeature.destination.sectionAnchor == nil
                && multiFeatureMerged.map(\.id) == [.page(.monitor), .feature(.monitorCPU)],
               "the real shared Monitor destination does not merge a multi-feature page")

        let actionCoveredMappings: [(SettingsPage, AppFeature)] = [
            (.cleaner, .cleaner),
            (.uninstaller, .uninstaller),
            (.appUpdates, .appUpdates),
        ]
        let actionCoveredPages = actionCoveredMappings.map { page, feature in
            SettingsSearchItem(id: .page(page), destination: FeatureSettingsDestination(page),
                               title: "Dedicated \(feature.rawValue) Page", icon: "gearshape")
        }
        let actionCoveredFeatures = SettingsSearchSupport.featureItems(language: .enUS) {
            "Generated \($0.rawValue) Feature"
        }.filter { item in
            actionCoveredMappings.contains { _, feature in item.id == .feature(feature) }
        }
        let actionCoveredItems = SettingsSearchSupport.combinedItems(
            pageItems: actionCoveredPages, featureItems: actionCoveredFeatures)
        for (page, feature) in actionCoveredMappings {
            suite.expect(actionCoveredItems.first { $0.id == .page(page) }?.feature == feature
                    && !actionCoveredItems.contains { $0.id == .feature(feature) },
                   "the differently titled \(feature.rawValue) rows keep only the page identity")
        }

        let dedicatedSettingsItems = [
            SettingsSearchItem(id: .page(.features),
                                destination: FeatureSettingsDestination(.features),
                                title: "Features", icon: "square.grid.2x2",
                                keywords: ["Homebrew", "Camera Preview"],
                                keywordFeatures: [.homebrew, .cameraPreview]),
            SettingsSearchItem(id: .page(.appUpdates),
                                destination: FeatureSettingsDestination(.appUpdates),
                                title: "App Updates", icon: "arrow.down.app",
                                keywords: ["Homebrew"]),
            SettingsSearchItem(id: .page(.quickTools),
                                destination: FeatureSettingsDestination(.quickTools),
                                title: "Quick Tools", icon: "wand.and.rays",
                                keywords: ["Camera Preview"]),
            SettingsSearchItem(id: .page(.homebrew),
                                destination: FeatureSettingsDestination(.homebrew),
                                title: "Homebrew", icon: "shippingbox"),
        ]
        let combinedSettingsItems = SettingsSearchSupport.combinedItems(
            pageItems: dedicatedSettingsItems,
            featureItems: featureSearchItems)
        suite.expect(combinedSettingsItems.filter {
            $0.title == "Homebrew" && $0.destination == FeatureSettingsDestination(.homebrew)
        }.count == 1
                && combinedSettingsItems.contains { $0.id == .page(.homebrew) },
               "the explicit Homebrew page result replaces its equivalent generated result")
        suite.expect(combinedSettingsItems.filter {
            $0.destination == FeatureSettingsDestination(.appUpdates)
        }.count == 1
                && combinedSettingsItems.contains { $0.id == .page(.appUpdates) },
               "a structurally one-to-one App Updates result is deduplicated to the page")
        suite.expect(combinedSettingsItems.contains { $0.id == .feature(.diskImageInstaller) },
               "a differently named feature remains discoverable through its Features fallback")
        suite.expect(combinedSettingsItems.first { $0.id == .page(.homebrew) }?.feature == .homebrew,
               "a deduplicated Homebrew page result keeps its feature identity")
        suite.expect(combinedSettingsItems.first { $0.id == .page(.features) }?.feature == nil,
               "a generic page result that does not merge with a feature carries no feature identity")
        suite.expect(combinedSettingsItems.first { $0.id == .feature(.diskImageInstaller) }?.feature
                == .diskImageInstaller,
               "a feature-only result carries its own feature identity")

        // MARK: Settings search routing

        let homebrewPageItem = combinedSettingsItems.first { $0.id == .page(.homebrew) }!
        let unavailableHomebrewRoute = SettingsSearchSupport.route(for: homebrewPageItem) { _ in false }
        suite.expect(unavailableHomebrewRoute.destination == FeatureSettingsDestination(.features)
                && unavailableHomebrewRoute.targetFeature == .homebrew,
               "an unavailable Homebrew result preserves its identity and targets its Feature Hub row")
        let availableHomebrewRoute = SettingsSearchSupport.route(for: homebrewPageItem) { _ in true }
        suite.expect(availableHomebrewRoute.destination == FeatureSettingsDestination(.homebrew)
                && availableHomebrewRoute.targetFeature == nil,
               "an available Homebrew result still opens its own dedicated page with no row to reveal")

        let cameraPreviewItem = featureSearchItems.first { $0.id == .feature(.cameraPreview) }!
        let unavailableCameraRoute = SettingsSearchSupport.route(for: cameraPreviewItem) { $0 != .cameraPreview }
        suite.expect(unavailableCameraRoute.destination == FeatureSettingsDestination(.features)
                && unavailableCameraRoute.targetFeature == .cameraPreview,
               "an unavailable grouped feature targets its own row even while its shared page stays visible")
        let availableCameraRoute = SettingsSearchSupport.route(for: cameraPreviewItem) { _ in true }
        suite.expect(availableCameraRoute.destination
                == FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview)
                && availableCameraRoute.targetFeature == nil,
               "an available grouped feature keeps opening its anchored section directly")

        let diskImageItem = featureSearchItems.first { $0.id == .feature(.diskImageInstaller) }!
        let diskImageRoute = SettingsSearchSupport.route(for: diskImageItem) { _ in true }
        suite.expect(diskImageRoute.destination == FeatureSettingsDestination(.features)
                && diskImageRoute.targetFeature == .diskImageInstaller,
               "Disk Image Installer, whose own destination is Features, still targets its exact row")

        let genericFeaturesItem = SettingsSearchItem(id: .page(.features),
                                                     destination: FeatureSettingsDestination(.features),
                                                     title: "Features", icon: "square.grid.2x2")
        let genericFeaturesRoute = SettingsSearchSupport.route(for: genericFeaturesItem) { _ in true }
        suite.expect(genericFeaturesRoute.destination == FeatureSettingsDestination(.features)
                && genericFeaturesRoute.targetFeature == nil,
               "a generic Features selection carries no feature target")

        let hiddenPageItem = SettingsSearchItem(id: .page(.shelf),
                                                destination: FeatureSettingsDestination(.shelf),
                                                title: "Shelf", icon: "tray.full")
        let hiddenPageRoute = SettingsSearchSupport.route(for: hiddenPageItem) { _ in false }
        suite.expect(hiddenPageRoute.destination == FeatureSettingsDestination(.features)
                && hiddenPageRoute.targetFeature == nil,
               "a page result with no merged feature identity still falls back to Features generically")

        // Window Layout stays in the sidebar for the green button override alone;
        // its page row keeps Window Layout's identity from the merge.
        let windowLayoutPage = SettingsSearchItem(
            id: .page(.windowLayout), destination: FeatureSettingsDestination(.windowLayout),
            title: "Window Layout", icon: "rectangle.3.group",
            keywords: ["Snap to edges", "Keep full screen in these apps"],
            keywordFeatures: [.windowLayout, .windowMaximizer])
        let windowLayoutItems = SettingsSearchSupport.combinedItems(
            pageItems: [windowLayoutPage],
            featureItems: SettingsSearchSupport.featureItems(language: .enUS) { $0.rawValue })
        let mergedWindowLayout = windowLayoutItems.first { $0.id == .page(.windowLayout) }!
        let maximizerOnly: (AppFeature) -> Bool = { $0 == .windowMaximizer }
        let maximizerOnlyRoute = SettingsSearchSupport.route(for: mergedWindowLayout, isAvailable: maximizerOnly)
        let noneRoute = SettingsSearchSupport.route(for: mergedWindowLayout) { _ in false }
        suite.expect(mergedWindowLayout.feature == .windowLayout
                && maximizerOnlyRoute.destination == FeatureSettingsDestination(.windowLayout)
                && maximizerOnlyRoute.targetFeature == nil
                && noneRoute.destination == FeatureSettingsDestination(.features)
                && noneRoute.targetFeature == .windowLayout,
               "a page kept visible by another feature opens itself, and falls back to its hub row once hidden")
        let exceptionGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "keep full screen", items: windowLayoutItems, isAvailable: maximizerOnly)
        let snapGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "snap", items: windowLayoutItems, isAvailable: maximizerOnly)
        let pageGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "window layout", items: windowLayoutItems, isAvailable: maximizerOnly)
        suite.expect(exceptionGroups.map(\.id) == [.windowLayout]
                && exceptionGroups.first?.suggestions.map(\.title) == ["Keep full screen in these apps"]
                && snapGroups.isEmpty
                && pageGroups.first?.id == .windowLayout && pageGroups.first?.parentMatches == true
                && pageGroups.first.map { SettingsSearchSupport.route(for: $0.pageItem, isAvailable: maximizerOnly) }?
                    .destination == FeatureSettingsDestination(.windowLayout),
               "the maximizer alone keeps its settings and the page findable, without Window Layout's own settings")

        let homebrewMatches = SettingsSearchSupport.matchingItems(
            query: "  HOMEBREW ", items: combinedSettingsItems)
        suite.expect(homebrewMatches.first?.destination == FeatureSettingsDestination(.homebrew)
                && homebrewMatches.map(\.id)
                    == [.page(.homebrew), .page(.features), .page(.appUpdates)],
               "an exact Homebrew title ranks before earlier generic keyword matches")
        let cameraPreviewMatches = SettingsSearchSupport.matchingItems(
            query: "Camera Preview", items: combinedSettingsItems)
        suite.expect(cameraPreviewMatches.first?.destination
                == FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview)
                && cameraPreviewMatches.map(\.id)
                    == [.feature(.cameraPreview), .page(.features), .page(.quickTools)],
               "an exact Camera Preview feature ranks before its page containers")

        let keywordBeforePartialTitle = SettingsSearchItem(
            id: .page(.features), destination: FeatureSettingsDestination(.features),
            title: "Features", icon: "square.grid.2x2", keywords: ["Homebrew Packages"])
        let partialTitleAfterKeyword = SettingsSearchItem(
            id: .page(.appUpdates), destination: FeatureSettingsDestination(.appUpdates),
            title: "Homebrew Packages", icon: "arrow.down.app")
        let partialMatches = SettingsSearchSupport.matchingItems(
            query: "brew", items: [keywordBeforePartialTitle, partialTitleAfterKeyword])
        suite.expect(partialMatches.map(\.id) == [.page(.appUpdates), .page(.features)],
               "partial title containment ranks before an earlier keyword-only match")

        let tiedTitleMatches = [
            SettingsSearchItem(id: .page(.quickTools),
                               destination: FeatureSettingsDestination(.quickTools),
                               title: "Camera Tools", icon: "wand.and.rays"),
            SettingsSearchItem(id: .feature(.cameraPreview),
                               destination: FeatureSettingsDestination(
                                 .quickTools, sectionAnchor: .cameraPreview),
                               title: "Camera Controls", icon: "web.camera"),
        ]
        suite.expect(SettingsSearchSupport.matchingItems(query: "camera", items: tiedTitleMatches)
                .map(\.id) == tiedTitleMatches.map(\.id),
               "Settings search preserves source order between equal-rank matches")
        suite.expect(SettingsSearchSupport.matchingItems(query: "  \n", items: tiedTitleMatches)
                .map(\.id) == tiedTitleMatches.map(\.id),
               "a blank Settings query preserves every item in source order")

        // MARK: Grouped Settings search suggestions
        let cameraGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "Camera Preview", items: combinedSettingsItems,
            isAvailable: { _ in true })
        suite.expect(cameraGroups.map(\.id) == [.quickTools, .features]
                && cameraGroups.first?.pageItem.title == "Quick Tools",
               "an exact utility match puts its main Settings page first")
        suite.expect(cameraGroups.first?.parentMatches == false
                && cameraGroups.first?.suggestions.map(\.title) == ["Camera Preview"]
                && cameraGroups.first?.suggestions.first?.item.destination
                    == FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview),
               "a grouped utility row retains its exact anchored destination")
        suite.expect(cameraGroups.last?.suggestions.map(\.title) == ["Camera Preview"],
               "every other main page containing the query remains represented")
        let installedCameraHubRoute = cameraGroups.last?.suggestions.first.map {
            SettingsSearchSupport.route(for: $0, isAvailable: { _ in true })
        }
        suite.expect(installedCameraHubRoute?.destination == FeatureSettingsDestination(.features)
                && installedCameraHubRoute?.targetFeature == .cameraPreview,
               "an installed utility's Features result reveals its exact uninstall row")

        let homebrewGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "Homebrew", items: combinedSettingsItems,
            isAvailable: { _ in true })
        suite.expect(homebrewGroups.map(\.id) == [.homebrew, .features, .appUpdates]
                && homebrewGroups.first?.parentMatches == true
                && homebrewGroups.first?.suggestions.isEmpty == true,
               "a matching main page is shown once before grouped keyword matches")

        let settingPage = SettingsSearchItem(
            id: .page(.energy), destination: FeatureSettingsDestination(.energy),
            title: "Energy", icon: "bolt.fill",
            keywords: ["Keep awake", "Show countdown", "Show remaining duration"])
        let settingGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "show", items: [settingPage], isAvailable: { _ in true })
        suite.expect(settingGroups.count == 1
                && settingGroups[0].id == .energy
                && !settingGroups[0].parentMatches
                && settingGroups[0].suggestions.map(\.title)
                    == ["Show countdown", "Show remaining duration"],
               "all matching setting labels are listed beneath their main page")
        suite.expect(SettingsSearchSupport.groupedMatchingItems(
                    query: " \n ", items: [settingPage],
                    isAvailable: { _ in true }).isEmpty,
               "a blank query does not replace the normal Settings sidebar with groups")

        let availabilityPage = SettingsSearchItem(
            id: .page(.quickTools), destination: FeatureSettingsDestination(.quickTools),
            title: "Quick Tools", icon: "wand.and.rays",
            keywords: ["Camera Preview", "Open camera automatically", "Scratchpad Notes"],
            keywordFeatures: [.cameraPreview, .cameraPreview, .scratchpad])
        let availabilityHub = SettingsSearchItem(
            id: .page(.features), destination: FeatureSettingsDestination(.features),
            title: "Features", icon: "square.grid.2x2",
            keywords: ["Camera Preview", "scratchpad"],
            keywordFeatures: [.cameraPreview, .scratchpad])
        let availabilityFeatures = featureSearchItems.filter {
            $0.id == .feature(.cameraPreview) || $0.id == .feature(.scratchpad)
        }
        let availabilityItems = [availabilityHub, availabilityPage] + availabilityFeatures
        let onlyScratchpadAvailable: (AppFeature) -> Bool = { $0 == .scratchpad }
        let unavailableCameraGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "camera", items: availabilityItems,
            isAvailable: onlyScratchpadAvailable)
        let unavailableCameraSuggestion = unavailableCameraGroups.first?.suggestions.first
        let groupedUnavailableCameraRoute = unavailableCameraSuggestion.map {
            SettingsSearchSupport.route(for: $0.item, isAvailable: onlyScratchpadAvailable)
        }
        suite.expect(unavailableCameraGroups.count == 1
                && unavailableCameraGroups[0].id == .features
                && unavailableCameraGroups[0].suggestions.map(\.title) == ["Camera Preview"]
                && groupedUnavailableCameraRoute?.destination == FeatureSettingsDestination(.features)
                && groupedUnavailableCameraRoute?.targetFeature == .cameraPreview,
               "an unavailable utility remains navigable through its exact Features row")
        suite.expect(SettingsSearchSupport.groupedMatchingItems(
                    query: "automatically", items: availabilityItems,
                    isAvailable: onlyScratchpadAvailable).isEmpty,
               "setting fields owned by an unavailable utility stay out of suggestions")
        let availableCameraSetting = SettingsSearchSupport.groupedMatchingItems(
            query: "automatically", items: availabilityItems,
            isAvailable: { _ in true }).first?.suggestions.first
        let availableCameraSettingRoute = availableCameraSetting.map {
            SettingsSearchSupport.route(for: $0, isAvailable: { _ in true })
        }
        suite.expect(availableCameraSetting?.title == "Open camera automatically"
                && availableCameraSettingRoute?.destination
                    == FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview)
                && availableCameraSettingRoute?.targetFeature == nil,
               "a feature-owned setting keyword opens its exact anchored section")
        let availableScratchpadGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "scratchpad", items: availabilityItems,
            isAvailable: onlyScratchpadAvailable)
        suite.expect(availableScratchpadGroups.first?.id == .quickTools
                && availableScratchpadGroups[0].suggestions.map(\.title)
                    == ["scratchpad", "Scratchpad Notes"]
                && availableScratchpadGroups[0].suggestions.first?.item.destination
                    == FeatureSettingsDestination(.quickTools, sectionAnchor: .scratchpad),
               "an installed utility remains searchable on a shared Settings page")
        suite.expect(SettingsSearchSupport.groupedMatchingItems(
                    query: "Quick Tools", items: availabilityItems,
                    isAvailable: { _ in false }).isEmpty,
               "a main page with no installed utilities is not suggested")

        let freshSize = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                 availableHeight: 1200)
        suite.expect(freshSize.width == 772 && freshSize.height == 838,
               "settings window opens at the tall default when nothing is saved")
        let clampedSize = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                   availableHeight: 700)
        suite.expect(clampedSize.height == 700,
               "the tall default shrinks to what the screen fits")
        let tinyScreen = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                  availableHeight: 400)
        suite.expect(tinyScreen.height == 528,
               "the default never goes below the design height")
        let savedSize = SettingsWindowSupport.initialContentSize(savedWidth: 900, savedHeight: 950,
                                                                 availableHeight: 700)
        suite.expect(savedSize.width == 900 && savedSize.height == 950,
               "a user-chosen size is restored as is")
        let bogusSaved = SettingsWindowSupport.initialContentSize(savedWidth: 300, savedHeight: 200,
                                                                  availableHeight: 1200)
        suite.expect(bogusSaved.width == 772 && bogusSaved.height == 838,
               "a saved size below the minimum falls back to the default")
        suite.expect(!SettingsWindowSupport.isValidContentSize(width: 300, height: 200),
               "sub-minimum sizes are rejected by isValidContentSize")
        suite.expect(SettingsWindowSupport.isValidContentSize(width: 772, height: 528),
               "exact minimum size is valid")
        suite.expect(SettingsWindowSupport.isValidContentSize(width: 1000, height: 800),
               "larger size is valid")
        let fullTourSize = CGSize(width: 600, height: 584)
        let tourSettingsSize = CGSize(width: 772, height: 750)
        let wideTourScreen = CGRect(x: -1600, y: 100, width: 1470, height: 900)
        let wideTourPlacement = SettingsWindowSupport.tourPlacement(
            settingsSize: tourSettingsSize, tourSize: fullTourSize, visibleFrame: wideTourScreen)
        suite.expect(!wideTourPlacement.settings.intersects(wideTourPlacement.tour)
                && wideTourPlacement.settings.maxX < wideTourPlacement.tour.minX,
               "the complete tour fits beside Settings on a wide display")
        suite.expect(wideTourScreen.contains(wideTourPlacement.settings)
                && wideTourScreen.contains(wideTourPlacement.tour),
               "tour placement respects external displays with offset coordinates")
        let smallTourScreen = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let smallTourPlacement = SettingsWindowSupport.tourPlacement(
            settingsSize: tourSettingsSize, tourSize: fullTourSize, visibleFrame: smallTourScreen)
        suite.expect(smallTourScreen.contains(smallTourPlacement.settings)
                && smallTourScreen.contains(smallTourPlacement.tour)
                && smallTourPlacement.settings.size == tourSettingsSize
                && smallTourPlacement.tour.size == fullTourSize,
               "narrow displays keep the complete images and controls on screen without resizing")
        let tallTourPlacement = SettingsWindowSupport.tourPlacement(
            settingsSize: tourSettingsSize, tourSize: fullTourSize,
            visibleFrame: CGRect(x: 200, y: -1700, width: 1000, height: 1600))
        suite.expect(!tallTourPlacement.settings.intersects(tallTourPlacement.tour)
                && tallTourPlacement.tour.minY > tallTourPlacement.settings.maxY,
               "portrait displays stack the tour above Settings when both fit")
        let oversizedTourPlacement = SettingsWindowSupport.tourPlacement(
            settingsSize: CGSize(width: 1600, height: 1000), tourSize: fullTourSize,
            visibleFrame: smallTourScreen)
        suite.expect(smallTourScreen.contains(oversizedTourPlacement.tour)
                && oversizedTourPlacement.settings.maxY == smallTourScreen.maxY - 20,
               "an oversized Settings window cannot push the tour or its own title bar off screen")
        let preferredSettingsFrame = CGRect(x: -50, y: 100, width: 1000, height: 700)
        let overlappingPlacement = SettingsWindowSupport.panelPlacement(
            preferredFrame: preferredSettingsFrame,
            panelFrame: CGRect(x: 450, y: 500, width: 300, height: 300),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        suite.expect(overlappingPlacement.closesPanel
                && overlappingPlacement.frame == CGRect(x: 20, y: 100, width: 1000, height: 700),
               "failed avoidance closes the panel and clamps the preferred settings frame")
        let separatePlacement = SettingsWindowSupport.panelPlacement(
            preferredFrame: CGRect(x: 600, y: 100, width: 800, height: 700),
            panelFrame: CGRect(x: 1200, y: 500, width: 300, height: 300),
            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 900))
        suite.expect(!separatePlacement.closesPanel
                && separatePlacement.frame.maxX == 1172,
               "successful avoidance keeps the panel beside settings")
        let verticalPlacement = SettingsWindowSupport.panelPlacement(
            preferredFrame: CGRect(x: 100, y: 400, width: 1000, height: 300),
            panelFrame: CGRect(x: 450, y: 500, width: 300, height: 100),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        suite.expect(!verticalPlacement.closesPanel
                && verticalPlacement.frame.maxY == 472,
               "vertical avoidance moves settings below the panel with the standard gap")

        suite.expect(UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-copy"),
               "a copy failure retries through the admin prompt")
        suite.expect(UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-swap"),
               "a swap failure retries through the admin prompt")
        suite.expect(!UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-verify"),
               "a verification failure is not a permission problem")
        suite.expect(!UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: nil),
               "no remembered failure means the normal path")

        let adminSource = AdminShell.appleScriptSource(
            command: #"printf "quoted" \ path"#,
            prompt: #"Approve "update" \ now"#)
        suite.expect(adminSource == #"do shell script "printf \"quoted\" \\ path" with administrator privileges with prompt "Approve \"update\" \\ now""#,
               "administrator source keeps commands and prompts inside AppleScript strings")
        var adminCompileError: NSDictionary?
        suite.expect(NSAppleScript(source: adminSource)?.compileAndReturnError(&adminCompileError) == true,
               "administrator source compiles in process")
        let inProcessScript = AppleScriptRunner.run(
            #"do shell script "/usr/bin/printf admin-probe""#)
        suite.expect(inProcessScript.ok && inProcessScript.output == "admin-probe",
               "in-process AppleScript executes a shell command and returns its output")
        let cancelledScript = AppleScriptRunner.runDetailed("error number -128")
        suite.expect(!cancelledScript.ok && cancelledScript.errorNumber == -128,
               "in-process AppleScript preserves cancellation as a failed request")

        let hiddenLayout = WindowLayoutAction.hiddenActions(from: "leftHalf, restore,bogus")
        suite.expect(hiddenLayout == [.leftHalf, .restore],
               "hidden layout actions parse names and drop unknown ones")
        suite.expect(WindowLayoutAction.hiddenActionsStorageValue([.restore, .leftHalf])
                   == "leftHalf,restore",
               "hidden layout actions serialize sorted for stable storage")
        suite.expect(WindowLayoutAction.hiddenActions(from: "").isEmpty,
               "an empty stored value hides nothing")

        suite.expect(MediaSupport.inputMatchesTool(contentType: .jpeg, inputTypes: [.image]),
               "a JPEG drop fits the image tool")
        suite.expect(!MediaSupport.inputMatchesTool(contentType: .pdf, inputTypes: [.image]),
               "a PDF drop does not fit the image tool")
        suite.expect(!MediaSupport.inputMatchesTool(contentType: nil, inputTypes: [.image]),
               "an unreadable content type is rejected")
        suite.expect(MediaSupport.inputMatchesTool(contentType: .quickTimeMovie,
                                             inputTypes: [.movie, .video]),
               "a movie drop fits the video tools")

        suite.expect(MediaSupport.outputGrew(originalBytes: 9_000, outputBytes: 12_000),
               "a larger output earns the grew caption")
        suite.expect(!MediaSupport.outputGrew(originalBytes: 12_000, outputBytes: 9_000),
               "a smaller output does not")
        suite.expect(!MediaSupport.outputGrew(originalBytes: 0, outputBytes: 12_000),
               "an unknown original size never triggers the grew caption")

        suite.expect(UpdateInstallerSupport.shellSingleQuoted("/Applications/My App.app")
                   == "'/Applications/My App.app'",
               "shell quoting wraps paths with spaces")
        suite.expect(UpdateInstallerSupport.shellSingleQuoted("it's") == "'it'\\''s'",
               "shell quoting survives embedded single quotes")
        suite.expect(UpdateInstallerSupport.installFailureCode(fromMarker: "ok\n") == nil,
               "an ok marker is not a failure")
        suite.expect(UpdateInstallerSupport.installFailureCode(fromMarker: " fail-verify\n") == "fail-verify",
               "a fail marker surfaces its step code")
        suite.expect(UpdateInstallerSupport.installFailureCode(fromMarker: "") == nil,
               "an empty marker is not a failure")
        suite.expect(UpdateInstallerSupport.runsFromImmutableLocation(
                   appPath: "/private/var/folders/ab/xyz/T/AppTranslocation/1F2/d/Vorssaint.app",
                   volumeIsReadOnly: { _ in false }),
               "translocated apps are flagged as not updatable in place")
        suite.expect(UpdateInstallerSupport.runsFromImmutableLocation(appPath: "/Volumes/Vorssaint/Vorssaint.app",
                                                                volumeIsReadOnly: { _ in true }),
               "apps on a read-only volume (the DMG) are flagged as not updatable in place")
        suite.expect(!UpdateInstallerSupport.runsFromImmutableLocation(appPath: "/Volumes/ExternalSSD/Vorssaint.app",
                                                                 volumeIsReadOnly: { _ in false }),
               "apps on a writable external volume stay updatable in place")
        let installerScript = UpdateInstallerSupport.installerScript()
        for step in ["fail-dmg-verify", "fail-tempdir", "fail-mount", "fail-no-app-in-dmg",
                     "fail-copy", "fail-version", "fail-verify", "fail-swap", "note ok"] {
            suite.expect(installerScript.contains(step),
                   "installer script reports the \(step) step")
        }
        suite.expect(installerScript.contains("spctl --status"),
               "installer script skips Gatekeeper assessment when the user disabled it")
        let dmgVerification = installerScript.range(of: "DMG_VERIFY_REQ")
        let dmgMount = installerScript.range(of: "/usr/bin/hdiutil attach")
        suite.expect(dmgVerification != nil && dmgMount != nil
               && dmgVerification!.lowerBound < dmgMount!.lowerBound,
               "installer verifies the release signer before mounting the DMG")
        suite.expect(installerScript.contains("BUNDLE_VERSION=")
               && installerScript.contains("\"$BUNDLE_VERSION\" = \"$EXPECTED_VERSION\""),
               "installer requires the signed app to match the offered release version")
        suite.expect(installerScript.contains("chown -R"),
               "an elevated install hands the bundle back to the user")
        suite.expect(installerScript.contains("update-old.$PID"),
               "the swap backup name is unique per run so a stale root-owned one never blocks it")
        suite.expect(installerScript.contains("STAGE=\"$DIR/.$NAME.update-new\""),
               "the staged copy is hidden so search never lists it under the staging name")
        suite.expect(installerScript.contains("/bin/rm -rf \"$STAGE\" \"$DEST.update-new\""),
               "a staged copy left under the old visible name is removed along with the hidden one")
        suite.expect(installerScript.contains("launchctl asuser"),
               "installer script relaunches as the user when running as root")
        suite.expect(installerScript.contains("$RESULT.progress") && installerScript.contains("finalize"),
               "installer markers stay in a progress file until the run finishes")
        suite.expect(installerScript.contains("/usr/bin/sudo -n -u \"#$ASUSER\" /bin/sh -c")
                && installerScript.contains("'/bin/echo \"$1\" > \"$2.progress\"' marker \"$1\" \"$RESULT\"")
                && installerScript.contains("/usr/bin/sudo -n -u \"#$ASUSER\" /bin/mv -f")
                && !installerScript.contains("note() { /bin/echo \"$1\" > \"$RESULT.progress\""),
               "elevated marker writes drop to the original user's credentials")
        let elevated = UpdateInstallerSupport.elevatedInstallCommand(
            appPath: "/Applications/Vorssaint.app",
            dmgPath: "/tmp/Vorssaint-update.dmg",
            pid: 123,
            resultPath: "/tmp/result",
            uid: 501,
            expectedVersion: "3.3.3")
        suite.expect(elevated.contains("POSIX::setsid()") && elevated.hasSuffix("&"),
               "elevated installer leaves this app's session so it outlives the app it replaces")
        suite.expect(elevated.contains("nohup"),
               "elevated installer keeps the nohup fallback if setsid is unavailable")
        suite.expect(elevated.contains("'/Applications/Vorssaint.app'"),
               "elevated installer passes the app path quoted for the shell")
        suite.expect(elevated.contains("'3.3.3'"),
               "elevated installer passes the expected version quoted for the shell")
        // The script travels inline and is long; it must be spelled once, with
        // both the setsid attempt and the fallback reusing the same "$@".
        suite.expect(elevated.components(separatedBy: "DMG_VERIFY_REQ=").count == 2
               && elevated.components(separatedBy: "\"$@\"").count == 3,
               "elevated installer names its arguments once and reuses them for the fallback")

        // The fallback branch has to be chosen on whether perl is there, never
        // on an exit code: perl execs the payload, so the status the shell sees
        // is the payload's own. Every `exit 1` inside the installer script would
        // otherwise start the whole installer a second time, as root.
        let detachRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintDetachTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: detachRoot, withIntermediateDirectories: true)
        let detachPayload = detachRoot.appendingPathComponent("payload.sh")
        let detachLedger = detachRoot.appendingPathComponent("runs")
        try? "#!/bin/sh\n/bin/echo ran >> \"$1\"\nexit 1\n"
            .write(to: detachPayload, atomically: true, encoding: .utf8)
        let detachCommand = DetachedProcess.detachedShellCommand(
            quotedArgv: ["/bin/sh", detachPayload.path, detachLedger.path]
                .map(UpdateInstallerSupport.shellSingleQuoted)
                .joined(separator: " "))
        let foregroundDetachCommand = String(detachCommand.dropLast(2))
        let detachResult = BoundedProcessRunner.run(
            "/bin/sh", ["-c", foregroundDetachCommand], timeout: 2, maxOutputBytes: 1_024)
        suite.expect(!detachResult.timedOut && detachResult.status == 1,
                     "the foreground form of the detached command observes its payload exit")
        func detachedRunCount() -> Int {
            (try? String(contentsOf: detachLedger, encoding: .utf8))?
                .split(separator: "\n").count ?? 0
        }
        suite.expect(detachedRunCount() == 1, "a detached command starts its payload once")
        try? FileManager.default.removeItem(at: detachRoot)

        // A detached spawn is only detached if the child really is its own
        // session leader; `nohup` alone leaves it in ours.
        do {
            let child = try DetachedProcess.spawn("/bin/sleep", ["30"])
            suite.expect(getsid(child) == child,
                   "a detached child is its own session leader")
            suite.expect(getsid(child) != getsid(0),
                   "a detached child is not in this process's session")
            kill(child, SIGKILL)
            var reaped: Int32 = 0
            waitpid(child, &reaped, 0)
        } catch {
            suite.expect(false, "detached spawn failed: \(error.localizedDescription)")
        }

        // A child built to outlive this app must not carry this app's open
        // descriptors with it: the app is gone before the child does its work,
        // so anything it inherited is held open by a process nobody can see or
        // close. `Process` gave its children a clean table; these children get
        // the same. 0/1/2 must still be open (on /dev/null), or the child's
        // first open() takes stdout's slot.
        let fdRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintDetachFDTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: fdRoot, withIntermediateDirectories: true)
        let fdHolder = fdRoot.appendingPathComponent("holder")
        let fdReport = fdRoot.appendingPathComponent("report")
        // Opened WITHOUT O_CLOEXEC, the way a plain open() anywhere in the app
        // leaves it — that is the descriptor that must not travel.
        let holderDescriptor = open(fdHolder.path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        suite.expect(holderDescriptor >= 3, "fd probe holds a descriptor above stdio")
        do {
            let probe = "{ /bin/echo leaked >&\(holderDescriptor); } 2>/dev/null; INHERITED=$?; "
                + "{ /bin/echo stdio; } 2>/dev/null; STDIO=$?; "
                + "/bin/echo \"$INHERITED $STDIO\" > \(UpdateInstallerSupport.shellSingleQuoted(fdReport.path))"
            let child = try DetachedProcess.spawn("/bin/sh", ["-c", probe])
            var reaped: Int32 = 0
            waitpid(child, &reaped, 0)
            let report = ((try? String(contentsOf: fdReport, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let status = report.split(separator: " ").map(String.init)
            suite.expect(status.count == 2 && status[0] != "0",
                   "a detached child does not inherit this app's open descriptors (probe: \"\(report)\")")
            suite.expect(((try? String(contentsOf: fdHolder, encoding: .utf8)) ?? "").isEmpty,
                   "a detached child cannot write through a descriptor this app opened")
            suite.expect(status.count == 2 && status[1] == "0",
                   "a detached child still has stdout open (probe: \"\(report)\")")
        } catch {
            suite.expect(false, "detached fd probe failed: \(error.localizedDescription)")
        }
        close(holderDescriptor)
        try? FileManager.default.removeItem(at: fdRoot)

        // MARK: - UpdateServiceSupport & SemVer channel reconciliation

        let vStable = UpdateServiceSupport.SemanticVersion(raw: "3.3.3")
        suite.expect(vStable?.major == 3 && vStable?.minor == 3 && vStable?.patch == 3 && !vStable!.isPrerelease,
               "parses standard stable version")

        let vBeta = UpdateServiceSupport.SemanticVersion(raw: "v3.3.4-beta.1")
        suite.expect(vBeta?.major == 3 && vBeta?.minor == 3 && vBeta?.patch == 4 && vBeta!.isPrerelease,
               "parses beta version with leading v")

        let vBuild = UpdateServiceSupport.SemanticVersion(raw: "3.3.4-rc.2+20260822")
        suite.expect(vBuild?.major == 3 && vBuild?.minor == 3 && vBuild?.patch == 4 && vBuild!.isPrerelease,
               "parses version with build metadata")

        // SemVer 2.0.0 ordering rules
        suite.expect(UpdateServiceSupport.isNewer("3.3.4", than: "3.3.3"),
               "newer major/minor/patch stable is newer")
        suite.expect(!UpdateServiceSupport.isNewer("3.3.3", than: "3.3.4"),
               "older stable is not newer")
        suite.expect(UpdateServiceSupport.isNewer("3.3.4-beta.1", than: "3.3.3"),
               "beta of higher version is newer than older stable")
        suite.expect(UpdateServiceSupport.isNewer("3.3.4-beta.2", than: "3.3.4-beta.1"),
               "beta.2 is newer than beta.1 of the same cycle")
        suite.expect(UpdateServiceSupport.isNewer("3.3.4-rc.1", than: "3.3.4-beta.2"),
               "rc.1 is newer than beta.2")
        suite.expect(UpdateServiceSupport.isNewer("3.3.4", than: "3.3.4-beta.2"),
               "final stable release is newer than beta of same version")
        suite.expect(UpdateServiceSupport.isNewer("3.3.4", than: "3.3.4-rc.1"),
               "final stable release is newer than rc of same version")
        suite.expect(!UpdateServiceSupport.isNewer("3.3.3", than: "3.3.4-beta.1"),
               "older stable is never newer than a beta of higher version (no downgrade)")
        suite.expect(!UpdateServiceSupport.isNewer("3.3.4-beta.1", than: "3.3.4"),
               "beta is not newer than the released final version")

        suite.expect(UpdateServiceSupport.isNewer("3.4.0-beta.2.1", than: "3.4.0-beta.2")
               && !UpdateServiceSupport.isNewer("3.4.0-beta.2", than: "3.4.0-beta.2.1")
               && UpdateServiceSupport.isNewer("3.4.0-beta.3", than: "3.4.0-beta.2.1")
               && UpdateServiceSupport.isNewer("3.4.0", than: "3.4.0-beta.2.1"),
               "beta hotfixes follow their parent beta and precede the next beta and stable version")
        let betaHotfix = UpdateServiceSupport.ReleaseCandidate(
            tagName: "v3.4.0-beta.2.1", isPrerelease: true, isDraft: false,
            dmgURL: URL(string: "https://example.com/update.dmg"), dmgExpectedBytes: 1000, body: "Hotfix")
        suite.expect(UpdateServiceSupport.selectUpdate(from: [betaHotfix], currentVersion: "3.4.0-beta.2",
                                                 includeBetas: true)?.tagName == betaHotfix.tagName
               && UpdateServiceSupport.selectUpdate(from: [betaHotfix], currentVersion: "3.3.5",
                                                     includeBetas: false) == nil,
               "the beta channel offers the hotfix while the stable channel ignores it")

        // Release candidate selection
        let dummyDMG = URL(string: "https://github.com/vorssaint/vorssaint-utils/releases/download/v3.3.4/Vorssaint.dmg")!
        let dummyBetaDMG = URL(string: "https://github.com/vorssaint/vorssaint-utils/releases/download/v3.3.4-beta.1/Vorssaint.dmg")!

        let candidateList = [
            UpdateServiceSupport.ReleaseCandidate(tagName: "v3.3.4-beta.1", isPrerelease: true, isDraft: false, dmgURL: dummyBetaDMG, dmgExpectedBytes: 1000, body: "Beta notes"),
            UpdateServiceSupport.ReleaseCandidate(tagName: "v3.3.3", isPrerelease: false, isDraft: false, dmgURL: dummyDMG, dmgExpectedBytes: 1000, body: "Stable notes"),
            UpdateServiceSupport.ReleaseCandidate(tagName: "v3.3.5-beta.1", isPrerelease: true, isDraft: true, dmgURL: dummyBetaDMG, dmgExpectedBytes: 1000, body: "Draft notes")
        ]

        let selectedStable = UpdateServiceSupport.selectUpdate(from: candidateList, currentVersion: "3.3.2", includeBetas: false)
        suite.expect(selectedStable?.tagName == "v3.3.3", "stable channel only picks stable releases")

        let selectedBeta = UpdateServiceSupport.selectUpdate(from: candidateList, currentVersion: "3.3.2", includeBetas: true)
        suite.expect(selectedBeta?.tagName == "v3.3.4-beta.1", "beta channel picks highest non-draft release")

        let selectedFromHigherBeta = UpdateServiceSupport.selectUpdate(from: candidateList, currentVersion: "3.3.4-beta.1", includeBetas: false)
        suite.expect(selectedFromHigherBeta == nil, "user on beta turning off betas does not downgrade to older stable")

        let knownDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        suite.expect(UpdateServiceSupport.sha256Matches(Data("abc".utf8), expectedHex: knownDigest),
               "update media accepts its pinned SHA-256 digest")
        suite.expect(!UpdateServiceSupport.sha256Matches(Data("altered".utf8), expectedHex: knownDigest),
               "update media rejects content that does not match its pinned digest")
        suite.expect(!UpdateServiceSupport.sha256Matches(Data("abc".utf8), expectedHex: "invalid"),
               "update media rejects a malformed pinned digest")

        // Defaults registered
        suite.expect(Defaults.registeredDefaults[DefaultsKey.includeBetaUpdates] as? Bool == false,
               "includeBetaUpdates defaults to false in registeredDefaults")

        let testDefaults = UserDefaults(suiteName: "com.vorssaint.tests.betaActivation")!
        testDefaults.removePersistentDomain(forName: "com.vorssaint.tests.betaActivation")
        Defaults.activateBetaChannelIfRunningBeta(in: testDefaults, version: "3.3.3-beta.1")
        suite.expect(testDefaults.bool(forKey: DefaultsKey.includeBetaUpdates) == true,
               "beta channel is activated automatically on a beta build")
        testDefaults.set(false, forKey: DefaultsKey.includeBetaUpdates)
        Defaults.activateBetaChannelIfRunningBeta(in: testDefaults, version: "3.3.3-beta.1")
        suite.expect(testDefaults.bool(forKey: DefaultsKey.includeBetaUpdates) == false,
               "manual opt-out on a beta build is preserved across launches")

        // Stable version does not activate beta channel
        let stableDefaults = UserDefaults(suiteName: "com.vorssaint.tests.stableActivation")!
        stableDefaults.removePersistentDomain(forName: "com.vorssaint.tests.stableActivation")
        Defaults.activateBetaChannelIfRunningBeta(in: stableDefaults, version: "3.3.3")
        suite.expect(stableDefaults.object(forKey: DefaultsKey.includeBetaUpdates) == nil,
               "stable release does not touch beta channel default")
        stableDefaults.removePersistentDomain(forName: "com.vorssaint.tests.stableActivation")
        testDefaults.removePersistentDomain(forName: "com.vorssaint.tests.betaActivation")

        // Localization completeness & formatting
        let originalLanguage = L10n.shared.language
        for language in AppLanguage.allCases {
            L10n.shared.language = language
            let s = L10n.shared.s
            suite.expect(!s.includeBetaUpdatesToggle.isEmpty, "\(language.rawValue) includeBetaUpdatesToggle non-empty")
            suite.expect(!s.includeBetaUpdatesCaption.isEmpty, "\(language.rawValue) includeBetaUpdatesCaption non-empty")
            suite.expect(!s.betaBadgeLabel.isEmpty, "\(language.rawValue) betaBadgeLabel non-empty")
            suite.expect(!s.includeBetaUpdatesCaption.contains("—"), "\(language.rawValue) has no em dash")
        }
        L10n.shared.language = originalLanguage

        // MARK: Launch at login reconciliation

        suite.expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .off,
                                                  locationIsUnstable: false) == .register,
               "a lost registration the user wants is redone at startup")
        suite.expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .off,
                                                  locationIsUnstable: true) == .none,
               "no registration is redone from an unstable location")
        suite.expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .enabled,
                                                  locationIsUnstable: false) == .none
                && LaunchAtLoginSupport.startupAction(wanted: true, registration: .enabled,
                                                      locationIsUnstable: true) == .none,
               "a healthy registration is left alone")
        suite.expect(LaunchAtLoginSupport.startupAction(wanted: false, registration: .enabled,
                                                  locationIsUnstable: false) == .adoptEnabled
                && LaunchAtLoginSupport.startupAction(wanted: false, registration: .enabled,
                                                      locationIsUnstable: true) == .adoptEnabled,
               "an enable made outside the app becomes the stored choice")
        suite.expect(LaunchAtLoginSupport.startupAction(wanted: false, registration: .off,
                                                  locationIsUnstable: false) == .none
                && LaunchAtLoginSupport.startupAction(wanted: false, registration: .off,
                                                      locationIsUnstable: true) == .none,
               "startup never turns launch at login on for a user who never asked")
        suite.expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .needsApproval,
                                                  locationIsUnstable: false) == .none
                && LaunchAtLoginSupport.startupAction(wanted: false, registration: .needsApproval,
                                                      locationIsUnstable: false) == .none,
               "an item awaiting approval in System Settings is never registered over (issue #260)")
        // `SMAppService.Status` cannot be driven without a real login item, so
        // what the service does with the third state is pinned by source. Both
        // needles are public symbols, not a line's spelling.
        let launchAtLoginSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/LaunchAtLogin.swift",
            encoding: .utf8)) ?? ""
        suite.expect(launchAtLoginSource.contains(".requiresApproval"),
               "an approval-pending login item is read as its own state")
        suite.expect(launchAtLoginSource.contains("throw NeedsApprovalError()"),
               "turning launch at login on says so when only approval is missing")

        // MARK: Release notes parsing

        let changelog = """
        # Changelog

        ## [2.17.2] - 2026-06-17

        ### Summary
        This update keeps **Shelf** clear
        and the update window centered.

        ### Fixed
        - **Shelf** no longer shows an extra outline.
        - The update window opens centered
          on the visible screen.

        ### Added
        - Coffee shortcut in the menu panel.
        ![Menu bar temperature metrics](Resources/Images/menu-bar-temperature-metrics.png)

        ### Website
        - Official site: [vorssaint.com](https://vorssaint.com).

        ## [2.17.1] - 2026-06-17

        ### Fixed
        - Older release note.
        """
        let notes = ReleaseNotes.notes(for: "2.17.2", changelog: changelog)
        suite.expect(notes.version == "2.17.2", "release notes version is parsed")
        suite.expect(notes.date == "2026-06-17", "release notes date is parsed")
        suite.expect(notes.sections.count == 3, "release notes keep sections for the requested version")
        suite.expect(notes.sections.first?.title == "Summary", "release notes first section title is parsed")
        suite.expect(notes.sections.first?.paragraphItems.first == "This update keeps Shelf clear and the update window centered.",
               "release notes parse summary paragraphs")
        suite.expect(notes.sections.dropFirst().first?.title == "Fixed", "release notes fixed section title is parsed")
        suite.expect(notes.sections.dropFirst().first?.bulletItems.first == "Shelf no longer shows an extra outline.",
               "release notes strip simple markdown emphasis")
        suite.expect(notes.sections.dropFirst().first?.bulletItems.dropFirst().first == "The update window opens centered on the visible screen.",
               "release notes join continuation lines")
        suite.expect(notes.sections.last?.bulletItems == ["Coffee shortcut in the menu panel."],
               "release notes stop before the next version")
        suite.expect(notes.sections.last?.items.last == .image(ReleaseNoteImage(alt: "Menu bar temperature metrics",
                                                                          path: "Resources/Images/menu-bar-temperature-metrics.png")),
               "release notes parse changelog images")
        suite.expect(!notes.sections.contains(where: { $0.title == "Website" }),
               "release notes hide website sections from the feature list")
        let previewBodyWithoutSummaryHeading = """
        ## [2.17.3]

        A short release summary from the GitHub release body.

        ### Fixed
        - Preview bullet.
        """
        let previewNotes = ReleaseNotes.notes(for: "2.17.3", changelog: previewBodyWithoutSummaryHeading)
        suite.expect(previewNotes.sections.first?.title == "Summary",
               "release notes preserve an unheaded release-body summary paragraph")
        suite.expect(previewNotes.sections.first?.paragraphItems.first == "A short release summary from the GitHub release body.",
               "release notes keep summary text before the first subsection")
        let githubReleaseBodyWithFooter = """
        ### Fixed
        - Update preview stays focused on changes.

        Signed with an Apple Developer ID and notarized by Apple, so it downloads and opens normally. Requires macOS 14 or later. Open the .dmg below and drag Vorssaint to Applications.
        """
        let inAppUpdateBody = ReleaseNotes.inAppUpdateNotes(from: githubReleaseBodyWithFooter) ?? ""
        suite.expect(!inAppUpdateBody.contains("Signed with an Apple Developer ID"),
               "in-app update notes remove the GitHub installation footer")
        let githubPreviewNotes = ReleaseNotes.notes(for: "2.17.4",
                                                    changelog: "## [2.17.4]\n\n" + inAppUpdateBody)
        suite.expect(githubPreviewNotes.sections.first?.bulletItems == ["Update preview stays focused on changes."],
               "in-app update notes keep release changes after removing the footer")
        let unreleasedChangelog = """
        ## [Unreleased]

        ### Added
        - Feature pending release.

        ## [2.17.4] - 2026-06-18

        ### Fixed
        - Shipped fix.
        """
        let unreleasedNotes = ReleaseNotes.notes(for: "Unreleased", changelog: unreleasedChangelog)
        suite.expect(unreleasedNotes.version == "Unreleased" && unreleasedNotes.date == nil
               && unreleasedNotes.sections.first?.bulletItems == ["Feature pending release."],
               "release notes parse unreleased blocks without dates")
        suite.expect(ReleaseNotes.allVersions(changelog: unreleasedChangelog) == ["2.17.4"],
               "allVersions excludes the unreleased header")
        suite.expect(ReleaseNotes.rawNotes(for: "dev", changelog: unreleasedChangelog).contains("Feature pending release."),
               "rawNotes for dev falls back to the unreleased block")

        // MARK: App updates

        suite.expect(AppUpdatesSupport.compare("1.130.0", "1.129.0") == .orderedDescending
                && AppUpdatesSupport.compare("0.730.0.7300790", "0.731.0") == .orderedAscending
                && AppUpdatesSupport.compare("26.084.0504", "26.119.0622.0003") == .orderedAscending,
               "versions compare part by part, as numbers")
        suite.expect(AppUpdatesSupport.compare("1.2", "1.2.0") == .orderedSame
                && AppUpdatesSupport.compare("1.2", "1.2.1") == .orderedAscending
                && AppUpdatesSupport.compare("3.5.230", "3.5.230") == .orderedSame,
               "a missing part counts as zero")
        suite.expect(AppUpdatesSupport.compare("2026.723.1724", "2026.714.1952") == .orderedDescending
                && AppUpdatesSupport.compare("00123", "123") == .orderedSame,
               "leading zeros never decide a comparison")
        suite.expect(!AppUpdatesSupport.isNewer("1.9a", than: "1.10")
                && AppUpdatesSupport.isNewer("1.10", than: "1.9a")
                && !AppUpdatesSupport.isNewer("3.5beta", than: "3.5")
                && AppUpdatesSupport.isNewer("3.5", than: "3.5beta")
                && AppUpdatesSupport.isNewer("1.9b", than: "1.9a"),
               "a lettered part compares by its number first, and the bare number outranks its own suffixed run")
        suite.expect(AppUpdatesSupport.versionCore("3.5.262,260717dcrpwg7m0") == "3.5.262"
                && AppUpdatesSupport.versionCore("0.0.402") == "0.0.402",
               "the revision after a comma is not part of the version")
        suite.expect(AppUpdatesSupport.versionCore(" v2.0.11.1,260925abc ") == "2.0.11.1"
                && AppUpdatesSupport.versionCore("V2.0.11.1") == "2.0.11.1"
                && !AppUpdatesSupport.isNewer("v2.0.11.1", than: "2.0.11.1")
                && !AppUpdatesSupport.isNewer("2.0.11.1", than: "V2.0.11.1"),
               "a leading v/V and surrounding whitespace normalize before numeric comparison")
        suite.expect(!AppUpdatesSupport.isNewer("2.0.11.1", than: "v2.0.11.1")
                && AppUpdatesSupport.isNewer("v2.0.11.2", than: "2.0.11.1")
                && AppUpdatesSupport.versionCore("version1") == "version1",
               "only a v/V directly before a number is removed, and prefixed versions compare by value")
        suite.expect(AppUpdatesSupport.isNewer("3.5.262,260717dcrpwg7m0", than: "3.5.230")
                && !AppUpdatesSupport.isNewer("1.130.0", than: "1.130.0"),
               "an update is only newer when the number really grew")
        suite.expect(AppUpdatesSupport.isUncomparable("latest") && AppUpdatesSupport.isUncomparable("")
                && !AppUpdatesSupport.isUncomparable("1.0"),
               "a package without a version number cannot be judged")

        func caskUpdate(_ token: String, installed: String, current: String,
                        pinned: Bool = false) -> HomebrewPackageUpdate {
            HomebrewPackageUpdate(kind: .cask, name: token, installedVersions: [installed],
                                  currentVersion: current, isPinned: pinned)
        }
        let caskRecords = [
            HomebrewCaskRecord(token: "editor", displayName: "Editor",
                               installedVersion: "1.129.0", appFileNames: ["Editor.app"]),
            HomebrewCaskRecord(token: "chat", displayName: "Chat",
                               installedVersion: "0.0.374", appFileNames: ["Chat.app"]),
            HomebrewCaskRecord(token: "installer", displayName: "Installer",
                               installedVersion: "26.078", appFileNames: []),
        ]
        // The receipt says 1.129 while the app on disk already updated itself
        // to 1.130: believing the receipt would offer an update that happened.
        let packageApps = [
            AppUpdatesSupport.InstalledApp(name: "Editor", bundleID: "com.vendor.editor",
                                           path: "/Applications/Editor.app", version: "1.130.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Chat", bundleID: "com.vendor.chat",
                                           path: "/Applications/Chat.app", version: "0.0.401",
                                           isFromAppStore: false),
        ]
        let packageRows = AppUpdatesSupport.packageUpdates(
            outdated: [caskUpdate("editor", installed: "1.129.0", current: "1.130.0"),
                       caskUpdate("chat", installed: "0.0.374", current: "0.0.402"),
                       caskUpdate("installer", installed: "26.078", current: "26.119"),
                       caskUpdate("pinnedApp", installed: "1.0", current: "2.0", pinned: true),
                       caskUpdate("rolling", installed: "latest", current: "latest")],
            installed: caskRecords,
            apps: packageApps)
        suite.expect(!packageRows.contains { $0.token == "editor" },
               "an app that already updated itself is not offered again")
        suite.expect(packageRows.contains { $0.token == "chat" && $0.installedVersion == "0.0.401" },
               "the version the app reports wins over the package receipt")
        suite.expect(!packageRows.contains { $0.token == "installer" },
               "a package record without an app bundle is not presented as an installed app")
        // Packages that install through an installer declare no app, so the
        // catalog name is tried as a bundle name before giving up.
        let namedRows = AppUpdatesSupport.packageUpdates(
            outdated: [caskUpdate("installer", installed: "26.078", current: "26.119")],
            installed: caskRecords,
            apps: [AppUpdatesSupport.InstalledApp(name: "Installer", bundleID: "com.vendor.installer",
                                                  path: "/Applications/Installer.app", version: "26.084",
                                                  isFromAppStore: false)])
        suite.expect(namedRows.first?.installedVersion == "26.084",
               "a package with no declared app is matched by its catalog name")
        let exactPathRecord = HomebrewCaskRecord(token: "editor", displayName: "Editor",
                                                 installedVersion: "1.0",
                                                 appFileNames: ["Editor.app"],
                                                 appPaths: ["/Users/test/Applications/Editor.app"])
        let duplicateNamedApps = [
            AppUpdatesSupport.InstalledApp(name: "Editor system", bundleID: "com.vendor.editor",
                                           path: "/Applications/Editor.app", version: "9.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Editor managed", bundleID: "com.vendor.editor",
                                           path: "/Users/test/Applications/Editor.app", version: "1.0",
                                           isFromAppStore: false),
        ]
        suite.expect(AppUpdatesSupport.packageBundle(for: exactPathRecord,
                                               apps: duplicateNamedApps)?.version == "1.0",
               "package updates use the exact managed app path when same-named copies exist")
        suite.expect(AppUpdatesSupport.packageBundle(for: caskRecords[0],
                                               apps: duplicateNamedApps,
                                               homeDirectory: "/Users/test") == nil,
               "a name-only package record never guesses between same-named app copies")
        let downloadOnlyCopy = AppUpdatesSupport.InstalledApp(
            name: "Editor download", bundleID: "com.vendor.editor",
            path: "/Users/test/Downloads/Editor.app", version: "1.0",
            isFromAppStore: false)
        suite.expect(AppUpdatesSupport.packageBundle(for: caskRecords[0],
                                               apps: [downloadOnlyCopy],
                                               homeDirectory: "/Users/test") == nil,
               "a name-only package record never claims a homonymous app outside standard app folders")
        let alreadyCurrent = AppUpdatesSupport.packageUpdates(
            outdated: [caskUpdate("installer", installed: "26.078", current: "26.119")],
            installed: caskRecords,
            apps: [AppUpdatesSupport.InstalledApp(name: "Installer", bundleID: "com.vendor.installer",
                                                  path: "/Applications/Installer.app", version: "26.200",
                                                  isFromAppStore: false)])
        suite.expect(alreadyCurrent.isEmpty,
               "the name match also suppresses an app that ran ahead of its package")
        suite.expect(!packageRows.contains { $0.token == "pinnedApp" }
                && !packageRows.contains { $0.token == "rolling" },
               "pinned packages and packages without a version stay out")
        suite.expect(packageRows.allSatisfy { $0.canInstallInPlace },
               "package rows can be installed on the spot")
        let ownPackageRows = AppUpdatesSupport.packageUpdates(
            outdated: [caskUpdate("vorssaint", installed: "3.1.12", current: "3.2.0")],
            installed: [],
            ignoredTokens: ["vorssaint"],
            apps: [])
        suite.expect(ownPackageRows.isEmpty,
               "the app update list never offers to replace Vorssaint through its own package")

        let storeApps = [
            AppUpdatesSupport.InstalledApp(name: "Blocker", bundleID: "net.example.blocker",
                                           path: "/Applications/Blocker.app",
                                           version: "2026.714.1952", isFromAppStore: true),
            AppUpdatesSupport.InstalledApp(name: "Sheets", bundleID: "com.example.sheets",
                                           path: "/Applications/Sheets.app",
                                           version: "16.111.1", isFromAppStore: true),
            AppUpdatesSupport.InstalledApp(name: "Chat", bundleID: "com.example.chat",
                                           path: "/Applications/Chat.app",
                                           version: "0.0.401", isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Future", bundleID: "com.example.future",
                                           path: "/Applications/Future.app",
                                           version: "1.0", isFromAppStore: true),
        ]
        let candidates = AppUpdatesSupport.appStoreCandidates(apps: storeApps,
                                                              coveredPaths: ["/Applications/Chat.app"])
        suite.expect(candidates.count == 3 && !candidates.contains { $0.bundleID == "com.example.chat" },
               "only store purchases are asked about, and never one the package manager answers for")
        let storeVersions = [
            "net.example.blocker": AppUpdatesSupport.StoreEntry(bundleID: "net.example.blocker",
                                                                version: "2026.723.1724",
                                                                minimumOSVersion: "14.0",
                                                                page: "https://apps.apple.com/app"),
            "com.example.sheets": AppUpdatesSupport.StoreEntry(bundleID: "com.example.sheets",
                                                               version: "16.111.1",
                                                               minimumOSVersion: nil, page: nil),
            "com.example.future": AppUpdatesSupport.StoreEntry(bundleID: "com.example.future",
                                                               version: "2.0",
                                                               minimumOSVersion: "26.0", page: nil),
        ]
        let storeRows = AppUpdatesSupport.appStoreUpdates(apps: candidates,
                                                         storeVersions: storeVersions,
                                                         operatingSystemVersion: "15.7")
        suite.expect(storeRows.count == 1 && storeRows[0].name == "Blocker"
                && !storeRows[0].canInstallInPlace,
               "a store app is listed only when its newer version runs on this macOS")

        let mergedRows = AppUpdatesSupport.merged(storeRows, packageRows)
        suite.expect(mergedRows.count == packageRows.count + storeRows.count
                && mergedRows.first?.canInstallInPlace == true
                && mergedRows.last?.canInstallInPlace == false,
               "the merged list puts what can be updated here first")
        let everything = Set(mergedRows.map(\.id))
        suite.expect(AppUpdatesSupport.tokens(in: mergedRows, selection: everything).count == packageRows.count
                && AppUpdatesSupport.hasStoreSelection(in: mergedRows, selection: everything),
               "the selection splits into package tokens and store hand-offs")
        suite.expect(AppUpdatesSupport.tokens(in: mergedRows, selection: []).isEmpty
                && !AppUpdatesSupport.hasStoreSelection(in: mergedRows, selection: []),
               "an empty selection asks for nothing")
        suite.expect(AppUpdatesSupport.singleStorePage(in: mergedRows, selection: everything)
                == "https://apps.apple.com/app",
               "one ticked store row hands off to its own page, where its own button goes")
        let secondStoreRow = AppUpdatesSupport.Item(id: "store:com.example.notes",
                                                    source: .appStore,
                                                    name: "Notes",
                                                    installedVersion: "1.0",
                                                    latestVersion: "2.0",
                                                    token: nil,
                                                    bundlePath: nil,
                                                    storePage: "https://apps.apple.com/notes")
        let twoStoreRows = mergedRows + [secondStoreRow]
        suite.expect(AppUpdatesSupport.singleStorePage(in: twoStoreRows,
                                                 selection: Set(twoStoreRows.map(\.id))) == nil
                && AppUpdatesSupport.singleStorePage(in: mergedRows, selection: []) == nil,
               "two store rows, or none, have no single page to land on")

        let keptSelection = AppUpdatesSupport.reconciledSelection(
            previous: [mergedRows[0].id, "gone:row"],
            knownIDs: Set(mergedRows.map(\.id)),
            items: mergedRows)
        suite.expect(keptSelection == [mergedRows[0].id],
               "a row that disappeared leaves the selection behind")
        let withNewFinding = AppUpdatesSupport.reconciledSelection(
            previous: [], knownIDs: [], items: mergedRows)
        suite.expect(withNewFinding == Set(mergedRows.map(\.id)),
               "findings the person has not seen yet arrive already ticked")

        suite.expect(AppUpdatesSupport.storeLookupURL(bundleIDs: [], country: "BR") == nil,
               "no identifiers means no request")
        let lookup = AppUpdatesSupport.storeLookupURL(bundleIDs: ["a.b", "c.d"], country: "BR")?
            .absoluteString ?? ""
        suite.expect(lookup.contains("bundleId=a.b,c.d") && lookup.contains("country=BR")
                && lookup.contains("entity=macSoftware"),
               "several apps are asked about in one request")
        let noCountry = AppUpdatesSupport.storeLookupURL(bundleIDs: ["a.b"], country: nil)?
            .absoluteString ?? ""
        suite.expect(!noCountry.contains("country="), "without a region the request carries none")
        let lookupBody = Data(#"{"resultCount":2,"results":[{"kind":"mac-software","bundleId":"a.b","version":"2.0","minimumOsVersion":"15.0","trackViewUrl":"https://x"},{"kind":"software","bundleId":"c.d","version":"9.0","minimumOsVersion":"12.0"}]}"#.utf8)
        let lookupEntries = AppUpdatesSupport.parseStoreLookup(lookupBody)
        let lookupEntry = lookupEntries["a.b"]
        suite.expect(lookupEntry?.version == "2.0" && lookupEntry?.minimumOSVersion == "15.0",
               "the store answer is read back")
        suite.expect(lookupEntries["c.d"] == nil,
               "another platform's listing is not the installed Mac app's version")
        suite.expect(AppUpdatesSupport.parseStoreLookup(Data("not json".utf8)).isEmpty,
               "a broken store answer yields nothing instead of throwing")

        let completeLookup = AppUpdatesSupport.storeLookupResponse(
            lookupBody, statusCode: 200)
        suite.expect(AppUpdatesSupport.hasStoreCoverage(bundleIDs: ["a.b"], entries: completeLookup)
                && completeLookup["a.b"]?.version == "2.0",
               "a successful Mac listing covers its requested app")
        let partialLookup = AppUpdatesSupport.storeLookupResponse(
            lookupBody, statusCode: 200)
        suite.expect(!AppUpdatesSupport.hasStoreCoverage(bundleIDs: ["a.b", "c.d"], entries: partialLookup)
                && partialLookup["a.b"]?.version == "2.0",
               "another platform's listing leaves coverage incomplete without losing valid results")
        suite.expect(!AppUpdatesSupport.hasStoreCoverage(bundleIDs: ["a.b", "missing.app"], entries: partialLookup),
               "a catalog omission cannot mean the missing app is up to date")
        let storeFailures: [(Data?, Int?)] = [
            (nil, 200), (lookupBody, nil), (lookupBody, 429), (lookupBody, 500),
            (Data("not json".utf8), 200), (Data("{}".utf8), 200),
            (Data(#"{"resultCount":0,"results":[]}"#.utf8), 200),
            (Data(#"{"results":[{"kind":"mac-software","bundleId":"a.b","version":""}]}"#.utf8), 200),
        ]
        for (body, status) in storeFailures {
            let result = AppUpdatesSupport.storeLookupResponse(body, statusCode: status)
            suite.expect(!AppUpdatesSupport.hasStoreCoverage(bundleIDs: ["a.b"], entries: result) && result.isEmpty,
                   "failed, malformed and empty store responses never certify an app as checked")
        }
        let partiallyCheckedApps = [AppUpdatesSupport.InstalledApp(
            name: "Editor", bundleID: "a.b", path: "/Applications/Editor.app",
            version: "1.0", isFromAppStore: true)]
        let partialStoreRows = AppUpdatesSupport.appStoreUpdates(
            apps: partiallyCheckedApps, storeVersions: partialLookup,
            operatingSystemVersion: "26.0")
        suite.expect(partialStoreRows.count == 1 && partialStoreRows[0].latestVersion == "2.0",
               "a partial store check still offers the updates it could verify")
        let uncheckedReader = AppUpdatesSupport.InstalledApp(
            name: "Reader", bundleID: "reader.example", path: "/Applications/Reader.app",
            version: "1.0", isFromAppStore: false)
        suite.expect(AppUpdatesSupport.uncheckedAppNames(
            partiallyCheckedApps + [uncheckedReader, uncheckedReader],
            checkedPaths: [partiallyCheckedApps[0].path]) == ["Reader"],
               "partial checks name only pending apps and coalesce repeated source failures")
        suite.expect(AppUpdatesSupport.uncheckedAppNames(
            [uncheckedReader], checkedPaths: [uncheckedReader.path]).isEmpty,
               "a successful publisher answer removes the app from failed catalog details")

        suite.expect(AppUpdatesSupport.storeIDLookupURL(ids: ["123", "456"], country: "BR")?
            .absoluteString.contains("id=123,456") == true
                && AppUpdatesSupport.storeIDLookupURL(ids: ["123"], country: "BR")?
                    .absoluteString.contains("platform=macappstore") == true,
               "store lookups use the product identity and explicitly request Mac metadata")
        suite.expect(AppUpdatesSupport.storeIDLookupURL(ids: [], country: nil) == nil
                && AppUpdatesSupport.storeIDLookupURL(ids: ["12&country=US"], country: nil) == nil,
               "store identifiers cannot add query parameters or create an empty request")
        let universalStoreBody = Data(#"""
        {"results":{
          "123":{"bundleId":"com.example.universal","kind":"iosSoftware","deviceFamilies":["mac","iphone"],"minimumOSVersion":"14.0","url":"https://apps.apple.com/app/id123","offers":[{"version":{"display":"2.0"},"assets":[{"flavor":"macSoftware"}]},{"version":{"display":"9.0"},"assets":[{"flavor":"iosSoftware"}]}]},
          "456":{"bundleId":"com.example.mobile","deviceFamilies":["iphone"],"minimumOSVersion":"18.0","offers":[{"version":{"display":"9.0"},"assets":[{"flavor":"iosSoftware"}]}]},
          "789":{"bundleId":"com.example.no-mac-offer","deviceFamilies":["mac","iphone"],"minimumOSVersion":"14.0","offers":[{"version":{"display":"9.0"},"assets":[{"flavor":"iosSoftware"}]}]}
        }}
        """#.utf8)
        let universalEntries = AppUpdatesSupport.storeMetadataResponse(universalStoreBody, statusCode: 200)
        suite.expect(universalEntries.count == 1 && universalEntries["com.example.universal"]?.version == "2.0"
                && universalEntries["com.example.universal"]?.minimumOSVersion == "14.0",
               "universal store apps use the Mac offer and Mac OS requirement, not the mobile version")
        let universalApp = AppUpdatesSupport.InstalledApp(name: "Universal", bundleID: "com.example.universal",
            path: "/Applications/Universal.app", version: "1.0", isFromAppStore: true)
        suite.expect(AppUpdatesSupport.appStoreUpdates(apps: [universalApp], storeVersions: universalEntries,
                                                operatingSystemVersion: "15.0").count == 1
                && AppUpdatesSupport.appStoreUpdates(apps: [universalApp], storeVersions: universalEntries,
                                                    operatingSystemVersion: "13.0").isEmpty,
               "a universal app update is detected only on a compatible Mac")
        suite.expect(AppUpdatesSupport.storeMetadataResponse(universalStoreBody, statusCode: 500).isEmpty
                && AppUpdatesSupport.storeMetadataResponse(Data("{}".utf8), statusCode: 200).isEmpty,
               "failed platform-specific lookups cannot create updates")
        let renamedStoreApp = AppUpdatesSupport.InstalledApp(
            name: "Editor", bundleID: "com.vendor.editor", path: "/Applications/Editor.app",
            version: "1.0", isFromAppStore: true)
        suite.expect(AppUpdatesSupport.packageUpdates(
            outdated: [caskUpdate("editor", installed: "1.0", current: "2.0")],
            installed: caskRecords, apps: [renamedStoreApp]).isEmpty,
               "an old package receipt cannot claim the store edition of an app")

        let publisherFeed = AppUpdateFeedSupport.feed(
            info: ["SUFeedURL": "https://updates.example.com/feed.xml"], configuration: nil)
        suite.expect(publisherFeed?.format == .appcast, "the app's declared feed is a supported source")
        suite.expect(AppUpdateFeedSupport.feedIsAbsent(statusCode: 404)
                && AppUpdateFeedSupport.feedIsAbsent(statusCode: 410)
                && !AppUpdateFeedSupport.feedIsAbsent(statusCode: 200)
                && !AppUpdateFeedSupport.feedIsAbsent(statusCode: 403)
                && !AppUpdateFeedSupport.feedIsAbsent(statusCode: 500)
                && !AppUpdateFeedSupport.feedIsAbsent(statusCode: 503)
               && !AppUpdateFeedSupport.feedIsAbsent(statusCode: nil),
               "only missing publisher responses can use catalog coverage")
        let packagedFeed = AppUpdateFeedSupport.feed(info: [:], configuration:
            "provider: generic\nurl: 'https://updates.example.com/stable'\n")
        suite.expect(packagedFeed?.url.absoluteString == "https://updates.example.com/stable/latest-mac.yml",
               "packaged update configuration selects the Mac release manifest")
        let hostedFeed = AppUpdateFeedSupport.feed(info: [:], configuration:
            "provider: github\nowner: example\nrepo: editor\n")
        suite.expect(hostedFeed?.url.absoluteString == "https://github.com/example/editor/releases/latest/download/latest-mac.yml",
               "an explicitly declared release repository supplies its Mac metadata")
        for invalid in ["file:///tmp/feed.xml", "http://example.com/feed.xml",
                        "https://user:password@example.com/feed.xml", "https://localhost/feed.xml",
                        "https://127.0.0.1/feed.xml", "https://192.168.1.1/feed.xml"] {
            suite.expect(AppUpdateFeedSupport.publicURL(invalid) == nil,
                   "feed discovery rejects local, insecure and credential-bearing URLs")
        }
        for invalid in ["provider: github\nowner: ../user\nrepo: editor",
                        "provider: github\nowner: user\nrepo: editor\nprivate: true",
                        "provider: generic\nurl: https://example.com\nchannel: beta",
                        "provider: generic\nurl: https://example.com\nrequestHeaders:\n  Authorization: secret",
                        "provider: custom\nurl: https://example.com",
                        "provider: generic\nurl: https://example.com\nurl: https://other.example.com"] {
            suite.expect(AppUpdateFeedSupport.feed(info: [:], configuration: invalid) == nil,
                   "private, ambiguous and unsupported update configuration is not guessed")
        }
        let appcast = Data(#"""
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
          <item><sparkle:version>110</sparkle:version><sparkle:shortVersionString>1.1</sparkle:shortVersionString><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion><enclosure url="https://example.com/app.zip" /></item>
          <item><sparkle:version>200</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString><sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion><enclosure url="https://example.com/new.zip" /></item>
          <item><sparkle:channel>beta</sparkle:channel><enclosure sparkle:version="300" sparkle:shortVersionString="3.0" url="https://example.com/beta.zip" /></item>
          <item><enclosure sparkle:version="400" sparkle:shortVersionString="4.0" sparkle:os="windows" url="https://example.com/app.exe" /></item>
          <item><sparkle:deltas><enclosure sparkle:version="500" sparkle:deltaFrom="100" url="https://example.com/app.delta" /></sparkle:deltas></item>
        </channel></rss>
        """#.utf8)
        let feedApp = AppUpdatesSupport.InstalledApp(
            name: "Editor", bundleID: "com.example.editor", path: "/Applications/Editor.app",
            version: "1.0", isFromAppStore: false, buildVersion: "100")
        let releases = AppUpdateFeedSupport.releases(data: appcast, format: .appcast) ?? []
        func feedUpdate(_ releases: [AppUpdateFeedSupport.Release],
                        format: AppUpdateFeedSupport.Format = .appcast) -> AppUpdatesSupport.Item? {
            AppUpdateFeedSupport.update(app: feedApp, releases: releases, format: format,
                                        operatingSystemVersion: "15.7", kernelVersion: "24.6.0",
                                        architecture: "arm64")
        }
        suite.expect(feedUpdate(releases)?.latestVersion == "1.1",
               "feeds choose the newest compatible stable Mac release, not the first or largest entry")
        suite.expect(feedUpdate(releases)?.isSelectable == false && feedUpdate(releases)?.token == nil,
               "publisher findings leave installation with the app's own updater")
        suite.expect(feedUpdate([.init(version: "101", displayVersion: "1.0", hasDownload: true)])?
            .latestVersion == "1.0 (101)",
               "new builds with the same visible version are detected and distinguished")
        for excluded in [
            AppUpdateFeedSupport.Release(version: "99", displayVersion: "2.0", hasDownload: true),
            .init(version: "110", displayVersion: "1.1beta", hasDownload: true),
            .init(version: "110", displayVersion: "1.1", maximumOS: "14.0", hasDownload: true),
            .init(version: "110", displayVersion: "1.1", minimumInstalledVersion: "105", hasDownload: true),
            .init(version: "110", displayVersion: "1.1", hardware: "x86_64", hasDownload: true),
        ] {
            suite.expect(feedUpdate([excluded]) == nil,
                   "older builds, preview releases and incompatible update paths are excluded")
        }
        for invalid in [Data("<rss><channel><item>".utf8), Data("<html/>".utf8),
                        Data(#"<!DOCTYPE rss [<!ENTITY x "110">]><rss><channel><item><version>&x;</version></item></channel></rss>"#.utf8),
                        Data(repeating: 32, count: AppUpdateFeedSupport.byteLimit + 1)] {
            suite.expect(AppUpdateFeedSupport.releases(data: invalid, format: .appcast) == nil,
                   "malformed, non-feed, entity-bearing and oversized responses are rejected")
        }
        let manifest = Data("version: 1.2\nfiles:\n  - url: app.zip\nminimumSystemVersion: 24.0.0\n".utf8)
        let manifestReleases = AppUpdateFeedSupport.releases(data: manifest, format: .manifest) ?? []
        suite.expect(feedUpdate(manifestReleases, format: .manifest)?.latestVersion == "1.2",
               "Mac manifests compare visible app versions and use the kernel version for their OS requirement")
        let absentFindings = AppUpdateFeedSupport.findings(
            loadResult: .absent, format: .manifest, apps: [feedApp],
            operatingSystemVersion: "15.7", kernelVersion: "24.6.0", architecture: "arm64")
        suite.expect(absentFindings.complete && absentFindings.checkedPaths.isEmpty
                && absentFindings.uncheckedPaths.isEmpty
                && absentFindings.catalogFallbackPaths == [feedApp.path],
               "an absent publisher manifest requires catalog coverage before clearing its warning")
        let failedFindings = AppUpdateFeedSupport.findings(
            loadResult: .failed, format: .manifest, apps: [feedApp],
            operatingSystemVersion: "15.7", kernelVersion: "24.6.0", architecture: "arm64")
        suite.expect(!failedFindings.complete && failedFindings.checkedPaths.isEmpty
                && failedFindings.uncheckedPaths == [feedApp.path],
               "a failed publisher manifest remains incomplete and names the app")
        let successfulFindings = AppUpdateFeedSupport.findings(
            loadResult: .data(manifest), format: .manifest, apps: [feedApp],
            operatingSystemVersion: "15.7", kernelVersion: "24.6.0", architecture: "arm64")
        suite.expect(successfulFindings.complete && successfulFindings.checkedPaths == [feedApp.path]
                && successfulFindings.uncheckedPaths.isEmpty
               && successfulFindings.items.first?.latestVersion == "1.2",
               "a readable publisher manifest still reports its newer release")
        let unparseableFindings = AppUpdateFeedSupport.findings(
            loadResult: .data(Data("not a manifest".utf8)), format: .manifest, apps: [feedApp],
            operatingSystemVersion: "15.7", kernelVersion: "24.6.0", architecture: "arm64")
        suite.expect(!unparseableFindings.complete && unparseableFindings.checkedPaths.isEmpty
                && unparseableFindings.uncheckedPaths == [feedApp.path]
                && unparseableFindings.items.isEmpty,
               "an unreadable publisher manifest stays a failure and is not treated as absent")
        let unstableFeedApp = AppUpdatesSupport.InstalledApp(
            name: "Preview", bundleID: "com.example.preview", path: "/Applications/Preview.app",
            version: "1.2b", isFromAppStore: false)
        let unstableFindings = AppUpdateFeedSupport.findings(
            loadResult: .data(manifest), format: .manifest, apps: [unstableFeedApp],
            operatingSystemVersion: "15.7", kernelVersion: "24.6.0", architecture: "arm64")
        suite.expect(!unstableFindings.complete && unstableFindings.checkedPaths.isEmpty
                && unstableFindings.uncheckedPaths == [unstableFeedApp.path],
               "a publisher feed cannot check an app with an unstable installed version")
        suite.expect(feedUpdate([.init(version: "1.2", displayVersion: "1.2", minimumOS: "25.0.0", hasDownload: true)],
                          format: .manifest) == nil,
               "a manifest requiring a newer kernel cannot be offered")

        let onlineCatalogBody = Data(#"""
        [
          {"token":"notes-stable","version":"2.0,revision","artifacts":[{"uninstall":[{"quit":"com.example.notes"}]},{"app":["Notes.app"],"target":"/Applications/Notes.app"}],"depends_on":{"macos":{">=":["14"]}}},
          {"token":"notes-preview","version":"3.0","artifacts":[{"uninstall":[{"quit":["com.example.notes.preview"]}]},{"app":["Notes.app"]}],"depends_on":{"macos":{">=":["14"]}}},
          {"token":"writer","version":"2.0","artifacts":[{"app":["Writer Source.app",{"target":"Writer.app"}],"target":"/Applications/Writer.app"}]},
          {"token":"duplicate-one","version":"2.0","artifacts":[{"uninstall":[{"quit":"com.example.one"}]},{"app":["Duplicate.app"]}]},
          {"token":"duplicate-two","version":"2.0","artifacts":[{"uninstall":[{"quit":"com.example.two"}]},{"app":["Duplicate.app"]}]},
          {"token":"future","version":"4.0","artifacts":[{"app":["Future.app"]}],"depends_on":{"macos":{">=":["26"]}}},
          {"token":"exact","version":"5.0","artifacts":[{"app":["Exact.app"]}],"depends_on":{"macos":{"==":["15"]}}},
          {"token":"rolling","version":"latest","artifacts":[{"app":["Rolling.app"]}]},
          {"token":"case-sensitive","version":"2.0","artifacts":[{"app":["Case.app"]}]},
          {"token":"older","version":"1.0","artifacts":[{"app":["Older.app"]}]},
          {"token":"own-tool","version":"9.0","artifacts":[{"app":["Own.app"]}]}
        ]
        """#.utf8)
        let onlineCatalog = AppUpdatesSupport.parseOnlineCatalog(onlineCatalogBody) ?? []
        suite.expect(onlineCatalog.count == 11
                && onlineCatalog.first?.bundleIDs == ["com.example.notes"]
                && onlineCatalog.first?.minimumOSVersions == ["14"]
                && onlineCatalog.first { $0.token == "writer" }?.appNames == ["Writer.app"],
               "the online catalog keeps final app names, explicit bundle identifiers and OS rules")
        suite.expect(AppUpdatesSupport.parseOnlineCatalogResponse(onlineCatalogBody, statusCode: 200)?.count == 11
                && AppUpdatesSupport.parseOnlineCatalogResponse(nil, statusCode: 200) == nil
                && AppUpdatesSupport.parseOnlineCatalogResponse(onlineCatalogBody, statusCode: 500) == nil
                && AppUpdatesSupport.parseOnlineCatalogResponse(Data("broken".utf8), statusCode: 200) == nil,
               "missing, failed and malformed network responses never become successful empty coverage")

        let onlineApps = [
            AppUpdatesSupport.InstalledApp(name: "Notes", bundleID: "com.example.notes",
                                           path: "/Applications/Notes.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Writer", bundleID: "com.example.writer",
                                           path: "/Applications/Writer.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Duplicate", bundleID: "com.example.other",
                                           path: "/Applications/Duplicate.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Future", bundleID: "com.example.future",
                                           path: "/Applications/Future.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Exact", bundleID: "com.example.exact",
                                           path: "/Applications/Exact.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Rolling", bundleID: "com.example.rolling",
                                           path: "/Applications/Rolling.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Case", bundleID: "com.example.case",
                                           path: "/Applications/case.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Older", bundleID: "com.example.older",
                                           path: "/Applications/Older.app", version: "2.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Own", bundleID: "com.example.own",
                                           path: "/Applications/Own.app", version: "1.0",
                                           isFromAppStore: false),
        ]
        let onlineRows = AppUpdatesSupport.onlineCatalogFindings(
            apps: onlineApps, catalog: onlineCatalog, operatingSystemVersion: "15.7",
            ignoredTokens: ["own-tool"]).items
        suite.expect(Set(onlineRows.map(\.name)) == ["Notes", "Writer", "Exact"]
                && onlineRows.allSatisfy { $0.source == .onlineCatalog && !$0.isSelectable },
               "online matching requires an exact unique bundle name, uses an explicit ID to resolve ambiguity and keeps rows action-only")
        let expandedCatalogBody = Data(#"""
        [
          {"token":"installer","version":"2.0","artifacts":[{"pkg":["installer.pkg"]},{"uninstall":[{"quit":["com.example.installer","com.example.installer.helper"],"delete":["/Applications/Installed.app","/Applications/Wild*.app","/tmp/Other.app"]}]}]},
          {"token":"renamed","version":"2.0","artifacts":[{"app":["Original.app"]},{"uninstall":[{"quit":"com.example.renamed"}]}]},
          {"token":"unrelated","version":"9.0","artifacts":[{"app":["Unrelated.app"]},{"uninstall":[{"quit":"com.example.other"}]}]},
          {"token":"companion","version":"99.0","artifacts":[{"app":["Companion.app"]},{"uninstall":[{"quit":["com.example.companion","com.example.renamed"]}]}]}
        ]
        """#.utf8)
        let expandedCatalog = AppUpdatesSupport.parseOnlineCatalog(expandedCatalogBody) ?? []
        suite.expect(expandedCatalog.first?.appNames == ["Installed.app"],
               "installer removal metadata supplies exact app names without treating globs or temporary paths as installed apps")
        let expandedApps = [
            AppUpdatesSupport.InstalledApp(name: "Installer", bundleID: "com.example.installer",
                path: "/Applications/Installed.app", version: "1.0", isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Renamed", bundleID: "com.example.renamed",
                path: "/Applications/My App.app", version: "1.0", isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Unrelated", bundleID: "com.example.unrelated",
                path: "/Applications/Unrelated.app", version: "1.0", isFromAppStore: false),
        ]
        let expandedRows = AppUpdatesSupport.onlineCatalogFindings(
            apps: expandedApps, catalog: expandedCatalog, operatingSystemVersion: "15.7").items
        suite.expect(Set(expandedRows.map(\.name)) == ["Installer", "Renamed"],
               "identity matching finds installer-based and renamed apps without accepting a conflicting same-name app")
        suite.expect(expandedRows.allSatisfy { $0.latestVersion == "2.0" },
               "a companion app's quit list cannot take over another app's identity")
        suite.expect(AppUpdatesSupport.onlineCatalogFindings(
            apps: expandedApps, catalog: expandedCatalog + expandedCatalog,
            operatingSystemVersion: "15.7").items.isEmpty,
               "multiple catalog entries claiming the same identity cannot choose an update by guesswork")
        suite.expect(!onlineRows.contains { $0.name == "Duplicate" || $0.name == "Future"
                || $0.name == "Rolling" || $0.name == "Case" || $0.name == "Older"
                || $0.name == "Own" },
               "ambiguous, incompatible, uncomparable, differently cased, current and ignored catalog entries stay out")
        let externalCandidates = AppUpdatesSupport.onlineCatalogCandidates(
            apps: [onlineApps[0],
                   AppUpdatesSupport.InstalledApp(name: "Store", bundleID: "com.example.store",
                                                  path: "/Applications/Store.app", version: "1.0",
                                                  isFromAppStore: true),
                   onlineApps[1]],
            coveredPaths: [onlineApps[1].path])
        suite.expect(externalCandidates == [onlineApps[0]],
               "store receipts and package-managed paths never reach the online catalog source")

        let listWithOnline = AppUpdatesSupport.merged(mergedRows, onlineRows)
        let selectionWithOnline = AppUpdatesSupport.reconciledSelection(
            previous: Set(onlineRows.map(\.id)), knownIDs: [], items: listWithOnline)
        suite.expect(selectionWithOnline == Set(mergedRows.map(\.id))
                && listWithOnline.suffix(onlineRows.count).allSatisfy { $0.source == .onlineCatalog },
               "online rows remain outside bulk selection and follow the managed sources in the list")
        let discoveredPaths = InstalledApps.applicationScanPaths(
            folderPaths: ["/Applications/Editor.app",
                          "/System/Applications/System Utility.app",
                          "/Applications/Editor.app"],
            spotlightPaths: ["/Users/test/Tools/Side App.app",
                             "/Users/test/.Trash/Old.app",
                             "/Users/test/Library/Services/Helper.app",
                             "/Users/test/Projects/Sample/build/Debug.app",
                             "/Users/test/Tools/Container.app/Contents/Helper.app",
                             "/Volumes/Installer/Sample.app"],
            homeDirectory: "/Users/test")
        suite.expect(discoveredPaths == ["/Applications/Editor.app", "/Users/test/Tools/Side App.app"],
               "shared app discovery keeps installed apps and rejects system, transient, nested and duplicate copies")

        let noon = Date(timeIntervalSince1970: 1_800_000_000)
        suite.expect(AppUpdatesSupport.nextCheckDate(lastCheck: noon, frequency: .off, now: noon) == nil,
               "with the schedule off nothing is armed")
        suite.expect(AppUpdatesSupport.nextCheckDate(lastCheck: nil, frequency: .daily, now: noon)
                == noon.addingTimeInterval(AppUpdatesSupport.catchUpDelay),
               "a schedule that never ran starts shortly after launch")
        suite.expect(AppUpdatesSupport.nextCheckDate(lastCheck: noon, frequency: .daily, now: noon)
                == noon.addingTimeInterval(86_400),
               "the next daily check follows the last one")
        suite.expect(AppUpdatesSupport.nextCheckDate(lastCheck: noon.addingTimeInterval(-200_000),
                                               frequency: .daily, now: noon)
                == noon.addingTimeInterval(AppUpdatesSupport.catchUpDelay),
               "a check missed while the Mac was off runs soon, not instantly")
        suite.expect(AppUpdatesSupport.shouldRecheck(hasCheckedThisSession: false, handoffPending: false,
                                               lastCheck: noon, now: noon),
               "a session that never scanned always scans on opening")
        suite.expect(AppUpdatesSupport.shouldRecheck(hasCheckedThisSession: true, handoffPending: true,
                                               lastCheck: noon, now: noon),
               "coming back from the store always re-reads the list")
        suite.expect(!AppUpdatesSupport.shouldRecheck(hasCheckedThisSession: true, handoffPending: false,
                                                lastCheck: noon, now: noon.addingTimeInterval(60)),
               "reopening the panel right away costs nothing")
        suite.expect(AppUpdatesSupport.shouldRecheck(hasCheckedThisSession: true, handoffPending: false,
                                               lastCheck: noon,
                                               now: noon.addingTimeInterval(AppUpdatesSupport.staleAfter)),
               "an old answer is read again")
        suite.expect(AppUpdatesSupport.CheckFrequency.sanitized("weekly") == .weekly
                && AppUpdatesSupport.CheckFrequency.sanitized("nonsense") == .off
                && AppUpdatesSupport.CheckFrequency.sanitized(nil) == .off,
               "a damaged frequency falls back to off")

        suite.expect(HomebrewCommandBuilder.upgradeCasks(brewPath: "/opt/x/brew", tokens: [])?.arguments == nil
                && HomebrewCommandBuilder.upgradeCasks(brewPath: "/opt/x/brew",
                                                       tokens: ["; rm -rf /"])?.arguments == nil,
               "an upgrade with nothing valid to name builds no command")
        suite.expect(HomebrewCommandBuilder.upgradeCasks(brewPath: "/opt/x/brew",
                                                   tokens: ["chat", "--force", "editor"])?.arguments
                == ["upgrade", "--cask", "--greedy", "chat", "editor"],
               "only real package names reach the upgrade command")
        suite.expect(HomebrewCommandBuilder.outdatedCasksIncludingSelfUpdating(brewPath: "/opt/x/brew").arguments
                == ["outdated", "--cask", "--greedy", "--json=v2"],
               "the update check asks for the apps that carry their own updater too")
        let caskJSON = #"{"formulae":[],"casks":[{"token":"editor","name":["Editor"],"installed":"1.129.0","artifacts":[{"app":["Source.app",{"target":"Editor.app"}],"target":"/Applications/Editor.app"},{"zap":[]}]},{"token":"tapped-tool","full_token":"example/tap/tapped-tool","name":["Tapped Tool"],"installed":"1.0.0","artifacts":[{"app":["Tapped Tool.app"]}]}]}"#
        let parsedRecords = HomebrewParser.parseInstalledCaskRecords(caskJSON)
        suite.expect(parsedRecords.count == 2 && parsedRecords[0].appFileNames == ["Editor.app"]
                && parsedRecords[0].appPaths == ["/Applications/Editor.app"]
                && parsedRecords[0].displayName == "Editor"
                && parsedRecords[0].installedVersion == "1.129.0",
               "an installed package is traced to the final app name after a rename")
        suite.expect(parsedRecords.first { $0.token == "tapped-tool" }?.displayName == "Tapped Tool",
               "parseInstalledCaskRecords keeps the short token brew outdated reports for a cask from a tap")
        suite.expect(HomebrewParser.parseInstalledCaskRecords("garbage").isEmpty,
               "unreadable package output yields no records")
        let managedPackage = HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Applications/Editor.app",
            installed: parsedRecords
        )
        suite.expect(managedPackage?.name == "editor" && managedPackage?.kind == .cask,
               "the exact installed app path resolves to its package")
        suite.expect(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Users/test/Desktop/Editor.app",
            installed: parsedRecords
        ) == nil,
        "a same-named app outside the managed path never resolves to a package")
        let legacyRecord = HomebrewCaskRecord(token: "legacy-tool",
                                              displayName: "Legacy Tool",
                                              installedVersion: "2.0",
                                              appFileNames: ["Legacy Tool.app"])
        suite.expect(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Users/test/Applications/Legacy Tool.app",
            installed: [legacyRecord]
        ) == nil,
        "package uninstall requires exact path ownership even when the catalog omits its target")
        suite.expect(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Applications/Legacy Tool.app",
            installed: [legacyRecord, legacyRecord]
        ) == nil,
        "ambiguous package ownership is never used for uninstall")

        suite.expect(Defaults.utilityOrderWithAppUpdates("screenshot,quickLauncher,cleaner,homebrew")
                == ["screenshot", "quickLauncher", "appUpdates", "cleaner", "homebrew"],
               "app updates joins a saved panel order next to its siblings")
        suite.expect(Defaults.utilityOrderWithAppUpdates("media,clipboard")
                == ["media", "appUpdates", "clipboard"],
               "without the cleaner to anchor to, it still lands near the top")
        suite.expect(Defaults.utilityOrderWithAppUpdates("cleaner,appUpdates,media")
                == ["cleaner", "appUpdates", "media"],
               "an order that already has it is left alone")
        suite.expect(Defaults.utilityOrderWithAppUpdates("") == ["appUpdates"],
               "an empty saved order does not lose the entry")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.appUpdatesCheckFrequency] as? String == "off",
               "the background check starts off")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.appUpdatesIncludeHomebrewApps] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.appUpdatesIncludeAppStore] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.appUpdatesIncludeOnlineCatalog] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.appUpdatesNotify] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.panelUtilityAppUpdates] as? Bool == true,
               "the app update defaults are registered")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.appUpdatesCheckFrequency)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.appUpdatesIncludeHomebrewApps)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.appUpdatesIncludeOnlineCatalog)
                && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.appUpdatesLastCheck),
               "app update preferences travel in a backup, the last check does not")
        suite.expect(AppFeature.appUpdates.enabledKeys.isEmpty
                && AppFeature.appUpdates.permissions == [.notifications, .appManagement]
                && AppFeature.appUpdates.group == .tools,
               "app updates is an on demand tool that declares its update access")
        suite.expect(FeatureVisibilitySupport.features(for: .appUpdates) == [.appUpdates]
                && !FeatureVisibilitySupport.isPageVisible(.appUpdates, isAvailable: { _ in false }),
               "the page follows the feature in the hub")
        suite.expect(activeSet(.notifications, on: [DefaultsKey.appUpdatesNotify],
                         strings: [DefaultsKey.appUpdatesCheckFrequency: "daily"])
                .contains(.appUpdates),
               "app updates only use notifications with a background check armed")
        suite.expect(!activeSet(.notifications, on: [DefaultsKey.appUpdatesNotify])
                .contains(.appUpdates),
               "with the schedule off, app updates need no notification permission")

    }
}
