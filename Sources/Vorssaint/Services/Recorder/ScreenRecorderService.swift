// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit
import CoreMedia

/// The two choices shown while the area is being picked. They write through to
/// preferences immediately, so the selection and Settings always start alike.
final class RecorderSelectionAudioOptions: ObservableObject {
    @Published var systemAudio: Bool {
        didSet { UserDefaults.standard.set(systemAudio, forKey: DefaultsKey.recorderSystemAudio) }
    }
    @Published var microphone: Bool {
        didSet { UserDefaults.standard.set(microphone, forKey: DefaultsKey.recorderMicrophone) }
    }

    init(defaults: UserDefaults = .standard) {
        systemAudio = defaults.bool(forKey: DefaultsKey.recorderSystemAudio)
        microphone = defaults.bool(forKey: DefaultsKey.recorderMicrophone)
    }
}

/// One recording, from the first frame to the closed file. Everything that
/// only exists while recording lives here and dies with it, so the service
/// itself keeps nothing running between recordings.
private final class RecorderSession: NSObject, RecorderCaptureEngineDelegate {
    let take: RecorderTakeStore.Take
    let region: RecorderSupport.Region
    private let engine = RecorderCaptureEngine()
    private let pauseClock = RecorderPauseClock()
    private let microphone: RecorderMicrophoneCapture?
    private let pointer: RecorderPointerSampler
    private let typing: RecorderTypingSampler
    private let writerQueue = DispatchQueue(label: "com.vorssaint.recorder.writer",
                                            qos: .userInitiated)
    private let startGate = RecorderStartGate()
    /// Immutable for the whole session, which is what makes it safe to touch
    /// from the capture queue while the main thread watches the clock.
    private let writer: RecorderWriter

    var onUnexpectedStop: ((RecorderFailure) -> Void)?
    var onMicrophoneUnavailable: (() -> Void)?

    init?(take: RecorderTakeStore.Take,
          region: RecorderSupport.Region,
          frameRate: Int,
          capturesSystemAudio: Bool,
          capturesMicrophone: Bool) {
        guard let writer = RecorderWriter(url: take.videoURL,
                                          pixelSize: region.pixelSize,
                                          frameRate: frameRate,
                                          capturesSystemAudio: capturesSystemAudio,
                                          capturesMicrophone: capturesMicrophone,
                                          pauseClock: pauseClock)
        else { return nil }
        self.take = take
        self.region = region
        self.writer = writer
        microphone = capturesMicrophone ? RecorderMicrophoneCapture() : nil
        pointer = RecorderPointerSampler(region: region, pauseClock: pauseClock)
        typing = RecorderTypingSampler(pauseClock: pauseClock)
        super.init()
        engine.delegate = self
        microphone?.onSample = { [weak self] sampleBuffer in
            self?.append(sampleBuffer, kind: .microphone)
        }
    }

    func start(frameRate: Int,
               capturesSystemAudio: Bool,
               excludedWindowNumbers: [Int]) async -> RecorderFailure? {
        guard startGate.begin() else { return .streamFailed }
        defer { startGate.finish() }
        guard writer.start() else {
            _ = startGate.claimStartFailure()
            return .writerFailed
        }
        if let failure = await engine.start(region: region,
                                            frameRate: frameRate,
                                            capturesSystemAudio: capturesSystemAudio,
                                            excludedWindowNumbers: excludedWindowNumbers,
                                            isCancelled: { [weak self] in
                                                self?.startGate.isAuthorized != true
                                            }) {
            if startGate.claimStartFailure() { writer.cancel() }
            return failure
        }
        guard startGate.isAuthorized else {
            await engine.stop()
            return .streamFailed
        }
        if let microphone, let clock = engine.synchronizationClock {
            if await microphone.start(synchronizingTo: clock) == false {
                onMicrophoneUnavailable?()
            }
            guard startGate.isAuthorized else {
                await microphone.stop()
                await engine.stop()
                return .streamFailed
            }
        }
        guard startGate.isAuthorized else {
            await engine.stop()
            return .streamFailed
        }
        pointer.start()
        typing.start()
        return nil
    }

    var isPaused: Bool { pauseClock.isPaused }

    func pause(at time: CFTimeInterval) -> Bool {
        pauseClock.pause(at: time)
    }

    func resume(at time: CFTimeInterval) -> Bool {
        pauseClock.resume(at: time)
    }

    func elapsed(since origin: CFTimeInterval, at time: CFTimeInterval) -> Double {
        pauseClock.elapsed(since: origin, at: time)
    }

