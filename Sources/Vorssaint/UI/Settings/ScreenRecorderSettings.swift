// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Settings for the screen recorder: how a recording starts, what it captures
/// and where the file lands. Everything a person rarely touches sits behind
/// one disclosure, so the page reads at a glance.
struct ScreenRecorderSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = ScreenRecorderService.shared
    @AppStorage(DefaultsKey.recorderShortcutEnabled) private var shortcutEnabled = false
    @AppStorage(DefaultsKey.recorderCountdown) private var countdown = 3
    @AppStorage(DefaultsKey.recorderQuality) private var qualityRaw =
        RecorderSupport.Quality.balanced.rawValue
    @AppStorage(DefaultsKey.recorderFrameRate) private var frameRate = 60
    @AppStorage(DefaultsKey.recorderSystemAudio) private var systemAudio = true
    @AppStorage(DefaultsKey.recorderSaveFolder) private var saveFolder = ""
    @AppStorage(DefaultsKey.recorderOpenEditor) private var opensEditor = true
    @AppStorage(DefaultsKey.recorderGIFSize) private var gifSizeRaw =
        RecorderSupport.GIFSize.medium.rawValue
    @AppStorage(DefaultsKey.recorderGIFFrameRate) private var gifFrameRate = 12
    @State private var showsMoreOptions = false

    private var strings: RecorderFeatureStrings {
        FeatureStrings.recorder(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                Button {
                    ScreenRecorderService.shared.toggle()
                } label: {
                    Label(service.isRecording ? strings.stopButton : strings.startButton,
                          systemImage: service.isRecording ? "stop.circle" : "record.circle")
                }
                Text(service.isRecording
                     ? RecorderSupport.elapsedLabel(seconds: service.elapsedSeconds)
                     : strings.panelCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in
                        ScreenRecorderService.shared.syncWithPreferences()
                    }
                ShortcutPreferenceRow(role: .screenRecorder,
                                      isEnabled: shortcutEnabled) {
                    ScreenRecorderService.shared.syncWithPreferences()
                }
                if shortcutEnabled, service.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !permissions.screenRecording {
                    PermissionRow(kind: .screenRecording)
                }
                if !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                }
            } header: {
                Text(strings.pageTitle)
            }

            Section {
                Picker(strings.countdownLabel, selection: $countdown) {
                    ForEach(ScreenshotSupport.allowedDelays, id: \.self) { seconds in
                        if seconds == 0 {
                            Text(strings.countdownOff).tag(0)
                        } else {
                            Text(String(format: strings.countdownSecondsFormat, seconds)).tag(seconds)
                        }
                    }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(strings.systemAudioToggle, isOn: $systemAudio)
                    Text(strings.systemAudioCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(strings.openEditorToggle, isOn: $opensEditor)
                    Text(strings.openEditorCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                folderRow
                DisclosureGroup(strings.moreOptions, isExpanded: $showsMoreOptions) {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker(strings.qualityLabel, selection: $qualityRaw) {
                            Text(strings.qualitySmall).tag(RecorderSupport.Quality.small.rawValue)
                            Text(strings.qualityBalanced).tag(RecorderSupport.Quality.balanced.rawValue)
                            Text(strings.qualityHigh).tag(RecorderSupport.Quality.high.rawValue)
                        }
                        Text(strings.qualityCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker(strings.frameRateLabel, selection: $frameRate) {
                        ForEach(RecorderSupport.frameRates, id: \.self) { rate in
                            Text(String(format: strings.frameRateFormat, rate)).tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker(strings.gifSizeLabel, selection: $gifSizeRaw) {
                        Text(strings.gifSizeSmall).tag(RecorderSupport.GIFSize.small.rawValue)
                        Text(strings.gifSizeMedium).tag(RecorderSupport.GIFSize.medium.rawValue)
                        Text(strings.gifSizeLarge).tag(RecorderSupport.GIFSize.large.rawValue)
                    }
                    .pickerStyle(.segmented)
                    Picker(strings.gifFrameRateLabel, selection: $gifFrameRate) {
                        ForEach(RecorderSupport.gifFrameRates, id: \.self) { rate in
                            Text(String(format: strings.frameRateFormat, rate)).tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var folderRow: some View {
        HStack {
            Text(strings.folderLabel)
            Spacer()
            Text(currentFolderName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if !saveFolder.isEmpty {
                Button {
                    saveFolder = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .screenshotSafeHelp(l10n.s.shortcutReset)
            }
            Button(strings.folderChoose) {
                chooseFolder()
            }
        }
    }

    private var currentFolderName: String {
        let manager = FileManager.default
        if !saveFolder.isEmpty {
            let expanded = (saveFolder as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return manager.displayName(atPath: expanded)
            }
        }
        let desktop = manager.urls(for: .desktopDirectory, in: .userDomainMask).first
        return desktop.map { manager.displayName(atPath: $0.path) } ?? "Desktop"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url.path
        }
    }
}
