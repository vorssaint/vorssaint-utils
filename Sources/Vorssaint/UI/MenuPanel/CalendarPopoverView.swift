// SPDX-License-Identifier: GPL-3.0-or-later

import EventKit
import SwiftUI

struct CalendarPopoverView: View {
    @ObservedObject private var service = CalendarService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.calendarShowWeekNumbers) private var showWeekNumbers = false
    @AppStorage(DefaultsKey.calendarShowWeekends) private var showWeekends = true
    @AppStorage(DefaultsKey.calendarShowLunarDate) private var showLunarDate = false
    @AppStorage(DefaultsKey.calendarShowMonthOutline) private var showMonthOutline = true
    @AppStorage(DefaultsKey.calendarShowAdjacentMonthDays) private var showAdjacentMonthDays = false
    @AppStorage(DefaultsKey.calendarShowDeclinedEvents) private var showDeclinedEvents = false
    @AppStorage(DefaultsKey.calendarEventDots) private var eventDots = CalendarEventDots.multiple.rawValue
    @AppStorage(DefaultsKey.calendarShowPastEvents) private var showPastEvents = true
    @AppStorage(DefaultsKey.calendarPreserveSelectedDate) private var preserveSelectedDate = true
    @AppStorage(DefaultsKey.calendarLastSelectedDate) private var lastSelectedDate = 0.0
    @State private var month = Date()
    @State private var day = Date()
    @State private var selectedEvent: EKEvent?
    @State private var showingQuickAdd = false

    private var strings: CalendarStrings { CalendarStrings.current(l10n.language) }

    var body: some View {
        let selectedDayEvents = CalendarSupport.visibleEvents(
            CalendarSupport.dayEvents(for: day, in: service.events, showDeclinedEvents: showDeclinedEvents),
            showPastEvents: showPastEvents,
            showDeclinedEvents: showDeclinedEvents
        )
        VStack(spacing: 10) {
            if service.authorizationStatus != .fullAccess { permissionState }
            else {
                HStack {
                    Text("\(strings.agenda): \(selectedDayEvents.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { showingQuickAdd = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help(strings.newEvent)
                    Button { NSWorkspace.shared.open(URL(string: "ical://")!) } label: { Image(systemName: "calendar") }.buttonStyle(.plain).help(strings.openInCalendar)
                }
                CalendarMonthView(month: $month, selectedDay: $day, events: service.events,
                                  showWeekNumbers: showWeekNumbers, showWeekends: showWeekends, showLunarDate: showLunarDate,
                                  showMonthOutline: showMonthOutline, showAdjacentMonthDays: showAdjacentMonthDays,
                                  eventDots: CalendarEventDots(rawValue: eventDots) ?? .multiple,
                                  showDeclinedEvents: showDeclinedEvents)
                Divider()
                CalendarEventListView(events: selectedDayEvents, selectedEvent: $selectedEvent, showPastEvents: showPastEvents, showDeclinedEvents: showDeclinedEvents, strings: strings)
                if let selectedEvent {
                    CalendarEventDetailView(event: selectedEvent, strings: strings)
                }
            }
        }
        .frame(width: 330)
        .padding(12)
        .sheet(isPresented: $showingQuickAdd) { CalendarQuickAddView(initialDate: day, strings: strings) }
        .onAppear { restoreSelectedDate() }
        .onReceive(NotificationCenter.default.publisher(for: .calendarPopoverWillShow)) { _ in restoreSelectedDate() }
        .onChange(of: day) { _, value in
            if preserveSelectedDate { lastSelectedDate = value.timeIntervalSinceReferenceDate }
            service.refresh(date: value)
            selectedEvent = nil
        }
        .onChange(of: month) { _, value in service.refresh(date: value) }
    }

    private var permissionState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark").font(.title2)
            Text(strings.accessRequired).multilineTextAlignment(.center)
            Button(strings.openPreferences) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }
        }.padding(24)
    }

    private func restoreSelectedDate() {
        let restored = Date(timeIntervalSinceReferenceDate: lastSelectedDate)
        day = preserveSelectedDate && lastSelectedDate > 0 ? restored : Date()
        month = day
        service.refresh(date: day)
    }
}

