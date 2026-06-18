// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Which per-app breakdown is expanded in the System section.
enum BreakdownKind {
    case cpu, gpu, memory
}

/// The "System" section of the panel: component temperatures, hardware usage
/// and memory pressure — only the readings that matter, presented cleanly.
/// Tapping CPU, GPU or Memory expands the top consumers of that resource.
struct SystemSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @State private var expanded: BreakdownKind?
    @State private var breakdownRows: [ProcessUsage] = []
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

    var body: some View {
        Group {
            if visibleBlocks.isEmpty {
                EmptyView()
            } else {
                PanelSection(.system, title: l10n.s.systemSection) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(visibleBlocks.enumerated()), id: \.element) { index, block in
                            if index > 0 { Divider() }
                            blockContent(block)
                        }
                    }
                    .panelCard()
                }
            }
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
        }
    }

    /// Card subsections, in order, filtered by the per-item toggles (and whether a
    /// battery exists). Drives divider interleaving so only rendered blocks get one.
    private enum Block: Hashable { case temps, usage, memory, uptime }

    private var usageVisible: Bool {
        sysCPU || sysGPU || (sysBattery && monitor.snapshot.power?.chargePercent != nil)
    }

    private var visibleBlocks: [Block] {
        var blocks: [Block] = []
        if sysTemps { blocks.append(.temps) }
        if usageVisible { blocks.append(.usage) }
        if sysMemory { blocks.append(.memory) }
        if sysUptime { blocks.append(.uptime) }
        return blocks
    }

    @ViewBuilder
    private func blockContent(_ block: Block) -> some View {
        switch block {
        case .temps: temperatureGrid
        case .usage: usageRows
        case .memory: memoryRows
        case .uptime: uptimeRow
        }
    }

    // MARK: Per-app breakdown

    private func toggleBreakdown(_ kind: BreakdownKind) {
        if expanded == kind {
            expanded = nil
            breakdownRows = []
        } else {
            expanded = kind
            breakdownRows = []
            refreshBreakdown()
        }
    }

    private func refreshBreakdown() {
        guard let kind = expanded else { return }
        lastBreakdownRefresh = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            let rows: [ProcessUsage]
            switch kind {
            case .cpu: rows = ProcessUsageService.shared.topCPU()
            case .gpu: rows = ProcessUsageService.shared.topGPU()
            case .memory: rows = ProcessUsageService.shared.topMemory()
            }
            DispatchQueue.main.async {
                guard expanded == kind else { return }
                breakdownRows = rows
            }
        }
    }

    @ViewBuilder
    private func breakdownList(for kind: BreakdownKind) -> some View {
        if expanded == kind {
            VStack(alignment: .leading, spacing: 4) {
                if breakdownRows.isEmpty {
                    Text(l10n.s.breakdownMeasuring)
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
                            Text(kind == .memory ? formatMemory(UInt64(row.value))
                                                 : String(format: "%.1f%%", row.value))
                                .font(.system(size: 10.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            if kind == .memory, !MemoryPurgeService.isProtected(pid: row.pid, name: row.name) {
                                Button("Kill") {
                                    _ = MemoryPurgeService.killProcess(pid: row.pid, name: row.name)
                                    refreshBreakdown()
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.red)
                            }
                        }
                        .padding(.leading, 38)
                    }
                }
            }
            .transition(.opacity)
        }
    }


    // MARK: Temperatures

    private var temperatureGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            subsectionLabel(l10n.s.temperatures)
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

    private var usageRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            subsectionLabel(l10n.s.usageSection)
            if sysCPU {
                usageRow(label: l10n.s.cpuLabel, fraction: monitor.snapshot.cpuUsage, kind: .cpu)
                if graphCPU, monitor.snapshot.cpuHistory.count >= 2 {
                    Sparkline(values: monitor.snapshot.cpuHistory, color: .accentColor, maxValue: 1)
                        .frame(height: 22)
                }
                breakdownList(for: .cpu)
            }
            if sysGPU {
                usageRow(label: l10n.s.gpuLabel, fraction: monitor.snapshot.gpuUsage, kind: .gpu)
                if graphGPU, monitor.snapshot.gpuHistory.count >= 2 {
                    Sparkline(values: monitor.snapshot.gpuHistory, color: .cyan, maxValue: 1)
                        .frame(height: 22)
                }
                breakdownList(for: .gpu)
            }
            if sysBattery {
                batteryUsageRow
            }
        }
    }

    // MARK: Battery (charge level, next to CPU/GPU) and uptime

    @ViewBuilder
    private var batteryUsageRow: some View {
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
                }
                if graphBattery, monitor.snapshot.batteryHistory.count >= 2 {
                    Sparkline(values: monitor.snapshot.batteryHistory, color: .green, maxValue: 1)
                        .frame(height: 22)
                }
            }
        }
    }

    private func chargeTint(_ charge: Int) -> Color {
        charge < 20 ? .red : (charge < 40 ? .yellow : .green)
    }

    private var uptimeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text("\(l10n.s.systemUptime) \(Self.uptimeString())")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    static func uptimeString() -> String {
        let total = Int(ProcessInfo.processInfo.systemUptime)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)min" }
        return "\(minutes)min"
    }

    private func usageRow(label: String, fraction: Double?, kind: BreakdownKind) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { toggleBreakdown(kind) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded == kind ? 90 : 0))
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
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Memory

    private var memoryRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            subsectionLabel(l10n.s.memorySection)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { toggleBreakdown(.memory) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded == .memory ? 90 : 0))
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if graphMemory, monitor.snapshot.memoryHistory.count >= 2 {
                Sparkline(values: monitor.snapshot.memoryHistory, color: .mint, maxValue: 1)
                    .frame(height: 22)
            }
            breakdownList(for: .memory)
        }
    }

    private func subsectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Thin capacity bar for CPU/GPU usage.
private struct UsageBar: View {
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
        case ..<0.85: return .yellow
        default: return .red
        }
    }
}

/// Traffic-light pill for memory pressure: green = normal, yellow = caution,
/// red = critical.
struct PressureIndicator: View {
    @ObservedObject private var l10n = L10n.shared
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
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
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
