// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ChargeControlSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChargeControlService.shared
    var collapsible = true

    private var strings: ChargeControlFeatureStrings {
        FeatureStrings.chargeControl(l10n.language)
    }

    var body: some View {
        PanelSection(.chargeControl, title: strings.title, collapsible: collapsible) {
            ChargeControlCardContent(compact: true)
                .panelCard()
                .onAppear { service.panelDidAppear() }
                .onDisappear { service.panelDidDisappear() }
        }
    }
}

/// Compact limit slider under the Battery metric's charge percentage.
struct ChargeLimitInlineAdjuster: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChargeControlService.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @Environment(\.colorScheme) private var colorScheme

    private var strings: ChargeControlFeatureStrings {
        FeatureStrings.chargeControl(l10n.language)
    }

    var body: some View {
        let _ = features.revision
        if PowerSampler.hasInternalBattery {
            VStack(alignment: .leading, spacing: 8) {
                Divider().opacity(0.55)

                HStack(spacing: 8) {
                    Text(strings.limitLabel)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text("\(service.limitPercent)%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ChargeLimitPalette.lime(for: colorScheme))
                }

                ChargeLimitSlider(
                    value: Binding(
                        get: { Double(service.limitPercent) },
                        set: { applyLimit(Int($0.rounded())) }
                    ),
                    range: Double(service.minimumSupportedLimit)...Double(ChargeControlPolicy.maximumLimit),
                    step: service.usesNativeCharging ? 5 : 1
                )
                .disabled(service.isCalibrating)
                .opacity(service.isCalibrating ? 0.45 : 1)
                .help(strings.enableCaption)
                .accessibilityLabel(strings.limitLabel)

                footer
            }
            .onAppear { service.panelDidAppear() }
            .onDisappear { service.panelDidDisappear() }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if service.accessState == .enabled {
            HStack(spacing: 8) {
                Toggle(strings.enableToggle, isOn: Binding(
                    get: { service.enabled },
                    set: { newValue in
                        ensureFeatureAvailable()
                        service.setEnabled(newValue)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(service.isCalibrating)
                Spacer(minLength: 0)
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        } else if service.accessState == .requiresApproval {
            Button(strings.openSettings, action: service.authorize)
                .buttonStyle(.borderedProminent)
                .tint(ChargeLimitPalette.lime(for: colorScheme))
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            Text(strings.approvalCaption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button(strings.allowControl) {
                ensureFeatureAvailable()
                service.authorize()
            }
            .buttonStyle(.borderedProminent)
            .tint(ChargeLimitPalette.lime(for: colorScheme))
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            if let message = errorMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(strings.approvalCaption)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusText: String {
        if service.isCalibrating, let phase = service.calibrationPhase {
            switch phase {
            case .chargingToFull: return strings.calPhaseCharge
            case .dischargingToFloor: return strings.calPhaseDischarge
            case .chargingToFullAgain: return strings.calPhaseChargeAgain
            case .holdingAtFull: return strings.calPhaseHold
            case .restoringLimit: return strings.calPhaseRestore
            }
        }
        if service.isDischargingToLimit { return strings.discharging }
        if service.isToppingUp { return strings.toppingUp }
        if service.isHolding { return strings.holding }
        if service.isCharging { return strings.charging }
        if !service.externalConnected { return strings.onBattery }
        return strings.notCharging
    }

    private var statusColor: Color {
        if service.appliedGate == .forceDischarge || service.isDischargingToLimit {
            return ChargeLimitPalette.discharge(for: colorScheme)
        }
        if service.isHolding {
            return ChargeLimitPalette.lime(for: colorScheme)
        }
        if service.isToppingUp || service.isCharging {
            return ChargeLimitPalette.charging(for: colorScheme)
        }
        return .secondary
    }

    private var errorMessage: String? {
        switch service.error {
        case .unsupportedHardware: return strings.unsupported
        case .helperUnavailable, .controlFailed: return strings.failed
        default: return nil
        }
    }

    private func applyLimit(_ percent: Int) {
        ensureFeatureAvailable()
        if !service.enabled { service.setEnabled(true) }
        service.setLimit(percent)
    }

    private func ensureFeatureAvailable() {
        if !AppFeature.chargeControl.isAvailable {
            FeatureRuntime.shared.setAvailable(.chargeControl, true)
            service.panelDidAppear()
        }
    }
}

/// Discharge and Top up while the adapter is connected. Discharge drains to
/// the saved limit; Top up temporarily charges to 100% and then restores it.
struct ChargeLimitPowerActions: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChargeControlService.shared
    @Environment(\.colorScheme) private var colorScheme

    private var strings: ChargeControlFeatureStrings {
        FeatureStrings.chargeControl(l10n.language)
    }

    var body: some View {
        Group {
            if service.accessState == .enabled,
               !service.isCalibrating,
               showDischarge || showTopUp {
                HStack(spacing: 8) {
                    if showDischarge {
                        Button {
                            if service.isDischargingToLimit { service.stopDischarge() }
                            else { service.startDischargeToLimit() }
                        } label: {
                            Label(service.isDischargingToLimit ? strings.stopDischarge : strings.discharge,
                                  systemImage: service.isDischargingToLimit
                                      ? "stop.circle.fill" : "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(service.isDischargingToLimit
                              ? ChargeLimitPalette.discharge(for: colorScheme)
                              : nil)
                        .controlSize(.small)
                        .disabled(service.isWorking)
                        .frame(maxWidth: .infinity)
                    }
                    if showTopUp {
                        Button {
                            if service.isToppingUp { service.stopTopUp() }
                            else { service.startTopUp() }
                        } label: {
                            Label(service.isToppingUp ? strings.stopTopUp : strings.topUp,
                                  systemImage: service.isToppingUp ? "stop.circle.fill" : "bolt.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(service.isToppingUp
                              ? ChargeLimitPalette.charging(for: colorScheme)
                              : nil)
                        .controlSize(.small)
                        .disabled(service.isWorking
                                  || (!service.isToppingUp && (service.profile?.supportsInhibit != true
                                      || !service.externalConnected
                                      || (service.chargePercent ?? 0) >= ChargeControlPolicy.maximumLimit)))
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onAppear { service.panelDidAppear() }
    }

    private var showDischarge: Bool {
        service.profile?.supportsDischarge == true
    }

    private var showTopUp: Bool {
        service.limitPercent < ChargeControlPolicy.maximumLimit
            || service.isToppingUp
    }
}

struct ChargeControlCardContent: View {
    var compact = false
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ChargeControlService.shared
    @Environment(\.colorScheme) private var colorScheme

    private var strings: ChargeControlFeatureStrings {
        FeatureStrings.chargeControl(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            header
            if service.hasBattery {
                batteryLevel
                limitSlider
                if service.enabled {
                    sailingControls
                }
                if let message = stateMessage {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(messageIsError ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions
                if !compact {
                    calibrationBlock
                    Text(service.usesNativeCharging
                         ? "macOS keeps the selected charge limit active. Adapter power is restored if Discharge loses its connection to the app."
                         : strings.safetyCaption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.secondary.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                } else if service.isCalibrating {
                    compactCalibration
                }
            } else {
                Text(strings.noBattery)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerSymbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(statusColor)
                .symbolEffect(.variableColor.iterative, options: .repeating,
                              isActive: service.isCharging && !service.isHolding)
                .frame(width: 24)
            Text(statusText)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(statusColor)
            Spacer()
            if service.isWorking { ProgressView().controlSize(.small) }
        }
    }

    private var batteryLevel: some View {
        ChargeLimitBars(
            charge: service.chargePercent ?? 0,
            limit: service.limitPercent,
            excessColor: service.isToppingUp
                ? ChargeLimitPalette.charging(for: colorScheme)
                : ChargeLimitPalette.discharge(for: colorScheme),
            statusLabel: statusText,
            limitLabel: strings.limitLabel,
            height: compact ? 25 : 30
        )
        .padding(.vertical, compact ? 0 : 4)
    }

    private var limitSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(strings.limitLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(service.limitPercent)%")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ChargeLimitPalette.lime(for: colorScheme))
            }
            ChargeLimitSlider(
                value: Binding(
                    get: { Double(service.limitPercent) },
                    set: { newValue in
                        if !service.enabled { service.setEnabled(true) }
                        service.setLimit(Int(newValue.rounded()))
                    }
                ),
                range: Double(service.minimumSupportedLimit)...Double(ChargeControlPolicy.maximumLimit),
                step: service.usesNativeCharging ? 5 : 1
            )
            .disabled(service.isCalibrating)
            .opacity(service.isCalibrating ? 0.45 : 1)
        }
    }

    private var sailingControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if service.usesNativeCharging {
                Text("macOS manages the charging range, including draining to the limit when above it. Limits use 5% steps from 80% to 100% and remain active when the app quits. Discharge uses battery power until stopped, regardless of the limit. Top Up charges to 100%.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
            Toggle(strings.sailingMode, isOn: Binding(
                get: { service.sailingEnabled },
                set: { service.setSailingEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(service.isCalibrating)

            if service.sailingEnabled {
                HStack {
                    Text(strings.sailingRangeLabel)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(service.sailingRangePercent)%")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ChargeLimitPalette.lime(for: colorScheme))
                }
                ChargeLimitSlider(
                    value: Binding(
                        get: { Double(service.sailingRangePercent) },
                        set: { service.setSailingRange(Int($0.rounded())) }
                    ),
                    range: Double(ChargeControlPolicy.minimumSailingRange)...Double(
                        ChargeControlPolicy.maximumSailingRange(limit: service.limitPercent))
                )
                .disabled(service.isCalibrating)
                .opacity(service.isCalibrating ? 0.45 : 1)
                .accessibilityLabel(strings.sailingRangeLabel)

                if !compact {
                    Text(strings.sailingCaption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if service.accessState == .enabled {
            Toggle(strings.enableToggle, isOn: Binding(
                get: { service.enabled },
                set: { service.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(service.isCalibrating)
            ChargeLimitPowerActions()
        } else if service.accessState == .requiresApproval {
            Button(strings.openSettings, action: service.authorize)
                .buttonStyle(.borderedProminent)
                .tint(ChargeLimitPalette.lime(for: colorScheme))
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else {
            Button(strings.allowControl, action: service.authorize)
                .buttonStyle(.borderedProminent)
                .tint(ChargeLimitPalette.lime(for: colorScheme))
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    private var calibrationBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.calibrationTitle).font(.system(size: 11, weight: .semibold))
            Text(strings.calibrationCaption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if service.isCalibrating {
                compactCalibration
                Button(strings.cancelCalibration, action: service.cancelCalibration)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else {
                Button(strings.startCalibration, action: service.startCalibration)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!canStartCalibration || service.isWorking)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private var compactCalibration: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let phase = service.calibrationPhase {
                Text(phaseText(phase))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(ChargeLimitPalette.lime(for: colorScheme))
            }
            if let remaining = service.holdRemainingSeconds {
                Text(String(format: strings.calHoldRemainingFormat,
                            max(1, Int((remaining / 60).rounded(.up)))))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if compact {
                Button(strings.cancelCalibration, action: service.cancelCalibration)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }

    private var canStartCalibration: Bool {
        service.accessState == .enabled
            && service.profile?.supportsDischarge == true
            && service.externalConnected
            && !service.isDischargingToLimit
    }

    private var headerSymbol: String {
        if service.isDischargingToLimit || service.appliedGate == .forceDischarge { return "battery.25" }
        if service.isHolding { return "battery.75percent" }
        if service.isCharging || service.isToppingUp { return "battery.100.bolt" }
        return "battery.75percent"
    }

    private var statusText: String {
        if service.isCalibrating, let phase = service.calibrationPhase { return phaseText(phase) }
        if service.isDischargingToLimit { return strings.discharging }
        if service.isToppingUp { return strings.toppingUp }
        if !service.externalConnected { return strings.onBattery }
        if service.isHolding { return strings.holding }
        if service.isCharging { return strings.charging }
        return strings.notCharging
    }

    private var statusColor: Color {
        if service.appliedGate == .forceDischarge || service.isDischargingToLimit {
            return ChargeLimitPalette.discharge(for: colorScheme)
        }
        if service.isHolding { return ChargeLimitPalette.lime(for: colorScheme) }
        if service.isToppingUp || service.isCharging {
            return ChargeLimitPalette.charging(for: colorScheme)
        }
        return .secondary
    }

    private var stateMessage: String? {
        if !service.hasBattery { return strings.noBattery }
        if service.error == .unsupportedHardware { return strings.unsupported }
        switch service.error {
        case .helperUnavailable, .controlFailed: return strings.failed
        case .authorizationRequired: return strings.approvalCaption
        default: break
        }
        if service.accessState == .notRegistered || service.accessState == .requiresApproval {
            return strings.approvalCaption
        }
        if service.accessState == .enabled, service.profile?.supportsDischarge == false {
            return strings.calUnsupportedDischarge
        }
        return nil
    }

    private var messageIsError: Bool {
        switch service.error {
        case .helperUnavailable, .controlFailed, .unsupportedHardware: return true
        default: return false
        }
    }

    private func phaseText(_ phase: ChargeCalibrationPhase) -> String {
        switch phase {
        case .chargingToFull: return strings.calPhaseCharge
        case .dischargingToFloor: return strings.calPhaseDischarge
        case .chargingToFullAgain: return strings.calPhaseChargeAgain
        case .holdingAtFull: return strings.calPhaseHold
        case .restoringLimit: return strings.calPhaseRestore
        }
    }
}

private enum ChargeLimitPalette {
    static func lime(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.42, green: 0.52, blue: 0.02)
                         : Color(red: 0.80, green: 0.88, blue: 0.22)
    }
    static func charging(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.10, green: 0.55, blue: 0.28)
                         : Color(red: 0.55, green: 0.90, blue: 0.45)
    }
    static func discharge(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.72, green: 0.38, blue: 0.04)
                         : Color(red: 1.00, green: 0.68, blue: 0.22)
    }
    static func track(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.10)
    }
}

struct ChargeLimitBars: View {
    let charge: Int
    let limit: Int
    let excessColor: Color
    let statusLabel: String
    let limitLabel: String
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filledSegments: Int {
        ChargeLimitBarSupport.filledSegmentCount(for: charge)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(ChargeLimitBarSupport.clampedPercent(charge))")
                    .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                Text("%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(limitLabel)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    Text("\(ChargeLimitBarSupport.clampedPercent(limit))%")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ChargeLimitPalette.lime(for: colorScheme))
                }
            }

            GeometryReader { proxy in
                let markerX = proxy.size.width * ChargeLimitBarSupport.targetFraction(for: limit)
                ZStack(alignment: .leading) {
                    HStack(spacing: 3) {
                        ForEach(0..<ChargeLimitBarSupport.segmentCount, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(segmentColor(index))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Rectangle()
                        .fill(Color.primary.opacity(0.72))
                        .frame(width: 1, height: height + 6)
                        .offset(x: min(max(0, markerX), max(0, proxy.size.width - 1)))
                }
                .frame(height: height)
            }
            .frame(height: height)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: filledSegments)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusLabel)
        .accessibilityValue("\(ChargeLimitBarSupport.clampedPercent(charge))%, \(limitLabel) \(ChargeLimitBarSupport.clampedPercent(limit))%")
    }

    private func segmentColor(_ index: Int) -> Color {
        guard index < filledSegments else { return ChargeLimitPalette.track(for: colorScheme) }
        if ChargeLimitBarSupport.isAboveLimit(segment: index, limit: limit) { return excessColor }
        return ChargeLimitPalette.lime(for: colorScheme)
    }
}

struct ChargeLimitSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            let x = max(7, min(width - 7, width * fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(ChargeLimitPalette.track(for: colorScheme)).frame(height: 8)
                Capsule().fill(ChargeLimitPalette.lime(for: colorScheme)).frame(width: x, height: 8)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .overlay(Circle().strokeBorder(ChargeLimitPalette.lime(for: colorScheme).opacity(0.85), lineWidth: 2))
                    .offset(x: x - 9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        }
        .frame(height: 22)
        .overlay {
            ChargeLimitSliderCatcher(value: $value, range: range, isEnabled: isEnabled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int(value.rounded()))%")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            default: break
            }
        }
    }
}

/// AppKit mouse tracking so the knob still moves inside Settings' Form and
/// the panel's NSScrollView, which swallow SwiftUI DragGesture.
private struct ChargeLimitSliderCatcher: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        context.coordinator.bind(view, value: $value)
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        context.coordinator.bind(view, value: $value)
        view.range = range
        view.isEnabled = isEnabled
        view.lastSent = value
    }

    final class Coordinator {
        func bind(_ view: CatcherView, value: Binding<Double>) {
            view.onChange = { value.wrappedValue = $0 }
        }
    }

    final class CatcherView: NSView {
        var range: ClosedRange<Double> = 20...100
        var isEnabled = true
        var lastSent: Double = 0
        var onChange: (Double) -> Void = { _ in }

        override var isOpaque: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }
        override func resetCursorRects() {
            guard isEnabled else { return }
            addCursorRect(bounds, cursor: .pointingHand)
        }
        override func mouseDown(with event: NSEvent) { send(event) }
        override func mouseDragged(with event: NSEvent) { send(event) }

        private func send(_ event: NSEvent) {
            guard isEnabled, bounds.width > 1 else { return }
            let x = convert(event.locationInWindow, from: nil).x
            let fraction = min(max(x / bounds.width, 0), 1)
            let next = (range.lowerBound + fraction * (range.upperBound - range.lowerBound)).rounded()
            let clamped = min(max(next, range.lowerBound), range.upperBound)
            guard clamped != lastSent else { return }
            lastSent = clamped
            onChange(clamped)
        }
    }
}
