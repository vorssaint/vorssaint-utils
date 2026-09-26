// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchLyricsView: View {
    let playback: NotchPlayback
    /// The card fills what the island gives it, so the verses take every
    /// line of that room instead of leaving a band below the timing row.
    let height: CGFloat
    @ObservedObject private var service = NotchLyricsService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchLyricsOnline) private var online = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchMusicExtrasStrings { FeatureStrings.notchMusicExtras(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let lyrics = service.lyrics {
                if lyrics.instrumental {
                    message(text.instrumental)
                } else if !lyrics.lines.isEmpty, playback.hasPosition {
                    synced(lyrics)
                    // Importing is a one-off; it shares the timing row as an
                    // icon instead of a row of its own under the verses.
                    HStack(spacing: 10) {
                        importButton
                        Text(text.offset).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button { service.adjustOffset(by: -0.25) } label: { Image(systemName: "minus") }
                            .help(text.earlier).accessibilityLabel(text.earlier)
                        Button { service.resetOffset() } label: {
                            Text(service.offset, format: .number.sign(strategy: .always()).precision(.fractionLength(2)))
                                .monospacedDigit().frame(minWidth: 44)
                        }.help(text.reset).accessibilityLabel(text.reset)
                        Button { service.adjustOffset(by: 0.25) } label: { Image(systemName: "plus") }
                            .help(text.later).accessibilityLabel(text.later)
                    }
                    .font(.caption).buttonStyle(.borderless)
                } else {
                    if !playback.hasPosition { Text(text.noPosition).font(.caption).foregroundStyle(.secondary) }
                    ScrollView {
                        Text(lyrics.plain.isEmpty ? lyrics.lines.map(\.text).joined(separator: "\n") : lyrics.plain)
                            .font(.system(size: 15, weight: .medium)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: max(40, readingHeight - (playback.hasPosition ? 0 : 24)))
                }
            } else if service.state == .loading {
                HStack { ProgressView().controlSize(.small); Text(text.loading) }.font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                if service.state != .consent { message(service.state == .failed ? text.failed : text.unavailable) }
                if !online {
                    Text(text.onlineHint).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle(text.online, isOn: $online).toggleStyle(.switch).controlSize(.small)
                } else {
                    Button(text.retry) { service.retry() }.buttonStyle(.borderless)
                }
            }
            if !showsTiming {
                HStack {
                    importButton
                    Spacer(minLength: 0)
                }.font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: online) { update() }
    }

    /// Room left for the verses under the card's padding and its one row of
    /// controls.
    private var readingHeight: CGFloat { height - 24 - 10 - 18 }

    private func update() { service.update(playback: playback, visible: true) }

    private var showsTiming: Bool {
        service.lyrics.map { !$0.instrumental && !$0.lines.isEmpty && playback.hasPosition } ?? false
    }

    private var importButton: some View {
        // A file being added, not the usual download arrow, which reads as saving.
        Button { service.importLyrics() } label: { Image(systemName: "doc.badge.plus") }
            .buttonStyle(.borderless)
            .help(text.importLyrics)
            .accessibilityLabel(text.importLyrics)
    }

    private func message(_ value: String) -> some View {
        Text(value).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
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
                        ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: index == active ? 18 : 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(index == active ? 1 : 0.4))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .id(index)
                        }
                    }.padding(.vertical, 6)
                }
                .frame(height: max(40, readingHeight))
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
