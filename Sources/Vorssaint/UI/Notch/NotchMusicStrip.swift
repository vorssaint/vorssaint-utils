// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Compact playback stays beside the camera and never grows a second row.
struct NotchMusicStrip: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { service.compactActivityGeometry }

    private var artworkSide: CGFloat {
        max(0, min(26, geometry.menuBarHeight - 6, geometry.compactActivityWingWidth - 20))
    }

    private var title: String { music.playback?.track.title ?? FeatureStrings.radialMenu(l10n.language).mediaNowPlaying }

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
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .frame(width: geometry.compactActivityWingWidth, alignment: .trailing)
                .clipped()
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                HStack {
                    if geometry.compactActivityWingWidth >= 44 {
                        NotchEqualizerBars(isPlaying: music.playback?.isPlaying == true,
                                           bars: 7, barWidth: 1.8,
                                           height: min(15, max(8, geometry.menuBarHeight - 9)),
                                           tint: music.artworkTint?.color ?? .white)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .frame(width: geometry.compactActivityWingWidth, alignment: .leading)
            }
            .frame(height: geometry.compactActivityContentHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([title, music.playback?.track.artist].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .help(title)
    }
}
