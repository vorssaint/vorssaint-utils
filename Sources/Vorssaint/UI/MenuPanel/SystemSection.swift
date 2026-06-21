// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Which per-app breakdown is expanded in the System section.
enum BreakdownKind {
    case cpu, gpu, memory, energy
}

/// The "System" section of the panel: component temperatures, hardware usage
/// and memory pressure — only the readings that matter, presented cleanly.
/// Tapping CPU, GPU, Battery or Memory expands the top consumers of that resource.
struct SystemSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.colorScheme) private var colorScheme
    var collapsible = true
    @State private var expanded: BreakdownKind?
    @State private var breakdownRows: [ProcessUsage] = []
    @State private var breakdownIsLoading = false
    @State private var lastBreakdownRefresh = Date.distantPast
    @AppStorage(DefaultsKey.monitorGraphCPU) private var graphCPU = true
    @AppStorage(DefaultsKey.monitorGraphGPU) private var graphGPU = true
    @AppStorage(DefaultsKey.monitorGraphMemory) private var graphMemory = true
    @AppStorage(DefaultsKey.monitorGraphBattery) private var graphBattery = true
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.monitorSysTemps) private var sysTemps = true
    @AppStorage(DefaultsKey.monitorSysCPU) private var sysCPU = true
    @AppStorage(DefaultsKey.monitorSysGPU) private var sysGPU = true
    @AppStorage(DefaultsKey.monitorSysBattery) private var sysBattery = true
    @AppStorage(DefaultsKey.monitorSysMemory) private var sysMemory = true
    @AppStorage(DefaultsKey.monitorSysUptime) private var sysUptime = true
    @AppStorage(DefaultsKey.panelSystemOrder) private var systemOrderRaw = ""
    @State private var draggingBlock: Block?

    var body: some View {
        PanelSection(.system, title: l10n.s.systemSection, collapsible: collapsible,
                     supportsEditing: true,
                     resetAction: resetPanelDefaults) { editing in
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks(editing: editing).enumerated()), id: \.element) { index, block in
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

    /// Card subsections, in order, filtered by the per-item toggles (and whether a
    /// battery exists). Drives divider interleaving so only rendered blocks get one.
    private enum Block: String, PanelOrderItem { case temps, usage, memory, uptime }

    private var usageVisible: Bool {
        sysCPU || sysGPU || (sysBattery && monitor.snapshot.power?.chargePercent != nil)
    }

    private var visibleBlocks: [Block] {
        orderedBlocks.filter(isVisible)
    }

    private func blocks(editing: Bool) -> [Block] {
        editing ? orderedBlocks : visibleBlocks
    }

    private var orderedBlocks: [Block] {
        _ = systemOrderRaw
        return PanelLayout.itemOrder(Block.self, key: DefaultsKey.panelSystemOrder)
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
        case .usage: return usageVisible
        case .memory: return sysMemory
        case .uptime: return sysUptime
        }
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelSystemOrder)
        systemOrderRaw = ""
        sysTemps = true
        sysCPU = true
        sysGPU = true
        sysBattery = true
        sysMemory = true
        sysUptime = true
    }

    @ViewBuilder
    private func blockContent(_ block: Block, editing: Bool) -> some View {
        switch block {
        case .temps: temperatureGrid(editing: editing)
        case .usage: usageRows(editing: editing)
        case .memory: memoryRows(editing: editing)
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
            breakdownRows = []
            refreshBreakdown()
        }
    }

    private func refreshBreakdown() {
        guard let kind = expanded else { return }
        lastBreakdownRefresh = Date()
        breakdownIsLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let rows: [ProcessUsage]
            switch kind {
            case .cpu: rows = ProcessUsageService.shared.topCPU()
            case .gpu: rows = ProcessUsageService.shared.topGPU()
            case .memory: rows = ProcessUsageService.shared.topMemory()
            case .energy: rows = ProcessUsageService.shared.topEnergy()
            }
            DispatchQueue.main.async {
                guard expanded == kind else { return }
                breakdownIsLoading = false
                breakdownRows = rows
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
                        HStack(spacing: 6) {
                            Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                                .resizable()
                                .frame(width: 14, height: 14)
                            Text(row.name)
                                .font(.system(size: 10.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(breakdownValue(row, for: kind))
                                .font(.system(size: 10.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 38)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func emptyBreakdownText(for kind: BreakdownKind) -> String {
        kind == .energy ? l10n.s.energyAppsIdle : l10n.s.breakdownMeasuring
    }

    private func breakdownValue(_ row: ProcessUsage, for kind: BreakdownKind) -> String {
        kind == .memory ? formatMemory(UInt64(row.value)) : String(format: "%.1f%%", row.value)
    }

    // MARK: Temperatures

    @ViewBuilder
    private func temperatureGrid(editing: Bool) -> some View {
        if !sysTemps {
            PanelHiddenItemRow(title: l10n.s.temperatures,
                               systemImage: "thermometer.medium",
                               isVisible: $sysTemps)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    subsectionLabel(l10n.s.temperatures)
                    Spacer(minLength: 0)
                    if editing {
                        PanelInlineHideButton(isVisible: $sysTemps)
                    }
                }
                HStack(spacing: 8) {
                    temperatureCell(icon: "cpu", label: l10n.s.cpuLabel,
                                    value: monitor.snapshot.cpuTemperature)
                    temperatureCell(icon: "memorychip", label: l10n.s.gpuLabel,
                                    value: monitor.snapshot.gpuTemperature)
                    temperatureCell(icon: "battery.100", label: l10n.s.batteryLabel,
                                    value: monitor.snapshot.batteryTemperature)
                }
                if monitor.snapshot.cpuTemperature == nil,
                   monitor.snapshot.gpuTemperature == nil,
                   monitor.snapshot.batteryTemperature == nil {
                    Text(l10n.s.monitorUnavailable)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func temperatureCell(icon: String, label: String, value: Double?) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(value.map { MetricFormat.temperature($0, unit: displayTemperatureUnit) } ?? "-")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var displayTemperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }

    // MARK: Hardware usage

    private func usageRows(editing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            subsectionLabel(l10n.s.usageSection)
            if sysCPU {
                usageRow(label: l10n.s.cpuLabel, fraction: monitor.snapshot.cpuUsage,
                         kind: .cpu, editing: editing, visible: $sysCPU)
                if graphCPU, monitor.snapshot.cpuHistory.count >= 2 {
                    Sparkline(values: monitor.snapshot.cpuHistory,
                              color: .accentColor,
                              maxValue: 1,
                              showsZeroBaseline: true)
                        .frame(height: 22)
                }
                breakdownList(for: .cpu)
            } else if editing {
                PanelHiddenItemRow(title: l10n.s.cpuLabel, systemImage: "cpu", isVisible: $sysCPU)
            }
            if sysGPU {
                usageRow(label: l10n.s.gpuLabel, fraction: monitor.snapshot.gpuUsage,
                         kind: .gpu, editing: editing, visible: $sysGPU)
                if graphGPU, monitor.snapshot.gpuHistory.count >= 2 {
                    Sparkline(values: monitor.snapshot.gpuHistory,
                              color: PanelMetricColor.cyan(for: colorScheme),
                              maxValue: 1,
                              showsZeroBaseline: true)
                        .frame(height: 22)
                }
                breakdownList(for: .gpu)
            } else if editing {
                PanelHiddenItemRow(title: l10n.s.gpuLabel, systemImage: "memorychip", isVisible: $sysGPU)
            }
            if sysBattery {
                batteryUsageRow(editing: editing)
            } else if editing {
                PanelHiddenItemRow(title: l10n.s.batteryLabel,
                                   systemImage: "battery.100",
                                   isVisible: $sysBattery)
            }
        }
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

    private var energyAppsHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { toggleBreakdown(.energy) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
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
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("\(l10n.s.systemUptime) \(Self.uptimeString())")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                if editing {
                    PanelInlineHideButton(isVisible: $sysUptime)
                }
            }
        }
    }

    static func uptimeString() -> String {
        let total = SystemInfo.wallClockUptimeSeconds() ?? Int(ProcessInfo.processInfo.systemUptime)
        return MetricFormat.uptime(total)
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
                    withAnimation(.easeInOut(duration: 0.15)) { toggleBreakdown(kind) }
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
                .foregroundStyle(.tertiary)
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

    // MARK: Memory

    @ViewBuilder
    private func memoryRows(editing: Bool) -> some View {
        if !sysMemory {
            PanelHiddenItemRow(title: l10n.s.memorySection,
                               systemImage: "memorychip.fill",
                               isVisible: $sysMemory)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    subsectionLabel(l10n.s.memorySection)
                    Spacer(minLength: 0)
                    if editing {
                        PanelInlineHideButton(isVisible: $sysMemory)
                    }
                }
                if editing {
                    memoryRowContent(isInteractive: false)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { toggleBreakdown(.memory) }
                    } label: {
                        memoryRowContent(isInteractive: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if graphMemory, monitor.snapshot.memoryHistory.count >= 2 {
                    Sparkline(values: monitor.snapshot.memoryHistory,
                              color: PanelMetricColor.mint(for: colorScheme),
                              maxValue: 1,
                              showsZeroBaseline: true)
                        .frame(height: 22)
                }
                breakdownList(for: .memory)
            }
        }
    }

    private func memoryRowContent(isInteractive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
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
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
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
                    .animation(.easeOut(duration: 0.4), value: fraction)
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
