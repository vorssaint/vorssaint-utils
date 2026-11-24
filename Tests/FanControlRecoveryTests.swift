// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the helper's session, watchdog and recovery methods against doubles.
/// It exercises session transitions without opening SMC or starting a timer.
enum FanControlRecoveryContract {
    enum ProcessInfo {
        static let processInfo = Clock()
        final class Clock {
            var systemUptime: TimeInterval = 100
            var thermalState: Foundation.ProcessInfo.ThermalState = .nominal
        }
    }

    typealias FanControlHardwareError = FanControlHardwareContract.FanControlHardwareError
    typealias FanControlIPC = FanControlResumeContract.FanControlIPC

    class FanControlHardware {
        var writeError: FanControlHardwareError?
        var restoreResults = [true]
        var updates: [Int] = []
        var restores = 0
        var checks = 0
        var isManual = true
        var controlIntact = true
        var temperatures = [FanControlTemperatureReading(source: .hottestSoC, celsius: 60)]
        var gpuPoweredDown = false

        func validateAutomaticControl() throws {
            if isManual { throw FanControlHardwareError.alreadyControlled }
        }

        func startCooling(level: Int) throws -> [FanControlFanReading] {
            try updateCooling(level: level)
        }

        func updateCooling(level: Int) throws -> [FanControlFanReading] {
            try holdCooling(level: level)
            return []
        }

        func holdCooling(level: Int) throws {
            updates.append(level)
            if let writeError { throw writeError }
            isManual = true
            controlIntact = true
        }

        func restoreAutomatic() -> Bool {
            restores += 1
            let succeeded = restoreResults.count > 1 ? restoreResults.removeFirst() : restoreResults[0]
            if succeeded { isManual = false }
            return succeeded
        }

        func coolingIsIntact() -> Bool {
            checks += 1
            return controlIntact
        }

        func readTemperatures() -> FanControlTemperatureSample {
            FanControlTemperatureSample(readings: temperatures, gpuPoweredDown: gpuPoweredDown)
        }

        func snapshot(isCooling: Bool, endsAt: Date?, stopReason: FanControlStopReason?,
                      coolingLevel: Int?, configuration: FanControlConfiguration?) throws -> FanControlSnapshot {
            FanControlSnapshot(fans: [], isCooling: isCooling, endsAt: endsAt, stopReason: stopReason,
                               coolingLevel: coolingLevel, configuration: configuration,
                               temperatures: temperatures, gpuPoweredDown: gpuPoweredDown)
        }
    }

    final class Ownership {
        final class Machine {
            var holder: ObjectIdentifier?
            var marker = true
            var directoryChange = 0
            var launchDirectoryChange = 0
            var generation: UUID?
            var removalID: UUID
            var recordedRemoval: UUID
            var permitsLaunch = false
            var canRecord = true
            init() {
                let stamp = UUID()
                removalID = stamp
                recordedRemoval = stamp
            }
        }
        var machine = Machine()
        var isHeld: Bool {
            get { machine.holder == ObjectIdentifier(self) }
            set {
                if newValue { machine.holder = ObjectIdentifier(self) }
                else if isHeld { machine.holder = nil }
            }
        }
        var marker: Bool {
            get { machine.marker }
            set {
                if machine.marker != newValue { machine.directoryChange += 1 }
                machine.marker = newValue
            }
        }
        var canRemoveMarker = true
        init() { isHeld = true }
        func acquire() -> Bool {
            guard isHeld || machine.holder == nil else { return false }
            isHeld = true
            return true
        }
        func resumeEpoch() -> FanControlResumeEpoch? {
            guard isHeld, machine.canRecord, let id = machine.generation,
                  machine.recordedRemoval == machine.removalID else { return nil }
            return FanControlResumeEpoch(id: id,
                                         permitsLaunch: machine.permitsLaunch && machine.directoryChange == machine.launchDirectoryChange,
                                         removalID: machine.removalID, directorySeconds: 0,
                                         directoryNanoseconds: machine.directoryChange)
        }
        func rotateResumeEpoch(permitsLaunch: Bool, expectedRemovalID: UUID? = nil,
                               sessionID: UUID = UUID()) -> FanControlResumeEpoch? {
            guard isHeld, machine.canRecord else { return nil }
            machine.generation = sessionID
            machine.recordedRemoval = machine.removalID
            machine.launchDirectoryChange = machine.directoryChange
            machine.permitsLaunch = permitsLaunch && expectedRemovalID == machine.removalID
            return resumeEpoch()
        }
        func markRemoval() -> Bool {
            machine.removalID = UUID()
            return true
        }
        func markerExists() -> Bool { marker }
        func createMarker() -> Bool {
            guard isHeld, !marker else { return false }
            marker = true
            return true
        }
        func removeMarker() -> Bool {
            if canRemoveMarker { marker = false }
            return canRemoveMarker
        }
        func release() { isHeld = false }
    }

    final class Timer {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    final class Queue {
        private(set) var scheduledExits = 0
        func async(_ work: () -> Void) { work() }
        func asyncAfter(deadline: DispatchTime, execute work: @escaping () -> Void) {
            scheduledExits += 1 // Observe scheduling without exiting the test process.
        }
    }

