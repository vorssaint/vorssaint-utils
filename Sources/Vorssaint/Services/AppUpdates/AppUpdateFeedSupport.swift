// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads update metadata only. Installation stays with the app that owns
/// the feed, including its signature, license and rollout checks.
enum AppUpdateFeedSupport {
    enum Format: Hashable { case appcast, manifest }
    struct Feed: Hashable {
        let url: URL
        let format: Format
    }
    struct Release {
        var version = ""
        var displayVersion = ""
        var minimumOS = ""
        var maximumOS = ""
        var minimumInstalledVersion = ""
        var channel = ""
        var hardware = ""
        var platform = ""
        var hasDownload = false
    }

    static let byteLimit = 2 * 1_024 * 1_024

    static func publicURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil, url.fragment == nil,
              let host = url.host?.lowercased(), host.contains("."),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              !host.contains(":"), host.contains(where: \.isLetter),
              host.split(separator: ".").allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } })
        else { return nil }
        return url
    }

    static func feed(info: [String: Any], configuration: String?) -> Feed? {
        if let value = info["SUFeedURL"] as? String, let url = publicURL(value) {
            return Feed(url: url, format: .appcast)
        }
        guard let configuration, configuration.utf8.count <= 64 * 1_024,
              let fields = scalars(configuration),
              fields["channel"] == nil || fields["channel"] == "latest",
              fields["private"] != "true", fields["token"] == nil,
              fields["requestHeaders"] == nil else { return nil }
        switch fields["provider"] {
        case "generic":
            guard let value = fields["url"], let base = publicURL(value),
                  base.query == nil else { return nil }
            return Feed(url: base.appendingPathComponent("latest-mac.yml"), format: .manifest)
        case "github":
            guard fields["host"] == nil || fields["host"] == "github.com",
                  let owner = fields["owner"], let repo = fields["repo"],
                  [owner, repo].allSatisfy({ value in
                      !value.isEmpty && value != "." && value != ".."
                          && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
                  }),
                  let url = publicURL("https://github.com/\(owner)/\(repo)/releases/latest/download/latest-mac.yml")
            else { return nil }
            return Feed(url: url, format: .manifest)
        default: return nil
        }
    }

    /// Only the flat scalar fields this metadata format defines are read.
    /// Nested configuration, tags and aliases never become request options.
    static func scalars(_ text: String) -> [String: String]? {
        var fields: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let first = line.first, !first.isWhitespace, first != "#",
                  let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            guard fields[key] == nil else { return nil }
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") {
                guard let decoded = try? JSONDecoder().decode(String.self, from: Data(value.utf8)) else { return nil }
                value = decoded
            } else if value.hasPrefix("'") {
                guard value.count >= 2, value.hasSuffix("'") else { return nil }
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            } else {
                if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]) }
                if let first = value.first, "&*!{|>[".contains(first) { continue }
            }
            fields[key] = value
        }
        return fields
    }

    static func releases(data: Data, format: Format) -> [Release]? {
        guard data.count <= byteLimit else { return nil }
        switch format {
        case .appcast:
            let delegate = AppcastReader()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            parser.delegate = delegate
            guard parser.parse(), delegate.isFeed, !delegate.releases.isEmpty else { return nil }
            return delegate.releases
        case .manifest:
            guard let text = String(data: data, encoding: .utf8),
                  let fields = scalars(text), let version = fields["version"],
                  fields["files"] != nil || fields["path"] != nil else { return nil }
            return [Release(version: version, displayVersion: version,
                            minimumOS: fields["minimumSystemVersion"] ?? "", hasDownload: true)]
        }
    }

    static func update(app: AppUpdatesSupport.InstalledApp, releases: [Release],
                       format: Format, operatingSystemVersion: String,
                       kernelVersion: String, architecture: String) -> AppUpdatesSupport.Item? {
        guard let installed = comparableInstalledVersion(app, format: format) else { return nil }
        let systemVersion = format == .manifest ? kernelVersion : operatingSystemVersion
        let eligible = releases.filter { release in
            let display = release.displayVersion.isEmpty ? release.version : release.displayVersion
            return release.hasDownload && release.channel.isEmpty
                && stableVersion(display) && stableVersion(release.version)
                && (release.platform.isEmpty || release.platform == "macos")
                && (release.hardware.isEmpty || release.hardware == architecture)
                && (release.minimumOS.isEmpty || AppUpdatesSupport.compare(systemVersion, release.minimumOS) != .orderedAscending)
                && (release.maximumOS.isEmpty || AppUpdatesSupport.compare(systemVersion, release.maximumOS) != .orderedDescending)
                && (release.minimumInstalledVersion.isEmpty || AppUpdatesSupport.compare(installed, release.minimumInstalledVersion) != .orderedAscending)
                && AppUpdatesSupport.isNewer(release.version, than: installed)
        }
        guard let latest = eligible.max(by: { AppUpdatesSupport.compare($0.version, $1.version) == .orderedAscending }) else { return nil }
        let display = latest.displayVersion.isEmpty ? latest.version : latest.displayVersion
        let sameDisplay = AppUpdatesSupport.compare(display, app.version) == .orderedSame
        return AppUpdatesSupport.Item(
            id: "\(AppUpdatesSupport.Source.onlineCatalog.rawValue):\(app.path)",
            source: .onlineCatalog, name: app.name,
            installedVersion: sameDisplay ? "\(app.version) (\(installed))" : app.version,
            latestVersion: sameDisplay ? "\(display) (\(latest.version))" : display,
            token: nil, bundlePath: app.path, storePage: nil)
    }

    static func comparableInstalledVersion(_ app: AppUpdatesSupport.InstalledApp, format: Format) -> String? {
        let version = format == .appcast && !app.buildVersion.isEmpty ? app.buildVersion : app.version
        return stableVersion(version) ? version : nil
    }

    private static func stableVersion(_ value: String) -> Bool {
        !value.isEmpty && value.first?.isNumber == true
            && value.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
    }
}

