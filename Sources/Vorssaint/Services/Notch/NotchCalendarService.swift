// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import EventKit

/// EventKit objects stay on one actor; only immutable display values reach UI.
private actor NotchCalendarReader {
    private lazy var store = EKEventStore()

    func read(interval: DateInterval, excluded: Set<String>) -> [NotchCalendarEvent] {
        guard !Task.isCancelled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendars = NotchCalendarSupport.calendarsToRead(store.calendars(for: .event), excluded: excluded,
                                                             identifier: \.calendarIdentifier)
        if calendars?.isEmpty == true { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate).compactMap { event in
            guard event.status != .canceled,
                  event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) != true,
                  let identifier = event.eventIdentifier,
                  let start = event.startDate, let end = event.endDate else { return nil }
            return NotchCalendarEvent(id: identifier + ":" + String(start.timeIntervalSinceReferenceDate),
                                      title: event.title ?? "", calendar: event.calendar.title,
                                      start: start, end: end, allDay: event.isAllDay,
                                      location: event.location ?? "", color: Self.tint(event.calendar),
                                      calendarItemIdentifier: event.calendarItemIdentifier,
                                      recurring: event.hasRecurrenceRules || event.isDetached)
        }
    }

    func calendars() -> [NotchCalendarChoice] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        return store.calendars(for: .event).map {
            NotchCalendarChoice(id: $0.calendarIdentifier, title: $0.title,
                                sourceID: $0.source?.sourceIdentifier ?? "", source: $0.source?.title ?? "",
                                color: Self.tint($0))
        }
    }

    private static func tint(_ calendar: EKCalendar) -> NotchCalendarColor {
        let color = calendar.cgColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        return color.map { NotchCalendarColor(red: $0.redComponent, green: $0.greenComponent,
                                              blue: $0.blueComponent) } ?? .fallback
    }
}

/// Owned by the notch lifecycle, including sleep and lock. No calendar data is persisted.
final class NotchCalendarService: NSObject, ObservableObject {
    static let shared = NotchCalendarService()
    @Published private(set) var events: [NotchCalendarEvent] = []
    @Published private(set) var countdownEvent: NotchCalendarEvent?
    @Published private(set) var loading = false
    private var reader: NotchCalendarReader?
    private var task: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var permissionSubscription: AnyCancellable?
    private var generation = UUID()
    private var visibleMonth: Date?
    private var countdownEnabled = false
    private var excludedCalendars = Set<String>()

    private override init() { super.init() }

    /// Every event calendar on this Mac, for the Settings list. Works while
    /// the island's reader is stopped, since the list is edited from Settings.
    func calendarChoices() async -> [NotchCalendarChoice] {
        await (reader ?? NotchCalendarReader()).calendars()
    }

    func showMonth(_ month: Date?) {
        visibleMonth = month
        events = []
        refresh()
    }

    func syncWithPreferences() {
        guard NotchCalendarSupport.isEnabled() else { stop(); return }
        let countdownEnabled = NotchCalendarSupport.showsCountdown()
        let excludedCalendars = NotchCalendarSupport.excludedCalendars()
        guard reader == nil else {
            if self.countdownEnabled != countdownEnabled || self.excludedCalendars != excludedCalendars {
                if !excludedCalendars.isSubset(of: self.excludedCalendars) {
                    events = []
                    countdownEvent = nil
                }
                self.countdownEnabled = countdownEnabled
                self.excludedCalendars = excludedCalendars
                if !countdownEnabled { countdownEvent = nil }
                refresh()
            }
            return
        }
        self.countdownEnabled = countdownEnabled
        self.excludedCalendars = excludedCalendars
        reader = NotchCalendarReader()
        for name in [Notification.Name.EKEventStoreChanged, NSApplication.didBecomeActiveNotification,
                     .NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.refresh()
            })
        }
        permissionSubscription = Permissions.shared.$calendarAccess.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        task?.cancel()
        refreshTimer?.invalidate(); refreshTimer = nil
        generation = UUID()
        guard NotchCalendarSupport.isEnabled(), let reader else { stop(); return }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            events = []; countdownEvent = nil; loading = false
            return
        }
        let requested = generation
        let now = Date()
        let interval = NotchCalendarSupport.readInterval(month: visibleMonth, now: now)
        let currentInterval = NotchCalendarSupport.readInterval(month: nil, now: now)
        let needsCurrentRead = NotchCalendarSupport.needsCurrentRead(
            visible: interval, current: currentInterval, countdownEnabled: countdownEnabled)
        let excluded = excludedCalendars
        loading = events.isEmpty
        task = Task { @MainActor [weak self] in
            let result = await reader.read(interval: interval, excluded: excluded)
            let currentResult = needsCurrentRead
                ? await reader.read(interval: currentInterval, excluded: excluded) : result
            guard !Task.isCancelled, let self, self.generation == requested,
                  NotchCalendarSupport.isEnabled() else { return }
            let now = Date()
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                self.events = []; self.countdownEvent = nil; self.loading = false; self.task = nil
                return
            }
            self.events = NotchCalendarSupport.ordered(result)
            let currentEvents = needsCurrentRead ? NotchCalendarSupport.ordered(currentResult) : self.events
            self.countdownEvent = self.countdownEnabled
                ? NotchCalendarSupport.countdownEvent(currentEvents, now: now) : nil
            self.loading = false
            self.task = nil
            let agendaRefresh = NotchCalendarSupport.nextRefresh(self.events, now: now)
            let countdownRefresh = self.countdownEnabled
                ? NotchCalendarSupport.countdownTransition(currentEvents, now: now) : nil
            let nextRefresh = min(agendaRefresh, countdownRefresh ?? agendaRefresh)
            let timer = Timer(fireAt: nextRefresh,
                              interval: 0, target: self, selector: #selector(self.timedRefresh),
                              userInfo: nil, repeats: false)
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            self.refreshTimer = timer
        }
    }

    @objc private func timedRefresh() { refresh() }

    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        refreshTimer?.invalidate(); refreshTimer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        permissionSubscription = nil
        reader = nil
        visibleMonth = nil
        countdownEnabled = false
        excludedCalendars = []
        events = []; countdownEvent = nil; loading = false
    }
}