    /// Accepts the helper's `Logger` interpolations, privacy included, and
    /// keeps the rendered text so a test can read why a session ended.
    struct LogMessage: ExpressibleByStringInterpolation {
        enum Privacy { case `public`, `private` }
        struct StringInterpolation: StringInterpolationProtocol {
            var text = ""
            init(literalCapacity: Int, interpolationCount: Int) {}
            mutating func appendLiteral(_ literal: String) { text += literal }
            mutating func appendInterpolation<Value>(_ value: Value, privacy: Privacy = .private) {
                text += "\(value)"
            }
        }
        let text: String
        init(stringLiteral value: String) { text = value }
        init(stringInterpolation: StringInterpolation) { text = stringInterpolation.text }
    }

    final class Log {
        var notices: [String] = []
        var errors: [String] = []
        func info(_ message: LogMessage) {}
        func notice(_ message: LogMessage) { notices.append(message.text) }
        func error(_ message: LogMessage) { errors.append(message.text) }
    }

    class Fixture {
        let queue = Queue()
        var connectionCount = 0
        var idleGeneration = 0
        let log = Log()
        let ownership = Ownership()
        var hardware: FanControlHardware? = FanControlHardware()
        var owner: UUID? = UUID()
        var isCooling = true
        var isRecovering = false
        var endsAt: Date?
        var endsAtUptime: TimeInterval?
        var lastHeartbeatUptime: TimeInterval = 100
        var verificationFailures = 0
        var temperatureFailures = 0
        var lastStopReason: FanControlStopReason?
        var lastStoppedOwner: UUID?
        var sessionStops: [UUID: FanControlSessionStop] = [:]
        var resumeGrants: [UUID: FanControlResumeGrant] = [:]
        var resumableStopEpoch: FanControlResumeEpoch?
        var controllingEpoch: FanControlResumeEpoch?
        var pendingRelaunchEpoch: FanControlResumeEpoch?
        var externalControlEpochID: UUID?
        var coolingLevel: Int? = 0
        var activeConfiguration: FanControlConfiguration? = .curve([.init(
            sensor: .hottestSoC,
            points: [.init(temperature: 40, coolingLevel: 0),
                     .init(temperature: 80, coolingLevel: 100)]
        )])
        var timer: Timer? = Timer()
        init(idle: Bool = false) {
            if idle {
                hardware = nil
                owner = nil
                isCooling = false
                coolingLevel = nil
                activeConfiguration = nil
                ownership.isHeld = false
                ownership.marker = false
                timer = nil
            } else {
                controllingEpoch = ownership.rotateResumeEpoch(permitsLaunch: false)
            }
        }
        func openHardware() -> FanControlHardware? {
            let hardware = FanControlHardware()
            hardware.isManual = false
            return hardware
        }
        func startWatchdog() {
            if timer == nil { timer = Timer() }
        }
    }

    /// Ticks until the verification tolerance is spent.
    private static func exhaustTolerance(_ controller: Controller) {
        for _ in 0..<FanControlPolicy.verificationFailureLimit { controller.watchdogTick() }
    }

    private static func readReply(_ operation: (@escaping (Data) -> Void) -> Void) -> FanControlResponse? {
        var response: FanControlResponse?
        operation { response = FanControlIPC.decode($0) }
        return response
    }

    private static func release(_ controller: Controller, from id: UUID) -> FanControlResponse? {
        readReply { controller.releaseControl(session: id, reply: $0) }
    }

