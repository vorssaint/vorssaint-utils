// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The "Network" card: live download/upload speed, a history graph and the
/// totals moved this session.
struct NetworkSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var speed = SpeedTest.shared
    @Environment(\.colorScheme) private var colorScheme
    var collapsible = true
    @AppStorage(DefaultsKey.monitorGraphNetwork) private var showGraph = true
    @AppStorage(DefaultsKey.monitorNetSpeed) private var netSpeed = true
    @AppStorage(DefaultsKey.monitorNetTotals) private var netTotals = true
    @AppStorage(DefaultsKey.monitorNetTest) private var netTest = true
    @AppStorage(DefaultsKey.panelNetworkOrder) private var networkOrderRaw = ""
    @State private var draggingBlock: Block?

    var body: some View {
        PanelSection(.network, title: l10n.s.networkSection, collapsible: collapsible,
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
    }

    private enum Block: String, PanelOrderItem { case speed, totals, test }

    private var visibleBlocks: [Block] {
        orderedBlocks.filter(isVisible)
    }

    private func blocks(editing: Bool) -> [Block] {
        editing ? orderedBlocks : visibleBlocks
    }

    private var orderedBlocks: [Block] {
        _ = networkOrderRaw
        return PanelLayout.itemOrder(Block.self, key: DefaultsKey.panelNetworkOrder)
    }

    private var blockOrderBinding: Binding<[Block]> {
        Binding {
            orderedBlocks
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.panelNetworkOrder)
        }
    }

    private func isVisible(_ block: Block) -> Bool {
        switch block {
        case .speed: return netSpeed
        case .totals: return netTotals
        case .test: return netTest
        }
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelNetworkOrder)
        networkOrderRaw = ""
        netSpeed = true
        netTotals = true
        netTest = true
    }

    @ViewBuilder
    private func blockContent(_ block: Block, editing: Bool) -> some View {
        switch block {
        case .speed: speedBlock(editing: editing)
        case .totals: totalsRow(editing: editing)
        case .test: speedTestRow(editing: editing)
        }
    }

    @ViewBuilder
    private func speedBlock(editing: Bool) -> some View {
        if !netSpeed {
            PanelHiddenItemRow(title: l10n.s.monitorItemNetSpeed,
                               systemImage: "arrow.down",
                               isVisible: $netSpeed)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if editing {
                    HStack {
                        Spacer(minLength: 0)
                        PanelInlineHideButton(isVisible: $netSpeed)
                    }
                }
                HStack(spacing: 10) {
                    rateColumn(icon: "arrow.down",
                               label: l10n.s.networkDownload,
                               value: monitor.snapshot.netDownBytesPerSec,
                               color: .accentColor)
                    Divider().frame(height: 28)
                    rateColumn(icon: "arrow.up",
                               label: l10n.s.networkUpload,
                               value: monitor.snapshot.netUpBytesPerSec,
                               color: PanelMetricColor.green(for: colorScheme))
                }
                if showGraph, monitor.snapshot.netDownHistory.count >= 2 {
                    graph
                }
            }
        }
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

    /// Download (filled) and upload (line) share one scale so they compare fairly.
    private var graph: some View {
        let down = monitor.snapshot.netDownHistory
        let up = monitor.snapshot.netUpHistory
        let peak = max(down.max() ?? 0, up.max() ?? 0, 1)
        return ZStack {
            Sparkline(values: down, color: .accentColor, maxValue: peak, showsZeroBaseline: true)
            Sparkline(values: up,
                      color: PanelMetricColor.green(for: colorScheme),
                      maxValue: peak,
                      fillOpacity: 0.08)
        }
        .frame(height: 30)
    }

    @ViewBuilder
    private func totalsRow(editing: Bool) -> some View {
        if !netTotals {
            PanelHiddenItemRow(title: l10n.s.monitorItemNetTotals,
                               systemImage: "sum",
                               isVisible: $netTotals)
        } else {
            HStack(spacing: 6) {
                Text(l10n.s.networkThisSession)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                if let down = monitor.snapshot.netTotalDown, let up = monitor.snapshot.netTotalUp {
                    Text("↓\(MetricFormat.bytes(down))  ↑\(MetricFormat.bytes(up))")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if editing {
                    PanelInlineHideButton(isVisible: $netTotals)
                }
            }
        }
    }

    /// On-demand internet speed test (latency, download, upload).
    @ViewBuilder
    private func speedTestRow(editing: Bool) -> some View {
        if !netTest {
            PanelHiddenItemRow(title: l10n.s.monitorItemNetTest,
                               systemImage: "gauge.with.dots.needle.67percent",
                               isVisible: $netTest)
        } else {
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
                            .contentTransition(.numericText())
                    }
                    if editing {
                        PanelInlineHideButton(isVisible: $netTest)
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
        }
    }

    private func mbps(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
