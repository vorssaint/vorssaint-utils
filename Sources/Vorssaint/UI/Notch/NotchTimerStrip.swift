// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchTimerStrip: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { service.compactActivityGeometry }
    /// Height the strip can give away once both edges keep their gap.
    private var budget: CGFloat { geometry.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2 }
    private var iconSize: CGFloat { min(service.hasDownloadActivity ? 13 : 20, budget) }
    private var textSize: CGFloat { min(16, geometry.compactActivityContentHeight - 6) }
    private var iconInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        return geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
    }
    private var textInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        // Digits carry no descenders, so their ink is about the cap height.
        return geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { service.open(service.hasDownloadActivity ? .downloads : .timer) } label: {
                Group {
                    if geometry.compactActivityWingWidth >= 28 {
                        if service.hasDownloadActivity {
                            downloadIndicator
                        } else {
                            Image(systemName: timer.session.completed ? "checkmark.circle"
                                  : timer.session.isPaused ? "pause.circle" : timer.session.countsUp ? "stopwatch" : "timer")
                                .font(.system(size: iconSize, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.leading, iconInset)
                .padding(.trailing, geometry.compactActivityUsesFooter ? 0 : 8)
                // Leading and trailing wings anchor to their own edge, so the
                // silhouette's curve decides the margin instead of the content.
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(service.hasDownloadActivity ? FeatureStrings.notchFiles(l10n.language).downloadsTitle
                                 : FeatureStrings.notchActivities(l10n.language).phase(timer.session.phase))
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
                }
            }
            .padding(.leading, geometry.compactActivityUsesFooter ? 0 : 8)
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
