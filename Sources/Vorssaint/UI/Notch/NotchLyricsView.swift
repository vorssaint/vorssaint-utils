// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchLyricsView: View {
    let playback: NotchPlayback
    @ObservedObject private var service = NotchLyricsService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchLyricsOnline) private var online = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchMusicExtrasStrings { FeatureStrings.notchMusicExtras(l10n.language) }

    // The verses sit on the island itself, as a player's own lyrics do, and
    // a song without them says so like the island's other empty pages.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lyrics = service.lyrics {
                if lyrics.instrumental {
                    NotchEmptyView(symbol: "music.note", message: text.instrumental) {
                        NotchPillButton(title: text.importLyrics, action: service.importLyrics)
                    }
                } else if !lyrics.lines.isEmpty, playback.hasPosition {
                    synced(lyrics)
                    // Importing is a one-off; it shares the timing row as an
                    // icon instead of a row of its own under the verses.
                    HStack(spacing: 10) {
                        importButton
                        Text(text.offset).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        // Hit the whole timing row height, not just the thin symbol.
                        Button { service.adjustOffset(by: -0.25) } label: {
                            Image(systemName: "minus")
                                .frame(width: 24, height: 18)
                                .contentShape(Rectangle())
                        }
                            .help(text.earlier).accessibilityLabel(text.earlier)
                        Button { service.resetOffset() } label: {
                            Text(service.offset, format: .number.sign(strategy: .always()).precision(.fractionLength(2)))
                                .monospacedDigit().frame(minWidth: 44)
                        }.help(text.reset).accessibilityLabel(text.reset)
                        Button { service.adjustOffset(by: 0.25) } label: {
                            Image(systemName: "plus")
                                .frame(width: 24, height: 18)
                                .contentShape(Rectangle())
                        }
                            .help(text.later).accessibilityLabel(text.later)
                    }
                    .font(.caption).buttonStyle(.borderless)
                } else {
                    if !playback.hasPosition { Text(text.noPosition).font(.caption).foregroundStyle(.secondary) }
                    ScrollView {
                        Text(lyrics.plain.isEmpty ? lyrics.lines.map(\.text).joined(separator: "\n") : lyrics.plain)
                            .font(.system(size: 15, weight: .medium)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .notchScrollEdgeFade()
                    Button { service.importLyrics() } label: { Label(text.importLyrics, systemImage: "doc.badge.plus") }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                }
            } else if service.state == .loading {
                // A slow lookup leaves importing within reach while it waits.
                VStack(spacing: 12) {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text.loading) }
                        .font(.callout).foregroundStyle(.secondary)
                    NotchPillButton(title: text.importLyrics, action: service.importLyrics)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NotchEmptyView(symbol: service.state == .failed ? "exclamationmark.triangle" : "quote.bubble",
                               message: emptyMessage) {
                    // A short island keeps importing as a glyph beside the
                    // next step rather than cutting either name short.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            nextStep
                            NotchPillButton(title: text.importLyrics, action: service.importLyrics)
                        }
                        HStack(spacing: 8) {
                            nextStep
                            NotchIconButton(symbol: "doc.badge.plus", title: text.importLyrics, action: service.importLyrics)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: online) { update() }
    }

    private func update() { service.update(playback: playback, visible: true) }

    /// An import that read no timed lines fails even with online lookup off,
    /// so the failure stays above the disclosure the next step needs.
    private var emptyMessage: String {
        let reason: String? = service.state == .failed ? text.failed : online ? text.unavailable : nil
        return [reason, online ? nil : text.onlineHint].compactMap { $0 }.joined(separator: "\n")
    }

    @ViewBuilder private var nextStep: some View {
        if online {
            NotchPillButton(title: text.retry, prominent: true, action: service.retry)
        } else {
            NotchPillButton(title: text.online, prominent: true) { online = true }
        }
    }

    private var importButton: some View {
        // A file being added, not the usual download arrow, which reads as saving.
        Button { service.importLyrics() } label: { Image(systemName: "doc.badge.plus") }
            .buttonStyle(.borderless)
            .help(text.importLyrics)
            .accessibilityLabel(text.importLyrics)
    }

    private func synced(_ lyrics: NotchLyrics) -> some View {
        TimelineView(.explicit(lyrics.changeDates(for: playback, offset: service.offset, from: .now))) { context in
            let active = lyrics.activeIndex(at: playback.position(at: context.date), offset: service.offset)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if active == nil {
                            Text(text.waiting).font(.caption).foregroundStyle(.secondary).id("start")
                        }
                        // Every verse keeps one size, so the lines never
                        // rewrap as the song moves. The sung one lights up.
                        ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white.opacity(index == active ? 1 : 0.35))
                                .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: index == active)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .id(index)
                        }
                    }.padding(.vertical, 6)
                }
                .notchScrollEdgeFade(length: 24)
                .onChange(of: active, initial: true) { _, index in
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                        if let index { proxy.scrollTo(index, anchor: .center) }
                        else { proxy.scrollTo("start", anchor: .top) }
                    }
                }
            }
        }
    }
}
