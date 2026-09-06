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
    @AppStorage(DefaultsKey.monitorSysBattery) private var showCharge = true
    @AppStorage(DefaultsKey.monitorPwrTemperature) private var showTemperature = true
    @AppStorage(DefaultsKey.menuBarPeripheralBattery) private var showPeripherals = false
    @AppStorage(DefaultsKey.monitorGraphBattery) private var graphBattery = true
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.monitorPwrSystem) private var pwrSystem = true
    @AppStorage(DefaultsKey.monitorPwrAdapter) private var pwrAdapter = true
    @AppStorage(DefaultsKey.monitorPwrBattery) private var pwrBattery = true
    @AppStorage(DefaultsKey.monitorPwrTimeRemaining) private var pwrTimeRemaining = true
    @AppStorage(DefaultsKey.monitorPwrHealth) private var pwrHealth = true
    @AppStorage(DefaultsKey.panelPowerOrder) private var powerOrderRaw = ""
    @State private var draggingBlock: Block?

    var body: some View {
        PanelSection(.power, title: l10n.s.powerSection, collapsible: collapsible,
                     supportsEditing: true,
                     resetAction: resetPanelDefaults) { editing in
            VStack(alignment: .leading, spacing: 10) {
                if blocks(editing: editing).isEmpty {
                    Text(l10n.s.powerUnavailable)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
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

    private enum Block: String, PanelOrderItem { case charge, temperature, system, adapter, battery, remaining, health, peripherals }

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
        let available = orderedBlocks.filter(isAvailable)
        return available.filter { isVisible($0) || (editing && !isEnabled($0)) }
    }

    private func isAvailable(_ block: Block) -> Bool {
        switch block {
        case .system, .adapter: return true
        case .peripherals: return showPeripherals && !monitor.snapshot.peripheralBatteries.isEmpty
        case .charge, .temperature, .battery, .remaining, .health: return PowerSampler.hasInternalBattery
        }
    }

    private func isEnabled(_ block: Block) -> Bool {
        switch block {
        case .charge: return showCharge
        case .temperature: return showTemperature
        case .system: return pwrSystem
        case .adapter: return pwrAdapter
        case .battery: return pwrBattery
        case .remaining: return pwrTimeRemaining
        case .health: return pwrHealth
        case .peripherals: return showPeripherals
        }
    }

    private func isVisible(_ block: Block) -> Bool {
        switch block {
        case .charge: return showCharge && monitor.snapshot.power?.chargePercent != nil
        case .temperature: return showTemperature && monitor.snapshot.batteryTemperature != nil
        case .peripherals: return showPeripherals && !monitor.snapshot.peripheralBatteries.isEmpty
        default: break
        }
        guard let power = monitor.snapshot.power, !power.isEmpty else { return false }
        switch block {
        case .charge, .temperature, .peripherals: return false
        case .system: return pwrSystem && power.systemWatts != nil
        case .adapter: return pwrAdapter && power.externalConnected && power.adapterWatts != nil
        case .battery: return pwrBattery && power.hasBattery && power.batteryWatts != nil
        case .remaining:
            return pwrTimeRemaining && power.hasBattery
                && !power.externalConnected && !power.isCharging
        case .health: return pwrHealth && power.healthPercent != nil
        }
    }

    @ViewBuilder
    private func blockContent(_ block: Block, editing: Bool) -> some View {
        let power = monitor.snapshot.power
        switch block {
        case .charge:
            if showCharge {
                batteryUsageRow(editing: editing)
            } else if editing {
                PanelHiddenItemRow(title: l10n.s.batteryCharge, systemImage: "battery.100", isVisible: $showCharge)
            }
        case .temperature:
            if showTemperature, let value = monitor.snapshot.batteryTemperature {
                row(icon: "thermometer.medium", color: .secondary,
                    label: l10n.s.monitorShowBatteryTemperature,
                    value: MetricFormat.temperature(value, unit: TemperatureUnit(rawValue: temperatureUnit) ?? .celsius),
                    visible: $showTemperature, editing: editing)
            } else if editing && !showTemperature {
                PanelHiddenItemRow(title: l10n.s.monitorShowBatteryTemperature,
                                   systemImage: "thermometer.medium", isVisible: $showTemperature)
            }
        case .peripherals:
            peripheralBatteryRows
        case .system:
            if pwrSystem, let watts = power?.systemWatts {
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
            if pwrAdapter, let power, power.externalConnected, let adapter = power.adapterWatts {
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
            if pwrBattery, power?.hasBattery == true, let flow = power?.batteryWatts {
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
            if pwrHealth, let power, let health = power.healthPercent {
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
        case .remaining:
            if pwrTimeRemaining, let power, power.hasBattery,
               !power.externalConnected, !power.isCharging {
                let strings = FeatureStrings.batteryTime(l10n.language)
                let value = power.timeRemainingSeconds.flatMap(BatteryTimeSupport.formatted)
                row(icon: "clock", color: PanelMetricColor.green(for: colorScheme),
                    label: strings.title,
                    value: value ?? "...",
                    caption: value == nil ? strings.calculating : strings.systemEstimate,
                    visible: $pwrTimeRemaining, editing: editing)
            } else if editing && !pwrTimeRemaining {
                PanelHiddenItemRow(title: FeatureStrings.batteryTime(l10n.language).title,
                                   systemImage: "clock",
                                   isVisible: $pwrTimeRemaining)
            }
        }
    }

    private func subsectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
    }

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
                        PanelInlineHideButton(isVisible: $showCharge)
                    }
                }
                if graphBattery, monitor.snapshot.batteryHistory.count >= 2 {
                    Sparkline(values: monitor.snapshot.batteryHistory,
                              color: PanelMetricColor.green(for: colorScheme),
                              maxValue: 1,
                              showsZeroBaseline: true)
                        .frame(height: 22)
                }
                EnergyAppsBreakdown()
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

    private func chargeTint(_ charge: Int) -> Color {
        if charge < 20 { return PanelMetricColor.red(for: colorScheme) }
        if charge < 40 { return PanelMetricColor.yellow(for: colorScheme) }
        return PanelMetricColor.green(for: colorScheme)
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelPowerOrder)
        powerOrderRaw = ""
        showCharge = true
        showTemperature = true
        pwrSystem = true
        pwrAdapter = true
        pwrBattery = true
        pwrTimeRemaining = true
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
                    .foregroundStyle(Color.primary.opacity(0.74))
                if let caption {
                    Text(caption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 44, alignment: .trailing)
            if editing {
                PanelInlineHideButton(isVisible: visible)
            }
        }
    }
}

private struct EnergyAppsBreakdown: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @AppStorage(DefaultsKey.monitorInterval) private var monitorInterval = 2
    @State private var expanded = false
    @State private var rows: [ProcessUsage] = []
    @State private var loading = false
    @State private var lastRefresh = Date.distantPast
    @State private var requestID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expanded.toggle()
                requestID = UUID()
                if expanded {
                    rows = ProcessUsageService.shared.cachedTop(.energy, limit: 15) ?? []
                    refresh()
                } else {
                    rows = []
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(l10n.s.energyAppsTitle)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                if rows.isEmpty {
                    Text(loading ? l10n.s.breakdownMeasuring : l10n.s.energyAppsIdle)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(rows) { row in
                        ProcessUsageRow(row: row,
                                        value: String(format: "%.1f%%", locale: MetricFormat.locale, row.value),
                                        iconSize: 14, leadingPadding: 16)
                    }
                }
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .onReceive(monitor.$snapshot) { _ in
            guard expanded, !loading,
                  Date().timeIntervalSince(lastRefresh) >= Double(Defaults.sanitizedMonitorInterval(monitorInterval))
            else { return }
            refresh()
        }
        .onDisappear {
            expanded = false
            requestID = UUID()
            rows = []
            loading = false
        }
    }

    private func refresh() {
        lastRefresh = Date()
        loading = true
        let currentRequest = requestID
        let interval = Double(Defaults.sanitizedMonitorInterval(monitorInterval))
        DispatchQueue.global(qos: .utility).async {
            let result = ProcessUsageService.shared.top(.energy, limit: 15, sampleInterval: interval)
            DispatchQueue.main.async {
                guard expanded, requestID == currentRequest else { return }
                loading = false
                if !result.isEmpty || rows.isEmpty { rows = result }
            }
        }
    }
}
