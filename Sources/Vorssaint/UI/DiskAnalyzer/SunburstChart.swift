// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Colours for the map. Hue follows a segment's position around the circle,
/// so a folder and everything inside it share a family of colours, and the
/// whole wheel re-spreads smoothly as the chart zooms. The sweep runs from
/// violet through blue, green and yellow to orange and never reaches red,
/// which stays reserved for items marked to go to the Trash.
enum SunburstPalette {
    static func color(for kind: DiskNode.Kind, mid: Double, depth: Double,
                      dark: Bool, highlighted: Bool = false) -> Color {
        switch kind {
        case .smallFiles:
            return Color(white: dark ? 0.42 : 0.70).opacity(highlighted ? 1 : 0.85)
        case .hidden:
            return Color(white: dark ? 0.27 : 0.55).opacity(highlighted ? 1 : 0.9)
        case .directory, .file:
            let hue = 0.82 - min(1, max(0, mid)) * 0.74
            let level = max(0, depth - 1)
            var saturation = (dark ? 0.66 : 0.58) - level * 0.055
            var brightness = (dark ? 0.86 : 0.90) - level * (dark ? 0.045 : 0.02)
            if kind == .file {
                saturation *= 0.55
                brightness += dark ? -0.06 : 0.04
            }
            if highlighted {
                saturation = min(1, saturation + 0.12)
                brightness = min(1, brightness + 0.1)
            }
            return Color(hue: hue, saturation: max(0.12, saturation), brightness: min(1, brightness))
        }
    }
}

/// The interactive sunburst: the focused folder sits in the middle, its
/// contents fan out in rings, and each segment's angle is its share of the
/// space. Clicking a folder zooms into it; clicking the middle zooms out.
struct SunburstChart: View {
    let focus: DiskNode
    let revision: Int
    let centerTitle: String
    let centerDetail: String
    let centerCaption: String
    let canGoUp: Bool
    let selected: DiskNode?
    let marked: [DiskNode]
    @Binding var hovered: DiskNode?
    let onSelect: (DiskNode) -> Void
    let onUp: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var transition: Transition?
    @State private var progress = 1.0
    @State private var shownFocus: DiskNode?
    @State private var transitionID = 0
    @State private var hoveringCenter = false
    @StateObject private var cache = SunburstLayoutCache()

    static let rings = 6
    private static let minimumSpan = 0.0022

