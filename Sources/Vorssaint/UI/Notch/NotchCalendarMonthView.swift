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
