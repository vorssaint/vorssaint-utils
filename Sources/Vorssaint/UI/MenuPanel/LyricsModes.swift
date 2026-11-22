// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The ways the wallpaper and the lock screen can show a lyric.
enum LyricsMode: String, CaseIterable, Identifiable {
    case constellation, scroll, typewriter, big, karaoke, pop, highlight, stack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .constellation: return "Graph"
        case .scroll: return "Scrolling"
        case .typewriter: return "Typewriter"
        case .big: return "Big"
        case .karaoke: return "Karaoke"
        case .pop: return "Word pop"
        case .highlight: return "Highlight"
        case .stack: return "Stack"
        }
    }

    var symbol: String {
        switch self {
        case .constellation: return "sparkles"
        case .scroll: return "text.alignleft"
        case .typewriter: return "keyboard"
        case .big: return "textformat.size.larger"
        case .karaoke: return "music.mic"
        case .pop: return "bubbles.and.sparkles"
        case .highlight: return "highlighter"
        case .stack: return "list.bullet.indent"
        }
    }

    /// A stored choice from an earlier build, or none, still reads as a mode.
    static func from(_ stored: String) -> LyricsMode {
        LyricsMode(rawValue: stored) ?? (stored == "classic" ? .scroll : .constellation)
    }

    static var current: LyricsMode {
        from(UserDefaults.standard.string(forKey: DefaultsKey.lyricsWallpaperStyle) ?? "")
    }

    var next: LyricsMode {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }
}

/// Where the current line stands: its words, how far through it the song is,
/// and its neighbours. Catalogs time whole lines, so each word's moment is
/// estimated from its length, with a pause after punctuation.
struct LyricsLineClock {
    let index: Int
    let text: String
    let words: [String]
    let progress: Double
    let edges: [(start: Double, end: Double)]
    let previous: String?
    let next: String?

    init?(lyrics: NotchLyrics, playback: NotchPlayback, offset: Double, date: Date) {
        let position = playback.position(at: date)
        guard let i = lyrics.activeIndex(at: position, offset: offset) else { return nil }
        index = i
        text = lyrics.lines[i].text
        words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        previous = i > 0 ? lyrics.lines[i - 1].text : nil
        next = i + 1 < lyrics.lines.count ? lyrics.lines[i + 1].text : nil
        let start = lyrics.lines[i].time + offset
        let end = i + 1 < lyrics.lines.count ? lyrics.lines[i + 1].time + offset : start + 5
        let gap = max(end - start, 0.8)
        let natural = Double(words.count) * 0.6 + 1
        let spoken = gap <= natural + 2 ? gap * 0.94 : natural
        progress = min(1, max(0, (position - start) / spoken))
        let weights = words.map { word -> Double in
            let pause = word.last.map { ",.;:!?…".contains($0) } == true ? 2.5 : 0
            return Double(max(word.count, 2)) + pause
        }
        let total = max(weights.reduce(0, +), 1)
        var run = 0.0
        edges = weights.map { weight in
            defer { run += weight }
            return (run / total, (run + weight) / total)
        }
    }
}

