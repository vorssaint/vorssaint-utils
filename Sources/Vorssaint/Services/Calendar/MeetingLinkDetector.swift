// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import EventKit
import Foundation

enum MeetingLinkKind: Equatable {
    case zoom(URL), googleMeet(URL), microsoftTeams(URL), webex(URL), facetime(URL)
    var url: URL { switch self { case let .zoom(url), let .googleMeet(url), let .microsoftTeams(url), let .webex(url), let .facetime(url): return url } }
}

enum MeetingLinkDetector {
    static func detect(event: EKEvent) -> MeetingLinkKind? {
        guard event.calendar.type != .birthday else { return nil }
        return detect(location: event.location, url: event.url, notes: event.notes)
    }

    static func detect(location: String?, url: URL?, notes: String?) -> MeetingLinkKind? {
        let candidates = [location].compactMap { $0 }.flatMap(urls(in:)) + (url.map { [$0] } ?? []) + (notes.map(urls(in:)) ?? [])
        return candidates.lazy.compactMap(kind(for:)).first
    }

    static func open(kind: MeetingLinkKind, workspace: NSWorkspace = .shared) {
        switch kind {
        case let .zoom(url):
            if workspace.urlForApplication(withBundleIdentifier: "us.zoom.xos") != nil,
               let id = url.pathComponents.last,
               let native = URL(string: "zoommtg://zoom.us/join?confno=\(id)") { workspace.open(native) } else { workspace.open(url) }
        case let .microsoftTeams(url):
            if workspace.urlForApplication(withBundleIdentifier: "com.microsoft.teams2") != nil,
               let native = URL(string: url.absoluteString.replacingOccurrences(of: "https://teams.microsoft.com/", with: "msteams://")) { workspace.open(native) } else { workspace.open(url) }
        default: workspace.open(kind.url)
        }
    }

    private static func urls(in text: String) -> [URL] {
        let range = NSRange(text.startIndex..., in: text)
        return (try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue))?.matches(in: text, range: range).compactMap(\.url) ?? []
    }

    private static func kind(for url: URL) -> MeetingLinkKind? {
        let value = url.absoluteString.lowercased()
        if value.contains("zoom.us/j/") { return .zoom(url) }
        if value.contains("meet.google.com/") { return .googleMeet(url) }
        if value.contains("teams.microsoft.com/l/meetup-join") { return .microsoftTeams(url) }
        if value.contains("webex.com/meet/") { return .webex(url) }
        if url.scheme?.lowercased() == "facetime" { return .facetime(url) }
        return nil
    }
}
