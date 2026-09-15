// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchTimerStrip: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var timer = NotchTimerService.shared
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { service.compactActivityGeometry }
    private var outerInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        let shoulder = min(NotchLayout.shoulder, geometry.compactActivityContentHeight * 0.28)
        return shoulder + 6
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { service.open(service.hasDownloadActivity ? .downloads : .timer) } label: {
                Group {
                    if geometry.compactActivityWingWidth >= 28 {
                        if service.hasDownloadActivity {
                            downloadIndicator
                        } else {
                            Image(systemName: timer.session.completed ? "checkmark.circle" : timer.session.isPaused ? "pause.circle" : "timer")
                                .font(.system(size: min(20, geometry.compactActivityContentHeight - 6), weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.leading, outerInset)
                .padding(.trailing, geometry.compactActivityUsesFooter ? 0 : 8)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(service.hasDownloadActivity ? FeatureStrings.notchFiles(l10n.language).downloadsTitle
                                 : FeatureStrings.notchActivities(l10n.language).phase(timer.session.phase))
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            TimelineView(.animation(minimumInterval: 1, paused: !timer.session.isRunning)) { _ in
                let seconds = timer.session.remaining(at: timer.now)
                let locale = Locale(identifier: l10n.language.rawValue)
                let remaining = seconds >= 3600
                    ? Duration.seconds(seconds).formatted(.time(pattern: .hourMinute(padHourToLength: 1, roundSeconds: .down)).locale(locale))
                    : NotchTimerSupport.compactText(seconds, locale: locale)
                Button { service.open(.timer) } label: {
                    Group {
                        if geometry.compactActivityWingWidth >= 42 {
                            Text(remaining)
                                .font(.system(size: min(16, geometry.compactActivityContentHeight - 6), weight: .medium)).monospacedDigit()
                                .foregroundStyle(.orange)
                                .lineLimit(1).minimumScaleFactor(0.65)
                        }
                    }
                    .padding(.leading, geometry.compactActivityUsesFooter ? 0 : 8)
                    .padding(.trailing, outerInset)
                    .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(FeatureStrings.notchActivities(l10n.language).phase(timer.session.phase))
                .accessibilityValue(NotchTimerSupport.clockText(seconds))
            }
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .buttonStyle(.plain)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
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
