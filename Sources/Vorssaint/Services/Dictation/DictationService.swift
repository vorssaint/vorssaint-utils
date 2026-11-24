// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import UniformTypeIdentifiers

private final class DictationDeliveryValidity {
    private let lock = NSLock()
    private var active = true
    func invalidate() { lock.lock(); active = false; lock.unlock() }
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
}

final class DictationService: ObservableObject {
    static let shared = DictationService()
    @Published private(set) var phase: DictationPhase = .idle {
        didSet { shortcut.setBusy(phase.isBusy) }
    }
    @Published private(set) var elapsed = 0.0
    @Published private(set) var waveform = [Double](repeating: 0, count: DictationSpectrum.count)
    @Published private(set) var result = ""
    @Published private(set) var status = ""
    @Published private(set) var error: String?
    @Published private(set) var shortcutAvailable = false
    private let recorder = DictationRecorder()
    private let engine = DictationEngine()
    private let shortcut = DictationShortcut()
    private var timer: Timer?
    private var completionWork: DispatchWorkItem?
    private var unloadWork: DispatchWorkItem?
    private var processingWatchdog: DispatchWorkItem?
    private var cleanupTask: Task<Void, Never>?
    private var liveID: UUID?
    private var recordingURL: URL?
    private var ownsRecording = false
    private var started = ProcessInfo.processInfo.systemUptime
    private var lastSpeech = 0.0
    private var heardSpeech = false
    private var deliveryValidity = DictationDeliveryValidity()
    private var generation = UUID() {
        didSet { deliveryValidity.invalidate(); deliveryValidity = DictationDeliveryValidity() }
    }
    private var pressTime: TimeInterval?
    private var startedWithShortcut = false
    private var targetPID: pid_t?
    private var shortcutSignature = ""
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var enabled = false
    private var activeModelID = ""
    private var activeModelURL: URL?
    private var activeLanguage = ""
    private var activeTranslate = false
    private var cleanedAbandonedAudio = false

