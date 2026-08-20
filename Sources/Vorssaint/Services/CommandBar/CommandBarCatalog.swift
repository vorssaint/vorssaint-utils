// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// One row the command bar can offer: something to find, read and run.
struct CommandBarEntry: Identifiable {
    enum Icon {
        case symbol(String)
        case appIcon(path: String)
        case clipboardImage(name: String)
        case filePath(String)
    }

    /// Why Return will not do the main thing yet. The row says so in one
    /// sentence instead of failing silently.
    enum Trouble {
        /// The feature is installed but its switch is off; Return opens the
        /// Settings page where it lives.
        case needsSetup(featureTitle: String, page: SettingsPage)
        /// A system permission is missing; Return runs anyway, which is what
        /// triggers the system prompt.
        case needsPermission
    }

    let id: String
    /// What a name, a pin or a habit is filed under. It has to survive what
    /// the id cannot: an app moving folder or being reinstalled somewhere
    /// else keeps its bundle id, while its path changes and would silently
    /// throw the person's name for it away.
    let stableKey: String
    let title: String
    let subtitle: String
    let keywords: String
    let icon: Icon
    let shortcut: GlobalShortcut?
    /// A shortcut that belongs to someone else's menu, already written out.
    let menuShortcut: String?
    /// A live state worth a small badge (keep awake on, mic muted).
    let isActive: Bool
    let trouble: Trouble?
    /// Present on commands that take a number ("brilho 40"); the bound range.
    let numericRange: ClosedRange<Int>?
    /// True when the number is welcome but not required, so Return without one
    /// still does the obvious thing instead of asking.
    let numericIsOptional: Bool
    /// The phrase the row shows before a destructive Return.
    let confirmationPrompt: String?
    /// A fact this row answers, shown on the right in the accent color.
    let answerValue: String?
    /// The calculator's row: pinned above everything and styled as a result.
    let isAnswer: Bool
    let countsUsage: Bool
    /// The text the ranking reads instead of the title, for the rows whose
    /// title carries something that is not a word. An emoji row shows the
    /// glyph first, and a glyph at the front of a title blocks the prefix
    /// bonus that the name deserves: "fire" would find a browser before it
    /// found the flame the bar itself offers as its example.
    let matchTitle: String?
    /// True for the few rows whose whole point is to leave the field standing:
    /// they put something INTO the bar instead of doing something with it.
    let keepsBarOpen: Bool
    /// True for a row that reads whatever is typed after its own name, the way
    /// a saved search does. The ranking has to score it against everything
    /// typed, or the words of the argument drop it from the list at the exact
    /// moment it was about to run. A row that does nothing with those words
    /// goes on answering to its name alone.
    let takesArgument: Bool
    /// Where this row lives on the disk, for the rows that are a real file:
    /// an app, one of the Mac's own folders, a place the person saved. The
    /// rows the bar makes up have no such place, and saying so here is what
    /// keeps ⌘Return and the actions list from ever disagreeing about it.
    let revealPath: String?
    let run: (Int?) -> Void

    /// Whether this row can be shown where it lives. One rule, read by the
    /// combination and by the actions list alike.
    var canRevealInFinder: Bool { revealPath != nil }

    /// Whether running this row asks the person something first. A row that
    /// would confirm, or wait for a number, or send them to a Settings page
    /// must do the same from a global shortcut as it does from the bar.
    var needsPrompt: Bool {
        if confirmationPrompt != nil { return true }
        if numericRange != nil, !numericIsOptional { return true }
        if case .needsSetup = trouble { return true }
        return false
    }

    /// The same row with a different caption, for the browse list: under a
    /// heading that already says "Tools", every row repeating "Tools" is noise.
    func withSubtitle(_ subtitle: String) -> CommandBarEntry {
        CommandBarEntry(id: id, stableKey: stableKey, title: title, subtitle: subtitle,
                        keywords: keywords, icon: icon, shortcut: shortcut,
                        menuShortcut: menuShortcut, isActive: isActive, trouble: trouble,
                        numericRange: numericRange, numericIsOptional: numericIsOptional,
                        confirmationPrompt: confirmationPrompt, answerValue: answerValue,
                        isAnswer: isAnswer, countsUsage: countsUsage,
                        matchTitle: matchTitle, keepsBarOpen: keepsBarOpen,
                        takesArgument: takesArgument, revealPath: revealPath, run: run)
    }

    /// Glyph rows get a tinted plate behind the icon; real app, file and
    /// image icons are drawn on their own.
    var usesPlateIcon: Bool {
        if case .symbol = icon { return true }
        if case .clipboardImage = icon { return false }
        return false
    }

    init(id: String,
         stableKey: String? = nil,
         title: String,
         subtitle: String,
         keywords: String = "",
         icon: Icon,
         shortcut: GlobalShortcut? = nil,
         menuShortcut: String? = nil,
         isActive: Bool = false,
         trouble: Trouble? = nil,
         numericRange: ClosedRange<Int>? = nil,
         numericIsOptional: Bool = false,
         confirmationPrompt: String? = nil,
         answerValue: String? = nil,
         isAnswer: Bool = false,
         countsUsage: Bool = true,
         matchTitle: String? = nil,
         keepsBarOpen: Bool = false,
         takesArgument: Bool = false,
         revealPath: String? = nil,
         run: @escaping (Int?) -> Void) {
        self.id = id
        self.stableKey = stableKey ?? id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.icon = icon
        self.shortcut = shortcut
        self.menuShortcut = menuShortcut
        self.isActive = isActive
        self.trouble = trouble
        self.numericRange = numericRange
        self.numericIsOptional = numericIsOptional
        self.confirmationPrompt = confirmationPrompt
        self.answerValue = answerValue
        self.isAnswer = isAnswer
        self.countsUsage = countsUsage
        self.matchTitle = matchTitle
        self.keepsBarOpen = keepsBarOpen
        self.takesArgument = takesArgument
        self.revealPath = revealPath
        self.run = run
    }
}

/// Builds everything the bar can offer right now: the app's own actions,
/// the Settings pages, the saved snippets and the installed apps. Rebuilt on
/// every open, so availability, live states and shortcuts are always current;
/// nothing here observes anything while the bar is closed.
enum CommandBarCatalog {
    /// Ids worth discovering before any habit forms; suggestion fill-ins.
    static let curatedSuggestionIDs = [
        "action.screenshot", "action.scrollingScreenshot", "action.keepAwake", "action.screenOCR",
        "action.clipboardWindow", "action.colorPicker", "action.darkMode",
        "action.snippetLibrary",
    ]

    static func build(automationDenied: Bool) -> [CommandBarEntry] {
        let s = L10n.shared.s
        let language = L10n.shared.language
        let bar = FeatureStrings.commandBar(language)
        var entries: [CommandBarEntry] = []
        entries.append(contentsOf: actionEntries(s, language: language, bar: bar,
                                                 automationDenied: automationDenied))
        entries.append(contentsOf: toggleEntries(s, language: language, bar: bar))
        entries.append(contentsOf: systemAnswerEntries(s, bar: bar))
        entries.append(contentsOf: settingsEntries(s, language: language, bar: bar))
        entries.append(contentsOf: snippetEntries(bar))
        entries.append(contentsOf: linkEntries(
            CommandBarLinks.decode(UserDefaults.standard.data(forKey: DefaultsKey.commandBarLinks)),
            bar: bar))
        return entries
    }

    /// The human name of the area a feature lives in, the same words the hub
    /// uses, so a row and its heading never disagree.
    static func groupTitle(_ group: FeatureGroup, hub: FeatureHubStrings) -> String {
        switch group {
        case .windowsDock: return hub.groupWindowsDock
        case .mouseKeyboard: return hub.groupMouseKeyboard
        case .clipboardFiles: return hub.groupClipboardFiles
        case .sound: return hub.groupSound
        case .energyDisplay: return hub.groupEnergyDisplay
        case .tools: return hub.groupTools
        case .monitor: return hub.groupMonitor
        }
    }

