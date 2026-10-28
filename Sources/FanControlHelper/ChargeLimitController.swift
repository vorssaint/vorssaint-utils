// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import IOKit
import IOKit.pwr_mgt
import os

private let log = Logger(subsystem: FanControlIdentifiers.helperID, category: "ChargeLimit")

/// Where the helper keeps the limits the app last asked for. /var/run is
/// volatile on purpose: a cold boot resets the charge platform state anyway,
/// and the app re-applies the stored choice at launch.
private let statePath = "/var/run/vorssaint-battery-control.json"

/// The charge-limit half of the privileged helper. The enforcing loop lives
/// here, not in the app, because the limit has to hold while the app is not
/// running. Nothing touches the SMC until a limit is stored or the app asks
/// for a status, so a Mac that only uses fan control never sees a charging
/// key written.
final class ChargeLimitController {
    private let queue = DispatchQueue(label: "com.vorssaint.charge-limit.helper")
    private var bridge: AppleSMCBatteryBridge?
    private var probe = Probe()
    private var limits = BatteryLimitState(enabled: false,
                                           upper: BatteryControlCore.defaultUpper,
                                           lowerDelta: BatteryControlCore.defaultLowerDelta)
    private var reconcileTimer: DispatchSourceTimer?
    private var lastFault = BatteryChargeControl.ErrorKind.none
    private var watching = false
    private var sleeping = false
    private var chargeStoppedBySleep = false
    private var powerPort: IONotificationPortRef?
    private var powerNotifier: io_object_t = 0
    private var rootPort: io_connect_t = 0

    init() {
        queue.async { [weak self] in self?.resumeStored() }
    }

    /// A limit in force keeps the helper running past its last client.
    var isEnforcing: Bool { queue.sync { limits.enabled } }

    // MARK: XPC surface

    func status(reply: @escaping (Data) -> Void) {
        queue.async {
            self.openBridge()
            reply(BatteryControlIPC.encode(self.snapshot()))
        }
    }

    func apply(encoded: Data, reply: @escaping (Data) -> Void) {
        queue.async {
            guard let requested = BatteryControlIPC.decodeLimits(encoded),
                  BatteryLimitState.valid(requested) else {
                reply(BatteryControlIPC.encode(self.snapshot(problem: .unverifiable)))
                return
            }
            self.limits = requested
            self.persist()
            self.openBridge()
            // Turning the limit off hands charging and wall power back at
            // once; the policy alone would leave an inhibited charge as is.
            let problem = requested.enabled ? self.applyLimits() : self.restoreDefaults()
            if requested.enabled { self.startWatching() }
            self.lastFault = problem
            reply(BatteryControlIPC.encode(self.snapshot(problem: problem)))
        }
    }

    func restore(reply: @escaping (Data) -> Void) {
        queue.async {
            // A Mac that never held a limit has nothing to give back.
            guard self.limits.enabled || FileManager.default.fileExists(atPath: statePath) else {
                reply(BatteryControlIPC.encode(self.snapshot()))
                return
            }
            self.limits.enabled = false
            self.persist()
            self.openBridge()
            let problem = self.restoreDefaults()
            self.lastFault = problem
            reply(BatteryControlIPC.encode(self.snapshot(problem: problem)))
        }
    }

    /// SIGTERM from launchd: charging goes back to defaults. The stored
    /// limits stay, so the next start enforces them again.
    func shutdown() {
        queue.sync {
            if limits.enabled { _ = restoreDefaults() }
        }
    }

    // MARK: Startup and recovery

    /// Every start replays the stored limits, so a helper that was killed or
    /// replaced never leaves the adapter cut or charging inhibited behind a
    /// limit nobody is enforcing. Without stored limits nothing is touched.
    private func resumeStored() {
        guard let stored = Self.readState(), stored.enabled else { return }
        log.notice("Resuming stored limits")
        limits = stored
        openBridge()
        lastFault = applyLimits()
        startWatching()
    }

