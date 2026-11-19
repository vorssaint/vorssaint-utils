// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.

import AppKit
import ApplicationServices
import AVFoundation
import Combine

extension FaceUnlockLiveness {
    /// The recognizer's own mode, nil when the checks are off.
    var mode: LivenessMode? {
        switch self {
        case .off: return nil
        case .light: return .light
        case .heavy: return .heavy
        }
    }
}

/// Signs in at the lock screen when the camera recognises the person.
///
/// macOS has no way for an app to approve a login, so the only way in is the
/// one a person uses: typing the account password. Face Unlock holds that
/// password sealed (see `FaceUnlockVault`) and types it, once a face matches
/// AND the liveness checks agree, while the session server says the screen is
/// really locked. It is a convenience, not a security upgrade: a Mac's camera
/// sees a flat image, not a depth map.
///
/// The service owns nothing while the feature is off: no observers, no timer,
/// no camera, no model.
@MainActor
final class FaceUnlockService: ObservableObject {
    static let shared = FaceUnlockService()

    /// What the lock screen's padlock shows.
    @Published private(set) var phase: FaceUnlockPhase = .idle
    /// Set when the saved password was typed twice and refused. Cleared when
    /// a new password is saved.
    @Published private(set) var passwordRejectedTwice = false

    private let lockMonitor = FaceUnlockLockMonitor()
    private let camera = FaceUnlockCamera()
    /// Loaded on first use: the model is several megabytes.
    private(set) lazy var pipeline = FaceRecognitionPipeline()

    private var isRunning = false
    private var hasArmedForCurrentLock = false
    private var hasRetriedForCurrentLock = false
    private var lastArmedAt: ContinuousClock.Instant?
    private var rejectionCount = 0
    private var scanTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var phaseResetTask: Task<Void, Never>?
    /// Bumped by every scan; a cycle that finds itself superseded does
    /// nothing further, so it cannot stop the camera a newer one is using.
    private var scanGeneration = 0
    private var idleTimer: Timer?
    private var defaultsObserver: NSObjectProtocol?

    private let rearmDebounce: Duration = .seconds(2)
    private let failureHold: Duration = .seconds(2)

    private init() {}

    // MARK: - Lifecycle

    func syncWithPreferences() {
        if FaceUnlockSupport.isEnabled() { start() } else { stop() }
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        FaceRecognitionPipeline.minimumProminentFaceWidth = FaceUnlockSupport.minimumFaceWidth
        lockMonitor.onEvent = { [weak self] event in self?.handle(event) }
        lockMonitor.start()
        let timer = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.lockSessionIfExpired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
        lockSessionIfExpired()
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        lockMonitor.onEvent = nil
        lockMonitor.stop()
        idleTimer?.invalidate()
        idleTimer = nil
        disarm()
        // Switched off, the key is forgotten too: the sealed data stays, and
        // reading it again takes the same Touch ID confirmation.
        FaceUnlockVault.lockSession()
    }

    // MARK: - Events

    private func handle(_ event: FaceUnlockLockEvent) {
        Task { [weak self] in
            // The session server can lag the notification by a moment.
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.evaluate(event)
        }
    }

    private func evaluate(_ event: FaceUnlockLockEvent) {
        guard isRunning else { return }
        guard FaceUnlockLockMonitor.isScreenActuallyLocked() else {
            hasArmedForCurrentLock = false
            hasRetriedForCurrentLock = false
            disarm()
            return
        }
        guard !lockMonitor.isSleeping else { return }
        if event == .wake, !isWithinRecentArmBurst { hasArmedForCurrentLock = false }
        guard !hasArmedForCurrentLock else { return }
        let defaults = UserDefaults.standard
        guard FaceUnlockSupport.armsScan(event: event,
                                         onWake: FaceUnlockSupport.triggersOnWake(in: defaults),
                                         onLock: FaceUnlockSupport.triggersOnLock(in: defaults)) else { return }
        lockSessionIfExpired()
        guard currentBlocker() == nil else {
            // Say why in the padlock only when the person can act on it.
            return
        }
        hasArmedForCurrentLock = true
        lastArmedAt = .now
        startScan()
    }

    /// One lid opening fires several wake signals within a few hundred
    /// milliseconds; they count as the same wake.
    private var isWithinRecentArmBurst: Bool {
        guard let lastArmedAt else { return false }
        return ContinuousClock.now - lastArmedAt < rearmDebounce
    }

    // MARK: - State for the settings

    var hasActiveFace: Bool {
        FaceEnrollmentStore.shared.activeIdentities.contains { !$0.samples.isEmpty }
    }

    /// Live answers, never the published caches: this runs at a lock screen.
    func currentBlocker() -> FaceUnlockBlocker? {
        FaceUnlockSupport.blocker(
            isEnabled: FaceUnlockSupport.isEnabled(),
            modelAvailable: !pipeline.usingFallbackEmbedder,
            passwordRejectedTwice: passwordRejectedTwice,
            accessibility: AXIsProcessTrusted(),
            camera: AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
            sessionUnlocked: FaceUnlockVault.isSessionUnlocked,
            hasPassword: FaceUnlockVault.hasStoredPassword(),
            hasActiveFace: hasActiveFace)
    }

