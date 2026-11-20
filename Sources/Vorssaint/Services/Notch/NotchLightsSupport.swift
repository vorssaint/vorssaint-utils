// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import simd
import SwiftUI

enum NotchHaloStyle: String, CaseIterable, Identifiable, Equatable {
    case classic, pixelated, volumetric, rays, bioluminescent, prism, nimbus

    var id: String { rawValue }
}

enum NotchHaloArmWidth: String, CaseIterable, Identifiable, Equatable {
    case narrow, medium, wide, extraWide

    var id: String { rawValue }

    var points: CGFloat {
        switch self {
        case .narrow: return 76
        case .medium: return 130
        case .wide: return 220
        case .extraWide: return min(520, 440)
        }
    }
}

enum NotchHaloEntryMode: String, CaseIterable, Identifiable, Equatable {
    case sweep, trace, blast

    var id: String { rawValue }
}

enum NotchHaloMotion: String, CaseIterable, Identifiable, Equatable {
    case none, ondulation, flux, ripple, shimmer

    var id: String { rawValue }
}

enum NotchHaloTransitionEffect: String, CaseIterable, Identifiable, Equatable {
    case hybrid, whiteFlash, hueSlide, shockwave, pulse, supernova, rings, prism, strobe, bigBang, off

    var id: String { rawValue }
}

enum NotchLightSurfaceStyle: String, CaseIterable, Identifiable, Equatable {
    case neon, velours

    var id: String { rawValue }
}

enum NotchHaloState: String, Equatable {
    case idle, running, success, warning, error, stalled, music, copy
}

enum NotchOutlineTheme: String, CaseIterable, Identifiable, Equatable {
    case adaptive, cyan, prism, aurora, sunlight, emerald, crimson, monochrome

    var id: String { rawValue }

    var palette: NotchHaloPalette {
        switch self {
        case .adaptive, .cyan:
            return .running
        case .prism:
            return NotchHaloPalette(
                primary: NotchHaloRGB(r: 0.45, g: 0.78, b: 1.00),
                secondary: NotchHaloRGB(r: 0.78, g: 0.42, b: 1.00),
                core: NotchHaloRGB(r: 0.90, g: 0.94, b: 1.00),
                rim: NotchHaloRGB(r: 1.00, g: 0.48, b: 0.72)
            )
        case .aurora:
            return NotchHaloPalette(
                primary: NotchHaloRGB(r: 0.18, g: 0.92, b: 0.78),
                secondary: NotchHaloRGB(r: 0.36, g: 0.56, b: 1.00),
                core: NotchHaloRGB(r: 0.80, g: 1.00, b: 0.94),
                rim: NotchHaloRGB(r: 0.24, g: 0.88, b: 0.62)
            )
        case .sunlight:
            return NotchHaloPalette(
                primary: NotchHaloRGB(r: 1.00, g: 0.88, b: 0.48),
                secondary: NotchHaloRGB(r: 1.00, g: 0.37, b: 0.09),
                core: NotchHaloRGB(r: 1.00, g: 0.97, b: 0.82),
                rim: NotchHaloRGB(r: 1.00, g: 0.62, b: 0.18)
            )
        case .emerald:
            return .success
        case .crimson:
            return NotchHaloPalette(
                primary: NotchHaloRGB(r: 0.94, g: 0.37, b: 0.48),
                secondary: NotchHaloRGB(r: 0.64, g: 0.13, b: 0.40),
                core: NotchHaloRGB(r: 1.00, g: 0.80, b: 0.84),
                rim: NotchHaloRGB(r: 0.96, g: 0.28, b: 0.42)
            )
        case .monochrome:
            return NotchHaloPalette(
                primary: NotchHaloRGB(r: 0.96, g: 0.97, b: 1.00),
                secondary: NotchHaloRGB(r: 0.72, g: 0.78, b: 0.86),
                core: NotchHaloRGB(r: 1.00, g: 1.00, b: 1.00),
                rim: NotchHaloRGB(r: 0.84, g: 0.88, b: 0.94)
            )
        }
    }
}

