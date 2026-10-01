// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Settings page of a feature that works in the Dynamic Island and in
/// the menu panel alike: whether it is on, where it shows, and its options.
/// What only changes the island stays with the island's own settings.
struct IslandFeatureSettings: View {
    let module: NotchModule
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchHiddenModules) private var hidden = ""
    @AppStorage private var enabled: Bool
    @AppStorage private var inPanel: Bool
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }

    init(module: NotchModule) {
        self.module = module
        // A page without a switch of its own is always on; its key is never written.
        _enabled = AppStorage(wrappedValue: true, module.enableKey ?? "islandFeatureAlwaysOn")
        _inPanel = AppStorage(wrappedValue: Defaults.registeredDefaults[module.panelEntryKey] as? Bool ?? true,
                              module.panelEntryKey)
    }

    private var inIsland: Binding<Bool> {
        Binding {
            !hidden.split(separator: ",").contains(Substring(module.rawValue))
        } set: { shown in
            var values = Set(hidden.split(separator: ",").map(String.init))
            if shown { values.remove(module.rawValue) } else { values.insert(module.rawValue) }
            hidden = values.sorted().joined(separator: ",")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    NotchSectionTile(module: module, shown: enabled, side: 38)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(module.title(l10n.language)).font(.title2.bold())
                        Text(editor.summary(module)).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    if module.enableKey != nil {
                        Toggle(module.title(l10n.language), isOn: $enabled).labelsHidden().toggleStyle(.switch)
                    }
                }
                SettingsCard {
                    SettingsRow(symbol: "macbook", title: FeatureStrings.notch(l10n.language).title) {
                        Toggle(FeatureStrings.notch(l10n.language).title, isOn: inIsland)
                            .labelsHidden().toggleStyle(.switch)
                    }
                    SettingsRow(symbol: "menubar.rectangle", title: FeatureStrings.appUpdates(l10n.language).showInPanel) {
                        Toggle(FeatureStrings.appUpdates(l10n.language).showInPanel, isOn: $inPanel)
                            .labelsHidden().toggleStyle(.switch)
                    }
                }
                .disabled(!enabled)
                IslandFeatureOptions(module: module)
                    .disabled(!enabled)
            }
            .padding(22)
        }
        .onChange(of: enabled) { _, _ in sync() }
        .onChange(of: hidden) { _, _ in sync() }
        .onChange(of: inPanel) { _, _ in sync() }
    }

    private func sync() {
        NotchService.shared.syncWithPreferences()
        // The panel's services run without the island, so they hear of it here too.
        NotchService.shared.panelDemandChanged(module)
        if module == .notifications { NotchNotificationService.shared.syncWithPreferences() }
        if module == .agents { AgentMenuBarReading.shared.syncWithPreferences() }
    }
}

/// A feature's options that apply wherever it shows.
struct IslandFeatureOptions: View {
    let module: NotchModule
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.notchTimerSoundEnabled) private var timerSoundEnabled = true
    @AppStorage(DefaultsKey.notchIncludeOtherPlayers) private var includeOtherPlayers = false
    @AppStorage(DefaultsKey.notchLyricsEnabled) private var lyricsEnabled = true
    @AppStorage(DefaultsKey.notchLyricsOnline) private var lyricsOnline = false
    @AppStorage(DefaultsKey.notchQueueEnabled) private var queueEnabled = true

    var body: some View {
        switch module {
        case .agents:
            SettingsCard { NotchAgentsSettingsControls() }
        case .calendar:
            let calendar = FeatureStrings.notchCalendar(l10n.language)
            SettingsCard {
                Text(calendar.permission).font(.callout).foregroundStyle(.secondary)
                if permissions.calendarAccess == .fullAccess {
                    Label(l10n.s.permissionGranted, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    NotchCalendarSelection()
                } else {
                    Button(calendar.allow, action: permissions.requestCalendar).disabled(permissions.requestingCalendar)
                    Button(calendar.settings, action: permissions.openCalendarSettings)
                }
            }
        case .timer:
            SettingsCard {
                switchRow("speaker.wave.2", FeatureStrings.notchActivities(l10n.language).soundEnabled,
                          isOn: $timerSoundEnabled)
            }
        case .downloads:
            SettingsCard {
                NotchDownloadsSettingsControls()
                    .toggleStyle(TrailingSwitchToggleStyle())
            }
        case .notifications:
            // Reading banners needs Accessibility wherever they are kept.
            if !permissions.accessibility {
                SettingsCard { PermissionRow(kind: .accessibility) }
            }
        case .music:
            let music = FeatureStrings.notchMusicExtras(l10n.language)
            SettingsCard {
                switchRow("play.rectangle", music.includeOtherPlayers, isOn: $includeOtherPlayers)
                switchRow("text.quote", music.enableLyrics, isOn: $lyricsEnabled)
                    .disabled(!AppFeature.notchLyrics.isAvailable)
                if lyricsEnabled, AppFeature.notchLyrics.isAvailable {
                    switchRow("globe", music.online, caption: music.onlineHint, isOn: $lyricsOnline)
                        .padding(.leading, settingsRowTextInset)
                }
                switchRow("list.bullet", music.enableQueue, caption: music.queueDescription, isOn: $queueEnabled)
                    .disabled(!AppFeature.notchQueue.isAvailable)
            }
            .onChange(of: lyricsEnabled) { _, _ in syncMusic() }
            .onChange(of: queueEnabled) { _, _ in syncMusic() }
            .onChange(of: includeOtherPlayers) { _, _ in NotchService.shared.syncWithPreferences() }
        default:
            EmptyView()
        }
    }

    private func syncMusic() {
        let panel = PanelModuleDemand.shared.shows(.music)
        if !NotchLyricsSupport.isEnabled(panelVisible: panel) { NotchLyricsService.shared.stop() }
        NotchMusicService.shared.syncQueuePreference()
    }

    private func switchRow(_ symbol: String, _ title: String, caption: String? = nil, isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title, caption: caption) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}
