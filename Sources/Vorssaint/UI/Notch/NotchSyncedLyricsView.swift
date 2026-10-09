// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

private struct LyricFramesKey: PreferenceKey {
    static var defaultValue: [NotchLyricScrollTarget: CGRect] = [:]
    static func reduce(value: inout [NotchLyricScrollTarget: CGRect], nextValue: () -> [NotchLyricScrollTarget: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
private extension View {
    func lyricAnchor(_ target: NotchLyricScrollTarget) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: LyricFramesKey.self, value: [target: geometry.frame(in: .named("lyricDocument"))])
        })
    }
}

struct NotchSyncedLyricsView: View {
    let lyrics: NotchLyrics
    let playback: NotchPlayback
    let offset: Double
    let waiting: String
    let instrumental: String
    var writtenBy = "Written By"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.explicit(lyrics.changeDates(for: playback, offset: offset, from: .now))) { context in
            let position = playback.position(at: context.date)
            NativeLyricsViewport(lyrics: lyrics, playback: playback, offset: offset, position: position,
                target: lyrics.scrollTarget(at: position, offset: offset, duration: playback.duration),
                gap: lyrics.presentedGap(at: position, offset: offset, duration: playback.duration),
                waiting: waiting, instrumental: instrumental, writtenBy: writtenBy, reduceMotion: reduceMotion)
        }
    }
}

private struct LyricRows: View {
    let lyrics: NotchLyrics
    let playback: NotchPlayback
    let offset: Double
    let position: Double
    let gap: NotchLyricGap?
    let waiting: String
    let instrumental: String
    let writtenBy: String
    let width: Double
    let bottomSpace: Double
    let framesChanged: ([NotchLyricScrollTarget: CGRect]) -> Void

    var body: some View {
        let active = lyrics.activeIndices(at: position, offset: offset, duration: playback.duration)
        let focus = lyrics.focusIndex(at: position, offset: offset)
        let visible = Array(lyrics.lines.enumerated()).filter { !$0.element.text.isEmpty }
        VStack(alignment: .leading, spacing: 0) {
            if focus == nil, gap == nil {
                Text(waiting).font(.caption).foregroundStyle(.secondary).padding(.bottom, 12).lyricAnchor(.start)
            }
            ForEach(visible, id: \.element.id) { index, line in
                if let gap, gap.nextIndex == index {
                    LyricGapSlot(gap: gap, playback: playback, offset: offset, label: instrumental,
                                 side: line.voices.first?.side ?? line.side, position: position).lyricAnchor(.gap(gap.begin))
                }
                VStack(spacing: 2) {
                    if line.voices.isEmpty {
                        NotchKaraokeLine(line: line, playback: playback, offset: offset,
                                        active: active.contains(index), distance: index - (focus ?? index))
                    } else {
                        ForEach(line.voices) { voice in
                            NotchKaraokeLine(line: voice.line, playback: playback, offset: offset,
                                active: voice.isActive(at: position - offset)
                                    || (active.contains(index) && line.end.map { position - offset >= $0 } == true),
                                distance: index - (focus ?? index))
                        }
                    }
                }.padding(.bottom, 12).lyricAnchor(.line(index))
            }
            if let gap, gap.nextIndex == nil {
                LyricGapSlot(gap: gap, playback: playback, offset: offset, label: instrumental, side: .leading, position: position)
                    .lyricAnchor(.gap(gap.begin))
            }
            if !lyrics.writers.isEmpty {
                Text("\(writtenBy): \(lyrics.writers.joined(separator: ", "))")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    .textSelection(.enabled).padding(.top, 18)
            }
        }
        .padding(.top, 6).padding(.bottom, bottomSpace)
        .frame(width: width, alignment: .leading)
        .coordinateSpace(name: "lyricDocument")
        .onPreferenceChange(LyricFramesKey.self, perform: framesChanged)
    }
}

private struct LyricGapSlot: View {
    let gap: NotchLyricGap
    let playback: NotchPlayback
    let offset: Double
    let label: String
    let side: NotchLyricSide
    let position: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let height = NotchKaraokeMotion.gapSlotHeight(at: position - offset, begin: gap.begin, end: gap.end, discrete: reduceMotion)
        NotchLyricGapView(gap: gap, playback: playback, offset: offset, label: label, side: side)
            .padding(.bottom, 12).frame(height: height, alignment: .top).clipped()
    }
}

private struct NativeLyricsViewport: NSViewRepresentable {
    let lyrics: NotchLyrics
    let playback: NotchPlayback
    let offset: Double
    let position: Double
    let target: NotchLyricScrollTarget
    let gap: NotchLyricGap?
    let waiting: String
    let instrumental: String
    let writtenBy: String
    let reduceMotion: Bool

    func makeNSView(context: Context) -> LyricScrollView { LyricScrollView() }
    func updateNSView(_ view: LyricScrollView, context: Context) { view.apply(self) }
    static func dismantleNSView(_ view: LyricScrollView, coordinator: ()) { view.stop() }
}

