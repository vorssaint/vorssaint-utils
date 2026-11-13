// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Apps "Quit all apps" leaves running. Mandatory rows (Finder, Vorssaint,
/// Phone when installed) stay locked; everything else is picked like the other
/// exception lists (issue #855).
struct QuitAllExceptionsList: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = QuickTogglesService.shared
    @State private var isExpanded: Bool
    @State private var showingAppPicker = false

    private var strings: QuickToggleFeatureStrings {
        FeatureStrings.quickToggles(l10n.language)
    }

    init() {
        let raw = UserDefaults.standard.stringArray(forKey: DefaultsKey.quitAppsKeptApps) ?? []
        // The locked rows are always there; open the list only for apps the user added.
        _isExpanded = State(initialValue: raw.contains {
            !Defaults.mandatoryAutoQuitExceptionBundleIDs.contains($0)
        })
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(sortedExceptions, id: \.self) { bundleID in
                HStack(spacing: 9) {
                    Image(nsImage: InstalledApps.icon(for: bundleID))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(InstalledApps.name(for: bundleID))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if service.isMandatoryQuitAllException(bundleID) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.tertiary)
                    } else {
                        Button {
                            service.removeQuitAllException(bundleID)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(l10n.s.actionRemove)
                    }
                }
            }

            Button {
                showingAppPicker = true
            } label: {
                Label(l10n.s.autoQuitAddApp, systemImage: "plus")
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(strings.exceptionsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text(strings.exceptionsTitle)
                Spacer()
                if !sortedExceptions.isEmpty {
                    Text("\(sortedExceptions.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            appPickerSheet
        }
    }

    private var sortedExceptions: [String] {
        AutoQuitSupport.visibleExceptions(service.quitAllExceptions) {
            InstalledApps.url(for: $0) != nil
        }
        .sorted {
            InstalledApps.name(for: $0).localizedCaseInsensitiveCompare(InstalledApps.name(for: $1))
                == .orderedAscending
        }
    }

    private var appPickerSheet: some View {
        let excluded = Set(service.quitAllExceptions)
        return AppPickerView {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            service.addQuitAllException(bundleID)
        } loadApps: {
            InstalledApps.installedBundleApplications(excluding: excluded)
        }
    }
}