    /// Stops the stream first and waits for it, so the file is closed knowing
    /// no further frame can arrive.
    func stop() async -> Bool {
        let ownsFinalization = startGate.cancelAndClaimStop()
        await startGate.waitUntilFinished()
        guard ownsFinalization else { return false }
        if let microphone {
            async let microphoneStop: Void = microphone.stop()
            await engine.stop()
            await microphoneStop
        } else {
            await engine.stop()
        }
        let track = pointer.stop()
        let typingTrack = typing.stop()
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        writerQueue.sync {}
        let written = await writer.finish(at: end)
        if written, !track.isEmpty {
            try? track.encoded().write(to: take.pointerURL, options: .atomic)
        }
        if written, !typingTrack.isEmpty, let data = typingTrack.encoded() {
            try? data.write(to: take.typingURL, options: .atomic)
        }
        return written
    }

    func captureEngine(_ engine: RecorderCaptureEngine,
                       didOutput sampleBuffer: CMSampleBuffer,
                       of kind: RecorderCaptureEngine.Kind) {
        append(sampleBuffer, kind: kind)
    }

    func captureEngine(_ engine: RecorderCaptureEngine, didStopWith failure: RecorderFailure) {
        onUnexpectedStop?(failure)
    }

    private func append(_ sampleBuffer: CMSampleBuffer, kind: RecorderCaptureEngine.Kind) {
        writerQueue.async { [writer] in
            writer.append(sampleBuffer, kind: kind)
        }
    }
}

/// The screen recorder: picks an area the same way the screenshot tool does,
/// records it with either optional sound source, and leaves a video file behind.
///
/// At rest it holds no recorder resource; the shared capture service owns the
/// optional global shortcut. The stream, writer, floating indicator and the
/// one timer that draws elapsed time are created only while recording.
final class ScreenRecorderService: ObservableObject {
    static let shared = ScreenRecorderService()

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsedSeconds = 0
    private var session: RecorderSession?
    private var indicator: RecorderIndicator?
    private var editors: [RecorderEditorController] = []
    private var mediaOwnedEditorIDs: Set<ObjectIdentifier> = []
    private var elapsedTimer: Timer?
    private var startedAt: CFTimeInterval = 0
    private var countdown: DispatchWorkItem?
    private var countdownRemaining = 0
    private var pendingStartGeneration = 0
    private var isAwaitingMicrophone = false
    private var sleepActivity: NSObjectProtocol?
    /// Set while a stop is being finalized, so a second press of the shortcut
    /// cannot start a recording on top of one still closing its file.
    private var isFinishing = false
    /// Set while the disk is being asked how much room is left, so a slow
    /// answer cannot pile the next second's question on top of it.
    private var isCheckingDisk = false

    private var strings: RecorderFeatureStrings {
        FeatureStrings.recorder(L10n.shared.language)
    }

    private init() {}

    // MARK: - Preferences

    func syncWithPreferences() {
        guard AppFeature.screenRecorder.isAvailable else {
            teardownSurfaces()
            return
        }
        sweepTakes()
    }

    /// Uninstalling the feature in the hub has to take everything off the
    /// screen, but a recording in progress still finishes into a file: losing
    /// what was already recorded would be worse than the delay.
    private func teardownSurfaces() {
        invalidatePendingStart()
        let recorderOwnedEditors = editors.filter {
            !mediaOwnedEditorIDs.contains(ObjectIdentifier($0))
        }
        for editor in recorderOwnedEditors {
            editor.close()
        }
        if session != nil {
            stop()
        }
    }

    // MARK: - Editor

    @discardableResult
    func openEditor(with take: RecorderTakeStore.Take,
                    owner: AppFeature = .screenRecorder) -> Bool {
        guard owner.isAvailable else { return false }
        WindowActivationPolicy.retain()
        let editor = RecorderEditorController(take: take)
        editors.append(editor)
        if owner == .mediaTools { mediaOwnedEditorIDs.insert(ObjectIdentifier(editor)) }
        editor.show()
        return true
    }

    func editorDidClose(_ editor: RecorderEditorController) {
        guard editors.contains(where: { $0 === editor }) else { return }
        editors.removeAll { $0 === editor }
        mediaOwnedEditorIDs.remove(ObjectIdentifier(editor))
        WindowActivationPolicy.release()
    }

    func closeEditors(ownedBy owner: AppFeature) {
        guard owner == .mediaTools else { return }
        let targets = editors.filter { mediaOwnedEditorIDs.contains(ObjectIdentifier($0)) }
        for editor in targets { editor.close() }
    }

    // MARK: - Entry