    /// Every feature that is a plain on-or-off preference becomes a row that
    /// flips it, generated from the catalog itself. This is what makes the bar
    /// enough on its own: the app has twenty switches that until now needed
    /// somebody to find the right page in Settings first, and a feature added
    /// tomorrow gets its row for free.
    static func toggleEntries(_ s: Strings,
                              language: AppLanguage,
                              bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        let hub = FeatureStrings.hub(language)
        func entry(for feature: AppFeature,
                   key: String,
                   name: String,
                   id: String) -> CommandBarEntry {
            let isOn = UserDefaults.standard.bool(forKey: key)
            let needsAccessibility = feature.permissions.contains(.accessibility)
                && !Permissions.shared.accessibility
            return CommandBarEntry(
                id: id,
                title: String(format: isOn ? bar.turnOffFormat : bar.turnOnFormat, name),
                subtitle: groupTitle(feature.group, hub: hub),
                keywords: name,
                icon: .symbol(feature.symbolName),
                isActive: isOn,
                trouble: needsAccessibility ? .needsPermission : nil,
                run: { _ in
                    UserDefaults.standard.set(!isOn, forKey: key)
                    FeatureRuntime.shared.sync([feature])
                    QuickToolHUD.show(icon: feature.symbolName, message: name)
                })
        }

        return AppFeature.allCases.flatMap { feature -> [CommandBarEntry] in
            guard feature.isAvailable else { return [] }
            if feature == .scrollInverter {
                return [
                    entry(for: feature,
                          key: DefaultsKey.scrollInverterEnabled,
                          name: s.invertVerticalScroll,
                          id: "toggle.scrollInverter.vertical"),
                    entry(for: feature,
                          key: DefaultsKey.scrollInverterHorizontalEnabled,
                          name: s.invertHorizontalScroll,
                          id: "toggle.scrollInverter.horizontal"),
                ]
            }
            // Two keys means two different switches; which one a single row
            // would flip is a guess, and a guess here changes the person's Mac.
            guard feature.enabledKeys.count == 1,
                  let key = feature.enabledKeys.first else { return [] }
            let name = feature.hubTitle(s, hub: hub)
            return [entry(for: feature,
                          key: key,
                          name: name,
                          id: "toggle.\(feature.rawValue)")]
        }
    }

    // MARK: - App actions