    var isEnabled: Bool { AppFeature.dictation.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.dictationEnabled) }
    private var text: DictationStrings { .localized(L10n.shared.language) }
    private var defaults: UserDefaults { .standard }

    private init() {
        shortcut.press = { [weak self] in self?.shortcutPressed() }
        shortcut.release = { [weak self] in self?.shortcutReleased() }
        shortcut.cancel = { [weak self] in self?.cancel() }
    }

    func syncWithPreferences() {
        guard isEnabled else {
            stop()
            if !AppFeature.dictation.isAvailable { DictationModelStore.shared.cancelDownload() }
            return
        }
        enabled = true
        if !cleanedAbandonedAudio {
            cleanedAbandonedAudio = true
            // Take the list before any new recording starts. Work left by a
            // crashed prior process must not become permanent audio history.
            if let directory = PrivateFileStore.containerURL?.appendingPathComponent("Dictation/Temporary", isDirectory: true),
               let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let abandoned = files.filter { ["caf", "f32"].contains($0.pathExtension) && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
                DispatchQueue.global(qos: .utility).async {
                    for file in abandoned { try? FileManager.default.removeItem(at: file) }
                }
            }
        }
        let binding = defaults.string(forKey: DefaultsKey.dictationShortcut) ?? "fn"
        let signature = binding + String(AXIsProcessTrusted())
        if signature != shortcutSignature || !shortcutAvailable {
            shortcutSignature = signature
            shortcutAvailable = AXIsProcessTrusted() && shortcut.start(storage: binding)
            shortcut.setBusy(phase.isBusy)
        }
        DictationHistoryStore.shared.syncWithPreferences()
        if observers.isEmpty {
            let workspace = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
                observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.cancel() }))
            }
            let distributed = DistributedNotificationCenter.default()
            observers.append((distributed, distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.cancel() }))
            let center = NotificationCenter.default
            observers.append((center, center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                guard self?.phase == .recording else { return }
                self?.fail("The microphone changed during recording. Please start again.")
            }))
        }
    }

    func stop() {
        enabled = false
        shortcut.stop(); shortcutSignature = ""; shortcutAvailable = false
        cancel()
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    private func shortcutPressed() {
        guard isEnabled else { return }
        let activation = DictationActivation(rawValue: defaults.string(forKey: DefaultsKey.dictationActivation) ?? "") ?? .hybrid
        if phase == .recording {
            if activation != .hold { finish() }
            return
        }
        guard !phase.isBusy else { return }
        pressTime = ProcessInfo.processInfo.systemUptime
        startedWithShortcut = true
        begin(fromShortcut: true)
    }

    private func shortcutReleased() {
        guard startedWithShortcut else { return }
        let activation = DictationActivation(rawValue: defaults.string(forKey: DefaultsKey.dictationActivation) ?? "") ?? .hybrid
        let held = ProcessInfo.processInfo.systemUptime - (pressTime ?? ProcessInfo.processInfo.systemUptime)
        if activation == .hold || (activation == .hybrid && held >= 0.35) {
            if phase == .requestingPermission { cancel() }
            else if phase == .recording { finish() }
        }
        startedWithShortcut = false
        pressTime = nil
    }

    func toggle() {
        if phase == .recording { finish() }
        else if !phase.isBusy { begin() }
    }

    func begin(fromShortcut: Bool = false) {
        guard isEnabled, !phase.isBusy else { return }
        guard !IsSecureEventInputEnabled() else { fail("Finish entering your password before starting dictation."); return }
        guard NotchService.shared.captureControls == nil else { fail("Finish screen capture before starting dictation."); return }
        guard let model = DictationModelStore.shared.selectedURL else {
            fail("Download or import a speech model in Dictation settings first."); return
        }
        cleanupPrevious()
        generation = UUID()
        let token = generation
        activeModelID = DictationModelStore.shared.selectedID
        activeModelURL = model
        activeLanguage = defaults.string(forKey: DefaultsKey.dictationLanguage) ?? ""
        activeTranslate = defaults.bool(forKey: DefaultsKey.dictationTranslate)
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if targetPID == ProcessInfo.processInfo.processIdentifier { targetPID = nil }
        error = nil; result = ""; elapsed = 0; heardSpeech = false; lastSpeech = 0
        waveform = [Double](repeating: 0, count: DictationSpectrum.count)
        phase = .requestingPermission
        let authorization = AVCaptureDevice.authorizationStatus(for: .audio)
        if authorization == .authorized { startRecording(token: token) }
        else if authorization == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                DispatchQueue.main.async {
                    guard self.generation == token, self.isEnabled else { return }
                    if allowed { self.startRecording(token: token) }
                    else { self.fail("Allow microphone access in System Settings → Privacy & Security → Microphone.") }
                }
            }
        } else { fail("Allow microphone access in System Settings → Privacy & Security → Microphone.") }
    }

    private func startRecording(token: UUID) {
        guard generation == token, isEnabled else { return }
        guard let directory = PrivateFileStore.containerURL?.appendingPathComponent("Dictation/Temporary", isDirectory: true),
              PrivateFileStore.createDirectory(at: directory) else { fail("Could not create private recording storage."); return }
        let url = directory.appendingPathComponent(UUID().uuidString + ".caf")
        do {
            recordingURL = url; ownsRecording = true
            unloadWork?.cancel(); unloadWork = nil
            guard let model = activeModelURL else { throw DictationError.message("The selected model is unavailable.") }
            let id = engine.beginLive(makeRequest(audio: url, model: model))
            liveID = id
            try recorder.start(at: url, microphoneUID: defaults.string(forKey: DefaultsKey.dictationMicrophone) ?? "") { [weak engine] data in
                engine?.appendLive(data, id: id)
            }
            started = ProcessInfo.processInfo.systemUptime
            phase = .recording
            if defaults.bool(forKey: DefaultsKey.dictationSound) { NSSound(named: "Tink")?.play() }
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } catch { fail(error.localizedDescription) }
    }

    private func tick() {
        guard phase == .recording else { return }
        elapsed = ProcessInfo.processInfo.systemUptime - started
        let reading = recorder.reading()
        if let error = reading.error { fail("Recording failed: \(error.localizedDescription)"); return }
        waveform = reading.waveform
        if reading.level > 0.035 { heardSpeech = true; lastSpeech = elapsed }
        let silence = defaults.double(forKey: DefaultsKey.dictationSilenceStop)
        if elapsed >= DictationSupport.maximumRecordingSeconds || (silence >= 1 && heardSpeech && elapsed - lastSpeech >= silence) { finish() }
    }

    func finish() {
        guard phase == .recording, let recordingURL else { return }
        elapsed = ProcessInfo.processInfo.systemUptime - started
        timer?.invalidate(); timer = nil; recorder.stop()
        if defaults.bool(forKey: DefaultsKey.dictationSound) { NSSound(named: "Pop")?.play() }
        // Avoid sending accidental taps or silence to a decoder that may hallucinate.
        guard elapsed >= 0.2, heardSpeech else { cancel(); return }
        process(recordingURL, duration: elapsed, deliver: true)
    }

    func importAudio() {
        guard isEnabled, !phase.isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transcribeFile(url)
    }

    func retry(_ entry: DictationEntry) {
        guard let url = DictationHistoryStore.shared.audioURL(entry) else { return }
        transcribeFile(url)
    }

    private func transcribeFile(_ url: URL) {
        guard isEnabled, !phase.isBusy else { return }
        guard let modelURL = DictationModelStore.shared.selectedURL else { fail("Select a downloaded model first."); return }
        cleanupPrevious(); generation = UUID(); error = nil; result = ""
        do {
            let audio = try AVAudioFile(forReading: url)
            elapsed = Double(audio.length) / audio.processingFormat.sampleRate
            guard elapsed > 0, elapsed <= 3600 else { throw DictationError.message("Choose audio shorter than one hour.") }
            recordingURL = url; ownsRecording = false; targetPID = nil
            activeModelID = DictationModelStore.shared.selectedID; activeModelURL = modelURL
            activeLanguage = defaults.string(forKey: DefaultsKey.dictationLanguage) ?? ""
            activeTranslate = defaults.bool(forKey: DefaultsKey.dictationTranslate)
            process(url, duration: elapsed, deliver: false)
        } catch { fail(error.localizedDescription) }
    }

    private func makeRequest(audio: URL, model: URL) -> DictationEngine.Request {
        DictationEngine.Request(audio: audio, model: model, language: activeLanguage, translate: activeTranslate,
            vocabulary: Array((defaults.string(forKey: DefaultsKey.dictationVocabulary) ?? "").split(separator: "\n").map(String.init).prefix(256)),
            cpu: defaults.bool(forKey: DefaultsKey.dictationCPUOnly))
    }

    private func process(_ url: URL, duration: TimeInterval, deliver: Bool) {
        guard let model = activeModelURL else { fail("The selected model is unavailable."); return }
        unloadWork?.cancel(); unloadWork = nil
        phase = .processing
        let token = generation
        let began = ProcessInfo.processInfo.systemUptime
        let request = makeRequest(audio: url, model: model)
        let finishingLive = deliver ? liveID : nil
        liveID = nil
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.phase == .processing else { return }
            self.engine.cancel(); self.fail("Transcription took too long. Try a smaller model or CPU mode.")
        }
        processingWatchdog = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + max(120, duration * 3), execute: timeout)
        engine.transcribe(request, finishingLive: finishingLive) { [weak self] response in
            guard let self, self.generation == token, self.isEnabled, self.phase == .processing else { return }
            self.processingWatchdog?.cancel(); self.processingWatchdog = nil
            switch response {
            case .failure(let error): self.fail(error.localizedDescription)
            case .success(let reply):
                let original = reply.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !original.isEmpty else { self.finishWithoutTranscript(); return }
                let language = reply.language?.isEmpty == false ? reply.language! : self.activeLanguage
                let cleaned = DictationSupport.cleaned(original, replacements: self.defaults.string(forKey: DefaultsKey.dictationReplacements) ?? "",
                    removeFillers: self.defaults.bool(forKey: DefaultsKey.dictationRemoveFillers), language: language)
                guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { self.finishWithoutTranscript(); return }
                self.cleanupTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    var output = cleaned
                    var cleanupError: String?
                    if self.defaults.bool(forKey: DefaultsKey.dictationCleanupEnabled) {
                        do { output = try await DictationCleanup.run(cleaned) }
                        catch { cleanupError = error.localizedDescription }
                    }
                    guard !Task.isCancelled, self.generation == token, self.isEnabled else { return }
                    if cleanupError == nil, output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.finishWithoutTranscript(); return
                    }
                    self.result = output
                    let entry = DictationEntry(text: output, originalText: original, modelID: self.activeModelID, language: language,
                        duration: duration, processingDuration: ProcessInfo.processInfo.systemUptime - began)
                    DictationHistoryStore.shared.add(entry, recording: url)
                    self.cleanupPrevious()
                    self.scheduleUnload()
                    if let cleanupError {
                        self.error = cleanupError + " The original transcription has been kept."
                        self.status = "Transcribed"
                        self.phase = .failed
                    } else if deliver { self.deliver(output, token: token) }
                    else { self.status = "Saved to speech history"; self.complete() }
                }
            }
        }
    }

    private func deliver(_ value: String, token: UUID) {
        let value = value + (defaults.bool(forKey: DefaultsKey.dictationTrailingSpace) ? " " : "")
        let delivery = DictationDelivery(rawValue: defaults.string(forKey: DefaultsKey.dictationDelivery) ?? "") ?? .paste
        let targetIsActive = targetPID != nil && NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID
        if delivery != .copy, targetIsActive, AXIsProcessTrusted(), !IsSecureEventInputEnabled() {
            let accepted = TransientPaste.shared.paste(value, restoreClipboard: delivery == .pasteAndRestore, suppressClipboardNotice: true,
                canPostShortcut: { [weak self] in
                    guard let self else { return false }
                    return self.generation == token && AXIsProcessTrusted() && !IsSecureEventInputEnabled()
                        && NSWorkspace.shared.frontmostApplication?.processIdentifier == self.targetPID
                },
                didPostShortcut: { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.status = "Text pasted"; self.complete()
                }, didFail: { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.copy(value, token: token)
                })
            if !accepted { copy(value, token: token) }
            return
        }
        // Clipboard delivery also acts as a safe fallback when focus changed.
        copy(value, token: token)
    }

    private func copy(_ value: String, token: UUID) {
        guard generation == token else { return }
        let validity = deliveryValidity
        GeneralPasteboardAccess.shared.async {
            guard validity.isActive else { return }
            let board = NSPasteboard.general
            board.clearContents()
            let succeeded = board.setString(value, forType: .string)
            if succeeded { board.setString("1", forType: NSPasteboard.PasteboardType(ClipboardHistoryCapturePolicy.dictationOriginType)) }
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                guard succeeded else { self.fail("The transcript is in speech history, but copying failed."); return }
                self.status = self.text.copied
                self.complete()
            }
        }
    }

    func copyEntry(_ entry: DictationEntry, completion: ((Bool) -> Void)? = nil) {
        guard AppFeature.dictation.isAvailable else { completion?(false); return }
        GeneralPasteboardAccess.shared.async {
            NSPasteboard.general.clearContents()
            let succeeded = NSPasteboard.general.setString(entry.text, forType: .string)
            if succeeded { NSPasteboard.general.setString("1", forType: NSPasteboard.PasteboardType(ClipboardHistoryCapturePolicy.dictationOriginType)) }
            DispatchQueue.main.async { completion?(succeeded) }
        }
    }

    func copyResult() {
        guard !result.isEmpty, !phase.isBusy else { return }
        copy(result, token: generation)
    }

    /// Silence/empty recognition is a normal end to a recording. Nothing is
    /// copied or saved, and the warm model remains available for the next press.
    private func finishWithoutTranscript() {
        generation = UUID()
        timer?.invalidate(); timer = nil
        processingWatchdog?.cancel(); processingWatchdog = nil
        cleanupTask?.cancel(); cleanupTask = nil
        cleanupPrevious()
        liveID = nil; pressTime = nil; startedWithShortcut = false
        result = ""; status = ""; error = nil; elapsed = 0
        phase = .idle
        scheduleUnload()
    }

    private func complete() {
        phase = .completed
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.phase == .completed else { return }
            self.phase = .idle
        }
        completionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    func dismiss() {
        guard !phase.isBusy else { return }
        completionWork?.cancel(); phase = .idle
    }

    func cancel() {
        let abandoned = phase == .recording && enabled && isEnabled ? liveID : nil
        generation = UUID()
        timer?.invalidate(); timer = nil
        processingWatchdog?.cancel(); processingWatchdog = nil
        completionWork?.cancel(); completionWork = nil
        cleanupTask?.cancel(); cleanupTask = nil
        recorder.stop()
        if let abandoned { engine.discardLive(abandoned) } else { engine.cancel() }
        liveID = nil
        unloadWork?.cancel(); unloadWork = nil
        if abandoned != nil { scheduleUnload() }
        cleanupPrevious()
        pressTime = nil; startedWithShortcut = false
        phase = .idle; error = nil
    }

    private func fail(_ message: String) {
        timer?.invalidate(); timer = nil; recorder.stop()
        if liveID != nil { engine.cancel(); liveID = nil }
        processingWatchdog?.cancel(); processingWatchdog = nil
        cleanupPrevious()
        error = message
        phase = .failed
        scheduleUnload()
    }

    private func cleanupPrevious() {
        completionWork?.cancel(); completionWork = nil
        if ownsRecording, let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil; ownsRecording = false
    }

    func unloadEngine() { unloadWork?.cancel(); unloadWork = nil; engine.cancel() }

    private func scheduleUnload() {
        unloadWork?.cancel()
        let seconds = defaults.double(forKey: DefaultsKey.dictationUnload)
        guard seconds >= 0 else { return }
        let work = DispatchWorkItem { [weak self] in self?.engine.cancel() }
        unloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

#if VORSSAINT_DEVELOPMENT
    static func verifiesEmptyOutcome() -> Bool {
        let fixture = presentationFixture(.processing)
        fixture.finishWithoutTranscript()
        return fixture.phase == .idle && fixture.error == nil && fixture.result.isEmpty && fixture.status.isEmpty
    }

    /// Inert view fixture: never starts input taps, capture, inference or storage.
    static func presentationFixture(_ phase: DictationPhase) -> DictationService {
        let service = DictationService()
        service.elapsed = 12
        let samples = DictationSpectrum()
        let audio: [Float] = (0..<7680).map { index in
            let phase = Double(index)
            let envelope = 0.06 + 0.12 * pow(sin(phase * 0.0005), 2)
            return Float(sin(phase * 0.09) * envelope)
        }
        samples.append(audio)
        service.waveform = samples.bars
        service.result = "A quieter place for your thoughts. Everything you say, right here on your Mac."
        service.status = "Text copied"
        service.error = "Download or import a speech model in Dictation settings first."
        service.phase = phase
        return service
    }
#endif
}
