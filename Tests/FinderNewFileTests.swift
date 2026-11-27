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
                         && !strings.manage.isEmpty && !strings.localNote.isEmpty,
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
            if let url = request.confirmationURL, case .confirmation(let decoded)? = FinderNewFileRequest.route(url) {
                suite.expect(decoded == request, "confirmation URL round trips")
            } else {
                suite.expect(false, "confirmation URL decodes")
            }
            if let url = request.wakeURL, case .queued(let id)? = FinderNewFileRequest.route(url) {
                suite.expect(id == request.id, "wake URL carries only a UUID")
            } else {
                suite.expect(false, "wake URL decodes")
            }
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
