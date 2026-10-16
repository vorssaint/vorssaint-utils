// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import UserNotifications

final class NotificationBreakDelivery: BreakDelivery {
    static let shared = NotificationBreakDelivery()

    private(set) var authorized = false
    private var handlers: [UUID: (BreakAction) -> Void] = [:]

    /// Cached because present must answer synchronously. A stale cache can
    /// drop one prompt until its timeout; accepted in the spec.
    func refreshAuthorization(requestIfUndetermined: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                if requestIfUndetermined, settings.authorizationStatus == .notDetermined {
                    Notifier.requestPermission()
                }
            }
        }
    }

    func present(_ prompt: BreakPrompt, respond: @escaping (BreakAction) -> Void) -> Bool {
        guard Bundle.main.bundleIdentifier != nil, authorized else { return false }
        let text = FeatureStrings.breakReminders(L10n.shared.language)
        Notifier.breakDoneTitle = text.done
        Notifier.breakSnoozeTitle = text.snooze
        Notifier.registerCategories()
        handlers[prompt.id] = respond
        let generic = prompt.kind == .eyes ? text.eyesGeneric : text.movementGeneric
        Notifier.postBreak(title: prompt.activity?.text ?? generic,
                           body: "\(prompt.seconds) s", promptID: prompt.id)
        return true
    }

    func dismiss(id: UUID) {
        handlers[id] = nil
        Notifier.removeBreak(promptID: id)
    }

    func handle(id: UUID, actionIdentifier: String) {
        guard let respond = handlers.removeValue(forKey: id) else { return }
        switch actionIdentifier {
        case Notifier.breakSnoozeAction: respond(.snooze)
        case UNNotificationDismissActionIdentifier: respond(.skip)
        default: respond(.done)   // Done button or a tap on the banner
        }
    }
}
