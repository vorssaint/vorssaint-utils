// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Renders the floating KeyCastr-style keystroke overlay in either the
/// "Svelte" box theme (with the 4-modifier bottom bar) or the "Keycaps" pill theme.
struct KeystrokeOverlayView: View {
    @ObservedObject var service: KeystrokeOverlayService

    var body: some View {
        Group {
            switch service.style {
            case .svelte:
                SvelteKeystrokeOverlayBox(
                    text: service.svelteText,
                    activeModifiers: service.activeModifiers,
                    size: service.size
                )
            case .keycaps:
                KeycapsKeystrokeOverlayRow(
                    items: service.items,
                    size: service.size
                )
            }
        }
        .padding(8)
    }
}

private struct SvelteKeystrokeOverlayBox: View {
    let text: String
    let activeModifiers: GlobalShortcutModifiers
    let size: KeystrokeOverlaySize

    var body: some View {
        let boxSize = size.svelteBoxSize
        let barHeight = size.svelteModifierBarHeight

        VStack(spacing: 0) {
            ZStack {
                Text(text)
                    .font(.system(size: size.svelteKeyFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.32)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(Array(KeystrokeOverlaySupport.svelteModifierCells.enumerated()), id: \.offset) { index, cell in
                    let isHighlighted = activeModifiers.contains(cell.modifier)
                    ZStack {
                        if isHighlighted {
                            Color.white.opacity(0.16)
                        }
                        Text(cell.symbol)
                            .font(.system(size: size.svelteModifierFontSize,
                                          weight: isHighlighted ? .bold : .medium,
                                          design: .rounded))
                            .foregroundStyle(Color.white.opacity(isHighlighted ? 1.0 : 0.42))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if index < KeystrokeOverlaySupport.svelteModifierCells.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 1)
                    }
                }
            }
            .frame(height: barHeight)
        }
        .frame(width: boxSize.width, height: boxSize.height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.85))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        .animation(.easeOut(duration: 0.1), value: activeModifiers)
    }
}

private struct KeycapsKeystrokeOverlayRow: View {
    let items: [KeystrokeOverlayItem]
    let size: KeystrokeOverlaySize

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                KeystrokeItemPill(item: item, size: size)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(.easeOut(duration: 0.14), value: items)
    }
}

private struct KeystrokeItemPill: View {
    let item: KeystrokeOverlayItem
    let size: KeystrokeOverlaySize

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(item.caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(minWidth: size.minCapDimension, minHeight: size.minCapDimension)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.09))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    )
            }
            if item.repeatCount > 1 {
                Text("×\(item.repeatCount)")
                    .font(.system(size: max(11, size.fontSize * 0.65), weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(
            HUDBackdrop(cornerRadius: 14, contrast: .high)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
        )
    }
}
