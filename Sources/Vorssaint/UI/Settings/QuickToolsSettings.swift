// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct QuickToolsSettings: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var micMute = MicMuteService.shared
    @ObservedObject private var launcher = QuickLauncherService.shared
    @ObservedObject private var cameraPreview = CameraPreviewService.shared
    @ObservedObject private var scratchpad = ScratchpadService.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @AppStorage(DefaultsKey.quickLauncherShortcutEnabled) private var launcherShortcutEnabled = true
    @AppStorage(DefaultsKey.micMuteShortcutEnabled) private var micShortcutEnabled = false
    @AppStorage(DefaultsKey.cameraPreviewShortcutEnabled) private var cameraShortcutEnabled = false
    @AppStorage(DefaultsKey.scratchpadShortcutEnabled) private var scratchpadShortcutEnabled = false
    @AppStorage(DefaultsKey.scratchpadRetention) private var scratchpadRetention = ScratchpadRetention.never.rawValue
    @AppStorage(DefaultsKey.scratchpadCloseOnClickOutside) private var scratchpadCloseOnClickOutside = true
    @AppStorage(DefaultsKey.scratchpadBackgroundOpacity) private var scratchpadBackgroundOpacity = 0.0
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
                .settingsSectionAnchor(.quickLauncher)
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
                    if brightness.keyboardLightEnabled != nil {
                        Toggle(isOn: Binding(
                            get: { brightness.keyboardLightEnabled ?? false },
                            set: { brightness.setKeyboardLightEnabled($0) }
                        )) {
                            Label(FeatureStrings.brightness(l10n.language).keyboardLight,
                                  systemImage: "keyboard")
                        }
                    }
                    DiskExclusionsList()
                    Text(FeatureStrings.quickToggles(l10n.language).panelCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(FeatureStrings.quickToggles(l10n.language).pageTitle)
                }
                .settingsSectionAnchor(.quickToggles)
                .onAppear { brightness.refreshKeyboardLight() }
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
                .settingsSectionAnchor(.micMute)
            }

            if AppFeature.cameraPreview.isAvailable {
                Section {
                    Button {
                        CameraPreviewService.shared.show()
                    } label: {
                        Label(FeatureStrings.cameraPreview(l10n.language).openButton,
                              systemImage: "web.camera")
                    }
                    Text(FeatureStrings.cameraPreview(l10n.language).panelCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(l10n.s.quickToolShortcutToggle, isOn: $cameraShortcutEnabled)
                        .onChange(of: cameraShortcutEnabled) { _, _ in
                            CameraPreviewService.shared.syncWithPreferences()
                        }
                    ShortcutPreferenceRow(role: .cameraPreview,
                                          isEnabled: cameraShortcutEnabled) {
                        CameraPreviewService.shared.syncWithPreferences()
                    }
                    if cameraShortcutEnabled, cameraPreview.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if permissions.camera == .denied {
                        CameraPermissionRow()
                    }
                } header: {
                    Text(FeatureStrings.cameraPreview(l10n.language).pageTitle)
                }
                .settingsSectionAnchor(.cameraPreview)
            }

            if AppFeature.scratchpad.isAvailable {
                Section {
                    Button {
                        ScratchpadService.shared.show()
                    } label: {
                        Label(FeatureStrings.scratchpad(l10n.language).openButton,
                              systemImage: "note.text")
                    }
                    Text(FeatureStrings.scratchpad(l10n.language).panelCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(FeatureStrings.scratchpad(l10n.language).retentionTitle,
                           selection: $scratchpadRetention) {
                        Text(FeatureStrings.scratchpad(l10n.language).retentionNever)
                            .tag(ScratchpadRetention.never.rawValue)
                        Text(FeatureStrings.scratchpad(l10n.language).retentionDay)
                            .tag(ScratchpadRetention.day.rawValue)
                        Text(FeatureStrings.scratchpad(l10n.language).retentionWeek)
                            .tag(ScratchpadRetention.week.rawValue)
                        Text(FeatureStrings.scratchpad(l10n.language).retentionMonth)
                            .tag(ScratchpadRetention.month.rawValue)
                    }
                    Text(FeatureStrings.scratchpad(l10n.language).retentionCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(FeatureStrings.scratchpad(l10n.language).closeOnClickOutside,
                           isOn: $scratchpadCloseOnClickOutside)
                        .onChange(of: scratchpadCloseOnClickOutside) { _, _ in
                            ScratchpadService.shared.outsideClickPreferenceDidChange()
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(FeatureStrings.scratchpad(l10n.language).backgroundOpacity)
                        Slider(value: scratchpadBackgroundOpacityBinding,
                               in: ScratchpadSupport.backgroundOpacityRange,
                               step: 0.05)
                        HStack {
                            Text(FeatureStrings.scratchpad(l10n.language).backgroundTranslucent)
                            Spacer()
                            Text(FeatureStrings.scratchpad(l10n.language).backgroundOpaque)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Toggle(l10n.s.quickToolShortcutToggle, isOn: $scratchpadShortcutEnabled)
                        .onChange(of: scratchpadShortcutEnabled) { _, _ in
                            ScratchpadService.shared.syncWithPreferences()
                        }
                    ShortcutPreferenceRow(role: .scratchpad,
                                          isEnabled: scratchpadShortcutEnabled) {
                        ScratchpadService.shared.syncWithPreferences()
                    }
                    if scratchpadShortcutEnabled, scratchpad.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text(FeatureStrings.scratchpad(l10n.language).pageTitle)
                }
                .settingsSectionAnchor(.scratchpad)
            }
        }
        .formStyle(.grouped)
    }

    private var scratchpadBackgroundOpacityBinding: Binding<Double> {
        Binding(
            get: { ScratchpadSupport.sanitizedBackgroundOpacity(scratchpadBackgroundOpacity) },
            set: { scratchpadBackgroundOpacity = ScratchpadSupport.sanitizedBackgroundOpacity($0) }
        )
    }
}

/// The camera state has no re-prompt once denied, so the row goes straight
/// to System Settings instead of offering a dead request button.
private struct CameraPermissionRow: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(FeatureStrings.cameraPreview(l10n.language).permName)
                Spacer()
                Text(l10n.s.permissionMissing)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button(l10n.s.permissionOpenSettings) {
                Permissions.shared.openCameraSettings()
            }
            .controlSize(.small)
        }
    }
}
