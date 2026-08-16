// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

enum VideoDownloaderPhase: Equatable {
    case idle
    case inspecting
    case ready
    case settingUp
    case downloading
    case finalizing
    case cancelling
    case completed
    case failed
    case cancelled

    var locksRequest: Bool {
        switch self {
        case .settingUp, .downloading, .finalizing, .cancelling: return true
        default: return false
        }
    }
}

enum VideoDownloaderDependencyState: Equatable {
    case probing(previous: VideoDownloaderDependencies?)
    case resolved(VideoDownloaderDependencies)

    var value: VideoDownloaderDependencies? {
        switch self {
        case let .probing(previous): return previous
        case let .resolved(value): return value
        }
    }

    var isProbing: Bool {
        if case .probing = self { return true }
        return false
    }
}

final class VideoDownloaderWorkflow: ObservableObject {
    /// Generational token gate for asynchronous callbacks. Keeps the UI state in sync
    /// and guarantees stale network completions or background tasks don't overwrite newer user actions.
    private struct OperationRegistry {
        enum ProcessKind: Equatable {
            case download
            case setup
        }

        private struct Process {
            let id: UUID
            let kind: ProcessKind
        }

        private var inspectionID = UUID()
        private var dependencyProbeID = UUID()
        private var process: Process?

        var currentInspectionID: UUID { inspectionID }
        var activeProcessKind: ProcessKind? { process?.kind }

        mutating func beginInspection() -> UUID {
            inspectionID = UUID()
            return inspectionID
        }

        mutating func invalidateInspection() {
            inspectionID = UUID()
        }

        func acceptsInspection(_ callbackID: UUID) -> Bool {
            VideoDownloaderCallbackGate.accepts(callbackID, currentID: inspectionID)
        }

        mutating func beginDependencyProbe() -> UUID {
            dependencyProbeID = UUID()
            return dependencyProbeID
        }

        mutating func invalidateDependencyProbe() {
            dependencyProbeID = UUID()
        }

        func acceptsDependencyProbe(_ callbackID: UUID) -> Bool {
            VideoDownloaderCallbackGate.accepts(callbackID, currentID: dependencyProbeID)
        }

        mutating func beginProcess(_ kind: ProcessKind) -> UUID {
            let id = UUID()
            process = Process(id: id, kind: kind)
            return id
        }

        func acceptsProcess(_ callbackID: UUID) -> Bool {
            guard let process else { return false }
            return VideoDownloaderCallbackGate.accepts(callbackID, currentID: process.id)
        }

        mutating func finishProcess(_ callbackID: UUID) -> ProcessKind? {
            guard let process, acceptsProcess(callbackID) else { return nil }
            self.process = nil
            return process.kind
        }

        func hasProcess(_ kind: ProcessKind) -> Bool {
            process?.kind == kind
        }

        mutating func clearProcess() {
            process = nil
        }

        mutating func invalidateAll() {
            inspectionID = UUID()
            dependencyProbeID = UUID()
            process = nil
        }
    }

    private static var sharedInstance: VideoDownloaderWorkflow?

    static var shared: VideoDownloaderWorkflow {
        if let sharedInstance { return sharedInstance }
        let workflow = VideoDownloaderWorkflow()
        sharedInstance = workflow
        return workflow
    }

    static func syncRuntimeIfNeeded() {
        guard sharedInstance != nil else { return }
        shared.syncWithFeature()
    }

    static func applicationBecameActiveIfNeeded() {
        guard sharedInstance != nil else { return }
        shared.applicationBecameActive()
    }

    static func terminateLoaded(completion: @escaping () -> Void) {
        guard let sharedInstance else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        sharedInstance.terminate(completion: completion)
    }

