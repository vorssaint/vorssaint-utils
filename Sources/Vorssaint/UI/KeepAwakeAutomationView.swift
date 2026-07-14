// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct KeepAwakeAutomationEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @AppStorage(DefaultsKey.keepAwakeExternalDisplay) private var externalDisplay = false
    @AppStorage(DefaultsKey.keepAwakeConnectedToPower) private var connectedToPower = false

    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .top, spacing: compact ? 6 : 8) {
                conditionTile(
                    title: strings.externalDisplayToggle,
                    icon: "display",
                    selected: externalDisplay
                ) {
                    externalDisplay.toggle()
                    awake.automationPreferencesDidChange()
                }
                conditionTile(
                    title: strings.powerToggle,
                    icon: "powerplug.fill",
                    selected: connectedToPower
                ) {
                    connectedToPower.toggle()
                    awake.automationPreferencesDidChange()
                }
            }
        }
    }

    private var strings: KeepAwakeAutomationStrings {
        FeatureStrings.keepAwakeAutomation(l10n.language)
    }

    private func conditionTile(title: String,
                               icon: String,
                               selected: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: compact ? 14 : 17, weight: .semibold))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: compact ? 11 : 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(title)
                    .font(.system(size: compact ? 10 : 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(compact ? 7 : 9)
            .frame(maxWidth: .infinity, minHeight: compact ? 65 : 78, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.32) : Color.primary.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

}
