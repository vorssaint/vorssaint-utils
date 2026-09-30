// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Resuming fan control after a restart or wake runs the production decisions
/// against doubles: nothing here can reach the helper or the fans.
enum FanControlResumeContract {
    enum Environment {
        static var available = true
    }
    enum AppFeature {
        case fanControl
        var isAvailable: Bool { Environment.available }
    }
    enum UserDefaults {
        static let standard = Store()
        final class Store {
            var values: [String: Any] = [:]
            func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
            func string(forKey key: String) -> String? { values[key] as? String }
            func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
            func set(_ value: Any?, forKey key: String) { values[key] = value }
            func removeObject(forKey key: String) { values[key] = nil }
        }
    }
    final class Invalidating {
        var invalidated = false
        func invalidate() { invalidated = true }
    }
    class Fixture {
        enum AccessState { case notRegistered, requiresApproval, enabled, unavailable }
        static let shared = Service()
        static var helperVersion = "bundled"
        var accessState = AccessState.enabled
        var snapshot = FanControlSnapshot.empty
        var panelIsVisible = false
        var timer: Invalidating?
        var connection: Invalidating?
        var observing = true
        var timedManualEnd: Date?
        var applied: [FanControlConfiguration] = []
        var appliedEnds: [Date?] = []
        var events: [String] = []
        func refreshAccessState() {}
        func applyConfiguration(_ configuration: FanControlConfiguration, endsAt: Date?) {
            applied.append(configuration)
            appliedEnds.append(endsAt)
        }
        func restoreAutomatic() { events.append("restore") }
        func restoreAutomatic(supersedingCurrentRequest: Bool) { events.append("restore superseding") }
        func restoreThenUnregister() { events.append("unregister") }
        func refresh() { events.append("refresh") }
        func stopObservingSystemState() { observing = false }
    }

    static func run(_ suite: TestSuite) {
        let service = Service.shared
        let defaults = UserDefaults.standard
        let manual = FanControlConfiguration.manual(level: 100)
        func reset(resume: Bool = true, stored: FanControlConfiguration? = manual,
                   recovery: Bool = false) {
            Environment.available = true
            defaults.values = [:]
            defaults.values[DefaultsKey.fanControlResume] = resume
            defaults.values[DefaultsKey.fanControlRecoveryNeeded] = recovery
            defaults.values[DefaultsKey.fanControlMode] = FanControlMode.manual.rawValue
            if let stored {
                defaults.values[DefaultsKey.fanControlResumeConfiguration] =
                    FanControlConfiguration.encodeResume(stored)
            }
            service.accessState = .enabled
            service.snapshot = .empty
            service.panelIsVisible = false
            service.timer = Invalidating()
            service.connection = Invalidating()
            service.observing = true
            service.timedManualEnd = nil
            service.applied = []
            service.appliedEnds = []
            service.events = []
        }
        var storedResume: String? { defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) }