    private static func connectionOwnership(_ suite: TestSuite) {
        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        guard let encoded = FanControlIPC.encode(curve) else {
            suite.expect(false, "the ownership test curve must be encodable")
            return
        }
        let clock = ProcessInfo.processInfo
        let initialUptime = clock.systemUptime
        defer { clock.systemUptime = initialUptime }
        let restarted = Controller(idle: true)
        let idleReply = release(restarted, from: UUID())
        suite.expect(idleReply?.error == .controlFailed && idleReply?.snapshot.stopReason == nil
                        && idleReply?.sessionStop == nil
                        && idleReply?.supportsSessionRelease == true && restarted.hardware == nil,
                     "a fresh idle helper cannot confirm a release requested on a former connection")
        let legacySession = FanControlSession(controller: restarted)
        suite.expect(readReply(legacySession.restoreAutomatic)?.succeeded == true,
                     "an old client can still confirm automatic control with an idle helper")
        let legacy = FanControlIPC.decode(Data(#"{"succeeded":true,"snapshot":{"fans":[],"isCooling":false}}"#.utf8))
        suite.expect(legacy?.succeeded == true && legacy?.supportsSessionRelease == nil
                        && legacy?.isRecovering == nil && legacy?.sessionStop == nil,
                     "an older helper reply decodes without advertising session release")

        for firstReadIsStatus in [false, true] {
            let controller = Controller(idle: true)
            let first = FanControlSession(controller: controller)
            let second = FanControlSession(controller: controller)
            let observer = FanControlSession(controller: controller)
            _ = readReply { first.applyConfiguration(encoded, withReply: $0) }
            controller.hardware?.controlIntact = false
            controller.hardware?.writeError = .unsafeControlState
            controller.watchdogTick()
            suite.expect(!controller.isCooling && controller.lastStopReason == .hardwareChanged,
                         "the first owner loses its curve to hardware protection before observing the stop")
            _ = readReply { second.applyConfiguration(encoded, withReply: $0) }
            if firstReadIsStatus {
                let stillActive = readReply(first.status)
                suite.expect(stillActive?.snapshot.isCooling == true && stillActive?.snapshot.configuration == curve
                                && stillActive?.sessionStop?.reason == .hardwareChanged && stillActive?.sessionStop?.restored == true,
                             "the first owner's receipt identifies its stopped session even while the same curve runs for its successor")
            }
            clock.systemUptime += FanControlPolicy.heartbeatLimit + 1
            controller.watchdogTick()
            let firstRead = readReply(firstReadIsStatus ? first.status : first.heartbeat)
            let secondRead = readReply(second.status)
            let panel = readReply(observer.status)
            suite.expect(firstRead?.snapshot.stopReason == .heartbeatLost && firstRead?.sessionStop?.reason == .hardwareChanged
                            && firstRead?.sessionStop?.restored == true && secondRead?.sessionStop?.reason == .heartbeatLost
                            && secondRead?.sessionStop?.restored == true && panel?.snapshot.stopReason == .heartbeatLost
                            && panel?.sessionStop == nil && controller.hardware?.restores == 1,
                         "status and heartbeat show the latest telemetry but attribute each completed stop only to its owner")
            let reapplied = readReply { first.applyConfiguration(encoded, withReply: $0) }
            suite.expect(reapplied?.succeeded == true && reapplied?.sessionStop == nil && readReply(first.status)?.sessionStop == nil,
                         "starting a new curve on the same connection discards its previous stop receipt")
        }

        for firstReadIsStatus in [false, true] {
            let controller = Controller(idle: true)
            let owner = FanControlSession(controller: controller)
            let observer = FanControlSession(controller: controller)
            _ = readReply { owner.applyConfiguration(encoded, withReply: $0) }
            controller.hardware?.restoreResults = [false, true]
            let failed = readReply(owner.releaseControl)
            suite.expect(failed?.error == .controlFailed && failed?.sessionStop?.restored == false
                            && failed?.sessionStop?.reason == nil && failed?.isRecovering == true,
                         "a failed voluntary release leaves its owner a pending receipt with no stop reason")
            controller.watchdogTick()
            let foreign = readReply(observer.status)
            let confirmed = readReply(firstReadIsStatus ? owner.status : owner.heartbeat)
            let duplicate = readReply(owner.status)
            suite.expect(foreign?.succeeded == true && foreign?.sessionStop == nil
                            && confirmed?.succeeded == true && confirmed?.sessionStop?.restored == true
                            && confirmed?.sessionStop?.reason == nil && confirmed?.isRecovering == false
                            && duplicate?.sessionStop == nil && readReply(owner.releaseControl)?.error == .controlFailed
                            && controller.hardware?.restores == 2 && !controller.ownership.marker,
                         "only the releasing owner can consume the watchdog's voluntary completion once on the same helper")
        }

        let removing = Controller(idle: true)
        let sleeper = FanControlSession(controller: removing)
        let uninstaller = FanControlSession(controller: removing)
        _ = readReply { sleeper.applyConfiguration(encoded, withReply: $0) }
        removing.hardware?.restoreResults = [false, true]
        let pending = readReply(sleeper.releaseControl)
        let removed = readReply(uninstaller.restoreForRemoval)
        let observed = readReply(sleeper.status)
        suite.expect(pending?.sessionStop?.restored == false && removed?.succeeded == true && observed?.succeeded == true
                        && observed?.sessionStop == nil && removing.hardware?.restores == 2 && !removing.ownership.marker,
                     "complete removal supersedes the sleeping owner's pending receipt before confirming automatic control")

        enum SessionEnd { case disconnect, ownedRelease, legacyRestore, heartbeatLoss, removalAfterHeartbeatLoss }
        for ending: SessionEnd in [.disconnect, .ownedRelease, .legacyRestore, .heartbeatLoss, .removalAfterHeartbeatLoss] {
            let controller = Controller(idle: true)
            let first = FanControlSession(controller: controller)
            let second = FanControlSession(controller: controller)
            let owner = first.id
            let other = second.id
            controller.connectionOpened()
            controller.connectionOpened()
            func apply(from session: FanControlSession) -> FanControlResponse? {
                readReply { session.applyConfiguration(encoded, withReply: $0) }
            }
            let started = apply(from: first)
            let initialWrites = controller.hardware?.updates
            suite.expect(started?.succeeded == true && started?.supportsSessionRelease == true
                            && started?.snapshot.configuration == curve
                            && controller.owner == owner && controller.ownership.marker
                            && controller.hardware?.isManual == true && initialWrites?.count == 1,
                         "the first accepted curve gives the applying connection ownership")

            if ending == .heartbeatLoss || ending == .removalAfterHeartbeatLoss {
                clock.systemUptime += FanControlPolicy.heartbeatLimit + 1
                controller.watchdogTick()
                suite.expect(controller.owner == nil && controller.lastStopReason == .heartbeatLost
                                && controller.hardware?.isManual == false && controller.hardware?.restores == 1,
                             "the watchdog releases the first owner's curve before either connection closes")
                let stopped = release(controller, from: owner)
                suite.expect(stopped?.succeeded == true && stopped?.snapshot.stopReason == .heartbeatLost
                                && release(controller, from: other)?.error == .alreadyControlled
                                && controller.hardware?.restores == 1,
                             "only the original owner can confirm its heartbeat loss without another restore")
                let next = apply(from: second)
                let late = readReply(first.releaseControl)
                let legacy = readReply(first.restoreAutomatic)
                controller.connectionClosed(owner)
                suite.expect(next?.succeeded == true && next?.snapshot.configuration == curve
                                && late?.error == .alreadyControlled && late?.snapshot == next?.snapshot
                                && legacy?.error == .alreadyControlled && legacy?.snapshot == next?.snapshot
                                && controller.isCooling && controller.owner == other && controller.ownership.marker
                                && controller.hardware?.isManual == true && controller.hardware?.restores == 0,
                             "both release selectors and a late close from the first owner preserve its successor's curve")
                if ending == .removalAfterHeartbeatLoss {
                    let remover = FanControlSession(controller: controller)
                    controller.connectionOpened()
                    let removed = readReply(remover.restoreForRemoval)
                    suite.expect(removed?.succeeded == true && removed?.snapshot.isCooling == false
                                    && !controller.isCooling && controller.hardware?.restores == 1,
                                 "complete removal from a third connection restores the live owner's fans")
                    controller.connectionClosed(remover.id)
                }
                controller.connectionClosed(other)
                suite.expect(controller.owner == nil && !controller.isCooling && !controller.ownership.marker
                                && controller.lastStopReason == (ending == .heartbeatLoss ? .appDisconnected : nil)
                                && controller.hardware?.restores == 1
                                && controller.hardware?.isManual == false,
                             "the new owner's disconnect or complete removal restores automatic control once")
                continue
            }

            let heartbeat = controller.lastHeartbeatUptime
            clock.systemUptime += 1
            let refused = apply(from: second)
            let system = FanControlConfiguration(mode: .system, manualLevel: 0, curves: [])
            let refusedSystem = controller.applyConfiguration(session: other, configuration: system, duration: nil)
            suite.expect(refused?.error == .alreadyControlled && refused?.supportsSessionRelease == true
                            && refusedSystem.error == .alreadyControlled && refused?.snapshot == started?.snapshot
                            && controller.owner == owner && controller.lastHeartbeatUptime == heartbeat
                            && controller.hardware?.updates == initialWrites && controller.hardware?.restores == 0,
                         "an identical curve from another connection cannot take ownership, renew it or write the fans")
            controller.connectionClosed(other)
            suite.expect(controller.owner == owner && controller.isCooling && controller.ownership.marker
                            && controller.hardware?.restores == 0,
                         "disconnecting the refused connection leaves the owner's curve running")

            if ending == .ownedRelease {
                let released = readReply(first.releaseControl)
                suite.expect(released?.succeeded == true && released?.snapshot.isCooling == false
                                && released?.snapshot.stopReason == nil && controller.hardware?.restores == 1,
                             "only a release performed for the active owner confirms a stop without a reason")
                suite.expect(release(controller, from: owner)?.error == .controlFailed,
                             "a repeated idle release cannot manufacture a second acknowledgement")
            } else if ending == .legacyRestore {
                let response = readReply(first.restoreAutomatic)
                suite.expect(response?.succeeded == true && response?.snapshot.isCooling == false
                                && controller.owner == nil && controller.hardware?.isManual == false,
                             "the legacy restore selector still releases its own active session")
            }
            controller.connectionClosed(owner)
            suite.expect(!controller.isCooling && controller.owner == nil && !controller.ownership.marker
                            && controller.hardware?.isManual == false && controller.hardware?.restores == 1
                            && controller.lastStopReason == (ending == .disconnect ? .appDisconnected : nil),
                         "owner disconnect and both owner release selectors return the fans to the system once")
        }
    }

    private static func conditionalResume(_ suite: TestSuite) {
        let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])
        guard let encoded = FanControlIPC.encode(curve) else {
            suite.expect(false, "the conditional resume fixture requires an encodable curve")
            return
        }
        func apply(_ session: FanControlSession) -> FanControlResponse? {
            readReply { session.applyConfiguration(encoded, withReply: $0) }
        }
        func resume(_ session: FanControlSession, _ token: UUID) -> FanControlResponse? {
            readReply { session.resumeConfiguration(encoded, authorization: token as NSUUID, withReply: $0) }
        }
        func loseHeartbeat(_ controller: Controller) {
            controller.lastHeartbeatUptime -= FanControlPolicy.heartbeatLimit + 1
            controller.watchdogTick()
        }
        func peer(of controller: Controller) -> Controller {
            let peer = Controller(idle: true)
            peer.ownership.machine = controller.ownership.machine
            return peer
        }

        let controller = Controller(idle: true)
        let owner = FanControlSession(controller: controller)
        let observer = FanControlSession(controller: controller)
        let fresh = readReply(observer.status)
        suite.expect(fresh?.succeeded == true && fresh?.resumeAuthorization == nil && fresh?.resumeSessionID == nil,
                     "fresh telemetry from a helper with no accepted session cannot authorize an old saved curve")
        guard let firstID = apply(owner)?.resumeSessionID else {
            suite.expect(false, "an accepted write must bind the saved curve to its session")
            return
        }
        suite.expect(readReply(owner.heartbeat)?.resumeSessionID == firstID && readReply(observer.status)?.resumeSessionID == nil,
                     "only the active owner sees its configuration's session ID")
        loseHeartbeat(controller)
        let stopped = readReply(owner.status)
        guard let token = stopped?.resumeAuthorization else {
            suite.expect(false, "a confirmed heartbeat stop must authorize its owner to resume")
            return
        }
        suite.expect(stopped?.sessionStop?.reason == .heartbeatLost && readReply(owner.status)?.resumeAuthorization == token
                        && resume(observer, token)?.error == .alreadyControlled && !controller.isCooling,
                     "duplicate idle status preserves the same ticket and another connection cannot spend it")
        let restarted = peer(of: controller)
        suite.expect(resume(FanControlSession(controller: restarted), token)?.error == .alreadyControlled,
                     "the former helper's in-flight ticket is unusable after reconnecting to another helper")
        let accepted = resume(owner, token)
        suite.expect(accepted?.succeeded == true && accepted?.resumeSessionID != nil && accepted?.resumeSessionID != firstID
                        && resume(owner, token)?.error == .alreadyControlled && controller.hardware?.updates.count == 1,
                     "one conditional write starts a new session and a duplicate cannot reapply the curve")
        controller.connectionClosed(owner.id)
        let launch = FanControlSession(controller: restarted)
        let relaunch = readReply(launch.status)
        suite.expect(relaunch?.resumeAuthorization != nil && relaunch?.resumeSessionID == accepted?.resumeSessionID
                        && relaunch?.resumeSessionID != firstID,
                     "the confirmed disconnect preserves only the latest accepted session ID across helper processes")
        restarted.ownership.machine.directoryChange += 1
        let afterLegacy = readReply(FanControlSession(controller: restarted).status)
        suite.expect(afterLegacy?.succeeded == true && afterLegacy?.resumeAuthorization == nil && afterLegacy?.resumeSessionID == nil,
                     "a legacy owner cycling its marker invalidates the saved session even for a newly opened connection")

        let edited = Controller(idle: true)
        let editor = FanControlSession(controller: edited)
        let original = apply(editor)?.resumeSessionID
        if let changed = FanControlIPC.encode(FanControlConfiguration.manual(level: 60)) {
            let updated = readReply { editor.applyConfiguration(changed, withReply: $0) }
            edited.connectionClosed(editor.id)
            let latest = readReply(FanControlSession(controller: edited).status)
            suite.expect(original != nil && updated?.resumeSessionID != nil && updated?.resumeSessionID != original
                            && latest?.resumeSessionID == updated?.resumeSessionID && latest?.resumeAuthorization != nil,
                         "a lost acknowledgement for an active edit cannot authorize the previous saved configuration on relaunch")
        }

        for independent in [false, true] {
            for readBeforeProtection in [false, true] {
                let a = Controller(idle: true)
                let b = independent ? peer(of: a) : a
                let old = FanControlSession(controller: a)
                let next = FanControlSession(controller: b)
                _ = apply(old)
                loseHeartbeat(a)
                let cached = readBeforeProtection ? readReply(old.status)?.resumeAuthorization : nil
                _ = apply(next)
                b.hardware?.controlIntact = false
                b.verificationFailures = FanControlPolicy.verificationFailureLimit - 1
                loseHeartbeat(b)
                let protection = readReply(next.status)
                let stale = readReply(old.status)
                suite.expect(protection?.sessionStop?.reason == .hardwareChanged && protection?.resumeAuthorization == nil
                                && stale?.sessionStop == nil && stale?.resumeAuthorization == nil && !b.ownership.marker,
                             "the successor's physical protection overrides its simultaneous heartbeat loss and revokes any prior receipt")
                if readBeforeProtection {
                    suite.expect(cached.map { resume(old, $0)?.error == .alreadyControlled } == true
                                    && !a.isCooling && a.hardware?.isManual == false,
                                 "an already-delivered ticket is checked against the shared generation before any fan write")
                }
            }
        }

        for independent in [false, true] {
            let a = Controller(idle: true)
            let b = independent ? peer(of: a) : a
            let sleeper = FanControlSession(controller: a)
            let remover = FanControlSession(controller: b)
            _ = apply(sleeper)
            a.hardware?.restoreResults = [false, true]
            suite.expect(readReply(sleeper.releaseControl)?.isRecovering == true, "the owner is recovering its failed sleep handoff")
            let removal = readReply(remover.restoreForRemoval)
            suite.expect(removal?.succeeded == !independent,
                         "only the helper holding the hardware lock can acknowledge the global restore")
            if independent { a.watchdogTick() }
            let completion = readReply(sleeper.status)
            suite.expect(completion?.succeeded == true && completion?.resumeAuthorization == nil && completion?.sessionStop == nil
                            && !a.ownership.marker && a.hardware?.isManual == false,
                         "even a contended removal revokes a pending handoff before its watchdog completes")

            _ = apply(sleeper)
            loseHeartbeat(a)
            let ticket = readReply(sleeper.heartbeat)?.resumeAuthorization
            let completed = readReply(remover.restoreForRemoval)
            suite.expect(completed?.succeeded == true && ticket.map { resume(sleeper, $0)?.error == .alreadyControlled } == true
                            && readReply(sleeper.status)?.resumeAuthorization == nil && !a.isCooling,
                         "full removal invalidates an already-delivered heartbeat ticket across connections and helpers")
        }
        let unsupportedRecord = Controller(idle: true)
        unsupportedRecord.ownership.machine.canRecord = false
        let explicit = FanControlSession(controller: unsupportedRecord)
        let manual = apply(explicit)
        loseHeartbeat(unsupportedRecord)
        suite.expect(manual?.succeeded == true && manual?.resumeSessionID == nil && readReply(explicit.status)?.resumeAuthorization == nil,
                     "manual control remains available when a trustworthy authority record cannot be written")
    }

