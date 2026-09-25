// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The "Monitor" settings page: pick what shows next to the menu bar icon, how
/// it looks and how often it refreshes, which blocks appear in the panel, when
/// to warn, and which metrics draw a history graph. Everything is opt-in or
/// reversible, so users keep only what they find useful. The live menu bar
/// preview stays pinned while the choices that change it scroll under it.
struct MonitorSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared

    @AppStorage(DefaultsKey.menuBarCombineTemperatures) private var combineTemperatures = true
    @AppStorage(DefaultsKey.menuBarSeparateMetrics) private var separateMetrics = false
    @AppStorage(DefaultsKey.menuBarMetricSpacing) private var metricSpacing = "standard"
    @AppStorage(DefaultsKey.menuBarMetricAppearance) private var metricAppearance = "values"
    @AppStorage(DefaultsKey.menuBarHideIconWithMetrics) private var hideIconWithMetrics = false
    @AppStorage(DefaultsKey.monitorInterval) private var interval = 2
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.monitorMemoryMetric) private var memoryMetric = "used"
    @AppStorage(DefaultsKey.panelShowFanControl) private var showFanControl = true


    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(l10n.s.tabMonitor).font(.title2.bold())
                    Text(FeatureStrings.settingsPages(l10n.language).monitorDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                groupHeading(l10n.s.monitorMenuBarSection, symbol: "menubar.rectangle")
                // Everything under this header changes what the header
                // shows, so it stays in view until the section ends.
                Section {
                    menuBarCard
                    menuBarStyleCard
                } header: {
                    MenuBarMetricsPreview()
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .windowBackgroundColor))
                }
                groupHeading(l10n.s.monitorPanelSection, symbol: "macwindow")
                panelCard
                if AppFeature.fanControl.isAvailable {
                    fanControlCard
                        .settingsSectionAnchor(.fanControl, cornerRadius: 16)
                }
                groupHeading(FeatureStrings.monitorLayout(l10n.language).shared, symbol: "slider.horizontal.3")
                readingsCard
                alertsCard
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .toggleStyle(.switch)
        .onAppear {
            interval = Defaults.sanitizedMonitorInterval(interval)
            metricAppearance = Defaults.sanitizedMenuBarMetricAppearance(metricAppearance)
            if TemperatureUnit(rawValue: temperatureUnit) == nil {
                temperatureUnit = TemperatureUnit.celsius.rawValue
            }
            memoryMetric = Defaults.sanitizedMonitorMemoryMetric(memoryMetric)
        }
    }

    /// Splits the page into what the menu bar shows, what the panel shows,
    /// and what both share, so an option is never read as the other's.
    private func groupHeading(_ title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 8)
    }

    private var appearanceStrings: MenuBarAppearanceStrings {
        FeatureStrings.menuBarAppearance(l10n.language)
    }

    private var appearance: MenuBarMetricAppearance {
        MenuBarMetricAppearance(rawValue: Defaults.sanitizedMenuBarMetricAppearance(metricAppearance)) ?? .values
    }

    /// The readings that can sit in the menu bar, as tiles in the order they
    /// appear there.
    private var menuBarCard: some View {
        SettingsCard {
            Text(l10n.s.monitorMenuBarCaption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            MenuBarMetricTiles()
            Text(FeatureStrings.notchEditor(l10n.language).reorderHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var menuBarStyleCard: some View {
        SettingsCard(title: appearanceStrings.label) {
            HStack(spacing: 10) {
                MenuBarStyleChoice(appearance: .values, title: appearanceStrings.values,
                                   selected: appearance == .values) { metricAppearance = "values" }
                MenuBarStyleChoice(appearance: .bars, title: appearanceStrings.bars,
                                   selected: appearance == .bars) { metricAppearance = "bars" }
            }
            Text(appearanceStrings.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if appearance == .bars {
                MenuBarUsageBarSettings(strings: appearanceStrings)
            } else {
                SettingsRow(symbol: "thermometer.medium", title: l10n.s.monitorCombineTemperatures,
                            caption: l10n.s.monitorCombineTemperaturesCaption) {
                    Toggle(l10n.s.monitorCombineTemperatures, isOn: $combineTemperatures).labelsHidden()
                }
            }
            Divider()
            SettingsRow(symbol: "arrow.left.and.right", title: l10n.s.menuBarSpacingLabel) {
                Picker(l10n.s.menuBarSpacingLabel, selection: $metricSpacing) {
                    Text(l10n.s.menuBarSpacingStandard).tag("standard")
                    Text(l10n.s.menuBarSpacingCompact).tag("compact")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(symbol: "eye.slash", title: l10n.s.menuBarHideIconToggle,
                        caption: l10n.s.menuBarHideIconCaption) {
                Toggle(l10n.s.menuBarHideIconToggle, isOn: $hideIconWithMetrics).labelsHidden()
            }
            SettingsRow(symbol: "rectangle.split.3x1", title: l10n.s.monitorSeparateMenuBarMetrics,
                        caption: appearance.allowsCombinedTemperatures
                            ? l10n.s.monitorSeparateMenuBarMetricsCaption : nil) {
                Toggle(l10n.s.monitorSeparateMenuBarMetrics, isOn: $separateMetrics).labelsHidden()
            }
        }
    }

    private var readingsCard: some View {
        SettingsCard {
            SettingsRow(symbol: "timer", title: l10n.s.monitorIntervalLabel) {
                HStack(spacing: 6) {
                    intervalChip(1, title: l10n.s.monitorInterval1)
                    intervalChip(2, title: l10n.s.monitorInterval2)
                    intervalChip(5, title: l10n.s.monitorInterval5)
                }
            }
            SettingsRow(symbol: "thermometer.medium", title: l10n.s.temperatures) {
                Picker(l10n.s.temperatures, selection: $temperatureUnit) {
                    Text("°C").tag(TemperatureUnit.celsius.rawValue)
                    Text("°F").tag(TemperatureUnit.fahrenheit.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if AppFeature.monitorMemory.isAvailable {
                SettingsRow(symbol: "memorychip", title: l10n.s.monitorMemoryMetricLabel) {
                    Picker(l10n.s.monitorMemoryMetricLabel, selection: $memoryMetric) {
                        Text(l10n.s.memoryMetricUsed).tag("used")
                        Text(l10n.s.memoryMetricApp).tag("app")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    private func intervalChip(_ seconds: Int, title: String) -> some View {
        let selected = interval == seconds
        return Button {
            interval = seconds
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var alertsCard: some View {
        SettingsCard(title: FeatureStrings.monitorAlerts(l10n.language).section) {
            MonitorAlertsControls(compact: false)
        }
    }

    private var panelCard: some View {
        SettingsCard {
            MonitorPanelConfig(tiles: true)
            Text(l10n.s.monitorPanelConfigHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fanControlCard: some View {
        let fanStrings = FeatureStrings.fanControl(l10n.language)
        return SettingsCard {
            SettingsRow(symbol: "fanblades.fill", title: fanStrings.title, badge: l10n.s.betaBadge,
                        caption: fanStrings.settingsCaption) {
                Toggle(fanStrings.showInPanel, isOn: $showFanControl).labelsHidden()
            }
            Text(l10n.s.betaFeatureWarning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, settingsRowTextInset)
        }
    }
}

/// Values or bars, each drawn the way the menu bar would draw a CPU reading.
private struct MenuBarStyleChoice: View {
    let appearance: MenuBarMetricAppearance
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                mockup
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : .primary)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // The same proportions the real blocks use (MenuBarRenderer), reduced to
    // a CPU sample so the two styles read as themselves.
    @ViewBuilder
    private var mockup: some View {
        switch appearance {
        case .values:
            HStack(spacing: 10) {
                block(label: "CPU", value: "42%")
                block(label: "RAM", value: "61%")
            }
        case .bars:
            HStack(spacing: 10) {
                bar(label: "CPU", fraction: 0.42)
                bar(label: "RAM", fraction: 0.61)
            }
        }
    }

    private func block(label: String, value: String) -> some View {
        VStack(spacing: -1) {
            Text(label)
                .font(.system(size: 6.6, weight: .medium))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.white)
    }

    private func bar(label: String, fraction: CGFloat) -> some View {
        HStack(spacing: 2) {
            VStack(spacing: -1.8) {
                ForEach(Array(label.enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(.system(size: 6.1, weight: .semibold))
                }
            }
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                    .stroke(Color.white, lineWidth: 1.15)
                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(Color(red: 0.39, green: 0.82, blue: 1.0))
                    .frame(width: 4.8, height: 13.8 * fraction)
                    .padding(.bottom, 2.1)
            }
            .frame(width: 9, height: 18)
        }
        .foregroundStyle(.white)
    }
}

/// The menu bar readings as tiles: drag to put them in order, click the
/// checkmark to show or hide one. The order stays independent from which
/// metrics are visible, so toggles do not reshuffle it.
private struct MenuBarMetricTiles: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @AppStorage(DefaultsKey.menuBarMetricOrder) private var metricOrder = ""
    @State private var order: [MenuBarMetric] = MenuBarMetric.order(in: .standard)
    @State private var dragging: MenuBarMetric?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: monitorTokenColumns, spacing: 8) {
                ForEach(visibleOrder) { metric in
                    // Dragging moves within the full saved order, so metrics
                    // hidden by the hub keep their slot for their return.
                    PanelReorderableItem(item: metric, order: $order, dragging: $dragging) {
                        MenuBarMetricTile(metric: metric)
                    }
                }
            }
            .monitorTokenGroup()
        }
        .onAppear { order = MenuBarMetric.order(in: .standard) }
        .onChange(of: order) { _, order in
            // Only a drag writes; reloading the saved order must not.
            if order != MenuBarMetric.order(in: .standard) { MenuBarMetric.setOrder(order) }
        }
        .onChange(of: metricOrder) { _, _ in order = MenuBarMetric.order(in: .standard) }
    }

    /// Metrics whose family left the hub keep their saved slot but stay out
    /// of the editor until they return.
    private var visibleOrder: [MenuBarMetric] {
        order.filter { $0.feature.isAvailable && $0.isAvailableOnCurrentHardware }
    }
}

extension MenuBarMetric: PanelOrderItem {}

/// One reading, backed by its own key so the preview above updates the
/// moment it is ticked. A reading with its own option carries it in its card.
private struct MenuBarMetricTile: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    let metric: MenuBarMetric
    @AppStorage private var shown: Bool
    @AppStorage(DefaultsKey.menuBarMemoryStyle) private var memoryStyle = "percent"
    @AppStorage(DefaultsKey.menuBarNetworkUploadFirst) private var uploadFirst = false
    @AppStorage(DiskMenuBarStyle.defaultsKey) private var diskStyle = DiskMenuBarStyle.percent

    init(metric: MenuBarMetric) {
        self.metric = metric
        _shown = AppStorage(wrappedValue: false, metric.defaultsKey)
    }

    var body: some View {
        MonitorToken(symbol: metric.symbolName, title: metric.title(l10n.s), included: $shown,
                     options: options, optionsSummary: optionsSummary)
    }

    /// What the reading's option makes the menu bar show, in its own terms.
    private var optionsSummary: String {
        switch metric {
        case .memory:
            return Defaults.sanitizedMenuBarMemoryStyle(memoryStyle) != "percent"
                ? l10n.s.monitorMemoryPressureDot : FeatureStrings.mouseClickDebounce(l10n.language).moreOptions
        case .network: return uploadFirst ? "↑ ↓" : "↓ ↑"
        case .diskUsage:
            switch diskStyle {
            case DiskMenuBarStyle.free: return l10n.s.diskMenuBarAvailableSpace
            case DiskMenuBarStyle.used: return l10n.s.diskMenuBarUsedSpace
            default: return l10n.s.diskMenuBarUsedPercentage
            }
        default: return ""
        }
    }

    private var options: AnyView? {
        switch metric {
        case .memory:
            return AnyView(MonitorTokenOption(
                symbol: "circle.fill",
                title: l10n.s.monitorMemoryPressureDot,
                tint: PanelMetricColor.green(for: colorScheme),
                isOn: Binding(get: { Defaults.sanitizedMenuBarMemoryStyle(memoryStyle) != "percent" },
                              set: { memoryStyle = $0 ? "both" : "percent" })))
        case .network:
            return AnyView(MonitorTokenOption(symbol: "arrow.up.arrow.down",
                                                 title: l10n.s.monitorNetworkUploadFirst,
                                                 isOn: $uploadFirst))
        case .diskUsage:
            return AnyView(Picker(l10n.s.diskMenuBarStyleLabel, selection: $diskStyle) {
                Text(l10n.s.diskMenuBarUsedPercentage).tag(DiskMenuBarStyle.percent)
                Text(l10n.s.diskMenuBarAvailableSpace).tag(DiskMenuBarStyle.free)
                Text(l10n.s.diskMenuBarUsedSpace).tag(DiskMenuBarStyle.used)
            }
            .pickerStyle(.menu))
        default:
            return nil
        }
    }
}

private struct MenuBarUsageBarSettings: View {
    let strings: MenuBarAppearanceStrings

    @AppStorage(DefaultsKey.menuBarUsageBarNormalColor) private var normalColor = MenuBarUsageBarSupport.defaultNormalColor
    @AppStorage(DefaultsKey.menuBarUsageBarElevatedColor) private var elevatedColor = MenuBarUsageBarSupport.defaultElevatedColor
    @AppStorage(DefaultsKey.menuBarUsageBarCriticalColor) private var criticalColor = MenuBarUsageBarSupport.defaultCriticalColor
    @AppStorage(DefaultsKey.menuBarUsageBarMediumThreshold) private var mediumThreshold = MenuBarUsageBarSupport.defaultMediumThreshold
    @AppStorage(DefaultsKey.menuBarUsageBarHighThreshold) private var highThreshold = MenuBarUsageBarSupport.defaultHighThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(strings.customize)
                .font(.subheadline.weight(.semibold))

            ColorPicker(strings.normalColor,
                        selection: colorBinding($normalColor,
                                                fallback: MenuBarUsageBarSupport.defaultNormalColor),
                        supportsOpacity: false)
            ColorPicker(strings.mediumColor,
                        selection: colorBinding($elevatedColor,
                                                fallback: MenuBarUsageBarSupport.defaultElevatedColor),
                        supportsOpacity: false)
            ColorPicker(strings.highColor,
                        selection: colorBinding($criticalColor,
                                                fallback: MenuBarUsageBarSupport.defaultCriticalColor),
                        supportsOpacity: false)

            Divider()

            Stepper(value: mediumBinding, in: 1...99) {
                HStack {
                    Text(strings.mediumFrom)
                    Spacer()
                    Text("\(mediumThreshold)%")
                        .monospacedDigit()
                }
            }
            Stepper(value: highBinding, in: 2...100) {
                HStack {
                    Text(strings.highFrom)
                    Spacer()
                    Text("\(highThreshold)%")
                        .monospacedDigit()
                }
            }
        }
        .onAppear(perform: sanitize)
    }

    private var mediumBinding: Binding<Int> {
        Binding(get: { mediumThreshold },
                set: { mediumThreshold = min(max(1, $0), max(1, highThreshold - 1)) })
    }

    private var highBinding: Binding<Int> {
        Binding(get: { highThreshold },
                set: { highThreshold = min(100, max(mediumThreshold + 1, $0)) })
    }

    private func colorBinding(_ storage: Binding<String>, fallback: String) -> Binding<Color> {
        Binding {
            let rgb = MenuBarUsageBarSupport.rgb(for: storage.wrappedValue, fallback: fallback)
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        } set: { color in
            guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return }
            storage.wrappedValue = MenuBarUsageBarSupport.hex(red: Double(converted.redComponent),
                                                              green: Double(converted.greenComponent),
                                                              blue: Double(converted.blueComponent))
        }
    }

    private func sanitize() {
        normalColor = MenuBarUsageBarSupport.sanitizedColorHex(normalColor,
                                                               fallback: MenuBarUsageBarSupport.defaultNormalColor)
        elevatedColor = MenuBarUsageBarSupport.sanitizedColorHex(elevatedColor,
                                                                 fallback: MenuBarUsageBarSupport.defaultElevatedColor)
        criticalColor = MenuBarUsageBarSupport.sanitizedColorHex(criticalColor,
                                                                 fallback: MenuBarUsageBarSupport.defaultCriticalColor)
        let thresholds = MenuBarUsageBarSupport.thresholds(medium: mediumThreshold,
                                                           high: highThreshold)
        mediumThreshold = thresholds.medium
        highThreshold = thresholds.high
    }
}
