// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import EventKit

struct NotchCalendarView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var month = Date()
    @State private var selectedDay: Date?
    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }

    var body: some View {
        Group {
            if permissions.calendarAccess == .fullAccess {
                TimelineView(.everyMinute) { context in
                    GeometryReader { geometry in
                        if geometry.size.width >= 420 {
                            HStack(alignment: .top, spacing: 16) {
                                ScrollView { monthView(now: context.date) }
                                    .scrollIndicators(.automatic)
                                    .frame(width: 196)
                                Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 12) {
                                    agendaHeader
                                    ScrollView { appointments(now: context.date) }
                                        .scrollIndicators(.automatic)
                                        .id(selectedDay)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 18) {
                                    monthView(now: context.date)
                                    Divider().overlay(.white.opacity(0.12))
                                    agendaHeader
                                    appointments(now: context.date)
                                }
                            }.scrollIndicators(.automatic)
                        }
                    }
                    .onChange(of: Calendar.current.startOfDay(for: context.date)) { _, _ in
                        if selectedDay == nil { month = context.date }
                    }
                }
            } else {
                permissionCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.locale, Locale(identifier: l10n.language.rawValue))
        .onAppear { calendar.showMonth(month) }
        .onChange(of: month) { _, date in calendar.showMonth(date) }
        .onDisappear { calendar.showMonth(nil) }
    }

    private func monthView(now: Date) -> some View {
        NotchCalendarMonthView(month: month, selectedDay: selectedDay, now: now,
                               events: calendar.events, text: text) { date in
            selectedDay = date
            if !Calendar.current.isDate(date, equalTo: month, toGranularity: .month) { month = date }
        } move: { offset in
            guard let start = Calendar.current.dateInterval(of: .month, for: month)?.start,
                  let date = Calendar.current.date(byAdding: .month, value: offset, to: start) else { return }
            selectedDay = date
            month = date
        } today: {
            selectedDay = Calendar.current.startOfDay(for: now)
            if !Calendar.current.isDate(month, equalTo: now, toGranularity: .month) { month = now }
        } open: {
            openCalendar()
        }
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
                    let now = Date()
                    if !Calendar.current.isDate(month, equalTo: now, toGranularity: .month) { month = now }
                }
            }
        }
        .frame(minHeight: 32)
    }

    @ViewBuilder private func appointments(now: Date) -> some View {
        let days = selectedDay.map { [$0] } ?? (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: now))
        }
        let events = selectedDay == nil ? NotchCalendarSupport.upcoming(calendar.events, now: now) : calendar.events
        let groups = days.map { (day: $0, events: NotchCalendarSupport.events(events, on: $0)) }
            .filter { !$0.events.isEmpty }
        let next = NotchCalendarSupport.next(calendar.events, now: now)
        if calendar.loading {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 150)
        } else if groups.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.45))
                    .accessibilityHidden(true)
                Text(selectedDay == nil ? text.empty : text.emptyDay)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 150)
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 7) {
                        if selectedDay == nil {
                            HStack(spacing: 5) {
                                if Calendar.current.isDate(group.day, inSameDayAs: now) {
                                    Text(text.today).foregroundStyle(.white)
                                } else {
                                    Text(group.day, format: .dateTime.weekday(.abbreviated))
                                }
                                Text(group.day, format: .dateTime.day().month(.abbreviated))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        }
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

    private var permissionCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 32))
            Text(text.title).font(.headline)
            Text(permissions.calendarAccess == .denied || permissions.calendarAccess == .restricted
                 ? text.denied : text.permission)
                .font(.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
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
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.color.color)
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                if ongoing || isNext {
                    Text(ongoing ? text.ongoing : text.next)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ongoing ? .mint : .white.opacity(0.7))
                        .lineLimit(2)
                }
                Text(event.title.isEmpty ? text.untitled : event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(ended ? 0.65 : 1))
                    .lineLimit(2)
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
        }
        .padding(10)
        .background(event.color.color.opacity(ongoing ? 0.2 : 0.1),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(.white.opacity(contrast == .increased ? 0.5 : ongoing ? 0.16 : 0.05), lineWidth: 0.75)
        }
    }
}

extension NotchCalendarColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}
