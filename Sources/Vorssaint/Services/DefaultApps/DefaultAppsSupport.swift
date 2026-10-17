// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import UniformTypeIdentifiers

/// Which file formats an app says it opens, read from its Info.plist and
/// grouped for the Default apps page.
enum DefaultAppsSupport {
    enum Category: CaseIterable {
        case video, audio, image, text, archive, other
    }

    /// Checked top to bottom. Some formats sit in two families (FLAC is also
    /// audiovisual content, SVG is also text), and the first match wins.
    private static let categoryRules: [(Category, [UTType])] = [
        (.audio, [.audio]),
        (.video, [.movie, .audiovisualContent]),
        (.image, [.image]),
        (.text, [.text, .sourceCode, .pdf, .compositeContent, .presentation, .spreadsheet]),
        (.archive, [.archive]),
    ]

    static func category(of type: UTType) -> Category {
        categoryRules.first { _, roots in roots.contains { type.conforms(to: $0) } }?.0 ?? .other
    }

    /// The concrete types in the app's document types, deduplicated and in
    /// declaration order. Roots like public.data or public.folder carry no
    /// filename extension, so requiring one drops every catch-all, and an
    /// extension macOS does not know (or "*") only yields a dynamic type.
    /// A declaration whose role or rank is None says the app does not open it.
    static func declaredTypes(infoDictionary: [String: Any]) -> [UTType] {
        let documents = infoDictionary["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        var types: [UTType] = []
        for document in documents {
            if document["CFBundleTypeRole"] as? String == "None"
                || document["LSHandlerRank"] as? String == "None" { continue }
            let byIdentifier = (document["LSItemContentTypes"] as? [String] ?? []).compactMap { UTType($0) }
            let byExtension = (document["CFBundleTypeExtensions"] as? [String] ?? [])
                .compactMap { UTType(filenameExtension: $0) }
            for type in byIdentifier + byExtension
            where !type.isDynamic && type.preferredFilenameExtension != nil
                && seen.insert(type.identifier).inserted {
                types.append(type)
            }
        }
        return types
    }
}
