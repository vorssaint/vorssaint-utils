// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import os

private let log = Logger(subsystem: FanControlIdentifiers.helperID, category: "FanControl")

private struct FanControlResumeEpoch: Equatable {
    let id: UUID
    let permitsLaunch: Bool
    let removalID: UUID
    // Older helpers create and remove the same marker without updating the
    // lock file. An unrelated directory change can conservatively expire a ticket.
    let directorySeconds: Int
    let directoryNanoseconds: Int
}

private enum FanControlResumeGrant {
    case issued(UUID, FanControlResumeEpoch)
    case revoked
}

private final class FanControlOwnership {
    private let lockPath = "/var/run/vorssaint-fan-control.lock"
    private let markerPath = "/var/run/vorssaint-fan-control.active"
    private var lockFile: Int32 = -1
    // Separate regions allow removal to signal the holder of the hardware
    // lock. Neither write truncates the other's record.
    private let removalOffset: off_t = 96
    private let initialRemovalID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

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

    /// The generation lives on the inode both the Developer and stable helpers
    /// already flock. A legacy empty file or malformed record grants no ticket.
    func resumeEpoch() -> FanControlResumeEpoch? {
        guard isHeld else { return nil }
        var bytes = [UInt8](repeating: 0, count: 89)
        let count = bytes.withUnsafeMutableBytes { pread(lockFile, $0.baseAddress, $0.count, 0) }
        guard count == bytes.count, bytes[0] == 0 || bytes[0] == 1,
              let uuid = UUID(uuidString: String(decoding: bytes[1..<37], as: UTF8.self)),
              let recordedRemoval = UUID(uuidString: String(decoding: bytes[37..<73], as: UTF8.self)),
              readRemovalID() == recordedRemoval else { return nil }
        guard let stamp = directoryStamp() else { return nil }
        let mayLaunch = bytes[0] == 1 && bytes[73..<89].elementsEqual(stamp.bytes)
        return FanControlResumeEpoch(id: uuid, permitsLaunch: mayLaunch, removalID: recordedRemoval,
                                     directorySeconds: stamp.seconds, directoryNanoseconds: stamp.nanoseconds)
    }

    private func directoryStamp() -> (seconds: Int, nanoseconds: Int, bytes: [UInt8])? {
        var directory = stat()
        guard stat("/var/run", &directory) == 0 else { return nil }
        let seconds = directory.st_mtimespec.tv_sec
        let nanoseconds = directory.st_mtimespec.tv_nsec
        let bytes = withUnsafeBytes(of: Int64(seconds).bigEndian) { Array($0) }
                  + withUnsafeBytes(of: Int64(nanoseconds).bigEndian) { Array($0) }
        return (seconds, nanoseconds, bytes)
    }

    func rotateResumeEpoch(permitsLaunch: Bool, expectedRemovalID: UUID? = nil,
                           sessionID: UUID = UUID()) -> FanControlResumeEpoch? {
        guard isHeld, let removalID = readRemovalID(), let stamp = directoryStamp() else { return nil }
        let mayLaunch = permitsLaunch && expectedRemovalID == removalID
        let bytes = [UInt8(mayLaunch ? 1 : 0)] + Array((sessionID.uuidString + removalID.uuidString).utf8) + stamp.bytes
        let count = bytes.withUnsafeBytes { pwrite(lockFile, $0.baseAddress, $0.count, 0) }
        guard count == bytes.count, fsync(lockFile) == 0 else {
            var invalid = UInt8.max
            _ = pwrite(lockFile, &invalid, 1, 0)
            return nil
        }
        return resumeEpoch()
    }

    private func readRemovalID() -> UUID? {
        var bytes = [UInt8](repeating: 0, count: 36)
        let count = bytes.withUnsafeMutableBytes { pread(lockFile, $0.baseAddress, $0.count, removalOffset) }
        if count == 0 { return initialRemovalID }
        guard count == bytes.count else { return nil }
        return UUID(uuidString: String(decoding: bytes, as: UTF8.self))
    }

