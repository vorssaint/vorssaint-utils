// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Emre Aribulan
import AppKit
import SwiftUI

struct WebsiteShortcutIcon: View {
    let image: NSImage
    let lightBackground: Bool
    let size: CGFloat

    var body: some View {
        Image(nsImage: image).resizable().scaledToFit()
            .padding(2)
            .frame(width: size, height: size)
            .background(
                lightBackground ? Color(white: 0.96) : Color(white: 0.12),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
