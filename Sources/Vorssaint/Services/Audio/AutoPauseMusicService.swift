// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon
import Darwin
import Foundation
import os.log

/// Pauses the chosen music player after another eligible app keeps an output
/// stream active, then optionally resumes it once that stream has remained
/// inactive. On macOS 14.4 and later this consumes the same push-driven Core
/// Audio process snapshot as the app-volume mixer; older systems retain a
/// small MediaRemote polling fallback.
final class AutoPauseMusicService: ObservableObject {
    static let shared = AutoPauseMusicService()

    static let fallbackPollInterval: TimeInterval = 1.5

    private enum AutomationPermissionState {
        case unknown
        case requesting
        case granted
        case denied
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "auto-pause-music")

    private var mediaRemoteBridge: MediaRemoteMonitorBridge?
    /// Permission checks and AppleScript both block their calling thread until
    /// the target replies. One serial worker keeps them ordered and off-main.
    private let automationQueue = DispatchQueue(
        label: "com.vorssaint.auto-pause-music.automation",
        qos: .userInitiated)

    private var fallbackTimer: Timer?
    private var audioProcessObservation: UUID?
    private var latestProcessSnapshot = AudioProcessActivitySnapshot.empty
    private var fallbackFetchInFlight = false
    private var stableOtherSourceIsActive = false
    private var pendingOtherSourceIsActive: Bool?
    private var activityTransitionGeneration = 0
    private var weAutoPaused = false
    private var automationTargetBundleID: String?
    private var automationPermissionState: AutomationPermissionState = .unknown
    private var automationActionInFlight = false
    private var reevaluateAfterAction = false
    private var automationActionGeneration = 0
    private var lifecycleGeneration = 0
    private var isRunningService = false
    private var lastActiveAudioBundleIDs: Set<String>?

    private init() {}

