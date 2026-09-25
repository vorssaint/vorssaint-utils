// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The clock keeps the right of the camera. The left shows the timer's mark,
/// or whatever shares the island with it: a download, working agents or the
/// music playing, each opening its own page. The wings are as wide as the
/// wider side needs, and both sit at the ends, where the island shows.
struct NotchTimerStrip: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { service.compactActivityGeometry }
    private var companion: NotchCompactActivity? { service.compactCompanion }
    private var iconSize: CGFloat {
        let size = NotchTimerSupport.stripIconSize(height: geometry.compactActivityContentHeight)
        return companion == .downloads ? min(13, size) : size
    }
    private var textSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var working: [AgentProvider] {
        AgentProvider.allCases.filter { provider in usage.snapshot.live.contains { $0.provider == provider } }
    }
    private var agentMarkSize: CGFloat {
        NotchTimerSupport.stripAgentMarkSize(height: geometry.compactActivityContentHeight, working: working.count)
    }
    private var iconInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        switch companion {
        case .agents:
            return geometry.compactActivityEdgeInset(boxHeight: agentMarkSize + 4, radius: (agentMarkSize + 4) / 2)
        case .music:
            return geometry.compactMusicArtworkInset
        default:
            return geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
        }
    }
    private var textInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        // Digits carry no descenders, so their ink is about the cap height.
        return geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { service.open(companion?.module ?? .timer) } label: {
                Group {
                    if geometry.compactActivityWingWidth >= 28 {
                        switch companion {
                        case .downloads:
                            downloadIndicator
                        case .agents:
                            HStack(spacing: 1) {
                                ForEach(working) { NotchAgentGlyph(provider: $0, size: agentMarkSize) }
                            }
                        case .music:
                            NotchMusicCover(artwork: music.artwork, side: geometry.compactMusicArtworkSide,
                                            radius: geometry.compactMusicArtworkRadius)
                        default:
                            Image(systemName: timer.session.completed ? "checkmark.circle"
                                  : timer.session.isPaused ? "pause.circle" : timer.session.countsUp ? "stopwatch" : "timer")
                                .font(.system(size: iconSize, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.leading, iconInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(companionLabel)
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            if timer.session.isRunning {
                TimelineView(.periodic(from: Date(timeIntervalSinceNow: NotchTimerSupport.tickScheduleOffset(
                    for: timer.session, at: timer.now)), by: 1)) { _ in reading }
            } else {
                reading
            }
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .buttonStyle(.plain)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private var companionLabel: String {
        switch companion {
        case .downloads:
            return FeatureStrings.notchFiles(l10n.language).downloadsTitle
        case .agents:
            return working.map(\.displayName).joined(separator: ", ")
        case .music:
            let title = music.playback?.track.title ?? FeatureStrings.radialMenu(l10n.language).mediaNowPlaying
            return [title, music.playback?.track.artist].compactMap { $0 }.joined(separator: ", ")
        default:
            return FeatureStrings.notchActivities(l10n.language).phase(timer.session.phase)
        }
    }

    private var reading: some View {
        let now = timer.now
        let text = NotchTimerSupport.compactText(for: timer.session, at: now,
                                                 locale: Locale(identifier: l10n.language.rawValue))
        return Button { service.open(.timer) } label: {
            Group {
                if geometry.compactActivityWingWidth >= 42 {
                    Text(text)
                        .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.orange)
                        .lineLimit(1).minimumScaleFactor(0.65)
                        // A reading that gains or loses a character, like
                        // 10m becoming 9m, resizes the wings; the service
                        // measures the same reading.
                        .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                            DispatchQueue.main.async { service.refreshPresentation() }
                        }
                }
            }
            .padding(.trailing, textInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                   alignment: .trailing)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(FeatureStrings.notchActivities(l10n.language).phase(timer.session.phase))
        .accessibilityValue(NotchTimerSupport.clockText(for: timer.session, at: now))
    }

    private var downloadIndicator: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 13))
            if geometry.compactActivityWingWidth >= 80,
               let fraction = downloads.items.first(where: { $0.active && !$0.completed })?.fraction {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
            }
        }
        .lineLimit(1)
        .clipped()
    }
}
