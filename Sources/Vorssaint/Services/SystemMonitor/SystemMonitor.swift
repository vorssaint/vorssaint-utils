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

/// What parts of the menu panel are actually visible right now. The popover can
/// be open on Keep Awake, Utilities or Controls; in those states the monitor
/// should not wake the heavier samplers just because the user clicked the icon.
struct SystemMonitorPanelNeeds: Equatable {
    var system = false
    var network = false
    var power = false

    static let none = SystemMonitorPanelNeeds()

    var any: Bool { system || network || power }
}

/// Reads temperatures (SMC), CPU/GPU usage, memory, network and power on a
/// background queue. Runs while the panel is visible (full readings) and/or
/// while a menu bar metric is enabled (only the readings that metric needs).
/// When nothing needs it, the timer stops — zero idle cost.
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published private(set) var snapshot = SystemSnapshot()

    private let queue = DispatchQueue(label: "com.vorssaint.utils.system-monitor", qos: .utility)
    private var timer: Timer?
    private var intervalSeconds = 2
    private var panelClients = 0
    private var menuPanelNeeds: SystemMonitorPanelNeeds = .none
    private var menuBarActive = false
    private var refreshInFlight = false
    private var pendingRefresh = false
    private var pendingRefreshSuppressesGPU = false
    private var suppressGPUReadsUntil: TimeInterval = 0

    // SMC sensors
    private var smc: SMCClient?
    private var smcTried = false
    private var cpuKeys: [SMCClient.Key] = []
    private var gpuKeys: [SMCClient.Key] = []
    private var batteryKeys: [SMCClient.Key] = []
    private var tempKeysPrepared = false
    private var cpuTemperaturePlatform: CPUTemperaturePlatform = .generic

    // Samplers
    private let networkSampler = NetworkSampler()
    private var powerSampler: PowerSampler?

    // Running state
    private var previousCPUTicks: (busy: UInt64, total: UInt64)?
    private var tickCount = 0
    private var lastCPUUsage: Double?
    private var missedCPUUsageSamples = 0
    private var lastGPUUsage: Double?
    private var missedGPUUsageSamples = 0
    private var memoryCache: CachedMemoryReading?
    private var cpuTemperatureCache: CachedSensorReading?
    private var gpuTemperatureCache: CachedSensorReading?
    private var batteryTemperatureCache: CachedSensorReading?

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

    /// A full monitor surface became visible (Settings preview or onboarding).
    func panelDidAppear() {
        runOnMain { [weak self] in
            guard let self else { return }
            panelClients += 1
            ensureTimer()
            refresh(suppressImmediateGPU: true)
            scheduleDeferredGPURefreshIfNeeded()
        }
    }

    /// A full monitor surface closed: keep going only if the menu panel or menu
    /// bar metrics still need readings.
    func panelDidDisappear() {
        runOnMain { [weak self] in
            guard let self else { return }
            panelClients = max(0, panelClients - 1)
            stopTimerIfIdle()
        }
    }

    /// The menu popover reports exactly which monitor sections are on screen.
    /// This avoids paying for GPU, network or power reads while the panel is open
    /// on another section.
    func setMenuPanelNeeds(_ needs: SystemMonitorPanelNeeds) {
        runOnMain { [weak self] in
            guard let self else { return }
            if needs == menuPanelNeeds {
                if shouldRun {
                    ensureTimer()
                    refresh()
                } else {
                    stopTimerIfIdle()
                }
                return
            }
            let defaults = UserDefaults.standard
            let previousNeeds = menuPanelNeeds
            let neededGPUBefore = currentPlan(defaults: defaults).needGPUUsage
            menuPanelNeeds = needs
            let needsGPUAfter = currentPlan(defaults: defaults).needGPUUsage
            if shouldRun {
                ensureTimer()
                let panelGPUBecameVisible = needs.system
                    && !previousNeeds.system
                    && defaults.bool(forKey: DefaultsKey.monitorSysGPU)
                let suppressImmediateGPU = needsGPUAfter && (!neededGPUBefore || panelGPUBecameVisible)
                refresh(suppressImmediateGPU: suppressImmediateGPU)
                if suppressImmediateGPU {
                    scheduleDeferredGPURefreshIfNeeded()
                }
            } else {
                stopTimerIfIdle()
            }
        }
    }

    /// The menu popover animation can briefly raise compositor GPU usage. When
    /// GPU is pinned to the menu bar, keep the previous value through that short
    /// window instead of sampling the animation itself.
    func suppressGPUReadsForTransientUI(duration: TimeInterval = 0.9) {
        runOnMain { [weak self] in
            guard let self else { return }
            let until = ProcessInfo.processInfo.systemUptime + max(0.1, duration)
            suppressGPUReadsUntil = max(suppressGPUReadsUntil, until)
            if shouldSample(), currentPlan(defaults: .standard).needGPUUsage {
                scheduleDeferredGPURefreshIfNeeded()
            }
        }
    }

    /// Toggles continuous light sampling for the menu bar metrics.
    func setMenuBarActive(_ active: Bool) {
        runOnMain { [weak self] in
            guard let self, active != menuBarActive else { return }
            menuBarActive = active
            if active {
                ensureTimer()
                refresh()
            } else {
                stopTimerIfIdle()
            }
        }
    }

    /// Changes the sampling cadence (seconds). Restarts a running timer.
    func setInterval(seconds: Int) {
        runOnMain { [weak self] in
            guard let self else { return }
            let clamped = max(1, seconds)
            guard clamped != intervalSeconds else { return }
            intervalSeconds = clamped
            if timer != nil { restartTimer() }
        }
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async { work() }
        }
    }

    private func scheduleDeferredGPURefreshIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self,
                  self.shouldRun,
                  self.currentPlan(defaults: .standard).needGPUUsage else { return }
            self.refresh()
        }
    }

    /// True while at least one full monitor surface (Settings or onboarding) is
    /// on screen. A depth count, not a bool, so overlapping appear/disappear from
    /// independent surfaces cannot desync.
    private var fullMonitorVisible: Bool { panelClients > 0 }

    private var shouldRun: Bool { fullMonitorVisible || menuPanelNeeds.any || menuBarActive }

    private func shouldSample(defaults: UserDefaults = .standard) -> Bool {
        shouldRun && currentPlan(defaults: defaults).any
    }

    private struct SamplingPlan {
        var needCPU = false
        var needMemory = false
        var needNetwork = false
        var needPower = false
        var needGPUUsage = false
        var gpuEveryTick = false
        var needCPUTemperature = false
        var needGPUTemperature = false
        var needBatteryTemperature = false

        var needSMC: Bool { needPower || needTemperature }

        var needTemperature: Bool {
            needCPUTemperature || needGPUTemperature || needBatteryTemperature
        }

        var any: Bool {
            needCPU || needMemory || needNetwork || needPower || needGPUUsage || needTemperature
        }
    }

    private struct CachedSensorReading {
        var value: Double
        var updatedAt: TimeInterval
        var missedSamples: Int
    }

    private struct CachedMemoryReading {
        var used: UInt64
        var total: UInt64
        var pressure: MemoryPressure
        var updatedAt: TimeInterval
        var missedSamples: Int
    }

    private func currentPlan(defaults: UserDefaults) -> SamplingPlan {
        var plan = SamplingPlan()
        let panelNeedsSystem = fullMonitorVisible || menuPanelNeeds.system
        let panelNeedsNetwork = fullMonitorVisible || menuPanelNeeds.network
        let panelNeedsPower = fullMonitorVisible || menuPanelNeeds.power

        let panelCPU = panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysCPU)
        let panelGPU = panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysGPU)
        let panelMemory = panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysMemory)
        let panelBattery = panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysBattery)
        let panelTemps = panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysTemps)

        plan.needCPU = panelCPU || defaults.bool(forKey: DefaultsKey.menuBarCPU)
        plan.needMemory = panelMemory || defaults.bool(forKey: DefaultsKey.menuBarMemory)
        plan.needNetwork = panelNeedsNetwork || defaults.bool(forKey: DefaultsKey.menuBarNetwork)
        plan.needPower = panelNeedsPower || panelBattery
            || defaults.bool(forKey: DefaultsKey.menuBarPower)
            || defaults.bool(forKey: DefaultsKey.menuBarBattery)
        plan.needGPUUsage = panelGPU || defaults.bool(forKey: DefaultsKey.menuBarGPU)
        plan.gpuEveryTick = panelGPU
        plan.needCPUTemperature = panelTemps || defaults.bool(forKey: DefaultsKey.menuBarCPUTemperature)
        plan.needGPUTemperature = panelTemps || defaults.bool(forKey: DefaultsKey.menuBarGPUTemperature)
        plan.needBatteryTemperature = panelTemps || defaults.bool(forKey: DefaultsKey.menuBarBatteryTemperature)
        return plan
    }

    /// In menu-bar-only mode the (relatively pricey) GPU read is throttled to
    /// about every 4 s; while the panel is open GPU samples every tick.
    private var gpuLightStride: Int { max(1, Int((4.0 / Double(intervalSeconds)).rounded())) }

    private func ensureTimer() {
        guard timer == nil, shouldSample() else { return }
        startTimer()
    }

    private func stopTimerIfIdle() {
        guard !shouldSample() else { return }
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        let t = Timer(timeInterval: TimeInterval(intervalSeconds), repeats: true) { [weak self] _ in
            self?.refresh()
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

    private func refresh(suppressImmediateGPU: Bool = false) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.refresh(suppressImmediateGPU: suppressImmediateGPU) }
            return
        }
        let defaults = UserDefaults.standard
        let plan = currentPlan(defaults: defaults)
        guard plan.any else {
            stopTimerIfIdle()
            return
        }
        if refreshInFlight {
            pendingRefresh = true
            pendingRefreshSuppressesGPU = pendingRefreshSuppressesGPU || suppressImmediateGPU
            return
        }
        refreshInFlight = true
        let suppressGPUReadsUntil = self.suppressGPUReadsUntil
        queue.async { [weak self] in
            guard let self else { return }
            self.prepareIfNeeded(needSMC: plan.needSMC, needTemperature: plan.needTemperature)
            let tick = self.tickCount
            self.tickCount &+= 1
            let now = ProcessInfo.processInfo.systemUptime

            var next = SystemSnapshot()

            if plan.needCPU {
                if let cpu = self.readCPUUsage() {
                    self.lastCPUUsage = cpu
                    self.missedCPUUsageSamples = 0
                    self.cpuHistory.push(cpu)
                } else if self.missedCPUUsageSamples < 3 {
                    self.missedCPUUsageSamples += 1
                } else {
                    self.lastCPUUsage = nil
                }
                next.cpuUsage = self.lastCPUUsage
            }

            if plan.needMemory {
                if let memory = self.stabilizedMemoryReading(now: now) {
                    next.memoryUsed = memory.used
                    next.memoryTotal = memory.total
                    next.memoryPressure = memory.pressure
                    if memory.isFresh, memory.total > 0 {
                        self.memoryHistory.push(Double(memory.used) / Double(memory.total))
                    }
                }
            }

            if plan.needNetwork {
                let network = self.networkSampler.sample(now: now)
                next.netDownBytesPerSec = network.downBytesPerSec
                next.netUpBytesPerSec = network.upBytesPerSec
                next.netTotalDown = network.totalDown
                next.netTotalUp = network.totalUp
                if let down = network.downBytesPerSec { self.netDownHistory.push(down) }
                if let up = network.upBytesPerSec { self.netUpHistory.push(up) }
            }

            if plan.needPower, let powerSampler = self.powerSampler {
                let power = powerSampler.sample()
                next.power = power
                if let watts = power.systemWatts { self.powerHistory.push(watts) }
                if let charge = power.chargePercent { self.batteryHistory.push(Double(charge) / 100.0) }
            }

            // GPU usage is the priciest normal monitor read. When the panel first
            // opens, skip the immediate read so the popover animation does not
            // become a visible one-sample GPU spike. A deferred refresh follows.
            if plan.needGPUUsage {
                let suppressGPUForUI = suppressImmediateGPU || now < suppressGPUReadsUntil
                let shouldSampleGPU = !suppressGPUForUI
                    && (plan.gpuEveryTick || tick % self.gpuLightStride == 0)
                if shouldSampleGPU {
                    if let rawGPU = Self.readGPUUsage() {
                        self.lastGPUUsage = MetricFormat.stabilizedGPUUsage(previous: self.lastGPUUsage,
                                                                            current: rawGPU)
                        self.missedGPUUsageSamples = 0
                        if let gpu = self.lastGPUUsage { self.gpuHistory.push(gpu) }
                    } else if self.missedGPUUsageSamples < 3 {
                        self.missedGPUUsageSamples += 1
                    } else {
                        self.lastGPUUsage = nil
                    }
                }
                next.gpuUsage = self.lastGPUUsage
            }
            if plan.needCPUTemperature {
                next.cpuTemperature = Self.stabilizedTemperature(self.cpuTemperature(),
                                                                 cache: &self.cpuTemperatureCache,
                                                                 now: now)
            }
            if plan.needGPUTemperature {
                next.gpuTemperature = Self.stabilizedTemperature(self.maxTemperature(of: self.gpuKeys),
                                                                 cache: &self.gpuTemperatureCache,
                                                                 now: now)
            }
            if plan.needBatteryTemperature {
                next.batteryTemperature = Self.stabilizedTemperature(self.maxTemperature(of: self.batteryKeys),
                                                                     cache: &self.batteryTemperatureCache,
                                                                     now: now)
            }

            next.cpuHistory = plan.needCPU ? self.cpuHistory.values : []
            next.gpuHistory = plan.needGPUUsage ? self.gpuHistory.values : []
            next.memoryHistory = plan.needMemory ? self.memoryHistory.values : []
            next.netDownHistory = plan.needNetwork ? self.netDownHistory.values : []
            next.netUpHistory = plan.needNetwork ? self.netUpHistory.values : []
            next.systemPowerHistory = plan.needPower ? self.powerHistory.values : []
            next.batteryHistory = plan.needPower ? self.batteryHistory.values : []

            DispatchQueue.main.async {
                self.snapshot = next
                self.refreshInFlight = false
                let shouldRunPendingRefresh = self.pendingRefresh
                let suppressGPU = self.pendingRefreshSuppressesGPU
                self.pendingRefresh = false
                self.pendingRefreshSuppressesGPU = false
                if shouldRunPendingRefresh, self.shouldRun {
                    self.refresh(suppressImmediateGPU: suppressGPU)
                }
            }
        }
    }

    private func stabilizedMemoryReading(now: TimeInterval) -> (used: UInt64, total: UInt64, pressure: MemoryPressure, isFresh: Bool)? {
        let pressure = Self.readMemoryPressure()
        if let memory = SystemInfo.memoryUsage(), memory.total > 0 {
            let stablePressure: MemoryPressure
            switch pressure {
            case .unknown:
                stablePressure = memoryCache?.pressure ?? .unknown
            case .normal, .warning, .critical:
                stablePressure = pressure
            }
            memoryCache = CachedMemoryReading(used: memory.used,
                                              total: memory.total,
                                              pressure: stablePressure,
                                              updatedAt: now,
                                              missedSamples: 0)
            return (memory.used, memory.total, stablePressure, true)
        }

        guard var cached = memoryCache else { return nil }
        cached.missedSamples += 1
        guard cached.missedSamples <= 4, now - cached.updatedAt <= 12 else {
            memoryCache = nil
            return nil
        }

        switch pressure {
        case .normal, .warning, .critical:
            cached.pressure = pressure
        case .unknown:
            break
        }
        memoryCache = cached
        return (cached.used, cached.total, cached.pressure, false)
    }

    private static func stabilizedTemperature(_ reading: Double?,
                                              cache: inout CachedSensorReading?,
                                              now: TimeInterval) -> Double? {
        if let reading, reading > 1, reading < 125 {
            cache = CachedSensorReading(value: reading, updatedAt: now, missedSamples: 0)
            return reading
        }
        guard var cached = cache else { return nil }
        cached.missedSamples += 1
        if cached.missedSamples <= 4, now - cached.updatedAt <= 12 {
            cache = cached
            return cached.value
        }
        cache = nil
        return nil
    }

    // MARK: - Sensor preparation

    /// Opens the SMC lazily. Temperature key discovery is heavier (it enumerates
    /// every SMC key) so it waits until the panel or a pinned temperature metric
    /// actually needs it.
    private func prepareIfNeeded(needSMC: Bool, needTemperature: Bool) {
        if needSMC, !smcTried {
            smcTried = true
            smc = SMCClient()
            cpuTemperaturePlatform = TemperatureSensorSelector.currentPlatform()
            powerSampler = PowerSampler(smc: smc)
        }
        guard needTemperature, !tempKeysPrepared else { return }
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

    private func cpuTemperature() -> Double? {
        guard let smc else { return nil }
        let readings = cpuKeys.compactMap { key -> (key: String, value: Double)? in
            guard let value = smc.readValue(key) else { return nil }
            return (key.name, value)
        }
        return TemperatureSensorSelector.displayedCPUTemperature(readings: readings,
                                                                 platform: cpuTemperaturePlatform)
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
