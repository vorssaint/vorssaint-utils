// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How a sampled color lands on the clipboard.
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

enum QuickToolsSupport {
    /// Formats sRGB components (0...1) in the chosen copy format. Components
    /// out of range are clamped so extended-gamut samples never produce
    /// invalid strings. `bareHex` drops the leading # (issue #168: some design
    /// tools reject pasted values that carry it); it only affects `.hex`.
    static func colorString(red: Double,
                            green: Double,
                            blue: Double,
                            format: ColorCopyFormat,
                            bareHex: Bool = false) -> String {
        let r = min(max(red, 0), 1)
        let g = min(max(green, 0), 1)
        let b = min(max(blue, 0), 1)
        switch format {
        case .hex:
            return String(format: bareHex ? "%02X%02X%02X" : "#%02X%02X%02X",
                          Int((r * 255).rounded()),
                          Int((g * 255).rounded()),
                          Int((b * 255).rounded()))
        case .rgb:
            return String(format: "rgb(%d, %d, %d)",
                          Int((r * 255).rounded()),
                          Int((g * 255).rounded()),
                          Int((b * 255).rounded()))
        case .hsl:
            let (h, s, l) = hsl(red: r, green: g, blue: b)
            return String(format: "hsl(%d, %d%%, %d%%)",
                          Int(h.rounded()),
                          Int((s * 100).rounded()),
                          Int((l * 100).rounded()))
        case .swiftui:
            return String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", r, g, b)
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

    // MARK: - Quick launcher

    enum GridDirection {
        case up, down, left, right
    }

    /// Keyboard navigation over a row-major grid: arrows move by one cell,
    /// clamped to the existing items (no wrapping, so the selection never
    /// jumps surprisingly from one edge to the other).
    static func gridIndex(after index: Int,
                          count: Int,
                          columns: Int,
                          direction: GridDirection) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        let current = min(max(index, 0), count - 1)
        let candidate: Int
        switch direction {
        case .left: candidate = current - 1
        case .right: candidate = current + 1
        case .up: candidate = current - columns
        case .down: candidate = current + columns
        }
        guard candidate >= 0, candidate < count else { return current }
        if direction == .left, current % columns == 0 { return current }
        if direction == .right, current % columns == columns - 1 { return current }
        return candidate
    }

    /// The launcher's hidden-item set travels as a comma-joined string.
    static func hiddenIDs(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    static func serializeHiddenIDs(_ ids: Set<String>) -> String {
        ids.sorted().joined(separator: ",")
    }

    /// One recognized line of screen text with its normalized position
    /// (bottom-left origin, as Vision reports it).
    struct RecognizedLine {
        let text: String
        let x: Double
        let y: Double
    }

    /// Joins recognized lines in natural reading order: top to bottom, left
    /// to right within the same visual row. Empty lines are dropped.
    static func joinedRecognizedText(_ lines: [RecognizedLine]) -> String {
        lines
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                // Vision's y grows upward; bucket rows so tiny baseline
                // wobbles don't shuffle words of the same line.
                let rowA = (1 - $0.y) * 50
                let rowB = (1 - $1.y) * 50
                if abs(rowA - rowB) >= 0.5 { return rowA < rowB }
                return $0.x < $1.x
            }
            .map(\.text)
            .joined(separator: "\n")
    }

    // MARK: - QR codes

    /// One decoded 2D code with its normalized position (bottom-left origin,
    /// as Vision reports it) so several codes join in reading order.
    struct DecodedBarcode {
        let payload: String
        let x: Double
        let y: Double
    }

    /// Joins decoded codes in natural reading order (top to bottom, left to
    /// right), dropping empty payloads. Several codes are newline separated.
    static func joinedBarcodePayloads(_ codes: [DecodedBarcode]) -> String {
        codes
            .filter { !$0.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                let rowA = (1 - $0.y) * 50
                let rowB = (1 - $1.y) * 50
                if abs(rowA - rowB) >= 0.5 { return rowA < rowB }
                return $0.x < $1.x
            }
            .map(\.payload)
            .joined(separator: "\n")
    }

    /// The payload as a web link for the optional open action. Limited to
    /// http and https on purpose: a scanned code must never be able to launch
    /// an arbitrary URL scheme (mailto, tel, custom app schemes and so on).
    static func openableURL(from payload: String) -> URL? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
