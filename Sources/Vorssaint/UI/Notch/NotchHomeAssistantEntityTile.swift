// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A native control card. The dimmer is a separate hit region from the primary button.
struct NotchHomeAssistantEntityTile: View, Equatable {
    let entity: HomeAssistantEntity?
    let name: String
    let columns: Int
    let connected: Bool
    let pending: Bool
    let text: HomeAssistantStrings
    var height: CGFloat = NotchLayout.homeAssistantCardHeight
    var readings: [HomeAssistantCardReading] = []
    let locale: Locale
    let temperatureUnit: String
    let activate: () -> Void
    let details: () -> Void
    let setBrightness: (Double) -> Void
    var setColor: (HomeAssistantRGB) -> Void = { _ in }
    @State private var draft = 0.0
    @State private var editing = false
    @State private var requestedBrightness: Double?
    @State private var hovered = false
    @State private var showingColor = false
    @Environment(\.homeAssistantCardVisible) private var cardVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entity == rhs.entity && lhs.name == rhs.name && lhs.columns == rhs.columns
            && lhs.connected == rhs.connected && lhs.pending == rhs.pending && lhs.height == rhs.height
            && lhs.readings == rhs.readings && lhs.locale == rhs.locale
            && lhs.temperatureUnit == rhs.temperatureUnit && lhs.text.values == rhs.text.values
    }

    private var dense: Bool { columns >= 6 }
    private var compact: Bool { height < 120 }
    private var tight: Bool { height < 100 }
    private var packed: Bool { dimmable || !readings.isEmpty }
    private var compressed: Bool { dimmable && readings.count > 1 }
    private var dimmable: Bool { entity?.domain == "light" && entity?.hasBrightness == true }
    private var interactive: Bool { connected && entity?.available == true && entity?.eligible == true && !pending }
    private var percent: Double {
        if editing { return draft }
        if pending, let requestedBrightness { return requestedBrightness }
        return entity?.brightnessPercent ?? 0
    }
    private var entitySymbol: String {
        if entity?.domain == "light", entity?.state == "on" { return "lightbulb.fill" }
        if entity?.domain == "switch", entity?.state == "on" { return "powerplug.fill" }
        return entity?.symbol ?? "house"
    }
    private var tint: Color {
        if entity?.state == "on", entity?.hasColor == true {
            if let color = entity?.rgbColor { return color.color }
            if ["white", "color_temp"].contains(entity?.attributes["color_mode"]?.string ?? "") { return .white }
            return .yellow
        }
        switch entity?.domain {
        case "light": return .yellow
        case "switch", "binary_sensor": return .green
        case "climate": return .orange
        case "scene", "script": return .purple
        default: return .cyan
        }
    }
    private var fill: Double {
        guard entity?.available == true else { return 0 }
        if dimmable { return percent / 100 }
        return entity?.state == "on" ? 1 : 0
    }
    private var displayedValue: String {
        guard columns >= 4, let entity, entity.available, entity.domain != "climate" else { return reading.value }
        switch entity.state {
        case "on": return text[.compactOn]
        case "off": return text[.compactOff]
        default: return ["scene", "script"].contains(entity.domain) ? text[.compactRun] : reading.value
        }
    }
    private var reading: (value: String, unit: String) {
        guard let entity else { return (text[.unavailable], "") }
        return HomeAssistantPresentation.reading(entity, text: text, temperatureUnit: temperatureUnit, locale: locale)
    }

    var body: some View {
        VStack(spacing: compact ? 2 : 4) {
            primaryButton
            if dimmable {
                VStack(spacing: 1) {
                    if !compact {
                        Text(Int(percent.rounded()).formatted(.number.locale(locale)) + "%")
                            .font(.system(size: dense ? 10 : 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(tint)
                            .contentTransition(.numericText())
                            .animation(reduceMotion || editing ? nil : .smooth(duration: 0.24), value: percent)
                    }
                    brightnessSlider
                }
                .frame(height: compact ? 14 : 30)
            }
        }
        .padding(dense || tight ? 3 : 6)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(hovered ? 0.12 : 0.045))
                    tint.opacity(connected ? 0.22 : 0.1).frame(width: geometry.size.width * fill)
                }
                .animation(reduceMotion || editing ? nil : .smooth(duration: 0.24), value: fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(hovered ? 0.55 : contrast == .increased ? 0.4 : fill > 0 ? 0.18 : 0.04), lineWidth: 1)
                .animation(reduceMotion || editing ? nil : .smooth(duration: 0.24), value: fill)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { value in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { hovered = value } }
        .help(([name, [reading.value, reading.unit].filter { !$0.isEmpty }.joined(separator: " ")] + readings.map(\.description)).joined(separator: " · "))
        .contextMenu { Button(text[.details], action: details) }
        .background {
            if entity?.hasColor == true { HomeAssistantSecondaryClick(enabled: cardVisible, action: { showingColor = true }) }
        }
        .popover(isPresented: $showingColor, arrowEdge: .bottom) {
            HomeAssistantColorSelector(name: name, initial: entity?.rgbColor ?? HomeAssistantRGB(red: 255, green: 255, blue: 255),
                                       text: text, enabled: interactive, apply: { setColor($0); showingColor = false },
                                       cancel: { showingColor = false })
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if entity?.hasColor == true { Button(text[.selectColor]) { showingColor = true } }
        }
        .onAppear { draft = entity?.brightnessPercent ?? 0 }
        .onChange(of: entity) {
            if !editing && (!pending || requestedBrightness == nil) { draft = entity?.brightnessPercent ?? 0 }
        }
        .onChange(of: pending) { if !pending { editing = false; requestedBrightness = nil; draft = entity?.brightnessPercent ?? 0 } }
        .onChange(of: connected) { if !connected { editing = false; requestedBrightness = nil; draft = entity?.brightnessPercent ?? 0 } }
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: entity?.rgbColor)
    }
    private var actionHint: String {
        guard let service = entity?.primaryService else { return text[.details] }
        if service == "turn_off" { return text[.off] }
        if entity?.domain == "light" || entity?.domain == "switch" { return text[.on] }
        return text[.run]
    }
    private var primaryButton: some View {
        Button(action: entity?.primaryService == nil ? details : activate) {
            primaryContent
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 16, lifts: false, disabledOpacity: pending ? 1 : 0.4))
        .disabled(entity?.primaryService != nil && !interactive)
        .accessibilityLabel(name)
        .accessibilityValue(([reading.value, reading.unit].filter { !$0.isEmpty } + readings.map(\.description)).joined(separator: " · "))
        .accessibilityHint(actionHint)
        .accessibilityAction(named: Text(text[.details]), details)
        .overlay(alignment: .topTrailing) { if !(tight && dense) { detailsButton } }
    }
    private var detailsButton: some View {
        Button(action: details) {
            Image(systemName: "ellipsis").font(.system(size: dense ? 10 : 13, weight: .bold))
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .frame(width: dense ? 14 : 20, height: 18)
        .contentShape(Rectangle())
        .help(text[.details]).accessibilityLabel(text[.details] + ": " + name)
    }
    private var primaryContent: some View {
        VStack(alignment: .center, spacing: compressed || dense ? 1 : packed ? 2 : 3) {
            entityIcon
            title
            cardReading
            if !readings.isEmpty { extraReadings }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
    }

    private var entityIcon: some View {
        Image(systemName: entitySymbol)
            .font(.system(size: compressed || dense && packed ? 12 : packed ? 16 : dense ? 18 : 22, weight: .medium))
            .contentTransition(.symbolEffect(.replace))
            .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: entitySymbol)
            .foregroundStyle(entity?.state == "on" ? tint : .secondary)
            .opacity(pending ? 0.35 : 1)
            .overlay {
                if pending { ProgressView().controlSize(.mini).scaleEffect(0.65) }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: pending)
            .frame(width: packed ? 18 : 25, height: compressed || dense && packed ? 12 : packed ? 16 : 25)
            .accessibilityHidden(true)
    }
    private var title: some View {
        Text(name)
                .font(.system(size: dense ? 11 : compressed ? 12 : 13, weight: .semibold))
                .foregroundStyle(.primary).lineLimit(packed ? 1 : 2)
                .minimumScaleFactor(0.85).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
    }
    private var brightnessSlider: some View {
        Slider(value: Binding(get: { draft }, set: { draft = $0.rounded() }), in: 0...100) { active in
            if active { requestedBrightness = nil }
            editing = active
            if !active { requestedBrightness = draft; setBrightness(draft) }
        }
        .controlSize(.mini).tint(tint).frame(height: 14)
        .disabled(!interactive)
        .accessibilityLabel(text[.brightness] + ": " + name)
    }

    private var cardReading: some View {
        let value = [displayedValue, reading.unit].filter { !$0.isEmpty }.joined(separator: " ")
        let label = value + (compact && dimmable ? " · " + Int(percent.rounded()).formatted(.number.locale(locale)) + "%" : "")
        return Text(label)
            .font(.system(size: compressed ? 9 : tight ? 10 : dense ? 11 : 13, weight: .medium))
            .foregroundStyle(.secondary).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentTransition(entity?.isSensor == true ? .numericText() : .opacity)
            .animation(reduceMotion || editing ? nil : .smooth(duration: 0.24), value: label)
    }
    private var extraReadings: some View {
        VStack(spacing: 1) {
            ForEach(readings) { sensor in
                HStack(spacing: 3) {
                    if !dense {
                        Text(sensor.name).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text([sensor.value, sensor.unit].filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                        .layoutPriority(1).contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: sensor.value)
                }.frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
