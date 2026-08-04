// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit
import CoreMedia

/// One recording, from the first frame to the closed file. Everything that
/// only exists while recording lives here and dies with it, so the service
/// itself keeps nothing running between recordings.
private final class RecorderSession: NSObject, RecorderCaptureEngineDelegate {
    let take: RecorderTakeStore.Take
    let region: RecorderSupport.Region
    private let engine = RecorderCaptureEngine()
    private let pointer: RecorderPointerSampler
    private let typing = RecorderTypingSampler()
    /// Immutable for the whole session, which is what makes it safe to touch
    /// from the capture queue while the main thread watches the clock.
    private let writer: RecorderWriter

    var onUnexpectedStop: ((RecorderFailure) -> Void)?

    init?(take: RecorderTakeStore.Take,
          region: RecorderSupport.Region,
          frameRate: Int,
          capturesSystemAudio: Bool) {
        guard let writer = RecorderWriter(url: take.videoURL,
                                          pixelSize: region.pixelSize,
                                          frameRate: frameRate,
                                          capturesSystemAudio: capturesSystemAudio)
        else { return nil }
        self.take = take
        self.region = region
        self.writer = writer
        pointer = RecorderPointerSampler(region: region)
        super.init()
        engine.delegate = self
    }

    func start(frameRate: Int,
               capturesSystemAudio: Bool,
               excludedWindowNumbers: [Int]) async -> RecorderFailure? {
        guard writer.start() else { return .writerFailed }
        if let failure = await engine.start(region: region,
                                            frameRate: frameRate,
                                            capturesSystemAudio: capturesSystemAudio,
                                            excludedWindowNumbers: excludedWindowNumbers) {
            writer.cancel()
            return failure
        }
        pointer.start()
        typing.start()
        return nil
    }

    /// Stops the stream first and waits for it, so the file is closed knowing
    /// no further frame can arrive.
    func stop() async -> Bool {
        await engine.stop()
        let track = pointer.stop()
        let typingTrack = typing.stop()
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        let written = await writer.finish(at: end)
        if written, !track.isEmpty {
            try? track.encoded().write(to: take.pointerURL, options: .atomic)
        }
        if written, !typingTrack.isEmpty, let data = typingTrack.encoded() {
            try? data.write(to: take.typingURL, options: .atomic)
        }
        return written
    }

    func abandon() async {
        await engine.stop()
        _ = pointer.stop()
        _ = typing.stop()
        writer.cancel()
    }

    func captureEngine(_ engine: RecorderCaptureEngine,
                       didOutput sampleBuffer: CMSampleBuffer,
                       of kind: RecorderCaptureEngine.Kind) {
        writer.append(sampleBuffer, kind: kind)
    }

    func captureEngine(_ engine: RecorderCaptureEngine, didStopWith failure: RecorderFailure) {
        onUnexpectedStop?(failure)
    }
}