enum NotchLevelBarKind: Equatable {
    case volume, brightness, keyboardLight
}

struct NotchLevelPrismPalette: Equatable {
    let lead: NotchHaloRGB
    let trail: NotchHaloRGB
    let core: NotchHaloRGB

    /// Cyan to electric indigo prism palette for volume levels
    static let volume = NotchLevelPrismPalette(
        lead: NotchHaloRGB(r: 0.10, g: 0.91, b: 1.00),
        trail: NotchHaloRGB(r: 0.22, g: 0.25, b: 1.00),
        core: NotchHaloRGB(r: 0.85, g: 0.98, b: 1.00)
    )

    /// Gold to solar orange prism palette for brightness and keyboard backlight levels
    static let sunlight = NotchLevelPrismPalette(
        lead: NotchHaloRGB(r: 1.00, g: 0.88, b: 0.48),
        trail: NotchHaloRGB(r: 1.00, g: 0.37, b: 0.09),
        core: NotchHaloRGB(r: 1.00, g: 0.97, b: 0.82)
    )

    /// Rose-crimson prism palette for muted audio
    static let silence = NotchLevelPrismPalette(
        lead: NotchHaloRGB(r: 0.94, g: 0.37, b: 0.48),
        trail: NotchHaloRGB(r: 0.64, g: 0.13, b: 0.40),
        core: NotchHaloRGB(r: 1.00, g: 0.80, b: 0.84)
    )

    static func palette(for kind: NotchLevelBarKind, muted: Bool) -> NotchLevelPrismPalette {
        if muted && kind == .volume { return .silence }
        switch kind {
        case .volume: return .volume
        case .brightness, .keyboardLight: return .sunlight
        }
    }
}

struct NotchHaloOverlayLayout: Equatable {
    let overlayScreenRect: CGRect
    let islandRect: CGRect
    let floatingGap: CGFloat?
    let shoulder: CGFloat
    let cornerRadius: CGFloat
}

struct NotchHaloRGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    var color: Color { Color(red: r, green: g, blue: b) }
    var simd3: SIMD3<Float> { SIMD3<Float>(Float(r), Float(g), Float(b)) }

    func blended(with other: NotchHaloRGB, amount: Double) -> NotchHaloRGB {
        let t = min(1, max(0, amount))
        return NotchHaloRGB(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t
        )
    }

    func adaptedForLightSurface(_ style: NotchLightSurfaceStyle) -> NotchHaloRGB {
        switch style {
        case .neon:
            // Cut milky floor and slightly push chroma contrast on bright menu bars.
            let m = min(r, g, b)
            let floorCut = min(0.12, m * 0.5)
            return NotchHaloRGB(
                r: min(1, max(0, (r - floorCut) * 1.04)),
                g: min(1, max(0, (g - floorCut) * 1.04)),
                b: min(1, max(0, (b - floorCut) * 1.04))
            )
        case .velours:
            // Deepen darks slightly so shadow-backed chrome remains rich over bright bars.
            return NotchHaloRGB(
                r: min(1, max(0, r * 0.86)),
                g: min(1, max(0, g * 0.86)),
                b: min(1, max(0, b * 0.86))
            )
        }
    }
}

struct NotchHaloPalette: Equatable {
    var primary: NotchHaloRGB
    var secondary: NotchHaloRGB
    var core: NotchHaloRGB
    var rim: NotchHaloRGB

    static let running = NotchHaloPalette(
        primary: NotchHaloRGB(r: 0.4, g: 0.8, b: 1.0),
        secondary: NotchHaloRGB(r: 0.2, g: 0.9, b: 1.0),
        core: NotchHaloRGB(r: 0.82, g: 0.96, b: 1.0),
        rim: NotchHaloRGB(r: 0.28, g: 0.72, b: 1.0)
    )

