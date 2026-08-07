// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DiskImageInstallerSupport {
    static func imageURL(mountedAt mountURL: URL, hdiutilInfo: Data) -> URL? {
        guard let root = try? PropertyListSerialization.propertyList(from: hdiutilInfo,
                                                                    options: [],
                                                                    format: nil) as? [String: Any],
              let images = root["images"] as? [[String: Any]]
        else { return nil }

        let mountPath = normalizedPath(mountURL.path)
        let matches = images.compactMap { image -> String? in
            guard let path = image["image-path"] as? String,
                  path.hasPrefix("/"),
                  let entities = image["system-entities"] as? [[String: Any]],
                  entities.contains(where: {
                      guard let entityMount = $0["mount-point"] as? String else { return false }
                      return normalizedPath(entityMount) == mountPath
                  })
            else { return nil }
            return path
        }

        guard Set(matches).count == 1, let path = matches.first else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.pathExtension.caseInsensitiveCompare("dmg") == .orderedSame else { return nil }
        return url
    }

    static func destinationURL(for appURL: URL, applicationsURL: URL) -> URL? {
        let name = appURL.lastPathComponent
        guard appURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              !name.hasPrefix("."),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }

        let root = applicationsURL.standardizedFileURL
        let destination = root.appendingPathComponent(name, isDirectory: true).standardizedFileURL
        guard destination.deletingLastPathComponent() == root else { return nil }
        return destination
    }

    static func displayName(preferred: String?, appURL: URL) -> String {
        let fallback = appURL.deletingPathExtension().lastPathComponent
        let source = preferred?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? preferred! : fallback
        let words = source.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let flattened = words.joined(separator: " ").unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.illegalCharacters.contains($0)
        }
        let result = String(String.UnicodeScalarView(flattened).prefix(80))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? fallback : result
    }

    private static func normalizedPath(_ path: String) -> String {
        var existing = URL(fileURLWithPath: path).standardizedFileURL
        var missingComponents: [String] = []
        while existing.path != "/", !FileManager.default.fileExists(atPath: existing.path) {
            missingComponents.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        return missingComponents.reversed().reduce(existing.resolvingSymlinksInPath()) {
            $0.appendingPathComponent($1)
        }.path
    }
}
