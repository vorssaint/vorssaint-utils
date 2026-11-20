// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct KeystrokeOverlaySettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var overlay = KeystrokeOverlayService.shared

    @AppStorage(DefaultsKey.keystrokeOverlayEnabled) private var enabled = false
    @AppStorage(DefaultsKey.keystrokeOverlayStyle) private var styleRaw = KeystrokeOverlayStyle.svelte.rawValue
    @AppStorage(DefaultsKey.keystrokeOverlayMode) private var modeRaw = KeystrokeOverlayMode.allKeys.rawValue
    @AppStorage(DefaultsKey.keystrokeOverlayPosition) private var positionRaw = KeystrokeOverlayPosition.bottomCenter.rawValue
    @AppStorage(DefaultsKey.keystrokeOverlaySize) private var sizeRaw = KeystrokeOverlaySize.medium.rawValue
    @AppStorage(DefaultsKey.keystrokeOverlayDuration) private var duration = KeystrokeOverlayConfig.defaultDurationSeconds
    @AppStorage(DefaultsKey.keystrokeOverlayShowInCaptures) private var showInCaptures = true

    private var strings: KeystrokeOverlayStrings {
        FeatureStrings.keystrokeOverlay(l10n.language)
    }

    var body: some View {
        Form {
            Section(strings.pageTitle) {
                Toggle(strings.enableToggle, isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        KeystrokeOverlayService.shared.syncWithPreferences()
                        guard value, !permissions.accessibility else { return }
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
                    }
                Text(strings.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, overlay.isRunning {
                    Label(strings.activeNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Label(strings.privacyNote, systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(strings.styleLabel, selection: styleBinding) {
                    ForEach(KeystrokeOverlayStyle.allCases) { style in
                        Text(strings.styleName(style)).tag(style)
                    }
                }

                Picker(strings.modeLabel, selection: modeBinding) {
                    Text(strings.modeAllKeys).tag(KeystrokeOverlayMode.allKeys)
                    Text(strings.modeShortcutsOnly).tag(KeystrokeOverlayMode.modeShortcutsTag)
                }
                Text(strings.modeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(strings.positionLabel, selection: positionBinding) {
                    ForEach(KeystrokeOverlayPosition.allCases) { position in
                        Text(strings.positionName(position)).tag(position)
                    }
                }
                Text(strings.dragPositionCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if overlay.hasCustomPosition {
                    Button {
                        KeystrokeOverlayService.shared.resetCustomPosition()
                    } label: {
                        Label(strings.resetPositionButton, systemImage: "arrow.counterclockwise")
                    }
                }

                Picker(strings.sizeLabel, selection: sizeBinding) {
                    ForEach(KeystrokeOverlaySize.allCases) { size in
                        Text(strings.sizeName(size)).tag(size)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(strings.durationLabel)
                        Spacer()
                        Text(String(format: strings.durationSecondsFormat,
                                    KeystrokeOverlayConfig.sanitizedDuration(duration)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: durationBinding,
                           in: KeystrokeOverlayConfig.durationRange,
                           step: 0.1)
                }

                Toggle(strings.showInCapturesToggle, isOn: $showInCaptures)
                    .onChange(of: showInCaptures) { _, _ in
                        KeystrokeOverlayService.shared.syncWithPreferences()
                    }
                Text(strings.showInCapturesCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    KeystrokeOverlayService.shared.showPreview()
                } label: {
                    Label(strings.previewButton, systemImage: "keyboard.badge.eye")
                }
            }

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            duration = KeystrokeOverlayConfig.sanitizedDuration(duration)
        }
    }

    private var styleBinding: Binding<KeystrokeOverlayStyle> {
        Binding {
            KeystrokeOverlayStyle.sanitized(styleRaw)
        } set: { value in
            styleRaw = value.rawValue
            KeystrokeOverlayService.shared.syncWithPreferences()
        }
    }

    private var modeBinding: Binding<KeystrokeOverlayMode> {
        Binding {
            KeystrokeOverlayMode.sanitized(modeRaw)
        } set: { value in
            modeRaw = value.rawValue
            KeystrokeOverlayService.shared.syncWithPreferences()
        }
    }

    private var positionBinding: Binding<KeystrokeOverlayPosition> {
        Binding {
            KeystrokeOverlayPosition.sanitized(positionRaw)
        } set: { value in
            positionRaw = value.rawValue
            KeystrokeOverlayService.shared.resetCustomPosition()
        }
    }

    private var sizeBinding: Binding<KeystrokeOverlaySize> {
        Binding {
            KeystrokeOverlaySize.sanitized(sizeRaw)
        } set: { value in
            sizeRaw = value.rawValue
            KeystrokeOverlayService.shared.syncWithPreferences()
        }
    }

    private var durationBinding: Binding<Double> {
        Binding {
            KeystrokeOverlayConfig.sanitizedDuration(duration)
        } set: { value in
            duration = KeystrokeOverlayConfig.sanitizedDuration(value)
            KeystrokeOverlayService.shared.syncWithPreferences()
        }
    }
}

private extension KeystrokeOverlayMode {
    static var modeShortcutsTag: KeystrokeOverlayMode { .shortcutsOnly }
}
