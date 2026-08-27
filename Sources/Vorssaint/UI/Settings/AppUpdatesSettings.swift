// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AppUpdatesSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var updates = AppUpdatesService.shared
    @AppStorage(DefaultsKey.appUpdatesCheckFrequency)
    private var frequencyRaw = AppUpdatesSupport.CheckFrequency.off.rawValue
    @AppStorage(DefaultsKey.appUpdatesNotify) private var notify = true
    @AppStorage(DefaultsKey.appUpdatesIncludeHomebrewApps) private var includeHomebrewApps = true
    @AppStorage(DefaultsKey.appUpdatesIncludeAppStore) private var includeAppStore = true
    @AppStorage(DefaultsKey.appUpdatesIncludeOnlineCatalog)
    private var includeOnlineCatalog = true
    @AppStorage(DefaultsKey.panelUtilityAppUpdates) private var showInPanel = true

    private var text: AppUpdateStrings { FeatureStrings.appUpdates(l10n.language) }

    var body: some View {
        Form {
            Section(text.pageTitle) {
                Text(text.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AppUpdatesListView()
                    .padding(.vertical, 2)
            }

            Section(text.frequencyLabel) {
                Picker(text.frequencyLabel, selection: frequencyBinding) {
                    Text(text.frequencyOff).tag(AppUpdatesSupport.CheckFrequency.off)
                    Text(text.frequencyDaily).tag(AppUpdatesSupport.CheckFrequency.daily)
                    Text(text.frequencyWeekly).tag(AppUpdatesSupport.CheckFrequency.weekly)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                if let next = updates.nextCheck {
                    Text(String(format: text.nextCheckFormat, nextCheckText(next)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(text.notifyToggle, isOn: $notify)
                    .disabled(AppUpdatesSupport.CheckFrequency.sanitized(frequencyRaw) == .off)
                    .onChange(of: notify) { _, value in
                        guard value else { return }
                        Notifier.requestPermission()
                    }
            }

            Section(text.sourcesTitle) {
                Toggle(text.includeHomebrewToggle, isOn: $includeHomebrewApps)
                    .disabled(includeHomebrewApps && enabledSourceCount == 1)
                    .onChange(of: includeHomebrewApps) { _, _ in
                        updates.sourceSelectionDidChange()
                    }
                Toggle(text.includeStoreToggle, isOn: $includeAppStore)
                    .disabled(includeAppStore && enabledSourceCount == 1)
                    .onChange(of: includeAppStore) { _, _ in
                        updates.sourceSelectionDidChange()
                    }
                Text(text.includeStoreCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(text.includeOnlineToggle, isOn: $includeOnlineCatalog)
                    .disabled(includeOnlineCatalog && enabledSourceCount == 1)
                    .onChange(of: includeOnlineCatalog) { _, _ in
                        updates.sourceSelectionDidChange()
                    }
                Text(text.includeOnlineCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(text.showInPanel, isOn: $showInPanel)
            }
        }
        .formStyle(.grouped)
        .onAppear { updates.checkIfNeeded() }
    }

    private var frequencyBinding: Binding<AppUpdatesSupport.CheckFrequency> {
        Binding {
            AppUpdatesSupport.CheckFrequency.sanitized(frequencyRaw)
        } set: { frequency in
            frequencyRaw = frequency.rawValue
            AppUpdatesService.shared.syncWithPreferences()
            if frequency != .off, notify { Notifier.requestPermission() }
        }
    }

    private var enabledSourceCount: Int {
        [includeHomebrewApps, includeAppStore, includeOnlineCatalog].filter { $0 }.count
    }

    private func nextCheckText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }
}
