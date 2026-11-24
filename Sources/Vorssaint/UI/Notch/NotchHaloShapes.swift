// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Traces Vorssaint's exact `NotchShape` ("Show Outline") open bottom-U path
/// with optional outward arm extensions along the menu bar edge, or the exact
/// floating-capsule perimeter when on a non-notched display.
struct NotchBottomUShape: Shape {
    var islandRect: CGRect
    var armRun: CGFloat
    var floatingGap: CGFloat?

    private static let tangent: CGFloat = 0.55228475

    func path(in rect: CGRect) -> Path {
        if let floatingGap {
            let capsule = Path(NotchLayout.capsulePath(in: islandRect, gap: floatingGap))
            guard armRun > 0 else { return capsule }
            let body = NotchLayout.capsuleBody(in: islandRect, gap: floatingGap)
            var p = capsule
            let midY = body.midY
            p.move(to: CGPoint(x: max(rect.minX, body.minX - armRun), y: midY))
            p.addLine(to: CGPoint(x: body.minX, y: midY))
            p.move(to: CGPoint(x: body.maxX, y: midY))
            p.addLine(to: CGPoint(x: min(rect.maxX, body.maxX + armRun), y: midY))
            return p
        }

        let w = islandRect.width
        let h = islandRect.height
        let shoulder = NotchLayout.shoulder(height: h)
        let radius = NotchLayout.surfaceRadius(height: h)
        let bottom = min(radius, h / 2, max(0, (w - shoulder * 2) / 2))
        let t = Self.tangent

        let minX = islandRect.minX
        let maxX = islandRect.maxX
        let minY = islandRect.minY
        let maxY = islandRect.maxY

        var p = Path()
        if armRun > 0 {
            p.move(to: CGPoint(x: minX - armRun, y: minY))
            p.addLine(to: CGPoint(x: minX, y: minY))
        } else {
            p.move(to: CGPoint(x: minX, y: minY))
        }

        // Top-left outward shoulder ear (matches NotchShape verbatim)
        p.addCurve(
            to: CGPoint(x: minX + shoulder, y: minY + shoulder),
            control1: CGPoint(x: minX + shoulder * t, y: minY),
            control2: CGPoint(x: minX + shoulder, y: minY + shoulder * (1 - t))
        )
        p.addLine(to: CGPoint(x: minX + shoulder, y: maxY - bottom))

        // Bottom-left corner
        p.addCurve(
            to: CGPoint(x: minX + shoulder + bottom, y: maxY),
            control1: CGPoint(x: minX + shoulder, y: maxY - bottom * (1 - t)),
            control2: CGPoint(x: minX + shoulder + bottom * (1 - t), y: maxY)
        )
        p.addLine(to: CGPoint(x: maxX - shoulder - bottom, y: maxY))

        // Bottom-right corner
        p.addCurve(
            to: CGPoint(x: maxX - shoulder, y: maxY - bottom),
            control1: CGPoint(x: maxX - shoulder - bottom * (1 - t), y: maxY),
            control2: CGPoint(x: maxX - shoulder, y: maxY - bottom * (1 - t))
        )
        p.addLine(to: CGPoint(x: maxX - shoulder, y: minY + shoulder))

        // Top-right outward shoulder ear
        p.addCurve(
            to: CGPoint(x: maxX, y: minY),
            control1: CGPoint(x: maxX - shoulder, y: minY + shoulder * (1 - t)),
            control2: CGPoint(x: maxX - shoulder * t, y: minY)
        )

        if armRun > 0 {
            p.addLine(to: CGPoint(x: maxX + armRun, y: minY))
        }
        return p
    }
}

/// Exact closed fill silhouette matching Vorssaint's `NotchShape`, positioned
/// at `islandRect` inside the halo overlay coordinate space.
struct NotchClosedShellShape: Shape {
    var islandRect: CGRect
    var floatingGap: CGFloat?

    func path(in rect: CGRect) -> Path {
        let local = NotchShape(
            attached: true,
            radius: NotchLayout.surfaceRadius(height: islandRect.height),
            floatingGap: floatingGap
        ).path(in: CGRect(origin: .zero, size: islandRect.size))
        return local.offsetBy(dx: islandRect.minX, dy: islandRect.minY)
    }
}

/// Punches out the exact interior of Vorssaint's notch shell so glow, blur,
/// rays, and level bars remain strictly outside and never bleed into or
/// lighten the black notch surface.
struct NotchOutsideShellMask: View {
    let islandRect: CGRect
    let floatingGap: CGFloat?

    var body: some View {
        ZStack {
            Rectangle().fill(.white)
            NotchClosedShellShape(islandRect: islandRect, floatingGap: floatingGap)
                .fill(.black)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}

/// Tapered trapezoidal light beam used for Organic Rays.
struct NotchRayTrapezoid: Shape {
    var topInset: CGFloat = 0.3
    var bottomInset: CGFloat = 0.0

    func path(in rect: CGRect) -> Path {
        let topHalfInset = rect.width * topInset * 0.5
        let botHalfInset = rect.width * bottomInset * 0.5
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + topHalfInset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - topHalfInset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - botHalfInset, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + botHalfInset, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Crisp four-point prismatic corner star flare.
struct NotchPrismCornerFlare: View {
    let color: Color
    let coreColor: Color
    let scale: CGFloat
    let opacity: Double

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, color.opacity(0.85), coreColor, color.opacity(0.85), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 24 * scale, height: 1.6 * max(0.7, scale * 0.85))
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, color.opacity(0.85), coreColor, color.opacity(0.85), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1.6 * max(0.7, scale * 0.85), height: 22 * scale)
            Circle()
                .fill(coreColor.opacity(0.9))
                .frame(width: 4 * scale, height: 4 * scale)
                .blur(radius: 1.5)
        }
        .opacity(opacity)
    }
}
