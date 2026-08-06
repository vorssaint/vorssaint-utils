// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The "apps to leave alone" block that lives INSIDE a mouse feature's own
/// section in Settings (issue #358), right under the switch it holds back, so
/// the list is where the user is already looking. One list per feature: the
/// same view with a different scope.
///
/// It stays a single quiet row while nothing is listed, and comes up open when
/// the feature already has exceptions, so a page with every mouse feature on
/// never turns into a wall of lists.
struct MouseExceptionsList: View {
    let scope: MouseExceptionScope

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var exceptions = MouseAppExceptions.shared
    @State private var isExpanded: Bool
    @State private var showingAppPicker = false

    init(scope: MouseExceptionScope) {
        self.scope = scope
        _isExpanded = State(initialValue: !MouseAppExceptions.shared.list(scope).isEmpty)
    }

    private var text: MouseExceptionStrings { FeatureStrings.mouseExceptions(l10n.language) }

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
                        exceptions.remove(bundleID, from: scope)
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

            Text(text.caption(for: scope))
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
        exceptions.list(scope).sorted {
            InstalledApps.name(for: $0).localizedCaseInsensitiveCompare(InstalledApps.name(for: $1))
                == .orderedAscending
        }
    }

    private var appPickerSheet: some View {
        let listed = Set(exceptions.list(scope))
        return AppPickerView(canBrowseApplications: true) {
            showingAppPicker = false
        } onSelect: { url in
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            exceptions.add(bundleID, to: scope)
            showingAppPicker = false
        } loadApps: {
            InstalledApps.installedBundleApplications(excluding: listed,
                                                       includeRunningApplications: true)
        }
    }
}
