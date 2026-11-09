// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import WidgetKit

@main
struct VorssaintWidgetBundle: WidgetBundle {
    var body: some Widget {
        VorssaintCPUWidget()
        VorssaintGPUWidget()
        VorssaintRAMWidget()
        VorssaintDiskWidget()
        VorssaintNetworkWidget()
        VorssaintUnitedWidget()
    }
}

struct VorssaintCPUWidget: Widget {
    var body: some WidgetConfiguration {
        VorssaintWidgetConfiguration(kind: .cpu)
    }
}

struct VorssaintGPUWidget: Widget {
    var body: some WidgetConfiguration {
        VorssaintWidgetConfiguration(kind: .gpu)
    }
}

struct VorssaintRAMWidget: Widget {
    var body: some WidgetConfiguration {
        VorssaintWidgetConfiguration(kind: .memory)
    }
}

struct VorssaintDiskWidget: Widget {
    var body: some WidgetConfiguration {
        VorssaintWidgetConfiguration(kind: .disk)
    }
}

struct VorssaintNetworkWidget: Widget {
    var body: some WidgetConfiguration {
        VorssaintWidgetConfiguration(kind: .network)
    }
}

struct VorssaintUnitedWidget: Widget {
    var body: some WidgetConfiguration {
        VorssaintWidgetConfiguration(kind: .united)
    }
}

private struct VorssaintWidgetConfiguration: WidgetConfiguration {
    let kind: VorssaintWidgetKind

    private var strings: Strings {
        Strings.localized(WidgetSharedData.language())
    }

    private var displayName: String {
        switch kind {
        case .cpu: return strings.widgetCPU
        case .gpu: return strings.widgetGPU
        case .memory: return strings.widgetRAM
        case .disk: return strings.widgetDisk
        case .network: return strings.widgetNetwork
        case .united: return strings.widgetUnited
        }
    }

    private var description: String {
        switch kind {
        case .cpu: return strings.widgetCPUDescription
        case .gpu: return strings.widgetGPUDescription
        case .memory: return strings.widgetRAMDescription
        case .disk: return strings.widgetDiskDescription
        case .network: return strings.widgetNetworkDescription
        case .united: return strings.widgetUnitedDescription
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind.rawValue, provider: VorssaintProvider(kind: kind)) { entry in
            VorssaintWidgetView(kind: kind, entry: entry)
        }
        .configurationDisplayName(displayName)
        .description(description)
        .supportedFamilies([.systemSmall])
    }
}
