// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchLyricGapView: View {
    let gap: NotchLyricGap
    let playback: NotchPlayback
    let offset: Double
    let label: String
    var side: NotchLyricSide = .leading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let time = playback.position(at: .now) - offset
        Group {
            if reduceMotion {
                let markers = (0...3).map { NotchLyricLine(time: gap.begin + (gap.end - gap.begin) * Double($0) / 3, text: "") }
                let schedule = NotchLyrics(lines: markers, plain: "", instrumental: false)
                TimelineView(.explicit(schedule.changeDates(for: playback, offset: offset, from: .now))) { context in
                    dots(at: playback.position(at: context.date) - offset, discrete: true)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !playback.isPlaying || time < gap.begin || time >= gap.end)) { context in
                    dots(at: playback.position(at: context.date) - offset, discrete: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: side == .trailing ? .trailing : side == .center ? .center : .leading)
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHidden(time < gap.begin || time >= gap.end)
    }

    private func dots(at time: Double, discrete: Bool) -> some View {
        let pose = NotchKaraokeMotion.gap(at: time, begin: gap.begin, end: gap.end, discrete: discrete)
        return HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle().fill(.white.opacity(pose.opacities[index]))
                    .frame(width: 10, height: 10)
            }
        }
        .scaleEffect(pose.scale, anchor: side == .trailing ? .trailing : side == .center ? .center : .leading)
        .opacity(NotchKaraokeMotion.gapOpacity(at: time, begin: gap.begin, end: gap.end, discrete: discrete))
        .padding(.horizontal, 3)
    }
}
