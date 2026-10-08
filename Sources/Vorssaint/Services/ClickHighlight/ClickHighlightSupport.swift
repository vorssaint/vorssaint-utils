// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// How a click is drawn under the pointer. Raw values are persisted.
enum ClickRippleStyle: String, CaseIterable, Identifiable {
    case ring, doubleRing, glow, dot

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .ring: return "circle"
        case .doubleRing: return "circle.circle"
        case .glow: return "sun.max"
        case .dot: return "circle.fill"
        }
    }
}

/// The highlight's preferences, read once per change so event handling
/// never touches UserDefaults.
struct ClickHighlightConfig: Equatable {
    var rippleEnabled = false
    var rippleOnlyWhileRecording = false
    var style = ClickRippleStyle.ring
    var size = Defaults.defaultClickHighlightSize
    var colorHex = Defaults.defaultClickHighlightColor
    var spotlightEnabled = false
    var spotlightOnlyWhileRecording = true
    var spotlightDarkness = Defaults.defaultClickHighlightSpotlightDarkness
    var spotlightRadius = Defaults.defaultClickHighlightSpotlightRadius

    static func load(from defaults: UserDefaults = .standard) -> ClickHighlightConfig {
        ClickHighlightConfig(
            rippleEnabled: defaults.bool(forKey: DefaultsKey.clickHighlightRippleEnabled),
            rippleOnlyWhileRecording: defaults.bool(forKey: DefaultsKey.clickHighlightRippleOnlyWhileRecording),
            style: ClickRippleStyle(
                rawValue: defaults.string(forKey: DefaultsKey.clickHighlightStyle) ?? "") ?? .ring,
            size: Defaults.sanitizedClickHighlightSize(defaults.double(forKey: DefaultsKey.clickHighlightSize)),
            colorHex: ClickHighlightSupport.sanitizedColorHex(
                defaults.string(forKey: DefaultsKey.clickHighlightColor)),
            spotlightEnabled: defaults.bool(forKey: DefaultsKey.clickHighlightSpotlightEnabled),
            spotlightOnlyWhileRecording: defaults.bool(
                forKey: DefaultsKey.clickHighlightSpotlightOnlyWhileRecording),
            spotlightDarkness: Defaults.sanitizedClickHighlightSpotlightDarkness(
                defaults.double(forKey: DefaultsKey.clickHighlightSpotlightDarkness)),
            spotlightRadius: Defaults.sanitizedClickHighlightSpotlightRadius(
                defaults.double(forKey: DefaultsKey.clickHighlightSpotlightRadius))
        )
    }

    func showsRipple(isRecording: Bool) -> Bool {
        rippleEnabled && (!rippleOnlyWhileRecording || isRecording)
    }

    func showsSpotlight(isRecording: Bool) -> Bool {
        spotlightEnabled && (!spotlightOnlyWhileRecording || isRecording)
    }

    /// Whether the tap is needed at all right now.
    func needsEvents(isRecording: Bool) -> Bool {
        showsRipple(isRecording: isRecording) || showsSpotlight(isRecording: isRecording)
    }
}

enum ClickHighlightSupport {
    /// A hex color the highlight can draw with, or the default.
    static func sanitizedColorHex(_ raw: String?) -> String {
        guard let raw, raw.hasPrefix("#"), ColorValue(text: raw) != nil else {
            return Defaults.defaultClickHighlightColor
        }
        return raw.uppercased()
    }

    static func color(hex: String) -> ColorValue {
        ColorValue(text: hex) ?? ColorValue(text: Defaults.defaultClickHighlightColor)!
    }

    static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ component: Double) -> Int { Int((max(0, min(1, component)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// Converts an event location (top-left origin of the main display) to
    /// AppKit's bottom-left global space.
    static func appKitPoint(fromEventLocation location: CGPoint, mainDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: location.x, y: mainDisplayHeight - location.y)
    }

    /// Gradient stops for the spotlight: clear inside the circle, fading to
    /// the full dim over a soft edge. Locations are fractions of `extent`,
    /// the gradient's radius.
    static func spotlightLocations(radius: Double, extent: Double) -> [Double] {
        guard extent > 0 else { return [0, 1] }
        let inner = max(0, min(1, (radius * 0.72) / extent))
        let outer = max(inner, min(1, (radius * 1.08) / extent))
        return [0, inner, outer, 1]
    }
}
