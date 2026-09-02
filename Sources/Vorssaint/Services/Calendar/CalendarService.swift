// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import EventKit
import Foundation

extension Notification.Name {
    static let calendarStatusItemClicked = Notification.Name("VorssaintCalendarStatusItemClicked")
    static let calendarPopoverWillShow = Notification.Name("VorssaintCalendarPopoverWillShow")
}

/// Local-only bridge to EventKit. Calendar access is deliberately requested
/// only after the user turns the feature on; disabling releases every timer
/// and observer immediately.
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var calendars: [EKCalendar] = []

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var refreshTimer: Timer?
    private var flashTimer: Timer?
    private var statusItem: NSStatusItem?
    private let alerts = CalendarAlertScheduler()
    private static let statusItemAutosaveName = "VorssaintCalendarItem"

    private init() {}

    func syncWithPreferences() {
        guard AppFeature.calendar.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.calendarEnabled) else {
            teardown()
            return
        }
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if authorizationStatus == .notDetermined {
            store.requestFullAccessToEvents { [weak self] _, _ in
                DispatchQueue.main.async { self?.syncWithPreferences() }
            }
            return
        }
        guard authorizationStatus == .fullAccess else {
            events = []
            return
        }
        installObserverIfNeeded()
        refresh()
        installTimerIfNeeded()
        installStatusItemIfNeeded()
    }

    func refresh(date: Date = Date()) {
        guard authorizationStatus == .fullAccess else { return }
        let calendar = Calendar.autoupdatingCurrent
        let window = CalendarSupport.eventWindow(around: date, calendar: calendar)
        calendars = store.calendars(for: .event)
        events = store.events(matching: store.predicateForEvents(withStart: window.start, end: window.end, calendars: selectedCalendars()))
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
        updateStatusItem(date: Date())
        if UserDefaults.standard.bool(forKey: DefaultsKey.calendarAlertEnabled) {
            alerts.scheduleAlerts(events: events,
                                  minutesBefore: UserDefaults.standard.integer(forKey: DefaultsKey.calendarAlertMinutesBefore),
                                  playsSound: UserDefaults.standard.bool(forKey: DefaultsKey.calendarAlertSound))
        } else { alerts.cancelAllAlerts() }
    }

    func teardown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        flashTimer?.invalidate()
        flashTimer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        events = []
        calendars = []
        alerts.cancelAllAlerts()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    private func selectedCalendars() -> [EKCalendar]? {
        guard let ids = CalendarSupport.selectedCalendarIDs(from: UserDefaults.standard.data(forKey: DefaultsKey.calendarSelectedCalendars)), !ids.isEmpty else { return nil }
        return store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
    }

    private func installObserverIfNeeded() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            self?.refresh()
        }
    }

    private func installTimerIfNeeded() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func setSelectedCalendars(_ ids: Set<String>) {
        if ids.isEmpty { UserDefaults.standard.removeObject(forKey: DefaultsKey.calendarSelectedCalendars) }
        else { UserDefaults.standard.set(CalendarSupport.encodedCalendarIDs(ids), forKey: DefaultsKey.calendarSelectedCalendars) }
        refresh()
    }

    func eventsForSelectedDay(_ date: Date) -> [EKEvent] {
        let calendar = Calendar.autoupdatingCurrent
        return events.filter { CalendarSupport.overlapsDay(start: $0.startDate, end: $0.endDate, day: date, calendar: calendar) }
    }

    @discardableResult
    func createEvent(from draft: CalendarQuickEventDraft) throws -> EKEvent {
        guard authorizationStatus == .fullAccess else { throw CalendarServiceError.accessRequired }
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        if let name = draft.calendarName?.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current),
           let matched = store.calendars(for: .event).first(where: { $0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(name) }) {
            event.calendar = matched
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }
        guard event.calendar != nil else { throw CalendarServiceError.noWritableCalendar }
        try store.save(event, span: .thisEvent, commit: true)
        refresh(date: draft.startDate)
        return event
    }

    func openMeeting(eventIdentifier: String) {
        guard let event = store.event(withIdentifier: eventIdentifier), event.endDate > Date(), let link = MeetingLinkDetector.detect(event: event) else { return }
        MeetingLinkDetector.open(kind: link)
    }

    func snooze(eventIdentifier: String) {
        guard let event = store.event(withIdentifier: eventIdentifier), event.endDate > Date() else { return }
        alerts.snooze(eventIdentifier: eventIdentifier)
    }

    func flashStatusItemForAlert() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.calendarAlertFlash), let button = statusItem?.button else { return }
        flashTimer?.invalidate()
        var remaining = 8
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self, weak button] timer in
            guard let button else { timer.invalidate(); return }
            button.alphaValue = button.alphaValue == 1 ? 0.2 : 1
            remaining -= 1
            if remaining == 0 { button.alphaValue = 1; timer.invalidate(); self?.flashTimer = nil }
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.statusItemAutosaveName
        item.button?.target = self
        item.button?.action = #selector(showCalendar)
        statusItem = item
        updateStatusItem(date: Date())
    }

    private func updateStatusItem(date: Date) {
        guard let button = statusItem?.button else { return }
        let defaults = UserDefaults.standard
        let style = CalendarIconStyle(rawValue: defaults.string(forKey: DefaultsKey.calendarIconStyle) ?? "icon") ?? .icon
        let components = CalendarSupport.menuBarComponents(
            from: defaults.string(forKey: DefaultsKey.calendarMenuBarComponents),
            fallbackStyle: style
        )
        let scale = min(1.4, max(0.8, UserDefaults.standard.double(forKey: DefaultsKey.calendarTextScale)))
        let dateFormat = CalendarDateDisplayFormat(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.calendarDateDisplayFormat) ?? "dayMonth") ?? .dayMonth
        let nextEvent = events.first(where: { !$0.isAllDay && $0.startDate >= date })
        button.image = CalendarStatusItemRenderer.render(components: components,
                                                          date: date,
                                                          nextEvent: nextEvent,
                                                          scale: scale == 0 ? 1 : scale,
                                                          dateFormat: dateFormat,
                                                          customPattern: defaults.string(forKey: DefaultsKey.calendarCustomDateFormat) ?? "dd/MM")
        button.toolTip = "Calendar"
    }

    @objc private func showCalendar() {
        refresh()
        if let button = statusItem?.button { NotificationCenter.default.post(name: .calendarStatusItemClicked, object: button) }
    }
}

enum CalendarServiceError: LocalizedError {
    case accessRequired, noWritableCalendar
    var errorDescription: String? {
        switch self {
        case .accessRequired: return "Calendar access is required."
        case .noWritableCalendar: return "No writable calendar is available."
        }
    }
}
