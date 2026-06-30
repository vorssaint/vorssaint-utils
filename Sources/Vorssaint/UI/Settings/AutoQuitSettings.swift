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
            }

            Section(l10n.s.autoQuitExceptionsTitle) {
                if sortedExceptions.isEmpty {
                    Text(l10n.s.autoQuitExceptionsEmpty)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedExceptions, id: \.self) { bundleID in
                        HStack(spacing: 9) {
                            Image(nsImage: InstalledApps.icon(for: bundleID))
                                .resizable().frame(width: 20, height: 20)
                            Text(InstalledApps.name(for: bundleID))
                            Spacer()
                            if service.isMandatoryException(bundleID) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.tertiary)
                            } else {
                                Button {
                                    service.removeException(bundleID)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Button {
                    showingAppPicker = true
                } label: {
                    Label(l10n.s.autoQuitAddApp, systemImage: "plus")
                }

                Text(l10n.s.autoQuitExceptionsCaption)
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

    private var sortedExceptions: [String] {
        service.exceptions.sorted { InstalledApps.name(for: $0).localizedCaseInsensitiveCompare(InstalledApps.name(for: $1)) == .orderedAscending }
    }

    private var appPickerSheet: some View {
        let excluded = Set(service.exceptions)
        return AppPickerView {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            service.addException(bundleID)
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
