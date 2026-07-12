// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Panel section with one brightness slider per adjustable display. Values
/// refresh whenever the section appears, so changes made with the keyboard,
/// in System Settings or on the monitor itself are picked up.
struct BrightnessSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    var collapsible = true

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }

    var body: some View {
        PanelSection(.brightness, title: strings.pageTitle, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 10) {
                if service.displays.isEmpty {
                    Text(strings.noDisplays)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.displays) { display in
                        row(display)
                    }
                }
            }
            .panelCard()
            .onAppear { service.refresh() }
        }
    }

    private func row(_ display: BrightnessDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(display.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(Int((display.brightness * 100).rounded()))%")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: brightnessBinding(display), in: 0...1)
                .controlSize(.small)
                .accessibilityLabel(display.name)
        }
    }

    private func brightnessBinding(_ display: BrightnessDisplay) -> Binding<Double> {
        Binding(get: { display.brightness },
                set: { service.setBrightness($0, for: display.id) })
    }
}
