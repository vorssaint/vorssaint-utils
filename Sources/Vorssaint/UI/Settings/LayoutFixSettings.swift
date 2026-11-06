// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import SwiftUI

struct LayoutFixSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = LayoutFixService.shared
    @AppStorage(DefaultsKey.layoutFixEnabled) private var enabled = false
    @AppStorage(DefaultsKey.layoutFixTrigger) private var triggerRaw = LayoutFixTrigger.rightOption.rawValue
    @State private var excluded: [String] = UserDefaults.standard.stringArray(
        forKey: DefaultsKey.layoutFixExcludedLayouts) ?? []

    private var text: LayoutFixStrings { FeatureStrings.layoutFix(l10n.language) }

    /// Every enabled layout, named the way the Input menu names it.
    private var enabledLayouts: [(id: String, name: String)] {
        InputSourceSelection.selectableInputSources().compactMap { source in
            guard InputSourceSelection.inputSourceString(source, property: kTISPropertyInputSourceType)
                    == kTISTypeKeyboardLayout as String,
                  let id = InputSourceSelection.inputSourceString(source, property: kTISPropertyInputSourceID)
            else { return nil }
            return (id, InputSourceSelection.inputSourceString(source, property: kTISPropertyLocalizedName) ?? id)
        }
    }

    var body: some View {
        Form {
            Section(text.pageTitle) {
                Toggle(text.enableToggle, isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        LayoutFixService.shared.syncWithPreferences()
                        guard value, !permissions.accessibility else { return }
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
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

            Section(text.triggerSection) {
                Picker(text.triggerSection, selection: triggerBinding) {
                    ForEach(LayoutFixTrigger.allCases.filter { $0 != .shortcut }) { trigger in
                        Text(text.triggerLabel(trigger)).tag(trigger)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                Text(text.triggerCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            Section(text.layoutsSection) {
                ForEach(enabledLayouts, id: \.id) { layout in
                    Toggle(layout.name, isOn: participates(layout.id))
                }
                Text(text.layoutsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            if enabled {
                MouseExceptionsList(scope: .layoutFix)
            }

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var triggerBinding: Binding<LayoutFixTrigger> {
        Binding(
            get: { LayoutFixTrigger.sanitized(triggerRaw) },
            set: {
                triggerRaw = $0.rawValue
                LayoutFixService.shared.syncWithPreferences()
            }
        )
    }

    private func participates(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !excluded.contains(id) },
            set: { included in
                excluded.removeAll { $0 == id }
                if !included { excluded.append(id) }
                UserDefaults.standard.set(excluded, forKey: DefaultsKey.layoutFixExcludedLayouts)
            }
        )
    }
}
