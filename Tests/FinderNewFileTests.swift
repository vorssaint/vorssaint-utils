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
            let strings = FinderNewFileStrings.localized(language.rawValue)
            suite.expect(!strings.title.isEmpty && !strings.description.isEmpty
                         && !strings.manage.isEmpty && !strings.error.isEmpty,
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
