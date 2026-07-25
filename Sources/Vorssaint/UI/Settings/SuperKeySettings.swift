// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct SuperKeySettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var superKey = SuperKeyService.shared
    @AppStorage(DefaultsKey.superKeyEnabled) private var enabled = false
    @AppStorage(DefaultsKey.superKeySoloAction) private var soloActionRaw = SuperKeySoloAction.none.rawValue

    private var text: SuperKeyStrings { FeatureStrings.superKey(l10n.language) }

    var body: some View {
        Form {
            Section(text.pageTitle) {
                Toggle(text.enableToggle, isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        SuperKeyService.shared.syncWithPreferences()
                        guard value, !permissions.accessibility else { return }
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
                    }
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                diagram
                if enabled, superKey.isRunning {
                    Label(text.activeNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section(text.soloSection) {
                Picker(text.soloSection, selection: soloBinding) {
                    Text(text.soloNothing).tag(SuperKeySoloAction.none)
                    Text(text.soloCapsLock).tag(SuperKeySoloAction.capsLock)
                    Text(text.soloEscape).tag(SuperKeySoloAction.escape)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                Text(text.soloCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The whole feature in one line: the key you hold, and the four keys it
    /// stands for. Dimmed while the feature is off, so the page reads the same
    /// either way without pretending to be active.
    private var diagram: some View {
        HStack(spacing: 10) {
            VStack(spacing: 3) {
                keyCap(text.capsLockKey, symbol: "capslock", wide: true)
                Text(text.holdHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 14)
            HStack(spacing: 5) {
                ForEach(["⇧", "⌃", "⌥", "⌘"], id: \.self) { glyph in
                    keyCap(glyph, symbol: nil, wide: false)
                }
            }
            .padding(.bottom, 14)
        }
        .opacity(enabled ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.18), value: enabled)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text.panelCaption)
    }

    private func keyCap(_ title: String, symbol: String?, wide: Bool) -> some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .frame(minWidth: wide ? 84 : 30, minHeight: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
    }

    private var soloBinding: Binding<SuperKeySoloAction> {
        Binding {
            SuperKeySoloAction.sanitized(soloActionRaw)
        } set: { action in
            soloActionRaw = action.rawValue
            SuperKeyService.shared.syncWithPreferences()
        }
    }
}
