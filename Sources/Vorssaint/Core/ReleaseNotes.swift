// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ReleaseNotes {
    let version: String
    let date: String?
    let sections: [ReleaseNoteSection]

    static var current: ReleaseNotes {
        notes(for: AppInfo.version)
    }

    static func notes(for version: String, changelog: String? = bundledChangelog()) -> ReleaseNotes {
        guard let changelog,
              let parsed = parse(version: version, changelog: changelog) else {
            return ReleaseNotes(version: version, date: nil, sections: [])
        }
        return parsed
    }

    /// Every version listed in the changelog, in document order (newest first).
    /// Used to surface the releases a user skipped between updates.
    static func allVersions(changelog: String? = bundledChangelog()) -> [String] {
        guard let changelog else { return [] }
        return changelog
            .components(separatedBy: .newlines)
            .compactMap { header(in: $0)?.version }
    }

    /// Raw markdown body of a version's changelog section (everything between its
    /// `## [version]` header and the next one), so the Developer build can feed
    /// the update preview real notes. Empty when the version is absent.
    static func rawNotes(for version: String, changelog: String? = bundledChangelog()) -> String {
        guard let changelog else { return "" }
        let lines = changelog.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { header(in: $0)?.version == version }) else { return "" }
        var body: [String] = []
        for line in lines.dropFirst(start + 1) {
            if line.hasPrefix("## [") { break }
            body.append(line)
        }
        return body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bundledChangelog() -> String? {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func parse(version: String, changelog: String) -> ReleaseNotes? {
        let lines = changelog.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { header(in: $0)?.version == version }),
              let header = header(in: lines[start]) else { return nil }

        var sections: [ReleaseNoteSection] = []
        var currentTitle = ""
        var currentItems: [ReleaseNoteItem] = []
        var currentParagraph: [String] = []

        func flushParagraph() {
            guard !currentParagraph.isEmpty else { return }
            let paragraph = clean(currentParagraph.joined(separator: " "))
            if !paragraph.isEmpty {
                currentItems.append(.paragraph(paragraph))
            }
            currentParagraph.removeAll()
        }

        func flushSection() {
            flushParagraph()
            defer { currentItems.removeAll() }
            guard !currentItems.isEmpty, shouldDisplaySection(currentTitle) else { return }
            sections.append(ReleaseNoteSection(title: currentTitle, items: currentItems))
        }

        for rawLine in lines.dropFirst(start + 1) {
            if rawLine.hasPrefix("## [") { break }
            if rawLine.hasPrefix("### ") {
                flushSection()
                currentTitle = String(rawLine.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                continue
            }

            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed.hasPrefix("- ") {
                flushParagraph()
                currentItems.append(.bullet(clean(String(trimmed.dropFirst(2)))))
            } else if let image = image(in: trimmed) {
                flushParagraph()
                currentItems.append(.image(image))
            } else if rawLine.hasPrefix("  "), !currentItems.isEmpty, !trimmed.isEmpty,
                      case let .bullet(text) = currentItems[currentItems.count - 1] {
                currentItems[currentItems.count - 1] = .bullet(text + " " + clean(trimmed))
            } else if !currentTitle.isEmpty {
                currentParagraph.append(trimmed)
            }
        }
        flushSection()

        return ReleaseNotes(version: header.version, date: header.date, sections: sections)
    }

    private static func header(in line: String) -> (version: String, date: String?)? {
        guard line.hasPrefix("## [") else { return nil }
        let versionStart = line.index(line.startIndex, offsetBy: 4)
        guard let close = line[versionStart...].firstIndex(of: "]") else { return nil }
        let version = String(line[versionStart..<close])
        let suffixStart = line.index(after: close)
        let suffix = line[suffixStart...]
        let date = suffix.range(of: " - ").map { range in
            String(suffix[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return (version, date)
    }

    private static func clean(_ text: String) -> String {
        var result = text
        while let labelStart = result.range(of: "["),
              let labelEnd = result[labelStart.upperBound...].range(of: "]"),
              let linkStart = result[labelEnd.upperBound...].range(of: "("),
              linkStart.lowerBound == labelEnd.upperBound,
              let linkEnd = result[linkStart.upperBound...].range(of: ")") {
            let label = String(result[labelStart.upperBound..<labelEnd.lowerBound])
            result.replaceSubrange(labelStart.lowerBound..<linkEnd.upperBound, with: label)
        }
        return result.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func image(in line: String) -> ReleaseNoteImage? {
        guard line.hasPrefix("!["),
              let altEnd = line[line.index(line.startIndex, offsetBy: 2)...].firstIndex(of: "]") else {
            return nil
        }
        let linkStartIndex = line.index(after: altEnd)
        guard linkStartIndex < line.endIndex,
              line[linkStartIndex] == "(",
              let linkEnd = line[line.index(after: linkStartIndex)...].firstIndex(of: ")") else {
            return nil
        }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<altEnd])
        let path = String(line[line.index(after: linkStartIndex)..<linkEnd])
        guard !path.isEmpty else { return nil }
        return ReleaseNoteImage(alt: alt, path: path)
    }

    private static func shouldDisplaySection(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized != "website" && normalized != "links"
    }
}

struct ReleaseNoteSection {
    let title: String
    let items: [ReleaseNoteItem]

    var bulletItems: [String] {
        items.compactMap {
            if case let .bullet(text) = $0 { return text }
            return nil
        }
    }

    var paragraphItems: [String] {
        items.compactMap {
            if case let .paragraph(text) = $0 { return text }
            return nil
        }
    }
}

enum ReleaseNoteItem: Equatable {
    case paragraph(String)
    case bullet(String)
    case image(ReleaseNoteImage)
}

struct ReleaseNoteImage: Equatable {
    let alt: String
    let path: String
}
