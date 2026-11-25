// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import os

private let log = Logger(subsystem: FanControlIdentifiers.helperID, category: "FanControl")

private final class FanControlOwnership {
    private let lockPath = "/var/run/vorssaint-fan-control.lock"
    private let markerPath = "/var/run/vorssaint-fan-control.active"
    private var lockFile: Int32 = -1

    var isHeld: Bool { lockFile >= 0 }

    func acquire() -> Bool {
        if isHeld { return true }
        let descriptor = Darwin.open(lockPath, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                                     mode_t(0o600))
        guard descriptor >= 0, secureRegularFile(descriptor) else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            return false
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            return false
        }
        lockFile = descriptor
        return true
    }

    func release() {
        guard isHeld else { return }
        _ = flock(lockFile, LOCK_UN)
        Darwin.close(lockFile)
        lockFile = -1
    }

    func markerExists() -> Bool {
        var info = stat()
        guard lstat(markerPath, &info) == 0 else { return false }
        return info.st_uid == 0 && (info.st_mode & S_IFMT) == S_IFREG
            && (info.st_mode & mode_t(0o077)) == 0 && info.st_nlink == 1
    }

    func createMarker() -> Bool {
        guard isHeld, !markerExists() else { return false }
        let descriptor = Darwin.open(markerPath,
                                     O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                                     mode_t(0o600))
        guard descriptor >= 0, secureRegularFile(descriptor) else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            return false
        }
        let marker = Array("v1\n".utf8)
        let written = marker.withUnsafeBytes {
            Darwin.write(descriptor, $0.baseAddress, $0.count)
        }
        let synced = fsync(descriptor) == 0
        Darwin.close(descriptor)
        if written != marker.count || !synced {
            _ = unlink(markerPath)
            return false
        }
        return true
    }

    func removeMarker() -> Bool {
        !markerExists() || unlink(markerPath) == 0
    }

    private func secureRegularFile(_ descriptor: Int32) -> Bool {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return false }
        return info.st_uid == 0 && (info.st_mode & S_IFMT) == S_IFREG
            && (info.st_mode & mode_t(0o077)) == 0 && info.st_nlink == 1
    }

    deinit { release() }
}

private final class FanControlController {
    private let log = Logger(subsystem: FanControlIdentifiers.helperID, category: "FanControl")
    private let queue = DispatchQueue(label: "com.vorssaint.fan-control.helper")
    private let ownership = FanControlOwnership()
    private var hardware: FanControlHardware?
    private var owner: UUID?
    private var unregisterSession: UUID?
    private var isCooling = false
    private var isRecovering = false
    private var endsAt: Date?
    private var endsAtUptime: TimeInterval?
    private var lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
    private var verificationFailures = 0
    private var temperatureFailures = 0
    private var lastStopReason: FanControlStopReason?
    private var coolingLevel: Int?
    private var activeConfiguration: FanControlConfiguration?
    private var connectionCount = 0
    private var idleGeneration = 0
    private var timer: DispatchSourceTimer?

    init() {
        queue.async { [weak self] in self?.recoverAbandonedControlIfNeeded() }
    }

    func connectionOpened() {
        queue.async {
            self.connectionCount += 1
            self.idleGeneration += 1
        }
    }

    func connectionClosed(_ id: UUID) {
        queue.async {
            self.connectionCount = max(0, self.connectionCount - 1)
            if self.owner == id, self.isCooling {
                _ = self.performRestore(reason: .appDisconnected)
            }
            if self.unregisterSession == id { self.unregisterSession = nil }
            self.scheduleExitIfIdle()
        }
    }

    func status(reply: @escaping (Data) -> Void) {
        queue.async {
            var response = self.statusResponse()
            response.supportsUnregisterPreparation = true
            reply(FanControlIPC.encode(response))
        }
    }

