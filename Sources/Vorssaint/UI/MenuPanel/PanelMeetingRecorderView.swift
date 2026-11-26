// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Inline Vorssaint menu panel surface for Meeting Recorder: live dual-track
/// controls, automatic call-recording toggle, audio level bars, and
/// recent saved recordings.
struct PanelMeetingRecorderView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = MeetingRecorderService.shared
    @ObservedObject private var transcription = AudioTranscriptionService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.meetingRecorderAutoRecord) private var autoRecord = false
    @AppStorage(DefaultsKey.meetingRecorderAutoTranscribe) private var autoTranscribe = false

    var onClose: () -> Void

    private var strings: MeetingRecorderFeatureStrings {
        FeatureStrings.meetingRecorder(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            recorderCard
            recentSection
        }
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
            service.setMeterObserving(true)
            service.refreshAudioPermission()
            service.refreshRecordings()
            permissions.refresh()
        }
        .onDisappear {
            service.setMeterObserving(false)
            PanelInteractionState.shared.viewKeepsPopoverOpen = false
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(strings.title, systemImage: "waveform.circle")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                service.openSaveFolder()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(strings.openFolder)
            .accessibilityLabel(strings.openFolder)
            Button {
                SettingsRouter.shared.page = .meetingRecorder
                appDelegate()?.openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuSettings)
            .accessibilityLabel(l10n.s.menuSettings)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.uninstallerCancel)
        }
    }

    private var recorderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Text(statusSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if service.isRecording {
                    Text(MeetingRecorderSupport.elapsedLabel(seconds: service.elapsedSeconds))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(service.isPaused ? .secondary : .primary)
                }
            }

            if service.isRecording {
                VStack(spacing: 5) {
                    if service.systemTrackActive {
                        levelRow(label: strings.systemTrackLabel, samples: service.systemLevels, tint: .accentColor)
                    }
                    if service.micTrackActive {
                        levelRow(label: strings.micTrackLabel, samples: service.micLevels, tint: .green)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 6) {
                Button {
                    service.toggleManualRecording()
                } label: {
                    Label(service.isRecording ? strings.stopButton : strings.startButton,
                          systemImage: service.isRecording ? "stop.fill" : "record.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(service.isRecording ? .red : .accentColor)
                .controlSize(.small)

                if service.isRecording {
                    Button {
                        service.togglePause()
                    } label: {
                        Image(systemName: service.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 24, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(service.isPaused ? strings.resumeButton : strings.pauseButton)

                    Button {
                        service.discardRecording()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 24, height: 18)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(strings.discardButton)
                }
            }

            if let error = service.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let warning = service.warningMessage {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if permissions.microphone != .granted || service.systemAudioPermission != .granted {
                HStack(spacing: 6) {
                    if permissions.microphone != .granted {
                        Button(AppPermission.microphone.name(FeatureStrings.hub(l10n.language))) {
                            if permissions.microphone == .undetermined {
                                permissions.requestMicrophone()
                            } else {
                                permissions.openMicrophoneSettings()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    if service.systemAudioPermission != .granted && service.systemAudioPermission != .unavailable {
                        Button(strings.systemAudioPermTitle) {
                            service.requestSystemAudioPermission()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }

            Divider()

            Toggle(isOn: $autoRecord) {
                Text(strings.autoRecordToggle)
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .onChange(of: autoRecord) { _, _ in
                service.syncWithPreferences()
            }

            Toggle(isOn: $autoTranscribe) {
                Text(FeatureStrings.audioTranscription(l10n.language).autoTranscribeToggle)
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .panelCard()
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(strings.recentHeader)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            if service.recentRecordings.isEmpty {
                Text(strings.emptyRecent)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .panelCard()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(service.recentRecordings) { item in
                            recordingRow(item)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private func recordingRow(_ item: MeetingRecorderSupport.RecordingSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.createdAt, style: .relative)
                    Text(trackSummary(item))
                    Text(ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if service.transcriptURL(for: item) != nil {
                Button {
                    service.openTranscript(item)
                } label: {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(FeatureStrings.audioTranscription(l10n.language).openTranscriptTooltip)
            } else {
                Button {
                    service.transcribe(item)
                } label: {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(transcription.isTranscribing)
                .help(FeatureStrings.audioTranscription(l10n.language).transcribeMeetingTooltip)
            }
            Button {
                service.reveal(item)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10.5))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(strings.revealInFinder)
            Button {
                service.delete(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(strings.deleteRecording)
        }
        .panelCard()
    }

    private func levelRow(label: String, samples: [Float], tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, value in
                    let normalized = min(max(Double(value) * 3.0, 0.12), 1.0)
                    Capsule()
                        .fill(tint.opacity(value > 0.01 ? 0.85 : 0.2))
                        .frame(maxWidth: .infinity)
                        .frame(height: CGFloat(normalized * 12.0))
                }
            }
            .frame(height: 12)
        }
    }

    private var statusDotColor: Color {
        if service.isRecording {
            return service.isPaused ? .orange : .red
        }
        return service.isListeningForCalls ? .green : .secondary.opacity(0.4)
    }

    private var statusTitle: String {
        if service.isRecording {
            if let app = service.detectedAppName {
                return String(format: strings.recordingAppFormat, app)
            }
            return strings.title
        }
        return service.isListeningForCalls ? strings.listeningCaption : strings.title
    }

    private var statusSubtitle: String {
        if service.isRecording {
            return service.isPaused ? strings.pauseButton : trackSummary(system: service.systemTrackActive,
                                                                         mic: service.micTrackActive)
        }
        return strings.panelCaption
    }

    private func trackSummary(_ item: MeetingRecorderSupport.RecordingSummary) -> String {
        trackSummary(system: item.hasSystemTrack, mic: item.hasMicTrack)
    }

    private func trackSummary(system: Bool, mic: Bool) -> String {
        switch (system, mic) {
        case (true, true): return "\(strings.systemTrackLabel) + \(strings.micTrackLabel)"
        case (true, false): return strings.systemTrackLabel
        case (false, true): return strings.micTrackLabel
        case (false, false): return ""
        }
    }
}
