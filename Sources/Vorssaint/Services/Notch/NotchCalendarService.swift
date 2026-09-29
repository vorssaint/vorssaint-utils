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
            let recurring = event.hasRecurrenceRules || event.isDetached
            let countdownKey = NotchCalendarSupport.countdownKey(
                identifier: identifier, occurrence: recurring ? event.occurrenceDate ?? start : nil)
            return NotchCalendarEvent(id: identifier + ":" + String(start.timeIntervalSinceReferenceDate),
                                      title: event.title ?? "", calendar: event.calendar.title,
                                      start: start, end: end, allDay: event.isAllDay,
                                      location: event.location ?? "", color: Self.tint(event.calendar),
                                      calendarItemIdentifier: event.calendarItemIdentifier,
                                      recurring: recurring, countdownKey: countdownKey)
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

/// Owned by the notch lifecycle, including sleep and lock. No event text is
/// persisted; events chosen for the countdown are kept by identifier only.
final class NotchCalendarService: NSObject, ObservableObject {
    static let shared = NotchCalendarService()
    @Published private(set) var events: [NotchCalendarEvent] = []
    @Published private(set) var countdown: NotchCalendarCountdown?
    @Published private(set) var loading = false
    /// Countdown keys of the events chosen from their menu.
    @Published private(set) var chosenCountdowns = Set<String>()
    private var reader: NotchCalendarReader?
    private var task: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var permissionSubscription: AnyCancellable?
    private var generation = UUID()
    private var visibleMonth: Date?
    private var countdownEnabled = false
    private var timeLeftEnabled = false
    private var excludedCalendars = Set<String>()

    private override init() { super.init() }

    /// Every event calendar on this Mac, for the Settings list. Works while
    /// the island's reader is stopped, since the list is edited from Settings.
    func calendarChoices() async -> [NotchCalendarChoice] {
        await (reader ?? NotchCalendarReader()).calendars()
    }

    func isChosen(_ event: NotchCalendarEvent) -> Bool {
        NotchCalendarSupport.isChosen(event, in: chosenCountdowns)
    }

    /// Counts down to one event, or stops, whatever the countdown for every event does.
    func setCountdown(_ chosen: Bool, for event: NotchCalendarEvent) {
        NotchCalendarSupport.setCountdown(chosen, for: event)
        let keys = Set(NotchCalendarSupport.chosenCountdowns().keys)
        guard keys != chosenCountdowns else { return }
        chosenCountdowns = keys
        if let countdown, !follows(countdown) { self.countdown = nil }
        refresh()
    }

    private func follows(_ countdown: NotchCalendarCountdown) -> Bool {
        countdown.ongoing ? timeLeftEnabled : countdownEnabled || isChosen(countdown.event)
    }

    func showMonth(_ month: Date?) {
        visibleMonth = month
        events = []
        refresh()
    }

    func syncWithPreferences() {
        guard NotchCalendarSupport.isEnabled() else { stop(); return }
        let countdownEnabled = NotchCalendarSupport.showsCountdown()
        let timeLeftEnabled = NotchCalendarSupport.showsTimeLeft()
        let excludedCalendars = NotchCalendarSupport.excludedCalendars()
        let chosenCountdowns = Set(NotchCalendarSupport.chosenCountdowns().keys)
        guard reader == nil else {
            if self.countdownEnabled != countdownEnabled || self.timeLeftEnabled != timeLeftEnabled
                || self.excludedCalendars != excludedCalendars || self.chosenCountdowns != chosenCountdowns {
                if !excludedCalendars.isSubset(of: self.excludedCalendars) {
                    events = []
                    countdown = nil
                }
                self.countdownEnabled = countdownEnabled
                self.timeLeftEnabled = timeLeftEnabled
                self.excludedCalendars = excludedCalendars
                if self.chosenCountdowns != chosenCountdowns { self.chosenCountdowns = chosenCountdowns }
                if let countdown, !follows(countdown) { self.countdown = nil }
                refresh()
            }
            return
        }
        self.countdownEnabled = countdownEnabled
        self.timeLeftEnabled = timeLeftEnabled
        self.excludedCalendars = excludedCalendars
        if self.chosenCountdowns != chosenCountdowns { self.chosenCountdowns = chosenCountdowns }
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
            events = []; countdown = nil; loading = false
            return
        }
        let requested = generation
        let now = Date()
        let interval = NotchCalendarSupport.readInterval(month: visibleMonth, now: now)
        let currentInterval = NotchCalendarSupport.readInterval(month: nil, now: now)
        let needsCurrentRead = NotchCalendarSupport.needsCurrentRead(
            visible: interval, current: currentInterval,
            countdownEnabled: countdownEnabled || timeLeftEnabled || !chosenCountdowns.isEmpty)
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
                self.events = []; self.countdown = nil; self.loading = false; self.task = nil
                return
            }
            self.events = NotchCalendarSupport.ordered(result)
            let currentEvents = needsCurrentRead ? NotchCalendarSupport.ordered(currentResult) : self.events
            self.updateChosenCountdowns(currentEvents, now: now)
            self.countdown = NotchCalendarSupport.countdown(currentEvents, now: now, starts: self.countdownEnabled,
                                                            ends: self.timeLeftEnabled, chosen: self.chosenCountdowns)
            self.loading = false
            self.task = nil
            let agendaRefresh = NotchCalendarSupport.nextRefresh(self.events, now: now)
            let countdownRefresh = NotchCalendarSupport.countdownTransition(
                currentEvents, now: now, starts: self.countdownEnabled, ends: self.timeLeftEnabled,
                chosen: self.chosenCountdowns)
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

    /// A chosen event read again keeps its current end, and one that has
    /// ended is forgotten. Only the week holding every countdown the island
    /// can show is read; a choice further ahead keeps its end until then.
    private func updateChosenCountdowns(_ events: [NotchCalendarEvent], now: Date) {
        guard !chosenCountdowns.isEmpty,
              let choices = NotchCalendarSupport.refreshedChoices(NotchCalendarSupport.chosenCountdowns(),
                                                                  events: events, now: now) else { return }
        NotchCalendarSupport.storeChosenCountdowns(choices)
        let keys = Set(choices.keys)
        if keys != chosenCountdowns { chosenCountdowns = keys }
    }

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
        timeLeftEnabled = false
        excludedCalendars = []
        if !chosenCountdowns.isEmpty { chosenCountdowns = [] }
        events = []; countdown = nil; loading = false
    }
}