    func prepareForUnregister(session id: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            guard self.unregisterSession == nil || self.unregisterSession == id,
                  !self.isCooling, !self.isRecovering, self.ownership.acquire() else {
                reply(FanControlIPC.encode(.failure(.alreadyControlled)))
                return
            }
            let needsRecovery = self.ownership.markerExists()
            self.ownership.release()
            guard !needsRecovery else {
                reply(FanControlIPC.encode(.failure(.controlFailed)))
                return
            }
            // This daemon cannot accept a new owner until the caller either
            // unregisters it or closes the connection to release the reservation.
            self.unregisterSession = id
            reply(FanControlIPC.encode(.success(.empty)))
        }
    }

    func startLegacySession(_ id: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            let response = self.applyConfiguration(
                session: id,
                configuration: .manual(level: FanControlPolicy.maximumCoolingLevel),
                duration: FanControlPolicy.coolingDuration
            )
            reply(FanControlIPC.encode(response))
        }
    }

    func apply(session id: UUID, encodedConfiguration: Data,
               reply: @escaping (Data) -> Void) {
        queue.async {
            guard let configuration = FanControlIPC.decodeConfiguration(encodedConfiguration) else {
                reply(FanControlIPC.encode(.failure(.controlFailed,
                                                    snapshot: self.currentSnapshot())))
                return
            }
            let response = self.applyConfiguration(session: id,
                                                   configuration: configuration,
                                                   duration: nil)
            reply(FanControlIPC.encode(response))
        }
    }

    func heartbeat(session id: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            guard self.isCooling else {
                reply(FanControlIPC.encode(self.statusResponse()))
                return
            }
            guard self.owner == id else {
                reply(FanControlIPC.encode(.failure(.alreadyControlled,
                                                    snapshot: self.currentSnapshot())))
                return
            }
            self.lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
            reply(FanControlIPC.encode(.success(self.currentSnapshot())))
        }
    }

    func restore(session id: UUID? = nil, reply: @escaping (Data) -> Void) {
        queue.async {
            if let id, !self.isCooling || self.owner != id {
                let error: FanControlErrorCode = self.isCooling ? .alreadyControlled : .controlFailed
                reply(FanControlIPC.encode(.failure(error, snapshot: self.currentSnapshot())))
                return
            }
            let succeeded = self.performRestore(reason: nil)
            let response = succeeded
                ? FanControlResponse.success(self.currentSnapshot())
                : FanControlResponse.failure(.controlFailed, snapshot: self.currentSnapshot())
            reply(FanControlIPC.encode(response))
            self.scheduleExitIfIdle()
        }
    }

    func shutdown(completion: @escaping (Bool) -> Void) {
        queue.async {
            guard self.isCooling || self.isRecovering || self.ownership.isHeld else {
                completion(true)
                return
            }
            let restored = self.performRestore(reason: .appDisconnected)
            completion(restored)
        }
    }

    // MARK: - Control

    private func applyConfiguration(session id: UUID,
                                    configuration: FanControlConfiguration,
                                    duration: TimeInterval?) -> FanControlResponse {
        guard FanControlPolicy.validConfiguration(configuration) else {
            return .failure(.controlFailed)
        }
        if configuration.mode == .system {
            return performRestore(reason: nil)
                ? .success(currentSnapshot())
                : .failure(.controlFailed, snapshot: currentSnapshot())
        }
        guard unregisterSession == nil else { return .failure(.alreadyControlled) }
        if isCooling {
            guard owner == id else {
                return .failure(.alreadyControlled, snapshot: currentSnapshot())
            }
            return updateActiveConfiguration(configuration, duration: duration)
        }
        guard ownership.acquire() else { return .failure(.alreadyControlled) }
        if ownership.markerExists() {
            _ = performRestore(reason: .recovery)
            return .failure(.controlFailed, snapshot: currentSnapshot())
        }
        let control = FanControlHardware()
        hardware = control
        guard let control else {
            ownership.release()
            return .failure(.unsupportedHardware)
        }

        do {
            try control.validateAutomaticControl()
        } catch FanControlHardwareError.noFans {
            ownership.release()
            return .failure(.noFans)
        } catch FanControlHardwareError.alreadyControlled {
            ownership.release()
            return .failure(.alreadyControlled)
        } catch {
            ownership.release()
            return .failure(.unsupportedHardware)
        }
        guard ownership.createMarker() else {
            ownership.release()
            return .failure(.controlFailed, retryableApply: true)
        }

        do {
            guard let level = requestedLevel(for: configuration, hardware: control) else {
                finishFailedStart(mayHaveChangedHardware: false)
                return .failure(.controlFailed, retryableApply: true)
            }
            _ = try control.startCooling(level: level)
            owner = id
            isCooling = true
            coolingLevel = level
            activeConfiguration = configuration
            isRecovering = false
            let uptime = ProcessInfo.processInfo.systemUptime
            endsAt = duration.map { Date().addingTimeInterval($0) }
            endsAtUptime = duration.map { uptime + $0 }
            lastHeartbeatUptime = uptime
            verificationFailures = 0
            temperatureFailures = 0
            lastStopReason = nil
            startWatchdog()
            log.notice("Cooling session started")
            return .success(currentSnapshot(), supportsOwnedRestore: true)
        } catch FanControlHardwareError.noFans {
            finishFailedStart(mayHaveChangedHardware: false)
            return .failure(.noFans)
        } catch FanControlHardwareError.alreadyControlled {
            finishFailedStart(mayHaveChangedHardware: false)
            return .failure(.alreadyControlled)
        } catch FanControlHardwareError.unsupported {
            finishFailedStart(mayHaveChangedHardware: false)
            return .failure(.unsupportedHardware)
        } catch {
            finishFailedStart(mayHaveChangedHardware: true)
            return .failure(.controlFailed, snapshot: currentSnapshot(),
                            localStopReason: isRecovering ? .recovery : nil, retryableApply: !isRecovering)
        }
    }

    private func updateActiveConfiguration(_ configuration: FanControlConfiguration,
                                           duration: TimeInterval?) -> FanControlResponse {
        if hardware == nil { hardware = FanControlHardware() }
        guard let hardware,
              let level = requestedLevel(for: configuration, hardware: hardware) else {
            return .failure(.controlFailed, snapshot: currentSnapshot())
        }
        do {
            _ = try hardware.updateCooling(level: level)
            activeConfiguration = configuration
            coolingLevel = level
            let uptime = ProcessInfo.processInfo.systemUptime
            endsAt = duration.map { Date().addingTimeInterval($0) }
            endsAtUptime = duration.map { uptime + $0 }
            lastHeartbeatUptime = uptime
            verificationFailures = 0
            temperatureFailures = 0
            lastStopReason = nil
            return .success(currentSnapshot(), supportsOwnedRestore: true)
        } catch {
            _ = performRestore(reason: .hardwareChanged)
            return .failure(.controlFailed, snapshot: currentSnapshot(), localStopReason: .hardwareChanged)
        }
    }

    private func requestedLevel(for configuration: FanControlConfiguration,
                                hardware: FanControlHardware,
                                previousLevel: Int? = nil) -> Int? {
        switch configuration.mode {
        case .system:
            return nil
        case .manual:
            return configuration.manualLevel
        case .curve:
            let sample = hardware.readTemperatures()
            return FanControlPolicy.curveCoolingLevel(
                curves: configuration.curves,
                temperatures: sample.readings,
                gpuPoweredDown: sample.gpuPoweredDown,
                previousLevel: previousLevel
            )
        }
    }

    private func finishFailedStart(mayHaveChangedHardware: Bool) {
        if mayHaveChangedHardware, hardware?.restoreAutomatic() != true {
            lastStopReason = .recovery
            isRecovering = true
            startWatchdog()
            return
        }
        _ = ownership.removeMarker()
        ownership.release()
        hardware = nil
        isRecovering = false
        stopWatchdogIfIdle()
    }

    @discardableResult
    private func performRestore(reason: FanControlStopReason?) -> Bool {
        if !ownership.isHeld {
            guard ownership.acquire() else { return false }
        }
        guard ownership.markerExists() || isCooling || isRecovering else {
            ownership.release()
            return true
        }
        // Retrying the restore must preserve the reason the session ended.
        if !isRecovering { lastStopReason = reason }
        if hardware == nil { hardware = FanControlHardware() }
        let restored = hardware?.restoreAutomatic() == true && ownership.removeMarker()
        isRecovering = !restored
        isCooling = false
        owner = nil
        coolingLevel = nil
        activeConfiguration = nil
        endsAt = nil
        endsAtUptime = nil
        verificationFailures = 0
        temperatureFailures = 0
        guard restored else {
            startWatchdog()
            log.error("Automatic fan recovery will retry: \(self.lastStopReason?.rawValue ?? "requested", privacy: .public)")
            return false
        }
        ownership.release()
        stopWatchdogIfIdle()
        // The reason is the only trace of why a session ended; the app's card
        // folds most of them into one generic message.
        log.notice("Automatic fan control restored: \(self.lastStopReason?.rawValue ?? "requested", privacy: .public)")
        return true
    }

    private func recoverAbandonedControlIfNeeded() {
        guard ownership.acquire() else {
            scheduleExitIfIdle()
            return
        }
        guard ownership.markerExists() else {
            ownership.release()
            scheduleExitIfIdle()
            return
        }
        hardware = FanControlHardware()
        if performRestore(reason: .recovery) {
            scheduleExitIfIdle()
        } else {
            startWatchdog()
        }
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.watchdogTick() }
        self.timer = timer
        timer.resume()
    }

    private func watchdogTick() {
        if isRecovering {
            if performRestore(reason: .recovery) { scheduleExitIfIdle() }
            return
        }
        guard isCooling else {
            stopWatchdogIfIdle()
            return
        }
        var level = coolingLevel
        if let configuration = activeConfiguration, configuration.mode == .curve {
            if let hardware, let requested = requestedLevel(for: configuration, hardware: hardware,
                                                           previousLevel: coolingLevel) {
                temperatureFailures = 0
                level = requested
            } else {
                temperatureFailures += 1
            }
        }
        // Check the previous targets even when the curve is changing level.
        // A successful write cannot prove that firmware will leave them in place.
        let controlIntact = level != nil && hardware?.coolingIsIntact() == true
        if !controlIntact { verificationFailures += 1 }
        if let reason = watchdogStopReason() {
            _ = performRestore(reason: reason)
            return
        }
        // With a missing sensor, only the already-verified targets may stay in place.
        // If firmware has taken any fan back, release all fans without a manual write.
        if temperatureFailures > 0 {
            if controlIntact {
                verificationFailures = 0
            } else {
                _ = performRestore(reason: .temperatureUnavailable)
            }
            return
        }
        guard let hardware, let level else { return }
        if controlIntact && level == coolingLevel {
            verificationFailures = 0
            return
        }
        do {
            try hardware.holdCooling(level: level)
            coolingLevel = level
            if controlIntact {
                verificationFailures = 0
            } else {
                log.info("Manual fan control reasserted")
            }
        } catch FanControlHardwareError.unsafeControlState {
            log.error("Fan control write left the manual targets unverified")
            _ = performRestore(reason: .hardwareChanged)
            return
        } catch {
            if controlIntact { verificationFailures += 1 }
            log.error("Fan control write failed (\(self.verificationFailures, privacy: .public) of \(FanControlPolicy.verificationFailureLimit, privacy: .public))")
        }
        // SMC retries can take time. Recheck deadlines and thermal pressure.
        if let reason = watchdogStopReason() { _ = performRestore(reason: reason) }
    }

    private func watchdogStopReason() -> FanControlStopReason? {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let deadlineNow: Date
        if let endsAt, let endsAtUptime, nowUptime >= endsAtUptime {
            deadlineNow = endsAt
        } else {
            deadlineNow = Date()
        }
        return FanControlPolicy.restoreReason(
            now: deadlineNow,
            endsAt: endsAt,
            heartbeatAge: max(0, nowUptime - lastHeartbeatUptime),
            verificationFailures: verificationFailures,
            temperatureFailures: temperatureFailures,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    private func stopWatchdogIfIdle() {
        guard !isCooling, !isRecovering else { return }
        timer?.cancel()
        timer = nil
    }

    // MARK: - Status and lifecycle

    private func statusResponse() -> FanControlResponse {
        if isRecovering { return .failure(.controlFailed, snapshot: currentSnapshot()) }
        if isCooling { return .success(currentSnapshot()) }

        guard ownership.acquire() else { return .failure(.alreadyControlled) }
        if ownership.markerExists() {
            _ = performRestore(reason: .recovery)
            return isRecovering ? .failure(.controlFailed, snapshot: currentSnapshot())
                                : .success(currentSnapshot())
        }
        ownership.release()

        if hardware == nil { hardware = FanControlHardware() }
        guard let hardware else { return .failure(.unsupportedHardware) }
        do {
            let snapshot = try hardware.snapshot(isCooling: false, endsAt: nil,
                                                 stopReason: lastStopReason,
                                                 coolingLevel: nil,
                                                 configuration: nil)
            if snapshot.fans.contains(where: \.isManuallyControlled) {
                return .failure(.alreadyControlled, snapshot: snapshot)
            }
            return .success(snapshot)
        } catch FanControlHardwareError.noFans {
            return .failure(.noFans)
        } catch FanControlHardwareError.unsupported {
            return .failure(.unsupportedHardware)
        } catch {
            return .failure(.controlFailed)
        }
    }

    private func currentSnapshot() -> FanControlSnapshot {
        (try? hardware?.snapshot(isCooling: isCooling, endsAt: endsAt,
                                 stopReason: lastStopReason,
                                 coolingLevel: coolingLevel,
                                 configuration: activeConfiguration))
            ?? FanControlSnapshot(fans: [], isCooling: isCooling,
                                  endsAt: endsAt, stopReason: lastStopReason,
                                  coolingLevel: coolingLevel,
                                  configuration: activeConfiguration,
                                  temperatures: nil)
    }

    private func scheduleExitIfIdle() {
        guard connectionCount == 0, !isCooling, !isRecovering else { return }
        idleGeneration += 1
        let generation = idleGeneration
        queue.asyncAfter(deadline: .now() + 1) {
            guard generation == self.idleGeneration,
                  self.connectionCount == 0, !self.isCooling, !self.isRecovering else { return }
            exit(EXIT_SUCCESS)
        }
    }
}

private final class FanControlSession: NSObject, FanControlXPCProtocol {
    let id = UUID()
    private let controller: FanControlController

    init(controller: FanControlController) {
        self.controller = controller
    }

    func status(withReply reply: @escaping (Data) -> Void) {
        controller.status(reply: reply)
    }

    func startMaximumCooling(withReply reply: @escaping (Data) -> Void) {
        controller.startLegacySession(id, reply: reply)
    }

    func applyConfiguration(_ configuration: Data, withReply reply: @escaping (Data) -> Void) {
        controller.apply(session: id, encodedConfiguration: configuration, reply: reply)
    }

    func heartbeat(withReply reply: @escaping (Data) -> Void) {
        controller.heartbeat(session: id, reply: reply)
    }

    func restoreAutomatic(withReply reply: @escaping (Data) -> Void) {
        controller.restore(reply: reply)
    }

    func restoreOwnedControl(withReply reply: @escaping (Data) -> Void) {
        controller.restore(session: id, reply: reply)
    }

    func prepareForUnregister(withReply reply: @escaping (Data) -> Void) {
        controller.prepareForUnregister(session: id, reply: reply)
    }
}

private final class FanControlListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let controller: FanControlController

    init(controller: FanControlController) {
        self.controller = controller
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let session = FanControlSession(controller: controller)
        connection.exportedInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [weak controller] in
            controller?.connectionClosed(session.id)
        }
        controller.connectionOpened()
        connection.activate()
        return true
    }
}

