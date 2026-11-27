// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A section of the existing Finder settings page, not a separate utility UI.
struct FinderNewFileSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.finderNewFileEnabled) private var enabled = false
    @AppStorage(DefaultsKey.finderNewFileKinds) private var selection = FinderNewFileKind.defaultSelection

    private var strings: FinderNewFileStrings {
        FinderNewFileStrings.localized(l10n.language.rawValue)
    }

    var body: some View {
        Section {
            Toggle(strings.enable, isOn: $enabled)
                .onChange(of: enabled) { _, _ in FinderNewFileService.syncWithPreferences() }
            Text(strings.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            if enabled {
                FinderNewFileExtensionStatus()
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
/// extension as a TCC permission. Only visible settings surfaces check it.
struct FinderNewFileExtensionStatus: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.finderNewFileEnabled) private var enabled = false
    @State private var extensionEnabled: Bool?
    var missingOnly = false

    private var strings: FinderNewFileStrings {
        FinderNewFileStrings.localized(l10n.language.rawValue)
    }

    var body: some View {
        Group {
            if enabled, let extensionEnabled, !missingOnly || !extensionEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: extensionEnabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(extensionEnabled ? .green : .orange)
                        Text(strings.extensionName)
                        Spacer()
                        Text(extensionEnabled ? strings.extensionEnabled : strings.extensionDisabled)
                            .font(.caption)
                            .foregroundStyle(extensionEnabled ? .green : .orange)
                    }
                    if !extensionEnabled {
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
            }
        }
        .onAppear { refresh() }
        .onChange(of: enabled) { _, _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        extensionEnabled = enabled ? FinderNewFileService.extensionEnabled : nil
    }
}
