// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import os

/// Production restoration and transaction bodies, with in-memory IOKit,
/// CoreGraphics, preferences and a manually drained main queue. No device writes.
enum DisplayRestorationTests {
    typealias CGDisplayConfigRef = Int
    typealias IONotificationPortRef = Int
    typealias io_object_t = UInt32
    static let kIOMainPortDefault: UInt32 = 0
    static let kIOGeneralInterest = "IOGeneralInterest"
    static let KERN_SUCCESS: Int32 = 0

    final class Queue {
        var jobs: [() -> Void] = []
        func async(execute work: @escaping () -> Void) { jobs.append(work) }
        func asyncAfter(deadline: DispatchTime, execute work: DispatchWorkItem) {
            jobs.append { if !work.isCancelled { work.perform() } }
        }
        func drain() {
            var count = 0
            while !jobs.isEmpty {
                count += 1
                precondition(count < 20, "recovery must not loop on its own notifications")
                jobs.removeFirst()()
            }
        }
    }
    enum DispatchQueue { static var main = Queue() }
    enum Hardware {
        static var lid: Bool? = true
        static var succeeds = true
        static var transactions = 0
        static var registrations = 0
        static var destroyedPorts = 0
        static var released: [UInt32] = []
        static var callback: (() -> Void)?
        static var onSubscribe: (() -> Void)?
        static var lidRead: (() -> Bool?)?
        static var fingerprints: [UInt32: String] = [:]
    }
    enum DefaultsKey {
        static let displaysSwitchedOff = "off"
        static let displaysSwitchedOffFingerprints = "offFingerprints"
    }
    final class UserDefaults {
        static var standard = UserDefaults()
        var stored: [Int] = []
        var fingerprints: [String: String] = [:]
        func array(forKey: String) -> [Any]? { stored }
        func dictionary(forKey: String) -> [String: Any]? { fingerprints }
        func set(_ value: Any, forKey key: String) {
            if key == DefaultsKey.displaysSwitchedOff { stored = value as? [Int] ?? [] }
            if key == DefaultsKey.displaysSwitchedOffFingerprints {
                fingerprints = value as? [String: String] ?? [:]
            }
        }
        func removeObject(forKey key: String) {
            if key == DefaultsKey.displaysSwitchedOff { stored = [] }
            if key == DefaultsKey.displaysSwitchedOffFingerprints { fingerprints = [:] }
        }
    }
    struct BrightnessDisplay {
        let id: UInt32
        var name: String
        var method: Int?
        var isActive: Bool
        let isBuiltIn: Bool
        var brightness: Double
        let readable: Bool
        var restorationFingerprint: String?

        init(id: UInt32, name: String = "Display", isBuiltIn: Bool? = nil,
             method: Int? = 1, isActive: Bool = false,
             brightness: Double = 1, readable: Bool = false,
             restorationFingerprint: String? = nil) {
            self.id = id
            self.name = name
            self.isBuiltIn = isBuiltIn ?? (id == 1)
            self.method = method
            self.isActive = isActive
            self.brightness = brightness
            self.readable = readable
            self.restorationFingerprint = restorationFingerprint
        }
    }
    enum DisplayConfigurationBridge {
        static var configureEnabled: ((Int, UInt32, Bool) -> Int32)? = { _, _, _ in 0 }
    }
    static func CGDisplayIsBuiltin(_ id: UInt32) -> UInt32 { id == 1 ? 1 : 0 }
    static func CGBeginDisplayConfiguration(_ reference: inout Int?) -> CGError {
        Hardware.transactions += 1
        reference = 1
        return .success
    }
    static func CGCancelDisplayConfiguration(_ reference: Int) {}
    static func CGCompleteDisplayConfiguration(_ reference: Int, _ option: CGConfigureOption) -> CGError {
        Hardware.callback?()
        return Hardware.succeeds ? .success : .failure
    }
    static func IOServiceMatching(_ name: String) -> Int { 1 }
    static func IOServiceGetMatchingService(_ port: UInt32, _ matching: Int) -> UInt32 { 2 }
    static func IOObjectRelease(_ object: UInt32) { Hardware.released.append(object) }
    static func IONotificationPortCreate(_ port: UInt32) -> Int? { 3 }
    static func IONotificationPortDestroy(_ port: Int) {
        Hardware.destroyedPorts += 1
        Hardware.callback = nil
    }
    static func IONotificationPortSetDispatchQueue(_ port: Int, _ queue: Queue) {}
    static func IOServiceAddInterestNotification(
        _ port: Int, _ root: UInt32, _ interest: String,
        _ callback: @escaping (UnsafeMutableRawPointer?, UInt32, UInt32, UnsafeMutableRawPointer?) -> Void,
        _ context: UnsafeMutableRawPointer?, _ notification: inout UInt32
    ) -> Int32 {
        Hardware.registrations += 1
        notification = 4
        Hardware.callback = { callback(context, root, 0, nil) }
        Hardware.onSubscribe?()
        return KERN_SUCCESS
    }

