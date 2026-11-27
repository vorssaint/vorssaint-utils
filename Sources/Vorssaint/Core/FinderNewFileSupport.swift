// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

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

/// The URL is a wake-up signal, not authority to write a file. Only a one-use
/// request in the protected, same-team app group can authorize direct creation.
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

    enum Route {
        case queued(UUID)
        case confirmation(FinderNewFileRequest)
    }

    var wakeURL: URL? {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = "queued"
        parts.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        return parts.url
    }

    var confirmationURL: URL? {
        guard isValid(), let data = try? JSONEncoder().encode(self),
              data.count <= Self.maximumPayloadBytes else { return nil }
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = "confirm"
        parts.queryItems = [URLQueryItem(name: "request", value: data.base64EncodedString())]
        return parts.url
    }

    static func route(_ url: URL, now: Date = Date()) -> Route? {
        guard url.absoluteString.utf8.count <= 32_768,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == scheme, parts.path.isEmpty, parts.fragment == nil,
              parts.user == nil, parts.password == nil, parts.port == nil,
              let query = parts.queryItems, query.count == 1,
              let value = query[0].value else { return nil }
        switch (parts.host, query[0].name) {
        case ("queued", "id"):
            return UUID(uuidString: value).map(Route.queued)
        case ("confirm", "request"):
            guard let data = Data(base64Encoded: value), data.count <= maximumPayloadBytes,
                  let request = try? JSONDecoder().decode(Self.self, from: data),
                  request.isValid(now: now) else { return nil }
            return .confirmation(request)
        default: return nil
        }
    }
}

/// The containing app and its sandboxed extension share only menu preferences
/// and short-lived requests. No directory paths are exported in settings backup.
enum FinderNewFileExchange {
    static var groupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "FinderNewFileAppGroup") as? String
    }

    static var supportsTrustedRequests: Bool {
        // macOS 15 protects same-team app group containers even when the
        // containing application itself is not sandboxed.
        if #available(macOS 15, *) { return groupIdentifier != nil }
        return false
    }

    private static var root: URL? {
        guard let groupIdentifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("FinderNewFile", isDirectory: true)
    }

    static func publish(_ snapshot: FinderNewFileSnapshot) throws {
        guard let root else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent("menu.json"), options: .atomic)
    }

    static func snapshot() -> FinderNewFileSnapshot? {
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent("menu.json")),
              data.count <= 4_096 else { return nil }
        return try? JSONDecoder().decode(FinderNewFileSnapshot.self, from: data)
    }

    private static func requestsDirectory() throws -> URL {
        guard let root else { throw CocoaError(.fileNoSuchFile) }
        let directory = root.appendingPathComponent("Requests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func enqueue(_ request: FinderNewFileRequest) throws {
        guard supportsTrustedRequests, request.isValid() else { throw CocoaError(.fileWriteNoPermission) }
        let directory = try requestsDirectory()
        let manager = FileManager.default
        // Bound storage; expired requests left by a failed launch are discarded.
        let entries = try manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
        var pending = 0
        for entry in entries where entry.pathExtension == "json"
            && UUID(uuidString: entry.deletingPathExtension().lastPathComponent) != nil {
            guard let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            if let modified = values.contentModificationDate,
               Date().timeIntervalSince(modified) > FinderNewFileRequest.maximumAge {
                try? manager.removeItem(at: entry)
            } else {
                pending += 1
            }
        }
        guard pending < 64 else { throw CocoaError(.fileWriteUnknown) }
        let data = try JSONEncoder().encode(request)
        guard data.count <= FinderNewFileRequest.maximumPayloadBytes else { throw CocoaError(.fileWriteUnknown) }
        // The wake signal is sent only after the exclusive write completes.
        try data.write(to: directory.appendingPathComponent(request.id.uuidString + ".json"),
                       options: .withoutOverwriting)
    }

    static func consume(_ id: UUID) -> FinderNewFileRequest? {
        guard supportsTrustedRequests, let root else { return nil }
        let url = root.appendingPathComponent("Requests", isDirectory: true)
            .appendingPathComponent(id.uuidString + ".json")
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= FinderNewFileRequest.maximumPayloadBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        // Consume before acting. Replayed wake URLs cannot create another file.
        do { try FileManager.default.removeItem(at: url) } catch { return nil }
        guard let request = try? JSONDecoder().decode(FinderNewFileRequest.self, from: data),
              request.id == id, request.isValid() else { return nil }
        return request
    }
}
