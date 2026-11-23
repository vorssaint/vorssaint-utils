// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production retry body without sleeping the computer. Native facts,
/// transport and time are controlled; the sleep policy itself is production.
enum KeepAwakeLidSleepContract {
    struct Instant {
        static func now() -> Instant { Instant() }
        static func + (lhs: Instant, rhs: Double) -> Instant { lhs }
    }
    enum DispatchQueue {
        static let main = Queue()
        static let background = Queue()
        static let native = Queue()
        enum QoS { case utility, userInitiated }
        static func global(qos: QoS) -> Queue { background }
        final class Queue {
            var immediate: [() -> Void] = []
            var pending: [() -> Void] = []
            func async(execute: @escaping () -> Void) { immediate.append(execute) }
            func sync<T>(execute: () -> T) -> T { flush(); return execute() }
            func flush() {
                while !immediate.isEmpty {
                    let ready = immediate
                    immediate.removeAll()
                    ready.forEach { $0() }
                }
            }
            func asyncAfter(deadline: Instant, execute: @escaping () -> Void) { pending.append(execute) }
            func asyncAfter(deadline: Instant, execute work: DispatchWorkItem) {
                pending.append { work.perform() }
            }
            func advance() {
                let ready = pending
                pending.removeAll()
                ready.forEach { $0() }
            }
        }
    }
    final class PowerNotificationSource {
        let notify: () -> Void
        init(notify: @escaping () -> Void) { self.notify = notify }
    }
    enum RunLoopMode { case defaultMode, commonModes }
    static func IOPSNotificationCreateRunLoopSource(
        _ callback: @escaping @convention(c) (UnsafeMutableRawPointer?) -> Void, _ context: UnsafeMutableRawPointer?
    ) -> Unmanaged<PowerNotificationSource>? {
        .passRetained(PowerNotificationSource { callback(context) })
    }
    static func CFRunLoopGetMain() -> RunLoop { .main }
    static func CFRunLoopAddSource(_ loop: RunLoop, _ source: PowerNotificationSource, _ mode: RunLoopMode) {}
    static func CFRunLoopRemoveSource(_ loop: RunLoop, _ source: PowerNotificationSource, _ mode: RunLoopMode) {}

