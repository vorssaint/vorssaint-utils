// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Reusable panel configuration: one block per panel section, each with a
/// master "show in panel" toggle plus per-item toggles. The onboarding panel
/// step draws it as expandable rows inside a grouped `Form`; Settings → Monitor
/// draws the same choices as tiles, one per block, with the chosen block's
/// items as tiles under it. Both write the same keys.
struct MonitorPanelConfig: View {
    var tiles = false
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var expandedBlocks = Set<PanelConfigBlock>()
    @State private var selectedBlock: PanelConfigBlock?

    @AppStorage(DefaultsKey.monitorShowSystem) private var showSystem = true
    @AppStorage(DefaultsKey.monitorSysTemps) private var sysTemps = true
    @AppStorage(DefaultsKey.monitorSysCPU) private var sysCPU = true
    @AppStorage(DefaultsKey.monitorSysGPU) private var sysGPU = true
    @AppStorage(DefaultsKey.monitorPwrTemperature) private var pwrTemperature = true
    @AppStorage(DefaultsKey.monitorSysBattery) private var sysBattery = true
    @AppStorage(DefaultsKey.monitorSysMemory) private var sysMemory = true
    @AppStorage(DefaultsKey.monitorSysUptime) private var sysUptime = true

    @AppStorage(DefaultsKey.monitorShowNetwork) private var showNetwork = true
    @AppStorage(DefaultsKey.monitorNetSpeed) private var netSpeed = true
    @AppStorage(DefaultsKey.monitorNetApps) private var netApps = true
    @AppStorage(DefaultsKey.monitorNetTotals) private var netTotals = true
    @AppStorage(DefaultsKey.monitorNetTest) private var netTest = true
    @AppStorage(DefaultsKey.monitorNetAddresses) private var netAddresses = true

    @AppStorage(DefaultsKey.monitorShowDisk) private var showDisk = true
    @AppStorage(DefaultsKey.monitorDiskUsage) private var diskUsage = true
    @AppStorage(DefaultsKey.monitorDiskActivity) private var diskActivity = true
    @AppStorage(DefaultsKey.monitorDiskSMART) private var diskSMART = true
    @AppStorage(DefaultsKey.monitorDiskProtection) private var diskProtection = true
    @AppStorage(DefaultsKey.monitorDiskTools) private var diskTools = true

    @AppStorage(DefaultsKey.monitorShowPower) private var showPower = true
    @AppStorage(DefaultsKey.monitorPwrSystem) private var pwrSystem = true
    @AppStorage(DefaultsKey.monitorPwrAdapter) private var pwrAdapter = true
    @AppStorage(DefaultsKey.monitorPwrBattery) private var pwrBattery = true
    @AppStorage(DefaultsKey.monitorPwrTimeRemaining) private var pwrTimeRemaining = true
    @AppStorage(DefaultsKey.monitorPwrHealth) private var pwrHealth = true

    @AppStorage(DefaultsKey.monitorShowMixer) private var showMixer = true

    var body: some View {
        if tiles {
            tileLayout
        } else {
            rowLayout
        }
    }

    // MARK: - Tiles

    private var availableBlocks: [PanelConfigBlock] {
        PanelConfigBlock.allCases.filter { $0.section.isAvailable }
    }

    private var currentBlock: PanelConfigBlock? {
        let blocks = availableBlocks
        if let selectedBlock, blocks.contains(selectedBlock) { return selectedBlock }
        return blocks.first
    }