    func markRemoval() -> Bool {
        let descriptor = Darwin.open(lockPath, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        guard secureRegularFile(descriptor) else { return false }
        let bytes = Array(UUID().uuidString.utf8)
        let count = bytes.withUnsafeBytes { pwrite(descriptor, $0.baseAddress, $0.count, removalOffset) }
        return count == bytes.count && fsync(descriptor) == 0
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
    private var isCooling = false
    private var isRecovering = false
    private var endsAt: Date?
    private var endsAtUptime: TimeInterval?
    private var lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
    private var verificationFailures = 0
    private var temperatureFailures = 0
    private var lastStopReason: FanControlStopReason?
    private var lastStoppedOwner: UUID?
    private var sessionStops: [UUID: FanControlSessionStop] = [:]
    private var resumeGrants: [UUID: FanControlResumeGrant] = [:]
    private var resumableStopEpoch: FanControlResumeEpoch?
    private var controllingEpoch: FanControlResumeEpoch?
    private var pendingRelaunchEpoch: FanControlResumeEpoch?
    private var externalControlEpochID: UUID?
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
            self.sessionStops.removeValue(forKey: id)
            self.resumeGrants.removeValue(forKey: id)
            self.scheduleExitIfIdle()
        }
    }

    func status(session id: UUID, reply: @escaping (Data) -> Void) {
        queue.async { reply(self.encodedResponse(self.statusResponse(), for: id, allowBootstrap: true)) }
    }

