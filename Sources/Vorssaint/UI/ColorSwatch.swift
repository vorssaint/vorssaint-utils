// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The small square a row shows before a color value, in Clipboard History and
/// in the Command Bar's color answers. The hairline border keeps white, black
/// and translucent colors visible on any background; the value beside it
/// already says the color, so it is hidden from VoiceOver.
struct ColorSwatch: View {
    let color: ColorValue
    var size: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