    private var tileLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                ForEach(availableBlocks, id: \.self) { block in
                    NotchEditorItem(symbol: block.section.symbolName,
                                    title: block.section.title(l10n.s),
                                    included: master(block),
                                    selected: currentBlock == block) {
                        selectedBlock = block
                    }
                }
            }
            if let block = currentBlock, block != .mixer {
                VStack(alignment: .leading, spacing: 10) {
                    Text(block.section.title(l10n.s))
                        .font(.subheadline.weight(.medium))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
                        itemTiles(for: block)
                    }
                }
            }
        }
    }

    private func master(_ block: PanelConfigBlock) -> Binding<Bool> {
        switch block {
        case .system: return $showSystem
        case .network: return $showNetwork
        case .disk: return $showDisk
        case .power: return $showPower
        case .mixer: return $showMixer
        }
    }

    /// The block's items as tiles, greyed while the whole block is hidden.
    @ViewBuilder
    private func itemTiles(for block: PanelConfigBlock) -> some View {
        let available = master(block).wrappedValue
        switch block {
        case .system:
            if AppFeature.monitorCPU.isAvailable || AppFeature.monitorGPU.isAvailable {
                itemTile(l10n.s.temperatures, symbol: "thermometer.medium", value: $sysTemps, available: available)
            }
            if AppFeature.monitorCPU.isAvailable {
                itemTile(l10n.s.cpuLabel, symbol: MenuBarMetric.cpu.symbolName, value: $sysCPU, available: available)
            }
            if AppFeature.monitorGPU.isAvailable {
                itemTile(l10n.s.gpuLabel, symbol: MenuBarMetric.gpu.symbolName, value: $sysGPU, available: available)
            }
            if AppFeature.monitorMemory.isAvailable {
                itemTile(l10n.s.memorySection, symbol: MenuBarMetric.memory.symbolName, value: $sysMemory, available: available)
            }
            itemTile(l10n.s.monitorItemUptime, symbol: "clock", value: $sysUptime, available: available)
        case .network:
            itemTile(l10n.s.monitorItemNetSpeed, symbol: "speedometer", value: $netSpeed, available: available)
            itemTile(l10n.s.networkApps, symbol: "app.badge", value: $netApps, available: available)
            itemTile(l10n.s.monitorItemNetTotals, symbol: "sum", value: $netTotals, available: available)
            itemTile(l10n.s.networkIPAddresses, symbol: "network", value: $netAddresses, available: available)
            itemTile(l10n.s.monitorItemNetTest, symbol: "gauge.with.needle", value: $netTest, available: available)
        case .disk:
            itemTile(l10n.s.monitorItemDiskUsage, symbol: "internaldrive", value: $diskUsage, available: available)
            itemTile(l10n.s.monitorItemDiskActivity, symbol: "arrow.up.arrow.down", value: $diskActivity, available: available)
            itemTile(l10n.s.monitorItemDiskSMART, symbol: "heart.text.square", value: $diskSMART, available: available)
            itemTile(l10n.s.monitorItemDiskProtection, symbol: "shield", value: $diskProtection, available: available)
            itemTile(l10n.s.monitorItemDiskTools, symbol: "wrench.and.screwdriver", value: $diskTools, available: available)
        case .power:
            itemTile(l10n.s.powerSystem, symbol: "bolt", value: $pwrSystem, available: available)
            itemTile(l10n.s.powerAdapter, symbol: "powerplug", value: $pwrAdapter, available: available)
            if PowerSampler.hasInternalBattery {
                itemTile(l10n.s.batteryCharge, symbol: "battery.75percent", value: $sysBattery, available: available)
                itemTile(l10n.s.powerBattery, symbol: "battery.100percent.bolt", value: $pwrBattery, available: available)
                itemTile(FeatureStrings.batteryTime(l10n.language).title, symbol: "clock", value: $pwrTimeRemaining,
                         available: available)
                itemTile(l10n.s.monitorShowBatteryTemperature, symbol: "thermometer.medium", value: $pwrTemperature,
                         available: available)
                itemTile(l10n.s.powerHealth, symbol: "heart", value: $pwrHealth, available: available)
            }
        case .mixer:
            EmptyView()
        }
    }

    private func itemTile(_ title: String, symbol: String, value: Binding<Bool>, available: Bool) -> some View {
        NotchEditorItem(symbol: symbol, title: title, included: value, available: available) {
            value.wrappedValue.toggle()
        }
        .disabled(!available)
    }

    // MARK: - Rows

    @ViewBuilder
    private var rowLayout: some View {
        if PanelSectionID.system.isAvailable {
            block(.system, title: l10n.s.systemSection, master: $showSystem) {
                if AppFeature.monitorCPU.isAvailable || AppFeature.monitorGPU.isAvailable {
                    Toggle(l10n.s.temperatures, isOn: $sysTemps)
                }
                if AppFeature.monitorCPU.isAvailable {
                    Toggle(l10n.s.cpuLabel, isOn: $sysCPU)
                }
                if AppFeature.monitorGPU.isAvailable {
                    Toggle(l10n.s.gpuLabel, isOn: $sysGPU)
                }
                if AppFeature.monitorMemory.isAvailable {
                    Toggle(l10n.s.memorySection, isOn: $sysMemory)
                }
                Toggle(l10n.s.monitorItemUptime, isOn: $sysUptime)
            }
        }
        if AppFeature.monitorNetwork.isAvailable {
            block(.network, title: l10n.s.networkSection, master: $showNetwork) {
                Toggle(l10n.s.monitorItemNetSpeed, isOn: $netSpeed)
                Toggle(l10n.s.networkApps, isOn: $netApps)
                Toggle(l10n.s.monitorItemNetTotals, isOn: $netTotals)
                Toggle(l10n.s.networkIPAddresses, isOn: $netAddresses)
                Toggle(l10n.s.monitorItemNetTest, isOn: $netTest)
            }
        }
        if AppFeature.monitorDisk.isAvailable {
            block(.disk, title: l10n.s.diskSection, master: $showDisk) {
                Toggle(l10n.s.monitorItemDiskUsage, isOn: $diskUsage)
                Toggle(l10n.s.monitorItemDiskActivity, isOn: $diskActivity)
                Toggle(l10n.s.monitorItemDiskSMART, isOn: $diskSMART)
                Toggle(l10n.s.monitorItemDiskProtection, isOn: $diskProtection)
                Toggle(l10n.s.monitorItemDiskTools, isOn: $diskTools)
            }
        }
        if AppFeature.monitorPower.isAvailable {
            block(.power, title: l10n.s.powerSection, master: $showPower) {
                Toggle(l10n.s.powerSystem, isOn: $pwrSystem)
                Toggle(l10n.s.powerAdapter, isOn: $pwrAdapter)
                if PowerSampler.hasInternalBattery {
                    Toggle(l10n.s.batteryCharge, isOn: $sysBattery)
                    Toggle(l10n.s.powerBattery, isOn: $pwrBattery)
                    Toggle(FeatureStrings.batteryTime(l10n.language).title, isOn: $pwrTimeRemaining)
                    DisclosureGroup(FeatureStrings.mouseClickDebounce(l10n.language).moreOptions) {
                        Toggle(l10n.s.monitorShowBatteryTemperature, isOn: $pwrTemperature)
                        Toggle(l10n.s.powerHealth, isOn: $pwrHealth)
                    }
                }
            }
        }
        // The mixer is a per-app list, so it has no sub-items — just show/hide.
        if AppFeature.mixer.isAvailable {
            Toggle(l10n.s.mixerSection, isOn: $showMixer)
        }
    }

    /// One expandable section: a master "show in panel" toggle, then the per-item
    /// toggles (disabled while the whole block is hidden).
    @ViewBuilder
    private func block<Content: View>(_ id: PanelConfigBlock,
                                      title: String,
                                      master: Binding<Bool>,
                                      @ViewBuilder _ items: @escaping () -> Content) -> some View {
        DisclosureHeaderRow(isExpanded: expansionBinding(for: id)) {
            Text(title)
            Spacer()
        }
        if expandedBlocks.contains(id) {
            Group {
                Toggle(l10n.s.monitorShowInPanel, isOn: master)
                items()
                    .disabled(!master.wrappedValue)
            }
            .disclosureIndent()
        }
    }

    private func expansionBinding(for id: PanelConfigBlock) -> Binding<Bool> {
        Binding(
            get: { expandedBlocks.contains(id) },
            set: { expanded in
                if expanded {
                    expandedBlocks.insert(id)
                } else {
                    expandedBlocks.remove(id)
                }
            }
        )
    }

}

private enum PanelConfigBlock: CaseIterable, Hashable {
    case system, network, disk, power, mixer

    var section: PanelSectionID {
        switch self {
        case .system: return .system
        case .network: return .network
        case .disk: return .disk
        case .power: return .power
        case .mixer: return .mixer
        }
    }
}