    /// The one control the shortcut, the panel tile and the command bar all
    /// use: it starts when nothing is running and stops when something is.
    func toggle() {
        if stopOrCancelActiveCapture() { return }
        ScreenCaptureService.shared.capture(initial: .recording)
    }

    func stopOrCancelActiveCapture() -> Bool {
        if isRecording || session != nil {
            stop()
            return true
        }
        if countdown != nil {
            invalidatePendingStart()
            return true
        }
        if isAwaitingMicrophone {
            invalidatePendingStart()
            return true
        }
        return isFinishing
    }

    func prepareForSelection() -> Bool {
        guard AppFeature.screenRecorder.isAvailable, !isFinishing,
              session == nil, countdown == nil, !isAwaitingMicrophone else { return false }
        guard Permissions.shared.screenRecording else {
            Permissions.shared.requestScreenRecording()
            return false
        }
        guard Permissions.shared.accessibility else {
            Permissions.shared.requestAccessibility()
            return false
        }
        guard RecorderSupport.canStart(freeBytes: RecorderTakeStore.shared.freeBytes()) else {
            reportNoSpace()
            return false
        }
        return true
    }

    func record(_ region: RecorderSupport.Region,
                audioOptions: RecorderSelectionAudioOptions) {
        guard prepareForSelection() else { return }
        let indicator = RecorderIndicator(
            onPause: { [weak self] in self?.togglePause() },
            onStop: { [weak self] in self?.stop() })
        indicator.showRegionGuide(for: region)
        self.indicator = indicator
        pendingStartGeneration &+= 1
        let generation = pendingStartGeneration
        prepareCountdown(for: region, wantsMicrophone: audioOptions.microphone,
                         generation: generation)
    }

    private func prepareCountdown(for region: RecorderSupport.Region,
                                  wantsMicrophone: Bool,
                                  generation: Int) {
        guard pendingStartIsAuthorized(generation) else { return }
        guard wantsMicrophone else {
            startCountdown(for: region, generation: generation)
            return
        }
        switch Permissions.shared.microphone {
        case .granted:
            startCountdown(for: region, generation: generation)
        case .undetermined:
            isAwaitingMicrophone = true
            Permissions.shared.requestMicrophone { [weak self] granted in
                guard let self, self.pendingStartIsAuthorized(generation) else { return }
                self.isAwaitingMicrophone = false
                if !granted {
                    QuickToolHUD.show(icon: "mic.slash",
                                      message: self.strings.microphoneUnavailableHUD)
                }
                self.startCountdown(for: region, generation: generation)
            }
        case .denied, .unknown:
            QuickToolHUD.show(icon: "mic.slash", message: strings.microphoneUnavailableHUD)
            startCountdown(for: region, generation: generation)
        }
    }

    // MARK: - Countdown

