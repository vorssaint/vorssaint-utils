// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The apps the clipboard history never saves from (issue #423). It sits with
/// the other choices about what gets saved, and stays a single quiet row until
/// there is an app in it, so the page reads the same for everyone who never
/// needs one.
struct ClipboardIgnoredAppsList: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var ignored = ClipboardIgnoredApps.shared
    @State private var isExpanded: Bool
    @State private var showingAppPicker = false

    init() {
        _isExpanded = State(initialValue: !ClipboardIgnoredApps.shared.apps.isEmpty)
    }

    private var text: ClipboardIgnoredAppsStrings {
        FeatureStrings.clipboardIgnoredApps(l10n.language)
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
                        ignored.remove(bundleID)
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
            // Rows inside a disclosure group center themselves; the button
            // belongs under the list it adds to.
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

    private var sortedApps: [String] {
        ignored.apps.sorted {
            InstalledApps.name(for: $0).localizedCaseInsensitiveCompare(InstalledApps.name(for: $1))
                == .orderedAscending
        }
    }

    private var appPickerSheet: some View {
        let listed = Set(ignored.apps)
        return AppPickerView {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            ignored.add(bundleID)
        } loadApps: {
            InstalledApps.installedBundleApplications(excluding: listed)
        }
    }
}
