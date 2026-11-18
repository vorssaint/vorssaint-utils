// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The month beside the agenda of a tall island. Its title, the arrows and
/// Today are in the island's top row.
struct NotchCalendarMonthView: View {
    let month: Date
    let selectedDay: Date?
    let now: Date
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    @Environment(\.locale) private var locale
    @AppStorage(DefaultsKey.notchCalendarWeekNumbers) private var weekNumbers = false
    private let accent = Color(red: 1, green: 0.36, blue: 0.39)
    private var columns: [GridItem] { NotchCalendarWeekNumber.columns(numbered: weekNumbers) }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            if weekNumbers { Color.clear.frame(height: 18).accessibilityHidden(true) }
            ForEach(0..<7, id: \.self) { column in
                let index = (Calendar.current.firstWeekday - 1 + column) % 7
                Text(weekdaySymbols[index])
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity).frame(height: 18)
                    .accessibilityHidden(true)
            }
            ForEach(NotchCalendarSupport.monthDays(containing: month), id: \.self) { date in
                if weekNumbers, NotchCalendarSupport.startsWeek(date) {
                    NotchCalendarWeekNumber(date: date, text: text, digit: 24, spacing: 2, height: 30)
                }
                dayButton(date)
            }
        }
        .foregroundStyle(.white)
    }

    private var weekdaySymbols: [String] {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar.veryShortStandaloneWeekdaySymbols
    }

    private func dayButton(_ date: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let selected = selectedDay.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let dayEvents = NotchCalendarSupport.events(events, on: date)
        let colors = dayEvents.reduce(into: [NotchCalendarColor]()) { result, event in
            if result.count < 3 && !result.contains(event.color) { result.append(event.color) }
        }
        return Button { select(date) } label: {
            VStack(spacing: 2) {
                // The number alone: a formatted day carries the language's suffix,
                // as 28日 or 28일, which the circle cuts off.
                Text(calendar.component(.day, from: date), format: .number)
                    .font(.system(size: 11, weight: isToday || selected ? .bold : .medium))
                    .foregroundStyle(selected && !isToday ? .black : .white.opacity(isToday || inMonth ? 1 : 0.4))
                    .frame(width: 24, height: 24)
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
            .frame(maxWidth: .infinity).frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 8, lifts: false))
        .help(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)))
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue([isToday ? text.today : "", dayEvents.isEmpty ? "" : text.hasEvents]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One week as a row of days across the page, for islands too short to hold
/// the month grid. The month, the arrows and Today are in the island's top
/// row; a second tap on the selected day returns to the coming week.
struct NotchCalendarWeekStrip: View {
    static let height: CGFloat = 52
    let focus: Date
    let selectedDay: Date?
    let now: Date
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    let week: () -> Void
    @Environment(\.locale) private var locale
    private let accent = Color(red: 1, green: 0.36, blue: 0.39)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchCalendarSupport.weekDays(containing: focus), id: \.self) { date in
                dayButton(date)
            }
        }
        .frame(height: Self.height)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(focus, format: .dateTime.month(.wide).year()))
    }

    private var weekdaySymbols: [String] {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar.veryShortStandaloneWeekdaySymbols
    }

    private func dayButton(_ date: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let selected = selectedDay.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let dayEvents = NotchCalendarSupport.events(events, on: date)
        let colors = dayEvents.reduce(into: [NotchCalendarColor]()) { result, event in
            if result.count < 3 && !result.contains(event.color) { result.append(event.color) }
        }
        // A second tap on the selected day returns to the coming week.
        return Button { selected ? week() : select(date) } label: {
            VStack(spacing: 2) {
                Text(weekdaySymbols[calendar.component(.weekday, from: date) - 1])
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                Text(calendar.component(.day, from: date), format: .number)
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
            .frame(height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 10, lifts: false))
        .help(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)))
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue([isToday ? text.today : "", dayEvents.isEmpty ? "" : text.hasEvents]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One week as a column of days down the side of the page, beside the agenda,
/// for an island wider than it is tall: the agenda then has the island's full
/// height rather than what a row above it leaves. The month, the arrows and
/// Today are in the island's top row; a second tap on the selected day returns
/// to the coming week, as the strip across the top does.
struct NotchCalendarDayRail: View {
    let focus: Date
    let selectedDay: Date?
    let now: Date
    let height: CGFloat
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    let week: () -> Void
    @Environment(\.locale) private var locale
    private let accent = Color(red: 1, green: 0.36, blue: 0.39)

    private var cellHeight: CGFloat { NotchLayout.calendarDayRailCellHeight(height: height) }
    private var circle: CGFloat { NotchLayout.calendarDayRailCircle(cellHeight: cellHeight) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(NotchCalendarSupport.weekDays(containing: focus), id: \.self) { date in
                dayButton(date)
            }
        }
        .frame(width: NotchLayout.calendarDayRailWidth, alignment: .top)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(focus, format: .dateTime.month(.wide).year()))
    }

    private var weekdaySymbols: [String] {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar.veryShortStandaloneWeekdaySymbols
    }

    private func dayButton(_ date: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let selected = selectedDay.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let dayEvents = NotchCalendarSupport.events(events, on: date)
        let colors = dayEvents.reduce(into: [NotchCalendarColor]()) { result, event in
            if result.count < 3 && !result.contains(event.color) { result.append(event.color) }
        }
        // A second tap on the selected day returns to the coming week.
        return Button { selected ? week() : select(date) } label: {
            HStack(spacing: NotchLayout.calendarDayRailCellSpacing) {
                Text(weekdaySymbols[calendar.component(.weekday, from: date) - 1])
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: NotchLayout.calendarDayRailLetterWidth, alignment: .trailing)
                    .accessibilityHidden(true)
                // The number alone, as the month grid draws it: a formatted day
                // carries the language's suffix, which the circle cuts off.
                Text(calendar.component(.day, from: date), format: .number)
                    .font(.system(size: min(12, circle * 0.55), weight: isToday || selected ? .bold : .medium))
                    .foregroundStyle(selected && !isToday ? .black : .white)
                    .frame(width: circle, height: circle)
                    .background(isToday ? accent : selected ? .white : .clear, in: Circle())
                    .overlay {
                        Circle().strokeBorder(.white.opacity(selected && isToday ? 0.8 : 0), lineWidth: 1.5)
                    }
                // The dots stand in a column: a day of the rail has height to
                // spare and the width of one dot is all it can give them.
                VStack(spacing: 1) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color.color)
                            .frame(width: NotchLayout.calendarDayRailDotWidth,
                                   height: NotchLayout.calendarDayRailDotWidth)
                    }
                }
                .frame(width: NotchLayout.calendarDayRailDotWidth)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 8, lifts: false))
        .help(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)))
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue([isToday ? text.today : "", dayEvents.isEmpty ? "" : text.hasEvents]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The month in an island too short for the grid beside the agenda: the
/// weekday line, then rows sized to what is left, under the island's top row
/// with the title, the arrows and Today. Choosing a day returns to the week
/// on that day.
struct NotchCalendarMonthGrid: View {
    let month: Date
    let selectedDay: Date?
    let now: Date
    let height: CGFloat
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    @Environment(\.locale) private var locale
    @AppStorage(DefaultsKey.notchCalendarWeekNumbers) private var weekNumbers = false
    private let accent = Color(red: 1, green: 0.36, blue: 0.39)
    private var columns: [GridItem] { NotchCalendarWeekNumber.columns(numbered: weekNumbers) }

    private var rowHeight: CGFloat { NotchLayout.calendarMonthRowHeight(height: height) }
    private var circle: CGFloat { min(24, rowHeight - 3) }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            if weekNumbers {
                Color.clear.frame(height: NotchLayout.calendarMonthWeekdayHeight).accessibilityHidden(true)
            }
            ForEach(0..<7, id: \.self) { column in
                let index = (Calendar.current.firstWeekday - 1 + column) % 7
                Text(weekdaySymbols[index])
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity).frame(height: NotchLayout.calendarMonthWeekdayHeight)
                    .accessibilityHidden(true)
            }
            ForEach(NotchCalendarSupport.monthDays(containing: month), id: \.self) { date in
                if weekNumbers, NotchCalendarSupport.startsWeek(date) {
                    NotchCalendarWeekNumber(date: date, text: text, digit: circle, spacing: 0, height: rowHeight)
                }
                dayButton(date)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var weekdaySymbols: [String] {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar.veryShortStandaloneWeekdaySymbols
    }

    private func dayButton(_ date: Date) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let selected = selectedDay.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let dayEvents = NotchCalendarSupport.events(events, on: date)
        let colors = dayEvents.reduce(into: [NotchCalendarColor]()) { result, event in
            if result.count < 3 && !result.contains(event.color) { result.append(event.color) }
        }
        return Button { select(date) } label: {
            VStack(spacing: 0) {
                Text(calendar.component(.day, from: date), format: .number)
                    .font(.system(size: min(11, circle * 0.62), weight: isToday || selected ? .bold : .medium))
                    .foregroundStyle(selected && !isToday ? .black : .white.opacity(isToday || inMonth ? 1 : 0.4))
                    .frame(width: circle, height: circle)
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
            .frame(maxWidth: .infinity).frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 6, lifts: false))
        .help(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale)))
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue([isToday ? text.today : "", dayEvents.isEmpty ? "" : text.hasEvents]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The number of the week a row of the month grid holds, in a narrow column
/// ahead of its days. It is laid out like a day, above the room a day keeps
/// for its event dots, so both sit on one line. No day's label names its
/// week, so VoiceOver reads the number as a week ahead of the row's days.
struct NotchCalendarWeekNumber: View {
    static let width: CGFloat = 18
    let date: Date
    let text: NotchCalendarStrings
    let digit: CGFloat
    let spacing: CGFloat
    let height: CGFloat

    static func columns(numbered: Bool) -> [GridItem] {
        (numbered ? [GridItem(.fixed(width), spacing: 0)] : [])
            + Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    }

    var body: some View {
        VStack(spacing: spacing) {
            Text(NotchCalendarSupport.weekNumber(of: date), format: .number)
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
                .frame(height: digit)
                .accessibilityLabel(NotchCalendarSupport.weekNumberLabel(of: date, text: text))
            Color.clear.frame(height: 3)
        }
        .frame(width: Self.width, height: height)
    }
}
