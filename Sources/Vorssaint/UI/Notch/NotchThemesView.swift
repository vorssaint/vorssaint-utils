// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The island's looks in one place: the outline and halo themes as swatches,
/// and the switches for the outline, the lights, the glass resting island and
/// the translucent open one. They are the same preferences Settings changes.
struct NotchThemesView: View {
    let size: CGSize
    @AppStorage(DefaultsKey.notchOutlineTheme) private var theme = NotchOutlineTheme.adaptive.rawValue
    @AppStorage(DefaultsKey.notchOutlineEnabled) private var outline = false
    @AppStorage(DefaultsKey.notchLightsEnabled) private var lights = true
    @AppStorage(DefaultsKey.notchRestingGlass) private var glass = false
    @AppStorage(DefaultsKey.notchTranslucentBackground) private var translucent = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(NotchOutlineTheme.allCases) { option in swatch(option) }
            }
            HStack(spacing: 8) {
                toggle("Outline", symbol: "capsule", isOn: $outline)
                toggle("Lights", symbol: "sparkles", isOn: $lights)
                toggle("Glass", symbol: "drop", isOn: $glass)
                toggle("Blur", symbol: "square.stack.3d.down.right", isOn: $translucent)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func swatch(_ option: NotchOutlineTheme) -> some View {
        let selected = theme == option.rawValue
        let palette = option.palette
        return Button {
            theme = option.rawValue
            outline = true
            lights = true
            NotchService.shared.syncWithPreferences()
        } label: {
            VStack(spacing: 5) {
                Capsule()
                    .fill(LinearGradient(colors: [palette.primary.color, palette.secondary.color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 14)
                    .overlay(Capsule().strokeBorder(palette.rim.color.opacity(0.9), lineWidth: 1))
                Text(option.rawValue.capitalized)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(selected ? 0.16 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(selected ? 0.55 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.rawValue.capitalized)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ title: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            NotchService.shared.syncWithPreferences()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(isOn.wrappedValue ? 0.2 : 0.07)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}
