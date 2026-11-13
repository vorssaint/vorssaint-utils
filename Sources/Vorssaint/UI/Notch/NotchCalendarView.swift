// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import EventKit

struct NotchCalendarView: View {
    let size: CGSize
    @Environment(\.notchSettingsPreview) private var preview
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.notchCalendarCountdown) private var countdownForEvery = false
    @AppStorage(DefaultsKey.notchCalendarWeekLayout) private var weekLayout = NotchCalendarWeekLayout.horizontal.rawValue
    @Environment(\.notchBand) private var band
    /// The day the month grid or the week strip is built around.
    @State private var focus = Date()
    @State private var selectedDay: Date?
    /// The strip's month grid, in place of the strip and the cards.
    @State private var showingMonth = false
    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    /// A month grid needs six rows beside an agenda; anything shorter shows
    /// the week alone, across the top of the agenda or down its side.
    private var showsMonth: Bool { size.height >= 300 && size.width >= 420 }
    /// Whether the week runs down the side of the agenda instead of across
    /// the top. A page too short for seven days keeps the strip, which costs
    /// one row; the month beside the agenda already reads down the side.
    private var railsWeek: Bool {
        NotchCalendarWeekLayout(stored: weekLayout) == .vertical
            && size.height >= NotchLayout.calendarDayRailMinimumHeight
    }

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
                                    agenda(now: context.date)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        } else if showingMonth {
                            monthGrid(now: context.date)
                        } else if railsWeek {
                            HStack(alignment: .top, spacing: NotchLayout.calendarDayRailSpacing) {
                                dayRail(now: context.date)
                                Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                                    .accessibilityHidden(true)
                                agenda(now: context.date)
                            }
                        } else {
                            VStack(spacing: NotchLayout.rowSpacing) {
                                weekStrip(now: context.date)
                                agenda(now: context.date)
                            }
                        }
                    }
                    .onChange(of: Calendar.current.startOfDay(for: context.date)) { _, _ in
                        if selectedDay == nil { focus = context.date }
                    }
                }
                // The month's name and the way through it head the page from
                // the island's top row, the same in all three layouts.
                .notchBand { monthTitle } trailing: { navigation }
            } else {
                permissionCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Day and month names follow the app's language; the order of the
        // date and the 12/24-hour clock follow the user's region.
        .environment(\.locale, l10n.language.formattingLocale())
        .onAppear { if ownsMonth { calendar.showMonth(focus) } }
        .onChange(of: focus) { previous, date in
            // A month read already covers every week of that month, so
            // moving the strip within it keeps the loaded events.
            if !Calendar.current.isDate(previous, equalTo: date, toGranularity: .month) { calendar.showMonth(date) }
        }
        // Escape returns from the month grid to the strip before the island closes.
        .onChange(of: showingMonth && !showsMonth) { _, showing in
            guard !preview else { return }
            NotchService.shared.setPageLayer(.calendar, close: showing ? { showingMonth = false } : nil)
        }
        .onDisappear {
            if ownsMonth { calendar.showMonth(nil) }
            if !preview { NotchService.shared.setPageLayer(.calendar, close: nil); calendar.revealing = nil }
        }
    }

    /// The month the service reads belongs to the island's own page; a preview
    /// in Settings borrows it only while the island shows another page.
    private var ownsMonth: Bool {
        !preview || !(NotchService.shared.expanded && NotchService.shared.selected == .calendar)
    }

    private func monthView(now: Date) -> some View {
        NotchCalendarMonthView(month: focus, selectedDay: selectedDay, now: now,
                               events: calendar.events, text: text, select: select)
    }

    private func weekStrip(now: Date) -> some View {
        NotchCalendarWeekStrip(focus: focus, selectedDay: selectedDay, now: now,
                               events: calendar.events, text: text, select: select) {
            selectedDay = nil
            focus = now
        }
    }

    private func dayRail(now: Date) -> some View {
        NotchCalendarDayRail(focus: focus, selectedDay: selectedDay, now: now, height: size.height,
                             events: calendar.events, text: text, select: select) {
            selectedDay = nil
            focus = now
        }
    }

    /// Picking a day lands back on the strip with that day.
    private func monthGrid(now: Date) -> some View {
        NotchCalendarMonthGrid(month: focus, selectedDay: selectedDay, now: now, height: size.height,
                               events: calendar.events, text: text) { date in
            select(date)
            showingMonth = false
        }
    }

    /// The month the page shows, named in the language's own words: in full
    /// where the row has room, abbreviated where the camera leaves less. Over
    /// the week strip it opens the month grid, and over that grid it closes it.
    private var monthTitle: some View {
        let title = ViewThatFits(in: .horizontal) {
            Text(focus, format: .dateTime.month(.wide).year())
            Text(focus, format: .dateTime.month(.abbreviated).year())
        }
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
        // The row is drawn by the island, outside this page's own locale.
        .environment(\.locale, l10n.language.formattingLocale())
        return Group {
            if showsMonth {
                title.accessibilityAddTraits(.isHeader)
            } else {
                Button { showingMonth.toggle() } label: {
                    title
                        .padding(.horizontal, 7)
                        .frame(height: 28)
                        .background(.white.opacity(showingMonth ? 0.12 : 0),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 9))
                .help(text.month)
                .accessibilityHint(text.month)
                .accessibilityAddTraits(showingMonth ? .isSelected : [])
            }
        }
    }

    /// Calendar itself follows the arrows where the row has room for four
    /// buttons, the last one apart; the island's own update or pin give way
    /// to it. Elsewhere an empty agenda offers it, and every appointment card
    /// opens it as well.
    private var rowOpensCalendar: Bool { !band.besideCamera || band.side >= 28 * 4 + 6 }

    /// The arrows step by week over the strip and by month over a grid,
    /// around the way back to today, as Calendar's own toolbar does.
    private var navigation: some View {
        let byWeek = !showsMonth && !showingMonth
        return HStack(spacing: 6) {
            HStack(spacing: 0) {
                NotchIconButton(symbol: "chevron.left", title: byWeek ? text.previousWeek : text.previousMonth) {
                    byWeek ? moveWeek(-1) : moveMonth(-1)
                }
                NotchIconButton(symbol: "circle.circle", title: text.today) {
                    today(now: Date())
                    showingMonth = false
                }
                NotchIconButton(symbol: "chevron.right", title: byWeek ? text.nextWeek : text.nextMonth) {
                    byWeek ? moveWeek(1) : moveMonth(1)
                }
            }
            if rowOpensCalendar {
                NotchIconButton(symbol: "arrow.up.forward.app", title: text.openCalendar) { openCalendar() }
            }
        }
    }

    private func moveWeek(_ offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset * 7, to: focus) else { return }
        selectedDay = Calendar.current.startOfDay(for: date)
        focus = date
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

    /// Scrolls once to the countdown's event opened from the closed island,
    /// after the reload that opening the page starts has finished.
    private func agenda(now: Date) -> some View {
        ScrollViewReader { proxy in
            ScrollView { appointmentList(now: now) }
                .scrollIndicators(.automatic)
                .id(selectedDay)
                .onChange(of: calendar.loading ? nil : calendar.revealing, initial: true) { _, target in
                    guard !preview, let target else { return }
                    DispatchQueue.main.async {
                        guard !calendar.loading, calendar.revealing == target else { return }
                        calendar.revealing = nil
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
        }
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
                                                  isNext: event.id == next?.id, text: text,
                                                  countdown: countdownChoice(event, now: now),
                                                  choose: { calendar.setCountdown($0, for: event) }) {
                                openCalendar(showing: event)
                            }
                            .id(event.id)
                        }
                    }
                }
            }
            .padding(.bottom, 2)
        }
    }

    /// Whether a timed event yet to start counts down on its own, or nil when
    /// its menu has nothing to offer: the countdown for every event covers it.
    private func countdownChoice(_ event: NotchCalendarEvent, now: Date) -> Bool? {
        guard !countdownForEvery, !event.allDay, event.start > now, !event.countdownKey.isEmpty else { return nil }
        return calendar.isChosen(event)
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
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedDay == nil ? text.empty : text.emptyDay)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                // With no card to open it from and no room for it in the row.
                if !rowOpensCalendar {
                    NotchPillButton(title: text.openCalendar) { openCalendar() }
                }
            }
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
    /// Whether the event counts down on its own; nil when it cannot.
    let countdown: Bool?
    let choose: (Bool) -> Void
    let open: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    private var ongoing: Bool { !event.allDay && event.start <= now && event.end > now }
    private var ended: Bool { event.end <= now }

    var body: some View {
        Button(action: open) { card }
            .buttonStyle(NotchButtonStyle(cornerRadius: 11, lifts: false))
            .help(text.openCalendar)
            .accessibilityHint(text.openCalendar)
            .modifier(NotchCountdownChoice(chosen: countdown, text: text, choose: choose))
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
            HStack(alignment: .firstTextBaseline, spacing: 5) {
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
                .fixedSize(horizontal: false, vertical: true)
                // The mark of an event chosen to count down on its own.
                if countdown == true {
                    Image(systemName: "timer")
                        .accessibilityLabel(text.countdown)
                }
            }
            .font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
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

/// A timed event yet to start offers its own countdown from its menu, and
/// to VoiceOver as an action, while the countdown for every event is off.
private struct NotchCountdownChoice: ViewModifier {
    let chosen: Bool?
    let text: NotchCalendarStrings
    let choose: (Bool) -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if let chosen {
            let title = chosen ? text.removeCountdown : text.addCountdown
            content
                .contextMenu { Button(title) { choose(!chosen) } }
                .accessibilityAction(named: Text(title)) { choose(!chosen) }
        } else {
            content
        }
    }
}

extension NotchCalendarColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}
