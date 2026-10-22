// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The lock screen widgets' look: glass tiles under a deep violet, type
/// tinted like the clock, big numbers in SF Pro Rounded as the clock draws
/// them, and section labels in small spaced capitals.
enum NotchLockScreenTile {
    static let cornerRadius: CGFloat = 28
    static let tint = Color(red: 28 / 255, green: 24 / 255, blue: 58 / 255).opacity(0.42)
    /// The tint without the wallpaper under it, for Reduce Transparency.
    static let solid = Color(red: 24 / 255, green: 21 / 255, blue: 46 / 255)
    static let text = Color(red: 240 / 255, green: 238 / 255, blue: 1).opacity(0.96)
    static let dim = Color(red: 222 / 255, green: 218 / 255, blue: 250 / 255).opacity(0.72)
    static let label = Color(red: 222 / 255, green: 218 / 255, blue: 250 / 255).opacity(0.70)
    static let track = Color.white.opacity(0.12)
    static let rule = Color.white.opacity(0.12)
    /// Speed is neither good nor bad, so the network keeps out of the
    /// green, yellow and red.
    static let down = Color(red: 0x3D / 255, green: 0x8B / 255, blue: 1)
    static let up = Color(red: 0xB3 / 255, green: 0x6B / 255, blue: 1)

    static func color(_ level: NotchLockScreenLevel) -> Color {
        switch level {
        case .good: return Color(red: 0x5F / 255, green: 0xD0 / 255, blue: 0x68 / 255)
        case .warning: return Color(red: 0xF2 / 255, green: 0xC9 / 255, blue: 0x4C / 255)
        case .critical: return Color(red: 1, green: 0x6B / 255, blue: 0x5E / 255)
        }
    }

    /// Lighter, for type and badges on the tile.
    static func light(_ level: NotchLockScreenLevel) -> Color {
        switch level {
        case .good: return Color(red: 0x8F / 255, green: 0xE2 / 255, blue: 0x97 / 255)
        case .warning: return Color(red: 0xF6 / 255, green: 0xD7 / 255, blue: 0x7A / 255)
        case .critical: return Color(red: 1, green: 0x9A / 255, blue: 0x90 / 255)
        }
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// One widget's tile: its content inset, on the tiles' glass.
    func lockScreenTile(horizontal: CGFloat = 18, vertical: CGFloat = 14) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(NotchLockScreenTile.text)
            .modifier(NotchLockScreenGlass(cornerRadius: NotchLockScreenTile.cornerRadius, tile: true))
            .environment(\.colorScheme, .dark)
    }
}

/// A tile's heading: a mark, its name in spaced capitals, and a note on
/// the right.
struct NotchLockScreenSection<Accessory: View>: View {
    let title: String
    var symbol: String?
    var symbolTint: Color = NotchLockScreenTile.label
    @ViewBuilder var accessory: Accessory
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(symbolTint)
            }
            Text(title.uppercased(with: l10n.language.formattingLocale()))
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(NotchLockScreenTile.label)
                .lineLimit(1)
            Spacer(minLength: 4)
            accessory
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NotchLockScreenTile.dim)
                .lineLimit(1)
        }
        .frame(height: 14)
    }
}

extension NotchLockScreenSection where Accessory == EmptyView {
    init(title: String, symbol: String? = nil, symbolTint: Color = NotchLockScreenTile.label) {
        self.init(title: title, symbol: symbol, symbolTint: symbolTint) { EmptyView() }
    }
}

/// A badge in a tile's heading, colored by how the reading stands.
struct NotchLockScreenBadge: View {
    let text: String
    let level: NotchLockScreenLevel?

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(level.map { NotchLockScreenTile.color($0).opacity(0.22) } ?? .white.opacity(0.14), in: Capsule())
            .foregroundStyle(level.map(NotchLockScreenTile.light) ?? NotchLockScreenTile.dim)
    }
}

/// A ring filled from the top, clockwise, with its reading inside.
struct NotchLockScreenRing<Inside: View>: View {
    let fill: Double
    let tint: Color
    let diameter: CGFloat
    var lineWidth: CGFloat?
    @ViewBuilder var inside: Inside

    var body: some View {
        let width = lineWidth ?? diameter * 0.11
        ZStack {
            Circle().stroke(NotchLockScreenTile.track, lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0.005, NotchLockScreenSupport.ringFill(fill)))
                .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            inside
        }
        .padding(width / 2)
        .frame(width: diameter, height: diameter)
    }
}
