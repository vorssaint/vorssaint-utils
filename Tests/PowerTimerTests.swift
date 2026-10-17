// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum PowerTimerTests {
    private final class Fixture {
        var now = Date(timeIntervalSince1970: 1_000_000)
        var uptime: TimeInterval = 100
        var available = true
        var sleepDisabled = false
        var assertionAllowed = true
        var acquired = 0
        var released = 0
        var actions: [PowerTimerAction] = []
        var pendingConsent: ((Bool) -> Void)?
        var pendingExecution: ((Bool) -> Void)?
        func make() -> PowerTimerService {
            PowerTimerService(available: { self.available }, sleepDisabled: { self.sleepDisabled },
                acquireAssertion: { self.acquired += 1; return self.assertionAllowed },
                releaseAssertion: { self.released += 1 },
                authorize: { self.pendingConsent = $0 },
                execute: { self.actions.append($0); self.pendingExecution = $1 },
                now: { self.now }, uptime: { self.uptime })
        }
        func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds); uptime += seconds }
    }

    static func run(_ suite: TestSuite) {
        for invalid in ["", "abc", "1.5", "0", "1441", "999999999999999999999999"] {
            suite.expect(PowerTimerSession.minutes(from: invalid) == nil,
                         "invalid text cannot silently reuse a previous duration: \(invalid)")
        }
        suite.expect(PowerTimerSession.minutes(from: " 30 ") == 30
                     && PowerTimerSession.minutes(from: "1440") == 1440,
                     "whole-minute input accepts trimming and the upper bound")
        let f = Fixture(), service = f.make()
        service.start(minutes: 1, action: .sleep)
        suite.expect(service.session?.action == .sleep && f.acquired == 1 && f.pendingConsent == nil,
                     "sleep arms without Automation and holds an idle-sleep assertion")
        service.start(minutes: 2, action: .shutDown)
        suite.expect(service.session?.action == .sleep && f.pendingConsent == nil,
                     "a second start cannot replace an active timer")
        f.advance(59); service.checkDeadline()
        suite.expect(f.actions.isEmpty && service.remaining() == 1, "a timer never executes early")
        f.now.addTimeInterval(3600)
        suite.expect(service.remaining() == 1 && service.scheduledDate() == f.now.addingTimeInterval(1),
                     "a wall-clock jump does not shorten a duration or leave its displayed date stale")
        f.advance(1); service.checkDeadline(); service.checkDeadline()
        suite.expect(f.actions == [.sleep] && f.released == 1 && service.session == nil && service.executing,
                     "expiry releases the assertion and consumes the session exactly once")
        f.pendingExecution?(false)
        suite.expect(service.failure == .execution && !service.executing,
                     "failed power requests are visible and never automatically retried")
        service.checkDeadline()
        suite.expect(f.actions.count == 1, "execution failures never repeat a power request")

        for minutes in [0, -1, 1441, Int.max] {
            service.cancel(); service.start(minutes: minutes, action: .sleep)
            suite.expect(service.session == nil && service.failure == .invalidTime,
                         "invalid duration \(minutes) cannot arm a power command")
        }
        service.cancel(); service.start(minutes: 1440, action: .sleep)
        suite.expect(service.remaining() == 86400, "a 24-hour duration is allowed")
        service.cancel()
        suite.expect(f.released == 2 && service.session == nil, "cancel releases an armed timer's assertion")
        f.advance(86400); service.checkDeadline()
        suite.expect(f.actions.count == 1, "cancelled timers stay cancelled after their deadline")

        for offset: TimeInterval in [0, -1, 86401, .infinity, .nan] {
            service.start(at: f.now.addingTimeInterval(offset), action: .sleep)
            suite.expect(service.failure == .invalidTime && service.session == nil,
                         "past, invalid and overlong clock schedules cannot arm")
        }
        service.start(at: f.now.addingTimeInterval(120), action: .sleep)
        f.now.addTimeInterval(-60)
        suite.expect(service.remaining() == 180, "clock schedules follow a backward clock adjustment")
        f.now.addTimeInterval(181); service.checkDeadline()
        suite.expect(f.actions.count == 2, "clock schedules execute after a forward adjustment crosses the deadline")
        f.pendingExecution?(true)

        let auth = Fixture(), waiting = auth.make()
        waiting.start(minutes: 1, action: .shutDown)
        suite.expect(waiting.preparing && waiting.session == nil && auth.acquired == 0,
                     "shutdown waits for consent before arming")
        waiting.cancel(); auth.pendingConsent?(true)
        suite.expect(waiting.session == nil && auth.acquired == 0,
                     "late consent cannot revive a cancelled timer")
        waiting.start(minutes: 1, action: .shutDown); auth.pendingConsent?(false)
        suite.expect(waiting.failure == .permission && waiting.session == nil,
                     "denied Automation never schedules a shutdown")
        waiting.start(minutes: 1, action: .shutDown)
        auth.advance(61); auth.pendingConsent?(true)
        suite.expect(waiting.failure == .invalidTime && auth.actions.isEmpty,
                     "a deadline passed during consent never triggers a surprise shutdown")
        waiting.start(minutes: 1, action: .shutDown)
        auth.available = false; auth.pendingConsent?(true)
        suite.expect(waiting.session == nil && auth.acquired == 0,
                     "feature removal while consent is pending prevents arming")
        auth.available = true
        waiting.start(minutes: 1, action: .shutDown); auth.pendingConsent?(true)
        suite.expect(waiting.session?.action == .shutDown, "authorized shutdown arms normally")
        auth.advance(60); waiting.checkDeadline(); auth.pendingExecution?(false)
        suite.expect(auth.actions == [.shutDown] && waiting.failure == .execution,
                     "an application refusing shutdown reports failure without escalation")

        let gate = Fixture(), gated = gate.make()
        gate.sleepDisabled = true; gated.start(minutes: 1, action: .sleep)
        suite.expect(gated.failure == .keepAwake && gate.acquired == 0,
                     "closed-lid sleep prevention refuses an incompatible timer")
        gate.sleepDisabled = false; gate.assertionAllowed = false
        gated.start(minutes: 1, action: .sleep)
        suite.expect(gated.failure == .execution && gated.session == nil && gate.released == 0,
                     "failed assertion acquisition does not pretend a timer is armed")
        gate.assertionAllowed = true; gated.start(minutes: 1, action: .sleep)
        gate.sleepDisabled = true; gate.advance(60); gated.checkDeadline()
        suite.expect(gated.failure == .keepAwake && gate.actions.isEmpty && gate.released == 1,
                     "closed-lid mode enabled after arming is rechecked before execution")
        gate.sleepDisabled = false; gated.start(minutes: 1, action: .sleep)
        gate.available = false; gated.syncWithFeatures(); gate.advance(60); gated.checkDeadline()
        suite.expect(gated.session == nil && gate.actions.isEmpty && gate.released == 2,
                     "uninstall immediately cancels the timer and releases resources")

        let life = Fixture(), live = life.make()
        live.start(minutes: 1, action: .shutDown)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        life.pendingConsent?(true)
        suite.expect(live.session == nil && !live.preparing && life.acquired == 0,
                     "sleep while permission is pending also cancels the timer")
        live.start(minutes: 1, action: .sleep)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        suite.expect(live.session == nil && life.released == 1, "manual sleep cancels an armed timer")
        live.start(minutes: 1, action: .sleep)
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        suite.expect(live.session == nil && life.released == 2, "quitting cancels an armed timer")

        suite.expect(!AppFeature.powerTimer.installedByDefault && AppFeature.powerTimer.enabledKeys.isEmpty
                     && AppFeature.powerTimer.group == .energyDisplay,
                     "the on-demand timer is opt-in and never arms on install")
        suite.expect(AppFeature.powerTimer.settingsDestination == FeatureSettingsDestination(.energy, sectionAnchor: .powerTimer)
                     && MenuPanelSectionGateContract.PanelSectionID.powerTimer.featureGate == [.powerTimer],
                     "the timer has independent Energy and panel destinations")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.powerTimerMinutes] as? Int == 30,
                     "the duration preference has a registered backup-compatible default")
    }
}