    /// A new password supersedes whatever was refused.
    func passwordWasSaved() {
        rejectionCount = 0
        passwordRejectedTwice = false
    }

    private func lockSessionIfExpired() {
        guard FaceUnlockVault.isSessionUnlocked,
              FaceUnlockSupport.sessionExpired(lastActivity: FaceUnlockVault.lastActivityAt,
                                               limit: FaceUnlockSupport.sessionLimit()) else { return }
        FaceUnlockVault.lockSession()
    }

    // MARK: - Scanning

    /// A tap on the padlock: look again, once the last look has finished.
    func retry() {
        guard isRunning, FaceUnlockLockMonitor.isScreenActuallyLocked() else { return }
        switch phase {
        case .armed, .failure: break
        default: return
        }
        guard currentBlocker() == nil else { return }
        startScan()
    }

    private func startScan() {
        scanTask?.cancel()
        retryTask?.cancel()
        phaseResetTask?.cancel()
        scanGeneration &+= 1
        let generation = scanGeneration
        scanTask = Task { [weak self] in await self?.runScan(generation: generation) }
    }

    private func disarm() {
        scanTask?.cancel()
        scanTask = nil
        retryTask?.cancel()
        retryTask = nil
        phaseResetTask?.cancel()
        phaseResetTask = nil
        scanGeneration &+= 1
        camera.stop()
        setPhase(.idle)
    }

    private func setPhase(_ new: FaceUnlockPhase) {
        guard phase != new else { return }
        phase = new
    }

    private enum ScanOutcome {
        case matched
        case consistentlyWrongFace
        case spoofSuspected
        case noResolution
        case passwordRejected
    }

    private func runScan(generation: Int) async {
        guard FaceUnlockLockMonitor.isScreenActuallyLocked() else { return }
        await camera.start()
        guard generation == scanGeneration else { return }
        if camera.error != nil {
            camera.stop()
            finish(.failure(.cameraUnavailable), generation: generation)
            return
        }
        setPhase(.scanning)

        let seconds = FaceUnlockSupport.scanSeconds()
        let outcome = await observe(deadline: Date().addingTimeInterval(TimeInterval(seconds)), mode: .unlock,
                                    generation: generation)
        // A newer scan now owns the camera and the padlock.
        guard generation == scanGeneration else { return }
        camera.stop()

        switch outcome {
        case .matched:
            setPhase(.success)
        case .consistentlyWrongFace:
            finish(.failure(.notRecognized), generation: generation)
        case .spoofSuspected:
            finish(.failure(.notLive), generation: generation)
        case .noResolution:
            finish(.failure(.noFace), generation: generation)
        case .passwordRejected:
            finish(.failure(.passwordRejected), generation: generation)
        }
    }

    /// Shows a failure, then settles to "tap to try again", retrying once on
    /// its own when that is chosen.
    private func finish(_ failure: FaceUnlockPhase, generation: Int) {
        guard generation == scanGeneration else { return }
        setPhase(failure)
        let retriesOnce = UserDefaults.standard.bool(forKey: DefaultsKey.faceUnlockRetryOnce)
            && !hasRetriedForCurrentLock && failure != .failure(.passwordRejected)
            && failure != .failure(.cameraUnavailable)
        if retriesOnce { hasRetriedForCurrentLock = true }
        phaseResetTask?.cancel()
        let hold = failureHold
        phaseResetTask = Task { [weak self] in
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled, let self, generation == self.scanGeneration else { return }
            guard FaceUnlockLockMonitor.isScreenActuallyLocked() else { return }
            if retriesOnce, self.currentBlocker() == nil {
                self.startScan()
            } else {
                self.setPhase(.armed)
            }
        }
    }

    /// Recognition and liveness run side by side and each latches when it
    /// succeeds, so the unlock happens the moment the second lands. Liveness
    /// never fails a scan by staying undecided; it keeps looking to the
    /// deadline.
    private enum ScanMode {
        /// The Mac is locked: a match types the saved password.
        case unlock
        /// Someone asks to open a locked app: a match only says it is them.
        case verify
    }