/// Words laid out in centred rows that wrap, so a line can reveal word by
/// word without the rest moving.
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 8

    private struct Row { var indices: [Int] = []; var sizes: [CGSize] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            if rows[rows.count - 1].width + extra + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].sizes.append(size)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 10_000
        let rows = rows(width: width, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: proposal.width ?? (rows.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for (slot, index) in row.indices.enumerated() {
                let size = row.sizes[slot]
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
}

/// Picks the view for a mode. The graph and the scrolling column keep their
/// own views; the rest are text modes that share one clock.
struct LyricsModeView: View {
    let mode: LyricsMode
    let lyrics: NotchLyrics
    let playback: NotchPlayback
    let offset: Double
    let accent: Color
    var compact = false

    var body: some View {
        switch mode {
        case .constellation:
            ConstellationLyricsView(lyrics: lyrics, playback: playback, offset: offset, compact: compact, accent: accent)
        case .scroll:
            ScrollLyricsView(lyrics: lyrics, playback: playback, offset: offset, compact: compact)
        default:
            LyricsTextModeView(mode: mode, lyrics: lyrics, playback: playback, offset: offset, accent: accent)
        }
    }
}

struct LyricsTextModeView: View {
    let mode: LyricsMode
    let lyrics: NotchLyrics
    let playback: NotchPlayback
    let offset: Double
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let unit = max(proxy.size.height / 10, 8)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playback.isPlaying)) { context in
                if let clock = LyricsLineClock(lyrics: lyrics, playback: playback, offset: offset, date: context.date) {
                    content(clock, unit: unit, date: context.date)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: clock.index)
                }
            }
        }
    }

    @ViewBuilder private func content(_ clock: LyricsLineClock, unit: CGFloat, date: Date) -> some View {
        switch mode {
        case .typewriter: typewriter(clock, unit: unit, date: date)
        case .big: big(clock, unit: unit)
        case .karaoke: karaoke(clock, unit: unit)
        case .pop: pop(clock, unit: unit)
        case .highlight: highlight(clock, unit: unit)
        default: stack(clock, unit: unit)
        }
    }

    // MARK: Typewriter

    private func typewriter(_ clock: LyricsLineClock, unit: CGFloat, date: Date) -> some View {
        let total = clock.text.count
        let typed = min(total, Int(min(1, clock.progress / 0.85) * Double(total) + 0.5))
        let cursor = Int(date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? "▍" : " "
        return VStack(alignment: .leading, spacing: unit * 0.4) {
            if let previous = clock.previous {
                Text(previous).font(.system(size: unit * 0.36, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3)).lineLimit(2)
            }
            Text(String(clock.text.prefix(typed)) + cursor)
                .font(.system(size: unit * 0.6, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white).multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Big

    private func big(_ clock: LyricsLineClock, unit: CGFloat) -> some View {
        Text(clock.text.isEmpty ? "♪" : clock.text)
            .font(.system(size: unit * 2.6, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.2).lineLimit(5).multilineTextAlignment(.center)
            .foregroundStyle(.white).shadow(color: accent.opacity(0.6), radius: 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(clock.index)
            .transition(.asymmetric(insertion: .scale(scale: 0.88).combined(with: .opacity), removal: .opacity))
    }

    // MARK: Karaoke

    private func karaoke(_ clock: LyricsLineClock, unit: CGFloat) -> some View {
        VStack(spacing: unit * 0.5) {
            FlowLayout(spacing: unit * 0.28, lineSpacing: unit * 0.12) {
                ForEach(Array(clock.words.enumerated()), id: \.offset) { index, word in
                    let edge = clock.edges[index]
                    let fill = min(1, max(0, (clock.progress - edge.start) / max(0.0001, edge.end - edge.start)))
                    Text(word).font(.system(size: unit * 0.82, weight: .bold, design: .rounded))
                        .foregroundStyle(fill >= 1 ? accent : (fill > 0 ? Color.white : Color.white.opacity(0.35)))
                        .scaleEffect(fill > 0 && fill < 1 ? 1.08 : 1)
                }
            }
            if let next = clock.next {
                Text(next).font(.system(size: unit * 0.36, weight: .medium)).lineLimit(2)
                    .multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, unit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Word pop

    private func pop(_ clock: LyricsLineClock, unit: CGFloat) -> some View {
        FlowLayout(spacing: unit * 0.3, lineSpacing: unit * 0.1) {
            ForEach(Array(clock.words.enumerated()), id: \.offset) { index, word in
                let edge = clock.edges[index]
                let t = min(1, max(0, (clock.progress - edge.start) / 0.12))
                let latest = clock.progress >= edge.start && clock.progress <= edge.end
                // Overshoots a little as it lands, then settles.
                let scale = t <= 0 ? 0.001 : 0.45 + 0.55 * (1 - pow(1 - t, 3)) + 0.14 * sin(t * .pi)
                Text(word).font(.system(size: unit * 0.98, weight: .heavy, design: .rounded))
                    .foregroundStyle(latest ? accent : .white)
                    .scaleEffect(scale).opacity(min(1, t * 3))
            }
        }
        .padding(.horizontal, unit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Highlight

    private func highlight(_ clock: LyricsLineClock, unit: CGFloat) -> some View {
        Text(clock.text.isEmpty ? "♪" : clock.text)
            .font(.system(size: unit * 0.72, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center).foregroundStyle(.black.opacity(0.88))
            .padding(.horizontal, unit * 0.55).padding(.vertical, unit * 0.34)
            .background(RoundedRectangle(cornerRadius: unit * 0.38, style: .continuous).fill(.white.opacity(0.96)))
            .shadow(color: accent.opacity(0.5), radius: 26, y: 8)
            .padding(.horizontal, unit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(clock.index)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Stack

    private func stack(_ clock: LyricsLineClock, unit: CGFloat) -> some View {
        let active = clock.index
        let range = max(0, active - 2)...min(lyrics.lines.count - 1, active + 2)
        return ZStack {
            ForEach(Array(range), id: \.self) { index in
                let distance = index - active
                let text = lyrics.lines[index].text
                Text(text.isEmpty ? "♪" : text)
                    .font(.system(size: unit * (distance == 0 ? 0.95 : 0.52), weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(distance == 0 ? 1 : max(0.12, 0.34 - Double(abs(distance) - 1) * 0.14)))
                    .shadow(color: distance == 0 ? accent.opacity(0.7) : .clear, radius: 18)
                    .multilineTextAlignment(.center).lineLimit(2).padding(.horizontal, unit)
                    .offset(y: CGFloat(distance) * unit * 1.6)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
