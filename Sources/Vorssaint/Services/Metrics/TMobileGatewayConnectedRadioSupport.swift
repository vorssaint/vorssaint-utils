// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A conservative projection of the gateway's latest status, not a second
/// connection probe. In NSA mode LTE may remain an anchor while 5G is selected
/// for the compact indicator; both radios remain available in the details.
struct TMobileGatewayConnectedRadio: Equatable {
    enum Technology: Equatable {
        case lte, fiveG

        var label: String { self == .fiveG ? "5G" : "LTE" }
    }

    let technology: Technology
    let radio: TMobileRadioSignal

    var technologyLabel: String { technology.label }
    var bands: [String] { radio.bands }
}

enum TMobileGatewayConnectedRadioSupport {
    /// The allowlisted status response has one generic registration value and
    /// no per-radio connected flag or measurement timestamp. A radio object,
    /// bars, band list or cell identifier alone may survive a disconnected
    /// state, so none of them establishes the active connection here. Only the
    /// recognized registered state plus valid RSRP selects a reported radio.
    /// Missing or unfamiliar registration values remain unknown.
    ///
    /// 5G is preferred when its serving signal is reported. This does not
    /// imply an exclusive radio connection or identify a primary component
    /// carrier: all selected-radio bands are preserved in gateway order, and
    /// a missing band list is never reconstructed from signal measurements.
    static func select(from snapshot: TMobileGatewaySnapshot?) -> TMobileGatewayConnectedRadio? {
        guard let snapshot,
              snapshot.registration?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "registered"
        else { return nil }

        if let radio = snapshot.fiveG, hasServingSignal(radio) {
            return TMobileGatewayConnectedRadio(technology: .fiveG, radio: radio)
        }
        if let radio = snapshot.lte, hasServingSignal(radio) {
            return TMobileGatewayConnectedRadio(technology: .lte, radio: radio)
        }
        return nil
    }

    private static func hasServingSignal(_ radio: TMobileRadioSignal) -> Bool {
        guard let rsrp = radio.rsrp else { return false }
        return rsrp.isFinite && (-160 ... -20).contains(rsrp)
    }
}
