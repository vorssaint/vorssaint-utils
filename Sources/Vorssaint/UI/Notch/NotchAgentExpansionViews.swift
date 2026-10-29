// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchAgentExpandedScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NotchAgentExpandedTotals: View {
    let title: String
    let totals: AgentTotals
    let byCost: Bool
    let text: NotchAgentStrings
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(tint ?? .white.opacity(0.55)).frame(width: 6, height: 6)
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text((totals.unpriced == 0 ? "" : "≥ ") + AgentFormat.cost(totals.cost))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                NotchAgentExpandedLine(label: "Requests", value: "\(totals.requests)")
                NotchAgentExpandedLine(label: "Tokens", value: AgentFormat.tokens(totals.tokens.total))
            }
            Text("Input \(AgentFormat.tokens(totals.tokens.prompt)) · Output \(AgentFormat.tokens(totals.tokens.output)) · Cache \(AgentFormat.percent(totals.tokens.cacheHitRate ?? 0))")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 3)
    }
}

struct NotchAgentExpandedLine: View {
    let label: String
    let value: String
    var tint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.9))
        }
    }
}

struct NotchAgentExpandedShareRow: View {
    let share: AgentShare
    let byCost: Bool
    let peak: Double
    let text: NotchAgentStrings

    var body: some View {
        HStack(spacing: 8) {
            Text(share.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Capsule(style: .continuous)
                .fill((share.provider?.tint ?? .white).opacity(0.85))
                .frame(width: max(4, 96 * share.totals.weight(byCost: byCost) / peak), height: 5)
                .frame(width: 96, alignment: .leading)
            Text(byCost ? AgentFormat.cost(share.totals.cost) : AgentFormat.tokens(share.totals.tokens.total))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
        }
        .padding(9)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help([share.name, text.tokens(AgentFormat.tokens(share.totals.tokens.total)),
               AgentFormat.cost(share.totals.cost)].joined(separator: " · "))
    }
}
