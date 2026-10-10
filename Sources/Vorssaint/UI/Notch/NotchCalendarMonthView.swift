// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchCalendarMonthView: View {
    let month: Date
    let selectedDay: Date?
    let now: Date
    let height: CGFloat
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    let move: (Int) -> Void
    let today: () -> Void
    let open: () -> Void
    var browse: (Date) -> Void = { _ in }
    var settled: (Date) -> Void = { _ in }
    @State private var displayedMonth: Date?

    // Reserve the fixed header, footer and their two gaps before sizing all
    // six date rows. The wide page starts at 300 points, including its padding.
    private var gridHeight: CGFloat { min(222, max(0, height - 42 - 28 - 24)) }
    private var rowHeight: CGFloat { max(0, (gridHeight - 18 - 24) / 6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayedMonth ?? month, format: .dateTime.month(.wide))
                        .font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(displayedMonth ?? month, format: .dateTime.year())
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NotchIconButton(symbol: "chevron.left", title: text.previousMonth) { move(-1) }
                NotchIconButton(symbol: "chevron.right", title: text.nextMonth) { move(1) }
            }
            .frame(height: 42)
            NotchCalendarMonthDates(month: month, selectedDay: selectedDay, now: now, events: events, text: text,
                                    rowHeight: rowHeight, weekdayHeight: 18, spacing: 4,
                                    circle: min(24, max(0, rowHeight - 5)), dotGap: 2,
                                    select: select, browse: { date in displayedMonth = date; browse(date) }, settled: settled)
                .frame(height: gridHeight)
            HStack {
                Button(action: today) {
                    Text(text.today)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 12).frame(height: 28)
                        .modifier(NotchControlSurface(cornerRadius: 9))
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 9))
                Spacer(minLength: 4)
                NotchIconButton(symbol: "arrow.up.forward.app", title: text.openCalendar, action: open)
            }
            .frame(height: 28)
        }
        .foregroundStyle(.white)
        .onChange(of: month) { _, date in displayedMonth = date }
    }
}

/// One week as a row of days, for islands too short to hold the month grid.
struct NotchCalendarWeekStrip: View {
    static let height: CGFloat = 52
    let width: CGFloat
    let focus: Date
    let selectedDay: Date?
    let now: Date
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    let move: (Int) -> Void
    let today: () -> Void
    let week: () -> Void
    let month: () -> Void
    let open: () -> Void
    var browse: (Date) -> Void = { _ in }
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(focus, format: .dateTime.month(.wide).year())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            dateRow
        }
    }

    private var dateRow: some View {
        HStack(spacing: 4) {
            NotchIconButton(symbol: "chevron.left", title: text.previousWeek) { move(-1) }
            NotchCalendarCarousel(date: focus, component: .day, visibleCount: 7, browse: browse, settled: browse,
                                  contentState: NotchCalendarCarouselContentState(
                                    events: events, selectedDay: selectedDay, today: Calendar.current.startOfDay(for: now))) { date in
                dayButton(date)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            NotchIconButton(symbol: "chevron.right", title: text.nextWeek) { move(1) }
            // The month grid keeps Today and Calendar in its own header, so
            // the narrowest island keeps every day tappable and drops the
            // extras: a second tap on the selected day still returns to the
            // coming week, and every appointment card opens Calendar.
            NotchIconButton(symbol: "calendar", title: text.month, action: month)
            if width >= 400 {
                NotchIconButton(symbol: "circle.circle", title: text.today, action: today)
                NotchIconButton(symbol: "calendar.badge.clock", title: text.week, selected: selectedDay == nil, action: week)
            }
            if width >= 340 {
                NotchIconButton(symbol: "arrow.up.forward.app", title: text.openCalendar, action: open)
            }
        }
        .frame(height: Self.height)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(focus, format: .dateTime.month(.wide).year()))
    }

    private func dayButton(_ date: Date) -> some View {
        NotchCalendarWeekDayButton(date: date, now: now, events: events, text: text, select: select, week: week, locale: locale)
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

/// The month in an island too short for the grid beside the agenda: one
/// header row with the title, the navigation, Today and Calendar, then rows
/// sized to what is left. Choosing a day returns to the week on that day.
struct NotchCalendarMonthGrid: View {
    let month: Date
    let selectedDay: Date?
    let now: Date
    let height: CGFloat
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    let move: (Int) -> Void
    let today: () -> Void
    let open: () -> Void
    let week: () -> Void
    var browse: (Date) -> Void = { _ in }
    var settled: (Date) -> Void = { _ in }
    @State private var displayedMonth: Date?

    private var rowHeight: CGFloat { NotchLayout.calendarMonthRowHeight(height: height) }
    private var circle: CGFloat { min(24, rowHeight - 3) }

    var body: some View {
        VStack(spacing: NotchLayout.calendarMonthSpacing) {
            HStack(spacing: 4) {
                NotchIconButton(symbol: "chevron.left", title: text.previousMonth) { move(-1) }
                Text(displayedMonth ?? month, format: .dateTime.month(.wide).year())
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NotchIconButton(symbol: "chevron.right", title: text.nextMonth) { move(1) }
                NotchIconButton(symbol: "circle.circle", title: text.today, action: today)
                NotchIconButton(symbol: "arrow.up.forward.app", title: text.openCalendar, action: open)
                NotchIconButton(symbol: "calendar", title: text.month, selected: true, action: week)
            }
            .frame(height: NotchLayout.calendarMonthHeaderHeight)
            NotchCalendarMonthDates(month: month, selectedDay: selectedDay, now: now, events: events, text: text,
                                    rowHeight: rowHeight, weekdayHeight: NotchLayout.calendarMonthWeekdayHeight,
                                    spacing: 0, circle: circle, dotGap: 0, select: select,
                                    browse: { date in displayedMonth = date; browse(date) }, settled: settled)
                .frame(height: NotchLayout.calendarMonthWeekdayHeight + 6 * rowHeight)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: month) { _, date in displayedMonth = date }
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
