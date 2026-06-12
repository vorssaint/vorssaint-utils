import ServiceManagement
import SwiftUI

/// One entry in the Settings sidebar. New features add a case here and a row in
/// the Features section, so every feature gets its own page.
enum SettingsPage: Hashable {
    case general, energy
    case mouse, switcher, cutPaste, autoQuit, uninstaller, shelf
    case about
}

/// System-Settings-style window: a sidebar of pages on the left, the selected
/// page on the right. Scales cleanly as features are added, and gives each
/// feature a page of its own with room for examples and advanced options.
struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var page: SettingsPage = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Label(l10n.s.tabGeneral, systemImage: "gearshape").tag(SettingsPage.general)
                Label(l10n.s.tabEnergy, systemImage: "bolt.fill").tag(SettingsPage.energy)

                Section(l10n.s.settingsGroupFeatures) {
                    Label(l10n.s.tabMouse, systemImage: "computermouse").tag(SettingsPage.mouse)
                    Label(l10n.s.tabSwitcher, systemImage: "rectangle.on.rectangle").tag(SettingsPage.switcher)
                    Label(l10n.s.cutPasteName, systemImage: "scissors").tag(SettingsPage.cutPaste)
                    Label(l10n.s.autoQuitName, systemImage: "xmark.rectangle").tag(SettingsPage.autoQuit)
                    Label(l10n.s.uninstallerName, systemImage: "trash").tag(SettingsPage.uninstaller)
                    Label(l10n.s.shelfName, systemImage: "tray.full").tag(SettingsPage.shelf)
                }

                Label(l10n.s.tabAbout, systemImage: "info.circle").tag(SettingsPage.about)
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
        switch page {
        case .general: GeneralSettings()
        case .energy: EnergySettings()
        case .mouse: MouseSettings()
        case .switcher: SwitcherSettings()
        case .cutPaste: CutPasteSettings()
        case .autoQuit: AutoQuitSettings()
        case .uninstaller: UninstallerSettings()
        case .shelf: ShelfSettings()
        case .about: AboutSettings()
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
                Toggle(l10n.s.keepDisplayOn, isOn: $awake.keepDisplayOn)
                Text(l10n.s.keepDisplayCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text(l10n.s.scrollLiveNote)
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
    @AppStorage(DefaultsKey.switcherShowBrowserTabs) private var showBrowserTabs = true

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
                Toggle(l10n.s.switcherTabsToggle, isOn: $showBrowserTabs)
                    .disabled(!switcherEnabled)
                Text(l10n.s.switcherTabsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(l10n.s.switcherUsageHint)
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
