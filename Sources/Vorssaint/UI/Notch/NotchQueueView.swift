// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchQueueView: View {
    let playback: NotchPlayback
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchMusicExtrasStrings { FeatureStrings.notchMusicExtras(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(text.queue).font(.callout.weight(.semibold))
                Spacer()
                if service.queueLoading || service.queueActionPending { ProgressView().controlSize(.mini) }
                Button { service.refreshQueue() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(service.queueLoading || service.queueActionPending)
                    .help(text.refresh).accessibilityLabel(text.refresh)
            }
            if service.queueActionFailed {
                Text(text.actionFailed).font(.caption).foregroundStyle(.orange)
            }
            if let queue = service.upcoming, !queue.items.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(queue.items) { item in
                            HStack(spacing: 10) {
                                Text("\(item.offset)").font(.caption).monospacedDigit()
                                    .foregroundStyle(.secondary).frame(width: 20)
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
                                    .disabled(service.queueActionPending)
                                    .help(text.playNow).accessibilityLabel("\(text.playNow): \(item.title)")
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                }.frame(maxHeight: 170)
            } else if !service.queueLoading {
                Text(service.upcoming == nil ? text.queueUnavailable : text.queueEmpty)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                Button(text.openPlayer) { RadialNowPlayingApplication.open(playback.track) }
                    .buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }
}
