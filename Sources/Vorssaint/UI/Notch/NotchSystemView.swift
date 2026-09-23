// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchSystemView: View {
    let size: CGSize
    let select: (MetricDetailKind) -> Void
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Card: Identifiable {
        let kind: MetricDetailKind
        let title: String
        let symbol: String
        let value: String?
        var detail: String? = nil
        var level: Double? = nil
        /// Set when the reading itself is the news, so the meter says so
        /// without the person having to read the number.
        var wantsAttention = false
        var id: String { kind.rawValue }
    }

    private var cards: [Card] {
        let snapshot = monitor.snapshot
        var cards: [Card] = []
        if AppFeature.monitorCPU.isAvailable {
            cards.append(Card(kind: .cpu, title: l10n.s.cpuLabel, symbol: "cpu",
                              value: percent(snapshot.cpuUsage), level: snapshot.cpuUsage,
                              wantsAttention: isBusy(snapshot.cpuUsage)))
        }
        if AppFeature.monitorGPU.isAvailable {
            cards.append(Card(kind: .gpu, title: l10n.s.gpuLabel, symbol: "rectangle.connected.to.line.below",
                              value: percent(snapshot.gpuUsage), level: snapshot.gpuUsage,
                              wantsAttention: isBusy(snapshot.gpuUsage)))
        }
        if AppFeature.monitorMemory.isAvailable {
            let ratio = snapshot.memoryUsed.flatMap { used in
                snapshot.memoryTotal.flatMap { total in total > 0 ? Double(used) / Double(total) : nil }
            }
            cards.append(Card(kind: .memory, title: l10n.s.memorySection, symbol: "memorychip",
                              value: percent(ratio), level: ratio, wantsAttention: isBusy(ratio)))
        }
        if AppFeature.monitorPower.isAvailable, let power = snapshot.power, power.hasBattery {
            cards.append(Card(kind: .battery, title: l10n.s.batteryLabel,
                              symbol: power.externalConnected ? "battery.100percent.bolt" : "battery.100percent",
                              value: power.chargePercent.map { "\($0)%" },
                              level: power.chargePercent.map { Double($0) / 100 },
                              wantsAttention: !power.externalConnected && (power.chargePercent ?? 100) <= 20))
        }
        if AppFeature.monitorNetwork.isAvailable {
            cards.append(Card(kind: .network, title: l10n.s.networkSection, symbol: "network",
                              value: snapshot.netDownBytesPerSec.map { "↓ " + MetricFormat.bytesPerSec($0) },
                              detail: snapshot.netUpBytesPerSec.map { "↑ " + MetricFormat.bytesPerSec($0) }))
        }
        if AppFeature.monitorDisk.isAvailable {
            let disk = snapshot.disk?.devices.first(where: { $0.mountPath == "/" })
                ?? snapshot.disk?.devices.first(where: \.isInternal)
            cards.append(Card(kind: .disk, title: l10n.s.diskAvailable.localizedCapitalized, symbol: "internaldrive",
                              value: disk.map { MetricFormat.diskBytes($0.freeBytes) },
                              level: disk.map { 1 - $0.usedFraction },
                              wantsAttention: disk.map { 1 - $0.usedFraction < 0.1 } ?? false))
        }
        // The panel's power and fan sections, as cards opening the same details.
        if AppFeature.monitorPower.isAvailable {
            let power = snapshot.power
            cards.append(Card(kind: .power, title: l10n.s.powerSection, symbol: "powerplug.fill",
                              value: power?.systemWatts.map(MetricFormat.wattsCompact),
                              detail: power?.externalConnected == true ? power?.adapterWatts.map(MetricFormat.watts) : nil))
        }
        if AppFeature.fanControl.isAvailable, !snapshot.fanSpeeds.isEmpty {
            let strings = FeatureStrings.fanControl(l10n.language)
            cards.append(Card(kind: .fan, title: strings.menuBarTitle, symbol: "fanblades",
                              value: snapshot.fanSpeeds.first.map { String(format: strings.rpmFormat, Int($0.rounded())) }))
        }
        return cards
    }

    private func isBusy(_ level: Double?) -> Bool {
        guard let level, level.isFinite else { return false }
        return level >= 0.85
    }

    var body: some View {
        let cards = cards
        if cards.isEmpty {
            NotchEmptyView(symbol: "gauge.with.dots.needle.50percent", message: l10n.s.monitorUnavailable)
        } else {
            let inset = NotchLayout.systemHoverInset(width: size.width)
            let rows = NotchLayout.systemRowRanges(count: cards.count, width: size.width - inset * 2)
            let height = NotchLayout.railHeight(rows: rows.count, rowHeight: NotchLayout.systemCardHeight,
                                               spacing: NotchLayout.rowSpacing) + inset * 2
            Group {
                if height > size.height {
                    ScrollView {
                        grid(cards: cards, rows: rows).padding(inset)
                            .contentShape(Rectangle())
                    }
                } else {
                    grid(cards: cards, rows: rows).padding(inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func grid(cards: [Card], rows: [Range<Int>]) -> some View {
        VStack(spacing: NotchLayout.rowSpacing) {
            ForEach(rows, id: \.lowerBound) { row in
                HStack(spacing: NotchLayout.rowSpacing) {
                    ForEach(Array(cards[row])) { card in
                        cardButton(card)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func cardButton(_ card: Card) -> some View {
        Button { select(card.kind) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(card.title, systemImage: card.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(1)
                Text(card.value ?? "…")
                    .font(.system(size: card.detail == nil ? 22 : 15, weight: .medium, design: .rounded))
                    .monospacedDigit().contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.75)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: card.value)
                if let detail = card.detail {
                    Text(detail).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                } else if let level = card.level {
                    NotchMeter(value: level, tint: card.wantsAttention ? .orange : .white)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: NotchLayout.systemCardHeight)
            .modifier(NotchControlSurface(cornerRadius: 18))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { select(card.kind) }
        .accessibilityLabel(card.title)
        .accessibilityValue([card.value, card.detail].compactMap { $0 }.joined(separator: ", "))
    }

    private func percent(_ value: Double?) -> String? {
        value.flatMap { $0.isFinite ? "\(Int((min(1, max(0, $0)) * 100).rounded()))%" : nil }
    }
}
