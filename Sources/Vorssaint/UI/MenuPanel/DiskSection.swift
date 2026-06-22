// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct DiskSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var protection = DiskProtectionService.shared
    @Environment(\.colorScheme) private var colorScheme
    var collapsible = true
    @AppStorage(DefaultsKey.monitorGraphDisk) private var showGraph = true
    @AppStorage(DefaultsKey.monitorDiskUsage) private var diskUsage = true
    @AppStorage(DefaultsKey.monitorDiskActivity) private var diskActivity = true
    @AppStorage(DefaultsKey.monitorDiskSMART) private var diskSMART = true
    @AppStorage(DefaultsKey.monitorDiskProtection) private var diskProtection = true
    @AppStorage(DefaultsKey.monitorDiskTools) private var diskTools = true
    @AppStorage(DefaultsKey.panelDiskOrder) private var diskOrderRaw = ""
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @State private var draggingBlock: Block?
    @State private var selectedDiskID: String?

    private enum Block: String, PanelOrderItem { case usage, activity, smart, protection, tools }

    var body: some View {
        PanelSection(.disk, title: l10n.s.diskSection, collapsible: collapsible,
                     supportsEditing: true,
                     resetAction: resetPanelDefaults) { editing in
            VStack(alignment: .leading, spacing: 10) {
                if disks.isEmpty {
                    Text(l10n.s.diskNoDisks)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                } else {
                    diskSelector
                    if let selected = selectedDisk {
                        ForEach(blocks(editing: editing), id: \.self) { block in
                            Divider()
                            PanelReorderableItem(item: block,
                                                 isEnabled: editing,
                                                 order: blockOrderBinding,
                                                 dragging: $draggingBlock) {
                                HStack(alignment: .top, spacing: 8) {
                                    if editing {
                                        PanelDragHandle()
                                    }
                                    blockContent(block, disk: selected, editing: editing)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
            .panelCard()
            .onAppear(perform: ensureSelectedDisk)
            .onChange(of: disks.map(\.id)) { _, _ in ensureSelectedDisk() }
        }
    }

    private var disks: [DiskDeviceReading] {
        monitor.snapshot.disk?.devices ?? []
    }

    private var selectedDisk: DiskDeviceReading? {
        if let selectedDiskID,
           let disk = disks.first(where: { $0.id == selectedDiskID }) {
            return disk
        }
        return disks.first
    }

    private var ejectableDisks: [DiskDeviceReading] {
        var seen = Set<String>()
        return disks.filter { disk in
            guard disk.canEject, let id = disk.ejectBSDName else { return false }
            return seen.insert(id).inserted
        }
    }

    private func ensureSelectedDisk() {
        guard !disks.isEmpty else {
            selectedDiskID = nil
            return
        }
        if selectedDiskID == nil || !disks.contains(where: { $0.id == selectedDiskID }) {
            selectedDiskID = disks.first?.id
        }
    }

    private var orderedBlocks: [Block] {
        _ = diskOrderRaw
        return PanelLayout.itemOrder(Block.self, key: DefaultsKey.panelDiskOrder)
    }

    private var blockOrderBinding: Binding<[Block]> {
        Binding {
            orderedBlocks
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.panelDiskOrder)
        }
    }

    private func blocks(editing: Bool) -> [Block] {
        editing ? orderedBlocks : orderedBlocks.filter(isVisible)
    }

    private func isVisible(_ block: Block) -> Bool {
        switch block {
        case .usage: return diskUsage
        case .activity: return diskActivity
        case .smart: return diskSMART
        case .protection: return diskProtection
        case .tools: return diskTools
        }
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelDiskOrder)
        diskOrderRaw = ""
        diskUsage = true
        diskActivity = true
        diskSMART = true
        diskProtection = true
        diskTools = true
    }

    @ViewBuilder
    private func blockContent(_ block: Block, disk: DiskDeviceReading, editing: Bool) -> some View {
        switch block {
        case .usage: usageBlock(disk: disk, editing: editing)
        case .activity: activityBlock(disk: disk, editing: editing)
        case .smart: smartBlock(disk: disk, editing: editing)
        case .protection: protectionBlock(disk: disk, editing: editing)
        case .tools: toolsBlock(disk: disk, editing: editing)
        }
    }

    @ViewBuilder
    private var diskSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.s.diskSelect)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(disks) { disk in
                        Button {
                            selectedDiskID = disk.id
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: disk.isInternal ? "internaldrive" : "externaldrive")
                                    .font(.system(size: 10, weight: .semibold))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(disk.name)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .lineLimit(1)
                                    Text("\(MetricFormat.percent(disk.usedFraction)) \(l10n.s.diskUsed)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(selectorBackground(for: disk))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func selectorBackground(for disk: DiskDeviceReading) -> some ShapeStyle {
        disk.id == selectedDisk?.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)
    }

    @ViewBuilder
    private func usageBlock(disk: DiskDeviceReading, editing: Bool) -> some View {
        if !diskUsage {
            PanelHiddenItemRow(title: l10n.s.monitorItemDiskUsage,
                               systemImage: "internaldrive",
                               isVisible: $diskUsage)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                blockHeader(l10n.s.monitorItemDiskUsage, editing: editing, visible: $diskUsage)
                VStack(alignment: .leading, spacing: 5) {
                    diskTitleRow(disk)
                    DiskUsageBar(fraction: disk.usedFraction)
                    HStack(spacing: 6) {
                        Text("\(MetricFormat.percent(disk.usedFraction)) \(l10n.s.diskUsed)")
                        Spacer()
                        Text("\(MetricFormat.diskBytes(disk.freeBytes)) \(l10n.s.diskFree)")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    Text("\(MetricFormat.diskBytes(disk.usedBytes)) / \(MetricFormat.diskBytes(disk.totalBytes))")
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func activityBlock(disk: DiskDeviceReading, editing: Bool) -> some View {
        if !diskActivity {
            PanelHiddenItemRow(title: l10n.s.monitorItemDiskActivity,
                               systemImage: "arrow.up.arrow.down",
                               isVisible: $diskActivity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                blockHeader(l10n.s.monitorItemDiskActivity, editing: editing, visible: $diskActivity)
                HStack(spacing: 10) {
                    rateColumn(icon: "arrow.down",
                               label: l10n.s.diskRead,
                               value: disk.readBytesPerSec,
                               color: .accentColor)
                    Divider().frame(height: 28)
                    rateColumn(icon: "arrow.up",
                               label: l10n.s.diskWrite,
                               value: disk.writeBytesPerSec,
                               color: PanelMetricColor.pink(for: colorScheme))
                }
                if showGraph, monitor.snapshot.diskReadHistory.count >= 2 {
                    graph
                }
                HStack(spacing: 6) {
                    Text(l10n.s.networkThisSession)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("↓ \(MetricFormat.diskBytes(disk.totalReadBytes ?? 0))  ↑ \(MetricFormat.diskBytes(disk.totalWrittenBytes ?? 0))")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var graph: some View {
        let read = monitor.snapshot.diskReadHistory
        let write = monitor.snapshot.diskWriteHistory
        let peak = max(read.max() ?? 0, write.max() ?? 0, 1)
        return ZStack {
            Sparkline(values: read, color: .accentColor, maxValue: peak, showsZeroBaseline: true)
            Sparkline(values: write,
                      color: PanelMetricColor.pink(for: colorScheme),
                      maxValue: peak,
                      fillOpacity: 0.08)
        }
        .frame(height: 30)
    }

    private func rateColumn(icon: String, label: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.map { MetricFormat.bytesPerSec($0) } ?? l10n.s.networkMeasuring)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func smartBlock(disk: DiskDeviceReading, editing: Bool) -> some View {
        if !diskSMART {
            PanelHiddenItemRow(title: l10n.s.monitorItemDiskSMART,
                               systemImage: "checkmark.shield",
                               isVisible: $diskSMART)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                blockHeader(l10n.s.monitorItemDiskSMART, editing: editing, visible: $diskSMART)
                VStack(alignment: .leading, spacing: 5) {
                    diskTitleRow(disk)
                    if let smart = disk.smart {
                        smartRows(smart)
                    } else {
                        Text(l10n.s.diskSMARTUnavailable)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func smartRows(_ smart: DiskSMARTReading) -> some View {
        if let status = smart.status {
            smartRow(l10n.s.diskSMARTStatus, status)
        }
        if let written = smart.totalWrittenBytes {
            smartRow(l10n.s.diskTotalWritten, MetricFormat.diskBytesPrecise(written))
        }
        if let read = smart.totalReadBytes {
            smartRow(l10n.s.diskTotalRead, MetricFormat.diskBytesPrecise(read))
        }
        if let temp = smart.temperatureCelsius {
            smartRow(l10n.s.diskTemperature, MetricFormat.temperature(temp, unit: displayTemperatureUnit))
        }
        if let health = smart.healthPercent {
            smartRow(l10n.s.diskHealth, "\(health)%")
        }
        if let cycles = smart.powerCycles {
            smartRow(l10n.s.diskPowerCycles, "\(cycles)")
        }
        if let hours = smart.powerOnHours {
            smartRow(l10n.s.diskPowerOnHours, "\(hours)")
        }
    }

    private func smartRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func protectionBlock(disk: DiskDeviceReading, editing: Bool) -> some View {
        if !diskProtection {
            PanelHiddenItemRow(title: l10n.s.monitorItemDiskProtection,
                               systemImage: "eject",
                               isVisible: $diskProtection)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                blockHeader(l10n.s.monitorItemDiskProtection, editing: editing, visible: $diskProtection)
                HStack(spacing: 7) {
                    Button {
                        protection.eject(disk)
                    } label: {
                        Label(l10n.s.diskEject, systemImage: "eject.fill")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!disk.canEject || protection.state(for: disk) == .ejecting)

                    Button {
                        protection.ejectAll(disks)
                    } label: {
                        Label(l10n.s.diskEjectAll, systemImage: "eject.fill")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(ejectableDisks.isEmpty)
                }
                Text(disk.canEject ? ejectCaption(for: disk) : l10n.s.diskNoExternal)
                    .font(.system(size: 9.5))
                    .foregroundStyle(disk.canEject ? ejectCaptionColor(for: disk) : .secondary)
                    .lineLimit(2)
            }
        }
    }

    private func ejectCaption(for disk: DiskDeviceReading) -> String {
        switch protection.state(for: disk) {
        case .ejecting: return l10n.s.diskEjecting
        case .ready: return l10n.s.diskReadyToRemove
        case .failed: return l10n.s.diskEjectFailed
        case .none: return l10n.s.diskProtectionCaption
        }
    }

    private func ejectCaptionColor(for disk: DiskDeviceReading) -> Color {
        switch protection.state(for: disk) {
        case .ready: return PanelMetricColor.green(for: colorScheme)
        case .failed: return PanelMetricColor.red(for: colorScheme)
        default: return .secondary
        }
    }

    @ViewBuilder
    private func toolsBlock(disk: DiskDeviceReading, editing: Bool) -> some View {
        if !diskTools {
            PanelHiddenItemRow(title: l10n.s.monitorItemDiskTools,
                               systemImage: "folder.badge.gearshape",
                               isVisible: $diskTools)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                blockHeader(l10n.s.monitorItemDiskTools, editing: editing, visible: $diskTools)
                HStack(spacing: 8) {
                    Text(disk.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: disk.mountPath))
                    } label: {
                        Label(l10n.s.diskOpenInFinder, systemImage: "folder")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Storage-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(l10n.s.diskStorageSettings, systemImage: "gearshape")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func diskTitleRow(_ disk: DiskDeviceReading) -> some View {
        HStack(spacing: 6) {
            Image(systemName: disk.isInternal ? "internaldrive" : "externaldrive")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(disk.name)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(disk.isInternal ? l10n.s.diskInternal : l10n.s.diskExternal)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
    }

    private func blockHeader(_ title: String, editing: Bool, visible: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if editing {
                PanelInlineHideButton(isVisible: visible)
            }
        }
    }

    private var displayTemperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }
}

private struct DiskUsageBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: max(3, proxy.size.width * min(1, max(0, fraction))))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 6)
    }

    private var color: Color {
        switch fraction {
        case ..<0.75: return .accentColor
        case ..<0.9: return PanelMetricColor.yellow(for: colorScheme)
        default: return PanelMetricColor.red(for: colorScheme)
        }
    }
}
