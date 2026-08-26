// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct KeyOverrideSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = KeyOverrideService.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.keyOverridesEnabled) private var enabled = true
    @State private var overrides: [KeyOverride] = []
    @State private var recordingID: UUID?
    @State private var recordErrorID: UUID?
    @State private var recordError: String?

    private var text: KeyOverrideStrings { FeatureStrings.keyOverrides(l10n.language) }

    var body: some View {
        Form {
            Section(text.pageTitle) {
                Toggle(text.enableToggle, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        KeyOverrideService.shared.syncWithPreferences()
                    }
                Text(text.intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if service.mappingFailed {
                    Label(text.mappingFailedNote, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !service.registrationFailed.isEmpty {
                    Label(text.shortcutTakenNote, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if overrides.isEmpty {
                    Text(text.emptyState)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach($overrides) { $override in
                    row($override)
                }
                HStack {
                    addMenu
                    if overrides.isEmpty {
                        commonSetButton
                    }
                    Spacer()
                }
                Text(text.remapNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            if enabled, KeyOverrideSupport.needsAccessibility(overrides),
               !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    // MARK: - Rows

    private func row(_ override: Binding<KeyOverride>) -> some View {
        let value = override.wrappedValue
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Picker("", selection: keyBinding(override)) {
                    ForEach(availableKeys(for: value), id: \.self) { key in
                        Text(keyName(key)).tag(key)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Picker("", selection: actionKindBinding(override)) {
                    ForEach(KeyOverrideActionKind.allCases, id: \.self) { kind in
                        Text(actionName(kind)).tag(kind)
                    }
                }
                .labelsHidden()
                .fixedSize()
                if value.action.kind == .pressShortcut {
                    ShortcutRecorderButton(
                        shortcut: value.action.shortcut ?? .keepAwakeDefault,
                        isEnabled: enabled && value.isEnabled,
                        waitingTitle: l10n.s.shortcutPressKeys,
                        emptyTitle: value.action.shortcut == nil
                            ? l10n.s.shortcutPressKeys : nil,
                        recordingChanged: { recording in
                            recordingID = recording ? value.id : nil
                            if recording { setRecordError(nil, for: value.id) }
                        },
                        invalidAction: {
                            setRecordError(l10n.s.shortcutInvalid, for: value.id)
                        },
                        captureAction: { shortcut in
                            override.wrappedValue.action.shortcut = shortcut
                            save()
                        }
                    )
                    .frame(width: 108)
                }
                Spacer()
                Toggle("", isOn: enabledBinding(override))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Button {
                    remove(value.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(text.removeButton)
                .accessibilityLabel(text.removeButton)
            }
            if let recordError, recordErrorID == value.id {
                Text(recordError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if recordingID == value.id {
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if value.action.kind == .micMute, !features.isAvailable(.micMute) {
                Text(text.micMuteNeedsFeature)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var addMenu: some View {
        Menu(text.addButton) {
            ForEach(remainingKeys, id: \.self) { key in
                Button(keyName(key)) { add(key) }
            }
        }
        .fixedSize()
        .disabled(remainingKeys.isEmpty)
    }

    private var commonSetButton: some View {
        Button(text.commonSetButton) {
            overrides = KeyOverrideSupport.sanitized(KeyOverrideSupport.commonOverrides())
            save()
        }
        .help(text.commonSetCaption)
    }

    // MARK: - Names

    /// A special key shows its purpose and its plain key. An upper F key shows only its label.
    private func keyName(_ key: KeyOverrideKey) -> String {
        let purpose: String?
        switch key {
        case .missionControl: purpose = text.keyMissionControl
        case .spotlight: purpose = text.keySpotlight
        case .dictation: purpose = text.keyDictation
        case .focus: purpose = text.keyFocus
        case .launchpad: purpose = text.keyLaunchpad
        case .f13, .f14, .f15, .f16, .f17, .f19, .f20: purpose = nil
        }
        guard let purpose else { return key.functionKeyLabel }
        return "\(purpose) (\(key.functionKeyLabel))"
    }

    private func actionName(_ kind: KeyOverrideActionKind) -> String {
        switch kind {
        case .remapOnly: return text.actionRemapOnly
        case .micMute: return text.actionMicMute
        case .pressShortcut: return text.actionPressShortcut
        }
    }

    // MARK: - Choices

    /// Spotlight and Launchpad share F4. A key is free when no other row uses its key code.
    private func availableKeys(for override: KeyOverride) -> [KeyOverrideKey] {
        let taken = Set(overrides.filter { $0.id != override.id }.map(\.key.keyCode))
        return KeyOverrideKey.allCases.filter {
            $0 == override.key || !taken.contains($0.keyCode)
        }
    }

    private var remainingKeys: [KeyOverrideKey] {
        let taken = Set(overrides.map(\.key.keyCode))
        return KeyOverrideKey.allCases.filter { !taken.contains($0.keyCode) }
    }

    // MARK: - Bindings

    private func keyBinding(_ override: Binding<KeyOverride>) -> Binding<KeyOverrideKey> {
        Binding {
            override.wrappedValue.key
        } set: { key in
            override.wrappedValue.key = key
            save()
        }
    }

    private func actionKindBinding(_ override: Binding<KeyOverride>)
        -> Binding<KeyOverrideActionKind> {
        Binding {
            override.wrappedValue.action.kind
        } set: { kind in
            let shortcut = kind == .pressShortcut
                ? override.wrappedValue.action.shortcut : nil
            override.wrappedValue.action = KeyOverrideAction(kind: kind, shortcut: shortcut)
            save()
        }
    }

    private func enabledBinding(_ override: Binding<KeyOverride>) -> Binding<Bool> {
        Binding {
            override.wrappedValue.isEnabled
        } set: { on in
            override.wrappedValue.isEnabled = on
            save()
        }
    }

    // MARK: - Persistence

    private func load() {
        overrides = KeyOverrideSupport.decode(
            UserDefaults.standard.data(forKey: DefaultsKey.keyOverrides))
    }

    private func save() {
        overrides = KeyOverrideSupport.sanitized(overrides)
        if let data = KeyOverrideSupport.encode(overrides) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.keyOverrides)
        }
        KeyOverrideService.shared.syncWithPreferences()
    }

    private func add(_ key: KeyOverrideKey) {
        let action: KeyOverrideAction = key == .dictation ? .micMute : .remapOnly
        overrides.append(KeyOverride(key: key, action: action))
        save()
    }

    private func remove(_ id: UUID) {
        overrides.removeAll { $0.id == id }
        save()
    }

    private func setRecordError(_ message: String?, for id: UUID) {
        recordError = message
        recordErrorID = message == nil ? nil : id
    }
}