    static let success = NotchHaloPalette(
        primary: NotchHaloRGB(r: 0.4, g: 0.92, b: 0.6),
        secondary: NotchHaloRGB(r: 0.18, g: 0.84, b: 0.48),
        core: NotchHaloRGB(r: 0.78, g: 1.0, b: 0.86),
        rim: NotchHaloRGB(r: 0.25, g: 0.88, b: 0.52)
    )

    static let warning = NotchHaloPalette(
        primary: NotchHaloRGB(r: 1.0, g: 0.85, b: 0.3),
        secondary: NotchHaloRGB(r: 1.0, g: 0.55, b: 0.05),
        core: NotchHaloRGB(r: 1.0, g: 0.95, b: 0.65),
        rim: NotchHaloRGB(r: 1.0, g: 0.65, b: 0.1)
    )

    static let error = NotchHaloPalette(
        primary: NotchHaloRGB(r: 1.0, g: 0.5, b: 0.5),
        secondary: NotchHaloRGB(r: 1.0, g: 0.15, b: 0.2),
        core: NotchHaloRGB(r: 1.0, g: 0.8, b: 0.82),
        rim: NotchHaloRGB(r: 1.0, g: 0.24, b: 0.26)
    )

    static let stalled = NotchHaloPalette(
        primary: NotchHaloRGB(r: 0.78, g: 0.72, b: 0.55),
        secondary: NotchHaloRGB(r: 0.62, g: 0.56, b: 0.42),
        core: NotchHaloRGB(r: 0.9, g: 0.86, b: 0.74),
        rim: NotchHaloRGB(r: 0.68, g: 0.62, b: 0.48)
    )

    static func matching(r: Double, g: Double, b: Double) -> NotchHaloPalette {
        let base = NotchHaloRGB(r: min(1, max(0, r)), g: min(1, max(0, g)), b: min(1, max(0, b)))
        return NotchHaloPalette(
            primary: base,
            secondary: NotchHaloRGB(
                r: min(1, base.r * 0.85 + 0.08),
                g: min(1, base.g * 0.85 + 0.08),
                b: min(1, base.b * 0.95 + 0.05)
            ),
            core: base.blended(with: NotchHaloRGB(r: 1, g: 1, b: 1), amount: 0.45),
            rim: NotchHaloRGB(r: base.r * 0.8, g: base.g * 0.8, b: min(1, base.b * 0.95))
        )
    }

    func adapted(lightSurface: Bool, style: NotchLightSurfaceStyle) -> NotchHaloPalette {
        guard lightSurface else { return self }
        return NotchHaloPalette(
            primary: primary.adaptedForLightSurface(style),
            secondary: secondary.adaptedForLightSurface(style),
            core: core.adaptedForLightSurface(style),
            rim: rim.adaptedForLightSurface(style)
        )
    }
}

struct NotchHaloRaySpec: Equatable {
    let index: Int
    let xOffset: CGFloat
    let width: CGFloat
    let length: CGFloat
    let angleDegrees: Double
    let opacity: Double
    let phase: Double
}

struct NotchEdgeWaveUniforms {
    var color: SIMD4<Float>
    var res: SIMD2<Float>
    var origin: SIMD2<Float>
    var notch: SIMD2<Float>
    var t: Float
    var clock: Float
    var mode: Float
    var progress: Float
    var fade: Float
    var floatingIsland: Float
    var contourCorner: Float
    var lightSurface: Float
    var pad0: Float = 0
    var pad1: Float = 0
}

enum NotchLightsSupport {
    static let thicknessRange: ClosedRange<Double> = 0.6...2.0
    static let maxArmRun: CGFloat = 520

    static let bayer8x8: [Double] = [
         0, 32,  8, 40,  2, 34, 10, 42,
        48, 16, 56, 24, 50, 18, 58, 26,
        12, 44,  4, 36, 14, 46,  6, 38,
        60, 28, 52, 20, 62, 30, 54, 22,
         3, 35, 11, 43,  1, 33,  9, 41,
        51, 19, 59, 27, 49, 17, 57, 25,
        15, 47,  7, 39, 13, 45,  5, 37,
        63, 31, 55, 23, 61, 29, 53, 21
    ].map { $0 / 64.0 }