private struct CalendarMonthView: View {
    @Binding var month: Date
    @Binding var selectedDay: Date
    let events: [EKEvent]
    let showWeekNumbers: Bool
    let showWeekends: Bool
    let showLunarDate: Bool
    let showMonthOutline: Bool
    let showAdjacentMonthDays: Bool
    let eventDots: CalendarEventDots
    let showDeclinedEvents: Bool
    private let calendar = Calendar.autoupdatingCurrent
    private let formatter: DateFormatter = { let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMM yyyy"); return f }()

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Button { month = calendar.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Spacer(); Text(formatter.string(from: month)).font(.headline); Spacer()
                Button { month = Date() } label: { Image(systemName: "circle") }.buttonStyle(.plain)
                Button { month = calendar.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
            }
            VStack(spacing: 6) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 22), spacing: 1), count: weekdaySymbols.count + (showWeekNumbers ? 1 : 0)), spacing: 4) {
                    if showWeekNumbers { Text("#").font(.caption2).foregroundStyle(.tertiary) }
                    ForEach(weekdaySymbols, id: \.self) { Text(String($0.prefix(1))).font(.caption2).foregroundStyle(.secondary) }
                    ForEach(Array(CalendarSupport.calendarDays(for: month, showAdjacentMonthDays: showAdjacentMonthDays, calendar: calendar).enumerated()), id: \.offset) { _, week in
                        if showWeekNumbers { Text("\(weekNumber(week))").font(.caption2).foregroundStyle(.tertiary) }
                        ForEach(Array(visibleDays(in: week).enumerated()), id: \.offset) { _, date in
                            if let date { dayCell(date) } else { Color.clear.frame(height: 31) }
                        }
                    }
                }
            }
            if showLunarDate { Text(lunarString).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(showMonthOutline ? 0.35 : 0.20))
        }
        .overlay {
            if showMonthOutline {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let ordered = Array(symbols[first...]) + Array(symbols[..<first])
        return showWeekends ? ordered : ordered.enumerated().compactMap { index, symbol in isWeekendColumn(index) ? nil : symbol }
    }

    private func visibleDays(in week: [Date?]) -> [Date?] {
        showWeekends ? week : week.enumerated().filter { !isWeekendColumn($0.offset) }.map(\.element)
    }

    private func isInDisplayedMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: month, toGranularity: .month)
    }

    private func isWeekendColumn(_ index: Int) -> Bool {
        let weekday = ((calendar.firstWeekday - 1 + index) % 7) + 1
        return weekday == 1 || weekday == 7
    }

    @ViewBuilder private func dayCell(_ date: Date) -> some View {
        Button {
            selectedDay = date
            month = date
        } label: {
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: calendar.isDateInToday(date) ? .bold : .regular))
                    .foregroundStyle(isInDisplayedMonth(date) ? Color.primary : Color.secondary.opacity(0.72))
                    .frame(width: 25, height: 25)
                    .background(calendar.isDate(date, inSameDayAs: selectedDay) ? Color.accentColor.opacity(0.35) : (calendar.isDateInToday(date) ? Color.secondary.opacity(0.18) : Color.clear), in: Circle())
                eventMarker(for: date)
            }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func eventMarker(for date: Date) -> some View {
        let dayEvents = CalendarSupport.dayEvents(for: date, in: events, showDeclinedEvents: showDeclinedEvents, calendar: calendar)
        switch eventDots {
        case .none:
            EmptyView()
        case .singleNeutral:
            Circle().fill(dayEvents.isEmpty ? Color.clear : Color.secondary.opacity(0.65)).frame(width: 3, height: 3)
        case .singleHighlighted:
            Circle().fill(dayEvents.isEmpty ? Color.clear : Color.accentColor).frame(width: 3, height: 3)
        case .multiple:
            let colors = Array(dayEvents.map { Color(nsColor: $0.calendar.color ?? .controlAccentColor) }.prefix(3))
            HStack(spacing: 1) {
                ForEach(colors.indices, id: \.self) { index in
                    Circle().fill(colors[index]).frame(width: 3, height: 3)
                }
            }
            .frame(height: 3)
        }
    }

    private func weekNumber(_ week: [Date?]) -> Int { week.compactMap { $0 }.first.map { calendar.component(.weekOfYear, from: $0) } ?? 0 }
    private var lunarString: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .chinese)
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateStyle = .medium
        return formatter.string(from: selectedDay)
    }
}

