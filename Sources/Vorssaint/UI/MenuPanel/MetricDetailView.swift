// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum MetricDetailKind: String, Equatable, Identifiable {
    case cpu, gpu, memory, network, disk, battery, power

    var id: String { rawValue }

    var panelSection: PanelSectionID {
        switch self {
        case .cpu, .gpu, .memory, .battery:
            return .system
        case .network:
            return .network
        case .disk:
            return .disk
        case .power:
            return .power
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "rectangle.connected.to.line.below"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .battery: return "battery.100"
        case .power: return "powerplug.fill"
        }
    }

    var monitorNeeds: SystemMonitorPanelNeeds {
        switch self {
        case .cpu:
            return SystemMonitorPanelNeeds(cpu: true, cpuTemperature: true)
        case .gpu:
            return SystemMonitorPanelNeeds(gpu: true, gpuTemperature: true)
        case .memory:
            return SystemMonitorPanelNeeds(memory: true)
        case .network:
            return SystemMonitorPanelNeeds(network: true)
        case .disk:
            return SystemMonitorPanelNeeds(disk: true)
        case .battery:
            return SystemMonitorPanelNeeds(power: true, battery: true, batteryTemperature: true)
        case .power:
            return SystemMonitorPanelNeeds(power: true)
        }
    }

    func title(_ s: Strings) -> String {
        switch self {
        case .cpu: return s.cpuLabel
        case .gpu: return s.gpuLabel
        case .memory: return s.memorySection
        case .network: return s.networkSection
        case .disk: return s.diskSection
        case .battery: return s.batteryLabel
        case .power: return s.powerSection
        }
    }

    var processKind: BreakdownKind? {
        switch self {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .memory: return .memory
        case .power: return .energy
        case .network, .disk, .battery: return nil
        }
    }
}

extension MenuBarMetric {
    var detailKind: MetricDetailKind {
        switch self {
        case .cpu, .cpuTemperature:
            return .cpu
        case .gpu, .gpuTemperature:
            return .gpu
        case .memory:
            return .memory
        case .network:
            return .network
        case .diskUsage, .diskActivity:
            return .disk
        case .battery, .batteryTemperature:
            return .battery
        case .power:
            return .power
        }
    }
}

