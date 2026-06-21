// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// A live reading the user can pin next to the menu bar icon.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, cpuTemperature, gpuTemperature, batteryTemperature, network, battery, power

    var id: String { rawValue }

    var defaultsKey: String {
        switch self {
        case .cpu: return DefaultsKey.menuBarCPU
        case .gpu: return DefaultsKey.menuBarGPU
        case .memory: return DefaultsKey.menuBarMemory
        case .cpuTemperature: return DefaultsKey.menuBarCPUTemperature
        case .gpuTemperature: return DefaultsKey.menuBarGPUTemperature
        case .batteryTemperature: return DefaultsKey.menuBarBatteryTemperature
        case .network: return DefaultsKey.menuBarNetwork
        case .battery: return DefaultsKey.menuBarBattery
        case .power: return DefaultsKey.menuBarPower
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "rectangle.connected.to.line.below"
        case .memory: return "memorychip"
        case .cpuTemperature: return "cpu"
        case .gpuTemperature: return "rectangle.connected.to.line.below"
        case .batteryTemperature: return "battery.100"
        case .network: return "network"
        case .battery: return "battery.100"
        case .power: return "powerplug.fill"
        }
    }

    static let defaultOrder: [MenuBarMetric] = [
        .cpu, .cpuTemperature,
        .gpu, .gpuTemperature,
        .memory,
        .battery, .batteryTemperature,
        .network, .power,
    ]

    static func order(in defaults: UserDefaults) -> [MenuBarMetric] {
        let raw = defaults.string(forKey: DefaultsKey.menuBarMetricOrder) ?? ""
        return Defaults.sanitizedMenuBarMetricOrder(raw).compactMap(MenuBarMetric.init(rawValue:))
    }

    static func setOrder(_ order: [MenuBarMetric], in defaults: UserDefaults = .standard) {
        let raw = order.map(\.rawValue).joined(separator: ",")
        defaults.set(raw, forKey: DefaultsKey.menuBarMetricOrder)
    }

    static func enabled(in defaults: UserDefaults) -> [MenuBarMetric] {
        order(in: defaults).filter { defaults.bool(forKey: $0.defaultsKey) }
    }

    static func anyEnabled(in defaults: UserDefaults) -> Bool {
        allCases.contains { defaults.bool(forKey: $0.defaultsKey) }
    }
}

enum MenuBarPreset: String, CaseIterable {
    case readable, dense

    static var current: MenuBarPreset {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.menuBarPreset) ?? ""
        let preset = Defaults.sanitizedMenuBarPreset(raw)
        return MenuBarPreset(rawValue: preset) ?? .dense
    }
}

/// How the Memory metric appears in the menu bar: a colored pressure dot, the
/// percentage of RAM in use, or both.
enum MemoryMenuBarStyle: String, CaseIterable {
    case dot, percent, both

    static var current: MemoryMenuBarStyle {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.menuBarMemoryStyle) ?? ""
        let style = Defaults.sanitizedMenuBarMemoryStyle(raw)
        return MemoryMenuBarStyle(rawValue: style) ?? .percent
    }

    var showsDot: Bool { self == .dot || self == .both }
    var showsPercent: Bool { self == .percent || self == .both }
}

enum MenuBarLabelStyle: String, CaseIterable {
    case compact, classic

    static var current: MenuBarLabelStyle {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.menuBarLabelStyle) ?? ""
        let style = Defaults.sanitizedMenuBarLabelStyle(raw)
        return MenuBarLabelStyle(rawValue: style) ?? .compact
    }
}

/// One drawable piece of the menu bar text: plain (adaptive) text, or the memory
/// pressure dot, which carries a green/yellow/red color.
enum MenuBarSegment {
    case text(String)
    case symbol(String)
    case largeSymbol(String)
    case metricBlock(label: String, value: String, minimumValue: String, style: MenuBarBlockStyle, pressure: MemoryPressure?)
    case networkBlock(down: String, up: String, style: MenuBarBlockStyle)
    case batteryBlock(percent: Int, isCharging: Bool, style: MenuBarBlockStyle)
    case dot(MemoryPressure)
    case separator
}

