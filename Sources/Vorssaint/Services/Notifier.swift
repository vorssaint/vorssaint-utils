// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os.log
import UserNotifications

enum Notifier {
    static let whatsAppOrganizerUndoActionIdentifier =
        "com.vorssaint.notification.whatsapp-organizer.undo"
    private static let whatsAppOrganizerCategoryIdentifier =
        "com.vorssaint.notification.whatsapp-organizer"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "notifications")

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            // A denied prompt is the user's call; a request that ERRORS means
            // notifications silently cannot work at all — leave a trace so
            // that state is diagnosable instead of invisible.
            if let error {
                log.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                log.notice("notification authorization not granted")
            }
        }
    }

    static func post(title: String, body: String) {
        post(title: title, body: body, categoryIdentifier: nil)
    }

    static func postWhatsAppOrganization(title: String,
                                         body: String,
                                         undoTitle: String) {
        let center = UNUserNotificationCenter.current()
        let undo = UNNotificationAction(
            identifier: whatsAppOrganizerUndoActionIdentifier,
            title: undoTitle,
            options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: whatsAppOrganizerCategoryIdentifier,
                                   actions: [undo], intentIdentifiers: [], options: []),
        ])
        post(title: title, body: body,
             categoryIdentifier: whatsAppOrganizerCategoryIdentifier)
    }

    private static func post(title: String,
                             body: String,
                             categoryIdentifier: String?) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
                log.notice("notification dropped: authorization status \(settings.authorizationStatus.rawValue)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let categoryIdentifier { content.categoryIdentifier = categoryIdentifier }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request) { error in
                if let error {
                    log.error("notification delivery failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
