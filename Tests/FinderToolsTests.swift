// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderToolsTests {
    static func run(_ suite: TestSuite) {
        suite.run("Finder tools selection boundary") {
            let file = URL(fileURLWithPath: "/tmp/日本語 & report.txt")
            let request = FinderToolsRequest(selection: [file], directory: nil)
            suite.expect(request.url.flatMap(FinderToolsRequest.init(url:)) == request,
                         "Unicode selection survives the extension handoff")
            suite.expect(FinderToolsRequest(selection: [], directory: URL(fileURLWithPath: "/tmp")).url != nil,
                         "background-folder context does not require a selected item")
            suite.expect(FinderToolsRequest(selection: [], directory: nil).url == nil,
                         "empty requests are rejected")
            suite.expect(FinderToolsRequest(selection: [URL(string: "https://example.com")!], directory: nil).url == nil,
                         "remote URLs cannot become local file operations")
            suite.expect(FinderToolsRequest(selection: Array(repeating: file, count: 129), directory: nil).url == nil,
                         "oversized selections are rejected")
            for raw in ["\(FinderToolsRequest.scheme)://selection?payload=e30=",
                        "\(FinderToolsRequest.scheme)://selection?payload=invalid",
                        "\(FinderToolsRequest.scheme)://delete?payload=e30="] {
                suite.expect(FinderToolsRequest(url: URL(string: raw)!) == nil,
                             "malformed handoff cannot open an operation: \(raw)")
            }
            if let valid = request.url {
                suite.expect(FinderToolsRequest(url: URL(string: valid.absoluteString + "&action=delete")!) == nil,
                             "additional command parameters are rejected")
            }
        }
        suite.run("Finder tools operations") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: root) }
                let token = FinderToolsCancellation()
                var request = FinderToolsOperation(action: .pasteText, selection: [], destination: root,
                    name: "note.txt", clipboardText: "Hello")
                let first = try FinderToolsExecutor.execute(request, cancellation: token)
                request.uniqueNames = false
                do {
                    _ = try FinderToolsExecutor.execute(request, cancellation: token)
                    suite.expect(false, "creation must report an existing name when numbering is disabled")
                } catch FinderFileActionError.destinationExists {
                    let contents = try String(contentsOf: first.outputs[0], encoding: .utf8)
                    suite.expect(contents == "Hello",
                                 "disabling numbered names preserves the existing file")
                }
                request.uniqueNames = true
                let second = try FinderToolsExecutor.execute(request, cancellation: token)
                suite.expect(first.outputs.first != second.outputs.first,
                             "repeated clipboard saves keep both files")
                request = FinderToolsOperation(action: .pasteText, selection: [], destination: root,
                    name: "empty.txt", clipboardText: nil)
                do {
                    _ = try FinderToolsExecutor.execute(request, cancellation: token)
                    suite.expect(false, "empty clipboard should reject creation")
                } catch {
                    suite.expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("empty.txt").path),
                                 "empty clipboard creates no file")
                }
                let missing = root.appendingPathComponent("missing")
                request = FinderToolsOperation(action: .sha256, selection: [first.outputs[0], missing],
                    destination: nil, name: "", clipboardText: nil)
                let mixed = try FinderToolsExecutor.execute(request, cancellation: token)
                suite.expect(mixed.text != nil && mixed.failures.map(\.url) == [missing],
                             "partial inspection retains successful output and identifies the failed item")
                token.cancel()
                do {
                    _ = try FinderToolsExecutor.execute(request, cancellation: token)
                    suite.expect(false, "cancelled operations must not start")
                } catch is CancellationError { suite.expect(true, "cancelled operation stopped") }
            } catch { suite.expect(false, "operation fixture failed: \(error)") }
        }
        suite.run("Finder tools localization") {
            for language in AppLanguage.allCases {
                let titles = FinderToolsAction.allCases.map { $0.title(languageCode: language.rawValue) }
                suite.expect(titles.allSatisfy { !$0.isEmpty } && Set(titles).count == titles.count,
                             "all actions have distinct nonempty labels in \(language.rawValue)")
                suite.expect(!FinderToolsStrings.localized(language).open.isEmpty,
                             "workspace entry is localized in \(language.rawValue)")
            }
        }
    }
}
