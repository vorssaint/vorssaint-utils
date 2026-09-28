// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The next timed event, or the one under way, stays readable beside the
/// camera and moves below a physical notch when the menu bar cannot spare
/// two useful wings.
struct NotchCalendarStrip: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { service.compactActivityGeometry }
    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    private var usesFullRow: Bool { geometry.compactActivityUsesFooter || geometry.compactActivityWingWidth == 0 }

    var body: some View {
        if let countdown = calendar.countdown {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let title = countdown.event.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = title.isEmpty ? text.untitled : title
                let remaining = NotchCalendarSupport.countdownText(until: countdown.target, now: context.date)
                Button { service.open(.calendar) } label: {
                    Group {
                        if usesFullRow {
                            fullRow(countdown, title: displayTitle, remaining: remaining)
                        } else {
                            wings(countdown, title: displayTitle, remaining: remaining)
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
                .accessibilityLabel("\(countdown.ongoing ? text.ongoing : text.next): \(displayTitle)")
                .accessibilityValue(NotchCalendarSupport.countdownAccessibilityText(
                    until: countdown.target, now: context.date, locale: l10n.language.formattingLocale()))
                .accessibilityHint(FeatureStrings.notch(l10n.language).open)
                .help(displayTitle)
            }
            .accessibilityIdentifier("notch.calendarCountdown")
        }
    }

    private func fullRow(_ countdown: NotchCalendarCountdown, title: String, remaining: String) -> some View {
        // The row below the camera ends in the island's deep lower corners;
        // a fixed margin left the dot and the clock on their curve.
        HStack(spacing: 6) {
            dot(countdown.event)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            clock(remaining, ongoing: countdown.ongoing)
        }
        .padding(.horizontal, max(10, geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0)))
    }

    private func wings(_ countdown: NotchCalendarCountdown, title: String, remaining: String) -> some View {
        let inset = geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0)
        return HStack(spacing: 0) {
            HStack(spacing: NotchCalendarSupport.stripTitleSpacing) {
                dot(countdown.event)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.leading, inset)
            .frame(width: geometry.compactActivityWingWidth, alignment: .trailing)
            .clipped()
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            // The start or end time fills the side the clock alone left
            // mostly empty; a wing narrowed by the menus keeps just the clock.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NotchCalendarSupport.stripClockSpacing) {
                    clock(remaining, ongoing: countdown.ongoing)
                    Text(NotchCalendarSupport.timeText(countdown, locale: l10n.language.formattingLocale()))
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize()
                }
                clock(remaining, ongoing: countdown.ongoing)
            }
            .padding(.trailing, inset)
            .frame(width: geometry.compactActivityWingWidth, alignment: .leading)
        }
    }

    private func dot(_ event: NotchCalendarEvent) -> some View {
        Circle().fill(event.color.color).frame(width: 6, height: 6)
            .overlay { Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5) }
            .accessibilityHidden(true)
    }

    /// Time left in an event under way takes the agenda's "happening now"
    /// color, so it never reads as a wait for the next one.
    private func clock(_ remaining: String, ongoing: Bool) -> some View {
        Text(remaining)
            .font(.system(size: 13, weight: .medium)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(ongoing ? Color.mint : Color.white)
    }
}
