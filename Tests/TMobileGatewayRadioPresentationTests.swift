// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TMobileGatewayRadioPresentationTests {
    static func run(_ suite: TestSuite) {
        let empty = TMobileRadioSignal(bars: nil, bands: [], rsrp: nil, rsrq: nil, rssi: nil, sinr: nil)
        func snapshot(lte: TMobileRadioSignal? = nil, fiveG: TMobileRadioSignal? = nil) -> TMobileGatewaySnapshot {
            .init(model: nil, firmware: nil, uptime: nil, registration: nil, roaming: nil, lte: lte, fiveG: fiveG)
        }
        suite.expect(TMobileGatewayRadioPresentation.sections(nil, strings: TMobileGatewayStrings.localized(.enUS)).isEmpty
                     && TMobileGatewayRadioPresentation.sections(snapshot(), strings: TMobileGatewayStrings.localized(.enUS)).isEmpty,
                     "missing snapshots and absent radios create no placeholder sections")
        suite.expect(TMobileGatewayRadioPresentation.sections(snapshot(lte: empty, fiveG: empty), strings: TMobileGatewayStrings.localized(.enUS)).isEmpty,
                     "radio objects without available fields create no empty LTE or 5G section")

        let full = TMobileRadioSignal(bars: 4, bands: ["n41"], rsrp: -95, rsrq: -10, rssi: -65, sinr: 13,
                                      cellID: 1234, antenna: "Internal", bandwidthMHz: 100, channel: 520_000,
                                      physicalCellID: 12, trackingAreaCode: 34, cqi: 15, gNodeBID: 56,
                                      ecgi: "001-01-1234", supportedBands: ["n25", "n41"])
        let fullRows = TMobileGatewayRadioPresentation.rows(full, isFiveG: true, strings: TMobileGatewayStrings.localized(.enUS))
        suite.expect(Set(fullRows.map(\.id)) == Set(TMobileGatewayRadioPresentation.Field.allCases.filter { $0 != .eNodeBID }),
                     "a complete NR fixture exposes every supported radio field exactly once")
        suite.expect(fullRows.count == Set(fullRows.map(\.id)).count,
                     "each available radio field has one stable row identity")
        suite.expect(fullRows.first(where: { $0.id == .rsrp })?.value.hasSuffix("dBm") == true
                     && fullRows.first(where: { $0.id == .rsrq })?.value.hasSuffix("dB") == true
                     && fullRows.first(where: { $0.id == .bandwidth })?.value.hasSuffix("MHz") == true,
                     "radio power, quality and bandwidth keep their distinct units")
        let nrOnly = TMobileGatewayRadioPresentation.sections(snapshot(fiveG: full), strings: TMobileGatewayStrings.localized(.enUS))
        suite.expect(nrOnly.map(\.id) == ["fiveG"] && nrOnly.first?.title == "5G",
                     "an NR-only fixture hides the entire LTE section")
        let lteOnly = TMobileGatewayRadioPresentation.sections(snapshot(lte: full), strings: TMobileGatewayStrings.localized(.enUS))
        suite.expect(lteOnly.map(\.id) == ["lte"]
                     && lteOnly.first?.rows.contains(where: { $0.id == .gNodeBID }) == false,
                     "an LTE-only fixture hides 5G and omits inapplicable gNB rows")
        let explicitLTE = TMobileRadioSignal(bars: nil, bands: [], rsrp: nil, rsrq: nil, rssi: nil, sinr: nil, eNodeBID: 123)
        suite.expect(TMobileGatewayRadioPresentation.rows(explicitLTE, isFiveG: false, strings: TMobileGatewayStrings.localized(.enUS)).map(\.id) == [.eNodeBID],
                     "an explicitly reported LTE node ID creates one available row")
        suite.expect(fullRows.first(where: { $0.id == .supportedBands })?.label.contains("capability") == true,
                     "supported band inventory is explicitly distinguished from connected bands")
        suite.expect(TMobileGatewayRadioPresentation.sections(snapshot(lte: full, fiveG: full), strings: TMobileGatewayStrings.localized(.enUS)).map(\.id)
                     == ["fiveG", "lte"], "both reported radios keep a stable display order")

        let sparse = TMobileRadioSignal(bars: nil, bands: ["n41"], rsrp: -100, rsrq: nil, rssi: nil, sinr: nil)
        let sparseRows = TMobileGatewayRadioPresentation.rows(sparse, isFiveG: true, strings: TMobileGatewayStrings.localized(.enUS))
        suite.expect(sparseRows.map(\.id) == [.bands, .rsrp],
                     "unreported metrics, antenna, channels and cell identifiers are omitted")
        suite.expect(sparseRows.allSatisfy { !$0.value.contains("Not reported") && !$0.value.contains("Not applicable") },
                     "available rows never manufacture unsupported placeholders")
        let zero = TMobileRadioSignal(bars: 0, bands: [], rsrp: nil, rsrq: 0, rssi: 0, sinr: 0,
                                      cellID: 0, channel: 0, physicalCellID: 0, trackingAreaCode: 0, cqi: 0, gNodeBID: 0)
        suite.expect(Set(TMobileGatewayRadioPresentation.rows(zero, isFiveG: true, strings: TMobileGatewayStrings.localized(.enUS)).map(\.id))
                     == [.bars, .rsrq, .rssi, .sinr, .channel, .pci, .tac, .cqi, .gNodeBID, .cellID],
                     "real zero signal bars, quality and identifiers remain visible rather than treated as nil")
        let invalid = TMobileRadioSignal(bars: 6, bands: ["", " "], rsrp: 0, rsrq: .nan, rssi: .infinity,
                                         sinr: .infinity, antenna: " ", bandwidthMHz: 0)
        suite.expect(TMobileGatewayRadioPresentation.rows(invalid, isFiveG: true, strings: TMobileGatewayStrings.localized(.enUS)).isEmpty,
                     "nonfinite metrics, impossible RSRP, empty text and invalid bars create no available rows")

        for (metric, values, expected) in [
            (TMobileSignalMetric.rsrp, [-105.1, -105, -95.1, -95, -85.1, -85],
             [TMobileSignalQuality.poor, .fair, .fair, .good, .good, .excellent]),
            (.rsrq, [-15.1, -15, -10.1, -10, -7.1, -7], [.poor, .fair, .fair, .good, .good, .excellent]),
            (.sinr, [-0.1, 0, 12.9, 13, 19.9, 20], [.poor, .fair, .fair, .good, .good, .excellent])
        ] {
            for (value, quality) in zip(values, expected) {
                let signal = TMobileRadioSignal(bars: nil, bands: [],
                                                rsrp: metric == .rsrp ? value : nil,
                                                rsrq: metric == .rsrq ? value : nil,
                                                rssi: nil, sinr: metric == .sinr ? value : nil)
                let row = TMobileGatewayRadioPresentation.measurementRow(signal, metric: metric, strings: TMobileGatewayStrings.localized(.enUS))
                suite.expect(row?.quality == quality && row?.qualityLabel == quality.label(TMobileGatewayStrings.localized(.enUS)),
                             "\(metric.label) presentation preserves Diagnostics quality at boundary \(value)")
            }
        }
        let rssi = TMobileGatewayRadioPresentation.measurementRow(full, metric: .rssi, strings: TMobileGatewayStrings.localized(.enUS))
        suite.expect(rssi?.quality == .unknown && rssi?.qualityLabel == nil,
                     "RSSI stays neutral without an unsound total-power quality grade")
        let weakWithFiveBars = TMobileRadioSignal(bars: 5, bands: [], rsrp: -118, rsrq: nil, rssi: nil, sinr: nil)
        let bars = TMobileGatewayRadioPresentation.rows(weakWithFiveBars, isFiveG: true, strings: TMobileGatewayStrings.localized(.enUS)).first { $0.id == .bars }
        suite.expect(bars?.value == "5 / 5" && bars?.quality == .poor && bars?.qualityLabel == "Poor RSRP",
                     "bar tint follows RSRP guidance without changing the gateway's independent bar count")
        suite.expect(bars?.accessibilityValue.contains("5 / 5") == true
                     && bars?.accessibilityValue.contains("Poor RSRP") == true,
                     "bar count and the RSRP basis of its color are explicit to assistive technology")
        let barsWithoutRSRP = TMobileRadioSignal(bars: 2, bands: [], rsrp: nil, rsrq: nil, rssi: nil, sinr: nil)
        let neutral = TMobileGatewayRadioPresentation.rows(barsWithoutRSRP, isFiveG: true, strings: TMobileGatewayStrings.localized(.enUS)).first
        suite.expect(neutral?.id == .bars && neutral?.quality == .unknown && neutral?.qualityLabel == nil,
                     "reported bars without a power reading remain visible and neutral")
    }
}
