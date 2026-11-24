// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit.pwr_mgt
import Darwin

/// Shares the authenticated helper transport, but never shares fan ownership or settings.
final class BatteryController {
    static let shared = BatteryController()
    private let queue = DispatchQueue(label: "com.vorssaint.battery-control")
    private var hardware: BatteryControlHardware?
    private var configuration = BatteryConfiguration()
    private var baseline: BatteryControlHardware.Baseline?
    private var policy = BatteryPolicy()
    private var state: BatteryState = .disabled
    private var error: String? { didSet { errorDetail = nil } }
    private var errorDetail: String?
    private var timer: DispatchSourceTimer?
    private var lockFile: Int32 = -1
    private var owner: UUID?
    private var sleeping = false
    private var assertion: IOPMAssertionID = 0
    private var powerPort: io_connect_t = 0
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private let path = "/var/db/\(FanControlIdentifiers.helperID).battery.json"
    private struct Saved: Codable {
        var configuration: BatteryConfiguration
        var baseline: BatteryControlHardware.Baseline
    }
    var isActive: Bool { queue.sync { baseline != nil || configuration.enabled } }

    private init() {
        queue.async {
            guard let data = self.readSaved(), let saved = try? JSONDecoder().decode(Saved.self, from: data),
                  saved.configuration.valid, self.acquire() else { return }
            self.hardware = BatteryControlHardware()
            self.baseline = saved.baseline
            self.configuration = saved.configuration
            // A crash never resumes an unfinished discharge or calibration cycle.
            if self.restore(), saved.configuration.enabled && (saved.configuration.continueWhenClosed || saved.configuration.pauseWhenClosed) {
                self.configuration = saved.configuration
                if saved.configuration.pauseWhenClosed { self.policy.mode = .paused }
                self.start()
            }
        }
        powerPort = IORegisterForSystemPower(Unmanaged.passUnretained(self).toOpaque(), &notificationPort, { context, _, message, argument in
            guard let context else { return }
            let controller = Unmanaged<BatteryController>.fromOpaque(context).takeUnretainedValue()
            controller.powerEvent(message, token: Int(bitPattern: argument))
        }, &notifier)
        if let notificationPort {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue(), .commonModes)
        }
    }
    private func powerEvent(_ message: UInt32, token: Int) {
        switch message {
        case 0xe0000270: IOAllowPowerChange(powerPort, token)
        case 0xe0000280:
            queue.sync { sleeping = true; tick() }
            IOAllowPowerChange(powerPort, token)
        case 0xe0000300:
            queue.async { self.sleeping = false; self.tick() }
        default: break
        }
    }
    func request(_ data: Data, session: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            defer { reply(self.response()) }
            guard data.count <= 32_768, let request = try? JSONDecoder().decode(BatteryRequest.self, from: data) else {
                self.error = "invalidConfiguration"; return
            }
            if let configuration = request.configuration {
                guard configuration.valid else { self.error = "invalidConfiguration"; return }
                if !configuration.enabled {
                    self.configuration = configuration
                    self.error = nil
                    if self.baseline != nil { self.persist() }
                    _ = self.restore()
                    return
                }
                guard self.owner == nil || self.owner == session else { self.error = "alreadyControlled"; return }
                self.configuration = configuration
                self.owner = session
                self.start()
            }
            if let led = request.led {
                guard self.configuration.enabled, self.baseline != nil else { self.error = "enableFirst"; return }
                guard self.hardware?.supportsLED == true else { self.error = "unsupported"; return }
                self.configuration.led = led
                if led != .automatic { self.baseline?.ledOverridden = true }
                if self.persist() { self.tick() }
            }
            if let action = request.action {
                guard self.configuration.enabled, self.baseline != nil else { self.error = "enableFirst"; return }
                self.execute(action, value: request.value)
                if self.error == nil {
                    if self.persist() { self.tick() }
                    else { self.configuration.enabled = false; _ = self.restore() }
                }
            }
        }
    }
    func status(reply: @escaping (Data) -> Void) { queue.async { reply(self.response()) } }
    func closed(_ id: UUID) {
        queue.async {
            guard self.owner == id else { return }
            self.owner = nil
            if self.configuration.pauseWhenClosed {
                self.policy.mode = .paused
                self.policy.startedAt = nil
                self.tick()
            } else if !self.configuration.continueWhenClosed {
                self.configuration.enabled = false
                _ = self.restore()
            }
        }
    }
    func shutdown() -> Bool {
        queue.sync {
            let resume = configuration.enabled && (configuration.continueWhenClosed || configuration.pauseWhenClosed)
            if !resume { configuration.enabled = false }
            return restore(preservingConfiguration: resume)
        }
    }
    private func start() {
        if hardware == nil { hardware = BatteryControlHardware() }
        guard let hardware, hardware.sample()?.valid == true else { error = "noBattery"; configuration.enabled = false; return }
        do {
            if baseline == nil {
                guard acquire() else { throw BatteryHardwareError.competingController }
                baseline = try hardware.baseline()
            }
            if configuration.led != .automatic { baseline?.ledOverridden = true }
            guard persist() else { throw BatteryHardwareError.rejected }
            error = nil
            startTimer()
            tick()
        } catch {
            switch error {
            case BatteryHardwareError.competingController: self.error = "alreadyControlled"
            case BatteryHardwareError.unavailable: self.error = "unsupported"
            default: self.error = "failed"
            }
            errorDetail = BatteryHardwareError.describe(error)
            configuration.enabled = false
            _ = restore()
        }
    }
    private func startTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer; timer.resume()
    }
    private func tick() {
        guard configuration.enabled, let hardware, baseline != nil else {
            if baseline != nil { _ = restore() }
            return
        }
        // A persistent daemon must not keep controlling a removed app's battery.
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        if executable.path.contains(".app/"), !FileManager.default.fileExists(atPath: executable.path) {
            configuration.enabled = false; _ = restore(); return
        }
        let now = Date()
        if !sleeping {
            for i in configuration.schedules.indices where configuration.schedules[i].enabled && configuration.schedules[i].date <= now {
                let task = configuration.schedules[i]
                // Only catch up recent jobs. Never start an old calibration on login.
                if now.timeIntervalSince(task.date) <= 600 { execute(task.action, value: task.value) }
                if let next = task.next(after: now) { configuration.schedules[i].date = next }
                else { configuration.schedules[i].enabled = false }
                persist()
            }
        }
        let reading = hardware.sample()
        let decision = policy.evaluate(configuration, reading: reading, sleeping: sleeping, now: now)
        do {
            guard let reading else { throw BatteryHardwareError.unavailable }
            try hardware.apply(decision, reading: reading, led: configuration.led)
            state = [.holding, .sailing].contains(decision.state) && reading.charging ? .charging : decision.state
            error = decision.state == .unavailable ? "telemetryUnavailable" : nil
            updateAssertion(configuration.preventSleep && !sleeping && [.charging, .topUp, .calibration].contains(state))
        } catch {
            self.error = "failed"
            errorDetail = BatteryHardwareError.describe(error)
            configuration.enabled = false
            _ = restore()
            state = .unavailable
        }
    }
    private func execute(_ action: BatteryAction, value: Int) {
        guard (20...100).contains(value) else { error = "invalidConfiguration"; return }
        if action == .lowPowerOn || action == .lowPowerOff {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-a", "lowpowermode", action == .lowPowerOn ? "1" : "0"]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let deadline = Date().addingTimeInterval(5)
                while process.isRunning && Date() < deadline { usleep(20_000) }
                if process.isRunning { process.terminate(); error = "failed" }
                else { error = process.terminationStatus == 0 ? nil : "unsupported" }
            } catch { self.error = "failed" }
            return
        }
        if [.discharge, .calibrate].contains(action), hardware?.supportsDischarge != true { error = "unsupported"; return }
        error = policy.perform(action, value: value, configuration: &configuration, reading: hardware?.sample(), now: Date()) ? nil : "invalidAction"
    }
    @discardableResult private func restore(preservingConfiguration: Bool = false) -> Bool {
        updateAssertion(false)
        if let baseline {
            do {
                guard let hardware else { throw BatteryHardwareError.unavailable }
                try hardware.restore(baseline)
            } catch {
                configuration.enabled = false
                let original = self.error == "restoreFailed" ? nil : errorDetail
                self.error = "restoreFailed"
                errorDetail = [original, "Restore: " + BatteryHardwareError.describe(error)].compactMap { $0 }.joined(separator: "\n")
                state = .unavailable; startTimer(); return false
            }
        }
        if preservingConfiguration && baseline != nil && !persist() { return false }
        baseline = nil; policy = BatteryPolicy(); state = .disabled
        if error == "restoreFailed" { error = nil }
        timer?.cancel(); timer = nil
        if lockFile >= 0 {
            if !preservingConfiguration { unlink(path) }
            flock(lockFile, LOCK_UN); close(lockFile); lockFile = -1
        }
        return true
    }
    private func updateAssertion(_ needed: Bool) {
        if needed && assertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                       IOPMAssertionLevel(kIOPMAssertionLevelOn), "Vorssaint battery operation" as CFString, &assertion)
        } else if !needed && assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
    }
    private func acquire() -> Bool {
        if lockFile >= 0 { return true }
        let fd = open("/var/run/vorssaint-battery-control.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { return false }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_nlink == 1,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        lockFile = fd; return true
    }
    @discardableResult private func persist() -> Bool {
        guard let baseline, lockFile >= 0,
              let data = try? JSONEncoder().encode(Saved(configuration: configuration, baseline: baseline)) else { return false }
        let temporary = path + "." + UUID().uuidString
        let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { error = "failed"; return false }
        let count = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        let synced = fsync(fd) == 0
        close(fd)
        guard count == data.count, synced, rename(temporary, path) == 0 else { unlink(temporary); error = "failed"; return false }
        return true
    }
    private func readSaved() -> Data? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_nlink == 1,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_size > 0, info.st_size <= 65_536 else { return nil }
        var data = Data(count: Int(info.st_size))
        let count = data.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        return count == data.count ? data : nil
    }
    private func response() -> Data {
        if hardware == nil { hardware = BatteryControlHardware() }
        let value = BatteryResponse(configuration: configuration, telemetry: hardware?.sample(), state: state,
                                    mode: policy.mode, phase: policy.phase, supportsLimit: hardware?.supportsLimit == true,
                                    supportsDischarge: hardware?.supportsDischarge == true, supportsLED: hardware?.supportsLED == true, error: error, errorDetail: errorDetail)
        return (try? JSONEncoder().encode(value)) ?? Data()
    }
}
