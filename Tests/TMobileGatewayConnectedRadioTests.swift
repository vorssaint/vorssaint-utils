// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TMobileGatewayConnectedRadioTests {
    static func run(_ suite: TestSuite) {
        let lte = radio(bands: ["b66", "b2"], rsrp: -92)
        let fiveG = radio(bands: ["n41"], rsrp: -97)
        let mixed = snapshot(registration: "registered", lte: lte, fiveG: fiveG)
        let selected = TMobileGatewayConnectedRadioSupport.select(from: mixed)
        suite.expect(selected?.technology == .fiveG && selected?.technologyLabel == "5G"
                     && selected?.radio == fiveG && selected?.bands == ["n41"],
                     "a registered NSA snapshot selects reported 5G while retaining LTE in the snapshot")
        suite.expect(mixed.lte == lte && mixed.fiveG == fiveG,
                     "connected-radio projection does not alter either radio's details")

        let lteOnly = TMobileGatewayConnectedRadioSupport.select(from:
            snapshot(registration: "registered", lte: lte))
        suite.expect(lteOnly?.technology == .lte && lteOnly?.technologyLabel == "LTE"
                     && lteOnly?.bands == ["b66", "b2"],
                     "a registered LTE-only connection preserves only its reported bands in gateway order")
        let nrOnly = TMobileGatewayConnectedRadioSupport.select(from:
            snapshot(registration: "registered", fiveG: fiveG))
        suite.expect(nrOnly?.technology == .fiveG && nrOnly?.bands == ["n41"],
                     "5G selection does not require an LTE anchor in the status response")

        for registration: String? in [nil, "", "unknown", "unregistered", "not registered", "searching",
                                     "denied", "disconnected", "not_registered", "unregistered roaming", "5"] {
            suite.expect(TMobileGatewayConnectedRadioSupport.select(from:
                snapshot(registration: registration, lte: lte, fiveG: fiveG)) == nil,
                         "missing, unfamiliar and non-registered states do not turn residual radio data into a connection")
        }
        suite.expect(TMobileGatewayConnectedRadioSupport.select(from: nil) == nil,
                     "an absent snapshot has no connected radio")
        suite.expect(TMobileGatewayConnectedRadioSupport.select(from:
            snapshot(registration: " ReGiStErEd \n", fiveG: fiveG))?.technology == .fiveG,
                     "the recognized registration value tolerates casing and surrounding whitespace")

        let emptyBand = radio(bands: [], rsrp: -100)
        suite.expect(TMobileGatewayConnectedRadioSupport.select(from:
            snapshot(registration: "registered", lte: lte, fiveG: emptyBand))?.bands == [],
                     "a valid 5G signal selects 5G without inventing a missing band")
        let multiBand = radio(bands: ["n71", "n41"], rsrp: -100)
        suite.expect(TMobileGatewayConnectedRadioSupport.select(from:
            snapshot(registration: "registered", fiveG: multiBand))?.bands == ["n71", "n41"],
                     "multiple reported 5G bands remain ordered rather than inventing one primary carrier")

        let metadataOnly = TMobileRadioSignal(bars: 5, bands: ["n41"], rsrp: nil,
                                             rsrq: -10, rssi: -70, sinr: 20,
                                             cellID: 12345, bandwidthMHz: 100, channel: 520000,
                                             physicalCellID: 100, trackingAreaCode: 1, gNodeBID: 42)
        suite.expect(TMobileGatewayConnectedRadioSupport.select(from:
            snapshot(registration: "registered", lte: lte, fiveG: metadataOnly))?.technology == .lte,
                     "5G bars, bands and metadata without valid RSRP do not override a reported LTE signal")
        suite.expect(TMobileGatewayConnectedRadioSupport.select(from:
            snapshot(registration: "registered", fiveG: metadataOnly)) == nil,
                     "registration alone plus residual metadata does not establish a serving radio")
        suite.expect(TMobileGatewayConnectedRadioSupport.select(from:
            snapshot(registration: "registered")) == nil,
                     "registered without any serving measurement remains unavailable")

        for invalid in [0.0, 99, -161, -19, .nan, .infinity, -.infinity] {
            suite.expect(TMobileGatewayConnectedRadioSupport.select(from:
                snapshot(registration: "registered", lte: lte,
                         fiveG: radio(bands: ["n41"], rsrp: invalid)))?.technology == .lte,
                         "invalid and sentinel 5G RSRP values fall back to a valid LTE serving signal")
            suite.expect(TMobileGatewayConnectedRadioSupport.select(from:
                snapshot(registration: "registered", lte: radio(bands: ["b66"], rsrp: invalid))) == nil,
                         "invalid and sentinel LTE RSRP values do not establish a connection")
        }
        for boundary in [-160.0, -20] {
            suite.expect(TMobileGatewayConnectedRadioSupport.select(from:
                snapshot(registration: "registered", fiveG: radio(bands: ["n41"], rsrp: boundary)))?.technology == .fiveG,
                         "the parser's inclusive real-signal RSRP boundaries remain usable")
        }
        let zeroBars = radio(bars: 0, bands: ["n71"], rsrp: -130)
        suite.expect(TMobileGatewayConnectedRadioSupport.select(from:
            snapshot(registration: "registered", fiveG: zeroBars))?.radio.bars == 0,
                     "zero bars do not erase a weak but valid registered serving measurement")

        let parsed = try? TMobileGatewaySupport.parse(Data(#"{"signal":{"generic":{"registration":"registered"},"4g":{"bands":["b66"],"rsrp":-98},"5g":{"bands":["n41"],"rsrp":0,"bars":0}}}"#.utf8))
        suite.expect(TMobileGatewayConnectedRadioSupport.select(from: parsed)?.technology == .lte,
                     "production parsing rejects zero RSRP before connected-radio fallback")
        let disconnected = try? TMobileGatewaySupport.parse(Data(#"{"signal":{"generic":{"registration":"searching"},"5g":{"bands":["n41"],"rsrp":-95}}}"#.utf8))
        suite.expect(TMobileGatewayConnectedRadioSupport.select(from: disconnected) == nil,
                     "production parsing retains diagnostic readings without claiming a searching gateway is connected")
    }

    private static func radio(bars: Int? = 3, bands: [String], rsrp: Double?) -> TMobileRadioSignal {
        TMobileRadioSignal(bars: bars, bands: bands, rsrp: rsrp, rsrq: -10, rssi: -65, sinr: 12)
    }

    private static func snapshot(registration: String?, lte: TMobileRadioSignal? = nil,
                                 fiveG: TMobileRadioSignal? = nil) -> TMobileGatewaySnapshot {
        TMobileGatewaySnapshot(model: nil, firmware: nil, uptime: nil, registration: registration,
                               roaming: false, lte: lte, fiveG: fiveG)
    }
}
