// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A single keyboard key drawn like a physical keycap. Used across Settings and
/// onboarding to show shortcuts such as ⌘X / ⌘V.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 20, minHeight: 22)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
    }
}

/// A row of keycaps for a shortcut, e.g. ["⌘", "X"].
struct ShortcutCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(label: key)
            }
        }
    }
}

/// Translucent HUD material behind floating panels (the shelf, the switcher, the
/// cut-feedback HUD). Mirrors the switcher's backdrop so every floating surface
/// matches.
///
/// The corner radius rounds the effect view's own layer, which matters for the
/// behind-window blur: SwiftUI's `.clipShape` rounds the drawn content but does
/// not clip an `NSVisualEffectView`'s behind-window material, so the blur (and
/// the borderless window's shadow, computed from it) keeps the full rectangular
/// bounds. Against a contrasty desktop that rectangle reads as a faint extra
/// outline just outside the rounded card, and whether it shows depends on what
/// is behind the window, which is why it looks intermittent. Clipping the layer
/// to the same radius as the card removes it. Pass the card's corner radius.
struct HUDBackdrop: NSViewRepresentable {
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
