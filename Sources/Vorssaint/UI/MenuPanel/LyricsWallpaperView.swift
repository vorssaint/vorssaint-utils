// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Full-screen music on the desktop. With the song wallpaper on, the cover
/// fills the screen under a veil and its own colours drift over it. With Show
/// lyrics on, the lyrics sit on top as a graph of stars or as an ordinary
/// scrolling column, as the style says, over the cover or, with the song
/// wallpaper off, straight over the normal wallpaper.
struct LyricsWallpaperView: View {
    @ObservedObject var service: LyricsWallpaperService
    @AppStorage(DefaultsKey.lyricsWallpaperStyle) private var style = "constellation"
    private var mode: LyricsMode { LyricsMode.from(style) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if service.songWallpaper { backdrop }
            if service.showLyrics {
                Group {
                    switch mode {
                    case .constellation: graph
                    case .scroll: scrolling
                    default: textMode
                    }
                }
                // Over a wallpaper of any colour, a soft shadow keeps the words readable.
                .shadow(color: .black.opacity(service.songWallpaper ? 0 : 0.6), radius: 10, y: 2)
            } else {
                caption
            }
        }
        .ignoresSafeArea()
        // Behind every app, or with the song paused, nothing on the desktop needs to move.
        .environment(\.lyricsAnimationsActive, service.onScreen && service.playback?.isPlaying == true)
    }

    // MARK: Backdrop

    /// The cover, the palette's moving colour and a vignette; the first two
    /// cross-fade together on a track change. The new cover fades in over the
    /// old one, which stays opaque beneath it, so the change never passes
    /// through black.
    private var backdrop: some View {
        ZStack {
            Color.black
            if let previous = service.previousCover {
                ZStack {
                    Image(nsImage: previous).resizable().interpolation(.high).scaledToFill()
                    Color.black.opacity(0.4)
                }
            }
            ZStack {
                if let cover = service.cover {
                    Image(nsImage: cover).resizable().interpolation(.high).scaledToFill()
                }
                Color.black.opacity(0.4)
                AuroraBackdrop(palette: service.palette).blendMode(.screen).opacity(0.75)
            }
            .id(service.coverID)
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
            RadialGradient(colors: [.clear, .black.opacity(0.5)], center: .center, startRadius: 220, endRadius: 1500)
        }
        .clipped()
        .animation(.easeInOut(duration: 0.9), value: service.coverID)
    }

    /// The lyrics' colour follows the cover, lifted toward white.
    private var accent: Color {
        service.palette.first.map { Color(nsColor: NSColor($0).blended(withFraction: 0.35, of: .white) ?? .white) }
            ?? Color(red: 0.43, green: 0.61, blue: 1.0)
    }

    private var playbackInfo: (NotchLyrics, NotchPlayback)? {
        guard let lyrics = service.lyrics, let playback = service.playback, !lyrics.lines.isEmpty, playback.hasPosition
        else { return nil }
        return (lyrics, playback)
    }

    // MARK: Graph

    private var graph: some View {
        ZStack(alignment: .bottomLeading) {
            if let (lyrics, playback) = playbackInfo {
                ConstellationLyricsView(lyrics: lyrics, playback: playback, offset: service.offset, accent: accent)
            } else {
                Text(service.state == .loading ? "…" : "♪").font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            caption
        }
    }

    /// Every other style: the lyrics across the middle of the screen, the
    /// caption small in the corner.
    private var textMode: some View {
        ZStack(alignment: .bottomLeading) {
            if let (lyrics, playback) = playbackInfo {
                LyricsModeView(mode: mode, lyrics: lyrics, playback: playback, offset: service.offset, accent: accent)
                    .padding(.horizontal, 140).padding(.vertical, 120)
            } else {
                Text(service.state == .loading ? "…" : "♪").font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.25)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            caption
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(service.playback?.track.title ?? "").font(.system(size: 16, weight: .semibold))
            Text(service.playback?.track.artist ?? "").font(.system(size: 13)).opacity(0.7)
        }
        .foregroundStyle(.white.opacity(0.6)).padding(40)
    }

    // MARK: Scrolling

    private var scrolling: some View {
        HStack(alignment: .center, spacing: 72) {
            coverCard
            lyricsColumn
        }
        .padding(.horizontal, 96)
    }

    private var coverCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Group {
                if let cover = service.cover {
                    Image(nsImage: cover).resizable().interpolation(.high).scaledToFill()
                } else {
                    Rectangle().fill(.white.opacity(0.1))
                        .overlay(Image(systemName: "music.note").font(.system(size: 80)).foregroundStyle(.white.opacity(0.5)))
                }
            }
            .frame(width: 380, height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(service.playback?.track.title ?? "").font(.system(size: 26, weight: .bold))
                Text(service.playback?.track.artist ?? "").font(.system(size: 18, weight: .medium)).opacity(0.7)
            }
            .foregroundStyle(.white).lineLimit(2).frame(width: 380, alignment: .leading)
        }
    }

    @ViewBuilder private var lyricsColumn: some View {
        if let (lyrics, playback) = playbackInfo {
            ScrollLyricsView(lyrics: lyrics, playback: playback, offset: service.offset)
        } else if let lyrics = service.lyrics, !lyrics.plain.isEmpty {
            ScrollView {
                Text(lyrics.plain).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(service.state == .loading ? "…" : (service.lyrics?.instrumental == true ? "♪ Instrumental" : "No synced lyrics for this song"))
                .font(.system(size: 28, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
