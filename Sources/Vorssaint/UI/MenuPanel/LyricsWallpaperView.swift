// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Full-screen music wallpaper: blurred cover, the song's name and its lyrics
/// scrolling in time. Highlighting only moves at verse boundaries, so nothing
/// ticks while paused.
struct LyricsWallpaperView: View {
    @ObservedObject var service: LyricsWallpaperService
    @ObservedObject private var music = NotchMusicService.shared
    @AppStorage(DefaultsKey.lyricsWallpaperStyle) private var style = "constellation"

    var body: some View {
        if style == "constellation" { constellation } else { classic }
    }

    /// Black sky, one constellation per lyric line, a small caption below.
    private var constellation: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let lyrics = service.lyrics, let playback = music.playback, !lyrics.lines.isEmpty, playback.hasPosition {
                ConstellationLyricsView(lyrics: lyrics, playback: playback, offset: service.offset)
            } else {
                Text(service.state == .loading ? "…" : "♪").font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(music.playback?.track.title ?? "").font(.system(size: 16, weight: .semibold))
                Text(music.playback?.track.artist ?? "").font(.system(size: 13)).opacity(0.7)
            }
            .foregroundStyle(.white.opacity(0.55)).padding(40)
        }
        .ignoresSafeArea()
    }

    private var classic: some View {
        ZStack {
            backdrop
            HStack(alignment: .center, spacing: 72) {
                cover
                lyricsColumn
            }
            .padding(.horizontal, 96)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: music.artwork == nil)
    }

    private var tint: Color {
        music.artworkTint.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .gray
    }

    private var backdrop: some View {
        ZStack {
            Color.black
            if let artwork = music.artwork {
                Image(nsImage: artwork)
                    .resizable().scaledToFill()
                    .blur(radius: 90).saturation(1.3).opacity(0.75)
                    .scaleEffect(1.3)
            }
            LinearGradient(colors: [tint.opacity(0.35), .black.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipped()
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: 18) {
            Group {
                if let artwork = music.artwork {
                    Image(nsImage: artwork).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.white.opacity(0.1))
                        .overlay(Image(systemName: "music.note").font(.system(size: 80)).foregroundStyle(.white.opacity(0.5)))
                }
            }
            .frame(width: 380, height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(music.playback?.track.title ?? "").font(.system(size: 26, weight: .bold))
                Text(music.playback?.track.artist ?? "").font(.system(size: 18, weight: .medium)).opacity(0.7)
            }
            .foregroundStyle(.white).lineLimit(2).frame(width: 380, alignment: .leading)
        }
    }

    @ViewBuilder private var lyricsColumn: some View {
        if let lyrics = service.lyrics, let playback = music.playback, !lyrics.lines.isEmpty, playback.hasPosition {
            TimelineView(.explicit(lyrics.changeDates(for: playback, offset: service.offset, from: Date()))) { context in
                let position = playback.position(at: context.date)
                synced(lyrics, active: lyrics.activeIndex(at: position, offset: service.offset))
            }
        } else if let lyrics = service.lyrics, !lyrics.plain.isEmpty {
            ScrollView { Text(lyrics.plain).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading) }
        } else {
            Text(service.state == .loading ? "…" : (service.lyrics?.instrumental == true ? "♪ Instrumental" : "No synced lyrics for this song"))
                .font(.system(size: 28, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func synced(_ lyrics: NotchLyrics, active: Int?) -> some View {
        GeometryReader { proxy in
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        Color.clear.frame(height: proxy.size.height * 0.35)
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            let distance = active.map { abs(index - $0) } ?? 99
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: index == active ? 46 : 36, weight: .bold))
                                .foregroundStyle(.white.opacity(index == active ? 1 : max(0.18, 0.55 - Double(distance) * 0.12)))
                                .blur(radius: index == active ? 0 : min(3, Double(distance) * 0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                        Color.clear.frame(height: proxy.size.height * 0.5)
                    }
                }
                .scrollDisabled(true)
                .onChange(of: active) { _, new in
                    guard let new else { return }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { reader.scrollTo(new, anchor: .init(x: 0, y: 0.38)) }
                }
                .onAppear { if let active { reader.scrollTo(active, anchor: .init(x: 0, y: 0.38)) } }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                     .init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
    }
}
