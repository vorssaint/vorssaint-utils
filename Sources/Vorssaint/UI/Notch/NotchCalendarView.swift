// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import EventKit

struct NotchCalendarView: View {
    let size: CGSize
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var permissions = Permissions.shared
    /// The day the month grid or the week strip is built around.
    @State private var focus = Date()
    @State private var selectedDay: Date?
    /// The strip's month grid, in place of the strip and the cards.
    @State private var showingMonth = false
    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    /// A month grid needs six rows beside an agenda; anything shorter shows
    /// the week as a strip above a vertical agenda.
    private var showsMonth: Bool { size.height >= 300 && size.width >= 420 }

    var body: some View {
        Group {
            if permissions.calendarAccess == .fullAccess {
                TimelineView(.everyMinute) { context in
                    Group {
                        if showsMonth {
                            HStack(alignment: .top, spacing: 16) {
                                ScrollView { monthView(now: context.date) }
                                    .scrollIndicators(.automatic)
                                    .frame(width: 196)
                                Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 12) {
                                    agendaHeader
                                    ScrollView { appointmentList(now: context.date) }
                                        .scrollIndicators(.automatic)
                                        .id(selectedDay)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        } else if showingMonth {
                            monthGrid(now: context.date)
                        } else {
                            VStack(spacing: NotchLayout.rowSpacing) {
                                weekStrip(now: context.date)
                                ScrollView {
                                    appointmentList(now: context.date)
                                }
                                .scrollIndicators(.automatic)
                                .id(selectedDay)
                            }
                        }
                    }
                    .onChange(of: Calendar.current.startOfDay(for: context.date)) { _, _ in
                        if selectedDay == nil { focus = context.date }
                    }
                }
            } else {
                permissionCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.locale, Locale(identifier: l10n.language.rawValue))
        .onAppear { calendar.showMonth(focus) }
        .onChange(of: focus) { previous, date in
            // A month read already covers every week of that month, so
            // moving the strip within it keeps the loaded events.
            if !Calendar.current.isDate(previous, equalTo: date, toGranularity: .month) { calendar.showMonth(date) }
        }
        .onDisappear { calendar.showMonth(nil) }
    }

    private func monthView(now: Date) -> some View {
        NotchCalendarMonthView(month: focus, selectedDay: selectedDay, now: now,
                               events: calendar.events, text: text, select: select, move: moveMonth) {
            today(now: now)
        } open: {
            openCalendar()
        }
    }

    private func weekStrip(now: Date) -> some View {
        NotchCalendarWeekStrip(width: size.width, focus: focus, selectedDay: selectedDay, now: now,
                               events: calendar.events, text: text, select: select) { offset in
            guard let date = Calendar.current.date(byAdding: .day, value: offset * 7, to: focus) else { return }
            selectedDay = Calendar.current.startOfDay(for: date)
            focus = date
        } today: {
            today(now: now)
        } week: {
            selectedDay = nil
            focus = now
        } month: {
            showingMonth = true
        } open: {
            openCalendar()
        }
    }

    /// Picking a day, or Today, lands back on the strip with that day.
    private func monthGrid(now: Date) -> some View {
        NotchCalendarMonthGrid(month: focus, selectedDay: selectedDay, now: now, height: size.height,
                               events: calendar.events, text: text, select: { date in
            select(date)
            showingMonth = false
        }, move: moveMonth, today: {
            today(now: now)
            showingMonth = false
        }, open: { openCalendar() }, week: {
            showingMonth = false
        })
    }

    private func moveMonth(_ offset: Int) {
        guard let start = Calendar.current.dateInterval(of: .month, for: focus)?.start,
              let date = Calendar.current.date(byAdding: .month, value: offset, to: start) else { return }
        selectedDay = date
        focus = date
    }

    private func select(_ date: Date) {
        selectedDay = date
        focus = date
    }

    private func today(now: Date) {
        selectedDay = Calendar.current.startOfDay(for: now)
        focus = now
    }

    private var agendaHeader: some View {
        HStack(spacing: 6) {
            Group {
                if let selectedDay {
                    Text(selectedDay, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                } else {
                    Text(text.week)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            if selectedDay != nil {
                NotchIconButton(symbol: "calendar.badge.clock", title: text.week) {
                    selectedDay = nil
                    focus = Date()
                }
            }
        }
        .frame(minHeight: 32)
    }

    private struct DayGroup {
        let day: Date
        let events: [NotchCalendarEvent]
    }

    private func groups(now: Date) -> [DayGroup] {
        let days = selectedDay.map { [$0] } ?? (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: now))
        }
        let events = selectedDay == nil ? NotchCalendarSupport.upcoming(calendar.events, now: now) : calendar.events
        return days.map { DayGroup(day: $0, events: NotchCalendarSupport.events(events, on: $0)) }
            .filter { !$0.events.isEmpty }
    }

    @ViewBuilder private func appointmentList(now: Date) -> some View {
        let groups = groups(now: now)
        let next = NotchCalendarSupport.next(calendar.events, now: now)
        if calendar.loading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 72)
        } else if groups.isEmpty {
            emptyAgenda.frame(maxWidth: .infinity, minHeight: 72)
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 7) {
                        if selectedDay == nil { dayLabel(group.day, now: now) }
                        ForEach(group.events) { event in
                            NotchCalendarEventRow(event: event, day: group.day, now: now,
                                                  isNext: event.id == next?.id, text: text) {
                                openCalendar(showing: event)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 2)
        }
    }

    private func dayLabel(_ day: Date, now: Date) -> some View {
        NotchCalendarDayLabel(day: day, now: now, text: text)
    }

    private var emptyAgenda: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
            Text(selectedDay == nil ? text.empty : text.emptyDay)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
    }

    private var permissionCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 28))
            Text(permissions.calendarAccess == .denied || permissions.calendarAccess == .restricted
                 ? text.denied : text.permission)
                .font(.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if permissions.calendarAccess == .denied || permissions.calendarAccess == .restricted {
                    Button(text.settings) { permissions.openCalendarSettings() }
                } else {
                    Button(text.allow) {
                        NotchService.shared.open(.calendar)
                        permissions.requestCalendar()
                    }
                    .disabled(permissions.requestingCalendar)
                }
                if permissions.requestingCalendar { ProgressView().controlSize(.small) }
            }
            if permissions.calendarRequestFailed {
                Text(text.requestFailed).font(.caption).foregroundStyle(.orange)
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    /// Calendar itself gets the link: another app claiming the `ical` scheme
    /// would not know EventKit's identifiers.
    private func openCalendar(showing event: NotchCalendarEvent? = nil) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        if let url = event.flatMap({ NotchCalendarSupport.eventURL($0) }) {
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
        } else {
            NSWorkspace.shared.openApplication(at: application, configuration: configuration)
        }
    }
}

