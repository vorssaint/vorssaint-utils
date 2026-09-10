// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import os

private let log = Logger(subsystem: ChargeControlIdentifiers.helperID, category: "ChargeControl")

private final class ChargeControlOwnership {
    private let lockPath = "/var/run/vorssaint-charge-control.lock"
    private let markerPath = "/var/run/vorssaint-charge-control.active"
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
        if markerExists() { return true }
        guard isHeld else { return false }
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

private final class ChargeControlController {
    private let queue = DispatchQueue(label: "com.vorssaint.charge-control.helper")
    private let ownership = ChargeControlOwnership()
    private var hardware: ChargeControlHardware?
    private var owner: UUID?
    private var gate: ChargeControlGate = .allowCharging
    private var lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
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
            if self.owner == id, self.gate != .allowCharging {
                _ = self.performRestore()
            }
            self.scheduleExitIfIdle()
        }
    }

    func status(reply: @escaping (Data) -> Void) {
        queue.async { reply(ChargeControlIPC.encode(self.statusResponse())) }
    }

    func apply(session id: UUID, request: ChargeControlRequest, reply: @escaping (Data) -> Void) {
        queue.async {
            reply(ChargeControlIPC.encode(self.performApply(session: id, request: request)))
        }
    }

    func heartbeat(session id: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            guard self.gate != .allowCharging else {
                reply(ChargeControlIPC.encode(self.statusResponse()))
                return
            }
            guard self.owner == id else {
                reply(ChargeControlIPC.encode(.failure(.controlFailed,
                                                       snapshot: self.currentSnapshot())))
                return
            }
            self.lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
            reply(ChargeControlIPC.encode(.success(self.currentSnapshot())))
        }
    }

    func restore(reply: @escaping (Data) -> Void) {
        queue.async {
            let succeeded = self.performRestore()
            let response = succeeded
                ? ChargeControlResponse.success(self.currentSnapshot())
                : ChargeControlResponse.failure(.controlFailed, snapshot: self.currentSnapshot())
            reply(ChargeControlIPC.encode(response))
            self.scheduleExitIfIdle()
        }
    }

    func shutdown(completion: @escaping (Bool) -> Void) {
        queue.async { completion(self.performRestore()) }
    }

    private func performApply(session id: UUID, request: ChargeControlRequest) -> ChargeControlResponse {
        let cap = ChargeControlPolicy.sanitizedLimit(request.limitPercent)
        guard ownership.acquire() else {
            return .failure(.controlFailed, snapshot: currentSnapshot())
        }
        if hardware == nil { hardware = ChargeControlHardware() }
        guard let hardware else {
            ownership.release()
            return .failure(.unsupportedHardware)
        }

        if request.gate == .allowCharging {
            let restored = performRestore()
            return restored
                ? .success(currentSnapshot())
                : .failure(.controlFailed, snapshot: currentSnapshot())
        }

        guard ownership.createMarker() else {
            return .failure(.controlFailed, snapshot: currentSnapshot())
        }
        guard hardware.apply(gate: request.gate, limit: cap) else {
            _ = performRestore()
            return .failure(.controlFailed, snapshot: currentSnapshot())
        }

        owner = id
        gate = request.gate
        lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
        startWatchdog()
        log.notice("Charge gate \(request.gate.rawValue, privacy: .public)")
        return .success(currentSnapshot())
    }

    @discardableResult
    private func performRestore() -> Bool {
        if !ownership.isHeld {
            guard ownership.acquire() else { return false }
        }
        guard ownership.markerExists() || gate != .allowCharging else {
            ownership.release()
            return true
        }
        if hardware == nil { hardware = ChargeControlHardware() }
        guard hardware?.restoreNormal() == true, ownership.removeMarker() else {
            startWatchdog()
            log.error("Charging restore will retry")
            return false
        }
        gate = .allowCharging
        owner = nil
        ownership.release()
        stopWatchdogIfIdle()
        log.notice("Charging restored")
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
        hardware = ChargeControlHardware()
        if performRestore() {
            scheduleExitIfIdle()
        } else {
            startWatchdog()
        }
    }

    private func startWatchdog() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.watchdogTick() }
        self.timer = timer
        timer.resume()
    }

    private func watchdogTick() {
        if gate == .allowCharging && !ownership.markerExists() {
            stopWatchdogIfIdle()
            return
        }
        if gate != .allowCharging {
            let age = max(0, ProcessInfo.processInfo.systemUptime - lastHeartbeatUptime)
            if ChargeControlPolicy.restoreReason(hasActiveGate: true, heartbeatAge: age) {
                _ = performRestore()
                return
            }
        }
        if ownership.markerExists(), gate == .allowCharging {
            _ = performRestore()
        }
    }

    private func stopWatchdogIfIdle() {
        guard gate == .allowCharging, !ownership.markerExists() else { return }
        timer?.cancel()
        timer = nil
    }

    private func statusResponse() -> ChargeControlResponse {
        if hardware == nil { hardware = ChargeControlHardware() }
        guard let hardware else { return .failure(.unsupportedHardware) }
        return .success(ChargeControlSnapshot(gate: gate,
                                              profile: hardware.profile,
                                              isDischarging: gate == .forceDischarge))
    }

    private func currentSnapshot() -> ChargeControlSnapshot {
        ChargeControlSnapshot(gate: gate,
                              profile: hardware?.profile,
                              isDischarging: gate == .forceDischarge)
    }

    private func scheduleExitIfIdle() {
        guard connectionCount == 0, gate == .allowCharging, !ownership.markerExists() else { return }
        idleGeneration += 1
        let generation = idleGeneration
        queue.asyncAfter(deadline: .now() + 1) {
            guard generation == self.idleGeneration,
                  self.connectionCount == 0,
                  self.gate == .allowCharging,
                  !self.ownership.markerExists() else { return }
            exit(EXIT_SUCCESS)
        }
    }
}