private final class AppcastReader: NSObject, XMLParserDelegate {
    var releases: [AppUpdateFeedSupport.Release] = []
    var isFeed = false
    private var path: [String] = []
    private var item: AppUpdateFeedSupport.Release?
    private var text = ""
    private let metadataNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        path.append(element)
        guard path.count <= 32, releases.count < 4_096 else { parser.abortParsing(); return }
        if path == ["rss", "channel"] { isFeed = true }
        if path == ["rss", "channel", "item"] { item = AppUpdateFeedSupport.Release() }
        text = ""
        guard path == ["rss", "channel", "item", "enclosure"] else { return }
        func attribute(_ key: String) -> String? {
            attributes["sparkle:\(key)"] ?? attributes.first { $0.key.hasSuffix(":\(key)") }?.value
        }
        item?.platform = attribute("os") ?? ""
        guard attribute("deltaFrom") == nil,
              attribute("os") == nil || attribute("os") == "macos",
              let url = attributes["url"], AppUpdateFeedSupport.publicURL(url) != nil else { return }
        item?.hasDownload = true
        if item?.version.isEmpty == true, let version = attribute("version") { item?.version = version }
        if item?.displayVersion.isEmpty == true, let display = attribute("shortVersionString") { item?.displayVersion = display }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard path.count == 4, let field = path.last,
              ["version", "shortVersionString", "minimumSystemVersion", "maximumSystemVersion",
               "minimumUpdateVersion", "channel", "hardwareRequirements", "link"].contains(field) else { return }
        guard text.utf8.count + string.utf8.count <= 64 * 1_024 else { parser.abortParsing(); return }
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let value = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: value) }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.count == 4, item != nil {
            if namespaceURI == metadataNamespace {
                switch element {
                case "version": item?.version = value
                case "shortVersionString": item?.displayVersion = value
                case "minimumSystemVersion": item?.minimumOS = value
                case "maximumSystemVersion": item?.maximumOS = value
                case "minimumUpdateVersion": item?.minimumInstalledVersion = value
                case "channel": item?.channel = value
                case "hardwareRequirements": item?.hardware = value
                default: break
                }
            } else if element == "link", AppUpdateFeedSupport.publicURL(value) != nil {
                item?.hasDownload = true
            }
        }
        if path == ["rss", "channel", "item"], let item {
            if !item.version.isEmpty { releases.append(item) }
            self.item = nil
        }
        path.removeLast()
        text = ""
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        parser.abortParsing()
    }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        parser.abortParsing()
    }
}
