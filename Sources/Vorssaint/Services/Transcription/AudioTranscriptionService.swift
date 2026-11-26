// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Coordinates standalone drag-and-drop audio transcription and automatic
/// post-meeting transcription using NVIDIA Parakeet Unified English 0.6B on
/// Apple Core ML.
final class AudioTranscriptionService: ObservableObject, @unchecked Sendable {
    static let shared = AudioTranscriptionService()

    struct RecentTranscript: Identifiable, Equatable {
        let id: String
        let title: String
        let sourceURL: URL
        let savedTranscriptURL: URL?
        let text: String
        let createdAt: Date
        let durationSeconds: Double
    }

    @Published private(set) var modelReady = false
    @Published private(set) var modelDiskBytes: Int64 = 0
    @Published private(set) var isDownloadingModel = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadBytesDone: Int64 = 0
    @Published private(set) var downloadBytesTotal: Int64 = AudioTranscriptionSupport.totalExpectedModelBytes

    @Published private(set) var isTranscribing = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentFileName: String?
    @Published private(set) var transcriptText = ""
    @Published private(set) var segments: [AudioTranscriptionSupport.TranscriptSegment] = []
    @Published private(set) var lastDurationSeconds: Double = 0
    @Published private(set) var lastProcessingSeconds: Double = 0
    @Published private(set) var lastSourceURL: URL?
    @Published private(set) var lastSavedTranscriptURL: URL?
    @Published private(set) var errorMessage: String?
    @Published private(set) var recentTranscripts: [RecentTranscript] = []

    private let engine = ParakeetCoreMLTranscriber()
    private var downloadTask: Task<Void, Never>?
    private var transcribeTask: Task<Void, Never>?
    private var pendingDropURL: URL?

    private init() {
        refreshModelStatus()
    }

    var modelDirectory: URL {
        AudioTranscriptionSupport.defaultModelDirectory()
    }

