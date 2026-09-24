// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchCalendarMonthView: View {
    let month: Date
    let selectedDay: Date?
    let now: Date
    let events: [NotchCalendarEvent]
    let text: NotchCalendarStrings
    let select: (Date) -> Void
    let move: (Int) -> Void
    let today: () -> Void
    let open: () -> Void
    @Environment(\.locale) private var locale
    private let accent = Color(red: 1, green: 0.36, blue: 0.39)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(month, format: .dateTime.month(.wide))
                        .font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(month, format: .dateTime.year())
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NotchIconButton(symbol: "chevron.backward", title: text.previousMonth) { move(-1) }
                NotchIconButton(symbol: "chevron.forward", title: text.nextMonth) { move(1) }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<7, id: \.self) { column in
                    let index = (Calendar.current.firstWeekday - 1 + column) % 7
                    Text(weekdaySymbols[index])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity).frame(height: 18)
                        .accessibilityHidden(true)
                }
                ForEach(NotchCalendarSupport.monthDays(containing: month), id: \.self) { date in
                    dayButton(date)
                }
            }
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
                Text(date, format: .dateTime.day())
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
    @Environment(\.locale) private var locale
    private let accent = Color(red: 1, green: 0.36, blue: 0.39)

    var body: some View {
        HStack(spacing: 4) {
            NotchIconButton(symbol: "chevron.backward", title: text.previousWeek) { move(-1) }
            ForEach(NotchCalendarSupport.weekDays(containing: focus), id: \.self) { date in
                dayButton(date)
            }
            NotchIconButton(symbol: "chevron.forward", title: text.nextWeek) { move(1) }
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
                Text(date, format: .dateTime.day())
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
    @Environment(\.locale) private var locale
    private let accent = Color(red: 1, green: 0.36, blue: 0.39)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var rowHeight: CGFloat { NotchLayout.calendarMonthRowHeight(height: height) }
    private var circle: CGFloat { min(24, rowHeight - 3) }

    var body: some View {
        VStack(spacing: NotchLayout.calendarMonthSpacing) {
            HStack(spacing: 4) {
                NotchIconButton(symbol: "chevron.backward", title: text.previousMonth) { move(-1) }
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NotchIconButton(symbol: "chevron.forward", title: text.nextMonth) { move(1) }
                NotchIconButton(symbol: "circle.circle", title: text.today, action: today)
                NotchIconButton(symbol: "arrow.up.forward.app", title: text.openCalendar, action: open)
                NotchIconButton(symbol: "calendar", title: text.month, selected: true, action: week)
            }
            .frame(height: NotchLayout.calendarMonthHeaderHeight)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(0..<7, id: \.self) { column in
                    let index = (Calendar.current.firstWeekday - 1 + column) % 7
                    Text(weekdaySymbols[index])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity).frame(height: NotchLayout.calendarMonthWeekdayHeight)
                        .accessibilityHidden(true)
                }
                ForEach(NotchCalendarSupport.monthDays(containing: month), id: \.self) { date in
                    dayButton(date)
                }
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
                Text(date, format: .dateTime.day())
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
