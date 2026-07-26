// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Which per-app breakdown is expanded in the System section.
enum BreakdownKind {
    case cpu, gpu, memory, energy, network
}

/// The "System" section of the panel: component temperatures, hardware usage
/// and memory pressure, only the readings that matter, presented cleanly.
/// Tapping CPU, GPU, Battery or Memory expands the top consumers of that resource.
struct SystemSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.colorScheme) private var colorScheme
    var collapsible = true
    @State private var expanded: BreakdownKind?
    @State private var alertsExpanded = false
    @State private var uptimeExpanded = false
    @State private var diskExpanded = false
    @State private var breakdownRows: [ProcessUsage] = []
    @State private var breakdownIsLoading = false
    @State private var lastBreakdownRefresh = Date.distantPast
    private let breakdownLimit = 15
    @AppStorage(DefaultsKey.monitorGraphCPU) private var graphCPU = true
    @AppStorage(DefaultsKey.monitorGraphGPU) private var graphGPU = true
    @AppStorage(DefaultsKey.monitorGraphMemory) private var graphMemory = true
    @AppStorage(DefaultsKey.monitorGraphBattery) private var graphBattery = true
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.menuBarCPU) private var menuBarCPU = false
    @AppStorage(DefaultsKey.menuBarGPU) private var menuBarGPU = false
    @AppStorage(DefaultsKey.menuBarMemory) private var menuBarMemory = false
    @AppStorage(DefaultsKey.menuBarCPUTemperature) private var menuBarCPUTemperature = false
    @AppStorage(DefaultsKey.menuBarGPUTemperature) private var menuBarGPUTemperature = false
    @AppStorage(DefaultsKey.menuBarBatteryTemperature) private var menuBarBatteryTemperature = false
    @AppStorage(DefaultsKey.menuBarNetwork) private var menuBarNetwork = false
    @AppStorage(DefaultsKey.menuBarBattery) private var menuBarBattery = false
    @AppStorage(DefaultsKey.menuBarBatteryTime) private var menuBarBatteryTime = false
    @AppStorage(DefaultsKey.menuBarPeripheralBattery) private var menuBarPeripheralBattery = false
    @AppStorage(DefaultsKey.menuBarPower) private var menuBarPower = false
    @AppStorage(DefaultsKey.menuBarSeparateMetrics) private var separateMenuBarMetrics = false
    @AppStorage(DefaultsKey.monitorSysTemps) private var sysTemps = true
    @AppStorage(DefaultsKey.monitorSysSensors) private var sysSensors = true
    @AppStorage(DefaultsKey.monitorSysSensorsExpanded) private var sensorsExpanded = true
    @AppStorage(DefaultsKey.monitorSysCPU) private var sysCPU = true
    @AppStorage(DefaultsKey.monitorSysGPU) private var sysGPU = true
    @AppStorage(DefaultsKey.monitorSysBattery) private var sysBattery = true
    @AppStorage(DefaultsKey.monitorSysMemory) private var sysMemory = true
    @AppStorage(DefaultsKey.monitorSysDisk) private var sysDisk = true
    @AppStorage(DefaultsKey.monitorSysNetwork) private var sysNetwork = true
    @AppStorage(DefaultsKey.monitorSysAlerts) private var sysAlerts = true
    @AppStorage(DefaultsKey.monitorSysUptime) private var sysUptime = true
    @AppStorage(DefaultsKey.panelSystemOrder) private var systemOrderRaw = ""
    @State private var draggingBlock: Block?
    // Transient hover reveal for the Sensors list: hovering the temperature
    // wheels opens it (iStats-style), released after a short grace period so
    // sliding onto the list doesn't collapse it. ORs with the pinned toggle.
    @State private var hoverSensors = false
    @State private var hoverSensorsToken = 0

    var body: some View {
        PanelSection(.system, title: l10n.s.systemSection, collapsible: collapsible,
                     supportsEditing: true,
                     resetAction: resetPanelDefaults) { editing in
            VStack(alignment: .leading, spacing: 10) {
                let currentBlocks = blocks(editing: editing)
                if hasMenuBarMetric {
                    menuBarMetricModeControl
                    if !currentBlocks.isEmpty {
                        Divider()
                    }
                }
                ForEach(Array(currentBlocks.enumerated()), id: \.element) { index, block in
                    if index > 0 { Divider() }
                    PanelReorderableItem(item: block,
                                         isEnabled: editing,
                                         order: blockOrderBinding,
                                         dragging: $draggingBlock) {
                        HStack(alignment: .top, spacing: 8) {
                            if editing {
                                PanelDragHandle()
                            }
                            blockContent(block, editing: editing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .panelCard()
        }
        .onReceive(monitor.$snapshot) { _ in
            // The breakdown forks `ps` (and walks IORegistry for GPU), so refresh it
            // at most every ~4 s while expanded instead of on every ~2 s snapshot.
            guard expanded != nil, Date().timeIntervalSince(lastBreakdownRefresh) > 4 else { return }
            refreshBreakdown()
        }
        .onDisappear {
            expanded = nil
            breakdownRows = []
            breakdownIsLoading = false
        }
    }

    private var menuBarMetricModeControl: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(l10n.s.monitorSeparateMenuBarMetrics, isOn: $separateMenuBarMetrics)
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5, weight: .medium))
            Text(l10n.s.monitorSeparateMenuBarMetricsCaption)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hasMenuBarMetric: Bool {
        menuBarCPU ||
        menuBarGPU ||
        menuBarMemory ||
        menuBarCPUTemperature ||
        menuBarGPUTemperature ||
        menuBarBatteryTemperature ||
        menuBarNetwork ||
        menuBarBattery ||
        menuBarBatteryTime ||
        menuBarPeripheralBattery ||
        menuBarPower
    }

    /// Card subsections, in order, filtered by the per-item toggles (and whether a
    /// battery exists). Drives divider interleaving so only rendered blocks get one.
    private enum Block: String, PanelOrderItem { case temps, usage, memory, disk, network, sensors, alerts, uptime }

    // Hub availability per metric family: an unavailable metric leaves the
    // card entirely, including the edit-mode hidden rows.
    private var cpuAvailable: Bool { AppFeature.monitorCPU.isAvailable }
    private var gpuAvailable: Bool { AppFeature.monitorGPU.isAvailable }
    private var memoryAvailable: Bool { AppFeature.monitorMemory.isAvailable }
    private var powerAvailable: Bool { AppFeature.monitorPower.isAvailable }
    private var diskAvailable: Bool { AppFeature.monitorDisk.isAvailable }
    private var networkAvailable: Bool { AppFeature.monitorNetwork.isAvailable }

    private var usageVisible: Bool {
        (sysCPU && cpuAvailable) || (sysGPU && gpuAvailable)
            || (sysBattery && powerAvailable && monitor.snapshot.power?.chargePercent != nil)
    }

    private var visibleBlocks: [Block] {
        orderedBlocks.filter { isBlockAvailable($0) && isVisible($0) }
    }

    private func blocks(editing: Bool) -> [Block] {
        editing ? orderedBlocks.filter(isBlockAvailable) : visibleBlocks
    }

    private func isBlockAvailable(_ block: Block) -> Bool {
        switch block {
        case .temps, .sensors, .usage: return cpuAvailable || gpuAvailable || powerAvailable
        case .memory: return memoryAvailable
        case .disk: return diskAvailable
        case .network: return networkAvailable
        case .alerts, .uptime: return true
        }
    }

    private var orderedBlocks: [Block] {
        _ = systemOrderRaw
        // Alert rules are configured in Settings. Keeping them out of the panel
        // avoids presenting the same controls twice.
        return PanelLayout.itemOrder(Block.self, key: DefaultsKey.panelSystemOrder).filter { $0 != .alerts }
    }

    private var blockOrderBinding: Binding<[Block]> {
        Binding {
            orderedBlocks
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.panelSystemOrder)
        }
    }

    private func isVisible(_ block: Block) -> Bool {
        switch block {
        case .temps: return sysTemps
        case .sensors: return sysSensors
        case .usage: return usageVisible
        case .memory: return sysMemory
        case .disk: return sysDisk
        case .network: return sysNetwork
        case .alerts: return sysAlerts
        case .uptime: return sysUptime
        }
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelSystemOrder)
        systemOrderRaw = ""
        sysTemps = true
        sysSensors = true
        sensorsExpanded = true
        sysCPU = true
        sysGPU = true
        sysBattery = true
        sysMemory = true
        sysDisk = true
        sysNetwork = true
        sysAlerts = true
        sysUptime = true
    }

    @ViewBuilder
    private func blockContent(_ block: Block, editing: Bool) -> some View {
        switch block {
        case .temps: temperatureGrid(editing: editing)
        case .sensors: sensorsRows(editing: editing)
        case .usage: usageRows(editing: editing)
        case .memory: memoryRows(editing: editing)
        case .disk: diskRows(editing: editing)
        case .network: networkRows(editing: editing)
        case .alerts: alertRows(editing: editing)
        case .uptime: uptimeRow(editing: editing)
        }
    }

    // MARK: Per-app breakdown

    private func toggleBreakdown(_ kind: BreakdownKind) {
        if expanded == kind {
            expanded = nil
            breakdownRows = []
            breakdownIsLoading = false
        } else {
            expanded = kind
            breakdownRows = ProcessUsageService.shared.cachedTop(kind, limit: breakdownLimit) ?? []
            refreshBreakdown()
        }
    }

    private func refreshBreakdown() {
        guard let kind = expanded else { return }
        lastBreakdownRefresh = Date()
        breakdownIsLoading = breakdownRows.isEmpty
        DispatchQueue.global(qos: .utility).async {
            let rows = ProcessUsageService.shared.top(kind, limit: breakdownLimit)
            DispatchQueue.main.async {
                guard expanded == kind else { return }
                breakdownIsLoading = false
                if !rows.isEmpty || breakdownRows.isEmpty {
                    breakdownRows = rows
                }
            }
        }
    }

    @ViewBuilder
    private func breakdownList(for kind: BreakdownKind) -> some View {
        if expanded == kind {
            VStack(alignment: .leading, spacing: 4) {
                if breakdownRows.isEmpty {
                    Text(breakdownIsLoading ? l10n.s.breakdownMeasuring : emptyBreakdownText(for: kind))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 38)
                } else {
                    ForEach(breakdownRows) { row in
                        ProcessUsageRow(row: row,
                                        value: breakdownValue(row, for: kind),
                                        iconSize: 14,
                                        leadingPadding: 38)
                    }
                }
            }
        }
    }

    private func emptyBreakdownText(for kind: BreakdownKind) -> String {
        kind == .energy ? l10n.s.energyAppsIdle : l10n.s.breakdownMeasuring
    }

    private func breakdownValue(_ row: ProcessUsage, for kind: BreakdownKind) -> String {
        kind == .memory ? formatMemory(UInt64(row.value)) : String(format: "%.1f%%", row.value)
    }

    // MARK: Gauges (CPU / GPU temperature + Fans)

    @ViewBuilder
    private func temperatureGrid(editing: Bool) -> some View {
        if !sysTemps {
            PanelHiddenItemRow(title: l10n.s.temperatures,
                               systemImage: "thermometer.medium",
                               isVisible: $sysTemps)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if editing {
                    HStack(spacing: 6) {
                        subsectionLabel(l10n.s.temperatures)
                        Spacer(minLength: 0)
                        PanelInlineHideButton(isVisible: $sysTemps)
                    }
                }
                HStack(spacing: 8) {
                    if cpuAvailable {
                        ringGauge(label: l10n.s.cpuLabel,
                                  text: gaugeTemp(monitor.snapshot.cpuTemperature),
                                  fraction: (monitor.snapshot.cpuTemperature ?? 0) / 110,
                                  color: gaugeColor(monitor.snapshot.cpuTemperature),
                                  subtitle: ghzText(monitor.snapshot.frequencies?.pCoreGHz
                                                    ?? monitor.snapshot.frequencies?.eCoreGHz),
                                  onTap: editing ? nil : { toggleBreakdown(.cpu) })
                    }
                    if gpuAvailable {
                        ringGauge(label: l10n.s.gpuLabel,
                                  text: gaugeTemp(monitor.snapshot.gpuTemperature),
                                  fraction: (monitor.snapshot.gpuTemperature ?? 0) / 110,
                                  color: gaugeColor(monitor.snapshot.gpuTemperature),
                                  subtitle: ghzText(monitor.snapshot.frequencies?.gpuGHz),
                                  onTap: editing ? nil : { toggleBreakdown(.gpu) })
                    }
                    if let fans = fanSummary {
                        ringGauge(label: FeatureStrings.sensors(l10n.language).fans,
                                  text: "\(Int((fans * 100).rounded()))%",
                                  fraction: fans,
                                  color: PanelMetricColor.cyan(for: colorScheme))
                    } else if powerAvailable {
                        ringGauge(label: l10n.s.batteryLabel,
                                  text: gaugeTemp(monitor.snapshot.batteryTemperature),
                                  fraction: (monitor.snapshot.batteryTemperature ?? 0) / 110,
                                  color: gaugeColor(monitor.snapshot.batteryTemperature))
                    }
                }
                // Hovering the temperature wheels fluidly reveals the sensor list.
                .onHover { setSensorHover($0) }
                metricExpansion(.cpu)
                metricExpansion(.gpu)
            }
        }
    }

    /// Average fan speed as a fraction of max; nil when the Mac has no fans.
    private var fanSummary: Double? {
        let fans = monitor.snapshot.fans
        guard !fans.isEmpty else { return nil }
        return fans.map(\.fraction).reduce(0, +) / Double(fans.count)
    }

    private func gaugeTemp(_ value: Double?) -> String {
        value.map { MetricFormat.temperatureCompact($0, unit: displayTemperatureUnit) } ?? "–"
    }

    private func gaugeColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        return Self.ringColor(value, scheme: colorScheme)
    }

    /// A big donut ring with a value centred and a caption beneath it. When
    /// `onTap` is set the whole gauge is tappable (drill-down).
    private func ringGauge(label: String, text: String, fraction: Double, color: Color,
                           subtitle: String? = nil, onTap: (() -> Void)? = nil) -> some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // iStats stacks the caption INSIDE the ring, above the value.
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 8.5, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.4)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 7.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .frame(width: 62, height: 62)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private func ghzText(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        return String(format: "%.2fGHz", value)
    }

    /// Inline drill-down shown under a tapped metric: its 1-hour history graph
    /// plus the top processes for that resource.
    @ViewBuilder
    private func metricExpansion(_ kind: BreakdownKind) -> some View {
        if expanded == kind {
            VStack(alignment: .leading, spacing: 6) {
                if let history = history(for: kind), history.count >= 2 {
                    Sparkline(values: history, color: sparklineColor(kind),
                              maxValue: 1, showsZeroBaseline: true)
                        .frame(height: 26)
                }
                if kind == .energy { batteryDetail }
                breakdownList(for: kind)
            }
        }
    }

    @ViewBuilder
    private var batteryDetail: some View {
        if let p = monitor.snapshot.power {
            let s = FeatureStrings.sensors(l10n.language)
            VStack(alignment: .leading, spacing: 3) {
                if let w = p.batteryWatts { sensorRow(label: s.power, value: MetricFormat.watts(abs(w))) }
                if let a = p.amperage { sensorRow(label: s.amperage, value: String(format: "%.0f mA", a)) }
                if let v = p.voltage { sensorRow(label: s.voltage, value: String(format: "%.2f V", v)) }
                if let t = monitor.snapshot.batteryTemperature {
                    sensorRow(label: s.temperature,
                              value: MetricFormat.temperature(t, unit: displayTemperatureUnit))
                }
                if let c = p.cycleCount { sensorRow(label: s.cycles, value: "\(c)") }
                sensorRow(label: s.condition, value: s.conditionNormal)
                if let full = p.fullChargeCapacity, let design = p.designCapacity {
                    sensorRow(label: s.capacity, value: "\(full) / \(design) mAh")
                }
            }
        }
    }

    private func history(for kind: BreakdownKind) -> [Double]? {
        switch kind {
        case .cpu: return monitor.snapshot.cpuHistory
        case .gpu: return monitor.snapshot.gpuHistory
        case .memory: return monitor.snapshot.memoryHistory
        case .energy: return monitor.snapshot.batteryHistory
        case .network: return nil
        }
    }

    private func sparklineColor(_ kind: BreakdownKind) -> Color {
        switch kind {
        case .cpu: return .accentColor
        case .gpu: return PanelMetricColor.cyan(for: colorScheme)
        case .memory: return PanelMetricColor.mint(for: colorScheme)
        case .energy: return PanelMetricColor.green(for: colorScheme)
        case .network: return .accentColor
        }
    }

    /// Shared temperature → ring-colour ramp (cyan → yellow → red).
    static func ringColor(_ celsius: Double, scheme: ColorScheme) -> Color {
        switch celsius {
        case ..<55: return PanelMetricColor.cyan(for: scheme)
        case ..<75: return PanelMetricColor.yellow(for: scheme)
        default: return PanelMetricColor.red(for: scheme)
        }
    }

    private var displayTemperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }

    // MARK: Sensors (temperatures, power, fans)

    /// The sensor list is showing if the user pinned it open OR is hovering the
    /// temperature wheels / the list itself.
    private var sensorsVisible: Bool { sensorsExpanded || hoverSensors }

    /// Debounced hover so the reveal survives the small gap between the wheels
    /// and the list. A newer event (in or out) cancels a pending collapse.
    private func setSensorHover(_ hovering: Bool) {
        hoverSensorsToken += 1
        if hovering {
            withAnimation(.easeInOut(duration: 0.15)) { hoverSensors = true }
        } else {
            let token = hoverSensorsToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                guard token == hoverSensorsToken else { return }
                withAnimation(.easeInOut(duration: 0.15)) { hoverSensors = false }
            }
        }
    }

    @ViewBuilder
    private func sensorsRows(editing: Bool) -> some View {
        let strings = FeatureStrings.sensors(l10n.language)
        if !sysSensors {
            PanelHiddenItemRow(title: strings.section,
                               systemImage: "gauge.with.dots.needle.bottom.50percent",
                               isVisible: $sysSensors)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { sensorsExpanded.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(sensorsVisible ? 90 : 0))
                            subsectionLabel(strings.section)
                            Spacer(minLength: 0)
                            if !sensorsVisible { sensorsSummary }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if editing {
                        PanelInlineHideButton(isVisible: $sysSensors)
                    }
                }
                if sensorsVisible {
                    sensorsBody(strings)
                }
            }
            .onHover { setSensorHover($0) }
        }
    }

    /// Collapsed-state glance: the hottest sensor reading.
    @ViewBuilder
    private var sensorsSummary: some View {
        if let hottest = monitor.snapshot.temperatureSensors.map(\.celsius).max() {
            HStack(spacing: 5) {
                SensorRing(celsius: hottest)
                Text(MetricFormat.temperature(hottest, unit: displayTemperatureUnit))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func sensorsBody(_ strings: SensorsFeatureStrings) -> some View {
        let temps = monitor.snapshot.temperatureSensors
        let fans = monitor.snapshot.fans
        let watts = powerAvailable ? monitor.snapshot.power?.systemWatts : nil
        if !temps.isEmpty {
            sensorSubsection(strings.temperature) {
                ForEach(temps) { sensor in
                    HStack(spacing: 8) {
                        Text(temperatureLabel(sensor.id, strings))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        Text(MetricFormat.temperature(sensor.celsius, unit: displayTemperatureUnit))
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                        SensorRing(celsius: sensor.celsius)
                    }
                }
            }
        }
        if let watts {
            sensorSubsection(strings.power) {
                sensorRow(label: strings.totalPower, value: MetricFormat.watts(watts))
            }
        }
        if !fans.isEmpty {
            sensorSubsection(strings.fans) {
                ForEach(fans) { fan in
                    sensorRow(label: fanLabel(fan.index, count: fans.count, strings: strings),
                              value: fan.rpm == 0 ? strings.fanOff : "\(fan.rpm) RPM")
                }
            }
        }
        if let freq = monitor.snapshot.frequencies, !freq.isEmpty {
            sensorSubsection(strings.frequency) {
                if let e = freq.eCoreGHz { sensorRow(label: strings.cpuEfficiency, value: String(format: "%.2f GHz", e)) }
                if let p = freq.pCoreGHz { sensorRow(label: strings.cpuPerformance, value: String(format: "%.2f GHz", p)) }
                if let g = freq.gpuGHz { sensorRow(label: strings.graphics, value: String(format: "%.2f GHz", g)) }
            }
        }
        if temps.isEmpty, fans.isEmpty, watts == nil {
            Text(l10n.s.monitorUnavailable)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func sensorSubsection<Content: View>(_ title: String,
                                                 @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionTitle(title)
            content()
        }
    }

    private func sensorRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
    }

    private func temperatureLabel(_ id: SensorGroupID, _ s: SensorsFeatureStrings) -> String {
        switch id {
        case .cpuPerformance: return s.cpuPerformance
        case .cpuEfficiency: return s.cpuEfficiency
        case .graphics: return s.graphics
        case .battery: return s.battery
        case .ssd: return s.ssd
        case .wifi: return s.wifi
        case .airflow: return s.airflow
        }
    }

    private func fanLabel(_ index: Int, count: Int, strings s: SensorsFeatureStrings) -> String {
        if count == 2 {
            return index == 0 ? s.leftFan : s.rightFan
        }
        return "\(s.fan) \(index + 1)"
    }

    // MARK: Cores (per-core activity)

    @ViewBuilder
    private func usageRows(editing: Bool) -> some View {
        if !sysCPU {
            if editing {
                PanelHiddenItemRow(title: l10n.s.usageSection, systemImage: "cpu", isVisible: $sysCPU)
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                if editing {
                    HStack(spacing: 6) {
                        subsectionLabel(l10n.s.usageSection)
                        Spacer(minLength: 0)
                        PanelInlineHideButton(isVisible: $sysCPU)
                    }
                }
                if cpuAvailable { coreDotsView }
            }
        }
    }

    /// iStats-style per-core activity dots with an efficiency/performance legend.
    @ViewBuilder
    private var coreDotsView: some View {
        let cores = monitor.snapshot.coreUsages
        if cores.isEmpty {
            usageRow(label: l10n.s.cpuLabel, fraction: monitor.snapshot.cpuUsage,
                     kind: .cpu, editing: false, visible: $sysCPU)
        } else {
            let eCount = min(max(0, monitor.snapshot.efficiencyCoreCount), cores.count)
            let ePink = PanelMetricColor.pink(for: colorScheme)
            let pCyan = PanelMetricColor.blue(for: colorScheme)
            let s = FeatureStrings.sensors(l10n.language)
            // Efficiency cores are the trailing cores (perflevel1); performance
            // cores lead (perflevel0). iStats groups efficiency first, so mirror
            // that: pink cluster, a small gap, then the cyan cluster.
            let eCores = Array(cores.suffix(eCount))
            let pCores = Array(cores.prefix(max(0, cores.count - eCount)))
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 4) {
                    ForEach(Array(eCores.enumerated()), id: \.offset) { _, usage in
                        CoreGauge(fraction: usage, color: ePink)
                    }
                    if !eCores.isEmpty && !pCores.isEmpty {
                        Spacer().frame(width: 5)
                    }
                    ForEach(Array(pCores.enumerated()), id: \.offset) { _, usage in
                        CoreGauge(fraction: usage, color: pCyan)
                    }
                    Spacer(minLength: 0)
                }
                coreLegend(color: ePink, name: s.cpuEfficiency,
                           fraction: clusterAverage(cores, efficiencyCount: eCount, efficiency: true))
                coreLegend(color: pCyan, name: s.cpuPerformance,
                           fraction: clusterAverage(cores, efficiencyCount: eCount, efficiency: false))
            }
        }
    }

    private func coreLegend(color: Color, name: String, fraction: Double) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
    }

    private func clusterAverage(_ cores: [Double], efficiencyCount: Int, efficiency: Bool) -> Double {
        // Efficiency cores are the trailing `efficiencyCount`; performance lead.
        let slice = efficiency ? Array(cores.suffix(efficiencyCount))
                               : Array(cores.prefix(max(0, cores.count - efficiencyCount)))
        guard !slice.isEmpty else { return 0 }
        return slice.reduce(0, +) / Double(slice.count)
    }

    // MARK: Battery (charge level, next to CPU/GPU) and uptime

    @ViewBuilder
    private func batteryUsageRow(editing: Bool) -> some View {
        if let charge = monitor.snapshot.power?.chargePercent {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: (monitor.snapshot.power?.isCharging ?? false) ? "bolt.fill" : "battery.100")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(l10n.s.batteryLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 52, alignment: .leading)
                    UsageBar(fraction: Double(charge) / 100, tint: chargeTint(charge))
                    Text("\(charge)%")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                    if editing {
                        PanelInlineHideButton(isVisible: $sysBattery)
                    }
                }
                if graphBattery, monitor.snapshot.batteryHistory.count >= 2 {
                    Sparkline(values: monitor.snapshot.batteryHistory,
                              color: PanelMetricColor.green(for: colorScheme),
                              maxValue: 1,
                              showsZeroBaseline: true)
                        .frame(height: 22)
                }
                energyAppsHeader
                breakdownList(for: .energy)
            }
        }
    }

    private var peripheralBatteryRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            subsectionLabel(l10n.s.monitorShowPeripheralBattery)
            ForEach(PeripheralBatterySupport.sorted(monitor.snapshot.peripheralBatteries).prefix(5)) { device in
                HStack(spacing: 8) {
                    Image(systemName: peripheralIcon(for: device.kind))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(device.name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("\(device.percent)%")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                }
            }
            let extra = max(0, monitor.snapshot.peripheralBatteries.count - 5)
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func peripheralIcon(for kind: PeripheralBatteryKind) -> String {
        switch kind {
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .audio: return "headphones"
        case .device: return "battery.100"
        }
    }

    private var energyAppsHeader: some View {
        Button {
            toggleBreakdown(.energy)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded == .energy ? 90 : 0))
                Text(l10n.s.energyAppsTitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chargeTint(_ charge: Int) -> Color {
        if charge < 20 { return PanelMetricColor.red(for: colorScheme) }
        if charge < 40 { return PanelMetricColor.yellow(for: colorScheme) }
        return PanelMetricColor.green(for: colorScheme)
    }

    @ViewBuilder
    private func uptimeRow(editing: Bool) -> some View {
        if !sysUptime {
            PanelHiddenItemRow(title: l10n.s.monitorItemUptime, systemImage: "clock", isVisible: $sysUptime)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if editing {
                        Image(systemName: "clock").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text("\(l10n.s.systemUptime) \(Self.uptimeString())")
                            .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        PanelInlineHideButton(isVisible: $sysUptime)
                    } else {
                        Button {
                            uptimeExpanded.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock").font(.system(size: 9)).foregroundStyle(.secondary)
                                Text("\(l10n.s.systemUptime) \(Self.uptimeString())")
                                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if uptimeExpanded, !editing, let detail = Self.uptimeDetail() {
                    let s = FeatureStrings.sensors(l10n.language)
                    VStack(alignment: .leading, spacing: 3) {
                        sensorRow(label: s.poweredOn, value: detail.poweredOn)
                        sensorRow(label: s.awake, value: MetricFormat.uptime(detail.awake))
                        sensorRow(label: s.sleeping, value: MetricFormat.uptime(detail.sleeping))
                    }
                }
            }
        }
    }

    static func uptimeString() -> String {
        let total = SystemInfo.wallClockUptimeSeconds() ?? Int(ProcessInfo.processInfo.systemUptime)
        return MetricFormat.uptime(total)
    }

    /// Boot date, awake time and (derived) sleeping time. `systemUptime` excludes
    /// sleep; wall-clock uptime includes it, so sleeping = wall − awake.
    static func uptimeDetail() -> (poweredOn: String, awake: Int, sleeping: Int)? {
        guard let wall = SystemInfo.wallClockUptimeSeconds() else { return nil }
        let awake = Int(ProcessInfo.processInfo.systemUptime)
        let sleeping = max(0, wall - awake)
        let bootDate = Date(timeIntervalSinceNow: -Double(wall))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return (formatter.string(from: bootDate), awake, sleeping)
    }

    private static let memoryFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter
    }()

    private func usageRow(label: String, fraction: Double?, kind: BreakdownKind,
                          editing: Bool, visible: Binding<Bool>) -> some View {
        Group {
            if editing {
                usageRowContent(label: label, fraction: fraction, kind: kind, isInteractive: false) {
                    PanelInlineHideButton(isVisible: visible)
                }
            } else {
                Button {
                    toggleBreakdown(kind)
                } label: {
                    usageRowContent(label: label, fraction: fraction, kind: kind, isInteractive: true) {
                        EmptyView()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func usageRowContent<Trailing: View>(label: String, fraction: Double?,
                                                 kind: BreakdownKind, isInteractive: Bool,
                                                 @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded == kind ? 90 : 0))
                .opacity(isInteractive ? 1 : 0.35)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 52, alignment: .leading)
            UsageBar(fraction: fraction ?? 0)
            Text(fraction.map { String(format: "%.0f%%", $0 * 100) } ?? "-")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
            trailing()
        }
    }

    // MARK: Disk

    private var primaryDisk: DiskDeviceReading? {
        let devices = monitor.snapshot.disk?.uniqueIODevices ?? []
        return devices.first { $0.isInternal } ?? devices.first
    }

    @ViewBuilder
    private func diskRows(editing: Bool) -> some View {
        if !sysDisk {
            if editing {
                PanelHiddenItemRow(title: l10n.s.diskSection, systemImage: "internaldrive", isVisible: $sysDisk)
            }
        } else if let device = primaryDisk {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if let temp = device.smart?.temperatureCelsius {
                        Text("\(Int(temp.rounded()))")
                            .font(.system(size: 9, weight: .bold)).monospacedDigit()
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Self.ringColor(temp, scheme: colorScheme), lineWidth: 1.5))
                    } else {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 22)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(device.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text("\(MetricFormat.diskBytes(device.freeBytes)) \(l10n.s.diskFree)")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if editing { PanelInlineHideButton(isVisible: $sysDisk) }
                }
                .contentShape(Rectangle())
                .onTapGesture { if !editing { diskExpanded.toggle() } }
                if diskExpanded, !editing {
                    VStack(alignment: .leading, spacing: 3) {
                        sensorRow(label: l10n.s.diskRead,
                                  value: MetricFormat.bytesPerSec(device.readBytesPerSec ?? 0))
                        sensorRow(label: l10n.s.diskWrite,
                                  value: MetricFormat.bytesPerSec(device.writeBytesPerSec ?? 0))
                        if let temp = device.smart?.temperatureCelsius {
                            sensorRow(label: l10n.s.diskTemperature,
                                      value: MetricFormat.temperature(temp, unit: displayTemperatureUnit))
                        }
                        if let health = device.smart?.healthPercent {
                            sensorRow(label: l10n.s.diskHealth, value: "\(health)%")
                        }
                    }
                }
            }
        }
    }

    // MARK: Network

    @ViewBuilder
    private func networkRows(editing: Bool) -> some View {
        if !sysNetwork {
            if editing {
                PanelHiddenItemRow(title: l10n.s.networkSection, systemImage: "network", isVisible: $sysNetwork)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Image(systemName: "network")
                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 22)
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(PanelMetricColor.cyan(for: colorScheme))
                        Text(MetricFormat.bytesPerSec(monitor.snapshot.netDownBytesPerSec ?? 0))
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(PanelMetricColor.pink(for: colorScheme))
                        Text(MetricFormat.bytesPerSec(monitor.snapshot.netUpBytesPerSec ?? 0))
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    if editing { PanelInlineHideButton(isVisible: $sysNetwork) }
                }
                .contentShape(Rectangle())
                .onTapGesture { if !editing { toggleBreakdown(.network) } }
                metricExpansion(.network)
            }
        }
    }

    // MARK: Memory + power donuts

    @ViewBuilder
    private func memoryRows(editing: Bool) -> some View {
        if !sysMemory {
            PanelHiddenItemRow(title: l10n.s.memorySection,
                               systemImage: "memorychip.fill",
                               isVisible: $sysMemory)
        } else {
            VStack(alignment: .leading, spacing: 11) {
                if editing {
                    HStack(spacing: 6) {
                        subsectionLabel(l10n.s.memorySection)
                        Spacer(minLength: 0)
                        PanelInlineHideButton(isVisible: $sysMemory)
                    }
                }
                if memoryAvailable {
                    let tapMemory: (() -> Void)? = editing ? nil : { toggleBreakdown(.memory) }
                    HStack(spacing: 10) {
                        Donut(caption: l10n.s.memoryPressure, percent: pressurePercent,
                              color: pressureColor, onTap: tapMemory)
                        SegmentedDonut(caption: l10n.s.memorySection, percent: memoryPercent,
                                       segments: memorySegments, onTap: tapMemory)
                    }
                    memoryBreakdown
                    metricExpansion(.memory)
                }
                if powerAvailable, let charge = monitor.snapshot.power?.chargePercent {
                    let tapEnergy: (() -> Void)? = editing ? nil : { toggleBreakdown(.energy) }
                    HStack(spacing: 10) {
                        Donut(caption: l10n.s.batteryLabel, percent: charge,
                              color: batteryDonutColor(charge), onTap: tapEnergy)
                        if let health = monitor.snapshot.power?.healthPercent {
                            // Short "Health" caption — "Battery health" clips inside the donut.
                            Donut(caption: l10n.s.diskHealth, percent: Int(health.rounded()),
                                  color: PanelMetricColor.pink(for: colorScheme), onTap: tapEnergy)
                        }
                    }
                    metricExpansion(.energy)
                }
            }
        }
    }

    private var memoryPercent: Int {
        guard let used = monitor.snapshot.memoryUsed, let total = monitor.snapshot.memoryTotal, total > 0
        else { return 0 }
        return Int((Double(used) / Double(total) * 100).rounded())
    }

    private var pressurePercent: Int {
        guard let wired = monitor.snapshot.memoryWired, let comp = monitor.snapshot.memoryCompressed,
              let total = monitor.snapshot.memoryTotal, total > 0 else { return 0 }
        return Int((Double(wired + comp) / Double(total) * 100).rounded())
    }

    private var pressureColor: Color {
        switch monitor.snapshot.memoryPressure {
        case .warning: return PanelMetricColor.yellow(for: colorScheme)
        case .critical: return PanelMetricColor.red(for: colorScheme)
        default: return PanelMetricColor.blue(for: colorScheme)
        }
    }

    /// Memory ring segments (app / wired / compressed as fractions of total),
    /// so the wheel is stacked and multi-colour like iStats instead of one arc.
    /// Free is left as the faint track.
    private var memorySegments: [DonutSegment] {
        guard let app = monitor.snapshot.memoryApp, let wired = monitor.snapshot.memoryWired,
              let comp = monitor.snapshot.memoryCompressed, let total = monitor.snapshot.memoryTotal,
              total > 0 else { return [] }
        let t = Double(total)
        return [
            DonutSegment(fraction: Double(app) / t, color: PanelMetricColor.blue(for: colorScheme)),
            DonutSegment(fraction: Double(wired) / t, color: PanelMetricColor.pink(for: colorScheme)),
            DonutSegment(fraction: Double(comp) / t, color: PanelMetricColor.yellow(for: colorScheme)),
        ]
    }

    private func batteryDonutColor(_ charge: Int) -> Color {
        if charge < 20 { return PanelMetricColor.red(for: colorScheme) }
        if charge < 40 { return PanelMetricColor.yellow(for: colorScheme) }
        return PanelMetricColor.green(for: colorScheme)
    }

    @ViewBuilder
    private var memoryBreakdown: some View {
        if let app = monitor.snapshot.memoryApp, let wired = monitor.snapshot.memoryWired,
           let comp = monitor.snapshot.memoryCompressed, let free = monitor.snapshot.memoryFree {
            let s = FeatureStrings.sensors(l10n.language)
            VStack(alignment: .leading, spacing: 5) {
                memoryLegend(PanelMetricColor.blue(for: colorScheme), s.memApp, app)
                memoryLegend(PanelMetricColor.pink(for: colorScheme), s.memWired, wired)
                memoryLegend(PanelMetricColor.yellow(for: colorScheme), s.memCompressed, comp)
                memoryLegend(.secondary, s.memFree, free)
            }
        }
    }

    private func memoryLegend(_ dot: Color, _ name: String, _ bytes: UInt64) -> some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(name).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(formatMemory(bytes)).font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
    }

    private func memoryRowContent(isInteractive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded == .memory ? 90 : 0))
                .opacity(isInteractive ? 1 : 0.35)
            Text(l10n.s.memoryPressure)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            PressureIndicator(pressure: monitor.snapshot.memoryPressure)
            Spacer()
            if let used = monitor.snapshot.memoryUsed, let total = monitor.snapshot.memoryTotal {
                Text("\(formatMemory(used)) / \(formatMemory(total))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subsectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func alertRows(editing: Bool) -> some View {
        let text = FeatureStrings.monitorAlerts(l10n.language)
        if !sysAlerts {
            PanelHiddenItemRow(title: text.section,
                               systemImage: "bell.badge",
                               isVisible: $sysAlerts)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Button {
                        alertsExpanded.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(alertsExpanded ? 90 : 0))
                            subsectionLabel(text.section)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if editing {
                        PanelInlineHideButton(isVisible: $sysAlerts)
                    }
                }
                if alertsExpanded {
                    MonitorAlertsControls(compact: true)
                }
            }
        }
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        Self.memoryFormatter.string(fromByteCount: Int64(bytes))
    }
}