        reset(resume: false, recovery: true)
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.events == ["restore"],
                     "without resume, a launch after an interrupted session only returns the fans to the system")
        reset(recovery: true)
        Service.recoverIfNeeded()
        suite.expect(service.applied == [manual] && service.events.isEmpty,
                     "with resume on, a launch re-applies the kept control instead of restoring first")
        reset()
        service.accessState = .requiresApproval
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.events.isEmpty,
                     "a resume never asks for helper approval on its own")
        reset()
        Environment.available = false
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty, "a feature removed from the hub resumes nothing")
        reset()
        defaults.values[DefaultsKey.fanControlResumeConfiguration] =
            #"{"curves":[],"manualLevel":100,"mode":"system"}"#
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty, "a damaged or System value is never re-applied")
        reset()
        defaults.values[DefaultsKey.fanControlMode] = FanControlMode.system.rawValue
        Service.recoverIfNeeded()
        service.workspaceDidWake()
        service.stopIdleWorkIfPossible()
        suite.expect(service.applied.isEmpty && !service.observing,
                     "picking System in the card, with the fans already back there, is never undone by a resume")
        reset()
        defaults.values[DefaultsKey.fanControlHelperVersion] = "registered before the update"
        Service.recoverIfNeeded()
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty,
                     "a helper replaced by an update is registered anew before any resume holds the fans")
        reset()
        defaults.values[DefaultsKey.fanControlHelperVersion] = Service.helperVersion
        Service.recoverIfNeeded()
        suite.expect(service.applied == [manual], "the registered helper resumes as before")

        reset(resume: false, stored: nil)
        service.rememberForResume(manual)
        suite.expect(storedResume == nil, "applied control is not kept while resume is off")
        reset(stored: nil)
        service.rememberForResume(.manual(level: 60))
        suite.expect(FanControlConfiguration.decodeResume(storedResume ?? "") == .manual(level: 60),
                     "applied control is kept while resume is on")

        reset(stored: nil)
        service.snapshot.isCooling = true
        service.snapshot.configuration = manual
        service.resumePreferenceDidChange()
        suite.expect(FanControlConfiguration.decodeResume(storedResume ?? "") == manual,
                     "turning resume on keeps the control already running")
        defaults.values[DefaultsKey.fanControlResume] = false
        service.resumePreferenceDidChange()
        suite.expect(storedResume == nil, "turning resume off forgets the kept control")
        reset(stored: nil)
        service.resumePreferenceDidChange()
        suite.expect(storedResume == nil, "turning resume on with the fans on System keeps nothing")
        reset()
        service.resumePreferenceDidChange()
        suite.expect(storedResume == nil,
                     "turning resume on with the fans on System drops an older kept control, such as a restored one")

        reset()
        service.returnToSystem()
        suite.expect(storedResume == nil && service.events == ["restore"],
                     "returning to System forgets the kept control and restores the fans")

        reset()
        service.stopIdleWorkIfPossible()
        suite.expect(service.timer == nil && service.connection == nil && service.observing,
                     "idle work stops while a pending resume keeps watching for the next wake")
        reset(resume: false)
        service.stopIdleWorkIfPossible()
        suite.expect(!service.observing, "without a pending resume the sleep observers stop too")

        reset()
        service.workspaceDidWake()
        suite.expect(service.applied == [manual] && service.events.isEmpty,
                     "waking re-applies the kept control")
        reset(resume: false, recovery: true)
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.events == ["restore superseding"],
                     "without resume, waking still returns an interrupted session to the system")
        reset(resume: false)
        service.panelIsVisible = true
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.events == ["refresh"],
                     "without resume, waking only refreshes a visible panel")

        reset()
        Environment.available = false
        service.syncWithPreferences()
        suite.expect(storedResume == nil && service.events == ["unregister"],
                     "removing the feature forgets the kept control before unregistering the helper")
        runTimedManual(suite)
        reset()
    }

    /// A timed manual speed ends through the ordinary return to System, and
    /// nothing (a wake, a launch, a clock moved back) may keep it running.
    static func runTimedManual(_ suite: TestSuite) {
        let service = Service.shared
        let defaults = UserDefaults.standard
        let manual = FanControlConfiguration.manual(level: 100)
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func reset(resume: Bool = true, end: Date?, recovery: Bool = false) {
            Environment.available = true
            defaults.values = [:]
            defaults.values[DefaultsKey.fanControlResume] = resume
            defaults.values[DefaultsKey.fanControlRecoveryNeeded] = recovery
            defaults.values[DefaultsKey.fanControlMode] = FanControlMode.manual.rawValue
            defaults.values[DefaultsKey.fanControlResumeConfiguration] =
                FanControlConfiguration.encodeResume(manual)
            service.accessState = .enabled
            service.snapshot = .empty
            service.panelIsVisible = false
            service.timer = Invalidating()
            service.connection = Invalidating()
            service.observing = true
            service.applied = []
            service.appliedEnds = []
            service.events = []
            service.timedManualEnd = nil
            service.rememberTimedManualEnd(end)
        }
        var storedResume: String? { defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) }
        var storedEnd: Double { defaults.double(forKey: DefaultsKey.fanControlManualEnd) }

        let tenMinutes = FanControlManualDuration.end(minutes: 10, from: now)
        suite.expect(tenMinutes == now.addingTimeInterval(600)
                && FanControlManualDuration.end(minutes: 60, from: now) == now.addingTimeInterval(3_600)
                && FanControlManualDuration.end(minutes: FanControlManualDuration.untilChanged,
                                                from: now) == nil,
               "a timed manual speed ends after the picked minutes; until I change it has no end")
        suite.expect(FanControlManualDuration.end(minutes: 7, from: now) == nil
                && FanControlManualDuration.end(minutes: -5, from: now) == nil
                && FanControlManualDuration.validated(7) == FanControlManualDuration.untilChanged
                && FanControlManualDuration.validated(30) == 30,
               "an unknown duration, such as one restored from a backup, keeps the untimed behavior")
        suite.expect(FanControlManualDuration.choices.first == 5
                && FanControlManualDuration.choices.last == FanControlManualDuration.untilChanged
                && Defaults.registeredDefaults[DefaultsKey.fanControlManualMinutes] as? Int
                    == FanControlManualDuration.untilChanged,
               "manual speed stays until changed by default, offered after the timed chips")
        let backupKeys = SettingsBackupSupport.exportKeys()
        suite.expect(backupKeys.contains(DefaultsKey.fanControlManualMinutes)
                && !backupKeys.contains(DefaultsKey.fanControlManualEnd),
               "the picked duration travels with a backup while the running end stays on this Mac")

        let end = now.addingTimeInterval(600)
        suite.expect(!FanControlManualDuration.hasEnded(end, now: now.addingTimeInterval(599))
                && FanControlManualDuration.hasEnded(end, now: end)
                && FanControlManualDuration.hasEnded(end, now: now.addingTimeInterval(7_200)),
               "a timed speed runs until its end, including an end that passed while the Mac slept")
        suite.expect(FanControlManualDuration.hasEnded(now.addingTimeInterval(3_601), now: now)
                && !FanControlManualDuration.hasEnded(now.addingTimeInterval(3_600), now: now),
               "an end further away than the longest choice, from a clock moved back, counts as ended")

        var cooling = FanControlSnapshot.empty
        cooling.isCooling = true
        cooling.configuration = manual
        var curveCooling = cooling
        curveCooling.configuration = .curve([FanControlConfiguration.defaultCurve])
        suite.expect(FanControlManualDuration.runningEnd(end, snapshot: cooling) == end
                && FanControlManualDuration.runningEnd(end, snapshot: .empty) == nil
                && FanControlManualDuration.runningEnd(end, snapshot: curveCooling) == nil
                && FanControlManualDuration.runningEnd(nil, snapshot: cooling) == nil,
               "the countdown shows only while the helper confirms the timed manual speed")

        reset(end: end)
        service.snapshot = cooling
        suite.expect(!service.expireTimedManualIfNeeded(now: now.addingTimeInterval(599))
                && service.events.isEmpty && service.timedManualEnd == end
                && storedEnd == end.timeIntervalSinceReferenceDate,
               "a timed speed keeps running before its end")
        suite.expect(service.expireTimedManualIfNeeded(now: end)
                && service.events == ["restore superseding"]
                && service.timedManualEnd == nil && storedEnd == 0 && storedResume == nil,
               "at its end a timed speed returns the fans to the system and forgets the kept control")
        suite.expect(!service.expireTimedManualIfNeeded(now: end.addingTimeInterval(1))
                && service.events == ["restore superseding"],
               "an ended speed is handed back once")

        reset(end: nil)
        service.snapshot = cooling
        suite.expect(!service.expireTimedManualIfNeeded(now: now.addingTimeInterval(86_400 * 30))
                && service.events.isEmpty && storedResume != nil,
               "a manual speed kept until I change it never ends on its own")

        reset(end: end)
        service.returnToSystem()
        suite.expect(service.timedManualEnd == nil && storedEnd == 0 && storedResume == nil
                && service.events == ["restore"],
               "returning to System early cancels the timed speed")

        reset(end: Date().addingTimeInterval(-60), recovery: true)
        service.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.events == ["restore superseding"]
                && service.timedManualEnd == nil && storedResume == nil,
               "an end passed during sleep hands the fans back on wake instead of resuming them")
        let remaining = Date().addingTimeInterval(300)
        reset(end: remaining)
        service.workspaceDidWake()
        suite.expect(service.applied == [manual] && service.appliedEnds == [remaining],
                     "waking before the end resumes the timed speed for the time it had left")

        reset(end: Date().addingTimeInterval(-60), recovery: true)
        Service.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.events == ["restore"]
                && storedResume == nil,
               "a launch after the end restores the system instead of resuming the timed speed")
        reset(end: remaining)
        Service.recoverIfNeeded()
        suite.expect(service.applied == [manual] && service.appliedEnds == [remaining],
                     "a launch before the end resumes the timed speed without extending it")
        reset(end: nil)
        Service.recoverIfNeeded()
        suite.expect(service.applied == [manual] && service.appliedEnds == [nil],
                     "a kept manual speed without an end resumes untimed, as before")

        reset(end: remaining)
        Environment.available = false
        service.syncWithPreferences()
        suite.expect(service.timedManualEnd == nil && storedEnd == 0,
                     "removing the feature forgets a running timed speed")
    }
}
