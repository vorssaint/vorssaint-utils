// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Compact playback stays beside the camera and never grows a second row.
struct NotchMusicStrip: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { service.compactActivityGeometry }
    private var innerInset: CGFloat { geometry.isNotched ? 0 : 8 }

    private static let edgeGap = NotchLayout.compactEdgeGap
    private static let barWidth: CGFloat = 1.8
    private static let barCount = 7

    /// The cover keeps `edgeGap` from the top and bottom edges, which is also
    /// what lets it clear the corner arc once it is inset for it.
    private var preferredArtworkSide: CGFloat {
        min(26, geometry.compactActivityContentHeight - Self.edgeGap * 2)
    }
    private var artworkSide: CGFloat {
        max(0, min(preferredArtworkSide, geometry.compactActivityWingWidth - artworkInset - innerInset))
    }
    private var artworkRadius: CGFloat { artworkSide * 0.28 }
    private var artworkInset: CGFloat {
        let ideal = geometry.compactActivityEdgeInset(boxHeight: preferredArtworkSide,
                                                      radius: preferredArtworkSide * 0.28,
                                                      gap: Self.edgeGap)
        // A short wing gives clearance back before the cover turns into a chip.
        return max(0, min(ideal, geometry.compactActivityWingWidth - min(preferredArtworkSide, 20) - innerInset))
    }
    /// Mirrors `NotchEqualizerBars`, whose spacing follows its bar width.
    private var barsWidth: CGFloat {
        Self.barWidth * (CGFloat(Self.barCount) + CGFloat(Self.barCount - 1) * 0.85)
    }
    private var barsInset: CGFloat {
        let ideal = geometry.compactActivityEdgeInset(boxHeight: barHeight,
                                                      radius: Self.barWidth / 2,
                                                      gap: Self.edgeGap)
        return max(0, min(ideal, geometry.compactActivityWingWidth - barsWidth - innerInset))
    }

    private var title: String { music.playback?.track.title ?? FeatureStrings.radialMenu(l10n.language).mediaNowPlaying }
    private var artist: String? {
        guard let artist = music.playback?.track.artist?.trimmingCharacters(in: .whitespaces), !artist.isEmpty else { return nil }
        return artist
    }
    /// A simulated camera has room for the track even when its wings disappear.
    private var fillsCameraGap: Bool { !geometry.isNotched && geometry.compactActivityCameraGap >= 56 }
    private var showsArtist: Bool { geometry.compactActivityContentHeight >= 28 }
    private var barHeight: CGFloat {
        min(16, max(6, geometry.compactActivityContentHeight - Self.edgeGap * 2))
    }

    var body: some View {
        Button { service.open(.music) } label: {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    if geometry.compactActivityWingWidth >= 44 {
                        Group {
                            if let image = music.artwork {
                                Image(nsImage: image).resizable().scaledToFill()
                            } else {
                                Color.black.overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
                            }
                        }
                        .frame(width: artworkSide, height: artworkSide)
                        .clipShape(RoundedRectangle(cornerRadius: artworkRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: artworkRadius, style: .continuous)
                                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                        }
                    }
                }
                .padding(.leading, artworkInset)
                .padding(.trailing, innerInset)
                .frame(width: geometry.compactActivityWingWidth, alignment: geometry.isNotched ? .trailing : .leading)
                .clipped()
                Group {
                    if fillsCameraGap { trackLabel } else { Color.clear }
                }
                .frame(width: geometry.compactActivityCameraGap, height: geometry.compactActivityContentHeight)
                .clipped()
                HStack {
                    if geometry.compactActivityWingWidth >= 44 {
                        NotchLiveEqualizerBars(isPlaying: music.playback?.isPlaying == true,
                                               bars: Self.barCount, barWidth: Self.barWidth,
                                               height: barHeight,
                                               tint: music.artworkTint?.color ?? .white)
                    }
                }
                .padding(.leading, innerInset)
                .padding(.trailing, barsInset)
                .frame(width: geometry.compactActivityWingWidth, alignment: geometry.isNotched ? .leading : .trailing)
            }
            .frame(height: geometry.compactActivityContentHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([title, music.playback?.track.artist].compactMap { $0 }.joined(separator: ", "))
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