/// The screen recorder: picks an area the same way the screenshot tool does,
/// records it with the sound of the Mac, and leaves a video file behind.
///
/// At rest the only resource is the optional global shortcut registration.
/// Everything else, the stream, the writer, the floating indicator and the one
/// timer that draws the elapsed time, is created when a recording starts and
/// released when it ends.
final class ScreenRecorderService: ObservableObject {
    static let shared = ScreenRecorderService()

    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 21)
    private var selection: ScreenshotSelectionController?
    private var session: RecorderSession?
    private var indicator: RecorderIndicator?
    private var editors: [RecorderEditorController] = []
    private var elapsedTimer: Timer?
    private var startedAt: CFTimeInterval = 0
    private var countdown: DispatchWorkItem?
    private var countdownRemaining = 0
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

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    // MARK: - Preferences

    func syncWithPreferences() {
        guard AppFeature.screenRecorder.isAvailable else {
            shortcutRegistrationFailed = false
            hotkey.unregister()
            teardownSurfaces()
            return
        }
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.recorderShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.recorderShortcut,
                                            fallback: .screenRecorderDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
        sweepTakes()
    }

    func suspend() {
        hotkey.unregister()
    }

    /// Uninstalling the feature in the hub has to take everything off the
    /// screen, but a recording in progress still finishes into a file: losing
    /// what was already recorded would be worse than the delay.
    private func teardownSurfaces() {
        countdown?.cancel()
        countdown = nil
        selection?.cancel()
        selection = nil
        for editor in editors {
            editor.close()
        }
        editors.removeAll()
        if session != nil {
            stop()
        }
    }

    // MARK: - Editor

    func openEditor(with take: RecorderTakeStore.Take) {
        EditorActivationPolicy.retain()
        let editor = RecorderEditorController(take: take)
        editors.append(editor)
        editor.show()
    }

    func editorDidClose(_ editor: RecorderEditorController) {
        guard editors.contains(where: { $0 === editor }) else { return }
        editors.removeAll { $0 === editor }
        EditorActivationPolicy.release()
    }

    // MARK: - Entry

    /// The one control the shortcut, the panel tile and the command bar all
    /// use: it starts when nothing is running and stops when something is.
    func toggle() {
        if isRecording {
            stop()
            return
        }
        if countdown != nil {
            countdown?.cancel()
            countdown = nil
            return
        }
        guard selection == nil, !isFinishing else { return }
        guard !ScreenshotSelectionController.isSessionOnScreen else { return }
        guard Permissions.shared.screenRecording else {
            Permissions.shared.requestScreenRecording()
            return
        }
        guard Permissions.shared.accessibility else {
            Permissions.shared.requestAccessibility()
            return
        }
        guard RecorderSupport.canStart(freeBytes: RecorderTakeStore.shared.freeBytes()) else {
            reportNoSpace()
            return
        }
        beginSelection()
    }

    private func beginSelection() {
        // Live pixels while choosing, not a still: what is worth recording is
        // usually something that moves, and freezing it would hide exactly
        // what the person is trying to frame.
        let controller = ScreenshotSelectionController(freeze: false,
                                                       includePointer: false,
                                                       showLastRegion: true,
                                                       purpose: strings.selectionPurpose,
                                                       mode: .geometry)
        selection = controller
        controller.begin { [weak self] outcome in
            guard let self else { return }
            self.selection = nil
            switch outcome {
            case .region(let region):
                self.startCountdown(for: region)
            case .captured, .scrollingRegion, .cancelled:
                break
            case .failed:
                QuickToolHUD.show(icon: "record.circle", message: self.strings.recordFailed)
            }
        }
    }

    // MARK: - Countdown

    private func startCountdown(for region: RecorderSupport.Region) {
        let delay = ScreenshotSupport.sanitizedDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.recorderCountdown))
        guard delay > 0 else {
            beginRecording(region: region)
            return
        }
        countdownRemaining = delay
        tickCountdown(region: region)
    }

    private func tickCountdown(region: RecorderSupport.Region) {
        guard countdownRemaining > 0 else {
            countdown = nil
            beginRecording(region: region)
            return
        }
        QuickToolHUD.showCountdown(countdownRemaining)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.countdownRemaining -= 1
            self.tickCountdown(region: region)
        }
        countdown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: - Recording

    private func beginRecording(region: RecorderSupport.Region) {
        guard session == nil, let take = RecorderTakeStore.shared.makeTake() else {
            QuickToolHUD.show(icon: "record.circle", message: strings.recordFailed)
            return
        }
        let defaults = UserDefaults.standard
        let frameRate = RecorderSupport.sanitizedFrameRate(
            defaults.integer(forKey: DefaultsKey.recorderFrameRate))
        let capturesSystemAudio = defaults.bool(forKey: DefaultsKey.recorderSystemAudio)
        guard let session = RecorderSession(take: take,
                                            region: region,
                                            frameRate: frameRate,
                                            capturesSystemAudio: capturesSystemAudio) else {
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
        self.session = session

        // The indicator goes up BEFORE the stream is asked to start, because
        // the capture filter names the windows it leaves out and can only name
        // the ones that already exist. Everything else this app shows stays in
        // the picture.
        let indicator = RecorderIndicator(onStop: { [weak self] in self?.stop() })
        indicator.show(on: NSScreen.screens.first { $0.displayID == region.displayID },
                       tooltip: strings.indicatorTooltip)
        indicator.update(elapsed: RecorderSupport.elapsedLabel(seconds: 0))
        self.indicator = indicator

        Task { @MainActor [weak self] in
            guard let self else { return }
            // The selection panels have just left the screen; the stream is
            // told to start only once the window server has caught up, so the
            // first frames are of the desktop and not of a fading overlay.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard self.session === session else { return }
            var chrome: [Int] = []
            if let number = indicator.excludedWindowNumber { chrome.append(number) }
            if let number = QuickToolHUD.currentWindowNumber { chrome.append(number) }
            if let failure = await session.start(frameRate: frameRate,
                                                 capturesSystemAudio: capturesSystemAudio,
                                                 excludedWindowNumbers: chrome) {
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

    private func recordingDidStart() {
        isRecording = true
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
        guard isRecording else { return }
        elapsedSeconds = Int(CACurrentMediaTime() - startedAt)
        indicator?.update(elapsed: RecorderSupport.elapsedLabel(seconds: elapsedSeconds))
        checkDiskSpace()
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
        guard let session, !isFinishing else { return }
        isFinishing = true
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
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        indicator?.hide()
        indicator = nil
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
            openEditor(with: take)
            return
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
