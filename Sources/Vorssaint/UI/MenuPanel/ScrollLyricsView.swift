// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Ordinary scrolling lyrics: the current line large and bright in a column
/// that keeps it in view, the lines around it fading with distance. It
/// redraws only at line boundaries, with no clock running while paused.
struct ScrollLyricsView: View {
    let lyrics: NotchLyrics
    let playback: NotchPlayback
    let offset: Double
    /// A shorter, centred column for the lock screen's band.
    var compact = false

    var body: some View {
        TimelineView(.explicit(lyrics.changeDates(for: playback, offset: offset, from: Date()))) { context in
            column(active: lyrics.activeIndex(at: playback.position(at: context.date), offset: offset))
        }
    }

    private func column(active: Int?) -> some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: compact ? .center : .leading, spacing: compact ? 10 : 22) {
                        Color.clear.frame(height: proxy.size.height * 0.4)
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            let distance = active.map { abs(index - $0) } ?? 99
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: (index == active ? 46 : 34) * (compact ? 0.55 : 1), weight: .bold))
                                .multilineTextAlignment(compact ? .center : .leading)
                                .foregroundStyle(.white.opacity(index == active ? 1 : max(0.16, 0.55 - Double(distance) * 0.13)))
                                .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                                .id(index)
                        }
                        Color.clear.frame(height: proxy.size.height * 0.5)
                    }
                }
                .scrollDisabled(true)
                .onChange(of: active) { _, new in
                    guard let new else { return }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                        reader.scrollTo(new, anchor: UnitPoint(x: 0.5, y: compact ? 0.5 : 0.4))
                    }
                }
                .onAppear {
                    if let active { reader.scrollTo(active, anchor: UnitPoint(x: 0.5, y: compact ? 0.5 : 0.4)) }
                }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                     .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }
}
