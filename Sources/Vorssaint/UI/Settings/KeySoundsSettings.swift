// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct KeySoundsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = KeySoundsService.shared
    @AppStorage(DefaultsKey.keySoundsEnabled) private var enabled = false
    @AppStorage(DefaultsKey.keySoundsPack) private var packID = Defaults.defaultKeySoundsPack
    @AppStorage(DefaultsKey.keySoundsVolume) private var volume = Defaults.defaultKeySoundsVolume
    @AppStorage(DefaultsKey.keySoundsVelocityEnabled) private var velocity = true
    @AppStorage(DefaultsKey.keySoundsSensitivity) private var sensitivity = 1.0
    @AppStorage(DefaultsKey.keySoundsReleaseEnabled) private var release = true
    @AppStorage(DefaultsKey.keySoundsMuteModifiers) private var muteModifiers = false
    @AppStorage(DefaultsKey.keySoundsBuiltInSpeakersOnly) private var builtInOnly = false
    @AppStorage(DefaultsKey.keySoundsShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.keySoundsShortcut) private var shortcutRaw = GlobalShortcut.keySoundsDefault.storageValue

    private var t: KeySoundsStrings { FeatureStrings.keySounds(l10n.language) }

    var body: some View {
        Form {
            Section(t.title) {
                Toggle(t.enable, isOn: Binding(
                    get: { enabled },
                    set: { service.setEnabled($0) }))
                Text(t.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, service.isRunning {
                    Label(t.active, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section(t.switchSection) {
                if service.packs.isEmpty {
                    Text(t.noPacks).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Picker(t.switchLabel, selection: Binding(
                            get: { service.selectedPack()?.id ?? packID },
                            set: { packID = $0; sync() })) {
                            ForEach(service.packs) { pack in
                                Text(pack.name).tag(pack.id)
                            }
                        }
                        Button(t.preview) {
                            if let pack = service.selectedPack() { service.preview(pack) }
                        }
                    }
                }
                HStack {
                    Text(t.volume)
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $volume, in: Defaults.allowedKeySoundsVolumeRange) { editing in if !editing { sync() } }
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
            }
            .disabled(!enabled && service.packs.isEmpty)

            Section(t.feelSection) {
                Toggle(t.velocity, isOn: $velocity)
                    .onChange(of: velocity) { _, _ in sync() }
                Text(t.velocityCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if velocity {
                    HStack {
                        Text(t.sensitivity)
                        Slider(value: $sensitivity, in: Defaults.allowedKeySoundsSensitivityRange) { editing in
                            if !editing { sync() }
                        }
                        Text(String(format: "%.1f×", locale: Locale(identifier: l10n.language.rawValue), sensitivity))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    if enabled {
                        sensorStatus
                    }
                }
                Toggle(t.release, isOn: $release)
                    .onChange(of: release) { _, _ in sync() }
                Text(t.releaseCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(t.muteModifiers, isOn: $muteModifiers)
                    .onChange(of: muteModifiers) { _, _ in sync() }
                Toggle(t.builtInOnly, isOn: $builtInOnly)
                    .onChange(of: builtInOnly) { _, _ in sync() }
                Text(t.builtInOnlyCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(t.shortcutSection) {
                Toggle(t.shortcutEnable, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in sync() }
                HStack {
                    Text(t.shortcutTitle)
                    Spacer()
                    ShortcutRecorderButton(
                        shortcut: GlobalShortcut(storageValue: shortcutRaw) ?? GlobalShortcut.keySoundsDefault,
                        isEnabled: shortcutEnabled,
                        waitingTitle: l10n.s.shortcutPressKeys,
                        recordingChanged: { recording in
                            if recording { service.suspendShortcut() } else { sync() }
                        },
                        invalidAction: {},
                        captureAction: { shortcut in
                            shortcutRaw = shortcut.storageValue
                            sync()
                        })
                        .frame(width: 150)
                }
                if shortcutEnabled, service.shortcutRegistrationFailed {
                    Text(t.shortcutFailed)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }

            Section {
                Text(t.credits)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .onAppear { service.reloadPacks() }
    }

    @ViewBuilder private var sensorStatus: some View {
        switch service.sensorState {
        case .running:
            HStack {
                Label(t.sensorRunning, systemImage: "waveform.path.ecg")
                    .foregroundStyle(.green)
                Spacer()
                if let strength = service.lastStrength {
                    Text("\(t.lastHit): \(t.strength(strength))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        case .unavailable:
            Label(t.sensorUnavailable, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .off:
            EmptyView()
        }
    }

    private func sync() { service.syncWithPreferences() }
}

/// The one-click tile in the menu bar panel's quick controls.
struct KeySoundsPanelRow: View {
    let editing: Bool
    @Binding var visibility: Bool
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = KeySoundsService.shared
    @AppStorage(DefaultsKey.keySoundsEnabled) private var enabled = false

    private var t: KeySoundsStrings { FeatureStrings.keySounds(l10n.language) }

    var body: some View {
        PanelToggleRow(title: t.title,
                       caption: caption,
                       systemImage: "speaker.wave.2.circle",
                       isOn: Binding(get: { enabled }, set: { service.setEnabled($0) }),
                       isEditing: editing,
                       showsDragHandle: true,
                       visibility: $visibility,
                       needsAttention: enabled && !permissions.accessibility,
                       permissionButtonTitle: l10n.s.permissionRequest,
                       permissionAction: enabled && !permissions.accessibility
                           ? { Permissions.shared.requestAccessibility()
                               Permissions.shared.openAccessibilitySettings() }
                           : nil)
    }

    private var caption: String {
        guard enabled, let pack = service.selectedPack() else { return t.panelCaption }
        return pack.name
    }
}
