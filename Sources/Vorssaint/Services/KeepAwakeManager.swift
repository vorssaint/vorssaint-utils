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
            if clamshellPreferred {
                applyClamshellPreference()
            } else if clamshellActive {
                clamshellSetupInProgress = false
                disableClamshell(synchronous: false)
            } else {
                clamshellSetupInProgress = false
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
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var automationEvaluationWorkItem: DispatchWorkItem?
    private var lastExternalDisplayConnected: Bool?
    private var automationSuppressedUntilConditionsClear = false
    private var recoveryCompleted = false
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
        DispatchQueue.global(qos: .utility).async {
            let configured = Sudoers.isConfigured()
            DispatchQueue.main.async {
                self.passwordlessClamshell = configured
            }
        }
    }

    // MARK: - Session

    func toggle() {
        if isActive {
            if sessionTrigger == .automation || !currentMatchingAutomationConditions().isEmpty {
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
        syncMouseJiggleTimer()
        syncAutomationMonitoring()
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
        activate(minutes: minutes, trigger: .manual)
    }

    private func activate(minutes: Int, trigger: SessionTrigger) {
        guard AppFeature.keepAwake.isAvailable else { return }
        let minutes = Defaults.sanitizedDefaultDuration(minutes)
        endTimer?.invalidate()
        endTimer = nil
        applyAssertions()
        sessionTrigger = trigger
        if trigger == .manual {
            activeAutomationConditions.removeAll()
        }
        isActive = true
        if minutes > 0 {
            let end = Date().addingTimeInterval(TimeInterval(minutes) * 60)
            endDate = end
            scheduleEnd(at: end)
        } else {
            endDate = nil
        }
        startBatteryWatch()
        syncMouseJiggleTimer()
        if clamshellPreferred {
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
            stopAutomationMonitoring()
        }
        endTimer?.invalidate()
        endTimer = nil
        endDate = nil
        releaseAssertions()
        if clamshellActive {
            disableClamshell(synchronous: reason == .quit)
        }
        sessionTrigger = nil
        activeAutomationConditions.removeAll()
        isActive = false
        stopBatteryWatch()
        stopMouseJiggleTimer()
        if hadSession, reason != .quit, reason != .manual {
            onSessionEnded?(reason)
        }
    }

    // MARK: - Automatic sessions

    private func syncAutomationMonitoring() {
        let available = AppFeature.keepAwake.isAvailable
        let observeScreens = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeExternalDisplay)
        let observePower = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.keepAwakeConnectedToPower)

        setScreenMonitoringEnabled(observeScreens)
        setPowerMonitoringEnabled(observePower)
        evaluateAutomation()
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
        activeAutomationConditions.removeAll()
    }

    private func evaluateAutomation() {
        guard recoveryCompleted else { return }
        let matches = currentMatchingAutomationConditions()

        if automationSuppressedUntilConditionsClear {
            if matches.isEmpty {
                automationSuppressedUntilConditionsClear = false
            }
            if sessionTrigger == .automation {
                deactivate(reason: .manual)
            }
            return
        }

        if sessionTrigger == .automation {
            activeAutomationConditions = matches
        }
        let action = KeepAwakeAutomationSupport.action(
            featureAvailable: AppFeature.keepAwake.isAvailable,
            matchingConditions: matches,
            sessionActive: isActive,
            automaticSessionActive: isActive && sessionTrigger == .automation
        )
        switch action {
        case .none:
            break
        case .activate:
            guard automaticSessionAllowedByBatteryProtection() else { return }
            activeAutomationConditions = matches
            activate(minutes: 0, trigger: .automation)
        case .deactivate:
            deactivate(reason: .manual)
        }
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

        return KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: externalDisplayEnabled,
            externalDisplayConnected: externalDisplayConnected,
            powerEnabled: powerEnabled,
            connectedToPower: connectedToPower
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
        let matches = currentMatchingAutomationConditions()
        guard !matches.isEmpty else { return false }
        activeAutomationConditions = matches
        activate(minutes: 0, trigger: .automation)
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
        // The display always stays on during a session; a Mac kept awake with
        // a dark screen reads as "not working" and invites a lid close.
        if !hasDisplayAssertion {
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

    private func applyClamshellPreference() {
        // A fresh user-driven attempt (toggle on, or a new session) gets one
        // automatic setup retry again.
        clamshellSetupRetried = false
        if passwordlessClamshell {
            if isActive {
                enableClamshell()
            }
        } else {
            prepareClamshellPreference()
        }
    }

    private func prepareClamshellPreference() {
        guard clamshellPreferred, !clamshellSetupInProgress else { return }
        clamshellSetupInProgress = true
        clamshellSetupFailed = false

        DispatchQueue.global(qos: .userInitiated).async {
            if Sudoers.isConfigured() {
                DispatchQueue.main.async {
                    self.finishClamshellSetup(ok: true)
                }
                return
            }

            Sudoers.install { ok in
                DispatchQueue.main.async {
                    self.finishClamshellSetup(ok: ok)
                }
            }
        }
    }

    private func finishClamshellSetup(ok: Bool) {
        clamshellSetupInProgress = false
        passwordlessClamshell = ok

        guard ok else {
            markClamshellSetupFailed()
            return
        }

        if isActive, clamshellPreferred {
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
        guard !clamshellActive else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Sudoers.pmsetDisableSleep(true)
            DispatchQueue.main.async {
                guard ok else {
                    // The rule was reported as working but the real call failed.
                    // Never fall back to a password prompt here: prompting per
                    // toggle is exactly the grind of issue #269. Repair the rule
                    // once through the regular setup; if that does not restore
                    // the passwordless path, stop and report the failure.
                    self.passwordlessClamshell = false
                    guard self.clamshellPreferred else { return }
                    if self.clamshellSetupRetried {
                        self.markClamshellSetupFailed()
                    } else {
                        self.clamshellSetupRetried = true
                        self.prepareClamshellPreference()
                    }
                    return
                }
                self.passwordlessClamshell = true
                UserDefaults.standard.set(true, forKey: DefaultsKey.sleepDisabledFlag)
                if self.isActive, self.clamshellPreferred {
                    self.clamshellActive = true
                } else {
                    // The session ended (or the preference flipped) while the
                    // setup was still running — restore normal sleep.
                    self.disableClamshell(synchronous: false)
                }
            }
        }
    }

    private func disableClamshell(synchronous: Bool) {
        clamshellActive = false
        let revert = { [synchronous] in
            let usedPasswordless = Sudoers.pmsetDisableSleep(false)
            // Quitting is the one moment where asking for a password is not
            // an option: the dialog would hold the app open until somebody
            // answers it, and nobody is watching an app that is closing. The
            // next start repairs a revert that was missed.
            let ok = usedPasswordless
                || (!synchronous
                    && AdminShell.runSync("pmset disablesleep 0",
                                          prompt: L10n.shared.s.adminPromptClamshellOff))
            if ok {
                DispatchQueue.main.async {
                    if !usedPasswordless {
                        self.passwordlessClamshell = false
                    }
                    UserDefaults.standard.set(false, forKey: DefaultsKey.sleepDisabledFlag)
                }
            }
        }
        if synchronous {
            revert()
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: revert)
        }
    }

    /// If the app died unexpectedly while sleep was disabled, restores normal
    /// behavior on the next launch.
    func recoverIfNeeded(completion: (() -> Void)? = nil) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag) else {
            finishRecovery(completion)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let out = Shell.run("/usr/bin/pmset", ["-g"]).output
            let stillDisabled = SudoersSupport.sleepDisabled(inPmsetOutput: out)
            if stillDisabled, Sudoers.pmsetDisableSleep(false) {
                // Silent recovery through the password-free path.
                DispatchQueue.main.async {
                    UserDefaults.standard.set(false, forKey: DefaultsKey.sleepDisabledFlag)
                    self.finishRecovery(completion)
                }
                return
            }
            DispatchQueue.main.async {
                if stillDisabled {
                    AdminShell.run("pmset disablesleep 0", prompt: L10n.shared.s.adminPromptRecover) { ok in
                        DispatchQueue.main.async {
                            if ok {
                                UserDefaults.standard.set(false, forKey: DefaultsKey.sleepDisabledFlag)
                            }
                            self.finishRecovery(completion)
                        }
                    }
                } else {
                    UserDefaults.standard.set(false, forKey: DefaultsKey.sleepDisabledFlag)
                    self.finishRecovery(completion)
                }
            }
        }
    }

    private func finishRecovery(_ completion: (() -> Void)?) {
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
