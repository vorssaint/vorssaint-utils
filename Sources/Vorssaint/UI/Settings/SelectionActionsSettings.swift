// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct SelectionActionsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = SelectionActionsService.shared
    @AppStorage(DefaultsKey.selectionActionsEnabled) private var enabled = false
    @AppStorage(DefaultsKey.selectionActionsShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.selectionActionsEnabledActions) private var enabledActionsRaw = ""
    @AppStorage(DefaultsKey.selectionActionsDisplayStyle) private var displayStyleRaw = "icon"
    @AppStorage(DefaultsKey.selectionActionsMaxVisible) private var maxVisible = 8
    /// Read only so this view redraws when the drag order changes; the order
    /// itself is read and written through `PanelLayout`.
    @AppStorage(DefaultsKey.selectionActionsOrder) private var orderRaw = ""
    @State private var draggingAction: SelectionAction?

    private var text: SelectionActionsStrings { FeatureStrings.selectionActions(l10n.language) }

    private var displayStyle: SelectionActionsDisplayStyle {
        SelectionActionsDisplayStyle.sanitized(displayStyleRaw)
    }

    private var orderedActions: [SelectionAction] {
        _ = orderRaw
        return PanelLayout.itemOrder(SelectionAction.self, key: DefaultsKey.selectionActionsOrder)
    }

    private var orderBinding: Binding<[SelectionAction]> {
        Binding {
            orderedActions
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.selectionActionsOrder)
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(text.enableToggleTitle, isOn: $enabled)
                    .onChange(of: enabled) { _, isOn in
                        if isOn, !permissions.accessibility {
                            Permissions.shared.requestAccessibility()
                        }
                        SelectionActionsService.shared.syncWithPreferences()
                    }
                Text(text.enableToggleCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, !permissions.accessibility {
                    Label(text.permissionBody, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(text.permissionButton) {
                        Permissions.shared.openAccessibilitySettings()
                    }
                }
                Picker(text.displayStyleLabel, selection: displayStyleBinding) {
                    Text(text.displayStyleIcon).tag(SelectionActionsDisplayStyle.icon)
                    Text(text.displayStyleWord).tag(SelectionActionsDisplayStyle.word)
                }
                .pickerStyle(.segmented)
                .disabled(!enabled)
                Stepper(value: $maxVisible, in: 1...SelectionAction.allCases.count) {
                    HStack {
                        Text(text.maxVisibleLabel)
                        Spacer()
                        Text("\(maxVisible)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(text.maxVisibleCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in
                        SelectionActionsService.shared.syncWithPreferences()
                    }
                    .disabled(!enabled)
                ShortcutPreferenceRow(role: .selectionActions, isEnabled: enabled && shortcutEnabled) {
                    SelectionActionsService.shared.syncWithPreferences()
                }
                if shortcutEnabled, service.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(text.pageTitle)
            }

            Section {
                SelectionActionsExcludedAppsList()
                SelectionActionsExcludedDomainsList()
            } header: {
                Text(text.excludedSectionTitle)
            }

            Section {
                VStack(spacing: 0) {
                    ForEach(orderedActions) { action in
                        PanelReorderableItem(item: action,
                                             order: orderBinding,
                                             dragging: $draggingAction) {
                            SelectionActionRow(action: action, strings: text,
                                              enabledActionsRaw: $enabledActionsRaw)
                        }
                        if action != orderedActions.last {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text(text.actionsSectionTitle)
            } footer: {
                Text(text.actionsSectionCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var displayStyleBinding: Binding<SelectionActionsDisplayStyle> {
        Binding {
            displayStyle
        } set: { newValue in
            displayStyleRaw = newValue.rawValue
        }
    }
}

/// One row: drag handle, icon, name, an ⓘ describing what it does, then —
/// only when the action has something to configure — a gear opening its own
/// settings, and always, at the end, the plain on/off switch.
private struct SelectionActionRow: View {
    let action: SelectionAction
    let strings: SelectionActionsStrings
    @Binding var enabledActionsRaw: String
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 8) {
            PanelDragHandle()
            Image(systemName: action.symbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(strings.title(for: action))
                .font(.system(size: 13))
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fastTooltip(strings.description(for: action))
            Spacer(minLength: 8)
            if action.hasSettings {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .popover(isPresented: $showingSettings) {
                    settingsPopover
                }
            }
            Toggle("", isOn: enabledBinding)
                .labelsHidden()
        }
        .frame(minHeight: 32)
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            SelectionActionCatalog.isEnabled(action, enabledRaw: enabledActionsRaw)
        } set: { isOn in
            var current = SelectionActionCatalog.enabledActions(from: enabledActionsRaw)
            if isOn { current.insert(action) } else { current.remove(action) }
            enabledActionsRaw = SelectionActionCatalog.storageValue(for: current)
        }
    }

    @ViewBuilder
    private var settingsPopover: some View {
        switch action {
        default: EmptyView()
        }
    }
}
