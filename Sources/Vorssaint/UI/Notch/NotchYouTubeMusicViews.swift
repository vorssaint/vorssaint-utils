// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A song or card read from YouTube Music's page, laid out as the queue's rows are.
struct NotchYouTubeMusicRowView: View {
    let row: NotchYouTubeMusicSupport.Row
    let playTitle: String
    @ObservedObject private var youTube = NotchYouTubeMusicService.shared

    var body: some View {
        HStack(spacing: 10) {
            NotchArtwork(image: row.imageURL.flatMap { youTube.images[$0] }, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.callout.weight(.medium)).lineLimit(1)
                if !row.subtitle.isEmpty {
                    Text(row.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { youTube.play(row) } label: {
                Image(systemName: "play.fill").font(.system(size: 11))
                    .frame(width: 28, height: 28).contentShape(Circle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 14))
            .disabled(youTube.actionPending)
            .help(playTitle).accessibilityLabel("\(playTitle): \(row.title)")
        }.padding(.vertical, 8)
    }
}

/// YouTube Music's Listen again shelf, below the idle player while a
/// YouTube Music page shows it.
struct NotchListenAgainView: View {
    @ObservedObject private var youTube = NotchYouTubeMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchMusicExtrasStrings { FeatureStrings.notchMusicExtras(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text.listenAgain).font(.callout.weight(.semibold))
                Spacer()
                if youTube.actionPending { ProgressView().controlSize(.mini) }
                Button { youTube.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(youTube.actionPending)
                    .help(text.refresh).accessibilityLabel(text.refresh)
            }
            if youTube.actionFailed {
                Text(text.actionFailed).font(.caption).foregroundStyle(.orange)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(youTube.listenAgain) { row in
                        NotchYouTubeMusicRowView(row: row, playTitle: text.playNow)
                    }
                }
            }
            .notchScrollEdgeFade()
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
