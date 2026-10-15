// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ScreenshotPinSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.screenshotPinRoundedCorners) private var rounded = true

    var body: some View {
        let strings = ScreenshotPinStrings.localized(l10n.language)
        Section {
            Toggle(strings.rounded, isOn: $rounded)
        } header: {
            Text(strings.title)
        }
    }
}
