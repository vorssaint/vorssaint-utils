// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import UniformTypeIdentifiers

enum DefaultAppsTests {
    static func run(_ suite: TestSuite) {
        let info: [String: Any] = ["CFBundleDocumentTypes": [
            ["LSItemContentTypes": ["public.data", "public.item", "public.content", "public.folder",
                                    "public.composite-content", "public.audio", "public.mp3"],
             "CFBundleTypeExtensions": ["mp3", "png", "*", "notaknownextension"]],
            ["CFBundleTypeRole": "None", "LSItemContentTypes": ["public.zip-archive"]],
            ["LSHandlerRank": "None", "CFBundleTypeExtensions": ["json"]],
            ["CFBundleTypeRole": "Viewer", "LSItemContentTypes": ["com.adobe.pdf", "public.png"]],
        ]]
        suite.expect(DefaultAppsSupport.declaredTypes(infoDictionary: info).map(\.identifier)
                == ["public.mp3", "public.png", "com.adobe.pdf"],
               "declared formats keep declaration order, merge identifiers with extensions, and drop "
               + "catch-all roots, unknown extensions and types the app declines to open")
        suite.expect(DefaultAppsSupport.declaredTypes(infoDictionary: [:]).isEmpty
                && DefaultAppsSupport.declaredTypes(infoDictionary: ["CFBundleDocumentTypes": "junk"]).isEmpty,
               "an app without document types offers no formats")

        let expected: [(String, DefaultAppsSupport.Category)] = [
            ("mp3", .audio), ("flac", .audio), ("mp4", .video), ("mov", .video), ("png", .image),
            ("svg", .image), ("txt", .text), ("swift", .text), ("pdf", .text), ("docx", .text),
            ("zip", .archive), ("ttf", .other),
        ]
        for (ext, category) in expected {
            let type = UTType(filenameExtension: ext)!
            suite.expect(DefaultAppsSupport.category(of: type) == category,
                   ".\(ext) is grouped as \(category)")
        }

        for lang in AppLanguage.allCases {
            let strings = FeatureStrings.defaultApps(lang)
            suite.expect(String(format: strings.currentFormat, "X").contains("X")
                    && String(format: strings.alreadyFormat, "X").contains("X")
                    && String(format: strings.moreFormat, 7).contains("7")
                    && String(format: strings.selectedFormat, 7).contains("7"),
                   "default apps formats fill in their value in \(lang)")
            suite.expect(DefaultAppsSupport.Category.allCases.allSatisfy { !strings.name(of: $0).isEmpty }
                    && !strings.hubDescription.isEmpty && !strings.confirmNote.isEmpty,
                   "default apps strings are filled in for \(lang)")
        }
    }
}