    private func observe(deadline: Date, mode: ScanMode, generation: Int) async -> ScanOutcome {
        let defaults = UserDefaults.standard
        let livenessChoice = FaceUnlockSupport.liveness(in: defaults)
        let livenessEnabled = livenessChoice != .off
        let liveness = LivenessAnalyzer()
        let livenessMode = livenessChoice.mode ?? .light
        liveness.modeProvider = { livenessMode }
        let threshold = FaceUnlockSupport.strictness(in: defaults).threshold

        var wrongFaceStartedAt: ContinuousClock.Instant?
        // Cleared the moment a detected face fails to match, so a latched
        // match can never be handed to whoever steps in next.
        var matched = false
        var livenessConfirmed = !livenessEnabled
        var lastFaceBox: CGRect?
        var lastFrameID: UInt64?

        while Date() < deadline, !Task.isCancelled, generation == scanGeneration {
            if mode == .unlock, !FaceUnlockLockMonitor.isScreenActuallyLocked() { return .noResolution }
            guard let frame = camera.currentFrame, frame.id != lastFrameID else {
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastFrameID = frame.id

            let pipeline = self.pipeline
            let previousBox = lastFaceBox
            let analysed = await Task.detached(priority: .userInitiated) {
                () -> (FaceRecognitionResult, LivenessFrame)? in
                guard let result = try? pipeline.recognize(in: frame.image, preferNear: previousBox) else { return nil }
                let crop = FaceUnlockCamera.renderCrop(from: frame, imageRect: result.face.boundingBox)
                return (result, LivenessFeatureExtractor.extract(from: result, frame: frame.image, faceCrop: crop))
            }.value

            guard let (result, livenessFrame) = analysed else {
                wrongFaceStartedAt = nil
                lastFaceBox = nil
                try? await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            lastFaceBox = result.face.normalizedBoundingBox

            // Fed whether or not the face matched, so liveness stays a gate of
            // its own rather than one starved by recognition confidence.
            if livenessEnabled {
                switch liveness.observe(livenessFrame).decision {
                case .denied:
                    // Overrides everything, a match and an earlier confirmation included.
                    return .spoofSuspected
                case .confirmed:
                    livenessConfirmed = true
                case .pending:
                    break
                }
            }

            // Someone switched off in Settings stays enrolled but never opens the Mac.
            let scored = pipeline.score(result.embedding, against: FaceEnrollmentStore.shared.activeIdentities)
            if pipeline.bestMatch(in: scored, threshold: threshold) != nil {
                wrongFaceStartedAt = nil
                matched = true
            } else {
                matched = false
                if wrongFaceStartedAt == nil { wrongFaceStartedAt = .now }
                if ContinuousClock.now - wrongFaceStartedAt! >= .seconds(FaceUnlockSupport.wrongFaceGrace) {
                    return .consistentlyWrongFace
                }
            }

            if matched, livenessConfirmed {
                if mode == .verify { return .matched }
                return await signIn() ? .matched : .passwordRejected
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return .noResolution
    }

    // MARK: - Proving it is you, for Privacy Lock

    /// Whether a face check can run now: Face Unlock is on, the camera is
    /// allowed, the Touch ID session is open and a face is enrolled. Nothing
    /// here needs Accessibility, because nothing is typed.
    func canVerifyFace() -> Bool {
        FaceUnlockSupport.isEnabled() && !pipeline.usingFallbackEmbedder
            && AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            && FaceUnlockVault.isSessionUnlocked && hasActiveFace
    }

    private var verifyGeneration: Int?

    /// Looks for an enrolled face, with the same match strictness and liveness
    /// checks as the lock screen, and answers whether it found one. Types
    /// nothing. Another look (or `cancelVerify`) ends this one.
    func verifyFace() async -> Bool {
        guard canVerifyFace(), phase != .scanning else { return false }
        scanGeneration &+= 1
        let generation = scanGeneration
        verifyGeneration = generation
        await camera.start()
        guard generation == scanGeneration, camera.error == nil else {
            if generation == scanGeneration { camera.stop() }
            return false
        }
        let outcome = await observe(deadline: Date().addingTimeInterval(TimeInterval(FaceUnlockSupport.scanSeconds())),
                                    mode: .verify, generation: generation)
        guard generation == scanGeneration else { return false }
        camera.stop()
        verifyGeneration = nil
        return outcome == .matched
    }

    func cancelVerify() {
        guard verifyGeneration != nil else { return }
        verifyGeneration = nil
        scanGeneration &+= 1
        camera.stop()
    }

    // MARK: - Typing the password

    /// Types the saved password and waits to see the Mac open. Returns false
    /// when the Mac is still locked afterwards, which means the password was
    /// refused (or never typed). Two refusals in a row stop the typing until
    /// a new password is saved, so a stale password cannot pile up wrong
    /// attempts on the account.
    private func signIn() async -> Bool {
        guard AXIsProcessTrusted(), FaceUnlockVault.isSessionUnlocked,
              FaceUnlockLockMonitor.isScreenActuallyLocked() else { return false }
        let typed: Bool = await Task.detached(priority: .userInitiated) {
            do {
                var bytes = try FaceUnlockVault.readPassword()
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                try KeystrokeInjector.typeAndReturn(bytes)
                return true
            } catch {
                return false
            }
        }.value
        guard typed else { return false }

        // The lock screen takes a moment to accept a password and drop.
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !FaceUnlockLockMonitor.isScreenActuallyLocked() {
                rejectionCount = 0
                return true
            }
        }
        rejectionCount += 1
        if rejectionCount >= 2 { passwordRejectedTwice = true }
        return false
    }
}
