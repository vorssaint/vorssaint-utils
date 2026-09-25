// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The last visible compact track stays intact while its island retracts.
struct NotchCompactMusicSnapshot {
    let playback: NotchPlayback
    let artwork: NSImage?
    let tint: NotchArtworkTint?
    let geometry: NotchGeometry
}

/// Compact playback stays beside the camera and never grows a second row.
struct NotchMusicStrip: View {
    @ObservedObject var service: NotchService
    var snapshot: NotchCompactMusicSnapshot? = nil
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { snapshot?.geometry ?? service.compactActivityGeometry }
    private var playback: NotchPlayback? { snapshot?.playback ?? music.playback }
    private var artwork: NSImage? { snapshot == nil ? music.artwork : snapshot?.artwork }
    private var tint: NotchArtworkTint? { snapshot == nil ? music.artworkTint : snapshot?.tint }
    /// A physical camera's wings are fitted to the cover and the bars; a
    /// simulated one keeps a little air beside its drawn cutout.
    private var innerInset: CGFloat { geometry.isNotched ? 0 : 8 }

    /// The cover sits at the strip's end, its corners concentric with the
    /// strip's own, so the two outlines keep one even gap.
    private var artworkSide: CGFloat {
        max(0, min(geometry.compactMusicArtworkSide, geometry.compactActivityWingWidth - artworkInset - innerInset))
    }
    private var artworkRadius: CGFloat { min(artworkSide / 2, geometry.compactMusicArtworkRadius) }
    private var artworkInset: CGFloat {
        // A short wing gives clearance back before the cover turns into a chip.
        max(0, min(geometry.compactMusicArtworkInset,
                   geometry.compactActivityWingWidth - min(geometry.compactMusicArtworkSide, 20) - innerInset))
    }
    private var barsInset: CGFloat {
        max(0, min(geometry.compactMusicBarsInset,
                   geometry.compactActivityWingWidth - NotchLayout.compactMusicBarsWidth - innerInset))
    }

    private var title: String { playback?.track.title ?? FeatureStrings.radialMenu(l10n.language).mediaNowPlaying }
    private var artist: String? {
        guard let artist = playback?.track.artist?.trimmingCharacters(in: .whitespaces), !artist.isEmpty else { return nil }
        return artist
    }
    /// A simulated camera has room for the track even when its wings disappear.
    private var fillsCameraGap: Bool { !geometry.isNotched && geometry.compactActivityCameraGap >= 56 }
    private var showsArtist: Bool { geometry.compactActivityContentHeight >= 28 }

    var body: some View {
        Button { service.open(.music) } label: {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    if geometry.compactActivityWingWidth > 0 {
                        // Circular corners, like the strip's, so the two stay parallel.
                        NotchMusicCover(artwork: artwork, side: artworkSide, radius: artworkRadius)
                    }
                }
                .padding(.leading, artworkInset)
                .padding(.trailing, innerInset)
                .frame(width: geometry.compactActivityWingWidth, alignment: .leading)
                .clipped()
                Group {
                    if fillsCameraGap { trackLabel } else { Color.clear }
                }
                .frame(width: geometry.compactActivityCameraGap, height: geometry.compactActivityContentHeight)
                .clipped()
                HStack {
                    if geometry.compactActivityWingWidth > 0 {
                        NotchLiveEqualizerBars(isPlaying: playback?.isPlaying == true,
                                               bars: NotchLayout.compactMusicBarCount,
                                               barWidth: NotchLayout.compactMusicBarWidth,
                                               height: geometry.compactMusicBarHeight,
                                               tint: tint?.color ?? .white)
                    }
                }
                .padding(.leading, innerInset)
                .padding(.trailing, barsInset)
                .frame(width: geometry.compactActivityWingWidth, alignment: .trailing)
            }
            .frame(height: geometry.compactActivityContentHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([title, playback?.track.artist].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .help(title)
    }

    private var trackLabel: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if showsArtist, let artist {
                Text(artist)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, geometry.compactMusicLabelInset)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// The playing track's cover beside the camera, with a hairline edge that
/// keeps a dark one apart from the island.
struct NotchMusicCover: View {
    let artwork: NSImage?
    let side: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                Color.black.overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .circular))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .circular)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
    }
}
