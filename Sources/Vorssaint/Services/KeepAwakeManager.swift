// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.pwr_mgt

/// Core of the energy feature: manages "keep awake" sessions through IOKit power
/// assertions, the closed-lid mode (pmset disablesleep, administrator password)
/// and the battery protection watchdog.
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()

    enum EndReason { case manual, timer, battery, quit }

    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date? // nil = indefinite
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
    /// Guards the closed-lid setup against an infinite retry loop: if `pmset
    /// disablesleep` keeps failing while the sudoers rule still checks out as
    /// installed, re-preparing would bounce here forever (and flicker the
    /// caption). One automatic re-acquire per user attempt, then we give up.
    private var clamshellSetupRetried = false

    private init() {
        clamshellPreferred = UserDefaults.standard.bool(forKey: DefaultsKey.clamshellPreferred)
        refreshPasswordlessStatus()
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
            deactivate(reason: .manual)
        } else {
            activate(minutes: Defaults.sanitizedDefaultDuration(UserDefaults.standard.integer(forKey: DefaultsKey.defaultDuration)))
        }
    }

    /// `minutes <= 0` activates indefinitely.
    func activate(minutes: Int) {
        let minutes = Defaults.sanitizedDefaultDuration(minutes)
        endTimer?.invalidate()
        endTimer = nil
        applyAssertions()
        isActive = true
        if minutes > 0 {
            let end = Date().addingTimeInterval(TimeInterval(minutes) * 60)
            endDate = end
            scheduleEnd(at: end)
        } else {
            endDate = nil
        }
        startBatteryWatch()
        if clamshellPreferred {
            applyClamshellPreference()
        }
    }

    func extend(minutes: Int) {
        guard isActive, let current = endDate else { return }
        let newEnd = max(current, Date()).addingTimeInterval(TimeInterval(minutes) * 60)
        endDate = newEnd
        scheduleEnd(at: newEnd)
    }

    func deactivate(reason: EndReason) {
        let hadSession = isActive
        endTimer?.invalidate()
        endTimer = nil
        endDate = nil
        releaseAssertions()
        if clamshellActive {
            disableClamshell(synchronous: reason == .quit)
        }
        isActive = false
        stopBatteryWatch()
        if hadSession, reason != .quit, reason != .manual {
            onSessionEnded?(reason)
        }
    }

    private func scheduleEnd(at date: Date) {
        endTimer?.invalidate()
        let t = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            self?.deactivate(reason: .timer)
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
                    self.passwordlessClamshell = false
                    guard self.clamshellPreferred else { return }
                    if self.clamshellSetupRetried {
                        // Already re-acquired the rule once and pmset still won't
                        // disable sleep: the rule lists as installed but the command
                        // fails on this Mac. Re-preparing again only loops (and
                        // flickers the caption), so stop and report the failure.
                        self.markClamshellSetupFailed()
                    } else {
                        self.clamshellSetupRetried = true
                        self.prepareClamshellPreference()
                    }
                    return
                }
                UserDefaults.standard.set(true, forKey: DefaultsKey.sleepDisabledFlag)
                if self.isActive, self.clamshellPreferred {
                    self.clamshellActive = true
                } else {
                    // The session ended (or the preference flipped) while the
                    // password prompt was up — restore normal sleep.
                    self.disableClamshell(synchronous: false)
                }
            }
        }
    }

    private func disableClamshell(synchronous: Bool) {
        clamshellActive = false
        let revert = {
            let ok = Sudoers.pmsetDisableSleep(false)
                || AdminShell.runSync("pmset disablesleep 0", prompt: L10n.shared.s.adminPromptClamshellOff)
            if ok {
                DispatchQueue.main.async {
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
    func recoverIfNeeded() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag) else { return }
        DispatchQueue.global(qos: .utility).async {
            let out = Shell.run("/usr/bin/pmset", ["-g"]).output
            let stillDisabled = out.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
            if stillDisabled, Sudoers.pmsetDisableSleep(false) {
                // Silent recovery through the password-free path.
                DispatchQueue.main.async {
                    UserDefaults.standard.set(false, forKey: DefaultsKey.sleepDisabledFlag)
                }
                return
            }
            DispatchQueue.main.async {
                if stillDisabled {
                    AdminShell.run("pmset disablesleep 0", prompt: L10n.shared.s.adminPromptRecover) { ok in
                        if ok {
                            DispatchQueue.main.async {
                                UserDefaults.standard.set(false, forKey: DefaultsKey.sleepDisabledFlag)
                            }
                        }
                    }
                } else {
                    UserDefaults.standard.set(false, forKey: DefaultsKey.sleepDisabledFlag)
                }
            }
        }
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
}
