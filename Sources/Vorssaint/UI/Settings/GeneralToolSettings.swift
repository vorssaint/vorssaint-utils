// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Tools that share General's destination have their own detail content, so
/// opening General does not also build the audio device and mixer controls.
struct GeneralToolSettings: View {
    let anchor: SettingsSectionAnchor
    @ObservedObject private var l10n = L10n.shared

    private var text: GeneralSettingsStrings { FeatureStrings.generalSettings(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch anchor {
                case .panelConfiguration:
                    SettingsCard(title: l10n.s.menuBarSection) {
                        Text(text.panelIntro)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        PanelLayoutEditor()
                        Divider()
                        SettingsRow(symbol: nil, title: text.iconMissingTitle,
                                    caption: text.iconMissingCaption) {
                            Button(l10n.s.showMenuBarIcon) {
                                appDelegate()?.reshowStatusItem()
                            }
                        }
                    }
                    .settingsSectionAnchor(.panelConfiguration, cornerRadius: 16)
                case .mixer:
                    MixerSection(settingsMode: true)
                        .settingsSectionAnchor(.mixer, cornerRadius: 16)
                case .soundOutputSwitcher:
                    SettingsCard(title: l10n.s.soundOutputSwitcherTitle) {
                        SoundOutputSwitcherControls()
                    }
                    .settingsSectionAnchor(.soundOutputSwitcher, cornerRadius: 16)
                case .audioPriority:
                    SettingsCard(title: l10n.s.audioPrioritySection) {
                        AudioPriorityDisclosure(initiallyExpanded: true, showsHeader: false)
                    }
                    .settingsSectionAnchor(.audioPriority, cornerRadius: 16)
                case .musicBlocking:
                    MusicBlockingSettings()
                        .settingsSectionAnchor(.musicBlocking, cornerRadius: 16)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
    }
}

private struct MusicBlockingSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var musicBlocker = MusicLaunchBlocker.shared
    @State private var replacementRejected = false
    @AppStorage(DefaultsKey.musicBlockEnabled) private var enabled = false
    @AppStorage(DefaultsKey.musicBlockReplacementPath) private var replacementPath = ""
    @AppStorage(DefaultsKey.musicBlockPlayReplacement) private var playReplacement = true

    var body: some View {
        SettingsCard(title: l10n.s.musicBlockSection) {
            SettingsRow(symbol: "playpause.fill", title: l10n.s.musicBlockTitle,
                        caption: l10n.s.musicBlockCaption) {
                Toggle(l10n.s.musicBlockTitle, isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: enabled) { _, _ in
                        musicBlocker.syncWithPreferences()
                    }
            }
            if enabled {
                if !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                        .padding(.leading, settingsRowTextInset)
                } else if !musicBlocker.isMonitoring {
                    Text(l10n.s.musicBlockUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
                HStack(spacing: 8) {
                    Text(l10n.s.musicBlockReplacementLabel)
                    Spacer()
                    Text(replacementName)
                        .foregroundStyle(.secondary)
                    Button(l10n.s.musicBlockChooseApp) { chooseReplacement() }
                    if !replacementPath.isEmpty {
                        Button {
                            replacementPath = ""
                            replacementRejected = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, settingsRowTextInset)
                if !replacementPath.isEmpty {
                    Toggle(l10n.s.musicBlockPlayReplacement, isOn: $playReplacement)
                        .padding(.leading, settingsRowTextInset)
                }
                if replacementRejected {
                    Text(l10n.s.musicBlockReplacementBlocked)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
            }
        }
    }

    private var replacementName: String {
        guard !replacementPath.isEmpty else { return l10n.s.musicBlockReplacementNone }
        let name = FileManager.default.displayName(atPath: replacementPath)
        return (name as NSString).deletingPathExtension
    }

    private func chooseReplacement() {
        replacementRejected = false
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Picking the blocked app itself would start a launch-and-kill loop.
        if let bundleID = Bundle(url: url)?.bundleIdentifier,
           MusicLaunchBlocker.blockedBundleIDs.contains(bundleID) {
            replacementRejected = true
            return
        }
        replacementPath = url.path
    }
}
