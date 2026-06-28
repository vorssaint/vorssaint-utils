// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ServiceManagement
import SwiftUI

/// One entry in the Settings sidebar. New features add a case here and a row in
/// the Features section, so every feature gets its own page.
enum SettingsPage: Hashable {
    case general, energy, monitor
    case mouse, switcher, cutPaste, autoQuit, uninstaller, urlCleaner, homebrew, media, clipboard, windowLayout, shelf
    case advanced, about, releaseNotes, support
}

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

    private var categories: SettingsCategoryStrings {
        FeatureStrings.settingsCategories(l10n.language)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $router.page) {
                Section(categories.essentials) {
                    Label(l10n.s.tabGeneral, systemImage: "gearshape").tag(SettingsPage.general)
                    Label(l10n.s.tabEnergy, systemImage: "bolt.fill").tag(SettingsPage.energy)
                    Label(l10n.s.tabMonitor, systemImage: "chart.line.uptrend.xyaxis").tag(SettingsPage.monitor)
                }

                Section(categories.windowsControls) {
                    Label(l10n.s.tabMouse, systemImage: "computermouse").tag(SettingsPage.mouse)
                    Label(l10n.s.tabSwitcher, systemImage: "rectangle.on.rectangle").tag(SettingsPage.switcher)
                    Label(FeatureStrings.windowLayout(l10n.language).title, systemImage: "rectangle.3.group").tag(SettingsPage.windowLayout)
                    Label(l10n.s.cutPasteName, systemImage: "scissors").tag(SettingsPage.cutPaste)
                    Label(l10n.s.autoQuitName, systemImage: "xmark.rectangle").tag(SettingsPage.autoQuit)
                }

                Section(categories.utilities) {
                    Label(FeatureStrings.clipboard(l10n.language).title, systemImage: "doc.on.clipboard").tag(SettingsPage.clipboard)
                    Label(l10n.s.shelfName, systemImage: "tray.full").tag(SettingsPage.shelf)
                    Label(l10n.s.uninstallerName, systemImage: "trash").tag(SettingsPage.uninstaller)
                    Label(l10n.s.urlCleanerName, systemImage: "link").tag(SettingsPage.urlCleaner)
                    Label(l10n.s.homebrewName, systemImage: "shippingbox").tag(SettingsPage.homebrew)
                    Label(l10n.s.mediaName, systemImage: "photo.on.rectangle.angled").tag(SettingsPage.media)
                }

                Section(categories.app) {
                    Label(l10n.s.tabAdvanced, systemImage: "wrench.and.screwdriver").tag(SettingsPage.advanced)
                    Label(l10n.s.tabAbout, systemImage: "info.circle").tag(SettingsPage.about)
                    Label(l10n.s.tabReleaseNotes, systemImage: "sparkles").tag(SettingsPage.releaseNotes)
                    Label(l10n.s.tabSupport, systemImage: "heart.fill").tag(SettingsPage.support)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 198, ideal: 210, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 772, height: 528)
    }

    @ViewBuilder
    private var detail: some View {
        switch router.page {
        case .general: GeneralSettings()
        case .energy: EnergySettings()
        case .monitor: MonitorSettings()
        case .mouse: MouseSettings()
        case .switcher: SwitcherSettings()
        case .cutPaste: CutPasteSettings()
        case .autoQuit: AutoQuitSettings()
        case .uninstaller: UninstallerView()
        case .urlCleaner: URLCleanerSettings()
        case .homebrew: HomebrewSettings()
        case .media: MediaSettings()
        case .clipboard: ClipboardSettings()
        case .windowLayout: WindowLayoutSettings()
        case .shelf: ShelfSettings()
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
    @ObservedObject private var hotkeys = HotkeyManager.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage(DefaultsKey.hotkeyEnabled) private var hotkeyEnabled = true
    @AppStorage(DefaultsKey.showCountdown) private var showCountdown = false

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
                Toggle(l10n.s.showCountdown, isOn: $showCountdown)
                Button(l10n.s.showMenuBarIcon) {
                    appDelegate()?.reshowStatusItem()
                }
                Text(l10n.s.showMenuBarIconCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        .formStyle(.grouped)
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
        case .downloading:
            label(l10n.s.updateDownloading, system: "arrow.down.circle", tint: .secondary)
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
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration = 0
    @AppStorage(DefaultsKey.batteryLimit) private var batteryLimit = 10
    @AppStorage(DefaultsKey.keepAwakeAutoStart) private var keepAwakeAutoStart = false
    @AppStorage(DefaultsKey.keepAwakeIconTint) private var keepAwakeIconTint = KeepAwakeIconTint.orange.rawValue
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleEnabled) private var keepAwakeMouseJiggle = false
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleInterval) private var keepAwakeMouseJiggleInterval = 5

    var body: some View {
        Form {
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
                Picker(l10n.s.keepAwakeIconTintLabel, selection: $keepAwakeIconTint) {
                    ForEach(KeepAwakeIconTint.allCases) { tint in
                        Text(tint.title(l10n.s)).tag(tint.rawValue)
                    }
                }
                .pickerStyle(.menu)
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
        .formStyle(.grouped)
        .onAppear {
            defaultDuration = Defaults.sanitizedDefaultDuration(defaultDuration)
            batteryLimit = Defaults.sanitizedBatteryLimit(batteryLimit)
            keepAwakeIconTint = Defaults.sanitizedKeepAwakeIconTint(keepAwakeIconTint).rawValue
            keepAwakeMouseJiggleInterval = Defaults.sanitizedKeepAwakeMouseJiggleInterval(keepAwakeMouseJiggleInterval)
            awake.refreshPasswordlessStatus()
        }
    }
}

// MARK: - Mouse

struct MouseSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var inverter = ScrollInverter.shared
    @AppStorage(DefaultsKey.scrollInverterEnabled) private var inverterEnabled = false

    var body: some View {
        Form {
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
            if inverterEnabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Switcher

struct SwitcherSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var dockPreview = DockPreviewService.shared
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true
    @AppStorage(DefaultsKey.switcherIconRowMode) private var switcherIconRowMode = false
    @AppStorage(DefaultsKey.switcherMergeTabs) private var switcherMergeTabs = false
    @AppStorage(DefaultsKey.switcherShowWindowlessFinder) private var switcherShowWindowlessFinder = true
    @AppStorage(DefaultsKey.dockPreviewEnabled) private var dockPreviewEnabled = false
    @AppStorage(DefaultsKey.previewSize) private var previewSize = "normal"

    var body: some View {
        Form {
            Section(l10n.s.switcherSection) {
                Toggle(l10n.s.switcherEnable, isOn: $switcherEnabled)
                    .onChange(of: switcherEnabled) { _, _ in
                        AppSwitcher.shared.syncWithPreferences()
                    }
                Text(l10n.s.switcherEnableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ShortcutPreferenceRow(role: .switcher, isEnabled: switcherEnabled) {
                    AppSwitcher.shared.syncWithPreferences()
                }
                Text(String(format: l10n.s.switcherUsageHintFormat,
                            GlobalShortcutRole.switcher.savedShortcut.displayString))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(l10n.s.switcherIconRowMode, isOn: $switcherIconRowMode)
                    .disabled(!switcherEnabled)
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
            Section {
                Toggle(l10n.s.dockPreviewEnable, isOn: $dockPreviewEnabled)
                    .onChange(of: dockPreviewEnabled) { _, _ in
                        DockPreviewService.shared.syncWithPreferences()
                    }
                Text(dockPreviewCaption)
                    .font(.caption)
                    .foregroundStyle(dockPreviewWarning ? .orange : .secondary)
            } header: {
                Text(l10n.s.dockPreviewName)
            }
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
            if switcherEnabled || dockPreviewEnabled {
                if !permissions.accessibility {
                    Section(l10n.s.permissionRequired) {
                        PermissionRow(kind: .accessibility)
                    }
                }
                if !permissions.screenRecording {
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