    /// A zoom between a folder and one of its descendants. The base layout
    /// stays fixed while `progress` slides the window over it.
    struct Transition {
        let base: DiskNode
        let window: ClosedRange<Double>
        let depth: Int
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let geometry = SunburstGeometry(radius: size / 2 - 6, rings: Self.rings)
            ZStack {
                SunburstCanvas(drawing: drawing(), progress: progress, geometry: geometry,
                               hovered: hovered, selected: selected,
                               marked: Set(marked.map(ObjectIdentifier.init)), dark: scheme == .dark)
                    .frame(width: size, height: size)
                centerLabel(radius: geometry.centerRadius)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    track(location, in: proxy.size, geometry: geometry)
                case .ended:
                    if hovered != nil { hovered = nil }
                    hoveringCenter = false
                }
            }
            .gesture(SpatialTapGesture().onEnded { value in
                tap(at: value.location, in: proxy.size, geometry: geometry)
            })
        }
        .onAppear { shownFocus = focus }
        .onChange(of: ObjectIdentifier(focus)) { _, _ in animate(to: focus) }
    }

    // MARK: - Drawing state

    private func drawing() -> SunburstDrawing {
        let base = transition?.base ?? focus
        let extra = transition?.depth ?? 0
        let arcs = cache.arcs(for: base, rings: Self.rings + extra, minimumSpan: Self.minimumSpan,
                              revision: revision)
        return SunburstDrawing(base: base, arcs: arcs, window: transition?.window ?? 0...1,
                               depthShift: Double(transition?.depth ?? 0))
    }

    private func animate(to newFocus: DiskNode) {
        defer { shownFocus = newFocus }
        guard let old = shownFocus, old !== newFocus else { return }
        hovered = nil
        if old.isAncestor(of: newFocus), let range = Self.range(of: newFocus, in: old) {
            transition = Transition(base: old, window: range.window, depth: range.depth)
            progress = 0
            withAnimation(.spring(response: 0.55, dampingFraction: 0.92)) { progress = 1 }
        } else if newFocus.isAncestor(of: old), let range = Self.range(of: old, in: newFocus) {
            transition = Transition(base: newFocus, window: range.window, depth: range.depth)
            progress = 1
            withAnimation(.spring(response: 0.5, dampingFraction: 0.95)) { progress = 0 }
        } else {
            transition = nil
            progress = 1
            return
        }
        transitionID += 1
        let token = transitionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard transitionID == token else { return }
            transition = nil
            progress = 1
        }
    }

    /// Where `node` sits inside `ancestor`'s full turn, and how many rings out.
    static func range(of node: DiskNode, in ancestor: DiskNode) -> (window: ClosedRange<Double>, depth: Int)? {
        var start = 0.0
        var span = 1.0
        var depth = 0
        let chain = node.lineage
        guard let index = chain.firstIndex(where: { $0 === ancestor }) else { return nil }
        for (parent, child) in zip(chain[index...], chain[(index + 1)...]) {
            guard parent.size > 0 else { return nil }
            for sibling in parent.children {
                if sibling === child { break }
                start += span * Double(max(0, sibling.size)) / Double(parent.size)
            }
            span *= Double(child.size) / Double(parent.size)
            depth += 1
        }
        guard depth > 0, span > 0 else { return nil }
        return (start...(start + span), depth)
    }

    // MARK: - Interaction

    private func polar(_ location: CGPoint, in size: CGSize) -> (radius: Double, angle: Double) {
        let dx = Double(location.x - size.width / 2)
        let dy = Double(location.y - size.height / 2)
        var angle = atan2(dx, -dy) / (2 * .pi)
        if angle < 0 { angle += 1 }
        return ((dx * dx + dy * dy).squareRoot(), angle)
    }

    private func hit(_ location: CGPoint, in size: CGSize, geometry: SunburstGeometry) -> (center: Bool, arc: DiskAnalyzerSupport.Arc?) {
        let (radius, angle) = polar(location, in: size)
        if radius < geometry.centerRadius { return (true, nil) }
        guard let depth = geometry.ring(at: radius) else { return (false, nil) }
        let arcs = cache.arcs(for: focus, rings: Self.rings, minimumSpan: Self.minimumSpan, revision: revision)
        return (false, DiskAnalyzerSupport.arc(at: angle, depth: depth, in: arcs))
    }

    private func track(_ location: CGPoint, in size: CGSize, geometry: SunburstGeometry) {
        guard transition == nil else { return }
        let result = hit(location, in: size, geometry: geometry)
        hoveringCenter = result.center && canGoUp
        let node = result.arc?.node
        if node !== hovered { hovered = node }
    }

    private func tap(at location: CGPoint, in size: CGSize, geometry: SunburstGeometry) {
        guard transition == nil else { return }
        let result = hit(location, in: size, geometry: geometry)
        if result.center {
            if canGoUp { onUp() }
        } else if let node = result.arc?.node {
            onSelect(node)
        }
    }

    // MARK: - Center

    private func centerLabel(radius: CGFloat) -> some View {
        VStack(spacing: 3) {
            if hoveringCenter && hovered == nil {
                Image(systemName: "arrow.up.left.circle.fill")
                    .font(.system(size: max(16, radius * 0.2)))
                    .foregroundStyle(.secondary)
                    .transition(.scale.combined(with: .opacity))
            }
            Text(centerTitle)
                .font(.system(size: max(11, radius * 0.11), weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(centerDetail)
                .font(.system(size: max(15, radius * 0.2), weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(centerCaption)
                .font(.system(size: max(10, radius * 0.085)))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: radius * 1.6)
        .minimumScaleFactor(0.6)
        .opacity(transition == nil ? 1 : 0.35)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: hoveringCenter)
    }
}

/// Ring radii. The middle disk holds the focused folder's summary; rings
/// thin slightly outwards so the inner, more important levels read first.
struct SunburstGeometry {
    let radius: CGFloat
    let rings: Int

    var centerRadius: CGFloat { radius * 0.27 }

    private var widths: [CGFloat] {
        let weights = (0..<rings).map { pow(0.9, CGFloat($0)) }
        let total = weights.reduce(0, +)
        return weights.map { $0 / total * (radius - centerRadius) }
    }

    /// Outer edge of ring `depth`, continuous so zooms can slide rings in
    /// and out: depth 0 is the center disk's edge, below it the disk shrinks.
    func edge(_ depth: Double) -> CGFloat {
        if depth <= 0 { return centerRadius * CGFloat(max(0, 1 + depth)) }
        let widths = widths
        var edge = centerRadius
        var level = 0
        var remaining = depth
        while remaining > 0 {
            let width = widths[min(level, widths.count - 1)]
            edge += width * CGFloat(min(1, remaining))
            remaining -= 1
            level += 1
        }
        return edge
    }

    func ring(at distance: Double) -> Int? {
        var inner = centerRadius
        for (index, width) in widths.enumerated() {
            if CGFloat(distance) >= inner && CGFloat(distance) < inner + width { return index + 1 }
            inner += width
        }
        return nil
    }
}

struct SunburstDrawing {
    let base: DiskNode
    let arcs: [DiskAnalyzerSupport.Arc]
    let window: ClosedRange<Double>
    let depthShift: Double
}

/// Holds the last layouts so hover and animation frames do not lay the
/// tree out again.
final class SunburstLayoutCache: ObservableObject {
    private struct Key: Hashable {
        let node: ObjectIdentifier
        let rings: Int
        let revision: Int
    }

    private var entries: [Key: [DiskAnalyzerSupport.Arc]] = [:]

    func arcs(for node: DiskNode, rings: Int, minimumSpan: Double, revision: Int) -> [DiskAnalyzerSupport.Arc] {
        let key = Key(node: ObjectIdentifier(node), rings: rings, revision: revision)
        if let cached = entries[key] { return cached }
        if entries.count > 8 { entries.removeAll() }
        let arcs = DiskAnalyzerSupport.sunburst(focus: node, maxDepth: rings, minimumSpan: minimumSpan)
        entries[key] = arcs
        return arcs
    }
}

/// The drawing itself, animatable through `progress`.
private struct SunburstCanvas: View, Animatable {
    let drawing: SunburstDrawing
    var progress: Double
    let geometry: SunburstGeometry
    let hovered: DiskNode?
    let selected: DiskNode?
    /// Items set aside for the Trash; everything inside them is tinted too.
    let marked: Set<ObjectIdentifier>
    let dark: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let shift = drawing.depthShift * progress
            let separator = dark ? Color.black.opacity(0.55) : Color.white.opacity(0.9)
            let rings = Double(geometry.rings)

            // The focused folder's disk, shrinking away while zooming in.
            let disk = geometry.edge(-shift)
            if disk > 0.5 {
                let rect = CGRect(x: center.x - disk, y: center.y - disk, width: disk * 2, height: disk * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.primary.opacity(dark ? 0.07 : 0.05)))
            }

            var labels: [(String, CGPoint, CGFloat, CGFloat)] = []
            for arc in drawing.arcs {
                let depth = Double(arc.depth) - shift
                guard depth > -1, depth - 1 < rings else { continue }
                guard let mapped = DiskAnalyzerSupport.zoomed(start: arc.start, end: arc.end,
                                                              window: drawing.window, progress: progress)
                else { continue }
                let span = mapped.end - mapped.start
                let inner = geometry.edge(depth - 1)
                let outer = geometry.edge(depth)
                guard outer - inner > 0.5, span > 0.0005 else { continue }
                let fade = min(1, max(0, rings + 1 - depth))
                let highlighted = hovered === arc.node
                var color = SunburstPalette.color(for: arc.node.kind, mid: (mapped.start + mapped.end) / 2,
                                                  depth: max(1, depth), dark: dark, highlighted: highlighted)
                if !marked.isEmpty, isMarked(arc.node) {
                    color = Color.red.opacity(highlighted ? 0.85 : 0.6)
                }
                let path = Self.segment(center: center, inner: inner, outer: outer,
                                        start: mapped.start, end: mapped.end)
                context.fill(path, with: .color(color.opacity(fade)), style: FillStyle(eoFill: true))
                context.stroke(path, with: .color(separator), lineWidth: span > 0.004 ? 1 : 0.5)

                // Names on segments roomy enough to carry them, inner rings
                // first, only while the chart is still.
                if drawing.depthShift == 0, arc.depth <= 2, arc.node.isFileSystemItem {
                    let mid = (inner + outer) / 2
                    let room = CGFloat(span) * 2 * .pi * mid
                    labels.append((arc.node.name,
                                   Self.point(center: center, radius: mid, angle: (mapped.start + mapped.end) / 2),
                                   min(room * 0.8, 120), outer - inner))
                }
            }
            if let selected, let arc = drawing.arcs.first(where: { $0.node === selected }), drawing.depthShift == 0,
               let mapped = DiskAnalyzerSupport.zoomed(start: arc.start, end: arc.end, window: drawing.window,
                                                       progress: progress) {
                let path = Self.segment(center: center, inner: geometry.edge(Double(arc.depth) - 1),
                                        outer: geometry.edge(Double(arc.depth)),
                                        start: mapped.start, end: mapped.end)
                context.stroke(path, with: .color(.accentColor), lineWidth: 3)
            }
            if let hovered, let arc = drawing.arcs.first(where: { $0.node === hovered }), drawing.depthShift == 0,
               let mapped = DiskAnalyzerSupport.zoomed(start: arc.start, end: arc.end, window: drawing.window,
                                                       progress: progress) {
                let path = Self.segment(center: center, inner: geometry.edge(Double(arc.depth) - 1),
                                        outer: geometry.edge(Double(arc.depth)),
                                        start: mapped.start, end: mapped.end)
                context.stroke(path, with: .color(dark ? .white : .black.opacity(0.75)), lineWidth: 2)
            }
            // Inner rings place first; a name that would touch one already
            // placed is left to the list and the center readout instead.
            labels.sort { $0.3 > $1.3 }
            var placed: [CGRect] = []
            for (name, point, width, height) in labels where height >= 15 && width >= 28 {
                let text = context.resolve(Text(name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(dark ? .white.opacity(0.92) : .black.opacity(0.78)))
                // Unbounded, so a long name reports its real width instead of
                // a wrapped one that would then be drawn at full length.
                let measured = text.measure(in: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude))
                guard measured.width <= width, measured.height <= height else { continue }
                let frame = CGRect(x: point.x - measured.width / 2, y: point.y - measured.height / 2,
                                   width: measured.width, height: measured.height).insetBy(dx: -3, dy: -2)
                guard !placed.contains(where: { $0.intersects(frame) }) else { continue }
                placed.append(frame)
                context.draw(text, at: point)
            }
        }
    }

    /// The item, or a folder holding it, is marked for the Trash.
    private func isMarked(_ node: DiskNode) -> Bool {
        var current: DiskNode? = node
        while let step = current {
            if marked.contains(ObjectIdentifier(step)) { return true }
            current = step.parent
        }
        return false
    }

    /// Clockwise from twelve o'clock, as fractions of a turn.
    private static func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = angle * 2 * .pi - .pi / 2
        return CGPoint(x: center.x + radius * CGFloat(cos(radians)),
                       y: center.y + radius * CGFloat(sin(radians)))
    }

    private static func segment(center: CGPoint, inner: CGFloat, outer: CGFloat,
                                start: Double, end: Double) -> Path {
        var path = Path()
        if end - start >= 0.9999 {
            path.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
            if inner > 0 {
                path.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner,
                                           width: inner * 2, height: inner * 2))
            }
            return path
        }
        let from = Angle(radians: start * 2 * .pi - .pi / 2)
        let to = Angle(radians: end * 2 * .pi - .pi / 2)
        path.addArc(center: center, radius: outer, startAngle: from, endAngle: to, clockwise: false)
        if inner > 0 {
            path.addArc(center: center, radius: inner, startAngle: to, endAngle: from, clockwise: true)
        } else {
            path.addLine(to: center)
        }
        path.closeSubpath()
        return path
    }
}
