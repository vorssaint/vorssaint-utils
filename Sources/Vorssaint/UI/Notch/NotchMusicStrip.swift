// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Compact playback stays beside the camera and never grows a second row.
struct NotchMusicStrip: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { service.compactActivityGeometry }

    private static let edgeGap = NotchLayout.compactEdgeGap

    /// The cover keeps `edgeGap` from the top and bottom edges, which is also
    /// what lets it clear the corner arc once it is inset for it.
    private var preferredArtworkSide: CGFloat {
        min(26, geometry.compactActivityContentHeight - Self.edgeGap * 2)
    }
    private var artworkSide: CGFloat {
        max(0, min(preferredArtworkSide, geometry.compactActivityWingWidth - artworkInset - 8))
    }
    private var artworkRadius: CGFloat { artworkSide * 0.28 }
    private var artworkInset: CGFloat {
        let ideal = geometry.compactActivityEdgeInset(boxHeight: preferredArtworkSide,
                                                      radius: preferredArtworkSide * 0.28,
                                                      gap: Self.edgeGap)
        // A short wing gives clearance back before the cover turns into a chip.
        return max(0, min(ideal, geometry.compactActivityWingWidth - min(preferredArtworkSide, 20) - 8))
    }
    private var playbackButtonSide: CGFloat {
        min(24, geometry.compactActivityContentHeight - Self.edgeGap * 2)
    }
    private var playbackButtonInset: CGFloat {
        let ideal = geometry.compactActivityEdgeInset(boxHeight: playbackButtonSide,
                                                      radius: playbackButtonSide / 2,
                                                      gap: Self.edgeGap)
        return max(0, min(ideal, geometry.compactActivityWingWidth - playbackButtonSide - 8))
    }

    private var title: String { music.playback?.track.title ?? FeatureStrings.radialMenu(l10n.language).mediaNowPlaying }
    private var artist: String? {
        guard let artist = music.playback?.track.artist?.trimmingCharacters(in: .whitespaces), !artist.isEmpty else { return nil }
        return artist
    }
    /// A simulated camera has room for the track even when its wings disappear.
    private var fillsCameraGap: Bool { !geometry.isNotched && geometry.compactActivityCameraGap >= 56 }
    private var showsArtist: Bool { geometry.compactActivityContentHeight >= 28 }

    var body: some View {
        HStack(spacing: 0) {
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
                            .overlay(alignment: .bottomTrailing) {
                                // Keep live audio visible while the opposite wing hosts playback.
                                NotchLiveEqualizerBars(isPlaying: music.playback?.isPlaying == true,
                                                       bars: 3, barWidth: min(1.5, artworkSide / 8),
                                                       height: min(10, artworkSide * 0.4),
                                                       tint: music.artworkTint?.color ?? .white)
                                    .padding(min(2, artworkSide / 10))
                                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: artworkRadius / 2))
                                    .padding(min(1, artworkSide / 12))
                            }
                        }
                    }
                    .padding(.leading, artworkInset)
                    .padding(.trailing, 8)
                    // Keep the wings spread out while clearing the curved edges.
                    .frame(width: geometry.compactActivityWingWidth, alignment: .leading)
                    .clipped()
                    Group {
                        if fillsCameraGap { trackLabel } else { Color.clear }
                    }
                    .frame(width: geometry.compactActivityCameraGap, height: geometry.compactActivityContentHeight)
                    .clipped()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel([title, music.playback?.track.artist].compactMap { $0 }.joined(separator: ", "))
            .accessibilityHint(FeatureStrings.notch(l10n.language).open)
            .help(title)
            Button {
                if music.canPerform(.toggle) {
                    music.send(.toggle, context: music.playback?.commandContext)
                } else {
                    service.open(.music)
                }
            } label: {
                Image(systemName: music.playback?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: playbackButtonSide, height: geometry.compactActivityContentHeight)
                    .padding(.leading, 8)
                    .padding(.trailing, playbackButtonInset)
                    .frame(width: geometry.compactActivityWingWidth, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(music.commandPending)
            .opacity(geometry.compactActivityWingWidth >= 44 ? 1 : 0)
            .allowsHitTesting(geometry.compactActivityWingWidth >= 44)
            .accessibilityHidden(geometry.compactActivityWingWidth < 44)
            .accessibilityLabel(FeatureStrings.radialMenu(l10n.language).mediaPlayPause)
            .help(FeatureStrings.radialMenu(l10n.language).mediaPlayPause)
        }
        .frame(height: geometry.compactActivityContentHeight)
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
