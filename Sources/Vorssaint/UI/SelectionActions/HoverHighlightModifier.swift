// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A subtle background that appears while the pointer is over the view —
/// used on every row and button in Selection Actions (the bar and its
/// Settings list) so hovering any option highlights it.
private struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 8
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = 8) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}

/// A tooltip that appears almost immediately on hover, instead of riding
/// AppKit's system tooltip (`.help()`), whose ~1.5s delay and frame tracking
/// both get confused inside a list that re-renders on every `@AppStorage`
/// change — which reads as the tooltip showing late or not at all. Meant for
/// a small number of short, primary-information hints (the Selection
/// Actions ⓘ), not a blanket replacement for `.help()` elsewhere.
///
/// Presented as a `.popover` rather than a plain `.overlay`: this row lives
/// inside a `Form`/`.formStyle(.grouped)`, which macOS backs with a `List`
/// that clips each row's content to its own bounds, so an overlay bubble
/// trying to float above the row was being cut down to a sliver of its
/// border. A popover renders in its own window layer and isn't clipped by
/// the row — the same approach the gear-icon settings panel next to this
/// already uses.
private struct FastTooltip: ViewModifier {
    let text: String
    @State private var hovering = false
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                hovering = isHovering
                if isHovering {
                    // No capture list: `hovering` must be re-read live when
                    // this fires, not frozen at the value it had the instant
                    // this was scheduled (which is always true) — otherwise
                    // the pointer leaving during the delay is never noticed.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        if hovering { showing = true }
                    }
                } else {
                    showing = false
                }
            }
            .popover(isPresented: $showing, arrowEdge: .top) {
                Text(text)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 220)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
    }
}

extension View {
    func fastTooltip(_ text: String) -> some View {
        modifier(FastTooltip(text: text))
    }
}
