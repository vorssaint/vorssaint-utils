// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct GlobeKeySettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var globe = GlobeKeyService.shared
    @AppStorage(DefaultsKey.globeKeyEnabled) private var enabled = false
    @AppStorage(DefaultsKey.globeKeySinglePressAction) private var singlePressRaw = ""
    @AppStorage(DefaultsKey.globeKeyDoublePressAction) private var doublePressRaw = ""
    @AppStorage(DefaultsKey.globeKeyTriplePressAction) private var triplePressRaw = ""
    @AppStorage(DefaultsKey.globeKeyLongPressAction) private var longPressRaw = ""
    @State private var sources: [InputSourceSelection.Reading] = []

    private var text: GlobeKeyStrings { FeatureStrings.globeKey(l10n.language) }

    /// One row of a gesture picker: nothing, a named input source, or the
    /// keyboard settings pane where the prerequisite lives.
    private struct ActionOption: Identifiable, Equatable {
        let action: GlobeKeyAction
        let label: String
        var id: String { action.storageValue.isEmpty ? "none" : action.storageValue }
    }

    var body: some View {
        Form {
            Section(text.pageTitle) {
                Toggle(text.enableToggle, isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        GlobeKeyService.shared.syncWithPreferences()
                        guard value, !permissions.accessibility else { return }
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
                    }
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(text.prerequisiteNote, systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(text.openKeyboardSettingsButton) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                if enabled, !permissions.accessibility {
                    Label(l10n.s.permissionRequired, systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if enabled, globe.tapRefused {
                    Label(text.tapRefused, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if enabled, globe.isRunning {
                    Label(text.activeNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section {
                Text(text.gestureCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                gesturePicker(title: text.singlePressLabel, raw: $singlePressRaw)
                gesturePicker(title: text.doublePressLabel, raw: $doublePressRaw)
                gesturePicker(title: text.triplePressLabel, raw: $triplePressRaw)
                gesturePicker(title: text.longPressLabel, raw: $longPressRaw)
            } header: {
                Text(text.gestureSection)
            }
            .disabled(!enabled)

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshSources() }
    }

    private func gesturePicker(title: String, raw: Binding<String>) -> some View {
        Picker(title, selection: Binding<GlobeKeyAction>(
            get: { GlobeKeyAction.sanitized(raw.wrappedValue) },
            set: { raw.wrappedValue = $0.storageValue }
        )) {
            ForEach(options(for: GlobeKeyAction.sanitized(raw.wrappedValue))) { option in
                Text(option.label).tag(option.action)
            }
        }
    }

    /// The picker's rows: nothing first, then every enabled input source, then
    /// the keyboard settings. A stored source that is no longer enabled keeps
    /// its row, so the selection never silently falls back to nothing.
    private func options(for current: GlobeKeyAction) -> [ActionOption] {
        var options = [ActionOption(action: .none, label: text.actionNothing)]
        for source in sources {
            options.append(ActionOption(action: .inputSource(id: source.id),
                                        label: source.name.isEmpty ? source.id : source.name))
        }
        if case .inputSource(let id) = current, !sources.contains(where: { $0.id == id }) {
            options.append(ActionOption(action: .inputSource(id: id), label: id))
        }
        options.append(ActionOption(action: .openKeyboardSettings, label: text.actionOpenSettings))
        return options
    }

    private func refreshSources() {
        sources = InputSourceSelection.readings()
    }
}
