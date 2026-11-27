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

    func name(_ strings: FinderNewFileStrings) -> String {
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
        return name
    }

    func title(_ strings: FinderNewFileStrings) -> String {
        "\(name(strings)) (.\(rawValue))"
    }

    /// Stable identifiers are independent of the order of allCases.
    var itemID: UUID {
        let number: Int
        switch self {
        case .text: number = 1
        case .markdown: number = 2
        case .json: number = 3
        case .word: number = 4
        case .excel: number = 5
        case .powerpoint: number = 6
        case .pages: number = 7
        case .numbers: number = 8
        case .keynote: number = 9
        }
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!
    }
}

/// User-editable definitions live only in the host's preferences. The menu
/// snapshot contains a separate, minimal projection with no template data.
struct FinderNewFileItem: Codable, Identifiable, Equatable {
    struct Template: Codable, Equatable {
        let id: UUID
        let name: String
    }

    var id = UUID()
    var title = ""
    var filename = "Untitled"
    var suffix = ""
    var template: Template?
    var builtIn: FinderNewFileKind?
    // Optional for decoding custom entries from the previous settings format.
    var enabled: Bool?
    var useBuiltInContent: Bool?

    var isEnabled: Bool { enabled ?? true }
    var canDelete: Bool { builtIn == nil }
    var hasBuiltInContent: Bool { template == nil && builtIn != nil && (useBuiltInContent ?? true) }
    var symbol: String { FinderNewFileKind(rawValue: suffix.lowercased())?.symbol ?? "doc" }

    func displayName(_ strings: FinderNewFileStrings) -> String {
        title.isEmpty ? (builtIn?.name(strings) ?? "") : title
    }

    func menuTitle(_ strings: FinderNewFileStrings) -> String {
        displayName(strings) + (suffix.isEmpty ? "" : " (.\(suffix))")
    }

    static let maximum = 32
    static let maximumTemplateBytes = 64 * 1024 * 1024

    var normalized: Self? {
        var item = self
        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.filename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        item.suffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.suffix.hasPrefix(".") { item.suffix.removeFirst() }
        if let kind = item.builtIn { item.id = kind.itemID }
        guard (!item.title.isEmpty || item.builtIn != nil), item.title.utf8.count <= 120,
              !item.title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              Self.validComponent(item.filename),
              item.suffix.isEmpty || Self.validComponent(item.suffix),
              !item.suffix.hasPrefix("."), !item.suffix.hasSuffix("."),
              !item.filename.hasSuffix("."),
              item.outputName.utf8.count <= 220 else { return nil }
        if let template = item.template {
            guard !template.name.isEmpty, template.name.utf8.count <= 1024 else { return nil }
        }
        return item
    }

    private static func validComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains(":")
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    var outputName: String { filename + (suffix.isEmpty ? "" : "." + suffix) }

    func menuItem(_ strings: FinderNewFileStrings) -> FinderNewFileMenuItem {
        FinderNewFileMenuItem(id: id, title: menuTitle(strings), symbol: symbol)
    }

    private static func decoded(_ raw: String) -> [Self]? {
        guard raw.utf8.count <= 256 * 1024,
              let items = try? JSONDecoder().decode([Self].self, from: Data(raw.utf8)) else { return nil }
        return items.compactMap(\.normalized)
    }

    static func defaults(_ selection: String?) -> [Self] {
        let selected = Set(FinderNewFileKind.selection(selection))
        return FinderNewFileKind.allCases.map {
            Self(id: $0.itemID, suffix: $0.rawValue, builtIn: $0, enabled: selected.contains($0),
                 useBuiltInContent: true)
        }
    }

    /// A single ordered list is authoritative. The previous selection and
    /// custom-list preferences are read only for migration.
    static func items(_ raw: String, legacySelection: String? = nil,
                      legacyCustom: String = "[]") -> [Self] {
        let defaults = defaults(legacySelection)
        let stored = decoded(raw) ?? (defaults + (decoded(legacyCustom) ?? []).filter(\.canDelete))
        let reserved = Set(FinderNewFileKind.allCases.map(\.itemID))
        var seen = Set<UUID>()
        var customCount = 0
        var result: [Self] = []
        for item in stored {
            if item.canDelete {
                guard !reserved.contains(item.id), customCount < maximum else { continue }
            }
            guard seen.insert(item.id).inserted else { continue }
            if item.canDelete { customCount += 1 }
            result.append(item)
        }
        // Built-in entries cannot be deleted, including by a malformed or
        // incomplete settings backup. Restore any missing default entries.
        result += defaults.filter { !seen.contains($0.id) }
        return result
    }

    /// Match the panel editor's directional move: dropping onto a row
    /// below the source inserts after that row, and vice versa.
    static func reordered(_ items: [Self], moving source: UUID, to target: UUID) -> [Self] {
        guard source != target,
              let from = items.firstIndex(where: { $0.id == source }),
              let to = items.firstIndex(where: { $0.id == target }) else { return items }
        var updated = items
        let moved = updated.remove(at: from)
        updated.insert(moved, at: to)
        return updated
    }

    static func encode(_ items: [Self]) -> String {
        guard let data = try? JSONEncoder().encode(items) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct FinderNewFileMenuItem: Codable, Equatable {
    let id: UUID
    let title: String
    let symbol: String
}

struct FinderNewFileSnapshot: Codable {
    let enabled: Bool
    let language: String
    let entries: [FinderNewFileMenuItem]
}

/// A short-lived request carries the selected directory and a stable item ID.
/// The older built-in kind field is accepted only for wire compatibility.
/// The host separately authenticates the system-provided Apple event sender.
struct FinderNewFileRequest: Codable, Equatable {
    let id: UUID
    let kind: FinderNewFileKind?
    let customID: UUID?
    let directory: URL
    let createdAt: Date

    init(kind: FinderNewFileKind, directory: URL, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.customID = nil
        self.directory = directory
        self.createdAt = createdAt
    }

    init(customID: UUID, directory: URL, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.kind = nil
        self.customID = customID
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
        return (kind != nil) != (customID != nil) && age >= -2 && age <= Self.maximumAge
            && Self.isLocalDirectoryURL(directory)
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
              data.count <= 32_768 else { return nil }
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