    class Fixture {
        static let log = Logger(subsystem: "vorssaint.tests", category: "restoration")
        var deferredRestoration = BrightnessSupport.DeferredDisplayRestoration()
        var lidNotificationPort: IONotificationPortRef?
        var lidNotification: io_object_t = 0
        let stateLock = NSLock()
        var managedDisabledIDs = Set<UInt32>()
        var managedDisabledDisplays: [UInt32: BrightnessDisplay] = [:]
        var pendingLevels: [UInt32: Double] = [:]
        var knownTopology = Set<UInt32>()
        var knownActiveTopology = Set<UInt32>()
        var knownDisplayFingerprints: [UInt32: String] = [:]
        var displayControlFailure: BrightnessService.DisplayControlFailure?
        var pendingDisplayIDs = Set<UInt32>()
        var displays: [BrightnessDisplay] = []
        var refreshes = 0
        var running = false
        var wakeObserversInstalled = false
        var wakeRebuild: DispatchWorkItem?
        static let wakeSettleDelay: TimeInterval = 3
        static func lidClosed() -> Bool? { Hardware.lidRead?() ?? Hardware.lid }
        static func displayInfoDictionary(_ id: UInt32) -> NSDictionary? { nil }
        static func displayFingerprint(_ id: UInt32) -> String {
            Hardware.fingerprints[id] ?? "0:0:0"
        }
        static func displayName(_ id: UInt32, info: NSDictionary?, screenNames: [UInt32: String]) -> String {
            "Display"
        }
        func refresh(force: Bool = false) { refreshes += 1 }
        func installWakeObservers() { wakeObserversInstalled = true }
        func removeWakeObservers() {
            wakeObserversInstalled = false
            wakeRebuild?.cancel()
            wakeRebuild = nil
        }

    }

