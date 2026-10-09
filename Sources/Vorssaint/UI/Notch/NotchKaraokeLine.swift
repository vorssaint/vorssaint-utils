// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Native TextKit shapes every word. Playback-driven transforms and feathered
/// glyph masks preserve the source's syllables, including simultaneous voices.
struct NotchKaraokeLine: View {
    let line: NotchLyricLine
    let playback: NotchPlayback
    let offset: Double
    let active: Bool
    var distance = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var alignment: Alignment {
        switch line.side { case .leading: return .leading; case .trailing: return .trailing; case .center: return .center }
    }
    private var anchor: UnitPoint {
        switch line.side { case .leading: return .leading; case .trailing: return .trailing; case .center: return .center }
    }
    var body: some View {
        Group {
            if line.syllables.isEmpty {
                Text(line.text)
                    .font(.system(size: line.background ? NotchKaraokeMotion.backgroundFontSize : NotchKaraokeMotion.fontSize, weight: .bold))
                    .foregroundStyle(.white.opacity(active ? 1 : 0.34))
                    .multilineTextAlignment(line.side == .trailing ? .trailing : line.side == .center ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else if reduceMotion {
                let boundaries = Set(line.syllables.flatMap { [$0.begin, $0.end] }).sorted()
                let schedule = NotchLyrics(lines: boundaries.map { .init(time: $0, text: "") }, plain: "", instrumental: false)
                TimelineView(.explicit(schedule.changeDates(for: playback, offset: offset, from: .now))) { context in
                    text(at: context.date, discrete: true)
                }
            } else {
                let time = playback.position(at: .now) - offset
                TimelineView(.animation(minimumInterval: 1 / 60,
                    paused: !playback.isPlaying || !NotchKaraokeMotion.needsClock(at: time, begin: line.time, end: line.end))) { context in
                    text(at: context.date, discrete: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .scaleEffect(reduceMotion || active ? 1 : 0.93, anchor: anchor)
        .blur(radius: reduceMotion || active ? 0 : min(2.8, 0.85 + Double(abs(distance)) * 0.35))
        .opacity(active ? 1 : max(0.6, 1 - Double(abs(distance)) * 0.07))
        .animation(reduceMotion ? nil : .spring(duration: 0.62, bounce: 0.12), value: active)
        .animation(reduceMotion ? nil : .spring(duration: 0.62, bounce: 0.12).delay(min(0.12, Double(abs(distance)) * 0.015)), value: distance)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.text)
    }
    private func text(at date: Date, discrete: Bool) -> some View {
        NativeKaraokeText(line: line, position: playback.position(at: date) - offset, active: active, discrete: discrete)
    }
}

private struct NativeKaraokeText: View {
    let line: NotchLyricLine
    let position: Double
    let active: Bool
    let discrete: Bool
    @StateObject private var renderer = KaraokeTextRenderer()

    var body: some View {
        let _ = renderer.update(line: line)
        KaraokeCanvasLayout(renderer: renderer) {
            Canvas(rendersAsynchronously: false) { graphics, size in
                graphics.withCGContext { context in
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                    renderer.render(width: size.width, position: position, active: active, discrete: discrete, context: context)
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct KaraokeCanvasLayout: Layout {
    let renderer: KaraokeTextRenderer
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        renderer.size(width: proposal.width ?? 250)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

private final class KaraokeTextRenderer: ObservableObject {
    struct Segment { let timing: NotchLyricSyllable; let rects: [CGRect] }
    struct Word {
        let glyphs: NSRange
        let rect: CGRect
        let segments: [Segment]
        let begin: Double
        let end: Double
        let background: Bool
    }
    private let storage = NSTextStorage()
    private let textLayout = NSLayoutManager()
    private let container = NSTextContainer(size: NSSize(width: 250, height: CGFloat.greatestFiniteMagnitude))
    private var line: NotchLyricLine?
    private var measuredWidth = 0.0
    private var words: [Word] = []
    private let origin = CGPoint(x: 0, y: 6)
    private let feather = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0)
    ] as CFArray, locations: [0, 1])!
    init() {
        container.lineFragmentPadding = 0
        textLayout.addTextContainer(container)
        storage.addLayoutManager(textLayout)
    }

    func update(line: NotchLyricLine) {
        if self.line != line {
            self.line = line
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.alignment = line.side == .trailing ? .right : line.side == .center ? .center : .left
            let size = line.background ? NotchKaraokeMotion.backgroundFontSize : NotchKaraokeMotion.fontSize
            storage.setAttributedString(NSAttributedString(string: line.text, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph
            ]))
            measuredWidth = 0
        }
    }
    func size(width: Double) -> CGSize {
        measure(width: max(1, width))
        return CGSize(width: width, height: ceil(textLayout.usedRect(for: container).height) + 12)
    }
    private func rects(for range: NSRange) -> [CGRect] {
        var result: [CGRect] = []
        textLayout.enumerateLineFragments(forGlyphRange: range) { _, _, _, fragment, _ in
            let intersection = NSIntersectionRange(range, fragment)
            if intersection.length > 0 {
                result.append(self.textLayout.boundingRect(forGlyphRange: intersection, in: self.container)
                    .offsetBy(dx: self.origin.x, dy: self.origin.y))
            }
        }
        return result
    }
    private func measure(width: Double) {
        guard measuredWidth != width, let line else { return }
        measuredWidth = width
        container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textLayout.ensureLayout(for: container)
        let regex = try! NSRegularExpression(pattern: #"\S+"#)
        words = regex.matches(in: line.text, range: NSRange(location: 0, length: storage.length)).map { match in
            let glyphs = textLayout.glyphRange(forCharacterRange: match.range, actualCharacterRange: nil)
            let segments = line.syllables.compactMap { syllable -> Segment? in
                let intersection = NSIntersectionRange(syllable.range, match.range)
                guard intersection.length > 0 else { return nil }
                let range = textLayout.glyphRange(forCharacterRange: intersection, actualCharacterRange: nil)
                return Segment(timing: syllable, rects: rects(for: range))
            }
            let rect = rects(for: glyphs).reduce(CGRect.null) { $0.union($1) }
            return Word(glyphs: glyphs, rect: rect, segments: segments,
                        begin: segments.map { $0.timing.begin }.min() ?? line.time,
                        end: segments.map { $0.timing.end }.max() ?? line.end ?? line.time,
                        background: line.background || (!segments.isEmpty && segments.allSatisfy { $0.timing.background }))
        }
    }

    func render(width: Double, position: Double, active: Bool, discrete: Bool, context: CGContext) {
        guard let line else { return }
        measure(width: max(1, width))
        let held = active && line.end.map { position >= $0 } == true
        let activity = discrete || held ? (active ? 1.0 : 0) : NotchKaraokeMotion.activity(at: position, begin: line.time, end: line.end)
        for word in words {
            let pose = NotchKaraokeMotion.word(at: position, begin: word.begin, end: word.end,
                                              background: word.background, discrete: discrete)
            context.saveGState()
            context.translateBy(x: word.rect.midX, y: word.rect.midY + pose.lift * activity)
            let scale = 1 + (pose.scale - 1) * activity
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -word.rect.midX, y: -word.rect.midY)
            if pose.emphasis > 0, activity > 0, word.glyphs.length > 1 {
                let progress = min(1, max(0, (position - word.begin) / max(0.001, word.end - word.begin)))
                for index in 0..<word.glyphs.length {
                    context.saveGState()
                    context.translateBy(x: 0, y: NotchKaraokeMotion.letterLift(index: index, count: word.glyphs.length,
                                                                          progress: progress, emphasis: pose.emphasis) * activity)
                    draw(word, glyphs: NSRange(location: word.glyphs.location + index, length: 1), activity: activity, glow: pose.glow, position: position, discrete: discrete, context: context)
                    context.restoreGState()
                }
            } else { draw(word, glyphs: word.glyphs, activity: activity, glow: pose.glow, position: position, discrete: discrete, context: context) }
            context.restoreGState()
        }
    }

    private func draw(_ word: Word, glyphs: NSRange, activity: Double, glow: Double, position: Double, discrete: Bool, context: CGContext) {
        context.saveGState()
        context.setAlpha(word.background ? 0.27 : 0.34)
        textLayout.drawGlyphs(forGlyphRange: glyphs, at: origin)
        context.restoreGState()
        guard activity > 0 else { return }
        if word.segments.isEmpty {
            context.saveGState()
            context.setAlpha(activity)
            textLayout.drawGlyphs(forGlyphRange: glyphs, at: origin)
            context.restoreGState()
            return
        }
        for segment in word.segments {
            let progress = discrete ? (position >= segment.timing.begin ? 1.0 : 0) : segment.timing.progress(at: position)
            guard progress > 0 else { continue }
            var remaining = segment.rects.reduce(0) { $0 + $1.width } * progress
            for rect in segment.rects {
                let fill = min(rect.width, remaining)
                remaining -= fill
                guard fill > 0 else { continue }
                context.saveGState()
                context.clip(to: rect.insetBy(dx: -2, dy: -5))
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                context.setAlpha(activity * (word.background ? 0.78 : 1))
                if !discrete, glow > 0 {
                    context.setShadow(offset: .zero, blur: glow, color: NSColor.white.withAlphaComponent(0.35).cgColor)
                }
                textLayout.drawGlyphs(forGlyphRange: glyphs, at: origin)
                context.setShadow(offset: .zero, blur: 0, color: nil)
                context.setBlendMode(.destinationIn)
                context.setAlpha(1)
                context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                if discrete || progress >= 1 { context.fill(rect.insetBy(dx: -2, dy: -5)) }
                else {
                    let edge = rect.minX + fill
                    let soft = min(9, rect.width * 0.3)
                    context.drawLinearGradient(feather, start: CGPoint(x: edge - soft / 2, y: rect.midY),
                                               end: CGPoint(x: edge + soft / 2, y: rect.midY),
                                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                context.setBlendMode(.normal)
                context.endTransparencyLayer()
                context.restoreGState()
            }
        }
    }
}
