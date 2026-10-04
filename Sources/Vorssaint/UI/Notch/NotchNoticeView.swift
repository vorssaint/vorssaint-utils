// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Feedback keeps the central camera area clear on physical and simulated notches.
struct NotchNoticeView: View {
    let notice: NotchNotice
    let geometry: NotchGeometry
    /// The window's own layer shows the companion stepping in from its rest
    /// and out again, and the notice leaves its own out meanwhile.
    var hidesMascot = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var wings: NotchNoticeWings { notice.wings(in: geometry) }
    private var tint: Color {
        switch notice.event {
        // A warning reads as one in any agent's color; other AI notices wear it.
        case .agents: return notice.symbol.hasPrefix("exclamationmark") ? .orange : notice.agent?.tint ?? .white
        // The timer's notice keeps the orange its strip and page wear.
        case .timer: return .orange
        default: return .white
        }
    }
    /// The words of a timer's notice share its orange too.
    private var textTint: Color { notice.event == .timer ? .orange : .white }
    /// With the companion on, it stands in for the symbol, and reacts unless
    /// its reactions are off.
    private var companionReaction: NotchMascotReaction? {
        NotchMascotSupport.isEnabled() ? notice.mascot : nil
    }

    @ViewBuilder var body: some View {
        if notice.isOutputDeviceChange {
            outputDevice
        } else {
            standardNotice
        }
    }

    private var outputDevice: some View {
        let size = notice.outputDeviceSize(in: geometry)
        return HStack(spacing: NotchNotice.outputDeviceSpacing) {
            Image(systemName: notice.symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: NotchNotice.outputDeviceSymbolWidth)
                .contentTransition(.symbolEffect(.replace))
            Text(notice.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, NotchNotice.outputDevicePadding)
        .frame(width: size.width, height: NotchNotice.outputDeviceRowHeight)
        .padding(.top, geometry.safeContentTop)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: notice.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.title)
    }

    private var standardNotice: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, notice.inset(wing: wings.leading))
                .padding(.trailing, notice.cameraGap)
                .frame(width: wings.leading, height: geometry.stripHeight)
                .clipped()
            Color.clear.frame(width: geometry.noticeCameraGap)
            trailing
                .padding(.trailing, notice.inset(wing: wings.trailing))
                .padding(.leading, notice.cameraGap)
                .frame(width: wings.trailing, height: geometry.stripHeight)
                .clipped()
        }
        .foregroundStyle(.white)
        .frame(height: geometry.stripHeight)
        // Each side is as wide as what it shows, so the island reaches
        // further toward the wider one and the camera's gap stays over it.
        .offset(x: (wings.trailing - wings.leading) / 2)
        // A new reading that needs another width, as a level passing 99%,
        // moves its mark and meter with the island's steady ease, not ahead of it.
        // Keyed on the notice's own widths, so a display change does not ease it.
        .animation(reduceMotion ? nil : .spring(duration: NotchMotion.steadyWidth.duration, bounce: 0),
                   value: notice.preferredWings)
        .transaction { $0.disablesAnimations = false }
        // Another kind of notice is drawn anew at its place, as the island
        // springs to it, rather than easing out of the last one's layout.
        .id(notice.event)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityText)
    }

    @ViewBuilder private var leading: some View {
        if let content = notice.notification {
            HStack(spacing: NotchNotificationBannerLayout.spacing) {
                NotchNotificationAppIcon(app: content.app, size: min(NotchNotificationBannerLayout.iconSize, geometry.stripHeight - 4))
                Text(content.compactTitle)
                    .font(Font(NotchNotificationBannerLayout.titleFont as CTFont))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: 8) {
                Group {
                    // A notice about the agent itself wears its mark, and a
                    // warning keeps a symbol that says what happened.
                    if let reaction = companionReaction {
                        let size = NotchMascotSupport.noticeSize
                        NotchMascotView(look: NotchMascotSupport.look(), mood: NotchService.shared.mascotRestingMood,
                                        size: size, reaction: NotchMascotSupport.reacts() ? reaction : nil)
                            .frame(width: size, height: size)
                            // Half a point low, on the line it rests on beside
                            // the camera, so it steps in and out with no jump.
                            .offset(y: 0.5)
                            // One notice in place of another plays its own reaction,
                            // swapped at once: two of it crossfading in one place dimmed it.
                            .id("\(notice.event)|\(notice.title)|\(notice.detail)|\(reaction.rawValue)")
                            .transition(.identity)
                            .opacity(hidesMascot ? 0 : 1)
                            .animation(nil, value: hidesMascot)
                    } else if notice.event == .agents, let agent = notice.agent, notice.symbol == agent.symbol {
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
                    .foregroundStyle(textTint)
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
            // At the far end, as far from it as the sender is from the other
            // one, with the air that fits it beside the camera.
            Text(content.compactDetail)
                .font(Font(NotchNotificationBannerLayout.messageFont as CTFont))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(NotchNotificationBannerLayout.messageLines(stripHeight: geometry.stripHeight))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else if let level = notice.level {
            NotchMeter(value: level, height: 5, tint: tint)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: level)
                .transaction { $0.disablesAnimations = false }
        } else {
            Text(notice.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(textTint.opacity(0.8))
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
            NotchMeter(value: notice.level ?? 0, height: 5, tint: .white)
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
