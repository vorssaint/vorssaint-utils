// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One bar per logical core, grouped by core class (Performance, Efficiency…)
/// and wrapped to the available width.
struct CPUCoreMatrix: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var width: CGFloat = 280
    let usage: [Double?]

    var body: some View {
        let strings = FeatureStrings.cpuCores(l10n.language)
        let layout: [[CPUCoreSegment]] = CPUCoreLayout.rows(groups: CPUCoreTopology.groups(for: usage.count),
                                                            width: max(70, width - 16))
        let rowCount = CGFloat(layout.count)
        let height: CGFloat = rowCount * 88 + max(0, rowCount - 1) * 12 + 16
        GeometryReader { proxy in
            grid(layout, strings: strings)
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, value in width = value }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.title)
        .accessibilityHint(strings.hint)
    }

    private func grid(_ layout: [[CPUCoreSegment]], strings: CPUCoreFeatureStrings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(layout.indices, id: \.self) { row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(layout[row].indices, id: \.self) { index in
                        coreGroup(layout[row][index], strings: strings)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private func coreGroup(_ segment: CPUCoreSegment, strings: CPUCoreFeatureStrings) -> some View {
        let name = switch segment.group.name.lowercased() {
        case "super": strings.superCores
        case "performance": strings.performanceCores
        case "efficiency": strings.efficiencyCores
        default: segment.group.name
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(segment.group.indices, id: \.self) { index in
                    coreBar(index, width: segment.barWidth, strings: strings)
                }
            }
            Text("\(name) ×\(segment.group.indices.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(height: 22, alignment: .topLeading)
        }
        .frame(width: segment.width, alignment: .leading)
    }

    private func coreBar(_ index: Int, width: Double, strings: CPUCoreFeatureStrings) -> some View {
        let value: Double? = usage[index]
        let increasedContrast = contrast == .increased
        return GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.035))
                if let value {
                    Rectangle()
                        .fill(Color.primary.opacity(0.78))
                        .frame(height: proxy.size.height * value)
                } else {
                    Text("–").font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(Color.primary.opacity(increasedContrast ? 0.65 : 0.25),
                                  style: StrokeStyle(lineWidth: increasedContrast ? 1.5 : 0.75,
                                                     dash: value == nil ? [2, 2] : []))
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value)
        }
        .frame(width: width, height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: strings.coreFormat, index + 1))
        .accessibilityValue(value.map(MetricFormat.percent) ?? "–")
    }
}
