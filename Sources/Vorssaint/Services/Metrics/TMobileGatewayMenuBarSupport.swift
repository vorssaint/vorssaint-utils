// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Visual choices for the one connected-radio item. They never change which
/// radio is selected, the polling opt-in, or its complete spoken description.
struct TMobileGatewayMenuBarComponents: OptionSet {
    let rawValue: Int
    static let defaultsKey = "tMobileMenuBarComponents"
    static let technology = Self(rawValue: 1)
    static let bars = Self(rawValue: 2)
    static let bands = Self(rawValue: 4)
    static let all: Self = [.technology, .bars, .bands]

    static func sanitized(_ rawValue: Int) -> Self {
        (1...all.rawValue).contains(rawValue) ? Self(rawValue: rawValue) : .all
    }

    static var current: Self {
        sanitized(UserDefaults.standard.integer(forKey: defaultsKey))
    }

    func setting(_ component: Self, enabled: Bool) -> Self {
        let current = Self.sanitized(rawValue)
        let next = enabled ? current.union(component) : current.subtracting(component)
        // The main item checkmark owns hiding the entire item.
        return next.isEmpty ? current : Self.sanitized(next.rawValue)
    }

    func summary(_ strings: TMobileGatewayStrings) -> String {
        switch Self.sanitized(rawValue) {
        case .technology: return strings.summaryTechnology
        case .bars: return strings.summaryBars
        case .bands: return strings.summaryBands
        case [.technology, .bars]: return strings.summaryTechnologyBars
        case [.technology, .bands]: return strings.summaryTechnologyBands
        case [.bars, .bands]: return strings.summaryBarsBands
        default: return strings.summaryAll
        }
    }
}

enum TMobileGatewayMenuBarSupport {
    struct ConnectionDisplay: Equatable {
        let badge: String
        let bands: String
        let bars: Int?
        let accessibilityValue: String
    }

    static func connection(snapshot: TMobileGatewaySnapshot?, strings: TMobileGatewayStrings) -> ConnectionDisplay {
        guard let active = TMobileGatewayConnectedRadioSupport.select(from: snapshot) else {
            return .init(badge: "—", bands: "", bars: nil, accessibilityValue: strings.connectionUnavailable)
        }
        // T-Mobile's published network table classifies these NR bands as UC.
        // This is a band-based label, not a gateway-reported UC flag or speed.
        let ucBands: Set<String> = ["n2", "n25", "n41", "n258", "n260", "n261"]
        let uc = active.technology == .fiveG && snapshot?.roaming != true
            && active.bands.contains { ucBands.contains($0) }
        let badge = uc ? "5G UC" : active.technologyLabel
        let bands = String(active.bands.prefix(3).joined(separator: "+").prefix(24))
            + (active.bands.count > 3 ? "+…" : "")
        let bars = active.radio.bars.flatMap { (0...5).contains($0) ? $0 : nil }
        let spokenBars = bars.map { String(format: strings.spokenBarsFormat, String($0)) } ?? strings.signalUnavailable
        let spokenBands = active.bands.isEmpty ? strings.bandNotReported
            : String(format: strings.reportedBandsFormat, active.bands.joined(separator: ", "))
        let spoken = String(format: strings.connectionSpokenFormat, badge, spokenBands, spokenBars)
        return .init(badge: badge, bands: bands, bars: bars,
                     accessibilityValue: spoken + (uc ? strings.ucInferred : ""))
    }

    /// The same decision serves the runtime and tests. Merely opening settings
    /// or the preview never requests gateway data.
    static func needsPolling(networkAvailable: Bool, panelVisible: Bool,
                             panelEnabled: Bool, menuBarEnabled: Bool) -> Bool {
        networkAvailable && ((panelVisible && panelEnabled) || menuBarEnabled)
    }
}