    static func run(_ suite: TestSuite) {
        func make() -> BrightnessService {
            DispatchQueue.main = Queue()
            UserDefaults.standard = UserDefaults()
            Hardware.lid = true
            Hardware.succeeds = true
            Hardware.transactions = 0
            Hardware.registrations = 0
            Hardware.destroyedPorts = 0
            Hardware.released = []
            Hardware.callback = nil
            Hardware.onSubscribe = nil
            Hardware.lidRead = nil
            Hardware.fingerprints = [1: "1:1:1", 2: "2:2:2"]
            return BrightnessService()
        }
        var service = make()
        UserDefaults.standard.stored = [1]
        service.restoreDisplaysLeftOff()
        service.restoreDisplaysLeftOff()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 0 && Hardware.registrations == 1
                     && UserDefaults.standard.stored == [1],
                     "closed startup retains its record and owns only one observer without starting the feature")
        Hardware.lid = false
        Hardware.callback?()
        suite.expect(Hardware.transactions == 0, "IOKit callback never configures displays inline")
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 1 && UserDefaults.standard.stored.isEmpty
                     && Hardware.destroyedPorts == 1 && Hardware.released.contains(4),
                     "lid-open notification alone restores startup intent and releases observation")

        service = make()
        UserDefaults.standard.stored = [1]
        service.managedDisabledIDs = [1]
        service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
        service.restoreManagedDisplays()
        Hardware.lid = false
        Hardware.succeeds = false
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 1 && service.managedDisabledIDs == [1]
                     && UserDefaults.standard.stored == [1] && Hardware.destroyedPorts == 0,
                     "feature-stop recovery retains failed intent without looping on transaction notifications")
        Hardware.lid = true
        Hardware.callback?()
        DispatchQueue.main.drain()
        Hardware.lid = false
        Hardware.succeeds = true
        Hardware.callback?()
        DispatchQueue.main.drain()
        suite.expect(service.managedDisabledIDs.isEmpty && service.managedDisabledDisplays.isEmpty
                     && UserDefaults.standard.stored.isEmpty && Hardware.destroyedPorts == 1,
                     "later opening clears managed snapshots and persisted recovery after success")

        service = make()
        UserDefaults.standard.stored = [1]
        Hardware.onSubscribe = { Hardware.lid = false }
        service.restoreDisplaysLeftOff()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 1 && UserDefaults.standard.stored.isEmpty,
                     "subscribe-then-recheck catches an opening during observer registration")

        service = make()
        service.managedDisabledIDs = [1]
        Hardware.lid = false
        service.restoreDeferredDisplays()
        suite.expect(Hardware.transactions == 0,
                     "an intentionally disabled display without deferred intent remains disabled")
        DispatchQueue.main.async { [weak service] in
            service?.commitDisplayToggle(BrightnessDisplay(id: 1), enabled: true)
        }
        Hardware.lid = true
        DispatchQueue.main.drain()
        suite.expect(service.displayControlFailure == .closedLid && Hardware.transactions == 0
                     && service.deferredRestoration.ids == [1] && Hardware.registrations == 1,
                     "a tap denied by the closed lid says so and is remembered for the lid opening")
        Hardware.lid = false
        Hardware.callback?()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 1 && service.displayControlFailure == nil
                     && service.deferredRestoration.ids.isEmpty && service.managedDisabledIDs.isEmpty
                     && Hardware.destroyedPorts == 1,
                     "opening the lid finishes the remembered tap and clears its message")
        Hardware.succeeds = false
        service.commitDisplayToggle(BrightnessDisplay(id: 1), enabled: true)
        DispatchQueue.main.drain()
        suite.expect(service.displayControlFailure == .failed && service.deferredRestoration.ids.isEmpty,
                     "an open-lid transaction failure remains generic and is not remembered")

        service = make()
        service.managedDisabledIDs = [1, 2]
        service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
        service.managedDisabledDisplays[2] = BrightnessDisplay(id: 2, restorationFingerprint: "2:2:2")
        service.commitDisplayToggle(BrightnessDisplay(id: 1), enabled: true)
        DispatchQueue.main.drain()
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        suite.expect(service.deferredRestoration.ids == [1] && service.managedDisabledIDs == [1]
                     && Hardware.transactions == 1 && Hardware.destroyedPorts == 0,
                     "a remembered tap outlives a headless recovery that brought another display back")
        Hardware.lid = false
        service.restoreDeferredDisplays()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 2 && service.deferredRestoration.ids.isEmpty
                     && service.managedDisabledIDs.isEmpty,
                     "opening the lid then finishes the tap as well")

        service = make()
        UserDefaults.standard.stored = [1]
        service.restoreDisplaysLeftOff()
        Hardware.lid = false
        service.commitDisplayToggle(BrightnessDisplay(id: 1, isActive: true), enabled: false)
        DispatchQueue.main.drain()
        suite.expect(service.deferredRestoration.ids.isEmpty && Hardware.transactions == 1
                     && Hardware.destroyedPorts == 1 && service.managedDisabledIDs == [1],
                     "new explicit disable cancels older deferred recovery before queued recheck")

        for initialFailure in [BrightnessService.DisplayControlFailure.failed, .closedLid] {
            service = make()
            UserDefaults.standard.stored = [1]
            service.managedDisabledIDs = [1]
            service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
            service.restoreDisplaysLeftOff()
            DispatchQueue.main.drain()
            Hardware.lid = initialFailure == .closedLid
            Hardware.succeeds = false
            service.commitDisplayToggle(BrightnessDisplay(id: 1), enabled: true)
            DispatchQueue.main.drain()
            suite.expect(service.displayControlFailure == initialFailure,
                         "production manual completion publishes the actual failure")
            Hardware.lid = true
            service.restoreDeferredDisplays()
            Hardware.lid = false
            service.restoreDeferredDisplays()
            DispatchQueue.main.drain()
            suite.expect(service.displayControlFailure == initialFailure
                         && UserDefaults.standard.stored == [1],
                         "failed deferred restoration preserves the existing error and recovery intent")
            Hardware.lid = true
            service.restoreDeferredDisplays()
            Hardware.lid = false
            Hardware.succeeds = true
            service.restoreDeferredDisplays()
            DispatchQueue.main.drain()
            suite.expect(service.displayControlFailure == nil && UserDefaults.standard.stored.isEmpty,
                         "successful deferred restoration clears generic and closed-lid errors")
        }

        service = make()
        service.managedDisabledIDs = [1]
        service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        suite.expect(service.displayControlFailure == .closedLid,
                     "headless restoration preserves the closed-lid denial reason")
        Hardware.lid = false
        Hardware.callback?()
        DispatchQueue.main.drain()
        suite.expect(service.displayControlFailure == nil,
                     "successful headless deferred recovery removes its panel error")

        service = make()
        service.managedDisabledIDs = [1, 2]
        service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
        service.managedDisabledDisplays[2] = BrightnessDisplay(id: 2, restorationFingerprint: "2:2:2")
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        suite.expect(service.deferredRestoration.ids.isEmpty && service.managedDisabledIDs == [1]
                     && Hardware.destroyedPorts == 1,
                     "headless success cancels only the newly queued closed-lid candidate")
        Hardware.lid = false
        service.restoreDeferredDisplays()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 1 && service.deferredRestoration.ids.isEmpty,
                     "superseded headless intent does not restore another display after lid opening")

        service = make()
        UserDefaults.standard.stored = [1]
        service.managedDisabledIDs = [1, 2]
        service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
        service.managedDisabledDisplays[2] = BrightnessDisplay(id: 2, restorationFingerprint: "2:2:2")
        service.restoreDisplaysLeftOff()
        DispatchQueue.main.drain()
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        suite.expect(service.deferredRestoration.ids == [1],
                     "headless success preserves an independently owed restoration")
        Hardware.lid = false
        service.restoreDeferredDisplays()
        DispatchQueue.main.drain()
        suite.expect(service.deferredRestoration.ids.isEmpty && Hardware.transactions == 2,
                     "independent deferred restoration still completes after headless success")

        service = make()
        service.managedDisabledIDs = [1, 2]
        service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
        service.managedDisabledDisplays[2] = BrightnessDisplay(id: 2, restorationFingerprint: "2:2:2")
        Hardware.succeeds = false
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        Hardware.succeeds = true
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        suite.expect(service.deferredRestoration.ids.isEmpty,
                     "repeated headless attempts retain ownership until a later external success")

        service = make()
        service.managedDisabledIDs = [1, 2]
        service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
        service.managedDisabledDisplays[2] = BrightnessDisplay(id: 2, restorationFingerprint: "2:2:2")
        Hardware.succeeds = false
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        Hardware.lid = false
        service.restoreManagedDisplays()
        DispatchQueue.main.drain()
        Hardware.lid = true
        Hardware.succeeds = true
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        suite.expect(service.deferredRestoration.ids == [1],
                     "a failed restore-all request promotes prior headless intent")

        service = make()
        UserDefaults.standard.stored = [1, 2]
        service.managedDisabledIDs = [1, 2]
        service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
        service.managedDisabledDisplays[2] = BrightnessDisplay(id: 2, restorationFingerprint: "2:2:2")
        Hardware.succeeds = false
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        suite.expect(service.deferredRestoration.ids == [1],
                     "failed headless round keeps the closed internal request queued")
        var retryReads = [false, true]
        Hardware.lidRead = { retryReads.isEmpty ? true : retryReads.removeFirst() }
        service.restoreDeferredDisplays()
        Hardware.lidRead = nil
        Hardware.lid = true
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 1 && service.deferredRestoration.ids == [1],
                     "a deferred retry that closes at the transaction keeps headless ownership")
        Hardware.lid = true
        Hardware.succeeds = true
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        suite.expect(service.deferredRestoration.ids.isEmpty && service.managedDisabledIDs == [1]
                     && UserDefaults.standard.stored == [1] && Hardware.destroyedPorts == 1,
                     "later external headless success cancels only the internal headless request: ids=\(service.deferredRestoration.ids) managed=\(service.managedDisabledIDs) stored=\(UserDefaults.standard.stored) destroyed=\(Hardware.destroyedPorts)")
        Hardware.lid = false
        service.restoreDeferredDisplays()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 2 && UserDefaults.standard.stored == [1],
                     "opening after cancellation does not enable the internal display: transactions=\(Hardware.transactions) stored=\(UserDefaults.standard.stored)")

        service = make()
        service.managedDisabledIDs = [1, 2]
        service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
        service.managedDisabledDisplays[2] = BrightnessDisplay(id: 2, restorationFingerprint: "2:2:2")
        var lidReads = [true, false, true]
        Hardware.lidRead = { lidReads.isEmpty ? true : lidReads.removeFirst() }
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        suite.expect(service.deferredRestoration.ids.isEmpty,
                     "headless candidate retry uses the shared transaction-time lid result")
        Hardware.lid = false
        service.restoreDeferredDisplays()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 1,
                     "opening after a successful external headless recovery does not enable the internal display")

        service = make()
        UserDefaults.standard.stored = [1]
        service.restoreDisplaysLeftOff()
        service.commitDisplayToggle(BrightnessDisplay(id: 1), enabled: true)
        Hardware.lid = false
        DispatchQueue.main.drain()
        suite.expect(service.displayControlFailure == nil && Hardware.transactions == 1,
                     "queued manual completion cannot republish denial after earlier queued recovery succeeds")

        for startup in [true, false] {
            service = make()
            service.commitDisplayToggle(BrightnessDisplay(id: 1), enabled: true)
            UserDefaults.standard.stored = [1]
            service.managedDisabledIDs = [1]
            service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
            Hardware.lid = false
            if startup { service.restoreDisplaysLeftOff() } else { service.restoreManagedDisplays() }
            DispatchQueue.main.drain()
            suite.expect(service.displayControlFailure == nil && UserDefaults.standard.stored.isEmpty,
                         "startup and feature-stop success share restoration error cleanup")
        }

        service = make()
        service.managedDisabledIDs = [1, 2]
        service.managedDisabledDisplays[1] = BrightnessDisplay(id: 1)
        service.managedDisabledDisplays[2] = BrightnessDisplay(id: 2, restorationFingerprint: "2:2:2")
        Hardware.succeeds = false
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        suite.expect(service.displayControlFailure == .failed,
                     "a genuine headless transaction failure is not mislabeled as a closed-lid denial")

        service = make()
        Hardware.lid = false
        service.running = true
        service.displays = [BrightnessDisplay(id: 1, isActive: true),
                            BrightnessDisplay(id: 2, isActive: true)]
        Hardware.callback = {
            suite.expect(UserDefaults.standard.fingerprints["2"] == "2:2:2"
                         && UserDefaults.standard.stored == [2],
                         "the original display identity reaches preferences before the disable transaction")
            Hardware.fingerprints[2] = "0:0:0"
        }
        service.commitDisplayToggle(service.displays[1], enabled: false)
        Hardware.callback = nil
        suite.expect(service.managedDisabledDisplays[2]?.restorationFingerprint == "2:2:2",
                     "the disabled monitor's identity is captured before its connection disappears")
        service.recordDiscoveredTopology(online: [1], active: [1, 2])
        Hardware.fingerprints[2] = "2:2:2"
        service.recordDiscoveredTopology(online: [1, 2], active: [1, 2],
                                        fingerprints: [2: "2:2:2"])
        service.recordDiscoveredTopology(online: [1], active: [1])
        service.displaysWokeUp()
        DispatchQueue.main.drain()
        suite.expect(service.managedDisabledIDs == [2]
                     && service.managedDisabledDisplays[2]?.isActive == false
                     && UserDefaults.standard.stored == [2] && Hardware.transactions == 1,
                     "transient active observations and waking preserve an intentionally disabled monitor's recovery row")
        service.commitDisplayToggle(service.displays[1], enabled: true)
        DispatchQueue.main.drain()
        suite.expect(service.managedDisabledIDs.isEmpty && service.managedDisabledDisplays.isEmpty
                     && UserDefaults.standard.stored.isEmpty && Hardware.transactions == 2,
                     "an explicit successful enable retires the preserved monitor row")

        service = make()
        Hardware.lid = false
        Hardware.succeeds = false
        UserDefaults.standard.stored = [2]
        UserDefaults.standard.fingerprints = ["2": "2:2:2"]
        service.restoreDisplaysLeftOff()
        DispatchQueue.main.drain()
        suite.expect(service.managedDisabledIDs == [2]
                     && service.managedDisabledDisplays[2]?.isActive == false
                     && service.managedDisabledDisplays[2]?.method == nil
                     && service.deferredRestoration.ids == [2] && service.wakeObserversInstalled,
                     "failed startup recreates the external monitor row and keeps wake recovery with display control off")
        let attemptsAfterStartup = Hardware.transactions
        Hardware.callback?()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == attemptsAfterStartup,
                     "ordinary IOKit callbacks do not loop a failed external restoration")
        service.displaysWokeUp()
        service.displaysWokeUp()
        suite.expect(Hardware.transactions == attemptsAfterStartup,
                     "wake restoration waits for connections to settle")
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == attemptsAfterStartup + 1
                     && service.deferredRestoration.ids == [2]
                     && UserDefaults.standard.stored == [2] && service.wakeObserversInstalled,
                     "paired wake notifications make one retry and a failure retains recovery")
        Hardware.succeeds = true
        service.displaysWokeUp()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == attemptsAfterStartup + 2
                     && service.managedDisabledIDs.isEmpty && service.managedDisabledDisplays.isEmpty
                     && service.deferredRestoration.ids.isEmpty && UserDefaults.standard.stored.isEmpty
                     && !service.wakeObserversInstalled && Hardware.destroyedPorts == 1,
                     "a later wake restores the monitor and releases observers while display control stays off")

        service = make()
        UserDefaults.standard.stored = [1]
        service.restoreDisplaysLeftOff()
        service.displaysWokeUp()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 0 && service.deferredRestoration.ids == [1]
                     && service.managedDisabledDisplays[1]?.isActive == false,
                     "wake recovery never enables the built-in panel behind a closed lid")
        Hardware.lid = false
        Hardware.callback?()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 1 && service.managedDisabledIDs.isEmpty
                     && service.managedDisabledDisplays.isEmpty && !service.wakeObserversInstalled,
                     "opening the lid restores the recreated startup row and releases wake observation")

        service = make()
        Hardware.lid = false
        Hardware.succeeds = false
        UserDefaults.standard.stored = [2]
        UserDefaults.standard.fingerprints = ["2": "2:2:2"]
        service.restoreDisplaysLeftOff()
        DispatchQueue.main.drain()
        service.displaysWokeUp()
        let attemptsBeforeDisable = Hardware.transactions
        Hardware.succeeds = true
        service.commitDisplayToggle(BrightnessDisplay(id: 2, isActive: true), enabled: false)
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == attemptsBeforeDisable + 1
                     && service.deferredRestoration.ids.isEmpty
                     && service.managedDisabledIDs == [2] && UserDefaults.standard.stored == [2],
                     "an explicit disable cancels a pending wake enable and keeps the monitor off")

        service = make()
        Hardware.lid = false
        service.displays = [BrightnessDisplay(id: 2, isActive: true)]
        service.commitDisplayToggle(service.displays[0], enabled: false)
        Hardware.fingerprints[2] = "3:3:3"
        service.recordDiscoveredTopology(online: [1, 2], active: [1, 2],
                                        fingerprints: [2: "3:3:3"])
        // The replacement is turned off elsewhere before queued cleanup runs,
        // so live identity reads no longer identify it.
        Hardware.fingerprints[2] = "0:0:0"
        service.restoreManagedDisplays()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 1 && service.managedDisabledIDs.isEmpty
                     && service.managedDisabledDisplays.isEmpty && UserDefaults.standard.stored.isEmpty
                     && service.deferredRestoration.ids.isEmpty,
                     "a replacement monitor is never enabled when it inherits a disabled display id, even across a connection gap")

        service = make()
        Hardware.lid = false
        service.commitDisplayToggle(BrightnessDisplay(id: 2, isActive: true), enabled: false)
        Hardware.fingerprints[2] = "3:3:3"
        service.recordDiscoveredTopology(online: [1, 2], active: [1, 2],
                                        fingerprints: [2: "3:3:3"])
        service.commitDisplayToggle(BrightnessDisplay(id: 2, isActive: true), enabled: false)
        DispatchQueue.main.drain()
        suite.expect(service.managedDisabledIDs == [2] && UserDefaults.standard.stored == [2]
                     && service.managedDisabledDisplays[2]?.restorationFingerprint == "3:3:3",
                     "queued replacement cleanup preserves a newer explicit disable of the new monitor")
        service.restoreManagedDisplays()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 3 && service.managedDisabledIDs.isEmpty,
                     "the new monitor can be restored when this app explicitly disabled it")

        service = make()
        Hardware.lid = false
        service.commitDisplayToggle(BrightnessDisplay(id: 2, isActive: true), enabled: false)
        Hardware.fingerprints[2] = "3:3:3"
        _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 1 && service.managedDisabledIDs.isEmpty
                     && UserDefaults.standard.stored.isEmpty,
                     "headless recovery rechecks physical identity before enabling a display")

        service = make()
        Hardware.lid = false
        Hardware.succeeds = false
        UserDefaults.standard.stored = [2]
        UserDefaults.standard.fingerprints = ["2": "2:2:2"]
        service.restoreDisplaysLeftOff()
        DispatchQueue.main.drain()
        let attemptsBeforeReplacement = Hardware.transactions
        Hardware.fingerprints[2] = "3:3:3"
        service.displaysWokeUp()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == attemptsBeforeReplacement
                     && service.managedDisabledIDs.isEmpty && service.managedDisabledDisplays.isEmpty
                     && service.deferredRestoration.ids.isEmpty && UserDefaults.standard.stored.isEmpty
                     && !service.wakeObserversInstalled,
                     "wake recovery discards replaced startup intent without configuring the new monitor")

        service = make()
        BrightnessService.rememberDisplaySwitchedOff(1, fingerprint: "1:1:1")
        BrightnessService.rememberDisplaySwitchedOff(2, fingerprint: "2:2:2")
        BrightnessService.rememberDisplaySwitchedOff(2, fingerprint: "3:3:3")
        suite.expect(UserDefaults.standard.stored == [1, 2]
                     && UserDefaults.standard.fingerprints == ["1": "1:1:1", "2": "3:3:3"],
                     "the legacy id list stays readable and a newer explicit disable updates its saved identity")
        BrightnessService.forgetDisplaySwitchedOff(2)
        suite.expect(UserDefaults.standard.stored == [1]
                     && UserDefaults.standard.fingerprints == ["1": "1:1:1"],
                     "forgetting one recovery preserves another monitor's record and identity")
        BrightnessService.forgetDisplaySwitchedOff(1)
        suite.expect(UserDefaults.standard.stored.isEmpty && UserDefaults.standard.fingerprints.isEmpty,
                     "successful recovery clears both machine repair records")

        for returningFingerprint in ["2:2:2", "3:3:3"] {
            service = make()
            Hardware.lid = false
            service.commitDisplayToggle(BrightnessDisplay(id: 2, isActive: true), enabled: false)
            let savedDefaults = UserDefaults.standard
            service = make()
            UserDefaults.standard = savedDefaults
            Hardware.lid = false
            // An empty connection names no monitor and cannot be switched on.
            Hardware.fingerprints[2] = "0:0:0"
            Hardware.succeeds = false
            service.restoreDisplaysLeftOff()
            DispatchQueue.main.drain()
            suite.expect(service.managedDisabledDisplays[2]?.restorationFingerprint == "2:2:2"
                         && service.deferredRestoration.ids == [2] && UserDefaults.standard.stored == [2],
                         "relaunch with an absent monitor keeps its saved identity and recovery when switching it on fails")
            let attemptsWhileAbsent = Hardware.transactions
            Hardware.fingerprints[2] = returningFingerprint
            Hardware.succeeds = true
            service.displaysWokeUp()
            DispatchQueue.main.drain()
            suite.expect(Hardware.transactions == attemptsWhileAbsent + (returningFingerprint == "2:2:2" ? 1 : 0)
                         && service.managedDisabledIDs.isEmpty && service.managedDisabledDisplays.isEmpty
                         && service.deferredRestoration.ids.isEmpty && UserDefaults.standard.stored.isEmpty
                         && UserDefaults.standard.fingerprints.isEmpty && !service.wakeObserversInstalled,
                         "wake restores only the original monitor and retires a replacement without enabling it")
        }

        service = make()
        Hardware.lid = false
        Hardware.succeeds = false
        UserDefaults.standard.stored = [2]
        Hardware.fingerprints[2] = "0:0:0"
        service.restoreDisplaysLeftOff()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions > 0 && UserDefaults.standard.stored == [2]
                     && service.deferredRestoration.ids == [2]
                     && service.managedDisabledDisplays[2]?.restorationFingerprint == nil,
                     "a legacy record without an identity is still switched on by number and kept when that fails")
        let attemptsBeforeManual = Hardware.transactions
        Hardware.succeeds = true
        service.displays = [service.managedDisabledDisplays[2] ?? BrightnessDisplay(id: 2)]
        service.commitDisplayToggle(service.displays[0], enabled: true)
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == attemptsBeforeManual + 1 && service.managedDisabledIDs.isEmpty
                     && UserDefaults.standard.stored.isEmpty && UserDefaults.standard.fingerprints.isEmpty,
                     "a legacy external record still offers explicit power-on recovery")

        for headless in [false, true] {
            service = make()
            Hardware.lid = false
            service.commitDisplayToggle(BrightnessDisplay(id: 2, isActive: true), enabled: false)
            // A monitor that is off can read like an empty connection.
            Hardware.fingerprints[2] = "0:0:0"
            if headless {
                _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
            } else {
                service.restoreManagedDisplays()
            }
            DispatchQueue.main.drain()
            suite.expect(Hardware.transactions == 2 && service.managedDisabledIDs.isEmpty
                         && UserDefaults.standard.stored.isEmpty,
                         "a disabled monitor that reports no identity still comes back when display control stops, the app quits or no screen is left")
        }

        // CoreGraphics answers all ones for a number no display uses, such as
        // while a monitor's connection is down, and the unknown vendor for a
        // monitor IOKit cannot identify. Neither names another monitor.
        for unknown in ["4294967295:4294967295:4294967295", "1970170734:0:0"] {
            service = make()
            Hardware.lid = false
            service.commitDisplayToggle(BrightnessDisplay(id: 2, isActive: true), enabled: false)
            Hardware.fingerprints[2] = unknown
            Hardware.succeeds = false
            _ = service.restoreManagedDisplayIfHeadless(drawableDisplayIDs: [])
            DispatchQueue.main.drain()
            service.commitDisplayToggle(service.managedDisabledDisplays[2] ?? BrightnessDisplay(id: 2), enabled: true)
            DispatchQueue.main.drain()
            suite.expect(service.managedDisabledIDs == [2] && UserDefaults.standard.stored == [2]
                         && UserDefaults.standard.fingerprints == ["2": "2:2:2"],
                         "a display number that reads \(unknown) never retires the saved row and recovery")
        }

        // The built-in's number never passes to another monitor, so an odd
        // reading while it is off cannot retire its row or its recovery.
        service = make()
        Hardware.lid = false
        service.commitDisplayToggle(BrightnessDisplay(id: 1, isActive: true), enabled: false)
        Hardware.fingerprints[1] = "9:9:9"
        service.restoreManagedDisplays()
        DispatchQueue.main.drain()
        suite.expect(Hardware.transactions == 2 && service.managedDisabledIDs.isEmpty
                     && UserDefaults.standard.stored.isEmpty && UserDefaults.standard.fingerprints.isEmpty,
                     "the built-in display comes back even when it reads as another monitor while off")
    }
}
