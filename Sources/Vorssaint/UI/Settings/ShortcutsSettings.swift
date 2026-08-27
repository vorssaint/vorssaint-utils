// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The central editor for every global shortcut belonging to an installed
/// feature. It writes the same preferences as each feature page, so there is
/// still one setting and one registration path for every action.
struct ShortcutsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var superKey = SuperKeyService.shared
    @State private var expandedFeatures: Set<AppFeature> = [.screenshot]

    private var text: ShortcutSettingsStrings { FeatureStrings.shortcuts(l10n.language) }
    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }

    private var availableRoles: [GlobalShortcutRole] {
        GlobalShortcutRole.availableRoles(isAvailable: { $0.isAvailable })
    }

    private var captureRoles: [GlobalShortcutRole] {
        GlobalShortcutRole.captureRoles(in: availableRoles)
    }

    private var visibleGroups: [FeatureGroup] {
        FeatureGroup.allCases.filter { group in
            availableRoles.contains { $0.feature.group == group }
                || (group == .windowsDock && AppFeature.windowLayout.isAvailable)
        }
    }

    var body: some View {
        Form {
            Section {
                Text(l10n.s.shortcutsPageCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(visibleGroups, id: \.self) { group in
                Section(groupTitle(group)) {
                    ForEach(featuresWithShortcuts(in: group), id: \.self) { feature in
                        if feature == .screenshot {
                            captureGroupRows
                        } else if feature == .soundOutputSwitcher {
                            featureRows(feature)
                                .settingsSectionAnchor(.soundOutputSwitcher)
                        } else {
                            featureRows(feature)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func featuresWithShortcuts(in group: FeatureGroup) -> [AppFeature] {
        AppFeature.features(in: group).filter { feature in
            // The screenshot slot anchors the combined capture group; the
            // other capture tools render inside it instead of on their own.
            if feature == .screenshot { return !captureRoles.isEmpty }
            if GlobalShortcutRole.captureFeatures.contains(feature) { return false }
            return (feature.isAvailable || availableRoles.contains { $0.feature == feature })
                && (feature == .windowLayout || availableRoles.contains { $0.feature == feature })
        }
    }

    /// One group for every capture tool's shortcut. Rows keep each tool's own
    /// icon; the group carries the shared page's name and symbol.
    @ViewBuilder
    private var captureGroupRows: some View {
        let roles = captureRoles
        disclosureHeader(
            title: FeatureStrings.screenshot(l10n.language).screenCaptureTitle,
            symbolName: AppFeature.screenshot.symbolName,
            isActive: featureHasActiveShortcut(.screenshot, roles: roles),
            count: roles.count,
            isExpanded: expansionBinding(for: .screenshot))
        if expandedFeatures.contains(.screenshot) {
            ForEach(roles) { role in
                roleRow(role, showsFeatureContext: false)
                    .disclosureIndent()
            }
        }
    }

    @ViewBuilder
    private func featureRows(_ feature: AppFeature) -> some View {
        let roles = availableRoles.filter { $0.feature == feature }
        let count = feature == .windowLayout ? WindowLayoutAction.shortcutActions.count : roles.count
        if count > 1 {
            disclosureHeader(
                title: feature.hubTitle(l10n.s, hub: hub),
                symbolName: feature.symbolName,
                isActive: featureHasActiveShortcut(feature, roles: roles),
                count: count,
                isExpanded: expansionBinding(for: feature))
            if expandedFeatures.contains(feature) {
                if feature == .windowLayout {
                    ForEach(WindowLayoutAction.shortcutActions) { action in
                        CentralWindowLayoutShortcutRow(
                            action: action,
                            shortcutsEnabled: UserDefaults.standard.bool(
                                forKey: DefaultsKey.windowLayoutShortcutsEnabled),
                            showsSuperKeyAlternative: superKey.isRunning,
                            superKeyModifiers: superKey.modifiers,
                            text: text
                        )
                        .disclosureIndent()
                    }
                } else {
                    ForEach(roles) { role in
                        roleRow(role, showsFeatureContext: false)
                            .disclosureIndent()
                    }
                }
            }
        } else if let role = roles.first {
            roleRow(role)
        }
    }

    private func disclosureHeader(title: String,
                                  symbolName: String,
                                  isActive: Bool,
                                  count: Int,
                                  isExpanded: Binding<Bool>) -> some View {
        DisclosureHeaderRow(isExpanded: isExpanded) {
            ShortcutRowLabel(
                title: title,
                symbolName: symbolName,
                contextLabel: nil,
                statusText: isActive ? text.active : text.inactive,
                statusIsActive: isActive
            )
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }

    private func roleRow(_ role: GlobalShortcutRole,
                         showsFeatureContext: Bool = true) -> some View {
        let title = role.title(l10n.s)
        let featureTitle = role.feature.hubTitle(l10n.s, hub: hub)
        let active = role.requiredEnableKeys.allSatisfy {
            UserDefaults.standard.bool(forKey: $0)
        }
        return ShortcutPreferenceRow(
            role: role,
            label: title,
            symbolName: role.feature.symbolName,
            contextLabel: showsFeatureContext && title != featureTitle ? featureTitle : nil,
            statusText: active ? text.active : text.inactive,
            statusIsActive: active,
            showsSuperKeyAlternative: superKey.isRunning,
            superKeyModifiers: superKey.modifiers,
            includeInactiveConflicts: true,
            additionalConflict: { shortcut in
                guard AppFeature.windowLayout.isAvailable else { return nil }
                return WindowLayoutService.shared.shortcutConflictTitle(shortcut, excluding: nil)
            },
            onChange: {
                FeatureRuntime.shared.sync([role.feature])
            }
        )
    }

    private func expansionBinding(for feature: AppFeature) -> Binding<Bool> {
        Binding {
            expandedFeatures.contains(feature)
        } set: { expanded in
            if expanded {
                expandedFeatures.insert(feature)
            } else {
                expandedFeatures.remove(feature)
            }
        }
    }

    private func featureHasActiveShortcut(_ feature: AppFeature,
                                          roles: [GlobalShortcutRole]) -> Bool {
        if feature == .windowLayout {
            return UserDefaults.standard.bool(forKey: DefaultsKey.windowLayoutShortcutsEnabled)
                && WindowLayoutAction.shortcutActions.contains { $0.savedShortcut != nil }
        }
        return roles.contains { role in
            role.requiredEnableKeys.allSatisfy { UserDefaults.standard.bool(forKey: $0) }
        }
    }

    private func groupTitle(_ group: FeatureGroup) -> String {
        switch group {
        case .windowsDock: return hub.groupWindowsDock
        case .mouseKeyboard: return hub.groupMouseKeyboard
        case .clipboardFiles: return hub.groupClipboardFiles
        case .sound: return hub.groupSound
        case .energyDisplay: return hub.groupEnergyDisplay
        case .tools: return hub.groupTools
        case .monitor: return hub.groupMonitor
        }
    }
}

private struct CentralWindowLayoutShortcutRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var superKey = SuperKeyService.shared
    let action: WindowLayoutAction
    let shortcutsEnabled: Bool
    let showsSuperKeyAlternative: Bool
    let superKeyModifiers: GlobalShortcutModifiers
    let text: ShortcutSettingsStrings
    @AppStorage private var rawValue: String
    @State private var errorText: String?
    @State private var isRecording = false

    init(action: WindowLayoutAction,
         shortcutsEnabled: Bool,
         showsSuperKeyAlternative: Bool,
         superKeyModifiers: GlobalShortcutModifiers,
         text: ShortcutSettingsStrings) {
        self.action = action
        self.shortcutsEnabled = shortcutsEnabled
        self.showsSuperKeyAlternative = showsSuperKeyAlternative
        self.superKeyModifiers = superKeyModifiers
        self.text = text
        _rawValue = AppStorage(
            wrappedValue: action.defaultShortcut?.storageValue
                ?? WindowLayoutAction.clearedShortcutStorageValue,
            action.shortcutKey
        )
    }

    private var windowText: WindowLayoutFeatureStrings {
        FeatureStrings.windowLayout(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                ShortcutRowLabel(
                    title: action.title(windowText),
                    symbolName: AppFeature.windowLayout.symbolName,
                    contextLabel: nil,
                    statusText: isActive ? text.active : text.inactive,
                    statusIsActive: isActive
                )
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        ShortcutRecorderButton(
                            shortcut: shortcut ?? action.defaultShortcut ?? .windowLayoutLeftDefault,
                            isEnabled: true,
                            waitingTitle: l10n.s.shortcutPressKeys,
                            emptyTitle: shortcut == nil ? l10n.s.shortcutNone : nil,
                            clearAction: clear,
                            notCapturedAction: { errorText = l10n.s.shortcutNotCaptured },
                            recordingChanged: { recording in
                                isRecording = recording
                                if recording { errorText = nil }
                            },
                            invalidAction: { errorText = l10n.s.shortcutInvalid },
                            captureAction: save
                        )
                        .frame(width: 108)
                        Button {
                            clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(shortcut == nil)
                        .help(l10n.s.shortcutClear)
                        .accessibilityLabel(l10n.s.shortcutClear)
                        Button(l10n.s.shortcutReset) {
                            rawValue = action.defaultShortcut?.storageValue
                                ?? WindowLayoutAction.clearedShortcutStorageValue
                            errorText = nil
                            WindowLayoutService.shared.syncWithPreferences()
                        }
                        .disabled(shortcut == action.defaultShortcut)
                    }
                    if let alternative = superKeyAlternative {
                        Text(String(format: text.superKeyAlternativeFormat, alternative))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(alternative)
                    }
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isRecording {
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: true))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: l10n.language) { _, _ in errorText = nil }
    }

    private var shortcut: GlobalShortcut? {
        WindowLayoutAction.resolvedShortcut(storedValue: rawValue,
                                            defaultShortcut: action.defaultShortcut)
    }

    private var isActive: Bool {
        shortcutsEnabled && shortcut != nil
    }

    private var superKeyAlternative: String? {
        guard showsSuperKeyAlternative, let shortcut else { return nil }
        return shortcut.superKeyAlternative(
            sourceLabel: FeatureStrings.superKey(l10n.language).sourceLabel(superKey.source),
            superKeyModifiers: superKeyModifiers)
    }

    private func clear() {
        rawValue = WindowLayoutAction.clearedShortcutStorageValue
        errorText = nil
        WindowLayoutService.shared.syncWithPreferences()
    }

    private func save(_ shortcut: GlobalShortcut) {
        if let conflict = GlobalShortcutRole.conflict(for: shortcut,
                                                      excluding: nil,
                                                      includeInactive: true) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict.title(l10n.s))
            return
        }
        if shortcut.conflictsWithSystemShortcut {
            errorText = String(format: l10n.s.shortcutConflictFormat, "macOS")
            return
        }
        if let conflict = WindowLayoutService.shared.shortcutConflictTitle(shortcut,
                                                                           excluding: action) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
        rawValue = shortcut.storageValue
        errorText = nil
        WindowLayoutService.shared.syncWithPreferences()
    }
}