private func runSelfTest() -> Bool {
    guard FanControlIdentifiers.helperID.hasSuffix(".fan-control"),
          FanControlPolicy.coolingDuration == 900,
          FanControlPolicy.validCoolingLevel(FanControlPolicy.defaultCoolingLevel),
          FanControlPolicy.validConfiguration(.curve([FanControlConfiguration.defaultCurve])),
          let encoded = SMCValueCodec.encode(4_800, type: "flt ", size: 4),
          SMCValueCodec.decode(encoded, type: "flt ") == 4_800 else { return false }
    print("fan-control-helper: ok")
    return true
}

if ProcessInfo.processInfo.arguments.contains("--selftest") {
    exit(runSelfTest() ? EXIT_SUCCESS : EXIT_FAILURE)
}

guard geteuid() == 0 else {
    log.error("The helper must run as root")
    exit(EXIT_FAILURE)
}

private let controller = FanControlController()
private let delegate = FanControlListenerDelegate(controller: controller)
private let listener = NSXPCListener(machServiceName: FanControlIdentifiers.helperID)
listener.setConnectionCodeSigningRequirement(FanControlIdentifiers.appCodeRequirement)
listener.delegate = delegate
listener.activate()

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    controller.shutdown { restored in
        if restored { exit(EXIT_SUCCESS) }
    }
}
termination.resume()
let interruption = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interruption.setEventHandler {
    controller.shutdown { restored in
        if restored { exit(EXIT_SUCCESS) }
    }
}
interruption.resume()

RunLoop.main.run()