private struct CalendarEventListView: View {
    let events: [EKEvent]
    @Binding var selectedEvent: EKEvent?
    let showPastEvents: Bool
    let showDeclinedEvents: Bool
    let strings: CalendarStrings
    var visibleEvents: [EKEvent] {
        CalendarSupport.visibleEvents(events, showPastEvents: showPastEvents, showDeclinedEvents: showDeclinedEvents)
    }

    var body: some View {
        let listHeight = CalendarSupport.eventListHeight(for: visibleEvents.count)
        ScrollView { LazyVStack(alignment: .leading, spacing: 4) {
            if visibleEvents.isEmpty { Text(strings.noEvents).frame(maxWidth: .infinity).foregroundStyle(.secondary).padding(.vertical, 18) }
            ForEach(visibleEvents, id: \.eventIdentifier) { event in Button { selectedEvent = event } label: {
                HStack(spacing: 8) {
                    Rectangle().fill(Color(nsColor: event.calendar.color ?? .controlAccentColor)).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title ?? "").lineLimit(1)
                        Text(event.isAllDay ? strings.allDay : "\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))  ·  \(strings.duration(from: event.endDate.timeIntervalSince(event.startDate)))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if event.hasRecurrenceRules { Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary) }
                    if MeetingLinkDetector.detect(event: event) != nil { Image(systemName: "video").font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 3)
            }.buttonStyle(.plain).opacity(event.endDate < Date() ? 0.5 : 1) }
        } }.frame(height: listHeight, alignment: .top)
    }
}

private struct CalendarEventDetailView: View {
    let event: EKEvent
    let strings: CalendarStrings
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text("\(event.calendar.title) · \(strings.duration(from: event.endDate.timeIntervalSince(event.startDate)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if MeetingLinkDetector.detect(event: event) != nil {
                    Image(systemName: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(event.isAllDay ? strings.allDay : "\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Label {
                        Text(location)
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }
            }

            if let notes = event.notes, !notes.isEmpty {
                ScrollView {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 54)
            }

            HStack(spacing: 8) {
                if let link = MeetingLinkDetector.detect(event: event) {
                    Button(strings.join) { MeetingLinkDetector.open(kind: link) }
                        .buttonStyle(.borderedProminent)
                }
                Button(strings.openInCalendar) {
                    NSWorkspace.shared.open(URL(string: "ical://")!)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }
}

private struct CalendarQuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = CalendarService.shared
    @State private var text = ""
    @State private var draft: CalendarQuickEventDraft
    @State private var error: String?
    let strings: CalendarStrings

    init(initialDate: Date, strings: CalendarStrings) {
        self.strings = strings
        _draft = State(initialValue: CalendarQuickEventDraft(title: "", startDate: initialDate, endDate: initialDate.addingTimeInterval(3600), isAllDay: false, calendarName: nil))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strings.newEvent)
                .font(.headline)
            TextField(strings.quickAddPlaceholder, text: $text)
                .onChange(of: text) { _, value in
                    draft = CalendarQuickEventParser.parse(value, now: draft.startDate)
                }
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 8) {
                DatePicker(strings.start, selection: $draft.startDate, displayedComponents: [.date, .hourAndMinute])
                DatePicker(strings.end, selection: $draft.endDate, displayedComponents: [.date, .hourAndMinute])
                Toggle(strings.allDay, isOn: $draft.isAllDay)
            }
            if let name = draft.calendarName {
                Text("\(strings.calendarLabel): \(name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(strings.cancel) { dismiss() }
                Button(strings.save) { save() }
                    .disabled(draft.title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { PanelInteractionState.shared.isPresentingPopoverModal = true }
        .onDisappear { PanelInteractionState.shared.isPresentingPopoverModal = false }
    }

    private func save() { do { _ = try service.createEvent(from: draft); dismiss() } catch { self.error = error.localizedDescription } }
}