    @Published private(set) var phase: VideoDownloaderPhase = .idle
    @Published private(set) var sourceText = ""
    @Published private(set) var media: VideoDownloaderMedia?
    @Published private(set) var mode: VideoDownloaderOutputMode = .video
    @Published private(set) var quality: VideoDownloaderQuality = .best
    @Published private(set) var subtitle: VideoDownloaderSubtitleTrack?
    @Published private(set) var subtitlesEnabled = false
    @Published private(set) var destination: URL
    @Published private(set) var dependencyState: VideoDownloaderDependencyState = .probing(previous: nil)
    @Published private(set) var progress = VideoDownloaderProgress(fraction: nil,
                                                                    speedBytesPerSecond: nil,
                                                                    etaSeconds: nil)
    @Published private(set) var activeTitle: String?
    @Published private(set) var qualityFallback: VideoDownloaderQualityFallback?
    @Published private(set) var completedFile: URL?
    @Published private(set) var warnings: [VideoDownloaderWarning] = []
    @Published private(set) var failure: VideoDownloaderFailure?
    @Published private(set) var validationError: VideoURLValidationError?
    /// Stores soft inspection failures (like broken metadata JSON) so we can explain to the user
    /// why thumbnails and resolution selectors are unavailable while still letting them download.
    @Published private(set) var inspectionNotice: VideoDownloaderFailure?
    @Published private(set) var terminalSetupPending = false

    private let service: VideoDownloaderProcessServicing
    private let mutationGate: HomebrewMutationGate
    private let brewPathProvider: () -> String?
    private let terminalInstallerOpener: ([String], Bool) -> Bool
    private let featureAvailability: () -> Bool
    private var operations = OperationRegistry()
    private var debounce: DispatchWorkItem?
    private var pendingValidatedSource: ValidatedVideoURL?
    private var hasPreparedDestination = false
    private var videoSubtitlesPreference: Bool?

    init(service: VideoDownloaderProcessServicing = VideoDownloaderProcessService.shared,
         mutationGate: HomebrewMutationGate = .shared,
         brewPathProvider: @escaping () -> String? = { VideoDownloaderDependencySupport.brewPath() },
         terminalInstallerOpener: @escaping ([String], Bool) -> Bool = { formulae, installHomebrew in
             HomebrewManager.shared.openVideoDownloaderInstaller(
                 formulae: formulae,
                 installHomebrew: installHomebrew)
         },
         featureAvailability: @escaping () -> Bool = { AppFeature.videoDownloader.isAvailable },
         automaticallyProbe: Bool = true) {
        self.service = service
        self.mutationGate = mutationGate
        self.brewPathProvider = brewPathProvider
        self.terminalInstallerOpener = terminalInstallerOpener
        self.featureAvailability = featureAvailability
        let saved = UserDefaults.standard.string(forKey: DefaultsKey.videoDownloaderDestinationPath)
        destination = VideoDownloaderDestinationSupport.configured(savedPath: saved)
        if automaticallyProbe { refreshDependencies() }
    }


    var canDownload: Bool {
        guard featureAvailability(), phase == .ready, dependencyState.value?.isReady == true,
              let media, !sourceText.isEmpty else { return false }
        switch mode {
        case .video: return media.canAttemptVideo
        case .audio: return media.canAttemptAudio
        }
    }

    var missingTools: Set<VideoDownloaderTool> {
        dependencyState.isProbing && dependencyState.value == nil
            ? [] : (dependencyState.value?.missing ?? [])
    }
    var isProbingDependencies: Bool { dependencyState.isProbing }
    /// Preserve the previous dependency snapshot during background re-checks so the UI doesn't
    /// flash an unnecessary loading skeleton when tools are already installed.
    var isInitialDependencyProbe: Bool {
        dependencyState.isProbing && dependencyState.value == nil
    }
    var canSetupDependencies: Bool {
        featureAvailability()
            && !terminalSetupPending
            && !dependencyState.isProbing
            && !missingTools.isEmpty
            && !phase.locksRequest
            && phase != .inspecting
    }
    var canCancelSetup: Bool {
        phase == .settingUp && operations.hasProcess(.setup)
    }
    var isCancellingSetup: Bool {
        phase == .cancelling && operations.activeProcessKind == .setup
    }
    func setSourceText(_ value: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !phase.locksRequest else { return }
        sourceText = value
        debounce?.cancel()
        debounce = nil
        let generation = operations.beginInspection()
        service.cancelInspection(wait: false)
        resetSourceState()
        progress = VideoDownloaderProgress(fraction: nil, speedBytesPerSecond: nil, etaSeconds: nil)
        do {
            let source = try VideoDownloaderURLValidator.validate(value)
            validationError = nil
            pendingValidatedSource = source
            phase = .idle
            let item = DispatchWorkItem { [weak self] in
                self?.beginInspection(source, id: generation)
            }
            debounce = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        } catch let error as VideoURLValidationError {
            validationError = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : error
            phase = .idle
        } catch {
            validationError = .malformed
            phase = .idle
        }
    }

