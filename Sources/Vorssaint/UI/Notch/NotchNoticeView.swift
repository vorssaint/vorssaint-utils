// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Feedback keeps the central camera area clear on physical and simulated notches.
struct NotchNoticeView: View {
    let notice: NotchNotice
    let geometry: NotchGeometry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var wingWidth: CGFloat { geometry.noticeWingWidth(preferred: notice.preferredWingWidth) }
    private var inset: CGFloat { min(16, wingWidth / 6) }
    private var tint: Color {
        switch notice.event {
        case .brightness, .keyboardLight: return .yellow
        // A warning reads as one in any agent's color; other AI notices wear it.
        case .agents: return notice.symbol.hasPrefix("exclamationmark") ? .orange : notice.agent?.tint ?? .white
        default: return .white
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, inset)
                .padding(.trailing, notice.cameraGap)
                .frame(width: wingWidth, height: geometry.stripHeight)
                .clipped()
            Color.clear.frame(width: geometry.noticeCameraGap)
            trailing
                .padding(.trailing, inset)
                .padding(.leading, notice.cameraGap)
                .frame(width: wingWidth, height: geometry.stripHeight)
                .clipped()
        }
        .foregroundStyle(.white)
        .frame(height: geometry.stripHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
    }

    @ViewBuilder private var leading: some View {
        if let content = notice.notification {
            HStack(spacing: 8) {
                NotchNotificationAppIcon(app: content.app, size: min(22, geometry.stripHeight - 4))
                Text(content.compactTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 8) {
                Group {
                    // A notice about the agent itself wears its mark; warnings
                    // and renewals keep a symbol that says what happened.
                    if notice.event == .agents, let agent = notice.agent, notice.symbol == agent.symbol {
                        NotchAgentMark(provider: agent, size: 13)
                    } else if notice.event == .track {
                        NotchTrackArtwork(size: min(18, geometry.stripHeight - 6))
                    } else {
                        Image(systemName: notice.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 18)
                Text(notice.level == nil ? notice.title : notice.detail)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(notice.event == .track ? .tail : .middle)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: notice.readsFromEnds ? .leading : .trailing)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: notice.detail)
            .transaction { $0.disablesAnimations = false }
        }
    }

    @ViewBuilder private var trailing: some View {
        if let content = notice.notification {
            Text(content.compactDetail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(geometry.stripHeight >= 30 ? 2 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let level = notice.level {
            NotchMeter(value: level, height: 5, tint: tint)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: level)
                .transaction { $0.disablesAnimations = false }
        } else {
            Text(notice.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(notice.event == .accessory ? .middle : .tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// The new song's cover, read as it arrives: it often lands after the title.
private struct NotchTrackArtwork: View {
    @ObservedObject private var music = NotchMusicService.shared
    let size: CGFloat

    var body: some View { NotchArtwork(image: music.artwork, size: size) }
}

/// Level feedback occupies the header while the current page stays usable.
struct NotchExpandedLevelView: View {
    let notice: NotchNotice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.symbol)
                .frame(width: 18)
            NotchMeter(value: notice.level ?? 0, height: 5,
                       tint: notice.event == .volume ? .white : .yellow)
                .frame(maxWidth: 96)
            Text(notice.detail)
                .monospacedDigit()
                .fixedSize()
        }
        .font(.system(size: 11, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
    }
}
