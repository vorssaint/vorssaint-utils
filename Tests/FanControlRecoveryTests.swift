// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the helper's production watchdog and recovery methods against doubles.
/// It exercises session transitions without opening SMC or starting a timer.
enum FanControlRecoveryContract {
    enum ProcessInfo {
        static let processInfo = Clock()
        struct Clock {
            let systemUptime: TimeInterval = 100
            let thermalState: Foundation.ProcessInfo.ThermalState = .nominal
        }
    }

    final class FanControlHardware {
        enum Failure: Error { case write }
        var failUpdate = false
        var restoreResults = [true]
        var updates: [Int] = []
        var restores = 0
        var checks = 0
        var isManual = true
        var controlIntact = true
        var temperatures = [FanControlTemperatureReading(source: .hottestSoC, celsius: 60)]

        func updateCooling(level: Int) throws -> [FanControlFanReading] {
            updates.append(level)
            if failUpdate { throw Failure.write }
            isManual = true
            return []
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

        func readTemperatures() -> [FanControlTemperatureReading] { temperatures }
    }

    final class Ownership {
        var isHeld = true
        var marker = true
        var canRemoveMarker = true
        func acquire() -> Bool { isHeld = true; return true }
        func markerExists() -> Bool { marker }
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

    struct Log {
        func notice(_ message: String) {}
        func error(_ message: String) {}
    }

    class Fixture {
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

    static func run(_ suite: TestSuite) {
        let healthy = Controller()
        let healthyOwner = healthy.owner
        healthy.watchdogTick()
        suite.expect(healthy.hardware?.updates == [50] && healthy.coolingLevel == 50
                        && healthy.isCooling && !healthy.isRecovering
                        && healthy.owner == healthyOwner && healthy.ownership.marker
                        && healthy.hardware?.restores == 0 && healthy.timer != nil,
                     "a successful curve write keeps the active session and ownership")
        healthy.watchdogTick()
        suite.expect(healthy.hardware?.updates == [50] && healthy.hardware?.checks == 1,
                     "an unchanged curve level verifies control without rewriting the fans")

        let failed = Controller()
        failed.hardware?.failUpdate = true
        failed.endsAt = Date(timeIntervalSince1970: 2_000)
        failed.endsAtUptime = 200
        let failedTimer = failed.timer
        failed.watchdogTick()
        suite.expect(failed.hardware?.updates == [50] && failed.hardware?.restores == 1
                        && failed.hardware?.isManual == false && !failed.isCooling
                        && !failed.isRecovering && failed.owner == nil
                        && failed.activeConfiguration == nil && failed.coolingLevel == nil
                        && failed.endsAt == nil && failed.endsAtUptime == nil
                        && !failed.ownership.marker && !failed.ownership.isHeld
                        && failed.lastStopReason == .hardwareChanged
                        && failedTimer?.cancelled == true && failed.timer == nil,
                     "a failed curve write immediately restores firmware control and clears the session")
        failed.hardware?.failUpdate = false
        failed.watchdogTick()
        suite.expect(failed.hardware?.updates == [50] && failed.hardware?.restores == 1,
                     "a later tick cannot restart manual control after a failed curve write")

        let recovering = Controller()
        recovering.hardware?.failUpdate = true
        recovering.hardware?.restoreResults = [false, false, true]
        recovering.watchdogTick()
        suite.expect(recovering.isRecovering && !recovering.isCooling
                        && recovering.owner == nil && recovering.activeConfiguration == nil
                        && recovering.coolingLevel == nil && recovering.ownership.isHeld
                        && recovering.ownership.marker && recovering.timer != nil,
                     "failed restoration retains the marker and watchdog but ends manual control ownership")
        recovering.hardware?.failUpdate = false
        recovering.watchdogTick()
        suite.expect(recovering.hardware?.updates == [50] && recovering.hardware?.restores == 2
                        && recovering.isRecovering && recovering.ownership.marker,
                     "recovery retries automatic mode without reapplying the curve")
        recovering.watchdogTick()
        suite.expect(recovering.hardware?.updates == [50] && recovering.hardware?.restores == 3
                        && recovering.hardware?.isManual == false && !recovering.isRecovering
                        && !recovering.ownership.marker && !recovering.ownership.isHeld
                        && recovering.timer == nil && recovering.exitChecks == 1,
                     "successful automatic recovery releases ownership and stops retrying")

        let markerFailure = Controller()
        markerFailure.hardware?.failUpdate = true
        markerFailure.ownership.canRemoveMarker = false
        markerFailure.watchdogTick()
        suite.expect(markerFailure.hardware?.isManual == false && markerFailure.isRecovering
                        && !markerFailure.isCooling && markerFailure.ownership.marker,
                     "a failed marker removal stays in recovery even after the fans return to automatic")
        markerFailure.ownership.canRemoveMarker = true
        markerFailure.watchdogTick()
        suite.expect(markerFailure.hardware?.updates == [50] && !markerFailure.isRecovering
                        && !markerFailure.ownership.marker,
                     "marker cleanup retries never restart the failed curve")

        let transientRead = Controller()
        transientRead.activeConfiguration = .manual(level: 50)
        transientRead.hardware?.controlIntact = false
        transientRead.watchdogTick()
        suite.expect(transientRead.isCooling && transientRead.verificationFailures == 1
                        && transientRead.hardware?.restores == 0,
                     "a read-only verification failure retains the existing watchdog tolerance")
        transientRead.hardware?.controlIntact = true
        transientRead.watchdogTick()
        suite.expect(transientRead.isCooling && transientRead.verificationFailures == 0
                        && transientRead.hardware?.restores == 0,
                     "healthy verification clears a transient read failure without stopping cooling")
    }
}
