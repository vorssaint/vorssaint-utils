// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AutoQuitSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = AutoQuitService.shared
    @AppStorage(DefaultsKey.autoQuitEnabled) private var enabled = false
    @State private var showingAppPicker = false

    var body: some View {
        Form {
            Section {
                Toggle(l10n.s.autoQuitEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        AutoQuitService.shared.syncWithPreferences()
                    }
                Text(l10n.s.autoQuitEnableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, service.isRunning {
                    Label(l10n.s.autoQuitActiveNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section(l10n.s.autoQuitHowTitle) {
                bullet("rectangle.badge.xmark", l10n.s.autoQuitStep1)
                bullet("bolt.fill", l10n.s.autoQuitStep2)
                Text(l10n.s.autoQuitPredictableNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(l10n.s.autoQuitOngoingWorkNote, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker(modeText.modeTitle, selection: onlyListedBinding) {
                    Text(modeText.allExceptTitle).tag(false)
                    Text(modeText.onlyListedTitle).tag(true)
                }
                .disabled(!enabled)
            }

            // The lists have one reader, the window check, and that only
            // runs while the feature does. With the switch off every edit here
            // is a no-op, so the list follows it. Only the list for the chosen
            // mode is shown; the other one keeps its apps for when it is picked.
            Section(service.onlyListedApps ? modeText.includedTitle : l10n.s.autoQuitExceptionsTitle) {
                if sortedApps.isEmpty {
                    Text(service.onlyListedApps ? modeText.includedEmpty : l10n.s.autoQuitExceptionsEmpty)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedApps, id: \.self) { bundleID in
                        HStack(spacing: 9) {
                            Image(nsImage: InstalledApps.icon(for: bundleID))
                                .resizable().frame(width: 20, height: 20)
                            Text(InstalledApps.name(for: bundleID))
                            Spacer()
                            if !service.onlyListedApps, service.isMandatoryException(bundleID) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.tertiary)
                            } else {
                                Button {
                                    if service.onlyListedApps {
                                        service.removeIncludedApp(bundleID)
                                    } else {
                                        service.removeException(bundleID)
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .disabled(!enabled)
                }

                Button {
                    showingAppPicker = true
                } label: {
                    Label(l10n.s.autoQuitAddApp, systemImage: "plus")
                }
                .disabled(!enabled)

                Text(service.onlyListedApps ? modeText.includedCaption : l10n.s.autoQuitExceptionsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAppPicker) {
            appPickerSheet
        }
    }

    private var modeText: AutoQuitModeStrings {
        FeatureStrings.autoQuitMode(l10n.language)
    }

    private var onlyListedBinding: Binding<Bool> {
        Binding(get: { service.onlyListedApps },
                set: { service.setOnlyListedApps($0) })
    }

    private var sortedApps: [String] {
        let listed = service.onlyListedApps
            ? service.includedApps
            : AutoQuitSupport.visibleExceptions(service.exceptions) {
                InstalledApps.url(for: $0) != nil
            }
        return listed.sorted {
            InstalledApps.name(for: $0).localizedCaseInsensitiveCompare(InstalledApps.name(for: $1))
                == .orderedAscending
        }
    }

    private var appPickerSheet: some View {
        let excluded = Set(service.onlyListedApps ? service.includedApps : service.exceptions)
        return AppPickerView {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            if service.onlyListedApps {
                service.addIncludedApp(bundleID)
            } else {
                service.addException(bundleID)
            }
        } loadApps: {
            InstalledApps.installedBundleApplications(excluding: excluded)
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.tint)
                .frame(width: 18)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
