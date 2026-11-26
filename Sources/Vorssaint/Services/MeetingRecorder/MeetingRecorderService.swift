// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Coordinates Stalkrr-style dual-track meeting recording (system audio +
/// microphone into separate WAVs), automatic call detection, capture-health
/// watchdogs, and Vorssaint's floating recording pill.
final class MeetingRecorderService: ObservableObject {
    static let shared = MeetingRecorderService()

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var isListeningForCalls = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var detectedAppName: String?
    @Published private(set) var systemTrackActive = false
    @Published private(set) var micTrackActive = false
    @Published private(set) var micLevels: [Float] = Array(repeating: 0, count: 18)
    @Published private(set) var systemLevels: [Float] = Array(repeating: 0, count: 18)
    @Published private(set) var warningMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var systemAudioPermission: MeetingAudioPermission.State = .undetermined
    @Published private(set) var recentRecordings: [MeetingRecorderSupport.RecordingSummary] = []

    private var session: MeetingCaptureSession?
    private var currentSessionAutomatic = false
    private var decider = MeetingAutoRecordDecider(ownPID: getpid())
    private var detectorQueue = DispatchQueue(label: "com.vorssaint.utils.meeting.detector", qos: .utility)
    private var detectorTimer: DispatchSourceTimer?
    private var elapsedTimer: Timer?
    private var meterTimer: Timer?
    private var healthTimer: Timer?
    private var indicator: RecorderIndicator?
    private var micHealth = MeetingStreamHealth()
    private var systemHealth = MeetingStreamHealth()
    private var lastObservedSystemBytes: Int64 = 0
    private var micSilentWindows = 0
    private var micSilentWarned = false
    private var activeMeterObservers = 0

    private init() {
        refreshAudioPermission()
    }

