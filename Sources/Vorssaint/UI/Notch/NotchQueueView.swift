// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchQueueView: View {
    let playback: NotchPlayback
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var youTube = NotchYouTubeMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchMusicExtrasStrings { FeatureStrings.notchMusicExtras(l10n.language) }

    /// A player that shares no queue may still be YouTube Music, whose page
    /// lists the songs to come.
    private var followsYouTube: Bool { !service.queueLoading && service.upcomingRows.isEmpty }
    private var youTubeRows: [NotchYouTubeMusicSupport.Row]? { followsYouTube ? youTube.upcoming : nil }
    private var loading: Bool { service.queueLoading || (followsYouTube && youTube.loading && youTube.upcoming == nil) }
    private var pending: Bool { service.queueActionPending || youTube.actionPending }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text.queue).font(.callout.weight(.semibold))
                Spacer()
                if loading || pending { ProgressView().controlSize(.mini) }
                Button {
                    service.refreshQueue()
                    youTube.refresh()
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(loading || pending)
                    .help(text.refresh).accessibilityLabel(text.refresh)
            }
            if service.queueActionFailed || (youTubeRows != nil && youTube.actionFailed) {
                Text(text.actionFailed).font(.caption).foregroundStyle(.orange)
            }
            if let queue = service.upcoming, !service.upcomingRows.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(service.upcomingRows) { item in
                            HStack(spacing: 10) {
                                NotchArtwork(image: service.upcomingArtwork[item.id], size: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                                    if !item.artist.isEmpty { Text(item.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if queue.canPlay {
                                    Button { service.playQueued(item) } label: {
                                        Image(systemName: "play.fill").font(.system(size: 11))
                                            .frame(width: 28, height: 28).contentShape(Circle())
                                    }
                                    .buttonStyle(NotchButtonStyle(cornerRadius: 14))
                                    .disabled(service.queueActionPending || service.upcomingIsHeld)
                                    .help(text.playNow).accessibilityLabel("\(text.playNow): \(item.title)")
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                }
                .notchScrollEdgeFade()
            } else if let rows = youTubeRows, !rows.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in NotchYouTubeMusicRowView(row: row, playTitle: text.playNow) }
                    }
                }
                .notchScrollEdgeFade()
            } else if !loading {
                NotchEmptyView(symbol: "list.bullet",
                               message: service.upcoming == nil && youTubeRows == nil ? text.queueUnavailable : text.queueEmpty) {
                    NotchPillButton(title: text.openPlayer, prominent: true) { RadialNowPlayingApplication.open(playback.track) }
                }
            }
        }
        // The title sits as far below the player as the first verse would.
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: syncYouTube)
        .onChange(of: followsYouTube) { syncYouTube() }
        .onChange(of: playback.track.title) { syncYouTube() }
        .onDisappear { youTube.stopFollowingQueue() }
    }

    private func syncYouTube() {
        if followsYouTube { youTube.followQueue(title: playback.track.title) } else { youTube.stopFollowingQueue() }
    }
}
