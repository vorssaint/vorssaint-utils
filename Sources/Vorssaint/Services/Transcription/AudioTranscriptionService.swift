// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import NaturalLanguage
import UniformTypeIdentifiers

/// Coordinates standalone drag-and-drop audio transcription, automatic
/// post-meeting transcription, optional on-device summarization with a custom
/// prompt, and system-wide voice dictation using NVIDIA Parakeet Unified
/// English 0.6B on Apple Core ML.
final class AudioTranscriptionService: ObservableObject, @unchecked Sendable {
    static let shared = AudioTranscriptionService()

    struct RecentTranscript: Identifiable, Equatable {
        let id: String
        let title: String
        let sourceURL: URL
        let savedTranscriptURL: URL?
        let text: String
        let summary: String?
        let savedSummaryURL: URL?
        let createdAt: Date
        let durationSeconds: Double
    }

    @Published private(set) var modelReady = false
    @Published private(set) var modelDiskBytes: Int64 = 0
    @Published private(set) var isDownloadingModel = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadBytesDone: Int64 = 0
    @Published private(set) var downloadBytesTotal: Int64 = AudioTranscriptionSupport.totalExpectedModelBytes

    // Hebrew specialist model (ivrit.ai Whisper Large v3 Turbo Core ML)
    @Published private(set) var ivritModelReady = false
    @Published private(set) var ivritModelDiskBytes: Int64 = 0
    @Published private(set) var isDownloadingIvritModel = false
    @Published private(set) var ivritDownloadProgress: Double = 0
    @Published private(set) var lastDetectedLanguageCode: String?

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

    // Summary state
    @Published private(set) var summaryText = ""
    @Published private(set) var isSummarizing = false
    @Published private(set) var summaryUsedOnDeviceLLM = false
    @Published private(set) var summaryProviderName: String?
    @Published private(set) var lastSavedSummaryURL: URL?

    // System-wide dictation state
    @Published private(set) var isDictating = false
    @Published private(set) var dictationLevel: Float = 0
    @Published private(set) var dictationElapsedSeconds = 0
    @Published private(set) var dictationShortcutRegistrationFailed = false

    private let engine = ParakeetCoreMLTranscriber()
    private let ivritEngine = WhisperCoreMLTranscriber()
    private let dictationHotkey = QuickToolHotkey(id: 82)
    private let dictationRecorder = AudioDictationRecorder()
    private var downloadTask: Task<Void, Never>?
    private var ivritDownloadTask: Task<Void, Never>?
    private var transcribeTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var dictationTimer: Timer?
    private var dictationStartedAt: Date?
    private var holdDictationActive = false
    private var pendingDropURL: URL?
    private var pendingDictationAfterDownload = false

    private init() {
        dictationHotkey.onPress = { [weak self] in
            self?.handleDictationHotkeyPressed()
        }
        dictationHotkey.onRelease = { [weak self] in
            self?.handleDictationHotkeyReleased()
        }
        refreshModelStatus()
    }