    /// The SMC user client can refuse a first open while other AppleSMC
    /// sessions churn, so a failure is retried instead of being remembered.
    private func openBridge() {
        guard bridge == nil else { return }
        guard let opened = AppleSMCBatteryBridge() else {
            log.fault("AppleSMC unavailable")
            return
        }
        bridge = opened
        probe = BatteryChargeControl.probe(bridge: opened)
        log.notice("Charge control probed: backend \(self.probe.backend.rawValue, privacy: .public), adapter key \(self.probe.adapterKeyName ?? "none", privacy: .public)")
    }

    private func startWatching() {
        guard !watching, bridge != nil else { return }
        watching = true
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 60)
        timer.setEventHandler { [weak self] in
            guard let self, self.limits.enabled, !self.sleeping else { return }
            let problem = self.applyLimits()
            self.lastFault = problem
            if problem != .none {
                log.error("Reconcile fault \(problem.rawValue, privacy: .public)")
            }
        }
        timer.resume()
        reconcileTimer = timer
        observeSleepWake()
    }

    // MARK: Snapshot

    private func snapshot(problem: BatteryChargeControl.ErrorKind? = nil) -> BatteryControlSnapshot {
        var result = BatteryControlSnapshot.empty
        result.backend = probe.backend
        result.adapterKeyPresent = probe.adapterKeyName != nil
        result.adapterConnected = bridge.flatMap { BatteryChargeControl.adapterEnabled($0, probe) }
        result.limits = limits
        result.percentage = bridge?.batteryPercentage
        result.isCharging = bridge?.isCharging ?? false
        result.lastFault = (problem ?? lastFault).rawValue
        return result
    }

    // MARK: Enforcement

    /// One pass of the standing policy, whatever the app is doing.
    private func applyLimits() -> BatteryChargeControl.ErrorKind {
        BatteryChargeControl.max(applyChargeLimit(), applyAdapterPolicy())
    }

    private func applyChargeLimit() -> BatteryChargeControl.ErrorKind {
        guard let bridge else { return .unsupported }
        guard probe.backend == .legacy else { return .unsupported }
        guard let percentage = bridge.batteryPercentage,
              let verdict = BatteryLimitState.charging(enabled: limits, percentage: percentage) else {
            // Between the limits, or no reading yet: macOS holds the
            // charging state, so we do not chase it.
            return .none
        }
        return BatteryChargeControl.legacySetCharging(bridge, probe, verdict == .enable)
    }

    /// Cycle mode: past the upper limit the wall power is cut so the battery
    /// carries the Mac down to the lower edge, then it comes back. Reads
    /// first, so a steady state costs no SMC write. A Mac with no adapter key
    /// simply holds at the limit.
    private func applyAdapterPolicy() -> BatteryChargeControl.ErrorKind {
        guard let bridge, probe.adapterKeyName != nil,
              let current = BatteryChargeControl.adapterEnabled(bridge, probe) else {
            return .none
        }
        let wanted: BatteryLimitState.Adapter
        if let percentage = bridge.batteryPercentage {
            wanted = BatteryLimitState.adapter(for: limits, percentage: percentage)
        } else {
            // No reading: never leave the Mac cut off blind. Reconnecting is
            // always safe, so that is the only move made.
            wanted = current ? .hold : .connect
        }
        switch wanted {
        case .connect where !current:
            return BatteryChargeControl.adapterSet(bridge, probe, true)
        case .disconnect where current:
            return BatteryChargeControl.adapterSet(bridge, probe, false)
        default:
            return .none
        }
    }

    /// Charging allowed and wall power connected, the way macOS found them.
    private func restoreDefaults() -> BatteryChargeControl.ErrorKind {
        guard let bridge else { return .unsupported }
        let problem = BatteryChargeControl.restoreSafe(bridge, probe)
        if problem == .none {
            log.notice("Charging restored to platform defaults")
        } else {
            log.error("Restore did not verify: \(problem.rawValue, privacy: .public)")
        }
        return problem
    }

    // MARK: Persistence

    private func persist() {
        // .atomic writes a temporary file and renames it over the old one: a
        // crash never leaves the helper with half a file or none.
        guard let data = try? JSONEncoder().encode(limits),
              (try? data.write(to: URL(fileURLWithPath: statePath), options: .atomic)) != nil else {
            log.error("Storing limits failed")
            return
        }
    }

    private static func readState() -> BatteryLimitState? {
        guard let data = FileManager.default.contents(atPath: statePath),
              let stored = BatteryControlIPC.decodeLimits(data),
              BatteryLimitState.valid(stored) else { return nil }
        return stored
    }

    // MARK: Sleep and wake

    /// iokit_common_msg values from IOMessage.h, spelled out because these
    /// macros do not import into Swift.
    private static let canSystemSleepMessage: UInt32 = 0xE0000270
    private static let willSleepMessage: UInt32 = 0xE0000280
    private static let willPowerOnMessage: UInt32 = 0xE0000320
    private static let hasPoweredOnMessage: UInt32 = 0xE0000300

    /// Nothing watches the level while the Mac sleeps, so macOS would carry
    /// the charge past the limit, or leave a cut adapter cut. Sleep stops the
    /// first and undoes the second; wake enforces the limits again.
    private func observeSleepWake() {
        let callback: IOServiceInterestCallback = { refcon, _, messageType, argument in
            guard let refcon else { return }
            let controller = Unmanaged<ChargeLimitController>
                .fromOpaque(refcon).takeUnretainedValue()
            // For the sleep messages the argument *is* the notification ID
            // (an integer smuggled through the pointer), not memory to read.
            let token = Int(bitPattern: argument)
            controller.handle(messageType: messageType, token: token)
        }
        // IORegisterForSystemPower allocates the notification port itself and
        // returns the root-domain connection (MACH_PORT_NULL on failure),
        // not a kern_return_t.
        rootPort = IORegisterForSystemPower(Unmanaged.passUnretained(self).toOpaque(),
                                            &powerPort, callback, &powerNotifier)
        guard rootPort != 0, let port = powerPort else {
            log.fault("Power notifications unavailable")
            return
        }
        // Callbacks arrive on the controller's own queue.
        IONotificationPortSetDispatchQueue(port, queue)
    }

    /// The root domain needs every can-sleep and will-sleep token
    /// acknowledged before sleep proceeds.
    private func handle(messageType: UInt32, token: Int) {
        switch messageType {
        case Self.canSystemSleepMessage:
            // Never veto: the Mac decides when it sleeps, not this daemon.
            IOAllowPowerChange(rootPort, token)
        case Self.willSleepMessage:
            sleeping = true
            if let bridge, limits.enabled {
                // Always stopped: nothing watches the level while asleep, and a
                // charge that carries on would run past the limit. Only a charge
                // that sleep itself stops comes back at wake; one the limit had
                // already held stays held.
                chargeStoppedBySleep = BatteryChargeControl.isLegacyChargingEnabled(bridge, probe) == true
                _ = BatteryChargeControl.legacySetCharging(bridge, probe, false)
                if BatteryChargeControl.adapterEnabled(bridge, probe) == false {
                    _ = BatteryChargeControl.adapterSet(bridge, probe, true)
                }
            }
            IOAllowPowerChange(rootPort, token)
        case Self.willPowerOnMessage, Self.hasPoweredOnMessage:
            sleeping = false
            if limits.enabled {
                if chargeStoppedBySleep, let bridge {
                    _ = BatteryChargeControl.legacySetCharging(bridge, probe, true)
                }
                chargeStoppedBySleep = false
                let problem = applyLimits()
                if problem != .none {
                    log.error("Wake reconcile: \(problem.rawValue, privacy: .public)")
                }
            }
        default:
            break
        }
    }
}
