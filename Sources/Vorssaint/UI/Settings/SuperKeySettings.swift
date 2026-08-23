// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct SuperKeySettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var superKey = SuperKeyService.shared
    @AppStorage(DefaultsKey.superKeyEnabled) private var enabled = false
    @AppStorage(DefaultsKey.superKeyModifiers) private var modifierStorage =
        SuperKeySupport.defaultModifierStorageValue
    @AppStorage(DefaultsKey.superKeySoloAction) private var soloActionRaw = SuperKeySoloAction.none.rawValue

    private var text: SuperKeyStrings { FeatureStrings.superKey(l10n.language) }

    private struct ModifierChoice: Identifiable {
        let modifier: GlobalShortcutModifiers
        let symbol: String
        let name: String
        var id: String { name }
    }

    private let modifierChoices = [
        ModifierChoice(modifier: .shift, symbol: "⇧", name: "Shift"),
        ModifierChoice(modifier: .control, symbol: "⌃", name: "Control"),
        ModifierChoice(modifier: .option, symbol: "⌥", name: "Option"),
        ModifierChoice(modifier: .command, symbol: "⌘", name: "Command"),
    ]

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
                    Text(text.soloInputSource).tag(SuperKeySoloAction.inputSource)
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

    /// The whole feature in one line: the key you hold, and the keys it stands
    /// for. Dimmed while the feature is off, so the page reads the same
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
                ForEach(modifierChoices) { choice in
                    modifierKeyCap(choice)
                }
            }
            .padding(.bottom, 14)
        }
        .opacity(enabled ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.18), value: enabled)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
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

    private func modifierKeyCap(_ choice: ModifierChoice) -> some View {
        let selected = selectedModifiers.contains(choice.modifier)
        return Button {
            toggle(choice.modifier)
        } label: {
            Text(choice.symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(minWidth: 30, minHeight: 30)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected
                            ? Color.accentColor.opacity(0.14)
                            : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected
                            ? Color.accentColor.opacity(0.45)
                            : Color.primary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled || (selected && !canRemove(choice.modifier)))
        .help(choice.name)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var selectedModifiers: GlobalShortcutModifiers {
        SuperKeySupport.modifiers(from: modifierStorage)
    }

    private func toggle(_ modifier: GlobalShortcutModifiers) {
        var next = selectedModifiers
        if next.contains(modifier) {
            next.remove(modifier)
        } else {
            next.insert(modifier)
        }
        guard next.hasPrimaryModifier else { return }
        modifierStorage = SuperKeySupport.storageValue(for: next)
        SuperKeyService.shared.syncWithPreferences()
    }

    private func canRemove(_ modifier: GlobalShortcutModifiers) -> Bool {
        var remaining = selectedModifiers
        remaining.remove(modifier)
        return remaining.hasPrimaryModifier
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
