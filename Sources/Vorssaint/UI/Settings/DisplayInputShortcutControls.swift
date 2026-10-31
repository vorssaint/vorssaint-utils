// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The input source shortcut, and per monitor the inputs it moves through.
struct DisplayInputShortcutControls: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @AppStorage(DefaultsKey.displayInputShortcutEnabled) private var enabled = false

    private var strings: DisplayInputStrings { DisplayInputStrings.localized(l10n.language) }
    private var monitors: [BrightnessDisplay] {
        brightness.displays.filter { $0.isActive && !$0.isBuiltIn && $0.method == .ddc }
    }

    var body: some View {
        SettingsRow(symbol: "arrow.right.square", title: strings.shortcutTitle, caption: strings.shortcutCaption) {
            Toggle(strings.shortcutTitle, isOn: $enabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .onChange(of: enabled) { _, _ in brightness.syncWithPreferences() }
        if enabled {
            ShortcutPreferenceRow(role: .displayInputNext, isEnabled: enabled,
                                  label: GlobalShortcutRole.displayInputNext.title(l10n.s),
                                  includeInactiveConflicts: true,
                                  additionalConflict: { shortcut in
                guard AppFeature.windowLayout.isAvailable else { return nil }
                return WindowLayoutService.shared.shortcutConflictTitle(shortcut, excluding: nil)
            }) {
                brightness.syncWithPreferences()
            }
            .padding(.leading, settingsRowTextInset)
            if brightness.displayInputShortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, settingsRowTextInset)
            }
            ForEach(monitors) { display in
                monitorInputs(display)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private func monitorInputs(_ display: BrightnessDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(display.name)
                .font(.subheadline.weight(.medium))
            if let state = brightness.inputStates[display.id] {
                let excluded = brightness.inputCycleExclusions(for: display.id)
                ForEach(state.inputs) { input in
                    Toggle(DisplayInputSupport.label(of: input), isOn: Binding(
                        get: { !excluded.contains(input.id) },
                        set: { brightness.setInput(input, cycled: $0, for: display.id) }))
                        .toggleStyle(.checkbox)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .onAppear { brightness.detectInputSources(for: display.id) }
    }
}
