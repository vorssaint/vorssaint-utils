// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AmbientLightSettingsCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = AmbientLightService.shared
    @AppStorage(DefaultsKey.ambientLightEnabled) private var enabled = false
    @AppStorage(DefaultsKey.ambientLightThreshold) private var threshold = AmbientLightSupport.defaultThreshold
    @AppStorage(DefaultsKey.ambientLightDefaultAppearance) private var defaultMode = "dark"

    private var strings: AmbientLightStrings { FeatureStrings.ambientLight(l10n.language) }

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "sun.max.circle", title: strings.title, caption: strings.description) {
                Toggle(strings.title, isOn: $enabled)
                    .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 12) {
                Picker(strings.defaultMode, selection: $defaultMode) {
                    Text(strings.dark).tag("dark")
                    Text(strings.light).tag("light")
                }
                .pickerStyle(.menu)
                Text(String(format: strings.aboveTriggerFormat,
                            AmbientLightAppearance.sanitized(defaultMode) == .dark ? strings.light : strings.dark))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(strings.threshold).font(.callout)
                    Spacer()
                    Text(luxText(AmbientLightSupport.sanitizedThreshold(threshold)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Slider(value: steppedThreshold, in: 0...9, step: 1)
                            .accessibilityLabel(strings.threshold)
                            .accessibilityValue(luxText(AmbientLightSupport.sanitizedThreshold(threshold)))
                        HStack {
                            ForEach(1...10, id: \.self) { level in
                                Text(level.formatted(.number.locale(l10n.language.formattingLocale())))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if level < 10 { Spacer(minLength: 0) }
                            }
                        }
                        .padding(.horizontal, 8)
                        .accessibilityHidden(true)
                        // A live input meter shares the slider's non-linear scale.
                        ProgressView(value: service.lux.map(AmbientLightSupport.meterPosition) ?? 0)
                            .tint(.secondary)
                            .opacity(service.lux == nil ? 0.3 : 1)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(strings.currentLight)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(service.lux.map(luxText) ?? "—")
                            .font(.title3.monospacedDigit())
                    }
                    .frame(minWidth: 100)
                    .accessibilityElement(children: .combine)
                }
                Text(strings.scaleHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled {
                    if let statusText {
                        Text(statusText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(strings.behavior)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, settingsRowTextInset)
        }
        .onAppear {
            defaultMode = AmbientLightAppearance.sanitized(defaultMode).rawValue
            service.syncWithPreferences()
        }
        .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
        .onChange(of: threshold) { _, _ in service.syncWithPreferences() }
        .onChange(of: defaultMode) { _, _ in service.syncWithPreferences() }
    }

    private var steppedThreshold: Binding<Double> {
        // Keep existing custom lux values until the user chooses a preset.
        Binding(get: { Double(AmbientLightSupport.nearestStep(threshold)) },
                set: { threshold = AmbientLightSupport.thresholdSteps[min(9, max(0, Int($0.rounded())))] })
    }

    private func luxText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))
            .locale(l10n.language.formattingLocale())) + " lux"
    }

    private var statusText: String? {
        switch service.status {
        case .disabled, .monitoring: return nil
        case .waiting: return strings.waiting
        case .unavailable: return strings.unavailable
        case .appearanceUnavailable: return strings.appearanceUnavailable
        case .paused: return strings.paused
        }
    }
}