/// Thin capacity bar for CPU/GPU usage.
private struct UsageBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let fraction: Double
    var tint: Color? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint ?? barColor)
                    .frame(width: max(3, proxy.size.width * min(1, fraction)))
            }
        }
        .frame(height: 5)
    }

    private var barColor: Color {
        switch fraction {
        case ..<0.6: return .accentColor
        case ..<0.85: return PanelMetricColor.yellow(for: colorScheme)
        default: return PanelMetricColor.red(for: colorScheme)
        }
    }
}

/// Small iStat-style ring gauge: a track circle with a colored arc filled in
/// proportion to the temperature, warming from cyan through yellow to red.
/// A single CPU core rendered as a tiny speedometer: a faint background ring
/// with a coloured arc trimmed to that core's live usage (0–100%). Replaces the
/// old on/off "activity light" so partial load reads as a partial fill.
private struct CoreGauge: View {
    let fraction: Double
    let color: Color

    var body: some View {
        let f = min(1, max(0, fraction))
        ZStack {
            Circle().stroke(Color.primary.opacity(0.16), lineWidth: 2)
            Circle()
                .trim(from: 0, to: f)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
    }
}

private struct SensorRing: View {
    @Environment(\.colorScheme) private var colorScheme
    let celsius: Double

    var body: some View {
        let fraction = min(1, max(0.02, celsius / 110))
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
    }

