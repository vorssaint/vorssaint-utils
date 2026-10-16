// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The last visible compact track stays intact while its island retracts.
struct NotchCompactMusicSnapshot {
    let playback: NotchPlayback
    let artwork: NSImage?
    let tint: NotchArtworkTint?
    let geometry: NotchGeometry
    /// The left side of a strip that was naming its song.
    var namedWing: CGFloat? = nil
    /// A capsule that was naming its song for the pointer.
    var namesSong = false
}

/// Compact playback stays beside the camera and never grows a second row.
/// Resting on the cover names the song beside it, and resting on the bars
/// turns them into the song's play or pause button.
struct NotchMusicStrip: View {
    @ObservedObject var service: NotchService
    var snapshot: NotchCompactMusicSnapshot? = nil
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    /// The island's own strip answers the pointer. A copy on another display
    /// or a strip on its way out only shows the song.
    var interactive = false
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias Layout = NotchMusicStripLayout
    private var geometry: NotchGeometry { snapshot?.geometry ?? displayGeometry ?? service.compactActivityGeometry }
    /// A new song stays off the strip until its notice has shown it, and a
    /// held song through a reading from its player without a name.
    private var shown: NotchCompactMusicSnapshot? {
        snapshot ?? service.heldMusic ?? (interactive ? service.musicStripStandIn(for: music.playback) : nil)
    }
    private var playback: NotchPlayback? { shown?.playback ?? music.playback }
    private var artwork: NSImage? { shown == nil ? music.artwork : shown?.artwork }
    private var tint: NotchArtworkTint? { shown == nil ? music.artworkTint : shown?.tint }
    private var live: Bool { interactive && snapshot == nil }
    /// A physical camera's wings are fitted to the cover and the bars; a
    /// simulated one keeps a little air beside its drawn cutout.
    private var innerInset: CGFloat { Layout.innerInset(geometry) }

    /// The cover sits at the strip's end, its corners concentric with the
    /// strip's own, so the two outlines keep one even gap.
    private var artworkSide: CGFloat { Layout.coverSide(geometry) }
    private var artworkRadius: CGFloat { min(artworkSide / 2, geometry.compactMusicArtworkRadius) }
    private var artworkInset: CGFloat { Layout.coverInset(geometry) }
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
    private var fillsCameraGap: Bool { Layout.fillsCameraGap(geometry) }
    private var showsArtist: Bool { Layout.showsArtist(geometry) }
    /// The left side while the pointer has the song named, nil otherwise. A
    /// strip on its way out keeps the name it had, which leaves with it.
    private var namedWing: CGFloat? { live ? service.namedMusicWings?.leading : snapshot?.namedWing }
    private var showsControl: Bool { live && service.musicStripShowsControl }
    /// A click's request shows at once, before the player says so.
    private var playing: Bool { (live ? service.musicStripRequest : nil) ?? playback?.isPlaying == true }

    var body: some View {
        let wing = geometry.compactActivityWingWidth
        let named = namedWing
        Button { live ? service.activateMusicStrip() : service.openActivity(.music) } label: {
            HStack(spacing: 0) {
                HStack(spacing: Layout.spacing) {
                    // The words grow out from behind the cover, which keeps its place.
                    if named != nil { namedLabel }
                    if wing > 0 {
                        // Circular corners, like the strip's, so the two stay parallel.
                        NotchMusicCover(artwork: artwork, side: artworkSide, radius: artworkRadius)
                    }
                }
                .padding(.leading, named == nil ? artworkInset : Layout.endInset)
                .padding(.trailing, named == nil ? innerInset : wing - artworkInset - artworkSide)
                .frame(width: named ?? wing, height: geometry.compactActivityContentHeight,
                       alignment: named == nil ? .leading : .trailing)
                .clipped()
                .contentShape(Rectangle())
                .onHover { if live { service.hoverMusicStrip(.cover, entered: $0) } }
                Group {
                    if fillsCameraGap { trackLabel } else { Color.clear }
                }
                .frame(width: geometry.compactActivityCameraGap, height: geometry.compactActivityContentHeight)
                .clipped()
                HStack {
                    if wing > 0 { bars }
                }
                .padding(.leading, innerInset)
                .padding(.trailing, barsInset)
                .frame(width: wing, height: geometry.compactActivityContentHeight, alignment: .trailing)
                .contentShape(Rectangle())
                .onHover { if live { service.hoverMusicStrip(.bars, entered: $0) } }
            }
            .frame(height: geometry.compactActivityContentHeight)
            .modifier(NotchMusicSwipeFeedback(enabled: snapshot == nil))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([title, playback?.track.artist].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .accessibilityAction(named: Text(FeatureStrings.radialMenu(l10n.language).mediaPlayPause)) {
            if !service.toggleMusicStripSong() { service.openActivity(.music) }
        }
        .help(title)
        // Named, the strip reaches further left. Laid out as wide on both
        // sides, it keeps the camera's gap over the camera, while the button
        // keeps to the strip, which takes clicks only in its own frame.
        .frame(width: (named ?? wing) * 2 + geometry.compactActivityCameraGap, alignment: .leading)
    }

    /// The bars, or the button they become while the pointer rests on them.
    /// Both stay in place and cross-fade, and hidden bars hold still.
    private var bars: some View {
        ZStack {
            NotchLiveEqualizerBars(isPlaying: playing && !showsControl,
                                   bars: NotchLayout.compactMusicBarCount,
                                   barWidth: NotchLayout.compactMusicBarWidth,
                                   height: geometry.compactMusicBarHeight,
                                   tint: tint?.color ?? .white)
                .opacity(showsControl ? 0 : 1)
            if showsControl {
                NotchMusicStripButton(playing: playing, tint: tint?.color ?? .white,
                                      height: geometry.compactMusicBarHeight)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: showsControl)
    }

    /// The song as the pointer asked for it: the title over the artist,
    /// ending at the cover.
    private var namedLabel: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(Font(Layout.titleFont as CTFont))
                .lineLimit(1)
                .truncationMode(.tail)
            if showsArtist, let artist {
                Text(artist)
                    .font(Font(Layout.artistFont as CTFont))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityHidden(true)
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

/// The play or pause button the strip's bars become under the pointer, in
/// the bars' own place and colour. A click flips it at once.
struct NotchMusicStripButton: View {
    let playing: Bool
    let tint: Color
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let symbol = playing ? "pause.fill" : "play.fill"
        let size = min(13, max(8, height - 3))
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: playing)
            // The ink, not the frame, sits on the bars' middle.
            .alignmentGuide(VerticalAlignment.center) {
                $0[VerticalAlignment.center] + NotchCapsuleLayout.symbolDrop(symbol, size: size, weight: .semibold)
            }
            .frame(width: NotchLayout.compactMusicBarsWidth, height: height)
            .accessibilityHidden(true)
    }
}

/// A brief directional nudge acknowledges the command without predicting the
/// next track or waiting for the player's artwork. No repeating work survives it.
struct NotchMusicSwipeFeedback: ViewModifier {
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = 0
    @State private var direction: CGFloat = -1

    func body(content: Content) -> some View {
        let displacement = reduceMotion ? 0 : direction
        return content
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, travel in
                view.offset(x: displacement * travel)
            } keyframes: { _ in
                CubicKeyframe(8, duration: 0.09)
                SpringKeyframe(0, duration: 0.25, spring: .smooth)
            }
            .onReceive(NotchMusicService.shared.gestureSkips) { forward in
                guard enabled, !reduceMotion else { return }
                direction = forward ? -1 : 1
                trigger &+= 1
            }
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
