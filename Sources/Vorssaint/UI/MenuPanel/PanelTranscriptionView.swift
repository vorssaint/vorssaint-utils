// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// Inline Vorssaint menu panel utility for Audio Transcription: drag-and-drop
/// audio files onto Parakeet Unified English 0.6B, copy/save transcripts, and
/// toggle automatic meeting transcription.
struct PanelTranscriptionView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = AudioTranscriptionService.shared
    @AppStorage(DefaultsKey.meetingRecorderAutoTranscribe) private var autoTranscribe = false
    @AppStorage(DefaultsKey.audioTranscriptionSummaryEnabled) private var summaryEnabled = false
    @AppStorage(DefaultsKey.audioTranscriptionModelChoice) private var modelChoiceRaw = TranscriptionModelChoice.auto.rawValue
    @State private var isDropTargeted = false

    var onClose: () -> Void

    private var strings: AudioTranscriptionFeatureStrings {
        FeatureStrings.audioTranscription(l10n.language)
    }
    private var extras: AudioTranscriptionExtrasStrings {
        FeatureStrings.audioTranscriptionExtras(l10n.language)
    }
    private var modelStrings: TranscriptionModelStrings {
        FeatureStrings.transcriptionModels(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            dropAndStatusCard
            if !service.transcriptText.isEmpty {
                transcriptCard
            }
            if service.isSummarizing || !service.summaryText.isEmpty {
                summaryCard
            }
            if !service.recentTranscripts.isEmpty {
                recentSection
            }
        }
        .onAppear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = true
            service.refreshModelStatus()
        }
        .onDisappear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = false
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(strings.title, systemImage: "captions.bubble")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                SettingsRouter.shared.page = .audioTranscription
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

    private var dropAndStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            dropZone

            Picker(modelStrings.modelChoiceLabel, selection: $modelChoiceRaw) {
                Text(modelStrings.modelAuto).tag(TranscriptionModelChoice.auto.rawValue)
                Text(modelStrings.modelParakeet).tag(TranscriptionModelChoice.parakeetEnglish.rawValue)
                Text(modelStrings.modelIvrit).tag(TranscriptionModelChoice.ivritHebrew.rawValue)
            }
            .pickerStyle(.menu)
            .controlSize(.mini)
            .font(.system(size: 10.5))

            if service.isDownloadingModel {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(format: strings.downloadingStatusFormat,
                                    Int((service.downloadProgress * 100).rounded())))
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                        Spacer()
                        Button(strings.cancelButton) {
                            service.cancelDownload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    ProgressView(value: service.downloadProgress)
                        .progressViewStyle(.linear)
                }
            } else if modelChoiceRaw != TranscriptionModelChoice.ivritHebrew.rawValue, !service.modelReady {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(strings.modelTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(strings.modelMissingStatus)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(strings.downloadModelButton) {
                        service.downloadModel()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }

            if service.isDownloadingIvritModel {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(format: strings.downloadingStatusFormat,
                                    Int((service.ivritDownloadProgress * 100).rounded())))
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                        Spacer()
                        Button(strings.cancelButton) {
                            service.cancelIvritDownload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    ProgressView(value: service.ivritDownloadProgress)
                        .progressViewStyle(.linear)
                }
            } else if modelChoiceRaw != TranscriptionModelChoice.parakeetEnglish.rawValue, !service.ivritModelReady {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(modelStrings.ivritModelTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(modelStrings.ivritModelMissingStatus)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(strings.downloadModelButton) {
                        service.downloadIvritModel()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }

            if service.isTranscribing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(format: strings.transcribingFormat, service.currentFileName ?? ""))
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Button(strings.cancelButton) {
                            service.cancelTranscription()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    ProgressView(value: service.progress)
                        .progressViewStyle(.linear)
                }
            }

            if let error = service.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 8) {
                if service.isDictating {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                    Text(String(format: extras.dictatingStatusFormat,
                                MeetingRecorderSupport.elapsedLabel(seconds: service.dictationElapsedSeconds)))
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                    Spacer()
                    Button(extras.stopDictationButton) {
                        service.toggleSystemDictation()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    Button(strings.cancelButton) {
                        service.cancelDictation()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else {
                    Button {
                        service.toggleSystemDictation()
                    } label: {
                        Label(extras.startDictationButton, systemImage: "mic.fill")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(service.isTranscribing || service.isDownloadingActiveModel)
                    Spacer()
                    Text(GlobalShortcutRole.voiceDictation.savedShortcut.displayString)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $autoTranscribe) {
                Text(strings.autoTranscribeToggle)
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Toggle(isOn: $summaryEnabled) {
                Text(extras.summaryToggle)
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .panelCard()
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: isDropTargeted ? "waveform.circle.fill" : "arrow.down.doc")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
            Text(strings.dropTitle)
                .font(.system(size: 11, weight: .semibold))
            Text(strings.dropSubtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(strings.chooseFileButton) {
                service.chooseAudioFile()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.primary.opacity(0.14),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(service.currentFileName ?? strings.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if service.lastDurationSeconds > 0, service.lastProcessingSeconds > 0 {
                    let rtfx = service.lastDurationSeconds / max(0.01, service.lastProcessingSeconds)
                    let dur = MeetingRecorderSupport.elapsedLabel(seconds: Int(service.lastDurationSeconds.rounded()))
                    Text("\(dur) · \(Int(rtfx.rounded()))×")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            let isRTL = AudioTranscriptionSupport.isPredominantlyHebrew(service.transcriptText)
            ScrollView {
                Text(service.transcriptText)
                    .font(.system(size: 10.5))
                    .textSelection(.enabled)
                    .multilineTextAlignment(isRTL ? .trailing : .leading)
                    .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                    .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            }
            .frame(maxHeight: 150)

            HStack(spacing: 6) {
                Button(strings.copyButton) {
                    service.copyTranscript()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)

                Button(strings.saveButton) {
                    service.saveTranscriptAs()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(service.summaryText.isEmpty ? extras.summarizeButton : extras.regenerateSummaryButton) {
                    service.summarizeCurrentTranscript()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(service.isSummarizing)

                if service.lastSavedTranscriptURL != nil {
                    Button {
                        service.revealSavedTranscript()
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(strings.revealButton)
                }

                Spacer()

                Button(strings.clearButton) {
                    service.clearTranscript()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
        .panelCard()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(extras.summaryTitle, systemImage: "text.badge.star")
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer()
                if service.isSummarizing {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            if service.isSummarizing {
                Text(extras.summarizingStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                let summaryRTL = AudioTranscriptionSupport.isPredominantlyHebrew(service.summaryText)
                ScrollView {
                    Text(service.summaryText)
                        .font(.system(size: 10.5))
                        .textSelection(.enabled)
                        .multilineTextAlignment(summaryRTL ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: summaryRTL ? .trailing : .leading)
                        .environment(\.layoutDirection, summaryRTL ? .rightToLeft : .leftToRight)
                }
                .frame(maxHeight: 120)

                HStack(spacing: 6) {
                    Button(extras.copySummaryButton) {
                        service.copySummary()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)

                    Button(extras.saveSummaryButton) {
                        service.saveSummaryAs()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Spacer()

                    Button(extras.regenerateSummaryButton) {
                        service.summarizeCurrentTranscript()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .panelCard()
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(strings.recentHeader)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(service.recentTranscripts.prefix(5)) { item in
                Button {
                    service.selectRecent(item)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                            Text(item.text)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .panelCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let direct = item as? URL {
                url = direct
            } else {
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async {
                service.transcribeFile(url)
            }
        }
        return true
    }
}
