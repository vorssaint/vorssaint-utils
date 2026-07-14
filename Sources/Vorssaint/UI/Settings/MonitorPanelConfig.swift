// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Reusable panel configuration: one expandable block per panel section, each
/// with a master "show in panel" toggle plus per-item toggles. Shared by
/// Settings → Monitor and the onboarding panel step so the two stay identical.
/// Designed to live inside a `Form` (grouped style) in both places.
struct MonitorPanelConfig: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var expandedBlocks = Set<PanelConfigBlock>()

    @AppStorage(DefaultsKey.monitorShowSystem) private var showSystem = true
    @AppStorage(DefaultsKey.monitorSysTemps) private var sysTemps = true
    @AppStorage(DefaultsKey.monitorSysCPU) private var sysCPU = true
    @AppStorage(DefaultsKey.monitorSysGPU) private var sysGPU = true
    @AppStorage(DefaultsKey.monitorSysBattery) private var sysBattery = true
    @AppStorage(DefaultsKey.monitorSysMemory) private var sysMemory = true
    @AppStorage(DefaultsKey.monitorSysUptime) private var sysUptime = true

    @AppStorage(DefaultsKey.monitorShowNetwork) private var showNetwork = true
    @AppStorage(DefaultsKey.monitorNetSpeed) private var netSpeed = true
    @AppStorage(DefaultsKey.monitorNetApps) private var netApps = true
    @AppStorage(DefaultsKey.monitorNetTotals) private var netTotals = true
    @AppStorage(DefaultsKey.monitorNetTest) private var netTest = true

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
        if PanelSectionID.system.isAvailable {
            block(.system, title: l10n.s.systemSection, master: $showSystem) {
                if AppFeature.monitorCPU.isAvailable || AppFeature.monitorGPU.isAvailable
                    || AppFeature.monitorPower.isAvailable {
                    Toggle(l10n.s.temperatures, isOn: $sysTemps)
                }
                if AppFeature.monitorCPU.isAvailable {
                    Toggle(l10n.s.cpuLabel, isOn: $sysCPU)
                }
                if AppFeature.monitorGPU.isAvailable {
                    Toggle(l10n.s.gpuLabel, isOn: $sysGPU)
                }
                if AppFeature.monitorPower.isAvailable {
                    Toggle(l10n.s.batteryLabel, isOn: $sysBattery)
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
                Toggle(l10n.s.powerBattery, isOn: $pwrBattery)
                Toggle(FeatureStrings.batteryTime(l10n.language).title, isOn: $pwrTimeRemaining)
                Toggle(l10n.s.powerHealth, isOn: $pwrHealth)
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
        DisclosureGroup(isExpanded: expansionBinding(for: id)) {
            Toggle(l10n.s.monitorShowInPanel, isOn: master)
            items()
                .disabled(!master.wrappedValue)
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                toggle(id)
            }
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

    private func toggle(_ id: PanelConfigBlock) {
        if expandedBlocks.contains(id) {
            expandedBlocks.remove(id)
        } else {
            expandedBlocks.insert(id)
        }
    }
}

private enum PanelConfigBlock: Hashable {
    case system, network, disk, power
}