    private static func actionEntries(_ s: Strings,
                                      language: AppLanguage,
                                      bar: CommandBarFeatureStrings,
                                      automationDenied: Bool) -> [CommandBarEntry] {
        let hub = FeatureStrings.hub(language)
        var entries: [CommandBarEntry] = []

        /// Where the action lives. When the feature's name IS the row title
        /// ("Screenshot" under "Screenshot" reads silly), the group name
        /// stands in.
        func area(_ feature: AppFeature, under title: String = "") -> String {
            let hubTitle = feature.hubTitle(s, hub: hub)
            guard hubTitle == title else { return hubTitle }
            return groupTitle(feature.group, hub: hub)
        }
        /// A shortcut is only shown while it actually fires (its enables on),
        /// so the bar never teaches a dead combination.
        func roleShortcut(_ role: GlobalShortcutRole) -> GlobalShortcut? {
            guard role.isAvailable(using: { $0.isAvailable }),
                  role.requiredEnableKeys.allSatisfy({ UserDefaults.standard.bool(forKey: $0) })
            else { return nil }
            return role.savedShortcut
        }
        func accessibilityTrouble() -> CommandBarEntry.Trouble? {
            Permissions.shared.accessibility ? nil : .needsPermission
        }

        // Screen tools first: the beat lets the bar leave before capture.
        if AppFeature.screenshot.isAvailable {
            let screenshot = FeatureStrings.screenshot(language)
            entries.append(CommandBarEntry(
                id: "action.screenshot",
                title: screenshot.pageTitle,
                subtitle: area(.screenshot, under: screenshot.pageTitle),
                icon: .symbol("camera.viewfinder"),
                shortcut: roleShortcut(.screenshot),
                trouble: Permissions.shared.screenRecording ? nil : .needsPermission,
                run: { _ in afterBeat { ScreenshotService.shared.capture() } }))
            entries.append(CommandBarEntry(
                id: "action.scrollingScreenshot",
                title: screenshot.scrollingCaptureTitle,
                subtitle: area(.screenshot, under: screenshot.pageTitle),
                icon: .symbol("rectangle.stack"),
                trouble: Permissions.shared.screenRecording && Permissions.shared.accessibility
                    ? nil : .needsPermission,
                run: { _ in afterBeat { ScreenshotService.shared.captureScrolling() } }))
        }
        if AppFeature.screenRecorder.isAvailable {
            let recorder = FeatureStrings.recorder(language)
            let running = ScreenRecorderService.shared.isRecording
            entries.append(CommandBarEntry(
                id: "action.screenRecorder",
                title: running ? recorder.stopButton : recorder.pageTitle,
                subtitle: area(.screenRecorder, under: recorder.pageTitle),
                icon: .symbol(running ? "stop.circle" : "record.circle"),
                shortcut: roleShortcut(.screenshot),
                trouble: Permissions.shared.screenRecording ? nil : .needsPermission,
                run: { _ in afterBeat { ScreenRecorderService.shared.toggle() } }))
        }
        if AppFeature.screenshot.isAvailable || AppFeature.screenRecorder.isAvailable {
            let recent = FeatureStrings.recentCaptures(language)
            entries.append(CommandBarEntry(
                id: "action.recentCaptures",
                title: recent.title,
                subtitle: groupTitle(.tools, hub: hub),
                keywords: [recent.screenshot, recent.recording,
                           RecentCaptureStrings.enUS.title].joined(separator: " "),
                icon: .symbol("clock.arrow.circlepath"),
                run: { _ in afterBeat(0.1) {
                    RecentCaptureService.shared.showHistoryWindow()
                } }))
        }
        if AppFeature.screenOCR.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.screenOCR",
                title: s.ocrName,
                subtitle: area(.screenOCR, under: s.ocrName),
                icon: .symbol("text.viewfinder"),
                shortcut: roleShortcut(.screenshot),
                trouble: Permissions.shared.screenRecording ? nil : .needsPermission,
                run: { _ in afterBeat { ScreenTextService.shared.capture() } }))
        }
        if AppFeature.colorPicker.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.colorPicker",
                title: s.colorPickerName,
                subtitle: area(.colorPicker, under: s.colorPickerName),
                icon: .symbol("eyedropper"),
                shortcut: roleShortcut(.screenshot),
                run: { _ in afterBeat { ColorSamplerService.shared.pick() } }))
        }
        if AppFeature.clipboardHistory.isAvailable {
            let clipboardTitle = FeatureStrings.clipboard(language).title
            let keepsHistory = UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled)
            let canUseHistory = CommandBarClipboardAccess.canUseHistory(
                captureEnabled: keepsHistory,
                hasSavedItems: !ClipboardHistoryService.shared.entries.isEmpty)
            entries.append(CommandBarEntry(
                id: "action.clipboardWindow",
                title: clipboardTitle,
                subtitle: area(.clipboardHistory, under: clipboardTitle),
                icon: .symbol("doc.on.clipboard"),
                shortcut: keepsHistory ? roleShortcut(.clipboard) : nil,
                trouble: canUseHistory ? nil
                    : .needsSetup(featureTitle: clipboardTitle, page: .clipboard),
                run: { _ in afterBeat(0.1) { ClipboardHistoryService.shared.showHistoryWindow() } }))
        }
        if AppFeature.textSnippets.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.snippetLibrary",
                title: FeatureStrings.snippets(language).libraryTitle,
                subtitle: area(.textSnippets),
                icon: .symbol("text.append"),
                shortcut: roleShortcut(.snippetLibrary),
                run: { _ in afterBeat { SnippetLibraryService.shared.show() } }))
        }
        if AppFeature.scratchpad.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.scratchpad",
                title: FeatureStrings.scratchpad(language).pageTitle,
                subtitle: area(.scratchpad, under: FeatureStrings.scratchpad(language).pageTitle),
                icon: .symbol("note.text"),
                shortcut: roleShortcut(.scratchpad),
                run: { _ in afterBeat { ScratchpadService.shared.show() } }))
        }
        if AppFeature.cameraPreview.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.cameraPreview",
                title: FeatureStrings.cameraPreview(language).pageTitle,
                subtitle: area(.cameraPreview, under: FeatureStrings.cameraPreview(language).pageTitle),
                icon: .symbol("web.camera"),
                shortcut: roleShortcut(.cameraPreview),
                trouble: Permissions.shared.camera == .granted ? nil : .needsPermission,
                run: { _ in afterBeat { CameraPreviewService.shared.show() } }))
        }
        if AppFeature.shelf.isAvailable {
            let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
            entries.append(CommandBarEntry(
                id: "action.shelf",
                title: s.shelfName,
                subtitle: area(.shelf, under: s.shelfName),
                icon: .symbol("tray.full"),
                shortcut: enabled ? roleShortcut(.shelf) : nil,
                trouble: enabled ? nil : .needsSetup(featureTitle: s.shelfName, page: .shelf),
                run: { _ in afterBeat { ShelfService.shared.summon() } }))
        }
        if AppFeature.pastePlain.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.pastePlain",
                title: s.pastePlainName,
                subtitle: area(.pastePlain, under: s.pastePlainName),
                icon: .symbol("doc.plaintext"),
                shortcut: roleShortcut(.pastePlain),
                trouble: accessibilityTrouble(),
                run: { _ in afterBeat { PastePlainService.shared.performPastePlain() } }))
        }
        if AppFeature.cleaningMode.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.cleaningMode",
                title: s.cleaningMenuItem,
                subtitle: area(.cleaningMode, under: s.cleaningMenuItem),
                icon: .symbol("keyboard"),
                trouble: accessibilityTrouble(),
                run: { _ in afterBeat(0.1) { CleaningModeManager.shared.activate() } }))
        }

        if AppFeature.keepAwake.isAvailable {
            let awake = KeepAwakeManager.shared
            entries.append(CommandBarEntry(
                id: "action.keepAwake",
                title: awake.isActive ? s.menuDisableAwake : s.menuEnableAwake,
                subtitle: area(.keepAwake),
                keywords: s.keepAwakeTitle,
                icon: .symbol(awake.isActive ? "bolt.fill" : "bolt"),
                shortcut: roleShortcut(.keepAwake),
                isActive: awake.isActive,
                // A typed number is a duration in minutes; without one the row
                // is the plain on and off switch.
                numericRange: 1...480,
                numericIsOptional: true,
                run: { minutes in
                    if let minutes {
                        KeepAwakeManager.shared.activate(minutes: minutes)
                    } else {
                        KeepAwakeManager.shared.toggle()
                    }
                }))
            let durations: [(String, String, Int)] = [
                ("action.keepAwake.30", s.minutes30, 30),
                ("action.keepAwake.60", s.hour1, 60),
                ("action.keepAwake.120", s.hours2, 120),
            ]
            for (id, label, minutes) in durations {
                entries.append(CommandBarEntry(
                    id: id,
                    title: String(format: bar.keepAwakeForFormat, label),
                    subtitle: area(.keepAwake),
                    keywords: s.keepAwakeTitle,
                    icon: .symbol("bolt.badge.clock"),
                    run: { _ in KeepAwakeManager.shared.activate(minutes: minutes) }))
            }
        }

        if AppFeature.micMute.isAvailable {
            let muted = MicMuteService.shared.isMuted
            entries.append(CommandBarEntry(
                id: "action.micMute",
                title: muted ? s.micUnmuteName : s.micMuteName,
                subtitle: area(.micMute),
                icon: .symbol(muted ? "mic.slash.fill" : "mic"),
                shortcut: roleShortcut(.micMute),
                isActive: muted,
                run: { _ in MicMuteService.shared.toggle() }))
        }

        if AppFeature.brightness.isAvailable {
            let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.brightnessControlEnabled)
            entries.append(CommandBarEntry(
                id: "action.brightness",
                title: bar.brightnessTitle,
                subtitle: enabled
                    ? String(format: bar.argumentRangeFormat, 0, 100)
                    : area(.brightness),
                // The Displays page name doubles as a synonym, so the words
                // of both surfaces land here.
                keywords: FeatureStrings.brightness(language).pageTitle,
                icon: .symbol("sun.max"),
                trouble: enabled ? nil
                    : .needsSetup(featureTitle: FeatureStrings.brightness(language).pageTitle,
                                  page: .energy),
                numericRange: enabled ? 0...100 : nil,
                run: { value in
                    guard let value else { return }
                    applyBrightness(percent: value)
                }))
        }

        if AppFeature.mixer.isAvailable {
            entries.append(CommandBarEntry(
            id: "action.volume",
            title: bar.volumeTitle,
            subtitle: String(format: bar.argumentRangeFormat, 0, 100),
            icon: .symbol("speaker.wave.2"),
            numericRange: 0...100,
            run: { value in
                guard let value else { return }
                let applied = AppVolumeMixer.setSystemOutputVolume(Double(value) / 100)
                if applied {
                    QuickToolHUD.show(icon: "speaker.wave.2",
                                      message: "\(FeatureStrings.commandBar(L10n.shared.language).volumeTitle) \(value)%")
                } else {
                    NSSound.beep()
                }
            }))
        }

        if AppFeature.mixer.isAvailable, let muted = AppVolumeMixer.systemOutputIsMuted() {
            entries.append(CommandBarEntry(
                id: "action.soundMute",
                title: muted ? bar.soundUnmute : bar.soundMute,
                subtitle: bar.volumeTitle,
                icon: .symbol(muted ? "speaker.slash.fill" : "speaker.wave.2"),
                isActive: muted,
                run: { _ in
                    if !AppVolumeMixer.setSystemOutputMuted(!muted) { NSSound.beep() }
                }))
        }

        if AppFeature.soundOutputSwitcher.isAvailable, AppFeature.mixer.isAvailable {
            let devices = AppVolumeMixer.shared.outputDevices.filter(\.canBeDefaultOutput)
            for device in devices {
                entries.append(CommandBarEntry(
                    id: "action.soundOutput.\(device.uid)",
                    title: device.name,
                    subtitle: device.isDefault ? bar.soundOutputCurrent : bar.soundOutputSubtitle,
                    keywords: bar.soundOutputSubtitle,
                    icon: .symbol(device.isHeadphones ? "headphones" : "hifispeaker"),
                    isActive: device.isDefault,
                    run: { _ in AppVolumeMixer.shared.setUniversalOutputDeviceUID(device.uid) }))
            }
        }

        if AppFeature.quickToggles.isAvailable {
            let toggles = QuickTogglesService.shared
            let togglesText = FeatureStrings.quickToggles(language)
            let togglesArea = area(.quickToggles)
            let isDark = toggles.systemAppearanceIsDark ?? false
            entries.append(CommandBarEntry(
                id: "action.darkMode",
                title: isDark ? togglesText.darkModeToLight : togglesText.darkModeToDark,
                subtitle: togglesArea,
                icon: .symbol(isDark ? "sun.max.fill" : "moon.fill"),
                run: { _ in QuickTogglesService.shared.toggleDarkMode() }))
            entries.append(CommandBarEntry(
                id: "action.lockScreen",
                title: togglesText.lockScreenTitle,
                subtitle: togglesArea,
                icon: .symbol("lock.fill"),
                run: { _ in afterBeat { QuickTogglesService.shared.lockScreen() } }))
            entries.append(CommandBarEntry(
                id: "action.displayOff",
                title: togglesText.displayOffTitle,
                subtitle: togglesArea,
                icon: .symbol("display"),
                run: { _ in afterBeat { QuickTogglesService.shared.turnDisplayOff() } }))
            entries.append(CommandBarEntry(
                id: "action.screenSaver",
                title: togglesText.screenSaverTitle,
                subtitle: togglesArea,
                icon: .symbol("sparkles.tv"),
                run: { _ in afterBeat { QuickTogglesService.shared.startScreenSaver() } }))
            entries.append(CommandBarEntry(
                id: "action.ejectDisks",
                title: togglesText.ejectTitle,
                subtitle: togglesArea,
                icon: .symbol("eject.fill"),
                run: { _ in QuickTogglesService.shared.ejectAllDisks() }))
            entries.append(CommandBarEntry(
                id: "action.hiddenFiles",
                title: toggles.hiddenFilesShown ? togglesText.hiddenFilesHide : togglesText.hiddenFilesShow,
                subtitle: togglesArea,
                icon: .symbol(toggles.hiddenFilesShown ? "eye.slash" : "eye"),
                run: { _ in QuickTogglesService.shared.toggleHiddenFiles() }))
            entries.append(CommandBarEntry(
                id: "action.desktopIcons",
                title: toggles.desktopIconsShown ? togglesText.desktopIconsHide : togglesText.desktopIconsShow,
                subtitle: togglesArea,
                icon: .symbol("desktopcomputer"),
                run: { _ in QuickTogglesService.shared.toggleDesktopIcons() }))
            entries.append(CommandBarEntry(
                id: "action.emptyTrash",
                title: togglesText.emptyTrashTitle,
                subtitle: togglesArea,
                icon: .symbol("trash"),
                trouble: automationDenied ? .needsPermission : nil,
                confirmationPrompt: togglesText.emptyTrashConfirmTitle,
                run: { _ in QuickTogglesService.shared.emptyTrashConfirmed() }))
        }

        if AppFeature.urlCleaner.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.cleanURL",
                title: bar.actionCleanURL,
                subtitle: area(.urlCleaner),
                keywords: s.urlCleanerName,
                icon: .symbol("link"),
                run: { _ in cleanClipboardURL() }))
        }

        if AppFeature.windowLayout.isAvailable {
            let layoutText = FeatureStrings.windowLayout(language)
            let layoutArea = area(.windowLayout)
            let axTrouble = accessibilityTrouble()
            for action in WindowLayoutAction.allCases {
                // The two ways of taking the whole screen answer to each
                // other's names: someone typing "full screen" means either.
                var keywords = layoutText.title
                if action == .maximize { keywords += " " + layoutText.fullScreen }
                if action == .fullScreen { keywords += " " + layoutText.maximize }
                entries.append(CommandBarEntry(
                    id: "action.layout.\(action.rawValue)",
                    title: action.title(layoutText),
                    subtitle: layoutArea,
                    keywords: keywords,
                    icon: .symbol(action.symbolName),
                    shortcut: action.savedShortcut,
                    trouble: axTrouble,
                    run: { _ in
                        afterBeat {
                            if case .failure = WindowLayoutService.shared.apply(action) {
                                NSSound.beep()
                            }
                        }
                    }))
            }
        }

        if AppFeature.appUpdates.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.appUpdates",
                title: bar.actionCheckAppUpdates,
                subtitle: area(.appUpdates),
                keywords: FeatureStrings.appUpdates(language).pageTitle,
                icon: .symbol("arrow.down.app"),
                run: { _ in
                    AppUpdatesService.shared.check()
                    openSettings(at: .appUpdates)
                }))
        }
        if AppFeature.cleaner.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.cleaner",
                title: s.cleanerName,
                subtitle: area(.cleaner, under: s.cleanerName),
                icon: .symbol("sparkle"),
                run: { _ in openSettings(at: .cleaner) }))
        }
        if AppFeature.uninstaller.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.uninstaller",
                title: s.uninstallerName,
                subtitle: area(.uninstaller, under: s.uninstallerName),
                icon: .symbol("trash"),
                run: { _ in openSettings(at: .uninstaller) }))
        }
        if AppFeature.quickLauncher.isAvailable {
            entries.append(CommandBarEntry(
                id: "action.quickLauncher",
                title: s.launcherName,
                subtitle: area(.quickLauncher, under: s.launcherName),
                icon: .symbol("square.grid.3x3"),
                shortcut: roleShortcut(.quickLauncher),
                run: { _ in afterBeat { QuickLauncherService.shared.show() } }))
        }
        entries.append(CommandBarEntry(
            id: CommandBarPreferences.emojiBrowserRowID,
            title: bar.sourceEmoji,
            subtitle: bar.pageTitle,
            keywords: bar.kindEmoji,
            icon: .symbol("face.smiling"),
            keepsBarOpen: true,
            run: { _ in CommandBarService.shared.setCategory(.emoji) }))
        if AppFeature.killProcess.isAvailable,
           UserDefaults.standard.bool(forKey: DefaultsKey.killProcessCommandBarEnabled) {
            let killStrings = FeatureStrings.killProcess(language)
            entries.append(CommandBarEntry(
                id: CommandBarPreferences.killProcessBrowserRowID,
                title: killStrings.pageTitle,
                subtitle: killStrings.browseSubtitle,
                icon: .symbol("xmark.octagon"),
                keepsBarOpen: true,
                run: { _ in
                    CommandBarService.shared.setCategory(.killProcess)
                    CommandBarService.shared.query = ""
                }))
        }
        let feedback = FeatureStrings.feedback(language)
        entries.append(CommandBarEntry(
            id: "action.feedback.bug",
            title: feedback.commandBug,
            subtitle: feedback.commandSubtitle,
            icon: .symbol("ladybug"),
            run: { _ in afterBeat { appDelegate()?.openFeedbackWindow(kind: .bug) } }))
        entries.append(CommandBarEntry(
            id: "action.feedback.feature",
            title: feedback.commandFeature,
            subtitle: feedback.commandSubtitle,
            icon: .symbol("lightbulb"),
            run: { _ in afterBeat { appDelegate()?.openFeedbackWindow(kind: .feature) } }))
        // What people try on day one: put the Mac to sleep, restart it, turn
        // Wi-Fi off. Everything but sleep confirms on the row first.
        for action in CommandBarExtras.PowerAction.allCases {
            let title: String
            let confirmation: String?
            switch action {
            case .sleep: title = bar.powerSleep; confirmation = nil
            case .restart: title = bar.powerRestart; confirmation = bar.powerRestartConfirm
            case .shutDown: title = bar.powerShutDown; confirmation = bar.powerShutDownConfirm
            case .logOut: title = bar.powerLogOut; confirmation = bar.powerLogOutConfirm
            }
            entries.append(CommandBarEntry(
                id: "action.power.\(action.rawValue)",
                title: title,
                subtitle: s.tabGeneral,
                icon: .symbol(action.symbolName),
                confirmationPrompt: confirmation,
                run: { _ in CommandBarExtras.run(action) }))
        }

        if let wifiOn = CommandBarExtras.cachedWiFiPower {
            entries.append(CommandBarEntry(
                id: "action.wifi",
                title: wifiOn ? bar.wifiOff : bar.wifiOn,
                subtitle: s.tabGeneral,
                keywords: "wifi wi-fi",
                icon: .symbol(wifiOn ? "wifi.slash" : "wifi"),
                isActive: wifiOn,
                run: { _ in
                    if !CommandBarExtras.setWiFiPower(!wifiOn) { NSSound.beep() }
                }))
        }

        // The folders every Mac has. A fixed set of destinations, never a
        // search through anyone's files.
        for folder in CommandBarExtras.standardFolders() {
            entries.append(CommandBarEntry(
                id: "folder.\(folder.url.path)",
                title: folder.name,
                subtitle: bar.kindFolder,
                keywords: bar.kindFolder,
                icon: .filePath(folder.url.path),
                countsUsage: true,
                revealPath: folder.url.path,
                run: { _ in NSWorkspace.shared.open(folder.url) }))
        }

        entries.append(contentsOf: dateAnswerEntries(bar: bar))

        entries.append(CommandBarEntry(
            id: "action.openSettings",
            title: bar.actionOpenSettings,
            subtitle: s.settingsTitle,
            icon: .symbol("gearshape"),
            run: { _ in openSettings(at: .general) }))
        return entries
    }

    // MARK: - Settings pages

    /// Pages an action row already opens; listing them again would put two
    /// rows in the list that lead to the same place.
    private static let pagesCoveredByActions: Set<SettingsPage> = [
        .general, .cleaner, .uninstaller, .appUpdates,
    ]

    private static func settingsEntries(_ s: Strings,
                                        language: AppLanguage,
                                        bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        SettingsDirectory.sections(s, language: language)
            .flatMap(\.items)
            .filter { item in
                !pagesCoveredByActions.contains(item.page)
                    && FeatureVisibilitySupport.isPageVisible(item.page) { $0.isAvailable }
            }
            .map { item in
                CommandBarEntry(
                    id: "settings.\(item.page)",
                    title: item.title,
                    subtitle: s.settingsTitle,
                    keywords: item.keywords.joined(separator: " "),
                    icon: .symbol(item.icon),
                    run: { _ in openSettings(at: item.page) })
            }
    }

    // MARK: - Files

    /// One row per file Spotlight found in the folders the person named.
    ///
    /// A found file is a passing thing, like something copied: it is not
    /// pinned, named or learned from, because the row exists for exactly as
    /// long as the words that found it. What it does keep is where it lives,
    /// so ⌘Return shows it in Finder.
    static func fileEntries(_ paths: [String],
                            bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        let home = NSHomeDirectory()
        return paths.map { path in
            let url = URL(fileURLWithPath: path)
            let folder = CommandBarFileSearchSupport.abbreviating(
                url.deletingLastPathComponent().path, homeDirectory: home)
            return CommandBarEntry(
                id: "file.\(path)",
                title: url.lastPathComponent,
                subtitle: folder,
                keywords: bar.sourceFiles,
                icon: .filePath(path),
                countsUsage: false,
                revealPath: path,
                run: { _ in
                    guard FileManager.default.fileExists(atPath: path) else {
                        QuickToolHUD.show(icon: "doc.questionmark", message: url.lastPathComponent)
                        return
                    }
                    NSWorkspace.shared.open(url)
                })
        }
    }

    // MARK: - The Mac's own Settings panes

    /// One row per pane System Settings shows, opened by the address macOS
    /// gives it. The names come from macOS and are the ones it shows itself;
    /// the words underneath them are translated, so the pane answers in the
    /// language the person is typing even where its name does not.
    static func macSettingsEntries(_ panes: [CommandBarSystemSettings.Pane],
                                   bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        panes.map { pane in
            CommandBarEntry(
                id: "macsettings.\(pane.bundleID)",
                title: pane.name,
                subtitle: bar.sourceMacSettings,
                keywords: pane.keywords,
                icon: .symbol("gearshape.2"),
                run: { _ in
                    guard let url = CommandBarSystemSettings.url(for: pane.bundleID) else {
                        NSSound.beep()
                        return
                    }
                    NSWorkspace.shared.open(url)
                })
        }
    }

    // MARK: - Snippets

    private static func snippetEntries(_ bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        guard AppFeature.textSnippets.isAvailable,
              let data = UserDefaults.standard.data(forKey: DefaultsKey.textSnippets)
        else { return [] }
        return TextSnippetSupport.decode(data)
            .filter { $0.enabled && !$0.name.isEmpty }
            .map { snippet in
                CommandBarEntry(
                    id: "snippet.\(snippet.id.uuidString)",
                    title: snippet.name,
                    subtitle: bar.kindSnippet,
                    keywords: snippet.trigger + " " + snippet.folder,
                    icon: .symbol("text.append"),
                    trouble: Permissions.shared.accessibility ? nil : .needsPermission,
                    run: { _ in
                        SnippetLibraryService.shared.insert(snippet)
                    })
            }
    }

    // MARK: - Installed apps

    /// Every installed app as one row. A running app keeps the same row (it
    /// activates instead of launching, which is what the person wants either
    /// way) and wears the live dot.
    static func appEntries(_ apps: [InstalledApps.InstalledApp],
                           runningBundleIDs: Set<String>,
                           runningPaths: Set<String>,
                           bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        // Offering ourselves is a dead end: activating a menu bar app shows
        // nothing, so the row would look broken.
        let ownBundleID = Bundle.main.bundleIdentifier
        return apps.filter { $0.bundleID != ownBundleID }.map { app in
            let isRunning = app.bundleID.map { runningBundleIDs.contains($0) } ?? false
                || runningPaths.contains(app.url.standardizedFileURL.path)
            // The title may be localized while the bundle keeps the name the
            // person learned, and an ideographic title may be easier to type
            // by sound.
            let diskName = app.url.deletingPathExtension().lastPathComponent
            let keywords = CommandBarSearch.applicationKeywords(
                title: app.name, diskName: diskName, alternateNames: app.alternateNames)
            return CommandBarEntry(
                id: "app.\(app.id)",
                // Two copies of one app need two rows, so the row is keyed by
                // where it lives; what the person named stays with the app.
                stableKey: app.bundleID.map { "app.bundle.\($0)" } ?? "app.\(app.id)",
                title: app.name,
                subtitle: bar.kindApp,
                keywords: keywords,
                icon: .appIcon(path: app.url.path),
                isActive: isRunning,
                revealPath: app.url.path,
                run: { _ in
                    NSWorkspace.shared.openApplication(at: app.url,
                                                       configuration: NSWorkspace.OpenConfiguration()) { _, error in
                        if error != nil { DispatchQueue.main.async { NSSound.beep() } }
                    }
                })
        }
    }

    // MARK: - Running apps and their windows

    /// Menu commands of the app in front, each one runnable and each one
    /// showing its own shortcut. This is how the bar reaches past Vorssaint
    /// without searching files or the internet.
    static func menuEntries(_ items: [CommandBarMenuItem],
                            appName: String,
                            bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        // A list of recently closed things holds the same words over and over,
        // one row per window. Five rows nobody can tell apart are worse than
        // one, and they crowd out everything else, so the first of each name
        // is the one offered.
        var seen = Set<String>()
        return items.enumerated().compactMap { index, item in
            let path = item.path.joined(separator: " › ")
            guard seen.insert(path + "\u{1}" + item.title).inserted else { return nil }
            return CommandBarEntry(
                id: "menu.\(index).\(item.title)",
                title: item.title,
                subtitle: path.isEmpty ? appName : "\(appName) › \(path)",
                keywords: bar.kindMenu + " " + appName + " " + path,
                icon: .symbol("filemenu.and.selection"),
                menuShortcut: item.shortcut,
                // What a menu does belongs to its app, not to this Mac: a
                // count of runs would mean nothing the next time around.
                countsUsage: false,
                run: { _ in
                    if !CommandBarMenus.press(item) { NSSound.beep() }
                })
        }
    }

    /// One "quit" row per running app. Quitting is graceful, so an app with
    /// unsaved work still gets to ask; the bar confirms first all the same.
    static func quitEntries(_ apps: [NSRunningApplication],
                            bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        // Two copies of one app run under one bundle id, and two rows sharing
        // an id is undefined behaviour in a SwiftUI list. The first one wins.
        var seen = Set<String>()
        return apps.compactMap { app in
            guard let name = app.localizedName, !name.isEmpty,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
            let pid = app.processIdentifier
            guard seen.insert(app.bundleIdentifier ?? String(pid)).inserted else { return nil }
            return CommandBarEntry(
                id: "quit.\(app.bundleIdentifier ?? String(pid))",
                title: String(format: bar.quitFormat, name),
                subtitle: bar.kindApp,
                keywords: name,
                icon: app.bundleURL.map { .appIcon(path: $0.path) } ?? .symbol("xmark.circle"),
                confirmationPrompt: String(format: bar.quitConfirmFormat, name),
                run: { _ in
                    guard let running = NSRunningApplication(processIdentifier: pid),
                          !running.isTerminated else {
                        NSSound.beep()
                        return
                    }
                    // An app with unsaved work answers a quit with a dialog.
                    // Bringing it forward first means that dialog is seen
                    // instead of waiting invisibly behind everything.
                    running.activate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        running.terminate()
                    }
                })
        }
    }

    /// One row per running process, so typing its name finds and can kill it
    /// directly. Force Kill, Kill All and Kill Process Tree live in the row's
    /// Actions panel, the same place Force Quit and Restart live for apps.
    static func killProcessEntries(_ processes: [KillProcessEntry],
                                   killStrings: KillProcessFeatureStrings) -> [CommandBarEntry] {
        processes.filter { !$0.isProtected }.map { process in
            CommandBarEntry(
                id: "kill.\(process.pid)",
                title: process.name,
                subtitle: String(format: killStrings.pidLabelFormat, process.pid),
                keywords: process.path,
                icon: process.bundleURL.map { .appIcon(path: $0.path) } ?? .symbol("xmark.octagon"),
                confirmationPrompt: String(format: killStrings.confirmKillFormat, process.name),
                run: { _ in
                    KillProcessService.shared.kill(process, force: false)
                })
        }
    }

    /// One row per open window, so a person with six windows of the same app
    /// can name the one they want. Titles come from the window server, which
    /// only fills them in with Screen Recording granted; without it there is
    /// nothing honest to show and the caller skips this entirely.
    static func windowEntries(_ windows: [SwitcherItem],
                              bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        windows.compactMap { window in
            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            // A window whose only name is its app repeats the app row.
            guard !title.isEmpty,
                  title.caseInsensitiveCompare(window.appName) != .orderedSame else { return nil }
            let pid = window.pid
            let windowID = window.windowID
            let appName = window.appName
            return CommandBarEntry(
                id: "window.\(window.id)",
                title: title,
                subtitle: appName.isEmpty ? bar.kindWindow : appName,
                keywords: bar.kindWindow + " " + appName,
                icon: NSRunningApplication(processIdentifier: pid)?.bundleURL
                    .map { .appIcon(path: $0.path) } ?? .symbol("macwindow"),
                run: { _ in
                    afterBeat(0.1) {
                        WindowActivator.activate(pid: pid, windowID: windowID, appName: appName)
                    }
                })
        }
    }

    // MARK: - Answers about this Mac

    /// Facts the Mac can answer instantly, read on demand with public calls
    /// and no permission: nothing here polls or stays alive.
    static func systemAnswerEntries(_ s: Strings,
                                    bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        var entries: [CommandBarEntry] = []

        if let battery = SystemInfo.batterySnapshot() {
            let value = "\(battery.percent)%"
            let detail = battery.isCharging
                ? bar.answerBatteryCharging
                : (battery.isOnBattery ? bar.answerBatteryLabel : bar.answerBatteryPlugged)
            entries.append(CommandBarEntry(
                id: "answer.battery",
                title: bar.answerBatteryLabel,
                subtitle: detail,
                icon: .symbol(battery.isCharging ? "battery.100.bolt" : "battery.75"),
                answerValue: value,
                countsUsage: false,
                run: { _ in copyAnswer(value) }))
        }

        if AppFeature.monitorMemory.isAvailable,
           let memory = SystemInfo.memoryUsage(), memory.total > 0 {
            let metric = Defaults.sanitizedMonitorMemoryMetric(
                UserDefaults.standard.string(forKey: DefaultsKey.monitorMemoryMetric) ?? "")
            let selected = MetricFormat.selectedMemory(used: memory.used,
                                                       app: memory.appUsed,
                                                       metric: metric)
            let used = MetricFormat.bytes(min(selected, memory.total))
            let total = MetricFormat.bytes(memory.total)
            let percent = Int((Double(selected) / Double(memory.total) * 100).rounded())
            entries.append(CommandBarEntry(
                id: "answer.memory",
                title: metric == "app" ? s.memoryMetricApp : bar.answerMemoryLabel,
                subtitle: String(format: bar.answerMemoryFormat, used, total),
                icon: .symbol("memorychip"),
                answerValue: "\(percent)%",
                countsUsage: false,
                run: { _ in copyAnswer("\(used) / \(total)") }))
        }

        if let storage = cachedBootVolumeSpace {
            let free = MetricFormat.diskBytes(storage.free)
            let total = MetricFormat.diskBytes(storage.total)
            // The chip carries the headline, the caption the detail: repeating
            // the same number twice on one row reads as a mistake.
            let freePercent = Int((Double(storage.free) / Double(storage.total) * 100).rounded())
            entries.append(CommandBarEntry(
                id: "answer.storage",
                title: bar.answerStorageLabel,
                subtitle: String(format: bar.answerStorageFormat, free, total),
                icon: .symbol("internaldrive"),
                answerValue: "\(freePercent)%",
                countsUsage: false,
                run: { _ in copyAnswer(free) }))
        }
        return entries
    }

    /// Today's date and the time right now, written the way this Mac writes
    /// them, ready to be copied.
    private static func dateAnswerEntries(bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        let now = Date()
        let longDate = DateFormatter()
        longDate.dateStyle = .full
        longDate.timeStyle = .none
        let shortDate = DateFormatter()
        shortDate.dateStyle = .short
        shortDate.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .medium
        let dateText = shortDate.string(from: now)
        let timeText = timeFormatter.string(from: now)
        return [
            CommandBarEntry(
                id: "answer.date",
                title: bar.answerDateLabel,
                subtitle: longDate.string(from: now),
                icon: .symbol("calendar"),
                answerValue: dateText,
                countsUsage: false,
                run: { _ in copyAnswer(dateText) }),
            CommandBarEntry(
                id: "answer.time",
                title: bar.answerTimeLabel,
                subtitle: timeText,
                icon: .symbol("clock"),
                answerValue: timeText,
                countsUsage: false,
                run: { _ in copyAnswer(timeText) }),
        ]
    }

    /// Filled in by the service from a background pass; nil until the first
    /// one lands, which simply means the row is not offered yet.
    static var cachedBootVolumeSpace: (free: UInt64, total: UInt64)?

    static func readBootVolumeSpace() -> (free: UInt64, total: UInt64)? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
        ]) else { return nil }
        let free = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
            ?? values.volumeAvailableCapacity.map { UInt64(max(0, $0)) }
        guard let free, let total = values.volumeTotalCapacity, total > 0 else { return nil }
        return (free, UInt64(total))
    }

    private static func copyAnswer(_ value: String) {
        GeneralPasteboardAccess.shared.sync {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
        QuickToolHUD.show(icon: "doc.on.doc", message: value)
    }

    // MARK: - Emoji

    /// Emoji rows, which type themselves at the caret the way a snippet does.
    /// Built once and reused: the names come from Unicode and never change.
    static func emojiEntries(bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        CommandBarEmoji.emoji.map { emoji in
            CommandBarEntry(
                id: "emoji.\(emoji.character)",
                title: emoji.character + "  " + emoji.name,
                subtitle: bar.kindEmoji,
                keywords: emoji.name + " " + bar.kindEmoji,
                icon: .symbol("face.smiling"),
                trouble: Permissions.shared.accessibility ? nil : .needsPermission,
                matchTitle: emoji.name,
                run: { _ in typeAtCursor(emoji.character) })
        }
    }

    /// Types text into whatever has the caret, through the routine the
    /// snippets already use, after the keyboard comes clean of modifiers.
    static func typeAtCursor(_ text: String) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                != ProcessInfo.processInfo.processIdentifier else {
            NSSound.beep()
            return
        }
        guard AXIsProcessTrusted() else {
            Permissions.shared.requestAccessibility()
            return
        }
        CommandBarTyping.post(text: text, attempt: 0)
    }

    // MARK: - The places the person saved

    /// Rows for the links, folders and searches the person saved themselves.
    /// A saved search reads whatever was typed after its name at the moment it
    /// runs, so one row serves both "gh" and "gh vorssaint".
    static func linkEntries(_ links: [CommandBarLink],
                            bar: CommandBarFeatureStrings) -> [CommandBarEntry] {
        links.map { link in
            CommandBarEntry(
                id: "link.\(link.id.uuidString)",
                title: link.name,
                subtitle: link.kind == .script
                    ? bar.scriptSearchHint
                    : (link.takesArgument ? bar.linkSearchHint : bar.kindLink),
                keywords: bar.kindLink,
                icon: .symbol(link.kind.symbolName),
                // A saved search, or a script, may still need to be told what
                // to look for, and it cannot ask from behind a closed panel.
                keepsBarOpen: link.takesArgument,
                // Only a search or a script reads the words that follow its
                // name; a plain site or folder opens the same either way.
                takesArgument: link.takesArgument,
                revealPath: CommandBarLinks.revealPath(for: link),
                run: { _ in
                    if link.kind == .script {
                        runScript(link)
                    } else {
                        open(link)
                    }
                })
        }
    }

    private static func open(_ link: CommandBarLink) {
        let service = CommandBarService.shared
        // What was typed and what was selected are read from the moment the
        // row ran: closing the bar wipes both, and a saved search lives on
        // exactly the words that were typed after its name.
        let typed = service.queryWhenRun.trimmingCharacters(in: .whitespaces)
        let argument = CommandBarLinks.trailingArgument(query: typed, name: link.name) ?? ""
        // A saved search with nothing to search for puts its own name in the
        // field instead of opening an empty result page. The bar was kept open
        // for this, so there is a field to put it in.
        if link.takesQuery, argument.isEmpty {
            service.prefill(link.name + " ")
            return
        }
        // Everything below opens something, so the bar is done. A row that
        // takes a query is still on screen; one that does not was already
        // hidden, and hiding twice costs nothing.
        defer { service.hide() }
        let date = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        let copied = GeneralPasteboardAccess.shared.sync {
            NSPasteboard.general.string(forType: .string)
        } ?? ""
        let expanded = CommandBarLinks.expand(link.destination,
                                              kind: link.kind,
                                              query: argument,
                                              clipboard: copied,
                                              selection: service.selectionWhenRun,
                                              date: date)
        guard let url = CommandBarLinks.url(for: link, expanded: expanded) else {
            NSSound.beep()
            return
        }
        if link.kind == .place, !FileManager.default.fileExists(atPath: url.path) {
            QuickToolHUD.show(icon: "folder.badge.questionmark", message: link.name)
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Return pressed before a script's debounced run has answered yet: runs
    /// at once instead of waiting, and leaves the bar open the way a search
    /// does, since there is nothing to copy until the row shows an answer.
    private static func runScript(_ link: CommandBarLink) {
        let service = CommandBarService.shared
        let typed = service.queryWhenRun.trimmingCharacters(in: .whitespaces)
        let argument = CommandBarLinks.trailingArgument(query: typed, name: link.name) ?? ""
        if argument.isEmpty {
            service.prefill(link.name + " ")
            return
        }
        if let cached = service.scriptRunner.cachedResult(linkID: link.id, argument: argument) {
            copyAnswer(cached.text)
            service.hide()
            return
        }
        service.scriptRunner.runNow(link: link, argument: argument)
    }

    /// The row a saved script shows once it has answered: the same shape as
    /// the calculator's own answer, so Return copies it the same way.
    static func scriptAnswerEntry(link: CommandBarLink,
                                  result: CommandBarScriptRunner.Result,
                                  bar: CommandBarFeatureStrings) -> CommandBarEntry {
        CommandBarEntry(
            id: "link.\(link.id.uuidString)",
            title: result.text,
            subtitle: bar.copyHint,
            icon: .symbol(link.kind.symbolName),
            isAnswer: true,
            countsUsage: false,
            run: { _ in copyAnswer(result.text) })
    }

    // MARK: - What is selected right now

    /// Rows that act on the text the person had selected when the bar opened.
    /// This is the bar meeting them where they already are: the alternative is
    /// copying, opening something, pasting, fixing it and coming back.
    ///
    /// Everything here is offered only when it would actually do something —
    /// a link row only for a link, a case row only when the case would change.
    static func selectionEntries(_ text: String,
                                 bar: CommandBarFeatureStrings,
                                 useInSearch: @escaping (String) -> Void) -> [CommandBarEntry] {
        guard !text.isEmpty else { return [] }
        let kind = bar.kindSelection
        var entries: [CommandBarEntry] = []

        entries.append(CommandBarEntry(
            id: "selection.copy",
            title: bar.selectionCopy,
            subtitle: kind,
            icon: .symbol("doc.on.doc"),
            run: { _ in copyAnswer(text) }))

        entries.append(CommandBarEntry(
            id: "selection.search",
            title: bar.selectionSearch,
            subtitle: kind,
            icon: .symbol("magnifyingglass"),
            // The bar stays open for this one: the whole point is to convert,
            // add up or look the selection up without retyping it.
            countsUsage: false,
            keepsBarOpen: true,
            run: { _ in useInSearch(text) }))

        if AppFeature.urlCleaner.isAvailable,
           let cleaned = URLCleanerService.shared.clean(text), cleaned != text {
            entries.append(CommandBarEntry(
                id: "selection.cleanLink",
                title: bar.actionCleanURL,
                subtitle: kind,
                keywords: L10n.shared.s.urlCleanerName,
                icon: .symbol("link"),
                run: { _ in
                    URLCleanerService.shared.copy(cleaned)
                    QuickToolHUD.show(icon: "link", message: L10n.shared.s.urlCleanerCleaned)
                }))
        }

        // Retyping a whole document would be slower than doing it by hand, and
        // the case rows only earn their place when the case would change.
        if text.count <= 5_000 {
            let cases: [(String, String, String, (String) -> String)] = [
                ("selection.upper", bar.selectionUpper, "textformat.size.larger",
                 { $0.localizedUppercase }),
                ("selection.lower", bar.selectionLower, "textformat.size.smaller",
                 { $0.localizedLowercase }),
                ("selection.titleCase", bar.selectionTitleCase, "textformat",
                 { $0.localizedCapitalized }),
            ]
            for (id, title, symbol, transform) in cases
            where CommandBarText.changesCase(text, to: transform) {
                entries.append(CommandBarEntry(
                    id: id,
                    title: title,
                    subtitle: kind,
                    icon: .symbol(symbol),
                    trouble: Permissions.shared.accessibility ? nil : .needsPermission,
                    run: { _ in typeAtCursor(transform(text)) }))
            }
        }

        if AppFeature.shelf.isAvailable,
           UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) {
            entries.append(CommandBarEntry(
                id: "selection.shelf",
                title: bar.selectionShelf,
                subtitle: kind,
                keywords: L10n.shared.s.shelfName,
                icon: .symbol("tray.full"),
                run: { _ in keepOnShelf(text) }))
        }

        let words = CommandBarText.wordCount(text)
        let characters = CommandBarText.characterCount(text)
        let count = String(format: bar.selectionCountFormat, words, characters)
        entries.append(CommandBarEntry(
            id: "selection.count",
            title: bar.selectionCount,
            subtitle: count,
            icon: .symbol("number"),
            answerValue: "\(characters)",
            countsUsage: false,
            run: { _ in copyAnswer(count) }))
        return entries
    }

    /// Puts the selection on the shelf without disturbing what the person has
    /// copied: a pasteboard of our own carries it across.
    private static func keepOnShelf(_ text: String) {
        let board = NSPasteboard(name: NSPasteboard.Name("com.vorssaint.commandbar.selection"))
        board.clearContents()
        board.setString(text, forType: .string)
        guard ShelfService.shared.accept(pasteboard: board) else {
            NSSound.beep()
            return
        }
        QuickToolHUD.show(icon: "tray.full", message: L10n.shared.s.shelfName)
    }

    // MARK: - The calculator answer

    /// The pinned first row when what was typed is a sum or a conversion.
    /// Enter copies it.
    static func answerEntry(for query: String, bar: CommandBarFeatureStrings) -> CommandBarEntry? {
        if let result = CommandBarMath.evaluate(query) {
            return CommandBarEntry(
                id: "math.result",
                title: result.formatted,
                subtitle: bar.copyHint,
                icon: .symbol("equal.square"),
                isAnswer: true,
                countsUsage: false,
                run: { _ in copyAnswer(result.formatted) })
        }
        if let converted = CommandBarUnits.convert(query) {
            return CommandBarEntry(
                id: "units.result",
                title: converted.formatted,
                subtitle: bar.copyHint,
                icon: .symbol("arrow.left.arrow.right"),
                isAnswer: true,
                countsUsage: false,
                run: { _ in copyAnswer(converted.formatted) })
        }
        // Dates last: a sum and a conversion are stricter, and "3" alone must
        // never become a date.
        if let dated = CommandBarDates.evaluate(query) {
            return CommandBarEntry(
                id: "date.result",
                title: dated.formatted,
                subtitle: dated.detail,
                icon: .symbol("calendar"),
                isAnswer: true,
                countsUsage: false,
                run: { _ in copyAnswer(dated.formatted) })
        }
        return nil
    }

    /// A row that opens what was typed as a web address, offered only when the
    /// text reads like one. It leads the list the way the calculator answer
    /// does, so Return opens it at once.
    static func openURLEntry(for query: String, bar: CommandBarFeatureStrings) -> CommandBarEntry? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = CommandBarLinks.typedURL(trimmed) else { return nil }
        return CommandBarEntry(
            id: "action.openURL",
            title: trimmed,
            subtitle: bar.openInBrowser,
            icon: .symbol("globe"),
            countsUsage: false,
            run: { _ in NSWorkspace.shared.open(url) })
    }

    // MARK: - Clipboard history

    /// Rows for history items matching the query, capped so pasted text never
    /// crowds out actions. Never offered on an empty query and never counted
    /// as usage; the items come and go with the clipboard.
    static func clipboardEntries(matching query: String,
                                 bar: CommandBarFeatureStrings,
                                 limit: Int = 4,
                                 paste: @escaping (ClipboardHistoryEntry) -> Void) -> [CommandBarEntry] {
        guard AppFeature.clipboardHistory.isAvailable,
              !query.isEmpty else { return [] }
        let history = ClipboardHistoryService.shared
        guard CommandBarClipboardAccess.canUseHistory(
            captureEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled),
            hasSavedItems: !history.entries.isEmpty) else { return [] }
        let imageLabel = FeatureStrings.clipboard(L10n.shared.language).imageEntryLabel
        return history.filteredEntries(matching: query)
            .prefix(limit)
            .map { clipboardRow($0, imageLabel: imageLabel, bar: bar, paste: paste) }
    }

    private static func clipboardRow(_ entry: ClipboardHistoryEntry,
                                     imageLabel: String,
                                     bar: CommandBarFeatureStrings,
                                     paste: @escaping (ClipboardHistoryEntry) -> Void)
        -> CommandBarEntry {
        let icon: CommandBarEntry.Icon
        switch entry.kind {
        case .text: icon = .symbol("doc.on.clipboard")
        case .image: icon = entry.imageFile.map { .clipboardImage(name: $0) } ?? .symbol("photo")
        case .files: icon = entry.filePaths.first.map { .filePath($0) } ?? .symbol("folder")
        }
        return CommandBarEntry(
            id: "clipboard.\(entry.id.uuidString)",
            title: entry.kind == .image
                ? entry.searchableText(imageLabel: imageLabel)
                : entry.preview,
            subtitle: bar.kindClipboard,
            icon: icon,
            trouble: Permissions.shared.accessibility ? nil : .needsPermission,
            countsUsage: false,
            run: { _ in paste(entry) })
    }

    /// The last few things copied, for the browse list at the bottom of the
    /// empty bar. It sits last on purpose: it is there to be found by someone
    /// scrolling through what the bar can do, not put on screen over whatever
    /// they were doing every single time the bar opens.
    static func clipboardBrowseEntries(limit: Int,
                                       bar: CommandBarFeatureStrings,
                                       paste: @escaping (ClipboardHistoryEntry) -> Void)
        -> [CommandBarEntry] {
        guard AppFeature.clipboardHistory.isAvailable else { return [] }
        let history = ClipboardHistoryService.shared
        guard CommandBarClipboardAccess.canUseHistory(
            captureEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled),
            hasSavedItems: !history.entries.isEmpty) else { return [] }
        let imageLabel = FeatureStrings.clipboard(L10n.shared.language).imageEntryLabel
        return history.entries.prefix(limit).map { entry in
            clipboardRow(entry, imageLabel: imageLabel, bar: bar, paste: paste)
        }
    }

    // MARK: - Shared helpers

    /// The pause every surface gives a non-activating panel to leave the
    /// screen before the action captures, presents or resolves focus.
    private static func afterBeat(_ delay: TimeInterval = 0.15, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func openSettings(at page: SettingsPage) {
        SettingsRouter.shared.page = page
        appDelegate()?.openSettingsWindow()
    }

    private static func cleanClipboardURL() {
        let s = L10n.shared.s
        guard let raw = NSPasteboard.general.string(forType: .string),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            QuickToolHUD.show(icon: "link", message: s.urlCleanerNoURL)
            return
        }
        guard let cleaned = URLCleanerService.shared.clean(raw) else {
            QuickToolHUD.show(icon: "link", message: s.urlCleanerNoURL)
            return
        }
        guard cleaned != raw else {
            QuickToolHUD.show(icon: "checkmark.circle", message: s.urlCleanerNoChange)
            return
        }
        URLCleanerService.shared.copy(cleaned)
        QuickToolHUD.show(icon: "link", message: s.urlCleanerCleaned)
    }

    /// Brightness lands on the display under the pointer, the screen where
    /// the bar was just used. The routes may need one refresh when the panel
    /// or Settings never opened this session.
    private static func applyBrightness(percent: Int, retried: Bool = false) {
        let service = BrightnessService.shared
        let value = Double(percent) / 100
        if let display = pointerDisplay(in: service.displays) {
            service.setBrightness(value, for: display.id, showOSD: true)
            return
        }
        guard !retried else {
            NSSound.beep()
            return
        }
        service.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            applyBrightness(percent: percent, retried: true)
        }
    }

    private static func pointerDisplay(in displays: [BrightnessDisplay]) -> BrightnessDisplay? {
        guard !displays.isEmpty else { return nil }
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        if let number = pointerScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let match = displays.first(where: { $0.id == number.uint32Value }) {
            return match
        }
        return displays.first
    }
}
