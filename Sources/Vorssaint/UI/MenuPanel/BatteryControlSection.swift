// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The battery charge limit, right in the menu panel: the same interactive
/// body as the settings card, dressed as a panel section.
struct BatteryControlSection: View {
    @ObservedObject private var l10n = L10n.shared
    var collapsible = true

    private var strings: BatteryControlFeatureStrings {
        BatteryControlFeatureStrings.batteryControl(l10n.language)
    }

    var body: some View {
        PanelSection(.chargeLimit, title: strings.title, collapsible: collapsible) {
            BatteryChargeLimitContent(style: .panel)
                .panelCard()
        }
    }
}