    func pasteURL() {
        GeneralPasteboardAccess.shared.async { [weak self] in
            let value = NSPasteboard.general.string(forType: .string) ?? ""
            DispatchQueue.main.async { self?.setSourceText(value) }
        }
    }

    func startDownload() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard canDownload,
              let media, let source = pendingValidatedSource else { return }
        beginDownload(source: source, media: media)
    }

    private func beginDownload(source: ValidatedVideoURL,
                               media: VideoDownloaderMedia) {
        let defaults = UserDefaults.standard
        let currentDestination = VideoDownloaderDestinationSupport.resolved(
            savedPath: defaults.string(forKey: DefaultsKey.videoDownloaderDestinationPath))
        destination = currentDestination
        let snapshot = VideoDownloaderEmbeddingOptions(
            thumbnail: defaults.bool(forKey: DefaultsKey.videoDownloaderEmbedThumbnail),
            metadata: defaults.bool(forKey: DefaultsKey.videoDownloaderEmbedMetadata),
            chapters: defaults.bool(forKey: DefaultsKey.videoDownloaderEmbedChapters)
        )
        let id = operations.beginProcess(.download)
        failure = nil
        inspectionNotice = nil
        completedFile = nil
        warnings = []
        activeTitle = media.title
        qualityFallback = nil
        progress = VideoDownloaderProgress(fraction: nil, speedBytesPerSecond: nil, etaSeconds: nil)
        phase = .downloading
        let request = VideoDownloaderRequest(source: source,
                                             mode: mode,
                                             quality: quality,
                                             subtitle: mode == .video && subtitlesEnabled ? subtitle : nil,
                                             destination: currentDestination,
                                             media: media,
                                             options: snapshot)
        service.download(request, id: id, progress: { [weak self] callbackID, event in
            guard let self, self.operations.acceptsProcess(callbackID) else { return }
            switch event {
            case let .progress(value):
                guard self.phase != .cancelling else { return }
                self.progress = value
                self.phase = value.isNetworkComplete ? .finalizing : .downloading
            case let .title(title):
                self.activeTitle = title
            case let .selectedVideoHeight(actualHeight):
                // Separate audio streams report height as nil; ignore them so they don't overwrite
                // the recorded video height resolution.
                if let actualHeight {
                    self.qualityFallback = VideoDownloaderQualityFallback.detect(
                        requested: request.quality,
                        actualHeight: actualHeight
                    )
                }
            }
        }, completion: { [weak self] callbackID, result in
            guard let self,
                  self.operations.finishProcess(callbackID) == .download else { return }
            switch result {
            case let .success(result):
                self.completedFile = result.file
                self.warnings = result.warnings
                self.progress = VideoDownloaderProgress(fraction: 1,
                                                        speedBytesPerSecond: nil,
                                                        etaSeconds: nil)
                self.phase = .completed
            case let .failure(error):
                if error == .cancelled {
                    self.phase = .cancelled
                    self.failure = nil
                } else {
                    self.fail(error)
                }
            }
        })
    }

    func setMode(_ value: VideoDownloaderOutputMode) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !phase.locksRequest else { return }
        // Allow mode switching freely; `canDownload` acts as the safety gate so unavailable options
        // remain visible for discovery without starting broken transfers.
        let previousMode = mode
        mode = value
        if previousMode == .video, value == .audio {
            videoSubtitlesPreference = subtitlesEnabled
            subtitlesEnabled = false
        } else if previousMode == .audio, value == .video {
            let preferred = videoSubtitlesPreference ?? false
            subtitlesEnabled = preferred && subtitle != nil
        }
    }

    func setQuality(_ value: VideoDownloaderQuality) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !phase.locksRequest, quality != value else { return }
        quality = value
    }

    func setSubtitlesEnabled(_ enabled: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !phase.locksRequest else { return }
        guard mode == .video else {
            subtitlesEnabled = false
            return
        }
        if enabled, subtitle == nil, let media {
            subtitle = VideoDownloaderSubtitleSelection.defaultTrack(
                in: media.subtitleOptions,
                appLanguage: L10n.shared.language
            )
        }
        subtitlesEnabled = enabled && subtitle != nil
        videoSubtitlesPreference = subtitlesEnabled
    }

    func selectSubtitle(id: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard mode == .video, !phase.locksRequest, let media,
              let track = media.subtitleOptions.first(where: { $0.id == id }) else { return }
        subtitle = track
    }

    func cancelActiveOperation() {
        dispatchPrecondition(condition: .onQueue(.main))
        switch operations.activeProcessKind {
        case .download:
            guard [.downloading, .finalizing, .cancelling].contains(phase) else { return }
            phase = .cancelling
            service.cancelDownload(wait: false)
        case .setup:
            // Keep showing "Cancelling" until all child processes and pipe reader threads have safely terminated.
            guard phase == .settingUp else { return }
            phase = .cancelling
            service.cancelSetup(wait: false)
        case nil:
            break
        }
    }

    func retry() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard featureAvailability() else {
            failure = nil
            phase = .cancelled
            return
        }
        if let failure, [.setupBusy, .setupFailed, .terminalPermission, .missingDependencies].contains(failure),
           !missingTools.isEmpty {
            self.failure = nil
            phase = .idle
            setupDependencies()
            return
        }
        failure = nil
        if inspectionNotice != nil {
            // If metadata inspection failed earlier, retrying should re-run inspection first
            // rather than jumping straight to downloading without stream information.
            inspectionNotice = nil
            if let source = pendingValidatedSource {
                phase = .idle
                beginInspection(source, id: operations.beginInspection())
            } else {
                phase = .idle
            }
        } else if media != nil, dependencyState.value?.isReady == true {
            phase = .ready
            startDownload()
        } else if let source = pendingValidatedSource {
            phase = .idle
            beginInspection(source, id: operations.beginInspection())
        } else {
            phase = .idle
        }
    }

    func downloadAnother() {
        dispatchPrecondition(condition: .onQueue(.main))
        operations.clearProcess()
        sourceText = ""
        resetSourceState()
        validationError = nil
        phase = .idle
    }

    func revealCompletedFile() {
        guard let completedFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([completedFile])
    }

    func setDestination(_ url: URL) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !phase.locksRequest else { return }
        let resolved = VideoDownloaderDestinationSupport.resolved(savedPath: url.path)
        destination = resolved
        hasPreparedDestination = true
        UserDefaults.standard.set(resolved.path, forKey: DefaultsKey.videoDownloaderDestinationPath)
        VideoDownloaderFileSupport.cleanupStaleDirectories(in: resolved)
    }

    func resetDestination() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !phase.locksRequest else { return }
        UserDefaults.standard.removeObject(forKey: DefaultsKey.videoDownloaderDestinationPath)
        destination = VideoDownloaderDestinationSupport.resolved(savedPath: nil)
        hasPreparedDestination = true
        VideoDownloaderFileSupport.cleanupStaleDirectories(in: destination)
    }

    func prepareForUse() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard featureAvailability(), !hasPreparedDestination else { return }
        let resolved = VideoDownloaderDestinationSupport.resolved(
            savedPath: UserDefaults.standard.string(forKey: DefaultsKey.videoDownloaderDestinationPath))
        destination = resolved
        hasPreparedDestination = true
        VideoDownloaderFileSupport.cleanupStaleDirectories(in: resolved)
    }

    func setupDependencies() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard canSetupDependencies else { return }
        let missing = missingTools
        let formulae = VideoDownloaderTerminalSetup.formulae(for: missing)
        failure = nil
        phase = .settingUp
        // Invalidate probe tokens that started before Homebrew ran so only post-install scans determine success.
        operations.invalidateDependencyProbe()
        if let brew = brewPathProvider() {
            let id = operations.beginProcess(.setup)
            service.installMissingTools(brewPath: brew, missing: missing,
                                        id: id) {
                [weak self] callbackID, result in
                guard let self,
                      self.operations.finishProcess(callbackID) == .setup else { return }
                switch result {
                case .success:
                    guard self.featureAvailability() else {
                        self.phase = .cancelled
                        return
                    }
                    self.beginDependencyProbe(context: .directSetup)
                case let .failure(error):
                    if error == .cancelled {
                        self.phase = .cancelled
                    } else if error == .terminalPermission {
                        guard self.handoffSetupToTerminal(formulae: formulae,
                                                         installHomebrew: false) else {
                            self.fail(.terminalPermission)
                            return
                        }
                    } else {
                        self.fail(error)
                    }
                }
            }
        } else {
            // When Homebrew requires sudo or interactive prompts, hand off to Terminal.
            // We pause background polling until the user returns so we don't race the active installer.
            guard handoffSetupToTerminal(formulae: formulae,
                                         installHomebrew: true) else {
                fail(.terminalPermission)
                return
            }
        }
    }

    @discardableResult
    private func handoffSetupToTerminal(formulae: [String], installHomebrew: Bool) -> Bool {
        guard terminalInstallerOpener(formulae, installHomebrew) else { return false }
        // Track that Terminal setup was offered so the settings view knows the installer was triggered.
        UserDefaults.standard.set(true, forKey: DefaultsKey.videoDownloaderTerminalSetupUsed)
        terminalSetupPending = true
        phase = .idle
        return true
    }

    /// Re-check tools after the user completes installation in Terminal and switches back to the app.
    func checkDependencies() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard featureAvailability() else { return }
        terminalSetupPending = false
        refreshDependencies()
    }

    func refreshDependencies(retryInspection: Bool = false) {
        guard featureAvailability() else { return }
        guard !terminalSetupPending else { return }
        guard phase != .settingUp else {
            // Avoid running concurrent filesystem probes while direct setup is still finishing its own install pass.
            return
        }
        beginDependencyProbe(context: .refresh(retryInspection: retryInspection))
    }

    func applicationBecameActive() {
        if terminalSetupPending { terminalSetupPending = false }
        refreshDependencies(retryInspection: allowsAutomaticInspection)
    }

    func syncWithFeature() {
        if featureAvailability() {
            refreshDependencies(retryInspection: allowsAutomaticInspection)
        } else {
            debounce?.cancel()
            service.cancelAll {}
            operations.invalidateAll()
            terminalSetupPending = false
            phase = .cancelled
        }
    }

    func terminate(completion: @escaping () -> Void) {
        debounce?.cancel()
        operations.invalidateAll()
        service.cancelAll { completion() }
    }

    private func beginInspection(_ source: ValidatedVideoURL, id: UUID) {
        guard operations.acceptsInspection(id),
              featureAvailability(),
              [.idle, .inspecting, .ready].contains(phase),
              !phase.locksRequest else { return }
        // When the app gains focus, don't restart inspection if the active task is already inspecting this exact URL.
        guard !(phase == .inspecting && pendingValidatedSource == source) else { return }
        guard dependencyState.value?.paths[.ytDlp] != nil else {
            phase = .idle
            return
        }
        phase = .inspecting
        validationError = nil
        failure = nil
        inspectionNotice = nil
        service.inspect(source, id: id) { [weak self] callbackID, result in
            guard let self,
                  self.operations.acceptsInspection(callbackID),
                  self.pendingValidatedSource == source else { return }
            switch result {
            case let .success(media):
                self.media = media
                self.inspectionNotice = nil
                // If the video has no audio track, reset mode from Audio back to Video to avoid requesting impossible audio extractions.
                if media.audioAvailability == .unavailable {
                    self.mode = .video
                }
                self.quality = VideoDownloaderQuality.highest(in: media.heights)
                self.subtitle = VideoDownloaderSubtitleSelection.defaultTrack(
                    in: media.subtitleOptions,
                    appLanguage: L10n.shared.language
                )
                // Keep subtitles opt-in by default to protect against extractor rate-limiting and 429 errors.
                let preferred = self.videoSubtitlesPreference ?? false
                self.subtitlesEnabled = preferred && self.mode == .video && self.subtitle != nil
                self.phase = .ready
            case let .failure(error):
                guard error != .cancelled else { return }
                // DRM, live streams, and playlists cannot be downloaded and are rejected immediately.
                // Restricted content can proceed if browser cookies are enabled so yt-dlp can attempt authenticated retrieval.
                let authenticatedContentAllowed = VideoDownloaderCookiesSupport.selectedBrowser() != nil
                let hardRejection = [.playlist, .live, .drm].contains(error)
                    || error == .cookiesPermission
                    || (error == .restricted && !authenticatedContentAllowed)
                if hardRejection {
                    self.media = nil
                    self.inspectionNotice = nil
                    self.fail(error)
                    return
                }
                // If metadata inspection fails softly (e.g. site changed its webpage layout), keep the fallback
                // shell so the user can still attempt direct downloading.
                self.media = VideoDownloaderMedia.fallback(for: source)
                self.inspectionNotice = error
                self.quality = .best
                // When stream capabilities are unknown, reset to the universal video mode to avoid broken audio-only assumptions.
                self.mode = .video
                self.subtitle = nil
                self.subtitlesEnabled = false
                self.failure = nil
                self.phase = .ready
            }
        }
    }

    private func resetSourceState() {
        media = nil
        subtitle = nil
        subtitlesEnabled = false
        quality = .best
        completedFile = nil
        warnings = []
        activeTitle = nil
        qualityFallback = nil
        failure = nil
        inspectionNotice = nil
        pendingValidatedSource = nil
        videoSubtitlesPreference = nil
    }

    private func fail(_ error: VideoDownloaderFailure) {
        failure = error
        phase = .failed
    }

    private enum DependencyProbeContext {
        case refresh(retryInspection: Bool)
        case directSetup
    }

    private func beginDependencyProbe(context: DependencyProbeContext) {
        guard featureAvailability() else { return }
        let id = operations.beginDependencyProbe()
        dependencyState = .probing(previous: dependencyState.value)
        service.probeDependencies { [weak self] dependencies in
            guard let self,
                  self.operations.acceptsDependencyProbe(id) else { return }
            switch context {
            case let .refresh(retryInspection):
                self.dependencyState = .resolved(dependencies)
                if self.phase == .settingUp {
                    if !self.operations.hasProcess(.setup) {
                        if dependencies.isReady {
                            self.phase = .idle
                        } else {
                            self.fail(.setupFailed)
                        }
                    }
                }
                if self.featureAvailability(), self.allowsAutomaticInspection,
                   retryInspection || (dependencies.paths[.ytDlp] != nil && self.media == nil) {
                    if let source = self.pendingValidatedSource {
                        self.beginInspection(source, id: self.operations.currentInspectionID)
                    }
                }
            case .directSetup:
                self.dependencyState = .resolved(dependencies)
                guard dependencies.isReady else {
                    self.fail(.setupFailed)
                    return
                }
                self.phase = .idle
                if let source = self.pendingValidatedSource {
                    self.beginInspection(source, id: self.operations.currentInspectionID)
                }
            }
        }
    }

    private var allowsAutomaticInspection: Bool {
        featureAvailability() && media == nil && [.idle, .inspecting, .ready].contains(phase)
    }

}
