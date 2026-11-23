// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

extension NotchNotificationSupport {
    /// Chat apps whose messages open the island's full preview as they arrive,
    /// the way a phone shows a message, instead of only its compact banner.
    static let openOnArrivalApps: Set<String> = ["whatsapp"]

    /// Mail apps by the name their banners carry, without spaces: Apple Mail
    /// fetching the person's Gmail and other accounts in the background, a Gmail
    /// web app made by Chrome or Safari, or Mimestream, a native Gmail client.
    static let mailApps: Set<String> = ["mail", "gmail", "mimestream"]
    /// Gmail open in a browser, as the browser names it on its banners.
    static let webMailSites = ["mail.google.com", "gmail.com"]
    static let browsers: Set<String> = ["googlechrome", "chrome", "safari", "arc", "microsoftedge", "brave",
                                        "bravebrowser", "firefox", "opera", "vivaldi", "orion", "dia", "zen"]

    /// How long an opened message stays before the island closes again; the
    /// pointer over it keeps it open.
    static let openPreviewDuration: TimeInterval = 5

    private static func key(_ text: String) -> String { text.lowercased().filter { !$0.isWhitespace } }

    static func opensOnArrival(app: String?) -> Bool {
        guard let app else { return false }
        let name = key(app)
        return openOnArrivalApps.contains { name.hasPrefix($0) } || mailApps.contains(name)
    }

    /// An email: from a mail app, or from Gmail in a browser.
    static func isMail(_ content: NotchNotificationContent) -> Bool {
        let app = key(content.app)
        if mailApps.contains(app) { return true }
        guard browsers.contains(app) else { return false }
        let text = [content.title, content.subtitle, content.body].joined(separator: " ").lowercased()
        return webMailSites.contains { text.contains($0) }
    }

    /// Messages and emails open the island as they arrive, and stack while it is open.
    static func opensOnArrival(_ content: NotchNotificationContent?) -> Bool {
        guard let content else { return false }
        return opensOnArrival(app: content.app) || isMail(content)
    }

    /// Whether a new message joins the open one: the same chat app, or email after email.
    static func stacks(_ next: NotchNotificationContent, onto previous: NotchNotificationContent) -> Bool {
        guard opensOnArrival(next), opensOnArrival(previous) else { return false }
        return isMail(next) ? isMail(previous) : previous.app == next.app
    }
}

struct NotchNotificationContent: Equatable, Sendable {
    let app: String
    let title: String
    let subtitle: String
    let body: String

    var compactTitle: String { title.isEmpty ? app : title }