struct MetricDetailView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var speed = SpeedTest.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    let kind: MetricDetailKind
    @State private var processRows: [ProcessUsage] = []
    @State private var processRowsLoading = false
    @State private var lastProcessRefresh = Date.distantPast
    @State private var refreshSerial = 0
    private let processLimit = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryCard
            detailCard
            if kind == .network {
                speedTestCard
            }
            if kind.processKind != nil {
                processCard
            }
        }
        .onAppear { refreshProcessRows(force: true, delay: 0.65) }
        .onChange(of: kind) { _, _ in refreshProcessRows(force: true, delay: 0.65) }
        .onReceive(monitor.$snapshot) { _ in refreshProcessRows(force: false, delay: 0.85) }
        .onDisappear {
            refreshSerial &+= 1
            processRows = []
            processRowsLoading = false
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(summaryColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(primaryValue)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(secondaryValue)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            graph
        }
        .panelCard()
    }

    @ViewBuilder
    private var graph: some View {
        switch kind {
        case .cpu:
            historyGraph(monitor.snapshot.cpuHistory, color: summaryColor, maxValue: 1)
        case .gpu:
            historyGraph(monitor.snapshot.gpuHistory, color: summaryColor, maxValue: 1)
        case .memory:
            historyGraph(monitor.snapshot.memoryHistory, color: summaryColor, maxValue: 1)
        case .network:
            networkGraph
        case .disk:
            diskGraph
        case .battery:
            historyGraph(monitor.snapshot.batteryHistory, color: summaryColor, maxValue: 1)
        case .power:
            historyGraph(monitor.snapshot.systemPowerHistory, color: summaryColor)
        }
    }

    @ViewBuilder
    private func historyGraph(_ values: [Double], color: Color, maxValue: Double? = nil) -> some View {
        if values.count >= 2 {
            Sparkline(values: values,
                      color: color,
                      maxValue: maxValue,
                      showsZeroBaseline: true)
                .frame(height: 38)
        }
    }

    @ViewBuilder
    private var networkGraph: some View {
        let down = monitor.snapshot.netDownHistory
        let up = monitor.snapshot.netUpHistory
        if down.count >= 2 || up.count >= 2 {
            let peak = max(down.max() ?? 0, up.max() ?? 0, 1)
            ZStack {
                Sparkline(values: down, color: .accentColor, maxValue: peak, showsZeroBaseline: true)
                Sparkline(values: up,
                          color: PanelMetricColor.green(for: colorScheme),
                          maxValue: peak,
                          fillOpacity: 0.08)
            }
            .frame(height: 38)
        }
    }

    @ViewBuilder
    private var diskGraph: some View {
        let read = monitor.snapshot.diskReadHistory
        let write = monitor.snapshot.diskWriteHistory
        if read.count >= 2 || write.count >= 2 {
            let peak = max(read.max() ?? 0, write.max() ?? 0, 1)
            ZStack {
                Sparkline(values: read, color: summaryColor, maxValue: peak, showsZeroBaseline: true)
                Sparkline(values: write,
                          color: PanelMetricColor.pink(for: colorScheme),
                          maxValue: peak,
                          fillOpacity: 0.08)
            }
            .frame(height: 38)
        }
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(detailRows) { row in
                detailRow(row)
            }
        }
        .panelCard()
    }

    private var speedTestCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if speed.isRunning {
                    ProgressView().controlSize(.small)
                    Text(l10n.s.speedTestTesting)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        speed.start()
                    } label: {
                        Label(speed.downloadMbps == nil ? l10n.s.speedTestRun : l10n.s.speedTestAgain,
                              systemImage: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
                if let down = speed.downloadMbps, let up = speed.uploadMbps {
                    Text("↓\(mbps(down)) ↑\(mbps(up)) Mbps")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
            }
            if case .failed = speed.phase {
                Text(l10n.s.speedTestFailed)
                    .font(.system(size: 10))
                    .foregroundStyle(PanelMetricColor.orange(for: colorScheme))
            } else if let latency = speed.latencyMs {
                Text("\(l10n.s.speedTestLatency): \(Int(latency.rounded())) ms")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .panelCard()
    }

    private var processCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(kind == .power ? l10n.s.energyAppsTitle : l10n.s.usageSection)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            if processRows.isEmpty {
                Text(processRowsLoading ? l10n.s.breakdownMeasuring : emptyProcessText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(processRows) { row in
                    ProcessUsageRow(row: row, value: processValue(row))
                }
            }
        }
        .panelCard()
    }

    private var detailRows: [MetricDetailRow] {
        let snapshot = monitor.snapshot
        switch kind {
        case .cpu:
            return [
                row(l10n.s.usageSection, snapshot.cpuUsage.map(MetricFormat.percent) ?? l10n.s.networkMeasuring),
                row(l10n.s.temperatures, snapshot.cpuTemperature.map(formatTemperature) ?? l10n.s.monitorUnavailable),
                row(l10n.s.systemUptime, SystemSection.uptimeString()),
            ]
        case .gpu:
            return [
                row(l10n.s.usageSection, snapshot.gpuUsage.map(MetricFormat.percent) ?? l10n.s.networkMeasuring),
                row(l10n.s.temperatures, snapshot.gpuTemperature.map(formatTemperature) ?? l10n.s.monitorUnavailable),
            ]
        case .memory:
            let used = snapshot.memoryUsed.map(formatMemory) ?? l10n.s.networkMeasuring
            let total = snapshot.memoryTotal.map(formatMemory) ?? "-"
            return [
                row(l10n.s.memorySection, "\(used) / \(total)"),
                row(l10n.s.memoryPressure, pressureText(snapshot.memoryPressure), showsPressure: true),
            ]
        case .network:
            return [
                row(l10n.s.networkDownload,
                    snapshot.netDownBytesPerSec.map(MetricFormat.bytesPerSec) ?? l10n.s.networkMeasuring),
                row(l10n.s.networkUpload,
                    snapshot.netUpBytesPerSec.map(MetricFormat.bytesPerSec) ?? l10n.s.networkMeasuring),
                row(l10n.s.networkThisSession, sessionNetworkText(snapshot)),
            ]
        case .disk:
            guard let disk = primaryDisk(from: snapshot.disk) else {
                return [row(l10n.s.diskSection, l10n.s.diskNoDisks)]
            }
            let activity = diskActivity(from: snapshot.disk)
            return [
                row(disk.name, "\(MetricFormat.percent(disk.usedFraction)) \(l10n.s.diskUsed)"),
                row(l10n.s.diskFree, MetricFormat.diskBytes(disk.freeBytes)),
                row(l10n.s.diskRead, activity.map { MetricFormat.bytesPerSec($0.read) } ?? l10n.s.networkMeasuring),
                row(l10n.s.diskWrite, activity.map { MetricFormat.bytesPerSec($0.write) } ?? l10n.s.networkMeasuring),
            ]
        case .battery:
            let power = snapshot.power
            return [
                row(l10n.s.batteryLabel, power?.chargePercent.map { "\($0)%" } ?? l10n.s.networkMeasuring),
                row(l10n.s.powerBattery, batteryFlowText(power)),
                row(l10n.s.temperatures, snapshot.batteryTemperature.map(formatTemperature) ?? l10n.s.monitorUnavailable),
                row(l10n.s.powerHealth, power?.healthPercent.map { "\(Int($0.rounded()))%" } ?? "-"),
                row(l10n.s.powerCycles, power?.cycleCount.map(String.init) ?? "-"),
            ]
        case .power:
            let power = snapshot.power
            return [
                row(l10n.s.powerSystem, power?.systemWatts.map(MetricFormat.watts) ?? l10n.s.networkMeasuring),
                row(l10n.s.powerAdapter, adapterText(power)),
                row(l10n.s.powerBattery, batteryFlowText(power)),
            ]
        }
    }

    private var primaryValue: String {
        let snapshot = monitor.snapshot
        switch kind {
        case .cpu:
            return snapshot.cpuUsage.map(MetricFormat.percent) ?? "-"
        case .gpu:
            return snapshot.gpuUsage.map(MetricFormat.percent) ?? "-"
        case .memory:
            guard let used = snapshot.memoryUsed, let total = snapshot.memoryTotal, total > 0 else { return "-" }
            return MetricFormat.percent(Double(used) / Double(total))
        case .network:
            return snapshot.netDownBytesPerSec.map(MetricFormat.bytesPerSecCompact) ?? "-"
        case .disk:
            return primaryDisk(from: snapshot.disk).map { MetricFormat.percent($0.usedFraction) } ?? "-"
        case .battery:
            return snapshot.power?.chargePercent.map { "\($0)%" } ?? "-"
        case .power:
            return snapshot.power?.systemWatts.map(MetricFormat.wattsCompact) ?? "-"
        }
    }

    private var secondaryValue: String {
        let snapshot = monitor.snapshot
        switch kind {
        case .cpu:
            return snapshot.cpuTemperature.map(formatTemperature) ?? l10n.s.temperatures
        case .gpu:
            return snapshot.gpuTemperature.map(formatTemperature) ?? l10n.s.temperatures
        case .memory:
            guard let used = snapshot.memoryUsed, let total = snapshot.memoryTotal else { return l10n.s.memoryPressure }
            return "\(formatMemory(used)) / \(formatMemory(total))"
        case .network:
            return "\(l10n.s.networkUpload) \(snapshot.netUpBytesPerSec.map(MetricFormat.bytesPerSecCompact) ?? "-")"
        case .disk:
            guard let disk = primaryDisk(from: snapshot.disk) else { return l10n.s.diskNoDisks }
            return "\(MetricFormat.diskBytes(disk.freeBytes)) \(l10n.s.diskFree)"
        case .battery:
            return (snapshot.power?.isCharging ?? false) ? l10n.s.powerCharging : l10n.s.powerOnBattery
        case .power:
            return powerSubtitle(snapshot.power)
        }
    }

    private var summaryColor: Color {
        switch kind {
        case .cpu, .network:
            return .accentColor
        case .gpu:
            return PanelMetricColor.cyan(for: colorScheme)
        case .memory:
            return PanelMetricColor.mint(for: colorScheme)
        case .disk:
            return PanelMetricColor.yellow(for: colorScheme)
        case .battery:
            return PanelMetricColor.green(for: colorScheme)
        case .power:
            return PanelMetricColor.orange(for: colorScheme)
        }
    }

    private var emptyProcessText: String {
        kind == .power ? l10n.s.energyAppsIdle : l10n.s.breakdownMeasuring
    }

    private func detailRow(_ row: MetricDetailRow) -> some View {
        HStack(spacing: 8) {
            Text(row.title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if row.showsPressure, case .memory = kind {
                PressureIndicator(pressure: monitor.snapshot.memoryPressure)
            } else {
                Text(row.value)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func row(_ title: String, _ value: String, showsPressure: Bool = false) -> MetricDetailRow {
        MetricDetailRow(id: title, title: title, value: value, showsPressure: showsPressure)
    }

    private func refreshProcessRows(force: Bool, delay: TimeInterval = 0) {
        guard let processKind = kind.processKind else { return }
        if force {
            if let cached = ProcessUsageService.shared.cachedTop(processKind, limit: processLimit) {
                processRows = cached
                processRowsLoading = false
            } else {
                processRows = []
                processRowsLoading = true
            }
        }
        guard force || Date().timeIntervalSince(lastProcessRefresh) > 4 else { return }

        refreshSerial &+= 1
        let serial = refreshSerial
        let run = {
            guard self.refreshSerial == serial,
                  self.kind.processKind == processKind else { return }
            self.lastProcessRefresh = Date()
            self.processRowsLoading = self.processRows.isEmpty
            DispatchQueue.global(qos: .utility).async {
                let rows = ProcessUsageService.shared.top(processKind, limit: processLimit)
                DispatchQueue.main.async {
                    guard self.refreshSerial == serial,
                          self.kind.processKind == processKind else { return }
                    self.processRowsLoading = false
                    if !rows.isEmpty || self.processRows.isEmpty {
                        self.processRows = rows
                    }
                }
            }
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: run)
        } else {
            run()
        }
    }

    private func processValue(_ row: ProcessUsage) -> String {
        kind == .memory ? formatMemory(UInt64(row.value)) : String(format: "%.1f%%", row.value)
    }

    private func primaryDisk(from reading: DiskReading?) -> DiskDeviceReading? {
        guard let devices = reading?.devices, !devices.isEmpty else { return nil }
        return devices.first(where: { $0.isInternal }) ?? devices.first
    }

    private func diskActivity(from reading: DiskReading?) -> (read: Double, write: Double)? {
        let devices = reading?.uniqueIODevices ?? []
        guard !devices.isEmpty else { return nil }
        let readValues = devices.compactMap(\.readBytesPerSec)
        let writeValues = devices.compactMap(\.writeBytesPerSec)
        guard !readValues.isEmpty || !writeValues.isEmpty else { return nil }
        return (readValues.reduce(0, +), writeValues.reduce(0, +))
    }

    private func formatTemperature(_ celsius: Double) -> String {
        MetricFormat.temperature(celsius, unit: displayTemperatureUnit)
    }

    private var displayTemperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        Self.memoryFormatter.string(fromByteCount: Int64(bytes))
    }

    private func pressureText(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: return l10n.s.pressureNormal
        case .warning: return l10n.s.pressureWarning
        case .critical: return l10n.s.pressureCritical
        case .unknown: return "-"
        }
    }

    private func sessionNetworkText(_ snapshot: SystemSnapshot) -> String {
        guard let down = snapshot.netTotalDown, let up = snapshot.netTotalUp else { return "-" }
        return "↓\(MetricFormat.bytes(down))  ↑\(MetricFormat.bytes(up))"
    }

    private func adapterText(_ power: PowerReading?) -> String {
        guard let power else { return "-" }
        if power.externalConnected, let adapter = power.adapterWatts {
            return MetricFormat.watts(adapter)
        }
        if power.externalConnected { return l10n.s.powerPluggedIn }
        return "-"
    }

    private func batteryFlowText(_ power: PowerReading?) -> String {
        guard let flow = power?.batteryWatts else { return "-" }
        let label = flow >= 0 ? l10n.s.powerCharging : l10n.s.powerOnBattery
        return "\(MetricFormat.watts(abs(flow))) · \(label)"
    }

    private func powerSubtitle(_ power: PowerReading?) -> String {
        guard let power else { return l10n.s.powerUnavailable }
        if power.externalConnected { return l10n.s.powerPluggedIn }
        if power.hasBattery { return l10n.s.powerOnBattery }
        return l10n.s.powerUnavailable
    }

    private func mbps(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private static let memoryFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter
    }()
}

private struct MetricDetailRow: Identifiable {
    let id: String
    let title: String
    let value: String
    var showsPressure = false
}
