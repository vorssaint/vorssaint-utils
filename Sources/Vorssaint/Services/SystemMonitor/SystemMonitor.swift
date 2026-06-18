// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation
import IOKit

/// Memory pressure as reported by the kernel, mapped to the traffic-light
/// indicator shown in the panel.
enum MemoryPressure {
    case normal, warning, critical, unknown

    init(kernelLevel: Int32) {
        switch kernelLevel {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unknown
        }
    }
}

/// One refresh tick of the system monitor. Optionals stay nil when a reading
/// is unavailable on the current hardware, and the UI hides those rows.
struct SystemSnapshot {
    var cpuTemperature: Double?
    var gpuTemperature: Double?
    var batteryTemperature: Double?
    var cpuUsage: Double?          // 0...1
    var gpuUsage: Double?          // 0...1
    var memoryUsed: UInt64?
    var memoryTotal: UInt64?
    var memoryPressure: MemoryPressure = .unknown

    // Network
    var netDownBytesPerSec: Double?
    var netUpBytesPerSec: Double?
    var netTotalDown: UInt64?      // since the app started watching
    var netTotalUp: UInt64?

    // Power
    var power: PowerReading?

    // History (oldest → newest) for the graphs
    var cpuHistory: [Double] = []          // 0...1
    var gpuHistory: [Double] = []          // 0...1
    var memoryHistory: [Double] = []       // 0...1
    var netDownHistory: [Double] = []      // bytes/sec
    var netUpHistory: [Double] = []        // bytes/sec
    var systemPowerHistory: [Double] = []  // watts
    var batteryHistory: [Double] = []      // 0...1 charge level
}