    private var color: Color { SystemSection.ringColor(celsius, scheme: colorScheme) }
}

/// Big iStat-style donut: a percentage centred with a caption beneath it.
private struct Donut: View {
    let caption: String
    let percent: Int
    let color: Color
    var onTap: (() -> Void)? = nil

    var body: some View {
        content
            .frame(width: 92, height: 92)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
    }

    private var content: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.09), lineWidth: 7)
            Circle()
                .trim(from: 0, to: min(1, max(0, Double(percent) / 100)))
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                percentText(percent)
                Text(caption.uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// The centred donut value: a big number with a smaller, raised "%" superscript
/// — the way iStats renders it, rather than a baseline-aligned percent sign.
@ViewBuilder
func percentText(_ percent: Int) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 1) {
        Text("\(percent)")
            .font(.system(size: 24, weight: .semibold))
            .monospacedDigit()
        Text("%")
            .font(.system(size: 11, weight: .semibold))
            .baselineOffset(7)
            .foregroundStyle(.secondary)
    }
}

/// One arc of a `SegmentedDonut`.
struct DonutSegment: Identifiable {
    let id = UUID()
    let fraction: Double
    let color: Color
}

/// Like `Donut`, but the ring is split into stacked coloured arcs (memory:
/// app / wired / compressed) over a faint free track, matching iStats' multi-
/// colour memory wheel. The centre shows the combined used percentage.
private struct SegmentedDonut: View {
    let caption: String
    let percent: Int
    let segments: [DonutSegment]
    var onTap: (() -> Void)? = nil

