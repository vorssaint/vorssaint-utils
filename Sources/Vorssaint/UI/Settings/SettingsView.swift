// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ServiceManagement
import SwiftUI

/// One entry in the Settings sidebar. New features add a case here and a row in
/// the Features section, so every feature gets its own page.
enum SettingsPage: Hashable {
    case general, energy, monitor
    case mouse, switcher, cutPaste, autoQuit, uninstaller, shelf
    case advanced, about, support
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
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $router.page) {
                Section {
                    sidebarLabel(l10n.s.tabGeneral, systemImage: "gearshape.fill", color: .blue).tag(SettingsPage.general)
                    sidebarLabel(l10n.s.tabAdvanced, systemImage: "slider.horizontal.3", color: .gray).tag(SettingsPage.advanced)
                }

                Section("System & Display") {
                    sidebarLabel(l10n.s.tabMonitor, systemImage: "display", color: .indigo).tag(SettingsPage.monitor)
                    sidebarLabel(l10n.s.tabEnergy, systemImage: "battery.100", color: .green).tag(SettingsPage.energy)
                }

                Section(l10n.s.settingsGroupFeatures) {
                    sidebarLabel(l10n.s.tabMouse, systemImage: "computermouse.fill", color: .blue).tag(SettingsPage.mouse)
                    sidebarLabel(l10n.s.tabSwitcher, systemImage: "square.on.square.fill", color: .purple).tag(SettingsPage.switcher)
                    sidebarLabel(l10n.s.cutPasteName, systemImage: "scissors", color: .orange).tag(SettingsPage.cutPaste)
                    sidebarLabel(l10n.s.autoQuitName, systemImage: "xmark.app.fill", color: .red).tag(SettingsPage.autoQuit)
                    sidebarLabel(l10n.s.shelfName, systemImage: "tray.full.fill", color: .teal).tag(SettingsPage.shelf)
                }

                Section("Maintenance") {
                    sidebarLabel(l10n.s.uninstallerName, systemImage: "trash.fill", color: .gray).tag(SettingsPage.uninstaller)
                    sidebarLabel(l10n.s.tabAbout, systemImage: "info.circle.fill", color: .blue).tag(SettingsPage.about)
                    sidebarLabel(l10n.s.tabSupport, systemImage: "heart.fill", color: .pink).tag(SettingsPage.support)
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 36)
            .searchable(text: $searchText, prompt: "Search Settings")
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 820, height: 560)
    }

    private func sidebarLabel(_ title: String, systemImage: String, color: Color) -> some View {
        Label {
            Text(title)
                .font(.system(size: 14))
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
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
        case .shelf: ShelfSettings()
        case .advanced: AdvancedSettings()
        case .about: AboutSettings()
        case .support: SupportSettings()
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject private var l10n = L10n.shared
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
                Text(l10n.s.hotkeyCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            UpdatesView()
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
                        updates.downloadAndInstall()
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
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration = 0
    @AppStorage(DefaultsKey.batteryLimit) private var batteryLimit = 10

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
            }
            Section(l10n.s.batteryProtectionSection) {
                Picker(l10n.s.batteryDisableBelow, selection: $batteryLimit) {
                    Text(l10n.s.batteryNever).tag(0)
                    Text("5%").tag(5)
                    Text("10%").tag(10)
                    Text("15%").tag(15)
                    Text("20%").tag(20)
                }
                Text(l10n.s.batteryProtectionCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(l10n.s.clamshellSection) {
                Toggle(l10n.s.clamshellTitle, isOn: $awake.clamshellPreferred)
                Text(l10n.s.clamshellExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            defaultDuration = Defaults.sanitizedDefaultDuration(defaultDuration)
            batteryLimit = Defaults.sanitizedBatteryLimit(batteryLimit)
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
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true
    @AppStorage(DefaultsKey.switcherMergeTabs) private var switcherMergeTabs = false

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
                Text(l10n.s.switcherUsageHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(l10n.s.switcherMergeTabs, isOn: $switcherMergeTabs)
                    .disabled(!switcherEnabled)
                Text(l10n.s.switcherMergeTabsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if switcherEnabled {
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
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
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
            Spacer()
            Text(AppInfo.copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
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

/// The Buy Me a Coffee call to action, shared by the Support page and the
/// onboarding announcement. Opens the donate page in the default browser.
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