    var compactDetail: String {
        [subtitle, body].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var accessibilityText: String {
        [app, title, subtitle, body].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct NotchSystemNotification: Equatable, Identifiable, Sendable {
    let id: UUID
    let content: NotchNotificationContent
    let received: Date
    var canOpen: Bool
    /// The app offers a reply right in its notification, as WhatsApp does for a message.
    var canReply = false
}

struct NotchNotificationInbox {
    struct ArrivalCheck: Equatable, Sendable {
        let id: UUID
        let openedAt: TimeInterval
        var notBefore: TimeInterval { openedAt + NotchNotificationSupport.centerOpeningGrace }

        func delay(at now: TimeInterval) -> TimeInterval { max(0, notBefore - now) }
    }

    private(set) var items: [NotchSystemNotification] = []
    /// Unconfirmed arrivals have their own limit, so opening the center
    /// cannot evict saved messages or publish its list in the island.
    private(set) var pendingItems: [NotchSystemNotification] = []
    private var seen = Set<UUID>()
    private var primed = false
    private var opening: ArrivalCheck?

    var arrivalCheck: ArrivalCheck? { pendingItems.isEmpty ? nil : opening }

    mutating func windowCreated(at now: TimeInterval) {
        opening = ArrivalCheck(id: UUID(), openedAt: now)
    }

    mutating func update(_ live: [NotchSystemNotification]) -> [NotchSystemNotification] {
        let byID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        func refreshed(_ item: NotchSystemNotification) -> NotchSystemNotification {
            if let current = byID[item.id] { return current }
            var expired = item; expired.canOpen = false
            return expired
        }
        items = items.map(refreshed)
        pendingItems = pendingItems.map(refreshed)
        var arrivals: [NotchSystemNotification] = []
        for item in live where seen.insert(item.id).inserted {
            guard primed else { continue }
            if opening != nil {
                pendingItems.append(item)
                if pendingItems.count > NotchNotificationSupport.maximumItems { pendingItems.removeFirst() }
            } else {
                items.insert(item, at: 0)
                if items.count > NotchNotificationSupport.maximumItems { items.removeLast() }
                arrivals.append(item)
            }
        }
        primed = true
        if seen.count > 200 { seen = Set(items.map(\.id) + pendingItems.map(\.id) + live.map(\.id)) }
        return arrivals
    }

    /// The opening stays unresolved across slow reads and failed focus
    /// queries. Only a fresh check for this window may publish its arrivals.
    mutating func settleArrivals(_ check: ArrivalCheck, centerFocused: Bool?, checkedAt: TimeInterval)
        -> [NotchSystemNotification]? {
        guard opening == check, checkedAt >= check.notBefore, let centerFocused else { return nil }
        opening = nil
        let arrivals = pendingItems
        pendingItems.removeAll()
        guard !centerFocused else { return [] }
        for item in arrivals {
            items.insert(item, at: 0)
            if items.count > NotchNotificationSupport.maximumItems { items.removeLast() }
        }
        return arrivals
    }

    mutating func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
        pendingItems.removeAll { $0.id == id }
    }

    /// Banners still on screen stay seen, so the next layout pass cannot
    /// bring back what was just cleared; later arrivals are mirrored as usual.
    mutating func clear() { items.removeAll(); pendingItems.removeAll() }
}

/// Only labelled notification text belongs in the mirror. Controls, widgets
/// and editable native fields never become message content.
enum NotchNotificationSupport {
    struct Text: Equatable {
        let identifier: String
        let value: String
    }

    static let bannerRoles: Set<String> = ["AXNotificationCenterAlert", "AXNotificationCenterBanner"]
    static let stackRoles: Set<String> = ["AXNotificationCenterAlertStack", "AXNotificationCenterBannerStack"]
    static let maximumItems = 50
    /// A brief grace avoids cutting off short alert tones when closing the
    /// original banner. This does not observe playback; longer sounds may stop.
    static let nativeCloseGrace: TimeInterval = 1.2
    /// Opening the center makes a window, and the center takes the keyboard
    /// a moment later. A read in between finds its list without the focus that
    /// marks it as the open center.
    static let centerOpeningGrace: TimeInterval = 0.3

    /// Moving the window that holds a banner was measured on macOS 27, where
    /// the center keeps its banners in one window it places again each time
    /// it shows one. A moved banner stays where it was put on macOS 26 as
    /// well, so the same close works there. Versions before 26 close the
    /// original after the grace.
    static var movesNativeWindow: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// Resolve only an unambiguous installed source. Formatting marks used by
    /// localized app labels are not part of the application's name.
    static func sourceBundleIdentifier(for names: [String],
                                       applications: [(name: String, bundleIdentifier: String)]) -> String? {
        func label(_ value: String) -> String {
            let scalars = value.unicodeScalars.filter {
                ![0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069].contains($0.value)
            }
            return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let names = names.filter { $0.utf8.count <= 256 }.map(label).filter { !$0.isEmpty }
        let matches = Set(applications.filter { app in
            names.contains { label(app.name).compare($0, options: .caseInsensitive) == .orderedSame }
        }.map(\.bundleIdentifier))
        return matches.count == 1 ? matches.first : nil
    }

    /// Many messages arrive while their app is closed, so installed apps can
    /// name a source too. A running match wins; otherwise the name must stay
    /// unambiguous across both lists.
    static func sourceBundleIdentifier(for names: [String],
                                       running: [(name: String, bundleIdentifier: String)],
                                       installed: [(name: String, bundleIdentifier: String)]) -> String? {
        sourceBundleIdentifier(for: names, applications: running)
            ?? sourceBundleIdentifier(for: names, applications: running + installed)
    }

    /// Native formatted descriptions include the app before the same labelled
    /// message fields. Remove that exact suffix rather than splitting names or
    /// message text at commas, which may be part of their content.
    static func applicationLabel(from description: String, content: NotchNotificationContent) -> String? {
        let suffix = ", " + [content.title, content.subtitle, content.body].filter { !$0.isEmpty }.joined(separator: ", ")
        guard description.utf8.count <= 50_000, description.hasSuffix(suffix) else { return nil }
        let source = String(description.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty || source.utf8.count > 256 ? nil : source
    }

    static func dismissesNative(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchDismissNativeNotifications)
    }

    /// A notification's action by its title, as macOS names it: "Name:Reply", often with an
    /// invisible direction mark before the title. Nil when there is none, or more than one.
    static func namedAction(in actions: [String], titles: [String]) -> String? {
        let wanted = Set(titles.map(plainTitle))
        let matches = actions.filter { action in
            guard let first = action.components(separatedBy: "\n").first, first.hasPrefix("Name:") else { return false }
            return wanted.contains(plainTitle(String(first.dropFirst(5))))
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// A title without direction marks or surrounding space, compared without case.
    static func plainTitle(_ title: String) -> String {
        title.unicodeScalars.filter { !["\u{200E}", "\u{200F}", "\u{202A}", "\u{202C}"].contains($0) }
            .map(String.init).joined().trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func closeAction(in actions: [String], title: String) -> String? {
        guard !title.isEmpty else { return nil }
        let matches = actions.filter { $0.components(separatedBy: "\n").first == "Name:" + title }
        return matches.count == 1 ? matches.first : nil
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults)
            && AppFeature.notchNotifications.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchNotificationsEnabled)
            && NotchSupport.modules(in: defaults).contains(.notifications)
    }

    static func content(from texts: [Text]) -> NotchNotificationContent? {
        func values(_ identifier: String) -> [String] {
            texts.filter { $0.identifier == identifier }.map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let headers = values("header"), titles = values("title"), bodies = values("body")
        let subtitles = values("subtitle")
        if texts.allSatisfy({ $0.identifier.isEmpty }), (2...3).contains(texts.count),
           texts.allSatisfy({ !$0.value.isEmpty && $0.value.utf8.count <= 16_384 }) {
            return NotchNotificationContent(app: "", title: texts[0].value,
                                            subtitle: texts.count == 3 ? texts[1].value : "",
                                            body: texts[texts.count - 1].value)
        }
        // Multiple messages in a stack must never be flattened into one sender.
        guard headers.count <= 1, titles.count == 1, bodies.count <= 1, subtitles.count <= 1,
              texts.allSatisfy({ $0.value.utf8.count <= 16_384 }) else { return nil }
        return NotchNotificationContent(app: headers.first ?? "", title: titles[0],
                                        subtitle: subtitles.first ?? "", body: bodies.first ?? "")
    }

    /// Structural view markers are not durable message identities. Opening
    /// still requires the unchanged native target and notification content.
    static func nativeIdentity(_ identifier: String?) -> String? {
        guard let identifier, identifier.utf8.count <= 2_048,
              identifier.range(of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
                               options: .regularExpression) != nil else { return nil }
        return identifier
    }
}

/// The banner beside the camera: the app's icon and title on one side, the
/// message on the other. Both sides take the width the longer one needs, so
/// a short message leaves no band of empty black at the ends, while a long
/// one keeps the widest banner and wraps or truncates within it.
enum NotchNotificationBannerLayout {
    static let iconSize: CGFloat = 22
    static let spacing: CGFloat = 8
    static let wingRange: ClosedRange<CGFloat> = NotchNotice.minimumWing...190
    /// The inset from the island's curved end, and a little air so the
    /// fitted text never truncates where SwiftUI rounds its width.
    static let inset: CGFloat = 16
    static let air: CGFloat = 6
    /// The fonts the banner draws with, so it is measured in the same ones.
    static let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let messageFont = NSFont.systemFont(ofSize: 11)

    /// A strip tall enough for two lines wraps a long message onto a second.
    static func messageLines(stripHeight: CGFloat) -> Int { stripHeight >= 30 ? 2 : 1 }

    /// The sender and the message each take a side as wide as they need. A
    /// message that wraps takes the width its lines need once wrapped at the
    /// widest side, not the whole side.
    static func wings(for content: NotchNotificationContent, wrapsMessage: Bool = false) -> NotchNoticeWings {
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            // A line or two is all the banner shows, and the widest wing is
            // reached long before this much text.
            (String(text.prefix(240)) as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        }
        let title = iconSize + spacing + width(content.compactTitle, titleFont)
        var detail = width(content.compactDetail, messageFont)
        let room = wingRange.upperBound - inset - air
        if wrapsMessage, detail > room {
            let wrapped = (String(content.compactDetail.prefix(240)) as NSString).boundingRect(
                with: CGSize(width: room, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: messageFont])
            detail = min(room, wrapped.width.rounded(.up))
        }
        func fitted(_ side: CGFloat) -> CGFloat { min(wingRange.upperBound, max(wingRange.lowerBound, side + inset + air)) }
        return NotchNoticeWings(leading: fitted(title), trailing: fitted(detail))
    }
}

/// The held preview is sized from the same fonts and line limits it draws
/// with, so the island fits the message rather than scrolling or padding it.
enum NotchNotificationPreviewLayout {
    static let iconSize: CGFloat = 26
    static let headerHeight: CGFloat = 28
    static let spacing: CGFloat = 8
    static let actionHeight: CGFloat = 28
    static let titleFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static let subtitleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let bodyFont = NSFont.systemFont(ofSize: 13)
    static let titleLines = 2
    static let subtitleLines = 1
    static let bodyLines = 6

    static func contentHeight(for content: NotchNotificationContent, width: CGFloat) -> CGFloat {
        let blocks = [textHeight(content.title, font: titleFont, lines: titleLines, width: width),
                      textHeight(content.subtitle, font: subtitleFont, lines: subtitleLines, width: width),
                      textHeight(content.body, font: bodyFont, lines: bodyLines, width: width)].filter { $0 > 0 }
        return headerHeight + (blocks + [actionHeight]).reduce(0) { $0 + spacing + $1 }
    }

    /// How many earlier messages stay above the newest in an open stack.
    static let stackLimit = 3
    static let stackTitleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let stackBodyFont = NSFont.systemFont(ofSize: 12)
    static let stackBodyLines = 2
    static let stackRowPadding: CGFloat = 8

    /// The earlier messages of a stack, each a compact row above the newest.
    static func stackHeight(for earlier: [NotchNotificationContent], width: CGFloat) -> CGFloat {
        earlier.reduce(0) { total, message in
            let rowWidth = max(0, width - stackRowPadding * 2)
            let title = textHeight(message.title.isEmpty ? message.app : message.title, font: stackTitleFont,
                                   lines: 1, width: rowWidth)
            let body = textHeight(message.compactDetail, font: stackBodyFont, lines: stackBodyLines, width: rowWidth)
            return total + title + (body > 0 ? 2 + body : 0) + stackRowPadding * 2 + spacing
        }
    }

    static func textHeight(_ text: String, font: NSFont, lines: Int, width: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 0 }
        let line = ceil(font.ascender - font.descender + font.leading)
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height
        // Layout may round a wrapped line differently; a point of slack keeps
        // the last line inside the island instead of under its edge.
        return min(ceil(measured) + 1, line * CGFloat(max(1, lines)) + 1)
    }
}
