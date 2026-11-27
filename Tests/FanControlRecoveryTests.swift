// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the helper's production watchdog and recovery methods against doubles.
/// It exercises session transitions without opening SMC or starting a timer.
enum FanControlRecoveryContract {
    enum ProcessInfo {
        static let processInfo = Clock()
        final class Clock {
            let systemUptime: TimeInterval = 100
            var thermalState: Foundation.ProcessInfo.ThermalState = .nominal
        }
    }

    typealias FanControlHardwareError = FanControlHardwareContract.FanControlHardwareError

    class FanControlHardware {
        var writeError: FanControlHardwareError?
        var restoreResults = [true]
        var updates: [Int] = []
        var restores = 0
        var checks = 0
        var isManual = true
        var controlIntact = true
        var failNextRPMRead = false
        var snapshotError: FanControlHardwareError?
        var temperatures = [FanControlTemperatureReading(source: .hottestSoC, celsius: 60)]
        var gpuPoweredDown = false

        func validateAutomaticControl() throws {
            if isManual { throw FanControlHardwareError.alreadyControlled }
        }

        func startCooling(level: Int) throws -> [FanControlFanReading] {
            if writeError == .unsafeControlState { isManual = true }
            return try updateCooling(level: level)
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
            if let snapshotError { throw snapshotError }
            if failNextRPMRead {
                failNextRPMRead = false
                throw FanControlHardwareError.operationFailed
            }
            let fan = FanControlFanReading(index: 0, actualRPM: 1_800, minimumRPM: 1_200,
                                           maximumRPM: 5_800, targetRPM: 1_800, isManuallyControlled: isManual)
            return FanControlSnapshot(fans: [fan], isCooling: isCooling, endsAt: endsAt, stopReason: stopReason,
                                      coolingLevel: coolingLevel, configuration: configuration,
                                      temperatures: temperatures, gpuPoweredDown: gpuPoweredDown)
        }
    }

    final class Ownership {
        var isHeld = true
        var marker = true
        var canRemoveMarker = true
        var canAcquire = true
        func acquire() -> Bool {
            guard canAcquire else { return false }
            isHeld = true
            return true
        }
        func markerExists() -> Bool { marker }
        func createMarker() -> Bool { marker = true; return true }
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

    struct ImmediateQueue {
        func async(_ work: () -> Void) { work() }
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
        let log = Log()
        let queue = ImmediateQueue()
        var connectionCount = 1
        let ownership = Ownership()
        var hardware: FanControlHardware? = FanControlHardware()
        var owner: UUID? = UUID()
        var unregisterSession: UUID?
        var isCooling = true
        var isRecovering = false
        var endsAt: Date?
        var endsAtUptime: TimeInterval?
        var lastHeartbeatUptime: TimeInterval = 100
        var verificationFailures = 0
        var temperatureFailures = 0
        var lastStopReason: FanControlStopReason?
        var coolingLevel: Int? = 0
        var activeConfiguration: FanControlConfiguration? = .curve([.init(
            sensor: .hottestSoC,
            points: [.init(temperature: 40, coolingLevel: 0),
                     .init(temperature: 80, coolingLevel: 100)]
        )])
        var timer: Timer? = Timer()
        var exitChecks = 0
        func startWatchdog() {
            if timer == nil { timer = Timer() }
        }
        func scheduleExitIfIdle() { exitChecks += 1 }
    }

    /// Ticks until the verification tolerance is spent.
    private static func exhaustTolerance(_ controller: Controller) {
        for _ in 0..<FanControlPolicy.verificationFailureLimit { controller.watchdogTick() }
    }

