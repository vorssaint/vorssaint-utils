// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The lock screen widgets' look: glass tiles under a tone, type tinted to
/// match, big numbers in SF Pro Rounded as the clock draws them, and section
/// labels in small spaced capitals.
enum NotchLockScreenTile {
    /// The tiles' palette, one for each part of a company, chosen as Job
    /// profile under Lock Screen in Settings and read each time the widgets
    /// draw. Each tints the glass and the type on it.
    enum Tone: String, CaseIterable, Identifiable {
        /// Engineering: neutral graphite, like a terminal.
        case graphite
        /// Product: the first deep violet.
        case violet
        /// Design: a light smoke that lets the wallpaper through.
        case smoke
        /// Executive: midnight navy under champagne type.
        case midnight
        /// Finance: a deep emerald.
        case emerald
        /// Sales: a deep crimson.
        case crimson
        /// Marketing: a warm sunset amber.
        case sunset
        /// Legal: walnut under parchment type.
        case walnut
        /// Customer Support: a calm teal.
        case teal
        /// People & HR: a soft rose.
        case rose

        var id: String { rawValue }

        static var current: Tone {
            UserDefaults.standard.string(forKey: DefaultsKey.notchLockScreenTileTone).flatMap(Tone.init) ?? .graphite
        }

        /// The tint's color, in 0–255, and how much of the glass it covers.
        var tint: (red: Double, green: Double, blue: Double, opacity: Double) {
            switch self {
            case .graphite: return (14, 14, 16, 0.50)
            case .violet: return (28, 24, 58, 0.42)
            case .smoke: return (0, 0, 0, 0.26)
            case .midnight: return (10, 16, 34, 0.58)
            case .emerald: return (8, 38, 28, 0.52)
            case .crimson: return (58, 12, 22, 0.48)
            case .sunset: return (66, 26, 8, 0.46)
            case .walnut: return (36, 26, 18, 0.55)
            case .teal: return (6, 40, 44, 0.50)
            case .rose: return (54, 20, 40, 0.46)
            }
        }

        /// The type's color, in 0–255.
        var ink: (red: Double, green: Double, blue: Double) {
            switch self {
            case .graphite, .smoke: return (255, 255, 255)
            case .violet: return (240, 238, 255)
            case .midnight: return (246, 236, 214)
            case .emerald: return (232, 246, 238)
            case .crimson: return (255, 236, 238)
            case .sunset: return (255, 240, 228)
            case .walnut: return (244, 236, 222)
            case .teal: return (230, 248, 248)
            case .rose: return (255, 236, 246)
            }
        }

        /// The tint brightened for Settings, where it shows on its own.
        var swatch: Color {
            let (red, green, blue, _) = tint
            let top = max(red, green, blue)
            guard top > 0 else { return Color(white: 0.32) }
            let scale = max(1, 120 / top)
            return Color(red: red * scale / 255, green: green * scale / 255, blue: blue * scale / 255)
        }

        func ink(_ opacity: Double) -> Color {
            Color(red: ink.red / 255, green: ink.green / 255, blue: ink.blue / 255).opacity(opacity)
        }
    }

    static let cornerRadius: CGFloat = 28
    static var tint: Color {
        let (red, green, blue, opacity) = Tone.current.tint
        return Color(red: red / 255, green: green / 255, blue: blue / 255).opacity(opacity)
    }
    /// The tint without the wallpaper under it, for Reduce Transparency.
    static var solid: Color {
        let (red, green, blue, _) = Tone.current.tint
        return Color(red: (red * 0.85 + 20) / 255, green: (green * 0.85 + 20) / 255, blue: (blue * 0.85 + 20) / 255)
    }
    /// The tiles' edge.
    static var edge: Double { Tone.current == .smoke ? 0.10 : 0.14 }
    static var text: Color { Tone.current.ink(0.96) }
    static var dim: Color { Tone.current.ink(0.70) }
    static var label: Color { Tone.current.ink(0.64) }
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
    var symbolTint: Color? = nil
    @ViewBuilder var accessory: Accessory
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(symbolTint ?? NotchLockScreenTile.label)
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
    init(title: String, symbol: String? = nil, symbolTint: Color? = nil) {
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
