// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// Native Vorssaint Settings page for Audio Transcription (Parakeet Unified English 0.6B).
struct TranscriptionSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = AudioTranscriptionService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.meetingRecorderAutoTranscribe) private var autoTranscribe = false
    @AppStorage(DefaultsKey.audioTranscriptionIncludeTimestamps) private var includeTimestamps = true
    @AppStorage(DefaultsKey.audioTranscriptionSaveBesideAudio) private var saveBesideAudio = true
    @AppStorage(DefaultsKey.audioTranscriptionComputeMode) private var computeModeRaw = ParakeetComputeMode.auto.rawValue
    @AppStorage(DefaultsKey.audioTranscriptionModelChoice) private var modelChoiceRaw = TranscriptionModelChoice.auto.rawValue
    @AppStorage(DefaultsKey.audioTranscriptionSummaryEnabled) private var summaryEnabled = false
    @AppStorage(DefaultsKey.audioTranscriptionSummaryPrompt) private var summaryPrompt = AudioTranscriptionSupport.defaultSummaryPrompt
    @AppStorage(DefaultsKey.audioTranscriptionDictationEnabled) private var dictationEnabled = false
    @AppStorage(DefaultsKey.panelUtilityAudioTranscription) private var showInPanel = true
    @State private var isDropTargeted = false

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
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: isDropTargeted ? "waveform.circle.fill" : "arrow.down.doc")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                    Text(strings.dropTitle)
                        .font(.headline)
                    Text(strings.dropSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(strings.chooseFileButton) {
                        service.chooseAudioFile()
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                        )
                )
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }

                if service.isTranscribing {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(format: strings.transcribingFormat, service.currentFileName ?? ""))
                                .font(.caption)
                            Spacer()
                            Button(strings.cancelButton) {
                                service.cancelTranscription()
                            }
                            .controlSize(.small)
                        }
                        ProgressView(value: service.progress)
                    }
                }

                if let error = service.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !service.transcriptText.isEmpty {
                    let isRTL = AudioTranscriptionSupport.isPredominantlyHebrew(service.transcriptText)
                    VStack(alignment: .leading, spacing: 8) {
                        if let detected = detectedLanguageLabel {
                            Text(String(format: modelStrings.detectedLanguageFormat, detected))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ScrollView {
                            Text(service.transcriptText)
                                .font(.callout)
                                .textSelection(.enabled)
                                .multilineTextAlignment(isRTL ? .trailing : .leading)
                                .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                        }
                        .frame(minHeight: 80, maxHeight: 180)
                        HStack(spacing: 8) {
                            Button(strings.copyButton) { service.copyTranscript() }
                            Button(strings.saveButton) { service.saveTranscriptAs() }
                            Button(service.summaryText.isEmpty ? extras.summarizeButton : extras.regenerateSummaryButton) {
                                service.summarizeCurrentTranscript()
                            }
                            .disabled(service.isSummarizing)
                            if service.lastSavedTranscriptURL != nil {
                                Button(strings.revealButton) { service.revealSavedTranscript() }
                            }
                            Spacer()
                            Button(strings.clearButton) { service.clearTranscript() }
                        }
                    }
                }

                if service.isSummarizing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(extras.summarizingStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !service.summaryText.isEmpty {
                    let summaryRTL = AudioTranscriptionSupport.isPredominantlyHebrew(service.summaryText)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(extras.summaryTitle, systemImage: "text.badge.star")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if !service.summaryUsedOnDeviceLLM {
                                Text(extras.summaryFallbackNote)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ScrollView {
                            Text(service.summaryText)
                                .font(.callout)
                                .textSelection(.enabled)
                                .multilineTextAlignment(summaryRTL ? .trailing : .leading)
                                .frame(maxWidth: .infinity, alignment: summaryRTL ? .trailing : .leading)
                                .environment(\.layoutDirection, summaryRTL ? .rightToLeft : .leftToRight)
                        }
                        .frame(minHeight: 60, maxHeight: 150)
                        HStack(spacing: 8) {
                            Button(extras.copySummaryButton) { service.copySummary() }
                            Button(extras.saveSummaryButton) { service.saveSummaryAs() }
                            Spacer()
                            Button(extras.regenerateSummaryButton) {
                                service.summarizeCurrentTranscript()
                            }
                        }
                    }
                }
            } header: {
                Text(strings.title)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(extras.dictationToggle, isOn: $dictationEnabled)
                        .onChange(of: dictationEnabled) { _, _ in
                            service.syncWithPreferences()
                        }
                    Text(extras.dictationCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ShortcutPreferenceRow(role: .voiceDictation,
                                      isEnabled: dictationEnabled,
                                      label: extras.dictationShortcutLabel) {
                    service.syncWithPreferences()
                }

                HStack(spacing: 10) {
                    if service.isDictating {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(String(format: extras.dictatingStatusFormat,
                                    MeetingRecorderSupport.elapsedLabel(seconds: service.dictationElapsedSeconds)))
                            .font(.caption)
                            .monospacedDigit()
                        Spacer()
                        Button(extras.stopDictationButton) {
                            service.toggleSystemDictation()
                        }
                        .buttonStyle(.borderedProminent)
                        Button(strings.cancelButton) {
                            service.cancelDictation()
                        }
                    } else {
                        Button {
                            service.toggleSystemDictation()
                        } label: {
                            Label(extras.startDictationButton, systemImage: "mic.fill")
                        }
                        .disabled(service.isTranscribing || service.isDownloadingModel)
                        Spacer()
                    }
                }

                if !permissions.accessibility {
                    Text(extras.dictationAccessibilityHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(extras.dictationSectionHeader)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(extras.summaryToggle, isOn: $summaryEnabled)
                    Text(extras.summaryCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(extras.summaryPromptLabel)
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button(extras.resetPromptButton) {
                            service.resetSummaryPrompt()
                        }
                        .controlSize(.small)
                        .disabled(summaryPrompt.trimmingCharacters(in: .whitespacesAndNewlines) == AudioTranscriptionSupport.defaultSummaryPrompt)
                    }
                    TextEditor(text: $summaryPrompt)
                        .font(.callout)
                        .frame(minHeight: 72, maxHeight: 120)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                }
            } header: {
                Text(extras.summarySectionHeader)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(modelStrings.modelChoiceLabel, selection: $modelChoiceRaw) {
                        Text(modelStrings.modelAuto).tag(TranscriptionModelChoice.auto.rawValue)
                        Text(modelStrings.modelParakeet).tag(TranscriptionModelChoice.parakeetEnglish.rawValue)
                        Text(modelStrings.modelIvrit).tag(TranscriptionModelChoice.ivritHebrew.rawValue)
                    }
                    Text(modelStrings.modelAutoCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strings.modelTitle)
                        Text(modelStatusSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if service.isDownloadingModel {
                        Button(strings.cancelButton) {
                            service.cancelDownload()
                        }
                    } else if service.modelReady {
                        Button(strings.deleteModelButton, role: .destructive) {
                            service.deleteModel()
                        }
                    } else {
                        Button(strings.downloadModelButton) {
                            service.downloadModel()
                        }
                    }
                }
                if service.isDownloadingModel {
                    ProgressView(value: service.downloadProgress)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(modelStrings.ivritModelTitle)
                        Text(ivritModelStatusSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if service.isDownloadingIvritModel {
                        Button(strings.cancelButton) {
                            service.cancelIvritDownload()
                        }
                    } else if service.ivritModelReady {
                        Button(strings.deleteModelButton, role: .destructive) {
                            service.deleteIvritModel()
                        }
                    } else {
                        Button(strings.downloadModelButton) {
                            service.downloadIvritModel()
                        }
                    }
                }
                if service.isDownloadingIvritModel {
                    ProgressView(value: service.ivritDownloadProgress)
                }

                Picker(strings.computeLabel, selection: $computeModeRaw) {
                    Text(strings.computeAuto).tag(ParakeetComputeMode.auto.rawValue)
                    Text(strings.computeGPU).tag(ParakeetComputeMode.cpuAndGPU.rawValue)
                    Text(strings.computeCPU).tag(ParakeetComputeMode.cpuOnly.rawValue)
                }
            } header: {
                Text(strings.modelSectionHeader)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(strings.autoTranscribeToggle, isOn: $autoTranscribe)
                    Text(strings.autoTranscribeCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle(strings.timestampsToggle, isOn: $includeTimestamps)
                Toggle(strings.saveBesideToggle, isOn: $saveBesideAudio)
                Toggle(strings.showInPanelToggle, isOn: $showInPanel)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            service.refreshModelStatus()
        }
    }

    private var modelStatusSubtitle: String {
        if service.isDownloadingModel {
            return String(format: strings.downloadingStatusFormat,
                          Int((service.downloadProgress * 100).rounded()))
        }
        if service.modelReady {
            let size = ByteCountFormatter.string(fromByteCount: service.modelDiskBytes, countStyle: .file)
            return "\(strings.modelReadyStatus) · \(size)"
        }
        return strings.modelMissingStatus
    }

    private var ivritModelStatusSubtitle: String {
        if service.isDownloadingIvritModel {
            return String(format: strings.downloadingStatusFormat,
                          Int((service.ivritDownloadProgress * 100).rounded()))
        }
        if service.ivritModelReady {
            let size = ByteCountFormatter.string(fromByteCount: service.ivritModelDiskBytes, countStyle: .file)
            return "\(strings.modelReadyStatus) · \(size)"
        }
        return modelStrings.ivritModelMissingStatus
    }

    private var detectedLanguageLabel: String? {
        switch service.lastDetectedLanguageCode {
        case "he": return modelStrings.languageHebrew
        case "en": return modelStrings.languageEnglish
        default: return nil
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
