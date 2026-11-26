// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Native Vorssaint Settings page for Meeting Recorder.
struct MeetingRecorderSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = MeetingRecorderService.shared
    @AppStorage(DefaultsKey.meetingRecorderAutoRecord) private var autoRecord = false
    @AppStorage(DefaultsKey.meetingRecorderAutoTranscribe) private var autoTranscribe = false
    @AppStorage(DefaultsKey.meetingRecorderPerAppAudio) private var perAppAudio = false
    @AppStorage(DefaultsKey.meetingRecorderEchoCancellation) private var echoCancellation = true
    @AppStorage(DefaultsKey.meetingRecorderShowIndicator) private var showIndicator = true
    @AppStorage(DefaultsKey.meetingRecorderSaveFolder) private var saveFolder = ""
    @AppStorage(DefaultsKey.panelUtilityMeetingRecorder) private var showInPanel = true

    private var strings: MeetingRecorderFeatureStrings {
        FeatureStrings.meetingRecorder(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Button {
                        service.toggleManualRecording()
                    } label: {
                        Label(service.isRecording ? strings.stopButton : strings.startButton,
                              systemImage: service.isRecording ? "stop.circle" : "record.circle")
                    }
                    if service.isRecording {
                        Button {
                            service.togglePause()
                        } label: {
                            Label(service.isPaused ? strings.resumeButton : strings.pauseButton,
                                  systemImage: service.isPaused ? "play.circle" : "pause.circle")
                        }
                        Button(role: .destructive) {
                            service.discardRecording()
                        } label: {
                            Label(strings.discardButton, systemImage: "trash")
                        }
                    }
                }
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let error = service.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let warning = service.warningMessage {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if permissions.microphone != .granted {
                    PermissionRow(kind: .microphone)
                }
                if service.systemAudioPermission != .granted && service.systemAudioPermission != .unavailable {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(strings.systemAudioPermTitle)
                            Text(strings.systemAudioPermCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(strings.grantButton) {
                            service.requestSystemAudioPermission()
                        }
                    }
                }
            } header: {
                Text(strings.title)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(strings.autoRecordToggle, isOn: $autoRecord)
                        .onChange(of: autoRecord) { _, _ in
                            service.syncWithPreferences()
                        }
                    Text(strings.autoRecordCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(FeatureStrings.audioTranscription(l10n.language).autoTranscribeToggle, isOn: $autoTranscribe)
                    Text(FeatureStrings.audioTranscription(l10n.language).autoTranscribeCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(strings.perAppToggle, isOn: $perAppAudio)
                    Text(strings.perAppCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(strings.echoCancelToggle, isOn: $echoCancellation)
                    Text(strings.echoCancelCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(strings.indicatorToggle, isOn: $showIndicator)
                        .onChange(of: showIndicator) { _, _ in
                            service.syncWithPreferences()
                        }
                    Text(strings.indicatorCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                folderRow
                Toggle(strings.showInPanelToggle, isOn: $showInPanel)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            service.refreshAudioPermission()
            permissions.refresh()
        }
    }

    private var statusLine: String {
        if service.isRecording {
            let timer = MeetingRecorderSupport.elapsedLabel(seconds: service.elapsedSeconds)
            if let app = service.detectedAppName {
                return "\(String(format: strings.recordingAppFormat, app)) · \(timer)"
            }
            return timer
        }
        return service.isListeningForCalls ? strings.listeningCaption : strings.panelCaption
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
                    service.refreshRecordings()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }
            Button(strings.openFolder) {
                service.openSaveFolder()
            }
            Button(strings.folderChoose) {
                chooseFolder()
            }
        }
    }

    private var currentFolderName: String {
        let url = service.saveFolderURL
        return FileManager.default.displayName(atPath: url.path)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url.path
            service.refreshRecordings()
        }
    }
}
