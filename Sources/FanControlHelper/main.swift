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
    private let queue = DispatchQueue(label: "com.vorssaint.fan-control.helper")
    private let ownership = FanControlOwnership()
    private var hardware: FanControlHardware?
    private var owner: UUID?
    private var isCooling = false
    private var isRecovering = false
    private var endsAt: Date?
    private var endsAtUptime: TimeInterval?
    private var lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
    private var verificationFailures = 0
    private var lastStopReason: FanControlStopReason?
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
            self.scheduleExitIfIdle()
        }
    }

    func status(reply: @escaping (Data) -> Void) {
        queue.async { reply(FanControlIPC.encode(self.statusResponse())) }
    }

    func start(session id: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            let response = self.startMaximumCooling(session: id)
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

    func restore(reply: @escaping (Data) -> Void) {
        queue.async {
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

    private func startMaximumCooling(session id: UUID) -> FanControlResponse {
        if isCooling {
            return owner == id ? .success(currentSnapshot())
                               : .failure(.alreadyControlled, snapshot: currentSnapshot())
        }
        guard ownership.acquire() else { return .failure(.alreadyControlled) }
        if ownership.markerExists() {
            isRecovering = true
            startWatchdog()
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
            return .failure(.controlFailed)
        }

        do {
            _ = try control.startMaximumCooling()
            owner = id
            isCooling = true
            isRecovering = false
            endsAt = Date().addingTimeInterval(FanControlPolicy.coolingDuration)
            let uptime = ProcessInfo.processInfo.systemUptime
            endsAtUptime = uptime + FanControlPolicy.coolingDuration
            lastHeartbeatUptime = uptime
            verificationFailures = 0
            lastStopReason = nil
            startWatchdog()
            log.notice("Maximum cooling started")
            return .success(currentSnapshot())
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
            return .failure(.controlFailed, snapshot: currentSnapshot())
        }
    }

    private func finishFailedStart(mayHaveChangedHardware: Bool) {
        if mayHaveChangedHardware, hardware?.restoreAutomatic() != true {
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
        if hardware == nil { hardware = FanControlHardware() }
        guard hardware?.restoreAutomatic() == true,
              ownership.removeMarker() else {
            isRecovering = true
            isCooling = false
            owner = nil
            endsAt = nil
            endsAtUptime = nil
            startWatchdog()
            log.error("Automatic fan recovery will retry")
            return false
        }

        isCooling = false
        isRecovering = false
        owner = nil
        endsAt = nil
        endsAtUptime = nil
        verificationFailures = 0
        lastStopReason = reason
        ownership.release()
        stopWatchdogIfIdle()
        log.notice("Automatic fan control restored")
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
        isRecovering = true
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
        guard isCooling, let endsAt, let endsAtUptime else {
            stopWatchdogIfIdle()
            return
        }
        if hardware?.maximumCoolingIsIntact() == true {
            verificationFailures = 0
        } else {
            verificationFailures += 1
        }
        let nowUptime = ProcessInfo.processInfo.systemUptime
        let deadlineNow = nowUptime >= endsAtUptime ? endsAt : Date()
        let reason = FanControlPolicy.restoreReason(
            now: deadlineNow,
            endsAt: endsAt,
            heartbeatAge: max(0, nowUptime - lastHeartbeatUptime),
            verificationFailures: verificationFailures,
            thermalState: ProcessInfo.processInfo.thermalState
        )
        if let reason { _ = performRestore(reason: reason) }
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
            isRecovering = true
            startWatchdog()
            _ = performRestore(reason: .recovery)
            return isRecovering ? .failure(.controlFailed, snapshot: currentSnapshot())
                                : .success(currentSnapshot())
        }
        ownership.release()

        if hardware == nil { hardware = FanControlHardware() }
        guard let hardware else { return .failure(.unsupportedHardware) }
        do {
            let snapshot = try hardware.snapshot(isCooling: false, endsAt: nil,
                                                 stopReason: lastStopReason)
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
                                 stopReason: lastStopReason))
            ?? FanControlSnapshot(fans: [], isCooling: isCooling,
                                  endsAt: endsAt, stopReason: lastStopReason)
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
        controller.start(session: id, reply: reply)
    }

    func heartbeat(withReply reply: @escaping (Data) -> Void) {
        controller.heartbeat(session: id, reply: reply)
    }

    func restoreAutomatic(withReply reply: @escaping (Data) -> Void) {
        controller.restore(reply: reply)
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
          let encoded = SMCValueCodec.encode(4_800, type: "flt ", size: 4),
          SMCValueCodec.decode(encoded, type: "flt ") == 4_800 else { return false }
    print("fan-control-helper: ok")
    return true
}

if CommandLine.arguments.contains("--selftest") {
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
