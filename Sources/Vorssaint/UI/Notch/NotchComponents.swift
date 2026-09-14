// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Feedback is local to a visible control. No recurring work is needed.
/// The pointer lifts a control slightly and a press settles it back, which is
/// what makes the panel feel physical rather than painted on.
struct NotchButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10
    var lifts = true
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let active = enabled && hovered
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(active ? 0.09 : 0))
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(reduceMotion || !lifts ? 1
                         : configuration.isPressed ? 0.965 : (active ? 1.022 : 1))
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7),
                       value: configuration.isPressed)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.75), value: hovered)
            .onHover { hovered = $0 }
    }
}

extension NotchArtworkTint {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

/// Bars that rise and fall while something is playing — the one moving thing
/// in the resting notch. Purely decorative, so it is hidden from assistive
/// technology, holds still when motion is reduced and stops dead when paused.
struct NotchEqualizerBars: View {
    var isPlaying = true
    var bars = 4
    var barWidth: CGFloat = 2.5
    var height: CGFloat = 14
    var tint: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { isPlaying && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { context in
            HStack(alignment: .center, spacing: barWidth * 0.85) {
                ForEach(0..<max(1, bars), id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: barWidth,
                               height: barHeight(index, at: context.date.timeIntervalSinceReferenceDate))
                }
            }
            .frame(height: height)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int, at phase: Double) -> CGFloat {
        guard animates else { return barWidth }
        let center = Double(max(1, bars) - 1) / 2
        let distance = abs(Double(index) - center) / max(1, center)
        let envelope = pow(1 - distance, 1.5)
        let wave = (sin(phase * (5.2 + Double(index) * 0.61) + Double(index) * 1.7) + 1) / 2
        return max(barWidth, height * (0.12 + envelope * (0.25 + 0.63 * wave)))
    }
}

/// A level readout in the same language as the notch's sliders, instead of the
/// thin system bar, so every meter in the panel matches.
struct NotchMeter: View {
    let value: Double
    var height: CGFloat = 5
    var tint: Color = .white

    var body: some View {
        let fraction = value.isFinite ? min(1, max(0, value)) : 0
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(.white.opacity(0.14))
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.9))
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct NotchIconButton: View {
    let symbol: String
    let title: String
    var selected = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? .white : .white.opacity(0.55))
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: symbol)
                .frame(width: 28, height: 28)
                .background(.white.opacity(selected ? 0.12 : 0),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 9))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct NotchEmptyView: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 250)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

struct NotchArtwork: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.black.overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// Short rows spread their remaining items evenly instead of leaving a hole.
struct NotchTileGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    var spacing: CGFloat = 12
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(stride(from: 0, to: items.count, by: max(1, columns))), id: \.self) { start in
                HStack(spacing: spacing) {
                    ForEach(Array(items[start..<min(items.count, start + max(1, columns))])) { item in
                        content(item).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

/// The base remains opaque black. Optional glass belongs to controls alone.
struct NotchControlSurface: ViewModifier {
    let cornerRadius: CGFloat
    var selected = false
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var glass = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
#if compiler(>=6.2)
            if #available(macOS 26, *), glass, !reduceTransparency {
                content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
                    .glassEffect(.regular.interactive(), in: shape)
            } else {
                content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
            }
#else
            content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
#endif
        }
        .overlay {
            shape.strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}
