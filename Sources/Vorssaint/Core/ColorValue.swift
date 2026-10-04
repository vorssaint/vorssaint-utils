// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A color read from text that is only a color value. The accepted forms are
/// the CSS ones designers copy and the ones the color picker writes: `#RGB`,
/// `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`, `rgba()`, `hsl()`, `hsla()` and
/// SwiftUI's `Color(red:green:blue:opacity:)`. The value must be the whole
/// entry; a color inside a longer text is not one, and a bare `RRGGBB` would
/// also match plain numbers and hashes.
struct ColorValue: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    /// Longer than any accepted form with generous spacing; the cap keeps a
    /// render from trimming or scanning a large entry.
    static let maxLength = 96

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(text: String) {
        guard text.utf8.count <= Self.maxLength else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") {
            self.init(hexDigits: value.dropFirst())
        } else if let arguments = Self.arguments(of: value, names: ["rgba", "rgb"]) {
            self.init(rgbArguments: arguments)
        } else if let arguments = Self.arguments(of: value, names: ["hsla", "hsl"]) {
            self.init(hslArguments: arguments)
        } else if value.hasPrefix("color("), value.hasSuffix(")") {
            self.init(swiftUIArguments: value.dropFirst(6).dropLast())
        } else {
            return nil
        }
    }

    private init?(hexDigits: Substring) {
        guard [3, 4, 6, 8].contains(hexDigits.count),
              hexDigits.allSatisfy(\.isHexDigit)
        else { return nil }
        let expanded = hexDigits.count <= 4
            ? String(hexDigits.flatMap { [$0, $0] })
            : String(hexDigits)
        guard let value = UInt64(expanded, radix: 16) else { return nil }
        let hasAlpha = expanded.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1)
    }

    private init?(rgbArguments: [String]) {
        guard (3...4).contains(rgbArguments.count) else { return nil }
        var channels: [Double] = []
        for argument in rgbArguments.prefix(3) {
            if let percent = Self.percentage(argument) {
                channels.append(percent)
            } else if let number = Self.number(argument), (0...255).contains(number) {
                channels.append(number / 255)
            } else {
                return nil
            }
        }
        guard let alpha = Self.alpha(rgbArguments.dropFirst(3).first) else { return nil }
        self.init(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    /// `red: 0.2, green: 0.4, blue: 0.6`, optionally followed by
    /// `opacity: 0.5`, with or without spaces around the labels.
    private init?(swiftUIArguments: Substring) {
        let labels = ["red", "green", "blue", "opacity"]
        let pairs = swiftUIArguments.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false) }
        guard (3...4).contains(pairs.count) else { return nil }
        var components: [Double] = []
        for (label, pair) in zip(labels, pairs) {
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespacesAndNewlines) == label,
                  let value = Self.number(pair[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                  (0...1).contains(value)
            else { return nil }
            components.append(value)
        }
        self.init(red: components[0], green: components[1], blue: components[2],
                  alpha: components.count == 4 ? components[3] : 1)
    }

    private init?(hslArguments: [String]) {
        guard (3...4).contains(hslArguments.count) else { return nil }
        let hueText = hslArguments[0].hasSuffix("deg")
            ? String(hslArguments[0].dropLast(3))
            : hslArguments[0]
        guard let hue = Self.number(hueText),
              let saturation = Self.percentage(hslArguments[1]),
              let lightness = Self.percentage(hslArguments[2]),
              let alpha = Self.alpha(hslArguments.dropFirst(3).first)
        else { return nil }
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        func channel(_ offset: Double) -> Double {
            let k = (offset + h * 12).truncatingRemainder(dividingBy: 12)
            return lightness - chroma / 2 * max(-1, min(k - 3, 9 - k, 1))
        }
        self.init(red: channel(0), green: channel(8), blue: channel(4), alpha: alpha)
    }

    /// The arguments of `name(...)`, split on commas, spaces and the slash
    /// that CSS puts before the alpha value.
    private static func arguments(of value: String, names: [String]) -> [String]? {
        guard value.hasSuffix(")"),
              let name = names.first(where: { value.hasPrefix($0 + "(") })
        else { return nil }
        let inner = value.dropFirst(name.count + 1).dropLast()
        return inner
            .split(whereSeparator: { $0 == "," || $0 == "/" || $0.isWhitespace })
            .map(String.init)
    }

    private static func number(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// A `0%`...`100%` value as a fraction.
    private static func percentage(_ text: String) -> Double? {
        guard text.hasSuffix("%"),
              let value = number(String(text.dropLast())),
              (0...100).contains(value)
        else { return nil }
        return value / 100
    }

    /// Opaque when absent; otherwise a `0`...`1` number or a percentage.
    private static func alpha(_ text: String?) -> Double? {
        guard let text else { return 1 }
        if let percent = percentage(text) { return percent }
        guard let value = number(text), (0...1).contains(value) else { return nil }
        return value
    }
}

/// How a color is written out.
enum ColorCopyFormat: String, CaseIterable, Identifiable {
    case hex
    case rgb
    case hsl
    case swiftui

    var id: String { rawValue }

    /// Short technical label; intentionally not localized.
    var label: String {
        switch self {
        case .hex: return "HEX"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        case .swiftui: return "SwiftUI"
        }
    }

    static func sanitized(_ raw: String) -> ColorCopyFormat {
        ColorCopyFormat(rawValue: raw) ?? .hex
    }
}

extension ColorValue {
    /// Formats sRGB components (0...1) in the chosen copy format. Components
    /// out of range are clamped so extended-gamut samples never produce
    /// invalid strings. `bareHex` drops the leading # (issue #168: some design
    /// tools reject pasted values that carry it); it only affects `.hex`.
    /// A non-nil `alpha` writes the alpha form.
    static func string(red: Double,
                       green: Double,
                       blue: Double,
                       alpha: Double? = nil,
                       format: ColorCopyFormat,
                       bareHex: Bool = false) -> String {
        let r = min(max(red, 0), 1)
        let g = min(max(green, 0), 1)
        let b = min(max(blue, 0), 1)
        let a = alpha.map { min(max($0, 0), 1) }
        // Three decimals are the fewest that bring every 8-bit alpha back.
        let alphaText = a.map { String(format: "%g", locale: Locale(identifier: "en_US_POSIX"),
                                       ($0 * 1000).rounded() / 1000) }
        switch format {
        case .hex:
            let hex = String(format: bareHex ? "%02X%02X%02X" : "#%02X%02X%02X",
                             Int((r * 255).rounded()),
                             Int((g * 255).rounded()),
                             Int((b * 255).rounded()))
            return a.map { hex + String(format: "%02X", Int(($0 * 255).rounded())) } ?? hex
        case .rgb:
            let channels = String(format: "%d, %d, %d",
                                  Int((r * 255).rounded()),
                                  Int((g * 255).rounded()),
                                  Int((b * 255).rounded()))
            return alphaText.map { "rgba(\(channels), \($0))" } ?? "rgb(\(channels))"
        case .hsl:
            let (h, s, l) = hsl(red: r, green: g, blue: b)
            let channels = String(format: "%d, %d%%, %d%%",
                                  Int(h.rounded()),
                                  Int((s * 100).rounded()),
                                  Int((l * 100).rounded()))
            return alphaText.map { "hsla(\(channels), \($0))" } ?? "hsl(\(channels))"
        case .swiftui:
            // Source code, not prose: a comma here would paste something that
            // does not compile, whatever region the reader is in.
            let posix = Locale(identifier: "en_US_POSIX")
            let rgb = String(format: "red: %.3f, green: %.3f, blue: %.3f", locale: posix, r, g, b)
            return a.map { "Color(\(rgb), opacity: \(String(format: "%.3f", locale: posix, $0)))" }
                ?? "Color(\(rgb))"
        }
    }

    static func hsl(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, lightness: Double) {
        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let delta = maxComponent - minComponent
        let lightness = (maxComponent + minComponent) / 2

        guard delta > 0.000001 else { return (0, 0, lightness) }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        if maxComponent == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxComponent == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, min(max(saturation, 0), 1), lightness)
    }
}
