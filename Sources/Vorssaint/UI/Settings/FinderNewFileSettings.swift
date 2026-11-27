// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// A section of the existing Finder settings page, not a separate utility UI.
struct FinderNewFileSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.finderNewFileEnabled) private var enabled = false
    @AppStorage(DefaultsKey.finderNewFileKinds) private var selection = FinderNewFileKind.defaultSelection

    private var strings: FinderNewFileStrings {
        FeatureStrings.finderNewFile(l10n.language)
    }

    var body: some View {
        Section {
            Toggle(strings.enable, isOn: $enabled)
                .onChange(of: enabled) { _, _ in FinderNewFileService.syncWithPreferences() }
            Text(strings.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            FinderNewFileExtensionStatus()
            if enabled {
                ForEach(FinderNewFileKind.allCases, id: \.self) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Label(kind.title(strings), systemImage: kind.symbol)
                    }
                }
            }
        } header: {
            Text(strings.title)
        }
        .settingsFormSectionAnchor(.finderNewFile)
        .onChange(of: selection) { _, _ in FinderNewFileService.syncWithPreferences() }
    }

    private func binding(for kind: FinderNewFileKind) -> Binding<Bool> {
        Binding(get: { FinderNewFileKind.selection(selection).contains(kind) },
                set: { value in
                    var kinds = Set(FinderNewFileKind.selection(selection))
                    if value { kinds.insert(kind) } else { kinds.remove(kind) }
                    selection = FinderNewFileKind.allCases.filter { kinds.contains($0) }
                        .map(\.rawValue).joined(separator: ",")
                })
    }
}

/// Mirrors PermissionRow's status and actions without treating a Finder
/// extension as a TCC permission. The management entry stays available even
/// when the feature switch is off, so the user can disable the extension.
struct FinderNewFileExtensionStatus: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var extensionEnabled: Bool?
    @State private var refreshID = UUID()

    private var strings: FinderNewFileStrings {
        FeatureStrings.finderNewFile(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SystemCapabilityStatusRow(name: strings.extensionName, granted: extensionEnabled,
                                      grantedTitle: strings.extensionEnabled,
                                      missingTitle: strings.extensionDisabled)
            if extensionEnabled == false {
                Text(strings.extensionHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(strings.manage) {
                FinderNewFileService.openExtensionSettings()
            }
            .controlSize(.small)
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        // Match WindowLayoutSettings' appearance/activation refresh policy.
        // Like the permission portal's automation check, keep the system
        // query off the UI thread. No separate periodic monitor is needed.
        let id = UUID()
        refreshID = id
        DispatchQueue.global(qos: .userInitiated).async {
            let enabled = FinderNewFileService.extensionEnabled
            DispatchQueue.main.async {
                guard refreshID == id else { return }
                extensionEnabled = enabled
            }
        }
    }
}
