// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The handoff a timed session makes when it runs out is extracted from
/// production. It is the one place that decides whether a session the user
/// started by hand carries on as an automatic one, and it has to ask the same
/// question the automation asks itself: under All, one matching condition is
/// not a session (issue #1587).
enum KeepAwakeTimerHandoffContract {
    enum SessionTrigger { case manual, automation }
    enum AppFeature {
        static let keepAwake = Feature()
        final class Feature { var isAvailable = true }
    }
}

enum KeepAwakeTimerHandoffTests {
    private typealias Context = KeepAwakeTimerHandoffContract

    /// A dock where both conditions are selected and only the monitor is
    /// attached: the Mac is on battery with an external display connected,
    /// which is the state the timer runs out in.
    private static func dockedOnBattery(requireAll: Bool) -> Context.Service {
        let service = Context.Service()
        service.enabled = [.externalDisplay, .power]
        service.matching = [.externalDisplay]
        service.requireAll = requireAll
        return service
    }

    static func run(expect: (Bool, String) -> Void) {
        Context.AppFeature.keepAwake.isAvailable = true

        let all = dockedOnBattery(requireAll: true)
        expect(!all.continueAutomaticallyAfterTimerIfNeeded()
                && all.activations.isEmpty
                && all.activeAutomationConditions.isEmpty,
               "a timer running out on battery hands nothing over to an All automation")

        let any = dockedOnBattery(requireAll: false)
        expect(any.continueAutomaticallyAfterTimerIfNeeded()
                && any.activations.count == 1
                && any.activations.first?.end == nil
                && any.activations.first?.trigger == .automation
                && any.activeAutomationConditions == [.externalDisplay],
               "the same timer still hands over under Any, which is today's behaviour")

        let plugged = dockedOnBattery(requireAll: true)
        plugged.matching = [.externalDisplay, .power]
        expect(plugged.continueAutomaticallyAfterTimerIfNeeded()
                && plugged.activations.count == 1
                && plugged.activeAutomationConditions == [.externalDisplay, .power],
               "All hands the session over once every selected condition is met")

        // The guards the handoff already had stay in force under either mode.
        for requireAll in [false, true] {
            let mode = requireAll ? "All" : "Any"
            let automatic = dockedOnBattery(requireAll: requireAll)
            automatic.matching = automatic.enabled
            automatic.sessionTrigger = .automation
            expect(!automatic.continueAutomaticallyAfterTimerIfNeeded() && automatic.activations.isEmpty,
                   "\(mode): a session already running automatically is never handed to itself")

            let suppressed = dockedOnBattery(requireAll: requireAll)
            suppressed.matching = suppressed.enabled
            suppressed.automationSuppressedUntilConditionsClear = true
            expect(!suppressed.continueAutomaticallyAfterTimerIfNeeded() && suppressed.activations.isEmpty,
                   "\(mode): a session switched off by hand is not restarted by the timer")

            let drained = dockedOnBattery(requireAll: requireAll)
            drained.matching = drained.enabled
            drained.batteryAllows = false
            expect(!drained.continueAutomaticallyAfterTimerIfNeeded() && drained.activations.isEmpty,
                   "\(mode): battery protection outranks the handoff")

            let unavailable = dockedOnBattery(requireAll: requireAll)
            unavailable.matching = unavailable.enabled
            Context.AppFeature.keepAwake.isAvailable = false
            expect(!unavailable.continueAutomaticallyAfterTimerIfNeeded() && unavailable.activations.isEmpty,
                   "\(mode): a Keep Awake removed from the hub hands nothing over")
            Context.AppFeature.keepAwake.isAvailable = true
        }
    }
}
