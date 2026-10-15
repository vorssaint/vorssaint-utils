// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// System readings in the expanded header, in the muted white of its resting
/// marks. As many fit as the room allows; orange only for a reading that is
/// itself the news. Without a reading to show, the header keeps its `…`.
struct NotchSystemReadoutView: View {
    /// Whether an empty readout leaves the header's resting `…` in its place.
    var showsEllipsisWhenEmpty = true
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let input = NotchSystemReadout.input(monitor.snapshot)
        let available = NotchSystemReadout.availableKinds()
        let all = NotchSystemReadout.readings(input, available: available)
        if all.isEmpty {
            if showsEllipsisWhenEmpty {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }
        } else {
            // Fewer readings where the header is narrower, as beside a camera.
            ViewThatFits(in: .horizontal) {
                row(all)
                row(NotchSystemReadout.readings(input, available: available, limit: 3))
                row(NotchSystemReadout.readings(input, available: available, limit: 2))
                row(NotchSystemReadout.readings(input, available: available, limit: 1))
            }
            .frame(height: 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(FeatureStrings.notch(l10n.language).systemReadout)
            .accessibilityValue(all.map { "\(title($0.kind)) \($0.value)" }.joined(separator: ", "))
        }
    }

    private func row(_ readings: [NotchSystemReadout.Reading]) -> some View {
        HStack(spacing: 9) {
            ForEach(readings) { reading in
                HStack(spacing: 3) {
                    Image(systemName: reading.symbol)
                        .font(.system(size: 9, weight: .semibold))
                    Text(reading.value)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: reading.value)
                }
                .foregroundStyle(reading.attention ? Color.orange : Color.white.opacity(0.6))
                .help(title(reading.kind))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func title(_ kind: NotchSystemReadout.Kind) -> String {
        switch kind {
        case .battery: return l10n.s.batteryLabel
        case .cpu: return l10n.s.cpuLabel
        case .gpu: return l10n.s.gpuLabel
        case .memory: return l10n.s.memorySection
        }
    }
}
