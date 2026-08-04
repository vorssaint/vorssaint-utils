// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct WindowPreviewExclusionsList: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var apps: [String]
    @State private var isExpanded: Bool
    @State private var showingAppPicker = false

    init() {
        let apps = Self.savedApps
        _apps = State(initialValue: apps)
        _isExpanded = State(initialValue: !apps.isEmpty)
    }

    private var text: WindowPreviewExclusionStrings {
        FeatureStrings.windowPreviewExclusions(l10n.language)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(sortedApps, id: \.self) { bundleID in
                HStack(spacing: 9) {
                    Image(nsImage: InstalledApps.icon(for: bundleID))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(InstalledApps.name(for: bundleID))
                    Spacer()
                    Button {
                        save(apps.filter { $0 != bundleID })
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(text.removeButton)
                }
            }

            Button {
                showingAppPicker = true
            } label: {
                Label(text.addButton, systemImage: "plus")
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(text.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text(text.listTitle)
                Spacer()
                if !sortedApps.isEmpty {
                    Text("\(sortedApps.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            appPickerSheet
        }
    }

    private static var savedApps: [String] {
        Defaults.sanitizedBundleIdentifierList(
            UserDefaults.standard.stringArray(forKey: DefaultsKey.windowPreviewExcludedApps) ?? [])
    }

    private var sortedApps: [String] {
        apps.sorted {
            InstalledApps.name(for: $0).localizedCaseInsensitiveCompare(InstalledApps.name(for: $1))
                == .orderedAscending
        }
    }

    private var appPickerSheet: some View {
        let listed = Set(apps)
        return AppPickerView {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            save(apps + [bundleID])
        } loadApps: {
            InstalledApps.installedBundleApplications(excluding: listed)
        }
    }

    private func save(_ bundleIDs: [String]) {
        let sanitized = Defaults.sanitizedBundleIdentifierList(bundleIDs)
        UserDefaults.standard.set(sanitized, forKey: DefaultsKey.windowPreviewExcludedApps)
        apps = sanitized
    }
}
