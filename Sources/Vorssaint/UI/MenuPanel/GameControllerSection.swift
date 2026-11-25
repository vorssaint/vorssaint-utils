// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Game controller tab in the menu panel.
struct GameControllerSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = GameControllerService.shared
    var collapsible = true

    private var text: GameControllerFeatureStrings { FeatureStrings.gameController(l10n.language) }

    var body: some View {
        PanelSection(.gameController, title: text.pageTitle, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 12) {
                if service.controllers.isEmpty {
                    emptyState
                } else {
                    ForEach(service.controllers) { controller in
                        GameControllerCard(controller: controller, text: text, locale: locale)
                    }
                }
            }
            .onAppear { service.refresh() }
        }
    }

    private var locale: Locale { Locale(identifier: l10n.language.rawValue) }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text(text.emptyTitle).font(.callout.weight(.medium))
            Text(text.emptyHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct GameControllerCard: View {
    let controller: ControllerInfo
    let text: GameControllerFeatureStrings
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let level = controller.batteryLevel { battery(level) }
            details
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gamecontroller.fill").font(.title3).foregroundStyle(Color.accentColor)
            Text(controller.name).font(.callout.weight(.semibold)).lineLimit(1)
        }
    }

    private func battery(_ level: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(GameControllerSupport.percent(level) ?? 0)%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                if let state = stateLabel {
                    Label(state.title, systemImage: state.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: level).tint(tint(for: level))
            if let estimate = estimateRow {
                row(estimate.title, estimate.value)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                row(text.connectedFor, connectedText(at: context.date))
                    .help(controller.connectionIsLowerBound ? text.connectedForLowerBoundHelp : "")
            }
            if let transport = controller.transport { row(text.connectionLabel, transport) }
            if let firmware = controller.firmware { row(text.firmwareLabel, firmware) }
            if let category = controller.category, category != controller.name {
                row(text.typeLabel, category)
            }
            if !controller.features.isEmpty {
                row(text.featuresLabel, controller.features.map(featureName).joined(separator: " · "))
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.caption).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    private func connectedText(at date: Date) -> String {
        let value = GameControllerSupport.duration(date.timeIntervalSince(controller.connectedAt), locale: locale)
        return controller.connectionIsLowerBound ? value + "+" : value
    }

    private var stateLabel: (title: String, symbol: String)? {
        switch controller.chargeState {
        case .charging: return (text.stateCharging, "bolt.fill")
        case .discharging: return (text.stateDischarging, "battery.50percent")
        case .full: return (text.stateFull, "checkmark.circle.fill")
        case .unknown: return nil
        }
    }

    private var estimateRow: (title: String, value: String)? {
        let title: String
        switch controller.chargeState {
        case .charging: title = text.timeToFull
        case .discharging: title = text.timeRemaining
        case .full, .unknown: return nil
        }
        let value = controller.chargeEstimate.map { GameControllerSupport.duration($0, locale: locale) }
        return (title, value ?? text.estimating)
    }

    private func tint(for level: Double) -> Color {
        if controller.chargeState == .charging { return .green }
        return level <= 0.15 ? .red : level <= 0.3 ? .orange : .green
    }

    private func featureName(_ feature: ControllerFeature) -> String {
        switch feature {
        case .haptics: return text.featureHaptics
        case .lightBar: return text.featureLightBar
        case .motion: return text.featureMotion
        case .adaptiveTriggers: return text.featureAdaptiveTriggers
        case .touchpad: return text.featureTouchpad
        }
    }
}
