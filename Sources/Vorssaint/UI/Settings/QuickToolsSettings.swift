// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct QuickToolsSettings: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var micMute = MicMuteService.shared
    @ObservedObject private var ocr = ScreenTextService.shared
    @ObservedObject private var colorSampler = ColorSamplerService.shared
    @ObservedObject private var launcher = QuickLauncherService.shared
    @AppStorage(DefaultsKey.quickLauncherShortcutEnabled) private var launcherShortcutEnabled = true
    @AppStorage(DefaultsKey.screenOCRShortcutEnabled) private var ocrShortcutEnabled = false
    @AppStorage(DefaultsKey.colorPickerShortcutEnabled) private var colorShortcutEnabled = false
    @AppStorage(DefaultsKey.micMuteShortcutEnabled) private var micShortcutEnabled = false
    @AppStorage(DefaultsKey.colorPickerFormat) private var colorFormat = "hex"
    @AppStorage(DefaultsKey.colorPickerBareHex) private var colorBareHex = false
    @AppStorage(DefaultsKey.micMuteMenuBarIndicator) private var micMenuBarIndicator = false

    var body: some View {
        Form {
            if AppFeature.quickLauncher.isAvailable {
                Section {
                    Button {
                        QuickLauncherService.shared.show()
                    } label: {
                        Label(l10n.s.launcherOpenNow, systemImage: "square.grid.2x2")
                    }
                    Text(l10n.s.launcherCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(l10n.s.launcherEditHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Toggle(l10n.s.quickToolShortcutToggle, isOn: $launcherShortcutEnabled)
                        .onChange(of: launcherShortcutEnabled) { _, _ in
                            QuickLauncherService.shared.syncWithPreferences()
                        }
                    ShortcutPreferenceRow(role: .quickLauncher,
                                          isEnabled: launcherShortcutEnabled) {
                        QuickLauncherService.shared.syncWithPreferences()
                    }
                    if launcherShortcutEnabled, launcher.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(l10n.s.launcherName)
                }
            }

            if AppFeature.quickToggles.isAvailable {
                Section {
                    Button {
                        QuickTogglesService.shared.toggleDarkMode()
                    } label: {
                        Label(colorScheme == .dark
                                ? FeatureStrings.quickToggles(l10n.language).darkModeToLight
                                : FeatureStrings.quickToggles(l10n.language).darkModeToDark,
                              systemImage: colorScheme == .dark ? "sun.max.fill" : "moon.fill")
                    }
                    Text(FeatureStrings.quickToggles(l10n.language).panelCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(FeatureStrings.quickToggles(l10n.language).pageTitle)
                }
            }

            if AppFeature.screenOCR.isAvailable {
                Section {
                    Button {
                        ScreenTextService.shared.capture()
                    } label: {
                        Label(l10n.s.ocrName, systemImage: "text.viewfinder")
                    }
                    Text(l10n.s.ocrCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(l10n.s.quickToolShortcutToggle, isOn: $ocrShortcutEnabled)
                        .onChange(of: ocrShortcutEnabled) { _, _ in
                            ScreenTextService.shared.syncWithPreferences()
                        }
                    ShortcutPreferenceRow(role: .screenOCR,
                                          isEnabled: ocrShortcutEnabled) {
                        ScreenTextService.shared.syncWithPreferences()
                    }
                    if ocrShortcutEnabled, ocr.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !permissions.screenRecording {
                        PermissionRow(kind: .screenRecording)
                    }
                } header: {
                    Text(l10n.s.ocrName)
                }
            }

            if AppFeature.colorPicker.isAvailable {
                Section {
                    Button {
                        ColorSamplerService.shared.pick()
                    } label: {
                        Label(l10n.s.colorPickerPickNow, systemImage: "eyedropper")
                    }
                    Text(l10n.s.colorPickerCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(l10n.s.colorPickerFormatLabel, selection: $colorFormat) {
                        ForEach(ColorCopyFormat.allCases) { format in
                            Text(format.label).tag(format.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    if colorFormat == ColorCopyFormat.hex.rawValue {
                        Toggle(l10n.s.colorPickerBareHexToggle, isOn: $colorBareHex)
                    }
                    Toggle(l10n.s.quickToolShortcutToggle, isOn: $colorShortcutEnabled)
                        .onChange(of: colorShortcutEnabled) { _, _ in
                            ColorSamplerService.shared.syncWithPreferences()
                        }
                    ShortcutPreferenceRow(role: .colorPicker,
                                          isEnabled: colorShortcutEnabled) {
                        ColorSamplerService.shared.syncWithPreferences()
                    }
                    if colorShortcutEnabled, colorSampler.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(l10n.s.colorPickerName)
                }
            }

            if AppFeature.micMute.isAvailable {
                Section {
                    Button {
                        MicMuteService.shared.toggle()
                    } label: {
                        Label(micMute.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName,
                              systemImage: micMute.isMuted ? "mic.slash.fill" : "mic")
                    }
                    if micMute.isMuted {
                        Label(l10n.s.micMutedHUD, systemImage: "mic.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(l10n.s.micMuteCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(l10n.s.micMuteMenuBarToggle, isOn: $micMenuBarIndicator)
                    Text(l10n.s.micMuteMenuBarCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(l10n.s.quickToolShortcutToggle, isOn: $micShortcutEnabled)
                        .onChange(of: micShortcutEnabled) { _, _ in
                            MicMuteService.shared.syncWithPreferences()
                        }
                    ShortcutPreferenceRow(role: .micMute,
                                          isEnabled: micShortcutEnabled) {
                        MicMuteService.shared.syncWithPreferences()
                    }
                    if micShortcutEnabled, micMute.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(l10n.s.micMuteName)
                }
            }
        }
        .formStyle(.grouped)
    }
}