    func startLegacySession(_ id: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            let response = self.applyConfiguration(
                session: id,
                configuration: .manual(level: FanControlPolicy.maximumCoolingLevel),
                duration: FanControlPolicy.coolingDuration
            )
            reply(self.encodedResponse(response, for: id))
        }
    }

    func apply(session id: UUID, encodedConfiguration: Data, authorization: UUID? = nil,
               reply: @escaping (Data) -> Void) {
        queue.async {
            guard let configuration = FanControlIPC.decodeConfiguration(encodedConfiguration) else {
                reply(self.encodedResponse(.failure(.controlFailed, snapshot: self.currentSnapshot()), for: id))
                return
            }
            let response = self.applyConfiguration(session: id,
                                                   configuration: configuration,
                                                   duration: nil, authorization: authorization)
            reply(self.encodedResponse(response, for: id))
        }
    }

    func heartbeat(session id: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            guard self.isCooling else {
                reply(self.encodedResponse(self.statusResponse(), for: id, allowBootstrap: true))
                return
            }
            guard self.owner == id else {
                reply(self.encodedResponse(.failure(.alreadyControlled, snapshot: self.currentSnapshot()), for: id))
                return
            }
            self.lastHeartbeatUptime = ProcessInfo.processInfo.systemUptime
            reply(self.encodedResponse(.success(self.currentSnapshot()), for: id))
        }
    }

    func restore(session id: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            // Older clients also use this selector for idle recovery.
            let response = self.isCooling ? self.releaseResponse(for: id) : self.restoreResponse()
            reply(self.encodedResponse(response, for: id))
            self.scheduleExitIfIdle()
        }
    }

    /// Full removal must restore any live session before unregistering this daemon.
    func restoreForRemoval(reply: @escaping (Data) -> Void) {
        queue.async {
            // A removal can finish a pending sleep handoff. No client should
            // use that completion to restart its curve during uninstall.
            self.sessionStops = self.sessionStops.filter { $0.value.reason != nil }
            self.revokeResumeGrants()
            let marked = self.ownership.markRemoval()
            let response = self.restoreResponse(forRemoval: true)
            reply(self.encodedResponse(marked ? response : .failure(.controlFailed, snapshot: response.snapshot)))
            self.scheduleExitIfIdle()
        }
    }

    func releaseControl(session id: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            reply(self.encodedResponse(self.releaseResponse(for: id), for: id))
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
                                    duration: TimeInterval?, authorization: UUID? = nil) -> FanControlResponse {
        guard FanControlPolicy.validConfiguration(configuration) else {
            return .failure(.controlFailed)
        }
        if configuration.mode == .system {
            guard authorization == nil else { return .failure(.controlFailed) }
            return releaseResponse(for: id)
        }
        if isCooling {
            guard owner == id, authorization == nil else {
                return .failure(.alreadyControlled, snapshot: currentSnapshot())
            }
            return updateActiveConfiguration(configuration, duration: duration)
        }
        if authorization != nil && isRecovering { return .failure(.alreadyControlled, snapshot: currentSnapshot()) }
        guard ownership.acquire() else {
            revokeResumeGrants()
            return .failure(.alreadyControlled)
        }
        // Ownership stays held through the actual configuration write. No
        // other cooperating helper can acquire the fans between these checks.
        var authorizedEpoch: FanControlResumeEpoch?
        if let authorization {
            guard case let .issued(ticket, epoch)? = resumeGrants[id], ticket == authorization,
                  !ownership.markerExists(), ownership.resumeEpoch() == epoch else {
                ownership.release()
                return .failure(.alreadyControlled)
            }
            authorizedEpoch = epoch
        }
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
            revokeForExternalControl()
            ownership.release()
            return .failure(.alreadyControlled)
        } catch {
            ownership.release()
            return .failure(.unsupportedHardware)
        }
        guard let level = requestedLevel(for: configuration, hardware: control) else {
            ownership.release()
            return .failure(.controlFailed)
        }
        let nextEpoch = changeResumeEpoch(permitsLaunch: false)
        if let authorizedEpoch, nextEpoch?.removalID != authorizedEpoch.removalID {
            ownership.release()
            return .failure(.alreadyControlled)
        }
        guard ownership.createMarker() else {
            ownership.release()
            return .failure(.controlFailed)
        }

        do {
            _ = try control.startCooling(level: level)
            owner = id
            controllingEpoch = nextEpoch
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
            lastStoppedOwner = nil
            sessionStops.removeValue(forKey: id)
            resumeGrants.removeValue(forKey: id)
            startWatchdog()
            log.notice("Cooling session started")
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

    private func updateActiveConfiguration(_ configuration: FanControlConfiguration,
                                           duration: TimeInterval?) -> FanControlResponse {
        if hardware == nil { hardware = FanControlHardware() }
        guard let hardware,
              let level = requestedLevel(for: configuration, hardware: hardware) else {
            return .failure(.controlFailed, snapshot: currentSnapshot())
        }
        do {
            _ = try hardware.updateCooling(level: level)
            if activeConfiguration != configuration {
                let previous = controllingEpoch
                let next = changeResumeEpoch(permitsLaunch: false)
                controllingEpoch = next?.removalID == previous?.removalID ? next : nil
            }
            activeConfiguration = configuration
            coolingLevel = level
            let uptime = ProcessInfo.processInfo.systemUptime
            endsAt = duration.map { Date().addingTimeInterval($0) }
            endsAtUptime = duration.map { uptime + $0 }
            lastHeartbeatUptime = uptime
            verificationFailures = 0
            temperatureFailures = 0
            lastStopReason = nil
            return .success(currentSnapshot())
        } catch {
            _ = performRestore(reason: .hardwareChanged)
            return .failure(.controlFailed, snapshot: currentSnapshot())
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
            lastStoppedOwner = nil
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

    private func releaseResponse(for id: UUID) -> FanControlResponse {
        if isCooling {
            guard owner == id else { return .failure(.alreadyControlled, snapshot: currentSnapshot()) }
            return restoreResponse(requestedBy: id)
        }
        // Only the stopped session may claim its watchdog reason. An idle
        // helper, including one restarted since the request, proves no release.
        guard sessionStops[id] != nil else {
            let foreign = lastStoppedOwner != nil && lastStoppedOwner != id
            return .failure(foreign ? .alreadyControlled : .controlFailed, snapshot: currentSnapshot())
        }
        return statusResponse(recoverAbandonedControl: false)
    }

    private func restoreResponse(requestedBy id: UUID? = nil, forRemoval: Bool = false) -> FanControlResponse {
        let restored = performRestore(reason: nil, requestedBy: id, forRemoval: forRemoval)
        let snapshot = currentSnapshot()
        return restored ? .success(snapshot) : .failure(.controlFailed, snapshot: snapshot)
    }

    @discardableResult
    private func performRestore(reason: FanControlStopReason?, requestedBy id: UUID? = nil,
                                forRemoval: Bool = false) -> Bool {
        if !ownership.isHeld {
            guard ownership.acquire() else { return false }
        }
        if forRemoval { _ = changeResumeEpoch(permitsLaunch: false) }
        guard ownership.markerExists() || isCooling || isRecovering else {
            ownership.release()
            return true
        }
        // Retrying the restore must preserve the reason the session ended.
        if !isRecovering {
            lastStopReason = reason
            lastStoppedOwner = owner
            let heldEpoch = ownership.resumeEpoch()
            let validSession = controllingEpoch != nil && heldEpoch?.id == controllingEpoch?.id
            let relaunchID = validSession && reason == .appDisconnected ? heldEpoch?.id : nil
            let epoch = forRemoval ? nil : changeResumeEpoch(permitsLaunch: false, sessionID: relaunchID ?? UUID())
            if relaunchID != nil, epoch?.removalID == heldEpoch?.removalID { pendingRelaunchEpoch = epoch }
            if let owner, reason != nil || owner == id {
                sessionStops[owner] = FanControlSessionStop(reason: reason, restored: false)
                if validSession, epoch?.removalID == heldEpoch?.removalID, reason == .heartbeatLost || reason == nil {
                    resumableStopEpoch = epoch
                }
            }
            controllingEpoch = nil
        }
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
        if let lastStoppedOwner { sessionStops[lastStoppedOwner]?.restored = true }
        if let pending = pendingRelaunchEpoch, ownership.resumeEpoch()?.id == pending.id {
            _ = changeResumeEpoch(permitsLaunch: true, expectedRemovalID: pending.removalID, sessionID: pending.id)
        }
        pendingRelaunchEpoch = nil
        if let recorded = resumableStopEpoch {
            // Removing our own marker changed the directory timestamp. Retain
            // the same generation only if removal did not revoke it in flight.
            let current = ownership.resumeEpoch()
            resumableStopEpoch = current?.id == recorded.id ? current : nil
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

    private func revokeResumeGrants() {
        resumeGrants = resumeGrants.mapValues { _ in .revoked }
        resumableStopEpoch = nil
        pendingRelaunchEpoch = nil
        for (id, stop) in sessionStops where stop.reason == nil || stop.reason == .heartbeatLost {
            resumeGrants[id] = .revoked
            sessionStops.removeValue(forKey: id)
        }
    }

    private func revokeForExternalControl() {
        if let epoch = ownership.resumeEpoch(), epoch.id != externalControlEpochID {
            externalControlEpochID = changeResumeEpoch(permitsLaunch: false)?.id
        } else {
            revokeResumeGrants()
        }
    }

    private func changeResumeEpoch(permitsLaunch: Bool, expectedRemovalID: UUID? = nil,
                                   sessionID: UUID = UUID()) -> FanControlResumeEpoch? {
        revokeResumeGrants()
        return ownership.rotateResumeEpoch(permitsLaunch: permitsLaunch, expectedRemovalID: expectedRemovalID, sessionID: sessionID)
    }

    /// The snapshot describes the whole device. Only the requesting connection
    /// receives its own stop, even if another session has run since.
    private func encodedResponse(_ result: FanControlResponse, for id: UUID? = nil, allowBootstrap: Bool = false) -> Data {
        var response = result
        response.isRecovering = isRecovering
        if let id {
            if isCooling && owner == id && result.succeeded { response.resumeSessionID = controllingEpoch?.id }
            attachSessionStop(to: &response, for: id, allowBootstrap: allowBootstrap)
        }
        return FanControlIPC.encode(response)
    }

    private func attachSessionStop(to response: inout FanControlResponse, for id: UUID, allowBootstrap: Bool) {
        let stop = sessionStops[id]
        if let reason = stop?.reason, reason != .heartbeatLost {
            response.sessionStop = stop
            return
        }
        guard !isCooling, stop != nil || response.succeeded else { return }
        let held = ownership.isHeld
        guard ownership.acquire() else {
            revokeResumeGrants()
            return
        }
        defer { if !held { ownership.release() } }
        guard let epoch = ownership.resumeEpoch() else { return }
        let ownStop = lastStoppedOwner == id && resumableStopEpoch == epoch
        if let stop, ownStop, stop.reason != nil || !stop.restored { response.sessionStop = stop }
        guard response.succeeded, !response.snapshot.isCooling, !isRecovering, !ownership.markerExists() else { return }
        let bootstrap = allowBootstrap && epoch.permitsLaunch && stop == nil
        guard ownStop || bootstrap else { return }
        switch resumeGrants[id] {
        case let .issued(token, issuedEpoch) where issuedEpoch == epoch:
            response.resumeAuthorization = token
        case nil:
            guard stop != nil || bootstrap else { return }
            let token = UUID()
            resumeGrants[id] = .issued(token, epoch)
            response.resumeAuthorization = token
        default:
            return
        }
        if bootstrap { response.resumeSessionID = epoch.id }
        if let stop, ownStop, stop.reason == nil, stop.restored {
            response.sessionStop = sessionStops.removeValue(forKey: id)
        }
    }

    private func statusResponse(recoverAbandonedControl: Bool = true) -> FanControlResponse {
        if isRecovering { return .failure(.controlFailed, snapshot: currentSnapshot()) }
        if isCooling { return .success(currentSnapshot()) }

        guard ownership.acquire() else {
            revokeResumeGrants()
            return .failure(.alreadyControlled)
        }
        if ownership.markerExists() {
            guard recoverAbandonedControl else {
                ownership.release()
                return .failure(.alreadyControlled, snapshot: currentSnapshot())
            }
            _ = performRestore(reason: .recovery)
            return isRecovering ? .failure(.controlFailed, snapshot: currentSnapshot())
                                : .success(currentSnapshot())
        }
        defer { ownership.release() }

        if hardware == nil { hardware = FanControlHardware() }
        guard let hardware else { return .failure(.unsupportedHardware) }
        do {
            let snapshot = try hardware.snapshot(isCooling: false, endsAt: nil,
                                                 stopReason: lastStopReason,
                                                 coolingLevel: nil,
                                                 configuration: nil)
            if snapshot.fans.contains(where: \.isManuallyControlled) {
                revokeForExternalControl()
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
        controller.status(session: id, reply: reply)
    }

    func startMaximumCooling(withReply reply: @escaping (Data) -> Void) {
        controller.startLegacySession(id, reply: reply)
    }

    func applyConfiguration(_ configuration: Data, withReply reply: @escaping (Data) -> Void) {
        controller.apply(session: id, encodedConfiguration: configuration, reply: reply)
    }

    func resumeConfiguration(_ configuration: Data, authorization: NSUUID, withReply reply: @escaping (Data) -> Void) {
        controller.apply(session: id, encodedConfiguration: configuration, authorization: authorization as UUID, reply: reply)
    }

    func heartbeat(withReply reply: @escaping (Data) -> Void) {
        controller.heartbeat(session: id, reply: reply)
    }

    func releaseControl(withReply reply: @escaping (Data) -> Void) {
        controller.releaseControl(session: id, reply: reply)
    }

    func restoreAutomatic(withReply reply: @escaping (Data) -> Void) {
        controller.restore(session: id, reply: reply)
    }

    func restoreForRemoval(withReply reply: @escaping (Data) -> Void) {
        controller.restoreForRemoval(reply: reply)
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
