// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DictationHistoryView: View {
    var compact = false
    @ObservedObject private var history = DictationHistoryStore.shared
    private let speech = DictationService.shared
    @State private var phase = DictationService.shared.phase
    @AppStorage(DefaultsKey.dictationEnabled) private var dictationEnabled = false
    @State private var historyNow = Date()
    @State private var ageTimer: Timer?
    @ObservedObject private var l10n = L10n.shared
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var editing: DictationEntry?
    @State private var editedText = ""
    @State private var confirmsClear = false
    @State private var copiedID: UUID?
    @State private var copyError = false
    @State private var copyToken = UUID()
    @State private var copyReset: DispatchWorkItem?
    private var text: DictationStrings { .localized(l10n.language) }
    private var matches: [DictationEntry] {
        history.entries.filter { (!favoritesOnly || $0.isFavorite) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.originalText.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(text.history, text: $query).textFieldStyle(.plain)
                        .accessibilityLabel(text.history)
                }.padding(9).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                Button { favoritesOnly.toggle() } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                }.help("Favorites").accessibilityLabel("Favorites").buttonStyle(.plain)
                Button(action: speech.toggle) { Image(systemName: "mic") }
                    .buttonStyle(.plain).help(text.start).accessibilityLabel(text.start)
                    .disabled(!dictationEnabled || !AppFeature.dictation.isAvailable || phase.isBusy)
                Button {
                    SettingsRouter.shared.request(FeatureSettingsDestination(.dictation))
                    (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
                } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help(text.title + " settings").accessibilityLabel(text.title + " settings")
                Menu {
                    Button(text.start, action: speech.toggle).disabled(!dictationEnabled || !AppFeature.dictation.isAvailable || phase.isBusy)
                    Button("Transcribe audio file…", action: speech.importAudio).disabled(!dictationEnabled || !AppFeature.dictation.isAvailable || phase.isBusy)
                    Button("Export history…", action: exportHistory).disabled(matches.isEmpty)
                    Button("Clear history…", role: .destructive) { confirmsClear = true }.disabled(history.entries.isEmpty)
                    Button(text.title + " settings") {
                        SettingsRouter.shared.request(FeatureSettingsDestination(.dictation))
                        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
            if let error = history.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if matches.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform").font(.system(size: 28, weight: .light)).foregroundStyle(.mint)
                    Text(query.isEmpty ? text.empty : "No matching transcripts").font(.system(size: 12, weight: .medium))
                    if query.isEmpty {
                        Button(text.start, action: speech.toggle).disabled(!dictationEnabled || !AppFeature.dictation.isAvailable || phase.isBusy)
                            .buttonStyle(.bordered)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(matches) { entry in card(entry) }
                    }
                }.scrollIndicators(.automatic)
            }
            HStack {
                if copiedID != nil {
                    Label(text.copied, systemImage: "checkmark").font(.system(size: 10, weight: .medium)).foregroundStyle(.green)
                } else if copyError {
                    Text("Couldn’t copy. Try again.").font(.system(size: 10)).foregroundStyle(.orange)
                } else {
                    Text("\(matches.count) · " + text.history).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("On this Mac").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .onReceive(speech.$phase.removeDuplicates()) { phase = $0 }
        .onAppear {
            history.syncWithPreferences()
            historyNow = Date()
            ageTimer?.invalidate()
            let timer = Timer(timeInterval: 60, repeats: true) { _ in historyNow = Date() }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            ageTimer = timer
        }
        .onDisappear {
            copyReset?.cancel(); copyToken = UUID()
            ageTimer?.invalidate(); ageTimer = nil
        }
        .confirmationDialog("Clear speech history and its recordings?", isPresented: $confirmsClear) {
            Button("Clear history", role: .destructive, action: history.clear)
        }
        .sheet(item: $editing) { entry in
            VStack(alignment: .leading, spacing: 14) {
                Text(text.history).font(.headline)
                TextEditor(text: $editedText).font(.body).frame(minWidth: 380, minHeight: 200)
                if entry.originalText != entry.text {
                    DisclosureGroup("Original transcription") { Text(entry.originalText).textSelection(.enabled).font(.caption) }
                }
                HStack {
                    Button(text.cancel) { editing = nil }
                    Spacer()
                    Button("Save") { history.update(entry.id, text: editedText); editing = nil }.keyboardShortcut(.defaultAction)
                }
            }.padding(20)
        }
        .accessibilityIdentifier("dictation.history")
    }

    private func card(_ entry: DictationEntry) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(entry.text).font(.system(size: compact ? 12 : 13)).lineLimit(compact ? 3 : 6)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            HStack(spacing: 10) {
                DictationHistoryAge(date: entry.createdAt, now: historyNow, locale: l10n.language.formattingLocale())
                    .equatable().font(.system(size: 10)).foregroundStyle(.secondary)
                Text(Duration.seconds(entry.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { copy(entry) } label: {
                    Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: copiedID == entry.id ? .semibold : .regular))
                        .foregroundStyle(copiedID == entry.id ? Color.green : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 24, height: 22).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .help(copiedID == entry.id ? text.copied : FeatureStrings.clipboard(l10n.language).copy)
                    .accessibilityLabel(copiedID == entry.id ? text.copied : FeatureStrings.clipboard(l10n.language).copy)
                    .accessibilityIdentifier("dictation.copy." + entry.id.uuidString)
                action(entry.isFavorite ? "star.fill" : "star", title: "Favorite") { history.favorite(entry.id) }
                Menu {
                    Button("Edit transcript…") { editedText = entry.text; editing = entry }
                    if history.audioURL(entry) != nil {
                        Button("Play recording") { history.play(entry) }
                        Button("Transcribe again") { speech.retry(entry) }.disabled(phase.isBusy || !dictationEnabled || !AppFeature.dictation.isAvailable)
                    }
                    Button("Delete", role: .destructive) { history.remove(entry.id) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
        }
        .padding(compact ? 11 : 14)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func copy(_ entry: DictationEntry) {
        copyReset?.cancel()
        let token = UUID(); copyToken = token
        speech.copyEntry(entry) { succeeded in
            guard copyToken == token else { return }
            copiedID = succeeded ? entry.id : nil
            copyError = !succeeded
            let reset = DispatchWorkItem {
                guard copyToken == token else { return }
                copiedID = nil; copyError = false
            }
            copyReset = reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reset)
        }
    }

    private func action(_ symbol: String, title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Image(systemName: symbol).font(.system(size: 11)) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Speech history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(matches).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { NSSound.beep() }
    }
}

/// Rendering this label never schedules SwiftUI's per-second relative-date updates.
private struct DictationHistoryAge: View, Equatable {
    let date: Date
    let now: Date
    let locale: Locale
    var body: some View {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return Text(formatter.localizedString(from: DictationSupport.historyAge(date, relativeTo: now)))
    }
}
