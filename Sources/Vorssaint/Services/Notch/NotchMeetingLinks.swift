// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A video call service an event's link can lead to.
enum NotchMeetingPlatform: String, CaseIterable, Sendable {
    case zoom, meet, teams, webex, slack, discord, skype, goTo, jitsi, whereby, facetime, chime

    var name: String {
        switch self {
        case .zoom: return "Zoom"
        case .meet: return "Google Meet"
        case .teams: return "Microsoft Teams"
        case .webex: return "Webex"
        case .slack: return "Slack"
        case .discord: return "Discord"
        case .skype: return "Skype"
        case .goTo: return "GoTo Meeting"
        case .jitsi: return "Jitsi Meet"
        case .whereby: return "Whereby"
        case .facetime: return "FaceTime"
        case .chime: return "Amazon Chime"
        }
    }

    /// The SVG in Resources/Images; nil draws a generic video mark.
    var logo: String? {
        switch self {
        case .zoom: return "meeting-zoom"
        case .meet: return "meeting-meet"
        case .teams: return "meeting-teams"
        case .webex: return "meeting-webex"
        case .slack: return "meeting-slack"
        case .discord: return "discord-symbol"
        case .skype: return "meeting-skype"
        case .goTo: return "meeting-goto"
        case .jitsi: return "meeting-jitsi"
        case .whereby, .facetime, .chime: return nil
        }
    }

    /// The service a link joins, or nil for any other page, so a calendar's
    /// agenda or a document link never reads as a call.
    static func platform(for url: URL) -> NotchMeetingPlatform? {
        let scheme = url.scheme?.lowercased() ?? ""
        // The apps' own schemes also open chats and other screens: only a
        // join with a meeting number, or a Teams meeting, is a call.
        if scheme == "zoommtg" || scheme == "zoomus" { return zoomNumber(url) != nil ? .zoom : nil }
        if scheme == "msteams" { return url.path.lowercased().hasPrefix("/l/meetup-join/") ? .teams : nil }
        guard scheme == "https" || scheme == "http", let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if on("zoom.us") || on("zoomgov.com") {
            return ["/j/", "/my/", "/s/", "/w/", "/wc/"].contains { path.hasPrefix($0) } ? .zoom : nil
        }
        if host == "meet.google.com" { return path.count > 1 ? .meet : nil }
        if on("teams.microsoft.com") || on("teams.live.com") {
            return path.contains("meetup-join") || path.hasPrefix("/meet/") ? .teams : nil
        }
        if on("webex.com") {
            // A personal room, a meeting number's join page, or the join service.
            let joins = (path.hasPrefix("/meet/") && path.count > 6) || path.hasSuffix("/j.php")
                || path.hasPrefix("/join/") || path.contains("/wbxmjs/joinservice/")
            return joins ? .webex : nil
        }
        if on("slack.com") { return path.contains("huddle") ? .slack : nil }
        if host == "discord.gg" { return .discord }
        if on("discord.com") { return path.hasPrefix("/channels/") || path.hasPrefix("/invite/") ? .discord : nil }
        if host == "join.skype.com" { return .skype }
        if ["meet.goto.com", "global.gotomeeting.com", "app.gotomeeting.com", "gotomeet.me"].contains(host) { return .goTo }
        if host == "meet.jit.si" { return path.count > 1 ? .jitsi : nil }
        if on("whereby.com") { return path.count > 1 ? .whereby : nil }
        if host == "facetime.apple.com" { return .facetime }
        if on("chime.aws") { return .chime }
        return nil
    }

    /// The meeting number a native Zoom join carries, or nil for any other action.
    static func zoomNumber(_ url: URL) -> String? {
        guard url.path.lowercased() == "/join" else { return nil }
        let number = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "confno" }?.value ?? ""
        return number.isEmpty || !number.allSatisfy(\.isNumber) ? nil : number
    }
}

/// The call an event joins: its service and the link the invitation gave.
struct NotchMeetingLink: Equatable, Sendable {
    let platform: NotchMeetingPlatform
    let url: URL

    /// How long before a start the island offers to join.
    static let joinLead: TimeInterval = 5 * 60

    /// The first call link among an event's URL, location and notes, in
    /// that order. Links wrapped by Outlook's or Google's redirectors are
    /// unwrapped first, as invitations often carry them.
    static func find(url: URL?, location: String, notes: String) -> NotchMeetingLink? {
        if let url, let link = link(unwrapped(url)) { return link }
        for text in [location, notes] where !text.isEmpty {
            if let link = links(in: text).lazy.compactMap({ link(unwrapped($0)) }).first { return link }
        }
        return nil
    }

    /// Whether `now` lies between the join lead before the start and the end.
    static func isJoinable(_ event: NotchCalendarEvent, now: Date) -> Bool {
        event.meeting != nil && !event.allDay
            && now >= event.start.addingTimeInterval(-joinLead) && now < event.end
    }

    /// Opens the meeting in its app when one handles the link without a
    /// browser page in between: Zoom's and Teams' own schemes.
    var nativeURL: URL? {
        guard url.scheme == "https" || url.scheme == "http" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch platform {
        case .zoom:
            let parts = url.path.split(separator: "/")
            guard parts.count >= 2, parts[0] == "j", let host = url.host else { return nil }
            var native = URLComponents()
            native.scheme = "zoommtg"
            native.host = host
            native.path = "/join"
            native.queryItems = [URLQueryItem(name: "action", value: "join"),
                                 URLQueryItem(name: "confno", value: String(parts[1]))]
                + (components?.queryItems?.filter { $0.name == "pwd" } ?? [])
            return native.url
        case .teams:
            guard url.path.lowercased().contains("meetup-join") else { return nil }
            let query = components?.percentEncodedQuery.map { "?" + $0 } ?? ""
            return URL(string: "msteams:" + (components?.percentEncodedPath ?? url.path) + query)
        default:
            return nil
        }
    }

    /// The call as a page a browser opens: the link itself, or the web
    /// meeting a native Zoom or Teams link stands for. Nil when there is none.
    var webURL: URL? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch url.scheme?.lowercased() {
        case "https", "http":
            return url
        case "zoommtg", "zoomus":
            guard let number = NotchMeetingPlatform.zoomNumber(url) else { return nil }
            let host = url.host?.lowercased() ?? ""
            var web = URLComponents()
            web.scheme = "https"
            web.host = host == "zoom.us" || host.hasSuffix(".zoom.us") ? host : "zoom.us"
            web.path = "/j/" + number
            let password = components?.queryItems?.filter { $0.name == "pwd" } ?? []
            web.queryItems = password.isEmpty ? nil : password
            return web.url
        case "msteams":
            guard let components else { return nil }
            let query = components.percentEncodedQuery.map { "?" + $0 } ?? ""
            return URL(string: "https://teams.microsoft.com" + components.percentEncodedPath + query)
        default:
            return nil
        }
    }

    private static func link(_ url: URL) -> NotchMeetingLink? {
        NotchMeetingPlatform.platform(for: url).map { NotchMeetingLink(platform: $0, url: url) }
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
    }

    /// The link a redirector forwards to, or the link itself.
    static func unwrapped(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return url }
        let key: String
        if host.hasSuffix("safelinks.protection.outlook.com") { key = "url" }
        else if (host == "www.google.com" || host == "google.com") && url.path == "/url" { key = "q" }
        else { return url }
        return items.first { $0.name == key }?.value.flatMap(URL.init(string:)) ?? url
    }
}
