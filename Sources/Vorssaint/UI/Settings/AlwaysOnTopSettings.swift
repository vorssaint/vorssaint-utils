// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AlwaysOnTopSettings: View {
    var body: some View {
        Form {
            Text(FeatureStrings.alwaysOnTop(L10n.shared.language).title)
        }
    }
}
