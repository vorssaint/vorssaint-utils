// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation
import IOKit
import IOKit.ps

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
    var peripheralBatteries: [PeripheralBatteryDevice] = []

    // Disk
    var disk: DiskReading?

    // History (oldest → newest) for the graphs
    var cpuHistory: [Double] = []          // 0...1
    var gpuHistory: [Double] = []          // 0...1
    var memoryHistory: [Double] = []       // 0...1
    var netDownHistory: [Double] = []      // bytes/sec
    var netUpHistory: [Double] = []        // bytes/sec
    var diskReadHistory: [Double] = []     // bytes/sec
    var diskWriteHistory: [Double] = []    // bytes/sec
    var systemPowerHistory: [Double] = []  // watts
    var batteryHistory: [Double] = []      // 0...1 charge level
}

/// What parts of the menu panel are actually visible right now. The popover can
/// be open on Keep Awake, Utilities or Controls; in those states the monitor
/// should not wake the heavier samplers just because the user clicked the icon.
struct SystemMonitorPanelNeeds: Equatable {
    var system = false
    var network = false
    var disk = false
    var power = false
    var cpu = false
    var gpu = false
    var memory = false
    var battery = false
    var peripheralBattery = false
    var cpuTemperature = false
    var gpuTemperature = false
    var batteryTemperature = false

    static let none = SystemMonitorPanelNeeds()

    var any: Bool {
        system || network || disk || power || cpu || gpu || memory || battery ||
            peripheralBattery || cpuTemperature || gpuTemperature || batteryTemperature
    }
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
    private var alertsActive = false
    private var refreshInFlight = false
    private var pendingRefresh = false
    private var pendingRefreshSuppressesGPU = false
    private var suppressGPUReadsUntil: TimeInterval = 0

    // SMC sensors
    private var smc: SMCClient?
    private var smcTried = false
    private var cpuKeys: [SMCClient.Key] = []
    /// The platform's known CPU core sensors (what the displayed value is
    /// actually computed from) and everything else, split once at discovery:
    /// each SMC read is a kernel call, so the per-tick read sticks to the
    /// core set and only sweeps the rest when the core set goes silent.
    private var preferredCPUKeys: [SMCClient.Key] = []
    private var fallbackCPUKeys: [SMCClient.Key] = []
    private var gpuKeys: [SMCClient.Key] = []
    private var batteryKeys: [SMCClient.Key] = []
    private var tempKeysPrepared = false
    private var cpuTemperaturePlatform: CPUTemperaturePlatform = .generic

    // Samplers
    private let networkSampler = NetworkSampler()
    private let diskSampler = DiskSampler()
    private let peripheralBatterySampler = PeripheralBatterySampler()
    private var powerSampler: PowerSampler?

    // Running state
    private var previousCPUTicks: (busy: UInt64, total: UInt64)?
    private var tickCount = 0
    /// Timer cadence in base ticks (GCD of the needed strides); 1 = every tick.
    private var scheduledWakeTicks = 1
    /// The plan the cadence was last derived from. Activation setters early
    /// return while their flag is unchanged, but a metric or alert toggle can
    /// still change the plan underneath a slow cadence — the comparison is
    /// what triggers the immediate resample instead of a wait of up to 60 s.
    private var lastSyncedPlan: SamplingPlan?
    private var lastCPUUsage: Double?
    private var missedCPUUsageSamples = 0
    private var lastGPUUsage: Double?
    private var missedGPUUsageSamples = 0
    private var memoryCache: CachedMemoryReading?
    private var cpuTemperatureCache: CachedSensorReading?
    private var gpuTemperatureCache: CachedSensorReading?
    private var batteryTemperatureCache: CachedSensorReading?
    private var lastDiskReading: DiskReading?
    private var lastPowerReading: PowerReading?
    private var lastPeripheralBatteries: [PeripheralBatteryDevice] = []
    private var lastPublishedPlan: SamplingPlan?
    private var lastPublishedForeground: Bool?