    enum BrightnessService {
        static var lid: Bool? = true
        static func lidClosed() -> Bool? { lid }
    }
    /// Only the built-in panel this fixture models; a value the production
    /// code would treat as "the panel already reads asleep" is `nil`, not 0.
    enum LidDisplayDimmer {
        static var reading: Double?
        static var written: [Double] = []
        /// True by default; set false to model the panel not being back in
        /// the online list yet, or the write itself failing.
        static var writeSucceeds = true
        static func currentBrightness() -> Double? { reading }
        @discardableResult
        static func setBrightness(_ value: Double) -> Bool {
            guard writeSucceeds else { return false }
            written.append(value)
            return true
        }
    }
    static let kIOMainPortDefault = 0
    static let kIOReturnSuccess = 0
    static let KERN_SUCCESS: Int32 = 0
    static let kIOGeneralInterest = "IOGeneralInterest"
    typealias IONotificationPortRef = Int
    typealias io_object_t = Int
    static var port = 1
    static var results = [0]
    static var calls = 0
    static var closes = 0
    static var policy: Bool? = true
    static var assertions: [[String: Any]]? = []
    static var externalDisplay: Bool? = false
    static var connectedToPower: Bool? = true
    static func IOPMFindPowerManagement(_ value: Int) -> Int { port }
    static func IOPMSleepSystem(_ value: Int) -> Int {
        calls += 1
        onSleep?()
        return results.count > 1 ? results.removeFirst() : results[0]
    }
    static func IOServiceClose(_ value: Int) { closes += 1 }
    /// The root-domain general-interest observer the dimming feature keeps.
    /// Registrations, releases and the queued callback are counted the same
    /// way `DisplayRestorationTests` models `BrightnessService`'s own use of
    /// this exact IOKit pattern.
    enum DimmingObserver {
        static var registrations = 0
        static var releasedObjects = 0
        static var destroyedPorts = 0
        static var callback: (() -> Void)?
    }
    static func IOServiceMatching(_ name: String) -> Int { 1 }
    static func IOServiceGetMatchingService(_ port: Int, _ matching: Int) -> Int { 2 }
    static func IOObjectRelease(_ object: Int) { DimmingObserver.releasedObjects += 1 }
    static func IONotificationPortCreate(_ port: Int) -> Int? { 3 }
    static func IONotificationPortDestroy(_ port: Int) {
        DimmingObserver.destroyedPorts += 1
        DimmingObserver.callback = nil
    }
    static func IONotificationPortSetDispatchQueue(_ port: Int, _ queue: DispatchQueue.Queue) {}
    static func IOServiceAddInterestNotification(
        _ port: Int, _ root: Int, _ interest: String,
        _ callback: @escaping (UnsafeMutableRawPointer?, Int, UInt32, UnsafeMutableRawPointer?) -> Void,
        _ context: UnsafeMutableRawPointer?, _ notification: inout Int
    ) -> Int32 {
        DimmingObserver.registrations += 1
        notification = 4
        DimmingObserver.callback = { callback(context, root, 0, nil) }
        return KERN_SUCCESS
    }
    static func reset() -> Service {
        port = 1; results = [0]; calls = 0; closes = 0
        policy = true; assertions = []; externalDisplay = false; connectedToPower = true; BrightnessService.lid = true
        LidDisplayDimmer.reading = nil; LidDisplayDimmer.written = []; LidDisplayDimmer.writeSucceeds = true
        DimmingObserver.registrations = 0; DimmingObserver.releasedObjects = 0
        DimmingObserver.destroyedPorts = 0; DimmingObserver.callback = nil
        for queue in [DispatchQueue.main, DispatchQueue.background, DispatchQueue.native] {
            queue.pending.removeAll(); queue.immediate.removeAll()
        }
        UserDefaults.standard.values.removeAll()
        AppFeature.keepAwake.isAvailable = true
        SystemInfo.battery = nil
        Sudoers.calls = []; Sudoers.results = [true]; Sudoers.disabled = false
        Sudoers.configured = true; Sudoers.installCompletions = []
        Sudoers.sleepStateProbeSuspensions = 0; Sudoers.probeWrites = []
        AdminShell.completions = []; AdminShell.prompts = 0; AdminShell.syncResult = false
        Shell.status = 0; Shell.output = nil
        Thread.waits = 0; Thread.onWait = nil; onSleep = nil
        return Service()
    }
}

enum KeepAwakeLidSleepTests {
    private typealias C = KeepAwakeLidSleepContract