    static func clampedThickness(_ raw: Double) -> Double {
        guard raw.isFinite else { return 1.0 }
        return min(thicknessRange.upperBound, max(thicknessRange.lowerBound, raw))
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchLightsEnabled) as? Bool ?? true
    }

    static func style(in defaults: UserDefaults = .standard) -> NotchHaloStyle {
        NotchHaloStyle(rawValue: defaults.string(forKey: DefaultsKey.notchHaloStyle) ?? "") ?? .rays
    }

    static func armWidth(in defaults: UserDefaults = .standard) -> NotchHaloArmWidth {
        NotchHaloArmWidth(rawValue: defaults.string(forKey: DefaultsKey.notchHaloArmWidth) ?? "") ?? .medium
    }

    static func thickness(in defaults: UserDefaults = .standard) -> Double {
        let value = defaults.object(forKey: DefaultsKey.notchHaloThickness) as? Double ?? 1.0
        return clampedThickness(value)
    }

    static func entryMode(in defaults: UserDefaults = .standard) -> NotchHaloEntryMode {
        NotchHaloEntryMode(rawValue: defaults.string(forKey: DefaultsKey.notchHaloEntry) ?? "") ?? .sweep
    }

    static func motion(in defaults: UserDefaults = .standard) -> NotchHaloMotion {
        NotchHaloMotion(rawValue: defaults.string(forKey: DefaultsKey.notchHaloMotion) ?? "") ?? .ondulation
    }

    static func transitionEffect(in defaults: UserDefaults = .standard) -> NotchHaloTransitionEffect {
        NotchHaloTransitionEffect(rawValue: defaults.string(forKey: DefaultsKey.notchHaloTransition) ?? "") ?? .hybrid
    }

    static func edgeWaveEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchEdgeWaveEnabled) as? Bool ?? true
    }

    static func lightSurfaceStyle(in defaults: UserDefaults = .standard) -> NotchLightSurfaceStyle {
        NotchLightSurfaceStyle(rawValue: defaults.string(forKey: DefaultsKey.notchLightSurfaceStyle) ?? "") ?? .neon
    }

    static func tracksAgents(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchLightsAgentActivity) as? Bool ?? true
    }

    static func tracksMusic(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchLightsMusicActivity) as? Bool ?? true
    }

    static func tracksCopy(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchLightsCopySweep) as? Bool ?? true
    }

    static func tracksNotices(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchLightsNotices) as? Bool ?? true
    }

    static func outlineTheme(in defaults: UserDefaults = .standard) -> NotchOutlineTheme {
        NotchOutlineTheme(rawValue: defaults.string(forKey: DefaultsKey.notchOutlineTheme) ?? "") ?? .adaptive
    }

    static func restingOutline(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchLightsRestingOutline) as? Bool ?? false
    }

    static func tracksLevelBars(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchLightsLevelBars) as? Bool ?? true
    }

    static func showsRestingOutline(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && (restingOutline(in: defaults) || defaults.bool(forKey: DefaultsKey.notchOutlineEnabled))
    }

    static func fract(_ x: Double) -> Double {
        x - floor(x)
    }

    static func hash(_ seed: Double) -> Double {
        fract(sin(seed) * 6151.71)
    }

    /// Generates deterministic left or right wing prism rays along the notch arm run.
    static func armRays(armRun: CGFloat, thicknessScale: Double, intensity: Double, sign: Double) -> [NotchHaloRaySpec] {
        let clampedRun = min(maxArmRun, max(40.0, armRun))
        let count = min(34, max(5, Int(max(40.0, clampedRun - 14.0) / 16.0)))
        let scale = clampedThickness(thicknessScale)
        let activeIntensity = min(1.5, max(0.0, intensity))
        let usable = max(24.0, clampedRun - 18.0)

        return (0..<count).map { index in
            let u = count > 1 ? Double(index) / Double(count - 1) : 0.5
            let seed = Double(index) + (sign < 0 ? 100.0 : 0.0)
            let rWidth = hash(seed + 53.271)
            let rLen = hash(seed + 21.703)
            let rAngle = hash(seed + 34.17)
            let rPos = hash(seed + 65.109)
            let rOpacity = hash(seed + 100.623)
            let rPhase = hash(seed + 171.651)
            let falloff = 1.0 - 0.45 * u * u

            let pos = (8.0 + u * usable + (rPos - 0.5) * 8.0) * sign
            let width = (1.3 + 3.0 * rWidth) * scale
            let length = (0.6 + 0.4 * rLen) * (0.72 + 0.28 * falloff) * (40.0 + 20.0 * activeIntensity)
            let angle = ((5.0 + 12.0 * u) * sign) + (rAngle - 0.5) * 4.0
            let opacity = (0.14 + 0.09 * rOpacity) * falloff

            return NotchHaloRaySpec(
                index: index,
                xOffset: pos,
                width: width,
                length: length,
                angleDegrees: angle,
                opacity: opacity,
                phase: rPhase * .pi * 2.0
            )
        }
    }

    static func overlayLayout(islandScreenRect: CGRect, floatingGap: CGFloat?, armRun: CGFloat,
                              thicknessScale: Double, screenScale: CGFloat = 2.0) -> NotchHaloOverlayLayout {
        let clampedArm = min(maxArmRun, max(40.0, armRun))
        let scale = clampedThickness(thicknessScale)
        let backingScale = max(1.0, screenScale)
        func snap(_ value: CGFloat) -> CGFloat { (value * backingScale).rounded() / backingScale }

        let snappedIsland = CGRect(
            x: snap(islandScreenRect.minX),
            y: snap(islandScreenRect.minY),
            width: snap(max(40, islandScreenRect.width)),
            height: snap(max(16, islandScreenRect.height))
        )
        let sidePad = snap(clampedArm + 48.0)
        let bottomBloom = snap(CGFloat(92.0 * scale))
        let topPad: CGFloat = floatingGap != nil ? snap(CGFloat(36.0 * scale)) : 0

        let overlayScreenRect = CGRect(
            x: snap(snappedIsland.minX - sidePad),
            y: snap(snappedIsland.minY - bottomBloom),
            width: snap(snappedIsland.width + sidePad * 2.0),
            height: snap(snappedIsland.height + bottomBloom + topPad)
        )

        // Convert AppKit bottom-up screen rect to SwiftUI top-down local rect inside overlayScreenRect.
        let localOriginY = snap(overlayScreenRect.maxY - snappedIsland.maxY)
        let localIslandRect = CGRect(
            x: snap(snappedIsland.minX - overlayScreenRect.minX),
            y: localOriginY,
            width: snappedIsland.width,
            height: snappedIsland.height
        )

        return NotchHaloOverlayLayout(
            overlayScreenRect: overlayScreenRect,
            islandRect: localIslandRect,
            floatingGap: floatingGap,
            shoulder: NotchLayout.shoulder(height: snappedIsland.height),
            cornerRadius: NotchLayout.surfaceRadius(height: snappedIsland.height)
        )
    }

    static func overlayFrame(geometry: NotchGeometry, closedSize: CGSize, armRun: CGFloat, thicknessScale: Double) -> CGRect {
        overlayLayout(
            islandScreenRect: geometry.frame(for: closedSize),
            floatingGap: geometry.floatingGap,
            armRun: armRun,
            thicknessScale: thicknessScale
        ).overlayScreenRect
    }
}