    var computeMode: ParakeetComputeMode {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.audioTranscriptionComputeMode) ?? ""
        return ParakeetComputeMode(rawValue: raw) ?? .auto
    }

    func refreshModelStatus() {
        let dir = modelDirectory
        modelReady = AudioTranscriptionSupport.isModelDirectoryReady(dir)
        modelDiskBytes = AudioTranscriptionSupport.directorySizeBytes(dir)
    }

    // MARK: - Model Lifecycle

    func downloadModel(thenTranscribe url: URL? = nil) {
        if let url { pendingDropURL = url }
        guard !isDownloadingModel else { return }
        errorMessage = nil
        isDownloadingModel = true
        downloadProgress = 0
        downloadBytesDone = 0
        downloadBytesTotal = AudioTranscriptionSupport.totalExpectedModelBytes

        let dir = modelDirectory
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await ParakeetCoreMLTranscriber.downloadModel(to: dir) { frac, done, total in
                    DispatchQueue.main.async {
                        self.downloadProgress = frac
                        self.downloadBytesDone = done
                        self.downloadBytesTotal = total
                    }
                }
                await MainActor.run {
                    self.isDownloadingModel = false
                    self.downloadTask = nil
                    self.refreshModelStatus()
                    let strings = FeatureStrings.audioTranscription(L10n.shared.language)
                    QuickToolHUD.show(icon: "checkmark.circle", message: strings.modelReadyHUD)
                    if let queued = self.pendingDropURL {
                        self.pendingDropURL = nil
                        self.transcribeFile(queued)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isDownloadingModel = false
                    self.downloadTask = nil
                    self.pendingDropURL = nil
                    self.refreshModelStatus()
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingModel = false
                    self.downloadTask = nil
                    self.pendingDropURL = nil
                    self.errorMessage = error.localizedDescription
                    self.refreshModelStatus()
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        pendingDropURL = nil
        isDownloadingModel = false
        refreshModelStatus()
    }

    func deleteModel() {
        cancelDownload()
        cancelTranscription()
        engine.evictCache()
        try? FileManager.default.removeItem(at: modelDirectory)
        refreshModelStatus()
    }

    // MARK: - Standalone Audio File Transcription

    func transcribeFile(_ url: URL) {
        let strings = FeatureStrings.audioTranscription(L10n.shared.language)
        guard AudioTranscriptionSupport.isSupportedAudioURL(url) else {
            errorMessage = strings.unsupportedFileError
            return
        }
        refreshModelStatus()
        if !modelReady {
            downloadModel(thenTranscribe: url)
            return
        }

        transcribeTask?.cancel()
        errorMessage = nil
        isTranscribing = true
        progress = 0
        currentFileName = url.lastPathComponent
        lastSourceURL = url
        lastSavedTranscriptURL = nil

        let dir = modelDirectory
        let mode = computeMode
        let includeTimestamps = UserDefaults.standard.bool(forKey: DefaultsKey.audioTranscriptionIncludeTimestamps)
        let saveBeside = UserDefaults.standard.bool(forKey: DefaultsKey.audioTranscriptionSaveBesideAudio)

        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.engine.transcribe(
                    audioURL: url,
                    modelDirectory: dir,
                    computeMode: mode,
                    speaker: nil
                ) { frac in
                    DispatchQueue.main.async {
                        self.progress = frac
                    }
                }
                let formatted = AudioTranscriptionSupport.formatTranscript(
                    segments: result.segments,
                    includeTimestamps: includeTimestamps
                )
                var savedURL: URL?
                if saveBeside, !formatted.isEmpty {
                    let dest = AudioTranscriptionSupport.transcriptFileURL(forAudioURL: url)
                    if (try? formatted.write(to: dest, atomically: true, encoding: .utf8)) != nil {
                        savedURL = dest
                    }
                }
                let finalSavedURL = savedURL
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcribeTask = nil
                    self.progress = 1
                    self.segments = result.segments
                    self.transcriptText = formatted
                    self.lastDurationSeconds = result.audioDurationSeconds
                    self.lastProcessingSeconds = result.elapsedSeconds
                    self.lastSavedTranscriptURL = finalSavedURL
                    if formatted.isEmpty {
                        self.errorMessage = strings.noSpeechDetected
                    } else {
                        self.recordRecent(
                            title: url.deletingPathExtension().lastPathComponent,
                            sourceURL: url,
                            savedURL: finalSavedURL,
                            text: formatted,
                            duration: result.audioDurationSeconds
                        )
                        QuickToolHUD.show(icon: "captions.bubble", message: strings.completedHUD)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcribeTask = nil
                }
            } catch ParakeetCoreMLTranscriber.TranscriberError.cancelled {
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcribeTask = nil
                }
            } catch {
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcribeTask = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Meeting Auto-Transcription (Dual-Track Merge)

    func transcribeMeeting(stem: String,
                           systemURL: URL?,
                           micURL: URL?,
                           outputDir: URL,
                           showHUD: Bool = true) {
        let strings = FeatureStrings.audioTranscription(L10n.shared.language)
        refreshModelStatus()
        guard modelReady else {
            errorMessage = strings.modelRequiredForAutoError
            if showHUD {
                QuickToolHUD.show(icon: "exclamationmark.triangle", message: strings.modelRequiredForAutoError)
            }
            return
        }
        guard systemURL != nil || micURL != nil else { return }

        transcribeTask?.cancel()
        errorMessage = nil
        isTranscribing = true
        progress = 0
        currentFileName = MeetingRecorderSupport.displayLabel(fromStem: stem)
        lastSourceURL = micURL ?? systemURL
        lastSavedTranscriptURL = nil

        let dir = modelDirectory
        let mode = computeMode
        let includeTimestamps = UserDefaults.standard.bool(forKey: DefaultsKey.audioTranscriptionIncludeTimestamps)
        let micLabel = strings.speakerYou
        let systemLabel = strings.speakerOthers

        transcribeTask = Task { [weak self] in
            guard let self else { return }
            let wallStart = Date()
            do {
                let trackCount = (micURL != nil ? 1 : 0) + (systemURL != nil ? 1 : 0)
                var completedTracks = 0
                var micSegments: [AudioTranscriptionSupport.TranscriptSegment] = []
                var sysSegments: [AudioTranscriptionSupport.TranscriptSegment] = []
                var maxDuration: Double = 0

                if let micURL {
                    let baseTracks = completedTracks
                    let res = try await self.engine.transcribe(
                        audioURL: micURL,
                        modelDirectory: dir,
                        computeMode: mode,
                        speaker: systemURL != nil ? micLabel : nil
                    ) { frac in
                        DispatchQueue.main.async {
                            self.progress = (Double(baseTracks) + frac) / Double(max(1, trackCount))
                        }
                    }
                    micSegments = res.segments
                    maxDuration = max(maxDuration, res.audioDurationSeconds)
                    completedTracks += 1
                }

                if let systemURL {
                    let baseTracks = completedTracks
                    let res = try await self.engine.transcribe(
                        audioURL: systemURL,
                        modelDirectory: dir,
                        computeMode: mode,
                        speaker: micURL != nil ? systemLabel : nil
                    ) { frac in
                        DispatchQueue.main.async {
                            self.progress = (Double(baseTracks) + frac) / Double(max(1, trackCount))
                        }
                    }
                    sysSegments = res.segments
                    maxDuration = max(maxDuration, res.audioDurationSeconds)
                    completedTracks += 1
                }

                let merged = AudioTranscriptionSupport.mergeSpeakerSegments(
                    systemSegments: sysSegments,
                    micSegments: micSegments
                )
                let formatted = AudioTranscriptionSupport.formatTranscript(
                    segments: merged,
                    includeTimestamps: includeTimestamps
                )

                var savedURL: URL?
                if !formatted.isEmpty {
                    let dest = AudioTranscriptionSupport.meetingTranscriptFileURL(stem: stem, in: outputDir)
                    if (try? formatted.write(to: dest, atomically: true, encoding: .utf8)) != nil {
                        savedURL = dest
                    }
                }

                let finalSavedURL = savedURL
                let finalDuration = maxDuration
                let elapsed = Date().timeIntervalSince(wallStart)
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcribeTask = nil
                    self.progress = 1
                    self.segments = merged
                    self.transcriptText = formatted
                    self.lastDurationSeconds = finalDuration
                    self.lastProcessingSeconds = elapsed
                    self.lastSavedTranscriptURL = finalSavedURL
                    if formatted.isEmpty {
                        self.errorMessage = strings.noSpeechDetected
                    } else {
                        self.recordRecent(
                            title: MeetingRecorderSupport.displayLabel(fromStem: stem),
                            sourceURL: micURL ?? systemURL ?? outputDir,
                            savedURL: finalSavedURL,
                            text: formatted,
                            duration: finalDuration
                        )
                        if showHUD {
                            QuickToolHUD.show(icon: "captions.bubble", message: strings.meetingTranscribedHUD)
                        }
                    }
                    MeetingRecorderService.shared.refreshRecordings()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcribeTask = nil
                }
            } catch ParakeetCoreMLTranscriber.TranscriberError.cancelled {
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcribeTask = nil
                }
            } catch {
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcribeTask = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelTranscription() {
        transcribeTask?.cancel()
        transcribeTask = nil
        isTranscribing = false
    }

    func clearTranscript() {
        transcriptText = ""
        segments = []
        lastDurationSeconds = 0
        lastProcessingSeconds = 0
        lastSourceURL = nil
        lastSavedTranscriptURL = nil
        errorMessage = nil
    }

    func selectRecent(_ item: RecentTranscript) {
        transcriptText = item.text
        lastSourceURL = item.sourceURL
        lastSavedTranscriptURL = item.savedTranscriptURL
        lastDurationSeconds = item.durationSeconds
        currentFileName = item.title
        errorMessage = nil
    }

    func copyTranscript() {
        guard !transcriptText.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(transcriptText, forType: .string)
        let strings = FeatureStrings.audioTranscription(L10n.shared.language)
        QuickToolHUD.show(icon: "doc.on.doc", message: strings.copiedHUD)
    }

    func saveTranscriptAs() {
        guard !transcriptText.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let defaultName = lastSourceURL.map { "\($0.deletingPathExtension().lastPathComponent)-transcript.txt" }
            ?? "transcript.txt"
        panel.nameFieldStringValue = defaultName
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try transcriptText.write(to: url, atomically: true, encoding: .utf8)
                lastSavedTranscriptURL = url
                let strings = FeatureStrings.audioTranscription(L10n.shared.language)
                QuickToolHUD.show(icon: "checkmark.circle", message: strings.savedHUD)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func chooseAudioFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Audio, .wav, .mp3, .aiff]
        if panel.runModal() == .OK, let url = panel.url {
            transcribeFile(url)
        }
    }

    func revealSavedTranscript() {
        if let url = lastSavedTranscriptURL, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func recordRecent(title: String, sourceURL: URL, savedURL: URL?, text: String, duration: Double) {
        let entry = RecentTranscript(
            id: UUID().uuidString,
            title: title,
            sourceURL: sourceURL,
            savedTranscriptURL: savedURL,
            text: text,
            createdAt: Date(),
            durationSeconds: duration
        )
        recentTranscripts.insert(entry, at: 0)
        if recentTranscripts.count > 15 {
            recentTranscripts.removeLast(recentTranscripts.count - 15)
        }
    }
}