    static func run(expect: (Bool, String) -> Void) {
        func allowed(_ policy: Bool?, _ assertions: [[String: Any]]?,
                     external: Bool? = false, power: Bool? = true) -> Bool {
            KeepAwakeAutomationSupport.lidSleepIsAllowed(systemAllowsSleep: policy,
                                                         externalDisplayConnected: external,
                                                         connectedToPower: power,
                                                         assertions: assertions)
        }
        let connection: [String: Any] = ["AssertType": "PreventSystemSleep", "AssertLevel": 1,
                                          "ProcessingHotPlug": true]
        expect(!allowed(true, [connection]),
               "a live monitor transition overrides a stale allowed lid policy")
        expect(!allowed(true, [], external: true),
               "closed-display mode with an external monitor is never forced to sleep")
        expect(!allowed(true, [], external: nil),
               "on external power an unreadable display list never authorizes forced sleep")
        expect(!allowed(true, [connection], external: nil, power: false)
               && !allowed(true, nil, external: nil, power: false),
               "the battery cutoff still checks live lid protections when the display list is unreadable")
        expect(allowed(true, [], external: true, power: false),
               "a monitor on battery is not closed-display mode, so the battery cutoff still sleeps")
        expect(!allowed(true, [], external: true, power: nil),
               "an unreadable power source with a monitor never authorizes forced sleep")
        expect(allowed(true, [], external: false, power: false) && allowed(true, [], external: false, power: nil),
               "without a monitor the power source does not matter")
        expect(!allowed(false, []) && !allowed(nil, []) && !allowed(true, nil),
               "closed-display mode and unavailable system facts never authorize forced sleep")
        expect(allowed(true, []) && allowed(true, [["AssertType": "PreventUserIdleSystemSleep", "AssertLevel": 1]]),
               "media idle assertions do not defeat the closed-lid battery cutoff")
        for type in ["UserIsActive", "DisplayWake", "PreventSystemSleep"] {
            for key in ["AppliesOnLidClose", "ProcessingHotPlug"] {
                expect(!allowed(true, [["AssertType": type, "AssertLevel": 1, key: true]]),
                       "active lid protection is preserved for \(type)")
                expect(allowed(true, [["AssertType": type, "AssertLevel": 0, key: true]]),
                       "released lid protection does not keep a finished session awake")
                expect(allowed(true, [["AssertType": type, "AssertLevel": 1, key: false]]),
                       "an assertion that does not apply to the lid does not block lid sleep")
            }
        }
        expect(!allowed(true, [["ProcessingHotPlug": true]]),
               "incomplete marked protection is not mistaken for an inactive assertion")
        expect(allowed(true, [["AssertType": "PreventUserIdleSystemSleep", "AssertLevel": 1,
                               "AppliesOnLidClose": true]]),
               "lid flags on unrelated assertion types do not change the system's policy")

        for lid in [true, false, nil] as [Bool?] {
            for policy in [true, false, nil] as [Bool?] {
                let service = C.reset()
                C.BrightnessService.lid = lid; C.policy = policy
                service.sleepIfLidAlreadyClosed()
                expect(C.calls == (lid == true && policy == true ? 1 : 0),
                       "only a closed lid with an affirmative current policy can request sleep")
                expect(C.closes == C.calls && C.DispatchQueue.main.pending.isEmpty,
                       "ports close and successful or inapplicable requests do not poll")
            }
        }
        let docked = C.reset(); C.externalDisplay = true
        docked.sleepIfLidAlreadyClosed()
        expect(C.calls == 0, "ending a session docked to a monitor does not blank it with a sleep")
        let unplugged = C.reset(); C.externalDisplay = true; C.connectedToPower = false
        unplugged.sleepIfLidAlreadyClosed()
        expect(C.calls == 1, "the battery cutoff still sleeps a closed lid with a monitor on battery")
        let blocked = C.reset(); C.assertions = [connection]
        blocked.sleepIfLidAlreadyClosed()
        expect(C.calls == 0, "the production request respects an in-progress monitor connection")
        C.assertions = []
        blocked.sleepIfLidAlreadyClosed()
        expect(C.calls == 1, "sleep is allowed again once the temporary protection is released")

        let retry = C.reset(); C.results = [1, 1, 0]
        retry.sleepIfLidAlreadyClosed()
        for _ in 0..<12 { C.DispatchQueue.main.advance() }
        expect(C.calls == 3 && C.closes == 3,
               "a refused lid sleep retries until the system accepts it")
        let refused = C.reset(); C.results = [1]
        refused.sleepIfLidAlreadyClosed()
        for _ in 0..<15 { C.DispatchQueue.main.advance() }
        expect(C.calls == 10 && C.DispatchQueue.main.pending.isEmpty,
               "refused sleep is bounded to ten attempts with no permanent timer")

        for change in 0..<6 {
            let service = C.reset(); C.results = [1]
            service.sleepIfLidAlreadyClosed()
            switch change {
            case 0: service.isActive = true
            case 1: C.BrightnessService.lid = false
            case 2: C.policy = false
            case 3: service.clamshellActive = true
            case 4: C.assertions = [connection]
            default: C.assertions = nil
            }
            C.DispatchQueue.main.advance()
            expect(C.calls == 1 && C.DispatchQueue.main.pending.isEmpty,
                   "each retry rechecks the session, lid and current system protection")
            service.isActive = false; service.clamshellActive = false
            C.BrightnessService.lid = true; C.policy = true; C.assertions = []
            C.DispatchQueue.main.advance()
            expect(C.calls == 1, "a canceled retry cannot resume after a later context change")
        }
        let paused = C.reset(); paused.isActive = true; paused.sessionPausedForScreenLock = true
        paused.sleepIfLidAlreadyClosed()
        expect(C.calls == 1, "a session paused for screen lock no longer asks to stay awake")
        let missing = C.reset(); C.port = 0
        missing.sleepIfLidAlreadyClosed()
        expect(C.calls == 0 && C.closes == 0, "an unavailable sleep service is not called or closed")
        KeepAwakeClamshellTests.run(expect: expect)
        KeepAwakeDimmingTests.run(expect: expect)
        powerNotifications(expect: expect)
        powerDisconnectDelay(expect: expect)
    }

