// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ServiceManagement
import SwiftUI

/// One entry in the Settings sidebar. New features add a case here and a row in
/// the Features section, so every feature gets its own page.
/// Selects the visible Settings page; the menu bar uses it to open Settings
/// directly on a specific page.
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var page: SettingsPage = .general
    private init() {}
}

/// System-Settings-style window: a sidebar of pages on the left, the selected
/// page on the right. Scales cleanly as features are added, and gives each
/// feature a page of its own with room for examples and advanced options.
struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var searchQuery = ""

    private var categories: SettingsCategoryStrings {
        FeatureStrings.settingsCategories(l10n.language)
    }

    private struct SidebarItem: Identifiable {
        let page: SettingsPage
        let title: String
        let icon: String
        /// Labels of options living inside the page, so the search finds a
        /// page by what it contains, in the user's language.
        var keywords: [String] = []
        var id: SettingsPage { page }
    }

    private var sidebarSections: [(title: String, items: [SidebarItem])] {
        [
            (categories.essentials, [
                SidebarItem(page: .general, title: l10n.s.tabGeneral, icon: "gearshape",
                            keywords: [l10n.s.launchAtLogin, l10n.s.languageLabel, l10n.s.showMenuBarIcon,
                                       l10n.s.musicBlockTitle, l10n.s.musicBlockSection]),
                // Searching any feature name lands here even when the feature
                // is hidden, so the hub is always the way back.
                SidebarItem(page: .features, title: FeatureStrings.hub(l10n.language).pageTitle,
                            icon: "square.grid.2x2",
                            keywords: AppFeature.allCases.map {
                                $0.hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language))
                            }),
                SidebarItem(page: .energy, title: l10n.s.tabEnergy, icon: "bolt.fill",
                            keywords: [l10n.s.keepAwakeTitle, l10n.s.clamshellTitle,
                                       l10n.s.defaultDurationLabel, l10n.s.extraBrightnessName,
                                       l10n.s.keepAwakeActiveIconLabel,
                                       l10n.s.keepAwakeActiveIconCoffee,
                                       l10n.s.keepAwakeActiveIconEye,
                                       FeatureStrings.brightness(l10n.language).pageTitle,
                                       FeatureStrings.keepAwakeAutomation(l10n.language)
                                           .externalDisplayToggle,
                                       FeatureStrings.keepAwakeAutomation(l10n.language).powerToggle]),
                SidebarItem(page: .monitor, title: l10n.s.tabMonitor, icon: "chart.line.uptrend.xyaxis",
                            keywords: [l10n.s.menuBarSpacingLabel, l10n.s.menuBarHideIconToggle,
                                       l10n.s.monitorMemoryPressureDot]),
            ]),
            (categories.windowsControls, [
                SidebarItem(page: .mouse, title: l10n.s.tabMouse, icon: "computermouse",
                            keywords: [l10n.s.invertMouseScroll, l10n.s.middleClickTapPicker,
                                       l10n.s.smoothScrollName, l10n.s.mouseNavigationEnable]),
                SidebarItem(page: .switcher, title: l10n.s.tabSwitcher, icon: "rectangle.on.rectangle",
                            keywords: [l10n.s.switcherEnable, l10n.s.dockClickMinimize,
                                       l10n.s.dockClickCycleWindows]),
                SidebarItem(page: .windowLayout, title: FeatureStrings.windowLayout(l10n.language).title, icon: "rectangle.3.group",
                            keywords: [l10n.s.dockClickCycleWindows,
                                       FeatureStrings.windowLayout(l10n.language).gestureEnable,
                                       FeatureStrings.windowLayout(l10n.language).gestureResize]),
                SidebarItem(page: .autoQuit, title: l10n.s.autoQuitName, icon: "xmark.rectangle",
                            keywords: [l10n.s.autoQuitEnable]),
            ]),
            (categories.files, [
                SidebarItem(page: .clipboard, title: FeatureStrings.clipboard(l10n.language).title, icon: "doc.on.clipboard",
                            keywords: [FeatureStrings.clipboard(l10n.language).limit,
                                       FeatureStrings.clipboard(l10n.language).skipSensitive]),
                SidebarItem(page: .cutPaste, title: l10n.s.cutPasteName, icon: "scissors",
                            keywords: [l10n.s.cutPasteEnable]),
                SidebarItem(page: .shelf, title: l10n.s.shelfName, icon: "tray.full",
                            keywords: [l10n.s.shelfEnable, l10n.s.shelfDropZoneToggle]),
                SidebarItem(page: .media, title: l10n.s.mediaName, icon: "photo.on.rectangle.angled",
                            keywords: ["PDF", "GIF", l10n.s.mediaStartConvertPDF, l10n.s.ocrName]),
            ]),
            (categories.utilities, [
                SidebarItem(page: .quickTools, title: l10n.s.quickToolsTab, icon: "wand.and.rays",
                            keywords: [l10n.s.launcherName, l10n.s.colorPickerName,
                                       l10n.s.micMuteName, l10n.s.ocrName,
                                       l10n.s.colorPickerBareHexToggle, l10n.s.micMuteMenuBarToggle,
                                       FeatureStrings.quickToggles(l10n.language).pageTitle,
                                       FeatureStrings.quickToggles(l10n.language).darkModeToDark,
                                       FeatureStrings.quickToggles(l10n.language).emptyTrashTitle]),
                SidebarItem(page: .urlCleaner, title: l10n.s.urlCleanerName, icon: "link"),
                SidebarItem(page: .homebrew, title: l10n.s.homebrewName, icon: "shippingbox"),
                SidebarItem(page: .uninstaller, title: l10n.s.uninstallerName, icon: "trash"),
                SidebarItem(page: .keyDebounce, title: l10n.s.keyDebounceName, icon: "keyboard"),
                SidebarItem(page: .textSnippets, title: FeatureStrings.snippets(l10n.language).pageTitle,
                            icon: "text.append",
                            keywords: [FeatureStrings.snippets(l10n.language).triggerLabel,
                                       FeatureStrings.snippets(l10n.language).addButton]),
            ]),
            (categories.app, [
                SidebarItem(page: .shortcuts, title: l10n.s.shortcutsPageTitle, icon: "command",
                            keywords: [l10n.s.hotkeyToggle]),
                SidebarItem(page: .advanced, title: l10n.s.tabAdvanced, icon: "wrench.and.screwdriver"),
                SidebarItem(page: .about, title: l10n.s.tabAbout, icon: "info.circle",
                            keywords: [l10n.s.reviewIntro]),
                SidebarItem(page: .releaseNotes, title: l10n.s.tabReleaseNotes, icon: "sparkles"),
                SidebarItem(page: .support, title: l10n.s.tabSupport, icon: "heart.fill"),
            ]),
        ]
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $router.page) {
                ForEach(sidebarSections, id: \.title) { section in
                    let items = section.items.filter {
                        FeatureVisibilitySupport.isPageVisible($0.page) { $0.isAvailable }
                            && SettingsSearchSupport.matches(query: searchQuery, title: $0.title,
                                                             keywords: $0.keywords)
                    }
                    if !items.isEmpty {
                        Section(section.title) {
                            ForEach(items) { item in
                                Label(item.title, systemImage: item.icon).tag(item.page)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchQuery,
                        placement: .sidebar,
                        prompt: l10n.s.settingsSearchPlaceholder)
            .settingsSidebarSearchEdge()
            .navigationSplitViewColumnWidth(min: 198, ideal: 210, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 772, maxWidth: .infinity, minHeight: 528, maxHeight: .infinity)
        .onAppear { ensureVisiblePage() }
        .onChange(of: features.revision) { _, _ in ensureVisiblePage() }
    }

    /// The selected page can leave the sidebar when its last feature is
    /// switched off in the hub; fall back to the hub itself, where the
    /// feature can be brought back.
    private func ensureVisiblePage() {
        if !FeatureVisibilitySupport.isPageVisible(router.page, isAvailable: { $0.isAvailable }) {
            router.page = .features
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch router.page {
        case .general: GeneralSettings()
        case .features: FeatureHubSettings()
        case .textSnippets: TextSnippetsSettings()
        case .energy: EnergySettings()
        case .monitor: MonitorSettings()
        case .mouse: MouseSettings()
        case .switcher: SwitcherSettings()
        case .keyDebounce: KeyboardDebounceSettings()
        case .cutPaste: CutPasteSettings()
        case .autoQuit: AutoQuitSettings()
        case .uninstaller: UninstallerView()
        case .urlCleaner: URLCleanerSettings()
        case .homebrew: HomebrewSettings()
        case .media: MediaSettings()
        case .clipboard: ClipboardSettings()
        case .quickTools: QuickToolsSettings()
        case .windowLayout: WindowLayoutSettings()
        case .shelf: ShelfSettings()
        case .shortcuts: ShortcutsSettings()
        case .advanced: AdvancedSettings()
        case .about: AboutSettings()
        case .releaseNotes: ReleaseNotesSettings()
        case .support: SupportSettings()
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var hotkeys = HotkeyManager.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage(DefaultsKey.hotkeyEnabled) private var hotkeyEnabled = true
    @AppStorage(DefaultsKey.showCountdown) private var showCountdown = false
    @AppStorage(DefaultsKey.musicBlockEnabled) private var musicBlockEnabled = false
    @AppStorage(DefaultsKey.musicBlockReplacementPath) private var musicBlockReplacementPath = ""

    var body: some View {
        Form {
            Section {
                Toggle(l10n.s.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Picker(l10n.s.languageLabel, selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }
            Section(l10n.s.menuBarSection) {
                if AppFeature.keepAwake.isAvailable {
                    Toggle(l10n.s.showCountdown, isOn: $showCountdown)
                }
                Button(l10n.s.showMenuBarIcon) {
                    appDelegate()?.reshowStatusItem()
                }
                Text(l10n.s.showMenuBarIconCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // The panel hosts more than monitoring, so its layout editor lives
            // here with the app-wide options rather than on the Monitor page
            // (which the hub can hide entirely).
            Section(l10n.s.monitorOrderSection) {
                PanelOrderEditor()
                Text(l10n.s.monitorOrderHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if AppFeature.keepAwake.isAvailable {
                Section(l10n.s.globalHotkeySection) {
                    Toggle(l10n.s.hotkeyToggle, isOn: $hotkeyEnabled)
                        .onChange(of: hotkeyEnabled) { _, enabled in
                            HotkeyManager.shared.setEnabled(enabled)
                        }
                    ShortcutPreferenceRow(role: .keepAwake, isEnabled: hotkeyEnabled) {
                        HotkeyManager.shared.syncWithPreferences()
                    }
                    if hotkeyEnabled, hotkeys.registrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(l10n.s.hotkeyCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if AppFeature.musicBlock.isAvailable {
                Section(l10n.s.musicBlockSection) {
                    Toggle(l10n.s.musicBlockTitle, isOn: $musicBlockEnabled)
                        .onChange(of: musicBlockEnabled) { _, _ in
                            MusicLaunchBlocker.shared.syncWithPreferences()
                        }
                    if musicBlockEnabled {
                        HStack {
                            Text(l10n.s.musicBlockReplacementLabel)
                            Spacer()
                            Text(musicBlockReplacementName)
                                .foregroundStyle(.secondary)
                            Button(l10n.s.musicBlockChooseApp) { chooseMusicReplacement() }
                            if !musicBlockReplacementPath.isEmpty {
                                Button {
                                    musicBlockReplacementPath = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    SettingsCaptionText(l10n.s.musicBlockCaption)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var musicBlockReplacementName: String {
        guard !musicBlockReplacementPath.isEmpty else { return l10n.s.musicBlockReplacementNone }
        let name = FileManager.default.displayName(atPath: musicBlockReplacementPath)
        return (name as NSString).deletingPathExtension
    }

    private func chooseMusicReplacement() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Picking the blocked app itself would start a launch-and-kill loop.
        if let bundleID = Bundle(url: url)?.bundleIdentifier,
           MusicLaunchBlocker.blockedBundleIDs.contains(bundleID) { return }
        musicBlockReplacementPath = url.path
    }
}

// MARK: - Updates

struct UpdatesView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var updates = UpdateService.shared
    @AppStorage(DefaultsKey.autoCheckUpdates) private var autoCheck = true

    var body: some View {
        Section(l10n.s.updatesSection) {
            Toggle(l10n.s.autoCheckToggle, isOn: $autoCheck)
                .onChange(of: autoCheck) { _, value in
                    UpdateService.shared.autoCheckEnabled = value
                }

            statusRow

            HStack {
                Button(l10n.s.checkNowButton) {
                    updates.check(manual: true)
                }
                .disabled(isBusy)

                if case .available = updates.state {
                    Button(l10n.s.updateInstallButton) {
                        appDelegate()?.showUpdatePreview()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let lastChecked = updates.lastChecked {
                Text("\(l10n.s.updateLastChecked) \(Self.format(lastChecked))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch updates.state {
        case .idle:
            EmptyView()
        case .checking:
            label(l10n.s.updateChecking, system: "arrow.triangle.2.circlepath", tint: .secondary)
        case .upToDate:
            label(l10n.s.updateUpToDate, system: "checkmark.circle.fill", tint: .green)
        case let .available(version):
            label("\(l10n.s.updateAvailablePrefix) \(version)", system: "arrow.down.circle.fill", tint: .accentColor)
        case let .downloading(progress):
            if let progress {
                label("\(l10n.s.updateDownloading) \(Int(progress * 100))%",
                      system: "arrow.down.circle", tint: .secondary)
            } else {
                label(l10n.s.updateDownloading, system: "arrow.down.circle", tint: .secondary)
            }
        case .installing:
            label(l10n.s.updateInstalling, system: "gearshape.2.fill", tint: .secondary)
        case let .failed(reason):
            label("\(l10n.s.updateFailedPrefix) \(reason)", system: "exclamationmark.triangle.fill", tint: .orange)
        }
    }

    private func label(_ text: String, system: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system).foregroundStyle(tint)
            Text(text).font(.callout)
            Spacer()
        }
    }

    private var isBusy: Bool {
        switch updates.state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Energy

struct EnergySettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var extraBrightness = ExtraBrightnessService.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @AppStorage(DefaultsKey.brightnessControlEnabled) private var brightnessEnabled = false
    @AppStorage(DefaultsKey.brightnessKeysEnabled) private var brightnessKeysEnabled = false
    @AppStorage(DefaultsKey.extraBrightnessEnabled) private var extraBrightnessEnabled = false
    @AppStorage(DefaultsKey.extraBrightnessLevel) private var extraBrightnessLevel = 100
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration = 0
    @AppStorage(DefaultsKey.batteryLimit) private var batteryLimit = 10
    @AppStorage(DefaultsKey.keepAwakeAutoStart) private var keepAwakeAutoStart = false
    @AppStorage(DefaultsKey.keepAwakeIconTint) private var keepAwakeIconTint = KeepAwakeIconTint.orange.rawValue
    @AppStorage(DefaultsKey.keepAwakeActiveIcon) private var keepAwakeActiveIcon = KeepAwakeActiveIcon.vorssaint.rawValue
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleEnabled) private var keepAwakeMouseJiggle = false
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleInterval) private var keepAwakeMouseJiggleInterval = 5

    var body: some View {
        Form {
            if AppFeature.keepAwake.isAvailable {
                Section(l10n.s.sessionSection) {
                    Picker(l10n.s.defaultDurationLabel, selection: $defaultDuration) {
                        Text(l10n.s.minutes15).tag(15)
                        Text(l10n.s.minutes30).tag(30)
                        Text(l10n.s.hour1).tag(60)
                        Text(l10n.s.hours2).tag(120)
                        Text(l10n.s.hours4).tag(240)
                        Text(l10n.s.hours8).tag(480)
                        Text(l10n.s.indefinite).tag(0)
                    }
                    SettingsToggleWithCaption(title: l10n.s.keepAwakeAutoStart,
                                              caption: l10n.s.keepAwakeAutoStartCaption,
                                              isOn: $keepAwakeAutoStart)
                }
                Section(automationStrings.automationSection) {
                    SettingsCaptionText(automationStrings.automationCaption)
                    KeepAwakeAutomationEditor()
                }
                Section(l10n.s.batteryProtectionSection) {
                    Picker(l10n.s.batteryDisableBelow, selection: $batteryLimit) {
                        Text(l10n.s.batteryNever).tag(0)
                        Text("5%").tag(5)
                        Text("10%").tag(10)
                        Text("15%").tag(15)
                        Text("20%").tag(20)
                    }
                    SettingsCaptionText(l10n.s.batteryProtectionCaption)
                }
                Section(l10n.s.keepAwakeTitle) {
                    KeepAwakeIconPicker(iconValue: $keepAwakeActiveIcon,
                                        tintValue: $keepAwakeIconTint)
                    SettingsToggleWithCaption(title: l10n.s.keepAwakeMouseJiggle,
                                              caption: l10n.s.keepAwakeMouseJiggleCaption,
                                              isOn: $keepAwakeMouseJiggle)
                    if keepAwakeMouseJiggle {
                        Picker(l10n.s.keepAwakeMouseJiggleInterval, selection: $keepAwakeMouseJiggleInterval) {
                            ForEach(Defaults.allowedKeepAwakeMouseJiggleIntervals, id: \.self) { minutes in
                                Text(KeepAwakeMouseJiggleIntervalPicker.label(for: minutes)).tag(minutes)
                            }
                        }
                        if !permissions.accessibility {
                            PermissionRow(kind: .accessibility)
                        }
                    }
                }
                Section(l10n.s.clamshellSection) {
                    Toggle(l10n.s.clamshellTitle, isOn: $awake.clamshellPreferred)
                        .disabled(awake.clamshellSetupInProgress)
                    if awake.clamshellSetupInProgress {
                        Text(l10n.s.configuring)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if awake.clamshellSetupFailed {
                        Text(l10n.s.sudoersFailed)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    SettingsCaptionText(l10n.s.clamshellExplanation)
                }
            }
            if AppFeature.brightness.isAvailable {
                let strings = FeatureStrings.brightness(l10n.language)
                Section(strings.pageTitle) {
                    SettingsToggleWithCaption(title: strings.enable,
                                              caption: strings.enableCaption,
                                              isOn: $brightnessEnabled)
                        .onChange(of: brightnessEnabled) { _, _ in
                            BrightnessService.shared.syncWithPreferences()
                        }
                    if brightnessEnabled {
                        if brightness.displays.isEmpty {
                            SettingsCaptionText(strings.noDisplays)
                        } else {
                            ForEach(brightness.displays) { display in
                                brightnessRow(display)
                            }
                        }
                        if let failure = brightness.displayControlFailure {
                            SettingsCaptionText(displayControlFailureText(failure, strings: strings))
                                .foregroundStyle(.red)
                        }
                        SettingsToggleWithCaption(title: strings.keysToggle,
                                                  caption: strings.keysCaption,
                                                  isOn: $brightnessKeysEnabled)
                            .onChange(of: brightnessKeysEnabled) { _, isOn in
                                if isOn { Permissions.shared.requestAccessibility() }
                                BrightnessService.shared.syncWithPreferences()
                            }
                        if brightnessKeysEnabled, !permissions.accessibility {
                            PermissionRow(kind: .accessibility)
                        }
                        SettingsCaptionText(strings.externalCaption)
                    }
                }
            }
            if AppFeature.extraBrightness.isAvailable {
                Section(l10n.s.extraBrightnessName) {
                    if extraBrightness.supported {
                        Toggle(l10n.s.extraBrightnessName, isOn: $extraBrightnessEnabled)
                            .onChange(of: extraBrightnessEnabled) { _, _ in
                                ExtraBrightnessService.shared.syncWithPreferences()
                            }
                        SettingsCaptionText(l10n.s.extraBrightnessCaption)
                        if extraBrightnessEnabled {
                            HStack {
                                Text(l10n.s.extraBrightnessLevelLabel)
                                Slider(value: extraBrightnessLevelBinding, in: 10...100, step: 5)
                                Text("\(extraBrightnessLevel)%")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 52, alignment: .trailing)
                            }
                        }
                    } else {
                        SettingsCaptionText(l10n.s.extraBrightnessUnsupported)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            defaultDuration = Defaults.sanitizedDefaultDuration(defaultDuration)
            batteryLimit = Defaults.sanitizedBatteryLimit(batteryLimit)
            keepAwakeIconTint = Defaults.sanitizedKeepAwakeIconTint(keepAwakeIconTint).rawValue
            keepAwakeActiveIcon = Defaults.sanitizedKeepAwakeActiveIcon(keepAwakeActiveIcon).rawValue
            keepAwakeMouseJiggleInterval = Defaults.sanitizedKeepAwakeMouseJiggleInterval(keepAwakeMouseJiggleInterval)
            awake.refreshPasswordlessStatus()
            // Displays may have changed since launch (docked, clamshell);
            // re-check so the section never shows a stale availability.
            ExtraBrightnessService.shared.syncWithPreferences()
            BrightnessService.shared.refresh()
        }
    }

    private func brightnessRow(_ display: BrightnessDisplay) -> some View {
        HStack(spacing: 10) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(display.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if display.isActive, display.method != nil {
                Slider(value: Binding(get: { display.brightness },
                                      set: { BrightnessService.shared.setBrightness($0,
                                                                                    for: display.id) }),
                       in: 0...1)
                    .disabled(brightness.isDisplayPending(display.id))
                    .accessibilityLabel(display.name)
                Text("\(Int((display.brightness * 100).rounded()))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            } else {
                Spacer()
                if !display.isActive {
                    Text(FeatureStrings.brightness(l10n.language).displayOff)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
            DisplayPowerButton(display: display)
        }
    }

    private var extraBrightnessLevelBinding: Binding<Double> {
        Binding(get: { Double(extraBrightnessLevel) },
                set: { newValue in
                    extraBrightnessLevel = Int(newValue)
                    ExtraBrightnessService.shared.levelDidChange()
                })
    }

    private var automationStrings: KeepAwakeAutomationStrings {
        FeatureStrings.keepAwakeAutomation(l10n.language)
    }
}

// MARK: - Mouse

struct MouseSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var inverter = ScrollInverter.shared
    @ObservedObject private var smoothScroll = SmoothScrollService.shared
    @ObservedObject private var mouseNavigation = MouseNavigationService.shared
    @ObservedObject private var middleClick = MiddleClickService.shared
    @AppStorage(DefaultsKey.scrollInverterEnabled) private var inverterEnabled = false
    @AppStorage(DefaultsKey.smoothScrollEnabled) private var smoothScrollEnabled = false
    @AppStorage(DefaultsKey.smoothScrollStep) private var smoothScrollStep = SmoothScrollSupport.defaultStep
    @AppStorage(DefaultsKey.mouseNavigationEnabled) private var mouseNavigationEnabled = false
    @AppStorage(DefaultsKey.middleClickEnabled) private var middleClickEnabled = false
    @AppStorage(DefaultsKey.middleClickTapFingers) private var middleClickTapFingers = 0

    var body: some View {
        Form {
            if AppFeature.scrollInverter.isAvailable {
                Section(l10n.s.scrollSection) {
                    Toggle(l10n.s.invertMouseScroll, isOn: $inverterEnabled)
                        .onChange(of: inverterEnabled) { _, _ in
                            ScrollInverter.shared.syncWithPreferences()
                        }
                    if inverterEnabled, inverter.isRunning {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(l10n.s.scrollActiveNow)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    Text(l10n.s.invertMouseScrollCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(l10n.s.scrollTrackpadNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if AppFeature.smoothScroll.isAvailable {
                Section(l10n.s.smoothScrollName) {
                    Toggle(l10n.s.smoothScrollName, isOn: $smoothScrollEnabled)
                        .onChange(of: smoothScrollEnabled) { _, _ in
                            SmoothScrollService.shared.syncWithPreferences()
                        }
                    Text(l10n.s.smoothScrollCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if smoothScrollEnabled {
                        HStack {
                            Slider(value: smoothScrollStepBinding,
                                   in: Double(SmoothScrollSupport.stepRange.lowerBound)...Double(SmoothScrollSupport.stepRange.upperBound),
                                   step: 10) {
                                Text(l10n.s.smoothScrollStepLabel)
                            }
                            Text("\(SmoothScrollSupport.sanitizedStep(smoothScrollStep))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
            if AppFeature.mouseNavigation.isAvailable {
                Section(l10n.s.mouseNavigationSection) {
                    Toggle(l10n.s.mouseNavigationEnable, isOn: $mouseNavigationEnabled)
                        .onChange(of: mouseNavigationEnabled) { _, _ in
                            MouseNavigationService.shared.syncWithPreferences()
                        }
                    Text(l10n.s.mouseNavigationCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if mouseNavigationEnabled, mouseNavigation.isRunning {
                        Label(l10n.s.mouseNavigationActiveNow, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            if AppFeature.middleClick.isAvailable {
                Section(l10n.s.middleClickSection) {
                    Toggle(l10n.s.middleClickEnable, isOn: $middleClickEnabled)
                        .onChange(of: middleClickEnabled) { _, _ in
                            MiddleClickService.shared.syncWithPreferences()
                        }
                    Text(l10n.s.middleClickEnableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if middleClickEnabled {
                        Picker(l10n.s.middleClickTapPicker, selection: $middleClickTapFingers) {
                            Text(l10n.s.middleClickTapOff).tag(0)
                            Text(l10n.s.middleClickTapThreeFingers).tag(3)
                            Text(l10n.s.middleClickTapFourFingers).tag(4)
                        }
                        .onChange(of: middleClickTapFingers) { _, _ in
                            MiddleClickService.shared.syncWithPreferences()
                        }
                        Text(l10n.s.middleClickTapCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if middleClickEnabled, middleClick.systemDragGestureConflict {
                        Text(l10n.s.middleClickDragConflict)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            if accessibilityNoteVisible {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            MiddleClickService.shared.refreshDragGestureConflict()
        }
    }

    /// Only features that are on AND still available can ask for the
    /// permission note; a hub-disabled one no longer needs anything.
    private var accessibilityNoteVisible: Bool {
        let anyEngaged = (inverterEnabled && AppFeature.scrollInverter.isAvailable)
            || (smoothScrollEnabled && AppFeature.smoothScroll.isAvailable)
            || (mouseNavigationEnabled && AppFeature.mouseNavigation.isAvailable)
            || (middleClickEnabled && AppFeature.middleClick.isAvailable)
        return anyEngaged && !permissions.accessibility
    }

    private var smoothScrollStepBinding: Binding<Double> {
        Binding(
            get: { Double(SmoothScrollSupport.sanitizedStep(smoothScrollStep)) },
            set: { smoothScrollStep = Int($0) }
        )
    }
}

// MARK: - Switcher

struct SwitcherSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var dockPreview = DockPreviewService.shared
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true
    @AppStorage(DefaultsKey.switcherIconRowMode) private var switcherIconRowMode = false
    @AppStorage(DefaultsKey.switcherSimpleMode) private var switcherSimpleMode = false
    @AppStorage(DefaultsKey.switcherMergeTabs) private var switcherMergeTabs = false
    @AppStorage(DefaultsKey.switcherShowWindowlessFinder) private var switcherShowWindowlessFinder = true
    @AppStorage(DefaultsKey.dockPreviewEnabled) private var dockPreviewEnabled = false
    @AppStorage(DefaultsKey.dockClickMinimize) private var dockClickMinimize = false
    @AppStorage(DefaultsKey.dockClickCycleWindows) private var dockClickCycleWindows = false
    @AppStorage(DefaultsKey.previewSize) private var previewSize = "normal"

    private var switcherEngaged: Bool { switcherEnabled && AppFeature.switcher.isAvailable }
    private var dockPreviewEngaged: Bool { dockPreviewEnabled && AppFeature.dockPreview.isAvailable }

    var body: some View {
        Form {
            if AppFeature.switcher.isAvailable {
                Section(l10n.s.switcherSection) {
                    Toggle(l10n.s.switcherEnable, isOn: $switcherEnabled)
                        .onChange(of: switcherEnabled) { _, _ in
                            AppSwitcher.shared.syncWithPreferences()
                        }
                    Text(l10n.s.switcherEnableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ShortcutPreferenceRow(role: .switcher,
                                          isEnabled: switcherEnabled,
                                          label: l10n.s.switcherShortcutHintApps) {
                        AppSwitcher.shared.syncWithPreferences()
                    }
                    ShortcutPreferenceRow(role: .switcherWindow,
                                          isEnabled: switcherEnabled,
                                          label: l10n.s.switcherShortcutHintWindows) {
                        AppSwitcher.shared.syncWithPreferences()
                    }
                    Text(l10n.s.switcherWindowShortcutCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: l10n.s.switcherUsageHintFormat,
                                GlobalShortcutRole.switcher.savedShortcut.displayString))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(l10n.s.switcherSimpleMode, isOn: $switcherSimpleMode)
                        .disabled(!switcherEnabled)
                        .onChange(of: switcherSimpleMode) { _, _ in
                            AppSwitcher.shared.syncWithPreferences()
                        }
                    Text(l10n.s.switcherSimpleModeCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(l10n.s.switcherIconRowMode, isOn: $switcherIconRowMode)
                        .disabled(!switcherEnabled || switcherSimpleMode)
                        .onChange(of: switcherIconRowMode) { _, _ in
                            AppSwitcher.shared.syncWithPreferences()
                        }
                    Text(l10n.s.switcherIconRowModeCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(l10n.s.switcherMergeTabs, isOn: $switcherMergeTabs)
                        .disabled(!switcherEnabled)
                    Text(l10n.s.switcherMergeTabsCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if switcherEnabled {
                        Toggle(l10n.s.switcherShowFinder, isOn: $switcherShowWindowlessFinder)
                        Text(l10n.s.switcherShowFinderCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if AppFeature.dockPreview.isAvailable || AppFeature.dockClick.isAvailable {
                Section {
                    if AppFeature.dockPreview.isAvailable {
                        Toggle(l10n.s.dockPreviewEnable, isOn: $dockPreviewEnabled)
                            .onChange(of: dockPreviewEnabled) { _, _ in
                                DockPreviewService.shared.syncWithPreferences()
                            }
                        Text(dockPreviewCaption)
                            .font(.caption)
                            .foregroundStyle(dockPreviewWarning ? .orange : .secondary)
                    }
                    if AppFeature.dockClick.isAvailable {
                        Toggle(l10n.s.dockClickMinimize, isOn: $dockClickMinimize)
                            .onChange(of: dockClickMinimize) { _, _ in
                                DockClickService.shared.syncWithPreferences()
                            }
                        Text(l10n.s.dockClickMinimizeCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle(l10n.s.dockClickCycleWindows, isOn: $dockClickCycleWindows)
                            .onChange(of: dockClickCycleWindows) { _, _ in
                                DockClickService.shared.syncWithPreferences()
                            }
                        Text(l10n.s.dockClickCycleWindowsCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(l10n.s.dockPreviewName)
                }
            }
            if AppFeature.switcher.isAvailable || AppFeature.dockPreview.isAvailable {
                Section {
                    Picker(l10n.s.previewSizeLabel, selection: $previewSize) {
                        Text(l10n.s.previewSizeNormal).tag("normal")
                        Text(l10n.s.previewSizeLarge).tag("large")
                        Text(l10n.s.previewSizeXLarge).tag("xlarge")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: previewSize) { _, _ in
                        AppSwitcher.shared.syncWithPreferences()
                    }
                } header: {
                    Text(l10n.s.previewSizeLabel)
                }
            }
            if switcherEngaged || dockPreviewEngaged {
                if !permissions.accessibility {
                    Section(l10n.s.permissionRequired) {
                        PermissionRow(kind: .accessibility)
                    }
                }
                if !permissions.screenRecording,
                   SwitcherSupport.needsScreenRecording(switcherEnabled: switcherEngaged,
                                                        simpleMode: switcherSimpleMode,
                                                        dockPreviewEnabled: dockPreviewEngaged) {
                    Section {
                        PermissionRow(kind: .screenRecording)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var dockPreviewCaption: String {
        guard dockPreviewEnabled else { return l10n.s.dockPreviewEnableCaption }
        if !permissions.accessibility { return "\(l10n.s.permissionRequired): \(l10n.s.permissionAccessibility)" }
        if !permissions.screenRecording { return "\(l10n.s.permissionRequired): \(l10n.s.permissionScreenRecording)" }
        switch dockPreview.blockedReason {
        case .magnification: return l10n.s.dockPreviewMagnificationBlocked
        case .dockUnavailable: return l10n.s.dockPreviewDockUnavailable
        default:
            return l10n.s.dockPreviewEnableCaption
        }
    }

    private var dockPreviewWarning: Bool {
        dockPreviewEnabled && dockPreview.blockedReason != nil
    }
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Form {
            Section {
                aboutContent
            }

            UpdatesView()
        }
        .formStyle(.grouped)
    }

    private var aboutContent: some View {
        VStack(spacing: 14) {
            BrandBadge(size: 76)
            VStack(spacing: 3) {
                Text(AppInfo.name)
                    .font(.title2.bold())
                Text("\(l10n.s.versionPrefix) \(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if AppInfo.isDeveloperBuild, let commit = AppInfo.buildCommit {
                    // Dev-only: which source commit this build came from. Never shipped.
                    Text(commit)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            Text(l10n.s.aboutDescription)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(l10n.s.reviewIntro) {
                    appDelegate()?.showOnboarding()
                }
                Link(l10n.s.viewOnGitHub, destination: AppInfo.repositoryURL)
            }
            Text(AppInfo.copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Release notes

struct ReleaseNotesSettings: View {
    @ObservedObject private var l10n = L10n.shared
    private let notes = ReleaseNotes.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.s.obWhatsNewTitle)
                    .font(.title2.bold())
                Text(versionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if notes.sections.isEmpty {
                        fallbackNote
                    } else {
                        ForEach(Array(notes.sections.enumerated()), id: \.offset) { _, section in
                            releaseSection(section)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var versionLine: String {
        if let date = notes.date {
            return "v\(notes.version) · \(date)"
        }
        return "v\(notes.version)"
    }

    private var fallbackNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, alignment: .center)
            Text(l10n.s.obWhatsNewFallback)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func releaseSection(_ section: ReleaseNoteSection) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if !section.title.isEmpty {
                Text(section.title.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }
            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                releaseItem(item, sectionTitle: section.title)
            }
        }
    }

    @ViewBuilder
    private func releaseItem(_ item: ReleaseNoteItem, sectionTitle: String) -> some View {
        switch item {
        case let .paragraph(text):
            Text(text)
                .font(.system(size: 12.8))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        case let .bullet(text):
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: iconName(for: sectionTitle))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18, alignment: .center)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .image(image):
            if let nsImage = releaseNoteImage(image) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                    .accessibilityLabel(image.alt)
                    .padding(.leading, 27)
            }
        }
    }

    private func releaseNoteImage(_ image: ReleaseNoteImage) -> NSImage? {
        var path = image.path
        if let resourcesRange = path.range(of: "Resources/") {
            path = String(path[resourcesRange.lowerBound...])
        }
        if path.hasPrefix("Resources/") {
            path.removeFirst("Resources/".count)
        }
        let nsPath = path as NSString
        let ext = nsPath.pathExtension
        let name = (nsPath.deletingPathExtension as NSString).lastPathComponent
        let directory = nsPath.deletingLastPathComponent
        guard !name.isEmpty, !ext.isEmpty else { return nil }
        let subdirectory = directory.isEmpty || directory == "." ? nil : directory
        guard let url = Bundle.main.url(forResource: name,
                                        withExtension: ext,
                                        subdirectory: subdirectory) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func iconName(for title: String) -> String {
        switch title.lowercased() {
        case "added": return "plus.circle.fill"
        case "changed": return "slider.horizontal.3"
        case "fixed": return "checkmark.circle.fill"
        default: return "circle.fill"
        }
    }
}

// MARK: - Support / donate

/// A calm, visual page inviting people to support the project. Nothing is
/// nagged or gated: the message and a single Buy Me a Coffee button that opens
/// the donate page in the browser.
struct SupportSettings: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.spaceGradient)
                    .frame(width: 84, height: 84)
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 33))
                    .foregroundStyle(.white)
            }
            Text(l10n.s.donateHeading)
                .font(.title2.bold())
            Text(l10n.s.donateMessage)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            CoffeeButton()
                .padding(.top, 4)
            Text(l10n.s.donateThanks)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// The Buy Me a Coffee call to action for the Support page. Opens the donate
/// page in the default browser.
struct CoffeeButton: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(AppInfo.donateURL)
        } label: {
            HStack(spacing: 8) {
                Text("☕").font(.system(size: 15))
                Text(l10n.s.donateButton)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color(red: 1.0, green: 0.84, blue: 0.0)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared settings rows

private struct SettingsCaptionText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsToggleWithCaption: View {
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                SettingsCaptionText(caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared permission row

enum PermissionKind {
    case accessibility
    case screenRecording
}

/// Status + actions for one TCC permission; shared by Settings and onboarding.
struct PermissionRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    let kind: PermissionKind

    private var granted: Bool {
        kind == .accessibility ? permissions.accessibility : permissions.screenRecording
    }

    private var name: String {
        kind == .accessibility ? l10n.s.permissionAccessibility : l10n.s.permissionScreenRecording
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                Text(name)
                Spacer()
                Text(granted ? l10n.s.permissionGranted : l10n.s.permissionMissing)
                    .font(.caption)
                    .foregroundStyle(granted ? .green : .orange)
            }
            if !granted {
                HStack(spacing: 8) {
                    Button(l10n.s.permissionRequest) {
                        if kind == .accessibility {
                            permissions.requestAccessibility()
                        } else {
                            permissions.requestScreenRecording()
                        }
                    }
                    Button(l10n.s.permissionOpenSettings) {
                        if kind == .accessibility {
                            permissions.openAccessibilitySettings()
                        } else {
                            permissions.openScreenRecordingSettings()
                        }
                    }
                }
                .controlSize(.small)
            }
        }
    }
}

private extension View {
    /// The sidebar search field is pinned to the top, so rows slide up behind it
    /// as the list scrolls. On macOS 26 the pinned field has no backing of its
    /// own, leaving the placeholder and the first rows overlapping (issue #183).
    /// A hard top scroll-edge effect gives that band a defined glass blur, so the
    /// rows fade out cleanly under the field. No-op on earlier systems, which
    /// keep the classic opaque sidebar chrome.
    @ViewBuilder
    func settingsSidebarSearchEdge() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }
}