private final class ChargeControlSession: NSObject, ChargeControlXPCProtocol {
    let id = UUID()
    private let controller: ChargeControlController

    init(controller: ChargeControlController) {
        self.controller = controller
    }

    func status(withReply reply: @escaping (Data) -> Void) {
        controller.status(reply: reply)
    }

    func apply(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        guard let decoded = ChargeControlIPC.decodeRequest(request) else {
            reply(ChargeControlIPC.encode(.failure(.controlFailed)))
            return
        }
        controller.apply(session: id, request: decoded, reply: reply)
    }

    func heartbeat(withReply reply: @escaping (Data) -> Void) {
        controller.heartbeat(session: id, reply: reply)
    }

    func restoreNormal(withReply reply: @escaping (Data) -> Void) {
        controller.restore(reply: reply)
    }
}

private final class ChargeControlListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let controller: ChargeControlController

    init(controller: ChargeControlController) {
        self.controller = controller
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let session = ChargeControlSession(controller: controller)
        connection.exportedInterface = NSXPCInterface(with: ChargeControlXPCProtocol.self)
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
    guard ChargeControlIdentifiers.helperID.hasSuffix(".charge-control"),
          ChargeControlPolicy.defaultLimit == 80,
          ChargeControlPolicy.sanitizedLimit(5) == 80,
          ChargeControlPolicy.desiredGate(chargePercent: 81, limit: 80,
                                          wasInhibited: false, mode: .limit,
                                          family: .appleSiliconCHT) == .inhibitCharging
    else { return false }
    print("charge-control-helper: ok")
    return true
}

if CommandLine.arguments.contains("--selftest") {
    exit(runSelfTest() ? EXIT_SUCCESS : EXIT_FAILURE)
}

guard geteuid() == 0 else {
    log.error("The helper must run as root")
    exit(EXIT_FAILURE)
}

private let controller = ChargeControlController()
private let delegate = ChargeControlListenerDelegate(controller: controller)
private let listener = NSXPCListener(machServiceName: ChargeControlIdentifiers.helperID)
listener.setConnectionCodeSigningRequirement(ChargeControlIdentifiers.appCodeRequirement)
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
