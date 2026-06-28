// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A faithful, live miniature of the menu bar corner. It uses the same compact
/// lines the real status item renders, so choices in Settings have an immediate
/// visual cost before they occupy the actual menu bar.
struct MenuBarMetricsPreview: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @AppStorage(DefaultsKey.menuBarCPU) private var cpu = false
    @AppStorage(DefaultsKey.menuBarGPU) private var gpu = false
    @AppStorage(DefaultsKey.menuBarMemory) private var memory = false
    @AppStorage(DefaultsKey.menuBarCPUTemperature) private var cpuTemperature = false
    @AppStorage(DefaultsKey.menuBarGPUTemperature) private var gpuTemperature = false
    @AppStorage(DefaultsKey.menuBarBatteryTemperature) private var batteryTemperature = false
    @AppStorage(DefaultsKey.menuBarNetwork) private var network = false
    @AppStorage(DefaultsKey.menuBarDiskUsage) private var diskUsage = false
    @AppStorage(DefaultsKey.menuBarDiskActivity) private var diskActivity = false
    @AppStorage(DefaultsKey.menuBarBattery) private var battery = false
    @AppStorage(DefaultsKey.menuBarPower) private var power = false
    @AppStorage(DefaultsKey.menuBarMetricOrder) private var metricOrder = ""
    @AppStorage(DefaultsKey.menuBarCombineTemperatures) private var combineTemperatures = true
    @AppStorage(DefaultsKey.menuBarLabelStyle) private var labelStyle = "compact"
    @AppStorage(DefaultsKey.menuBarMemoryStyle) private var memoryStyle = "percent"
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue

    var body: some View {
        let _ = metricOrder
        let _ = combineTemperatures
        let _ = labelStyle
        let _ = memoryStyle
        let _ = temperatureUnit
        let lines = MenuBarRenderer.lines(for: monitor.snapshot, metrics: activeMetrics)
        let stacked = lines.count > 1

        HStack(spacing: 12) {
            Spacer()
            Image(systemName: "wifi")
                .foregroundStyle(.white.opacity(0.5))
            Image(systemName: "battery.75")
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 5) {
                glyph
                    .frame(width: 20, height: 14)
                if !lines.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            HStack(spacing: 0) {
                                ForEach(Array(line.enumerated()), id: \.offset) { _, segment in
                                    segmentView(segment, stacked: stacked)
                                }
                            }
                            .frame(height: MenuBarRenderer.statusLineHeight(stacked: stacked))
                        }
                    }
                }
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
    }

    private var activeMetrics: [MenuBarMetric] {
        let _ = cpu
        let _ = gpu
        let _ = memory
        let _ = cpuTemperature
        let _ = gpuTemperature
        let _ = batteryTemperature
        let _ = network
        let _ = diskUsage
        let _ = diskActivity
        let _ = battery
        let _ = power
        return MenuBarMetric.enabled(in: .standard)
    }

    @ViewBuilder
    private func segmentView(_ segment: MenuBarSegment, stacked: Bool) -> some View {
        switch segment {
        case let .text(string):
            Text(string)
                .font(.system(size: MenuBarRenderer.statusFontSize(stacked: stacked),
                              weight: stacked ? .semibold : .medium,
                              design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: stacked ? 8.8 : 10.8, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: stacked ? 9.2 : 11.4, height: stacked ? 9.2 : 11.4)
        case let .largeSymbol(name):
            Image(systemName: name)
                .font(.system(size: 13.6, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 14.2, height: 14.2)
        case let .metricBlock(label, value, minimumValue, style, pressure):
            metricBlock(label: label,
                        value: value,
                        minimumValue: minimumValue,
                        style: style,
                        pressure: pressure)
        case let .networkBlock(down, up, style):
            VStack(alignment: .leading, spacing: -0.6) {
                Text("↓\(down)")
                Text("↑\(up)")
            }
            .font(.system(size: MenuBarRenderer.networkBlockFontSize(style: style),
                          weight: .semibold,
                          design: .monospaced))
            .foregroundStyle(.white)
            .frame(minWidth: style == .readable ? 39 : 36,
                   minHeight: style == .readable ? 22 : 20,
                   alignment: .center)
            .fixedSize(horizontal: true, vertical: true)
        case let .diskActivityBlock(read, write, style):
            VStack(alignment: .leading, spacing: -0.6) {
                Text("R\(read)")
                Text("W\(write)")
            }
            .font(.system(size: MenuBarRenderer.networkBlockFontSize(style: style),
                          weight: .semibold,
                          design: .monospaced))
            .foregroundStyle(.white)
            .frame(minWidth: style == .readable ? 39 : 36,
                   minHeight: style == .readable ? 22 : 20,
                   alignment: .center)
            .fixedSize(horizontal: true, vertical: true)
        case let .batteryBlock(percent, isCharging, style):
            HStack(spacing: style == .readable ? 5 : 4) {
                Image(systemName: MenuBarRenderer.batterySymbol(for: percent, isCharging: isCharging))
                    .font(.system(size: style == .readable ? 17 : 15.5, weight: .regular))
                Text("\(max(0, min(100, percent)))%")
                    .font(.system(size: style == .readable ? 13 : 12,
                                  weight: .semibold,
                                  design: .monospaced))
                    .frame(minWidth: style == .readable ? 33 : 30, alignment: .leading)
            }
            .foregroundStyle(.white)
            .fixedSize(horizontal: true, vertical: true)
        case let .dot(pressure):
            Circle()
                .fill(dotColor(pressure))
                .frame(width: stacked ? 5.5 : 7.5, height: stacked ? 5.5 : 7.5)
        case .separator:
            Text("│")
                .font(.system(size: MenuBarRenderer.statusFontSize(stacked: stacked),
                              weight: .medium,
                              design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.horizontal, 5)
        }
    }

    private func metricBlock(label: String,
                             value: String,
                             minimumValue: String,
                             style: MenuBarBlockStyle,
                             pressure: MemoryPressure?) -> some View {
        VStack(spacing: -1) {
            Text(label)
                .font(.system(size: style == .readable ? 7.2 : 6.6, weight: .medium))
            HStack(spacing: pressure == nil ? 0 : 4) {
                if let pressure {
                    Circle()
                        .fill(dotColor(pressure))
                        .frame(width: style == .readable ? 5.2 : 4.8,
                               height: style == .readable ? 5.2 : 4.8)
                }
                Text(value)
                    .font(.system(size: style == .readable ? 13 : 12,
                                  weight: .semibold,
                                  design: .monospaced))
                    .frame(minWidth: metricValueMinWidth(minimumValue: minimumValue, style: style),
                           alignment: .center)
            }
        }
        .foregroundStyle(.white)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func metricValueMinWidth(minimumValue: String, style: MenuBarBlockStyle) -> CGFloat {
        switch minimumValue {
        case "100% 999°":
            return style == .readable ? 62 : 56
        case "100%", "999°":
            return style == .readable ? 33 : 30
        case "99W":
            return style == .readable ? 28 : 25
        default:
            return 0
        }
    }

    private func dotColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .gray
        }
    }

    private var glyph: some View {
        Group {
            if let image = BlackHoleGlyph.image(active: true) {
                Image(nsImage: image).renderingMode(.template)
            } else {
                Image(systemName: "circle.fill")
            }
        }
        .foregroundStyle(.white)
    }
}
