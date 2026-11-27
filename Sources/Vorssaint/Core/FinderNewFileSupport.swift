// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreFoundation

enum FinderNewFileKind: String, CaseIterable, Codable {
    case text = "txt", markdown = "md", json
    case word = "docx", excel = "xlsx", powerpoint = "pptx"
    case pages, numbers, keynote = "key"

    static let defaultKinds: [Self] = [.text, .markdown, .word, .excel, .powerpoint]
    static let defaultSelection = defaultKinds.map(\.rawValue).joined(separator: ",")

    static func selection(_ raw: String?) -> [Self] {
        let enabled = Set((raw ?? defaultSelection).split(separator: ",").map(String.init))
        return allCases.filter { enabled.contains($0.rawValue) }
    }

    var usesTemplate: Bool { self != .text && self != .markdown && self != .json }

    var symbol: String {
        switch self {
        case .text, .markdown: return "doc.text"
        case .json: return "curlybraces"
        case .word, .pages: return "doc.richtext"
        case .excel, .numbers: return "tablecells"
        case .powerpoint, .keynote: return "rectangle.on.rectangle"
        }
    }

    func title(_ strings: FinderNewFileStrings) -> String {
        let name: String
        switch self {
        case .text: name = strings.text
        case .markdown: name = "Markdown"
        case .json: name = "JSON"
        case .word: name = "Word"
        case .excel: name = "Excel"
        case .powerpoint: name = "PowerPoint"
        case .pages: name = "Pages"
        case .numbers: name = "Numbers"
        case .keynote: name = "Keynote"
        }
        return "\(name) (.\(rawValue))"
    }
}

struct FinderNewFileSnapshot: Codable {
    let enabled: Bool
    let language: String
    let selection: String

    var kinds: [FinderNewFileKind] { FinderNewFileKind.selection(selection) }
}

/// A short-lived request carries only the selected directory and document kind.
/// The host separately authenticates the system-provided Apple event sender.
struct FinderNewFileRequest: Codable, Equatable {
    let id: UUID
    let kind: FinderNewFileKind
    let directory: URL
    let createdAt: Date

    init(kind: FinderNewFileKind, directory: URL, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.directory = directory
        self.createdAt = createdAt
    }

    static let maximumAge: TimeInterval = 60
    static let maximumPayloadBytes = 16_384

    static func isLocalDirectoryURL(_ url: URL) -> Bool {
        url.isFileURL && [nil, "", "localhost"].contains(url.host)
            && url.path.hasPrefix("/") && !url.path.contains("\0")
            && url.path.utf8.count <= 8_192
            && url.query == nil && url.fragment == nil
            && url.user == nil && url.password == nil && url.port == nil
    }

    func isValid(now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        return age >= -2 && age <= Self.maximumAge && Self.isLocalDirectoryURL(directory)
    }

    static var scheme: String {
        #if VORSSAINT_DEVELOPMENT
        return "vorssaint-dev-new-file"
        #else
        return "vorssaint-new-file"
        #endif
    }

    var url: URL? {
        guard isValid(), let data = try? JSONEncoder().encode(self),
              data.count <= Self.maximumPayloadBytes else { return nil }
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = "create"
        parts.queryItems = [URLQueryItem(name: "request", value: data.base64EncodedString())]
        guard let url = parts.url, url.absoluteString.utf8.count <= 32_768 else { return nil }
        return url
    }

    static func decode(_ url: URL, now: Date = Date()) -> Self? {
        guard url.absoluteString.utf8.count <= 32_768,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == scheme, parts.host == "create", parts.path.isEmpty,
              parts.fragment == nil, parts.user == nil, parts.password == nil, parts.port == nil,
              let query = parts.queryItems, query.count == 1, query[0].name == "request",
              let value = query[0].value, let data = Data(base64Encoded: value),
              data.count <= maximumPayloadBytes,
              let request = try? JSONDecoder().decode(Self.self, from: data),
              request.isValid(now: now) else { return nil }
        return request
    }

}

/// Presentation preferences only. This domain is readable by the sandboxed
/// extension but never grants the authority to write a file.
enum FinderNewFileExchange {
    private static var menuDomain: CFString {
        #if VORSSAINT_DEVELOPMENT
        return "com.vorssaint.utils.dev.finder-new-file-menu" as CFString
        #else
        return "com.vorssaint.utils.finder-new-file-menu" as CFString
        #endif
    }

    private static let snapshotKey = "snapshot" as CFString

    static func publish(_ snapshot: FinderNewFileSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        CFPreferencesSetValue(snapshotKey, data as CFData, menuDomain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(menuDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        else { throw CocoaError(.fileWriteUnknown) }
    }

    static func snapshot() -> FinderNewFileSnapshot? {
        CFPreferencesSynchronize(menuDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard let data = CFPreferencesCopyValue(snapshotKey, menuDomain,
                                                kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Data,
              data.count <= 4_096 else { return nil }
        return try? JSONDecoder().decode(FinderNewFileSnapshot.self, from: data)
    }
}

/// Bounded in-memory replay protection, used on the main thread after sender
/// authentication. Never evict a still-valid ID to make room for a new request.
struct FinderNewFileReplayGuard {
    private var seen: [UUID: Date] = [:]

    mutating func accept(_ request: FinderNewFileRequest, now: Date = Date()) -> Bool {
        guard request.isValid(now: now) else { return false }
        seen = seen.filter { $0.value >= now }
        guard seen[request.id] == nil, seen.count < 1_024 else { return false }
        seen[request.id] = request.createdAt.addingTimeInterval(FinderNewFileRequest.maximumAge)
        return true
    }
}
