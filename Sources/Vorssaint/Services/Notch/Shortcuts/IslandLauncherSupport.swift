// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Emre Aribulan
import Foundation

struct IslandLauncherEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var path: String
    var bookmark: Data
    var website: String?

    init(id: UUID = UUID(), name: String, path: String, bookmark: Data = Data(), website: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.website = website
    }

    var websiteURL: URL? { website.flatMap(IslandLauncherSupport.websiteURL) }
}

enum IslandLauncherSupport {
    static let maximumItems = 100
    static let maximumDataSize = 1_048_576

    static func sanitized(_ entries: [IslandLauncherEntry]) -> [IslandLauncherEntry] {
        var ids = Set<UUID>()
        var targets = Set<String>()
        var encodedSize = 2
        return entries.prefix(500).compactMap { item in
            var item = item
            let target: String
            let fallback: String
            if let website = item.website {
                guard let url = websiteURL(website) else { return nil }
                item.website = url.absoluteString
                item.path = ""
                item.bookmark = Data()
                target = "web:" + url.absoluteString
                fallback = url.host ?? "Website"
            } else {
                let url = URL(fileURLWithPath: item.path).standardizedFileURL
                guard item.path.hasPrefix("/"), item.path.utf8.count <= 8192, url.pathExtension.lowercased() == "app",
                    item.bookmark.count <= 65_536
                else { return nil }
                item.path = url.path
                target = "app:" + url.path
                fallback = url.deletingPathExtension().lastPathComponent
            }
            guard !ids.contains(item.id), !targets.contains(target), targets.count < maximumItems else { return nil }
            item.name = String(
                item.name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
                    .map(String.init).joined().trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
            if item.name.isEmpty { item.name = String(fallback.prefix(100)) }
            guard let data = try? JSONEncoder().encode(item), encodedSize + data.count + 1 <= maximumDataSize else {
                return nil
            }
            encodedSize += data.count + 1
            ids.insert(item.id)
            targets.insert(target)
            return item
        }
    }

    /// Only ordinary web destinations; never executable/custom schemes or embedded credentials.
    static func websiteURL(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 8192,
            !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        let hostWithPort = value.range(of: "^[^/?#]+:[0-9]+([/?#]|$)", options: .regularExpression) != nil
        let explicitScheme = !hostWithPort && URLComponents(string: value)?.scheme != nil
        guard var parts = URLComponents(string: explicitScheme ? value : "https://" + value),
            let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = parts.host?.lowercased(), !host.isEmpty,
            !host.contains(where: { $0.isWhitespace }), parts.user == nil, parts.password == nil,
            parts.port.map({ (1...65535).contains($0) }) ?? true
        else { return nil }
        parts.scheme = scheme
        parts.host = host
        if parts.port == (scheme == "https" ? 443 : 80) { parts.port = nil }
        if parts.path.isEmpty { parts.path = "/" }
        return parts.url
    }

    static func decode(_ data: Data) -> [IslandLauncherEntry] {
        guard data.count <= maximumDataSize,
            let entries = try? JSONDecoder().decode([IslandLauncherEntry].self, from: data)
        else { return [] }
        return sanitized(entries)
    }
}
