// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Keeps empty surface taps in the host without taking button taps from child views.
struct NotchSurfaceTapGesture: ViewModifier {
    func body(content: Content) -> some View {
        content.simultaneousGesture(TapGesture().onEnded {})
    }
}
