// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderNewFileTests {
    static func run(_ suite: TestSuite) {
        suite.expect(FinderNewFileKind.selection(nil) == FinderNewFileKind.defaultKinds,
                     "new file defaults include Office formats")
        suite.expect(FinderNewFileKind.selection("xlsx,unknown,txt,txt") == [.text, .excel],
                     "file choices are sanitized and stable")
        suite.expect(FinderNewFileKind.selection("").isEmpty, "no selected file types stays empty")
        suite.expect(FinderNewFileStrings.supportedCodes == Set(AppLanguage.allCases.map(\.rawValue)),
                     "Finder new file supports every app language")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.finderNewFile(language)
            suite.expect(strings.title == FinderNewFileStrings.localized(language.rawValue).title,
                         "host and extension share the same Finder menu title: \(language)")
            suite.expect(!strings.title.isEmpty && !strings.description.isEmpty
                         && !strings.enable.isEmpty && !strings.page.isEmpty && !strings.text.isEmpty
                         && !strings.cancel.isEmpty && !strings.manage.isEmpty && !strings.error.isEmpty
                         && !strings.extensionName.isEmpty && !strings.extensionEnabled.isEmpty
                         && !strings.extensionDisabled.isEmpty && !strings.extensionHelp.isEmpty
                         && strings.extensionEnabled != strings.extensionDisabled,
                         "localized Finder labels are complete: \(language)")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-new-file-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let first = try FinderNewFileCreator.create(.text, in: directory, templates: nil)
            try Data("keep".utf8).write(to: first)
            let second = try FinderNewFileCreator.create(.text, in: directory, templates: nil)
            suite.expect(first.lastPathComponent == "Untitled.txt"
                         && second.lastPathComponent == "Untitled 2.txt",
                         "repeated creation gets a unique filename")
            suite.expect(try Data(contentsOf: first) == Data("keep".utf8), "existing content is preserved")
            suite.expect(try Data(contentsOf: second).isEmpty, "new text is empty")
            let json = try FinderNewFileCreator.create(.json, in: directory, templates: nil)
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: json))
            suite.expect((value as? [String: Any])?.isEmpty == true, "JSON starts as a valid empty object")

            let templates = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/FinderNewFileTemplates", isDirectory: true)
            for kind in FinderNewFileKind.allCases where kind.usesTemplate {
                let file = try FinderNewFileCreator.create(kind, in: directory, templates: templates)
                let source = try Data(contentsOf: templates.appendingPathComponent("Blank.\(kind.rawValue)"))
                let actual = try Data(contentsOf: file)
                suite.expect(!source.isEmpty && actual == source, "template copied without alteration: \(kind)")
            }
            do {
                _ = try FinderNewFileCreator.create(.excel, in: directory, templates: nil)
                suite.expect(false, "missing document template must not create an empty Office file")
            } catch {
                suite.expect(true, "missing document template rejected")
            }
            var custom = FinderNewFileCustomItem(title: "Python", filename: "main", suffix: ".py")
            guard let normalized = custom.normalized else {
                suite.expect(false, "valid custom item"); return
            }
            custom = normalized
            let customFirst = try FinderNewFileCreator.create(custom, in: directory, templateDirectory: nil)
            let customSecond = try FinderNewFileCreator.create(custom, in: directory, templateDirectory: nil)
            suite.expect(customFirst.lastPathComponent == "main.py" && customSecond.lastPathComponent == "main 2.py",
                         "custom filename and suffix use exclusive numbered creation")
            suite.expect(try Data(contentsOf: customFirst).isEmpty, "custom blank file is empty")
            var invalid = custom
            invalid.filename = "../outside"
            suite.expect(invalid.normalized == nil, "reject path traversal in custom filename")
            invalid = custom
            invalid.suffix = "/txt"
            suite.expect(invalid.normalized == nil, "reject path separators in custom suffix")
            suite.expect(FinderNewFileCustomItem.decode(FinderNewFileCustomItem.encode([custom, custom, invalid])) == [custom],
                         "custom settings round trip and reject duplicate/invalid entries")
            let customRequest = FinderNewFileRequest(customID: custom.id, directory: directory)
            suite.expect(customRequest.url.flatMap { FinderNewFileRequest.decode($0) } == customRequest,
                         "custom request carries a registered item ID")
            let store = directory.appendingPathComponent("templates")
            let source = directory.appendingPathComponent("source.txt")
            let contents = Data("template contents".utf8)
            try contents.write(to: source)
            custom.template = try FinderNewFileTemplateStore.importFile(source, into: store, container: directory)
            try FileManager.default.removeItem(at: source)
            let copy = try FinderNewFileCreator.create(custom, in: directory, templateDirectory: store)
            suite.expect(try Data(contentsOf: copy) == contents, "imported template survives source removal")
            FinderNewFileTemplateStore.remove(custom.template!, from: store)
            do {
                _ = try FinderNewFileCreator.create(custom, in: directory, templateDirectory: store)
                suite.expect(false, "missing custom template must not silently create an empty file")
            } catch {
                suite.expect(true, "missing custom template rejected")
            }
            let request = FinderNewFileRequest(kind: .excel, directory: directory)
            if let url = request.url {
                suite.expect(FinderNewFileRequest.decode(url) == request, "creation request round trips")
                var oldRoute = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                oldRoute.host = "confirm"
                suite.expect(FinderNewFileRequest.decode(oldRoute.url!) == nil, "old confirmation route rejected")
                oldRoute.host = "queued"
                suite.expect(FinderNewFileRequest.decode(oldRoute.url!) == nil, "old queue route rejected")
                var invalid = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                invalid.queryItems?.append(URLQueryItem(name: "extra", value: "1"))
                suite.expect(FinderNewFileRequest.decode(invalid.url!) == nil, "unexpected URL fields rejected")
            } else {
                suite.expect(false, "creation URL encodes")
            }
            var replay = FinderNewFileReplayGuard()
            suite.expect(replay.accept(request), "fresh request accepted")
            suite.expect(!replay.accept(request), "duplicate request rejected")
            suite.expect(!replay.accept(FinderNewFileRequest(kind: .text, directory: directory,
                                                            createdAt: Date(timeIntervalSinceNow: -120))),
                         "expired requests rejected by replay guard")
            suite.expect(!FinderNewFileRequest(kind: .text, directory: directory,
                                                createdAt: Date(timeIntervalSinceNow: -120)).isValid(),
                         "expired request rejected")
            suite.expect(!FinderNewFileRequest.isLocalDirectoryURL(URL(string: "https://example.com")!),
                         "remote URL rejected")
        } catch {
            suite.expect(false, "new file fixture failed: \(error)")
        }
    }
}