    private static func powerNotifications(expect: (Bool, String) -> Void) {
        let service = C.reset()
        service.clamshellPreferred = false
        service.recoveryCompleted = true
        service.setPowerMonitoringEnabled(true)
        guard let source = service.powerSourceRunLoopSource else {
            expect(false, "Keep Awake registers its power callback")
            return
        }
        defer {
            service.setPowerMonitoringEnabled(false)
            service.deactivate(reason: .manual)
        }

        // With the default zero delay, a brief source change is still coalesced.
        service.matchingConditions = [.power]
        source.notify()
        expect(!service.isActive, "zero delay preserves the existing power notification debounce")
        C.DispatchQueue.main.advance()
        expect(service.isActive, "the debounced power evaluation starts the automatic session")
        service.matchingConditions = []
        source.notify()
        expect(service.isActive && service.assertionsHeld,
               "a brief unplug retains the session until the default debounce runs")
        service.matchingConditions = [.power]
        source.notify()
        C.DispatchQueue.main.advance()
        expect(service.isActive && service.assertionsHeld && service.assertionReleases == 0
                && service.powerDisconnectEvaluation == nil,
               "a reconnect inside the default debounce leaves the powered session active")

        C.UserDefaults.standard.set(15, forKey: C.DefaultsKey.keepAwakePowerDisconnectDelay)
        service.matchingConditions = []
        source.notify()
        guard let first = service.powerDisconnectEvaluation?.deadline else {
            expect(false, "a reported disconnect sets a deadline in the power callback")
            return
        }
        service.powerSample = (isOnBattery: false, isOnExternalPower: false)
        source.notify()
        expect(service.powerDisconnectEvaluation?.deadline == first,
               "a source description with no power state preserves the original deadline")
        service.matchingConditions = []
        source.notify()
        expect(service.powerDisconnectEvaluation?.deadline == first,
               "a subsequent battery reading does not restart the delay")

        // Deliver both edges before another main-queue evaluation can run.
        service.matchingConditions = [.power]
        source.notify()
        expect(service.isActive && service.assertionsHeld && service.assertionReleases == 0
                && service.powerDisconnectEvaluation == nil,
               "the confirmed reconnect clears the first deadline synchronously")
        service.matchingConditions = []
        source.notify()
        expect(service.powerDisconnectEvaluation.map { $0.deadline > first } == true,
               "a second reported dropout gets a new deadline even before the debounce would fire")
    }

