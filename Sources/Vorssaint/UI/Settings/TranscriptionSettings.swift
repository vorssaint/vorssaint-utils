// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// Native Vorssaint Settings page for Audio Transcription (Parakeet Unified English 0.6B).
struct TranscriptionSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = AudioTranscriptionService.shared
    @AppStorage(DefaultsKey.meetingRecorderAutoTranscribe) private var autoTranscribe = false
    @AppStorage(DefaultsKey.audioTranscriptionIncludeTimestamps) private var includeTimestamps = true
    @AppStorage(DefaultsKey.audioTranscriptionSaveBesideAudio) private var saveBesideAudio = true
    @AppStorage(DefaultsKey.audioTranscriptionComputeMode) private var computeModeRaw = ParakeetComputeMode.auto.rawValue
    @AppStorage(DefaultsKey.panelUtilityAudioTranscription) private var showInPanel = true
    @State private var isDropTargeted = false

    private var strings: AudioTranscriptionFeatureStrings {
        FeatureStrings.audioTranscription(l10n.language)
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
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView {
                            Text(service.transcriptText)
                                .font(.callout)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 80, maxHeight: 180)
                        HStack(spacing: 8) {
                            Button(strings.copyButton) { service.copyTranscript() }
                            Button(strings.saveButton) { service.saveTranscriptAs() }
                            if service.lastSavedTranscriptURL != nil {
                                Button(strings.revealButton) { service.revealSavedTranscript() }
                            }
                            Spacer()
                            Button(strings.clearButton) { service.clearTranscript() }
                        }
                    }
                }
            } header: {
                Text(strings.title)
            }

            Section {
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
