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
                        Text(entry.rawText)
                            .lineLimit(3)
                        HStack(spacing: 10) {
                            Label(entry.language.displayName, systemImage: "globe")
                            Text(entry.model.id)
                                .foregroundStyle(.secondary)
                            if entry.audioFileName != nil {
                                Button(playingID == entry.id ? "Parar" : "Ouvir") {
                                    togglePlayback(entry)
                                }
                                .buttonStyle(.borderless)
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
        .onChange(of: playbackRate) { _, rate in player?.rate = Float(rate) }
        .onAppear(perform: reload)
        .onDisappear {
            player?.stop()
            player = nil
            playingID = nil
        }
        .confirmationDialog("Apagar este ditado?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }), titleVisibility: .visible) {
            Button("Apagar", role: .destructive) {
                if let entryToDelete { delete(entryToDelete) }
            }
            Button("Cancelar", role: .cancel) { entryToDelete = nil }
        }
    }

    private func reload() {
        entries = DictationHistoryStore.shared.entries()
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
    }

    private static func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
