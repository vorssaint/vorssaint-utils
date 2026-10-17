// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The scrolling month beside the agenda; controls live in the island's top row.
struct NotchCalendarMonthView: View {
    let month: Date
    let selectedDay: Date?
    let now: Date
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    var browse: (Date) -> Void = { _ in }
    var settled: (Date) -> Void = { _ in }

    var body: some View {
        NotchCalendarMonthDates(month: month, selectedDay: selectedDay, now: now, events: events, text: text,
                                rowHeight: 30, weekdayHeight: 18, spacing: 4,
                                circle: 24, dotGap: 2, select: select, browse: browse, settled: settled)
            .frame(height: 222)
            .foregroundStyle(.white)
    }
}

/// One scrolling week, with navigation in the island's top row.
struct NotchCalendarWeekStrip: View {
    static let height: CGFloat = 52
    let focus: Date
    let selectedDay: Date?
    let now: Date
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    let week: () -> Void
    var browse: (Date) -> Void = { _ in }
    @Environment(\.locale) private var locale

    var body: some View {
        NotchCalendarCarousel(date: focus, component: .day, visibleCount: 7, browse: browse, settled: browse,
                              contentState: NotchCalendarCarouselContentState(
                                events: events, selectedDay: selectedDay, today: Calendar.current.startOfDay(for: now))) { date in
            NotchCalendarWeekDayButton(date: date, now: now, events: events, text: text,
                                       select: select, week: week, locale: locale)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(focus, format: .dateTime.month(.wide).year()))
    }
}

private struct NotchCalendarWeekDayButton: View {
    let date: Date
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    let week: () -> Void
    private let isToday: Bool
    private let colors: [NotchCalendarColor]
    private let hasEvents: Bool
    private let weekday: String
    private let dayNumber: String
    private let label: String
    @EnvironmentObject private var selection: NotchCalendarTileSelection
    private let accent = Color(red: 1, green: 0.36, blue: 0.39)

    init(date: Date, now: Date, events: [NotchCalendarEvent], text: NotchCalendarStrings,
         select: @escaping (Date) -> Void, week: @escaping () -> Void, locale: Locale) {
        self.date = date
        self.text = text
        self.select = select
        self.week = week
        var calendar = Calendar.current
        calendar.locale = locale
        isToday = calendar.isDate(date, inSameDayAs: now)
        dayNumber = NotchCalendarSupport.dayNumber(date, locale: locale, calendar: calendar)
        let dayEvents = NotchCalendarSupport.events(events, on: date, calendar: calendar)
        hasEvents = !dayEvents.isEmpty
        colors = dayEvents.reduce(into: [NotchCalendarColor]()) { colors, event in
            if colors.count < 3 && !colors.contains(event.color) { colors.append(event.color) }
        }
        weekday = calendar.veryShortStandaloneWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        label = date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale))
    }

    var body: some View {
        let selected = selection.selected
        // A second tap on the selected day returns to the coming week.
        return Button { selected ? week() : select(date) } label: {
            VStack(spacing: 2) {
                Text(weekday)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Text(dayNumber)
                    .font(.system(size: 12, weight: isToday || selected ? .bold : .medium))
                    .foregroundStyle(selected && !isToday ? .black : .white)
                    .frame(width: 26, height: 26)
                    .background(isToday ? accent : selected ? .white : .clear, in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(selected && isToday ? 0.8 : 0), lineWidth: 1.5)
                    }
                HStack(spacing: 2) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color.color).frame(width: 3, height: 3)
                    }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: NotchCalendarWeekStrip.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 10, lifts: false))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue([isToday ? text.today : "", hasEvents ? text.hasEvents : ""]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The scrolling month fills a short island below its top-row controls.
struct NotchCalendarMonthGrid: View {
    let month: Date
    let selectedDay: Date?
    let now: Date
    let height: CGFloat
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    var browse: (Date) -> Void = { _ in }
    var settled: (Date) -> Void = { _ in }

    private var rowHeight: CGFloat { NotchLayout.calendarMonthRowHeight(height: height) }
    private var circle: CGFloat { min(24, rowHeight - 3) }

    var body: some View {
        NotchCalendarMonthDates(month: month, selectedDay: selectedDay, now: now, events: events, text: text,
                                rowHeight: rowHeight, weekdayHeight: NotchLayout.calendarMonthWeekdayHeight,
                                spacing: 0, circle: circle, dotGap: 0, select: select,
                                browse: browse, settled: settled)
            .frame(height: NotchLayout.calendarMonthWeekdayHeight + 6 * rowHeight)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Only the date drawings travel. Titles and controls belong to the fixed
/// surrounding layout, so a fractional month cannot cut them in half.
private struct NotchCalendarMonthDates: View {
    let month: Date
    let selectedDay: Date?
    let now: Date
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let rowHeight: CGFloat
    let weekdayHeight: CGFloat
    let spacing: CGFloat
    let circle: CGFloat
    let dotGap: CGFloat
    let select: (Date) -> Void
    let browse: (Date) -> Void
    let settled: (Date) -> Void
    @AppStorage(DefaultsKey.notchCalendarWeekNumbers) private var weekNumbers = false

    var body: some View {
        NotchCalendarCarousel(date: month, component: .month, visibleCount: 1,
                              browse: browse, settled: settled, scrollSensitivity: 0.75, monthAlignmentTolerance: 0.14,
                              coastsMonths: true,
                              contentState: NotchCalendarCarouselContentState(
                                events: events, selectedDay: selectedDay, today: Calendar.current.startOfDay(for: now),
                                weekNumbers: weekNumbers)) { date in
            NotchCalendarMonthCanvas(month: date, selectedDay: selectedDay, now: now, events: events, text: text,
                                     rowHeight: rowHeight, weekdayHeight: weekdayHeight, spacing: spacing,
                                     circle: circle, dotGap: dotGap, select: select,
                                     horizontalPadding: 20, weekNumbers: weekNumbers)
        }
        .clipped()
    }
}
