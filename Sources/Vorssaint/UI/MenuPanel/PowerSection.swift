// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The "Power" card: how much the Mac is drawing overall, from the adapter, and
/// to/from the battery. Rows that the hardware cannot report are simply hidden;
/// a Mac that reports nothing shows a short note instead.
struct PowerSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @Environment(\.colorScheme) private var colorScheme
    var collapsible = true
    @AppStorage(DefaultsKey.monitorGraphPower) private var showGraph = true
    @AppStorage(DefaultsKey.monitorPwrSystem) private var pwrSystem = true
    @AppStorage(DefaultsKey.monitorPwrAdapter) private var pwrAdapter = true
    @AppStorage(DefaultsKey.monitorPwrBattery) private var pwrBattery = true
    @AppStorage(DefaultsKey.monitorPwrHealth) private var pwrHealth = true
    @AppStorage(DefaultsKey.panelPowerOrder) private var powerOrderRaw = ""
    @State private var draggingBlock: Block?

    var body: some View {
        PanelSection(.power, title: l10n.s.powerSection, collapsible: collapsible,
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

    private enum Block: String, PanelOrderItem { case system, adapter, battery, health }

    private var orderedBlocks: [Block] {
        _ = powerOrderRaw
        return PanelLayout.itemOrder(Block.self, key: DefaultsKey.panelPowerOrder)
    }

    private var blockOrderBinding: Binding<[Block]> {
        Binding {
            orderedBlocks
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.panelPowerOrder)
        }
    }

    private func blocks(editing: Bool) -> [Block] {
        if editing { return orderedBlocks }
        return orderedBlocks.filter(isVisible)
    }

    private func isVisible(_ block: Block) -> Bool {
        guard let power = monitor.snapshot.power, !power.isEmpty else { return false }
        switch block {
        case .system: return pwrSystem && power.systemWatts != nil
        case .adapter: return pwrAdapter && power.externalConnected && power.adapterWatts != nil
        case .battery: return pwrBattery && power.hasBattery && power.batteryWatts != nil
        case .health: return pwrHealth && power.healthPercent != nil
        }
    }

    @ViewBuilder
    private func blockContent(_ block: Block, editing: Bool) -> some View {
        if let power = monitor.snapshot.power, !power.isEmpty {
            switch block {
            case .system:
            if pwrSystem, let watts = power.systemWatts {
                row(icon: "bolt.fill", color: PanelMetricColor.orange(for: colorScheme),
                    label: l10n.s.powerSystem, value: MetricFormat.watts(watts),
                    visible: $pwrSystem, editing: editing)
                if showGraph, monitor.snapshot.systemPowerHistory.count >= 2 {
                    Sparkline(values: monitor.snapshot.systemPowerHistory,
                              color: PanelMetricColor.orange(for: colorScheme),
                              showsZeroBaseline: true)
                        .frame(height: 26)
                }
            } else if editing && !pwrSystem {
                PanelHiddenItemRow(title: l10n.s.powerSystem,
                                   systemImage: "bolt.fill",
                                   isVisible: $pwrSystem)
            }
            case .adapter:
            if pwrAdapter, power.externalConnected, let adapter = power.adapterWatts {
                row(icon: "powerplug.fill", color: .accentColor,
                    label: l10n.s.powerAdapter, value: MetricFormat.watts(adapter),
                    caption: adapterCaption(power),
                    visible: $pwrAdapter, editing: editing)
            } else if editing && !pwrAdapter {
                PanelHiddenItemRow(title: l10n.s.powerAdapter,
                                   systemImage: "powerplug.fill",
                                   isVisible: $pwrAdapter)
            }
            case .battery:
            if pwrBattery, power.hasBattery, let flow = power.batteryWatts {
                row(icon: flow >= 0 ? "battery.100.bolt" : "battery.50",
                    color: flow >= 0 ? PanelMetricColor.green(for: colorScheme) : .secondary,
                    label: l10n.s.powerBattery,
                    value: MetricFormat.watts(abs(flow)),
                    caption: flow >= 0 ? l10n.s.powerCharging : l10n.s.powerOnBattery,
                    visible: $pwrBattery, editing: editing)
            } else if editing && !pwrBattery {
                PanelHiddenItemRow(title: l10n.s.powerBattery,
                                   systemImage: "battery.100.bolt",
                                   isVisible: $pwrBattery)
            }
            case .health:
            if pwrHealth, let health = power.healthPercent {
                row(icon: "heart.fill", color: PanelMetricColor.pink(for: colorScheme),
                    label: l10n.s.powerHealth,
                    value: "\(Int(health.rounded()))%",
                    caption: power.cycleCount.map { "\($0) \(l10n.s.powerCycles)" },
                    visible: $pwrHealth, editing: editing)
            } else if editing && !pwrHealth {
                PanelHiddenItemRow(title: l10n.s.powerHealth,
                                   systemImage: "heart.fill",
                                   isVisible: $pwrHealth)
            }
            }
        } else {
            if block == orderedBlocks.first {
                Text(l10n.s.powerUnavailable)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            } else if editing {
                hiddenRow(for: block)
            }
        }
    }

    @ViewBuilder
    private func hiddenRow(for block: Block) -> some View {
        switch block {
        case .system:
            PanelHiddenItemRow(title: l10n.s.powerSystem,
                               systemImage: "bolt.fill",
                               isVisible: $pwrSystem)
        case .adapter:
            PanelHiddenItemRow(title: l10n.s.powerAdapter,
                               systemImage: "powerplug.fill",
                               isVisible: $pwrAdapter)
        case .battery:
            PanelHiddenItemRow(title: l10n.s.powerBattery,
                               systemImage: "battery.100.bolt",
                               isVisible: $pwrBattery)
        case .health:
            PanelHiddenItemRow(title: l10n.s.powerHealth,
                               systemImage: "heart.fill",
                               isVisible: $pwrHealth)
        }
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelPowerOrder)
        powerOrderRaw = ""
        pwrSystem = true
        pwrAdapter = true
        pwrBattery = true
        pwrHealth = true
    }

    private func adapterCaption(_ power: PowerReading) -> String {
        if let rated = power.adapterMaxWatts {
            return String(format: l10n.s.powerAdapterMaxFormat, MetricFormat.watts(rated))
        }
        return l10n.s.powerPluggedIn
    }

    private func row(icon: String, color: Color, label: String, value: String, caption: String? = nil,
                     visible: Binding<Bool>, editing: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let caption {
                    Text(caption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if editing {
                PanelInlineHideButton(isVisible: visible)
            }
        }
    }
}
