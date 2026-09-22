// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import EventKit

/// EventKit objects stay on one actor; only immutable display values reach UI.
private actor NotchCalendarReader {
    private lazy var store = EKEventStore()

    func read(interval: DateInterval) -> [NotchCalendarEvent] {
        guard !Task.isCancelled, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard event.status != .canceled,
                  event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) != true,
                  let identifier = event.eventIdentifier,
                  let start = event.startDate, let end = event.endDate else { return nil }
            let color = event.calendar.cgColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
            let tint = color.map { NotchCalendarColor(red: $0.redComponent, green: $0.greenComponent,
                                                     blue: $0.blueComponent) } ?? .fallback
            return NotchCalendarEvent(id: identifier + ":" + String(start.timeIntervalSinceReferenceDate),
                                      title: event.title ?? "", calendar: event.calendar.title,
                                      start: start, end: end, allDay: event.isAllDay,
                                      location: event.location ?? "", color: tint,
                                      calendarItemIdentifier: event.calendarItemIdentifier,
                                      recurring: event.hasRecurrenceRules || event.isDetached)
        }
    }
}

/// Owned by the notch lifecycle, including sleep and lock. No calendar data is persisted.
final class NotchCalendarService: NSObject, ObservableObject {
    static let shared = NotchCalendarService()
    @Published private(set) var events: [NotchCalendarEvent] = []
    @Published private(set) var loading = false
    private var reader: NotchCalendarReader?
    private var task: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var permissionSubscription: AnyCancellable?
    private var generation = UUID()
    private var visibleMonth: Date?

    private override init() { super.init() }

    func showMonth(_ month: Date?) {
        visibleMonth = month
        events = []
        refresh()
    }

    func syncWithPreferences() {
        guard NotchCalendarSupport.isEnabled() else { stop(); return }
        guard reader == nil else { return }
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
            events = []; loading = false
            return
        }
        let requested = generation
        let interval = NotchCalendarSupport.readInterval(month: visibleMonth, now: Date())
        loading = events.isEmpty
        task = Task { @MainActor [weak self] in
            let result = await reader.read(interval: interval)
            guard !Task.isCancelled, let self, self.generation == requested,
                  NotchCalendarSupport.isEnabled() else { return }
            let now = Date()
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                self.events = []; self.loading = false; self.task = nil
                return
            }
            self.events = NotchCalendarSupport.ordered(result)
            self.loading = false
            self.task = nil
            let timer = Timer(fireAt: NotchCalendarSupport.nextRefresh(self.events, now: now),
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
        events = []; loading = false
    }
}