enum MenuBarBlockStyle {
    case readable, dense
}

/// Builds the compact content shown next to the icon.
///
/// Output is a list of segments so two consumers stay in sync: the status item
/// turns them into a colored attributed string, and the onboarding preview into
/// SwiftUI views. Labels are intentionally abbreviated because the menu bar is
/// a scarce space, especially on notched MacBooks.
enum MenuBarRenderer {
    private static let stackedFontSize: CGFloat = 9.4
    private static let singleLineFontSize: CGFloat = 11.6
    private static let statusTextGapColumns = 1
    private static let countdownColumns = 7
    private static let glyphAndButtonChrome: CGFloat = 26
    private static let separatorWidth = 3
    private static let blockImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    private struct MetricItem {
        var metric: MenuBarMetric
        var segments: [MenuBarSegment]
        var width: Int
    }

    static func lines(for snapshot: SystemSnapshot,
                      metrics: [MenuBarMetric],
                      allowStacked: Bool = true) -> [[MenuBarSegment]] {
        let denseSegments = blockSegments(for: snapshot, metrics: metrics, style: .dense)
        return denseSegments.isEmpty ? [] : [denseSegments]
    }

    static func segments(for snapshot: SystemSnapshot,
                         metrics: [MenuBarMetric],
                         allowStacked: Bool = true) -> [MenuBarSegment] {
        var segments: [MenuBarSegment] = []
        for (index, line) in lines(for: snapshot, metrics: metrics, allowStacked: allowStacked).enumerated() {
            if index > 0 { segments.append(.text("\n")) }
            segments.append(contentsOf: line)
        }
        return segments
    }

    static func usesStackedLayout(for snapshot: SystemSnapshot,
                                  metrics: [MenuBarMetric],
                                  allowStacked: Bool = true) -> Bool {
        lines(for: snapshot, metrics: metrics, allowStacked: allowStacked).count > 1
    }

