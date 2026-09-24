// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The next timed event stays readable beside the camera and moves below a
/// physical notch when the menu bar cannot spare two useful wings.
struct NotchCalendarStrip: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { service.compactActivityGeometry }
    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    private var usesFullRow: Bool { geometry.compactActivityUsesFooter || geometry.compactActivityWingWidth == 0 }

    var body: some View {
        if let event = calendar.countdownEvent {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = title.isEmpty ? text.untitled : title
                let remaining = NotchCalendarSupport.countdownText(until: event.start, now: context.date)
                Button { service.open(.calendar) } label: {
                    Group {
                        if usesFullRow {
                            fullRow(event: event, title: displayTitle, remaining: remaining)
                        } else {
                            wings(event: event, title: displayTitle, remaining: remaining)
                        }
                    }
                    .frame(width: geometry.compactActivitySize.width - geometry.compactActivityHorizontalPadding * 2,
                           height: geometry.compactActivityContentHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, geometry.compactActivityHorizontalPadding)
                .padding(.top, geometry.compactActivityTopPadding)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(text.next): \(displayTitle)")
                .accessibilityValue(NotchCalendarSupport.countdownAccessibilityText(
                    until: event.start, now: context.date, locale: l10n.language.formattingLocale()))
                .accessibilityHint(FeatureStrings.notch(l10n.language).open)
                .help(displayTitle)
            }
            .accessibilityIdentifier("notch.calendarCountdown")
        }
    }

    private func fullRow(event: NotchCalendarEvent, title: String, remaining: String) -> some View {
        HStack(spacing: 6) {
            dot(event)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            clock(remaining)
        }
        .padding(.horizontal, 10)
    }

    private func wings(event: NotchCalendarEvent, title: String, remaining: String) -> some View {
        let inset = geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0)
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                dot(event)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.leading, inset)
            .frame(width: geometry.compactActivityWingWidth, alignment: .trailing)
            .clipped()
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            clock(remaining)
                .padding(.trailing, inset)
                .frame(width: geometry.compactActivityWingWidth, alignment: .leading)
        }
    }

    private func dot(_ event: NotchCalendarEvent) -> some View {
        Circle().fill(event.color.color).frame(width: 6, height: 6)
            .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5) }
            .accessibilityHidden(true)
    }

    private func clock(_ remaining: String) -> some View {
        Text(remaining)
            .font(.system(size: 13, weight: .medium)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(.white)
    }
}