    private static func checkRestoreCapability(_ suite: TestSuite) {
        struct LegacyResponse: Decodable {
            let succeeded: Bool
            let snapshot: FanControlSnapshot
            let error: FanControlErrorCode?
        }

        let legacyData = Data(#"{"succeeded":true,"snapshot":{"fans":[],"isCooling":true}}"#.utf8)
        let fromLegacyHelper = FanControlIPC.decode(legacyData)
        suite.expect(fromLegacyHelper?.snapshot.isCooling == true && fromLegacyHelper?.supportsOwnedRestore == nil
                        && fromLegacyHelper?.localStopReason == nil,
                     "an active reply from an older helper grants no owner-checked restore")

        let controller = Controller()
        let owner = UUID()
        controller.owner = owner
        let accepted = controller.applyConfiguration(session: owner, configuration: .manual(level: 65), duration: nil)
        let data = FanControlIPC.encode(accepted)
        let legacyClient = try? JSONDecoder().decode(LegacyResponse.self, from: data)
        suite.expect(FanControlIPC.decode(data)?.supportsOwnedRestore == true && legacyClient?.succeeded == true
                        && legacyClient?.snapshot == accepted.snapshot && legacyClient?.error == nil,
                     "an accepted Apply advertises the owner check while older clients still decode the same result")
    }

    private static func checkApplyStopReason(_ suite: TestSuite) {
        let controller = Controller()
        let owner = UUID()
        controller.owner = owner
        controller.hardware?.writeError = .unsafeControlState
        let manual = FanControlConfiguration.manual(level: 65)
        let update = controller.applyConfiguration(session: owner, configuration: manual, duration: nil)
        suite.expect(update.error == .controlFailed && update.localStopReason == .hardwareChanged
                        && update.snapshot.stopReason == .hardwareChanged && !controller.isCooling,
                     "a failed update reports the stop it caused in its own session")

        controller.hardware?.restoreResults = [false]
        let start = controller.applyConfiguration(session: owner, configuration: manual, duration: nil)
        let other = controller.applyConfiguration(session: UUID(), configuration: manual, duration: nil)
        suite.expect(start.error == .controlFailed && start.snapshot.stopReason == .recovery
                        && start.localStopReason == .recovery && controller.isRecovering,
                     "a partial first write whose rollback fails reports its own recovery")
        suite.expect(other.error == .controlFailed && other.snapshot.stopReason == .recovery
                        && other.localStopReason == nil && controller.statusResponse().localStopReason == nil,
                     "an Apply during another client's recovery and a status read carry only the global reason")
    }

    static func run(_ suite: TestSuite) {
        checkRestoreCapability(suite)
        checkApplyStopReason(suite)
        for pendingMarker in [false, true] {
            let idle = Controller()
            idle.isCooling = false
            idle.owner = nil
            idle.ownership.isHeld = false
            idle.ownership.canAcquire = pendingMarker
            idle.ownership.marker = pendingMarker
            var error: FanControlErrorCode?
            idle.prepareForUnregister(session: UUID()) { error = FanControlIPC.decode($0)?.error }
            suite.expect(error == (pendingMarker ? .controlFailed : .alreadyControlled) && idle.unregisterSession == nil
                            && !idle.ownership.isHeld && idle.hardware?.restores == 0,
                         "a shared lock held elsewhere or an abandoned marker prevents a removal reservation without writes")
        }
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
        recovering.hardware?.writeError = .operationFailed
        recovering.hardware?.restoreResults = [false, false, true]
        exhaustTolerance(recovering)
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
                        && recovering.isRecovering && recovering.ownership.marker,
                     "recovery retries automatic mode without reapplying the curve")
        recovering.watchdogTick()
        suite.expect(recovering.hardware?.updates == [50, 50, 50] && recovering.hardware?.restores == 3
                        && recovering.hardware?.isManual == false && !recovering.isRecovering
                        && !recovering.ownership.marker && !recovering.ownership.isHeld
                        && recovering.timer == nil && recovering.exitChecks == 1
                        && recovering.lastStopReason == .hardwareChanged
                        && recovering.log.notices.last?.hasSuffix("hardwareChanged") == true,
                     "successful automatic recovery releases ownership and stops retrying")

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
        requested.hardware?.restoreResults = [false, true]
        _ = requested.performRestore(reason: nil)
        requested.watchdogTick()
        suite.expect(!requested.isRecovering && requested.lastStopReason == nil
                        && requested.log.notices.last?.hasSuffix("requested") == true,
                     "an explicit restore retains its requested reason across recovery")

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