    static func run(_ suite: TestSuite) {
        connectionOwnership(suite)
        conditionalResume(suite)
        let healthy = Controller()
        let healthyOwner = healthy.owner
        healthy.watchdogTick()
        suite.expect(healthy.hardware?.updates == [50] && healthy.coolingLevel == 50
                        && healthy.isCooling && !healthy.isRecovering
                        && healthy.owner == healthyOwner && healthy.ownership.marker
                        && healthy.hardware?.restores == 0 && healthy.timer != nil,
                     "a successful curve write keeps the active session and ownership")
        healthy.watchdogTick()
        suite.expect(healthy.hardware?.updates == [50] && healthy.hardware?.checks == 2,
                     "an unchanged curve level verifies control without rewriting the fans")

        let transientWrite = Controller()
        transientWrite.hardware?.writeError = .operationFailed
        transientWrite.watchdogTick()
        suite.expect(transientWrite.isCooling && transientWrite.hardware?.restores == 0
                        && transientWrite.verificationFailures == 1
                        && transientWrite.coolingLevel == 0 && transientWrite.ownership.marker,
                     "one refused curve write keeps the session at its last manual level")
        transientWrite.hardware?.writeError = nil
        transientWrite.watchdogTick()
        suite.expect(transientWrite.isCooling && transientWrite.hardware?.updates == [50, 50]
                        && transientWrite.coolingLevel == 50
                        && transientWrite.verificationFailures == 0
                        && transientWrite.hardware?.restores == 0,
                     "the next tick retries the curve level and clears the failure")

        let failed = Controller()
        failed.hardware?.writeError = .operationFailed
        failed.endsAt = .distantFuture
        failed.endsAtUptime = 200
        let failedTimer = failed.timer
        exhaustTolerance(failed)
        suite.expect(failed.hardware?.updates == [50, 50, 50] && failed.hardware?.restores == 1
                        && failed.hardware?.isManual == false && !failed.isCooling
                        && !failed.isRecovering && failed.owner == nil
                        && failed.activeConfiguration == nil && failed.coolingLevel == nil
                        && failed.endsAt == nil && failed.endsAtUptime == nil
                        && !failed.ownership.marker && !failed.ownership.isHeld
                        && failed.lastStopReason == .hardwareChanged
                        && failedTimer?.cancelled == true && failed.timer == nil,
                     "curve writes refused through the whole tolerance restore firmware control and clear the session")
        suite.expect(failed.log.notices.last?.hasSuffix("hardwareChanged") == true
                        && failed.log.errors.count == FanControlPolicy.verificationFailureLimit,
                     "each refused write and the reason the session ended reach the log")
        failed.hardware?.writeError = nil
        failed.watchdogTick()
        suite.expect(failed.hardware?.updates == [50, 50, 50] && failed.hardware?.restores == 1,
                     "a later tick cannot restart manual control after a failed curve write")

        let reclaimed = Controller()
        reclaimed.activeConfiguration = .manual(level: 50)
        reclaimed.coolingLevel = 50
        reclaimed.hardware?.controlIntact = false
        reclaimed.watchdogTick()
        suite.expect(reclaimed.isCooling && reclaimed.hardware?.updates == [50]
                        && reclaimed.verificationFailures == 1
                        && reclaimed.hardware?.restores == 0,
                     "a single lost manual target is reasserted within the failure limit")
        reclaimed.watchdogTick()
        suite.expect(reclaimed.verificationFailures == 0 && reclaimed.hardware?.updates == [50],
                     "a later tick that finds the target intact clears the reclaim")

        let reclaimedCurve = Controller()
        reclaimedCurve.coolingLevel = 50
        reclaimedCurve.hardware?.controlIntact = false
        reclaimedCurve.watchdogTick()
        suite.expect(reclaimedCurve.isCooling && reclaimedCurve.hardware?.updates == [50]
                        && reclaimedCurve.verificationFailures == 1,
                     "an unchanged curve level is written again once the firmware takes it back")

        for levelChanges in [false, true] {
            let contested = Controller()
            contested.coolingLevel = 50
            for tick in 0..<FanControlPolicy.verificationFailureLimit {
                contested.hardware?.controlIntact = false
                if levelChanges && tick == 1 {
                    contested.hardware?.temperatures = [.init(source: .hottestSoC, celsius: 80)]
                }
                contested.watchdogTick()
            }
            suite.expect(!contested.isCooling && contested.lastStopReason == .hardwareChanged
                            && contested.hardware?.restores == 1
                            && contested.hardware?.updates == (levelChanges ? [50, 100] : [50, 50]),
                         "consecutive firmware reclaims return control before another write, even across a curve change")
        }
        let changing = Controller()
        for celsius in [60.0, 80, 35, 60] {
            changing.hardware?.temperatures = [.init(source: .hottestSoC, celsius: celsius)]
            changing.watchdogTick()
        }
        suite.expect(changing.isCooling && changing.hardware?.updates == [50, 100, 0, 50]
                        && changing.verificationFailures == 0,
                     "legitimate curve changes on intact fans do not consume the failure limit")

        let unsafe = Controller()
        unsafe.hardware?.writeError = .unsafeControlState
        unsafe.watchdogTick()
        suite.expect(!unsafe.isCooling && unsafe.hardware?.restores == 1
                        && unsafe.hardware?.updates == [50] && unsafe.lastStopReason == .hardwareChanged,
                     "a partially applied or unverified write restores automatic control on the first tick")

        let blindCurve = Controller()
        blindCurve.coolingLevel = 50
        blindCurve.hardware?.temperatures = []
        for tick in 1..<FanControlPolicy.temperatureFailureLimit {
            blindCurve.watchdogTick()
            suite.expect(blindCurve.isCooling && blindCurve.coolingLevel == 50
                            && blindCurve.temperatureFailures == tick
                            && blindCurve.hardware?.updates.isEmpty == true && blindCurve.hardware?.restores == 0,
                         "missing samples leave verified fan targets in place during the temperature tolerance")
        }
        blindCurve.hardware?.temperatures = [.init(source: .hottestSoC, celsius: 80)]
        blindCurve.watchdogTick()
        suite.expect(blindCurve.isCooling && blindCurve.coolingLevel == 100
                        && blindCurve.temperatureFailures == 0 && blindCurve.hardware?.updates == [100],
                     "a fresh sample before the limit lets the curve follow the current temperature again")

        let stopReasons: [FanControlStopReason] = [.heartbeatLost, .timeLimit, .thermalPressure,
                                                   .temperatureUnavailable]
        for reason in stopReasons {
            let stopping = Controller()
            stopping.hardware?.controlIntact = false
            switch reason {
            case .heartbeatLost:
                stopping.lastHeartbeatUptime -= FanControlPolicy.heartbeatLimit + 1
            case .timeLimit:
                stopping.endsAt = .distantFuture
                stopping.endsAtUptime = ProcessInfo.processInfo.systemUptime
            case .thermalPressure:
                ProcessInfo.processInfo.thermalState = .serious
            case .temperatureUnavailable:
                stopping.hardware?.temperatures = []
                stopping.temperatureFailures = FanControlPolicy.temperatureFailureLimit - 1
            default:
                break
            }
            stopping.watchdogTick()
            ProcessInfo.processInfo.thermalState = .nominal
            suite.expect(stopping.lastStopReason == reason && !stopping.isCooling
                            && stopping.hardware?.updates.isEmpty == true && stopping.hardware?.restores == 1,
                         "\(reason.rawValue) stops a session before the watchdog can reassert manual control")
        }

        let recovering = Controller()
        let protectedOwner = UUID()
        recovering.owner = protectedOwner
        recovering.hardware?.writeError = .operationFailed
        recovering.hardware?.restoreResults = [false, false, true]
        exhaustTolerance(recovering)
        let unconfirmed = release(recovering, from: protectedOwner)
        suite.expect(unconfirmed?.error == .controlFailed && unconfirmed?.snapshot.stopReason == .hardwareChanged
                        && recovering.hardware?.restores == 1 && recovering.ownership.marker
                        && recovering.queue.scheduledExits == 0,
                     "a release during protection recovery only reports the outstanding restore")
        suite.expect(recovering.isRecovering && !recovering.isCooling
                        && recovering.owner == nil && recovering.activeConfiguration == nil
                        && recovering.coolingLevel == nil && recovering.ownership.isHeld
                        && recovering.ownership.marker && recovering.timer != nil
                        && recovering.lastStopReason == .hardwareChanged
                        && recovering.log.errors.last?.hasSuffix("hardwareChanged") == true,
                     "failed restoration retains the marker and watchdog but ends manual control ownership")
        recovering.hardware?.writeError = nil
        recovering.watchdogTick()
        suite.expect(recovering.hardware?.updates == [50, 50, 50] && recovering.hardware?.restores == 2
                        && recovering.isRecovering && recovering.ownership.marker && recovering.queue.scheduledExits == 0,
                     "recovery retries automatic mode without reapplying the curve")
        recovering.watchdogTick()
        suite.expect(recovering.hardware?.updates == [50, 50, 50] && recovering.hardware?.restores == 3
                        && recovering.hardware?.isManual == false && !recovering.isRecovering
                        && !recovering.ownership.marker && !recovering.ownership.isHeld
                        && recovering.timer == nil && recovering.queue.scheduledExits == 1
                        && recovering.lastStopReason == .hardwareChanged
                        && recovering.log.notices.last?.hasSuffix("hardwareChanged") == true,
                     "successful automatic recovery releases ownership and stops retrying")
        recovering.watchdogTick()
        suite.expect(recovering.hardware?.restores == 3 && recovering.hardware?.updates == [50, 50, 50]
                        && recovering.queue.scheduledExits == 1,
                     "an idle tick after recovery neither rewrites the fans nor schedules another exit")
        let confirmed = release(recovering, from: protectedOwner)
        suite.expect(confirmed?.succeeded == true && confirmed?.snapshot.stopReason == .hardwareChanged
                        && recovering.hardware?.restores == 3,
                     "the protected owner's later release acknowledges the hardware stop without changing it")
        recovering.ownership.marker = true
        suite.expect(release(recovering, from: protectedOwner)?.error == .alreadyControlled
                        && recovering.ownership.marker && !recovering.ownership.isHeld && recovering.hardware?.restores == 3,
                     "a session release leaves a later abandoned ownership marker for the helper's recovery path")

        let markerFailure = Controller()
        markerFailure.hardware?.temperatures = []
        markerFailure.ownership.canRemoveMarker = false
        for _ in 0..<FanControlPolicy.temperatureFailureLimit { markerFailure.watchdogTick() }
        suite.expect(markerFailure.hardware?.isManual == false && markerFailure.isRecovering
                        && !markerFailure.isCooling && markerFailure.ownership.marker,
                     "a failed marker removal stays in recovery even after the fans return to automatic")
        markerFailure.ownership.canRemoveMarker = true
        markerFailure.watchdogTick()
        suite.expect(markerFailure.hardware?.updates.isEmpty == true && !markerFailure.isRecovering
                        && !markerFailure.ownership.marker && markerFailure.lastStopReason == .temperatureUnavailable
                        && markerFailure.log.notices.last?.hasSuffix("temperatureUnavailable") == true,
                     "marker cleanup retries never restart the failed curve")

        let requested = Controller()
        let requestingOwner = UUID()
        requested.owner = requestingOwner
        requested.hardware?.restoreResults = [false, true]
        let failedRelease = release(requested, from: requestingOwner)
        suite.expect(failedRelease?.error == .controlFailed && failedRelease?.snapshot.stopReason == nil,
                     "a failed owner release cannot acknowledge automatic control")
        requested.watchdogTick()
        let completedRequest = release(requested, from: requestingOwner)
        suite.expect(completedRequest?.succeeded == true && completedRequest?.sessionStop?.restored == true
                        && completedRequest?.sessionStop?.reason == nil
                        && release(requested, from: requestingOwner)?.error == .controlFailed
                        && !requested.isRecovering && requested.lastStopReason == nil
                        && requested.log.notices.last?.hasSuffix("requested") == true,
                     "the scoped release can collect the owner's voluntary completion once after the watchdog restores the fans")

        let transientRead = Controller()
        transientRead.activeConfiguration = .manual(level: 50)
        transientRead.coolingLevel = 50
        transientRead.hardware?.controlIntact = false
        transientRead.hardware?.writeError = .operationFailed
        transientRead.watchdogTick()
        suite.expect(transientRead.isCooling && transientRead.verificationFailures == 1
                        && transientRead.hardware?.restores == 0,
                     "a lost target that cannot be written again retains the existing watchdog tolerance")
        transientRead.hardware?.controlIntact = true
        transientRead.hardware?.writeError = nil
        transientRead.watchdogTick()
        suite.expect(transientRead.isCooling && transientRead.verificationFailures == 0
                        && transientRead.hardware?.restores == 0,
                     "healthy verification clears a transient failure without stopping cooling")

        let gpu = Controller()
        gpu.activeConfiguration = .curve([.init(sensor: .hottestGPU, points: [
            .init(temperature: 25, coolingLevel: 35), .init(temperature: 60, coolingLevel: 100),
        ])])
        gpu.hardware?.temperatures = []
        gpu.hardware?.gpuPoweredDown = true
        for _ in 0...FanControlPolicy.temperatureFailureLimit { gpu.watchdogTick() }
        suite.expect(gpu.isCooling && gpu.coolingLevel == 35 && gpu.temperatureFailures == 0,
                     "verified GPU sleep keeps a GPU-only session running at its first curve point")
        gpu.hardware?.gpuPoweredDown = false
        gpu.hardware?.temperatures = [.init(source: .hottestGPU, celsius: 63)]
        gpu.watchdogTick()
        suite.expect(gpu.isCooling && gpu.coolingLevel == 100,
                     "the first real GPU reading after wake can immediately raise the fan target")
        gpu.hardware?.temperatures = []
        for _ in 0..<FanControlPolicy.temperatureFailureLimit { gpu.watchdogTick() }
        suite.expect(!gpu.isCooling && gpu.lastStopReason == .temperatureUnavailable,
                     "missing GPU readings without the sleep signature still end the session")
    }
}