    private func startCountdown(for region: RecorderSupport.Region, generation: Int) {
        guard pendingStartIsAuthorized(generation), session == nil, !isFinishing else { return }
        let delay = ScreenshotSupport.sanitizedDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.recorderCountdown))
        guard delay > 0 else {
            beginRecording(region: region, generation: generation)
            return
        }
        countdownRemaining = delay
        tickCountdown(region: region, generation: generation)
    }

    private func tickCountdown(region: RecorderSupport.Region, generation: Int) {
        guard pendingStartIsAuthorized(generation) else { return }
        guard countdownRemaining > 0 else {
            countdown = nil
            beginRecording(region: region, generation: generation)
            return
        }
        QuickToolHUD.showCountdown(countdownRemaining)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingStartIsAuthorized(generation) else { return }
            self.countdownRemaining -= 1
            self.tickCountdown(region: region, generation: generation)
        }
        countdown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: - Recording

    private func beginRecording(region: RecorderSupport.Region, generation: Int) {
        guard pendingStartIsAuthorized(generation), session == nil,
              !isFinishing, let take = RecorderTakeStore.shared.makeTake() else {
            indicator?.hide()
            indicator = nil
            QuickToolHUD.show(icon: "record.circle", message: strings.recordFailed)
            return
        }
        let defaults = UserDefaults.standard
        let frameRate = RecorderSupport.sanitizedFrameRate(
            defaults.integer(forKey: DefaultsKey.recorderFrameRate))
        let capturesSystemAudio = defaults.bool(forKey: DefaultsKey.recorderSystemAudio)
        let capturesMicrophone = defaults.bool(forKey: DefaultsKey.recorderMicrophone)
            && Permissions.shared.microphone == .granted
        guard let session = RecorderSession(take: take,
                                            region: region,
                                            frameRate: frameRate,
                                            capturesSystemAudio: capturesSystemAudio,
                                            capturesMicrophone: capturesMicrophone) else {
            indicator?.hide()
            indicator = nil
            RecorderTakeStore.shared.delete(take)
            QuickToolHUD.show(icon: "record.circle", message: strings.recordFailed)
            return
        }
        session.onUnexpectedStop = { [weak self] _ in
            // The stream ended without being asked to. Whatever was recorded
            // is still worth keeping, so this closes the file rather than
            // throwing the take away.
            self?.stop()
        }
        session.onMicrophoneUnavailable = { [weak self] in
            guard let self else { return }
            QuickToolHUD.show(icon: "mic.slash", message: self.strings.microphoneUnavailableHUD)
        }
        self.session = session

        // The indicator goes up BEFORE the stream is asked to start, because
        // the capture filter names the windows it leaves out and can only name
        // the ones that already exist. Everything else this app shows stays in
        // the picture.
        let indicator = indicator ?? RecorderIndicator(
            onPause: { [weak self] in self?.togglePause() },
            onStop: { [weak self] in self?.stop() })
        indicator.show(on: NSScreen.screens.first { $0.displayID == region.displayID },
                       tooltip: strings.indicatorTooltip,
                       pauseTooltip: strings.pauseButton,
                       resumeTooltip: strings.resumeButton,
                       stopTooltip: strings.stopButton)
        indicator.update(elapsed: RecorderSupport.elapsedLabel(seconds: 0))
        self.indicator = indicator

        Task { @MainActor [weak self] in
            guard let self else { return }
            // The selection panels have just left the screen; the stream is
            // told to start only once the window server has caught up, so the
            // first frames are of the desktop and not of a fading overlay.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard self.session === session,
                  self.pendingStartIsAuthorized(generation) else { return }
            var chrome = Set(ScreenshotService.shared.protectedWindowIDsForCapture.map(Int.init))
            chrome.formUnion(indicator.excludedWindowNumbers)
            if let number = QuickToolHUD.currentWindowNumber { chrome.insert(number) }
            let failure = await session.start(frameRate: frameRate,
                                              capturesSystemAudio: capturesSystemAudio,
                                              excludedWindowNumbers: Array(chrome))
            guard self.session === session, !self.isFinishing,
                  self.pendingStartIsAuthorized(generation) else { return }
            if let failure {
                self.session = nil
                self.indicator?.hide()
                self.indicator = nil
                RecorderTakeStore.shared.delete(take)
                self.report(failure)
                return
            }
            self.recordingDidStart()
        }
    }

    private func pendingStartIsAuthorized(_ generation: Int) -> Bool {
        RecorderSupport.pendingStartIsAuthorized(
            requestGeneration: generation,
            currentGeneration: pendingStartGeneration,
            featureIsAvailable: AppFeature.screenRecorder.isAvailable)
    }

    private func invalidatePendingStart() {
        pendingStartGeneration &+= 1
        isAwaitingMicrophone = false
        countdown?.cancel()
        countdown = nil
        indicator?.hide()
        indicator = nil
    }

    private func recordingDidStart() {
        isRecording = true
        isPaused = false
        elapsedSeconds = 0
        startedAt = CACurrentMediaTime()
        sleepActivity = ProcessInfo.processInfo.beginActivity(
            options: .idleSystemSleepDisabled,
            reason: "Recording the screen")

        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickElapsed()
        }
        timer.tolerance = 0.1
        elapsedTimer = timer
    }

    private func tickElapsed() {
        guard isRecording, let session else { return }
        elapsedSeconds = Int(session.elapsed(since: startedAt, at: CACurrentMediaTime()))
        indicator?.update(elapsed: RecorderSupport.elapsedLabel(seconds: elapsedSeconds))
        checkDiskSpace()
    }

    func togglePause() {
        guard isRecording, let session else { return }
        let now = CACurrentMediaTime()
        if session.isPaused {
            guard session.resume(at: now) else { return }
            isPaused = false
        } else {
            guard session.pause(at: now) else { return }
            isPaused = true
        }
        elapsedSeconds = Int(session.elapsed(since: startedAt, at: now))
        indicator?.update(elapsed: RecorderSupport.elapsedLabel(seconds: elapsedSeconds))
        indicator?.update(paused: isPaused)
    }

    /// A recording that fills the disk is a much worse failure than one that
    /// stopped early, so the free space is checked while it runs. Asking the
    /// system how much room is left has to account for purgeable files, which
    /// makes it slow enough that it can never ride the main thread: only the
    /// decision to stop comes back.
    private func checkDiskSpace() {
        guard !isCheckingDisk, let asked = session?.take.id else { return }
        isCheckingDisk = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let low = RecorderSupport.shouldStopForDisk(
                freeBytes: RecorderTakeStore.shared.freeBytes())
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCheckingDisk = false
                // The answer belongs to the recording that asked for it: one
                // that lands late says nothing about the one running now.
                guard low, self.isRecording, self.session?.take.id == asked else { return }
                self.stop(reason: self.strings.stoppedNoSpaceHUD)
            }
        }
    }

    // MARK: - Stopping

    func stop(reason: String? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stop(reason: reason) }
            return
        }
        guard let session, !isFinishing else { return }
        isFinishing = true
        invalidatePendingStart()
        endRecordingSurfaces()

        Task { @MainActor [weak self] in
            let written = await session.stop()
            guard let self else { return }
            self.session = nil
            self.isFinishing = false
            if written {
                self.deliver(session.take, reason: reason)
            } else {
                RecorderTakeStore.shared.delete(session.take)
                QuickToolHUD.show(icon: "record.circle", message: self.strings.recordFailed)
            }
            self.sweepTakes()
        }
    }

    private func endRecordingSurfaces() {
        isRecording = false
        isPaused = false
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        if let sleepActivity {
            ProcessInfo.processInfo.endActivity(sleepActivity)
            self.sleepActivity = nil
        }
    }

    // MARK: - Output

    /// A finished recording either opens in the editor, which is where trim,
    /// sound and format are decided, or goes straight to a file for whoever
    /// only wanted the raw recording.
    private func deliver(_ take: RecorderTakeStore.Take, reason: String?) {
        if reason == nil, UserDefaults.standard.bool(forKey: DefaultsKey.recorderOpenEditor) {
            if openEditor(with: take) { return }
        }
        saveDirect(take, reason: reason)
    }

    private func saveDirect(_ take: RecorderTakeStore.Take, reason: String?) {
        let destination = Self.saveDestination(strings: strings, fileExtension: "mov")
        do {
            try RecorderTakeStore.shared.saveDirectly(take, to: destination)
        } catch {
            NSSound.beep()
            QuickToolHUD.show(icon: "record.circle", message: strings.recordFailed)
            openEditor(with: take)
            return
        }
        RecentCaptureService.shared.recordRecording(at: destination)
        let folder = destination.deletingLastPathComponent().lastPathComponent
        QuickToolHUD.show(icon: "record.circle",
                          message: reason ?? String(format: strings.savedHUDFormat, folder))
    }

    /// The configured folder when it still exists, otherwise the Desktop, with
    /// a unique dated name. Deliberately the same shape the screenshot tool
    /// uses, so both tools behave the same way about where things land.
    static func saveDestination(strings: RecorderFeatureStrings,
                                fileExtension: String) -> URL {
        let manager = FileManager.default
        var folder: URL?
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.recorderSaveFolder) ?? ""
        if !stored.isEmpty {
            let expanded = (stored as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: expanded, isDirectory: &isDirectory),
               isDirectory.boolValue {
                folder = URL(fileURLWithPath: expanded)
            }
        }
        let destination = folder
            ?? manager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? manager.homeDirectoryForCurrentUser
        let name = ScreenshotSupport.fileName(prefix: strings.fileNamePrefix,
                                              date: Date(),
                                              fileExtension: fileExtension)
        let unique = ScreenshotSupport.uniqueFileName(name) { candidate in
            manager.fileExists(atPath: destination.appendingPathComponent(candidate).path)
        }
        return destination.appendingPathComponent(unique)
    }

    // MARK: - Failures

    private func report(_ failure: RecorderFailure) {
        switch failure {
        case .permissionDenied:
            Permissions.shared.requestScreenRecording()
        case .diskFull:
            reportNoSpace()
        case .noContent, .streamFailed, .writerFailed:
            QuickToolHUD.show(icon: "record.circle", message: strings.recordFailed)
        }
    }

    private func reportNoSpace() {
        let alert = NSAlert()
        alert.messageText = strings.noSpaceTitle
        alert.informativeText = strings.noSpaceMessage
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Retention

    private func sweepTakes() {
        // Read on the main thread, where the editors live, and handed over as
        // a value: a recording with a window on screen is never swept.
        var owned = Set(editors.map(\.takeID))
        if let session { owned.insert(session.take.id) }
        DispatchQueue.global(qos: .utility).async {
            RecorderTakeStore.shared.sweep(keeping: owned)
        }
    }
}
