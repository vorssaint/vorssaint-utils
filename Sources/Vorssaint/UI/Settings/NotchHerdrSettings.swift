// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The herdr island section's options. v1 has no toggles of its own: the
/// section shows while the herdr binary is installed, and the text says
/// where to get it otherwise.
struct NotchHerdrSettingsControls: View {
    @ObservedObject private var l10n = L10n.shared

    private var strings: HerdrFeatureStrings { FeatureStrings.herdr(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(strings.hubDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !HerdrStatusService.shared.isInstalled {
                Text(strings.installHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
