// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import EventKit
import SwiftUI

/// The This Mac page's calendar: today, this week or the month, as chosen in
/// Settings. The card keeps the height the page gives it in every view, and
/// what does not fit scrolls inside it: the one part of the page that takes
/// input, along with picking a day in the month.
struct NotchLockScreenCalendarCard: View {
    let events: [NotchCalendarEvent]
    let hidesTitles: Bool
    let access: EKAuthorizationStatus
    let view: NotchLockScreenCalendarView
    @ObservedObject private var l10n = L10n.shared
    /// The day picked in the month; today until one is.
    @State private var picked: Date?

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = l10n.language.formattingLocale()
        return calendar
    }

    var body: some View {
        let text = FeatureStrings.notchCalendar(l10n.language)
        let locked = FeatureStrings.notchLockScreen(l10n.language)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            NotchAgentCardChrome {
                VStack(alignment: .leading, spacing: 8) {
                    NotchAgentCardHeader(title: title(now, text: text, locked: locked), symbol: "calendar", tint: .red) {
                        Text(subtitle(now))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if access != .fullAccess {
                        message(access == .denied || access == .restricted ? text.denied : text.permission)
                    } else {
                        switch view {
                        case .day: day(now, text: text, locked: locked)
                        case .week: week(now, text: text, locked: locked)
                        case .month: month(now, text: text)
                        }
                    }
                }
            }
        }
    }

    private func title(_ now: Date, text: NotchCalendarStrings, locked: NotchLockScreenStrings) -> String {
        switch view {
        case .day: return text.today
        case .week: return locked.thisWeek
        case .month: return now.formatted(.dateTime.month(.wide).locale(l10n.language.formattingLocale()))
        }
    }

    private func subtitle(_ now: Date) -> String {
        let locale = l10n.language.formattingLocale()
        switch view {
        case .day:
            return now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
        case .week:
            let days = NotchCalendarSupport.weekDays(containing: now, calendar: calendar)
            guard let first = days.first, let last = days.last else { return "" }
            return (first..<last).formatted(.interval.day().month(.abbreviated).locale(locale))
        case .month:
            return now.formatted(.dateTime.year().locale(locale))
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func name(_ event: NotchCalendarEvent, text: NotchCalendarStrings) -> String {
        hidesTitles ? FeatureStrings.notchLockScreen(l10n.language).busy
            : NotchCalendarStrip.displayTitle(event, untitled: text.untitled)
    }

    private func ended(_ event: NotchCalendarEvent, now: Date) -> Bool {
        event.end <= now && !event.allDay
    }

    private func day(of date: Date, offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date
    }

    // MARK: Day

    /// Today's all-day events, then what has ended, a line at the time and
    /// what is still to come, then tomorrow. It opens on the line.
    private func day(_ now: Date, text: NotchCalendarStrings, locked: NotchLockScreenStrings) -> some View {
        let today = NotchCalendarSupport.events(events, on: now, calendar: calendar)
        let allDay = today.filter(\.allDay)
        let timed = today.filter { !$0.allDay }
        let past = timed.filter { ended($0, now: now) }
        let coming = timed.filter { !ended($0, now: now) }
        let tomorrowDate = day(of: now, offset: 1)
        let tomorrow = NotchCalendarSupport.events(events, on: tomorrowDate, calendar: calendar)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(allDay + past) { dayRow($0, now: now, today: true, text: text, locked: locked) }
                    nowLine(now).id(Self.nowLine)
                    if coming.isEmpty { emptyLine(locked.nothingElse) }
                    ForEach(coming) { dayRow($0, now: now, today: true, text: text, locked: locked) }
                    sectionTitle(locked.tomorrow + " · " + tomorrowDate.formatted(
                        .dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(l10n.language.formattingLocale())),
                                 tint: .secondary)
                    if tomorrow.isEmpty { emptyLine(text.emptyDay) }
                    ForEach(tomorrow) { dayRow($0, now: now, today: false, text: text, locked: locked) }
                }
                .padding(.bottom, 14)
            }
            .scrollIndicators(.automatic)
            .mask(Self.fade)
            .onAppear { proxy.scrollTo(Self.nowLine, anchor: UnitPoint(x: 0, y: 0.2)) }
        }
    }

    private static let nowLine = "now"

    private func dayRow(_ event: NotchCalendarEvent, now: Date, today: Bool, text: NotchCalendarStrings,
                        locked: NotchLockScreenStrings) -> some View {
        let live = today && !event.allDay && event.start <= now && event.end > now
        let soon = today && !event.allDay && event.start > now
        let locale = l10n.language.formattingLocale()
        return HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 0) {
                Text(event.allDay ? text.allDay : event.start.formatted(.dateTime.hour().minute().locale(locale)))
                    .font(.system(size: 9.5, weight: .semibold))
                if !event.allDay {
                    Text(event.end.formatted(.dateTime.hour().minute().locale(locale)))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: 52, alignment: .leading)
            RoundedRectangle(cornerRadius: 1.5).fill(event.color.color).frame(width: 3, height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(name(event, text: text))
                    .font(.system(size: 10.5, weight: .semibold))
                if !hidesTitles, !event.location.isEmpty {
                    Text(event.location)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if live {
                Text(locked.now).foregroundStyle(.red)
            } else if soon {
                Text(event.start.formatted(.relative(presentation: .named).locale(locale))).foregroundStyle(.cyan)
            }
        }
        .font(.system(size: 9.5, weight: .semibold))
        .monospacedDigit()
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background(live ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .opacity(today && ended(event, now: now) ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    private func nowLine(_ now: Date) -> some View {
        HStack(spacing: 5) {
            Text(now.formatted(.dateTime.hour().minute().locale(l10n.language.formattingLocale())))
                .font(.system(size: 8.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.red)
                .frame(width: 52, alignment: .leading)
            Circle().fill(.red).frame(width: 5, height: 5)
            Capsule().fill(.red).frame(height: 1)
        }
        .padding(.horizontal, 6)
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private func sectionTitle(_ title: String, tint: Color) -> some View {
        Text(title.uppercased(with: l10n.language.formattingLocale()))
            .font(.system(size: 8, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func emptyLine(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(height: 24)
    }

    // MARK: Week

    /// The calendar's week around today, a column a day; a busy day scrolls
    /// the whole week.
    private func week(_ now: Date, text: NotchCalendarStrings, locked: NotchLockScreenStrings) -> some View {
        let days = NotchCalendarSupport.weekDays(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let locale = l10n.language.formattingLocale()
        return ScrollView {
            HStack(alignment: .top, spacing: 4) {
                ForEach(days, id: \.self) { date in
                    let isToday = date == today
                    let shown = NotchCalendarSupport.events(events, on: date, calendar: calendar)
                    VStack(spacing: 3) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated).locale(locale)).uppercased(with: locale))
                            .font(.system(size: 7.5, weight: .semibold))
                            .foregroundStyle(isToday ? Color.red : .secondary)
                            .lineLimit(1)
                        Text(date.formatted(.dateTime.day().locale(locale)))
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 19, height: 19)
                            .background(isToday ? Color.red : .clear, in: Circle())
                        ForEach(shown) { event in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(event.allDay ? text.allDay : event.start.formatted(.dateTime.hour().minute().locale(locale)))
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundStyle(event.color.color)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                Text(name(event, text: text))
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(event.color.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .opacity(isToday && ended(event, now: now) ? 0.45 : 1)
                            .accessibilityElement(children: .combine)
                        }
                        if shown.isEmpty {
                            Text(locked.free)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 22)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(.white.opacity(0.16), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(date < today ? 0.5 : 1)
                }
            }
            .padding(.bottom, 14)
        }
        .scrollIndicators(.automatic)
        .mask(Self.fade)
    }

    // MARK: Month

    /// The month grid stays put; the picked day's events, and the next days
    /// with any, scroll beside it.
    private func month(_ now: Date, text: NotchCalendarStrings) -> some View {
        let locale = l10n.language.formattingLocale()
        let days = NotchCalendarSupport.monthDays(containing: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let selected = picked ?? today
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let weekdays = Array(symbols[first...] + symbols[..<first])
        return HStack(alignment: .top, spacing: 10) {
            GeometryReader { proxy in
                // The weekday letters, then six weeks with a gap between each.
                let row = max(14, min(24, (proxy.size.height - 12 - 2 - 5 * 2) / 6))
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        ForEach(weekdays.indices, id: \.self) { index in
                            Text(weekdays[index]).frame(maxWidth: .infinity)
                        }
                    }
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(height: 12)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                        ForEach(days, id: \.self) { date in
                            dayCell(date, today: today, selected: selected, month: now, height: row, locale: locale)
                        }
                    }
                }
            }
            .frame(width: 182)
            Divider().overlay(.white.opacity(0.12))
            agenda(selected: selected, today: today, now: now, text: text, locale: locale)
        }
    }

    private func dayCell(_ date: Date, today: Date, selected: Date, month: Date, height: CGFloat,
                         locale: Locale) -> some View {
        let isToday = date == today
        let isPicked = date == selected
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let dots = Array(NotchCalendarSupport.events(events, on: date, calendar: calendar).prefix(3))
        return Button {
            picked = date
        } label: {
            VStack(spacing: 1) {
                Text(date.formatted(.dateTime.day().locale(locale)))
                    .font(.system(size: 9.5, weight: isToday || isPicked ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday && !isPicked ? Color.red : date < today ? .secondary : .primary)
                HStack(spacing: 1.5) {
                    ForEach(dots) { event in
                        Circle().fill(isToday && isPicked ? Color.white : event.color.color).frame(width: 3, height: 3)
                    }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(isToday && isPicked ? Color.red : isPicked ? Color.white.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .opacity(inMonth ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func agenda(selected: Date, today: Date, now: Date, text: NotchCalendarStrings,
                        locale: Locale) -> some View {
        let format = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)
        let following = (1...40).lazy
            .map { self.day(of: selected, offset: $0) }
            .map { ($0, NotchCalendarSupport.events(events, on: $0, calendar: calendar)) }
            .filter { !$0.1.isEmpty }
            .prefix(4)
        let picked = NotchCalendarSupport.events(events, on: selected, calendar: calendar)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle((selected == today ? text.today + " · " : "") + selected.formatted(format),
                             tint: selected == today ? .red : .secondary)
                if picked.isEmpty { emptyLine(text.emptyDay) }
                ForEach(picked) { agendaRow($0, past: selected < today || (selected == today && ended($0, now: now)),
                                            text: text, locale: locale) }
                ForEach(Array(following), id: \.0) { date, shown in
                    sectionTitle(date.formatted(format), tint: .secondary)
                    ForEach(shown) { agendaRow($0, past: false, text: text, locale: locale) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.automatic)
        .mask(Self.fade)
    }

    private func agendaRow(_ event: NotchCalendarEvent, past: Bool, text: NotchCalendarStrings,
                           locale: Locale) -> some View {
        HStack(spacing: 6) {
            Circle().fill(event.color.color).frame(width: 5, height: 5)
            Text(event.allDay ? text.allDay : event.start.formatted(.dateTime.hour().minute().locale(locale)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 48, alignment: .leading)
            Text(name(event, text: text))
                .fontWeight(.semibold)
        }
        .font(.system(size: 9.5, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(height: 22)
        .opacity(past ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    /// What scrolls fades out at the card's foot, saying there is more.
    private static let fade = LinearGradient(
        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1)],
        startPoint: .top, endPoint: .bottom)
}