    var body: some View {
        content
            .frame(width: 92, height: 92)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
    }

    private var content: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.09), lineWidth: 7)
            // Stack the arcs end-to-end starting at 12 o'clock. A tiny gap
            // between segments keeps the colour boundaries legible.
            ForEach(Array(runningSegments.enumerated()), id: \.offset) { _, run in
                Circle()
                    .trim(from: run.start, to: run.end)
                    .stroke(run.color, style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                percentText(percent)
                Text(caption.uppercased()).font(.system(size: 8.5, weight: .semibold))
                    .kerning(0.4).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private struct Run: Identifiable { let id: UUID; let start: Double; let end: Double; let color: Color }

    private var runningSegments: [Run] {
        var cursor = 0.0
        let gap = 0.006
        return segments.compactMap { seg in
            let f = min(1, max(0, seg.fraction))
            guard f > 0.001 else { return nil }
            let start = min(1, cursor)
            let end = min(1, cursor + f)
            cursor = end
            return Run(id: seg.id, start: min(start + gap, end), end: end, color: seg.color)
        }
    }
}

/// Traffic-light pill for memory pressure: green = normal, yellow = caution,
/// red = critical.
struct PressureIndicator: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    let pressure: MemoryPressure

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.6), radius: 2)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.13)))
    }

    private var color: Color {
        switch pressure {
        case .normal: return PanelMetricColor.green(for: colorScheme)
        case .warning: return PanelMetricColor.yellow(for: colorScheme)
        case .critical: return PanelMetricColor.red(for: colorScheme)
        case .unknown: return .secondary
        }
    }

    private var label: String {
        switch pressure {
        case .normal: return l10n.s.pressureNormal
        case .warning: return l10n.s.pressureWarning
        case .critical: return l10n.s.pressureCritical
        case .unknown: return "-"
        }
    }
}
