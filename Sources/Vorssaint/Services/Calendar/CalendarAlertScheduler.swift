// SPDX-License-Identifier: GPL-3.0-or-later

import EventKit
import UserNotifications

final class CalendarAlertScheduler {
    static let prefix = "calendar-"
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        let join = UNNotificationAction(identifier: "calendarJoin", title: "Join", options: [.foreground])
        let snooze = UNNotificationAction(identifier: "calendarSnooze", title: "Snooze 5 min", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: "calendarAlert", actions: [join, snooze], intentIdentifiers: [])])
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in completion(granted) }
    }

    func scheduleAlerts(events: [EKEvent], minutesBefore: Int, playsSound: Bool) {
        cancelAllAlerts {
            let now = Date()
            for event in events where event.startDate.timeIntervalSince(now) > TimeInterval(minutesBefore * 60) && MeetingLinkDetector.detect(event: event) != nil {
                let content = UNMutableNotificationContent()
                content.title = event.title ?? "Calendar"
                content.body = "Meeting starts soon"
                content.categoryIdentifier = "calendarAlert"
                content.userInfo = ["eventIdentifier": event.eventIdentifier ?? ""]
                if playsSound { content.sound = .default }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: event.startDate.timeIntervalSince(now) - TimeInterval(minutesBefore * 60), repeats: false)
                self.center.add(UNNotificationRequest(identifier: Self.prefix + (event.eventIdentifier ?? UUID().uuidString), content: content, trigger: trigger))
            }
        }
    }

    func cancelAllAlerts(completion: (() -> Void)? = nil) {
        center.getPendingNotificationRequests { requests in
            self.center.removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix(Self.prefix) }.map(\.identifier))
            completion?()
        }
    }

    func snooze(eventIdentifier: String, by minutes: Int = 5) {
        let content = UNMutableNotificationContent()
        content.title = "Calendar"
        content.body = "Meeting reminder"
        content.categoryIdentifier = "calendarAlert"
        content.userInfo = ["eventIdentifier": eventIdentifier]
        center.removePendingNotificationRequests(withIdentifiers: [Self.prefix + eventIdentifier, Self.prefix + "snooze-" + eventIdentifier])
        center.add(UNNotificationRequest(identifier: Self.prefix + "snooze-" + eventIdentifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)))
    }
}