private struct NotchCalendarDayLabel: View {
    let day: Date
    let now: Date
    let text: NotchCalendarStrings

    var body: some View {
        HStack(spacing: 5) {
            if Calendar.current.isDate(day, inSameDayAs: now) {
                Text(text.today).foregroundStyle(.white)
            } else {
                Text(day, format: .dateTime.weekday(.abbreviated))
            }
            Text(day, format: .dateTime.day().month(.abbreviated))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.5))
        .lineLimit(1)
    }
}

private struct NotchCalendarEventRow: View {
    let event: NotchCalendarEvent
    let day: Date
    let now: Date
    let isNext: Bool
    let text: NotchCalendarStrings
    let open: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    private var ongoing: Bool { !event.allDay && event.start <= now && event.end > now }
    private var ended: Bool { event.end <= now }

    var body: some View {
        Button(action: open) { card }
            .buttonStyle(NotchButtonStyle(cornerRadius: 11, lifts: false))
            .help(text.openCalendar)
            .accessibilityHint(text.openCalendar)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            if ongoing || isNext {
                Text(ongoing ? text.ongoing : text.next)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ongoing ? .mint : .white.opacity(0.7))
                    .lineLimit(1)
            }
            Text(event.title.isEmpty ? text.untitled : event.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(ended ? 0.65 : 1))
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if event.allDay {
                    Text(text.allDay)
                } else if Calendar.current.isDate(event.start, inSameDayAs: day)
                            && Calendar.current.isDate(event.end.addingTimeInterval(-1), inSameDayAs: day) {
                    Text(event.start, format: .dateTime.hour().minute())
                        + Text(" · ") + Text(event.end, format: .dateTime.hour().minute())
                } else {
                    Text(event.start, format: .dateTime.day().month(.abbreviated).hour().minute())
                        + Text(" → ") + Text(event.end, format: .dateTime.day().month(.abbreviated).hour().minute())
                }
            }
            .font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
            Text(event.calendar)
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(event.color.color)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(event.color.color.opacity(ongoing ? 0.2 : 0.1),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(contrast == .increased ? 0.5 : ongoing ? 0.16 : 0.05), lineWidth: 0.75)
        }
        .clipped()
    }
}

extension NotchCalendarColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}
