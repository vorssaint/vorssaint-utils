// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct MediaDownloaderSettings: View {
    var body: some View {
        MediaDownloaderView(compact: false)
            .padding(16)
    }
}

struct PanelMediaDownloaderView: View {
    var onClose: () -> Void

    var body: some View {
        MediaDownloaderView(compact: true, onClose: onClose)
            .onAppear { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
            .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
    }
}

private enum MediaDownloadKind: String, CaseIterable, Identifiable {
    case video, audio
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .video ? "video" : "waveform" }
}

struct MediaDownloaderView: View {
    @ObservedObject private var service = MediaDownloaderService.shared
    @ObservedObject private var homebrew = HomebrewManager.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var kind: MediaDownloadKind = .video
    @State private var selectedHeight = 0
    @State private var batchMaximumHeight = 0
    @State private var audioFormat = "original"
    @State private var inspectTask: Task<Void, Never>?
    @State private var showHistory = true

    let compact: Bool
    var onClose: (() -> Void)?

    private var platform: MediaDownloaderPlatform? {
        MediaDownloaderSupport.normalizedURL(service.inputURLText).map(MediaDownloaderPlatform.identify)
    }

    private var selectedQuality: Int? { selectedHeight == 0 ? nil : selectedHeight }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? 10 : 16) {
                heading
                if !service.dependencies.areReady {
                    dependencyCard
                } else {
                    linkCard
                    batchCard
                    if let metadata = service.metadata { downloadCard(metadata) }
                    if service.isDownloading { progressCard }
                    if let error = service.errorMessage { messageCard(error, symbol: "exclamationmark.triangle", tint: .orange) }
                    historyCard
                }
            }
            .frame(maxWidth: compact ? .infinity : 700, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(compact ? 0 : 22)
        }
        .scrollIndicators(compact ? .hidden : .automatic)
        .onAppear { service.refreshDependencies() }
        .onChange(of: homebrew.operationStatus?.finishedAt) { _, finishedAt in
            guard finishedAt != nil else { return }
            service.refreshDependencies()
        }
        .onChange(of: service.metadata) { _, metadata in
            if let metadata, !metadata.videoQualities.contains(selectedHeight) {
                selectedHeight = 0
            }
        }
        .onDisappear { inspectTask?.cancel() }
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 10) {
            MediaDownloaderMark(size: compact ? 22 : 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Online Media Downloader")
                    .font(compact ? .headline : .title2.bold())
                if !compact {
                    Text("Save video or audio directly to your Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }
        }
    }

    private var dependencyCard: some View {
        SettingsCard(title: "Download tools") {
            Label("yt-dlp and FFmpeg are needed for media downloads and format merging.",
                  systemImage: "shippingbox")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Media is fetched directly from the source and processed on this Mac.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let error = homebrew.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            if let status = homebrew.operationStatus, status.isActive {
                ProgressView(value: status.progressFraction)
                Text(status.lastActivity ?? "Installing with Homebrew…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Cancel installation") { homebrew.cancelOperation() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                HStack {
                    Button(homebrew.brewPath == nil ? "Install Homebrew" : "Install yt-dlp and FFmpeg") {
                        if homebrew.brewPath == nil {
                            homebrew.openHomebrewInstaller()
                        } else {
                            homebrew.installMediaDownloaderDependencies()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(homebrew.operation != nil)
                    Button("Check again") { service.refreshDependencies() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var linkCard: some View {
        SettingsCard(title: "Media link") {
            HStack(spacing: 8) {
                TextField("Paste a video or post URL", text: $service.inputURLText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(service.isBatchRunning)
                    .onSubmit { inspect() }
                    .onChange(of: service.inputURLText) { _, value in
                        inspectTask?.cancel()
                        service.prepareForURLChange()
                        guard MediaDownloaderSupport.normalizedURL(value) != nil else { return }
                        inspectTask = Task {
                            try? await Task.sleep(for: .milliseconds(550))
                            guard !Task.isCancelled else { return }
                            inspect()
                        }
                    }
                Button("Paste") { pasteURL() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
            HStack(spacing: 8) {
                if let platform {
                    Label(platform.title, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("YouTube, Instagram, TikTok, and more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if service.isInspecting {
                    ProgressView().controlSize(.small)
                    Text("Checking link…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Get formats", action: inspect)
                        .buttonStyle(.bordered)
                        .disabled(platform == nil)
                }
            }
        }
    }

    private var batchCard: some View {
        SettingsCard(title: "Batch download") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Import CSV, TSV, text, or JSON. Add a format tag after each link (for example #MKV, #M4A, or #HEIC). Untagged links default to MP4. Each run creates one new folder at the selected location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Video: MP4, MKV, MOV, WEBM, AVI, FLV, GIF · Audio: MP3, M4A, WAV, OPUS, FLAC, AAC, ALAC, VORBIS, ORIGINAL · Images: JPG, PNG, WEBP, HEIC, HEIF (thumbnails)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Batch location")
                            .font(.caption.weight(.medium))
                        Text(service.batchDestinationFolder.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Button("Choose", action: service.chooseBatchDestinationFolder)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(service.isBatchRunning)
                }
                .help(service.batchDestinationFolder.path)

                HStack(spacing: 8) {
                    Button(action: service.importBatchFile) {
                        Label(service.isImportingBatchFile ? "Reading file…" : "Import links file",
                              systemImage: "doc.badge.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(service.isDownloading || service.isInspecting || service.isBatchRunning
                              || service.isImportingBatchFile)
                    if !service.batchItems.isEmpty {
                        Button("Clear", action: service.clearBatchLinks)
                            .buttonStyle(.borderless)
                            .disabled(service.isBatchRunning)
                    }
                    Spacer(minLength: 0)
                    if !service.batchItems.isEmpty {
                        Text("\(service.batchItems.count) items")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if !service.batchItems.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(service.batchItems.prefix(3).enumerated()), id: \.offset) { row in
                            HStack(spacing: 8) {
                                Label(row.element.url.host ?? row.element.url.absoluteString,
                                      systemImage: row.element.kind == .image ? "photo" :
                                        (row.element.kind == .audio ? "waveform" : "play.rectangle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(row.element.formatTag)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if service.batchItems.count > 3 {
                            Text("and \(service.batchItems.count - 3) more")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Picker("Video quality", selection: $batchMaximumHeight) {
                        Text("Best available").tag(0)
                        ForEach([360, 480, 720, 1080, 1440, 2160], id: \.self) { height in
                            Text("Up to \(height)p").tag(height)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(service.isBatchRunning)

                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            service.startBatchDownloads(
                                maximumHeight: batchMaximumHeight == 0 ? nil : batchMaximumHeight
                            )
                        } label: {
                            Label(service.isBatchRunning ? "Downloading batch…" : "Download \(service.batchItems.count) items",
                                  systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(service.batchItems.isEmpty || service.isDownloading || service.isInspecting || service.isBatchRunning)
                    }
                }
                if !service.isBatchRunning, let status = service.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let folder = service.batchOutputFolder {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.fill").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current batch folder")
                                .font(.caption.weight(.medium))
                            Text(folder.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        Button("Show in Finder", action: service.revealBatchFolder)
                            .buttonStyle(.borderless)
                            .disabled(!FileManager.default.fileExists(atPath: folder.path))
                    }
                    .help(folder.path)
                }
            }
        }
    }

    private func downloadCard(_ metadata: MediaDownloaderSupport.Metadata) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: compact ? 9 : 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: metadata.platform == .other ? "play.rectangle" : "play.rectangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(metadata.title).font(.headline).lineLimit(2)
                        HStack(spacing: 8) {
                            Text(metadata.platform.title)
                            if !metadata.uploader.isEmpty { Text("·"); Text(metadata.uploader).lineLimit(1) }
                            if let duration = metadata.duration { Text("·"); Text(Self.durationText(duration)) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Picker("Download type", selection: $kind) {
                    ForEach(MediaDownloadKind.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                if kind == .video {
                    Picker("MP4 quality", selection: $selectedHeight) {
                        Text("Best available").tag(0)
                        ForEach(metadata.videoQualities, id: \.self) { height in
                            Text("Up to \(height)p").tag(height)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Picker("Audio format", selection: $audioFormat) {
                        Text("Original").tag("original")
                        Text("MP3").tag("mp3")
                        Text("M4A").tag("m4a")
                        Text("Opus").tag("opus")
                        Text("WAV").tag("wav")
                    }
                    .pickerStyle(.menu)
                }
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(service.destinationFolder.lastPathComponent)
                        .lineLimit(1).truncationMode(.middle)
                        .font(.caption)
                    Spacer(minLength: 0)
                    Button("Choose folder", action: service.chooseDestinationFolder)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .help(service.destinationFolder.path)
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        if kind == .video {
                            service.downloadVideo(from: service.inputURLText, maximumHeight: selectedQuality)
                        } else {
                            service.downloadAudio(from: service.inputURLText, format: audioFormat)
                        }
                    } label: {
                        Label(kind == .video ? "Download MP4" : "Download audio", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.isDownloading || service.isInspecting || service.isBatchRunning)
                }
            }
        }
    }

    private var progressCard: some View {
        SettingsCard(title: "Downloading") {
            HStack(spacing: 8) {
                if let fraction = service.progress?.fraction {
                    ProgressView(value: fraction)
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                } else {
                    ProgressView()
                    Text("Preparing download…").font(.caption)
                }
            }
            HStack {
                if let status = service.statusMessage {
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let speed = service.progress?.speedText {
                    Text(speed).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(service.isBatchRunning ? "Cancel batch" : "Cancel download", action: service.cancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var historyCard: some View {
        SettingsCard {
            DisclosureGroup(isExpanded: $showHistory) {
                if service.history.isEmpty {
                    Text("Completed downloads will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(service.history) { entry in
                            historyRow(entry)
                            if entry.id != service.history.last?.id { Divider() }
                        }
                    }
                    .padding(.top, 6)
                    HStack {
                        Spacer()
                        Button("Clear history", role: .destructive, action: service.clearHistory)
                            .buttonStyle(.borderless)
                    }
                }
            } label: {
                HStack {
                    Text("Download history").font(.headline)
                    Spacer()
                    Text("\(service.history.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
        }
    }

    private func historyRow(_ entry: MediaDownloaderSupport.HistoryEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind == .image ? "photo" : (entry.kind == .video ? "film" : "waveform"))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.callout.weight(.medium)).lineLimit(1)
                Text("\(entry.platform.title) · \(entry.quality) · \(entry.completedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { service.open(entry) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .help("Open file")
            Button { service.reveal(entry) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless)
                .help("Show in Finder")
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func messageCard(_ message: String, symbol: String, tint: Color) -> some View {
        SettingsCard {
            Label(message, systemImage: symbol)
                .font(.callout)
                .foregroundStyle(tint)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pasteURL() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        service.inputURLText = value.trimmingCharacters(in: .whitespacesAndNewlines)
        inspect()
    }

    private func inspect() {
        inspectTask?.cancel()
        service.inspect(service.inputURLText)
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3_600
        let minutes = total / 60 % 60
        let remaining = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remaining) }
        return String(format: "%d:%02d", minutes, remaining)
    }
}

private struct MediaDownloaderMark: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "film")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: size * 0.53, weight: .bold))
                    .foregroundStyle(Color.accentColor, Color(nsColor: .windowBackgroundColor))
                    .offset(x: size * 0.22, y: size * 0.18)
            }
            .frame(width: size * 1.18, height: size * 1.18)
            .accessibilityLabel("Media Downloader")
    }
}