    private static func powerDisconnectDelay(expect: (Bool, String) -> Void) {
        func evaluate(_ service: C.Service, matching conditions: Set<KeepAwakeAutomationCondition>) {
            service.matchingConditions = conditions
            service.evaluateAutomation()
        }

        func poweredSession(delay: Int, conditions: Set<KeepAwakeAutomationCondition> = [.power],
                            requireAll: Bool = false) -> C.Service {
            let service = C.reset()
            service.clamshellPreferred = false
            service.recoveryCompleted = true
            C.UserDefaults.standard.set(delay, forKey: C.DefaultsKey.keepAwakePowerDisconnectDelay)
            service.enabledConditions = conditions
            service.requireAll = requireAll
            evaluate(service, matching: conditions)
            return service
        }

        let immediate = poweredSession(delay: 0)
        evaluate(immediate, matching: [])
        expect(!immediate.isActive && !immediate.assertionsHeld,
               "a zero power disconnect delay ends the automatic session immediately")

        let stopped = poweredSession(delay: 20)
        evaluate(stopped, matching: [])
        stopped.toggle()
        expect(!stopped.isActive && !stopped.assertionsHeld && stopped.powerDisconnectEvaluation == nil,
               "switching off during the delay releases assertions and cancels the deadline")
        evaluate(stopped, matching: [.power])
        expect(stopped.isActive && stopped.sessionTrigger == .automation,
               "a new connection starts automation after a stop on battery without an intervening evaluation")
        stopped.deactivate(reason: .manual)

        let stoppedWithApp = poweredSession(delay: 20, conditions: [.power, .runningApps])
        evaluate(stoppedWithApp, matching: [.runningApps])
        stoppedWithApp.toggle()
        evaluate(stoppedWithApp, matching: [.power, .runningApps])
        expect(!stoppedWithApp.isActive && !stoppedWithApp.assertionsHeld
                && stoppedWithApp.powerDisconnectEvaluation == nil,
               "stopping with an Any app still running suppresses automation through reconnection")
        evaluate(stoppedWithApp, matching: [])
        evaluate(stoppedWithApp, matching: [.runningApps])
        expect(stoppedWithApp.isActive, "a new Any match can start a session after all conditions clear")
        stoppedWithApp.deactivate(reason: .manual)

        let all = poweredSession(delay: 20, conditions: [.externalDisplay, .power], requireAll: true)
        evaluate(all, matching: [.externalDisplay])
        expect(all.isActive && all.waitingForPower,
               "All waits for power when the other required condition still matches")
        evaluate(all, matching: [])
        expect(!all.isActive && !all.assertionsHeld && all.powerDisconnectEvaluation == nil,
               "All ends immediately if the external display condition is lost during the delay")

        // Exercise all five-second deadlines in the same pass through the main run loop.
        let manual = poweredSession(delay: 5)
        let any = poweredSession(delay: 5, conditions: [.power, .runningApps])
        let allWithDisplay = poweredSession(delay: 5, conditions: [.power, .externalDisplay], requireAll: true)
        let locked = poweredSession(delay: 5)
        let delayed = poweredSession(delay: 5)
        C.UserDefaults.standard.set(true, forKey: C.DefaultsKey.keepAwakePauseWhenLocked)

        evaluate(manual, matching: [])
        manual.activate(minutes: 15)
        let manualEnd = manual.endDate
        expect(manual.isActive && manual.sessionTrigger == .manual && manual.powerDisconnectEvaluation == nil,
               "a manual replacement clears the automatic session's pending stop")

        evaluate(any, matching: [])
        evaluate(any, matching: [.runningApps])
        expect(any.isActive && any.assertionsHeld && !any.waitingForPower,
               "a selected app can take over while an Any session is waiting for power")
        evaluate(allWithDisplay, matching: [.externalDisplay])

        locked.screenLockStateDidChange(locked: true)
        evaluate(locked, matching: [])
        expect(locked.sessionPausedForScreenLock && !locked.assertionsHeld && !locked.waitingForPower,
               "disconnecting power while locked leaves assertions paused")
        locked.screenLockStateDidChange(locked: false)
        expect(locked.isActive && locked.assertionsHeld && locked.waitingForPower,
               "unlocking before the deadline resumes the automatic session on battery")
        locked.screenLockStateDidChange(locked: true)

        evaluate(delayed, matching: [])
        let firstDeadline = delayed.powerDisconnectEvaluation?.deadline
        expect(delayed.isActive && delayed.assertionsHeld && delayed.waitingForPower && firstDeadline != nil,
               "disconnecting power retains the automatic session and its assertions")
        delayed.evaluateAutomation()
        expect(delayed.powerDisconnectEvaluation?.deadline == firstDeadline,
               "repeated evaluations do not extend a disconnect delay")
        evaluate(delayed, matching: [.power])
        expect(delayed.isActive && delayed.assertionsHeld && !delayed.waitingForPower
                && delayed.powerDisconnectEvaluation == nil,
               "reconnecting power cancels the pending stop without releasing assertions")
        evaluate(delayed, matching: [])
        let timeout = Date().addingTimeInterval(7)
        while (delayed.isActive || allWithDisplay.isActive || any.powerDisconnectEvaluation != nil), Date() < timeout {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        expect(!delayed.isActive && !delayed.assertionsHeld && delayed.powerDisconnectEvaluation == nil,
               "a later disconnect expires on its own and releases assertions")
        delayed.evaluateAutomation()
        expect(!delayed.isActive, "a Mac already on battery cannot start a session through the delay")
        expect(any.isActive && any.assertionsHeld && any.assertionReleases == 0 && any.powerDisconnectEvaluation == nil,
               "a matching Any app keeps the session and assertions past the power deadline")
        evaluate(any, matching: [])
        expect(!any.isActive && !any.assertionsHeld,
               "losing the last Any match after the deadline ends the session immediately")
        expect(!allWithDisplay.isActive && !allWithDisplay.assertionsHeld,
               "reaching the deadline ends an All session with only the display still matching")
        locked.screenLockStateDidChange(locked: false)
        expect(!locked.isActive && !locked.assertionsHeld && locked.powerDisconnectEvaluation == nil,
               "unlocking after the deadline on battery leaves the automatic session stopped")
        expect(manual.isActive && manual.assertionsHeld && manualEnd != nil && manual.endDate == manualEnd,
               "the old power deadline leaves the replacement session and its chosen end time intact")
        manual.deactivate(reason: .manual)

        let lowBattery = poweredSession(delay: 20)
        C.UserDefaults.standard.set(10, forKey: C.DefaultsKey.batteryLimit)
        C.SystemInfo.battery = (isOnBattery: true, percent: 11)
        evaluate(lowBattery, matching: [])
        var endReason: C.EndReason?
        lowBattery.onSessionEnded = { endReason = $0 }
        C.SystemInfo.battery = (isOnBattery: true, percent: 10)
        lowBattery.evaluateAutomation()
        expect(endReason == .battery && !lowBattery.isActive && !lowBattery.assertionsHeld
                && lowBattery.powerDisconnectEvaluation == nil,
               "reaching the battery cutoff during the delay ends the session and cancels its deadline")

        let lowBatteryWithApp = poweredSession(delay: 20, conditions: [.power, .runningApps])
        C.UserDefaults.standard.set(10, forKey: C.DefaultsKey.batteryLimit)
        C.SystemInfo.battery = (isOnBattery: true, percent: 5)
        evaluate(lowBatteryWithApp, matching: [.runningApps])
        expect(!lowBatteryWithApp.isActive && !lowBatteryWithApp.assertionsHeld
                && lowBatteryWithApp.powerDisconnectEvaluation == nil,
               "battery protection wins on unplug even if another Any condition still matches")
    }
}
