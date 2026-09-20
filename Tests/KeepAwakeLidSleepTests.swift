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
        final class Queue {
            var pending: [() -> Void] = []
            func asyncAfter(deadline: Instant, execute: @escaping () -> Void) { pending.append(execute) }
            func advance() {
                let ready = pending
                pending.removeAll()
                ready.forEach { $0() }
            }
        }
    }
    enum BrightnessService {
        static var lid: Bool? = true
        static func lidClosed() -> Bool? { lid }
    }
    static let kIOMainPortDefault = 0
    static let kIOReturnSuccess = 0
    static var port = 1
    static var results = [0]
    static var calls = 0
    static var closes = 0
    static var policy: Bool? = true
    static var assertions: [[String: Any]]? = []
    static func IOPMFindPowerManagement(_ value: Int) -> Int { port }
    static func IOPMSleepSystem(_ value: Int) -> Int {
        calls += 1
        return results.count > 1 ? results.removeFirst() : results[0]
    }
    static func IOServiceClose(_ value: Int) { closes += 1 }
    static func reset() -> Service {
        port = 1; results = [0]; calls = 0; closes = 0
        policy = true; assertions = []; BrightnessService.lid = true
        DispatchQueue.main.pending.removeAll()
        return Service()
    }
}

enum KeepAwakeLidSleepTests {
    private typealias C = KeepAwakeLidSleepContract

    static func run(expect: (Bool, String) -> Void) {
        func allowed(_ policy: Bool?, _ assertions: [[String: Any]]?) -> Bool {
            KeepAwakeAutomationSupport.lidSleepIsAllowed(systemAllowsSleep: policy, assertions: assertions)
        }
        let connection: [String: Any] = ["AssertType": "PreventSystemSleep", "AssertLevel": 1,
                                          "ProcessingHotPlug": true]
        expect(!allowed(true, [connection]),
               "a live monitor transition overrides a stale allowed lid policy")
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
    }
}
