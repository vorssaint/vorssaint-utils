// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Only available, normalized values reach the dropdown. Keeping the projection
/// independent of SwiftUI makes absence and legitimate zero readings testable.
enum TMobileGatewayRadioPresentation {
    enum Field: String, CaseIterable {
        case bars, bands, rsrp, rsrq, rssi, sinr, antenna, bandwidth, channel, pci, tac, cqi, gNodeBID, eNodeBID, cellID, ecgi, supportedBands
    }

    struct Row: Identifiable, Equatable {
        let id: Field
        let label: String
        let value: String
        let quality: TMobileSignalQuality
        let qualityLabel: String?

        init(id: Field, label: String, value: String, quality: TMobileSignalQuality, strings: TMobileGatewayStrings) {
            self.id = id; self.label = label; self.value = value; self.quality = quality
            let rating = quality.label(strings)
            qualityLabel = quality == .unknown ? nil
                : id == .bars ? String(format: strings.rsrpRatingFormat, rating) : rating
        }

        var accessibilityValue: String {
            "\(label), \(value)" + (qualityLabel.map { ", \($0)" } ?? "")
        }
    }

    struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        let radio: TMobileRadioSignal
        let rows: [Row]
    }

    static func sections(_ snapshot: TMobileGatewaySnapshot?, strings: TMobileGatewayStrings) -> [Section] {
        guard let snapshot else { return [] }
        return [("fiveG", "5G", snapshot.fiveG, true), ("lte", "LTE / 4G", snapshot.lte, false)]
            .compactMap { id, title, radio, isFiveG in
                guard let radio else { return nil }
                let rows = rows(radio, isFiveG: isFiveG, strings: strings)
                guard !rows.isEmpty else { return nil }
                return Section(id: id, title: title, radio: radio, rows: rows)
            }
    }

    static func rows(_ radio: TMobileRadioSignal, isFiveG: Bool, strings: TMobileGatewayStrings) -> [Row] {
        var result: [Row] = []
        func append(_ id: Field, _ label: String, _ value: String?, quality: TMobileSignalQuality = .unknown) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result.append(Row(id: id, label: label, value: value, quality: quality, strings: strings))
        }
        if let bars = radio.bars, (0...5).contains(bars) {
            // The tint is RSRP placement guidance, not a reclassification of the
            // gateway's independent bar count. Without RSRP it remains neutral.
            append(.bars, strings.signalBars, "\(bars) / 5",
                   quality: TMobileGatewayDiagnostics.quality(for: radio.rsrp, metric: .rsrp))
        }
        let bands = radio.bands.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !bands.isEmpty { append(.bands, strings.bands, bands.joined(separator: ", ")) }
        for metric in TMobileSignalMetric.allCases {
            if let row = measurementRow(radio, metric: metric, strings: strings) { result.append(row) }
        }
        append(.antenna, strings.antenna, radio.antenna)
        if let bandwidth = radio.bandwidthMHz, bandwidth.isFinite, bandwidth > 0 {
            append(.bandwidth, strings.bandwidth, formatted(bandwidth, unit: "MHz"))
        }
        append(.channel, isFiveG ? strings.channelNR : strings.channelLTE, radio.channel.map(String.init))
        append(.pci, "PCI", radio.physicalCellID.map(String.init))
        append(.tac, "TAC", radio.trackingAreaCode.map(String.init))
        append(.cqi, "CQI", radio.cqi.map(String.init))
        if isFiveG { append(.gNodeBID, "gNB ID", radio.gNodeBID.map(String.init)) }
        else { append(.eNodeBID, "eNB ID", radio.eNodeBID.map(String.init)) }
        append(.cellID, strings.cellID, radio.cellID.map(String.init))
        append(.ecgi, "ECGI", radio.ecgi)
        if let inventory = radio.supportedBands, !inventory.isEmpty {
            append(.supportedBands, strings.supportedBands, inventory.joined(separator: ", "))
        }
        return result
    }

    static func measurementRow(_ radio: TMobileRadioSignal, metric: TMobileSignalMetric,
                               strings: TMobileGatewayStrings) -> Row? {
        let value: Double?
        let field: Field
        switch metric {
        case .rsrp: value = radio.rsrp; field = .rsrp
        case .rsrq: value = radio.rsrq; field = .rsrq
        case .rssi: value = radio.rssi; field = .rssi
        case .sinr: value = radio.sinr; field = .sinr
        }
        guard let value, value.isFinite else { return nil }
        let quality = TMobileGatewayDiagnostics.quality(for: value, metric: metric)
        // Diagnostics supplies the same sanity limits for graded metrics.
        // RSSI has no standalone rating, but its normalized range is still known.
        guard metric == .rssi ? (-160...0).contains(value) : quality != .unknown else { return nil }
        return Row(id: field, label: metric.label, value: formatted(value, unit: metric.unit), quality: quality,
                   strings: strings)
    }

    private static func formatted(_ value: Double, unit: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }
}
