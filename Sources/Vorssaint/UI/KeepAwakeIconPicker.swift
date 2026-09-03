// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct KeepAwakeIconPicker: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var iconValue: String
    @Binding var tintValue: String
    var compact = false
    /// Non-nil only when hosted in the panel: wires each swatch into
    /// keyboard navigation under this section. Settings hosts the same
    /// picker without it.
    var keyboardSection: PanelSectionID? = nil

    private var selectedIcon: KeepAwakeActiveIcon {
        Defaults.sanitizedKeepAwakeActiveIcon(iconValue)
    }

    private var selectedTint: KeepAwakeIconTint {
        Defaults.sanitizedKeepAwakeIconTint(tintValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            choiceHeader(l10n.s.keepAwakeActiveIconLabel,
                         value: selectedIcon.title(l10n.s))

            HStack(spacing: compact ? 5 : 7) {
                ForEach(KeepAwakeActiveIcon.allCases) { icon in
                    iconButton(icon)
                }
            }
            .panelKeyboardRowGroup(iconRowIDs)

            choiceHeader(l10n.s.keepAwakeIconTintLabel,
                         value: selectedTint.title(l10n.s))

            HStack(spacing: compact ? 6 : 8) {
                ForEach(KeepAwakeIconTint.allCases) { tint in
                    tintButton(tint)
                }
            }
            .panelKeyboardRowGroup(tintRowIDs)
        }
        .padding(compact ? 8 : 0)
        .background {
            if compact {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.secondary.opacity(0.055))
            }
        }
    }

    private var iconRowIDs: [PanelRowID] {
        guard let keyboardSection else { return [] }
        return KeepAwakeActiveIcon.allCases.map { PanelRowID(keyboardSection, "keepAwakeIcon-\($0.rawValue)") }
    }

    private var tintRowIDs: [PanelRowID] {
        guard let keyboardSection else { return [] }
        return KeepAwakeIconTint.allCases.map { PanelRowID(keyboardSection, "keepAwakeTint-\($0.rawValue)") }
    }

    private func choiceHeader(_ title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: compact ? 10.5 : 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func iconButton(_ icon: KeepAwakeActiveIcon) -> some View {
        let selected = icon == selectedIcon
        return Button {
            iconValue = icon.rawValue
        } label: {
            iconGlyph(icon, selected: selected)
        }
        .buttonStyle(.plain)
        .help(icon.title(l10n.s))
        .accessibilityLabel(icon.title(l10n.s))
        .panelKeyboardRow(keyboardSection.map { PanelRowID($0, "keepAwakeIcon-\(icon.rawValue)") },
                          actions: PanelRowActions(activate: { iconValue = icon.rawValue }))
    }

    /// Split out of `iconButton` so its background/overlay ternaries (and the
    /// row registration appended alongside them) don't all sit in the one
    /// expression the type checker has to solve at once.
    private func iconGlyph(_ icon: KeepAwakeActiveIcon, selected: Bool) -> some View {
        Group {
            if let image = BlackHoleGlyph.activeImage(style: icon, tint: selectedTint) {
                Image(nsImage: image)
                    .renderingMode(selectedTint == .none ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: "circle.fill")
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: 21, maxHeight: compact ? 14 : 16)
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 29 : 35)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.14)
                               : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.75)
                                       : Color.secondary.opacity(0.13),
                              lineWidth: selected ? 1.2 : 1)
        )
        .contentShape(Rectangle())
    }

    private func tintButton(_ tint: KeepAwakeIconTint) -> some View {
        let selected = tint == selectedTint
        return Button {
            tintValue = tint.rawValue
        } label: {
            tintGlyph(tint, selected: selected)
        }
        .buttonStyle(.plain)
        .help(tint.title(l10n.s))
        .accessibilityLabel(tint.title(l10n.s))
        .panelKeyboardRow(keyboardSection.map { PanelRowID($0, "keepAwakeTint-\(tint.rawValue)") },
                          actions: PanelRowActions(activate: { tintValue = tint.rawValue }))
    }

    /// Split out of `tintButton` for the same reason as `iconGlyph`.
    private func tintGlyph(_ tint: KeepAwakeIconTint, selected: Bool) -> some View {
        ZStack {
            if let color = tintColor(tint) {
                Circle()
                    .fill(color)
                    .frame(width: compact ? 12 : 14, height: compact ? 12 : 14)
            } else {
                Circle()
                    .strokeBorder(Color.secondary, lineWidth: 1.2)
                    .frame(width: compact ? 12 : 14, height: compact ? 12 : 14)
                Image(systemName: "slash")
                    .font(.system(size: compact ? 8 : 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 24 : 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.7) : Color.clear,
                              lineWidth: 1.1)
        )
        .contentShape(Rectangle())
    }

    private func tintColor(_ tint: KeepAwakeIconTint) -> Color? {
        switch tint {
        case .orange: return .orange
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .none: return nil
        }
    }
}
