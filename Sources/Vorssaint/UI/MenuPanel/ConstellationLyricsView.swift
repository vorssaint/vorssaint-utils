// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Lyrics as a constellation: every word of the current line is a star joined
/// to its neighbours by thin lines, and the word being sung swells into a
/// glowing blue headline with a halo. Word timing is estimated from the
/// line's timing, weighted by word length, since catalogs time whole lines.
struct ConstellationLyricsView: View {
    @Environment(\.lyricsAnimationsActive) private var active
    let lyrics: NotchLyrics
    let playback: NotchPlayback
    let offset: Double
    /// A smaller band for the lock screen, between its clock and its login.
    var compact = false
    var accent = Color(red: 0.43, green: 0.61, blue: 1.0)

    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private var glow: Color { accent }
    /// Idle stars and lines: the accent washed toward white.
    private var soft: Color {
        Color(nsColor: NSColor(accent).blended(withFraction: 0.55, of: .white) ?? .white)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playback.isPlaying || !active)) { context in
            Canvas { gc, size in draw(&gc, size: size, now: context.date) }
        }
    }

    private func draw(_ gc: inout GraphicsContext, size: CGSize, now: Date) {
        let position = playback.position(at: now)
        guard let index = lyrics.activeIndex(at: position, offset: offset) else { return }
        let line = lyrics.lines[index]
        let words = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return }

        let start = line.time + offset
        let next = index + 1 < lyrics.lines.count ? lyrics.lines[index + 1].time + offset : start + 5
        // The line's own span is the best clock there is: sing it across nearly
        // all of it, unless a long instrumental gap follows, then a natural pace.
        let gap = max(next - start, 0.8)
        let natural = Double(words.count) * 0.6 + 1
        let spoken = gap <= natural + 2 ? gap * 0.94 : natural
        let progress = min(1, max(0, (position - start) / spoken))
        let appear = min(1, max(0, (position - start) / 0.6))

        // Word intervals in progress space, weighted by length.
        // Longer words take longer, and a word before a comma or full stop
        // carries the pause that follows it.
        let weights = words.map { word -> Double in
            let pause = word.last.map { ",.;:!?…".contains($0) } == true ? 1.5 : 0
            return LyricsLineClock.syllables(in: word) + pause
        }
        let total = weights.reduce(0, +)
        var edges: [(Double, Double)] = []
        var run = 0.0
        for weight in weights { edges.append((run / total, (run + weight) / total)); run += weight }

        // Layout: jittered rows in reading order, steady for this line.
        var rng = SplitMix(state: UInt64(truncatingIfNeeded: index) &* 7919 &+ UInt64(words.count))
        let area = compact
            ? CGRect(x: size.width * 0.1, y: size.height * 0.27, width: size.width * 0.8, height: size.height * 0.24)
            : CGRect(x: size.width * 0.12, y: size.height * 0.22, width: size.width * 0.76, height: size.height * 0.56)
        let scale: CGFloat = compact ? 0.55 : 1
        let columns = max(2, Int(ceil(sqrt(Double(words.count) * 1.7))))
        let rows = max(1, Int(ceil(Double(words.count) / Double(columns))))
        let cell = CGSize(width: area.width / CGFloat(columns), height: area.height / CGFloat(rows))
        let points: [CGPoint] = words.indices.map { i in
            let column = i % columns, row = i / columns
            let jx = CGFloat.random(in: -0.32...0.32, using: &rng), jy = CGFloat.random(in: -0.32...0.32, using: &rng)
            return CGPoint(x: area.minX + (CGFloat(column) + 0.5 + jx) * cell.width,
                           y: area.minY + (CGFloat(row) + 0.5 + jy) * cell.height)
        }

        // Links: each star to the next, plus a few extra chords.
        var links: [(Int, Int)] = words.indices.dropLast().map { ($0, $0 + 1) }
        for i in words.indices where words.count > 3 {
            if Double.random(in: 0...1, using: &rng) < 0.45 {
                let j = (i + 2 + Int.random(in: 0...2, using: &rng)) % words.count
                if j != i, !links.contains(where: { ($0.0, $0.1) == (i, j) || ($0.0, $0.1) == (j, i) }) { links.append((i, j)) }
            }
        }

        let emphasis: [Double] = edges.map { low, high in
            if progress >= low && progress <= high { return 1 }
            let distance = progress < low ? low - progress : progress - high
            return max(0, 1 - distance / 0.16)
        }
        let reached = edges.map { progress >= $0.0 }

        for (a, b) in links {
            let strength = (reached[a] || reached[b]) ? 0.55 : 0.22
            var path = Path()
            path.move(to: points[a]); path.addLine(to: points[b])
            gc.stroke(path, with: .color(soft.opacity(strength * appear)), lineWidth: 1.1)
        }

        for i in words.indices {
            let e = emphasis[i]
            let size = (22 + 66 * e * e + (reached[i] ? 6 : 0)) * scale
            let color = e > 0.05 ? glow.opacity(0.55 + 0.45 * e) : soft.opacity(reached[i] ? 0.8 : 0.5)
            let anchor = CGPoint(x: points[i].x, y: points[i].y + size * 0.55)
            let text = Text(words[i]).font(.system(size: size, weight: .bold, design: .rounded)).foregroundColor(color)
            if e > 0.3 {
                // A cheap glow: a soft radial wash behind the word, no per-frame blur.
                let width = size * Double(max(words[i].count, 2)) * 0.62, height = size * 1.5
                let rect = CGRect(x: anchor.x - width / 2, y: anchor.y - height / 2, width: width, height: height)
                gc.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(colors: [glow.opacity(0.35 * e * appear), .clear]),
                    center: anchor, startRadius: 0, endRadius: width / 2))
            }
            gc.opacity = appear
            gc.draw(gc.resolve(text), at: anchor, anchor: .center)
            gc.opacity = 1
            star(&gc, at: points[i], radius: (6 + 10 * e) * scale, color: e > 0.05 ? glow : soft, alpha: appear)
            if e > 0.6 {
                let halo = Path(ellipseIn: CGRect(x: points[i].x - 26 * scale, y: points[i].y - 26 * scale, width: 52 * scale, height: 52 * scale))
                gc.stroke(halo, with: .color(glow.opacity(0.7 * e * appear)), lineWidth: 1.6)
            }
        }
    }

    private func star(_ gc: inout GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color, alpha: Double) {
        let k = radius * 0.14
        var path = Path()
        path.move(to: CGPoint(x: point.x, y: point.y - radius))
        path.addQuadCurve(to: CGPoint(x: point.x + radius, y: point.y), control: CGPoint(x: point.x + k, y: point.y - k))
        path.addQuadCurve(to: CGPoint(x: point.x, y: point.y + radius), control: CGPoint(x: point.x + k, y: point.y + k))
        path.addQuadCurve(to: CGPoint(x: point.x - radius, y: point.y), control: CGPoint(x: point.x - k, y: point.y + k))
        path.addQuadCurve(to: CGPoint(x: point.x, y: point.y - radius), control: CGPoint(x: point.x - k, y: point.y - k))
        gc.fill(path, with: .color(color.opacity(alpha)))
    }
}
