// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Panel section showing the system's Now Playing session with transport
/// controls. The read arrives from `NowPlayingPanelService` and happens when
/// the section appears, so a panel that is shut costs nothing.
struct NowPlayingSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = NowPlayingPanelService.shared
    var collapsible = true

    private var media: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var strings: NowPlayingFeatureStrings { FeatureStrings.nowPlaying(l10n.language) }

    var body: some View {
        PanelSection(.nowPlaying, title: media.mediaNowPlaying, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 10) {
                switch service.state {
                case let .playing(snapshot):
                    session(snapshot)
                case .loading, .nothingPlaying:
                    Text(strings.nothingPlaying)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear { service.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .menuPanelWillShow)) { _ in
                service.refresh()
            }
        }
    }

    private func session(_ snapshot: RadialNowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                artwork(snapshot)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title ?? RadialNowPlayingApplication.name(for: snapshot)
                            ?? media.mediaNowPlaying)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    if let artist = snapshot.artist {
                        Text(artist)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let album = snapshot.album {
                        Text(album)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            transport
        }
    }

    @ViewBuilder
    private func artwork(_ snapshot: RadialNowPlayingSnapshot) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if let data = snapshot.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 54, height: 54)
                .clipShape(shape)
        } else {
            shape
                .fill(Color.primary.opacity(0.08))
                .frame(width: 54, height: 54)
                .overlay {
                    if let icon = RadialNowPlayingApplication.icon(for: snapshot) {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    private var transport: some View {
        HStack(spacing: 6) {
            button(.previousTrack, symbol: "backward.fill", label: media.mediaPrevious)
            button(.playPause, symbol: isPlaying ? "pause.fill" : "play.fill",
                   label: media.mediaPlayPause)
            button(.nextTrack, symbol: "forward.fill", label: media.mediaNext)
        }
        .frame(maxWidth: .infinity)
    }

    private var isPlaying: Bool {
        if case let .playing(snapshot) = service.state { return snapshot.isPlaying }
        return false
    }

    private func button(_ key: RadialMenuMediaKey, symbol: String, label: String) -> some View {
        Button {
            service.press(key)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 22)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
        .help(label)
        .accessibilityLabel(label)
    }
}
