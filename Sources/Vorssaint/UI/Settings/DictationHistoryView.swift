// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Local dictation library. Entries stay compact until opened, while selection
/// is separate from opening so reviewing many recordings stays quick.
struct DictationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DictationHistoryEntry] = []
    @State private var searchText = ""
    @State private var selectedIDs = Set<UUID>()
    @State private var expandedID: UUID?
    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?
    @State private var playbackRate = 1.0
    @State private var waveforms: [UUID: [Float]] = [:]
    @State private var entryToDelete: DictationHistoryEntry?
    @State private var deleteAudioOnly = false
    @State private var deleteSelected = false
    @State private var retryingID: UUID?
    @State private var retryStatus: String?
    @State private var detailsEntry: DictationHistoryEntry?

    private var visibleEntries: [DictationHistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.rawText.localizedCaseInsensitiveContains(query)
                || (entry.enhancedText?.localizedCaseInsensitiveContains(query) ?? false)
                || entry.model.id.localizedCaseInsensitiveContains(query)
                || entry.language.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Nenhum ditado salvo", systemImage: "waveform",
                                       description: Text("As sessões aparecerão aqui quando o histórico estiver ativado."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleEntries) { entry in entryCard(entry) }
                    }
                    .padding(16)
                }
                .searchable(text: $searchText, prompt: "Buscar transcrições")
            }
        }
        .navigationTitle("Histórico do ditado")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Voltar", systemImage: "chevron.left") { dismiss() }
                    .accessibilityLabel("Voltar para Ditado")
            }
            ToolbarItemGroup {
                if !entries.isEmpty {
                    Button(selectedIDs.count == entries.count ? "Limpar seleção" : "Selecionar todos",
                           systemImage: selectedIDs.count == entries.count ? "checkmark.circle.fill" : "checkmark.circle") {
                        selectedIDs = selectedIDs.count == entries.count ? [] : DictationHistorySelection.all(in: entries)
                    }
                }
                if !selectedIDs.isEmpty {
                    Button("Exportar selecionados", systemImage: "square.and.arrow.up", action: exportSelection)
                    Button("Apagar selecionados", systemImage: "trash", role: .destructive) { deleteSelected = true }
                }
                Button("Atualizar", systemImage: "arrow.clockwise", action: reload)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let retryStatus {
                Text(retryStatus).font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
            }
        }
        .onAppear(perform: reload)
        .onDisappear(perform: stopPlayback)
        .sheet(item: $detailsEntry) { DictationHistoryDetails(entry: $0) }
        .confirmationDialog(deleteSelected ? "Apagar os ditados selecionados?"
                                           : (deleteAudioOnly ? "Apagar o áudio deste ditado?" : "Apagar este ditado?"),
                            isPresented: Binding(get: { deleteSelected || entryToDelete != nil },
                                                 set: { if !$0 { entryToDelete = nil; deleteSelected = false } }),
                            titleVisibility: .visible) {
            Button("Apagar", role: .destructive) {
                if deleteSelected { deleteSelection() }
                else if let entryToDelete { deleteAudioOnly ? deleteAudio(entryToDelete) : delete(entryToDelete) }
            }
            Button("Cancelar", role: .cancel) {
                entryToDelete = nil; deleteAudioOnly = false; deleteSelected = false
            }
        }
    }

    @ViewBuilder
    private func entryCard(_ entry: DictationHistoryEntry) -> some View {
        let expanded = expandedID == entry.id
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button { toggleSelection(entry.id) } label: {
                    Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedIDs.contains(entry.id) ? Color.accentColor : .secondary).font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selectedIDs.contains(entry.id) ? "Desmarcar ditado" : "Selecionar ditado")
                Button { expandedID = expanded ? nil : entry.id } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(entry.createdAt.formatted(date: .long, time: .shortened)).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(Self.duration(entry.duration)).font(.headline.monospacedDigit()).foregroundStyle(.secondary)
                            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        Text(entry.enhancedText ?? entry.rawText).font(.body).multilineTextAlignment(.leading).lineLimit(expanded ? nil : 2)
                        if let failure = entry.failure {
                            Label("Falha anterior: \(failure)", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityHint(expanded ? "Recolher detalhes" : "Abrir controles e detalhes")
                Button("Copiar", systemImage: "doc.on.doc") { copyText(for: entry) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Copiar transcrição")
                    .accessibilityLabel("Copiar transcrição")
            }
            if expanded { expandedContent(for: entry) }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.primary.opacity(0.075), lineWidth: 1) }
    }

    @ViewBuilder
    private func expandedContent(for entry: DictationHistoryEntry) -> some View {
        Divider()
        if entry.enhancedText != nil {
            Text("Texto cru: \(entry.rawText)").font(.caption).foregroundStyle(.secondary)
        }
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let progress = playingID == entry.id ? ((player?.duration ?? 0) > 0 ? (player?.currentTime ?? 0) / (player?.duration ?? 1) : 0) : 0
            DictationWaveform(peaks: waveforms[entry.id] ?? [], progress: progress).frame(height: 42)
                .accessibilityLabel("Forma de onda do áudio")
        }
        .task(id: entry.audioFileName) { loadWaveform(for: entry) }
        HStack(spacing: 12) {
            if entry.audioFileName != nil {
                Button(playbackLabel(for: entry), systemImage: playbackIcon(for: entry)) { togglePlayback(entry) }
                Button(playbackRate.label, action: cyclePlaybackRate).monospacedDigit().help("Velocidade: \(playbackRate.label)")
                Button("Abrir áudio", systemImage: "folder") { revealAudio(for: entry) }.help("Mostrar o arquivo no Finder")
                retryMenu(for: entry)
            } else {
                Label("Áudio não salvo", systemImage: "waveform.slash").foregroundStyle(.secondary)
            }
            Button("Copiar transcrição", systemImage: "doc.on.doc") { copyText(for: entry) }
            Spacer()
            Button("Detalhes", systemImage: "info.circle") { detailsEntry = entry }
            if entry.audioFileName != nil {
                Button("Apagar áudio", systemImage: "waveform.slash", role: .destructive) {
                    deleteAudioOnly = true; entryToDelete = entry
                }
            }
            Button("Apagar ditado", systemImage: "trash", role: .destructive) { entryToDelete = entry }
        }
        .font(.caption).buttonStyle(.borderless)
    }

    private func reload() {
        entries = DictationHistoryStore.shared.entries()
        selectedIDs = DictationHistorySelection.retaining(selectedIDs, in: entries)
    }

    private func toggleSelection(_ id: UUID) {
        selectedIDs = DictationHistorySelection.toggled(id, in: selectedIDs)
    }

    @ViewBuilder
    private func retryMenu(for entry: DictationHistoryEntry) -> some View {
        Menu(retryingID == entry.id ? "Retranscrevendo…" : "Retranscrever") {
            ForEach(DictationProvider.allCases) { provider in
                Menu(provider == .openAI ? "OpenAI" : "Groq") {
                    ForEach(provider.models) { model in
                        Button(model.id) { retry(entry, provider: provider, model: model) }
                    }
                }
            }
        }.disabled(retryingID != nil)
    }

    private func retry(_ entry: DictationHistoryEntry, provider: DictationProvider, model: DictationModel) {
        guard entry.audioFileName != nil else { return }
        retryingID = entry.id; retryStatus = nil
        Task {
            do {
                _ = try await DictationService.shared.retranscribe(entry: entry, provider: provider, model: model, language: entry.language)
                guard !Task.isCancelled else { return }
                reload(); retryStatus = "Nova tentativa salva no histórico."
            } catch let failure as DictationFailure {
                guard !Task.isCancelled else { return }
                retryStatus = FeatureStrings.dictation(L10n.shared.language).failureMessage(failure)
            } catch { retryStatus = FeatureStrings.dictation(L10n.shared.language).failureMessage(.network) }
            retryingID = nil
        }
    }

    private func togglePlayback(_ entry: DictationHistoryEntry) {
        if playingID == entry.id, let player {
            if player.isPlaying { player.pause() } else { player.play() }
            return
        }
        guard let fileName = entry.audioFileName, let url = DictationHistoryStore.shared.audioURL(for: fileName),
              let next = try? AVAudioPlayer(contentsOf: url) else { return }
        stopPlayback(); next.enableRate = true; next.rate = Float(playbackRate); next.play(); player = next; playingID = entry.id
    }

    private func copyText(for entry: DictationHistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.enhancedText ?? entry.rawText, forType: .string)
        retryStatus = "Transcrição copiada."
    }

    private func stopPlayback() { player?.stop(); player = nil; playingID = nil }

    private func playbackLabel(for entry: DictationHistoryEntry) -> String {
        playingID == entry.id && player?.isPlaying == true ? "Pausar" : "Reproduzir"
    }

    private func playbackIcon(for entry: DictationHistoryEntry) -> String {
        playingID == entry.id && player?.isPlaying == true ? "pause.fill" : "play.fill"
    }

    private func cyclePlaybackRate() {
        playbackRate = switch playbackRate { case 1.0: 1.5; case 1.5: 2.0; default: 1.0 }
        player?.rate = Float(playbackRate)
    }

    private func revealAudio(for entry: DictationHistoryEntry) {
        guard let fileName = entry.audioFileName, let url = DictationHistoryStore.shared.audioURL(for: fileName) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func loadWaveform(for entry: DictationHistoryEntry) {
        guard waveforms[entry.id] == nil, let fileName = entry.audioFileName,
              let url = DictationHistoryStore.shared.audioURL(for: fileName) else { return }
        Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
            let peaks = tracks.first.map {
                RecorderAudioWaveform.load(asset: asset, track: $0, duration: entry.duration, count: 96)
            } ?? []
            await MainActor.run { waveforms[entry.id] = peaks }
        }
    }

    private func delete(_ entry: DictationHistoryEntry) {
        if playingID == entry.id { stopPlayback() }
        DictationHistoryStore.shared.remove(entry); selectedIDs.remove(entry.id)
        if expandedID == entry.id { expandedID = nil }
        reload(); entryToDelete = nil; deleteAudioOnly = false
    }

    private func deleteAudio(_ entry: DictationHistoryEntry) {
        if playingID == entry.id { stopPlayback() }
        DictationHistoryStore.shared.removeAudio(from: entry); waveforms.removeValue(forKey: entry.id)
        reload(); entryToDelete = nil; deleteAudioOnly = false
    }

    private func deleteSelection() {
        let selected = entries.filter { selectedIDs.contains($0.id) }
        if selected.contains(where: { $0.id == playingID }) { stopPlayback() }
        selected.forEach(DictationHistoryStore.shared.remove)
        selectedIDs.removeAll(); expandedID = nil; reload(); deleteSelected = false
    }

    private func exportSelection() {
        let selected = entries.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let content = selected.map { "\($0.createdAt.formatted(date: .long, time: .shortened))\n\($0.enhancedText ?? $0.rawText)" }
            .joined(separator: "\n\n")
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "Transcrições do Vorssaint.txt"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try content.write(to: url, atomically: true, encoding: .utf8); retryStatus = "Transcrições exportadas." }
        catch { retryStatus = "Não foi possível exportar as transcrições." }
    }

    static func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct DictationWaveform: View {
    let peaks: [Float]
    var progress: Double = 0
    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else {
                context.stroke(Path(CGRect(x: 0, y: size.height / 2, width: size.width, height: 1)),
                               with: .color(.secondary.opacity(0.35)))
                return
            }
            let step = size.width / CGFloat(peaks.count)
            for (index, peak) in peaks.enumerated() {
                let height = max(2, CGFloat(peak) * (size.height - 5))
                let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2,
                                  width: max(1, step * 0.58), height: height)
                let played = Double(index) / Double(max(1, peaks.count - 1)) <= progress
                context.fill(Path(roundedRect: rect, cornerRadius: 1),
                             with: .color(played ? .accentColor : .secondary.opacity(0.38)))
            }
        }
    }
}

private struct DictationHistoryDetails: View {
    @Environment(\.dismiss) private var dismiss
    let entry: DictationHistoryEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Detalhes do ditado").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                row("Gravado", entry.createdAt.formatted(date: .long, time: .shortened))
                row("Duração", DictationHistoryView.duration(entry.duration))
                row("Provedor", entry.provider == .openAI ? "OpenAI" : "Groq")
                row("Modelo", entry.model.id)
                row("Idioma", entry.language.displayName)
                row("Transcrição", entry.processingDuration.map { String(format: "%.1f s", $0) } ?? "Não disponível")
            }
            HStack { Spacer(); Button("Concluído") { dismiss() } }
        }
        .padding(20).frame(minWidth: 360)
    }
    @ViewBuilder private func row(_ label: String, _ value: String) -> some View {
        GridRow { Text(label).foregroundStyle(.secondary); Text(value) }
    }
}

private extension Double {
    var label: String { switch self { case 1.5: "1,5×"; case 2.0: "2×"; default: "1×" } }
}