enum NotchEdgeWaveShaderSource {
    static let metalSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4 color;
        float2 res;
        float2 origin;
        float2 notch;
        float t;
        float clock;
        float mode;
        float progress;
        float fade;
        float floatingIsland;
        float contourCorner;
        float lightSurface;
        float pad0;
        float pad1;
    };

    struct VOut {
        float4 position [[position]];
    };

    vertex VOut edgeWaveVertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        VOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    static float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    static float noise2(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        float a = hash21(i);
        float b = hash21(i + float2(1.0, 0.0));
        float c = hash21(i + float2(0.0, 1.0));
        float d = hash21(i + float2(1.0, 1.0));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    static float fbm(float2 p) {
        float v = 0.0;
        float a = 0.5;
        for (int i = 0; i < 3; i++) {
            v += a * noise2(p);
            p *= 2.03;
            a *= 0.5;
        }
        return v;
    }

    static float radiusWave(float t) {
        float u = clamp(t / 2.8, 0.0, 1.0);
        float s = u * u * (3.0 - 2.0 * u);
        return 42.0 + s * 2200.0;
    }

    static float4 contourOutput(float3 col, float contour, float lightSurface) {
        if (lightSurface > 0.5) {
            float boosted = contour * 1.18;
            float3 pure = clamp(col * 1.06, 0.0, 1.0);
            return float4(pure * boosted, clamp(boosted, 0.0, 0.96));
        }
        return float4(col * contour, clamp(contour, 0.0, 0.92));
    }

    fragment float4 edgeWaveFragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float2 uv = in.position.xy;
        float2 delta = uv - u.origin;
        float angle = atan2(delta.y, delta.x);
        float dist = length(delta);

        float wob = (fbm(float2(angle * 3.0 + u.clock * 0.7, u.clock * 0.4)) - 0.5) * 32.0;

        if (u.mode > 0.5) {
            float maxR = length(max(u.origin, u.res - u.origin)) + 80.0;
            float targetR = mix(maxR, length(u.notch) * 0.45 + 14.0, clamp(u.progress, 0.0, 1.0));
            float ringDist = abs(dist - (targetR + wob));
            float ring = exp(-pow(ringDist / 26.0, 2.0));
            float edge = min(min(uv.x, u.res.x - uv.x), min(uv.y, u.res.y - uv.y));
            float frame = exp(-pow(max(0.0, edge) / 14.0, 2.0)) * 0.55;
            float alpha = (ring * 0.85 + frame * (1.0 - u.progress * 0.5)) * u.fade * u.color.a;
            return contourOutput(u.color.rgb, alpha, u.lightSurface);
        }

        float r = radiusWave(u.t) + wob;
        float ringDist = abs(dist - r);
        float width = 34.0 + u.t * 14.0;
        float wave = exp(-pow(ringDist / width, 2.0));

        float leftD = uv.x;
        float rightD = u.res.x - uv.x;
        float bottomD = u.res.y - uv.y;
        float topD = uv.y;
        float borderD = min(min(leftD, rightD), min(topD, bottomD));
        float rimMask = exp(-pow(max(0.0, borderD - 1.0) / 9.5, 2.0));

        float rimArrival = smoothstep(0.15, 0.55, clamp(u.t / 2.8, 0.0, 1.0));
        float tailFade = 1.0 - smoothstep(1.9, 2.8, u.t);

        float islandMask = 0.0;
        if (u.floatingIsland > 0.5) {
            float2 halfBox = max(u.notch * 0.5, float2(40.0, 14.0));
            float2 q = abs(uv - u.origin) - (halfBox - float2(u.contourCorner));
            float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - u.contourCorner;
            islandMask = exp(-pow(abs(sd) / 8.0, 2.0)) * (1.0 - smoothstep(0.0, 0.8, u.t)) * 0.9;
        }

        float combined = (wave * 0.34 + rimMask * rimArrival * 0.95 + islandMask) * tailFade * u.fade * u.color.a;
        float3 mixed = mix(u.color.rgb, float3(1.0), wave * 0.25);
        return contourOutput(mixed, combined, u.lightSurface);
    }
    """
}

// MARK: - Fluid level physics, brightness observer, modifier indicators & paste trigger

/// Critically-damped spring interpolation for 120Hz notch level gauges so
/// successive volume or brightness steps glide continuously with C1 velocity.
struct NotchFluidLevelSpring: Equatable {
    var startValue: Double = 0
    var startVelocity: Double = 0
    var targetValue: Double = 0
    var startTime: TimeInterval = 0
    var peakEnergy: Double = 0

    static let angularFrequency: Double = 20.0

    func sample(at time: TimeInterval, reduceMotion: Bool = false) -> (value: Double, velocity: Double, energy: Double) {
        let clampedTarget = targetValue.isFinite ? min(1, max(0, targetValue)) : 0
        if reduceMotion {
            return (clampedTarget, 0, 0)
        }
        let dt = max(0, time - startTime)
        let w = Self.angularFrequency
        let x0 = startValue - clampedTarget
        let c2 = startVelocity + w * x0
        let decay = exp(-w * dt)
        let value = min(1, max(0, clampedTarget + (x0 + c2 * dt) * decay))
        let velocity = (startVelocity - w * c2 * dt) * decay
        let impulse = peakEnergy * exp(-dt / 0.26)
        let kinetic = min(0.85, abs(velocity) * 0.22)
        let energy = min(1.0, max(impulse, kinetic))
        return (value, velocity, energy)
    }

    mutating func retarget(to newTarget: Double, at time: TimeInterval, continuing: Bool) {
        let clamped = newTarget.isFinite ? min(1, max(0, newTarget)) : 0
        if continuing {
            let cur = sample(at: time)
            startValue = cur.value
            startVelocity = cur.velocity
            peakEnergy = min(1.0, max(cur.energy * 0.85, 0.35 + abs(clamped - cur.value) * 2.4))
        } else {
            startValue = clamped
            startVelocity = 0
            peakEnergy = 0.55
        }
        targetValue = clamped
        startTime = time
    }
}

/// Filters ambient auto-brightness drift while catching hardware brightness keys,
/// Control Center drags, Touch Bar sliders, and Vorssaint slider changes without duplicates.
struct NotchBrightnessChangeDetector: Equatable {
    private(set) var baseline: Double?
    private(set) var lastUserKeyAt: TimeInterval = -.infinity
    private(set) var lastUserBurstAt: TimeInterval = -.infinity
    private(set) var lastHandledValue: Double?
    private(set) var lastHandledAt: TimeInterval = -.infinity

    mutating func noteKeyPress(at now: TimeInterval) {
        lastUserKeyAt = now
    }

    mutating func noteHandled(level: Double, at now: TimeInterval) {
        guard level.isFinite else { return }
        let clamped = min(1, max(0, level))
        baseline = clamped
        lastHandledValue = clamped
        lastHandledAt = now
        lastUserBurstAt = now
    }

    mutating func observe(level: Double, at now: TimeInterval, forceBoundaryOnKey: Bool = false) -> Double? {
        guard level.isFinite else { return nil }
        let clamped = min(1, max(0, level))
        guard let previous = baseline else {
            baseline = clamped
            return nil
        }
        if let handled = lastHandledValue,
           now - lastHandledAt < 0.25,
           abs(clamped - handled) < 0.008 {
            baseline = clamped
            return nil
        }

        let delta = abs(clamped - previous)
        let recentKey = (now - lastUserKeyAt) < 0.65
        let recentBurst = (now - lastUserBurstAt) < 0.85
        let atBoundary = clamped <= 0.001 || clamped >= 0.999

        let accepted = delta >= 0.014
            || (recentKey && delta >= 0.002)
            || (recentBurst && delta >= 0.004)
            || (forceBoundaryOnKey && recentKey && atBoundary)

        baseline = clamped
        if accepted {
            lastUserBurstAt = now
            return clamped
        }
        return nil
    }
}
