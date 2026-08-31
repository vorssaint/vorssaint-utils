// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import SwiftUI

struct DictationHistoryView: View {
    @State private var entries: [DictationHistoryEntry] = []
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?
    @State private var playbackRate = 1.0
    @State private var entryToDelete: DictationHistoryEntry?
    @State private var deleteAudioOnly = false
    @State private var retryingID: UUID?
    @State private var retryStatus: String?

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Nenhum ditado salvo",
                                       systemImage: "waveform",
                                       description: Text("As sessões aparecerão aqui quando o histórico estiver ativado."))
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(entry.createdAt, style: .date)
                            Text(entry.createdAt, style: .time)
                            Spacer()
                            Text(Self.duration(entry.duration))
                                .foregroundStyle(.secondary)
                        }
                        .font(.headline)
                        Text(entry.enhancedText ?? entry.rawText)
                            .lineLimit(3)
                        if entry.enhancedText != nil {
                            Text("Crua: \(entry.rawText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("Saída aprimorada")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let failure = entry.failure {
                            Label("Falha anterior: \(failure)", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        HStack(spacing: 10) {
                            Label(entry.language.displayName, systemImage: "globe")
                            Text(entry.model.id)
                                .foregroundStyle(.secondary)
                            if entry.audioFileName != nil {
                                Button(playingID == entry.id ? "Parar" : "Ouvir") {
                                    togglePlayback(entry)
                                }
                                .buttonStyle(.borderless)
                                Button {
                                    deleteAudioOnly = true
                                    entryToDelete = entry
                                } label: {
                                    Image(systemName: "waveform.slash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Apagar áudio")
                                retryMenu(for: entry)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                entryToDelete = entry
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Apagar ditado")
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Histórico do ditado")
        .toolbar {
            ToolbarItem {
                Picker("Velocidade", selection: $playbackRate) {
                    Text("1×").tag(1.0)
                    Text("2×").tag(2.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 92)
            }
            ToolbarItem {
                Button("Atualizar", systemImage: "arrow.clockwise", action: reload)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let retryStatus {
                Text(retryStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
        }
        .onChange(of: playbackRate) { _, rate in player?.rate = Float(rate) }
        .onAppear(perform: reload)
        .onDisappear {
            player?.stop()
            player = nil
            playingID = nil
        }
        .confirmationDialog(deleteAudioOnly ? "Apagar o áudio deste ditado?" : "Apagar este ditado?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }), titleVisibility: .visible) {
            Button("Apagar", role: .destructive) {
                if let entryToDelete {
                    if deleteAudioOnly { deleteAudio(entryToDelete) }
                    else { delete(entryToDelete) }
                }
            }
            Button("Cancelar", role: .cancel) {
                entryToDelete = nil
                deleteAudioOnly = false
            }
        }
    }

    private func reload() {
        entries = DictationHistoryStore.shared.entries()
    }

    @ViewBuilder
    private func retryMenu(for entry: DictationHistoryEntry) -> some View {
        Menu(retryingID == entry.id ? "Retranscrevendo…" : "Retranscrever") {
            ForEach(DictationProvider.allCases) { provider in
                Menu(provider == .openAI ? "OpenAI" : "Groq") {
                    ForEach(provider.models) { model in
                        Button(model.id) {
                            retry(entry, provider: provider, model: model)
                        }
                    }
                }
            }
        }
        .disabled(retryingID != nil)
    }

    private func retry(_ entry: DictationHistoryEntry,
                       provider: DictationProvider,
                       model: DictationModel) {
        guard entry.audioFileName != nil else { return }
        retryingID = entry.id
        retryStatus = nil
        Task {
            do {
                _ = try await DictationService.shared.retranscribe(
                    entry: entry,
                    provider: provider,
                    model: model,
                    language: entry.language)
                guard !Task.isCancelled else { return }
                reload()
                retryStatus = "Nova tentativa salva no histórico."
            } catch let failure as DictationFailure {
                guard !Task.isCancelled else { return }
                retryStatus = FeatureStrings.dictation(L10n.shared.language).failureMessage(failure)
            } catch {
                guard !Task.isCancelled else { return }
                retryStatus = FeatureStrings.dictation(L10n.shared.language).failureMessage(.network)
            }
            retryingID = nil
        }
    }

    private func togglePlayback(_ entry: DictationHistoryEntry) {
        if playingID == entry.id {
            player?.stop()
            player = nil
            playingID = nil
            return
        }
        guard let fileName = entry.audioFileName,
              let url = DictationHistoryStore.shared.audioURL(for: fileName),
              let next = try? AVAudioPlayer(contentsOf: url) else { return }
        player?.stop()
        next.enableRate = true
        next.rate = Float(playbackRate)
        next.play()
        player = next
        playingID = entry.id
    }

    private func delete(_ entry: DictationHistoryEntry) {
        if playingID == entry.id {
            player?.stop()
            player = nil
            playingID = nil
        }
        DictationHistoryStore.shared.remove(entry)
        reload()
        entryToDelete = nil
        deleteAudioOnly = false
    }

    private func deleteAudio(_ entry: DictationHistoryEntry) {
        if playingID == entry.id {
            player?.stop()
            player = nil
            playingID = nil
        }
        DictationHistoryStore.shared.removeAudio(from: entry)
        reload()
        entryToDelete = nil
        deleteAudioOnly = false
    }

    private static func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
