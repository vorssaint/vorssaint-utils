// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Apple's own Liquid Glass where the system has it, the classic material
/// where it does not or where Reduce Transparency is on. One place, so every
/// floating surface gets the same real glass, not a blurred imitation.
struct TrueGlass<S: Shape>: ViewModifier {
    let shape: S
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            content.trueGlass(in: shape)
        }
#else
        content.trueGlass(in: shape)
#endif
    }
}

extension View {
    /// Liquid Glass behind this view in `shape`.
    func trueGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(TrueGlass(shape: shape, interactive: interactive))
    }
}