/// Reads temperatures (SMC), CPU/GPU usage, memory, network and power on a
/// background queue. Runs while the panel is visible (full readings, including
/// temperatures and GPU) and/or while a menu bar metric is enabled (light
/// readings only). When nothing needs it, the timer stops — zero idle cost.
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published private(set) var snapshot = SystemSnapshot()

    private let queue = DispatchQueue(label: "com.vorssaint.utils.system-monitor", qos: .utility)
    private var timer: Timer?
    private var intervalSeconds = 2
    private var panelClients = 0
    private var menuBarActive = false
    private var refreshInFlight = false
    private var pendingFullRefresh = false

    // SMC sensors
    private var smc: SMCClient?
    private var smcTried = false
    private var cpuKeys: [SMCClient.Key] = []
    private var gpuKeys: [SMCClient.Key] = []
    private var batteryKeys: [SMCClient.Key] = []
    private var tempKeysPrepared = false

    // Samplers
    private let networkSampler = NetworkSampler()
    private var powerSampler: PowerSampler?

    // Running state
    private var previousCPUTicks: (busy: UInt64, total: UInt64)?
    private var tickCount = 0
    private var lastGPUUsage: Double?

    // History
    private let historyCapacity = 120
    private var cpuHistory: MetricHistory
    private var gpuHistory: MetricHistory
    private var memoryHistory: MetricHistory
    private var netDownHistory: MetricHistory
    private var netUpHistory: MetricHistory
    private var powerHistory: MetricHistory
    private var batteryHistory: MetricHistory

    private init() {
        cpuHistory = MetricHistory(capacity: historyCapacity)
        gpuHistory = MetricHistory(capacity: historyCapacity)
        memoryHistory = MetricHistory(capacity: historyCapacity)
        netDownHistory = MetricHistory(capacity: historyCapacity)
        netUpHistory = MetricHistory(capacity: historyCapacity)
        powerHistory = MetricHistory(capacity: historyCapacity)
        batteryHistory = MetricHistory(capacity: historyCapacity)
    }

    // MARK: - Lifecycle

    /// The panel became visible: sample everything, including the heavier
    /// temperature and GPU readings.
    func panelDidAppear() {
        panelClients += 1
        ensureTimer()
        refresh(full: true)
    }

    /// The panel closed: keep going only if a menu bar metric still needs it.
    func panelDidDisappear() {
        panelClients = max(0, panelClients - 1)
        stopTimerIfIdle()
    }

    /// Toggles continuous light sampling for the menu bar metrics.
    func setMenuBarActive(_ active: Bool) {
        guard active != menuBarActive else { return }
        menuBarActive = active
        if active {
            ensureTimer()
            refresh(full: panelVisible)
        } else {
            stopTimerIfIdle()
        }
    }

    /// Forces an immediate full refresh (e.g. after a memory purge).
    func refreshNow() {
        ensureTimer()
        refresh(full: true)
    }

    /// Changes the sampling cadence (seconds). Restarts a running timer.
    func setInterval(seconds: Int) {
        let clamped = max(1, seconds)
        guard clamped != intervalSeconds else { return }
        intervalSeconds = clamped
        if timer != nil { restartTimer() }
    }

    /// True while at least one panel surface (the popover, or an onboarding monitor
    /// step) is on screen. A depth count, not a bool, so overlapping appear/disappear
    /// from independent surfaces can't desync and leave the full-rate timer stuck on
    /// (battery drain) or freeze a still-open preview.
    private var panelVisible: Bool { panelClients > 0 }

    private var shouldRun: Bool { panelVisible || menuBarActive }

    /// In menu-bar-only mode the (relatively pricey) GPU read is throttled to
    /// about every 4 s; while the panel is open GPU samples every tick.
    private var gpuLightStride: Int { max(1, Int((4.0 / Double(intervalSeconds)).rounded())) }

    private func ensureTimer() {
        guard timer == nil, shouldRun else { return }
        startTimer()
    }

    private func stopTimerIfIdle() {
        guard !shouldRun else { return }
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        let t = Timer(timeInterval: TimeInterval(intervalSeconds), repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refresh(full: self.panelVisible)
        }
        t.tolerance = TimeInterval(intervalSeconds) * 0.15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        startTimer()
    }

    // MARK: - Refresh

    private func refresh(full: Bool) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.refresh(full: full) }
            return
        }
        if refreshInFlight {
            pendingFullRefresh = pendingFullRefresh || full
            return
        }
        refreshInFlight = true
        // Network and power are heavier to read, so sample them only when the
        // panel is open or that metric is pinned to the menu bar.
        let defaults = UserDefaults.standard
        let needNetwork = full || defaults.bool(forKey: DefaultsKey.menuBarNetwork)
        let needPower = full || defaults.bool(forKey: DefaultsKey.menuBarPower)
        let needGPU = full || defaults.bool(forKey: DefaultsKey.menuBarGPU)
        queue.async { [weak self] in
            guard let self else { return }
            self.prepareIfNeeded(full: full)
            let tick = self.tickCount
            self.tickCount &+= 1

            var next = SystemSnapshot()

            // Light readings — always cheap, always sampled.
            next.cpuUsage = self.readCPUUsage()
            if let cpu = next.cpuUsage { self.cpuHistory.push(cpu) }

            if let memory = SystemInfo.memoryUsage() {
                next.memoryUsed = memory.used
                next.memoryTotal = memory.total
                if memory.total > 0 {
                    self.memoryHistory.push(Double(memory.used) / Double(memory.total))
                }
            }
            next.memoryPressure = Self.readMemoryPressure()

            if needNetwork {
                let network = self.networkSampler.sample(now: ProcessInfo.processInfo.systemUptime)
                next.netDownBytesPerSec = network.downBytesPerSec
                next.netUpBytesPerSec = network.upBytesPerSec
                next.netTotalDown = network.totalDown
                next.netTotalUp = network.totalUp
                if let down = network.downBytesPerSec { self.netDownHistory.push(down) }
                if let up = network.upBytesPerSec { self.netUpHistory.push(up) }
            }

            if needPower, let powerSampler = self.powerSampler {
                let power = powerSampler.sample()
                next.power = power
                if let watts = power.systemWatts { self.powerHistory.push(watts) }
                if let charge = power.chargePercent { self.batteryHistory.push(Double(charge) / 100.0) }
            }

            // GPU usage is also wanted when pinned to the menu bar; temperatures
            // only matter while the panel is open. The GPU read is the priciest,
            // so in menu-bar-only mode it is throttled (gpuLightStride) and the
            // last value carried forward so the menu bar number stays stable.
            if needGPU {
                if full || tick % self.gpuLightStride == 0 {
                    self.lastGPUUsage = Self.readGPUUsage()
                    if let gpu = self.lastGPUUsage { self.gpuHistory.push(gpu) }
                }
                next.gpuUsage = self.lastGPUUsage
            }
            if full {
                next.cpuTemperature = self.maxTemperature(of: self.cpuKeys)
                next.gpuTemperature = self.maxTemperature(of: self.gpuKeys)
                next.batteryTemperature = self.maxTemperature(of: self.batteryKeys)
            }

            next.cpuHistory = self.cpuHistory.values
            next.gpuHistory = self.gpuHistory.values
            next.memoryHistory = self.memoryHistory.values
            next.netDownHistory = self.netDownHistory.values
            next.netUpHistory = self.netUpHistory.values
            next.systemPowerHistory = self.powerHistory.values
            next.batteryHistory = self.batteryHistory.values

            DispatchQueue.main.async {
                self.snapshot = next
                self.refreshInFlight = false
                let shouldRunFullRefresh = self.pendingFullRefresh
                self.pendingFullRefresh = false
                if shouldRunFullRefresh, self.shouldRun {
                    self.refresh(full: self.panelVisible)
                }
            }
        }
    }

    // MARK: - Sensor preparation

    /// Opens the SMC and resolves the power sampler once (cheap). Temperature key
    /// discovery is heavier (it enumerates every SMC key) so it waits for the
    /// first full sample — the menu-bar-only path never pays for it.
    private func prepareIfNeeded(full: Bool) {
        if !smcTried {
            smcTried = true
            smc = SMCClient()
            powerSampler = PowerSampler(smc: smc)
        }
        guard full, !tempKeysPrepared else { return }
        tempKeysPrepared = true
        guard let client = smc else { return }

        let all = client.keys { name in
            name.hasPrefix("Tp") || name.hasPrefix("Te") || name.hasPrefix("Tg")
                || name.range(of: "^TB[0-9]T$", options: .regularExpression) != nil
        }
        cpuKeys = all.filter { $0.name.hasPrefix("Tp") || $0.name.hasPrefix("Te") }
        gpuKeys = all.filter { $0.name.hasPrefix("Tg") }
        batteryKeys = all.filter { $0.name.hasPrefix("TB") }
    }

    private func maxTemperature(of keys: [SMCClient.Key]) -> Double? {
        guard let smc else { return nil }
        let values = keys.compactMap { key -> Double? in
            guard let v = smc.readValue(key), v > 1, v < 125 else { return nil }
            return v
        }
        return values.max()
    }

    // MARK: - CPU usage

    /// Aggregated load from HOST_CPU_LOAD_INFO; usage is the busy-tick share
    /// since the previous refresh.
    private func readCPUUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        // mach_host_self() returns a send right the caller owns; release it or each
        // call leaks a mach port (this runs on every sampling tick).
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle

        defer { previousCPUTicks = (busy, total) }
        guard let previous = previousCPUTicks, total > previous.total else { return nil }
        return Double(busy - previous.busy) / Double(total - previous.total)
    }

    // MARK: - GPU usage

    /// "Device Utilization %" published by the graphics accelerator
    /// (AGXAccelerator on Apple Silicon).
    private static func readGPUUsage() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            // Fetch ONLY PerformanceStatistics, not the whole (large) property
            // tree. Copying every property each tick is what made continuous GPU
            // sampling for the menu bar expensive.
            guard let ref = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString,
                                                            kCFAllocatorDefault, 0),
                  let stats = ref.takeRetainedValue() as? [String: Any],
                  let utilization = stats["Device Utilization %"] as? Int
            else { continue }
            return Double(utilization) / 100.0
        }
        return nil
    }

    // MARK: - Memory pressure

    private static func readMemoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        return MemoryPressure(kernelLevel: level)
    }
}
