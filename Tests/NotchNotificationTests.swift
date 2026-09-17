// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchNotificationTests {
    static func run(expect: (Bool, String) -> Void) {
        expect(NotchEvent.systemNotification.duration == 3 && NotchEvent.timer.duration == 6,
               "message banners close sooner without shortening timers or other activities")
        expect(NotchNotificationSupport.closeAction(in: ["Name:Close\nTarget:0x0\nSelector:(null)"], title: "Close") != nil
               && NotchNotificationSupport.closeAction(in: ["Name:Close All\nTarget:0x0"], title: "Close") == nil,
               "native closing uses the exact system action label and cannot match a group action")
        typealias Text = NotchNotificationSupport.Text
        let texts = [Text(identifier: "header", value: "Chat"), Text(identifier: "title", value: "Alex"),
                     Text(identifier: "body", value: "Hello")]
        let content = NotchNotificationSupport.content(from: texts)!
        expect(content.app == "Chat" && content.title == "Alex" && content.body == "Hello",
               "notifications keep application, conversation and message separate")
        expect(NotchNotificationSupport.content(from: texts + [Text(identifier: "title", value: "Sam")]) == nil,
               "stacked senders are never combined into one notification")
        expect(NotchNotificationSupport.content(from: texts + [Text(identifier: "body", value: "Second")]) == nil,
               "multiple messages require separate notification identities")
        expect(NotchNotificationSupport.content(from: [Text(identifier: "body", value: "No sender")]) == nil,
               "a body without a title cannot become a notification")
        expect(NotchNotificationSupport.content(from: [Text(identifier: "title", value: String(repeating: "a", count: 16_385))]) == nil,
               "notification text has a bounded memory budget")
        expect(NotchNotificationSupport.content(from: [Text(identifier: "", value: "Alex"), Text(identifier: "", value: "Hello")])?.body == "Hello",
               "legacy banners with two static labels preserve sender and message")
        expect(NotchNotificationSupport.content(from: texts + [Text(identifier: "editableText", value: "Private draft")]) == content,
               "editable native content never becomes part of a mirrored notification")
        expect(NotchNotificationSupport.nativeIdentity("AXNotificationListItems") == nil
               && NotchNotificationSupport.nativeIdentity(nil) == nil
               && NotchNotificationSupport.nativeIdentity("title") == nil,
               "a structural view marker is not a durable notification identity")
        let attributedContent = NotchNotificationContent(app: "", title: "Alex, Sam", subtitle: "Group", body: "Hello, everyone")
        expect(NotchNotificationSupport.applicationLabel(from: "Chat, Inc., Alex, Sam, Group, Hello, everyone", content: attributedContent) == "Chat, Inc.",
               "formatted descriptions preserve commas in app names, senders and messages")
        expect(NotchNotificationSupport.applicationLabel(from: "Chat, Different message", content: attributedContent) == nil
               && NotchNotificationSupport.applicationLabel(from: "Alex, Sam, Group, Hello, everyone", content: attributedContent) == nil,
               "unmatched descriptions and message-only descriptions cannot invent an app source")
        let applications = [(name: "Chat", bundleIdentifier: "test.chat"),
                            (name: "Mail", bundleIdentifier: "test.mail")]
        expect(NotchNotificationSupport.sourceBundleIdentifier(for: [" chat "], applications: applications) == "test.chat",
               "a complete source label selects its application icon without depending on label capitalization")
        expect(NotchNotificationSupport.sourceBundleIdentifier(for: ["\u{200e}Chat"], applications: applications) == "test.chat"
               && NotchNotificationSupport.sourceBundleIdentifier(for: ["Chat"], applications: [(name: "\u{200e}Chat", bundleIdentifier: "test.chat")]) == "test.chat",
               "directional formatting on either system label does not hide the application icon")
        expect(NotchNotificationSupport.sourceBundleIdentifier(for: [""], applications: applications) == nil
               && NotchNotificationSupport.sourceBundleIdentifier(for: ["Cha"], applications: applications) == nil
               && NotchNotificationSupport.sourceBundleIdentifier(for: ["test.chat"], applications: applications) == nil,
               "missing, partial or technical-looking source labels cannot invent application identity")
        expect(NotchNotificationSupport.sourceBundleIdentifier(for: ["Chat"], applications: applications + [
            (name: "Chat", bundleIdentifier: "test.other")]) == nil,
               "ambiguous application names retain the neutral notification icon")
        expect(NotchNotificationSupport.sourceBundleIdentifier(for: ["Chat"], applications: applications + [
            (name: "Chat", bundleIdentifier: "test.chat")]) == "test.chat",
               "multiple processes belonging to the same application do not create false ambiguity")
        expect(NotchNotificationSupport.sourceBundleIdentifier(for: ["Contact photo", "Chat"], applications: applications) == "test.chat",
               "an application icon label can identify the source beside an unrelated contact image")
        expect(NotchNotificationSupport.sourceBundleIdentifier(for: ["Chat", "Mail"], applications: applications) == nil,
               "conflicting image labels cannot attribute a message to an arbitrary application")
        let shortBanner = NotchNotificationContent(app: "Chat", title: "Alex", subtitle: "", body: "Test")
        let longBanner = NotchNotificationContent(app: "Chat", title: "Alex", subtitle: "", body: String(repeating: "Message ", count: 100))
        expect(shortBanner.compactTitle == "Alex" && shortBanner.compactDetail == "Test",
               "compact notifications keep the sender and message in their separate wings")
        expect(longBanner.compactDetail == longBanner.body,
               "visual truncation never discards the full stored notification text")
        expect(NotchNotificationContent(app: "Chat", title: "", subtitle: "Group", body: "Test").compactTitle == "Chat",
               "notifications without a title keep their source as context")
        let conversation = NotchNotificationContent(app: "Chat", title: "Alex", subtitle: "Trip", body: "Hello")
        expect(conversation.compactDetail == "Trip · Hello",
               "conversation context and the message share the compact detail without extra rows")
        expect(conversation.accessibilityText == "Chat, Alex, Trip, Hello",
               "a banner announces source, sender, conversation and message in reading order")
        expect(NotchNotificationContent(app: "", title: "Alex", subtitle: "", body: "Hello").accessibilityText == "Alex, Hello",
               "unavailable source metadata never duplicates or corrupts the announcement")
        let requestIdentity = "request." + UUID().uuidString
        expect(NotchNotificationSupport.nativeIdentity(requestIdentity) == requestIdentity,
               "a UUID-shaped candidate passes the conservative filter without proving native request semantics")

        func item(_ id: UUID = UUID()) -> NotchSystemNotification {
            NotchSystemNotification(id: id, content: content, received: Date(), canOpen: true)
        }
        var inbox = NotchNotificationInbox()
        let existing = item(), first = item(), second = item()
        expect(inbox.update([existing]).isEmpty && inbox.items.isEmpty,
               "enabling mirroring does not replay banners already on screen")
        expect(inbox.update([existing, first, first]).map(\.id) == [first.id] && inbox.items.count == 1,
               "repeated layout callbacks deliver each new notification once")
        expect(inbox.update([first, second]).map(\.id) == [second.id] && inbox.items.count == 2,
               "identical text from different notifications remains distinct")
        inbox.dismiss(second.id)
        expect(inbox.update([first, second]).isEmpty && !inbox.items.contains(where: { $0.id == second.id }),
               "a dismissed mirror does not return when the native banner changes layout")
        _ = inbox.update([])
        expect(inbox.items.first?.canOpen == false,
               "expired native banners lose their actions while their mirrored text remains")
        for _ in 0..<300 { _ = inbox.update([item()]) }
        expect(inbox.items.count == NotchNotificationSupport.maximumItems, "the session inbox stays bounded during bursts")
        inbox = NotchNotificationInbox()
        expect(inbox.items.isEmpty, "locking or disabling discards mirrored messages")

        let suite = "com.vorssaint.tests.notch-notifications"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        expect(!NotchNotificationSupport.isEnabled(in: defaults), "enabling the notch never enables message mirroring")
        defaults.set(true, forKey: DefaultsKey.notchNotificationsEnabled)
        expect(NotchSupport.routes(.systemNotification, in: defaults), "an explicit opt-in enables new notification banners")
        expect(!NotchNotificationSupport.dismissesNative(in: defaults), "native banners remain intact by default")
        defaults.set(true, forKey: DefaultsKey.notchDismissNativeNotifications)
        expect(NotchNotificationSupport.dismissesNative(in: defaults), "native closing requires both notification opt-ins")
        defaults.set(false, forKey: AppFeature.notchNotifications.availabilityKey)
        expect(!NotchSupport.routes(.systemNotification, in: defaults) && !NotchNotificationSupport.dismissesNative(in: defaults), "the hub gates the reader, banners and native closing together")
        defaults.set(true, forKey: AppFeature.notchNotifications.availabilityKey)
        defaults.set("notifications", forKey: DefaultsKey.notchHiddenModules)
        expect(!NotchNotificationSupport.isEnabled(in: defaults), "hiding notifications also stops reading messages")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        expect(!NotchNotificationSupport.isEnabled(in: defaults), "the master switch gates mirroring")
        expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchNotificationsEnabled,
                                                                 AppFeature.notchNotifications.availabilityKey, DefaultsKey.notchDismissNativeNotifications]),
               "notification preferences are included in settings backup")
        expect(AppFeature.notchNotifications.permissions == [.accessibility],
               "banner mirroring needs Accessibility rather than access to private notification databases")
    }
}
