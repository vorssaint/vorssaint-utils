// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Ties the readout to the app's feature catalog and monitor, kept apart from
/// its rules so they can be tested without either.
extension NotchSystemReadout {
    /// Each reading follows its Monitor feature, as the System page does.
    static func availableKinds() -> Set<Kind> {
        var kinds = Set<Kind>()
        if AppFeature.monitorPower.isAvailable { kinds.insert(.battery) }
        if AppFeature.monitorCPU.isAvailable { kinds.insert(.cpu) }
        if AppFeature.monitorGPU.isAvailable { kinds.insert(.gpu) }
        if AppFeature.monitorMemory.isAvailable { kinds.insert(.memory) }
        return kinds
    }

    static func monitorNeeds(available: Set<Kind>) -> SystemMonitorPanelNeeds {
        var needs = SystemMonitorPanelNeeds.none
        needs.battery = available.contains(.battery)
        needs.cpu = available.contains(.cpu)
        needs.gpu = available.contains(.gpu)
        needs.memory = available.contains(.memory)
        return needs
    }

    static func input(_ snapshot: SystemSnapshot) -> Input {
        Input(cpu: snapshot.cpuUsage, gpu: snapshot.gpuUsage,
              memoryUsed: snapshot.memoryUsed, memoryTotal: snapshot.memoryTotal,
              batteryPercent: snapshot.power?.chargePercent,
              hasBattery: snapshot.power?.hasBattery ?? false,
              externalPower: snapshot.power?.externalConnected ?? false)
    }
}