    func syncWithPreferences() {
        refreshModelStatus()
        let available = AppFeature.audioTranscription.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.audioTranscriptionDictationEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.audioTranscriptionDictationShortcut,
                                            fallback: .voiceDictationDefault)
        dictationShortcutRegistrationFailed = !dictationHotkey.sync(
            enabled: enabled,
            shortcut: shortcut,
            storageKey: DefaultsKey.audioTranscriptionDictationShortcut
        )
        if !available, isDictating {
            cancelDictation()
        }
    }

    var summaryEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.audioTranscriptionSummaryEnabled)
    }

    var summaryPrompt: String {
        AudioTranscriptionSupport.resolvedSummaryPrompt(
            UserDefaults.standard.string(forKey: DefaultsKey.audioTranscriptionSummaryPrompt)
        )
    }

    var summaryProvider: SummaryInferenceProvider {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.audioTranscriptionSummaryProvider) ?? ""
        return SummaryInferenceProvider(rawValue: raw) ?? .auto
    }

    var summaryModel: String {
        UserDefaults.standard.string(forKey: DefaultsKey.audioTranscriptionSummaryModel) ?? ""
    }

    var dictationTriggerMode: DictationTriggerMode {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.audioTranscriptionDictationMode) ?? ""
        return DictationTriggerMode(rawValue: raw) ?? .toggle
    }

    var modelDirectory: URL {
        AudioTranscriptionSupport.defaultModelDirectory()
    }

    var ivritModelDirectory: URL {
        AudioTranscriptionSupport.defaultIvritModelDirectory()
    }

    var computeMode: ParakeetComputeMode {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.audioTranscriptionComputeMode) ?? ""
        return ParakeetComputeMode(rawValue: raw) ?? .auto
    }

    var modelChoice: TranscriptionModelChoice {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.audioTranscriptionModelChoice) ?? ""
        return TranscriptionModelChoice(rawValue: raw) ?? .auto
    }

    var activeModelReady: Bool {
        switch modelChoice {
        case .parakeetEnglish: return modelReady
        case .ivritHebrew: return ivritModelReady
        case .auto: return modelReady || ivritModelReady
        }
    }

    var isDownloadingActiveModel: Bool {
        isDownloadingModel || isDownloadingIvritModel
    }

    func refreshModelStatus() {
        let dir = modelDirectory
        modelReady = AudioTranscriptionSupport.isModelDirectoryReady(dir)
        modelDiskBytes = AudioTranscriptionSupport.directorySizeBytes(dir)
        let ivritDir = ivritModelDirectory
        ivritModelReady = AudioTranscriptionSupport.isIvritModelDirectoryReady(ivritDir)
        ivritModelDiskBytes = AudioTranscriptionSupport.ivritDirectorySizeBytes(ivritDir)
    }

    func downloadIvritModel(thenTranscribe url: URL? = nil) {
        if let url { pendingDropURL = url }
        guard !isDownloadingIvritModel else { return }
        errorMessage = nil
        isDownloadingIvritModel = true
        ivritDownloadProgress = 0

        let dir = ivritModelDirectory
        ivritDownloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await WhisperCoreMLTranscriber.downloadModel(to: dir) { frac, _, _ in
                    DispatchQueue.main.async {
                        self.ivritDownloadProgress = frac
                    }
                }
                await MainActor.run {
                    self.isDownloadingIvritModel = false
                    self.ivritDownloadTask = nil
                    self.refreshModelStatus()
                    let mStrings = FeatureStrings.transcriptionModels(L10n.shared.language)
                    QuickToolHUD.show(icon: "checkmark.circle", message: mStrings.ivritModelReadyHUD)
                    if let queued = self.pendingDropURL {
                        self.pendingDropURL = nil
                        self.transcribeFile(queued)
                    } else if self.pendingDictationAfterDownload {
                        self.pendingDictationAfterDownload = false
                        self.startDictationCapture()
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isDownloadingIvritModel = false
                    self.ivritDownloadTask = nil
                    self.pendingDropURL = nil
                    self.refreshModelStatus()
                }
            } catch WhisperCoreMLTranscriber.TranscriberError.cancelled {
                await MainActor.run {
                    self.isDownloadingIvritModel = false
                    self.ivritDownloadTask = nil
                    self.pendingDropURL = nil
                    self.refreshModelStatus()
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingIvritModel = false
                    self.ivritDownloadTask = nil
                    self.pendingDropURL = nil
                    self.errorMessage = error.localizedDescription
                    self.refreshModelStatus()
                }
            }
        }
    }

    func cancelIvritDownload() {
        ivritDownloadTask?.cancel()
        ivritDownloadTask = nil
        pendingDropURL = nil
        pendingDictationAfterDownload = false
        isDownloadingIvritModel = false
        refreshModelStatus()
    }

    func deleteIvritModel() {
        cancelIvritDownload()
        cancelTranscription()
        ivritEngine.evictCache()
        try? FileManager.default.removeItem(at: ivritModelDirectory)
        refreshModelStatus()
    }

    /// Runs per-segment language detection (when in `.auto` mode with both
    /// models installed) so bilingual ("Heblish") calls switch seamlessly
    /// between Parakeet Unified 0.6B (English) and ivrit.ai Whisper Large v3
    /// Turbo (Hebrew) on each speech region.
    private func transcribeRoutedSamples(_ samples: [Float],
                                         choice: TranscriptionModelChoice,
                                         computeMode: ParakeetComputeMode,
                                         speaker: String?,
                                         progress: (@Sendable (Double) -> Void)?) async throws
        -> (result: ParakeetCoreMLTranscriber.TranscriptionResult, detectedLanguage: String?) {
        let parakeetDir = modelDirectory
        let ivritDir = ivritModelDirectory
        let parakeetOK = AudioTranscriptionSupport.isModelDirectoryReady(parakeetDir)
        let ivritOK = AudioTranscriptionSupport.isIvritModelDirectoryReady(ivritDir)

        if choice == .auto, parakeetOK, ivritOK {
            let wallStart = Date()
            let sr = AudioTranscriptionSupport.sampleRate
            let totalDuration = Double(samples.count) / sr
            let chunks = AudioTranscriptionSupport.languageRoutingChunks(in: samples)
            guard !chunks.isEmpty else {
                return (
                    ParakeetCoreMLTranscriber.TranscriptionResult(
                        segments: [],
                        audioDurationSeconds: totalDuration,
                        elapsedSeconds: Date().timeIntervalSince(wallStart)
                    ),
                    nil
                )
            }

            var allSegments: [AudioTranscriptionSupport.TranscriptSegment] = []
            var detectedCodes: [String] = []

            for (index, chunk) in chunks.enumerated() {
                try Task.checkCancellation()
                let lo = max(0, Int(chunk.startSec * sr))
                let hi = min(samples.count, Int(chunk.endSec * sr))
                guard hi - lo >= Int(sr * 0.2) else { continue }
                let slice = Array(samples[lo..<hi])

                let probe = await detectSpokenLanguage(
                    samples: slice,
                    parakeetDir: parakeetDir,
                    ivritDir: ivritDir,
                    computeMode: computeMode
                )
                let resolved = AudioTranscriptionSupport.routeModel(
                    choice: .auto,
                    detectedLanguage: probe?.code,
                    confidence: probe?.confidence ?? 0,
                    parakeetReady: parakeetOK,
                    ivritReady: ivritOK
                )

                let chunkCount = Double(max(1, chunks.count))
                let baseFrac = Double(index) / chunkCount
                let chunkProgress: (@Sendable (Double) -> Void)? = progress.map { cb in
                    { @Sendable frac in cb(min(1.0, baseFrac + frac / chunkCount)) }
                }

                let chunkResult: ParakeetCoreMLTranscriber.TranscriptionResult
                let usedCode: String
                switch resolved {
                case .ivritHebrew:
                    chunkResult = try await ivritEngine.transcribe(
                        samples: slice,
                        modelDirectory: ivritDir,
                        computeMode: computeMode,
                        languageTokenID: AudioTranscriptionSupport.whisperHebrewToken,
                        speaker: speaker,
                        progress: chunkProgress
                    )
                    usedCode = "he"
                case .parakeetEnglish, nil:
                    chunkResult = try await engine.transcribe(
                        samples: slice,
                        modelDirectory: parakeetDir,
                        computeMode: computeMode,
                        speaker: speaker,
                        progress: chunkProgress
                    )
                    usedCode = "en"
                }

                if !chunkResult.segments.isEmpty {
                    let shifted = AudioTranscriptionSupport.shiftSegments(chunkResult.segments, by: chunk.startSec)
                    allSegments.append(contentsOf: shifted)
                    detectedCodes.append(usedCode)
                }
            }

            allSegments.sort { $0.startSeconds < $1.startSeconds }
            let summaryLang = AudioTranscriptionSupport.summarizeDetectedLanguages(detectedCodes)
            return (
                ParakeetCoreMLTranscriber.TranscriptionResult(
                    segments: allSegments,
                    audioDurationSeconds: totalDuration,
                    elapsedSeconds: Date().timeIntervalSince(wallStart)
                ),
                summaryLang
            )
        }

        let detectedCode: String? = switch choice {
        case .ivritHebrew: "he"
        case .parakeetEnglish: "en"
        case .auto: nil
        }
        let resolved = AudioTranscriptionSupport.routeModel(
            choice: choice,
            detectedLanguage: detectedCode,
            confidence: detectedCode == nil ? 0 : 1.0,
            parakeetReady: parakeetOK,
            ivritReady: ivritOK
        )

        switch resolved {
        case .ivritHebrew:
            let res = try await ivritEngine.transcribe(
                samples: samples,
                modelDirectory: ivritDir,
                computeMode: computeMode,
                languageTokenID: AudioTranscriptionSupport.whisperHebrewToken,
                speaker: speaker,
                progress: progress
            )
            return (res, detectedCode ?? "he")
        case .parakeetEnglish:
            let res = try await engine.transcribe(
                samples: samples,
                modelDirectory: parakeetDir,
                computeMode: computeMode,
                speaker: speaker,
                progress: progress
            )
            return (res, detectedCode ?? "en")
        case nil:
            throw choice == .ivritHebrew
                ? WhisperCoreMLTranscriber.TranscriberError.modelNotDownloaded
                : ParakeetCoreMLTranscriber.TranscriberError.modelNotDownloaded
        }
    }

    /// Two-signal on-device language detector for bilingual English/Hebrew
    /// workflows: combines Whisper's acoustic language probability with a fast
    /// Parakeet English plausibility check (protecting against fine-tune head
    /// bias on English clips).
    private func detectSpokenLanguage(samples: [Float],
                                      parakeetDir: URL,
                                      ivritDir: URL,
                                      computeMode: ParakeetComputeMode) async -> (code: String, confidence: Double)? {
        let regions = AudioTranscriptionSupport.speechRegions(in: samples)
        let sr = AudioTranscriptionSupport.sampleRate
        let probeSlice: [Float]
        if let longest = regions.max(by: { ($0.endSec - $0.startSec) < ($1.endSec - $1.startSec) }) {
            let lo = max(0, Int(longest.startSec * sr))
            let hi = min(samples.count, min(lo + Int(15 * sr), Int(longest.endSec * sr)))
            probeSlice = hi > lo ? Array(samples[lo..<hi]) : Array(samples.prefix(Int(15 * sr)))
        } else {
            probeSlice = Array(samples.prefix(Int(15 * sr)))
        }
        guard probeSlice.count >= Int(sr * 0.4) else { return nil }

        let whisperProbe = try? await ivritEngine.detectLanguage(
            samples: probeSlice,
            modelDirectory: ivritDir,
            computeMode: computeMode
        )

        if let whisperProbe, whisperProbe.englishProbability >= 0.55 {
            return ("en", whisperProbe.englishProbability)
        }

        // Because a Hebrew-specialized Whisper fine-tune can lean toward `he`
        // even on clean English speech, verify English plausibility via a fast
        // (~0.09 s) Parakeet probe + NLLanguageRecognizer before routing to `he`.
        if let parakeetRes = try? await engine.transcribe(
            samples: probeSlice,
            modelDirectory: parakeetDir,
            computeMode: computeMode,
            speaker: nil,
            progress: nil
        ) {
            let text = AudioTranscriptionSupport.formatTranscript(
                segments: parakeetRes.segments,
                includeTimestamps: false
            )
            let words = text.split(whereSeparator: { !$0.isLetter })
            if words.count >= 4 {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(text)
                let enHyp = recognizer.languageHypotheses(withMaximum: 3)[.english] ?? 0
                if enHyp >= 0.85, (whisperProbe?.hebrewProbability ?? 0) < 0.85 {
                    return ("en", enHyp)
                }
            }
        }

        if let whisperProbe {
            return (whisperProbe.topLanguageCode, whisperProbe.topConfidence)
        }
        return nil
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
                    } else if self.pendingDictationAfterDownload {
                        self.pendingDictationAfterDownload = false
                        self.startDictationCapture()
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isDownloadingModel = false
                    self.downloadTask = nil
                    self.pendingDropURL = nil
                    self.refreshModelStatus()
                }
            } catch ParakeetCoreMLTranscriber.TranscriberError.cancelled {
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
        if !activeModelReady {
            if modelChoice == .ivritHebrew {
                downloadIvritModel(thenTranscribe: url)
            } else {
                downloadModel(thenTranscribe: url)
            }
            return
        }

        transcribeTask?.cancel()
        summaryTask?.cancel()
        errorMessage = nil
        summaryText = ""
        lastSavedSummaryURL = nil
        lastDetectedLanguageCode = nil
        isTranscribing = true
        progress = 0
        currentFileName = url.lastPathComponent
        lastSourceURL = url
        lastSavedTranscriptURL = nil

        let choice = modelChoice
        let mode = computeMode
        let includeTimestamps = UserDefaults.standard.bool(forKey: DefaultsKey.audioTranscriptionIncludeTimestamps)
        let saveBeside = UserDefaults.standard.bool(forKey: DefaultsKey.audioTranscriptionSaveBesideAudio)

        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let samples = try await ParakeetCoreMLTranscriber.load16kMonoSamples(from: url)
                let routed = try await self.transcribeRoutedSamples(
                    samples,
                    choice: choice,
                    computeMode: mode,
                    speaker: nil
                ) { frac in
                    DispatchQueue.main.async {
                        self.progress = frac
                    }
                }
                let result = routed.result
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
                    self.lastDetectedLanguageCode = routed.detectedLanguage
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
                        if self.summaryEnabled {
                            let summaryDest = saveBeside ? AudioTranscriptionSupport.summaryFileURL(forAudioURL: url) : nil
                            self.generateSummary(for: formatted, saveDestination: summaryDest)
                        }
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
        guard activeModelReady else {
            errorMessage = strings.modelRequiredForAutoError
            if showHUD {
                QuickToolHUD.show(icon: "exclamationmark.triangle", message: strings.modelRequiredForAutoError)
            }
            return
        }
        guard systemURL != nil || micURL != nil else { return }

        transcribeTask?.cancel()
        summaryTask?.cancel()
        errorMessage = nil
        summaryText = ""
        lastSavedSummaryURL = nil
        lastDetectedLanguageCode = nil
        isTranscribing = true
        progress = 0
        currentFileName = MeetingRecorderSupport.displayLabel(fromStem: stem)
        lastSourceURL = micURL ?? systemURL
        lastSavedTranscriptURL = nil

        let choice = modelChoice
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
                var detectedCodes: [String] = []

                if let micURL {
                    let baseTracks = completedTracks
                    let samples = try await ParakeetCoreMLTranscriber.load16kMonoSamples(from: micURL)
                    let routed = try await self.transcribeRoutedSamples(
                        samples,
                        choice: choice,
                        computeMode: mode,
                        speaker: systemURL != nil ? micLabel : nil
                    ) { frac in
                        DispatchQueue.main.async {
                            self.progress = (Double(baseTracks) + frac) / Double(max(1, trackCount))
                        }
                    }
                    micSegments = routed.result.segments
                    maxDuration = max(maxDuration, routed.result.audioDurationSeconds)
                    if let lang = routed.detectedLanguage {
                        if lang == "mixed" {
                            detectedCodes.append(contentsOf: ["en", "he"])
                        } else {
                            detectedCodes.append(lang)
                        }
                    }
                    completedTracks += 1
                }

                if let systemURL {
                    let baseTracks = completedTracks
                    let samples = try await ParakeetCoreMLTranscriber.load16kMonoSamples(from: systemURL)
                    let routed = try await self.transcribeRoutedSamples(
                        samples,
                        choice: choice,
                        computeMode: mode,
                        speaker: micURL != nil ? systemLabel : nil
                    ) { frac in
                        DispatchQueue.main.async {
                            self.progress = (Double(baseTracks) + frac) / Double(max(1, trackCount))
                        }
                    }
                    sysSegments = routed.result.segments
                    maxDuration = max(maxDuration, routed.result.audioDurationSeconds)
                    if let lang = routed.detectedLanguage {
                        if lang == "mixed" {
                            detectedCodes.append(contentsOf: ["en", "he"])
                        } else {
                            detectedCodes.append(lang)
                        }
                    }
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
                let finalDetectedLang = AudioTranscriptionSupport.summarizeDetectedLanguages(detectedCodes)
                let elapsed = Date().timeIntervalSince(wallStart)
                await MainActor.run {
                    self.isTranscribing = false
                    self.transcribeTask = nil
                    self.progress = 1
                    self.segments = merged
                    self.transcriptText = formatted
                    self.lastDetectedLanguageCode = finalDetectedLang
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
                        if self.summaryEnabled {
                            let summaryDest = AudioTranscriptionSupport.meetingSummaryFileURL(stem: stem, in: outputDir)
                            self.generateSummary(for: formatted, saveDestination: summaryDest)
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
        summaryTask?.cancel()
        summaryTask = nil
        isSummarizing = false
        transcriptText = ""
        summaryText = ""
        summaryUsedOnDeviceLLM = false
        summaryProviderName = nil
        segments = []
        lastDurationSeconds = 0
        lastProcessingSeconds = 0
        lastSourceURL = nil
        lastSavedTranscriptURL = nil
        lastSavedSummaryURL = nil
        errorMessage = nil
    }

    func selectRecent(_ item: RecentTranscript) {
        summaryTask?.cancel()
        summaryTask = nil
        isSummarizing = false
        transcriptText = item.text
        summaryText = item.summary ?? ""
        lastSourceURL = item.sourceURL
        lastSavedTranscriptURL = item.savedTranscriptURL
        lastSavedSummaryURL = item.savedSummaryURL
        lastDurationSeconds = item.durationSeconds
        currentFileName = item.title
        errorMessage = nil
    }

    // MARK: - Summary Generation

    func summarizeCurrentTranscript() {
        guard !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let saveBeside = UserDefaults.standard.bool(forKey: DefaultsKey.audioTranscriptionSaveBesideAudio)
        let saveDest: URL?
        if let saved = lastSavedTranscriptURL {
            saveDest = saved.deletingLastPathComponent()
                .appendingPathComponent(
                    saved.deletingPathExtension().lastPathComponent
                        .replacingOccurrences(of: "-transcript", with: "") + "-summary.md"
                )
        } else if saveBeside, let source = lastSourceURL {
            saveDest = AudioTranscriptionSupport.summaryFileURL(forAudioURL: source)
        } else {
            saveDest = nil
        }
        generateSummary(for: transcriptText, saveDestination: saveDest)
    }

    func resetSummaryPrompt() {
        UserDefaults.standard.set(AudioTranscriptionSupport.defaultSummaryPrompt,
                                  forKey: DefaultsKey.audioTranscriptionSummaryPrompt)
    }

    func copySummary() {
        guard !summaryText.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(summaryText, forType: .string)
        let extras = FeatureStrings.audioTranscriptionExtras(L10n.shared.language)
        QuickToolHUD.show(icon: "doc.on.doc", message: extras.summaryCopiedHUD)
    }

    func saveSummaryAs() {
        guard !summaryText.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let defaultName = lastSourceURL.map { "\($0.deletingPathExtension().lastPathComponent)-summary.md" }
            ?? "summary.md"
        panel.nameFieldStringValue = defaultName
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try summaryText.write(to: url, atomically: true, encoding: .utf8)
                lastSavedSummaryURL = url
                let extras = FeatureStrings.audioTranscriptionExtras(L10n.shared.language)
                QuickToolHUD.show(icon: "checkmark.circle", message: extras.summarySavedHUD)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func generateSummary(for text: String, saveDestination: URL?) {
        summaryTask?.cancel()
        let prompt = summaryPrompt
        let provider = summaryProvider
        let model = summaryModel
        isSummarizing = true
        summaryText = ""
        summaryProviderName = nil
        lastSavedSummaryURL = nil

        summaryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await TranscriptSummarizer.summarize(
                    transcript: text,
                    prompt: prompt,
                    provider: provider,
                    model: model
                )
                var savedSummaryURL: URL?
                if let saveDestination, !result.text.isEmpty {
                    if (try? result.text.write(to: saveDestination, atomically: true, encoding: .utf8)) != nil {
                        savedSummaryURL = saveDestination
                    }
                }
                let finalSavedURL = savedSummaryURL
                await MainActor.run {
                    self.isSummarizing = false
                    self.summaryTask = nil
                    self.summaryText = result.text
                    self.summaryUsedOnDeviceLLM = result.usedOnDeviceLLM
                    self.summaryProviderName = result.providerDisplayName
                    self.lastSavedSummaryURL = finalSavedURL
                    if let idx = self.recentTranscripts.firstIndex(where: { $0.text == text }) {
                        let existing = self.recentTranscripts[idx]
                        self.recentTranscripts[idx] = RecentTranscript(
                            id: existing.id,
                            title: existing.title,
                            sourceURL: existing.sourceURL,
                            savedTranscriptURL: existing.savedTranscriptURL,
                            text: existing.text,
                            summary: result.text,
                            savedSummaryURL: finalSavedURL,
                            createdAt: existing.createdAt,
                            durationSeconds: existing.durationSeconds
                        )
                    }
                    if finalSavedURL != nil {
                        MeetingRecorderService.shared.refreshRecordings()
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.isSummarizing = false
                    self.summaryTask = nil
                }
            } catch {
                await MainActor.run {
                    self.isSummarizing = false
                    self.summaryTask = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - System-Wide Voice Dictation

    private func handleDictationHotkeyPressed() {
        switch dictationTriggerMode {
        case .toggle:
            toggleSystemDictation()
        case .holdToTalk:
            guard !isDictating else { return }
            holdDictationActive = true
            startSystemDictation()
        }
    }

    private func handleDictationHotkeyReleased() {
        guard dictationTriggerMode == .holdToTalk, holdDictationActive else { return }
        holdDictationActive = false
        if isDictating {
            finishDictationAndInsert()
        }
    }

    func toggleSystemDictation() {
        if isDictating {
            finishDictationAndInsert()
        } else {
            startSystemDictation()
        }
    }

    func startSystemDictation() {
        guard !isDictating else { return }
        let extras = FeatureStrings.audioTranscriptionExtras(L10n.shared.language)
        refreshModelStatus()
        guard activeModelReady else {
            pendingDictationAfterDownload = true
            QuickToolHUD.show(icon: "arrow.down.circle", message: extras.dictationModelMissingHUD)
            if modelChoice == .ivritHebrew {
                downloadIvritModel()
            } else {
                downloadModel()
            }
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startDictationCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.startDictationCapture()
                    } else {
                        self.errorMessage = extras.dictationMicDeniedError
                        QuickToolHUD.show(icon: "mic.slash", message: extras.dictationMicDeniedError)
                    }
                }
            }
        default:
            errorMessage = extras.dictationMicDeniedError
            QuickToolHUD.show(icon: "mic.slash", message: extras.dictationMicDeniedError)
        }
    }

    private func startDictationCapture() {
        guard !isDictating else { return }
        let extras = FeatureStrings.audioTranscriptionExtras(L10n.shared.language)
        errorMessage = nil
        do {
            try dictationRecorder.start { [weak self] level in
                DispatchQueue.main.async {
                    self?.dictationLevel = level
                }
            }
            isDictating = true
            dictationStartedAt = Date()
            dictationElapsedSeconds = 0
            dictationTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self, let started = self.dictationStartedAt else { return }
                self.dictationElapsedSeconds = max(0, Int(Date().timeIntervalSince(started).rounded(.down)))
            }
            RunLoop.main.add(timer, forMode: .common)
            dictationTimer = timer
            let hudMessage = dictationTriggerMode == .holdToTalk
                ? FeatureStrings.summaryProviders(L10n.shared.language).dictationHoldListeningHUD
                : extras.dictationListeningHUD
            QuickToolHUD.show(icon: "mic.fill", message: hudMessage)
        } catch {
            isDictating = false
            holdDictationActive = false
            dictationLevel = 0
            errorMessage = error.localizedDescription
        }
    }

    func cancelDictation() {
        dictationTimer?.invalidate()
        dictationTimer = nil
        dictationStartedAt = nil
        dictationElapsedSeconds = 0
        dictationLevel = 0
        isDictating = false
        holdDictationActive = false
        pendingDictationAfterDownload = false
        dictationRecorder.stopAndDiscard()
    }

    private func finishDictationAndInsert() {
        dictationTimer?.invalidate()
        dictationTimer = nil
        dictationStartedAt = nil
        dictationElapsedSeconds = 0
        dictationLevel = 0
        isDictating = false

        let samples = dictationRecorder.stop()
        let strings = FeatureStrings.audioTranscription(L10n.shared.language)
        let extras = FeatureStrings.audioTranscriptionExtras(L10n.shared.language)
        guard samples.count >= Int(AudioTranscriptionSupport.sampleRate * 0.15) else {
            QuickToolHUD.show(icon: "waveform", message: strings.noSpeechDetected)
            return
        }

        transcribeTask?.cancel()
        summaryTask?.cancel()
        errorMessage = nil
        summaryText = ""
        lastSavedSummaryURL = nil
        isTranscribing = true
        progress = 0
        currentFileName = extras.dictationTitle
        lastSourceURL = nil
        lastSavedTranscriptURL = nil

        let choice = modelChoice
        let mode = computeMode

        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let routed = try await self.transcribeRoutedSamples(
                    samples,
                    choice: choice,
                    computeMode: mode,
                    speaker: nil
                ) { frac in
                    DispatchQueue.main.async {
                        self.progress = frac
                    }
                }
                let result = routed.result
                let text = AudioTranscriptionSupport.formatTranscript(
                    segments: result.segments,
                    includeTimestamps: false
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                await MainActor.run {
                    self.isTranscribing = false
                    self.transcribeTask = nil
                    self.progress = 1
                    self.segments = result.segments
                    self.transcriptText = text
                    self.lastDetectedLanguageCode = routed.detectedLanguage
                    self.lastDurationSeconds = result.audioDurationSeconds
                    self.lastProcessingSeconds = result.elapsedSeconds
                    if text.isEmpty {
                        self.errorMessage = strings.noSpeechDetected
                        QuickToolHUD.show(icon: "waveform", message: strings.noSpeechDetected)
                    } else {
                        self.recordRecent(
                            title: extras.dictationTitle,
                            sourceURL: URL(fileURLWithPath: "/dev/null"),
                            savedURL: nil,
                            text: text,
                            duration: result.audioDurationSeconds
                        )
                        if AXIsProcessTrusted() {
                            _ = TransientPaste.shared.paste(text)
                            QuickToolHUD.show(icon: "text.cursor", message: extras.dictationInsertedHUD)
                        } else {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(text, forType: .string)
                            QuickToolHUD.show(icon: "doc.on.doc", message: extras.dictationCopiedHUD)
                        }
                        if self.summaryEnabled {
                            self.generateSummary(for: text, saveDestination: nil)
                        }
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
            summary: nil,
            savedSummaryURL: nil,
            createdAt: Date(),
            durationSeconds: duration
        )
        recentTranscripts.insert(entry, at: 0)
        if recentTranscripts.count > 15 {
            recentTranscripts.removeLast(recentTranscripts.count - 15)
        }
    }
}
