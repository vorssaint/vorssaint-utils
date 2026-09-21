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
        default: return .white
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .padding(.horizontal, inset)
                .frame(width: wingWidth, height: geometry.stripHeight)
                .clipped()
            Color.clear.frame(width: geometry.noticeCameraGap)
            trailing
                .padding(.horizontal, inset)
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
                Image(systemName: notice.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(notice.level == nil ? notice.title : notice.detail)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