    static func statusFont(stacked: Bool) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: statusFontSize(stacked: stacked),
                                    weight: stacked ? .semibold : .medium)
    }

    static func statusFontSize(stacked: Bool) -> CGFloat {
        stacked ? stackedFontSize : singleLineFontSize
    }

    static func statusLineHeight(stacked: Bool) -> CGFloat {
        stacked ? 10.2 : 14
    }

    static func reservedStatusItemLength(for metrics: [MenuBarMetric],
                                         includesCountdown: Bool,
                                         allowStacked: Bool = true) -> CGFloat {
        let preset = MenuBarPreset.current
        let stacked = !includesCountdown && estimatedUsesStackedLayout(for: metrics,
                                                                       preset: preset,
                                                                       allowStacked: allowStacked)
        let font = statusFont(stacked: stacked)
        let estimated = NSMutableAttributedString()
        if includesCountdown {
            estimated.append(NSAttributedString(string: "888 min  "))
        }
        estimated.append(attributed(for: estimatedSnapshot(),
                                    metrics: metrics,
                                    allowStacked: allowStacked && !includesCountdown,
                                    linePrefix: includesCountdown ? " " : ""))
        guard estimated.length > 0 else { return NSStatusItem.variableLength }

        estimated.addAttribute(.font, value: font, range: NSRange(location: 0, length: estimated.length))
        let rect = estimated.boundingRect(with: NSSize(width: 2000, height: 80),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(glyphAndButtonChrome + rect.width + 8)
    }

    static func reservedContentColumns(for metrics: [MenuBarMetric],
                                       includesCountdown: Bool,
                                       allowStacked: Bool = true) -> Int {
        let columns = reservedColumns(for: metrics,
                                      includesCountdown: includesCountdown,
                                      allowStacked: allowStacked)
        return columns > 0 ? columns + statusTextGapColumns : 0
    }

    private static func metricItems(for snapshot: SystemSnapshot,
                                    metrics: [MenuBarMetric],
                                    preset: MenuBarPreset) -> [MetricItem] {
        var items: [MetricItem] = []
        for metric in metrics {
            switch metric {
            case .cpu:
                if let usage = snapshot.cpuUsage {
                    let text = "CPU " + percent(usage)
                    items.append(MetricItem(metric: metric,
                                            segments: [.symbol(metric.symbolName), .text(" " + text)],
                                            width: reservedWidth(for: metric, preset: preset)))
                }
            case .gpu:
                if let usage = snapshot.gpuUsage {
                    let text = "GPU " + percent(usage)
                    items.append(MetricItem(metric: metric,
                                            segments: [.symbol(metric.symbolName), .text(" " + text)],
                                            width: reservedWidth(for: metric, preset: preset)))
                }
            case .memory:
                guard let used = snapshot.memoryUsed, let total = snapshot.memoryTotal, total > 0 else { break }
                let style = MemoryMenuBarStyle.current
                var segments: [MenuBarSegment] = []
                segments.append(.symbol(metric.symbolName))
                if style.showsDot {
                    segments.append(.text(" "))
                    segments.append(.dot(snapshot.memoryPressure))
                }
                let text = " RAM " + percent(Double(used) / Double(total))
                segments.append(.text(text))
                items.append(MetricItem(metric: metric,
                                        segments: segments,
                                        width: reservedWidth(for: metric, preset: preset)))
            case .cpuTemperature:
                if let temperature = snapshot.cpuTemperature {
                    let text = "CPU " + temperatureCompact(temperature)
                    items.append(MetricItem(metric: metric,
                                            segments: [.symbol(metric.symbolName), .text(" " + text)],
                                            width: reservedWidth(for: metric, preset: preset)))
                }
            case .gpuTemperature:
                if let temperature = snapshot.gpuTemperature {
                    let text = "GPU " + temperatureCompact(temperature)
                    items.append(MetricItem(metric: metric,
                                            segments: [.symbol(metric.symbolName), .text(" " + text)],
                                            width: reservedWidth(for: metric, preset: preset)))
                }
            case .batteryTemperature:
                if let temperature = snapshot.batteryTemperature {
                    let text = "BAT " + temperatureCompact(temperature)
                    items.append(MetricItem(metric: metric,
                                            segments: [.symbol(metric.symbolName), .text(" " + text)],
                                            width: reservedWidth(for: metric, preset: preset)))
                }
            case .network:
                if let down = snapshot.netDownBytesPerSec, let up = snapshot.netUpBytesPerSec {
                    let downText = MetricFormat.bytesPerSecCompact(down)
                    let upText = MetricFormat.bytesPerSecCompact(up)
                    items.append(MetricItem(metric: metric,
                                            segments: [.symbol("arrow.down"), .text(" " + downText),
                                                       .text(" "), .symbol("arrow.up"), .text(" " + upText)],
                                            width: reservedWidth(for: metric, preset: preset)))
                }
            case .battery:
                if let charge = snapshot.power?.chargePercent {
                    let symbol = (snapshot.power?.isCharging ?? false) ? "battery.100.bolt" : metric.symbolName
                    let text = "BAT " + percent(Double(charge) / 100.0)
                    items.append(MetricItem(metric: metric,
                                            segments: [.symbol(symbol), .text(" " + text)],
                                            width: reservedWidth(for: metric, preset: preset)))
                }
            case .power:
                if let watts = snapshot.power?.systemWatts {
                    let text = "PWR " + MetricFormat.wattsCompact(watts)
                    items.append(MetricItem(metric: metric,
                                            segments: [.symbol(metric.symbolName), .text(" " + text)],
                                            width: reservedWidth(for: metric, preset: preset)))
                }
            }
        }
        return items
    }

    private static func blockSegments(for snapshot: SystemSnapshot,
                                      metrics: [MenuBarMetric],
                                      style: MenuBarBlockStyle) -> [MenuBarSegment] {
        var groups: [[MenuBarSegment]] = []
        let combineTemperatures = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarCombineTemperatures)
        let enabled = Set(metrics)
        var renderedCPU = false
        var renderedGPU = false
        var renderedBattery = false

        for metric in metrics {
            switch metric {
            case .cpu, .cpuTemperature:
                if combineTemperatures {
                    guard !renderedCPU else { break }
                    renderedCPU = true
                    let usage = enabled.contains(.cpu) ? snapshot.cpuUsage.map(percent) : nil
                    let temperature = enabled.contains(.cpuTemperature) ? snapshot.cpuTemperature.map(temperatureCompact) : nil
                    if let value = combinedComponentValue(primary: usage, temperature: temperature) {
                        groups.append([.metricBlock(label: combinedComponentLabel("CPU",
                                                                                  hasPrimary: usage != nil,
                                                                                  hasTemperature: temperature != nil),
                                                    value: value,
                                                    minimumValue: minimumCombinedValue(primary: usage != nil,
                                                                                       temperature: temperature != nil),
                                                    style: style,
                                                    pressure: nil)])
                    }
                    break
                }
                guard metric == .cpu else {
                    if let temperature = snapshot.cpuTemperature {
                        groups.append([.metricBlock(label: temperatureLabel("CPU"),
                                                    value: temperatureCompact(temperature),
                                                    minimumValue: "999°",
                                                    style: style,
                                                    pressure: nil)])
                    }
                    break
                }
                if let usage = snapshot.cpuUsage {
                    groups.append([.metricBlock(label: "CPU",
                                                value: percent(usage),
                                                minimumValue: "100%",
                                                style: style,
                                                pressure: nil)])
                }
            case .gpu, .gpuTemperature:
                if combineTemperatures {
                    guard !renderedGPU else { break }
                    renderedGPU = true
                    let usage = enabled.contains(.gpu) ? snapshot.gpuUsage.map(percent) : nil
                    let temperature = enabled.contains(.gpuTemperature) ? snapshot.gpuTemperature.map(temperatureCompact) : nil
                    if let value = combinedComponentValue(primary: usage, temperature: temperature) {
                        groups.append([.metricBlock(label: combinedComponentLabel("GPU",
                                                                                  hasPrimary: usage != nil,
                                                                                  hasTemperature: temperature != nil),
                                                    value: value,
                                                    minimumValue: minimumCombinedValue(primary: usage != nil,
                                                                                       temperature: temperature != nil),
                                                    style: style,
                                                    pressure: nil)])
                    }
                    break
                }
                guard metric == .gpu else {
                    if let temperature = snapshot.gpuTemperature {
                        groups.append([.metricBlock(label: temperatureLabel("GPU"),
                                                    value: temperatureCompact(temperature),
                                                    minimumValue: "999°",
                                                    style: style,
                                                    pressure: nil)])
                    }
                    break
                }
                if let usage = snapshot.gpuUsage {
                    groups.append([.metricBlock(label: "GPU",
                                                value: percent(usage),
                                                minimumValue: "100%",
                                                style: style,
                                                pressure: nil)])
                }
            case .memory:
                guard let used = snapshot.memoryUsed, let total = snapshot.memoryTotal, total > 0 else { break }
                groups.append([.metricBlock(label: "RAM",
                                            value: percent(Double(used) / Double(total)),
                                            minimumValue: "100%",
                                            style: style,
                                            pressure: MemoryMenuBarStyle.current.showsDot ? snapshot.memoryPressure : nil)])
            case .network:
                if let down = snapshot.netDownBytesPerSec, let up = snapshot.netUpBytesPerSec {
                    groups.append([.networkBlock(down: MetricFormat.bytesPerSecCompact(down),
                                                 up: MetricFormat.bytesPerSecCompact(up),
                                                 style: style)])
                }
            case .battery, .batteryTemperature:
                if combineTemperatures {
                    guard !renderedBattery else { break }
                    renderedBattery = true
                    let charge = enabled.contains(.battery)
                        ? snapshot.power?.chargePercent.map { "\(max(0, min(100, $0)))%" }
                        : nil
                    let temperature = enabled.contains(.batteryTemperature)
                        ? snapshot.batteryTemperature.map(temperatureCompact)
                        : nil
                    if charge != nil, temperature != nil,
                       let value = combinedComponentValue(primary: charge, temperature: temperature) {
                        groups.append([.metricBlock(label: "BAT",
                                                    value: value,
                                                    minimumValue: "100% 999°",
                                                    style: style,
                                                    pressure: nil)])
                    } else if let chargePercent = enabled.contains(.battery) ? snapshot.power?.chargePercent : nil {
                        groups.append([.batteryBlock(percent: chargePercent,
                                                     isCharging: snapshot.power?.isCharging ?? false,
                                                     style: style)])
                    } else if let temperature {
                        groups.append([.metricBlock(label: temperatureLabel("BAT"),
                                                    value: temperature,
                                                    minimumValue: "999°",
                                                    style: style,
                                                    pressure: nil)])
                    }
                    break
                }
                guard metric == .battery else {
                    if let temperature = snapshot.batteryTemperature {
                        groups.append([.metricBlock(label: temperatureLabel("BAT"),
                                                    value: temperatureCompact(temperature),
                                                    minimumValue: "999°",
                                                    style: style,
                                                    pressure: nil)])
                    }
                    break
                }
                if let charge = snapshot.power?.chargePercent {
                    groups.append([.batteryBlock(percent: charge,
                                                 isCharging: snapshot.power?.isCharging ?? false,
                                                 style: style)])
                }
            case .power:
                if let watts = snapshot.power?.systemWatts {
                    groups.append([.metricBlock(label: "PWR",
                                                value: MetricFormat.wattsCompact(watts),
                                                minimumValue: "99W",
                                                style: style,
                                                pressure: nil)])
                }
            }
        }
        return blockJoined(groups, style: style)
    }

    private static func estimatedUsesStackedLayout(for metrics: [MenuBarMetric],
                                                   preset: MenuBarPreset,
                                                   allowStacked: Bool) -> Bool {
        false
    }

    private static func reservedColumns(for metrics: [MenuBarMetric],
                                        includesCountdown: Bool,
                                        allowStacked: Bool) -> Int {
        let preset = MenuBarPreset.current
        let items = estimatedMetricItems(for: metrics, preset: preset)
        guard !items.isEmpty else { return includesCountdown ? countdownColumns : 0 }

        if includesCountdown {
            return countdownColumns + 2 + joinedWidth(items, usesSeparators: true)
        }

        return joinedWidth(items, usesSeparators: preset != .dense)
    }

    private static func estimatedMetricItems(for metrics: [MenuBarMetric],
                                             preset: MenuBarPreset) -> [MetricItem] {
        metrics.map {
            MetricItem(metric: $0, segments: [], width: reservedWidth(for: $0, preset: preset))
        }
    }

    private static func reservedWidth(for metric: MenuBarMetric, preset: MenuBarPreset) -> Int {
        switch (preset, metric) {
        case (_, .cpu), (_, .gpu):
            return 11      // symbol + " CPU 100%"
        case (_, .memory):
            return MemoryMenuBarStyle.current.showsDot ? 13 : 11
        case (_, .cpuTemperature), (_, .gpuTemperature), (_, .batteryTemperature):
            return 11      // symbol + " CPU 999°" / " GPU 999°" / " BAT 999°"
        case (_, .network):
            return 15      // down symbol + 1.0G + up symbol + 1.0G
        case (_, .battery), (_, .power):
            return 11      // symbol + " BAT 100%" / " PWR 99W"
        }
    }

    private static func joinedWidth(_ items: [MetricItem], usesSeparators: Bool) -> Int {
        let separatorColumns = usesSeparators ? separatorWidth : 1
        let separators = max(0, items.count - 1) * separatorColumns
        return items.reduce(0) { $0 + $1.width } + separators
    }

    private static func joined(_ items: [MetricItem], usesSeparators: Bool) -> [MenuBarSegment] {
        var segments: [MenuBarSegment] = []
        for item in items {
            if !segments.isEmpty {
                segments.append(usesSeparators ? .separator : .text(" "))
            }
            segments.append(contentsOf: item.segments)
        }
        return segments
    }

    private static func blockJoined(_ groups: [[MenuBarSegment]], style: MenuBarBlockStyle) -> [MenuBarSegment] {
        var segments: [MenuBarSegment] = []
        for group in groups {
            if !segments.isEmpty { segments.append(.text(style == .readable ? "  " : " ")) }
            segments.append(contentsOf: group)
        }
        return segments
    }

    /// The colored attributed string for the status item. Only the memory dot
    /// gets an explicit color; everything else stays adaptive (the caller applies
    /// the font over the whole run, which does not disturb the dot's color).
    static func attributed(for snapshot: SystemSnapshot,
                           metrics: [MenuBarMetric],
                           allowStacked: Bool = true,
                           linePrefix: String = "") -> NSAttributedString {
        let result = NSMutableAttributedString()
        let stacked = usesStackedLayout(for: snapshot, metrics: metrics, allowStacked: allowStacked)
        for segment in segments(for: snapshot, metrics: metrics, allowStacked: allowStacked) {
            switch segment {
            case let .text(string):
                let rendered = string == "\n" && !linePrefix.isEmpty ? "\n" + linePrefix : string
                result.append(NSAttributedString(string: rendered))
            case let .symbol(name):
                result.append(symbolAttachment(named: name, stacked: stacked))
            case let .largeSymbol(name):
                result.append(symbolAttachment(named: name, stacked: stacked, enlarged: true))
            case let .metricBlock(label, value, minimumValue, style, pressure):
                result.append(metricBlockAttachment(label: label,
                                                    value: value,
                                                    minimumValue: minimumValue,
                                                    style: style,
                                                    pressure: pressure))
            case let .networkBlock(down, up, style):
                result.append(networkBlockAttachment(down: down, up: up, style: style))
            case let .batteryBlock(percent, isCharging, style):
                result.append(batteryBlockAttachment(percent: percent,
                                                     isCharging: isCharging,
                                                     style: style))
            case let .dot(pressure):
                result.append(NSAttributedString(string: "●", attributes: [.foregroundColor: nsColor(for: pressure)]))
            case .separator:
                result.append(NSAttributedString(string: " │ ",
                                                 attributes: [.foregroundColor: NSColor.tertiaryLabelColor]))
            }
        }
        return result
    }

    private static func symbolAttachment(named name: String,
                                         stacked: Bool,
                                         enlarged: Bool = false) -> NSAttributedString {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: enlarged ? 13.6 : (stacked ? 8.8 : 10.8),
                                                                 weight: .semibold)) else {
            return NSAttributedString(string: "")
        }
        image.isTemplate = true
        let attachment = NSTextAttachment()
        attachment.image = image
        let side: CGFloat = enlarged ? 14.2 : (stacked ? 9.2 : 11.4)
        attachment.bounds = NSRect(x: 0, y: enlarged ? -3.0 : (stacked ? -1.0 : -1.8), width: side, height: side)
        return NSAttributedString(attachment: attachment)
    }

    private static func metricBlockAttachment(label: String,
                                              value: String,
                                              minimumValue: String,
                                              style: MenuBarBlockStyle,
                                              pressure: MemoryPressure?) -> NSAttributedString {
        let image = metricBlockImage(label: label,
                                     value: value,
                                     minimumValue: minimumValue,
                                     style: style,
                                     pressure: pressure)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -4.4, width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    private static func networkBlockAttachment(down: String, up: String, style: MenuBarBlockStyle) -> NSAttributedString {
        let image = networkBlockImage(down: down, up: up, style: style)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -4.4, width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    private static func batteryBlockAttachment(percent: Int,
                                               isCharging: Bool,
                                               style: MenuBarBlockStyle) -> NSAttributedString {
        let image = batteryBlockImage(percent: percent,
                                      isCharging: isCharging,
                                      style: style)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -4.2, width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    private static func metricBlockImage(label: String,
                                         value: String,
                                         minimumValue: String,
                                         style: MenuBarBlockStyle,
                                         pressure: MemoryPressure?) -> NSImage {
        let pressureKey = pressure.map(String.init(describing:)) ?? "none"
        let cacheKey = "metric|\(label)|\(value)|\(minimumValue)|\(style)|\(pressureKey)" as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return cached }

        let labelFont = NSFont.systemFont(ofSize: style == .readable ? 7.2 : 6.6, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: style == .readable ? 13.0 : 12.0,
                                                         weight: .semibold)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.white]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: NSColor.white]
        let labelSize = (label as NSString).size(withAttributes: labelAttrs)
        let valueSize = (value as NSString).size(withAttributes: valueAttrs)
        let minimumValueSize = (minimumValue as NSString).size(withAttributes: valueAttrs)
        let dotDiameter: CGFloat = pressure == nil ? 0 : (style == .readable ? 5.2 : 4.8)
        let dotGap: CGFloat = pressure == nil ? 0 : 4
        let reservedValueWidth = max(valueSize.width, minimumValueSize.width)
        let reservedGroupWidth = dotDiameter + dotGap + reservedValueWidth
        let drawnGroupWidth = dotDiameter + dotGap + valueSize.width
        let width = ceil(max(labelSize.width, reservedGroupWidth) + (style == .readable ? 2 : 0.5))
        let height: CGFloat = style == .readable ? 22 : 20
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        (label as NSString).draw(at: NSPoint(x: (width - labelSize.width) / 2,
                                 y: style == .readable ? 12.9 : 12.0),
                                 withAttributes: labelAttrs)
        var valueX = (width - drawnGroupWidth) / 2
        if let pressure {
            let dotRect = NSRect(x: valueX,
                                 y: style == .readable ? 4.1 : 3.5,
                                 width: dotDiameter,
                                 height: dotDiameter)
            nsColor(for: pressure).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            valueX += dotDiameter + dotGap
        }
        (value as NSString).draw(at: NSPoint(x: valueX, y: style == .readable ? -0.4 : -0.8),
                                 withAttributes: valueAttrs)
        image.unlockFocus()
        image.isTemplate = true
        blockImageCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func networkBlockImage(down: String, up: String, style: MenuBarBlockStyle) -> NSImage {
        let cacheKey = "network|\(down)|\(up)|\(style)" as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return cached }

        let font = NSFont.monospacedSystemFont(ofSize: style == .readable ? 8.6 : 8.0,
                                               weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let lines = ["↓\(down)", "↑\(up)"]
        let lineHeight: CGFloat = style == .readable ? 9.4 : 8.7
        let reservedLines = lines + ["↓000B", "↑000B"]
        let width = reservedLines.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 22
        let image = NSImage(size: NSSize(width: ceil(width), height: ceil(lineHeight * 2)))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        for (index, line) in lines.enumerated() {
            let y = image.size.height - lineHeight * CGFloat(index + 1) + 0.2
            (line as NSString).draw(at: NSPoint(x: 0, y: y), withAttributes: attrs)
        }
        image.unlockFocus()
        image.isTemplate = true
        blockImageCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static func batteryBlockImage(percent: Int,
                                          isCharging: Bool,
                                          style: MenuBarBlockStyle) -> NSImage {
        let clampedPercent = max(0, min(100, percent))
        let cacheKey = "battery|\(clampedPercent)|\(isCharging)|\(style)" as NSString
        if let cached = blockImageCache.object(forKey: cacheKey) { return cached }

        let symbolName = batterySymbol(for: percent, isCharging: isCharging)
        let symbolPointSize: CGFloat = style == .readable ? 17.0 : 15.5
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: style == .readable ? 13.0 : 12.0,
                                                         weight: .semibold)
        let value = "\(clampedPercent)%"
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: NSColor.white]
        let valueSize = (value as NSString).size(withAttributes: valueAttrs)
        let reservedValueSize = max(valueSize.width, ("100%" as NSString).size(withAttributes: valueAttrs).width)
        let symbolWidth: CGFloat = style == .readable ? 20 : 18
        let gap: CGFloat = style == .readable ? 5 : 4
        let height: CGFloat = style == .readable ? 22 : 20
        let image = NSImage(size: NSSize(width: ceil(symbolWidth + gap + reservedValueSize), height: height))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) {
            let symbolSize = symbol.size
            let rect = NSRect(x: 0,
                              y: (height - symbolSize.height) / 2,
                              width: min(symbolWidth, symbolSize.width),
                              height: symbolSize.height)
            symbol.draw(in: rect)
        }
        let valueY = (height - valueSize.height) / 2
        (value as NSString).draw(at: NSPoint(x: symbolWidth + gap, y: valueY),
                                 withAttributes: valueAttrs)
        image.unlockFocus()
        image.isTemplate = true
        blockImageCache.setObject(image, forKey: cacheKey)
        return image
    }

    static func batterySymbol(for percent: Int, isCharging: Bool) -> String {
        if isCharging { return "battery.100.bolt" }
        switch percent {
        case 85...: return "battery.100"
        case 60..<85: return "battery.75"
        case 35..<60: return "battery.50"
        case 10..<35: return "battery.25"
        default: return "battery.0"
        }
    }

    private static func estimatedSnapshot() -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        snapshot.cpuUsage = 1
        snapshot.gpuUsage = 1
        snapshot.memoryUsed = 100
        snapshot.memoryTotal = 100
        snapshot.memoryPressure = .normal
        snapshot.cpuTemperature = 125
        snapshot.gpuTemperature = 125
        snapshot.batteryTemperature = 125
        snapshot.netDownBytesPerSec = 1_000_000_000
        snapshot.netUpBytesPerSec = 1_000_000_000
        var power = PowerReading()
        power.systemWatts = 99
        power.chargePercent = 100
        power.isCharging = true
        snapshot.power = power
        return snapshot
    }

    static func nsColor(for pressure: MemoryPressure) -> NSColor {
        switch pressure {
        case .normal: return .systemGreen
        case .warning: return .systemYellow
        case .critical: return .systemRed
        case .unknown: return .secondaryLabelColor
        }
    }

    /// A compact 0...1 fraction: "5%", "47%", "100%".
    private static func percent(_ fraction: Double) -> String {
        let value = Int((max(0, min(1, fraction)) * 100).rounded())
        return "\(value)%"
    }

    private static func temperatureCompact(_ celsius: Double) -> String {
        let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "")
            ?? .celsius
        return MetricFormat.temperatureCompact(celsius, unit: unit)
    }

    private static func temperatureLabel(_ component: String) -> String {
        let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.temperatureUnit) ?? "")
            ?? .celsius
        return component + MetricFormat.temperatureUnitSuffix(unit)
    }

    private static func combinedComponentLabel(_ component: String,
                                               hasPrimary: Bool,
                                               hasTemperature: Bool) -> String {
        if hasPrimary { return component }
        return hasTemperature ? temperatureLabel(component) : component
    }

    private static func combinedComponentValue(primary: String?, temperature: String?) -> String? {
        var values: [String] = []
        if let primary { values.append(primary) }
        if let temperature { values.append(temperature) }
        return values.isEmpty ? nil : values.joined(separator: " ")
    }

    private static func minimumCombinedValue(primary: Bool, temperature: Bool) -> String {
        switch (primary, temperature) {
        case (true, true): return "100% 999°"
        case (true, false): return "100%"
        case (false, true): return "999°"
        case (false, false): return ""
        }
    }
}