    var saveFolderURL: URL {
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.meetingRecorderSaveFolder) ?? ""
        return MeetingRecorderSupport.resolvedFolderURL(storedPath: stored)
    }

    func syncWithPreferences() {
        refreshAudioPermission()
        guard AppFeature.meetingRecorder.isAvailable else {
            stopDetector()
            if isRecording { stopRecording(userInitiated: false, showHUD: false) }
            return
        }
        let autoRecord = UserDefaults.standard.bool(forKey: DefaultsKey.meetingRecorderAutoRecord)
        if autoRecord {
            startDetector()
        } else {
            stopDetector()
        }
        if isRecording {
            if UserDefaults.standard.bool(forKey: DefaultsKey.meetingRecorderShowIndicator) {
                if indicator == nil { showIndicatorIfEnabled() }
            } else {
                hideIndicator()
            }
        }
    }

    func stopBeforeTermination() {
        stopDetector()
        if isRecording {
            stopRecording(userInitiated: false, showHUD: false)
        }
    }

    func refreshAudioPermission() {
        let state = MeetingAudioPermission.preflight()
        if systemAudioPermission != state { systemAudioPermission = state }
    }

    func requestSystemAudioPermission() {
        let current = MeetingAudioPermission.preflight()
        systemAudioPermission = current
        if current == .denied {
            Permissions.shared.openAudioCaptureSettings()
            return
        }
        MeetingAudioPermission.request { [weak self] _ in
            self?.refreshAudioPermission()
        }
    }

    func setMeterObserving(_ observing: Bool) {
        activeMeterObservers = max(0, activeMeterObservers + (observing ? 1 : -1))
        updateMeterTimer()
    }

    // MARK: - Recording Lifecycle

    func toggleManualRecording() {
        if isRecording {
            stopRecording(userInitiated: true, showHUD: true)
        } else {
            startManualRecording()
        }
    }

    func startManualRecording() {
        guard AppFeature.meetingRecorder.isAvailable, !isRecording else { return }
        startSession(appName: nil, pid: nil, automatic: false)
    }

    func togglePause() {
        guard isRecording, let session else { return }
        isPaused.toggle()
        session.setPaused(isPaused)
        indicator?.update(paused: isPaused)
        if isPaused {
            stopHealthWatchdog()
            warningMessage = nil
        } else {
            startHealthWatchdog()
        }
    }

    func stopRecording(userInitiated: Bool = true, showHUD: Bool = true) {
        guard isRecording, let session else { return }
        stopRecordingTimers()
        hideIndicator()
        let result = session.stop()
        self.session = nil
        currentSessionAutomatic = false
        isRecording = false
        isPaused = false
        systemTrackActive = false
        micTrackActive = false
        detectedAppName = nil
        warningMessage = nil
        micLevels = Array(repeating: 0, count: 18)
        systemLevels = Array(repeating: 0, count: 18)
        if userInitiated {
            decider.noteRecordingStopped()
        }
        refreshRecordings()
        let strings = FeatureStrings.meetingRecorder(L10n.shared.language)
        if result.systemCaptured || result.micCaptured {
            if showHUD {
                QuickToolHUD.show(icon: "checkmark.circle", message: strings.savedHUD)
            }
            if UserDefaults.standard.bool(forKey: DefaultsKey.meetingRecorderAutoTranscribe) {
                AudioTranscriptionService.shared.transcribeMeeting(
                    stem: result.stem,
                    systemURL: result.systemAudioURL,
                    micURL: result.micAudioURL,
                    outputDir: saveFolderURL,
                    showHUD: showHUD
                )
            }
        } else {
            errorMessage = strings.noAudioCapturedError
            if showHUD {
                QuickToolHUD.show(icon: "exclamationmark.triangle", message: strings.noAudioCapturedError)
            }
        }
    }

    func discardRecording() {
        guard isRecording, let session else { return }
        stopRecordingTimers()
        hideIndicator()
        session.discard()
        self.session = nil
        currentSessionAutomatic = false
        isRecording = false
        isPaused = false
        systemTrackActive = false
        micTrackActive = false
        detectedAppName = nil
        warningMessage = nil
        micLevels = Array(repeating: 0, count: 18)
        systemLevels = Array(repeating: 0, count: 18)
        decider.noteRecordingStopped()
        refreshRecordings()
        let strings = FeatureStrings.meetingRecorder(L10n.shared.language)
        QuickToolHUD.show(icon: "trash", message: strings.discardedHUD)
    }

    private func startSession(appName: String?, pid: pid_t?, automatic: Bool) {
        errorMessage = nil
        warningMessage = nil
        refreshAudioPermission()
        Permissions.shared.refresh()

        let outputDir = saveFolderURL
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let fm = FileManager.default
        let existingNames = Set((try? fm.contentsOfDirectory(atPath: outputDir.path)) ?? [])
        let baseStem = MeetingRecorderSupport.sessionStem(date: Date(), appName: appName)
        let stem = MeetingRecorderSupport.uniqueSessionStem(
            baseStem: baseStem,
            existingFileNames: existingNames,
            fileExists: { MeetingCoreAudio.pathEntryExists(outputDir.appendingPathComponent($0)) }
        )
        let perApp = UserDefaults.standard.bool(forKey: DefaultsKey.meetingRecorderPerAppAudio)
        let echoCancel = UserDefaults.standard.bool(forKey: DefaultsKey.meetingRecorderEchoCancellation)

        let capture = MeetingCaptureSession(
            stem: stem,
            detectedApp: appName,
            detectedPID: pid,
            outputDir: outputDir,
            perApp: perApp,
            echoCancellation: echoCancel
        )
        do {
            try capture.start()
        } catch {
            errorMessage = error.localizedDescription
            if automatic { decider.noteRecordingStopped() }
            return
        }

        session = capture
        currentSessionAutomatic = automatic
        isRecording = true
        isPaused = false
        elapsedSeconds = 0
        detectedAppName = appName
        systemTrackActive = capture.systemRunning
        micTrackActive = capture.micRunning

        if !capture.systemRunning, capture.micRunning {
            let strings = FeatureStrings.meetingRecorder(L10n.shared.language)
            warningMessage = strings.micOnlyWarning
        } else if !capture.micRunning, capture.systemRunning {
            let strings = FeatureStrings.meetingRecorder(L10n.shared.language)
            warningMessage = strings.systemOnlyWarning
        }

        startElapsedTimer()
        updateMeterTimer()
        startHealthWatchdog()
        showIndicatorIfEnabled()

        let strings = FeatureStrings.meetingRecorder(L10n.shared.language)
        let message = appName.map { String(format: strings.recordingAppFormat, $0) } ?? strings.recordingStartedHUD
        QuickToolHUD.show(icon: "waveform.circle.fill", message: message)
    }

    // MARK: - Automatic Call Detection

    private func startDetector() {
        guard detectorTimer == nil else { return }
        decider.reset()
        isListeningForCalls = true
        let timer = DispatchSource.makeTimerSource(queue: detectorQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            let consumers = MeetingCoreAudio.activeMicConsumers()
            DispatchQueue.main.async {
                self?.handleDetectorPoll(consumers)
            }
        }
        detectorTimer = timer
        timer.resume()
    }

    private func stopDetector() {
        detectorTimer?.cancel()
        detectorTimer = nil
        decider.reset()
        if isListeningForCalls { isListeningForCalls = false }
    }

    private func handleDetectorPoll(_ consumers: [MeetingMicConsumer]) {
        guard AppFeature.meetingRecorder.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.meetingRecorderAutoRecord) else {
            stopDetector()
            return
        }
        switch decider.tick(consumers: consumers) {
        case .none:
            break
        case .begin(let trigger):
            guard !isRecording else { return }
            let localized = NSRunningApplication(processIdentifier: trigger.pid)?.localizedName
            let label = MeetingRecorderSupport.displayName(for: trigger, localizedAppName: localized)
            startSession(appName: label, pid: trigger.pid, automatic: true)
        case .stop:
            guard MeetingRecorderSupport.shouldApplyDetectorStop(
                isRecording: isRecording,
                sessionIsAutomatic: currentSessionAutomatic
            ) else { return }
            stopRecording(userInitiated: false, showHUD: true)
        }
    }

    // MARK: - Timers, Meters & Health Watchdog

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isRecording, !self.isPaused else { return }
            self.elapsedSeconds += 1
            self.indicator?.update(elapsed: MeetingRecorderSupport.elapsedLabel(seconds: self.elapsedSeconds))
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    private func updateMeterTimer() {
        let shouldRun = isRecording && activeMeterObservers > 0
        if shouldRun, meterTimer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let session = self.session, self.isRecording else { return }
                if self.isPaused {
                    self.micLevels = Array(repeating: 0, count: 18)
                    self.systemLevels = Array(repeating: 0, count: 18)
                } else {
                    self.micLevels = session.micLevels.snapshot(18)
                    self.systemLevels = session.systemLevels.snapshot(18)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            meterTimer = timer
        } else if !shouldRun, let meterTimer {
            meterTimer.invalidate()
            self.meterTimer = nil
        }
    }

    private func startHealthWatchdog() {
        stopHealthWatchdog()
        micHealth = MeetingStreamHealth()
        systemHealth = MeetingStreamHealth()
        lastObservedSystemBytes = 0
        micSilentWindows = 0
        micSilentWarned = false
        let timer = Timer(timeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.checkCaptureHealth()
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func stopHealthWatchdog() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func stopRecordingTimers() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        meterTimer?.invalidate()
        meterTimer = nil
        stopHealthWatchdog()
    }

    private func checkCaptureHealth() {
        guard isRecording, !isPaused, let session else { return }
        let strings = FeatureStrings.meetingRecorder(L10n.shared.language)
        let micInGrace = session.micSecondsSinceDeviceChange < 30

        if micInGrace {
            micSilentWindows = 0
            micHealth = MeetingStreamHealth()
            if micSilentWarned {
                micSilentWarned = false
                warningMessage = nil
            }
        } else if session.micRunning {
            let peakDb = session.consumeMicWindowPeakDb()
            if MeetingRecorderSupport.isMicSilent(peakDb: peakDb) {
                micSilentWindows += 1
                if micSilentWindows >= 2, !micSilentWarned {
                    micSilentWarned = true
                    let device = MeetingCoreAudio.defaultInputDeviceName() ?? strings.unknownDevice
                    warningMessage = String(format: strings.silentMicWarningFormat, device)
                }
            } else {
                micSilentWindows = 0
                if micSilentWarned {
                    micSilentWarned = false
                    warningMessage = nil
                }
            }
        }

        if session.micRunning, !micInGrace {
            switch micHealth.observe(bytes: session.micReceivedFrames) {
            case .stalled:
                session.kickMic()
            case .wedged, .neverStarted:
                warningMessage = strings.micStalledWarning
            default:
                break
            }
        }

        if session.systemRunning {
            let sysFrames = session.systemReceivedFrames
            // Core Audio process taps pause IOProc callbacks when no app is
            // outputting audio (e.g. idle Bluetooth output). Only advance
            // stall detection when real tap frames grew or another process is
            // actively playing audio (ignoring silence-heartbeat writes).
            let shouldObserveSystem = sysFrames > lastObservedSystemBytes
                || MeetingCoreAudio.isAnyOtherProcessPlayingAudio()
            lastObservedSystemBytes = max(lastObservedSystemBytes, sysFrames)
            if shouldObserveSystem {
                switch systemHealth.observe(bytes: sysFrames) {
                case .stalled:
                    _ = session.kickSystem()
                case .wedged, .neverStarted:
                    warningMessage = strings.systemStalledWarning
                default:
                    break
                }
            }
        }

        if !micSilentWarned, !micHealth.isWedged, !systemHealth.isWedged,
           session.micRunning && session.systemRunning {
            warningMessage = nil
        }
    }

    // MARK: - Floating Indicator

    private func showIndicatorIfEnabled() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.meetingRecorderShowIndicator),
              !ScreenRecorderService.shared.isRecording else { return }
        let strings = FeatureStrings.meetingRecorder(L10n.shared.language)
        let pill = RecorderIndicator(
            onPause: { [weak self] in self?.togglePause() },
            onStop: { [weak self] in self?.stopRecording(userInitiated: true, showHUD: true) }
        )
        pill.show(
            on: NSScreen.main ?? NSScreen.screens.first,
            tooltip: strings.title,
            pauseTooltip: strings.pauseButton,
            resumeTooltip: strings.resumeButton,
            stopTooltip: strings.stopButton
        )
        pill.update(elapsed: MeetingRecorderSupport.elapsedLabel(seconds: elapsedSeconds))
        indicator = pill
    }

    private func hideIndicator() {
        indicator?.hide()
        indicator = nil
    }

    // MARK: - Saved Recordings

    func refreshRecordings() {
        let dir = saveFolderURL
        let activeStem = session?.stem
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else {
            recentRecordings = []
            return
        }
        var regularNames: [String] = []
        var sizes: [String: Int64] = [:]
        var dates: [String: Date] = [:]
        var identities: [String: MeetingRecorderSupport.FileIdentity] = [:]
        for name in names where name.hasSuffix(".wav") {
            let url = dir.appendingPathComponent(name)
            if let identity = MeetingCoreAudio.regularFileIdentity(of: url),
               MeetingCoreAudio.isRecorderOwnedFile(url, expectedIdentity: identity),
               let attrs = try? fm.attributesOfItem(atPath: url.path) {
                regularNames.append(name)
                identities[name] = identity
                if let size = attrs[.size] as? NSNumber { sizes[name] = size.int64Value }
                if let date = (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date) {
                    dates[name] = date
                }
            }
        }
        recentRecordings = Array(
            MeetingRecorderSupport.scanRecordings(
                fileNames: regularNames,
                sizes: sizes,
                dates: dates,
                identities: identities,
                excludingStem: activeStem
            ).prefix(20)
        )
    }

    func openSaveFolder() {
        let dir = saveFolderURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func reveal(_ item: MeetingRecorderSupport.RecordingSummary) {
        let dir = saveFolderURL
        let urls = [item.systemFileName, item.micFileName]
            .compactMap { $0 }
            .map { dir.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        } else {
            openSaveFolder()
        }
    }

    func transcriptURL(for item: MeetingRecorderSupport.RecordingSummary) -> URL? {
        let url = AudioTranscriptionSupport.meetingTranscriptFileURL(stem: item.stem, in: saveFolderURL)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func transcribe(_ item: MeetingRecorderSupport.RecordingSummary) {
        let dir = saveFolderURL
        let sysURL = item.systemFileName.map { dir.appendingPathComponent($0) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        let micURL = item.micFileName.map { dir.appendingPathComponent($0) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        AudioTranscriptionService.shared.transcribeMeeting(
            stem: item.stem,
            systemURL: sysURL,
            micURL: micURL,
            outputDir: dir
        )
    }

    func openTranscript(_ item: MeetingRecorderSupport.RecordingSummary) {
        if let url = transcriptURL(for: item) {
            NSWorkspace.shared.open(url)
        }
    }

    func delete(_ item: MeetingRecorderSupport.RecordingSummary) {
        let dir = saveFolderURL
        let fm = FileManager.default
        let targets: [(String?, MeetingRecorderSupport.FileIdentity?)] = [
            (item.systemFileName, item.systemFileIdentity),
            (item.micFileName, item.micFileIdentity),
        ]
        for (name, expectedIdentity) in targets {
            guard let name, let expectedIdentity else { continue }
            let url = dir.appendingPathComponent(name)
            guard MeetingCoreAudio.isRecorderOwnedFile(url, expectedIdentity: expectedIdentity) else {
                continue
            }
            if (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil {
                MeetingCoreAudio.forgetRecorderOwnedFile(url)
            }
        }
        refreshRecordings()
    }
}
