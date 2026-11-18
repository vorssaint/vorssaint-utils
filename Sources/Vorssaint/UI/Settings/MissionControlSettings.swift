// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct MissionControlSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.missionControlActionsEnabled) private var enabled = false
    @AppStorage(DefaultsKey.missionControlRightClickAction) private var rightClickRaw =
        MissionControlAction.terminateApp.rawValue
    @AppStorage(DefaultsKey.missionControlMiddleClickAction) private var middleClickRaw =
        MissionControlAction.none.rawValue
    @AppStorage(DefaultsKey.missionControlKeyboardShortcutsEnabled) private var shortcutsEnabled = false

    private var text: MissionControlActionsStrings {
        FeatureStrings.missionControlActions(l10n.language)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(text.title).font(.title2.bold())
                    Text(text.pageDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SettingsCard {
                    SettingsRow(symbol: AppFeature.missionControlActions.symbolName,
                                title: text.enable, caption: text.enableCaption) {
                        Toggle(text.enable, isOn: $enabled)
                            .labelsHidden()
                            .accessibilityIdentifier("missionControl.enable")
                            .onChange(of: enabled) { _, value in
                                if value { Permissions.shared.requestAccessibility() }
                                MissionControlActionsService.shared.syncWithPreferences()
                            }
                    }
                    if enabled {
                        actionRow(symbol: "cursorarrow.click.2", title: text.rightClick,
                                  selection: $rightClickRaw)
                        actionRow(symbol: "computermouse", title: text.middleClick,
                                  selection: $middleClickRaw)
                        SettingsRow(symbol: "command", title: text.keyboardShortcuts,
                                    caption: text.keyboardShortcutsCaption) {
                            Toggle(text.keyboardShortcuts, isOn: $shortcutsEnabled)
                                .labelsHidden()
                                .onChange(of: shortcutsEnabled) { _, value in
                                    if value { Permissions.shared.requestAccessibility() }
                                    MissionControlActionsService.shared.syncWithPreferences()
                                }
                        }
                    }
                }
                SettingsCard {
                    Text(text.help)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if enabled, !permissions.accessibility {
                    SettingsCard(title: l10n.s.permissionRequired) {
                        PermissionRow(kind: .accessibility)
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .toggleStyle(.switch)
    }

    private func actionRow(symbol: String, title: String,
                           selection: Binding<String>) -> some View {
        SettingsRow(symbol: symbol, title: title) {
            Picker(title, selection: selection) {
                ForEach(MissionControlAction.allCases) { action in
                    Text(label(for: action)).tag(action.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 190)
            .onChange(of: selection.wrappedValue) { _, _ in
                MissionControlActionsService.shared.syncWithPreferences()
            }
        }
    }

    private func label(for action: MissionControlAction) -> String {
        switch action {
        case .none: return text.actionNone
        case .closeWindow: return text.actionCloseWindow
        case .minimizeWindow: return text.actionMinimizeWindow
        case .terminateApp: return text.actionTerminateApp
        case .hideApp: return text.actionHideApp
        }
    }
}
