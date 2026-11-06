// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AutoFullscreenSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = AutoFullscreenService.shared
    @AppStorage(DefaultsKey.autoFullscreenEnabled) private var enabled = false
    @AppStorage(DefaultsKey.autoFullscreenBuiltInDisplayOnly) private var builtInDisplayOnly = true
    @State private var showingAppPicker = false

    private var text: AutoFullscreenStrings {
        FeatureStrings.autoFullscreen(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                Toggle(text.enable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        AutoFullscreenService.shared.syncWithPreferences()
                    }
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, service.isRunning {
                    Label(text.activeNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section(text.howTitle) {
                bullet("rectangle.inset.filled", text.stepWindow)
                bullet("clock", text.stepWait)
                Text(text.predictableNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Both the display rule and the exception list are only read when
            // an app launches with the feature on, so they follow its switch.
            Section {
                Toggle(text.builtInDisplayOnly, isOn: $builtInDisplayOnly)
                    .disabled(!enabled)
                Text(text.builtInDisplayOnlyCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(text.exceptionsTitle) {
                if sortedExceptions.isEmpty {
                    Text(text.exceptionsEmpty)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedExceptions, id: \.self) { bundleID in
                        HStack(spacing: 9) {
                            Image(nsImage: InstalledApps.icon(for: bundleID))
                                .resizable().frame(width: 20, height: 20)
                            Text(InstalledApps.name(for: bundleID))
                            Spacer()
                            Button {
                                service.removeException(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(text.removeApp)
                        }
                    }
                    .disabled(!enabled)
                }

                Button {
                    showingAppPicker = true
                } label: {
                    Label(text.addApp, systemImage: "plus")
                }
                .disabled(!enabled)

                Text(text.exceptionsCaption)
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
        .onAppear { service.reloadExceptions() }
        .sheet(isPresented: $showingAppPicker) {
            appPickerSheet
        }
    }

    private var sortedExceptions: [String] {
        service.exceptions.sorted {
            InstalledApps.name(for: $0).localizedCaseInsensitiveCompare(InstalledApps.name(for: $1))
                == .orderedAscending
        }
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