    func syncWithPreferences() {
        let shouldRun = AppFeature.autoPauseMusic.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.autoPauseMusicEnabled)
        if shouldRun {
            start()
            evaluateCurrentSourceState()
        } else {
            stop()
        }
    }

    /// Requests the per-player Automation permission explicitly. The TCC call
    /// runs off-main because it can wait on the consent sheet; activation stays
    /// on-main so a menu-bar-only app presents that sheet visibly.
    func requestAutomationPermission(forAppAtPath requestedPath: String? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.requestAutomationPermission(forAppAtPath: requestedPath)
            }
            return
        }
        let requested = requestedPath ?? ""
        let path = requested.isEmpty ? selectedPlayerPath() : requested
        guard let bundleID = AutoPauseMusicSupport.bundleIdentifier(forAppAtPath: path) else {
            Self.log.notice("permission request skipped: no valid player bundle")
            return
        }
        prepareAutomationTarget(bundleID)
        guard isRunning(bundleID: bundleID) else {
            automationPermissionState = .unknown
            Self.log.notice("permission request deferred: target \(bundleID, privacy: .public) is not running")
            return
        }
        beginAutomationPermissionRequest(bundleID: bundleID, force: true)
    }

    private func start() {
        guard !isRunningService else { return }
        isRunningService = true
        lifecycleGeneration &+= 1
        Self.log.log("service started")

        if AudioProcessActivitySupport.isSupported {
            audioProcessObservation = AudioProcessActivityMonitor.shared.observe { [weak self] snapshot in
                self?.receiveProcessSnapshot(snapshot)
            }
        } else {
            let bridge = MediaRemoteMonitorBridge()
            mediaRemoteBridge = bridge
            bridge.registerForNotifications()
            let timer = Timer(timeInterval: Self.fallbackPollInterval, repeats: true) { [weak self] _ in
                self?.fetchMediaRemoteFallback()
            }
            timer.tolerance = Self.fallbackPollInterval * 0.2
            RunLoop.main.add(timer, forMode: .common)
            fallbackTimer = timer
            fetchMediaRemoteFallback()
        }
    }

    private func stop() {
        guard isRunningService else { return }
        isRunningService = false
        lifecycleGeneration &+= 1
        activityTransitionGeneration &+= 1
        automationActionGeneration &+= 1

        if let audioProcessObservation {
            AudioProcessActivityMonitor.shared.removeObserver(audioProcessObservation)
            self.audioProcessObservation = nil
        }
        if fallbackTimer != nil {
            mediaRemoteBridge?.unregisterForNotifications()
            fallbackTimer?.invalidate()
            fallbackTimer = nil
            mediaRemoteBridge = nil
        }
        latestProcessSnapshot = .empty
        fallbackFetchInFlight = false
        stableOtherSourceIsActive = false
        pendingOtherSourceIsActive = nil
        weAutoPaused = false
        automationActionInFlight = false
        reevaluateAfterAction = false
        lastActiveAudioBundleIDs = nil
        Self.log.log("service stopped")
    }

    private func selectedPlayerPath() -> String {
        let defaults = UserDefaults.standard
        return AutoPauseMusicSupport.selectedPlayerPath(
            autoPausePath: defaults.string(forKey: DefaultsKey.autoPauseMusicPlayerPath) ?? "",
            musicBlockReplacementPath: defaults.string(
                forKey: DefaultsKey.musicBlockReplacementPath) ?? "")
    }

    private func selectedPlayerBundleID() -> String? {
        AutoPauseMusicSupport.bundleIdentifier(forAppAtPath: selectedPlayerPath())
    }

    private func evaluateCurrentSourceState() {
        guard isRunningService else { return }
        if AudioProcessActivitySupport.isSupported {
            receiveProcessSnapshot(latestProcessSnapshot)
        } else {
            fetchMediaRemoteFallback()
        }
    }

    private func receiveProcessSnapshot(_ snapshot: AudioProcessActivitySnapshot) {
        latestProcessSnapshot = snapshot
        guard let musicPlayerBundleID = selectedPlayerBundleID() else {
            observeOtherSource(isActive: false)
            return
        }
        prepareAutomationTarget(musicPlayerBundleID)

        let sourceActivities = snapshot.apps.map { activity in
            AutoPauseMusicSupport.SourceActivity(
                bundleIdentifier: activity.bundleIdentifier ?? "pid:\(activity.ownerPid)",
                isRunningOutput: activity.isRunningOutput,
                bypassesProcessTap: activity.bypassesProcessTap)
        }
        let activeBundleIDs = AutoPauseMusicSupport.activeBundleIdentifiers(from: sourceActivities)
        logActiveSources(activeBundleIDs)
        observeOtherSource(isActive: AutoPauseMusicSupport.otherAudioSourceIsActive(
            activeBundleIDs: activeBundleIDs,
            musicPlayerBundleID: musicPlayerBundleID))
    }

    private func fetchMediaRemoteFallback() {
        guard isRunningService, !fallbackFetchInFlight,
              let musicPlayerBundleID = selectedPlayerBundleID() else {
            if selectedPlayerBundleID() == nil { observeOtherSource(isActive: false) }
            return
        }
        prepareAutomationTarget(musicPlayerBundleID)
        fallbackFetchInFlight = true
        let generation = lifecycleGeneration
        guard let mediaRemoteBridge else {
            fallbackFetchInFlight = false
            return
        }
        mediaRemoteBridge.fetch { [weak self] nowPlayingBundleID, isPlaying in
            guard let self else { return }
            guard self.isRunningService, self.lifecycleGeneration == generation else { return }
            self.fallbackFetchInFlight = false
            let activeBundleIDs = isPlaying
                ? Set([nowPlayingBundleID].compactMap { $0 })
                : []
            self.logActiveSources(activeBundleIDs)
            self.observeOtherSource(isActive: AutoPauseMusicSupport.otherSourceIsActive(
                nowPlayingBundleID: nowPlayingBundleID,
                nowPlayingIsPlaying: isPlaying,
                musicPlayerBundleID: musicPlayerBundleID))
        }
    }

    private func logActiveSources(_ activeBundleIDs: Set<String>) {
        guard lastActiveAudioBundleIDs != activeBundleIDs else { return }
        let sources = activeBundleIDs.sorted().joined(separator: ",")
        Self.log.log("Active output streams=\(sources.isEmpty ? "none" : sources, privacy: .public)")
        lastActiveAudioBundleIDs = activeBundleIDs
    }

    private func observeOtherSource(isActive: Bool) {
        guard isRunningService else { return }
        if isActive == stableOtherSourceIsActive {
            activityTransitionGeneration &+= 1
            pendingOtherSourceIsActive = nil
            evaluateDecision()
            return
        }
        guard pendingOtherSourceIsActive != isActive,
              let delay = AutoPauseMusicSupport.transitionDelay(
                stableOtherSourceIsActive: stableOtherSourceIsActive,
                observedOtherSourceIsActive: isActive) else { return }

        pendingOtherSourceIsActive = isActive
        activityTransitionGeneration &+= 1
        let transition = activityTransitionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.isRunningService,
                  self.activityTransitionGeneration == transition,
                  self.pendingOtherSourceIsActive == isActive else { return }
            self.pendingOtherSourceIsActive = nil
            self.stableOtherSourceIsActive = isActive
            Self.log.log("competing output became \(isActive ? "active" : "inactive", privacy: .public)")
            self.evaluateDecision()
        }
    }

    private func evaluateDecision() {
        guard isRunningService else { return }
        if automationActionInFlight {
            reevaluateAfterAction = true
            return
        }
        guard let musicPlayerBundleID = selectedPlayerBundleID() else { return }
        prepareAutomationTarget(musicPlayerBundleID)
        let decision = AutoPauseMusicSupport.decide(
            otherSourceIsActive: stableOtherSourceIsActive,
            weAutoPaused: weAutoPaused,
            resumeEnabled: UserDefaults.standard.bool(
                forKey: DefaultsKey.autoPauseMusicResumeEnabled))
        act(decision, musicPlayerBundleID: musicPlayerBundleID)
    }

    private func act(_ decision: AutoPauseMusicSupport.Decision, musicPlayerBundleID: String) {
        switch decision {
        case .pause:
            guard isRunning(bundleID: musicPlayerBundleID) else { return }
            guard automationPermissionState == .granted else {
                beginAutomationPermissionRequest(bundleID: musicPlayerBundleID, force: false)
                return
            }
            runPause(bundleID: musicPlayerBundleID)
        case .resume:
            weAutoPaused = false
            guard isRunning(bundleID: musicPlayerBundleID) else { return }
            runResume(bundleID: musicPlayerBundleID)
        case .clearFlag:
            weAutoPaused = false
        case .none:
            break
        }
    }

    private func runPause(bundleID: String) {
        beginAutomationAction()
        let action = automationActionGeneration
        let generation = lifecycleGeneration
        let source = AutoPauseMusicSupport.pauseIfPlayingScript(bundleID: bundleID)
        automationQueue.async { [weak self] in
            let result = AppleScriptRunner.runDetailed(source)
            DispatchQueue.main.async {
                guard let self else { return }
                self.finishPause(result, bundleID: bundleID,
                                 action: action, generation: generation)
            }
        }
    }

    private func finishPause(_ result: (ok: Bool, errorNumber: Int?, message: String, output: String),
                             bundleID: String,
                             action: Int,
                             generation: Int) {
        guard actionIsCurrent(action, generation: generation, bundleID: bundleID) else { return }
        if result.ok {
            weAutoPaused = AutoPauseMusicSupport.didPause(output: result.output)
            Self.log.log("AppleScript pause check succeeded for \(bundleID, privacy: .public)")
        } else {
            handleAppleScriptFailure(result, operation: "pause", bundleID: bundleID)
        }
        finishAutomationAction()
    }

    private func runResume(bundleID: String) {
        beginAutomationAction()
        let action = automationActionGeneration
        let generation = lifecycleGeneration
        let source = AutoPauseMusicSupport.playScript(bundleID: bundleID)
        automationQueue.async { [weak self] in
            let result = AppleScriptRunner.runDetailed(source)
            DispatchQueue.main.async {
                guard let self,
                      self.actionIsCurrent(action, generation: generation, bundleID: bundleID)
                else { return }
                if result.ok {
                    Self.log.log("AppleScript resume succeeded for \(bundleID, privacy: .public)")
                } else {
                    self.handleAppleScriptFailure(result, operation: "resume", bundleID: bundleID)
                }
                self.finishAutomationAction()
            }
        }
    }

    private func beginAutomationAction() {
        automationActionGeneration &+= 1
        automationActionInFlight = true
        reevaluateAfterAction = false
    }

    private func actionIsCurrent(_ action: Int, generation: Int, bundleID: String) -> Bool {
        isRunningService
            && lifecycleGeneration == generation
            && automationActionGeneration == action
            && automationTargetBundleID == bundleID
    }

    private func finishAutomationAction() {
        automationActionInFlight = false
        if reevaluateAfterAction {
            reevaluateAfterAction = false
            evaluateDecision()
        }
    }

    private func handleAppleScriptFailure(
        _ result: (ok: Bool, errorNumber: Int?, message: String, output: String),
        operation: String,
        bundleID: String
    ) {
        if result.errorNumber == Int(errAEEventNotPermitted) {
            automationPermissionState = .denied
        } else if result.errorNumber == Int(errAEEventWouldRequireUserConsent) {
            automationPermissionState = .unknown
        }
        Self.log.error("AppleScript \(operation, privacy: .public) failed for \(bundleID, privacy: .public): \(result.errorNumber ?? 0) \(result.message, privacy: .public)")
    }

    private func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private func prepareAutomationTarget(_ bundleID: String) {
        guard automationTargetBundleID != bundleID else { return }
        automationTargetBundleID = bundleID
        automationPermissionState = .unknown
        weAutoPaused = false
        automationActionGeneration &+= 1
        automationActionInFlight = false
        reevaluateAfterAction = false
        Self.log.log("automation target changed to \(bundleID, privacy: .public)")
    }

    private func beginAutomationPermissionRequest(bundleID: String, force: Bool) {
        guard automationTargetBundleID == bundleID else { return }
        if !force {
            guard automationPermissionState == .unknown else { return }
        } else if automationPermissionState == .requesting {
            return
        }
        automationPermissionState = .requesting
        Self.log.log("checking Automation permission for \(bundleID, privacy: .public)")

        automationQueue.async { [weak self] in
            let status = AppleScriptRunner.automationPermissionStatus(
                bundleID: bundleID, askUserIfNeeded: false)
            DispatchQueue.main.async {
                self?.handleAutomationPermissionCheck(status, bundleID: bundleID)
            }
        }
    }

    private func handleAutomationPermissionCheck(_ status: OSStatus, bundleID: String) {
        guard automationTargetBundleID == bundleID,
              automationPermissionState == .requesting else { return }
        guard status == OSStatus(errAEEventWouldRequireUserConsent) else {
            finishAutomationPermissionRequest(status, bundleID: bundleID)
            return
        }

        Self.log.log("Automation consent is undetermined for \(bundleID, privacy: .public); prompting")
        NSApp.activate(ignoringOtherApps: true)
        automationQueue.async { [weak self] in
            let promptedStatus = AppleScriptRunner.automationPermissionStatus(
                bundleID: bundleID, askUserIfNeeded: true)
            DispatchQueue.main.async {
                self?.finishAutomationPermissionRequest(promptedStatus, bundleID: bundleID)
            }
        }
    }

    private func finishAutomationPermissionRequest(_ status: OSStatus, bundleID: String) {
        guard automationTargetBundleID == bundleID else { return }
        switch status {
        case 0:
            automationPermissionState = .granted
            Self.log.log("Automation permission granted for \(bundleID, privacy: .public)")
            evaluateDecision()
        case OSStatus(errAEEventNotPermitted):
            automationPermissionState = .denied
            Self.log.error("Automation permission denied for \(bundleID, privacy: .public) (status \(status))")
        case OSStatus(procNotFound):
            automationPermissionState = .unknown
            Self.log.notice("Automation permission unavailable: target \(bundleID, privacy: .public) stopped (status \(status))")
        default:
            automationPermissionState = .denied
            Self.log.error("Automation permission check failed for \(bundleID, privacy: .public) (status \(status))")
        }
    }
}

