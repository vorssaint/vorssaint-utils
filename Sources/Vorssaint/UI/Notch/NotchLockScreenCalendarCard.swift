// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import EventKit
import SwiftUI

/// Today on the stage over the player: as many of the day's events as the
/// card holds, the last one past dimmed above the next, which counts down.
/// It never scrolls and takes no input. A day with nothing left says so,
/// with tomorrow's first event.
struct NotchLockScreenCalendarCard: View {
    let hidesTitles: Bool
    let size: CGSize
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared

    private typealias Tile = NotchLockScreenTile
    static let rowHeight: CGFloat = 32
    static let rowGap: CGFloat = 7
    private static let padding: CGFloat = 16
    private static let header: CGFloat = 14 + 9

    private var cal: Calendar {
        var cal = Calendar.current
        cal.locale = l10n.language.formattingLocale()
        return cal
    }

    var body: some View {
        let text = FeatureStrings.notchCalendar(l10n.language)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let today = NotchCalendarSupport.events(calendar.events, on: now, calendar: cal)
            let upcoming = today.firstIndex { !ended($0, now: now) }
            let left = today.filter { !$0.allDay && !ended($0, now: now) }.count
            VStack(alignment: .leading, spacing: 9) {
                NotchLockScreenSection(title: text.today, symbol: "calendar") {
                    if left > 0 {
                        Text(String(format: FeatureStrings.notchLockScreenWidgets(l10n.language).leftFormat, left))
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                if permissions.calendarAccess != .fullAccess {
                    message(permissions.calendarAccess == .denied || permissions.calendarAccess == .restricted
                            ? text.denied : text.permission)
                } else if let upcoming {
                    let fits = Int((size.height - Self.padding * 2 - Self.header + Self.rowGap)
                                   / (Self.rowHeight + Self.rowGap))
                    let shown = NotchLockScreenSupport.dayWindow(count: today.count, upcoming: upcoming, fits: fits)
                    let next = today[upcoming...].first { !$0.allDay }?.id
                    VStack(alignment: .leading, spacing: Self.rowGap) {
                        ForEach(today[shown]) { row($0, now: now, next: $0.id == next, text: text) }
                    }
                } else {
                    clear(now: now, text: text)
                }
            }
            .lockScreenTile(horizontal: 20, vertical: Self.padding)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func ended(_ event: NotchCalendarEvent, now: Date) -> Bool {
        event.end <= now
    }

    private func title(_ event: NotchCalendarEvent, text: NotchCalendarStrings) -> String {
        hidesTitles ? FeatureStrings.notchLockScreen(l10n.language).busy
            : NotchCalendarStrip.displayTitle(event, untitled: text.untitled)
    }

    private func row(_ event: NotchCalendarEvent, now: Date, next: Bool, text: NotchCalendarStrings) -> some View {
        let locale = l10n.language.formattingLocale()
        let live = !event.allDay && event.start <= now && event.end > now
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(event.allDay ? text.allDay : event.start.formatted(.dateTime.hour().minute().locale(locale)))
                    .font(.system(size: 13, weight: .semibold))
                if !event.allDay {
                    Text(event.end.formatted(.dateTime.hour().minute().locale(locale)))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Tile.dim)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 70, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(event.color.color).frame(width: 4, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(title(event, text: text))
                    .font(.system(size: 15, weight: .semibold))
                if !hidesTitles, !event.location.isEmpty {
                    Text(event.location)
                        .font(.system(size: 10))
                        .foregroundStyle(Tile.dim)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if live || next {
                NotchLockScreenBadge(
                    text: live ? FeatureStrings.notchLockScreen(l10n.language).now
                        : event.start.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(locale)),
                    level: .good)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
            }
        }
        .frame(height: Self.rowHeight)
        .opacity(ended(event, now: now) ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    /// Nothing left today: tomorrow's first event under it, if any.
    private func clear(now: Date, text: NotchCalendarStrings) -> some View {
        let locked = FeatureStrings.notchLockScreen(l10n.language)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let first = NotchCalendarSupport.events(calendar.events, on: tomorrow, calendar: cal).first
        return VStack(alignment: .leading, spacing: 4) {
            Text(locked.nothingElse)
                .font(Tile.rounded(26))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let first {
                Text(locked.tomorrow + " "
                     + (first.allDay ? text.allDay
                        : first.start.formatted(.dateTime.hour().minute().locale(l10n.language.formattingLocale())))
                     + " · " + title(first, text: text))
                    .font(.system(size: 12))
                    .foregroundStyle(Tile.dim)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Tile.dim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