    // History
    private let historyCapacity = 120
    private var cpuHistory: MetricHistory
    private var gpuHistory: MetricHistory
    private var memoryHistory: MetricHistory
    private var netDownHistory: MetricHistory
    private var netUpHistory: MetricHistory
    private var diskReadHistory: MetricHistory
    private var diskWriteHistory: MetricHistory
    private var powerHistory: MetricHistory
    private var batteryHistory: MetricHistory
    private var powerSourceRunLoopSource: CFRunLoopSource?

    private init() {
        cpuHistory = MetricHistory(capacity: historyCapacity)
        gpuHistory = MetricHistory(capacity: historyCapacity)
        memoryHistory = MetricHistory(capacity: historyCapacity)
        netDownHistory = MetricHistory(capacity: historyCapacity)
        netUpHistory = MetricHistory(capacity: historyCapacity)
        diskReadHistory = MetricHistory(capacity: historyCapacity)
        diskWriteHistory = MetricHistory(capacity: historyCapacity)
        powerHistory = MetricHistory(capacity: historyCapacity)
        batteryHistory = MetricHistory(capacity: historyCapacity)
        installPowerSourceObserver()
    }

    deinit {
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }
    }

    // MARK: - Lifecycle

    /// The same system notification used by the reference battery monitor.
    /// It removes the normal background sampling delay after unplugging,
    /// charging changes or a newly calculated time-to-empty value.
    private func installPowerSourceObserver() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        powerSourceRunLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<SystemMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                guard monitor.shouldRun,
                      monitor.currentPlan(defaults: .standard).needPower else { return }
                monitor.refresh()
            }
        }, context).takeRetainedValue()
        if let powerSourceRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
        }
    }

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
            guard let self else { return }
            guard active != menuBarActive else {
                if active { resyncIfPlanChanged() }
                return
            }
            menuBarActive = active
            if active {
                ensureTimer()
                refresh()
            } else {
                stopTimerIfIdle()
            }
        }
    }

    /// Optional alert rules can keep only the necessary samplers alive even when
    /// no monitor UI is visible and no metric is pinned to the menu bar.
    func setAlertsActive(_ active: Bool) {
        runOnMain { [weak self] in
            guard let self else { return }
            guard active != alertsActive else {
                if active { resyncIfPlanChanged() }
                return
            }
            alertsActive = active
            if active {
                ensureTimer()
                refresh()
            } else {
                stopTimerIfIdle()
            }
        }
    }

    /// A settings change can swap which metrics are needed without flipping
    /// any activation flag. On a slow wake cadence the newly pinned metric
    /// would sit on its placeholder until the next wake (up to 60 s), so a
    /// changed plan resamples right away.
    private func resyncIfPlanChanged() {
        guard shouldSample() else { return }
        let plan = currentPlan(defaults: .standard)
        guard plan != lastSyncedPlan else { return }
        syncTimerCadence(plan: plan)
        refresh()
    }

    /// The hub switching a metric on or off changes the plan without touching
    /// any activation flag; resample right away like any settings change.
    func planDidChange() {
        runOnMain { [weak self] in self?.resyncIfPlanChanged() }
    }

    /// Changes the sampling cadence (seconds). Restarts a running timer.
    func setInterval(seconds: Int) {
        runOnMain { [weak self] in
            guard let self else { return }
            let clamped = max(1, seconds)
            guard clamped != intervalSeconds else { return }
            intervalSeconds = clamped
            // Strides are derived from the interval, so the wake cadence must
            // resync before the timer is rebuilt on the new base interval.
            syncTimerCadence(plan: currentPlan(defaults: .standard))
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

    private var shouldRun: Bool { fullMonitorVisible || menuPanelNeeds.any || menuBarActive || alertsActive }

    private func shouldSample(defaults: UserDefaults = .standard) -> Bool {
        shouldRun && currentPlan(defaults: defaults).any
    }

    private struct SamplingPlan: Equatable {
        var needCPU = false
        var needMemory = false
        var needNetwork = false
        var needDisk = false
        var needPower = false
        var needPeripheralBattery = false
        var needGPUUsage = false
        var needCPUTemperature = false
        var needGPUTemperature = false
        var needBatteryTemperature = false

        var needSMC: Bool { needPower || needTemperature }

        var needTemperature: Bool {
            needCPUTemperature || needGPUTemperature || needBatteryTemperature
        }

        var any: Bool {
            needCPU || needMemory || needNetwork || needDisk || needPower ||
                needPeripheralBattery || needGPUUsage || needTemperature
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
        let panelNeedsDisk = fullMonitorVisible || menuPanelNeeds.disk
        let panelNeedsPower = fullMonitorVisible || menuPanelNeeds.power

        let panelCPU = (panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysCPU)) || menuPanelNeeds.cpu
        let panelGPU = (panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysGPU)) || menuPanelNeeds.gpu
        let panelMemory = (panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysMemory)) || menuPanelNeeds.memory
        let panelBattery = (panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysBattery)) || menuPanelNeeds.battery
        let panelTemps = panelNeedsSystem && defaults.bool(forKey: DefaultsKey.monitorSysTemps)
        let alertCPU = defaults.bool(forKey: DefaultsKey.monitorAlertCPU)
        let alertCPUTemperature = defaults.bool(forKey: DefaultsKey.monitorAlertCPUTemperature)
        let alertMemory = defaults.bool(forKey: DefaultsKey.monitorAlertMemory)
        let alertDisk = defaults.bool(forKey: DefaultsKey.monitorAlertDisk)
        let alertBattery = defaults.bool(forKey: DefaultsKey.monitorAlertBattery)

        plan.needCPU = panelCPU || defaults.bool(forKey: DefaultsKey.menuBarCPU) || alertCPU
        plan.needMemory = panelMemory || defaults.bool(forKey: DefaultsKey.menuBarMemory) || alertMemory
        plan.needNetwork = panelNeedsNetwork || defaults.bool(forKey: DefaultsKey.menuBarNetwork)
        plan.needDisk = panelNeedsDisk
            || defaults.bool(forKey: DefaultsKey.menuBarDiskUsage)
            || defaults.bool(forKey: DefaultsKey.menuBarDiskActivity)
            || alertDisk
        plan.needPower = panelNeedsPower || panelBattery
            || defaults.bool(forKey: DefaultsKey.menuBarPower)
            || defaults.bool(forKey: DefaultsKey.menuBarBattery)
            || defaults.bool(forKey: DefaultsKey.menuBarBatteryTime)
            || alertBattery
        plan.needPeripheralBattery = menuPanelNeeds.peripheralBattery
            || defaults.bool(forKey: DefaultsKey.menuBarPeripheralBattery)
        plan.needGPUUsage = panelGPU || defaults.bool(forKey: DefaultsKey.menuBarGPU)
        plan.needCPUTemperature = panelTemps || menuPanelNeeds.cpuTemperature ||
            defaults.bool(forKey: DefaultsKey.menuBarCPUTemperature) || alertCPUTemperature
        plan.needGPUTemperature = panelTemps || menuPanelNeeds.gpuTemperature ||
            defaults.bool(forKey: DefaultsKey.menuBarGPUTemperature)
        plan.needBatteryTemperature = panelTemps || menuPanelNeeds.batteryTemperature ||
            defaults.bool(forKey: DefaultsKey.menuBarBatteryTemperature)

        // The hub gates whole metric families: an unavailable metric never
        // samples, no matter what is pinned, shown or alerting.
        func available(_ feature: AppFeature) -> Bool {
            defaults.bool(forKey: feature.availabilityKey)
        }
        if !available(.monitorCPU) {
            plan.needCPU = false
            plan.needCPUTemperature = false
        }
        if !available(.monitorGPU) {
            plan.needGPUUsage = false
            plan.needGPUTemperature = false
        }
        if !available(.monitorMemory) { plan.needMemory = false }
        if !available(.monitorNetwork) { plan.needNetwork = false }
        if !available(.monitorDisk) { plan.needDisk = false }
        if !available(.monitorPower) {
            plan.needPower = false
            plan.needPeripheralBattery = false
            plan.needBatteryTemperature = false
        }
        return plan
    }

    private func ensureTimer() {
        guard shouldSample() else { return }
        syncTimerCadence(plan: currentPlan(defaults: .standard))
        guard timer == nil else { return }
        startTimer()
    }

    private func stopTimerIfIdle() {
        guard !shouldSample() else { return }
        timer?.invalidate()
        timer = nil
    }

    /// Keeps the timer waking only when the next needed sample can be due.
    /// The cadence is the GCD of the needed strides, so every sample still
    /// lands exactly on its original schedule; the tick counter is realigned
    /// onto the new grid or `tick % stride` could become unreachable.
    private func syncTimerCadence(plan: SamplingPlan) {
        lastSyncedPlan = plan
        let foreground = fullMonitorVisible || menuPanelNeeds.any
        let desired = MonitorSamplingPolicy.wakeTicks(for: Self.neededKinds(of: plan),
                                                      intervalSeconds: intervalSeconds,
                                                      foreground: foreground)
        guard desired != scheduledWakeTicks else { return }
        scheduledWakeTicks = desired
        tickCount = MonitorSamplingPolicy.alignedTick(tickCount, wakeTicks: desired)
        if timer != nil {
            restartTimer()
        }
    }

    private static func neededKinds(of plan: SamplingPlan) -> [MonitorSamplingKind] {
        var kinds: [MonitorSamplingKind] = []
        if plan.needCPU { kinds.append(.cpu) }
        if plan.needMemory { kinds.append(.memory) }
        if plan.needNetwork { kinds.append(.network) }
        if plan.needDisk { kinds.append(.disk) }
        if plan.needPower { kinds.append(.power) }
        if plan.needPeripheralBattery { kinds.append(.peripheralBattery) }
        if plan.needGPUUsage { kinds.append(.gpuUsage) }
        if plan.needTemperature { kinds.append(.temperature) }
        return kinds
    }

    private func startTimer() {
        let cadenceSeconds = TimeInterval(intervalSeconds * scheduledWakeTicks)
        let t = Timer(timeInterval: cadenceSeconds, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        t.tolerance = cadenceSeconds * 0.15
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
        syncTimerCadence(plan: plan)
        refreshInFlight = true
        let suppressGPUReadsUntil = self.suppressGPUReadsUntil
        let foregroundSampling = fullMonitorVisible || menuPanelNeeds.any
        let intervalSeconds = self.intervalSeconds
        // Ticks advance by the timer's cadence so `tick % stride` keeps
        // measuring base intervals; mutated on main only, read by the queue
        // through the captured value.
        let tick = tickCount
        tickCount &+= scheduledWakeTicks
        queue.async { [weak self] in
            guard let self else { return }
            self.prepareIfNeeded(needSMC: plan.needSMC, needTemperature: plan.needTemperature)
            let now = ProcessInfo.processInfo.systemUptime

            var next = SystemSnapshot()

            // Publishing a snapshot redraws the menu bar (attributed-string
            // rebuild + width measurement); on ticks where every needed metric
            // was stride-skipped the values are pure carry-over, so the publish
            // is skipped below to save that work.
            var sampledAnything = false
            func take(_ kind: MonitorSamplingKind) -> Bool {
                let sample = MonitorSamplingPolicy.shouldSample(kind,
                                                                tick: tick,
                                                                intervalSeconds: intervalSeconds,
                                                                foreground: foregroundSampling)
                if sample { sampledAnything = true }
                return sample
            }

            if plan.needCPU {
                if take(.cpu),
                   let cpu = self.readCPUUsage() {
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
                if take(.memory),
                   let memory = self.stabilizedMemoryReading(now: now) {
                    next.memoryUsed = memory.used
                    next.memoryTotal = memory.total
                    next.memoryPressure = memory.pressure
                    if memory.isFresh, memory.total > 0 {
                        self.memoryHistory.push(Double(memory.used) / Double(memory.total))
                    }
                }
            }

            if plan.needNetwork {
                if take(.network) {
                    let network = self.networkSampler.sample(now: now)
                    next.netDownBytesPerSec = network.downBytesPerSec
                    next.netUpBytesPerSec = network.upBytesPerSec
                    next.netTotalDown = network.totalDown
                    next.netTotalUp = network.totalUp
                    if let down = network.downBytesPerSec { self.netDownHistory.push(down) }
                    if let up = network.upBytesPerSec { self.netUpHistory.push(up) }
                }
            }

            if plan.needDisk {
                if take(.disk) {
                    let disk = self.diskSampler.sample(now: now, refreshMetadata: foregroundSampling)
                    self.lastDiskReading = disk
                    next.disk = disk
                    let ioDevices = disk.uniqueIODevices
                    let readValues = ioDevices.compactMap(\.readBytesPerSec)
                    let writeValues = ioDevices.compactMap(\.writeBytesPerSec)
                    if !readValues.isEmpty {
                        self.diskReadHistory.push(readValues.reduce(0, +))
                    }
                    if !writeValues.isEmpty {
                        self.diskWriteHistory.push(writeValues.reduce(0, +))
                    }
                } else {
                    next.disk = self.lastDiskReading
                }
            }

            if plan.needPower, let powerSampler = self.powerSampler {
                if take(.power) {
                    let power = powerSampler.sample()
                    self.lastPowerReading = power
                    next.power = power
                    if let watts = power.systemWatts { self.powerHistory.push(watts) }
                    if let charge = power.chargePercent { self.batteryHistory.push(Double(charge) / 100.0) }
                } else {
                    next.power = self.lastPowerReading
                }
            }

            if plan.needPeripheralBattery {
                if take(.peripheralBattery) {
                    self.lastPeripheralBatteries = self.peripheralBatterySampler.sample(now: now)
                }
                next.peripheralBatteries = self.lastPeripheralBatteries
            }

            // GPU usage is the priciest normal monitor read. When the panel first
            // opens, skip the immediate read so the popover animation does not
            // become a visible one-sample GPU spike. A deferred refresh follows.
            if plan.needGPUUsage {
                let suppressGPUForUI = suppressImmediateGPU || now < suppressGPUReadsUntil
                let shouldSampleGPU = !suppressGPUForUI && take(.gpuUsage)
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
            // The anti-glitch bridge must span a couple of sampling gaps or it
            // is useless on the slow background cadence (15 s): one bad SMC
            // read would land past the window and blank the metric.
            let temperatureGap = TimeInterval(MonitorSamplingPolicy.sampleStride(
                for: .temperature,
                intervalSeconds: intervalSeconds,
                foreground: foregroundSampling) * intervalSeconds)
            let temperatureBridge = max(12, temperatureGap * 2.2)
            if plan.needCPUTemperature {
                if take(.temperature) {
                    next.cpuTemperature = Self.stabilizedTemperature(self.cpuTemperature(),
                                                                     cache: &self.cpuTemperatureCache,
                                                                     now: now,
                                                                     maxAge: temperatureBridge)
                } else {
                    next.cpuTemperature = self.cpuTemperatureCache?.value
                }
            }
            if plan.needGPUTemperature {
                if take(.temperature) {
                    next.gpuTemperature = Self.stabilizedTemperature(self.maxTemperature(of: self.gpuKeys),
                                                                     cache: &self.gpuTemperatureCache,
                                                                     now: now,
                                                                     maxAge: temperatureBridge)
                } else {
                    next.gpuTemperature = self.gpuTemperatureCache?.value
                }
            }
            if plan.needBatteryTemperature {
                if take(.temperature) {
                    next.batteryTemperature = Self.stabilizedTemperature(self.maxTemperature(of: self.batteryKeys),
                                                                         cache: &self.batteryTemperatureCache,
                                                                         now: now,
                                                                         maxAge: temperatureBridge)
                } else {
                    next.batteryTemperature = self.batteryTemperatureCache?.value
                }
            }

            next.cpuHistory = plan.needCPU ? self.cpuHistory.values : []
            next.gpuHistory = plan.needGPUUsage ? self.gpuHistory.values : []
            next.memoryHistory = plan.needMemory ? self.memoryHistory.values : []
            next.netDownHistory = plan.needNetwork ? self.netDownHistory.values : []
            next.netUpHistory = plan.needNetwork ? self.netUpHistory.values : []
            next.diskReadHistory = plan.needDisk ? self.diskReadHistory.values : []
            next.diskWriteHistory = plan.needDisk ? self.diskWriteHistory.values : []
            next.systemPowerHistory = plan.needPower ? self.powerHistory.values : []
            next.batteryHistory = plan.needPower ? self.batteryHistory.values : []

            DispatchQueue.main.async {
                // Skip pure carry-over publishes (nothing sampled, same plan,
                // same mode): the values are identical to the ones on screen.
                let planChanged = plan != self.lastPublishedPlan
                    || foregroundSampling != self.lastPublishedForeground
                if sampledAnything || planChanged {
                    self.snapshot = next
                    self.lastPublishedPlan = plan
                    self.lastPublishedForeground = foregroundSampling
                }
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
                                              now: TimeInterval,
                                              maxAge: TimeInterval) -> Double? {
        if let reading, reading > 1, reading < 125 {
            cache = CachedSensorReading(value: reading, updatedAt: now, missedSamples: 0)
            return reading
        }
        guard var cached = cache else { return nil }
        cached.missedSamples += 1
        if cached.missedSamples <= 4, now - cached.updatedAt <= maxAge {
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
        preferredCPUKeys = cpuKeys.filter {
            TemperatureSensorSelector.isCPUCoreKey($0.name, platform: cpuTemperaturePlatform)
        }
        let preferredNames = Set(preferredCPUKeys.map(\.name))
        fallbackCPUKeys = cpuKeys.filter { !preferredNames.contains($0.name) }
        gpuKeys = all.filter { $0.name.hasPrefix("Tg") }
        batteryKeys = all.filter { $0.name.hasPrefix("TB") }
    }

    private func cpuTemperature() -> Double? {
        guard smc != nil else { return nil }
        // The core set decides the displayed value whenever it answers, so a
        // normal tick reads only those keys; the remaining Tp/Te keys are
        // swept exactly when they would have mattered before the split —
        // unknown platforms (empty core set) or a tick with no plausible
        // core reading.
        var readings = temperatureReadings(of: preferredCPUKeys)
        if let value = TemperatureSensorSelector.displayedCPUTemperature(readings: readings,
                                                                         platform: cpuTemperaturePlatform) {
            return value
        }
        readings += temperatureReadings(of: fallbackCPUKeys)
        return TemperatureSensorSelector.displayedCPUTemperature(readings: readings,
                                                                 platform: cpuTemperaturePlatform)
    }

    private func temperatureReadings(of keys: [SMCClient.Key]) -> [(key: String, value: Double)] {
        guard let smc else { return [] }
        return keys.compactMap { key -> (key: String, value: Double)? in
            guard let value = smc.readValue(key) else { return nil }
            return (key.name, value)
        }
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