/// AppKit scrolling is explicitly interpolated on the main run loop. SwiftUI's
/// scrollTo transaction does not control the underlying clip view reliably.
private final class LyricScrollView: NSScrollView {
    private let host = NSHostingView(rootView: AnyView(Color.clear))
    private var input: NativeLyricsViewport?
    private var anchors: [NotchLyricScrollTarget: CGRect] = [:]
    private var lastTarget: NotchLyricScrollTarget?
    private var pending = false
    private var timer: Timer?
    private var scrolling = false
    private var animationStart = 0.0
    private var animationDuration = 0.0
    private var startY = 0.0
    private var lastWidth = 0.0
    private var lastViewportHeight = 0.0
    private var updating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        backgroundColor = .clear
        contentView.drawsBackground = false
        contentView.backgroundColor = .clear
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        host.sizingOptions = [.intrinsicContentSize]
        documentView = host
    }
    required init?(coder: NSCoder) { nil }

    func apply(_ next: NativeLyricsViewport) {
        let previous = input?.target
        input = next
        if previous != next.target || lastTarget == nil { pending = true }
        rebuild()
        // A new verse normally keeps exactly the same layout rectangles.
        // Do not wait for onPreferenceChange to deliver identical anchors again.
        if pending { beginScroll() }
        ensureClock()
    }
    override func layout() {
        super.layout()
        if abs(contentSize.width - lastWidth) > 0.5 || abs(contentSize.height - lastViewportHeight) > 0.5 { rebuild() }
    }
    private func rebuild() {
        guard !updating, let input, contentSize.width > 1 else { return }
        updating = true
        lastWidth = contentSize.width
        lastViewportHeight = contentSize.height
        let position = max(input.position, input.playback.position(at: .now))
        host.rootView = AnyView(LyricRows(lyrics: input.lyrics, playback: input.playback, offset: input.offset,
            position: position, gap: input.gap, waiting: input.waiting, instrumental: input.instrumental,
            writtenBy: input.writtenBy, width: lastWidth, bottomSpace: max(30, lastViewportHeight * 0.6),
            framesChanged: { [weak self] frames in
                DispatchQueue.main.async { self?.received(frames) }
            }).environment(\.colorScheme, .dark))
        host.frame.size = NSSize(width: lastWidth, height: max(1, host.fittingSize.height))
        updating = false
    }
    private func received(_ frames: [NotchLyricScrollTarget: CGRect]) {
        anchors = frames
        let height = max(1, host.fittingSize.height)
        if abs(host.frame.height - height) > 0.25 { host.frame.size.height = height }
        if pending { beginScroll() }
    }
    private func desiredY() -> Double? {
        guard let input else { return nil }
        if input.target == .start { return 0 }
        guard let rect = anchors[input.target] else { return nil }
        let first = input.lyrics.lines.firstIndex { !$0.text.isEmpty }
        let top: Bool
        if case .line(let index) = input.target { top = index == first } else { top = false }
        let y = top ? rect.minY : rect.midY - contentSize.height / 2
        return min(max(0, host.frame.height - contentSize.height), max(0, y))
    }
    private func beginScroll() {
        guard let input, let y = desiredY() else { return }
        let old = lastTarget
        pending = false
        lastTarget = input.target
        scrolling = false
        let handingOff: Bool
        if case .gap = old, case .line = input.target { handingOff = true } else { handingOff = false }
        if old == nil || input.reduceMotion || abs(y - contentView.bounds.minY) < 0.5 {
            move(to: y); return
        }
        startY = contentView.bounds.minY
        animationStart = ProcessInfo.processInfo.systemUptime
        animationDuration = handingOff ? NotchKaraokeMotion.gapHandoffDuration : 0.55
        scrolling = true
        ensureClock()
    }
    private var reflowingGap: Bool {
        guard let input, let gap = input.gap, input.playback.isPlaying, !input.reduceMotion else { return false }
        let time = input.playback.position(at: .now) - input.offset
        let entering = gap.begin > 0 && time >= gap.begin && time < gap.begin + NotchKaraokeMotion.gapEntranceDuration
        return entering || (time >= gap.end && time < gap.end + NotchKaraokeMotion.gapCollapseDuration)
    }
    private func ensureClock() {
        guard timer == nil, scrolling || reflowingGap else { return }
        let clock = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.tick() }
        timer = clock
        RunLoop.main.add(clock, forMode: .common)
    }
    private func tick() {
        // One native clock drives both the clip offset and the releasing row.
        // This avoids depending on a paused inner SwiftUI display timeline to resume.
        if input?.gap != nil { rebuild() }
        if scrolling {
            if let end = desiredY() {
                let p = min(1, max(0, (ProcessInfo.processInfo.systemUptime - animationStart) / max(0.001, animationDuration)))
                let eased = 1 - pow(1 - p, 3)
                move(to: startY + (end - startY) * eased)
                if p >= 1 { scrolling = false }
            } else { scrolling = false }
        }
        if !scrolling, !reflowingGap { stop() }
    }
    private func move(to y: Double) {
        contentView.scroll(to: NSPoint(x: 0, y: y))
        reflectScrolledClipView(contentView)
    }
    func stop() { timer?.invalidate(); timer = nil; scrolling = false }
    override func scrollWheel(with event: NSEvent) {
        scrolling = false
        if !reflowingGap { stop() }
        super.scrollWheel(with: event)
    }
}
