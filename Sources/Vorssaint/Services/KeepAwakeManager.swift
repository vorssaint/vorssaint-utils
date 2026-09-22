// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.ps
import IOKit.pwr_mgt

/// Core of the energy feature: manages "keep awake" sessions through IOKit power
/// assertions, the closed-lid mode (pmset disablesleep, administrator password)
/// and the battery protection watchdog.
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()

    enum EndReason { case manual, timer, battery, quit }
    enum SessionTrigger { case manual, automation }

    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date? // nil = indefinite
    @Published private(set) var sessionTrigger: SessionTrigger?
    @Published private(set) var runningAppBundleIDs: [String] = []
    @Published private(set) var activeAutomationConditions = Set<KeepAwakeAutomationCondition>()
    @Published private(set) var clamshellActive = false
    @Published private(set) var passwordlessClamshell = false
    @Published private(set) var clamshellSetupInProgress = false
    @Published private(set) var clamshellSetupFailed = false

    /// Persistent preference: when on, every keep-awake session also disables
    /// lid sleep, and ending the session restores it — no per-session setup.
    @Published var clamshellPreferred: Bool {
        didSet {
            guard clamshellPreferred != oldValue else { return }
            UserDefaults.standard.set(clamshellPreferred, forKey: DefaultsKey.clamshellPreferred)
            clamshellSetupFailed = false
            guard !isTerminating else { return }
            if clamshellPreferred {
                if !sessionPausedForScreenLock { applyClamshellPreference() }
            } else if clamshellNeedsRestore {
                clamshellSetupInProgress = false
                clamshellSetupID = nil
                disableClamshell(synchronous: false)
            } else {
                clamshellSetupInProgress = false
                clamshellSetupID = nil
            }
        }
    }

    var onSessionEnded: ((EndReason) -> Void)?

    private var systemAssertion = IOPMAssertionID(0)
    private var displayAssertion = IOPMAssertionID(0)
    private var hasSystemAssertion = false
    private var hasDisplayAssertion = false
    private var endTimer: Timer?
    private var batteryTimer: Timer?
    private var mouseJiggleTimer: Timer?
    private var pendingMouseReturn: DispatchWorkItem?
    private var defaultsObserver: AnyCancellable?
    private var screenParametersObserver: NSObjectProtocol?
    private var screenLockObservers: [NSObjectProtocol] = []
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var runningAppsObservers: [NSObjectProtocol] = []
    private var automationEvaluationWorkItem: DispatchWorkItem?
    private var lastExternalDisplayConnected: Bool?
    private var screenLocked = false
    private var sessionPausedForScreenLock = false
    private var automationSuppressedUntilConditionsClear = false
    private var recoveryCompleted = false
    private var isTerminating = false
    private var clamshellEnablePending = false
    private var clamshellRestorePending = false
    private var clamshellOperationGeneration = 0
    private var clamshellSetupID: UUID?
    private var lidSleepGeneration = 0
    private var lidSleepAttemptsRemaining = 0
    private static let screenLockNotification = Notification.Name("com.apple.screenIsLocked")
    private static let screenUnlockNotification = Notification.Name("com.apple.screenIsUnlocked")
    /// Guards the closed-lid setup against an infinite retry loop: if `pmset
    /// disablesleep` keeps failing while the sudoers rule still checks out as
    /// installed, re-preparing would bounce here forever (and flicker the
    /// caption). One automatic re-acquire per user attempt, then we give up.
    private var clamshellSetupRetried = false
    /// A reply to a settings change already waiting for the next run loop turn.
    private var preferenceSyncScheduled = false

    private init() {
        clamshellPreferred = UserDefaults.standard.bool(forKey: DefaultsKey.clamshellPreferred)
        refreshPasswordlessStatus()
        // Every settings write announces itself, including the ones made from
        // inside this class, so a burst folds into a single reply on the next
        // turn of the run loop rather than one full pass per write.
        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                guard let self, !self.preferenceSyncScheduled else { return }
                self.preferenceSyncScheduled = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.preferenceSyncScheduled = false
                    self.syncWithPreferences()
                }
            }
    }

    /// Refreshes (in the background) whether the closed-lid sudoers rule is installed.
    func refreshPasswordlessStatus() {
        guard !isTerminating, !clamshellRestorePending else { return }
        let generation = clamshellOperationGeneration
        DispatchQueue.global(qos: .utility).async {
            let configured = Sudoers.isConfigured()
            DispatchQueue.main.async {
                guard !self.isTerminating, !self.clamshellRestorePending,
                      self.clamshellOperationGeneration == generation else { return }
                self.passwordlessClamshell = configured
            }
        }
    }

    // MARK: - Session

    func toggle() {
        if isActive {
            if sessionTrigger == .automation || automationConditionsHold() {
                automationSuppressedUntilConditionsClear = true
            }
            deactivate(reason: .manual)
        } else {
            activate(minutes: Defaults.sanitizedDefaultDuration(UserDefaults.standard.integer(forKey: DefaultsKey.defaultDuration)))
        }
    }

    /// Keep Awake leaving the hub ends any running session; everything else
    /// (saved duration, tint, shortcut setting) stays for its return.
    func syncWithFeatures() {
        guard AppFeature.keepAwake.isAvailable else {
            stopAutomationMonitoring()
            if isActive { deactivate(reason: .manual) }
            return
        }
        syncWithPreferences()
    }

    func syncWithPreferences() {
        guard !isTerminating else { return }
        syncAutomationMonitoring()
        if isActive, !sessionPausedForScreenLock { applyAssertions() }
        syncMouseJiggleTimer()
    }

    /// Called by automation controls so a deliberate preference change can
    /// resume evaluation after a manually stopped automatic session.
    func automationPreferencesDidChange() {
        automationSuppressedUntilConditionsClear = false
        syncWithPreferences()
    }

    /// `minutes <= 0` activates indefinitely.
    func activate(minutes: Int) {
        automationSuppressedUntilConditionsClear = false
        let minutes = Defaults.sanitizedDefaultDuration(minutes)
        let end = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes) * 60) : nil
        activate(end: end, trigger: .manual)
    }

    func activate(until date: Date) {
        guard date > Date() else { return }
        automationSuppressedUntilConditionsClear = false
        activate(end: date, trigger: .manual)
    }

    private func activate(end: Date?, trigger: SessionTrigger) {
        guard !isTerminating, AppFeature.keepAwake.isAvailable else { return }
        lidSleepGeneration &+= 1
        lidSleepAttemptsRemaining = 0
        endTimer?.invalidate()
        endTimer = nil
        syncScreenLockMonitoring()
        sessionPausedForScreenLock = screenLocked
            && UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakePauseWhenLocked)
        if !sessionPausedForScreenLock { applyAssertions() }
        sessionTrigger = trigger
        if trigger == .manual {
            activeAutomationConditions.removeAll()
        }
        isActive = true
        if let end {
            endDate = end
            scheduleEnd(at: end)
        } else {
            endDate = nil
        }
        if !sessionPausedForScreenLock { startBatteryWatch() }
        syncMouseJiggleTimer()
        if clamshellPreferred, !sessionPausedForScreenLock {
            applyClamshellPreference()
        }
    }

    func activateOnLaunchIfNeeded() {
        guard AppFeature.keepAwake.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeAutoStart),
              !isActive else { return }
        activate(minutes: Defaults.sanitizedDefaultDuration(
            UserDefaults.standard.integer(forKey: DefaultsKey.defaultDuration)))
    }

    func extend(minutes: Int) {
        guard isActive, let current = endDate else { return }
        let newEnd = max(current, Date()).addingTimeInterval(TimeInterval(minutes) * 60)
        endDate = newEnd
        scheduleEnd(at: newEnd)
    }

    func deactivate(reason: EndReason) {
        let hadSession = isActive
        if reason == .quit {
            isTerminating = true
            clamshellSetupID = nil
            clamshellSetupInProgress = false
            stopAutomationMonitoring()
        }
        endTimer?.invalidate()
        endTimer = nil
        endDate = nil
        releaseAssertions()
        sessionTrigger = nil
        activeAutomationConditions.removeAll()
        isActive = false
        sessionPausedForScreenLock = false
        stopBatteryWatch()
        stopMouseJiggleTimer()
        // An enable can still be on the serialized native queue even though
        // its main-thread reply has not marked the session active yet.
        if clamshellNeedsRestore {
            disableClamshell(synchronous: reason == .quit)
        } else if reason == .quit, lidSleepAttemptsRemaining > 0 {
            sleepIfLidAlreadyClosed(attemptsLeft: lidSleepAttemptsRemaining, synchronous: true)
        }
        if hadSession, reason != .quit, reason != .manual {
            onSessionEnded?(reason)
        }
    }

    // MARK: - Automatic sessions

    private func syncAutomationMonitoring() {
        let available = AppFeature.keepAwake.isAvailable
        let selectedApps = Defaults.sanitizedBundleIdentifierList(
            UserDefaults.standard.stringArray(forKey: DefaultsKey.keepAwakeRunningAppBundleIDs) ?? [])
        if runningAppBundleIDs != selectedApps { runningAppBundleIDs = selectedApps }
        syncScreenLockMonitoring()
        let observeScreens = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeExternalDisplay)
        let observePower = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeConnectedToPower)
        let observeRunningApps = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeRunningApps)
            && !runningAppBundleIDs.isEmpty

        setScreenMonitoringEnabled(observeScreens)
        setPowerMonitoringEnabled(observePower)
        setRunningAppsMonitoringEnabled(observeRunningApps)
        evaluateAutomation()
    }

    private func syncScreenLockMonitoring() {
        let enabled = AppFeature.keepAwake.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakePauseWhenLocked)
        let center = DistributedNotificationCenter.default()

        if enabled {
            guard screenLockObservers.isEmpty else { return }
            screenLockObservers = [
                center.addObserver(forName: Self.screenLockNotification,
                                   object: nil, queue: .main) { [weak self] _ in
                    self?.screenLockStateDidChange(locked: true)
                },
                center.addObserver(forName: Self.screenUnlockNotification,
                                   object: nil, queue: .main) { [weak self] _ in
                    self?.screenLockStateDidChange(locked: false)
                },
            ]
            screenLocked = KeepAwakeAutomationSupport.isScreenLocked(
                sessionDictionary: CGSessionCopyCurrentDictionary() as? [String: Any]
            )
            syncSessionWithScreenLock()
        } else {
            guard !screenLockObservers.isEmpty else { return }
            for observer in screenLockObservers { center.removeObserver(observer) }
            screenLockObservers.removeAll()
            screenLocked = false
            syncSessionWithScreenLock()
        }
    }

    private func screenLockStateDidChange(locked: Bool) {
        guard screenLocked != locked else { return }
        screenLocked = locked
        syncSessionWithScreenLock()
        evaluateAutomation()
    }

    private func syncSessionWithScreenLock() {
        guard isActive else {
            sessionPausedForScreenLock = false
            return
        }
        let shouldPause = screenLocked
            && UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakePauseWhenLocked)
        guard shouldPause != sessionPausedForScreenLock else { return }

        if shouldPause {
            sessionPausedForScreenLock = true
            releaseAssertions()
            if clamshellNeedsRestore { disableClamshell(synchronous: false) }
            stopBatteryWatch()
            stopMouseJiggleTimer()
            return
        }

        sessionPausedForScreenLock = false
        if let endDate, endDate <= Date() {
            if !continueAutomaticallyAfterTimerIfNeeded() { deactivate(reason: .timer) }
            return
        }
        if sessionTrigger == .automation, !automationConditionsHold() {
            deactivate(reason: .manual)
            return
        }
        startBatteryWatch()
        guard isActive else { return }
        applyAssertions()
        syncMouseJiggleTimer()
        if clamshellPreferred { applyClamshellPreference() }
    }

    private func setScreenMonitoringEnabled(_ enabled: Bool) {
        if enabled {
            guard screenParametersObserver == nil else { return }
            screenParametersObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleAutomationEvaluation(after: 0.35)
            }
        } else if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
            lastExternalDisplayConnected = nil
        }
    }

    private func setPowerMonitoringEnabled(_ enabled: Bool) {
        if enabled {
            guard powerSourceRunLoopSource == nil else { return }
            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            powerSourceRunLoopSource = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                let manager = Unmanaged<KeepAwakeManager>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.scheduleAutomationEvaluation(after: 0.1)
                }
            }, context)?.takeRetainedValue()
            if let powerSourceRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
            }
        } else if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
            self.powerSourceRunLoopSource = nil
        }
    }

    private func setRunningAppsMonitoringEnabled(_ enabled: Bool) {
        let center = NSWorkspace.shared.notificationCenter
        if enabled {
            guard runningAppsObservers.isEmpty else { return }
            let handler: (Notification) -> Void = { [weak self] _ in
                self?.scheduleAutomationEvaluation(after: 0.1)
            }
            runningAppsObservers = [
                center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                   object: nil, queue: .main, using: handler),
                center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                   object: nil, queue: .main, using: handler),
            ]
        } else {
            guard !runningAppsObservers.isEmpty else { return }
            for observer in runningAppsObservers { center.removeObserver(observer) }
            runningAppsObservers.removeAll()
        }
    }

    private func scheduleAutomationEvaluation(after delay: TimeInterval) {
        automationEvaluationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.automationEvaluationWorkItem = nil
            self?.evaluateAutomation()
        }
        automationEvaluationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func stopAutomationMonitoring() {
        automationEvaluationWorkItem?.cancel()
        automationEvaluationWorkItem = nil
        setScreenMonitoringEnabled(false)
        setPowerMonitoringEnabled(false)
        setRunningAppsMonitoringEnabled(false)
        let center = DistributedNotificationCenter.default()
        for observer in screenLockObservers { center.removeObserver(observer) }
        screenLockObservers.removeAll()
        screenLocked = false
        sessionPausedForScreenLock = false
        activeAutomationConditions.removeAll()
    }

    private func evaluateAutomation() {
        guard recoveryCompleted, !isTerminating else { return }
        let matches = currentMatchingAutomationConditions()
        let enabled = currentEnabledAutomationConditions()
        let requireAll = automationRequiresAllConditions()
        let satisfied = KeepAwakeAutomationSupport.conditionsSatisfied(
            matching: matches, enabled: enabled, requireAll: requireAll)

        if automationSuppressedUntilConditionsClear {
            if !satisfied {
                automationSuppressedUntilConditionsClear = false
            }
            if sessionTrigger == .automation {
                deactivate(reason: .manual)
            }
            return
        }

        if screenLocked,
           UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakePauseWhenLocked) {
            if sessionTrigger == .automation { activeAutomationConditions = matches }
            return
        }

        if sessionTrigger == .automation {
            activeAutomationConditions = matches
        }
        let action = KeepAwakeAutomationSupport.action(
            featureAvailable: AppFeature.keepAwake.isAvailable,
            matchingConditions: matches,
            enabledConditions: enabled,
            requireAll: requireAll,
            sessionActive: isActive,
            automaticSessionActive: isActive && sessionTrigger == .automation
        )
        switch action {
        case .none:
            break
        case .activate:
            guard automaticSessionAllowedByBatteryProtection() else { return }
            activeAutomationConditions = matches
            activate(end: nil, trigger: .automation)
        case .deactivate:
            deactivate(reason: .manual)
        }
    }

    private func automationRequiresAllConditions() -> Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeAutomationRequireAll)
    }

    private func currentEnabledAutomationConditions() -> Set<KeepAwakeAutomationCondition> {
        KeepAwakeAutomationSupport.enabledConditions(
            externalDisplayEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeExternalDisplay),
            powerEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeConnectedToPower),
            runningAppsEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeRunningApps),
            hasSelectedApps: !runningAppBundleIDs.isEmpty
        )
    }

    /// Whether the automation currently asks for a session, in either match
    /// mode. Every caller that used to read "any condition matches" has to ask
    /// this instead: under All, a session that stops being wanted still has a
    /// non-empty matching set (issue #1587).
    private func automationConditionsHold() -> Bool {
        KeepAwakeAutomationSupport.conditionsSatisfied(
            matching: currentMatchingAutomationConditions(),
            enabled: currentEnabledAutomationConditions(),
            requireAll: automationRequiresAllConditions())
    }

    private func currentMatchingAutomationConditions() -> Set<KeepAwakeAutomationCondition> {
        let externalDisplayEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeExternalDisplay)
        let externalDisplayConnected: Bool
        if externalDisplayEnabled {
            if let current = Self.hasExternalDisplay() {
                lastExternalDisplayConnected = current
            }
            externalDisplayConnected = lastExternalDisplayConnected ?? false
        } else {
            externalDisplayConnected = false
        }

        let powerEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeConnectedToPower)
        let connectedToPower = powerEnabled
            && (SystemInfo.batterySnapshot().map { !$0.isOnBattery } ?? false)

        let runningAppsEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeRunningApps)
        let selectedAppsRunning: Bool
        if runningAppsEnabled, !runningAppBundleIDs.isEmpty {
            let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            selectedAppsRunning = KeepAwakeAutomationSupport.selectedAppsAreRunning(
                selectedBundleIDs: runningAppBundleIDs,
                runningBundleIDs: running
            )
        } else {
            selectedAppsRunning = false
        }

        return KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: externalDisplayEnabled,
            externalDisplayConnected: externalDisplayConnected,
            powerEnabled: powerEnabled,
            connectedToPower: connectedToPower,
            runningAppsEnabled: runningAppsEnabled,
            selectedAppsRunning: selectedAppsRunning
        )
    }

    private static func hasExternalDisplay() -> Bool? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return false }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        let builtInFlags = displays.prefix(Int(count)).map { CGDisplayIsBuiltin($0) != 0 }
        return KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: builtInFlags)
    }

    private func automaticSessionAllowedByBatteryProtection() -> Bool {
        let limit = Defaults.sanitizedBatteryLimit(
            UserDefaults.standard.integer(forKey: DefaultsKey.batteryLimit)
        )
        guard limit > 0,
              let battery = SystemInfo.batterySnapshot(),
              battery.isOnBattery else { return true }
        return battery.percent > limit
    }

    private func continueAutomaticallyAfterTimerIfNeeded() -> Bool {
        guard sessionTrigger == .manual,
              AppFeature.keepAwake.isAvailable,
              !automationSuppressedUntilConditionsClear,
              automaticSessionAllowedByBatteryProtection() else { return false }
        // The same full match the automation itself would need to start a
        // session: under All, a timed session must not be handed over on one
        // condition the automation would never have acted on (issue #1587).
        let matches = currentMatchingAutomationConditions()
        guard KeepAwakeAutomationSupport.conditionsSatisfied(
                matching: matches,
                enabled: currentEnabledAutomationConditions(),
                requireAll: automationRequiresAllConditions()) else { return false }
        activeAutomationConditions = matches
        activate(end: nil, trigger: .automation)
        return true
    }

    private func scheduleEnd(at date: Date) {
        endTimer?.invalidate()
        let t = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.continueAutomaticallyAfterTimerIfNeeded() {
                self.deactivate(reason: .timer)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        endTimer = t
    }

    // MARK: - IOKit assertions

    private func applyAssertions() {
        if !hasSystemAssertion {
            var id = IOPMAssertionID(0)
            let ok = IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Vorssaint: keep the Mac awake" as CFString,
                                                 &id)
            if ok == kIOReturnSuccess {
                systemAssertion = id
                hasSystemAssertion = true
            }
        }
        let allowDisplaySleep = UserDefaults.standard.bool(
            forKey: DefaultsKey.keepAwakeAllowDisplaySleep
        )
        if allowDisplaySleep, hasDisplayAssertion {
            IOPMAssertionRelease(displayAssertion)
            hasDisplayAssertion = false
        } else if !allowDisplaySleep, !hasDisplayAssertion {
            var id = IOPMAssertionID(0)
            let ok = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Vorssaint: keep the display on" as CFString,
                                                 &id)
            if ok == kIOReturnSuccess {
                displayAssertion = id
                hasDisplayAssertion = true
            }
        }
    }

    private func releaseAssertions() {
        if hasSystemAssertion {
            IOPMAssertionRelease(systemAssertion)
            hasSystemAssertion = false
        }
        if hasDisplayAssertion {
            IOPMAssertionRelease(displayAssertion)
            hasDisplayAssertion = false
        }
    }

    // MARK: - Closed lid (pmset disablesleep)

    private var clamshellNeedsRestore: Bool {
        clamshellActive || clamshellEnablePending || clamshellRestorePending
            || UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag)
    }

    private func applyClamshellPreference() {
        guard !isTerminating, !clamshellRestorePending else { return }
        // A fresh user-driven attempt (toggle on, or a new session) gets one
        // automatic setup retry again.
        clamshellSetupRetried = false
        if passwordlessClamshell {
            if isActive, !sessionPausedForScreenLock {
                enableClamshell()
            }
        } else {
            prepareClamshellPreference()
        }
    }

    private func prepareClamshellPreference() {
        guard !isTerminating, !clamshellRestorePending,
              clamshellPreferred, !clamshellSetupInProgress else { return }
        let requestID = UUID()
        clamshellSetupID = requestID
        clamshellSetupInProgress = true
        clamshellSetupFailed = false

        DispatchQueue.global(qos: .userInitiated).async {
            let configured = Sudoers.isConfigured()
            DispatchQueue.main.async {
                guard !self.isTerminating, self.clamshellSetupID == requestID else { return }
                if configured {
                    self.finishClamshellSetup(ok: true, requestID: requestID)
                } else {
                    Sudoers.install { ok in
                        DispatchQueue.main.async {
                            self.finishClamshellSetup(ok: ok, requestID: requestID)
                        }
                    }
                }
            }
        }
    }

    private func finishClamshellSetup(ok: Bool, requestID: UUID) {
        guard !isTerminating, clamshellSetupID == requestID else { return }
        clamshellSetupID = nil
        clamshellSetupInProgress = false
        passwordlessClamshell = ok

        guard ok else {
            markClamshellSetupFailed()
            return
        }

        if isActive, clamshellPreferred, !sessionPausedForScreenLock {
            enableClamshell()
        }
    }

    /// Turns the preference back off and surfaces the error, ending any retry
    /// loop. Setting `clamshellPreferred` false runs its `didSet`, which clears
    /// the in-progress/failed flags, so the failure flag is raised afterwards.
    private func markClamshellSetupFailed() {
        clamshellSetupInProgress = false
        guard clamshellPreferred else { return }
        clamshellPreferred = false
        clamshellSetupFailed = true
    }

    private func enableClamshell() {
        guard !isTerminating, isActive, clamshellPreferred, !sessionPausedForScreenLock,
              !clamshellActive, !clamshellEnablePending, !clamshellRestorePending else { return }
        clamshellOperationGeneration &+= 1
        let generation = clamshellOperationGeneration
        clamshellEnablePending = true
        // Persist before submitting the write: quitting or crashing before
        // its reply must not leave an unrecorded system-wide sleep override.
        UserDefaults.standard.set(true, forKey: DefaultsKey.sleepDisabledFlag)
        Sudoers.pmsetDisableSleep(true) { ok in
            DispatchQueue.main.async {
                guard !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
                self.clamshellEnablePending = false
                guard ok else {
                    // Repair the passwordless path once per deliberate attempt.
                    self.passwordlessClamshell = false
                    guard self.isActive, self.clamshellPreferred, !self.sessionPausedForScreenLock else { return }
                    if self.clamshellSetupRetried {
                        self.markClamshellSetupFailed()
                    } else {
                        self.clamshellSetupRetried = true
                        self.prepareClamshellPreference()
                    }
                    return
                }
                self.passwordlessClamshell = true
                if self.isActive, self.clamshellPreferred, !self.sessionPausedForScreenLock {
                    self.clamshellActive = true
                } else {
                    self.disableClamshell(synchronous: false)
                }
            }
        }
    }

    private func disableClamshell(synchronous: Bool) {
        // A new session waits for an outstanding restore, including its
        // authorization fallback, so an old off cannot overwrite a new on.
        guard synchronous || !clamshellRestorePending else { return }
        clamshellSetupID = nil
        clamshellSetupInProgress = false
        clamshellOperationGeneration &+= 1
        let generation = clamshellOperationGeneration
        lidSleepGeneration &+= 1
        lidSleepAttemptsRemaining = 0
        clamshellActive = false
        clamshellEnablePending = false
        clamshellRestorePending = true
        if synchronous {
            // This drains earlier native writes, including a pending enable.
            // Complete here: no main-queue callback survives process teardown.
            let ok = Sudoers.pmsetDisableSleep(false)
            finishClamshellRestore(ok: ok, usedPasswordless: true,
                                  generation: generation, synchronous: true)
        } else {
            Sudoers.pmsetDisableSleep(false) { ok in
                DispatchQueue.main.async {
                    guard !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
                    if ok {
                        self.finishClamshellRestore(ok: true, usedPasswordless: true,
                                                   generation: generation, synchronous: false)
                    } else {
                        // Never wait for a prompt on Sudoers' native queue:
                        // quit drains that queue while running on the main thread.
                        Sudoers.restoreSleepWithAuthorization(
                            prompt: L10n.shared.s.adminPromptClamshellOff,
                            shouldProceed: { !self.isTerminating && self.clamshellOperationGeneration == generation }
                        ) { restored in
                            DispatchQueue.main.async {
                                guard !self.isTerminating else { return }
                                self.finishClamshellRestore(ok: restored, usedPasswordless: false,
                                                           generation: generation, synchronous: false)
                            }
                        }
                    }
                }
            }
        }
    }

    private func finishClamshellRestore(ok: Bool, usedPasswordless: Bool,
                                        generation: Int, synchronous: Bool) {
        guard clamshellOperationGeneration == generation else { return }
        clamshellRestorePending = false
        if !usedPasswordless { passwordlessClamshell = false }
        // Keep the recovery marker on failure; never request sleep while the
        // system-wide override may still be set.
        guard ok else { return }
        UserDefaults.standard.set(false, forKey: DefaultsKey.sleepDisabledFlag)
        if !isTerminating, isActive, clamshellPreferred, !sessionPausedForScreenLock {
            enableClamshell()
        } else {
            sleepIfLidAlreadyClosed(synchronous: synchronous)
        }
    }

    /// Clearing `disablesleep` only clears a kernel flag. macOS evaluates the
    /// lid when it opens or closes, so a lid that shut during the session is
    /// never looked at again and the Mac stays awake until the battery runs
    /// out (#1729). Request the sleep that closing the lid would have caused.
    /// `pmset` returns before powerd has handed the cleared flag to the
    /// kernel, which refuses sleep until it has, so a refusal is retried.
    private func sleepIfLidAlreadyClosed(attemptsLeft: Int = 10, synchronous: Bool = false,
                                          generation: Int? = nil) {
        let generation = generation ?? lidSleepGeneration
        guard generation == lidSleepGeneration else { return }
        lidSleepAttemptsRemaining = 0
        guard !isActive || sessionPausedForScreenLock, !clamshellActive else { return }
        guard BrightnessService.lidClosed() == true, Self.lidSleepIsAllowed() else { return }
        let rootDomain = IOPMFindPowerManagement(kIOMainPortDefault)
        guard rootDomain != 0 else { return }
        let result = IOPMSleepSystem(rootDomain)
        IOServiceClose(rootDomain)
        guard result != kIOReturnSuccess, attemptsLeft > 1 else { return }
        if synchronous {
            // The existing bounded retry must finish before quit returns.
            // Re-read the lid and external protections after every refusal.
            Thread.sleep(forTimeInterval: 0.5)
            sleepIfLidAlreadyClosed(attemptsLeft: attemptsLeft - 1, synchronous: true,
                                    generation: generation)
        } else {
            lidSleepAttemptsRemaining = attemptsLeft - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.isTerminating else { return }
                self.sleepIfLidAlreadyClosed(attemptsLeft: attemptsLeft - 1, generation: generation)
            }
        }
    }

    private static func lidSleepIsAllowed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let allowsSleep = IORegistryEntryCreateCFProperty(
            service, kAppleClamshellCausesSleepKey as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
        guard allowsSleep == true else { return false }

        // The kernel does not republish its lid policy for every assertion
        // change. Read live protections as well, especially display hot-plug.
        var snapshot: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&snapshot)
        let values = snapshot?.takeRetainedValue()
        guard result == kIOReturnSuccess,
              let assertions = values as? [AnyHashable: [[String: Any]]]
        else { return false }
        return KeepAwakeAutomationSupport.lidSleepIsAllowed(
            systemAllowsSleep: allowsSleep, assertions: assertions.values.flatMap { $0 })
    }

    /// If the app died unexpectedly while sleep was disabled, restores normal
    /// behavior on the next launch.
    func recoverIfNeeded(completion: (() -> Void)? = nil) {
        guard !isTerminating else { return }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag) else {
            finishRecovery(completion)
            return
        }
        // A manual session may start while launch recovery is asking for
        // authorization. Its enable must wait until that older off is done.
        clamshellSetupID = nil
        clamshellSetupInProgress = false
        clamshellOperationGeneration &+= 1
        let generation = clamshellOperationGeneration
        clamshellRestorePending = true
        let finish: (Bool) -> Void = { ok in
            guard !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
            self.clamshellRestorePending = false
            if ok { UserDefaults.standard.set(false, forKey: DefaultsKey.sleepDisabledFlag) }
            self.finishRecovery(completion)
            if ok, self.isActive, self.clamshellPreferred, !self.sessionPausedForScreenLock {
                self.enableClamshell()
            }
        }
        DispatchQueue.global(qos: .utility).async {
            let report = Shell.run("/usr/bin/pmset", ["-g"])
            let stillDisabled = SudoersSupport.sleepDisabled(inPmsetOutput: report.output)
            // An unreadable report is not evidence that a persisted override
            // has disappeared. Keep its recovery marker unless an off succeeds.
            if report.status == 0, !stillDisabled {
                DispatchQueue.main.async { finish(true) }
            } else if Sudoers.pmsetDisableSleep(false) {
                DispatchQueue.main.async { finish(true) }
            } else {
                DispatchQueue.main.async {
                    guard !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
                    Sudoers.restoreSleepWithAuthorization(
                        prompt: L10n.shared.s.adminPromptRecover,
                        shouldProceed: { !self.isTerminating && self.clamshellOperationGeneration == generation }
                    ) { ok in
                        DispatchQueue.main.async { finish(ok) }
                    }
                }
            }
        }
    }

    private func finishRecovery(_ completion: (() -> Void)?) {
        guard !isTerminating else { return }
        recoveryCompleted = true
        completion?()
        syncWithPreferences()
    }

    // MARK: - Battery protection

    private func startBatteryWatch() {
        stopBatteryWatch()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkBattery()
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        batteryTimer = t
        checkBattery()
    }

    private func stopBatteryWatch() {
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    private func checkBattery() {
        let limit = Defaults.sanitizedBatteryLimit(UserDefaults.standard.integer(forKey: DefaultsKey.batteryLimit))
        guard limit > 0, isActive else { return }
        guard let battery = SystemInfo.batterySnapshot(),
              battery.isOnBattery,
              battery.percent <= limit else { return }
        deactivate(reason: .battery)
    }

    // MARK: - Optional pointer activity

    private func syncMouseJiggleTimer() {
        guard isActive,
              !sessionPausedForScreenLock,
              UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeMouseJiggleEnabled)
        else {
            stopMouseJiggleTimer()
            return
        }

        let minutes = Defaults.sanitizedKeepAwakeMouseJiggleInterval(
            UserDefaults.standard.integer(forKey: DefaultsKey.keepAwakeMouseJiggleInterval)
        )
        let interval = TimeInterval(minutes * 60)
        if mouseJiggleTimer?.timeInterval == interval { return }

        stopMouseJiggleTimer()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.jiggleMousePointer()
        }
        timer.tolerance = min(10, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        mouseJiggleTimer = timer
    }

    private func stopMouseJiggleTimer() {
        mouseJiggleTimer?.invalidate()
        mouseJiggleTimer = nil
        pendingMouseReturn?.cancel()
        pendingMouseReturn = nil
    }

    private func jiggleMousePointer() {
        guard isActive,
              UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeMouseJiggleEnabled),
              let original = Self.currentMouseLocation(),
              let target = Self.mouseJiggleTarget(from: original)
        else {
            syncMouseJiggleTimer()
            return
        }

        guard Self.postMouseMove(to: target) else { return }

        pendingMouseReturn?.cancel()
        let returnMove = DispatchWorkItem { [weak self] in
            self?.pendingMouseReturn = nil
            guard let current = Self.currentMouseLocation() else { return }
            guard abs(current.x - target.x) <= 2,
                  abs(current.y - target.y) <= 2 else { return }
            _ = Self.postMouseMove(to: original)
        }
        pendingMouseReturn = returnMove
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: returnMove)
    }

    private static func currentMouseLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private static func mouseJiggleTarget(from original: CGPoint) -> CGPoint? {
        guard let bounds = displayBounds(containing: original) else { return nil }
        let safeFrame = bounds.insetBy(dx: 2, dy: 2)
        let x = min(max(original.x, safeFrame.minX), safeFrame.maxX)
        let y = min(max(original.y, safeFrame.minY), safeFrame.maxY)

        if x + 1 <= safeFrame.maxX {
            return CGPoint(x: x + 1, y: y)
        }
        if x - 1 >= safeFrame.minX {
            return CGPoint(x: x - 1, y: y)
        }
        if y + 1 <= safeFrame.maxY {
            return CGPoint(x: x, y: y + 1)
        }
        if y - 1 >= safeFrame.minY {
            return CGPoint(x: x, y: y - 1)
        }
        return nil
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return nil
        }

        for display in displays.prefix(Int(count)) {
            let bounds = CGDisplayBounds(display)
            if point.x >= bounds.minX, point.x <= bounds.maxX,
               point.y >= bounds.minY, point.y <= bounds.maxY {
                return bounds
            }
        }
        return nil
    }

    private static func postMouseMove(to point: CGPoint) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(mouseEventSource: source,
                                  mouseType: .mouseMoved,
                                  mouseCursorPosition: point,
                                  mouseButton: .left) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
}
