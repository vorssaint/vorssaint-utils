// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os.log
import UserNotifications

enum Notifier {
    static let whatsAppOrganizerUndoActionIdentifier =
        "com.vorssaint.notification.whatsapp-organizer.undo"
    private static let whatsAppOrganizerTransactionKey =
        "com.vorssaint.notification.whatsapp-organizer.transaction"
    private static let whatsAppOrganizerCategoryIdentifier =
        "com.vorssaint.notification.whatsapp-organizer"
    static let breakCategoryIdentifier = "breakReminder"
    static let breakPromptKey = "breakPromptID"
    static let breakDoneAction = "breakReminder.done"
    static let breakSnoozeAction = "breakReminder.snooze"

    /// Latest localized titles; registerCategories rebuilds both categories from them.
    static var whatsAppUndoTitle = "Undo"
    static var breakDoneTitle = "Done"
    static var breakSnoozeTitle = "Snooze 5 min"

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
        post(title: title, body: body, categoryIdentifier: nil, userInfo: [:], identifier: nil)
    }

    /// The one place categories are registered: the call replaces every category.
    static func registerCategories() {
        let undo = UNNotificationAction(identifier: whatsAppOrganizerUndoActionIdentifier,
                                        title: whatsAppUndoTitle, options: [.foreground])
        let done = UNNotificationAction(identifier: breakDoneAction, title: breakDoneTitle, options: [])
        let snooze = UNNotificationAction(identifier: breakSnoozeAction, title: breakSnoozeTitle, options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: whatsAppOrganizerCategoryIdentifier,
                                   actions: [undo], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: breakCategoryIdentifier,
                                   actions: [done, snooze], intentIdentifiers: [], options: [.customDismissAction]),
        ])
    }

    static func postBreak(title: String, body: String, promptID: UUID) {
        post(title: title, body: body, categoryIdentifier: breakCategoryIdentifier,
             userInfo: [breakPromptKey: promptID.uuidString], identifier: promptID.uuidString)
    }

    static func removeBreak(promptID: UUID) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [promptID.uuidString])
        center.removePendingNotificationRequests(withIdentifiers: [promptID.uuidString])
    }

    static func postWhatsAppOrganization(title: String,
                                         body: String,
                                         undoTitle: String,
                                         transactionID: UUID) {
        whatsAppUndoTitle = undoTitle
        registerCategories()
        post(title: title, body: body,
             categoryIdentifier: whatsAppOrganizerCategoryIdentifier,
             userInfo: [whatsAppOrganizerTransactionKey: transactionID.uuidString])
    }

    static func whatsAppOrganizerTransactionID(from response: UNNotificationResponse) -> UUID? {
        guard response.actionIdentifier == whatsAppOrganizerUndoActionIdentifier,
              let raw = response.notification.request.content.userInfo[
                whatsAppOrganizerTransactionKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    private static func post(title: String,
                             body: String,
                             categoryIdentifier: String?,
                             userInfo: [AnyHashable: Any],
                             identifier: String? = nil) {
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
            content.userInfo = userInfo
            let request = UNNotificationRequest(identifier: identifier ?? UUID().uuidString, content: content, trigger: nil)
            center.add(request) { error in
                if let error {
                    log.error("notification delivery failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
