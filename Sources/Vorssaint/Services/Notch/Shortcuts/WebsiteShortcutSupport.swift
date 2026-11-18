// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Emre Aribulan
import Foundation

enum WebsiteShortcutSupport {
    static func origin(of url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = "/"
        parts.query = nil
        parts.fragment = nil
        return parts.url.flatMap { IslandLauncherSupport.websiteURL($0.absoluteString) }
    }

    /// Extract icon declarations, resolving relative URLs against the page base.
    static func iconCandidates(html: String, pageURL: URL) -> [URL] {
        let stripped = html.replacingOccurrences(
            of: "(?is)<!--.*?-->|<script\\b[^>]*>.*?</script\\s*>|<style\\b[^>]*>.*?</style\\s*>",
            with: "", options: .regularExpression)
        let tagPattern = "(?is)<(link|base)\\b(?:[^\"'>]|\"[^\"]*\"|'[^']*')*>"
        guard let regex = try? NSRegularExpression(pattern: tagPattern) else { return [] }
        var base = pageURL
        var sawBase = false
        var links: [[String: String]] = []
        for match in regex.matches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)).prefix(200) {
            guard let range = Range(match.range, in: stripped), let nameRange = Range(match.range(at: 1), in: stripped)
            else { continue }
            let attributes = attributes(String(stripped[range]))
            if stripped[nameRange].lowercased() == "base", !sawBase, let href = attributes["href"],
                let url = URL(string: href, relativeTo: pageURL)?.absoluteURL,
                let safe = IslandLauncherSupport.websiteURL(url.absoluteString)
            {
                base = safe
                sawBase = true
            } else if stripped[nameRange].lowercased() == "link" {
                links.append(attributes)
            }
        }
        var seen = Set<URL>()
        let icons = links.enumerated().compactMap { index, attributes -> (Int, Int, URL)? in
            let rel = Set(
                (attributes["rel"] ?? "").lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init))
            guard
                rel.contains("icon") || rel.contains("apple-touch-icon")
                    || rel.contains("apple-touch-icon-precomposed"),
                let href = attributes["href"], let url = URL(string: href, relativeTo: base)?.absoluteURL,
                let safe = IslandLauncherSupport.websiteURL(url.absoluteString), seen.insert(safe).inserted
            else { return nil }
            let size =
                (attributes["sizes"] ?? "").split(separator: " ").compactMap {
                    Int($0.split(separator: "x").first ?? "")
                }.max() ?? 0
            let raster = (attributes["type"] ?? "").lowercased().contains("svg") ? 0 : 1000
            return (raster + min(size, 512), index, safe)
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }.map(\.2)
        var result = Array(icons.prefix(6))
        if let origin = origin(of: pageURL) {
            for path in ["favicon.ico", "apple-touch-icon.png"] {
                let url = origin.appendingPathComponent(path)
                if !result.contains(url) { result.append(url) }
            }
        }
        return result
    }

    private static func attributes(_ tag: String) -> [String: String] {
        let pattern = "(?is)([a-z][a-z0-9:_-]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var values: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let key = Range(match.range(at: 1), in: tag),
                let value = (2...4).compactMap({ Range(match.range(at: $0), in: tag) }).first
            else { continue }
            let name = tag[key].lowercased()
            if values[name] == nil { values[name] = entities(String(tag[value])) }
        }
        return values
    }

    private static func entities(_ value: String) -> String {
        var result = value
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let numberRange = Range(match.range(at: 1), in: result),
                    let range = Range(match.range, in: result)
                else { continue }
                let number = String(result[numberRange])
                let code = number.hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
                if let code, let scalar = UnicodeScalar(code) { result.replaceSubrange(range, with: String(scalar)) }
            }
        }
        for (entity, text) in [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: text)
        }
        return result
    }
}