/// Minimal, session-scoped bridge to the private MediaRemote framework: just
/// enough to learn which app currently owns Now Playing and whether it is
/// producing sound. It is loaded and registered only on systems predating the
/// public Core Audio process property used by the shared push monitor.
private final class MediaRemoteMonitorBridge {
    private typealias PIDCallback = @convention(block) (Int32) -> Void
    private typealias PIDFunction = @convention(c) (DispatchQueue, @escaping PIDCallback) -> Void
    private typealias DisplayIDCallback = @convention(block) (NSString?) -> Void
    private typealias DisplayIDFunction = @convention(c) (DispatchQueue, @escaping DisplayIDCallback) -> Void
    private typealias IsPlayingCallback = @convention(block) (Bool) -> Void
    private typealias IsPlayingFunction = @convention(c) (DispatchQueue, @escaping IsPlayingCallback) -> Void
    private typealias RegisterFunction = @convention(c) (DispatchQueue) -> Void
    private typealias UnregisterFunction = @convention(c) () -> Void

    private let queue = DispatchQueue(label: "com.vorssaint.auto-pause-music.media-remote", qos: .utility)
    private let handle: UnsafeMutableRawPointer?
    private let getPID: PIDFunction?
    private let getDisplayID: DisplayIDFunction?
    private let getIsPlaying: IsPlayingFunction?
    private let register: RegisterFunction?
    private let unregister: UnregisterFunction?
    private var isRegistered = false

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        self.handle = handle
        getPID = Self.function(handle, "MRMediaRemoteGetNowPlayingApplicationPID", as: PIDFunction.self)
        getDisplayID = Self.function(handle, "MRMediaRemoteGetNowPlayingApplicationDisplayID",
                                     as: DisplayIDFunction.self)
        getIsPlaying = Self.function(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
                                     as: IsPlayingFunction.self)
        register = Self.function(handle, "MRMediaRemoteRegisterForNowPlayingNotifications",
                                 as: RegisterFunction.self)
        unregister = Self.function(handle, "MRMediaRemoteUnregisterForNowPlayingNotifications",
                                   as: UnregisterFunction.self)
    }

    func registerForNotifications() {
        guard !isRegistered, let register else { return }
        register(queue)
        isRegistered = true
    }

    func unregisterForNotifications() {
        guard isRegistered, let unregister else { return }
        unregister()
        isRegistered = false
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    func fetch(completion: @escaping (String?, Bool) -> Void) {
        guard (getDisplayID != nil || getPID != nil), let getIsPlaying else {
            completion(nil, false)
            return
        }
        let result = FetchResult(completion: completion)
        let group = DispatchGroup()

        if let getDisplayID {
            group.enter()
            getDisplayID(queue) { value in
                result.setDisplayID(value as String?)
                group.leave()
            }
        }
        if let getPID {
            group.enter()
            getPID(queue) { value in
                result.setPID(value)
                group.leave()
            }
        }
        group.enter()
        getIsPlaying(queue) { value in
            result.setIsPlaying(value)
            group.leave()
        }
        group.notify(queue: .main) {
            result.finish()
        }
        queue.asyncAfter(deadline: .now() + 0.75) {
            DispatchQueue.main.async { result.finish() }
        }
    }

    private final class FetchResult {
        private let lock = NSLock()
        private var pid: Int32 = 0
        private var displayID: String?
        private var isPlaying = false
        private var finished = false
        private let completion: (String?, Bool) -> Void

        init(completion: @escaping (String?, Bool) -> Void) {
            self.completion = completion
        }

        func setPID(_ pid: Int32) {
            lock.withLock { self.pid = pid }
        }

        func setDisplayID(_ displayID: String?) {
            lock.withLock { self.displayID = displayID }
        }

        func setIsPlaying(_ isPlaying: Bool) {
            lock.withLock { self.isPlaying = isPlaying }
        }

        func finish() {
            let values: (Int32, String?, Bool)? = lock.withLock {
                guard !finished else { return nil }
                finished = true
                return (pid, displayID, isPlaying)
            }
            guard let (pid, displayID, isPlaying) = values else { return }
            let pidBundleID = pid > 0
                ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                : nil
            let bundleID = AutoPauseMusicSupport.nowPlayingBundleIdentifier(
                displayID: displayID,
                pidBundleIdentifier: pidBundleID)
            completion(bundleID, isPlaying)
        }
    }

    private static func function<T>(_ handle: UnsafeMutableRawPointer?,
                                    _ name: String,
                                    as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }
}
