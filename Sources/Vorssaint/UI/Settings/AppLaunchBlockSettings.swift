// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Music media-key protection, then the apps that are always quit on
/// launch. The two rules stay apart: Music is only stopped when a media key
/// explains the launch, while a listed app is stopped every time.
struct AppLaunchBlockSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var blocker = AppLaunchBlocker.shared
    @State private var protectedRejected = false

    private var text: AppLaunchBlockStrings { FeatureStrings.appLaunchBlock(l10n.language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MusicBlockingSettings()
                SettingsCard {
                    AppBundleList(title: text.listTitle,
                                  caption: text.caption,
                                  addTitle: text.addButton,
                                  removeLabel: text.removeButton,
                                  bundleIDs: blocker.apps,
                                  reachesEveryApp: true,
                                  onAdd: add,
                                  onRemove: { blocker.remove($0) })
                    if protectedRejected {
                        Text(text.protectedApp)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
    }

    private func add(_ bundleID: String) {
        protectedRejected = AppLaunchBlocker.isProtected(bundleID: bundleID, bundleURL: nil)
        guard !protectedRejected else { return }
        blocker.add(bundleID)
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
