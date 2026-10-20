// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Applied inside each hosted root so existing AppKit controller types stay intact.
/// Observing the language also updates already-open panels when the picker changes.
struct AppLocalizedView<Content: View>: View {
    @ObservedObject private var l10n = L10n.shared
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environment(\.layoutDirection, l10n.language.isRightToLeft ? .rightToLeft : .leftToRight)
            .environment(\.locale, l10n.language.formattingLocale())
    }
}
