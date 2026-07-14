// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ShelfSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var shelf = ShelfService.shared
    @AppStorage(DefaultsKey.shelfEnabled) private var enabled = false
    @AppStorage(DefaultsKey.shelfShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.shelfShakeToOpen) private var shake = true
    @AppStorage(DefaultsKey.shelfDropZoneEnabled) private var dropZone = true
    @AppStorage(DefaultsKey.shelfCloseAfterDrop) private var closeAfterDrop = false
    @AppStorage(DefaultsKey.shelfRemoveAfterDrop) private var removeAfterDrop = true
    @State private var showingAppPicker = false

    var body: some View {
        Form {
            Section {
                Toggle(l10n.s.shelfEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        ShelfService.shared.syncWithPreferences()
                    }
                Text(l10n.s.shelfEnableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(l10n.s.shelfNoPermission, systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l10n.s.shelfHowTitle) {
                bullet("1", l10n.s.shelfStep1)
                bullet("2", l10n.s.shelfStep2)
                bullet("3", l10n.s.shelfStep3)
            }

            if enabled {
                Section {
                    Toggle(l10n.s.shelfShortcutToggle, isOn: $shortcutEnabled)
                        .onChange(of: shortcutEnabled) { _, _ in
                            ShelfService.shared.syncHotkey()
                        }
                    ShortcutPreferenceRow(role: .shelf, isEnabled: shortcutEnabled) {
                        ShelfService.shared.syncHotkey()
                    }
                    if shortcutEnabled, shelf.hotkeyRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(l10n.s.shelfShakeToggle, isOn: $shake)
                            .onChange(of: shake) { _, _ in
                                ShelfService.shared.syncDragMonitor()
                            }
                        Text(l10n.s.shelfShakeCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(l10n.s.shelfDropZoneToggle, isOn: $dropZone)
                            .onChange(of: dropZone) { _, _ in
                                ShelfService.shared.syncDragMonitor()
                            }
                        Text(l10n.s.shelfDropZoneCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        ShelfService.shared.summon()
                    } label: {
                        Label(l10n.s.shelfOpenNow, systemImage: "tray.and.arrow.down")
                    }
                }

                Section(l10n.s.shelfBehaviorTitle) {
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(l10n.s.shelfCloseAfterDrop, isOn: $closeAfterDrop)
                        Text(l10n.s.shelfCloseAfterDropCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(l10n.s.shelfRemoveAfterDrop, isOn: $removeAfterDrop)
                        Text(l10n.s.shelfRemoveAfterDropCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(l10n.s.shelfExclusionsTitle) {
                    if sortedExclusions.isEmpty {
                        Text(l10n.s.shelfExclusionsEmpty)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedExclusions, id: \.self) { bundleID in
                            HStack(spacing: 9) {
                                Image(nsImage: InstalledApps.icon(for: bundleID))
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(InstalledApps.name(for: bundleID))
                                Spacer()
                                Button {
                                    shelf.removeAutomaticExclusion(bundleID)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button {
                        showingAppPicker = true
                    } label: {
                        Label(l10n.s.autoQuitAddApp, systemImage: "plus")
                    }
                    Text(l10n.s.shelfExclusionsCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAppPicker) {
            appPickerSheet
        }
    }

    private var sortedExclusions: [String] {
        shelf.automaticExclusions.sorted {
            InstalledApps.name(for: $0)
                .localizedCaseInsensitiveCompare(InstalledApps.name(for: $1)) == .orderedAscending
        }
    }

    private var appPickerSheet: some View {
        let excluded = Set(shelf.automaticExclusions)
        return AppPickerView {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            shelf.addAutomaticExclusion(bundleID)
        } loadApps: {
            InstalledApps.installedBundleApplications(excluding: excluded)
        }
    }

    private func bullet(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
